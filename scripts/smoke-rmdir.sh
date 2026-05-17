#!/bin/sh
# smoke-rmdir.sh — behavioural test for `kriya rmdir`.
#
# Pure-function helpers for rmdir don't exist (its work is all
# syscalls); the entire behaviour lives at the process boundary.
# Mirrors scripts/smoke-mkdir.sh.

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

expect_gone() {
    if [ ! -e "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' still exists\n" "$1" "$2" >&2
    fi
}

expect_present() {
    if [ -e "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' missing\n" "$1" "$2" >&2
    fi
}

# --- happy path ---
mkdir empty1
expect_exit "rmdir empty"          0 "$BIN" rmdir empty1
expect_gone "empty1 removed"       empty1

mkdir -p tree/a/b/c
expect_exit "rmdir -p deep"        0 "$BIN" rmdir -p tree/a/b/c
expect_gone "tree fully removed"   tree

# Multiple operands all empty.
mkdir m1 m2
expect_exit "rmdir m1 m2"          0 "$BIN" rmdir m1 m2
expect_gone "m1 gone"              m1
expect_gone "m2 gone"              m2

# --- error paths ---
mkdir nonempty
touch nonempty/file
expect_exit "ENOTEMPTY"            1 "$BIN" rmdir nonempty
expect_present "nonempty kept"     nonempty
rm -rf nonempty

# Missing dir.
expect_exit "ENOENT"               1 "$BIN" rmdir nope
expect_exit "ENOENT under -p"      1 "$BIN" rmdir -p nope/deep

# rmdir on a regular file: ENOTDIR.
: > afile
expect_exit "ENOTDIR on file"      1 "$BIN" rmdir afile
expect_present "afile kept"        afile

# rmdir on / : kernel EBUSY (not the protected_paths[] check — that's
# ADR 0004 / rm only).
expect_exit "EBUSY on /"           1 "$BIN" rmdir /

# No operands → usage error (exit 2).
expect_exit "no operands"          2 "$BIN" rmdir

# --- -p cascade with sibling content ---
mkdir -p sibling/a sibling/b
# Without --ignore-fail-on-non-empty, the cascade fails at `sibling`
# because `b` is still there. The leaf `sibling/a` should be gone but
# `sibling/b` and `sibling` remain.
expect_exit "cascade halts"        1 "$BIN" rmdir -p sibling/a
expect_gone "sibling/a gone"       sibling/a
expect_present "sibling/b kept"    sibling/b
expect_present "sibling kept"      sibling
rm -rf sibling

# With --ignore-fail-on-non-empty, the leaf still goes, the cascade
# stops at the non-empty parent silently (exit 0).
mkdir -p sibling/a sibling/b
expect_exit "ignore non-empty"     0 "$BIN" rmdir -p --ignore-fail-on-non-empty sibling/a
expect_gone "sibling/a gone"       sibling/a
expect_present "sibling/b kept"    sibling/b
expect_present "sibling kept (non-empty)" sibling
rm -rf sibling

# --- verbose ---
mkdir -p v/a/b
out=$("$BIN" rmdir -v -p v/a/b 2>&1)
expected="kriya rmdir: removed directory 'v/a/b'
kriya rmdir: removed directory 'v/a'
kriya rmdir: removed directory 'v'"
expect_eq "verbose -p output" "$expected" "$out"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
