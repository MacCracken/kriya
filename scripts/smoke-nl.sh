#!/bin/sh
# smoke-nl.sh — behavioural test for `kriya nl`.
#
# Compares output cell-by-cell against GNU `nl` for every shipped
# flag combination. The "unnumbered padding = width + sep_len spaces"
# rule is the load-bearing GNU quirk and gets explicit coverage.

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

# --- fixture: mix of empty + non-empty lines ---
printf "alpha\n\nbeta\ngamma\n\n\ndelta\n" > mix
printf "x\ny\nz\n" > short
seq 1 50 > nums
printf "no trailing nl"                   > nonl
printf ""                                 > empty

# --- default -b t (number non-empty) ---
expect_eq "default mix"   "$(nl mix)"             "$($BIN nl mix)"
expect_eq "default short" "$(nl short)"           "$($BIN nl short)"
expect_eq "default empty" "$(nl empty)"           "$($BIN nl empty)"
expect_eq "default nonl"  "$(nl nonl)"            "$($BIN nl nonl)"

# --- -b a (number all) ---
expect_eq "-b a mix"      "$(nl -b a mix)"        "$($BIN nl -b a mix)"

# --- -b n (number none) ---
expect_eq "-b n mix"      "$(nl -b n mix)"        "$($BIN nl -b n mix)"

# --- -n FORMAT ---
expect_eq "-n rz"         "$(nl -n rz mix)"       "$($BIN nl -n rz mix)"
expect_eq "-n ln"         "$(nl -n ln mix)"       "$($BIN nl -n ln mix)"
expect_eq "-n rn explicit" "$(nl -n rn mix)"      "$($BIN nl -n rn mix)"

# --- -w width ---
expect_eq "-w 3"          "$(nl -w 3 mix)"        "$($BIN nl -w 3 mix)"
expect_eq "-w 10"         "$(nl -w 10 mix)"       "$($BIN nl -w 10 mix)"

# --- -s separator (the unnumbered-padding interaction is the key test) ---
expect_eq "-s ': '"       "$(nl -s ': ' mix)"     "$($BIN nl -s ': ' mix)"
expect_eq "-s 'XXX'"      "$(nl -s XXX mix)"      "$($BIN nl -s XXX mix)"

# --- -v starting number ---
expect_eq "-v 100"        "$(nl -v 100 short)"    "$($BIN nl -v 100 short)"

# --- -i increment ---
expect_eq "-i 5"          "$(nl -i 5 short)"      "$($BIN nl -i 5 short)"

# --- combined flags ---
expect_eq "-b a -n rz -w 4" \
    "$(nl -b a -n rz -w 4 short)" \
    "$($BIN nl -b a -n rz -w 4 short)"

# --- stdin ---
expect_eq "stdin"         "$(nl < mix)"           "$($BIN nl < mix)"
expect_eq "stdin -b a"    "$(nl -b a < mix)"      "$($BIN nl -b a < mix)"

# --- larger input ---
expect_eq "50 lines"      "$(nl nums)"            "$($BIN nl nums)"

# --- errors ---
expect_exit "bad -b"      2 "$BIN" nl -b xyz mix
expect_exit "bad -n"      2 "$BIN" nl -n abc mix
expect_exit "missing file" 1 "$BIN" nl ghost

# --- multi-file (GNU continuous numbering) ---
expect_eq "multi-file"    "$(nl short mix)"       "$($BIN nl short mix)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
