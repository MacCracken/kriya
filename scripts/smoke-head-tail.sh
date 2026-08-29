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
