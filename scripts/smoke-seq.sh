#!/bin/sh
# smoke-seq.sh — behavioural test for `kriya seq`.
#
# Compares output cell-by-cell against GNU `seq` for every shipped
# combination of shape (1 / 2 / 3 operands), flag (-s, -w), sign,
# direction, and edge cases (zero increment, descending direction,
# negative bounds, double-dash). Asserts the deferred -f path errors.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0
FAIL=0

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nexpected: '%s'\ngot:      '%s'\n" "$1" "$2" "$3" >&2
    fi
}

expect_exit() {
    name=$1
    expected=$2
    shift 2
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}

# Cell-by-cell parity check. Runs `kriya seq` and GNU `seq` with the
# same args, then diffs the bytes.
check_parity() {
    name=$1
    shift
    expected=$(seq "$@")
    actual=$("$BIN" seq "$@")
    expect_eq "$name" "$expected" "$actual"
}

# --- 1-operand form: seq LAST ---
check_parity "seq 1"           1
check_parity "seq 5"           5
check_parity "seq 0"           0
# seq 0 emits nothing (1 > 0 with default incr +1).

# --- 2-operand form: seq FIRST LAST ---
check_parity "seq 3 7"         3 7
check_parity "seq 7 3"         7 3
check_parity "seq 5 5"         5 5
check_parity "seq -2 2"        -2 2
check_parity "seq 0 4"         0 4

# --- 3-operand form: seq FIRST INCR LAST ---
check_parity "seq 1 2 10"      1 2 10
check_parity "seq 10 -2 0"     10 -2 0
check_parity "seq -5 3 5"      -5 3 5
check_parity "seq 1 1 1"       1 1 1
check_parity "seq 5 1 3"       5 1 3        # empty: incr direction disagrees with bounds
check_parity "seq 3 -1 5"      3 -1 5        # empty: incr direction disagrees with bounds

# --- -s SEPARATOR ---
check_parity "seq -s , 1 5"    -s , 1 5
check_parity "seq -s ,_ 1 4"   -s ,_ 1 4
check_parity "seq -s, 1 5"     -s, 1 5       # attached short value
expect_eq "seq -s '' falls back to newline" "$(seq 1 3)" "$("$BIN" seq -s '' 1 3)"
# Separator with space embedded.
check_parity "seq -s 'X Y' 1 3" -s 'X Y' 1 3

# --- -w EQUAL WIDTH ---
check_parity "seq -w 8 12"     -w 8 12
check_parity "seq -w 0 5"      -w 0 5        # width 1; no pad needed
check_parity "seq -w 95 105"   -w 95 105     # width 3
check_parity "seq -w 1 1 10"   -w 1 1 10
# GNU's width treatment of negatives can differ; only assert what we set as policy.
# Our policy: width = max(text_len(first), text_len(last)) including sign.
# Verify against ourselves only.
actual=$("$BIN" seq -w -3 3)
expect_eq "seq -w -3 3 width-2 pad" "-3
-2
-1
00
01
02
03" "$actual"

# --- Long options ---
check_parity "--separator newline"  --separator , 1 4
check_parity "--separator= eq form" --separator=, 1 4
check_parity "--equal-width"        --equal-width 1 5

# --- -- terminator ---
check_parity "seq -- 1 5"      -- 1 5
check_parity "seq -- -3 3"     -- -3 3

# --- Bare -DIGIT positional (negative-FIRST UX) ---
# `seq -3 3` would otherwise look like a short option. Our parser
# treats `-DIGIT` as positional.
check_parity "seq -3 3 (negfirst)" -3 3
check_parity "seq -5 1 5"          -5 1 5

# --- Exit codes & usage errors ---
expect_exit "seq no operand"        2 "$BIN" seq
expect_exit "seq too many operands" 2 "$BIN" seq 1 2 3 4
expect_exit "seq zero increment"    2 "$BIN" seq 0 0 5
expect_exit "seq -f deferred"       2 "$BIN" seq -f %d 1 3
expect_exit "seq --format deferred" 2 "$BIN" seq --format=%d 1 3
expect_exit "seq unknown short"     2 "$BIN" seq -x 5
expect_exit "seq unknown long"      2 "$BIN" seq --nope 5
expect_exit "seq bad LAST"          2 "$BIN" seq abc
expect_exit "seq bad FIRST"         2 "$BIN" seq abc 5
expect_exit "seq bad INCR"          2 "$BIN" seq 1 abc 5

# --- Output bytes match GNU bytes ---
check_parity "large ascending"      1 100
check_parity "large with incr"      1 7 99
check_parity "negative large"       -50 50

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
