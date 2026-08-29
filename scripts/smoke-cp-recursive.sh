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

# --- copy-a-directory-into-itself refusal (v1.1.11) ---------------------
# ⛔ This used to recurse forever. `cp -r dir dir/sub` descended into the copy
# it had just made and made another: 12,188 directories created before the
# process DUMPED CORE, with the half-built tree left behind. One mistyped
# operand, a full filesystem and a crash. GNU refuses immediately; so do we.
#
# The refusal must be exact in BOTH directions — an over-broad rule would
# reject the legitimate copies below, which are the common case.
mkdir -p self/sub
echo payload > self/f
echo nested  > self/sub/g

# Refused: destination lands inside the source.
expect_exit "cp -r X X (onto itself)"        1 "$BIN" cp -r self self
expect_exit "cp -r X X/sub (into own subdir)" 1 "$BIN" cp -r self self/sub
expect_exit "cp -r X X/sub/ (trailing slash)" 1 "$BIN" cp -r self self/sub/
# Refused before ANY directory is created — kriya leaves no partial tree
# (GNU creates two levels before it notices).
SELF_DIRS=$(find self -type d | wc -l | tr -d ' ')
expect_eq  "no partial tree left behind"     "2" "$SELF_DIRS"
# ...and refused when the two operands are spelled differently.
expect_exit "cp -r ABS X/sub (abs vs rel)"   1 "$BIN" cp -r "$WORK/self" self/sub

# Allowed: destination is outside the source. These are the copies the guard
# must not touch.
expect_exit "cp -r X sibling"                0 "$BIN" cp -r self sibling
expect_type "sibling copied"                 dir sibling
expect_exit "cp -r X/sub X/sub2 (same parent)" 0 "$BIN" cp -r self/sub self/sub2
expect_type "sub2 created"                   dir self/sub2
mkdir -p intodir
expect_exit "cp -r X existing-dir/"          0 "$BIN" cp -r self intodir/
expect_type "nested under existing dir"      dir intodir/self

# --- the recursive path honours -i and the no-clobber default (v1.2.3) ---
# ⛔ `cp -R` opened every destination with O_TRUNC and never asked, so
# `cp -i -R src dst` overwrote WITHOUT A SINGLE PROMPT (verified under a real
# pty: GNU asks, kriya did not), and `cp -R src dst` with no -f silently
# replaced existing files — while the NON-recursive path right beside it has
# always refused that. cp was inconsistent with itself, and the recursive half
# was the one contradicting CLAUDE.md's "no silent file overwrites without -f".
mkdir -p iact/s iact/d/s
echo NEW           > iact/s/f
echo OLD-IMPORTANT > iact/d/s/f

# No -f: refuse, and leave the destination alone.
expect_exit "cp -R no -f refuses"     1 "$BIN" cp -R iact/s iact/d
expect_eq   "…destination untouched"  "OLD-IMPORTANT" "$(cat iact/d/s/f)"
# -f: overwrite.
expect_exit "cp -R -f overwrites"     0 "$BIN" cp -R -f iact/s iact/d
expect_eq   "…destination replaced"   "NEW" "$(cat iact/d/s/f)"

# -i under a real pty. ⚠ `script(1)` is what makes the prompt reachable from a
# shell script at all — kriya refuses -i on a non-tty stdin by design (ADR 0002),
# so a plain pipe cannot exercise this path.
# ⚠ `command -v script` is satisfied by BusyBox's applet too, and `-qec` is
# util-linux syntax that BusyBox does not accept — on Alpine or any busybox
# rootfs the invocation fails and the assertion blames kriya. Probe the actual
# flags, not the name.
if script -qec true /dev/null >/dev/null 2>&1; then
    echo OLD-IMPORTANT > iact/d/s/f
    # ⚠ `|| rc=$?` is load-bearing under `set -e`: declining is EXPECTED to exit
    # 1, and a bare pipeline would abort the script at that status before the
    # assertion ran.
    rc=0
    printf 'n\n' | script -qec "'$BIN' cp -i -R iact/s iact/d" /dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "cp -i -R declined: exit 1"     "1" "$rc"
    expect_eq "cp -i -R declined: kept file"  "OLD-IMPORTANT" "$(cat iact/d/s/f)"

    echo OLD-IMPORTANT > iact/d/s/f
    rc=0
    printf 'y\n' | script -qec "'$BIN' cp -i -R iact/s iact/d" /dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "cp -i -R accepted: exit 0"     "0" "$rc"
    expect_eq "cp -i -R accepted: replaced"   "NEW" "$(cat iact/d/s/f)"
else
    echo "skip: script(1) unavailable — the -i prompt path was not exercised"
fi

# A fresh recursive copy is unaffected by any of the above.
mkdir -p fresh_src/sub && echo A > fresh_src/a && echo B > fresh_src/sub/b
expect_exit "fresh recursive copy"    0 "$BIN" cp -R fresh_src fresh_dst
expect_eq   "…copied both files"      "a sub/b" "$(cd fresh_dst && find . -type f | sed 's|^\./||' | sort | tr '\n' ' ' | sed 's/ $//')"

# --- 1.6.9: the create / withhold / restore protocol on directories ----------
#
# ⛔ A SOURCE DIRECTORY WITHOUT OWNER-WRITE COPIED NOTHING INTO ITSELF, and
# nothing in this file could see it: every fixture above builds its directories
# at the default mode, and at 0755 the broken implementation and the correct one
# produce identical trees. The distinguishing shape is a source directory the
# OWNER cannot write to — a `chmod -R a-w` archive, an exported release tree —
# where kriya used to make the destination at 0500 and then fail on every entry
# it tried to put inside it.
#
# ⚠ EVERY CASE BELOW IS COMPARED TO GNU rather than to a mode written here by
# hand: the answer depends on the umask, on the kernel's set-id rules for
# `mkdir`, and on whether `-p` is in play, and a hand-written expectation would
# be a fourth opinion about all three.
cpm_clean() { chmod -R u+rwX cpm_s cpm_g cpm_k 2>/dev/null || true; rm -rf cpm_s cpm_g cpm_k; }

# cpm_case <name> <umask> <srcmode> [flags...] — builds a three-deep chain at
# <srcmode>, copies it with GNU and with kriya, and compares the modes of all
# three levels, the presence of the deepest file, and the exit code.
cpm_case() {
    _n=$1; _um=$2; _sm=$3; shift 3
    cpm_clean
    mkdir -p cpm_s/a/b/c
    : > cpm_s/a/b/c/f
    : > cpm_s/a/f2
    chmod "$_sm" cpm_s/a/b/c cpm_s/a/b cpm_s/a
    chmod 755 cpm_s
    _grc=0; ( umask "$_um"; cp    -R "$@" cpm_s cpm_g >/dev/null 2>&1 ) || _grc=$?
    _krc=0; ( umask "$_um"; "$BIN" cp -R "$@" cpm_s cpm_k >/dev/null 2>&1 ) || _krc=$?
    _gs=""; _ks=""
    for _p in a a/b a/b/c; do
        _gs="$_gs$(stat -c %a "cpm_g/$_p" 2>/dev/null || echo ABSENT)/"
        _ks="$_ks$(stat -c %a "cpm_k/$_p" 2>/dev/null || echo ABSENT)/"
    done
    _gf=$([ -e cpm_g/a/b/c/f ] && echo y || echo n)
    _kf=$([ -e cpm_k/a/b/c/f ] && echo y || echo n)
    expect_eq "$_n" "$_gs|$_gf|$_grc" "$_ks|$_kf|$_krc"
    cpm_clean
}

# ⭐ 0500 and 0550 ARE THE CASES THAT WERE BROKEN. The rest are here so a fix
# that widens the wrong thing — or forgets to narrow it again — goes red too.
for _um in 022 077 000; do
    for _sm in 700 755 777 750 500 550 2755 1777; do
        cpm_case "cp -R umask=$_um src=$_sm" "$_um" "$_sm"
    done
done
# ⚠ `-p` needs the working mode just as badly, and it took a second wiring: the
# widen is unconditional, only the restore is not.
for _um in 022 077; do
    for _sm in 700 755 500 550 1777 2755; do
        cpm_case "cp -pR umask=$_um src=$_sm" "$_um" "$_sm" -p
    done
done
cpm_case "cp -R --preserve=mode of a 0500 tree" 022 500 --preserve=mode

# ⛔ THE RESTORE RUNS AFTER A FAILURE TOO. A copy that cannot read one source
# file still leaves the directory at the source's mode with the readable entries
# in it — anything else leaves the WORKING mode behind on a copy the user can
# see failed.
cpm_clean
mkdir -p cpm_s/sub; : > cpm_s/sub/ok; : > cpm_s/sub/bad
chmod 000 cpm_s/sub/bad; chmod 500 cpm_s/sub; chmod 550 cpm_s
grc=0; ( umask 022; cp    -R cpm_s cpm_g >/dev/null 2>&1 ) || grc=$?
krc=0; ( umask 022; "$BIN" cp -R cpm_s cpm_k >/dev/null 2>&1 ) || krc=$?
expect_eq "partial failure: exit code"   "$grc" "$krc"
expect_eq "partial failure: root mode"   "$(stat -c %a cpm_g)"     "$(stat -c %a cpm_k)"
expect_eq "partial failure: dir mode"    "$(stat -c %a cpm_g/sub)" "$(stat -c %a cpm_k/sub)"
expect_eq "partial failure: what landed" "$(ls -A cpm_g/sub | sort | tr '\n' ' ')" \
                                         "$(ls -A cpm_k/sub | sort | tr '\n' ' ')"
cpm_clean

# ⛔ THE DESTINATION IS CREATED BEFORE THE SOURCE IS OPENED. With a source
# directory that has no owner READ, GNU still leaves the mirroring destination
# behind at `src & ~umask`; kriya opened the source first and left nothing.
for _sm in 300 333 111; do
    cpm_clean
    mkdir -p cpm_s/sub; : > cpm_s/sub/f; chmod "$_sm" cpm_s/sub; chmod 755 cpm_s
    grc=0; ( umask 022; cp    -R cpm_s cpm_g >/dev/null 2>&1 ) || grc=$?
    krc=0; ( umask 022; "$BIN" cp -R cpm_s cpm_k >/dev/null 2>&1 ) || krc=$?
    expect_eq "unreadable src=$_sm leaves the same shape" \
      "$grc|$(stat -c %a cpm_g/sub 2>/dev/null || echo ABSENT)" \
      "$krc|$(stat -c %a cpm_k/sub 2>/dev/null || echo ABSENT)"
    cpm_clean
done

# ⚠ AN EXISTING DESTINATION DIRECTORY IS NOT OURS TO WIDEN. The withhold applies
# to directories cp makes; one that was already there keeps its mode, and a 0500
# one still fails — exactly as GNU's does.
for _dm in 777 700 555 500; do
    cpm_clean
    mkdir -p cpm_s/sub; : > cpm_s/sub/f; chmod 755 cpm_s/sub cpm_s
    mkdir -p cpm_g/sub cpm_k/sub; chmod "$_dm" cpm_g/sub; chmod "$_dm" cpm_k/sub
    grc=0; ( umask 022; cp    -R cpm_s/. cpm_g >/dev/null 2>&1 ) || grc=$?
    krc=0; ( umask 022; "$BIN" cp -R cpm_s/. cpm_k >/dev/null 2>&1 ) || krc=$?
    expect_eq "existing dst=$_dm is left alone" \
      "$grc|$(stat -c %a cpm_g/sub 2>/dev/null)" "$krc|$(stat -c %a cpm_k/sub 2>/dev/null)"
    cpm_clean
done

# ⛔ THE GROUP/OTHER WITHHOLD HAS NO FINAL-STATE SIGNATURE, so nothing above can
# see it: the directory ends at the same mode whether or not it was narrowed
# while cp was writing into it. That is precisely why it is worth a test — a
# change that keeps every final mode right and drops the withhold is invisible
# otherwise, and it reopens the window another user races into.
#
# ⚠ BEST-EFFORT BY CONSTRUCTION. Catching a transient means polling against a
# running copy, so a fast machine can finish before the poll sees anything. On a
# miss this SKIPS with a note rather than passing quietly — a silent pass here
# would be the same lie the missing test already was.
#
# ⭐ The expectation is GNU's OWN observed transient, not a mode written here.
cpm_clean
mkdir -p cpm_s/sub
_i=0
while [ "$_i" -lt 800 ]; do : > "cpm_s/sub/f$_i"; _i=$((_i + 1)); done
chmod 777 cpm_s/sub; chmod 755 cpm_s

cpm_watch() {   # cpm_watch <dest> <cmd...> — echoes every distinct mode seen
    _d=$1; shift
    ( umask 000
      "$@" >/dev/null 2>&1 &
      _p=$!; _seen=""
      while kill -0 "$_p" 2>/dev/null; do
          _m=$(stat -c %a "$_d" 2>/dev/null)
          if [ -n "$_m" ]; then
              case " $_seen " in *" $_m "*) ;; *) _seen="$_seen $_m" ;; esac
          fi
      done
      wait "$_p" 2>/dev/null || true
      echo "$_seen"
      true )
}
# ⚠ EVERY STEP HERE IS `|| true`. This is a probe, not an assertion, and a probe
# that can abort the suite is worse than no probe: it died silently under
# `set -e` in the ubuntu:24.04 container on the FIRST run, taking 108 real
# assertions with it and reporting nothing at all.
g_seen=$(cpm_watch cpm_g/sub cp -R cpm_s cpm_g 2>/dev/null || true)
k_seen=$(cpm_watch cpm_k/sub "$BIN" cp -R cpm_s cpm_k 2>/dev/null || true)
# A "withheld" observation is any mode that is not the final 0777.
g_with=$(printf '%s\n' $g_seen | grep -v '^777$' | grep . | head -1 || true)
k_with=$(printf '%s\n' $k_seen | grep -v '^777$' | grep . | head -1 || true)
if [ -n "$g_with" ]; then
    expect_eq "the withheld mode matches GNU's" "$g_with" "${k_with:-NONE-OBSERVED}"
else
    echo "note: the copy finished before the poll saw a transient mode;"
    echo "      the group/other withhold is unverified on this run"
fi
expect_eq "...and both end at the source mode" \
  "$(stat -c %a cpm_g/sub 2>/dev/null || echo ABSENT)" \
  "$(stat -c %a cpm_k/sub 2>/dev/null || echo ABSENT)"
cpm_clean

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
