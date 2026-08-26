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

# --- ⭐ [=c=] equivalence classes and [c*N] repetition -------------------
#
# ⛔ `[=e=]` used to fall through to the LITERAL branch, so it was read as the
# set {'[', '=', 'e', ']'} — `tr '[=e=]' X` on `a[b=c]de` produced `aXbXcXdX`
# where GNU produces `a[b=c]dX`. ⚠ Invisible on any input without a bracket or
# equals sign in it, which is most input, so the fixture below deliberately
# contains both.
#
# ⚠ In the C and C.UTF-8 locales an equivalence class holds only the character
# itself — measured: `tr '[=e=]' x` leaves é and è untouched.
# ⚠ This script's `compare` helper builds its command with `eval`, which cannot
# carry a set containing `[`, `*` or `=` safely. These pass argv directly and
# diff the bytes, so a set is never re-parsed by a shell.
eq_bytes() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nexpected: %s\ngot:      %s\n" "$1" "$2" "$3" >&2
    fi
}
tr_same() {
    label=$1; inp=$2; shift 2
    g=$(printf '%s' "$inp" | tr "$@" 2>&1 | od -An -c) || true
    k=$(printf '%s' "$inp" | "$BIN" tr "$@" 2>&1 | od -An -c) || true
    eq_bytes "set-syntax: $label" "$g" "$k"
}
tr_same "[=e=] with brackets in input" 'a[b=c]de' '[=e=]' X
tr_same "[=e=] plain"                  'eee'      '[=e=]' X
tr_same "[=e=] leaves é and è"         'eéè'      '[=e=]' X
tr_same "[x*3] explicit count"         'abc'        abc '[x*3]'
tr_same "[x*] pads to SET1 length"     'abc'        abc '[x*]'
tr_same "[x*2] shorter than SET1"      'abc'        abc '[x*2]'
tr_same "[a*3] under -d"               'aaabbb'   -d '[a*3]'
tr_same "classes still work"           'abc'      '[:lower:]' '[:upper:]'
tr_same "ranges still work"            'abc'      a-c x-z
tr_same "a literal bracket set"        'a[b]c'    '[]' X

# ⛔ A LEADING ZERO IS OCTAL, as in GNU: `[x*010]` is eight, not ten.
tr_same "[x*010] is octal (8)"         'abcdefghij' abcdefghij '[x*010]'

# ⛔ `[c*]` is refused in SET1 — GNU: "the [c*] repeat construct may not appear
# in string1". ⚠ kriya exits 2 (ADR 0008 usage error) where GNU exits 1; that
# policy is pre-existing, `tr abc` with a missing SET2 already differs the same
# way, so only the REFUSAL is compared here, not the status.
rc=0; printf 'aaa' | "$BIN" tr -s '[a*]' >/dev/null 2>&1 || rc=$?
eq_bytes "set-syntax: [c*] refused in SET1" "2" "$rc"
grc=0; printf 'aaa' | tr -s '[a*]' >/dev/null 2>&1 || grc=$?
if [ "$grc" -ne 0 ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); echo "FAIL set-syntax: GNU should also refuse [c*] in SET1" >&2
fi

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
