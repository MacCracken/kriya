#!/bin/sh
# smoke-rm.sh — behavioural test for `kriya rm`.
#
# Exhaustively verifies the load-bearing safety properties:
#   - ADR 0004 root refusal across every canonicalization escape
#     (`rm /`, `rm /.`, `rm /tmp/..`, `rm ////`, multi-op with `/`).
#   - No `--no-preserve-root` flag exists (rejected as unknown option).
#   - No env-var bypass (`KRIYA_ALLOW_ROOT_DELETE=1` still refused).
#   - ADR 0003 never-follow on symlinks (rm of symlink-to-dir removes
#     only the link; rm -r of a tree containing a symlink-to-dir
#     never descends into the target).
#
# Plus the standard surface: file/symlink rm, -f silences ENOENT, -r
# recursive, -d empty-only, -v verbose, -i invocation-wide non-tty
# refusal per ADR 0002.

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
    if [ -e "$2" ] || [ -L "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' missing\n" "$1" "$2" >&2
    fi
}

expect_absent() {
    if [ ! -e "$2" ] && [ ! -L "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' should not exist\n" "$1" "$2" >&2
    fi
}

# --- ADR 0004 root refusal — every canonicalization route ---
expect_exit "rm /"                       2 "$BIN" rm /
expect_exit "rm -r -f /"                 2 "$BIN" rm -r -f /
expect_exit "rm /."                      2 "$BIN" rm /.
expect_exit "rm /tmp/.."                 2 "$BIN" rm /tmp/..
expect_exit "rm ////"                    2 "$BIN" rm ////
expect_exit "rm /../../../../"           2 "$BIN" rm /../../../../

# Relative canonicalization: in a path where ../../ resolves to /.
# We're in $WORK (something like /tmp/tmp.XXXXXXXX), so ../../ from
# here goes to /tmp, ../../../ goes to /. Build that depth-relative
# refusal exactly.
# $WORK is /tmp/tmp.XXXXXXXX so depth is 2 dirs deep from /; ../.. → /.
expect_exit "rm relative ../../"         2 "$BIN" rm ../../

# Output message check.
out=$("$BIN" rm / 2>&1 || true)
expected="kriya rm: refusing to operate on '/'"
expect_eq "refusal message"              "$expected" "$out"

# No escape-hatch flag.
expect_exit "no --no-preserve-root"      2 "$BIN" rm --no-preserve-root /
expect_exit "no --preserve-root"         2 "$BIN" rm --preserve-root /

# No env-var bypass.
rc=0
KRIYA_ALLOW_ROOT_DELETE=1 "$BIN" rm / >/dev/null 2>&1 || rc=$?
expect_eq "no env bypass"                "2" "$rc"

# Multi-operand atomicity: if any operand is `/`, the whole invocation
# refuses and OTHER operands are not touched.
echo "data" > survivor
expect_exit "multi-op refuses all"       2 "$BIN" rm survivor /
expect_present "survivor untouched"      survivor

# --- ADR 0003 symlink never-follow ---
mkdir target_dir
echo "do-not-touch" > target_dir/important
ln -s target_dir symdir

# rm of the symlink: removes the link, NOT the contents.
expect_exit "rm symlink-to-dir"          0 "$BIN" rm symdir
expect_absent "symlink unlinked"         symdir
expect_present "target dir intact"       target_dir
expect_present "important file intact"   target_dir/important
content=$(cat target_dir/important)
expect_eq "important content"            "do-not-touch" "$content"

# rm -r of a directory CONTAINING a symlink-to-dir: never descends.
mkdir -p container
echo "still here" > target_dir/witness
ln -s ../target_dir container/symlink_in
expect_exit "rm -r preserves linkees"    0 "$BIN" rm -r container
expect_absent "container gone"           container
expect_present "target_dir still here"   target_dir
expect_present "witness preserved"       target_dir/witness
content=$(cat target_dir/witness)
expect_eq "witness content"              "still here" "$content"

# rm of a dangling symlink: removes the link.
ln -s nonexistent_target dangling
expect_exit "rm dangling symlink"        0 "$BIN" rm dangling
expect_absent "dangling unlinked"        dangling

# --- basic file removal ---
echo "x" > file1
expect_exit "rm file"                    0 "$BIN" rm file1
expect_absent "file gone"                file1

# Multi-operand.
echo a > a; echo b > b; echo c > c
expect_exit "rm a b c"                   0 "$BIN" rm a b c
expect_absent "a"                        a
expect_absent "b"                        b
expect_absent "c"                        c

# --- error paths ---
expect_exit "no operands"                2 "$BIN" rm
expect_exit "missing source"             1 "$BIN" rm gone
# -f silences missing (POSIX).
expect_exit "rm -f missing"              0 "$BIN" rm -f gone
# -f with no operands is exit 0 (POSIX: rm -f with no args is OK).
expect_exit "rm -f no operands"          0 "$BIN" rm -f

# -i on non-tty is invocation-wide usage error.
expect_exit "-i on pipe"                 2 "$BIN" rm -i file1

# Directory without -r or -d: EISDIR.
mkdir somedir
expect_exit "dir w/o -r"                 1 "$BIN" rm somedir
expect_present "somedir kept"            somedir

# -d on empty dir: success.
expect_exit "rm -d empty"                0 "$BIN" rm -d somedir
expect_absent "somedir removed"          somedir

# -d on non-empty dir: ENOTEMPTY.
mkdir notempty && touch notempty/inside
expect_exit "rm -d nonempty"             1 "$BIN" rm -d notempty
expect_present "notempty kept"           notempty

# --- recursive ---
mkdir -p tree/sub/deep
touch tree/a tree/sub/b tree/sub/deep/c
ln -s a tree/sub/innerlink
expect_exit "rm -r tree"                 0 "$BIN" rm -r tree
expect_absent "tree gone"                tree

# -R alias.
mkdir -p tree2/sub && touch tree2/sub/x
expect_exit "rm -R alias"                0 "$BIN" rm -R tree2
expect_absent "tree2 gone"               tree2

# --- partial failure: one good + one bad → exit 1, good still removed ---
echo p > present
expect_exit "partial failure"            1 "$BIN" rm present nonexistent
expect_absent "present removed"          present

# --- -v verbose ---
echo v > vfile
out=$("$BIN" rm -v vfile 2>&1)
expect_eq "verbose file"                 "removed 'vfile'" "$out"

mkdir -p vtree/sub
touch vtree/a vtree/sub/b
out=$("$BIN" rm -r -v vtree 2>&1 | sort)
echo "$out" | grep -q "^removed 'vtree/a'" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL verbose missing vtree/a" >&2; }
echo "$out" | grep -q "^removed 'vtree/sub/b'" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL verbose missing vtree/sub/b" >&2; }
echo "$out" | grep -q "^removed directory 'vtree/sub'" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL verbose missing vtree/sub dir" >&2; }
echo "$out" | grep -q "^removed directory 'vtree'" && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL verbose missing vtree dir" >&2; }

# --- POSIX "." / ".." operand refusal (v1.1.11) -------------------------
# ⛔ `rm -r dir/sub/..` resolved to the PARENT and emptied it: measured on a
# parent/{keep.txt,sub/} tree, BOTH were deleted and rm then reported "no such
# file or directory" — an error for an operation that had already destroyed the
# wrong directory. POSIX requires the refusal; GNU refuses even under -f.
# The refusal is PER-OPERAND (exit 1, other operands still run), unlike the
# ADR-0004 protected-path check which is invocation-wide.
mkdir -p dot/d/sub dot/sub
echo KEEP > dot/keep.txt
echo DF   > dot/d/f
mkdir -p dot/... dot/a.. dot/..x

expect_exit "rm -r -f .        refused" 1 sh -c "cd dot && '$BIN' rm -r -f ."
expect_exit "rm -r -f ..       refused" 1 sh -c "cd dot && '$BIN' rm -r -f .."
expect_exit "rm -r -f sub/..   refused" 1 sh -c "cd dot && '$BIN' rm -r -f sub/.."
expect_exit "rm -r -f d/.      refused" 1 sh -c "cd dot && '$BIN' rm -r -f d/."
expect_exit "rm -r -f d/./     refused" 1 sh -c "cd dot && '$BIN' rm -r -f d/./"
# Nothing was touched by any of the above.
expect_present "keep.txt survives the refusals" dot/keep.txt
expect_present "d/f survives the refusals"      dot/d/f
expect_present "sub/ survives the refusals"     dot/sub
# ...and names that merely CONTAIN dots are still ordinary, removable names.
expect_exit "rm -r ... removes"  0 "$BIN" rm -r dot/...
expect_exit "rm -r a.. removes"  0 "$BIN" rm -r dot/a..
expect_exit "rm -r ..x removes"  0 "$BIN" rm -r dot/..x
expect_absent "... gone" dot/...
expect_absent "a.. gone" dot/a..
expect_absent "..x gone" dot/..x

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
