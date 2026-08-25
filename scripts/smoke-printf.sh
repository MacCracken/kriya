#!/bin/sh
# smoke-printf.sh — behavioural test for `kriya printf`.
#
# Compares output cell-by-cell against `/usr/bin/printf` (the GNU
# coreutils binary, not the shell builtin which has different escape
# semantics) for every shipped conversion and flag combination.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"
GNU=/usr/bin/printf

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

# `compare NAME ARGS...` runs both impls with the same args and diffs.
compare() {
    name=$1
    shift
    mine=$("$BIN" printf "$@" 2>/dev/null || true)
    gnu=$("$GNU" "$@" 2>/dev/null || true)
    expect_eq "$name" "$gnu" "$mine"
}

# --- escapes in FORMAT ---
compare "literal text"        "hello"
compare "\\n escape"          "a\nb\n"
compare "\\t escape"          "x\ty"
compare "octal \\012"         "\012"
compare "octal \\110"         "\110\145\154\154\157"   # "Hello"
compare "literal \\\\"        "\\\\"

# --- %s ---
compare "%s simple"           "%s\n" "world"
compare "%s empty"            "%s\n" ""
compare "%s width"            "[%10s]\n" "hi"
compare "%s left"             "[%-10s]\n" "hi"
compare "%s precision"        "[%.3s]\n" "hellothere"
compare "%s width+prec"       "[%10.3s]\n" "hellothere"
compare "%s * width"          "[%*s]\n" "8" "abc"
compare "%s * prec"           "[%.*s]\n" "3" "abcdef"

# --- %d / %i ---
compare "%d"                  "%d\n" "42"
# Negative-data arg needs `--` to terminate option parsing (POSIX
# convention; kriya is strict per ADR 0002).
mine=$("$BIN" printf "%d\n" -- "-7" 2>/dev/null || true)
gnu=$("$GNU" "%d\n" "-7" 2>/dev/null || true)
expect_eq "%d negative" "$gnu" "$mine"
compare "%d zero"             "%d\n" "0"
compare "%i alias"            "%i\n" "100"
compare "%d width"            "[%5d]\n" "42"
compare "%d zero-pad"         "[%05d]\n" "42"
compare "%d +"                "[%+d]\n" "42"
compare "%d space"            "[% d]\n" "42"
compare "%d left-justify"     "[%-5d|]\n" "42"
compare "%d precision"        "[%.5d]\n" "42"

# --- %u ---
compare "%u positive"         "%u\n" "42"

# --- %o ---
compare "%o"                  "%o\n" "8"
compare "%#o alt"             "%#o\n" "8"
compare "%o width"            "[%5o]\n" "8"

# --- %x / %X ---
compare "%x"                  "%x\n" "255"
compare "%X"                  "%X\n" "255"
compare "%#x"                 "%#x\n" "255"
compare "%#X"                 "%#X\n" "255"
compare "%08x"                "%08x\n" "255"

# --- %c ---
compare "%c first byte"       "%c\n" "abc"
compare "%c empty"            "%c\n" ""

# --- %b ---
compare "%b with \\n"         "%b" "hello\nworld\n"
compare "%b with \\t"         "%b" "a\tb\tc\n"
compare "%b with octal"       "%b" "\110ello\n"

# --- %% ---
compare "%% literal"          "100%%\n"
compare "%% in middle"        "[%%]\n"

# --- arg reuse: more args than spec, format repeats ---
compare "arg reuse %s"        "%s\n" "a" "b" "c"
compare "arg reuse %d %s"     "%d=%s\n" "1" "one" "2" "two" "3" "three"

# --- arg shortage: missing args = 0 / "" ---
compare "missing %s"          "[%s]\n"
compare "missing %d"          "[%d]\n"

# --- numeric arg parsing: 'X form, 0x hex, 0 octal ---
compare "'X char-constant"    "%d\n" "'A"
compare "0x hex arg"          "%d\n" "0xff"
compare "0 octal arg"         "%d\n" "0177"

# --- errors ---
expect_exit "no FORMAT"  2 "$BIN" printf

# --- invalid directives fail instead of lying (v1.2.1) ---
# ⛔ printf used to WARN on stderr, write the bare conversion LETTER to stdout
# (dropping the `%`) and exit 0 — so `printf '%f' 1.5` produced the text "f" and
# reported success. GNU exits 1 and prints nothing for an invalid conversion.
for d in %f %e %g %a; do
    rc=0; out=$("$BIN" printf "$d" 1.5 2>/dev/null) || rc=$?
    expect_eq "$d exits 1"       "1" "$rc"
    expect_eq "$d prints nothing" ""  "$out"
done
rc=0; out=$("$BIN" printf '%Z' 2>/dev/null) || rc=$?
expect_eq "%Z exits 1"        "1" "$rc"
expect_eq "%Z prints nothing" ""  "$out"
# Output already written before the error is kept, and processing STOPS —
# byte-for-byte what GNU does.
expect_eq "abc%Zdef stops after abc" "$(/usr/bin/printf 'abc%Zdef' 2>/dev/null)" "$("$BIN" printf 'abc%Zdef' 2>/dev/null)"

# --- \xHH hex escape (v1.2.1) ---
# Used to fall through to the unknown-escape path and print a literal "x41".
for e in '\x41' '\x7a' '\x4' '\x41B' '\101' '\n' '\t'; do
    expect_eq "escape $e" "$(/usr/bin/printf "$e" | od -An -c)" "$("$BIN" printf "$e" | od -An -c)"
done
rc=0; "$BIN" printf '\xZ' >/dev/null 2>&1 || rc=$?
expect_eq "\\xZ exits 1" "1" "$rc"
expect_eq "abc\\xZdef stops after abc" "$(/usr/bin/printf 'abc\xZdef' 2>/dev/null)" "$("$BIN" printf 'abc\xZdef' 2>/dev/null)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
