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

# --- 1.6.15: the count forms --------------------------------------------------
#
# ⭐ `head -n -N` / `-c -N` (all but the last N), `tail -n +N` / `-c +N` (from N
# on), a sign on either count, and the obsolescent first argument past bare
# digits (`head -5c`, `tail +5`, `tail -5cf`). Every one was a refusal, exit 2,
# until 1.6.15 — and `tail +5 FILE` read a FILE named `+5`. Each case below is
# compared with GNU byte for byte, exit status included.
printf 'a\nb\nc' > ht_nonl                  # an unended last line
printf '\n\n\n' > ht_blank
: > ht_empty
seq 1 10 > ht_ten
# ⚠ PAST ONE 64 KiB READ, so the held-back bytes have to slide and grow, and the
# regular-file `-c -N` path (which only trusts a size bigger than one read) runs.
seq 1 200000 > ht_big
awk 'BEGIN { for (i = 0; i < 300000; i++) printf "%c", 65 + i % 26 }' > ht_nolf
awk 'BEGIN { for (i = 0; i < 70000; i++) printf "x"; printf "\nend" }' > ht_long

ht_same() {   # ht_same <util> <args...>: GNU and kriya agree on stdout and exit status
    _u=$1; shift
    _grc=0; timeout 1 "$_u" "$@" </dev/null >ht_g.out 2>/dev/null || _grc=$?
    _krc=0; timeout 1 "$BIN" "$_u" "$@" </dev/null >ht_k.out 2>/dev/null || _krc=$?
    if cmp -s ht_g.out ht_k.out && [ "$_grc" = "$_krc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s %s: GNU exit %s, kriya exit %s, output %s\n' "$_u" "$*" "$_grc" "$_krc" \
            "$(cmp -s ht_g.out ht_k.out && echo same || echo differs)" >&2
    fi
}
ht_pipe() {   # ht_pipe <file> <util> <args...>: the same, reading the file through a pipe
    _f=$1; _u=$2; shift 2
    _grc=0; cat "$_f" | "$_u" "$@" >ht_g.out 2>/dev/null || _grc=$?
    _krc=0; cat "$_f" | "$BIN" "$_u" "$@" >ht_k.out 2>/dev/null || _krc=$?
    if cmp -s ht_g.out ht_k.out && [ "$_grc" = "$_krc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); printf 'FAIL pipe %s %s %s\n' "$_u" "$*" "$_f" >&2
    fi
}

# head: all but the last N.
for _a in "-n -3" "-n -0" "-n -1" "-n -9" "-n -10" "-n -99" "-n -02" "-c -3" "-c -0" \
          "-c -99" "--lines=-3" "--bytes=-3" "-n -+3"; do
    for _f in ht_ten ht_nonl ht_blank ht_empty; do
        # shellcheck disable=SC2086
        ht_same head $_a "$_f"
    done
done
for _a in "-n -3" "-n -150000" "-n -199999" "-n -200000" "-n -70000" "-c -3" "-c -200000"; do
    # shellcheck disable=SC2086
    ht_same head $_a ht_big
    # shellcheck disable=SC2086
    ht_pipe ht_big head $_a
done
for _a in "-c -1" "-c -65535" "-c -65536" "-c -65537" "-c -299999" "-c -300000" "-c -300001" "-n -1"; do
    # shellcheck disable=SC2086
    ht_same head $_a ht_nolf
    # shellcheck disable=SC2086
    ht_pipe ht_nolf head $_a
done
ht_same head -n -1 ht_long
ht_same head -c -2 ht_long
ht_same head -n -2 ht_ten ht_nonl
ht_same head -c -2 ht_nonl ht_ten
ht_same head -v -n -2 ht_ten
# A `+` on head's count is only a sign.
ht_same head -n +3 ht_ten
ht_same head -c +3 ht_ten
ht_same head -n ' 3' ht_ten

# tail: from N on.
for _a in "-n +3" "-n +1" "-n +0" "-n +10" "-n +11" "-n +100" "-c +3" "-c +0" "-c +21" \
          "-c +22" "--lines=+3" "--bytes=+3"; do
    for _f in ht_ten ht_nonl ht_blank ht_empty; do
        # shellcheck disable=SC2086
        ht_same tail $_a "$_f"
    done
done
for _a in "-n +199990" "-n +2" "-c +1288000" "-c +70000"; do
    # shellcheck disable=SC2086
    ht_same tail $_a ht_big
    # shellcheck disable=SC2086
    ht_pipe ht_big tail $_a
done
ht_same tail -n +2 ht_long
ht_same tail -c +70001 ht_long
ht_same tail -n +3 ht_ten ht_nonl
# A `-` on tail's count is only a sign — and ONLY THE FIRST BYTE decides, so a
# blank in front turns the `+` into a sign as well: the LAST three lines.
ht_same tail -n -3 ht_ten
ht_same tail -n -+3 ht_ten
ht_same tail -n ' +3' ht_ten

# The obsolescent first argument.
for _a in -3c -3cv -3l -3cl -3kc -3kl -3lk -3k -3b -3m -03c -0 -3v -3q; do
    ht_same head "$_a" ht_ten
done
ht_same head -3qv ht_ten ht_nonl
ht_same head -3vq ht_ten ht_nonl
ht_same head -3v -q ht_ten ht_nonl
ht_same head -3c -v ht_ten
ht_same head -3c -n 2 ht_ten
ht_same head -3 -c 2 ht_ten
ht_same head -3c ht_ten ht_nonl
for _a in +3 +3l +3c +3b +0 + +c -3c -3l -1b -l -b -0; do
    ht_same tail "$_a" ht_ten
done
ht_same tail +3 -- ht_ten
ht_same tail -3 -- ht_ten
ht_same tail +3 -n 2 ht_ten
# ⚠ A `+` FIRST ARGUMENT IS A LEGAL FILE NAME, and GNU's rule for when it is
# one is kept exactly: a count only when at most one operand follows (or `--`
# and one). So both of these read a FILE named `+3`, fail on it, and go on.
ht_same tail +3 ht_ten ht_nonl
ht_same tail +3 -v ht_ten
ht_same tail +3x ht_ten
# Follow forms, cut off by the helper's one-second timeout at the same point.
ht_same tail -3f ht_ten
ht_same tail -cf ht_ten
ht_same tail +8f ht_ten
# ⚠ The `-` forms do NOT follow GNU's operand rule — see the deviation note at
# the obsolescent block above: a token starting with `-` cannot be a file name,
# so kriya takes it whatever follows, where GNU refuses.
expect_eq "tail -3c two files (kriya takes it)" "$(tail -c 3 ht_ten ht_nonl)" "$($BIN tail -3c ht_ten ht_nonl)"
expect_nonzero "gnu tail -3c two files refused" tail -3c ht_ten ht_nonl

# ⭐ OVERSIZED COUNTS SATURATE. `head -n 18446744073709551617` printed ONE line at
# exit 0 until 1.6.15: the parser wrapped past 2^64. GNU 9.11 clamps these to
# "more than the input has", and so does kriya. ⚠ Asserted against the answer,
# not against the local GNU: 9.4 (CI's container) refuses them outright.
expect_eq "head -n 2^64+1 is everything"  "$(cat ht_ten)" "$($BIN head -n 18446744073709551617 ht_ten)"
expect_eq "head -n huge is everything"    "$(cat ht_ten)" "$($BIN head -n 99999999999999999999 ht_ten)"
expect_eq "head -huge is everything"      "$(cat ht_ten)" "$($BIN head -99999999999999999999 ht_ten)"
expect_eq "head -c huge is everything"    "$(cat ht_ten)" "$($BIN head -c 99999999999999999999 ht_ten)"
expect_eq "head -n -huge is nothing"      "" "$($BIN head -n -99999999999999999999 ht_ten)"
expect_eq "head -c -huge is nothing"      "" "$($BIN head -c -99999999999999999999 ht_ten)"
expect_eq "tail -n huge is everything"    "$(cat ht_ten)" "$($BIN tail -n 99999999999999999999 ht_ten)"
expect_eq "tail -n +huge is nothing"      "" "$($BIN tail -n +99999999999999999999 ht_ten)"
expect_eq "tail +huge is nothing"         "" "$($BIN tail +99999999999999999999 ht_ten)"
# ⛔ A SEEK THAT CLOSE TO 2^63 SUCCEEDS AND THE READ AFTER IT FAILS (EINVAL), so
# this exited 1 in development; the seek now stops at the end of the file.
expect_exit "tail -c +huge exits 0"       0 "$BIN" tail -c +99999999999999999999 ht_ten
expect_eq "tail -c +huge is nothing"      "" "$($BIN tail -c +99999999999999999999 ht_ten)"

# ⚠ THREE GNU `tail` BEHAVIOURS KRIYA DOES NOT REPRODUCE, found by the grammar
# fuzz at 1.6.15 (`difffuzz-head-tail.py`) and asserted here as kriya's own answer:
# - With `-n 0` or `-c 0` and no `-f`, GNU 9.11 exits at once: no headers, and
#   no file is even opened, so `tail -n 0 missing` exits 0. kriya prints the
#   headers, as GNU's own `head -n 0 a b` does, and reports the missing file.
# - A `+N` of 2^63-1 or more makes GNU exit the same way; kriya prints the
#   headers over empty output, as it does for any `+N` past the end.
# - GNU's `tail` takes a negative zero (`-n --0` is 0) where its `head` refuses
#   one. kriya refuses it in both.
printf '==> ht_ten <==\n\n==> ht_nonl <==\n' > ht_hdrs
# ⚠ `|| true`: under `set -e` a regression here must FAIL an assertion, not end the suite.
"$BIN" tail -n 0 ht_ten ht_nonl > ht_k.out || true
expect_eq "tail -n 0 two files prints the headers" "$(cksum < ht_hdrs)" "$(cksum < ht_k.out)"
expect_exit "tail -n 0 missing reports it"       1 "$BIN" tail -n 0 ghost
expect_exit "tail -n --0 refused"                2 "$BIN" tail -n --0 ht_ten
"$BIN" tail -n +99999999999999999999 ht_ten ht_nonl > ht_k.out || true
expect_eq "tail +huge two files prints the headers" "$(cksum < ht_hdrs)" "$(cksum < ht_k.out)"

# Refusals: both refuse (kriya with 2, per ADR 0008).
for _c in "head -3x ht_ten" "head -n - ht_ten" "head -n + ht_ten" \
          "head -n --3 ht_ten" "head -c ++3 ht_ten" "tail -n ++3 ht_ten" "tail -n +-3 ht_ten" \
          "tail -n - ht_ten" "tail -3x ht_ten" "tail -3fl ht_ten"; do
    # shellcheck disable=SC2086
    expect_exit "kriya $_c refused" 2 "$BIN" $_c
    # shellcheck disable=SC2086
    expect_nonzero "gnu $_c refused" $_c
done
# ⚠ GNU takes `z` (NUL-terminated lines) in the obsolescent argument. kriya's
# `head` has no `-z` at all, so `-3z` is refused exactly as `-z` is.
expect_exit "head -3z refused (no -z in kriya)" 2 "$BIN" head -3z ht_ten
expect_exit "head -z refused the same way"      2 "$BIN" head -z ht_ten
expect_exit "head -n ' -3' refused" 2 "$BIN" head -n ' -3' ht_ten
expect_nonzero "gnu head -n ' -3' refused" head -n ' -3' ht_ten
expect_exit "tail -n '+ 3' refused" 2 "$BIN" tail -n '+ 3' ht_ten
expect_nonzero "gnu tail -n '+ 3' refused" tail -n '+ 3' ht_ten
err=$("$BIN" head -3x ht_ten 2>&1 >/dev/null | head -1)
case "$err" in
    *"invalid trailing option -- x"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL head -3x diagnostic:\ngot: '%s'\n" "$err" >&2 ;;
esac
err=$("$BIN" head -n abc ht_ten 2>&1 >/dev/null | head -1)
expect_eq "head -n abc diagnostic" "kriya head: abc: invalid number of lines" "$err"

# --- 1.6.15: a shared descriptor is left where `head` stopped ------------------
#
# ⛔ `{ head -n 1 >/dev/null; cat; } < file` PRINTED NOTHING AFTER THE FIRST LINE,
# at exit 0: the 64 KiB read that found line 1 took the rest of the file with it.
# POSIX asks a utility that stops before EOF to leave a seekable input just past
# the last byte it processed (XCU 1.4, INPUT FILES), and GNU does. ⚠ A pipe
# cannot be put back, so only the forms that never over-read are compared there.
ht_offset() {   # ht_offset <file> <util> <args...>
    _f=$1; _u=$2; shift 2
    # ⚠ `|| true` inside the group: `set -e` reaches into it, and a refusal
    # must fail the comparison below rather than end the suite.
    { "$_u" "$@" >/dev/null 2>&1 || true; echo ---; cat; } < "$_f" > ht_g.out
    { "$BIN" "$_u" "$@" >/dev/null 2>&1 || true; echo ---; cat; } < "$_f" > ht_k.out
    if cmp -s ht_g.out ht_k.out; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); printf 'FAIL offset after %s %s < %s\n' "$_u" "$*" "$_f" >&2
    fi
}
for _a in "-n 2" "-n 0" "-c 4" "-c 0" "-2" "-3c" "-n -3" "-c -3" "-n -0"; do
    # shellcheck disable=SC2086
    ht_offset ht_ten head $_a
done
for _a in "-n 5" "-n 70000" "-c 70000" "-n -3" "-c -3" "-c -100000"; do
    # shellcheck disable=SC2086
    ht_offset ht_big head $_a
done
ht_offset ht_nolf head -c -100000
ht_offset ht_ten tail -n +3
for _a in "-c 4" "-c 0" "-3c"; do
    # shellcheck disable=SC2086
    expect_eq "pipe keeps the rest after head $_a" \
        "$(cat ht_big | { head $_a >/dev/null || true; cat; } | cksum)" \
        "$(cat ht_big | { "$BIN" head $_a >/dev/null || true; cat; } | cksum)"
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
