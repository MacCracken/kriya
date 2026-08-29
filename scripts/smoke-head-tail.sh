#!/bin/sh
# smoke-head-tail.sh — paired behavioural test for `kriya head` and
# `kriya tail`. Compares against GNU `head` / `tail` for every shipped
# flag combination.

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

# For the cases where kriya and GNU agree that a command is an ERROR but not on
# which non-zero code says so — GNU's head/tail exit 1 on a usage error, kriya
# exits 2 for every one of its 38 utilities. Asserting "GNU also refuses this"
# rather than assuming it is the point: it is what makes the deviation a
# deliberate one-field difference instead of an untested claim.
expect_nonzero() {
    name=$1
    shift
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
        expect_eq "$name" "non-zero exit" "exit 0"
    else
        expect_eq "$name" "non-zero exit" "non-zero exit"
    fi
}

# --- fixture ---
seq 1 50 > nums            # 50 lines
seq 1 5 > short            # 5 lines
printf "no trailing nl"    > nonl
printf ""                  > empty
seq 1 1000 > big           # 1000 lines
# ⚠ A LONG FIRST LINE AND A SHORT SECOND, so the -n answer and the -c answer
# differ at BOTH ends. On `nums` the two happen to overlap enough that a
# mode mix-up can still look plausible.
printf 'abcdefghij\nklmnop\n' > mixed

# --- head: default 10 ---
expect_eq "head default"        "$(head nums)"           "$($BIN head nums)"
expect_eq "head default short"  "$(head short)"          "$($BIN head short)"

# --- head -n N ---
expect_eq "head -n 3"           "$(head -n 3 nums)"      "$($BIN head -n 3 nums)"
expect_eq "head -n 0"           "$(head -n 0 nums)"      "$($BIN head -n 0 nums)"
expect_eq "head -n 100 over"    "$(head -n 100 short)"   "$($BIN head -n 100 short)"
expect_eq "head -n 1000 big"    "$(head -n 1000 big)"    "$($BIN head -n 1000 big)"

# --- head -c N ---
expect_eq "head -c 5"           "$(head -c 5 nums)"      "$($BIN head -c 5 nums)"
expect_eq "head -c 0"           "$(head -c 0 nums)"      "$($BIN head -c 0 nums)"
expect_eq "head -c 99999 over"  "$(head -c 99999 short)" "$($BIN head -c 99999 short)"

# --- head no trailing newline ---
expect_eq "head nonl"           "$(head -n 5 nonl)"      "$($BIN head -n 5 nonl)"
expect_eq "head empty"          "$(head empty)"          "$($BIN head empty)"

# --- head stdin ---
expect_eq "head stdin"          "$(head -n 3 < nums)"    "$($BIN head -n 3 < nums)"

# --- head multi-file with headers ---
expect_eq "head multi"          "$(head -n 2 short nums)" "$($BIN head -n 2 short nums)"

# --- head -q multi-file ---
expect_eq "head -q multi"       "$(head -q -n 2 short nums)" "$($BIN head -q -n 2 short nums)"

# --- head -v single file ---
expect_eq "head -v single"      "$(head -v -n 2 short)"  "$($BIN head -v -n 2 short)"

# --- head: -n and -c are LAST-WINS ---------------------------------------
# ⛔ THIS USED TO BE A PRECEDENCE RULE — "-c wins over -n" — under a comment
# claiming it was last-wins. Only the order the two rules agree on was covered.
# Measured against GNU coreutils 9.11 on `abcdefghij\nklmnop\n`:
#
#     $ head -c 3 -n 1 mixed      abcdefghij      (the -n answer)
#     $ kriya head -c 3 -n 1      abc             (the -c answer)
#
# ⭐ Both orders, both attached spellings, the long forms, and a cluster mixing
# a bool with a value-taking short — the shapes a generated command line
# actually produces when a wrapper appends one flag to a base carrying the other.
expect_eq "head -c then -n"        "$(head -c 3 -n 1 mixed)"        "$($BIN head -c 3 -n 1 mixed)"
expect_eq "head -n then -c"        "$(head -n 1 -c 3 mixed)"        "$($BIN head -n 1 -c 3 mixed)"
expect_eq "head -c3 -n1 attached"  "$(head -c3 -n1 mixed)"          "$($BIN head -c3 -n1 mixed)"
expect_eq "head -n1 -c3 attached"  "$(head -n1 -c3 mixed)"          "$($BIN head -n1 -c3 mixed)"
expect_eq "head -c 3 -n1 mixed"    "$(head -c 3 -n1 mixed)"         "$($BIN head -c 3 -n1 mixed)"
expect_eq "head --bytes= --lines=" "$(head --bytes=3 --lines=1 mixed)" "$($BIN head --bytes=3 --lines=1 mixed)"
expect_eq "head --lines= --bytes=" "$(head --lines=1 --bytes=3 mixed)" "$($BIN head --lines=1 --bytes=3 mixed)"
expect_eq "head -c then --lines"   "$(head -c 3 --lines 1 mixed)"   "$($BIN head -c 3 --lines 1 mixed)"
expect_eq "head --lines then -c"   "$(head --lines 1 -c 3 mixed)"   "$($BIN head --lines 1 -c 3 mixed)"
# ⚠ A BOOL CLUSTERED ONTO THE VALUE-TAKING SHORT, which is where reading the
# raw token instead of the expanded one stops seeing the second flag at all.
expect_eq "head -qc3 then -n 1"    "$(head -qc3 -n 1 mixed)"        "$($BIN head -qc3 -n 1 mixed)"
expect_eq "head -qn1 then -c 3"    "$(head -qn1 -c 3 mixed)"        "$($BIN head -qn1 -c 3 mixed)"
# ⚠ A REPEATED FLAG: the LAST occurrence is the one that counts, not the first.
expect_eq "head -c 3 -n 1 -c 5"    "$(head -c 3 -n 1 -c 5 mixed)"   "$($BIN head -c 3 -n 1 -c 5 mixed)"
expect_eq "head -n 1 -c 3 -n 2"    "$(head -n 1 -c 3 -n 2 mixed)"   "$($BIN head -n 1 -c 3 -n 2 mixed)"
# ⚠ PAST `--` EVERY TOKEN IS AN OPERAND.
expect_eq "head -c 3 -- mixed"     "$(head -c 3 -- mixed)"          "$($BIN head -c 3 -- mixed)"

# --- tail: default 10 ---
expect_eq "tail default"        "$(tail nums)"           "$($BIN tail nums)"
expect_eq "tail default short"  "$(tail short)"          "$($BIN tail short)"

# --- tail -n N ---
expect_eq "tail -n 3"           "$(tail -n 3 nums)"      "$($BIN tail -n 3 nums)"
expect_eq "tail -n 0"           "$(tail -n 0 nums)"      "$($BIN tail -n 0 nums)"
expect_eq "tail -n 100 over"    "$(tail -n 100 short)"   "$($BIN tail -n 100 short)"
expect_eq "tail -n 5 big"       "$(tail -n 5 big)"       "$($BIN tail -n 5 big)"

# --- tail -c N ---
expect_eq "tail -c 5"           "$(tail -c 5 nums)"      "$($BIN tail -c 5 nums)"
expect_eq "tail -c 0"           "$(tail -c 0 nums)"      "$($BIN tail -c 0 nums)"
expect_eq "tail -c 99999 over"  "$(tail -c 99999 short)" "$($BIN tail -c 99999 short)"

# --- tail no trailing newline ---
expect_eq "tail nonl"           "$(tail -n 5 nonl)"      "$($BIN tail -n 5 nonl)"
expect_eq "tail empty"          "$(tail empty)"          "$($BIN tail empty)"

# --- tail stdin ---
expect_eq "tail stdin"          "$(tail -n 3 < nums)"    "$($BIN tail -n 3 < nums)"

# --- tail multi-file with headers ---
expect_eq "tail multi"          "$(tail -n 2 short nums)" "$($BIN tail -n 2 short nums)"

# --- tail -q multi-file ---
expect_eq "tail -q multi"       "$(tail -q -n 2 short nums)" "$($BIN tail -q -n 2 short nums)"

# --- tail -v single file ---
expect_eq "tail -v single"      "$(tail -v -n 2 short)"  "$($BIN tail -v -n 2 short)"

# --- tail: -n and -c are LAST-WINS ---------------------------------------
# ⛔ THE SAME DEFECT, IN THE SAME SHAPE, IN HEAD'S PAIR UTILITY. Measured
# against GNU coreutils 9.11 on `abcdefghij\nklmnop\n`:
#
#     $ tail -c 3 -n 1 mixed      klmnop      (the -n answer)
#     $ kriya tail -c 3 -n 1      op          (the -c answer)
expect_eq "tail -c then -n"        "$(tail -c 3 -n 1 mixed)"        "$($BIN tail -c 3 -n 1 mixed)"
expect_eq "tail -n then -c"        "$(tail -n 1 -c 3 mixed)"        "$($BIN tail -n 1 -c 3 mixed)"
expect_eq "tail -c3 -n1 attached"  "$(tail -c3 -n1 mixed)"          "$($BIN tail -c3 -n1 mixed)"
expect_eq "tail -n1 -c3 attached"  "$(tail -n1 -c3 mixed)"          "$($BIN tail -n1 -c3 mixed)"
expect_eq "tail --bytes= --lines=" "$(tail --bytes=3 --lines=1 mixed)" "$($BIN tail --bytes=3 --lines=1 mixed)"
expect_eq "tail --lines= --bytes=" "$(tail --lines=1 --bytes=3 mixed)" "$($BIN tail --lines=1 --bytes=3 mixed)"
expect_eq "tail -c then --lines"   "$(tail -c 3 --lines 1 mixed)"   "$($BIN tail -c 3 --lines 1 mixed)"
expect_eq "tail -qc3 then -n 1"    "$(tail -qc3 -n 1 mixed)"        "$($BIN tail -qc3 -n 1 mixed)"
expect_eq "tail -qn1 then -c 3"    "$(tail -qn1 -c 3 mixed)"        "$($BIN tail -qn1 -c 3 mixed)"
expect_eq "tail -c 3 -n 1 -c 5"    "$(tail -c 3 -n 1 -c 5 mixed)"   "$($BIN tail -c 3 -n 1 -c 5 mixed)"
expect_eq "tail -c 3 -- mixed"     "$(tail -c 3 -- mixed)"          "$($BIN tail -c 3 -- mixed)"

# --- errors ---
expect_exit "head missing"      1 "$BIN" head ghost
expect_exit "tail missing"      1 "$BIN" tail ghost
expect_exit "head bad -n"       2 "$BIN" head -n abc
expect_exit "tail bad -c"       2 "$BIN" tail -c xyz

# --- obsolescent bare-digit count (`head -5`, `tail -5`) ---------------
#
# ⛔ IT USED TO FIRE AT ANY POSITION, WHICH SILENTLY OVERRODE THE OPTION IN
# FRONT OF IT. `head -n 1 -5 nums` expanded the trailing `-5` into `-n 5` and
# printed FIVE lines with exit 0, where the command as written says one. GNU
# 9.11 refuses the form in every position but the first — `head: invalid
# trailing option -- 5`, `tail: option used in invalid context -- 5` — because a
# digit that far from the front is a typo far more often than an intent.
#
# ⚠ The position is the ARGUMENT's, not "the first option": GNU reads argv[1]
# and nothing else, so `head nums -5` is refused too. Asserted below.
#
# ⚠ Known deviation, deliberate: `tail -5 -c 3` is accepted here and refused by
# GNU, whose tail takes the obsolescent form only when it is the ONLY option
# (its parse gives up once argc exceeds 3). kriya applies the same
# first-argument rule to both utilities rather than reproducing that asymmetry.
expect_eq "head -5 first arg"     "$(head -5 nums)"        "$($BIN head -5 nums)"
expect_eq "tail -5 first arg"     "$(tail -5 nums)"        "$($BIN tail -5 nums)"
expect_eq "head -1 first arg"     "$(head -1 nums)"        "$($BIN head -1 nums)"
expect_eq "tail -1 first arg"     "$(tail -1 nums)"        "$($BIN tail -1 nums)"
expect_eq "head -25 over-length"  "$(head -25 short)"      "$($BIN head -25 short)"
# First position still composes with a later option — `-c` wins, as in GNU.
expect_eq "head -5 then -c 3"     "$(head -5 -c 3 nums)"   "$($BIN head -5 -c 3 nums)"

expect_exit    "head -c 3 -5 refused"     2 "$BIN" head -c 3 -5 nums
expect_nonzero "gnu head -c 3 -5 refused"   head -c 3 -5 nums
expect_exit    "head -n 1 -5 refused"     2 "$BIN" head -n 1 -5 nums
expect_nonzero "gnu head -n 1 -5 refused"   head -n 1 -5 nums
expect_exit    "head FILE -5 refused"     2 "$BIN" head nums -5
expect_nonzero "gnu head FILE -5 refused"   head nums -5
expect_exit    "head -5 -5 refused"       2 "$BIN" head -5 -5 nums
expect_nonzero "gnu head -5 -5 refused"     head -5 -5 nums

expect_exit    "tail -c 3 -5 refused"     2 "$BIN" tail -c 3 -5 nums
expect_nonzero "gnu tail -c 3 -5 refused"   tail -c 3 -5 nums
expect_exit    "tail -n 1 -5 refused"     2 "$BIN" tail -n 1 -5 nums
expect_nonzero "gnu tail -n 1 -5 refused"   tail -n 1 -5 nums
expect_exit    "tail FILE -5 refused"     2 "$BIN" tail nums -5
expect_nonzero "gnu tail FILE -5 refused"   tail nums -5

# A refusal has to NAME the offender, or the next person reads "bad option" and
# goes looking at `-c`.
err=$("$BIN" head -c 3 -5 nums 2>&1 >/dev/null | head -1)
case "$err" in
    *"invalid trailing option -- 5"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL head trailing-digit diagnostic:\ngot: '%s'\n" "$err" >&2 ;;
esac
err=$("$BIN" tail -c 3 -5 nums 2>&1 >/dev/null | head -1)
case "$err" in
    *"invalid trailing option -- 5"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL tail trailing-digit diagnostic:\ngot: '%s'\n" "$err" >&2 ;;
esac

# `--` still ends option parsing before any of this: a first-argument `-5` in
# front of it is a count, and one behind it is a filename.
expect_eq   "head -5 -- FILE"     "$(head -5 -- nums)"     "$($BIN head -5 -- nums)"
expect_exit "head -- -5 is a file" 1 "$BIN" head -- -5

# --- -q / -v is last-wins, on both the operand and the stdin path ------------
#
# ⛔ IT WAS A PRECEDENCE LADDER TWENTY LINES BELOW THE -n/-c ONE THIS RELEASE
# REPLACED, and it ran in both directions: quiet won unconditionally over
# operands and verbose won unconditionally on stdin. `head -q -v a b` dropped
# BOTH headers and concatenated two files with nothing marking the boundary, at
# exit 0 — a consumer cannot recover where one file ended.
#
# ⚠ Every pair is asserted in BOTH orders. `-vq` agreed with GNU under the old
# rule too, which is exactly why one-order coverage saw nothing.
printf 'abcdefghij\nklmnop\n' > qv1
printf 'ZYXWVUTSRQ\nPONMLK\n' > qv2
qv_case() {   # qv_case <util> <flags...>
    _u=$1; shift
    expect_eq "$_u $* (operands)" "$("$_u" "$@" qv1 qv2 2>&1)" "$("$BIN" "$_u" "$@" qv1 qv2 2>&1)"
}
for _u in head tail; do
    qv_case "$_u" -q -v
    qv_case "$_u" -v -q
    qv_case "$_u" -qv -n 1
    qv_case "$_u" -vq -n 1
    qv_case "$_u" --quiet --verbose
    qv_case "$_u" --verbose --quiet
    qv_case "$_u" -qqv
    qv_case "$_u" -vvq
    qv_case "$_u" -v -q -v
    qv_case "$_u" -q
    qv_case "$_u" -v
    # ⚠ The stdin path had its own copy of the ladder, with the winner reversed.
    for _fl in "-v -q" "-q -v" "-v" "-q"; do
        expect_eq "$_u $_fl <stdin" "$("$_u" $_fl < qv1 2>&1)" "$("$BIN" "$_u" $_fl < qv1 2>&1)"
    done
done

# --- an empty count value is an error, not an absent option ------------------
#
# ⛔ `head --lines=` PRINTED TEN LINES AND EXITED 0. The empty value was skipped
# over, the option thrown away, and the default used — a silently different
# answer to the question actually asked, which is the case
# [ADR 0002](../docs/adr/0002-argument-parsing-is-agent-safe.md) names.
# ⚠ Exit 2 here against GNU's 1, per ADR 0008; what matters is that both refuse.
for _u in head tail; do
    for _a in "--lines=" "--bytes="; do
        expect_exit "$_u $_a is a usage error" 2 "$BIN" "$_u" "$_a" qv1
        _grc=0; $_u "$_a" qv1 >/dev/null 2>&1 || _grc=$?
        expect_eq "...and GNU refuses it too" "yes" "$([ "$_grc" != 0 ] && echo yes || echo no)"
    done
    expect_exit "$_u -n '' is a usage error"        2 "$BIN" "$_u" -n "" qv1
    expect_exit "$_u -n 5 --lines= still refuses"   2 "$BIN" "$_u" -n 5 --lines= qv1
done

# --- partial failure ---
rc=0
out=$($BIN head -n 2 short ghost nums 2>/dev/null) || rc=$?
expect_eq "head partial rc"     "1" "$rc"
# Should still have output for short and nums.
if echo "$out" | grep -q "short"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL head partial missing short header" >&2; fi
if echo "$out" | grep -q "nums";  then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL head partial missing nums header"  >&2; fi

# --- "-" operand = stdin ---
expect_eq "head - stdin"        "$(head -n 2 - < nums)"  "$($BIN head -n 2 - < nums)"

# --- tail -f follow mode ---
follow_dir=$(mktemp -d)

# Single-file follow: initial output + appended lines.
#
# ⛔ THIS IS A WALL-CLOCK RACE AND USED TO HAVE NO RETRY. The writer appends at
# t≈0.4 s and t≈0.8 s, kriya polls the path every 200 ms, and `timeout 1.4`
# killed it — a budget with roughly one poll of slack. On a loaded runner the
# writer subshell may not be scheduled in time, or the final poll may not land
# before the kill, and the assertion then blames kriya for the scheduler.
# ⭐ Retry rather than widening the budget: a flake passes on the second try in
# a fraction of the time a budget generous enough to never flake would cost on
# EVERY run. Three attempts, and the failure message still shows the last one.
follow_expected="line2
line3
line4
line5"
out=""
attempt=1
while [ "$attempt" -le 3 ]; do
    printf "line1\nline2\nline3\n" > "$follow_dir/log"
    ( sleep 0.4; echo "line4" >> "$follow_dir/log"; sleep 0.4; echo "line5" >> "$follow_dir/log" ) &
    writer_pid=$!
    out=$(timeout 2.5 "$BIN" tail -f -n 2 "$follow_dir/log" 2>/dev/null || true)
    wait "$writer_pid" 2>/dev/null || true
    if [ "$out" = "$follow_expected" ]; then
        attempt=4
    else
        attempt=$((attempt + 1))
    fi
done
expect_eq "tail -f appends" "$follow_expected" "$out"

# Truncation detection: shrinking write emits the warning + new content.
# ⚠ Same race, same treatment — the truncation has to land inside the window.
out_err=""
attempt=1
while [ "$attempt" -le 3 ]; do
    printf "line-A\nline-B\nline-C\n" > "$follow_dir/big"
    ( sleep 0.4; printf "tiny\n" > "$follow_dir/big" ) &
    writer_pid=$!
    out_err=$(timeout 2.5 "$BIN" tail -f -n 1 "$follow_dir/big" 2>&1 || true)
    wait "$writer_pid" 2>/dev/null || true
    case "$out_err" in
        *"file truncated"*tiny*) attempt=4 ;;
        *) attempt=$((attempt + 1)) ;;
    esac
done
if echo "$out_err" | grep -q "file truncated"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL truncate warning missing" >&2; fi
if echo "$out_err" | grep -q "tiny"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL truncate new content missing" >&2; fi

# Multi-file follow is currently rejected with usage error.
expect_exit "tail -f multi-file rejected" 2 "$BIN" tail -f "$follow_dir/log" "$follow_dir/big"

rm -rf "$follow_dir"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
