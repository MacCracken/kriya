#!/bin/sh
# smoke-sort.sh — behavioural test for `kriya sort`.
#
# Compares output cell-by-cell against GNU `sort` for every shipped
# flag combination, plus stability + the boundary cases (empty input,
# no trailing newline, very long lines, multi-file concat).

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
        printf "FAIL %s:\nexpected: %s\ngot:      %s\n" "$1" "$2" "$3" >&2
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

# Compare $BIN sort against GNU sort for the same input + args.
compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | eval "$BIN sort $args")
    gnu=$(printf '%s' "$input" | eval "LC_ALL=C sort $args")
    expect_eq "$name" "$gnu" "$mine"
}

# --- fixtures ---
printf "banana\napple\ncherry\ndate\n" > words
printf "10\n2\n1\n20\n3\n100\n"       > nums
printf "Banana\napple\nCherry\nDate\n" > mixed_case
printf "  hello\nworld\n  foo\n"      > with_blanks
printf "3 c\n1 a\n2 b\n5 e\n4 d\n"    > fielded
printf "a:3\nb:1\nc:2\n"              > csv

# --- default lexicographic ---
compare "default sort"      "$(cat words)"          ""
compare "stable default"    "$(printf 'b\na\nb\nc\nb\n')" ""

# --- -n numeric ---
compare "-n"                "$(cat nums)"           "-n"
compare "-n with negatives" "$(printf '5\n-3\n0\n-10\n7\n')" "-n"

# --- -r reverse ---
compare "-r"                "$(cat words)"          "-r"
compare "-rn"               "$(cat nums)"           "-r -n"

# --- -u unique ---
compare "-u"                "$(printf 'a\na\nb\nb\nc\n')" "-u"
compare "-u with sort"      "$(printf 'z\na\nb\nz\na\n')" "-u"

# --- -f case-fold ---
compare "-f"                "$(cat mixed_case)"     "-f"

# --- -b ignore leading blanks ---
compare "-b"                "$(cat with_blanks)"    "-b"

# --- -t / -k ---
compare "-t ' ' -k 2"       "$(cat fielded)"        "-t ' ' -k 2"
compare "-t ':' -k 2 -n"    "$(cat csv)"            "-t ':' -k 2 -n"

# --- combined ---
compare "-n -r -u"          "$(printf '5\n2\n5\n8\n2\n1\n')" "-n -r -u"

# --- empty input ---
compare "empty"             ""                      ""

# --- no trailing newline ---
compare "no trailing nl"    "$(printf 'b\na\nc')"   ""

# --- multi-file concat ---
printf "x\ny\nz\n" > f1
printf "a\nb\nc\n" > f2
mine=$("$BIN" sort f1 f2)
gnu=$(LC_ALL=C sort f1 f2)
expect_eq "multi-file"      "$gnu" "$mine"

# --- -c check mode ---
expect_exit "-c sorted ok"      0 sh -c "printf 'a\nb\nc\n' | '$BIN' sort -c"
expect_exit "-c unsorted fail"  1 sh -c "printf 'b\na\nc\n' | '$BIN' sort -c"
expect_exit "-c -n unsorted"    1 sh -c "printf '10\n2\n' | '$BIN' sort -c -n"

# --- -o output file ---
"$BIN" sort -o /tmp/sort_out_$$ words
expected=$(LC_ALL=C sort words)
got=$(cat /tmp/sort_out_$$)
expect_eq "-o output"       "$expected" "$got"
rm -f /tmp/sort_out_$$

# --- -z NUL terminator ---
printf 'b\0a\0c\0' > nul_input
mine=$("$BIN" sort -z < nul_input)
expected=$(printf 'a\0b\0c\0')
expect_eq "-z NUL"          "$expected" "$mine"

# --- stable: equal keys keep original order ---
printf "1 z\n2 a\n1 y\n2 b\n1 x\n" > stable_input
mine=$("$BIN" sort -k 1 -s stable_input)
gnu=$(LC_ALL=C sort -k 1 -s stable_input)
expect_eq "stable on equal keys" "$gnu" "$mine"

# --- larger input (1000 lines) ---
seq 1000 -1 1 > big_unsorted
mine=$("$BIN" sort -n big_unsorted)
gnu=$(LC_ALL=C sort -n big_unsorted)
expect_eq "1000 numeric"    "$gnu" "$mine"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
