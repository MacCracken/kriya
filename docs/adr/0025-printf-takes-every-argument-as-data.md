# 0025 — `printf` takes every argument as data

**Status**: Accepted
**Date**: 2026-09-23

## Context

[ADR 0002](0002-option-parsing-humans-and-agents.md) gives kriya one option parser. Its table of
allowed forms ends with a rule for a negative number: `cmd -- -5`, because a raw `-5` "is rejected
as an unknown short flag". The rule keeps an option typo from being read as data. `seq` has always
been exempt: it walks argv itself, and `seq -5 -3` counts.

`printf` went through the shared parser, so the rule applied to it too:

- `printf '%d\n' -5` was *bad option*, exit 2, and so was `printf '-> %s\n' x`.
- ⛔ **A `--` among the arguments was deleted.** `printf '%s|' a -- b` printed `a|b|` at exit 0.
  The parser consumed the terminator wherever it stood, so the data changed silently.
- `printf --help foo` printed the manual.

The rule protects nothing in `printf`. The utility has no options for a `-5` to be mistaken for.
POSIX lists its OPTIONS as *None*, and XCU 1.4 asks a utility with no options for one thing only: to
drop `--` when it is the first argument. GNU's rule, measured on coreutils 9.4 and 9.11, is that
`--help` and `--version` are options only as the sole argument. A first `--` is dropped, and
everything else is FORMAT or an ARGUMENT, whatever it starts with.

The cost of the rule was real. `printf '%d\n' "$n"` is the idiom for printing a number, and it
failed for every negative `n`. The roadmap asked for this to be decided before 1.6.17 changed
anything.

## Decision

**`printf` takes every argument as data, the FORMAT included; GNU's rule, exactly.**

- `--help`, `--help=FORMAT` and `--version` are honoured only as the **sole** argument. With anything
  after them, they are the FORMAT: `printf --help foo` prints `--help`, and warns that `foo` was
  not used, as GNU does.
- A `--` as the **first** argument is dropped (POSIX XCU 1.4). Anywhere else it is data.
- Nothing else is an option. `printf -5` prints `-5`; `printf '%d\n' -5` prints `-5`.

**The same sole-argument rule applies to `echo`, `true` and `false`**, the other utilities whose
arguments are all data. GNU tests `argc == 2` in all four. kriya honoured `--help` as the first
argument there too, so `echo --help foo` printed the manual where GNU prints `--help foo`, and
`false --version x` exited 0 where GNU exits 1. `help_if_sole` in `src/lib/help.cyr` is the one
implementation.

**Unchanged:** every other utility keeps ADR 0002's rule. A utility that has options still needs
`--` before a negative operand.

## Consequences

- **Positive**: every `printf` invocation GNU accepts is accepted here, with the same output. The
  deleted `--` is gone, and it is the defect that mattered: data changed silently at exit 0.
- **Positive**: the parser and the help text agree. `printf --help=json` still works for an agent,
  because a sole argument is the only shape in which it was ever a request for help.
- **Negative, breaking**: `printf --help foo` and `echo --help foo` no longer print the manual. A
  script that relied on it was relying on a divergence from GNU.
- **Neutral**: ADR 0002's negative-number row now has two exemptions, `seq` by its grammar and
  `printf` by this ADR. Each utility that walks argv itself owns the reason it does.

## Alternatives considered

- **Keep ADR 0002's rule and document `--`.** Rejected. It breaks the most common `printf` idiom
  for negative numbers and protects no option, and it did not stop the parser deleting a `--`
  that was data.
- **Treat a leading `-` as data only after FORMAT.** Rejected. A FORMAT such as `-> %s\n` is as
  legitimate as an argument, and GNU prints it. A half rule is one more thing to remember and gains
  nothing.
- **Honour `--help` anywhere, as the shared parser does.** Rejected. `--help` can be a string a
  script wants printed, and GNU prints it. Help only as the sole argument is unambiguous for
  humans and agents alike.
