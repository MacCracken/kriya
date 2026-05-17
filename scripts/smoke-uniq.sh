#!/bin/sh
# smoke-uniq.sh — behavioural test for `kriya uniq`.
#
# Compares output cell-by-cell against GNU `uniq` for every shipped
# flag combination, plus the comparison-key permutations (-f field
# skip, -s char skip, -w width cap, -i case fold).

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

# --- fixtures ---
printf "alpha\nalpha\nbeta\ngamma\ngamma\ngamma\ndelta\n" > dups
printf "Apple\napple\nAPPLE\nBANANA\nbanana\n"             > cased
printf "1 alpha\n2 alpha\n3 beta\n4 beta\n5 gamma\n"      > fielded
printf "alpha\nalbatross\nbeta\nbeam\n"                   > widthed
printf "alpha\nalpha\nalpha\n"                            > all_same
printf "one\ntwo\nthree\n"                                > all_unique
printf ""                                                  > empty
printf "lonely"                                            > nonl  # no newline

# --- default ---
expect_eq "default dups"  "$(uniq dups)"            "$($BIN uniq dups)"
expect_eq "default cased" "$(uniq cased)"           "$($BIN uniq cased)"
expect_eq "default all-same" "$(uniq all_same)"     "$($BIN uniq all_same)"
expect_eq "default all-unique" "$(uniq all_unique)" "$($BIN uniq all_unique)"
expect_eq "default empty" "$(uniq empty)"           "$($BIN uniq empty)"
expect_eq "default nonl"  "$(uniq nonl)"            "$($BIN uniq nonl)"

# --- -c count ---
expect_eq "-c dups"       "$(uniq -c dups)"         "$($BIN uniq -c dups)"
expect_eq "-c all-same"   "$(uniq -c all_same)"     "$($BIN uniq -c all_same)"

# --- -d repeated only ---
expect_eq "-d dups"       "$(uniq -d dups)"         "$($BIN uniq -d dups)"
expect_eq "-d all-unique" "$(uniq -d all_unique)"   "$($BIN uniq -d all_unique)"

# --- -u unique only ---
expect_eq "-u dups"       "$(uniq -u dups)"         "$($BIN uniq -u dups)"
expect_eq "-u all-same"   "$(uniq -u all_same)"     "$($BIN uniq -u all_same)"

# --- -i ignore case ---
expect_eq "-i cased"      "$(uniq -i cased)"        "$($BIN uniq -i cased)"
expect_eq "-i -c cased"   "$(uniq -i -c cased)"     "$($BIN uniq -i -c cased)"

# --- -f field skip ---
expect_eq "-f 1 fielded"  "$(uniq -f 1 fielded)"    "$($BIN uniq -f 1 fielded)"
expect_eq "-f 2 fielded"  "$(uniq -f 2 fielded)"    "$($BIN uniq -f 2 fielded)"
expect_eq "-f 0 = default" "$(uniq -f 0 dups)"      "$($BIN uniq -f 0 dups)"

# --- -s char skip ---
printf "abc1\nabc2\nxyz1\n" > char_skip
expect_eq "-s 3 char skip" "$(uniq -s 3 char_skip)"  "$($BIN uniq -s 3 char_skip)"

# --- -w width ---
expect_eq "-w 3 widthed"   "$(uniq -w 3 widthed)"   "$($BIN uniq -w 3 widthed)"

# --- combined comparison flags ---
expect_eq "-f 1 -c"        "$(uniq -f 1 -c fielded)" "$($BIN uniq -f 1 -c fielded)"
expect_eq "-i -w 1 cased"  "$(uniq -i -w 1 cased)"   "$($BIN uniq -i -w 1 cased)"

# --- stdin ---
expect_eq "stdin"         "$(uniq < dups)"          "$($BIN uniq < dups)"

# --- two-operand: input output ---
$BIN uniq dups out_file
expect_eq "2-op out matches" "$(uniq dups)" "$(cat out_file)"

# --- -z NUL terminator (input AND output are NUL-separated) ---
printf 'a\0a\0b\0b\0c\0' > nul_input
nul=$($BIN uniq -z < nul_input | tr -dc '\0' | wc -c | tr -d ' ')
nl=$($BIN uniq -z < nul_input | tr -dc '\n' | wc -c | tr -d ' ')
# 3 distinct groups → 3 NUL terminators in output.
expect_eq "-z 3 NULs"     "3" "$nul"
expect_eq "-z 0 newlines" "0" "$nl"

# --- errors ---
expect_exit "missing"     1 "$BIN" uniq ghost
expect_exit "too many"    2 "$BIN" uniq a b c

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
