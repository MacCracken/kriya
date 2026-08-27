#!/bin/sh
# smoke-hardlinks.sh — behavioural test for hard-link awareness (v1.6.0).
#
# One feature, two utilities, one shared helper (`fs_inoset_*` in
# src/lib/fs.cyr) — so one script, rather than half the cases in smoke-cp.sh
# and half in smoke-du.sh where neither half shows the shared rule.
#
#   `cp --preserve=links`  two source names on one inode become two names for
#                          ONE destination file.
#   `du`                   a file reached under two names is counted once;
#                          `-l`/`--count-links` turns that off.
#
# ⭐ THE ASSERTIONS ARE ABOUT INODE IDENTITY, NOT ABOUT WHICH NAME IS THE
# ORIGINAL. GNU walks a directory in ASCENDING INODE order (coreutils'
# `savedir(SAVEDIR_SORT_FASTREAD)`) while kriya walks in raw `getdents64`
# order, so the two can disagree about which name gets the real copy and which
# gets the link — and that is invisible in the result, because every name in
# the group ends up naming the same file either way. Asserting "dst/a is the
# master" would be asserting readdir order.

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
        printf "FAIL %s:\nexpected:\n%s\ngot:\n%s\n" "$1" "$2" "$3" >&2
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

# Number of DISTINCT inodes across the named paths. The whole feature reduces
# to this number: 1 means the group was preserved, N means it was not.
inodes() {
    stat -c '%i' "$@" | sort -u | wc -l
}

# The link count the destination reports, which must equal the group size.
nlink() {
    stat -c '%h' "$1"
}

# Compare kriya's `du` output against GNU's, sorted. ⚠ Sorted because subtree
# traversal order is not ABI-stable across filesystems, which smoke-du.sh
# already establishes; every assertion here is about WHICH lines appear and
# what they say, never about their order.
same_du() {
    name=$1
    shift
    g=$(du "$@" 2>&1 | sort)
    k=$("$BIN" du "$@" 2>&1 | sort)
    expect_eq "$name" "$g" "$k"
}

# ⛔ `du` compares st_blocks, which is not stable until writeback — the same
# reason smoke-du.sh syncs its fixtures.
mkfixtures() {
    rm -rf tree
    mkdir -p tree/x tree/y
    head -c 8192 /dev/zero > tree/x/f 2>/dev/null || printf '%08192d' 0 > tree/x/f
    ln tree/x/f tree/x/g
    ln tree/x/f tree/y/h
    echo solo > tree/other
    sync 2>/dev/null || true
}
mkfixtures

# =====================================================================
# cp --preserve=links
# =====================================================================

# --- the base case: one inode reached under three names --------------
rm -rf c1
expect_exit "cp -R --preserve=links"    0 "$BIN" cp -R --preserve=links tree c1
expect_eq "three names, one inode"      "1" "$(inodes c1/x/f c1/x/g c1/y/h)"
expect_eq "destination link count is 3" "3" "$(nlink c1/x/f)"
# ⚠ The unlinked file must NOT join the group — a dedup keyed on something
# coarser than (dev, ino) would fold it in and nothing else here would notice.
expect_eq "the unrelated file is its own inode" "2" "$(inodes c1/x/f c1/other)"
expect_eq "and its link count is 1"     "1" "$(nlink c1/other)"

# --- GNU agrees, on the same fixture ---------------------------------
rm -rf g1
cp -R --preserve=links tree g1
expect_eq "GNU: three names, one inode" "1" "$(inodes g1/x/f g1/x/g g1/y/h)"
expect_eq "GNU: link count is 3"        "3" "$(nlink g1/x/f)"

# --- ⛔ WITHOUT THE FLAG, NOTHING IS LINKED. The regression that matters
# most: link preservation must not leak into the default, where it would
# silently make two files share storage the user expects to be independent.
rm -rf c2
expect_exit "cp -R (no flag)"           0 "$BIN" cp -R tree c2
expect_eq "plain -R: three inodes"      "3" "$(inodes c2/x/f c2/x/g c2/y/h)"
rm -rf c3
expect_exit "cp -pR (mode+times only)"  0 "$BIN" cp -pR tree c3
expect_eq "-p alone does not link"      "3" "$(inodes c3/x/f c3/x/g c3/y/h)"

# --- across command-line operands, recursive and not -----------------
rm -rf c4; mkdir c4
expect_exit "cp --preserve=links A B D/" 0 "$BIN" cp --preserve=links tree/x/f tree/y/h c4/
expect_eq "operands linked to each other" "1" "$(inodes c4/f c4/h)"
rm -rf c5; mkdir c5
expect_exit "cp -R --preserve=links DIRS" 0 "$BIN" cp -R --preserve=links tree/x tree/y c5/
expect_eq "linked across directory operands" "1" "$(inodes c5/x/f c5/x/g c5/y/h)"

# --- the attribute list is a SET, and each member means only itself ---
# ⛔ `-p` USED TO BE ONE BIT meaning "mode AND timestamps", so `--preserve=mode`
# silently preserved timestamps and `--preserve=timestamps` silently preserved
# the mode. Both were accepted; neither did what it said.
#
# ⚠ The fixture's mode is 0777 ON PURPOSE. At 0741 the umask does not bite and
# an unpreserved destination comes out 0741 anyway — the first draft of this
# test asserted "the mode was not kept" against a mode that was never going to
# change, and passed for the wrong reason. 0777 under the usual 022 lands at
# 0755 when nothing preserves it, so the two cases are actually distinguishable.
#
# Every row is DIFFERENTIAL against GNU rather than an absolute: it asks the
# oracle what mode and mtime each form produces and demands the same pair.
rm -rf attr; mkdir attr
echo stamped > attr/src
chmod 0777 attr/src
touch -t 202001010000.00 attr/src

# pair <path> -> "MODE MTIME"
pair() { stat -c '%a %Y' "$1"; }

# same_preserve <name> <flag...> — one cp each, kriya and GNU, same source.
same_preserve() {
    name=$1
    shift
    rm -f attr/k attr/g
    "$BIN" cp "$@" attr/src attr/k
    cp "$@" attr/src attr/g
    expect_eq "$name" "$(pair attr/g)" "$(pair attr/k)"
}
same_preserve "--preserve=mode vs GNU"             --preserve=mode
same_preserve "--preserve=timestamps vs GNU"       --preserve=timestamps
same_preserve "--preserve=mode,timestamps vs GNU"  --preserve=mode,timestamps
same_preserve "--preserve=links vs GNU"            --preserve=links
same_preserve "bare --preserve vs GNU"             --preserve
same_preserve "-p vs GNU"                          -p
same_preserve "no preserve flag vs GNU"

# ...and spelled out, so a reader sees WHICH half each form keeps rather than
# only that kriya agrees with something.
SRC_M=$(stat -c %a attr/src)
SRC_T=$(stat -c %Y attr/src)
kept() {   # kept <flag...> -> "mode:yes|no time:yes|no"
    rm -f attr/k
    "$BIN" cp "$@" attr/src attr/k
    m=no; t=no
    [ "$(stat -c %a attr/k)" = "$SRC_M" ] && m=yes
    [ "$(stat -c %Y attr/k)" = "$SRC_T" ] && t=yes
    echo "mode:$m time:$t"
}
expect_eq "=mode keeps only the mode"        "mode:yes time:no"  "$(kept --preserve=mode)"
expect_eq "=timestamps keeps only the time"  "mode:no time:yes"  "$(kept --preserve=timestamps)"
expect_eq "=mode,timestamps keeps both"      "mode:yes time:yes" "$(kept --preserve=mode,timestamps)"
expect_eq "-p keeps both"                    "mode:yes time:yes" "$(kept -p)"
expect_eq "bare --preserve keeps both"       "mode:yes time:yes" "$(kept --preserve)"
expect_eq "=links keeps neither"             "mode:no time:no"   "$(kept --preserve=links)"

# ⚠ GNU's forms are CUMULATIVE: `-p --preserve=links` is all three.
#
# ⛔ THE FIRST VERSION OF THIS CASE PASSED WHILE THE FEATURE WAS BROKEN. It
# compared the copy's mtime against a fixture built seconds earlier, so both
# were the current second and the assertion held whether or not anything was
# preserved — while `-p --preserve=links` was in fact dropping mode and
# timestamps entirely, because the list replaced the `-p` bits instead of ORing
# onto them. The fixture is stamped in 2020 and moded 0777 so both halves can
# actually fail.
rm -rf cum; mkdir cum
echo cumulative > cum/f
ln cum/f cum/g
chmod 0777 cum/f
touch -t 202001010000.00 cum/f cum/g
CUM_M=$(stat -c %a cum/f)
CUM_T=$(stat -c %Y cum/f)
rm -rf c6
expect_exit "cp -pR --preserve=links"   0 "$BIN" cp -pR --preserve=links cum c6
expect_eq "cumulative: still links"     "1" "$(inodes c6/f c6/g)"
expect_eq "cumulative: keeps the mode"  "$CUM_M" "$(stat -c %a c6/f)"
expect_eq "cumulative: keeps the time"  "$CUM_T" "$(stat -c %Y c6/f)"
# ...and the same three, asked of GNU on the same fixture.
rm -rf g6
cp -pR --preserve=links cum g6
expect_eq "GNU cumulative: links"       "1" "$(inodes g6/f g6/g)"
expect_eq "GNU cumulative: mode"        "$CUM_M" "$(stat -c %a g6/f)"
expect_eq "GNU cumulative: time"        "$CUM_T" "$(stat -c %Y g6/f)"
# The order of the two forms must not matter.
rm -rf c6b
expect_exit "cp --preserve=links -pR"   0 "$BIN" cp --preserve=links -pR cum c6b
expect_eq "order-independent: links"    "1" "$(inodes c6b/f c6b/g)"
expect_eq "order-independent: time"     "$CUM_T" "$(stat -c %Y c6b/f)"

# --- attributes kriya does not preserve are still refused BY NAME ----
# ⛔ `ownership` and `xattr` FLIPPED FROM REFUSED TO IMPLEMENTED AT v1.6.1 —
# their own coverage lives in scripts/smoke-ownership-xattr.sh. `all` and
# `context` stay refusals: `all` implies the SELinux `context`, and a
# `--preserve=all` that quietly skipped the security label would be the same lie
# in a more dangerous place.
expect_exit "--preserve=ownership accepted" 0 "$BIN" cp --preserve=ownership attr/src attr/own
expect_exit "--preserve=xattr accepted"     0 "$BIN" cp --preserve=xattr attr/src attr/xa
expect_exit "--preserve=all refused"        2 "$BIN" cp --preserve=all attr/src attr/all
expect_exit "--preserve=context refused"    2 "$BIN" cp --preserve=context attr/src attr/ctx
expect_eq "a refused attribute copies nothing" "no" \
          "$([ -e attr/all ] && echo yes || echo no)"

# --- symlinks: hard links TO a symlink, and -L folding two symlinks ---
rm -rf sl; mkdir sl
echo target-bytes > sl/target
ln -s target sl/s1
ln sl/s1 sl/s2
rm -rf c7
expect_exit "cp -R --preserve=links (linked symlinks)" 0 "$BIN" cp -R --preserve=links sl c7
expect_eq "two names for one symlink inode" "1" "$(inodes c7/s1 c7/s2)"
expect_eq "...with link count 2"            "2" "$(nlink c7/s1)"
rm -rf g7
cp -R --preserve=links sl g7
expect_eq "GNU agrees on linked symlinks"   "1" "$(inodes g7/s1 g7/s2)"

# ⛔ UNDER -L THE LINK COUNT PROVES NOTHING. `deref/f` has st_nlink 1 and so do
# both symlinks to it, yet GNU produces one inode with three names — because
# dereferencing is what makes one file reachable by several paths. A gate on
# `st_nlink > 1` alone would silently make three copies here.
rm -rf deref; mkdir deref
echo deref-bytes > deref/f
ln -s f deref/x
ln -s f deref/y
rm -rf c8
expect_exit "cp -RL --preserve=links"    0 "$BIN" cp -RL --preserve=links deref c8
expect_eq "-L folds file and both links"  "1" "$(inodes c8/f c8/x c8/y)"
expect_eq "...into a link count of 3"     "3" "$(nlink c8/f)"
rm -rf g8
cp -RL --preserve=links deref g8
expect_eq "GNU agrees under -L"           "1" "$(inodes g8/f g8/x g8/y)"
# Non-recursive cp dereferences unconditionally (POSIX), so the same rule holds
# with no -L anywhere on the line.
rm -rf c9; mkdir c9
expect_exit "cp --preserve=links FILE SYMLINK D/" 0 "$BIN" cp --preserve=links deref/f deref/x c9/
expect_eq "non-recursive cp folds them too" "1" "$(inodes c9/f c9/x)"
# ...and without -L the symlinks are copied as symlinks, so nothing folds.
rm -rf c10
expect_exit "cp -R --preserve=links (no -L)" 0 "$BIN" cp -R --preserve=links deref c10
expect_eq "-P keeps three separate inodes"   "3" "$(inodes c10/f c10/x c10/y)"

# --- -v says the same thing for a copy and for a link ----------------
rm -rf c11; mkdir c11
VOUT=$("$BIN" cp -v --preserve=links tree/x/f tree/x/g c11/ 2>&1)
GOUT=$(rm -rf g11; mkdir g11; cp -v --preserve=links tree/x/f tree/x/g g11/ 2>&1 | sed 's/g11/c11/')
expect_eq "-v output matches GNU"        "$GOUT" "$VOUT"

# --- ⚠ mv rides on cp's preserve path and must still keep the mtime ---
# The bitmask split changed the value mv passes; a bare 1 now means "mode only".
rm -rf mvsrc; mkdir mvsrc
echo moved > mvsrc/f
touch -t 201901010000.00 mvsrc/f
MV_T=$(stat -c %Y mvsrc/f)
expect_exit "mv still works"             0 "$BIN" mv mvsrc/f mvsrc/g
expect_eq "mv preserved the mtime"       "$MV_T" "$(stat -c %Y mvsrc/g)"

# =====================================================================
# du — dedup by (dev, ino)
# =====================================================================

mkfixtures

# --- ⛔ A REPEAT PRINTS NO LINE AT ALL, not a zero line. Under -a the second
# and third names are absent from the output entirely.
same_du "du -a on a hardlink tree"       -a tree
same_du "du on a hardlink tree"          tree
same_du "du -s"                          -s tree
same_du "du -c across subtrees"          -c tree/x tree/y
same_du "du -S separate-dirs"            -S tree
same_du "du -a -d 1"                     -a -d 1 tree
same_du "du -h"                          -h tree
same_du "du -b apparent size"            -b tree

# --- -l / --count-links restores the pre-1.6.0 accounting ------------
same_du "du -l -a"                       -l -a tree
same_du "du --count-links -a"            --count-links -a tree
same_du "du -l"                          -l tree
same_du "du -sl"                         -sl tree
# ⚠ Clustered with another short, which is how anyone actually types it.
same_du "du -al clustered"               -al tree
expect_eq "-l really changes the total" "no" \
          "$([ "$("$BIN" du -s tree | cut -f1)" = "$("$BIN" du -sl tree | cut -f1)" ] && echo yes || echo no)"

# --- across operands, in both orders ---------------------------------
same_du "du DIR DIR (same operand twice)" tree tree
same_du "du X Y (link in each)"           tree/x tree/y
same_du "du Y X (order reversed)"         tree/y tree/x
same_du "du F G (two names, explicit)"    tree/x/f tree/x/g
same_du "du -c F G"                       -c tree/x/f tree/x/g
same_du "du FILE DIR (file counted first)" tree/other tree

# --- ⚠ ONE RECORDED DIVERGENCE, asserted so it cannot drift silently.
# An operand naming a single-link file that an EARLIER operand's walk already
# counted: GNU omits it, kriya prints it. kriya tracks operands and multiply-
# linked files rather than every file it counts, because GNU's every-file set is
# a sparse structure costing ~1 bit per file and kriya's is a 32-byte hash —
# 200,000 files measured at 20 KB for GNU against 6 MB here. This asserts
# kriya's OWN answer; the day it gains the sparse form, this case flips to
# `same_du` and the line below is what says so out loud.
expect_eq "recorded divergence: du DIR DIR/file lists the file" "yes" \
          "$("$BIN" du tree tree/other 2>/dev/null | grep -c 'tree/other' >/dev/null && echo yes || echo no)"
expect_eq "...while GNU omits it"        "0" "$(du tree tree/other 2>/dev/null | grep -c 'tree/other$')"

# --- -L: dereferencing makes link count useless, same as for cp -------
rm -rf dtree; mkdir dtree
head -c 8192 /dev/zero > dtree/f 2>/dev/null || printf '%08192d' 0 > dtree/f
ln -s f dtree/s1
ln -s f dtree/s2
sync 2>/dev/null || true
same_du "du -a (symlinks are their own size)" -a dtree
same_du "du -aL (all three fold to one)"      -aL dtree
same_du "du -aL -l (folding turned off)"      -aL -l dtree
same_du "du -sL"                              -sL dtree

# --- ⛔ A SYMLINK CYCLE UNDER -L USED TO DUMP CORE. Nothing remembered which
# directories the walk had entered, so `-L` recursed until the stack died. The
# `-l` form is the one that proves cycle detection is NOT part of the dedup:
# turning the dedup off must not bring the crash back.
rm -rf cyc; mkdir -p cyc/a
echo cycle-bytes > cyc/a/f
ln -s .. cyc/a/up
sync 2>/dev/null || true
expect_exit "du -L over a cycle terminates"  0 "$BIN" du -L cyc
expect_exit "du -lL over a cycle terminates" 0 "$BIN" du -lL cyc
same_du "du -L over a cycle"                 -L cyc
same_du "du -lL over a cycle"                -lL cyc
same_du "du -aL over a cycle"                -aL cyc
# A cycle two levels up, so the detection is not just "the parent".
rm -rf cyc2; mkdir -p cyc2/x/y
echo deeper > cyc2/x/y/g
ln -s ../.. cyc2/x/y/back
sync 2>/dev/null || true
expect_exit "du -L over a two-level cycle"   0 "$BIN" du -L cyc2
same_du "du -L over a two-level cycle"       -L cyc2

# =====================================================================
# The defects an adversarial pass found in the first cut of this feature,
# and the two older ones it found next to them. Every case below reproduced
# before it was fixed.
# =====================================================================

# --- ⛔ TWO OPERANDS THAT LAND ON ONE DESTINATION NAME ----------------
# `cp -f --preserve=links a/f b/f dst/` resolves both to `dst/f`. The link
# path unlinked `dst/f` and then tried to link it to ITSELF, so the file — and
# any file that was already there — was DESTROYED and cp exited 1 with nothing
# on disk. GNU refuses the second operand and keeps the first.
#
# ⚠ The guard is NOT part of `--preserve=links`: plain `cp -f a/f b/f dst/`
# silently clobbered too, for as long as cp has existed here. It is
# unconditional now, which is what makes the link path safe rather than a
# special case bolted onto it.
rm -rf jc; mkdir -p jc/a jc/b jc/dk jc/dg
echo IMPORTANT > jc/a/f
ln jc/a/f jc/b/f
"$BIN" cp -f --preserve=links jc/a/f jc/b/f jc/dk/ 2>/dev/null || true
cp -f --preserve=links jc/a/f jc/b/f jc/dg/ 2>/dev/null || true
expect_eq "just-created: the file survives"    "IMPORTANT" "$(cat jc/dk/f 2>/dev/null)"
expect_eq "just-created: matches GNU"          "$(cat jc/dg/f 2>/dev/null)" "$(cat jc/dk/f 2>/dev/null)"
expect_eq "just-created: says so"              "1" \
          "$("$BIN" cp -f --preserve=links jc/a/f jc/b/f jc/dk/ 2>&1 | grep -c 'will not overwrite just-created')"
expect_exit "just-created: exits 1"            1 "$BIN" cp -f --preserve=links jc/a/f jc/b/f jc/dk/
# The same without --preserve=links — the older, plain-copy half of it.
rm -rf jp; mkdir -p jp/a jp/b jp/dk jp/dg
echo FIRST  > jp/a/f
echo SECOND > jp/b/f
"$BIN" cp -f jp/a/f jp/b/f jp/dk/ 2>/dev/null || true
cp -f jp/a/f jp/b/f jp/dg/ 2>/dev/null || true
expect_eq "plain copy keeps the first operand" "FIRST" "$(cat jp/dk/f 2>/dev/null)"
expect_eq "...and matches GNU"                 "$(cat jp/dg/f)" "$(cat jp/dk/f)"
# ⛔ And the stale-master shape: a third operand sharing an inode with the FIRST
# must not link to a destination path a SECOND operand has since overwritten.
rm -rf sm; mkdir -p sm/x sm/y sm/z sm/dk sm/dg
echo XF > sm/x/f
ln sm/x/f sm/z/g
echo YF > sm/y/f
"$BIN" cp -f --preserve=links sm/x/f sm/y/f sm/z/g sm/dk/ 2>/dev/null || true
cp -f --preserve=links sm/x/f sm/y/f sm/z/g sm/dg/ 2>/dev/null || true
expect_eq "stale master: g holds the right bytes" "XF" "$(cat sm/dk/g 2>/dev/null)"
expect_eq "stale master: f untouched"             "XF" "$(cat sm/dk/f 2>/dev/null)"
expect_eq "stale master: matches GNU"             "$(cat sm/dg/f)-$(cat sm/dg/g)" "$(cat sm/dk/f)-$(cat sm/dk/g)"
# The recursive spelling, where GNU merges the two trees successfully.
rm -rf rs; mkdir -p rs/p/sub rs/q/sub rs/dk rs/dg
echo PAYLOAD > rs/p/sub/f
ln rs/p/sub/f rs/q/sub/f
"$BIN" cp -Rf --preserve=links rs/p/sub rs/q/sub rs/dk/ 2>/dev/null || true
cp -Rf --preserve=links rs/p/sub rs/q/sub rs/dg/ 2>/dev/null || true
expect_eq "recursive merge keeps the payload"  "PAYLOAD" "$(cat rs/dk/sub/f 2>/dev/null)"
expect_eq "...matching GNU"                    "$(cat rs/dg/sub/f)" "$(cat rs/dk/sub/f)"

# --- ⛔ `cp -RL` OVER A SYMLINK CYCLE ---------------------------------
# Three commands to reproduce, and cp wrote a real directory at every level of
# `dir/up/dir/up/...` until the stack died, leaving the half-built tree behind.
# The in-tree `cp -r dir dir/backup` guard could not see it: that one is a
# textual prefix test, and this cycle is made of a symlink.
rm -rf cyc; mkdir -p cyc/src/a
echo cyc-bytes > cyc/src/a/f
ln -s .. cyc/src/a/up
expect_exit "cp -RL over a cycle terminates" 1 "$BIN" cp -RL cyc/src cyc/k
expect_eq "cp -RL names the cyclic LINK"     "1" \
          "$("$BIN" cp -RL cyc/src cyc/k2 2>&1 | grep -c "cannot copy cyclic symbolic link 'cyc/src/a/up'")"
expect_eq "...and GNU says the same"         "1" \
          "$(cp -RL cyc/src cyc/g 2>&1 | grep -c "cannot copy cyclic symbolic link 'cyc/src/a/up'")"
expect_eq "the rest of the tree is copied"   "cyc-bytes" "$(cat cyc/k/a/f 2>/dev/null)"
expect_eq "...and the tree matches GNU"      \
          "$(cd cyc/g && find . | sort)" "$(cd cyc/k && find . | sort)"
# ⚠ Without -L the symlink is copied AS a symlink and nothing cycles.
expect_exit "cp -R (no -L) is unaffected"    0 "$BIN" cp -R cyc/src cyc/k3
expect_eq "...and the link is preserved"     "symbolic link" "$(stat -c %F cyc/k3/a/up)"
# A cycle two levels up, so the check is not merely "the immediate parent".
rm -rf cy2; mkdir -p cy2/s/x/y
echo deep > cy2/s/x/y/f
ln -s ../../ cy2/s/x/y/back
expect_exit "cp -RL over a two-level cycle"  1 "$BIN" cp -RL cy2/s cy2/k
# ⚠ `|| true` is load-bearing: `set -e` reaches inside `$( )`, so the failing
# `cp` would abandon the substitution and the expected value would be empty —
# an assertion that compares nothing to something and calls it a difference.
expect_eq "...and the tree still matches GNU" \
          "$( { cp -RL cy2/s cy2/g 2>/dev/null || true; } ; cd cy2/g && find . | sort)" \
          "$(cd cy2/k && find . | sort)"

# --- ⛔ THE OTHER HALF OF THE `-L` RUNAWAY: ESCAPING INTO THE DESTINATION ---
# A symlink out of the source tree into a directory that CONTAINS the
# destination walks back down into the destination and copies it into itself.
# ⚠ GNU does not close this one: measured, it wrote a 1,536-entry
# `dst/up/dst/up/…` tree and stopped only when the path exceeded the filesystem
# limit, exiting 0. kriya wrote 11,635 entries and dumped core. Refusing to
# descend into the destination is a deliberate deviation from the oracle
# (ADR 0012), in the direction the in-tree `cp -r dir dir/backup` guard already
# takes — so this case asserts kriya's own answer, not GNU's.
rm -rf esc; mkdir -p esc/t
echo esc-bytes > esc/t/f
ln -s .. esc/t/up
( cd esc && "$BIN" cp -RL t kdst >/dev/null 2>&1 ) || true
expect_eq "escape-to-destination terminates"  "3" "$(find esc/kdst | wc -l | tr -d ' ')"
expect_eq "...and the real content is copied" "esc-bytes" "$(cat esc/kdst/f 2>/dev/null)"
expect_eq "...and it says why"                "1" \
          "$( cd esc && "$BIN" cp -RL t kdst2 2>&1 | grep -c 'not descending into the destination' )"
# ⚠ And the ordinary -L copy is untouched by the guard.
rm -rf lok; mkdir -p lok/src/sub
echo la > lok/src/f
echo lb > lok/src/sub/g
ln -s ../f lok/src/sub/link
expect_exit "an ordinary -L copy still works" 0 "$BIN" cp -RL lok/src lok/kk
cp -RL lok/src lok/gg
expect_eq "...and matches GNU's tree"         "$(cd lok/gg && find . | sort)" "$(cd lok/kk && find . | sort)"
expect_eq "...and the symlink was followed"   "regular file" "$(stat -c %F lok/kk/sub/link)"

# --- ⛔ `du -L` CYCLE DETECTION IS AN ANCESTOR TEST, NOT A VISITED SET ---
# Two symlinks pointing at one directory are NOT a loop. A permanent
# visited-set stops the recursion and also silently drops the second and third
# path, which `-l` is supposed to make visible: GNU counts 12 blocks across
# `real`, `link1` and `link2` where the set answered 4.
rm -rf anc; mkdir -p anc/real
head -c 4096 /dev/zero > anc/real/g 2>/dev/null || printf '%04096d' 0 > anc/real/g
ln -s real anc/link1
ln -s real anc/link2
sync 2>/dev/null || true
same_du "two symlinks to one dir, -aL"   -aL anc
same_du "...with -l, all three count"    -alL anc
same_du "...and the -c total"            -clL anc
same_du "...summarised"                  -sL anc

# --- ⛔ A NESTED DIRECTORY OPERAND WAS WALKED AND CHARGED TWICE --------
# The insert rule guarded the link-count test with `is_dir == 0`, which reads
# correctly and left directories out of the table entirely. No hard link is
# needed to reach it.
rm -rf nest; mkdir -p nest/a/b/c
head -c 8192 /dev/zero > nest/a/b/c/f 2>/dev/null || printf '%08192d' 0 > nest/a/b/c/f
head -c 4096 /dev/zero > nest/a/b/g 2>/dev/null || printf '%04096d' 0 > nest/a/b/g
head -c 2048 /dev/zero > nest/a/h   2>/dev/null || printf '%02048d' 0 > nest/a/h
sync 2>/dev/null || true
same_du "nested directory operands"      -c nest/a nest/a/b
same_du "...without -c"                  nest/a nest/a/b
same_du "...with -a"                     -a nest/a nest/a/b
same_du "...reversed"                    -c nest/a/b nest/a

# --- ⛔ `du -cS` REPORTED A TOTAL NO LINE ADDED UP TO ------------------
# `-S` strips subdirectories out of a directory's own line; the grand total was
# summing those stripped values instead of the tree. Pre-existing.
same_du "du -cS"                         -cS nest/a
same_du "du -acS"                        -acS nest/a
same_du "du -clS"                        -clS nest/a
expect_eq "the -cS total equals the tree total" \
          "$("$BIN" du -sc nest/a | tail -1 | cut -f1)" "$("$BIN" du -cS nest/a | tail -1 | cut -f1)"

# --- ⛔ A CHILD WHOSE STAT FAILED WAS DROPPED IN SILENCE ---------------
# `-L` turns a broken symlink into ENOENT and a self-referential one into
# ELOOP, where the default `-P` lstat succeeds on both. du reported neither and
# exited 0 over a tree it could not read.
rm -rf bad; mkdir bad
echo hi > bad/f
ln -s nowhere  bad/broken
ln -s selfloop bad/selfloop
sync 2>/dev/null || true
expect_exit "du -L over unreadable children exits 1" 1 "$BIN" du -L bad
expect_eq "...and names both of them" "2" \
          "$("$BIN" du -L bad 2>&1 | grep -c 'cannot access')"
expect_exit "GNU exits 1 too"                       1 du -L bad
expect_eq "the readable part is still reported"     "1" \
          "$("$BIN" du -L bad 2>/dev/null | grep -c 'bad$')"

# --- ⛔ MORE THAN 512 OPERANDS SMASHED THE HEAP -----------------------
# `du *` in a directory of more than 512 entries walked off the end of a fixed
# array. A glob, not an exotic input. Pre-existing.
rm -rf wide; mkdir wide
i=0
while [ "$i" -lt 600 ]; do echo x > "wide/f$i"; i=$((i + 1)); done
sync 2>/dev/null || true
expect_exit "600 operands do not crash"  0 sh -c "cd '$WORK' && '$BIN' du wide/f* >/dev/null 2>&1"
expect_eq "600 operands produce 600 lines" "600" \
          "$(cd "$WORK" && "$BIN" du wide/f* 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "...same as GNU"                 "$(cd "$WORK" && du wide/f* 2>/dev/null | wc -l | tr -d ' ')" \
          "$(cd "$WORK" && "$BIN" du wide/f* 2>/dev/null | wc -l | tr -d ' ')"

# --- the introspection interface knows about the new flag ------------
expect_eq "-l is advertised in --help" "1" \
          "$("$BIN" du --help 2>&1 | grep -c -- '--count-links')"
expect_eq "-l is advertised in --help=json" "1" \
          "$("$BIN" du --help=json 2>&1 | grep -c '"count-links"')"
expect_eq "cp --help names the extra attributes" "1" \
          "$("$BIN" cp --help=json 2>&1 | grep -c -- '=links, =xattr for more')"

printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
