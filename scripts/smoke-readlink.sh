#!/bin/sh
# smoke-readlink.sh — behavioural test for `kriya readlink`.
#
# Two surfaces:
#   - POSIX raw read-link (no flag): print the symlink's target text.
#     Error if the operand is not a symlink (EINVAL).
#   - Canonicalize modes (-f / -e / -m): delegate to `fs_realpath`,
#     same helper that powers `realpath`. The realpath smoke covers
#     the canonicalization algorithm deeply; here we just verify
#     readlink's flag-to-mode mapping and display modifiers.

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
WORK_REAL=$(readlink -f "$WORK")

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

# --- fixture ---
mkdir -p a/b
echo "x" > a/b/file
ln -s a/b/file linkfile
ln -s linkfile chain
ln -s /tmp     abs_link
ln -s ghost    dangling

# --- POSIX raw read-link ---
out=$("$BIN" readlink linkfile)
expect_eq "raw linkfile"          "a/b/file" "$out"

out=$("$BIN" readlink chain)
expect_eq "raw chain"             "linkfile" "$out"

out=$("$BIN" readlink abs_link)
expect_eq "raw abs_link"          "/tmp" "$out"

out=$("$BIN" readlink dangling)
expect_eq "raw dangling"          "ghost" "$out"

# POSIX on a non-symlink: EINVAL (exit 1).
expect_exit "non-symlink"         1 "$BIN" readlink a/b/file

# --- -f (REQUIRE_PARENT): last component may be missing ---
out=$("$BIN" readlink -f linkfile)
expect_eq "-f linkfile"           "$WORK_REAL/a/b/file" "$out"

out=$("$BIN" readlink -f chain)
expect_eq "-f chain (resolves)"   "$WORK_REAL/a/b/file" "$out"

# -f tolerates missing last component (parent exists).
out=$("$BIN" readlink -f a/b/missing)
expect_eq "-f missing last"       "$WORK_REAL/a/b/missing" "$out"

# -f rejects missing parent.
expect_exit "-f missing parent"   1 "$BIN" readlink -f a/b/nope/deep

# --- -e (REQUIRE_ALL) ---
out=$("$BIN" readlink -e a/b/file)
expect_eq "-e existing"           "$WORK_REAL/a/b/file" "$out"

expect_exit "-e missing"          1 "$BIN" readlink -e a/b/nope
expect_exit "-e missing parent"   1 "$BIN" readlink -e a/b/nope/deep

# --- -m (ALLOW_MISSING) ---
out=$("$BIN" readlink -m a/b/nope/totally/missing)
expect_eq "-m deep missing"       "$WORK_REAL/a/b/nope/totally/missing" "$out"

out=$("$BIN" readlink -m linkfile)
expect_eq "-m on symlink"         "$WORK_REAL/a/b/file" "$out"

# --- -q silences error stderr ---
err=$("$BIN" readlink -q -e a/b/nope 2>&1 >/dev/null || true)
expect_eq "-q silences -e"        "" "$err"

err=$("$BIN" readlink -q a/b/file 2>&1 >/dev/null || true)
expect_eq "-q silences POSIX"     "" "$err"

# --- -n (no-newline) on final operand only ---
# Single operand: no trailing newline at all.
nl=$("$BIN" readlink -n linkfile | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "-n single 0 newlines"  "0" "$nl"

# Multi operands: trailing newlines on all but the last.
nl=$("$BIN" readlink -n linkfile chain abs_link | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "-n multi 2 newlines"   "2" "$nl"

# --- -z NUL terminator (overrides -n) ---
nul=$("$BIN" readlink -z linkfile chain | tr -dc '\0' | wc -c | tr -d ' ')
expect_eq "-z multi 2 NULs"       "2" "$nul"

# -z + -n: -z wins; every operand gets a NUL.
nul=$("$BIN" readlink -z -n linkfile chain | tr -dc '\0' | wc -c | tr -d ' ')
expect_eq "-z -n multi 2 NULs"    "2" "$nul"

# --- multi-operand partial failure ---
rc=0
out=$("$BIN" readlink -e a/b/file a/b/nope linkfile 2>/dev/null) || rc=$?
expect_eq "multi partial rc"      "1" "$rc"
expected="$WORK_REAL/a/b/file
$WORK_REAL/a/b/file"
expect_eq "multi partial stdout"  "$expected" "$out"

# --- canonicalize precedence: -m > -e > -f ---
out=$("$BIN" readlink -f -e -m a/b/nope/deeper)
# -m wins → allows missing → returns the canonical path
expect_eq "-f -e -m: m wins"      "$WORK_REAL/a/b/nope/deeper" "$out"

# --- no operands ---
expect_exit "no operands"         2 "$BIN" readlink

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
