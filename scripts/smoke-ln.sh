#!/bin/sh
# smoke-ln.sh — behavioural test for `kriya ln`.
#
# Covers symbolic + hard link creation, -f overwrite, -n no-dereference
# (the ln -s -f -n deploy-retarget idiom in ADR 0003), -P hard-link
# the symlink itself, multi-into-dir, and the verbose form.

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

expect_symlink() {
    if [ -L "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' is not a symlink\n" "$1" "$2" >&2
    fi
}

expect_target() {
    actual=$(readlink "$2")
    expect_eq "$1" "$3" "$actual"
}

# --- symbolic links ---
echo "src content" > src.txt

expect_exit "ln -s create"           0 "$BIN" ln -s src.txt link1
expect_symlink "link1 is a symlink"  link1
expect_target "link1 -> src.txt"     link1 src.txt

# Existing dest without -f — error.
expect_exit "ln -s clobber w/o -f"   1 "$BIN" ln -s src.txt link1

# Existing dest with -f — overwrites.
expect_exit "ln -s -f overwrite"     0 "$BIN" ln -s -f src.txt link1
expect_symlink "link1 still symlink" link1

# --- single-arg form (link name = basename of target) ---
mkdir other && echo "data" > other/payload
expect_exit "ln -s single-arg"       0 "$BIN" ln -s other/payload
expect_symlink "payload created"     payload
expect_target "payload -> other/payload"  payload other/payload

# --- hard links ---
expect_exit "ln (hard)"              0 "$BIN" ln src.txt hardlink1
src_inode=$(stat -c %i src.txt)
hard_inode=$(stat -c %i hardlink1)
expect_eq "hard inode matches src"   "$src_inode" "$hard_inode"

# Hard link to a symlink without -P: follows the symlink — hardlink
# points at src.txt's inode, NOT link1's symlink inode.
expect_exit "ln (hard, follow)"      0 "$BIN" ln link1 hardThroughLink
through_inode=$(stat -c %i hardThroughLink)
expect_eq "follow: same inode as src"  "$src_inode" "$through_inode"

# Hard link to a symlink WITH -P: link the symlink itself.
link1_inode=$(stat -c %i link1)
expect_exit "ln -P (no follow)"      0 "$BIN" ln -P link1 hardOfLink
of_link_inode=$(stat -c %i hardOfLink)
expect_eq "-P: hardlink to symlink"  "$link1_inode" "$of_link_inode"

# --- ADR 0003 deploy-retarget idiom: ln -s -f -n NEW LINK ---
mkdir current.v1 current.v2
expect_exit "first deploy"           0 "$BIN" ln -s current.v1 current
expect_target "current -> v1"        current current.v1

# Without -n, ln -s -f NEW LINK would create current/current.v2 inside
# the symlinked dir. With -n, it replaces the symlink.
expect_exit "retarget with -n"       0 "$BIN" ln -s -f -n current.v2 current
expect_target "current -> v2"        current current.v2
expect_symlink "current still link"  current
# current.v1 must still exist (we didn't traverse into it).
if [ -d current.v1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL current.v1 vanished" >&2; fi

# --- multi-source-into-dir ---
mkdir bindir
echo a > a.bin && echo b > b.bin
expect_exit "ln -s a b bindir/"      0 "$BIN" ln -s ../a.bin ../b.bin bindir/
expect_symlink "bindir/a.bin"        bindir/a.bin
expect_symlink "bindir/b.bin"        bindir/b.bin

# Multi-source with non-directory final arg — usage error.
expect_exit "multi non-dir final"    2 "$BIN" ln -s ../a.bin ../b.bin notadir

# --- errors ---
expect_exit "no operands"            2 "$BIN" ln

# Hard link to a non-existent target without -s: ENOENT (kernel-level).
expect_exit "hard to missing"        1 "$BIN" ln nope deadhard

# Symbolic link to a non-existent target is FINE (POSIX) — the target
# is just text.
expect_exit "symlink to missing"     0 "$BIN" ln -s nope dangling
expect_symlink "dangling exists"     dangling

# --- verbose ---
out=$("$BIN" ln -s -v src.txt vlink 2>&1)
expected="kriya ln: 'vlink' -> 'src.txt'"
expect_eq "verbose -s output" "$expected" "$out"

# --- -f must not destroy the destination on failure (v1.1.11) -----------
# ⛔ `-f` used to unlink the destination and THEN attempt the link, so any
# failure afterwards left nothing behind. Measured: `ln -f /nonexistent-src
# keep.txt` reported "no such file or directory" and DELETED keep.txt. Now the
# link is made under a temp name in the same directory and renamed over the
# target, so the destination is only replaced once a replacement exists.
#
# ⚠ The obvious shortcut — unlink only on EEXIST, since that "proves" the source
# is linkable — is NOT enough: the kernel reports EEXIST before EXDEV, so a
# cross-device link onto an existing path still answered 17 and still deleted.
mkdir -p ffail
echo IMPORTANT > ffail/keep.txt
echo SRC       > ffail/src.txt

expect_exit "ln -f missing src fails"    1 "$BIN" ln -f /nonexistent-src ffail/keep.txt
expect_eq   "destination survives"       "IMPORTANT" "$(cat ffail/keep.txt)"
expect_exit "ln -f valid src replaces"   0 "$BIN" ln -f ffail/src.txt ffail/keep.txt
expect_eq   "destination replaced"       "SRC" "$(cat ffail/keep.txt)"
# No temp file is left behind on either path.
expect_eq   "no stray temp files"        "0" "$(ls -A ffail | grep -c 'kriya-ln-tmp')"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
