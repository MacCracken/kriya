# 0015 — `sleep` sums its operands, and refuses GNU's number grammar

**Status**: Accepted
**Date**: 2026-08-27

## Context

kriya's `sleep` took exactly one operand and rejected a second with exit 2 and
the message *"too many operands (POSIX sleep takes one integer)"*. GNU sums
several — `sleep 1m 30s` is ninety seconds, and GNU's own `--help` says so:
*"With multiple arguments, pause for the sum of their values."*

The roadmap carried this as an unnamed follow-up for six releases on the strength
of the parenthetical in that message. ⛔ **The parenthetical is not sourceable.**
There is no POSIX text on this machine — no `man`, no `man1p`, no
`man-pages-posix` — so the claim that "POSIX specifies exactly one" cannot be
checked against the standard from here. What POSIX does is name one operand in a
SYNOPSIS, which constrains what portable callers should *write*; it does not
forbid an implementation from accepting more. GNU's own manual says the same
thing in the same direction: *portable scripts* must pass a single value.

Three things settle it:

- **ADR 0011's test applies unchanged.** Its decisive argument was that kriya
  ships a *binary*, reached when a shell builtin is not, so it should match the
  binary it substitutes for. `/usr/bin/sleep` sums, documents summing, and is the
  thing an AGNOS script reaches.
- **Nothing is silently reinterpreted.** `sleep` has no second parameter, so a
  second operand has no competing meaning to be confused with. This is not
  ADR 0004's `rm` case, where a guard prevents an irreversible catastrophe; the
  worst outcome of summing is that a process waits three seconds.
- **Summing is strictly more permissive.** Every single-operand invocation keeps
  byte-identical behaviour. The only invocations whose meaning changes are the
  ones that exit 2 today — already broken from the caller's point of view.

Measuring GNU also turned up four things a naive implementation gets wrong, and
one of them is a trap GNU documents rather than fixes.

## Decision

**`sleep` sums its operands.** Every operand is parsed and validated BEFORE any
sleeping begins, the total is accumulated in microseconds, and the process sleeps
once.

kriya deliberately does NOT take the rest of GNU's behaviour:

| GNU | kriya | why |
|---|---|---|
| `strtod` grammar: `0x10`, `1e2`, `+1`, leading whitespace, `inf`, `infinity` | decimal only, with an `s`/`m`/`h`/`d` suffix | see the `0x1d` trap below |
| exit 1 for every usage error | **exit 2** | ADR 0008's three-tier convention, already diverging across 38 utilities |
| `sleep --` exits 0, having slept nothing | **usage error** | GNU's own bare `sleep` is an error; the difference is a getopt accident, not a rule |
| options permuted after operands (`sleep 5 --help`) | not permuted | ADR 0002 |
| one diagnostic per invalid operand | same — every bad operand is named | matched deliberately |

⛔ **THE HEX TRAP IS THE REASON FOR THE GRAMMAR DECISION.** Under `strtod`,
`sleep 0x1d` sleeps **29 seconds**, not one day: `d` is consumed as a hexadecimal
DIGIT, so `0x1d` is 29 and the day suffix silently disappears. Measured — 29,002
ms, exit 0. GNU documents the workaround (*"A hexadecimal number can precede a
'd' suffix only if the number has a 'p' style exponent, e.g., '0x1p0d' means one
day"*) rather than fixing it, and `0x1p-16d` does indeed sleep 1,320 ms.
⚠ **Inheriting that is a regression dressed as compatibility.** A decimal-only
grammar cannot express the ambiguity.

Out-of-range durations **saturate** at ~292 years rather than erroring, which
is what GNU does in effect (`sleep 1e400` overflows a double to `+inf` and sleeps
forever, with no diagnostic anywhere).

## Consequences

- **Positive** — `sleep 1m 30s`, GNU's own motivating example, works. Scripts
  ported to AGNOS stop hitting an exit 2 that cited an unciteable requirement.
- **Positive** — three defects fixed on the way in, all of them pre-existing and
  all of them silent (see below).
- **Negative** — a caller relying on `kriya sleep 1 2` exiting 2 as an argument
  canary loses it. Nothing in-tree did; there were no `sleep` tests at all.
- **Negative** — kriya now differs from GNU on a grammar that GNU's `--help`
  describes loosely as "an integer or floating-point number". `0x10`, `1e2` and
  `+1` are refused. Asserted, so the refusal is visible rather than incidental.
- **Neutral** — `sleep -- -0` is exit 0 under GNU (IEEE `-0.0` passes its
  `0 <= s` guard) and exit 2 here. Recorded, not chased.

### Three silent defects fixed by the same change

⛔ **A 49.7-day sleep returned in 707 milliseconds.** `sleep_ms` passes its
argument to `poll(2)`, whose timeout is an `int`; 2^32 ms truncates to zero.
Measured before the fix: `kriya sleep 4294968` — forty-nine days — returned in
**707 ms with exit 0**. ⚠ The failure is silent and in the dangerous direction: a
retry loop or a boot script believes it waited. `_sleep_total_ms` now sleeps in
one-day chunks — 86,400,000 ms against `INT_MAX`'s 2,147,483,647, a margin of
**24.9x**.

⛔ **A well-formed long duration was reported as malformed.** The parser's
accumulator wrapped, the caller read the negative result as "not a number", and
`kriya sleep 9999999999999999` printed *"DURATION must be a non-negative
number"* about an operand that was one. Overflow now returns a distinct sentinel
and saturates.

⛔ **`--` was counted as an operand.** `kriya sleep -- 0.1` reported *"too many
operands"* for a command line with exactly one. ⚠ Left unfixed, the summing
change would have converted that usage error into a silently wrong TOTAL.

### And one the summing itself created, caught before release

⛔ **Truncating each operand to whole milliseconds before summing.** Two thousand
`0.0004` operands are 0.8 s under GNU and were **42 ms** here — every one of them
rounded to zero on its own. The parser now works in microseconds and the
conversion to milliseconds happens ONCE, on the total. ⚠ Sub-millisecond
resolution is still lost at the syscall; it is lost once instead of per operand.

## Alternatives considered

- **Keep the refusal and write the ADR defending it.** Rejected: the ADR would
  have to say "we prefer the error", not "POSIX made us", because the POSIX claim
  cannot be sourced. That is a much weaker thing to write down, and it leaves
  GNU's documented idiom broken against kriya.
- **Adopt `strtod` wholesale for grammar parity.** Rejected on `0x1d`. Copying a
  documented footgun to score a compatibility point is the wrong trade, and the
  same reasoning already appears in ADR 0011.
- **Error on an out-of-range duration instead of saturating.** Rejected: GNU has
  no overflow path at all, and erroring on `sleep 1e400` would refuse an
  invocation GNU accepts while buying nothing — the request is "sleep longer than
  this machine will exist" either way.
- **Sleep each operand in turn.** Rejected, and it is the obvious shape:
  `sleep 3600 bogus` would block for an hour and THEN report the bad operand.
  GNU returns in a millisecond; parse-all-then-sleep-once is required, not
  stylistic.
