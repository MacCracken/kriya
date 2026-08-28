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
    # ⛔ stdin FROM /dev/null, not inherited. Without this the three `-i on
    # pipe` assertions below tested whatever stdin the SUITE was launched
    # with: run from an interactive terminal, `-i` sees a tty, PROMPTS, and
    # hangs forever — the worst failure shape in CI, because it burns the
    # whole job timeout instead of failing. Verified by running this script
    # under a pty: it blocked until killed.
    "$@" </dev/null >/dev/null 2>&1 || rc=$?
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
# ⚠ Compare the device of $WORK, not of /tmp. The cross-filesystem move under
# test is /dev/shm -> $WORK, and $WORK comes from `mktemp -d`, which honours
# $TMPDIR — so on a host whose TMPDIR is not on /tmp's filesystem this guard
# was answering a question about a pair the test never touches.
TMP_DEV=$(stat -c %d "$WORK" 2>/dev/null || echo 0)
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

    # Cross-FS directory mv: cp -R + rm -r round trip.
    XFS_DIR=$(mktemp -d -p /dev/shm kriya-mv-dir.XXXXXX)
    echo "x" > "$XFS_DIR/inside"
    mkdir "$XFS_DIR/sub"
    echo "deep" > "$XFS_DIR/sub/nested"
    ln -s /etc/hostname "$XFS_DIR/sub/link"
    chmod 0750 "$XFS_DIR/sub"
    SRC_SUB_MODE=$(stat -c %a "$XFS_DIR/sub")
    XFS_DIR_DST="$WORK/dir_landed"
    expect_exit "cross-FS dir succeeds"  0 "$BIN" mv "$XFS_DIR" "$XFS_DIR_DST"
    # The src directory must be gone (rm -r ran after cp -R).
    expect_absent "xfs src dir gone"     "$XFS_DIR"
    # The destination tree mirrors the source — files, nested dir, symlink.
    expect_present "xfs dst dir present" "$XFS_DIR_DST"
    expect_eq "xfs dst file content"     "x" "$(cat "$XFS_DIR_DST/inside")"
    expect_eq "xfs dst nested content"   "deep" "$(cat "$XFS_DIR_DST/sub/nested")"
    if [ -L "$XFS_DIR_DST/sub/link" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL xfs symlink preserved as link" >&2; fi
    target=$(readlink "$XFS_DIR_DST/sub/link")
    expect_eq "xfs dst link target"      "/etc/hostname" "$target"
    # -p semantic: subdir mode preserved through cp -R.
    sub_mode=$(stat -c %a "$XFS_DIR_DST/sub")
    # ⚠ Compare against the SOURCE mode captured before the move, not a literal.
    # The literal duplicated the fixture: change the chmod above and this
    # silently starts asserting the old value against the new one.
    expect_eq "xfs dst subdir mode preserved" "$SRC_SUB_MODE" "$sub_mode"
    # The inode of the destination must differ from anything in /dev/shm —
    # proof we crossed filesystems. (We can only check that dst exists on
    # the same FS as $WORK, which is on /tmp; the inode-differ check on
    # the regular-file path above already proves the EXDEV path is taken.)

    # Failed cross-FS dir mv: existing non-dir at destination must NOT clobber
    # the source. cp -R into a file destination errors; we then roll back.
    XFS_DIR2=$(mktemp -d -p /dev/shm kriya-mv-dir2.XXXXXX)
    echo "x" > "$XFS_DIR2/inside"
    BLOCKER="$WORK/dir_blocker"
    echo "blocker" > "$BLOCKER"
    expect_exit "cross-FS dir onto file" 1 "$BIN" mv "$XFS_DIR2" "$BLOCKER"
    # Source dir must remain (we failed before rm -r ran).
    expect_present "xfs src after fail"  "$XFS_DIR2"
    rm -rf "$XFS_DIR2"
else
    echo "(skipping cross-FS tests — /tmp and /dev/shm on same fs or /dev/shm missing)"
fi

# --- ADR 0009: a completed copy is never rolled back --------------------
# ⛔ THIS WAS TOTAL DATA LOSS. Cross-FS `mv` is copy-then-remove, and the removal
# is a RECURSIVE walk that can PARTIALLY succeed — drain most of a tree and then
# fail on one entry. The old code rolled the destination back on that failure,
# deleting the only complete copy of everything already removed. Measured with an
# unwritable source PARENT (so the final rmdir fails after the contents are
# gone): source emptied, destination deleted, both files gone from the filesystem
# entirely. GNU keeps the destination; ADR 0009 adopts that.
# ⛔ ROOT BYPASSES DAC, SO THIS BLOCK CANNOT WORK AS ROOT. It manufactures its
# failure with an unwritable PARENT directory, and CAP_DAC_OVERRIDE makes uid 0
# succeed regardless — the final rmdir would work, no failure would occur, and
# the assertion would report kriya broken when it is not. ⚠ GitHub's hosted
# runners are non-root so this is latent there; "latent until someone runs CI
# in a container" is exactly how the argv[0] bug survived two releases.
if [ "$(id -u)" = "0" ]; then
    echo "skip: running as root — an unwritable parent cannot deny rmdir"
elif [ -d /dev/shm ] && [ "$TMP_DEV" != "$SHM_DEV" ]; then
    RB=/dev/shm/kriya-mv-adr9.$$
    rm -rf "$RB"; mkdir -p "$RB/ro/tree/sub"
    echo ONLY-COPY-A > "$RB/ro/tree/a.txt"
    echo ONLY-COPY-B > "$RB/ro/tree/sub/b.txt"
    chmod 555 "$RB/ro"                       # parent unwritable -> final rmdir fails
    RBDST="$WORK/adr9_landed"
    rc=0
    "$BIN" mv "$RB/ro/tree" "$RBDST" >/dev/null 2>&1 || rc=$?
    expect_eq "ADR 0009: reports failure"       "1"   "$rc"
    expect_eq "ADR 0009: destination kept"      "yes" "$([ -f "$RBDST/a.txt" ] && echo yes || echo no)"
    expect_eq "ADR 0009: nested file kept too"  "yes" "$([ -f "$RBDST/sub/b.txt" ] && echo yes || echo no)"
    expect_eq "ADR 0009: content intact"        "ONLY-COPY-A" "$(cat "$RBDST/a.txt" 2>/dev/null)"
    chmod 755 "$RB/ro" 2>/dev/null || true
    rm -rf "$RB"

    # Same rule for a regular file: once the copy is durable, it stays.
    RF=/dev/shm/kriya-mv-adr9f.$$
    rm -rf "$RF"; mkdir -p "$RF/ro"; echo PAYLOAD > "$RF/ro/f"; chmod 555 "$RF/ro"
    rc=0
    "$BIN" mv "$RF/ro/f" "$WORK/adr9_file" >/dev/null 2>&1 || rc=$?
    expect_eq "ADR 0009 (file): reports failure" "1"   "$rc"
    expect_eq "ADR 0009 (file): source intact"   "yes" "$([ -f "$RF/ro/f" ] && echo yes || echo no)"
    expect_eq "ADR 0009 (file): dest kept"       "yes" "$([ -f "$WORK/adr9_file" ] && echo yes || echo no)"
    chmod 755 "$RF/ro" 2>/dev/null || true
    rm -rf "$RF"
else
    echo "skip: /tmp and /dev/shm share a filesystem — ADR 0009 cases not exercised"
fi

# --- 1.6.5: the backup trio, same helper as cp (ADR 0017) -----------------
# ⚠ THE SAME MATRIX, DELIBERATELY RE-ASSERTED HERE. `src/lib/backup.cyr` serves
# all three utilities, and a hook wired into only one of them is exactly the
# failure this catches — `cp` needed TWO hooks because it has two copy paths,
# and neither of them is mv's.
BK="env -u VERSION_CONTROL -u SIMPLE_BACKUP_SUFFIX"
ubk_mk() { rm -rf ubk; mkdir ubk; echo NEW > ubk/src; echo OLD > ubk/dst; for _f in "$@"; do echo B > "ubk/$_f"; done; }
ubk_show() { ls ubk | tr '\n' ' '; }
ubk() {   # ubk <name> <expected> <flag...>
    _n=$1; _want=$2; shift 2
    ubk_mk
    ( cd ubk && $BK "$BIN" mv "$@" src dst 2>/dev/null ) || true
    expect_eq "$_n" "$_want" "$(ubk_show)"
}
ubk "-b makes a simple backup"     "dst dst~ "     -b
ubk "--backup=numbered"            "dst dst.~1~ "   --backup=numbered
ubk "--backup=simple"              "dst dst~ "     --backup=simple
ubk "-S .bak"                      "dst dst.bak "   -S .bak
ubk_mk "dst.~1~"
( cd ubk && $BK "$BIN" mv -b src dst 2>/dev/null ) || true
expect_eq "existing goes numbered when one exists" "dst dst.~1~ dst.~2~ " "$(ubk_show)"
# ⭐ The variables reach mv too — the helper reads them, not the utility.
ubk_mk; ( cd ubk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=numbered "$BIN" mv -b src dst 2>/dev/null ) || true
expect_eq "\$VERSION_CONTROL reaches mv"    "dst dst.~1~ " "$(ubk_show)"
# ⛔ ...and is INERT without the flag, which is the ADR 0017 property.
ubk_mk; ( cd ubk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=numbered "$BIN" mv -f src dst 2>/dev/null ) || true
expect_eq "...and makes no backup on its own" "dst " "$(ubk_show)"
expect_exit "a bad control is a usage error"  2 "$BIN" mv --backup=bogus src dst

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
