#!/bin/sh
# smoke-du.sh — behavioural test for `kriya du`.
#
# Compares output cell-by-cell against GNU `du` for the shipped flag
# matrix. Tree built fresh under WORK with deterministic file sizes
# (small 5-byte text + 4 KiB binary + nested-deep + side-branch).

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

# Build a deterministic tree.
mkdir -p a/b/c d
echo "small" > a/file1
head -c 4096 /dev/urandom > a/big
echo "deep" > a/b/c/deeper
echo "side" > d/file
head -c 5242880 /dev/urandom > big5m

PASS=0
FAIL=0

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nexpected:\n%s\ngot:\n%s\n" "$1" "$2" "$3" >&2
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

# `du`'s subtree-traversal order isn't ABI-stable across filesystems,
# so we sort both outputs by path before comparing.
sorted_check() {
    name=$1
    shift
    k=$("$BIN" du "$@" | sort -k2)
    # ⛔ GNU du's DEFAULT BLOCK SIZE IS ENVIRONMENT-CONTROLLED and kriya's is not.
    # Measured on a 5-byte file: plain `du` prints 4, `POSIXLY_CORRECT=1 du`
    # prints 8 (512-byte units), `BLOCK_SIZE=1 du` prints 4096. kriya prints 4
    # in all three. So on any host exporting one of these — and POSIXLY_CORRECT
    # is not exotic — every one of the ~30 cell-by-cell comparisons below fails
    # at once, blaming kriya for the shell's environment.
    # ⚠ Pin the oracle's environment rather than kriya's: the comparison is
    # about du's ARITHMETIC, not about which units the caller asked for.
    g=$(env -u POSIXLY_CORRECT -u DU_BLOCK_SIZE -u BLOCK_SIZE du "$@" | sort -k2)
    expect_eq "$name" "$g" "$k"
}

# --- Default: per-dir entries only, 1024-byte blocks ---
sorted_check "default ."                .
sorted_check "default a"                a
sorted_check "default a b"              a d
sorted_check "default single file"      a/file1

# --- -s summary ---
sorted_check "du -s ."                  -s .
sorted_check "du -s a d"                -s a d
sorted_check "du -s file"               -s a/file1

# --- -a all entries ---
sorted_check "du -a"                    -a .
sorted_check "du -a -s"                 -a -s .
sorted_check "du -a a"                  -a a

# --- -h human-readable ---
sorted_check "du -h"                    -h .
sorted_check "du -h big5m"              -h big5m
sorted_check "du -h a/big"              -h a/big
sorted_check "du -ah"                   -ah .

# --- -b apparent size ---
sorted_check "du -b a/file1"            -b a/file1
sorted_check "du -b a"                  -b a

# --- -c grand total ---
sorted_check "du -c a d"                -c a d
sorted_check "du -sc a d"               -sc a d
sorted_check "du -c file"               -c a/file1

# --- -d max-depth ---
sorted_check "du -d 0"                  -d 0 .
sorted_check "du -d 1"                  -d 1 .
sorted_check "du -d 2"                  -d 2 .

# --- -S separate-dirs ---
sorted_check "du -S"                    -S .

# --- Symlink policy: -P default (no follow) vs -L follow ---
ln -s a alink
mkdir -p targetdir
echo "x" > targetdir/file
ln -s targetdir lnkdir
# Default -P treats lnkdir as a symlink (size of link text).
sorted_check "du default symlink"       lnkdir
sorted_check "du -L symlink follow"     -L lnkdir

# --- Long-form options ---
sorted_check "--summarize"              --summarize a
sorted_check "--all"                    --all a
sorted_check "--total"                  --total a d
sorted_check "--bytes"                  --bytes a/file1
sorted_check "--human-readable"         --human-readable a
sorted_check "--max-depth=1"            --max-depth=1 .

# --- Exit codes ---
expect_exit "du missing file"       1 "$BIN" du nope
expect_exit "du unknown flag"       2 "$BIN" du -Z .
expect_exit "du unknown long"       2 "$BIN" du --bogus .
expect_exit "du -d no arg"          2 "$BIN" du -d
expect_exit "du --max-depth=bad"    2 "$BIN" du --max-depth=abc .

# --- Default-to-`.` when no operand ---
k=$("$BIN" du | sort -k2)
# ⚠ Same environment pin as `sorted_check` — this one bypassed the helper.
g=$(env -u POSIXLY_CORRECT -u DU_BLOCK_SIZE -u BLOCK_SIZE du | sort -k2)
expect_eq "du with no operand" "$g" "$k"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
