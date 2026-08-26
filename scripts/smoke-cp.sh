#!/bin/sh
# smoke-cp.sh — behavioural test for `kriya cp` (non-recursive ship).
#
# Covers single-file copy, multi-into-dir, -f / -i / -p / -v, self-copy
# refusal, directory-source-without-R error. Recursive cp + the ADR
# 0003 symlink-policy matrix lands in a separate commit on top of
# src/lib/fs.cyr.

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
    # ⛔ stdin FROM /dev/null, not inherited. Without this the three `-i on
    # pipe` assertions below tested whatever stdin the SUITE was launched
    # with: run from an interactive terminal, `-i` sees a tty, PROMPTS, and
    # hangs forever — the worst failure shape in CI, because it burns the
    # whole job timeout instead of failing. Verified by running this script
    # under a pty: it blocked until killed.
    "$@" </dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}

expect_file_match() {
    if cmp -s "$2" "$3"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' and '%s' differ\n" "$1" "$2" "$3" >&2
    fi
}

# --- happy path ---
echo "hello world" > src.txt
expect_exit "cp basic"               0 "$BIN" cp src.txt dst.txt
expect_file_match "byte-identical"   src.txt dst.txt

# Larger file to exercise the multi-block loop (>64KiB).
dd if=/dev/urandom of=big.bin bs=1024 count=200 status=none
expect_exit "cp 200KB"               0 "$BIN" cp big.bin big.copy
expect_file_match "200KB match"      big.bin big.copy

# --- existing dest gating ---
expect_exit "exists without -f"      1 "$BIN" cp src.txt dst.txt
expect_exit "exists with -f"         0 "$BIN" cp -f src.txt dst.txt
expect_file_match "still match"      src.txt dst.txt

# -i on non-tty is exit 2 (usage error per ADR 0002).
expect_exit "-i on pipe"             2 "$BIN" cp -i src.txt dst.txt

# --- multi-into-dir ---
mkdir into
echo a > a.txt && echo b > b.txt
expect_exit "cp a b into/"           0 "$BIN" cp a.txt b.txt into/
expect_file_match "into/a.txt"       a.txt into/a.txt
expect_file_match "into/b.txt"       b.txt into/b.txt

# Multi-source with non-dir final operand — usage error.
expect_exit "multi non-dir"          2 "$BIN" cp a.txt b.txt notadir

# --- -p preserve mode + times ---
# Order matters: write content first, then chmod/touch -t. A trailing
# `>> file` would re-bump mtime to "now".
echo "stamped" > oldtime.txt
chmod 0640 oldtime.txt
touch -t 202001010000.00 oldtime.txt
SRC_M=$(stat -c %a oldtime.txt)
SRC_T=$(stat -c %Y oldtime.txt)
expect_exit "cp -p"                  0 "$BIN" cp -p oldtime.txt oldtime.copy
DST_M=$(stat -c %a oldtime.copy)
DST_T=$(stat -c %Y oldtime.copy)
expect_eq "preserved mode"           "$SRC_M" "$DST_M"
expect_eq "preserved mtime"          "$SRC_T" "$DST_T"

# Without -p, mtime should be "now" — much greater than the 2020
# timestamp the source carries.
expect_exit "cp without -p"          0 "$BIN" cp -f oldtime.txt fresh.copy
FRESH_T=$(stat -c %Y fresh.copy)
if [ "$FRESH_T" -gt "$SRC_T" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL non-p mtime should be current ($FRESH_T vs $SRC_T)" >&2; fi

# --- -v verbose ---
out=$("$BIN" cp -v -f src.txt v.txt 2>&1)
expected="'src.txt' -> 'v.txt'"
expect_eq "verbose output" "$expected" "$out"

# --- errors ---
expect_exit "missing source"         1 "$BIN" cp gone there
expect_exit "no operands"            2 "$BIN" cp
expect_exit "one operand"            2 "$BIN" cp onlyone

# Directory source without -R: exit 1, "is a directory".
mkdir somedir
expect_exit "dir source w/o -R"      1 "$BIN" cp somedir other

# Self-copy refused.
expect_exit "self-copy"              1 "$BIN" cp src.txt src.txt

# Partial failure: one bad + one good — exit 1, good copy still made.
expect_exit "partial fail"           1 "$BIN" cp missing.src good.src into/
echo "good_content" > good.src
expect_exit "partial fail (after)"   1 "$BIN" cp missing.src good.src into/
expect_file_match "into/good.src"    good.src into/good.src

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
