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
        # ⚠ stdout ONLY — `2>&1` folded GNU's ERROR TEXT into the comparison,
        # so on any input where GNU fails, kriya had to reproduce that wording
        # byte-for-byte. Error strings are the part of GNU that changes most
        # freely between releases; pinning them makes the test a version
        # detector rather than a behaviour check. Exit status IS compared,
        # which is the part that carries meaning.
        g=$(realpath -m "$P" 2>/dev/null); grc=$?
        k=$("$BIN" realpath -m "$P" 2>/dev/null); krc=$?
        expect_eq "operand of ${#P} bytes matches GNU"        "$g"   "$k"
        expect_eq "operand of ${#P} bytes: same exit as GNU"  "$grc" "$krc"
    fi
done
# ⚠ Growth must not weaken the cycle guard — that bound is the ELOOP counter,
# not the buffer size.
ln -sf cyc_b cyc_a
ln -sf cyc_a cyc_b
expect_exit "symlink cycle still ELOOPs" 1 "$BIN" realpath cyc_a

# =====================================================================
# -m / ALLOW_MISSING: what "missing" is allowed to mean
# =====================================================================
# ⛔ `-m` TOLERATED ONLY ENOENT, AND STOPPED RESOLVING AFTER IT. Both halves were
# wrong against GNU, and the second one is the subtler: a symlink AFTER a missing
# component was never followed, so the answer was not canonical.
# ⚠ gnulib calls this mode CAN_MISSING and its rule is simply "a component we
# cannot lstat is not a symlink" — commit it and carry on.
# ⭐ Found through `ln -sr`, which uses the same mode: the ELOOP case made kriya
# write a link that silently pointed at a DIFFERENT REAL FILE.
rm -rf mm; mkdir mm; cd mm
mkdir -p real/sub; echo x > real/sub/f
ln -s real slink
ln -s loopb loopa; ln -s loopa loopb
echo plainfile > plain
mkdir -p priv/sub; echo secret > priv/sub/f; chmod 000 priv

same_m() {   # same_m <name> <path>
    expect_eq "$1" "$(realpath -m "$2" 2>&1)" "$("$BIN" realpath -m "$2" 2>&1)"
}
same_m "-m resolves a symlink AFTER a missing component" nonexistent/../slink/sub/f
same_m "-m on a symlink LOOP answers the path"           loopa
same_m "-m through a plain file (ENOTDIR)"               plain/sub
same_m "-m on a plain missing name"                      nonexistent
same_m "-m through a symlinked directory"                slink/sub/f
same_m "-m with a trailing .."                           slink/sub/..
chmod 000 priv
same_m "-m through an unsearchable directory (EACCES)"   priv/sub/f
chmod 755 priv

# ⚠ THE STRICT MODES ARE UNCHANGED, which is the other half of the fix: only
# ALLOW_MISSING tolerates a failure, and a loop is still an error without -m.
expect_exit "plain realpath still refuses a loop"  1 "$BIN" realpath loopa
expect_eq "...with GNU's exit"                     "$(realpath loopa >/dev/null 2>&1; echo $?)" \
                                                   "$("$BIN" realpath loopa >/dev/null 2>&1; echo $?)"
expect_exit "realpath -e still refuses a missing"  1 "$BIN" realpath -e nonexistent
cd ..

# --- ADR 0014: the traversal limit is the KERNEL'S 40, not GNU's ------------
# ⛔ THIS IS A DELIBERATE DIVERGENCE and the asymmetry is the reason. GNU's
# `realpath` resolves a symlink chain of ANY length — measured to 121 — so for a
# long-enough chain it prints a path that GNU's own `cat` cannot open, because
# the kernel gives up at 40. An answer no `open(2)` will honour is worse than an
# error. Inside a CYCLE, GNU stops after 20 traversals and kriya after 40; every
# answer there is unresolvable either way, so only the name differs.
mkdir chain; cd chain
echo hi > target
N=60; ln -s target "l$N"; i=$N
while [ "$i" -gt 0 ]; do p=$((i - 1)); ln -s "l$i" "l$p"; i=$p; done

# 40 hops: the kernel allows it, so kriya must resolve it.
expect_eq "a 40-hop chain resolves (the kernel's limit)" "hi" "$(cat "l$((N - 39))")"
expect_eq "...and realpath agrees" "$(realpath "l$((N - 39))")" "$("$BIN" realpath "l$((N - 39))")"

# 61 hops: the kernel refuses, so kriya refuses — and GNU does not.
expect_exit "a 61-hop chain is ELOOP, as it is for open(2)" 1 "$BIN" realpath l0
expect_eq "...the kernel refuses that same name" "cannot-open" \
          "$(cat l0 >/dev/null 2>&1 && echo opened || echo cannot-open)"
expect_eq "...and GNU answers a name it cannot open" "yes" \
          "$(realpath l0 >/dev/null 2>&1 && echo yes || echo no)"
expect_exit "...-m refuses to invent one either" 0 "$BIN" realpath -m l0

# A cycle terminates in every mode rather than hanging — the counter never
# resets, so declining to follow further still ends the walk.
mkdir -p cyc; ( cd cyc && ln -s n1 n0 && ln -s n2 n1 && ln -s n0 n2 )
expect_exit "a cycle is ELOOP in the strict mode"   1 "$BIN" realpath cyc/n0
expect_exit "a cycle ANSWERS under -m"              0 "$BIN" realpath -m cyc/n0
expect_eq "...and the answer is inside the cycle" "yes" \
          "$(case "$("$BIN" realpath -m cyc/n0)" in */cyc/n[012]) echo yes;; *) echo no;; esac)"
cd ..

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
