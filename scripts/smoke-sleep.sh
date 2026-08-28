#!/bin/sh
# smoke-sleep.sh — behavioural test for `sleep`.
#
# ⚠ Until v1.2.5 `sleep` took a bare integer only: `sleep 0.5`, `sleep 1s` and
# `sleep 1m` were all usage errors. The header deferred them "until the wider
# duration parser lands in lib/chrono.cyr" — but chrono at pin 6.5.35 has
# duration CONSTRUCTORS (`dur_seconds`, `dur_minutes`, …) and no duration STRING
# parser, so there was nothing upstream to wait for.
#
# Timing assertions use a generous floor and a loose ceiling: the point is that
# the duration was PARSED as intended, not that the scheduler is precise. Each
# case is bounded so a parse regression fails the suite instead of hanging it.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

PASS=0
FAIL=0

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: expected '%s', got '%s'\n" "$1" "$2" "$3" >&2
    fi
}

expect_exit() {
    name=$1; expected=$2; shift 2
    rc=0
    timeout 20 "$@" >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}

# elapsed_ms DURATION — wall time of `kriya sleep DURATION`, in milliseconds.
elapsed_ms() {
    s=$(date +%s%N)
    timeout 20 "$BIN" sleep "$1" >/dev/null 2>&1 || true
    e=$(date +%s%N)
    echo $(( (e - s) / 1000000 ))
}

# Measure the harness's own cost with a command that certainly does not sleep,
# so the "returns at once" ceilings scale with the machine instead of asserting
# a constant that only held on the box where it was written.
elapsed_ms_noop() {
    _t0=$(date +%s%N)
    "$BIN" true >/dev/null 2>&1 || true
    _t1=$(date +%s%N)
    echo $(( (_t1 - _t0) / 1000000 ))
}

# elapsed_ms_args ... — wall time of `kriya sleep` with SEVERAL operands.
elapsed_ms_args() {
    s=$(date +%s%N)
    timeout 20 "$BIN" sleep "$@" >/dev/null 2>&1 || true
    e=$(date +%s%N)
    echo $(( (e - s) / 1000000 ))
}

# in_range NAME LOW HIGH ACTUAL
in_range() {
    if [ "$4" -ge "$2" ] && [ "$4" -le "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: %sms outside [%s,%s]\n" "$1" "$4" "$2" "$3" >&2
    fi
}

# --- accepted forms ---------------------------------------------------
# ⚠ These two ceilings have NO sleep underneath them, so the whole budget is
# process overhead: two `date +%s%N` forks, a `timeout` fork, and kriya's own
# exec. On this box that is ~5 ms; on a loaded CI runner it is not bounded by
# anything the test controls. ⭐ Calibrate against a measured no-op instead of
# guessing a constant — `elapsed_ms` of a command that provably does not sleep
# gives the floor, and anything within a wide multiple of it is "at once".
NOOP_MS=$(elapsed_ms_noop)
ZERO_CEIL=$((NOOP_MS * 4 + 200))
in_range "sleep 0 returns at once"  0    "$ZERO_CEIL"  "$(elapsed_ms 0)"
in_range "sleep 0.25 fractional"    200  900  "$(elapsed_ms 0.25)"
in_range "sleep 0.5s frac+suffix"   450  1200 "$(elapsed_ms 0.5s)"
in_range "sleep 1 bare integer"     950  1800 "$(elapsed_ms 1)"
in_range "sleep 1s suffix"          950  1800 "$(elapsed_ms 1s)"
in_range "sleep 0.02m minutes"      1150 2000 "$(elapsed_ms 0.02m)"

# Sub-millisecond fractions truncate rather than surprising: 0.0001s is a no-op.
in_range "sleep 0.0001 truncates"   0    "$ZERO_CEIL" "$(elapsed_ms 0.0001)"

# --- rejected forms ---------------------------------------------------
# ⚠ Each of these must be a USAGE error, not a silent zero-length sleep — a
# mis-parsed duration that returns instantly is the failure mode with no symptom.
expect_exit "no operand"        2 "$BIN" sleep
expect_exit "empty operand"     2 "$BIN" sleep ""
expect_exit "negative"          2 "$BIN" sleep -1
expect_exit "non-numeric"       2 "$BIN" sleep abc
expect_exit "unknown suffix"    2 "$BIN" sleep 1x
expect_exit "bare suffix"       2 "$BIN" sleep s
expect_exit "two decimal points" 2 "$BIN" sleep 1.2.3

# --- several operands SUM (ADR 0015) ------------------------------------
# ⚠ The comment that used to sit here said POSIX specifies exactly one operand
# and that summing would make `sleep 1 2` "silently mean 3 rather than the error
# it is today". There is no POSIX text on this box to source that from, and a
# second operand has no competing meaning to be confused with. GNU sums, its
# `--help` says it sums, and `sleep 1m 30s` is GNU's own documented idiom.
in_range "two operands sum"        380 900 "$(elapsed_ms_args 0.2 0.2)"
in_range "mixed units sum"         380 900 "$(elapsed_ms_args 0.2 0.2s)"
in_range "four operands sum"       380 900 "$(elapsed_ms_args 0.05 0.05 0.05 0.25)"

# ⛔ EVERY OPERAND IS PARSED BEFORE ANY SLEEPING STARTS. The obvious shape —
# parse one, sleep it, move on — makes this case block for an hour and THEN
# report the bad operand.
in_range "a bad operand returns AT ONCE, before sleeping the good one" \
         0 "$ZERO_CEIL" "$(elapsed_ms_args 3600 bogus)"
expect_exit "...with a usage error"  2 "$BIN" sleep 3600 bogus
expect_eq "...and every bad operand is named, not just the first" "3" \
          "$("$BIN" sleep bad1 bad2 bad3 2>&1 | grep -c 'invalid duration')"

# ⛔ SUB-MILLISECOND OPERANDS SUM. Truncating each to whole milliseconds BEFORE
# adding them is a wrong answer that summing made reachable: these two thousand
# operands are 0.8 s, and were 42 ms when every one of them rounded to zero on
# its own. ⚠ The generous ceiling absorbs kriya's per-operand argv cost, which
# is quadratic and tracked separately.
SUBMS=""
i=0
while [ "$i" -lt 2000 ]; do SUBMS="$SUBMS 0.0004"; i=$((i + 1)); done
# shellcheck disable=SC2086
in_range "2000 sub-millisecond operands sum to ~0.8s" 700 2500 "$(elapsed_ms_args $SUBMS)"

# --- `--` ends the options ----------------------------------------------
# ⛔ It used to be COUNTED AS AN OPERAND: `sleep -- 0.1` reported "too many
# operands" for a command line with exactly one. Left unfixed, summing would
# have turned that usage error into a silently wrong total.
expect_exit "-- then one operand"      0 "$BIN" sleep -- 0.1
in_range "...and it sleeps the operand, not zero" 60 "$((ZERO_CEIL + 400))" \
         "$(elapsed_ms_args -- 0.1)"
expect_exit "-- between two operands"  0 "$BIN" sleep 0.1 -- 0.1
# ⚠ GNU exits 0 here, having slept nothing. That is a getopt accident — its
# missing-operand check runs before `--` is consumed — and it contradicts bare
# `sleep`, which GNU does reject. kriya refuses both (ADR 0015).
expect_exit "-- with nothing after it" 2 "$BIN" sleep --

# --- the grammar kriya deliberately does NOT accept (ADR 0015) ----------
# ⛔ `sleep 0x1d` UNDER strtod IS 29 SECONDS, NOT ONE DAY: the `d` is eaten as a
# hex DIGIT and the day suffix silently disappears. GNU documents the trap
# instead of fixing it. A decimal-only grammar cannot express the ambiguity.
expect_exit "hex is refused"        2 "$BIN" sleep 0x1d
expect_exit "exponents are refused" 2 "$BIN" sleep 1e2
expect_exit "a leading + is refused" 2 "$BIN" sleep +1
expect_exit "inf is refused"        2 "$BIN" sleep inf
expect_exit "nan is refused"        2 "$BIN" sleep nan
expect_exit "uppercase suffix is refused" 2 "$BIN" sleep 1S
# ⚠ `1.` IS a decimal and `.5` always worked; rejecting the first was an
# accident of the trailing-character check, not a decision.
expect_exit "a trailing decimal point is a number" 0 "$BIN" sleep 1.
expect_exit "a bare decimal point is not"          2 "$BIN" sleep .

# --- 1.6.3 review: behaviour ADR 0015 records but nothing asserted -------
# ⚠ Both of these are DELIBERATE divergences from GNU. Left unasserted, the ADR
# and the binary could drift apart without a single test turning red.
expect_exit "options are not permuted after operands" 2 "$BIN" sleep 5 --help
expect_exit "negative zero is refused"                2 "$BIN" sleep -- -0
expect_exit "...and so is -0.0"                       2 "$BIN" sleep -- -0.0

# ⛔ THE FRACTION IS MICROSECONDS OF A SECOND, NOT A MILLIONTH OF THE SUFFIX'S
# UNIT. Six digits of a DAY is a granularity of 86.4 ms: `sleep 0.0000009d` is
# 78 ms and returned in 2. ⚠ The bound is generous but the FLOOR is what bites —
# a broken implementation returns immediately.
in_range "a sub-microsecond fraction of a DAY still sleeps" 60 400 \
         "$(elapsed_ms_args 0.0000009d)"
in_range "...and of an hour"  60 400 "$(elapsed_ms_args 0.000022h)"
in_range "...and of a minute" 60 400 "$(elapsed_ms_args 0.0013m)"

# ⛔ A MALFORMED OPERAND WHOSE DIGITS OVERFLOW FIRST IS STILL MALFORMED. The
# sentinel used to return mid-scan, leaving the rest unvalidated, so this
# plainly-broken operand saturated to ~292 years and SLEPT. ⚠ A hang is the
# dangerous direction for a typo.
in_range "a malformed operand with a huge digit run returns at once" \
         0 "$ZERO_CEIL" "$(elapsed_ms_args 99999999999999999999.1.2)"
expect_exit "...with a usage error"  2 "$BIN" sleep 99999999999999999999.1.2
expect_exit "...and the .. spelling" 2 "$BIN" sleep 99999999999999999999..9

# --- durations past the ceiling saturate, they do not wrap ---------------
# ⛔ `sleep 9999999999999999` — a legal 317-million-year request — used to come
# back INSTANTLY with "DURATION must be a non-negative number", because the
# accumulator wrapped negative and the caller read that as "malformed". And
# ⛔ `sleep 4294968` — 49.7 days — RETURNED IN 707 ms WITH EXIT 0, because
# `sleep_ms` hands its argument to `poll(2)`, whose timeout is an `int`, and
# 2^32 ms truncates to nothing. Both are silent failures in the dangerous
# direction: the caller believes it waited.
# ⚠ `3000000` s truncates to a NEGATIVE poll timeout, which blocks forever — so
# it looks identical whether the chunking is there or not and asserts nothing
# about the fix. The values that discriminate are the ones whose truncation is a
# SMALL POSITIVE: `4294968` s is 2^32 + 704 ms, which returned in 707 ms.
for huge in 9999999999999999 4294968 4294967.4 4294968.5 8589935 200000000000d; do
    rc=0
    timeout 2 "$BIN" sleep "$huge" >/dev/null 2>&1 || rc=$?
    expect_eq "a huge duration actually sleeps ($huge)" "124" "$rc"
done

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
