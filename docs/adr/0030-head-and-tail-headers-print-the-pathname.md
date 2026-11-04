# 0030 — `head` and `tail` headers print the pathname, as POSIX specifies

**Status**: Accepted
**Date**: 2026-11-04

## Context

GNU coreutils 9.12 quotes the name in a `head` or `tail` file header whenever shell-escape quoting
would quote it, with `:` quoted too (`quotef`): `==> 'a b' <==`, `==> 'a:b' <==`, and the stdin label
as `==> 'standard input' <==`. 9.4 through 9.11 print the name as given, and so does kriya. The quoting
ignores `QUOTING_STYLE`. NEWS 9.12 calls it a bug fix: *"'head' and 'tail' now quote names in file
headers when needed."*

POSIX XCU `head` specifies the header as `"\n==> %s <==\n", <pathname>`. `tail` takes one file in
POSIX, so its headers, `-v` and the stdin label are GNU's alone.

The choice was drafted as Appendix A of
[the 9.12 parity review](../audit/2026-11-03-gnu-9.12-parity.md) (§ 1), and accepted at 1.8.11.

## Decision

**kriya's `head` and `tail` print the pathname in a header byte for byte, and never quote it.** The
stdin label is the literal `standard input`. `tail` follows `head`, so one rule holds for both.

## Consequences

- **Positive**
  - POSIX's header, exactly. A reader recovers the name by stripping eight fixed bytes, with no
    unquoting step.
  - The same bytes as every GNU release before 9.12.
- **Negative**
  - kriya differs from GNU 9.12 for every name shell-escape would quote.
  - A name containing a newline still makes a header that reads as two lines. That is ambiguous in
    POSIX's own format.
- **Neutral**
  - The GNU comparisons in `smoke-head-tail.sh` put a quoting oracle's stdin label back to the bare
    form, which is the only difference in those cases. An absolute assertion pins the decision:
    `head qv1 'qv a b'` prints `==> qv a b <==`, on every oracle. Both have been there since 1.8.5;
    this ADR records why.

## Alternatives considered

- **Follow 9.12.** It makes the newline case unambiguous, at the cost of POSIX's format for every
  name with a space, a quote or a colon. For the newline case, POSIX's stated direction (Austin Group
  Defect 251, in `head`'s FUTURE DIRECTIONS as in `ls`'s) is an error, not quoting.
- **Quote only a name that contains a newline.** It matches neither POSIX nor GNU: a third behaviour
  to document, for the one case nobody parses headers for.
