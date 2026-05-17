#!/bin/sh
# smoke-cut.sh — behavioural test for `kriya cut`.
#
# Compares output cell-by-cell against GNU `cut` for every shipped
# mode (-b/-c/-f) + LIST grammar form (N, N-, -M, N-M, N,M, mixed).

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

# Compare $BIN cut against GNU cut for the same args+input.
compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | eval "$BIN cut $args")
    gnu=$(printf '%s' "$input" | eval "cut $args")
    expect_eq "$name" "$gnu" "$mine"
}

# --- fixtures ---
printf "a,b,c,d,e\nf,g,h,i,j\nk,l,m,n,o\n" > csv
printf "abcdef\nghijkl\n123456\n"           > raw
printf "a:b:c\nnocolon\nd:e:f\n"            > mixed
printf "field1\tfield2\tfield3\n"           > tabs

# --- -f field mode ---
compare "-f 1 -d ,"           "$(cat csv)"   "-f 1 -d ','"
compare "-f 2 -d ,"           "$(cat csv)"   "-f 2 -d ','"
compare "-f 1,3 -d ,"         "$(cat csv)"   "-f 1,3 -d ','"
compare "-f 1-3 -d ,"         "$(cat csv)"   "-f 1-3 -d ','"
compare "-f 3- -d ,"          "$(cat csv)"   "-f 3- -d ','"
compare "-f -3 -d ,"          "$(cat csv)"   "-f -3 -d ','"
compare "-f 1,3,5 -d ,"       "$(cat csv)"   "-f 1,3,5 -d ','"
compare "-f 2-4 -d ,"         "$(cat csv)"   "-f 2-4 -d ','"
compare "-f 99 -d ,"          "$(cat csv)"   "-f 99 -d ','"

# --- default TAB delimiter ---
compare "-f 2 default delim"  "$(cat tabs)"  "-f 2"

# --- -s only-delimited ---
compare "-f 1 -s with no-delim line" "$(cat mixed)" "-f 1 -d ':' -s"
compare "-f 1 default (no -s)"       "$(cat mixed)" "-f 1 -d ':'"

# --- -b byte mode ---
compare "-b 1 raw"            "$(cat raw)"   "-b 1"
compare "-b 1-3 raw"          "$(cat raw)"   "-b 1-3"
compare "-b 3- raw"           "$(cat raw)"   "-b 3-"
compare "-b -3 raw"           "$(cat raw)"   "-b -3"
compare "-b 1,3,5 raw"        "$(cat raw)"   "-b 1,3,5"

# --- -c char mode (ASCII-only — same as -b for our smoke) ---
compare "-c 1-3 raw"          "$(cat raw)"   "-c 1-3"
compare "-c 2-4 raw"          "$(cat raw)"   "-c 2-4"

# --- --complement ---
compare "-f --complement"     "$(cat csv)"   "-f 1 -d ',' --complement"
compare "-c --complement"     "$(cat raw)"   "-c 1-3 --complement"

# --- --output-delimiter ---
compare "-f w/ output-delim"  "$(cat csv)"   "-f 1,3,5 -d ',' --output-delimiter='|'"

# --- stdin ---
compare "stdin -f"            "$(cat csv)"   "-f 2 -d ','"

# --- empty / partial inputs ---
compare "empty input"         ""             "-f 1 -d ','"
compare "single line"         "a,b,c"        "-f 2 -d ','"
compare "no trailing newline" "a,b,c"        "-f 1 -d ','"

# --- errors ---
expect_exit "no mode"         2 "$BIN" cut /dev/null
expect_exit "two modes"       2 "$BIN" cut -c 1 -f 1 /dev/null
expect_exit "-s without -f"   2 "$BIN" cut -c 1 -s /dev/null
expect_exit "multibyte delim" 2 "$BIN" cut -f 1 -d ',,' /dev/null
expect_exit "missing file"    1 "$BIN" cut -f 1 ghost_file

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
