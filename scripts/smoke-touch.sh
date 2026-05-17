#!/bin/sh
# smoke-touch.sh — behavioural test for `kriya touch`.
#
# Covers create, update-existing, -a / -m selectivity, -c (no-create)
# semantics, multi-operand exit codes. Defers -r / -t / -d testing to
# the milestone where they ship (chrono helper dependency).

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

expect_present() {
    if [ -e "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' missing\n" "$1" "$2" >&2
    fi
}

expect_absent() {
    if [ ! -e "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' should not exist\n" "$1" "$2" >&2
    fi
}

# --- create ---
expect_exit "touch new"             0 "$BIN" touch new1
expect_present "new1 created"       new1

# Multi-operand create.
expect_exit "touch a b c"           0 "$BIN" touch a b c
expect_present "a"                  a
expect_present "b"                  b
expect_present "c"                  c

# --- update existing (both atime + mtime by default) ---
# Set a known-old time so we can observe the bump.
touch -t 202001010000.00 oldfile
OLD_A=$(stat -c %X oldfile)
OLD_M=$(stat -c %Y oldfile)
expect_exit "touch oldfile"         0 "$BIN" touch oldfile
NEW_A=$(stat -c %X oldfile)
NEW_M=$(stat -c %Y oldfile)
if [ "$NEW_A" -gt "$OLD_A" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL atime did not advance ($OLD_A -> $NEW_A)" >&2; fi
if [ "$NEW_M" -gt "$OLD_M" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL mtime did not advance ($OLD_M -> $NEW_M)" >&2; fi

# --- -a updates atime only ---
touch -t 202001010000.00 afile
OA=$(stat -c %X afile); OM=$(stat -c %Y afile)
expect_exit "touch -a"              0 "$BIN" touch -a afile
NA=$(stat -c %X afile); NM=$(stat -c %Y afile)
if [ "$NA" -gt "$OA" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -a did not advance atime" >&2; fi
expect_eq "-a left mtime alone"     "$OM" "$NM"

# --- -m updates mtime only ---
touch -t 202001010000.00 mfile
OA=$(stat -c %X mfile); OM=$(stat -c %Y mfile)
expect_exit "touch -m"              0 "$BIN" touch -m mfile
NA=$(stat -c %X mfile); NM=$(stat -c %Y mfile)
expect_eq "-m left atime alone"     "$OA" "$NA"
if [ "$NM" -gt "$OM" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -m did not advance mtime" >&2; fi

# --- -a -m together updates both (same as default) ---
touch -t 202001010000.00 bothfile
OA=$(stat -c %X bothfile); OM=$(stat -c %Y bothfile)
expect_exit "touch -a -m"           0 "$BIN" touch -a -m bothfile
NA=$(stat -c %X bothfile); NM=$(stat -c %Y bothfile)
if [ "$NA" -gt "$OA" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -a -m did not advance atime" >&2; fi
if [ "$NM" -gt "$OM" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -a -m did not advance mtime" >&2; fi

# --- -c (--no-create) ---
# Missing file: exit 1 (POSIX says still an error), file stays absent.
expect_exit "touch -c missing"      1 "$BIN" touch -c gone
expect_absent "gone not created"    gone

# Existing file: -c works normally, bumps times.
touch -t 202001010000.00 keeper
OM=$(stat -c %Y keeper)
expect_exit "touch -c existing"     0 "$BIN" touch -c keeper
NM=$(stat -c %Y keeper)
if [ "$NM" -gt "$OM" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -c on existing did not advance mtime" >&2; fi

# --- errors ---
expect_exit "no operands"           2 "$BIN" touch

# Touch in a non-existent directory fails (ENOENT).
expect_exit "missing parent dir"    1 "$BIN" touch nope/here

# Partial failure: one good, one bad — exit 1, the good one is still
# created. Use a missing-parent case for the bad operand so the
# failure is isolated to that operand (using -c would suppress
# creation invocation-wide).
expect_exit "partial fail"          1 "$BIN" touch nope/parent/bad good1
expect_present "good1 created"      good1

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
