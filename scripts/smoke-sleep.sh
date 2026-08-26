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
expect_exit "too many operands" 2 "$BIN" sleep 1 2

# GNU accepts `sleep 1m 30s` and sums; POSIX specifies exactly one operand and
# kriya refuses. Summing would make `sleep 1 2` silently mean 3 rather than the
# error it is today — named as a follow-up rather than assumed.

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
