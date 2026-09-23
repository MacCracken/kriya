# 0023 — `head` and `tail` take the obsolescent count form first, and a `-` form whatever follows

**Status**: Accepted
**Date**: 2026-09-22

## Context

POSIX removed the obsolescent count forms from `head` and `tail` in 2001. Every shell script still
uses them anyway, and GNU still accepts them. Until 1.6.15 kriya accepted one form, the bare digits
(`head -5`, `tail -5`), in the first argument only. Every other spelling GNU takes exited 2, and
`tail +5 FILE` read a **file** named `+5`.

GNU's two grammars are not the same. Both were measured on coreutils 9.11 and read from its source.

- **`head`** takes `-` and digits, followed by any number of letters, applied in order: `c`
  (bytes), `b` `k` `m` (bytes × 512, 1024 or 1048576), `l` (lines), `q` `v` (headers) and `z`
  (NUL-terminated lines). `c` clears a multiplier and `l` does not, so `-3kc` is 3 bytes but `-3kl`
  is 3072 **lines**. Nothing about the other arguments matters.
- **`tail`** takes `+` or `-`, optional digits (ten when there are none), an optional `b` / `c` /
  `l`, and an optional `f`. `+` counts from the start. `-cf` is ten bytes and follow, not `-c f`.
  The form applies **only when at most one operand follows** it, or `--` and one. Otherwise GNU
  reads a `+` form as a file name, and refuses a `-` form outright:

  | command | GNU 9.11 | kriya until 1.6.15 |
  |---|---|---|
  | `tail +3 f` | from line 3 | a file named `+3`, then `f` |
  | `tail +3 a b` | a file named `+3`, then `a`, `b` | the same |
  | `tail -5 a b` | *option used in invalid context -- 5*, exit 1 | the last 5 of each |
  | `tail -5 -f f` | *option used in invalid context -- 5*, exit 1 | the last 5, following |

The last two rows were already a deviation, written down in `smoke-head-tail.sh`: kriya took the
first-argument `-5` whatever followed it. Taking the full grammar forces the question. Does the
operand rule apply to the new `-` spellings (`-5c`, `-l`, `-cf`) too?

One more difference is between GNU versions. For an oversized count
(`head -n 99999999999999999999`), **9.4 refuses** with *Value too large for defined data type* and
**9.11 saturates** to "more than the input has". Until 1.6.15 kriya **wrapped** the number past 2^64,
so `head -n 18446744073709551617` printed **one** line at exit 0.

## Decision

**Both utilities take GNU's full obsolescent grammar in the first argument**, under the five rules
below; the second and third are where kriya differs from GNU on purpose. The utility parses that
argument itself (`_head_obs_parse`, `_tail_obs_parse`) and has the shared expander drop it
(`kriya_obs_consume_first`). A bare-digit option anywhere else is still refused.

1. **A `+` form follows GNU's operand rule exactly** (`_tail_plus_is_count`). `+3` is a legal file
   name, and the rule is what tells the two readings apart, so `tail +3 a b` still reads a file
   named `+3`, as GNU does.
2. **A `-` form is taken whatever follows it**, as `-5` already was. A token that starts with `-`
   cannot be a file name, so the rule has nothing to tell apart. Where GNU refuses (`tail -3c a b`,
   `tail -5 -f f`), kriya answers what the command says.
3. **`head`'s `z` is refused.** kriya's `head` has no `-z` at all, so `head -3z` is refused as
   `head -z` is.
4. **Oversized counts saturate**, as in GNU 9.11 (`kriya_parse_count`, `KRIYA_COUNT_MAX`). The
   number is well formed and only large.
5. A refusal exits **2**, per [ADR 0008](0008-posix-exit-code-policy.md), where GNU exits 1.

`_POSIX2_VERSION` is not read. GNU's `tail` treats `+3` as a file name under
`_POSIX2_VERSION=200112`; kriya always takes GNU's default reading.

## Consequences

- **Positive**: every spelling GNU accepts in the one-operand case gives GNU's bytes and exit
  status (`smoke-head-tail.sh`, and 8,500 generated command lines through
  `scripts/difffuzz-head-tail.py` and its development versions). `tail +2 f`, the idiom for skipping
  a header line, works.
- **Positive**: `tail -5 a b` and `tail -5 -f f`, which kriya has always accepted, keep working.
- **Negative — breaking**: a first argument such as `+5`, followed by at most one operand, is a
  count now, as in GNU. `tail +5 f` used to read a file named `+5`, then `f`. A script that means
  the file writes `./+5` or puts it after `--`. The first `+` form with no operand, `tail +5`, now
  reads standard input from line 5 rather than opening `+5`.
- **Negative**: a script that works under kriya can fail under GNU (`tail -3c a b`). The reverse
  never happens; this is a superset.
- **Negative**: `tail`'s answer for a `+` first argument depends on how many operands follow, as
  GNU's does. This is inherited, not chosen: it is the only rule that reads `tail +3 a b` the way
  GNU does.
- **Neutral**: CI's GNU (9.4) refuses the oversized counts that kriya saturates, so those
  assertions check kriya's answer directly rather than comparing with the local GNU.

## Alternatives considered

- **GNU's operand rule for the `-` forms too.** Rejected. It would turn `tail -5 a b` and
  `tail -5 -f f`, which kriya has accepted since the obsolescent form first shipped, into usage
  errors in a patch release. There is no safety benefit: a `-` token has no second reading to
  protect.
- **Take the `+` forms whatever follows, like the `-` forms.** Rejected. `tail +3 a b` would stop
  reading a file named `+3`, which GNU reads, and would give a different answer rather than a
  refusal.
- **Refuse the `+` forms, as strict POSIX 2008 does.** Rejected. GNU's default accepts them, and
  `tail +2` is in real scripts.
- **Refuse oversized counts, as GNU 9.4 does.** Rejected in favour of the newer GNU behaviour. A
  refusal is safe but unhelpful. A wrap, which kriya did until 1.6.15, is the one wrong answer.
