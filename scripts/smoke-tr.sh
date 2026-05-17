#!/bin/sh
# smoke-tr.sh — behavioural test for `kriya tr`.
#
# Compares output cell-by-cell against GNU `tr` for every shipped
# mode + set-grammar feature: literal chars, ranges, backslash
# escapes (named + octal), POSIX character classes, complement,
# delete, squeeze, and the combined `-d -s` mode.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

PASS=0
FAIL=0

# Compare stdout between kriya and GNU for the same input.
# Args: name input "kriya_args" "gnu_args" [optional: pass quoted set strings]
compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | eval "$BIN tr $args")
    gnu=$(printf '%s' "$input" | eval "tr $args")
    if [ "$mine" = "$gnu" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nargs:     tr %s\ninput:    %s\nexpected: %s\ngot:      %s\n" "$name" "$args" "$input" "$gnu" "$mine" >&2
    fi
}

expect_exit() {
    name=$1
    expected=$2
    shift 2
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [ "$expected" = "$rc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL $name: expected $expected, got $rc" >&2
    fi
}

# --- translate, literal sets ---
compare "literal pair"      "hello"          "'h' 'H'"
compare "lowercase→upper"   "hello world"    "'a-z' 'A-Z'"
compare "uppercase→lower"   "HELLO World"    "'A-Z' 'a-z'"
compare "rot13"             "Hello, World!"  "'A-Za-z' 'N-ZA-Mn-za-m'"

# --- delete ---
compare "-d vowels"         "hello world"    "-d 'aeiou'"
compare "-d digits"         "abc123def456"   "-d '0-9'"
compare "-d space+tab"      "a b\tc"         "-d ' \t'"

# --- squeeze ---
compare "-s letters"        "heeellloooo"    "-s 'a-z'"
compare "-s space"          "a  b   c"       "-s ' '"
compare "-s all"            "aabbccdd"       "-s 'a-z'"

# --- complement ---
compare "-c -d non-alpha"   "abc 123 def!"   "-c -d '[:alpha:]'"
compare "-c -d non-digit"   "abc 123 def"    "-c -d '[:digit:]'"
compare "-c translate"      "abc 123"        "-c '[:alpha:]' ' '"

# --- POSIX character classes ---
compare "-d [:digit:]"      "abc123def"      "-d '[:digit:]'"
compare "-d [:space:]"      "a b\tc\nd"      "-d '[:space:]'"
compare "-d [:alpha:]"      "abc123"         "-d '[:alpha:]'"
compare "-d [:punct:]"      "hi!world,go."   "-d '[:punct:]'"
compare "[:lower:]→[:upper:]" "Hello"        "'[:lower:]' '[:upper:]'"
compare "-d [:alnum:]"      "ab1c2!#"        "-d '[:alnum:]'"
compare "-d [:cntrl:]"      "$(printf 'a\x01b\x02c')" "-d '[:cntrl:]'"
compare "-d [:xdigit:]"     "1ag2bz"         "-d '[:xdigit:]'"

# --- backslash escapes ---
compare "\\n→space"         "$(printf 'a\nb\nc')" "'\n' ' '"
compare "\\t→pipe"          "$(printf 'a\tb\tc')" "'\t' '|'"
compare "\\\\ literal"      "a\\b"           "'\\\\' '/'"

# --- octal escape ---
compare "octal \\011"       "$(printf 'a\tb')" "'\011' '_'"

# --- -d -s combined (flags before positionals) ---
compare "-d -s SET1 SET2"   "heeellloo  world" "-d -s 'aeiou' ' '"

# --- shorter SET2 padded (GNU behaviour) ---
compare "SET2 shorter pads" "abcdef"         "'a-f' 'X'"

# --- -t truncate ---
compare "-t shorter SET2"   "abcdef"         "-t 'a-f' 'XY'"

# --- errors ---
expect_exit "no args"        2 "$BIN" tr
expect_exit "translate needs 2"  2 sh -c "echo hi | '$BIN' tr 'a-z'"
expect_exit "-d takes one set" 2 sh -c "echo hi | '$BIN' tr -d 'a' 'b'"

# --- empty input ---
compare "empty input"       ""               "'a-z' 'A-Z'"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
