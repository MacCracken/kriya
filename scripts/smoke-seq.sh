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
# ⛔ AN EMPTY SEPARATOR IS EMPTY (1.9.0): `seq -s '' 1 3` is `123`. kriya swapped in a newline,
# and this case asserted it, against GNU 9.4 and 9.12 alike.
check_parity "seq -s '' 1 3"   -s '' 1 3
# Separator with space embedded.
check_parity "seq -s 'X Y' 1 3" -s 'X Y' 1 3

# --- -w EQUAL WIDTH ---
check_parity "seq -w 8 12"     -w 8 12
check_parity "seq -w 0 5"      -w 0 5        # width 1; no pad needed
check_parity "seq -w 95 105"   -w 95 105     # width 3
check_parity "seq -w 1 1 10"   -w 1 1 10
# ⭐ -w's width is GNU's since 1.9.0: from the operands' TEXT, so `008` is three wide.
check_parity "seq -w -3 3"     -w -3 3
check_parity "seq -w 008 11"   -w 008 11
check_parity "seq -w -05 3"    -w -05 3

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
expect_exit "seq -f %d refused"     2 "$BIN" seq -f %d 1 3
expect_exit "seq --format=%d refused" 2 "$BIN" seq --format=%d 1 3
expect_exit "seq unknown short"     2 "$BIN" seq -x 5
expect_exit "seq unknown long"      2 "$BIN" seq --nope 5
expect_exit "seq bad LAST"          2 "$BIN" seq abc
expect_exit "seq bad FIRST"         2 "$BIN" seq abc 5
expect_exit "seq bad INCR"          2 "$BIN" seq 1 abc 5

# --- Output bytes match GNU bytes ---
check_parity "large ascending"      1 100
check_parity "large with incr"      1 7 99
check_parity "negative large"       -50 50

# --- past 2^63 - 1: GNU's numbers, not a refusal (1.9.0) --------------------
#
# ⛔ `seq 18446744073709551617 18446744073709551617` printed `1` and `seq 9223372036854775807
# 9223372036854775807` printed forever, until 1.6.16; then kriya refused every number past an i64.
# ⭐ Since 1.9.0 it prints GNU's: non-negative integers of any size as decimal strings, the rest as
# `long double`s. The i64 edge, where the step used to wrap, stays covered.
for _a in "9223372036854775806 9223372036854775807" "9223372036854775807 9223372036854775807" \
          "9223372036854775800 5 9223372036854775807" "-9223372036854775800 -5 -9223372036854775807" \
          "-9223372036854775807 -9223372036854775806" "-9223372036854775807 -9223372036854775807" \
          "9223372036854775808 9223372036854775808" "18446744073709551617 18446744073709551617" \
          "18446744073709551614 18446744073709551617" "1 18446744073709551616 18446744073709551617" \
          "-9223372036854775808 -9223372036854775808" "5 -18446744073709551617 3" \
          "-18446744073709551617 -18446744073709551615" "9223372036854775806 9223372036854775809"; do
    # shellcheck disable=SC2086
    expect_eq "seq $_a" "$(seq $_a)" "$(timeout 5 "$BIN" seq $_a)"
done
# ⚠ These two run as far as GNU's do, which is past any test: compare the start.
expect_eq "seq 99999999999999999999 starts as GNU's" "$(seq 99999999999999999999 | head -3)" \
    "$(timeout 5 "$BIN" seq 99999999999999999999 | head -3)"
expect_eq "seq 18446744073709551617 starts as GNU's" "$(seq 18446744073709551617 | head -3)" \
    "$(timeout 5 "$BIN" seq 18446744073709551617 | head -3)"

# --- 1.9.0: floating point --------------------------------------------------
#
# ⭐ FIRST, INCREMENT and LAST are GNU's `long double` (src/lib/xfloat.cyr, ADR 0032): `first + i *
# step` with two roundings, the default `%.Pf`, `%0W.Pf` or `%g`, the value past LAST printed when
# it prints as LAST. Byte for byte, against GNU 9.4, 9.7 and 9.12. ⚠ The oracle is x86_64: GNU's
# `long double` is binary128 on aarch64.
for _a in "0.1 0.1 0.5" "0 0.000001 0.000003" "1 0.1 1.3" "-1 0.25 1" "0.1 0.3" "5 -0.5 3" "1e2 1e2" \
          "0 0.1 1" "-1 2e-1 0" "1 3 9e0" "1e-3 1e-3 3e-3" "1.5" "0x1p1 3" "0 1e-1 0.3" "10 -1e0 8" \
          "1e4932 1e4932" "-0 2" "2 -1 0" "0.25 0.1 1.05" "100 -33.3 0" "0.000001 0.0000003 0.000003"; do
    # shellcheck disable=SC2086
    expect_eq "seq $_a" "$(seq $_a)" "$(timeout 10 "$BIN" seq $_a)"
done
for _a in "-w 1 0.5 3" "-w 10 -0.5 9" "-w .5 2" "-w 1. 3" "-w 1e1 12" "-w 0x10 18" "-w -1.5 0.5 1" "-w 9.5 0.25 10.5"; do
    # shellcheck disable=SC2086
    expect_eq "seq $_a" "$(seq $_a)" "$(timeout 10 "$BIN" seq $_a)"
done
# -f FORMAT: one floating-point directive, flags, width, precision, `L`, `%%` around it.
for _f in '%.3f' 'x%gy' '%%%g%%' '%e' '%a' '%5.1f' '%-6g|' '%Lg' "%'g" '%#g' '% g' '%+05.1f' \
          '%E' '%G' '%A' '%.0f' '%010.4e'; do
    expect_eq "seq -f $_f" "$(seq -f "$_f" 0.5 0.5 3)" "$(timeout 10 "$BIN" seq -f "$_f" 0.5 0.5 3)"
done
expect_eq "seq -f halves to even" "$(seq -f %.0f 0.5 1 3.5)" "$("$BIN" seq -f %.0f 0.5 1 3.5)"
for _f in '%d' 'abc' '%g%g' '%' '%*g' '%5'; do
    expect_exit "seq -f $_f refused" 2 "$BIN" seq -f "$_f" 3
done
expect_exit "seq -f with -w refused" 2 "$BIN" seq -f %g -w 3
for _a in "0.1 x" "nan" "1 nan 3" "1 0 3" "1 -0 3" "1e5000" "inf 3" "1 inf 3"; do
    # shellcheck disable=SC2086
    rc=0; timeout 5 "$BIN" seq $_a > /dev/null 2>&1 || rc=$?
    grc=0; timeout 5 seq $_a > /dev/null 2>&1 || grc=$?
    if [ "$grc" = 0 ]; then expect_eq "seq $_a" "$(seq $_a | head -5)" "$(timeout 5 "$BIN" seq $_a | head -5)"
    else expect_eq "seq $_a refused" "2" "$rc"; fi
done
# ⚠ An operand below the smallest normal: 9.12 reads it, 9.4 called it an invalid argument (older
# gnulib `xstrtold` counted gradual underflow as an error). kriya follows 9.12; asserted.
expect_eq "seq -f %f 1e-4950 1" "$(printf '0.000000\n1.000000')" "$("$BIN" seq -f %f 1e-4950 1)"
expect_eq "seq -s, 0.5 0.5 2" "$(seq -s, 0.5 0.5 2)" "$("$BIN" seq -s, 0.5 0.5 2)"
expect_eq "seq -s '' 0 0.5 1" "$(seq -s '' 0 0.5 1)" "$("$BIN" seq -s '' 0 0.5 1)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
