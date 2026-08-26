#!/bin/sh
# smoke-basename-dirname.sh — paired behavioural test for the two
# text-only path utilities. Both wrap primitives already in
# `src/lib/path.cyr` (tested at the unit level by `tests/kriya.tcyr`);
# this script covers the CLI surface and POSIX/GNU edges.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

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
        printf "FAIL %s: expected '%s', got '%s'\n" "$1" "$2" "$3" >&2
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

run_capture() {
    "$@" 2>/dev/null
}

# --- basename POSIX single-pair ---
expect_eq "basename /usr/bin/cp"     "cp"  "$(run_capture "$BIN" basename /usr/bin/cp)"
expect_eq "basename cp"              "cp"  "$(run_capture "$BIN" basename cp)"
expect_eq "basename /"               "/"   "$(run_capture "$BIN" basename /)"
expect_eq "basename ./cp"            "cp"  "$(run_capture "$BIN" basename ./cp)"
expect_eq "basename /a/b/"           "b"   "$(run_capture "$BIN" basename /a/b/)"
expect_eq "basename empty"           ""    "$(run_capture "$BIN" basename "")"

# --- basename with suffix ---
expect_eq "basename cp.exe .exe"     "cp"  "$(run_capture "$BIN" basename /usr/bin/cp.exe .exe)"
expect_eq "basename foo.log .log"    "foo" "$(run_capture "$BIN" basename foo.log .log)"
# Suffix only stripped if result has at least one byte (POSIX).
expect_eq "basename whole-suffix"    ".log" "$(run_capture "$BIN" basename .log .log)"
# Non-matching suffix is a no-op.
expect_eq "basename non-matching"    "foo.txt" "$(run_capture "$BIN" basename foo.txt .log)"

# --- basename -a (multiple) ---
out=$(run_capture "$BIN" basename -a /usr/bin/cp /var/log/foo /home/x)
expected="cp
foo
x"
expect_eq "basename -a multi" "$expected" "$out"

# --- basename -s SUFFIX (multiple + suffix) ---
out=$(run_capture "$BIN" basename -s .log /var/log/foo.log /var/log/bar.log)
expected="foo
bar"
expect_eq "basename -s" "$expected" "$out"

# --- basename -z (NUL terminator) ---
# ⚠ Compare BYTES, not `od`'s rendering. This asserted a string that encodes
# GNU od's three-column layout, its leading blank, and its spelling of NUL as
# `\0` — none of which are kriya's output. busybox od and BSD od pad and
# escape differently, so the test measured which od was installed.
out=$("$BIN" basename -z /usr/bin/cp | tr '\0' '@')
expect_eq "basename -z NUL-terminated" "cp@" "$out"

# --- basename errors ---
expect_exit "basename no args"       2 "$BIN" basename
expect_exit "basename too many"      2 "$BIN" basename a b c

# --- dirname POSIX ---
expect_eq "dirname /a/b/c"           "/a/b" "$(run_capture "$BIN" dirname /a/b/c)"
expect_eq "dirname a/b"              "a"    "$(run_capture "$BIN" dirname a/b)"
expect_eq "dirname a"                "."    "$(run_capture "$BIN" dirname a)"
expect_eq "dirname /a"               "/"    "$(run_capture "$BIN" dirname /a)"
expect_eq "dirname /"                "/"    "$(run_capture "$BIN" dirname /)"
expect_eq "dirname empty"            "."    "$(run_capture "$BIN" dirname "")"
expect_eq "dirname /a/b/"            "/a"   "$(run_capture "$BIN" dirname /a/b/)"

# --- dirname multiple operands (GNU) ---
out=$(run_capture "$BIN" dirname /usr/bin /var/log /home/x)
expected="/usr
/var
/home"
expect_eq "dirname multi" "$expected" "$out"

# --- dirname -z ---
out=$("$BIN" dirname -z /usr/bin/cp | od -An -c | head -1 | tr -s ' ')
expect_eq "dirname -z" " / u s r / b i n \\0" "$out"

# --- dirname errors ---
expect_exit "dirname no args"        2 "$BIN" dirname

# --- pipe-friendly composition ---
out=$(printf '%s\n' /a/b/c | "$BIN" basename - 2>/dev/null || true)
# `-` is treated as a literal path, not stdin; result is "-".
expect_eq "basename dash literal"    "-" "$(run_capture "$BIN" basename -)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
