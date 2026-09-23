# 0022 — `grep -E` refuses a repetition operator that repeats nothing

**Status**: Accepted
**Date**: 2026-09-22

## Context

An ERE repetition operator (`*`, `+`, `?` or an interval `{n,m}`) needs something before it to
repeat. POSIX leaves it **undefined** when there is nothing: at the start of the pattern, right after
`(` or `|`, or right after `^`. It is also undefined when one operator repeats another (`a**`,
`a++`, `a*+`).

kriya refused all of these with a bare `bad pattern` and exit 2; niyama will not compile them. The
roadmap filed this as a divergence to decide, saying *"`grep -E '*'` … is a LITERAL asterisk in
GNU"*. **Measured, that is not what GNU does**, on 3.11 (CI's) or on 3.12:

| pattern | GNU 3.11 and 3.12 | kriya |
|---|---|---|
| `*` | `warning: * at start of expression`, then matches **every** line | refused |
| `*a` | the same warning, then matches exactly what `a` matches | refused |
| `x\|*`, `(*a)`, `+`, `?`, `{2}` | a warning naming the operator, which is then dropped | refused |
| `a**`, `a*+` | accepted silently as `a*` | refused |
| `a++` | accepted silently as `a+` | refused |

So GNU treats a leading operator neither as a literal nor as an error: it warns, then **discards**
it. A script that writes `grep -E '*.txt'` gets the lines containing `.txt` from GNU — every line
that has any byte followed by `txt`, since the `.` is still a wildcard — plus a warning on stderr.

BRE is different. POSIX *defines* the same positions there: a `*` first in the pattern, or first in
a `\(` group (after an initial `^`), is a literal. kriya honours that since 1.6.14; see
`icase_bre_literal_stars`.

## Decision

**kriya keeps refusing, and names the rule.** `grep -E` exits 2 on a repetition operator with
nothing to repeat:

    kriya grep: error: a repetition operator repeats nothing (undefined in POSIX; write \* for a literal *) in: *a

It also exits 2 on one operator repeating another:

    kriya grep: error: a repetition operator repeats a repetition (undefined in POSIX) in: a**

The check (`_gr_ere_repeat_fault`) runs only after niyama has refused the pattern, to choose the
message. It never decides what compiles.

## Consequences

- **Positive** — the pattern is almost certainly a mistake, and GNU agrees enough to warn about it.
  An exit 2 cannot be missed, while a warning disappears when stderr is discarded, which in a
  pipeline it usually is. The message says how to get what was probably meant, a literal `\*`.
- **Positive** — stacked operators are refused rather than guessed. `a++` is a *possessive*
  quantifier in PCRE, a different meaning from GNU's reading of it as `a+`. A refusal is the only
  answer that is not wrong for one of the two readers.
- **Negative** — a divergence from GNU: a script that relied on GNU dropping the operator now fails
  loudly. Such a script was already printing a warning on every run.
- **Neutral** — if niyama ever compiles these constructs, the refusal stops happening by accident.
  The day that is proposed, this ADR is what has to change first.

## Alternatives considered

- **Treat a leading `*` as a literal.** Rejected. That is what the roadmap assumed GNU does, and GNU
  does not, so it would match neither POSIX (undefined) nor GNU (dropped). It would be a third
  behaviour.
- **Warn and drop, as GNU does.** Rejected. "Undefined" is not a licence to rewrite the pattern
  silently. GNU's own warning is an admission that the result is probably not what was asked for,
  and a warning is lost wherever stderr is discarded.
- **Collapse stacked operators (`a**` → `a*`).** Rejected for now, partly because of the PCRE
  possessive reading above. It is cheap to add if a real script needs it; this ADR would record the
  change.
