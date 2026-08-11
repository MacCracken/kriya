#!/bin/sh
# smoke-wc.sh — behavioural test for `kriya wc`.
#
# Compares output cell-by-cell against GNU `wc` for each shipped
# flag combination, plus edge cases (empty file, no trailing newline,
# UTF-8 multi-byte sequences, stdin, multi-file total, partial fail).

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

# --- fixture ---
printf "one two three\nfour five\nsix\n" > simple        # 3 lines 6 words 28 bytes
printf "alpha beta\ngamma\n"             > short          # 2 lines 3 words 17 bytes
printf ""                                > empty
printf "no newline"                      > nonl           # 1 partial line
printf "héllo wörld\n"                  > utf8           # 12 codepoints, 14 bytes

# --- default (-l -w -c) matches GNU ---
expect_eq "default simple" "$(wc simple)"       "$($BIN wc simple)"
expect_eq "default short"  "$(wc short)"        "$($BIN wc short)"
expect_eq "default empty"  "$(wc empty)"        "$($BIN wc empty)"
expect_eq "default nonl"   "$(wc nonl)"         "$($BIN wc nonl)"

# --- individual flags ---
expect_eq "-l"             "$(wc -l simple)"    "$($BIN wc -l simple)"
expect_eq "-w"             "$(wc -w simple)"    "$($BIN wc -w simple)"
expect_eq "-c"             "$(wc -c simple)"    "$($BIN wc -c simple)"
# ⚠ The oracle MUST name a UTF-8 locale. GNU `wc -m` counts CHARACTERS only when the locale is
# multibyte; with LANG/LC_ALL unset it silently degrades to counting BYTES, so this line compared
# kriya's (correct) 12 against GNU's byte count of 14 and reported kriya as broken. kriya decodes
# UTF-8 unconditionally and has no locale to degrade to — the test was wrong, not the code.
expect_eq "-m UTF-8"       "$(LC_ALL=C.UTF-8 wc -m utf8)" "$($BIN wc -m utf8)"
expect_eq "-c UTF-8"       "$(wc -c utf8)"      "$($BIN wc -c utf8)"
expect_eq "-L max-line"    "$(wc -L simple)"    "$($BIN wc -L simple)"

# --- combined flags ---
expect_eq "-l -w"          "$(wc -l -w simple)" "$($BIN wc -l -w simple)"
expect_eq "-l -c"          "$(wc -l -c simple)" "$($BIN wc -l -c simple)"
expect_eq "-c -L"          "$(wc -c -L simple)" "$($BIN wc -c -L simple)"

# --- multi-file with total ---
expect_eq "multi default"  "$(wc simple short)" "$($BIN wc simple short)"
expect_eq "multi -l"       "$(wc -l simple short)" "$($BIN wc -l simple short)"

# --- stdin (no operands) ---
expect_eq "stdin default" \
    "$(wc < simple)" \
    "$($BIN wc < simple)"
expect_eq "stdin -l" \
    "$(wc -l < simple)" \
    "$($BIN wc -l < simple)"

# --- large file (exercises multi-read loop) ---
dd if=/dev/zero bs=1024 count=200 2>/dev/null | tr '\0' 'a' > big.txt
echo "" >> big.txt   # 1 line
expect_eq "200KB" "$(wc big.txt)" "$($BIN wc big.txt)"

# --- many lines (sanity on lines+max-line-length) ---
seq 1 1000 > seq.txt
expect_eq "1000 lines"    "$(wc seq.txt)"        "$($BIN wc seq.txt)"
expect_eq "1000 max-line" "$(wc -L seq.txt)"     "$($BIN wc -L seq.txt)"

# --- partial failure: existing + missing ---
rc=0
out=$($BIN wc simple ghost 2>/dev/null) || rc=$?
expect_eq "partial-fail rc" "1" "$rc"
# stdout should still have the simple line (and possibly the total).
if echo "$out" | grep -q "simple"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL partial-fail stdout missing simple" >&2; fi

# --- no operands stdin error path: not applicable here (no error path
#     on empty stdin), but verify with a closed stdin.
expect_exit "no operands ok"    0 sh -c "$BIN wc < /dev/null"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
