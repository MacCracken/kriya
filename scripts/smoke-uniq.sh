#!/bin/sh
# smoke-uniq.sh — behavioural test for `kriya uniq`.
#
# Compares output cell-by-cell against GNU `uniq` for every shipped
# flag combination, plus the comparison-key permutations (-f field
# skip, -s char skip, -w width cap, -i case fold).

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
        printf "FAIL %s:\nexpected: '%s'\ngot:      '%s'\n" "$1" "$2" "$3" >&2
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

# --- fixtures ---
printf "alpha\nalpha\nbeta\ngamma\ngamma\ngamma\ndelta\n" > dups
printf "Apple\napple\nAPPLE\nBANANA\nbanana\n"             > cased
printf "1 alpha\n2 alpha\n3 beta\n4 beta\n5 gamma\n"      > fielded
printf "alpha\nalbatross\nbeta\nbeam\n"                   > widthed
printf "alpha\nalpha\nalpha\n"                            > all_same
printf "one\ntwo\nthree\n"                                > all_unique
printf ""                                                  > empty
printf "lonely"                                            > nonl  # no newline

# --- default ---
expect_eq "default dups"  "$(uniq dups)"            "$($BIN uniq dups)"
expect_eq "default cased" "$(uniq cased)"           "$($BIN uniq cased)"
expect_eq "default all-same" "$(uniq all_same)"     "$($BIN uniq all_same)"
expect_eq "default all-unique" "$(uniq all_unique)" "$($BIN uniq all_unique)"
expect_eq "default empty" "$(uniq empty)"           "$($BIN uniq empty)"
expect_eq "default nonl"  "$(uniq nonl)"            "$($BIN uniq nonl)"

# --- -c count ---
expect_eq "-c dups"       "$(uniq -c dups)"         "$($BIN uniq -c dups)"
expect_eq "-c all-same"   "$(uniq -c all_same)"     "$($BIN uniq -c all_same)"

# --- -d repeated only ---
expect_eq "-d dups"       "$(uniq -d dups)"         "$($BIN uniq -d dups)"
expect_eq "-d all-unique" "$(uniq -d all_unique)"   "$($BIN uniq -d all_unique)"

# --- -u unique only ---
expect_eq "-u dups"       "$(uniq -u dups)"         "$($BIN uniq -u dups)"
expect_eq "-u all-same"   "$(uniq -u all_same)"     "$($BIN uniq -u all_same)"

# --- -i ignore case ---
expect_eq "-i cased"      "$(uniq -i cased)"        "$($BIN uniq -i cased)"
expect_eq "-i -c cased"   "$(uniq -i -c cased)"     "$($BIN uniq -i -c cased)"

# --- -f field skip ---
expect_eq "-f 1 fielded"  "$(uniq -f 1 fielded)"    "$($BIN uniq -f 1 fielded)"
expect_eq "-f 2 fielded"  "$(uniq -f 2 fielded)"    "$($BIN uniq -f 2 fielded)"
expect_eq "-f 0 = default" "$(uniq -f 0 dups)"      "$($BIN uniq -f 0 dups)"

# --- -s char skip ---
printf "abc1\nabc2\nxyz1\n" > char_skip
expect_eq "-s 3 char skip" "$(uniq -s 3 char_skip)"  "$($BIN uniq -s 3 char_skip)"

# --- -w width ---
expect_eq "-w 3 widthed"   "$(uniq -w 3 widthed)"   "$($BIN uniq -w 3 widthed)"

# --- combined comparison flags ---
expect_eq "-f 1 -c"        "$(uniq -f 1 -c fielded)" "$($BIN uniq -f 1 -c fielded)"
expect_eq "-i -w 1 cased"  "$(uniq -i -w 1 cased)"   "$($BIN uniq -i -w 1 cased)"

# --- stdin ---
expect_eq "stdin"         "$(uniq < dups)"          "$($BIN uniq < dups)"

# --- two-operand: input output ---
$BIN uniq dups out_file
expect_eq "2-op out matches" "$(uniq dups)" "$(cat out_file)"

# --- -z NUL terminator (input AND output are NUL-separated) ---
printf 'a\0a\0b\0b\0c\0' > nul_input
nul=$($BIN uniq -z < nul_input | tr -dc '\0' | wc -c | tr -d ' ')
nl=$($BIN uniq -z < nul_input | tr -dc '\n' | wc -c | tr -d ' ')
# 3 distinct groups → 3 NUL terminators in output.
expect_eq "-z 3 NULs"     "3" "$nul"
expect_eq "-z 0 newlines" "0" "$nl"

# --- errors ---
expect_exit "missing"     1 "$BIN" uniq ghost
expect_exit "too many"    2 "$BIN" uniq a b c

# --- ⭐ --group / --all-repeated / -D ------------------------------------
#
# ⭐ These emit EVERY line of a group, not the representative N times. With
# `-f`/`-s`/`-w` the comparison key is a WINDOW, so lines in one group can
# differ outside it — `--group -f 1` on `x a / y a / z b` must print both
# `x a` AND `y a`. A test using identical lines could not tell the two
# implementations apart, so the fixture below has a group whose members differ.
printf 'a\na\nb\nc\nc\nc\nd\n' > grp.txt
printf 'x a\ny a\nz b\n'          > grpf.txt
printf 'A\na\nb\n'                > grpi.txt

g_same() {
    label=$1; shift
    grc=0; g=$(uniq "$@" 2>&1) || grc=$?
    krc=0; k=$("$BIN" uniq "$@" 2>&1) || krc=$?
    expect_eq "group: $label" "$g" "$k"
    expect_eq "group: $label (exit)" "$grc" "$krc"
}
g_same "--group bare"          --group grp.txt
g_same "--group=separate"      --group=separate grp.txt
g_same "--group=prepend"       --group=prepend grp.txt
g_same "--group=append"        --group=append grp.txt
g_same "--group=both"          --group=both grp.txt
g_same "--all-repeated bare"   --all-repeated grp.txt
g_same "--all-repeated=none"   --all-repeated=none grp.txt
g_same "--all-repeated=prepend" --all-repeated=prepend grp.txt
g_same "--all-repeated=separate" --all-repeated=separate grp.txt
g_same "-D short form"         -D grp.txt
# ⭐ The discriminating case: members of one group that are not byte-identical.
g_same "--group -f 1 keeps both" --group -f 1 grpf.txt
g_same "--group -i"            --group -i grpi.txt
g_same "-D -i"                 -D -i grpi.txt

# ⛔ Conflicts. GNU: "--group is mutually exclusive with -c/-d/-D/-u", and
# --all-repeated with -c is "meaningless". ⚠ `--all-repeated -d` and `-u` ARE
# accepted by GNU, so they must not be rejected here either.
for combo in "--group -c" "--group -d" "--group -u"; do
    rc=0; "$BIN" uniq $combo grp.txt >/dev/null 2>&1 || rc=$?
    expect_eq "group: $combo is refused" "2" "$rc"
done
rc=0; "$BIN" uniq --all-repeated -c grp.txt >/dev/null 2>&1 || rc=$?
expect_eq "group: --all-repeated -c is refused" "2" "$rc"
g_same "--all-repeated -d allowed" --all-repeated -d grp.txt
g_same "--all-repeated -u allowed" --all-repeated -u grp.txt

# ⛔ The two METHOD vocabularies OVERLAP but differ: --group takes
# separate|prepend|append|both, --all-repeated takes none|prepend|separate.
# `--group=none` and `--all-repeated=append` are errors in GNU, and rejecting by
# vocabulary rather than a shared list is what keeps that true.
for bad in "--group=none" "--group=bogus" "--all-repeated=append" "--all-repeated=both"; do
    rc=0; "$BIN" uniq "$bad" grp.txt >/dev/null 2>&1 || rc=$?
    expect_eq "group: $bad is refused" "2" "$rc"
    grc=0; uniq "$bad" grp.txt >/dev/null 2>&1 || grc=$?
    if [ "$grc" -ne 0 ]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); echo "FAIL group: GNU should also refuse $bad" >&2
    fi
done

# ⚠ Separator placement is pinned at the boundaries, where leading/trailing
# rules actually show. A multi-group fixture cannot distinguish "before every
# group" from "between groups" for the FIRST group — a single-line input can.
printf 'a\n'     > g1.txt
printf ''        > g0.txt
printf 'a\nb\n'  > gu.txt
b_same() {
    label=$1; f=$2; shift 2
    g=$(uniq "$@" "$f" 2>&1 | od -An -c) || true
    k=$("$BIN" uniq "$@" "$f" 2>&1 | od -An -c) || true
    expect_eq "group edge: $label" "$g" "$k"
}
for m in separate prepend append both; do
    b_same "one line --group=$m"  g1.txt --group=$m
    b_same "empty in --group=$m"  g0.txt --group=$m
done
b_same "all-unique --all-repeated=prepend"  gu.txt --all-repeated=prepend
b_same "all-unique --all-repeated=separate" gu.txt --all-repeated=separate
b_same "--all-repeated=separate -u"         grp.txt --all-repeated=separate -u

# ⛔ An EMPTY method value is an error, not the default — GNU calls it
# "ambiguous argument ''". ⚠ And kriya does NOT accept GNU's unambiguous-prefix
# forms (`--group=sep`): ADR 0002 rules out prefix matching for names and, since
# 1.4.3, for their values too. Both directions pinned so neither drifts.
for bad in "--group=" "--all-repeated="; do
    rc=0; "$BIN" uniq "$bad" grp.txt >/dev/null 2>&1 || rc=$?
    expect_eq "group edge: $bad is refused" "2" "$rc"
    grc=0; uniq "$bad" grp.txt >/dev/null 2>&1 || grc=$?
    if [ "$grc" -ne 0 ]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); echo "FAIL group edge: GNU should also refuse $bad" >&2
    fi
done
for pfx in "--group=sep" "--group=b" "--all-repeated=n"; do
    rc=0; "$BIN" uniq "$pfx" grp.txt >/dev/null 2>&1 || rc=$?
    expect_eq "group edge: $pfx refused (no prefix matching, ADR 0002)" "2" "$rc"
done

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
