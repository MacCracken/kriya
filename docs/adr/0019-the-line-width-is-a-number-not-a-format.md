# 0019 — The line width is a number, not a format

**Status**: Accepted
**Date**: 2026-08-28

## Context

`ls` takes a width from four places, in this order: `-w`/`--width`, the `TIOCGWINSZ` ioctl, the
`$COLUMNS` environment variable, and a built-in 80. Until 1.6.8 kriya used two of them to decide
something else as well — **whether the output was columnar at all** — and read the remaining two in
the wrong order.

Three separate defects came out of that one confusion, and each was live:

1. `ls -w 200 | cat` was multi-column here and one name per line under GNU. `-w` was forcing
   columns because, before `-C` existed, it was the only way to ask for them off a tty. 1.6.5 saw
   this and deliberately left it, on the grounds that removing it without `-C` would delete the
   capability.
2. `$COLUMNS` was read before the ioctl, so on a pty with `stty cols 40` and `COLUMNS=20` kriya
   listed at 20 columns where GNU listed at 40. Bash exports `COLUMNS` from interactive shells, so
   the stale guess beat the live terminal in the common case, not a contrived one.
3. `-w -5` printed a listing and exited **0**, and `-w 9223372036854775808` wrapped through i64 to a
   negative width and collapsed the layout — a flag where a *larger* number produced a *narrower*
   listing.

[ADR 0017](0017-environment-variables-configure-features-the-caller-turned-on.md) settled the
environment half of this — a variable may configure a feature the caller turned on, never turn one
on — but it is stated about variables, and two of the three defects above are about a *flag* and a
*syscall*. The rule generalises; it had not been written down that way.

## Decision

**Every width source supplies a NUMBER. None of them chooses a format.** `-C`, `-x`, `-m`, `-1`,
`-l` and `--format=WORD` choose the format; `-w`, the ioctl and `$COLUMNS` only say how wide it may
be. Off a tty with no `-w` and no `$COLUMNS`, the width is 80 — not unlimited.

**Precedence is `-w` > ioctl > `$COLUMNS` > 80.** A live terminal knows its own size; an exported
`COLUMNS` is a guess that survives a resize. The variable is the fallback for when the ioctl cannot
answer — not a tty, or a tty reporting zero columns — which is exactly when it is the only source
there is.

**The value is a decimal non-negative integer. `0` means unlimited.** That holds for `-w 0` and for
`COLUMNS=0` alike. Anything else — a sign, a non-digit, a value past i64 — is a usage error with
exit 2 for the flag, and is ignored in favour of 80 for the variable.

Scope: this is about `ls`. Any future utility that grows a width control adopts the same three
rules rather than re-deriving them.

## Consequences

- **Positive** — `kriya ls | while read f` cannot produce several names on one line because of the
  parent shell, whatever `COLUMNS` holds. A width can no longer be silently misread: kriya either
  uses the number written or exits 2.
- **Positive** — the ioctl-first order means resizing a terminal takes effect without re-exporting
  anything, which is what a user expects of the terminal they are looking at.
- **Negative — BREAKING.** `ls -w N` no longer columnates a pipe. A caller who used `-w` to force
  columns must now write `-C -w N`. This is the second half of a change 1.6.5 started and could not
  finish.
- **Negative** — two divergences from GNU on the value, both refusals. GNU parses the width with a
  base-0, unsigned, saturating reader: it takes `-w 0x20` as 32, **`-w 040` as 32**, and clamps
  anything past 2^64. kriya refuses the hex form, reads `040` as FORTY, and exits 2 past i64.
  ⭐ Every one of these is kriya declining to act rather than acting on a different number than the
  one written — `040` under GNU is the failure mode this avoids.
- **Neutral** — an invalid `$COLUMNS` falls back to 80 as GNU's does, but GNU also warns
  (`ls: ignoring invalid width in environment variable COLUMNS: 'abc'`) and kriya is silent. That
  is a new stderr shape and has to answer to
  [architecture 001](../architecture/001-one-write-per-error-line.md) first; filed at roadmap
  1.6.10.

## Alternatives considered

- **Keep `-w` forcing columns.** Rejected: it is the divergence, not a feature. `-C` exists now, so
  the capability `-w` was standing in for has its own spelling, which is precisely the condition
  1.6.5 said it was waiting for.
- **Read `$COLUMNS` before the ioctl, as kriya did.** Rejected on measurement: GNU does the
  opposite, and the reasoning holds independently — a variable can be stale, a terminal cannot be
  wrong about its own width.
- **Adopt GNU's base-0 parse so `-w 040` is 32.** Rejected. A user who writes `040` in a shell
  almost always means forty; C's leading-zero-is-octal rule is a language convention, not a
  command-line one, and [ADR 0002](0002-argument-parsing-is-agent-safe.md) is built on the argument
  meaning what it looks like. Refusing a form is recoverable; silently halving a width is not.
- **Saturate an out-of-range width instead of refusing.** Rejected: saturating quietly is how the
  wraparound bug read to the caller in the first place. An exit 2 says which operand was the
  problem.
- **Fold this into ADR 0017 rather than write a new one.** Rejected: 0017 is about environment
  variables and is correct as it stands. Two of the three defects here are a flag and a syscall, and
  hanging them off a variables ADR would put the general rule where nobody looks for it.
