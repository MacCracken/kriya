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
printf "line1\nline2\nline3\n" > "$follow_dir/log"
( sleep 0.4; echo "line4" >> "$follow_dir/log"; sleep 0.4; echo "line5" >> "$follow_dir/log" ) &
writer_pid=$!
out=$(timeout 1.4 "$BIN" tail -f -n 2 "$follow_dir/log" 2>/dev/null || true)
wait "$writer_pid" 2>/dev/null
expect_eq "tail -f appends" \
    "line2
line3
line4
line5" \
    "$out"

# Truncation detection: shrinking write emits the warning + new content.
printf "line-A\nline-B\nline-C\n" > "$follow_dir/big"
( sleep 0.4; printf "tiny\n" > "$follow_dir/big" ) &
writer_pid=$!
out_err=$(timeout 1.2 "$BIN" tail -f -n 1 "$follow_dir/big" 2>&1 || true)
wait "$writer_pid" 2>/dev/null
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
