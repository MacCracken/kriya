#!/bin/sh
# smoke-touch.sh — behavioural test for `kriya touch`.
#
# Covers create, update-existing, -a / -m selectivity, -c (no-create)
# semantics, multi-operand exit codes. Defers -r / -t / -d testing to
# the milestone where they ship (chrono helper dependency).

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
    if [ -e "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' missing\n" "$1" "$2" >&2
    fi
}

expect_absent() {
    if [ ! -e "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' should not exist\n" "$1" "$2" >&2
    fi
}

# --- create ---
expect_exit "touch new"             0 "$BIN" touch new1
expect_present "new1 created"       new1

# Multi-operand create.
expect_exit "touch a b c"           0 "$BIN" touch a b c
expect_present "a"                  a
expect_present "b"                  b
expect_present "c"                  c

# --- update existing (both atime + mtime by default) ---
# Set a known-old time so we can observe the bump.
touch -t 202001010000.00 oldfile
OLD_A=$(stat -c %X oldfile)
OLD_M=$(stat -c %Y oldfile)
expect_exit "touch oldfile"         0 "$BIN" touch oldfile
NEW_A=$(stat -c %X oldfile)
NEW_M=$(stat -c %Y oldfile)
if [ "$NEW_A" -gt "$OLD_A" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL atime did not advance ($OLD_A -> $NEW_A)" >&2; fi
if [ "$NEW_M" -gt "$OLD_M" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL mtime did not advance ($OLD_M -> $NEW_M)" >&2; fi

# --- -a updates atime only ---
touch -t 202001010000.00 afile
OA=$(stat -c %X afile); OM=$(stat -c %Y afile)
expect_exit "touch -a"              0 "$BIN" touch -a afile
NA=$(stat -c %X afile); NM=$(stat -c %Y afile)
if [ "$NA" -gt "$OA" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -a did not advance atime" >&2; fi
expect_eq "-a left mtime alone"     "$OM" "$NM"

# --- -m updates mtime only ---
touch -t 202001010000.00 mfile
OA=$(stat -c %X mfile); OM=$(stat -c %Y mfile)
expect_exit "touch -m"              0 "$BIN" touch -m mfile
NA=$(stat -c %X mfile); NM=$(stat -c %Y mfile)
expect_eq "-m left atime alone"     "$OA" "$NA"
if [ "$NM" -gt "$OM" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -m did not advance mtime" >&2; fi

# --- -a -m together updates both (same as default) ---
touch -t 202001010000.00 bothfile
OA=$(stat -c %X bothfile); OM=$(stat -c %Y bothfile)
expect_exit "touch -a -m"           0 "$BIN" touch -a -m bothfile
NA=$(stat -c %X bothfile); NM=$(stat -c %Y bothfile)
if [ "$NA" -gt "$OA" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -a -m did not advance atime" >&2; fi
if [ "$NM" -gt "$OM" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -a -m did not advance mtime" >&2; fi

# --- -c (--no-create) ---
# ⛔ THIS ASSERTION WAS WRONG, and so was the comment defending it: it said
# "exit 1 (POSIX says still an error)". POSIX says the opposite —
# "Do not create a specified file if it does not exist. Do not write any
# diagnostic messages concerning this condition." — and GNU exits 0 in silence.
# kriya exited 1 with a diagnostic, against both. Measured, then fixed.
# ⚠ The differential below is the part that keeps it fixed: asserting a bare 0
# would have been just as assertable as the bare 1 that was wrong for years.
expect_exit "touch -c missing exits 0"   0 "$BIN" touch -c gone
expect_eq "...as GNU does"               "$(touch -c gone2 2>/dev/null; echo $?)" \
                                         "$("$BIN" touch -c gone3 2>/dev/null; echo $?)"
expect_eq "...and says nothing"          "" "$("$BIN" touch -c gone4 2>&1)"
expect_eq "...and creates nothing"       "no" "$([ -e gone ] && echo yes || echo no)"
# ⚠ ONLY THE ABSENCE IS EXCUSED — the condition POSIX forgives is the missing
# file, not a failure to set the times. ⛔ The first attempt at this case used a
# missing file in a read-only directory, which is still ENOENT and so was
# excused exactly as it should be: it asserted the opposite of what it meant and
# failed. An UNSEARCHABLE directory gives EACCES on a file that does exist,
# which is the distinction under test.
mkdir -p nox && echo x > nox/f && chmod 000 nox
expect_exit "touch -c does NOT excuse EACCES"  1 "$BIN" touch -c -t 202001010000 nox/f
expect_eq "...as GNU does"                     "$(touch -c -t 202001010000 nox/f 2>/dev/null; echo $?)" \
                                               "$("$BIN" touch -c -t 202001010000 nox/f 2>/dev/null; echo $?)"
expect_eq "...and says so"                     "1" \
                                               "$("$BIN" touch -c -t 202001010000 nox/f 2>&1 | grep -c 'permission denied')"
chmod 700 nox
expect_absent "gone not created"    gone

# Existing file: -c works normally, bumps times.
touch -t 202001010000.00 keeper
OM=$(stat -c %Y keeper)
expect_exit "touch -c existing"     0 "$BIN" touch -c keeper
NM=$(stat -c %Y keeper)
if [ "$NM" -gt "$OM" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL -c on existing did not advance mtime" >&2; fi

# --- errors ---
expect_exit "no operands"           2 "$BIN" touch

# Touch in a non-existent directory fails (ENOENT).
expect_exit "missing parent dir"    1 "$BIN" touch nope/here

# Partial failure: one good, one bad — exit 1, the good one is still
# created. Use a missing-parent case for the bad operand so the
# failure is isolated to that operand (using -c would suppress
# creation invocation-wide).
expect_exit "partial fail"          1 "$BIN" touch nope/parent/bad good1
expect_present "good1 created"      good1

# --- -t STAMP and -r REF (v1.2.5) ---------------------------------------
# ⚠ Both were deferred "until the wider duration/date parser lands in
# lib/chrono.cyr". Checked at pin 6.5.35: chrono has `dt_strptime` but no POSIX
# stamp parser, and `-r` needs no parser at all — just a stat. There was nothing
# upstream to wait for.
#
# ⚠ Compared under TZ=UTC: kriya interprets the stamp as UTC (ADR 0007), so an
# untagged GNU comparison would differ by the local offset, by design.
for st in 202601011200 202601011200.30 2601011200 01011200 197001010000; do
    # ⚠ `|| true` on both: these are bare simple commands under `set -e` with
    # stderr discarded, so a host where either refuses a stamp would abort the
    # whole script silently at this line rather than failing one assertion.
    "$BIN" touch -t "$st" tstamp_k 2>/dev/null || true
    TZ=UTC touch  -t "$st" tstamp_g 2>/dev/null || true
    expect_eq "-t $st matches GNU" \
        "$(TZ=UTC stat -c %y tstamp_g | cut -c1-19)" "$(TZ=UTC stat -c %y tstamp_k | cut -c1-19)"
done
# The century rule: 69-99 -> 19xx, 00-68 -> 20xx (POSIX).
# ⚠ 69 -> 1969 is a PRE-EPOCH (negative time_t) stamp, so this asserts the
# filesystem under $TMPDIR can store and return one. Most can; some cannot
# (several network filesystems clamp at the epoch, and so do a few FUSE
# layers). Probe with GNU first — if GNU cannot store it here either, the
# limitation is the filesystem's and the century rule is untestable, not broken.
"$BIN" touch -t 6901011200 cent_k 2>/dev/null
TZ=UTC touch -t 6901011200 cent_g 2>/dev/null || true
cent_g_year=$(TZ=UTC stat -c %y cent_g 2>/dev/null | cut -c1-10)
if [ "$cent_g_year" = "1969-01-01" ]; then
    expect_eq "-t century rule (69 -> 1969)" "1969-01-01" "$(TZ=UTC stat -c %y cent_k | cut -c1-10)"
else
    echo "skip: this filesystem cannot store a pre-epoch stamp (GNU got '$cent_g_year')"
fi

# Malformed stamps are refused, not silently coerced.
for bad in "" abc 20260101120 202613011200 202601321200 202601012500 202601011260 202601011200.6a; do
    expect_exit "-t rejects [$bad]" 2 "$BIN" touch -t "$bad" tbad
done

# -r REF copies the reference's mtime.
"$BIN" touch -t 202503151030 tref 2>/dev/null
expect_exit "-r REF"              0 "$BIN" touch -r tref tcopy
expect_eq   "-r copied the time"  "$(TZ=UTC stat -c %y tref)" "$(TZ=UTC stat -c %y tcopy)"
expect_exit "-r missing REF -> 1" 1 "$BIN" touch -r no_such_ref tz1
# ⚠ -r and -t together are REFUSED rather than last-one-wins. Silently picking a
# winner between two explicit time sources is the "accepts and lies" shape the
# v1.2.1 sweep removed.
expect_exit "-r with -t refused"  2 "$BIN" touch -r tref -t 202601011200 tz2

# -a / -m stay selective when an explicit time is given.
"$BIN" touch -t 202001010000 tsel 2>/dev/null
"$BIN" touch -m -t 202101010000 tsel 2>/dev/null
expect_eq "-m -t leaves atime alone" "2020-01-01" "$(TZ=UTC stat -c %x tsel | cut -c1-10)"
expect_eq "-m -t sets mtime"         "2021-01-01" "$(TZ=UTC stat -c %y tsel | cut -c1-10)"

# =====================================================================
# -h / --no-dereference — stamp the LINK, not what it points at
# =====================================================================

# ⛔ SKIPPING THE CREATE STEP IS THE WHOLE POINT, not an optimisation. The create
# is `open(O_WRONLY|O_CREAT)`, which FOLLOWS a symlink — so without the skip,
# `touch -h danglinglink` would create the missing TARGET and then stamp it.
rm -rf hh; mkdir hh; cd hh
ln -s missing dang
expect_exit "touch -h on a dangling link"   0 "$BIN" touch -h -t 202001010000 dang
expect_eq "...stamps the LINK"              "1577836800" "$(stat -c %Y dang)"
expect_eq "...and does NOT create the target" "no" "$([ -e missing ] && echo yes || echo no)"
# ⚠ The control: WITHOUT -h the same command creates the target, which is the
# behaviour -h exists to avoid.
rm -f missing
expect_exit "touch (no -h) on a dangling link" 0 "$BIN" touch dang
expect_eq "...DOES create the target"        "yes" "$([ -e missing ] && echo yes || echo no)"
rm -f missing

# A link to an existing file: the link moves, the target does not.
echo x > real
ln -s real good
BEFORE=$(stat -c %Y real)
expect_exit "touch -h on a live link"       0 "$BIN" touch -h -t 201901010000 good
expect_eq "...stamps the link"              "1546300800" "$(stat -c %Y good)"
expect_eq "...and leaves the target alone"  "$BEFORE" "$(stat -c %Y real)"

# ⚠ `-h` NEVER CREATES. GNU errors on a path that is not there at all, and stays
# silent only when `-c` is also given — measured on both.
expect_exit "touch -h on a missing path fails" 1 "$BIN" touch -h -t 202001010000 brandnew
expect_eq "...and creates nothing"           "no" "$([ -e brandnew ] && echo yes || echo no)"
expect_eq "...matching GNU's exit"           "$(touch -h -t 202001010000 gnew 2>/dev/null; echo $?)" \
                                             "$("$BIN" touch -h -t 202001010000 knew 2>/dev/null; echo $?)"
expect_exit "touch -h -c on a missing path"  0 "$BIN" touch -h -c brandnew2
expect_eq "...and still creates nothing"     "no" "$([ -e brandnew2 ] && echo yes || echo no)"
cd ..

# ⛔ EVERY `-h` CASE ABOVE PASSES `-t`, so the plain form — the one that stamps
# with "now" — was untested, and a mutant breaking only that path would have
# gone unnoticed. ⚠ The fixture stamps the link and the target at DIFFERENT past
# times, so "moved" and "did not move" are distinguishable; with both at "now"
# the assertion holds whatever the code does.
rm -rf hp; mkdir hp; cd hp
echo x > f
touch -t 201001010000 f
ln -s f flink
touch -h -t 200501010000 flink
BL=$(stat -c %Y flink); BT=$(stat -c %Y f)
expect_exit "plain touch -h (no -t)"        0 "$BIN" touch -h flink
expect_eq "...moves the LINK"               "no"  "$([ "$(stat -c %Y flink)" = "$BL" ] && echo yes || echo no)"
expect_eq "...and leaves the target alone"  "$BT" "$(stat -c %Y f)"
# ...and the same for the -a / -m halves, which take a different code path.
touch -h -t 200501010000 flink; touch -t 201001010000 f
expect_exit "touch -h -m"                   0 "$BIN" touch -h -m flink
expect_eq "...still leaves the target"      "$BT" "$(stat -c %Y f)"
cd ..

# ⛔ `-h` REACHES THE REFERENCE TOO. With `-h`, GNU reads the reference LINK's
# own times rather than its target's — and that also makes a DANGLING reference
# legal, which a plain `stat` cannot survive.
rm -rf hr; mkdir hr; cd hr
echo r > ref
touch -t 201501010000 ref
ln -s ref reflink
touch -h -t 200001010000 reflink
echo x > f; ln -s f flink
expect_exit "touch -h -r on a symlink reference" 0 "$BIN" touch -h -r reflink flink
expect_eq "...uses the LINK's own time"          "$(stat -c %Y reflink)" "$(stat -c %Y flink)"
# ⚠ The GNU side gets its own link, stamped from the same reference — the first
# version of this line built two links inside one command substitution and the
# value came back empty, which compares nothing to something.
ln -s f gflink
touch -h -r reflink gflink
expect_eq "...matching GNU"                      "$(stat -c %Y gflink)" "$(stat -c %Y flink)"
ln -s nowhere dangref
ln -s f flink4
expect_exit "touch -h -r with a DANGLING reference" 0 "$BIN" touch -h -r dangref flink4
expect_eq "...matching GNU's exit"               "$(ln -s f flink5; touch -h -r dangref flink5 2>/dev/null; echo $?)" "0"
cd ..

# ⛔ `-r` COPIES BOTH TIMES, and it copied the mtime into both. A single stamp
# value gave the destination an ACCESS time it had never had. Pre-existing, in
# the function this release edits.
rm -rf ra; mkdir ra; cd ra
echo r > ref
touch -a -t 201101010000 ref
touch -m -t 201202020000 ref
echo x > f
expect_exit "touch -r"                      0 "$BIN" touch -r ref f
expect_eq "...copies the reference ATIME"   "$(stat -c %X ref)" "$(stat -c %X f)"
expect_eq "...and the reference MTIME"      "$(stat -c %Y ref)" "$(stat -c %Y f)"
expect_eq "...and the two really differ"    "no" \
          "$([ "$(stat -c %X ref)" = "$(stat -c %Y ref)" ] && echo yes || echo no)"
cd ..

# The introspection interface knows about it.
expect_eq "--help names --no-dereference"   "1" "$("$BIN" touch --help 2>&1 | grep -c -- '--no-dereference')"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
