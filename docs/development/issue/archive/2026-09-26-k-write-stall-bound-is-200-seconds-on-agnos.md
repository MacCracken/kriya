# `k_write`'s stall bound is ~200 s on agnos ≥ 1.57.9

- **Filed**: 2026-09-26
- **Repo**: kriya
- **Found by**: agnos 1.57.9 (end review of its blocking pipe writes)
- **kriya**: 1.7.1 (the fix; 1.1.8 through 1.7.0 had the 20,000-round bound)
- **Status**: FIXED in **1.7.1** — time-bounded stall, blocking pipe writes (a4 = 0), -1 acted on at
  once; measured on agnos in QEMU (below). ⚠ With agnsh 2.0.0 a pipeline whose consumer exits early
  now waits for the shell — agnoshi's `2026-09-26-pipeline-keeps-read-end-and-hangs`.

## What happens

`k_write` (`src/lib/sys.cyr`) retries a short/stalled write up to 20,000 times with `sched_yield` (#44) between tries. On agnos
≥ 1.57.7 a `#44` with nothing else READY parks the CPU until the next timer interrupt (~10 ms), and since 1.57.9 it never kicks
another CPU, so the bound is ~200 s, not "a short spin". A producer whose consumer is gone looks hung for minutes.

## Fix

Bound the stall by time, not by an iteration count (e.g. `uptime_ms`#40, a few seconds), and on agnos ≥ 1.57.9 prefer the blocking
pipe write (`write` with a4 = 0 blocks until a reader makes room; it returns the partial count or −1 when no reader is left — act on
that instead of retrying).

## Resolution (kriya 1.7.1)

Both halves of the fix as asked, and two things the fix needed that the issue did not name:

- **a4 = 0 on every write** (and every read): on agnos ≥ 1.57.9 a pipe write blocks until a reader
  makes room and answers -1 once none is left. The three-argument `syscall(1, …)` passed a garbage
  `r10`, which was in practice non-zero — O_NONBLOCK. `k_read` passes a4 = 0 too (1.57.8's blocking
  read).
- **The stall is bounded by time**: 5 s of no progress by `uptime_ms`#40, with a 500,000-round
  backstop for a clock that does not move (pre-1.57.7, IF=0). It returns ENOSPC — gnulib's
  `full_write` name for a write that takes nothing.
- **-1 is acted on at once**: recorded as EPIPE on a descriptor kriya inherited (the pipe case), EIO
  on a file kriya opened (agnos `open` returns no pipes). ⛔ The first draft called every -1 EPIPE,
  and `tee -p` then dropped a FAT file's failure at exit 0 (found by review).
- ⛔ **Not in the issue — a stalled descriptor stays failed.** Measured in QEMU, the time bound
  alone left the `early` pipeline hung past 40 s: `grep` writes each line in two calls and never
  looks at the result, so every call waited its own 5 s. Later writes to a marked descriptor fail
  at once; `k_close` clears the mark.
- ⛔ **Not in the issue — `k_write` never returns a short count**: seven utilities loop "write the
  rest" around it, and a short count from a give-up sent them back into the stall for ever.

### Measured (agnos `scripts/smoke/pipeline-smoke.sh`, `-smp 1`, scratch copies of agnos and agnoshi)

| Kernel | Shell | kriya | `early` | `s2fail` | message |
|---|---|---|---|---|---|
| 1.57.9, PIPEW reverted (1.57.8 writes) | agnsh 2.0.0 | 1.7.0 | FAIL (no prompt in 40 s) | FAIL | — |
| same | same | 1.7.1, time bound only | FAIL | FAIL | — |
| same | same | **1.7.1** | **PASS, 4.0 s** | **PASS, 4.0 s** | *write error: no space left on device* |
| 1.57.9 stock | agnsh + agnoshi's read-end patch | 1.7.0 | PASS, 0.0 s | PASS, 0.0 s | *write error: operation not permitted* |
| same | same | **1.7.1** | **PASS, 0.0 s** | **PASS, 0.0 s** | *write error: broken pipe* |

On stock 1.57.9 with the shipped agnsh 2.0.0 the pipeline hangs with either kriya — agnsh holds the
read end, and a blocking write waits for it, as the agnos 1.57.9 release notes describe for every
program. That one is agnoshi's.
