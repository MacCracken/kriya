# 0016 — `tee` changes signal dispositions, and only when asked

**Status**: Accepted
**Date**: 2026-08-27

## Context

[architecture 002](../architecture/002-signal-handling-model.md) records that kriya installs no
signal handlers and lists the triggers that would land the first one. Its **hard rule #1** is:

> **No utility ignores SIGPIPE.** SIGPIPE is the canonical "downstream reader is gone" signal;
> ignoring it would turn `kriya yes | head -10` into a hang on the next write after `head` exits.

`tee -i` and `tee -p` / `--output-error=MODE` both require exactly what that rule forbids — one for
SIGINT, one for SIGPIPE. They cannot be implemented without changing a disposition, so the rule needs
a decision rather than an exception made in passing.

⚠ **The infrastructure they were said to be waiting on already existed.** `src/cmd/tee.cyr`'s header
deferred them as needing "the signal-handler infrastructure flagged in
`docs/architecture/002-signal-handling-model.md` (M2/M3 trigger row — not yet installed)". Checked at
pin 6.5.35: `lib/syscalls.cyr` has `signal_ignore(signum)` and `signal_default(signum)`, with `SIGINT`
and `SIGPIPE` in a `Signal` enum, and has had them since v6.4.51. **Second time a kriya deferral has
outlived its blocker** — `sleep`'s fractional durations were the first, deferred to a chrono duration
parser that was never going to arrive.

Measuring GNU also showed that these are not two features but one mechanism seen twice, and that the
five `--output-error` mode NAMES are two independent bits:

| mode | non-pipe write error | pipe write error |
|---|---|---|
| default | warn, keep other outputs, exit 1 | **killed by SIGPIPE** |
| `-p` | warn, keep going, exit 1 | silent, drop that output, exit **0** |
| `warn` | warn, keep going, exit 1 | warn, keep going, exit 1 |
| `warn-nopipe` | warn, keep going, exit 1 | silent, drop it, exit **0** |
| `exit` | warn, **stop at once**, exit 1 | warn, **stop at once**, exit 1 |
| `exit-nopipe` | warn, **stop at once**, exit 1 | silent, drop it, exit **0** |

⛔ **Every non-default row also means SIGPIPE is ignored.** Without that the kernel kills the process
on the first write to a closed pipe and no per-output policy ever runs — the rows are unobservable.

## Decision

**A kriya utility may change a signal's disposition only when an explicit flag asks it to, and only
to `SIG_IGN`. No handler function is installed anywhere.**

For `tee`:

- **`-i` / `--ignore-interrupts`** → `signal_ignore(SIGINT)` before the copy loop.
- **`-p` and any `--output-error=MODE`** → `signal_ignore(SIGPIPE)` before the copy loop.
- Neither is on by default. Plain `kriya tee` dies on SIGINT (exit `-2`) and on SIGPIPE (exit `141`),
  which is what GNU does and what architecture 002 already specified.

architecture 002's hard rule #1 is amended to read **"No utility ignores SIGPIPE by default, and none
ignores it without an explicit flag"** — the concern it protects (`kriya yes | head -10` hanging)
is untouched, because `yes` has no such flag and `tee`'s is opt-in.

⭐ **A disposition is not a handler.** `SIG_IGN` installs no function, uses no stack, needs no
`sa_restorer`, sets no flag for a loop to poll, and cannot run at an awkward moment. Architecture
002's four hard rules about what handlers may do therefore do not apply to it — which is why this
lands without the flag-based-handler infrastructure its trigger table anticipated.

### `--output-error` requires its value

GNU accepts a bare `--output-error` and reads it as `warn-nopipe`. kriya makes it a usage error:
[ADR 0002](0002-option-parsing-humans-and-agents.md) rule 3 is *"a flag is either a boolean or it
requires a value — never both; ambiguity here is the single biggest source of agent miscalls"*, and
`tee --output-error file` is precisely that ambiguity. `-p` is the compact spelling and
`--output-error=warn-nopipe` the explicit one.

⚠ **`-p` has no long form**, because GNU's does not either. Inventing a `--pipe-mode` would make a
script written against kriya fail on GNU — the portability trap running the other way.

### The write-failure net has to be told

`k_write` records a sticky failure and the dispatcher reports it at exit whenever the applet returned
success. That is right for every other utility and the exact opposite of what `-p` asks for, so
`src/lib/sys.cyr` gains **`k_write_forgive(errno)`**, which clears the sticky state only when the
RECORDED errno is the one named. ⛔ Narrow on purpose: an applet cannot forgive a failure it never
looked at, and a first-recorded ENOSPC still stands.

### agnos

`signal_ignore` is a no-op on agnos — ring 3 has no signal delivery yet. `-i` and `-p` are accepted
there and there is nothing to ignore. ⚠ That is the honest behaviour, not a stub: the signals do not
arrive, so the flags describe a condition that cannot occur.

## Consequences

- **Positive** — `tee -i` works, which is the flag's entire audience: a long build piped through
  `tee` that must survive the ^C aimed at the foreground job.
- **Positive** — all six `--output-error` behaviours match GNU exactly, measured across both a
  non-pipe failure (`/dev/full`) and a pipe failure (a closed reader).
- **Positive** — the precedent is narrow and checkable: "only `SIG_IGN`, only behind a flag" is a
  rule a reviewer can apply without judgement.
- **Negative** — architecture 002's hard rule #1 is now conditional, and a conditional rule is weaker
  than an absolute one. Mitigated by the amendment naming the flag as the only door.
- **Negative** — a bare `--output-error` diverges from GNU. Asserted, so it cannot drift.
- **Neutral** — the trigger table in architecture 002 still has no flag-based handler in it. When one
  lands (`cp`/`mv`/`rm` interruption, `find`/`xargs`), it gets its own ADR; this one deliberately
  does not authorise it.

## Alternatives considered

- **Implement `-i` and `-p` as no-ops that accept the flag.** Rejected: an accepted flag that does
  nothing is the accepts-and-lies shape this project keeps removing. A script using `tee -i` to
  survive ^C would silently not survive it.
- **Install a real SIGINT handler that sets a flag the copy loop polls.** Rejected as strictly worse
  for this purpose: `-i` means "do not be interrupted", so there is nothing for a flag to convey, and
  a handler would need the infrastructure and the ADR that architecture 002's trigger table
  anticipates for the destructive utilities. That work is still ahead; it is not this.
- **Ignore SIGPIPE unconditionally in `tee` and handle EPIPE per output.** Rejected: it changes plain
  `kriya tee`'s exit from 141 to something else and breaks parity for the default invocation, which
  is the overwhelmingly common one.
- **Support a bare `--output-error` by treating the next argv token as the mode when it names one.**
  Rejected on ADR 0002 rule 3 — that is optional-value parsing wearing a disguise, and
  `tee --output-error warn` where `warn` is a FILE is unresolvable.
