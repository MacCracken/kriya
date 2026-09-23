# 002 — Signal handling model

kriya utilities run as short-lived processes invoked from a shell or pipeline. The signal model is correspondingly minimal at M1 and grows precisely as later milestones introduce utilities that earn the cost of a handler. This note records what kriya does today, what it deliberately does NOT do, and the trigger that lands each follow-on.

## Default behaviour (M1, no installed handlers)

- **SIGPIPE** — kernel default terminates the process with exit code `141` (128 + 13). For `yes`, `head`, `tail`, `tee`, and any other utility that writes to a downstream pipe, this is the correct end state when the reader closes. kriya does not install a handler; the existing default does the right thing and avoids the overhead of a per-write `write()` return-value branch.
- **SIGINT** — kernel default terminates with exit `130`. M1 utilities (`true`, `false`, `echo`, `pwd`, `yes`, `sleep`) hold no resources that need rollback, so the default termination is the right answer. `sleep` interrupted by SIGINT exits 130 without printing — same as GNU `sleep`.
- **SIGTERM** — kernel default terminates with exit `143`. Same reasoning as SIGINT.
- **SIGQUIT, SIGSEGV, SIGBUS, SIGFPE** — kernel defaults (core dump or terminate). kriya does not catch these.

## Hard rules (No-Gos)

1. **No utility ignores SIGPIPE by default, and none ignores it without an explicit flag.** SIGPIPE is the canonical "downstream reader is gone" signal; ignoring it would turn `kriya yes | head -10` into a hang on the next write after `head` exits. ⚠ **Amended at 1.6.4 by [ADR 0016](../adr/0016-tee-signal-dispositions.md)**, which was the first thing to need the exception: `tee -p` / `--output-error=MODE` cannot express any of its behaviours unless a write to a closed pipe RETURNS EPIPE instead of killing the process. The concern this rule protects is untouched — `yes` has no such flag, and `tee`'s is opt-in.
2. **No utility catches SIGSEGV / SIGBUS / SIGFPE.** A crash means a bug — the core dump is the diagnostic. kriya does not paper over memory corruption with a handler.
3. **No utility installs a signal handler before `args_init()`** — the args/alloc bootstrap has its own assumptions about signal masks at startup and any pre-init handler runs on an undefined stack.
4. **No utility sleeps in a signal handler.** Handlers do minimal work: set a flag, restore terminal state (M3 `ls --color` if it lands), `_exit(128 + signo)`. They never call `printf`-class functions or take heap locks.

## Triggers for installing handlers (later milestones)

| Utility | Signal | What the handler does | Planned for |
|---|---|---|---|
| `cp`, `mv`, `rm` (destructive) | SIGINT, SIGTERM | Set a `_kriya_interrupted = 1` flag. Main loop checks the flag between operations and exits 130/143 cleanly without leaving a half-copied file. No mid-syscall `cleanup()` — the worst case is one partially-written destination file, which the user sees via the exit code and can resume. | unscheduled |
| `find`, `xargs` (long-running) | SIGINT, SIGTERM | Same flag pattern, checked between directory entries / batched exec spawns. | unscheduled |
| `ls --color`, `wc` on a tty | SIGINT | Restore ANSI defaults (`\x1b[0m`) to stderr before `_exit`. Without it, a ^C mid-output leaves the terminal in a coloured state. | unscheduled |
| `tail -f` | SIGINT | Cleanly close the watched file descriptor and exit 130. | unscheduled |

⚠ The milestones these rows first named (M2–M5) closed without them, and no roadmap slot holds them
now; a row gains a slot when one is filed.

When a handler lands, it gets its own ADR (the policy decision: "destructive utilities install a flag-based SIGINT handler") and the table here grows. The table is the running record, not the decision point.

## Dispositions are not handlers (1.6.4)

⭐ **`tee -i` and `tee -p` change a signal's DISPOSITION to `SIG_IGN`. They install no handler**, and the distinction is what let them ship without any of the infrastructure this table anticipates: `SIG_IGN` installs no function, uses no stack, needs no `sa_restorer`, sets no flag for a loop to poll, and cannot run at an awkward moment. The four hard rules above are about what a handler may DO; none of them binds a disposition.

| Utility | Signal | Disposition | Gated on |
|---|---|---|---|
| `tee` | SIGINT | `SIG_IGN` | `-i` / `--ignore-interrupts` |
| `tee` | SIGPIPE | `SIG_IGN` | `-p` or any `--output-error=MODE` |

⚠ **The trigger table above still has no entry that has fired.** The flag-based handler it describes for `cp`/`mv`/`rm` and `find`/`xargs` is still ahead, and [ADR 0016](../adr/0016-tee-signal-dispositions.md) deliberately does not authorise it.

⛔ **`signal_ignore`/`signal_default` existed in the Cyrius stdlib the whole time** (`lib/syscalls.cyr`, since v6.4.51, with `SIGINT` and `SIGPIPE` already enumerated). `tee`'s header deferred `-i` on "the signal-handler infrastructure ... not yet installed" for six releases and there was nothing to build. ⚠ **Second kriya deferral to outlive its blocker**, after `sleep`'s fractional durations waited on a chrono duration parser that was never coming. **A deferral naming a blocker is a claim with an expiry date; re-check it before repeating it.**

## Why so light at M1

Every M1 utility is bounded: it either does one syscall and returns (`true`, `false`, `pwd`), prints a fixed buffer once (`echo`), or loops on a single `write(2)` (`yes`). The kernel-default behaviour is correct for all of them. A handler at this stage would be dead weight that consumes the signal_handlers static budget for utilities that don't need it.

## Out of scope

- **SIGCHLD reaping** — `find -exec` and `xargs` are parents, but each waits for its one child
  before starting the next, so there is nothing to reap asynchronously. When `xargs -P` lands
  (roadmap 1.7.2), it gets its own SIGCHLD note.
- **Signal masking around `*at()` syscalls** — POSIX guarantees these are atomic with respect to signals; no masking needed. If a future utility nests `*at()` calls in a way that requires atomic windows, that's its own arch note, not a global policy.
- **Real-time signals (SIGRTMIN..SIGRTMAX)** — not used by kriya.
