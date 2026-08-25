#!/bin/sh
# smoke-realpath.sh — behavioural test for `kriya realpath` and the
# shared `fs_realpath` canonicalization helper in `src/lib/fs.cyr`.
#
# Covers: absolute/relative inputs, `.` / `..` collapse, symlink
# chains, `-e` (default) ENOENT, `-m` text completion, cycle ELOOP,
# multiple operands, `-z` NUL terminator, `-q` silent mode. The
# helper is shared with the forthcoming `readlink -f`/`-e`/`-m`
# follow-up so the test suite here doubles as its canonicalization
# baseline.

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

# Resolve $WORK once for absolute comparison.
WORK_REAL=$(readlink -f "$WORK")

# --- fixture tree ---
mkdir -p a/b/c
echo "x" > a/b/file
ln -s a/b              symdir
ln -s a/b/file         linkfile
ln -s linkfile         chained
ln -s /tmp             abs_symlink
ln -s nope             dangling

# --- absolute path resolution ---
out=$("$BIN" realpath "$WORK/a/b/file")
expect_eq "absolute"             "$WORK_REAL/a/b/file" "$out"

# --- relative path resolution ---
out=$("$BIN" realpath a/b/file)
expect_eq "relative"             "$WORK_REAL/a/b/file" "$out"

# --- . and .. ---
out=$("$BIN" realpath ./a/b/file)
expect_eq "dot collapse"         "$WORK_REAL/a/b/file" "$out"

out=$("$BIN" realpath a/b/../b/file)
expect_eq "dotdot collapse"      "$WORK_REAL/a/b/file" "$out"

out=$("$BIN" realpath a/b/c/../../b/file)
expect_eq "multi dotdot"         "$WORK_REAL/a/b/file" "$out"

# --- root and trailing slashes ---
out=$("$BIN" realpath /)
expect_eq "root /"               "/" "$out"

out=$("$BIN" realpath a/b/)
expect_eq "trailing slash"       "$WORK_REAL/a/b" "$out"

out=$("$BIN" realpath a//b///file)
expect_eq "duplicate slashes"    "$WORK_REAL/a/b/file" "$out"

# --- symlink resolution ---
out=$("$BIN" realpath symdir)
expect_eq "symlink to dir"       "$WORK_REAL/a/b" "$out"

out=$("$BIN" realpath symdir/file)
expect_eq "via symlink-dir"      "$WORK_REAL/a/b/file" "$out"

out=$("$BIN" realpath linkfile)
expect_eq "symlink to file"      "$WORK_REAL/a/b/file" "$out"

out=$("$BIN" realpath chained)
expect_eq "two-hop chain"        "$WORK_REAL/a/b/file" "$out"

out=$("$BIN" realpath abs_symlink)
# /tmp itself may be a symlink to /private/tmp on some systems; match
# only the leading slash. We just check it resolves to something
# absolute.
case "$out" in
    /*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL absolute symlink resolved to non-absolute: $out" >&2 ;;
esac

# --- default mode is -e: ENOENT on missing ---
expect_exit "missing default"    1 "$BIN" realpath a/b/nope

# Dangling symlink under -e: error (the target doesn't exist).
expect_exit "dangling under -e"  1 "$BIN" realpath dangling

# --- -m: ALLOW_MISSING ---
out=$("$BIN" realpath -m a/b/nope)
expect_eq "missing under -m"     "$WORK_REAL/a/b/nope" "$out"

out=$("$BIN" realpath -m a/b/nope/deeper)
expect_eq "deep missing under -m" "$WORK_REAL/a/b/nope/deeper" "$out"

# Dangling symlink under -m: the link IS canonicalized (target is text).
out=$("$BIN" realpath -m dangling)
expect_eq "dangling under -m"    "$WORK_REAL/nope" "$out"

# -m with . / .. mid-path on missing.
out=$("$BIN" realpath -m a/b/nope/../also_missing)
expect_eq "-m with .. through missing" "$WORK_REAL/a/b/also_missing" "$out"

# --- -e explicit (same as default) ---
out=$("$BIN" realpath -e a/b/file)
expect_eq "-e on existing"       "$WORK_REAL/a/b/file" "$out"

expect_exit "-e on missing"      1 "$BIN" realpath -e a/b/nope

# --- cycle: ELOOP ---
ln -s cycle_b cycle_a
ln -s cycle_a cycle_b
expect_exit "cycle ELOOP"        1 "$BIN" realpath cycle_a

# --- multiple operands; partial failure exits 1 but other paths still print ---
out=$("$BIN" realpath a/b/file linkfile chained 2>/dev/null)
expected="$WORK_REAL/a/b/file
$WORK_REAL/a/b/file
$WORK_REAL/a/b/file"
expect_eq "multi all good"       "$expected" "$out"

# Multi with one bad: exit 1, others still printed.
rc=0
out=$("$BIN" realpath a/b/file a/b/nope linkfile 2>/dev/null) || rc=$?
expect_eq "multi partial rc"     "1" "$rc"
expected="$WORK_REAL/a/b/file
$WORK_REAL/a/b/file"
expect_eq "multi partial stdout" "$expected" "$out"

# -q silences stderr on failure.
err=$("$BIN" realpath -q a/b/nope 2>&1 >/dev/null || true)
expect_eq "-q silences stderr"   "" "$err"

# --- -z NUL terminator ---
# Count NULs in the output — should be one per resolved path.
nul_count=$("$BIN" realpath -z a/b/file linkfile | tr -dc '\0' | wc -c | tr -d ' ')
expect_eq "-z emits 2 NULs"      "2" "$nul_count"
# And no newlines at all.
nl_count=$("$BIN" realpath -z a/b/file linkfile | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "-z emits 0 newlines"  "0" "$nl_count"

# --- errors ---
expect_exit "no operands"        2 "$BIN" realpath
expect_exit "empty operand"      1 "$BIN" realpath ""

# --- operands past the old 16 KiB ceiling (M17j, v1.2.6) ---------------
# ⚠ v1.1.11 bounded `fs_realpath`'s previously unchecked seed copies, turning a
# silently wrong answer into an honest ENAMETOOLONG — but it left kriya REFUSING
# 16 KiB operands that GNU resolves. The buffer was never a limit worth having,
# just a constant nobody had revisited. It is sized from the operand now, and
# grows for symlink expansion beyond that.
mkdir -p longp/d
touch longp/d/f
ln -s d longp/ld
for n in 8300 20000; do
    if command -v python3 >/dev/null 2>&1; then
        dots=$(python3 -c "print('/.'*$n)")
        P="$PWD/longp/ld${dots}/f"
        expect_eq "operand of ${#P} bytes matches GNU" \
            "$(realpath -m "$P" 2>&1)" "$("$BIN" realpath -m "$P" 2>&1)"
    fi
done
# ⚠ Growth must not weaken the cycle guard — that bound is the ELOOP counter,
# not the buffer size.
ln -sf cyc_b cyc_a
ln -sf cyc_a cyc_b
expect_exit "symlink cycle still ELOOPs" 1 "$BIN" realpath cyc_a

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
