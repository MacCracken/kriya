#!/bin/sh
# smoke-readlink.sh — behavioural test for `kriya readlink`.
#
# Two surfaces:
#   - POSIX raw read-link (no flag): print the symlink's target text.
#     Error if the operand is not a symlink (EINVAL).
#   - Canonicalize modes (-f / -e / -m): delegate to `fs_realpath`,
#     same helper that powers `realpath`. The realpath smoke covers
#     the canonicalization algorithm deeply; here we just verify
#     readlink's flag-to-mode mapping and display modifiers.

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
WORK_REAL=$(readlink -f "$WORK")

PASS=0
FAIL=0
SKIP=0

skip() {
    SKIP=$((SKIP + 1))
    echo "skip: $1"
}

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

# --- fixture ---
mkdir -p a/b
echo "x" > a/b/file
ln -s a/b/file linkfile
ln -s linkfile chain
ln -s /tmp     abs_link
ln -s ghost    dangling

# --- POSIX raw read-link ---
out=$("$BIN" readlink linkfile)
expect_eq "raw linkfile"          "a/b/file" "$out"

out=$("$BIN" readlink chain)
expect_eq "raw chain"             "linkfile" "$out"

out=$("$BIN" readlink abs_link)
expect_eq "raw abs_link"          "/tmp" "$out"

out=$("$BIN" readlink dangling)
expect_eq "raw dangling"          "ghost" "$out"

# POSIX on a non-symlink: EINVAL (exit 1).
expect_exit "non-symlink"         1 "$BIN" readlink a/b/file

# --- -f (REQUIRE_PARENT): last component may be missing ---
out=$("$BIN" readlink -f linkfile)
expect_eq "-f linkfile"           "$WORK_REAL/a/b/file" "$out"

out=$("$BIN" readlink -f chain)
expect_eq "-f chain (resolves)"   "$WORK_REAL/a/b/file" "$out"

# -f tolerates missing last component (parent exists).
out=$("$BIN" readlink -f a/b/missing)
expect_eq "-f missing last"       "$WORK_REAL/a/b/missing" "$out"

# -f rejects missing parent.
expect_exit "-f missing parent"   1 "$BIN" readlink -f a/b/nope/deep

# --- -e (REQUIRE_ALL) ---
out=$("$BIN" readlink -e a/b/file)
expect_eq "-e existing"           "$WORK_REAL/a/b/file" "$out"

expect_exit "-e missing"          1 "$BIN" readlink -e a/b/nope
expect_exit "-e missing parent"   1 "$BIN" readlink -e a/b/nope/deep

# --- -m (ALLOW_MISSING) ---
out=$("$BIN" readlink -m a/b/nope/totally/missing)
expect_eq "-m deep missing"       "$WORK_REAL/a/b/nope/totally/missing" "$out"

out=$("$BIN" readlink -m linkfile)
expect_eq "-m on symlink"         "$WORK_REAL/a/b/file" "$out"

# --- -q silences error stderr ---
err=$("$BIN" readlink -q -e a/b/nope 2>&1 >/dev/null || true)
expect_eq "-q silences -e"        "" "$err"

err=$("$BIN" readlink -q a/b/file 2>&1 >/dev/null || true)
expect_eq "-q silences POSIX"     "" "$err"

# --- -n (no-newline) on final operand only ---
# Single operand: no trailing newline at all.
nl=$("$BIN" readlink -n linkfile | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "-n single 0 newlines"  "0" "$nl"

# Multi operands: trailing newlines on all but the last.
nl=$("$BIN" readlink -n linkfile chain abs_link | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "-n multi 2 newlines"   "2" "$nl"

# --- -z NUL terminator (overrides -n) ---
nul=$("$BIN" readlink -z linkfile chain | tr -dc '\0' | wc -c | tr -d ' ')
expect_eq "-z multi 2 NULs"       "2" "$nul"

# -z + -n: -z wins; every operand gets a NUL.
nul=$("$BIN" readlink -z -n linkfile chain | tr -dc '\0' | wc -c | tr -d ' ')
expect_eq "-z -n multi 2 NULs"    "2" "$nul"

# --- multi-operand partial failure ---
rc=0
out=$("$BIN" readlink -e a/b/file a/b/nope linkfile 2>/dev/null) || rc=$?
expect_eq "multi partial rc"      "1" "$rc"
expected="$WORK_REAL/a/b/file
$WORK_REAL/a/b/file"
expect_eq "multi partial stdout"  "$expected" "$out"

# --- canonicalize precedence: -m > -e > -f ---
out=$("$BIN" readlink -f -e -m a/b/nope/deeper)
# -m wins → allows missing → returns the canonical path
expect_eq "-f -e -m: m wins"      "$WORK_REAL/a/b/nope/deeper" "$out"

# --- no operands ---
expect_exit "no operands"         2 "$BIN" readlink

# --- 1.6.3: readlink shares fs_realpath, so it shared the defect ----------
# ⛔ A TRAILING SLASH IS A DIRECTORY ASSERTION. `readlink -f flink/` on a symlink
# to a REGULAR FILE is an error under GNU and under open(2); kriya stripped the
# slash and printed the file with exit 0. ⚠ That output is normally fed straight
# into the next command, which is why a wrong answer here is worse than an error.
mkdir -p rl163/dir
echo f > rl163/plain
( cd rl163 && ln -s plain flink && ln -s dir dlink )
cd rl163
expect_exit "readlink -f on a symlink-to-file WITH a slash" 1 "$BIN" readlink -f flink/
expect_exit "...and without one"                            0 "$BIN" readlink -f flink
expect_exit "readlink -f on a symlink-to-dir with a slash"  0 "$BIN" readlink -f dlink/
expect_exit "readlink -f through a regular file"            1 "$BIN" readlink -f plain/..
# ⚠ -m never asserts it, in readlink as in realpath.
expect_exit "readlink -m ignores the assertion"             0 "$BIN" readlink -m flink/
# ⛔ AND THE `.` SPELLING, which the first version of the fix missed entirely —
# it read the last byte of the operand, so `flink/.` slipped through.
expect_exit "readlink -f with a trailing ."                1 "$BIN" readlink -f flink/.
expect_exit "readlink -e with a trailing ."                1 "$BIN" readlink -e flink/.
expect_exit "...and on a real directory it is fine"        0 "$BIN" readlink -f dir/.
# ⚠ A separator arriving from the LINK'S OWN TARGET, which argv never sees.
ln -s "plain/" slashtgt
expect_exit "readlink -f through a link whose target ends in /" 1 "$BIN" readlink -f slashtgt
cd "$WORK"

# --- 1.6.6: silent by default, and the -s/-v pair (ADR 0018) --------------
# ⛔ THE DEFAULT CHANGED AND NOTHING WENT RED. kriya's readlink used to print a
# diagnostic on failure; GNU's prints nothing. The suite passed either way,
# which is the gap these assertions close.
mkdir -p rlq; echo x > rlq/plain; ln -s plain rlq/good; ln -s nowhere rlq/dang
expect_eq "a non-symlink is SILENT by default" "" \
          "$("$BIN" readlink rlq/plain 2>&1)"
expect_exit "...and still exit 1"            1 "$BIN" readlink rlq/plain
expect_eq "a missing operand is silent too"  "" \
          "$("$BIN" readlink rlq/missing 2>&1)"
expect_eq "...and GNU agrees on both"        "" \
          "$(readlink rlq/plain 2>&1; readlink rlq/missing 2>&1)"
# ⭐ `-v` IS THE WHOLE OPT-IN, because kriya does not honour POSIXLY_CORRECT —
# GNU's own route to verbose, and one that BEATS an explicit -q (measured).
expect_eq "-v opts into the diagnostic" "1" \
          "$("$BIN" readlink -v rlq/plain 2>&1 | grep -c 'invalid argument')"
expect_eq "--verbose does too"          "1" \
          "$("$BIN" readlink --verbose rlq/plain 2>&1 | grep -c 'invalid argument')"
# ⚠ `readlink -s` IS NOT `realpath -s`: here it is a synonym for -q, there it
# means "do not expand symlinks". One letter, opposite meanings.
# ⚠ AGAINST `-v`, NOT AGAINST THE DEFAULT. The default is already silent, so
# `readlink -s plain` produces no output whether `-s` does anything or not —
# mutation-testing found the first version of these three green against a build
# where `-s` was ignored entirely.
expect_eq "-s silences an explicit -v"      "" "$("$BIN" readlink -v -s rlq/plain 2>&1)"
expect_eq "--silent does too"               "" "$("$BIN" readlink -v --silent rlq/plain 2>&1)"
expect_eq "-q silences an explicit -v"      "" "$("$BIN" readlink -v -q rlq/plain 2>&1)"
expect_eq "...and -v alone still speaks"    "1" \
          "$("$BIN" readlink -v rlq/plain 2>&1 | grep -c 'invalid argument')"
# ⛔ AN EXPLICIT -q BEATS -v, in either order. GNU cannot say this — its
# POSIXLY_CORRECT overrides -q, which is what ADR 0017 forbids.
expect_eq "-v -q is quiet"              "" "$("$BIN" readlink -v -q rlq/plain 2>&1)"
expect_eq "-q -v is quiet"              "" "$("$BIN" readlink -q -v rlq/plain 2>&1)"
# ⚠ AND POSIXLY_CORRECT CHANGES NOTHING HERE. ⛔ Whether it changes anything in
# GNU is VERSION-DEPENDENT, which is why the comparison is probed rather than
# asserted: coreutils **9.4 ignores it entirely** for `readlink` (its `--help`
# says `-q`/`-s` are "on by default" with no mention of the variable), while
# **9.11 honours it AND lets it override an explicit `-q`**. This box has 9.11
# and the CI runner has 9.4, so the un-probed version of this assertion was
# green here and red there. **Second time a dev-box-versus-runner coreutils
# difference has cost a release cycle** — see `check-oracles.sh`.
expect_eq "POSIXLY_CORRECT does not flip it" "" \
          "$(POSIXLY_CORRECT=1 "$BIN" readlink rlq/plain 2>&1)"
expect_eq "...nor does it override -q"       "" \
          "$(POSIXLY_CORRECT=1 "$BIN" readlink -q rlq/plain 2>&1)"
if [ -n "$(POSIXLY_CORRECT=1 readlink rlq/plain 2>&1)" ]; then
    expect_eq "...where this GNU's does"     "1" \
              "$(POSIXLY_CORRECT=1 readlink rlq/plain 2>&1 | grep -c 'Invalid argument')"
    expect_eq "...and overrides its own -q"  "1" \
              "$(POSIXLY_CORRECT=1 readlink -q rlq/plain 2>&1 | grep -c 'Invalid argument')"
else
    skip "this GNU readlink ignores POSIXLY_CORRECT (pre-9.11) — the contrast is unverified"
fi

# --- 1.6.6: the operand is shell-quoted when it needs to be ---------------
# ⛔ A NAME CONTAINING A NEWLINE USED TO SPLIT THE DIAGNOSTIC IN TWO, breaking
# architecture 001's "one write per error line" in writing. ⚠ It also made
# `kriya rm: a b: ...` unreadable — one operand or two?
_nl_name=$(printf 'a\nb')
expect_eq "a newline name stays on ONE line" "1" \
          "$("$BIN" readlink -v "rlq/$_nl_name" 2>&1 | wc -l)"
expect_eq "...quoted the way GNU quotes it"  "1" \
          "$("$BIN" readlink -v "rlq/$_nl_name" 2>&1 | grep -cF "\$'\\n'")"
expect_eq "a space forces quoting"           "1" \
          "$("$BIN" readlink -v "rlq/a b" 2>&1 | grep -c "'rlq/a b'")"
# ⭐ AND A PLAIN PATH STAYS BARE. Reusing `ls`'s quoting set would have quoted
# every path in every diagnostic, because `/` can never appear in an `ls` name
# and was therefore never in the measured set.
expect_eq "a plain path is NOT quoted"       "1" \
          "$("$BIN" readlink -v rlq/missing 2>&1 | grep -c 'rlq/missing: no such')"
expect_eq "an empty operand shows as ''"     "1" \
          "$("$BIN" readlink -v '' 2>&1 | grep -c "'': no such")"
# ⛔ `:` IS QUOTED, and it is the one byte where the diagnostic style differs
# from `ls`'s in the OTHER direction. The message is colon-delimited, so an
# unquoted `a:b` makes `kriya readlink: a:b: no such file` unparseable back into
# utility, operand and message. ⚠ `ls` leaves it bare and must keep doing so.
expect_eq "a colon in the name is quoted"    "1" \
          "$("$BIN" readlink -v 'rlq/a:b' 2>&1 | grep -c "'rlq/a:b'")"
expect_eq "...and GNU quotes it too"         "1" \
          "$(readlink -v 'rlq/a:b' 2>&1 | grep -c "'rlq/a:b'")"

# --- summary ---
TOTAL=$((PASS + FAIL))
if [ "$SKIP" -gt 0 ]; then
    printf "%d passed, %d failed, %d skipped (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$TOTAL"
else
    printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
fi
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
