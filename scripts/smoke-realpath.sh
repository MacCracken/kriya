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

# --- default mode is -E, and these four assertions used to say otherwise ------
# ⛔ THE HEADING HERE READ "default mode is -e" AND KRIYA IMPLEMENTED IT.
# GNU's default is -E — "all but the last component must exist" — so
# `realpath a/b/nope` and `realpath dangling` both SUCCEED, and a multi-operand
# run with one missing tail exits 0 with every operand printed. ⚠ The tests
# agreed with the code and both agreed with a comment nobody had measured.
expect_exit "a missing LAST component is fine by default" 0 "$BIN" realpath a/b/nope
expect_exit "a missing PARENT is not"                     1 "$BIN" realpath a/b/nope/deeper
expect_exit "a dangling symlink is fine by default"       0 "$BIN" realpath dangling
expect_exit "...and -e refuses it"                        1 "$BIN" realpath -e dangling

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

# Multi with one bad: exit 1, others still printed. ⚠ The bad one has to be bad
# under the REAL default: `a/b/nope` is a missing LAST component, which -E
# allows, so this needs a missing PARENT to fail at all.
rc=0
out=$("$BIN" realpath a/b/file a/b/nope/deeper linkfile 2>/dev/null) || rc=$?
expect_eq "multi partial rc"     "1" "$rc"
expected="$WORK_REAL/a/b/file
$WORK_REAL/a/b/file"
expect_eq "multi partial stdout" "$expected" "$out"

# -q silences stderr on failure.
err=$("$BIN" realpath -q a/b/nope/deeper 2>&1 >/dev/null || true)
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
# ⚠ AND THE ANSWER ITSELF, not just the exit code. Every assertion in this block
# used to check `rc` alone, so it passed 9/9 against a binary whose `realpath -m`
# printed GNU's stopping point instead of kriya's — which is the entire subject
# of ADR 0014.
expect_eq "...at KRIYA's stopping point, not GNU's" "$(pwd -P)/cyc/n1" \
          "$("$BIN" realpath -m cyc/n0)"
expect_eq "...and GNU stops somewhere else" "no" \
          "$([ "$(realpath -m cyc/n0)" = "$("$BIN" realpath -m cyc/n0)" ] && echo yes || echo no)"
expect_eq "...and the answer is inside the cycle" "yes" \
          "$(case "$("$BIN" realpath -m cyc/n0)" in */cyc/n[012]) echo yes;; *) echo no;; esac)"
cd ..

# --- 1.6.3: the flag surface, measured against GNU ------------------------
# ⭐ A DIFFERENTIAL HELPER, because every rule below was pinned by running GNU
# rather than by reading its manual — and three of them contradict what the
# manual's phrasing suggests. ⚠ Only stdout and the exit code are compared:
# kriya's diagnostics follow its own framing (architecture 001) and GNU
# shell-quotes operands where kriya does not, which is a project-wide style
# difference rather than anything realpath decides.
same_rp() {   # same_rp <name> <arg...>
    # ⚠ SHIFT THE NAME OFF. Without it every GNU invocation gets the test's own
    # description as an extra operand and returns 1, which reads as "kriya
    # diverges everywhere" — a harness bug that fails LOUDLY rather than
    # silently, but only because the two sides disagree by construction.
    _n=$1; shift
    _g=$(realpath "$@" 2>/dev/null || true)
    _gr=0; realpath "$@" >/dev/null 2>&1 || _gr=$?
    _k=$("$BIN" realpath "$@" 2>/dev/null || true)
    _kr=0; "$BIN" realpath "$@" >/dev/null 2>&1 || _kr=$?
    expect_eq "$_n [out]" "$_g" "$_k"
    expect_eq "$_n [rc]"  "$_gr" "$_kr"
}

# ⛔ `-E` / `--canonicalize` IS NOT IN EVERY GNU, AND ITS ABSENCE LOOKS EXACTLY
# LIKE A PATH FAILURE. An older coreutils rejects it as an invalid option — rc=1
# with empty stdout — which is byte-identical to "this path could not be
# resolved", so a differential comparison reports kriya as diverging when kriya
# is right. Measured: green on coreutils 9.11 here, four red on the CI runner.
# ⚠ **A differential test is only as portable as the oracle's option surface.**
#
# ⭐ kriya's own answer is asserted EITHER WAY. The claim under test — that `-E`
# spells kriya's default — is about kriya, and skipping it entirely would leave
# the flag untested exactly where the comparison could not run.
HAVE_E=no
if realpath -E . >/dev/null 2>&1; then HAVE_E=yes; fi
if [ "$HAVE_E" = no ]; then
    echo "note: this GNU realpath has no -E — those comparisons assert kriya alone"
fi

same_rp_e() {   # same_rp_e <name> <expected-stdout> <expected-rc> <arg...>
    _en=$1; _eo=$2; _erc=$3
    shift 3
    if [ "$HAVE_E" = yes ]; then
        same_rp "$_en" "$@"
    else
        skip "$_en — this GNU realpath has no -E"
    fi
    _ek=$("$BIN" realpath "$@" 2>/dev/null || true)
    _ekr=0
    "$BIN" realpath "$@" >/dev/null 2>&1 || _ekr=$?
    expect_eq "$_en [kriya out]" "$_eo" "$_ek"
    expect_eq "$_en [kriya rc]"  "$_erc" "$_ekr"
}

mkdir -p fx/base/one/two/three fx/base/d fx/deep/a/b fx/usr/lib fx/usr/libexec fx/x/y fx/priv/inner
echo f > fx/base/plainfile
echo A > fx/realy
( cd fx && ln -s base/plainfile flink && ln -s base dlink && ln -s one/two base/link1 )
( cd fx && ln -s deep/a/b nest && ln -s /nowhere dang )
( cd fx/base && ln -s cycB cycA && ln -s cycA cycB )
cd fx
FX=$(pwd -P)

# ⛔ THE DEFAULT MODE IS `-E`, NOT `-e`, AND KRIYA HAD IT WRONG UNTIL 1.6.3.
# GNU's own --help says "all but the last component must exist (default)". The
# consequence is not cosmetic: `realpath build/out` for a file a build is about
# to create answers under GNU and failed here.
same_rp "default mode allows a missing LAST component" base/nope
same_rp "...but not a missing parent"                  nope/deeper
same_rp_e "-E is that default, spelled" "$FX/base/nope" 0    -E base/nope
same_rp "-e requires every component"                  -e base/nope
same_rp "-m requires none"                             -m nope/deeper
same_rp "a dangling symlink resolves by default"       dang

# ⚠ BOTH AXES ARE LAST-WINS. The flag table keeps a bool per flag with no order,
# so an argv walk decides. A precedence rule instead only shows up in generated
# command lines, where a wrapper appends `-e` to a base that already carried -m.
same_rp "-e then -m is -m" -e -m base/nope
same_rp "-m then -e is -e" -m -e base/nope
same_rp_e "-E then -m is -m" "$FX/nope/deeper" 0 -E -m nope/deeper
# ⚠ This one AGREED WITH GNU BY ACCIDENT on a runner without `-E`: an invalid
# option and a missing parent are both rc=1 with no stdout. Asserted deliberately
# now rather than passing for the wrong reason.
same_rp_e "-m then -E is -E" "" 1 -m -E nope/deeper

# ⛔ -L/-P/-s ARE ONE MUTUALLY-EXCLUSIVE GROUP, also last-wins. OR-ing `-s` into
# a separate boolean — the obvious shape, since the flag table has one entry per
# spelling — makes `-P -s` strip when GNU does not.
same_rp "-s then -P is physical" -s -P base/link1/three
same_rp "-P then -s is stripped" -P -s base/link1/three
same_rp "-s then -L is logical"  -s -L base/link1/three
same_rp "-L then -s is stripped" -L -s base/link1/three
# ⚠ THE OPERAND HAS TO MAKE -L AND -P DISAGREE. `base/link1/three` has no `..`,
# so both answers are identical and the pair asserted NOTHING — a review found
# these two green against a binary with the last-wins scan removed. `nest/..` is
# `.` logically and `deep/a` physically.
same_rp "-L then -P is physical" -L -P nest/..
same_rp "-P then -L is logical"  -P -L nest/..
same_rp "-L then -P, second operand shape" -L -P nest/../..
same_rp "-P then -L, second operand shape" -P -L nest/../..

# ⛔ AND EVERY ONE OF THOSE PAIRS IS WRITTEN SEPARATED, WHICH IS THE HALF THAT
# WORKED. The scan answering them read the RAW argv, where `-Ps` is one
# three-byte token it tested for a length of two and skipped entirely — so
# `realpath -Ps flink` RESOLVED THE SYMLINK and `realpath -sP flink` did not,
# out of a scan that is supposed to be reading the same two flags. Measured
# against GNU 9.11; the separated spellings stayed green throughout.
same_rp "-Ps clustered is -P then -s" -Ps base/link1/three
same_rp "-sP clustered is -s then -P" -sP base/link1/three
same_rp "-Ls clustered is -L then -s" -Ls base/link1/three
same_rp "-sL clustered is -s then -L" -sL base/link1/three
same_rp "-LP clustered is -L then -P" -LP nest/..
same_rp "-PL clustered is -P then -L" -PL nest/..
same_rp "-em clustered is -e then -m" -em base/nope
same_rp "-me clustered is -m then -e" -me base/nope
same_rp_e "-Em clustered is -E then -m" "$FX/nope/deeper" 0 -Em nope/deeper
same_rp_e "-mE clustered is -m then -E" "" 1 -mE nope/deeper
# ⚠ A CLUSTER SPANNING BOTH AXES. Reading only the first letter of the token is
# enough to look right on one axis while silently dropping the other.
same_rp "-sm crosses both axes" -sm base/link1/nope
same_rp "-ms crosses both axes" -ms base/link1/nope
same_rp "-Pe crosses both axes" -Pe base/link1/three
same_rp "-eP crosses both axes" -eP base/link1/three
# ⚠ A SEPARATED VALUE SITTING BETWEEN THE PAIR. `--relative-to`'s DIR is not an
# option, and a scan that forgets to step over it reads the operand's leading
# letters as flags.
same_rp "a separated --relative-to value is stepped over" \
        --relative-to "$FX" -Ps base/link1/three
same_rp "...and the attached spelling is not" \
        --relative-to="$FX" -Ps base/link1/three
# ⚠ PAST `--` EVERY TOKEN IS AN OPERAND, including one whose name is a flag.
same_rp "-- ends the option scan" -P -- base/link1/three

# --- -s / --strip / --no-symlinks ---
same_rp "-s leaves the last symlink"     -s flink
same_rp "-s leaves an intermediate one"  -s base/link1/three
same_rp "--strip is the same flag"       --strip base/link1/three
same_rp "--no-symlinks is the same flag" --no-symlinks base/link1/three
same_rp "-s is still absolute"           -s base/d
same_rp "-s collapses . and //"          -s ./base//d
same_rp "-s clamps .. at the root"       -s ../../../../../../..

# ⛔ `-s` DOES NOT MEAN "DO NOT TOUCH THE FILESYSTEM". It means "do not expand
# symlinks in the OUTPUT" — the text is still stat'ed unless -m is in force, so
# every one of these is a case a "skip readlink" model gets wrong.
same_rp "-s still fails ELOOP"                 -s base/cycA
same_rp "-s still fails ENOTDIR"               -s base/plainfile/q
same_rp "-s FORGIVES a missing component"      -s base/no/pe/q
same_rp "-s -e forgives nothing"               -s -e base/no/pe/q
same_rp "-s -e on a dangling link is ENOENT"   -s -e dang
same_rp_e "-s -E on a dangling link is fine" "$FX/dang" 0 -s -E dang
same_rp "-s -m is the only lexical form"       -s -m base/cycA
same_rp "-s -m tolerates ENOTDIR too"          -s -m base/plainfile/q

# ⛔ `-s -e slink/../f` FAILS WHERE PLAIN `-e slink/../f` SUCCEEDS: the stripped
# text names a different file than the physical walk does, and the stat follows
# the text.
# ⚠ THE CONTRAST NEEDS A FILE THAT EXISTS ON EXACTLY ONE OF THE TWO PATHS.
# `base/link1/../realy` was ENOENT under both, so the pair could not tell the
# stripped text from the physical walk apart. `link1 -> one/two`, so
# `base/link1/../x` is `base/x` stripped and `base/one/x` physical — and only
# one of those exists at a time.
echo strip-side > base/onlystrip
same_rp "-s -e follows the STRIPPED text"      -s -e base/link1/../onlystrip
same_rp "...where -e follows the physical one" -e    base/link1/../onlystrip
echo phys-side > base/one/onlyphys
same_rp "...and the reverse, stripped"         -s -e base/link1/../onlyphys
same_rp "...and the reverse, physical"         -e    base/link1/../onlyphys

# --- -L / --logical vs -P / --physical ---
# ⚠ The fixture has to make them disagree: `nest -> deep/a/b`, so `nest/..` is
# `.` logically and `deep/a` physically. A symlink pointing at a directory in
# the CWD makes both answers identical and asserts nothing.
same_rp "-L pops the name"           -L nest/..
same_rp "-P follows then pops"       -P nest/..
same_rp "-L twice over"              -L nest/../..
same_rp "-P twice over"              -P nest/../..
same_rp "-L still expands symlinks"  -L base/link1/three
same_rp "-L can change EXISTENCE"    -L -e nest/../realy
same_rp "-P on the same operand"     -P -e nest/../realy
# ⚠ THE LOGICAL TREATMENT IS FOR `..` IN THE OPERAND ONLY. A `..` inside a
# symlink's own TARGET stays physical, which is why both answer the same here.
( cd base && ln -s link1/.. via ) 2>/dev/null || true
same_rp "-L on a link whose TARGET has .." -L base/via
same_rp "-P on the same link"              -P base/via

# ⛔ `..` IS A DIRECTORY ASSERTION ABOUT WHAT PRECEDES IT. Collapsing
# `base/plainfile/..` to `base` as pure text answers a question nobody asked —
# a canonical path built by walking THROUGH a regular file, exit 0.
same_rp "..  after a regular file is ENOTDIR"    base/plainfile/..
same_rp "..  after a missing component is ENOENT" base/nope/..
same_rp "...and -m forgives both"                 -m base/plainfile/..
same_rp "-s asserts it too"                       -s base/plainfile/..
same_rp "-L asserts it too"                       -L base/plainfile/..
same_rp "-s on a missing one"                     -s base/nope/../d

# ⛔ A TRAILING SLASH IS A DIRECTORY ASSERTION, NOT DECORATION. `realpath flink/`
# on a symlink to a REGULAR FILE is ENOTDIR under GNU and under open(2); kriya
# used to strip the slash and answer the file with exit 0, and so did
# `readlink -f`, whose output is normally fed straight into the next command.
same_rp "trailing slash on a symlink-to-file" flink/
same_rp "trailing slash on a plain file"      base/plainfile/
same_rp "trailing slash on a symlink-to-dir"  dlink/
same_rp "several trailing slashes"            base/plainfile///
same_rp "...and on a directory"               base/d///
# ⚠ THE ASSERTION ONLY REJECTS AN *EXISTING* NON-DIRECTORY. Coding it as
# "trailing slash means must be a directory" refuses three legal inputs.
same_rp "trailing slash on a MISSING name"    base/nope/
same_rp "trailing slash on a dangling link"   dang/
same_rp "-m never asserts it"                 -m flink/
same_rp "-e does"                             -e flink/

# --- --relative-to=DIR ---
same_rp "--relative-to below"          --relative-to=base/one base/one/two/three
same_rp "--relative-to above"          --relative-to=base/one/two base/one
same_rp "--relative-to sideways"       --relative-to=base x/y
same_rp "--relative-to equal is ."     --relative-to=base base
# ⛔ COMPONENT-WISE, NOT BYTE-WISE: a byte prefix calls /usr/lib and
# /usr/libexec common through `lib` and emits a path into the wrong directory.
same_rp "--relative-to is component-wise" --relative-to=usr/lib usr/libexec
same_rp "--relative-to canonicalises DIR" --relative-to=base/link1 base/one/two/three
same_rp "--relative-to with several operands" --relative-to=base base/d x/y
same_rp "a repeated --relative-to takes the last" --relative-to=base --relative-to=x base/d
same_rp "--relative-to DIR need not exist under -E" --relative-to=nodir base/d
same_rp "--relative-to under -m"       -m --relative-to=base base/nope/deep
same_rp "--relative-to with -s"        -s --relative-to=base/link1 base/link1/three

# --- --relative-base=DIR ---
same_rp "--relative-base below is relative" --relative-base=base base/one/two
same_rp "--relative-base outside is absolute" --relative-base=base x/y
same_rp "--relative-base equal is ."        --relative-base=base base
same_rp "--relative-base is component-wise" --relative-base=usr/lib usr/libexec
same_rp "--relative-base=/ drops the slash" --relative-base=/ base/d
# ⛔ WITH BOTH, DIR1 MUST BE UNDER DIR2 — "otherwise realpath prints absolute
# file names", says the manual, and it means for EVERY operand, including ones
# that are themselves under DIR2.
same_rp "both, operand under base"      --relative-to=base/one --relative-base=base base/one/two
same_rp "both, operand outside base"    --relative-to=base/one --relative-base=base x/y
same_rp "both, TO not under BASE"       --relative-to=x --relative-base=base base/one/two
same_rp "both, BASE deeper than TO"     --relative-to=base --relative-base=base/one base/one/two
# ⚠ An operand equal to BASE does NOT always print `.` — that only holds when TO
# defaults to BASE.
same_rp "both, operand equals base"     --relative-to=base/one/two --relative-base=base base
# ⚠ A BASE that does not exist still participates in the prefix test and can
# silently disable the feature.
same_rp "both, a missing BASE still gates" --relative-to=base --relative-base=base/nope base/d

# ⛔ A FAILING DIR ABORTS THE WHOLE RUN — one diagnostic, no operands printed.
# It is the one place realpath does not continue past an error.
same_rp "-e with an unresolvable DIR is fatal" -e --relative-to=/no/such/dir base/d base/plainfile
expect_eq "...and prints no operand" "" \
          "$("$BIN" realpath -e --relative-to=/no/such/dir base/d 2>/dev/null)"
# ⚠ `-q` DOES NOT SUPPRESS THAT ONE. Swallowing it leaves the caller with no
# output and no reason.
expect_eq "-q still reports the fatal DIR error" "1" \
          "$("$BIN" realpath -q -e --relative-to=/no/such/dir base/d 2>&1 >/dev/null | grep -c 'no such file')"
# ⚠ `-e` ALSO REQUIRES EACH DIR TO BE A DIRECTORY, and only `-e`. The check is
# on the DIRs alone — an OPERAND that is a regular file is fine in every mode.
same_rp "-e refuses a file as --relative-base" -e --relative-base=base/plainfile base/plainfile
same_rp_e "-E accepts one" "." 0               -E --relative-base=base/plainfile base/plainfile
same_rp "-e refuses a file as --relative-to"   -e --relative-to=base/plainfile base/plainfile

# --- 1.6.3 review: the `.` spelling, and separators from symlink targets ---
# ⛔ A `.` COMPONENT IS THE SAME DIRECTORY ASSERTION AS A SLASH, and the first
# version of this fix read the LAST BYTE OF THE OPERAND, so it caught `flink/`
# and missed every one of these: `flink/.` (no trailing slash at all),
# `flink/./.`, and a separator arriving from a SYMLINK'S OWN TARGET, which argv
# never sees. ⚠ `realpath dir/file/.` answered the FILE with exit 0 — a path no
# `open(2)` will honour.
ln -s base/plainfile fslash 2>/dev/null || true
ln -s "base/plainfile/" slashtgt 2>/dev/null || true
ln -s "base/" dirtgt 2>/dev/null || true
for how in "" "-L" "-P" "-s"; do
    same_rp "$how . after a regular file"        $how base/plainfile/.
    same_rp "$how . after a symlink-to-file"     $how flink/.
    same_rp "$how . twice over"                  $how base/plainfile/./.
    same_rp "$how . after a real directory"      $how base/d/.
    same_rp "$how . after a missing component"   $how base/nope/.
    same_rp "$how . after a dangling symlink"    $how dang/.
    same_rp "$how a slash from the link TARGET"  $how slashtgt
    same_rp "$how ...and a directory target"     $how dirtgt
    same_rp "$how a slash AFTER a symlink"       $how flink/
done
# ⚠ ALLOW_MISSING asserts none of it, in every how-value.
for how in "" "-L" "-P" "-s"; do
    same_rp "$how -m never asserts . " $how -m base/plainfile/.
    same_rp "$how -m on a link target" $how -m slashtgt
done

# ⛔ AND `-s`/`-L` MUST KEEP THE TRAILING SLASH THEY ARE HANDED. Nothing here
# combined either flag with a trailing slash, so both slash-preservation paths
# could be deleted with the suite still green.
same_rp "-s keeps a trailing slash"      -s base/plainfile/
same_rp "-L keeps a trailing slash"      -L base/plainfile/
same_rp "-s keeps it on a directory"     -s base/d/
same_rp "-L keeps it on a directory"     -L base/d/
same_rp "-s -e keeps it"                 -s -e base/plainfile/
same_rp "-s -m drops the assertion"      -s -m base/plainfile/

# ⚠ `--relative-to` IS DIAGNOSED FIRST WHATEVER THE ARGV ORDER, and nothing
# asserted it — swapping the two blocks left the whole suite green.
expect_eq "--relative-to is diagnosed before --relative-base" "1" \
          "$("$BIN" realpath -e --relative-base=/no/such/b --relative-to=/no/such/t base/d 2>&1 >/dev/null \
             | grep -c '/no/such/t')"
expect_eq "...in the other argv order too" "1" \
          "$("$BIN" realpath -e --relative-to=/no/such/t --relative-base=/no/such/b base/d 2>&1 >/dev/null \
             | grep -c '/no/such/t')"

# ⛔ OPERANDS PAST THE PARSER'S 128-SLOT CAP ARE REFUSED, NOT DISCARDED. The
# stdlib drops them and returns success; `kriya rm *` on 200 files deleted 128
# and exited 0.
MANY=""
i=0
while [ "$i" -lt 140 ]; do MANY="$MANY base/d"; i=$((i + 1)); done
# shellcheck disable=SC2086
expect_exit "141 operands is a usage error, not a silent truncation" 2 "$BIN" realpath $MANY
FEW=""
i=0
while [ "$i" -lt 128 ]; do FEW="$FEW base/d"; i=$((i + 1)); done
# shellcheck disable=SC2086
expect_exit "...and exactly 128 is still fine" 0 "$BIN" realpath $FEW
# shellcheck disable=SC2086
expect_exit "...as is 128 plus a flag"         0 "$BIN" realpath -m $FEW

# ⛔ THE EMPTY STRING IS ENOENT IN EVERY MODE, `-m` AND `-s` INCLUDED. Answering
# the CWD instead is the "an unset shell variable silently became `.`" failure.
same_rp "empty operand"        ""
same_rp "empty operand under -m" -m ""
same_rp "empty operand under -s" -s ""
same_rp "empty operand under -s -m" -s -m ""
cd "$WORK"

# --- summary ---
TOTAL=$((PASS + FAIL))
if [ "$SKIP" -gt 0 ]; then
    printf "%d passed, %d failed, %d skipped (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$TOTAL"
else
    printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
fi
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
