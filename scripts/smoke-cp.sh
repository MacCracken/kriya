#!/bin/sh
# smoke-cp.sh — behavioural test for `kriya cp` (non-recursive ship).
#
# Covers single-file copy, multi-into-dir, -f / -i / -p / -v, self-copy
# refusal, directory-source-without-R error. Recursive cp + the ADR
# 0003 symlink-policy matrix lands in a separate commit on top of
# src/lib/fs.cyr.

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
# ⚠ `set -e` is on and this was a bare command, so THREE host dependencies were
# each fatal to the whole script rather than to one assertion: /dev/urandom
# existing (absent in a minimal chroot or an unpopulated initramfs — precisely
# the environments an AGNOS-targeted toolset runs in), `dd` existing, and `dd`
# accepting `status=none` (a GNU extension busybox's dd rejects). Random bytes
# are the better fixture where they are available, so probe rather than assume,
# and fall back to a deterministic payload the shell alone can produce.
gen_payload() {   # gen_payload <path> <kib>
    if [ -r /dev/urandom ] && head -c 1024 /dev/urandom >/dev/null 2>&1; then
        head -c $(( $2 * 1024 )) /dev/urandom > "$1"
    else
        : > "$1"
        _i=0
        while [ "$_i" -lt "$2" ]; do
            printf '%01024d' "$_i" >> "$1"
            _i=$((_i + 1))
        done
    fi
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
    # ⛔ stdin FROM /dev/null, not inherited. Without this the three `-i on
    # pipe` assertions below tested whatever stdin the SUITE was launched
    # with: run from an interactive terminal, `-i` sees a tty, PROMPTS, and
    # hangs forever — the worst failure shape in CI, because it burns the
    # whole job timeout instead of failing. Verified by running this script
    # under a pty: it blocked until killed.
    "$@" </dev/null >/dev/null 2>&1 || rc=$?
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

# --- happy path ---
echo "hello world" > src.txt
expect_exit "cp basic"               0 "$BIN" cp src.txt dst.txt
expect_file_match "byte-identical"   src.txt dst.txt

# Larger file to exercise the multi-block loop (>64KiB).
gen_payload big.bin 200
expect_exit "cp 200KB"               0 "$BIN" cp big.bin big.copy
expect_file_match "200KB match"      big.bin big.copy

# --- existing dest gating ---
expect_exit "exists without -f"      1 "$BIN" cp src.txt dst.txt
expect_exit "exists with -f"         0 "$BIN" cp -f src.txt dst.txt
expect_file_match "still match"      src.txt dst.txt

# -i on non-tty is exit 2 (usage error per ADR 0002).
expect_exit "-i on pipe"             2 "$BIN" cp -i src.txt dst.txt

# --- multi-into-dir ---
mkdir into
echo a > a.txt && echo b > b.txt
expect_exit "cp a b into/"           0 "$BIN" cp a.txt b.txt into/
expect_file_match "into/a.txt"       a.txt into/a.txt
expect_file_match "into/b.txt"       b.txt into/b.txt

# Multi-source with non-dir final operand — usage error.
expect_exit "multi non-dir"          2 "$BIN" cp a.txt b.txt notadir

# --- -p preserve mode + times ---
# Order matters: write content first, then chmod/touch -t. A trailing
# `>> file` would re-bump mtime to "now".
echo "stamped" > oldtime.txt
chmod 0640 oldtime.txt
touch -t 202001010000.00 oldtime.txt
SRC_M=$(stat -c %a oldtime.txt)
SRC_T=$(stat -c %Y oldtime.txt)
expect_exit "cp -p"                  0 "$BIN" cp -p oldtime.txt oldtime.copy
DST_M=$(stat -c %a oldtime.copy)
DST_T=$(stat -c %Y oldtime.copy)
expect_eq "preserved mode"           "$SRC_M" "$DST_M"
expect_eq "preserved mtime"          "$SRC_T" "$DST_T"

# Without -p, mtime should be "now" — much greater than the 2020
# timestamp the source carries.
expect_exit "cp without -p"          0 "$BIN" cp -f oldtime.txt fresh.copy
FRESH_T=$(stat -c %Y fresh.copy)
if [ "$FRESH_T" -gt "$SRC_T" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL non-p mtime should be current ($FRESH_T vs $SRC_T)" >&2; fi

# --- -v verbose ---
out=$("$BIN" cp -v -f src.txt v.txt 2>&1)
expected="'src.txt' -> 'v.txt'"
expect_eq "verbose output" "$expected" "$out"

# --- errors ---
expect_exit "missing source"         1 "$BIN" cp gone there
expect_exit "no operands"            2 "$BIN" cp
expect_exit "one operand"            2 "$BIN" cp onlyone

# Directory source without -R: exit 1, "is a directory".
mkdir somedir
expect_exit "dir source w/o -R"      1 "$BIN" cp somedir other

# Self-copy refused.
expect_exit "self-copy"              1 "$BIN" cp src.txt src.txt

# Partial failure: one bad + one good — exit 1, good copy still made.
expect_exit "partial fail"           1 "$BIN" cp missing.src good.src into/
echo "good_content" > good.src
expect_exit "partial fail (after)"   1 "$BIN" cp missing.src good.src into/
expect_file_match "into/good.src"    good.src into/good.src

# --- 1.6.5: the backup matrix, shared with mv and ln (ADR 0017) -----------
# ⛔ EVERY CELL WAS MEASURED AGAINST GNU, not inferred. The control is a matrix:
# `existing` asks ONE question — does any dst.~N~ exist? — and numbering is
# HIGHEST + 1, not first gap. Both are counter-intuitive and both are asserted.
#
# ⚠ The variables are unset for every case that means to measure the DEFAULT. A
# value inherited from the runner's shell would silently rewrite every result.
BK="env -u VERSION_CONTROL -u SIMPLE_BACKUP_SUFFIX"

bk_mk() {   # bk_mk [extra files...]
    rm -rf bk; mkdir bk
    echo NEW > bk/src; echo OLD > bk/dst
    for _f in "$@"; do echo B > "bk/$_f"; done
}
bk_show() { ls bk | grep -v '^src$' | tr '\n' ' '; }
# ⚠ TWO HELPERS RATHER THAN A `--` SENTINEL. The first version took
# `[--pre f1 f2] -- <flags>` and, with no `--pre`, passed the bare `--` straight
# through to `cp` — which turned every flag after it into an OPERAND, so twelve
# cases ran a plain copy and reported the backup missing.
bk_case() {   # bk_case <name> <expected> <flag...>
    _n=$1; _want=$2; shift 2
    bk_mk
    ( cd bk && $BK "$BIN" cp "$@" src dst 2>/dev/null ) || true
    expect_eq "$_n" "$_want" "$(bk_show)"
}
bk_case_pre() {   # bk_case_pre <name> <expected> <"pre files"> <flag...>
    _n=$1; _want=$2; _pre=$3; shift 3
    # shellcheck disable=SC2086
    bk_mk $_pre
    ( cd bk && $BK "$BIN" cp "$@" src dst 2>/dev/null ) || true
    expect_eq "$_n" "$_want" "$(bk_show)"
}

bk_case "-b with nothing else"        "dst dst~ " -b
bk_case "--backup=numbered"           "dst dst.~1~ " --backup=numbered
bk_case "--backup=t is numbered"      "dst dst.~1~ " --backup=t
bk_case "--backup=existing"           "dst dst~ " --backup=existing
bk_case "--backup=nil is existing"    "dst dst~ " --backup=nil
bk_case "--backup=simple"             "dst dst~ " --backup=simple
bk_case "--backup=never is simple"    "dst dst~ " --backup=never
bk_case "--backup=none makes none"    "dst " --backup=none -f
bk_case "--backup=off makes none"     "dst " --backup=off -f

# ⛔ `existing` ASKS ABOUT NUMBERED BACKUPS ONLY. With `dst~` present and no
# numbered one it stays simple; with `dst.~1~` present it goes numbered — even
# when `dst~` is there too.
bk_case_pre "existing + dst~ stays simple" "dst dst~ " "dst~" -b
bk_case_pre "existing + dst.~1~ goes numbered" "dst dst.~1~ dst.~2~ " "dst.~1~" -b
bk_case_pre "existing + both goes numbered" "dst dst.~1~ dst.~2~ dst~ " "dst~ dst.~1~" -b
# ⛔ HIGHEST + 1, NOT FIRST GAP. With ~1~ and ~3~ present GNU writes ~4~; a
# first-gap implementation would write ~2~ and silently reuse a visible slot.
bk_case_pre "numbering skips the gap" "dst dst.~1~ dst.~3~ dst.~4~ " "dst.~1~ dst.~3~" -b
bk_case_pre "simple clobbers its own" "dst dst~ " "dst~" --backup=simple

# ⚠ THE SUFFIX ONLY EVER APPLIES TO A SIMPLE BACKUP.
bk_case "-S sets the simple suffix"   "dst dst.bak " -S .bak
bk_case "--suffix= does too"          "dst dst.bak " --suffix=.bak
bk_case "-S implies -b"               "dst dst.bak " -S .bak
bk_case "numbered ignores -S"         "dst dst.~1~ " --backup=numbered -S .bak
bk_case "an empty -S falls back to ~" "dst dst~ " -b -S ''

# ⛔ NO DESTINATION MEANS NO BACKUP — there is nothing to move aside.
rm -rf bk; mkdir bk; echo NEW > bk/src
( cd bk && $BK "$BIN" cp -b src dst 2>/dev/null ) || true
expect_eq "no destination, no backup file" "dst src " "$(ls bk | tr '\n' ' ')"

# ⛔ THE BACKUP IS A RENAME, NOT A COPY. Measured by inode against GNU: the old
# destination's inode is what ends up at the backup name, so a hard link to it
# follows the BACKUP and the new destination is a fresh inode. A copy-based
# implementation passes every name assertion above and fails this one.
bk_mk
_ino_before=$(stat -c %i bk/dst)
( cd bk && $BK "$BIN" cp -b src dst 2>/dev/null ) || true
expect_eq "the backup carries the old inode" "$_ino_before" "$(stat -c %i bk/dst~)"
# ⚠ AND ITS CONTENT, which the inode alone does not pin. A hard link would give
# the backup the same inode AND then be truncated by the copy's O_TRUNC, leaving
# both names holding the NEW bytes — every name assertion above still green.
expect_eq "the backup holds the OLD bytes" "OLD" "$(cat bk/dst~)"
expect_eq "...and the destination the new" "NEW" "$(cat bk/dst)"
# ⚠ And they are now separate files: writing one must not change the other.
echo CHANGED > bk/dst
expect_eq "the backup is independent of the destination" "OLD" "$(cat bk/dst~)"

# ⭐ `-b` NEEDS NO `-f`. kriya refuses a silent overwrite without -f, and a
# backup is not a silent overwrite — the old contents survive under a new name.
# Without this the flag would be useless on its own.
bk_mk
rc=0; ( cd bk && $BK "$BIN" cp -b src dst >/dev/null 2>&1 ) || rc=$?
expect_eq "-b alone is allowed to replace" "0" "$rc"
bk_mk
rc=0; ( cd bk && $BK "$BIN" cp src dst >/dev/null 2>&1 ) || rc=$?
expect_eq "...while a plain overwrite still needs -f" "1" "$rc"
# ⚠ And `--backup=none` is NOT a backup, so it does not grant the replacement.
bk_mk
rc=0; ( cd bk && $BK "$BIN" cp --backup=none src dst >/dev/null 2>&1 ) || rc=$?
expect_eq "--backup=none does not grant it" "1" "$rc"

# ⛔ A DANGLING SYMLINK DESTINATION IS NOT AN ABSENT ONE. `k_stat` follows, so a
# link pointing at nothing read as "no destination" and the copy created the
# link's TARGET — measured before the fix: `cp -f src dst` with `dst -> nowhere`
# exited 0 and produced a file called `nowhere`, which the caller never named.
# GNU refuses. ⭐ `-b` rescues it in both, by renaming the dangling link aside.
rm -rf dang; mkdir dang; echo SRC > dang/src; ln -s nowhere dang/dst
rc=0; ( cd dang && $BK "$BIN" cp -f src dst >/dev/null 2>&1 ) || rc=$?
expect_eq "cp -f refuses a dangling symlink dest" "1" "$rc"
expect_eq "...and writes nothing through it" "dst src " "$(ls -A dang | tr '\n' ' ')"
# ⚠ The GNU side needs its own fixture — the kriya run above already refused,
# but a subshell that only `cd`s and runs cannot report a code the caller reads
# when `set -e` is in force. Rebuild and measure it on its own.
rm -rf dang2; mkdir dang2; echo SRC > dang2/src; ln -s nowhere dang2/dst
_grc=0
( cd dang2 && env -u VERSION_CONTROL -u SIMPLE_BACKUP_SUFFIX cp -f src dst >/dev/null 2>&1 ) || _grc=$?
expect_eq "...with GNU's exit code" "1" "$_grc"
rm -rf dang; mkdir dang; echo SRC > dang/src; ln -s nowhere dang/dst
rc=0; ( cd dang && $BK "$BIN" cp -b src dst >/dev/null 2>&1 ) || rc=$?
expect_eq "-b rescues it by renaming the link aside" "0" "$rc"
expect_eq "...leaving the link at the backup name" "dst dst~ src " "$(ls -A dang | tr '\n' ' ')"

# --- ADR 0017: the two variables, and the deliberate divergences ----------
# ⭐ HONOURED, because they are INERT without -b/-S — that is the property that
# separates them from POSIXLY_CORRECT and QUOTING_STYLE, which kriya declines.
bk_mk; ( cd bk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=numbered "$BIN" cp -b src dst 2>/dev/null )
expect_eq "\$VERSION_CONTROL selects the style" "dst dst.~1~ " "$(bk_show)"
bk_mk; ( cd bk && env -u VERSION_CONTROL SIMPLE_BACKUP_SUFFIX=.bak "$BIN" cp -b src dst 2>/dev/null )
expect_eq "\$SIMPLE_BACKUP_SUFFIX sets the suffix" "dst dst.bak " "$(bk_show)"
# ⛔ INERT WITHOUT THE FLAG. This is the assertion ADR 0017 turns on.
bk_mk; ( cd bk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=numbered "$BIN" cp -f src dst 2>/dev/null )
expect_eq "\$VERSION_CONTROL alone makes no backup" "dst " "$(bk_show)"
bk_mk; ( cd bk && env -u VERSION_CONTROL SIMPLE_BACKUP_SUFFIX=.bak "$BIN" cp -f src dst 2>/dev/null )
expect_eq "\$SIMPLE_BACKUP_SUFFIX alone makes none" "dst " "$(bk_show)"
# ⚠ An empty value is an unset one.
bk_mk; ( cd bk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL= "$BIN" cp -b src dst 2>/dev/null )
expect_eq "an empty \$VERSION_CONTROL is unset" "dst dst~ " "$(bk_show)"
# ⭐ THE COMMAND LINE ALWAYS WINS, in both directions.
bk_mk; ( cd bk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=numbered "$BIN" cp --backup=simple src dst 2>/dev/null )
expect_eq "--backup beats \$VERSION_CONTROL" "dst dst~ " "$(bk_show)"
bk_mk; ( cd bk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=simple "$BIN" cp --backup=numbered src dst 2>/dev/null )
expect_eq "...and the other way round" "dst dst.~1~ " "$(bk_show)"
bk_mk; ( cd bk && env -u VERSION_CONTROL SIMPLE_BACKUP_SUFFIX=.bak "$BIN" cp -b -S .x src dst 2>/dev/null )
expect_eq "-S beats \$SIMPLE_BACKUP_SUFFIX" "dst dst.x " "$(bk_show)"

# ⚠ DELIBERATE DIVERGENCES, asserted so they cannot drift into accidents.
# GNU exits 1 for a bad control; ADR 0008 makes every kriya usage error 2.
expect_exit "a bad --backup value is a usage error" 2 "$BIN" cp --backup=bogus src dst
rc=0; ( cd bk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=bogus "$BIN" cp -b src dst >/dev/null 2>&1 ) || rc=$?
expect_eq "...and so is a bad \$VERSION_CONTROL" "2" "$rc"
# ⛔ NO PREFIX MATCHING (ADR 0002). GNU takes `--backup=num` and rejects `n` as
# ambiguous; kriya takes the eight exact spellings and nothing else.
expect_exit "an abbreviation is not a control name" 2 "$BIN" cp --backup=num src dst
rc=0; ( cd bk && env -u SIMPLE_BACKUP_SUFFIX VERSION_CONTROL=numb "$BIN" cp -b src dst >/dev/null 2>&1 ) || rc=$?
expect_eq "...in the variable either" "2" "$rc"

# --- 1.6.9: the ownership window on a regular file ---------------------------
#
# ⛔ UNTIL THE `fchown` LANDS, THE DESTINATION IS OWNED BY WHOEVER RAN `cp`. So a
# 0777 source copied with `-p` used to spend its entire write group- and
# other-readable under an owner it is not supposed to end up with. GNU creates
# the file with the group and other triads stripped and chmods up at the end.
#
# ⚠ MEASURED, and the condition is narrower than it looks — polling `stat`
# against a 300 MB copy at umask 000 from a source at 0777:
#
#     cp big out                       during 0777   final 0777
#     cp -p big out                    during 0700   final 0777
#     cp --preserve=mode big out       during 0777   final 0777
#     cp --preserve=ownership big out  during 0700   final 0777
#
# The withhold is for OWNERSHIP and for nothing else.
#
# ⚠ THE ASSERTIONS BELOW ARE ON THE FINAL MODE, NOT ON THE WINDOW. The window is
# a race by construction and any test of it is timing-dependent; the final mode
# is not, and it is what a withhold-without-a-restore breaks — which is the
# realistic way to get this wrong. A `--preserve=ownership` copy that ends at
# 0700 instead of 0777 is exactly that bug, and this goes red on it.
cpw_clean() { chmod -R u+rwX cpw 2>/dev/null || true; rm -rf cpw; }
cpw_case() {
    _n=$1; _um=$2; _sm=$3; shift 3
    cpw_clean; mkdir cpw; printf 'contents\n' > cpw/src; chmod "$_sm" cpw/src
    _grc=0; ( cd cpw && umask "$_um" && cp    "$@" src g >/dev/null 2>&1 ) || _grc=$?
    _krc=0; ( cd cpw && umask "$_um" && "$BIN" cp "$@" src k >/dev/null 2>&1 ) || _krc=$?
    expect_eq "$_n" "$(stat -c %a cpw/g 2>/dev/null || echo ABSENT)|$_grc" \
                    "$(stat -c %a cpw/k 2>/dev/null || echo ABSENT)|$_krc"
    cpw_clean
}
for _um in 022 077 000; do
    for _sm in 777 755 644 600 400; do
        cpw_case "cp --preserve=ownership umask=$_um src=$_sm" "$_um" "$_sm" --preserve=ownership
        cpw_case "cp -p umask=$_um src=$_sm"                   "$_um" "$_sm" -p
        cpw_case "cp plain umask=$_um src=$_sm"                "$_um" "$_sm"
    done
done
# ⚠ A source with NO owner-write is the shape that catches a withhold which
# forgets that 0700 is a floor and not a target.
cpw_case "cp --preserve=ownership of a 0444 source" 022 444 --preserve=ownership
cpw_case "cp -p of a 0444 source"                   022 444 -p
cpw_case "cp -p of a 0000 source"                   022 000 -p

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
