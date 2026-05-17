#!/bin/sh
# smoke-mv.sh — behavioural test for `kriya mv`.
#
# Covers same-filesystem rename, multi-into-dir, ADR-0003 hard rule
# #3 (refuse symlink-to-directory destination), self-move detection,
# -i / -n / -v / -f, dir rename. Cross-FS (EXDEV) is exercised when
# /tmp and /dev/shm are on different filesystems; skipped otherwise.

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

# --- basic rename ---
echo "alpha" > a
expect_exit "mv a b"                 0 "$BIN" mv a b
expect_absent "a gone"               a
expect_present "b present"           b

# --- overwrite default ---
echo "old" > old
echo "new" > new
expect_exit "mv overwrites by default" 0 "$BIN" mv new old
content=$(cat old)
expect_eq "old has new's content"    "new" "$content"
expect_absent "new gone after mv"    new

# --- -n no-clobber: silent skip, exit 0 ---
echo "keep" > keep
echo "trying" > trying
expect_exit "-n leaves dest"         0 "$BIN" mv -n trying keep
content=$(cat keep)
expect_eq "keep unchanged"           "keep" "$content"
# Source still exists since -n skipped.
expect_present "src kept by -n"      trying

# --- -i on non-tty is usage error (ADR 0002) ---
expect_exit "-i on pipe"             2 "$BIN" mv -i a b

# --- multi-into-dir ---
mkdir into
echo c1 > c1 && echo c2 > c2
expect_exit "mv c1 c2 into/"         0 "$BIN" mv c1 c2 into/
expect_present "into/c1"             into/c1
expect_present "into/c2"             into/c2
expect_absent "c1 moved away"        c1
expect_absent "c2 moved away"        c2

# Multi-source with non-dir final operand — usage error.
expect_exit "multi non-dir"          2 "$BIN" mv into/c1 into/c2 notadir

# --- directory rename (same-FS) ---
mkdir treedir
echo deep > treedir/deep
expect_exit "rename dir"             0 "$BIN" mv treedir renamed_tree
expect_absent "treedir gone"         treedir
expect_present "renamed_tree exists" renamed_tree
expect_present "deep moved with"     renamed_tree/deep

# --- ADR 0003 hard rule #3: refuse symlink-to-directory destination ---
mkdir realdir
ln -s realdir linkdir
echo z > z

# Single-pair shape.
expect_exit "refuse symlink-to-dir"  1 "$BIN" mv z linkdir
expect_present "z still around"      z
# Real dir contents weren't touched.
expect_absent "z not in realdir"     realdir/z

# Multi-into-dir shape (last operand is symlink-to-dir).
echo m1 > m1
expect_exit "refuse SLD multi"       1 "$BIN" mv m1 linkdir
expect_present "m1 untouched"        m1
expect_absent "m1 not in realdir"    realdir/m1

# --- self-move ---
echo "same" > self
expect_exit "self-move refused"      1 "$BIN" mv self self
expect_present "self still around"   self

# --- error paths ---
expect_exit "no operands"            2 "$BIN" mv
expect_exit "one operand"            2 "$BIN" mv only
expect_exit "missing source"         1 "$BIN" mv ghost dest

# --- verbose ---
echo "v1" > v_src
out=$("$BIN" mv -v v_src v_dst 2>&1)
expected="renamed 'v_src' -> 'v_dst'"
expect_eq "verbose output" "$expected" "$out"

# --- cross-FS (EXDEV) — only if /tmp and /dev/shm are different filesystems ---
TMP_DEV=$(stat -c %d /tmp 2>/dev/null || echo 0)
SHM_DEV=$(stat -c %d /dev/shm 2>/dev/null || echo 1)
if [ -d /dev/shm ] && [ "$TMP_DEV" != "$SHM_DEV" ]; then
    # File: copy + unlink should succeed and the bytes should match.
    XFS_SRC=$(mktemp -p /dev/shm kriya-mv-xfs.XXXXXX)
    XFS_DST="$WORK/xfs_landed"
    echo "cross-fs-content" > "$XFS_SRC"
    XFS_INODE_SRC=$(stat -c %i "$XFS_SRC")
    expect_exit "cross-FS regular file" 0 "$BIN" mv "$XFS_SRC" "$XFS_DST"
    expect_absent "src gone after xfs"  "$XFS_SRC"
    expect_present "dst arrived"        "$XFS_DST"
    content=$(cat "$XFS_DST")
    expect_eq "xfs content match"       "cross-fs-content" "$content"
    # The inode MUST differ — that's the proof we crossed filesystems.
    XFS_INODE_DST=$(stat -c %i "$XFS_DST")
    if [ "$XFS_INODE_SRC" != "$XFS_INODE_DST" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL xfs inode should differ" >&2; fi

    # Symlink: also copy + unlink semantics.
    XFS_LINK=$(mktemp -u -p /dev/shm kriya-mv-link.XXXXXX)
    ln -s /some/target "$XFS_LINK"
    XFS_LINK_DST="$WORK/link_landed"
    expect_exit "cross-FS symlink"       0 "$BIN" mv "$XFS_LINK" "$XFS_LINK_DST"
    expect_absent "link src gone"        "$XFS_LINK"
    if [ -L "$XFS_LINK_DST" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL xfs symlink should land as symlink" >&2; fi
    target=$(readlink "$XFS_LINK_DST")
    expect_eq "link target preserved"    "/some/target" "$target"

    # Cross-FS directory mv: not supported until rm tree-walk ships.
    XFS_DIR=$(mktemp -d -p /dev/shm kriya-mv-dir.XXXXXX)
    echo "x" > "$XFS_DIR/inside"
    expect_exit "cross-FS dir errors"   1 "$BIN" mv "$XFS_DIR" "$WORK/dir_landed"
    # The src directory must still exist (we failed before unlinking).
    expect_present "xfs src dir intact" "$XFS_DIR"
    rm -rf "$XFS_DIR"
else
    echo "(skipping cross-FS tests — /tmp and /dev/shm on same fs or /dev/shm missing)"
fi

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
