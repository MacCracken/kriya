# 0011 — `echo` matches the non-XSI binary, not the shell builtin, and `POSIXLY_CORRECT` does not flip it

**Status**: Accepted
**Date**: 2026-08-26

## Context

`echo` is the one utility where "match POSIX" is not a readable instruction, because
three incompatible `echo`s all have a claim:

1. **POSIX (non-XSI)** — `echo` writes its operands literally. There is no `-e`, no
   `-E`, and the meaning of a leading `-n` is explicitly *implementation-defined*.
   A backslash in an operand is just a backslash.
2. **XSI** — escape sequences are **always** interpreted, with no flag to ask for it
   and no flag to turn it off. `\c` truncates the output.
3. **The shell builtin** — which is what most scripts actually reach. `bash`'s builtin
   defaults to *no* escapes and honours `-e`; `dash`'s builtin interprets escapes
   *always* and has no `-e` at all. So "the shell builtin" is not one behaviour either.

GNU `/usr/bin/echo` sits in camp 1 by default and adds `-e`/`-E` as extensions — and
then flips to camp 2 when `POSIXLY_CORRECT` is set in the environment. That flip was
measured, not assumed: with `POSIXLY_CORRECT=1`, `/usr/bin/echo 'a\tb'` emits a real
tab, and `/usr/bin/echo -e 'x\ty'` prints the string `-e x<TAB>y` — the `-e` becomes
data.

kriya has to pick one, and the pick is visible in every script that calls `echo`.

## Decision

**kriya `echo` implements GNU `/usr/bin/echo`'s default, non-XSI behaviour, and
`POSIXLY_CORRECT` does not change it.**

In scope:

- `-n`, `-e`, `-E` are options; escapes are **off** by default.
- Option scanning takes clusters made up **entirely** of `n`/`e`/`E` (`-neE` is three
  options). Any other character makes the whole token an operand: `-ex` prints as
  `-ex`. A bare `-` is an operand. `--` has no special meaning and prints as `--`.
- The last of `-e`/`-E` wins, across cluster boundaries as well as inside one.
- The escape set is GNU `echo`'s: `\\ \a \b \c \e \f \n \r \t \v`, octal `\0NNN`
  under the **prefix** rule (`\101` and `\0101` are both `A`), and `\xHH`. Every
  other backslash sequence keeps its backslash. `\"` is **not** in this set — that
  one belongs to `printf`.
- `\c` cancels the rest of the output: the remainder of the operand, every later
  operand, and the trailing newline. Exit status stays 0.

Out of scope: the `POSIXLY_CORRECT` → XSI flip.

## Consequences

- **Positive** — the common case is right. `echo -e 'a\tb'` does what a decade of
  scripts expect, and the far more common `echo -n` keeps working. Behaviour is a
  function of the command line alone, which is the property ADR 0002 exists to
  protect: an agent reading `--help=json` gets a complete account of what the
  command will do, with no hidden environmental input.
- **Positive** — declining the flip removes a genuine footgun that GNU has. Under
  GNU's rule, exporting `POSIXLY_CORRECT` for some *unrelated* utility silently turns
  every `echo -e` in the same shell into a command that prints `-e` as data. kriya
  cannot be broken that way.
- **Negative** — a measured divergence from GNU, and it is a real one: a script that
  sets `POSIXLY_CORRECT` and then relies on bare `echo 'a\tb'` emitting a tab gets a
  literal backslash-t from kriya. This is a deliberate deviation, recorded here per
  the "diverge only with an ADR" rule.
- **Negative** — kriya now owns an escape decoder shared with `printf`. The two
  callers genuinely disagree in two places (the octal-prefix rule and `\"`), so
  `src/lib/str.cyr` carries mode bits rather than one table. A future caller that
  disagrees somewhere new adds a third bit, not a third copy.
- **Neutral** — [agnoshi](https://github.com/MacCracken/agnoshi) owns the *builtin*
  `echo` and is free to choose differently; that is a shell decision, not a kriya
  one. This ADR binds the binary only.

## Alternatives considered

- **Implement the `POSIXLY_CORRECT` flip for full GNU parity.** Rejected: it buys
  parity in the rarest case and costs a hidden environmental input in the most
  common one. The failure it enables is silent and acts at a distance — the
  environment variable and the broken `echo` are usually in different files.
- **Implement XSI unconditionally** (escapes always on, no `-e`). Rejected: it
  breaks every `echo 'C:\temp'` and every `echo` of a Windows path or a regex, and
  it makes `-e` print as data, which reads as a kriya bug at the call site.
- **Ship no escapes at all**, keeping the pre-1.4.4 literal-only `echo`. Rejected:
  `echo -e` is load-bearing in real scripts, and leaving it out pushed the work onto
  every consumer. The shared escape table landed in 1.4.3 and removed the only real
  obstacle.
- **Match `bash`'s builtin specifically.** Rejected: kriya ships a *binary*, and the
  binary is reached when the shell's builtin is not — so matching the builtin would
  make kriya's `echo` disagree with the thing it is actually substituting for. It
  also is not a single target, since `dash` and `bash` disagree with each other.
