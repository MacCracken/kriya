# 0026 — Batched exec counts a command line as GNU does

**Status**: Accepted
**Date**: 2026-09-23

## Context

`find -exec … {} +` and `xargs` do one job from two directions: gather arguments until a command
line is full, run it, start the next. Roadmap 1.7.0 asked for the `+` form, which kriya refused,
and for `xargs -L`, `-x` and `--show-limits`, which it lacked. They share one question, "how full
is full", and the answer decides which files end up in which command.

Measured against GNU findutils 4.9 (CI's) and 4.11 (this box), and read in its source
(`lib/buildcmd.c`, `xargs/xargs.c`, `find/parser.c`):

- **A command line's size** is the sum of strlen + 1 over every argument, the command's own
  included. It is full when the next argument would pass the buffer. The buffer is 131,072 bytes
  unless `xargs -s` says otherwise; exactly equal still fits.
- **The ceiling** is glibc's ARG_MAX (a quarter of the stack limit, at least 131,072, at most
  6,291,456), less the environment, less 2,048 bytes of headroom. `-s` is clamped to it with a
  warning.
- **When execve still says E2BIG**, because the kernel also counts the pointers, xargs halves the
  batch and then bisects, remembering across batches. `find` does not retry.

kriya's `xargs` got none of this: a byte tally of its own, no `-L` or `-x`, and several GNU
behaviours the slot did not name, which measuring turned up:
- It read all of stdin before running anything, so `yes | xargs -n1 echo | head` never ended.
- It never ran the command on empty input, under a comment claiming modern GNU does not either.
  4.9 and 4.11 both run it once unless `-r`, and POSIX says "one or more times".
- `-I` substituted into the command name. POSIX inserts the line "in arguments", and GNU skips
  the command, so under kriya the input chose which program ran.
- Items split at VT, FF and CR, `-0` dropped empty items, and an unmatched quote was accepted.
- A failed exec went on to the next batch, where GNU stops.
- Every command allocated fresh argument arrays from an allocator that never frees: 80,000
  commands peaked at 84.5 MB against GNU's 18.4.

## Decision

**Batched exec counts a command line exactly as GNU's `buildcmd` does**. One implementation,
`src/lib/argbatch.cyr`, serves both utilities: the ceiling, the 131,072-byte buffer, the size
rule, the argument-count limit, and the E2BIG bisection, ported line for line. A batch therefore
splits where GNU's splits. That is a testable claim, and `smoke-find.sh` and `smoke-xargs.sh`
check it against the local GNU, the E2BIG sequence included.

**`find -exec … {} +`**, GNU 4.10's grammar: `+` ends the command only straight after a token that
is exactly `{}`, and only one token may hold `{}` at all. The predicate is always true. A command
that fails, is not found or is killed makes find exit 1. Batches run as they fill; what is left
runs after the walk, in the order the `-exec`s were written.

**`xargs` behaves as GNU's does**, input grammar included:
- It streams its input, and each child reads `/dev/null`, so a child cannot consume the input
  meant for the next.
- It runs the command once on empty input unless `-r`.
- `-I` never substitutes into the command name.
- Items end at blanks and newline only; an unmatched quote is fatal, after running what was read
  before it; `-0` keeps empty items.
- `-n`, `-L` and `-I` are last-wins against each other, with GNU's warnings; `-L` and `-I` imply
  `-x`; and `-x` bites only alongside them.
- An exec failure stops xargs, with 127 or 126.
- `--show-limits` prints GNU's six lines, byte for byte.

**Unchanged, and asserted as kriya's own answers:**
- A usage error exits 2 ([ADR 0008](0008-posix-exit-code-policy.md)); GNU exits 1.
- There is no `-l[N]`: [ADR 0002](0002-option-parsing-humans-and-agents.md) has no optional values,
  and `-L N` is the same option. For the same reason `--max-lines 1 echo` reads `1` as the value,
  where GNU's `--max-lines` is `-l`'s long form and runs a command named `1`.
- A `-exec … ;` command that cannot run or is killed still makes find exit 1. GNU reports it and
  exits 0 in that form; POSIX asks for a non-zero status only in the `+` form.
- On agnos, whose exec passes no arguments at all, ARG_MAX is the 131,072 floor.

## Consequences

- **Positive**: the batches, the E2BIG retries and `--show-limits` are GNU's, measured on two
  versions. A script moved between the two gets the same commands.
- **Positive**: xargs streams in constant memory, as GNU does. `-n1` over 80,000 items peaks at
  18.5 MB.
- **Positive**: the input can no longer choose the program under `-I`.
- **Negative, breaking**:
  - `xargs CMD` with empty input runs CMD once. **Migration:** add `-r`, as with GNU.
  - `xargs -I{} {} …` no longer runs the input as a command.
  - VT, FF and CR no longer split items.
  - An unmatched quote is an error.
  - `-0` passes empty items.
  - A failed exec stops the run.
- **Neutral**: `-P` (roadmap 1.7.2) will need the batch builder to hand out command lines
  concurrently. `--show-limits` already prints GNU's ceiling for it, 2,147,483,647.

## Alternatives considered

- **Keep kriya's own byte tally.** Rejected. It split batches in different places from GNU for
  no reason, and "which files went into which command" is exactly what a user debugging an
  `xargs rm` needs to reproduce.
- **Batch conservatively, well under the limit, and skip the E2BIG retry.** Rejected. It is
  simpler, but it diverges from GNU on every large input. The retry is GNU's answer to a kernel
  limit the byte count cannot see, and a port that can be compared against GNU beats an
  approximation that cannot.
- **Keep not running the command on empty input.** Rejected. It violates POSIX, and scripts that
  want it write `-r` for GNU already.
