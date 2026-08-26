#!/bin/sh
# smoke-echo.sh — behavioural test for `kriya echo`.
#
# Compares BYTES against GNU `/usr/bin/echo`, not `$(...)` output. That is not
# fussiness: command substitution strips trailing newlines, and the trailing
# newline is precisely what `-n` and `\c` exist to remove — so a `$(...)`
# comparison passes whether or not either flag works at all.
#
# ⛔ The oracle is `/usr/bin/echo`, never the shell builtin. `sh`'s builtin is a
# different `echo` with different rules (dash interprets escapes with no `-e`),
# and ADR 0011 is explicit that kriya matches the BINARY.
#
# ⛔ POSIXLY_CORRECT is deliberately NOT exercised as a parity case. GNU flips to
# XSI under it — escapes always on, `-e` demoted to data — and ADR 0011 declines
# that flip on purpose. The test below asserts kriya's chosen behaviour instead.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"
GNU=/usr/bin/echo

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

# Byte-exact parity against GNU for one argument vector.
#
# ⛔ THE ORACLE RUNS WITH `POSIXLY_CORRECT` UNSET, and that is not tidiness. GNU
# `echo` flips to XSI under it — escapes always interpreted, `-e` demoted to
# literal data — so on a host that exports it EVERY case below diverges at once,
# while kriya is behaving exactly as ADR 0011 says it should. Caught by the
# hostile-environment matrix run, which turned 129 passes into 99 failures.
#
# ⚠ Third time a GNU oracle has been environment-controlled where kriya is not:
# `du` and `df` took the same treatment for `BLOCK_SIZE`/`POSIXLY_CORRECT` at
# 1.3.5. The rule that generalises: if kriya ignores a variable by design, the
# oracle must ignore it too, or the test measures the environment.
same() {
    g=$(unset POSIXLY_CORRECT; "$GNU" "$@" | od -An -c)
    k=$("$BIN" echo "$@" | od -An -c)
    expect_eq "echo $*" "$g" "$k"
}

# --- the escape table, with and without -e ---
for s in '\\' '\a' '\b' '\e' '\f' '\n' '\r' '\t' '\v' \
         '\0' '\1' '\01' '\101' '\0101' '\10' '\777' '\8' '\9' \
         '\x41' '\x4' '\xff' '\xZ' '\x' '\z' '\q' '\"' "\\'" \
         'plain' 'a\tb\nc' 'trailing\'; do
    same -e "$s"
    same "$s"
    same -E "$s"
done

# --- \c cancels EVERYTHING that follows, not just this operand ---
same -e 'A\cB'
same -e 'A\cB' SECOND THIRD
same -e '\c'
same -e x '\cy' z
same -en 'A\cB'

# --- option clusters: all-or-nothing, last -e/-E wins ---
for o in -n -e -E -ne -en -eE -Ee -nE -neE - -- -x -ex -ne5 ''; do
    same "$o" tail
done
same -n -e '\t'
same -e -n '\t'
same -E -e '\t'
same -e -E '\t'

# --- operands: spacing, empties, and `-` after the first operand is DATA ---
same
same ''
same '' ''
same a b c
same -n
same -e
same x -n
same x -e '\t'
same -e x -E '\t'

# --- ADR 0011: POSIXLY_CORRECT does NOT flip kriya to XSI ---
#
# GNU under POSIXLY_CORRECT emits a real tab here and prints `-e` as data.
# kriya keeps the command line as the only input to its behaviour.
# ⚠ The control side explicitly UNSETS the variable rather than trusting the
# ambient environment — on a host that already exports it, comparing kriya to
# kriya would be trivially true and would assert nothing at all.
out=$(POSIXLY_CORRECT=1 "$BIN" echo 'a\tb' | od -An -c)
expect_eq "POSIXLY_CORRECT leaves escapes off" \
    "$(unset POSIXLY_CORRECT; "$BIN" echo 'a\tb' | od -An -c)" "$out"
out=$(POSIXLY_CORRECT=1 "$BIN" echo -e 'a\tb' | od -An -c)
expect_eq "POSIXLY_CORRECT leaves -e an option" \
    "$(unset POSIXLY_CORRECT; "$BIN" echo -e 'a\tb' | od -An -c)" "$out"
# ⭐ And the assertion that actually bites: under the variable, kriya must still
# print a LITERAL backslash-t, which is where GNU would emit a real tab.
expect_eq "POSIXLY_CORRECT: escapes stay literal" \
    "$(printf 'a\\tb\n' | od -An -c)" \
    "$(POSIXLY_CORRECT=1 "$BIN" echo 'a\tb' | od -An -c)"

# --- exit status is always 0, `\c` included ---
expect_exit() {
    name=$1
    expected=$2
    shift 2
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}
expect_exit "plain echo"   0 "$BIN" echo hi
expect_exit "echo -e"      0 "$BIN" echo -e 'a\tb'
expect_exit "echo \\c"     0 "$BIN" echo -e 'a\cb'
expect_exit "echo -x"      0 "$BIN" echo -x

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
