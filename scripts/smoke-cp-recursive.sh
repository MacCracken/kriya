#!/bin/sh
# smoke-cp-recursive.sh — behavioural test for `kriya cp -R`.
#
# Exercises the ADR-0003 symlink-policy matrix end-to-end:
#   -P (default with -R): preserve all symlinks.
#   -H: follow command-line operands, preserve in-walk.
#   -L: follow everywhere; destination tree is all-content, no links.
# Plus: basic recursion, into-existing-dir, mixed contents (regular +
# symlink + nested dirs), preserve mode + times via -p, error paths.

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

expect_file_match() {
    if cmp -s "$2" "$3"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' and '%s' differ\n" "$1" "$2" "$3" >&2
    fi
}

expect_type() {
    # expect_type name dir|file|symlink path
    actual=""
    if [ -L "$3" ]; then actual="symlink";
    elif [ -d "$3" ]; then actual="dir";
    elif [ -f "$3" ]; then actual="file";
    else actual="other"; fi
    expect_eq "$1" "$2" "$actual"
}

expect_link_target() {
    actual=$(readlink "$2")
    expect_eq "$1" "$3" "$actual"
}

# --- build a fixture tree with mixed content ---
mkdir -p tree/sub/deep
echo "root-content" > tree/a.txt
echo "sub-content"  > tree/sub/b.txt
echo "deep-content" > tree/sub/deep/c.txt
ln -s ../a.txt      tree/sub/link_to_a

# --- basic -R ---
expect_exit "cp -R tree copy1"        0 "$BIN" cp -R tree copy1
expect_type "copy1 is dir"            dir     copy1
expect_type "copy1/a.txt is file"     file    copy1/a.txt
expect_file_match "a.txt content"     tree/a.txt copy1/a.txt
expect_type "copy1/sub is dir"        dir     copy1/sub
expect_type "copy1/sub/deep is dir"   dir     copy1/sub/deep
expect_file_match "deep/c.txt"        tree/sub/deep/c.txt copy1/sub/deep/c.txt
# Default = -P: symlink preserved.
expect_type "default preserves link"  symlink copy1/sub/link_to_a
expect_link_target "link target text" copy1/sub/link_to_a ../a.txt

# `-r` alias works.
expect_exit "cp -r alias"             0 "$BIN" cp -r tree copy_r
expect_type "copy_r is dir"           dir copy_r

# --- -R into existing directory ---
mkdir into
expect_exit "cp -R tree into/"        0 "$BIN" cp -R tree into/
expect_type "into/tree is dir"        dir  into/tree
expect_type "into/tree/a.txt"         file into/tree/a.txt

# --- -P explicit (== default) ---
ln -s tree topsym
expect_exit "cp -R -P topsym dst"     0 "$BIN" cp -R -P topsym copy_P
# Top-level symlink preserved.
expect_type "copy_P is symlink"       symlink copy_P
expect_link_target "copy_P target"    copy_P tree

# --- -H follow command-line only ---
expect_exit "cp -R -H topsym dst"     0 "$BIN" cp -R -H topsym copy_H
expect_type "copy_H is dir (followed)" dir copy_H
expect_type "copy_H/a.txt is file"    file copy_H/a.txt
# Inner symlink should still be preserved (-H only follows the operand).
expect_type "inner link preserved"    symlink copy_H/sub/link_to_a
expect_link_target "inner target"     copy_H/sub/link_to_a ../a.txt

# --- -L follow everywhere ---
expect_exit "cp -R -L topsym dst"     0 "$BIN" cp -R -L topsym copy_L
expect_type "copy_L is dir"           dir copy_L
# Inner symlink should have been followed and replaced by content.
expect_type "inner link followed"     file copy_L/sub/link_to_a
expect_file_match "followed content"  tree/a.txt copy_L/sub/link_to_a

# --- -p preserve mode + times under -R ---
# Set timestamps and mode AFTER content is written so they stick.
echo "stamped" > tree/a.txt
chmod 0640 tree/a.txt
touch -t 202001010000.00 tree/a.txt
SRC_M=$(stat -c %a tree/a.txt)
SRC_T=$(stat -c %Y tree/a.txt)
expect_exit "cp -R -p"                0 "$BIN" cp -R -p tree copy_p
DST_M=$(stat -c %a copy_p/a.txt)
DST_T=$(stat -c %Y copy_p/a.txt)
expect_eq "preserved mode"            "$SRC_M" "$DST_M"
expect_eq "preserved mtime"           "$SRC_T" "$DST_T"

# --- error paths ---
# Missing source.
expect_exit "missing src"             1 "$BIN" cp -R no_such_tree dest

# Source is a directory; destination is an existing regular file: ENOTDIR-like.
: > existing_file
expect_exit "dir over file"           1 "$BIN" cp -R tree existing_file

# Without -R, copying a directory still errors (regression of the
# non-recursive ship).
expect_exit "dir w/o -R"              1 "$BIN" cp tree no_R_dest

# Self-copy refused at the regular-file level — sanity check that the
# non-recursive path still works after the cp.cyr restructure.
echo "self" > selftest
expect_exit "self-copy regression"    1 "$BIN" cp selftest selftest

# --- verbose ---
out=$("$BIN" cp -R -v tree copy_v 2>&1 | sort)
# Order across find/getdents is filesystem-dependent; we just check the
# expected lines are all present.
echo "$out" | grep -q "'tree/a.txt' -> 'copy_v/a.txt'" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL verbose missing a.txt line" >&2; }
echo "$out" | grep -q "'tree/sub/link_to_a' -> 'copy_v/sub/link_to_a'" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL verbose missing link line" >&2; }
echo "$out" | grep -q "'tree/sub/deep/c.txt' -> 'copy_v/sub/deep/c.txt'" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL verbose missing deep line" >&2; }

# --- TOCTOU-style protection: symlink swap fails ELOOP at descend ---
# Create a directory, copy it via -R, then in a parallel test:
#   - replace an internal entry with a symlink between lstat and open.
# We can't easily race in a shell test; instead, we directly confirm
# that opening an existing dir entry that IS a symlink with NOFOLLOW
# fails. Static surrogate:
mkdir nofollow_test
ln -s /etc nofollow_test/etc_link
# Without -L, the inner link should be preserved as a symlink — not
# followed into /etc.
expect_exit "preserve /etc link"      0 "$BIN" cp -R nofollow_test nofollow_copy
expect_type "etc_link preserved"      symlink nofollow_copy/etc_link
expect_link_target "etc_link target"  nofollow_copy/etc_link /etc

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
