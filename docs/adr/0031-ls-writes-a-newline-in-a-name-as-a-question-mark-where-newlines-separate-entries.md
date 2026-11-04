# 0031 — `ls` writes a newline in a name as `?` wherever a newline separates entries

**Status**: Accepted
**Date**: 2026-11-04

## Context

Off a terminal, GNU 9.4–9.11 wrote a newline in a name as itself, and so did kriya until 1.8.11. A
file called `nl⏎X` therefore listed as two entries, `nl` and `X`. With files of those two names
present, `ls | while read -r f; do rm -- "$f"; done` removed both, and nobody had named either.
`ls | wc -l` counted one file too many.

GNU 9.12 writes `?` instead wherever a newline separates entries (NEWS: *"'ls' now replaces newlines
in file names if ambiguous with separators"*). Its rule, `qmark_newline`, measured byte for byte:

- in `-1` and `-l`, and in `-C`, `-x` and `-m` when the width is not 0;
- for the quoting styles that write a control byte raw, `literal`, `shell` and `shell-always`; the
  escaping styles already write `\n` or `$'\n'`;
- for names, `-l` link targets and `-R` section headers alike;
- not under `--show-control-chars` or `--zero` given after `-q`, and not under `--dired`.

POSIX XCU `ls` allows `?` by default only on a terminal, through `-q`: *"Implementations may provide
this option by default if the output is to a terminal device."* Its Issue 8 FUTURE DIRECTIONS (Austin
Group Defect 251) encourage implementations *"to treat this as an error"* when such a pathname is
written where a newline is a separator, and say a future version may require that.

The choice was drafted as Appendix B of
[the 9.12 parity review](../audit/2026-11-03-gnu-9.12-parity.md) (§ 3), and accepted at 1.8.11.

## Decision

**kriya's `ls` follows GNU 9.12's rule, and ships the ways out with it.** This is a recorded deviation
from the letter of POSIX's `-q`.

- `--show-control-chars` (since 1.8.8) writes the bytes as they are. `-q` and it are last-wins.
- `--zero` (new) ends each entry with a NUL. It is the lossless form for a program, and it turns the
  rule off. At its place in the command line it also sets one entry per line unless the format is
  long, colour off, literal quoting and raw control bytes, as GNU's does, and a later option sets each
  of those again. A section header and the blank line before it keep their newlines. `--dired` with
  `--zero` is a usage error, exit 2.

## Consequences

- **Positive**
  - One entry per line, always, so `ls | wc -l` counts correctly, and a `while read` loop cannot act
    on two other files that a newline in a name happens to spell.
  - The same bytes as GNU 9.12, compared in `smoke-ls.sh`.
- **Negative**
  - Lossy: `nl?X` names nothing, or a different file that happens to be called `nl?X`.
  - kriya differs from POSIX's letter and from every GNU before 9.12. On those oracles `smoke-ls.sh`
    asserts kriya's answer as 9.12 writes it, and gives kriya `--show-control-chars` where it compares
    the quoting alone.
- **Neutral**
  - `--zero` is a new option, and `difffuzz-quote.py` gives both sides `--show-control-chars`.

## Alternatives considered

- **Keep raw bytes.** It is the POSIX letter and matches 9.4–9.11, but it leaves the wrong-files
  failure in place, and GNU and POSIX have both moved away from it.
- **POSIX's encouraged error.** The safest signal, but no implementation does it yet, so kriya would
  differ from GNU and from today's POSIX text at once.
