#!/bin/sh
# bench-coldstart.sh — measure end-to-end process spawn cost for the
# dispatcher. Reports min/median/max of `./build/kriya true`.
#
# In-process bench numbers (tests/kriya.bcyr) measure warm steady-
# state; they don't include ELF startup, `args_init()` reading
# /proc/self/cmdline, the heap bootstrap, or kernel exec(). This
# script does.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"
RUNS=${RUNS:-100}

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# ⛔ THE OBVIOUS LOOP IS WRONG, AND WAS WRONG FOR TEN RELEASES.
#
#     t0=$(date +%s%N); "$BIN" true; t1=$(date +%s%N)
#
# The span from t0 to t1 contains the kriya exec AND the whole `date` process
# that produces t1 — a fork+exec of GNU coreutils, measured here at ~0.57 ms
# against kriya's ~0.43 ms. So the per-iteration form reported roughly 1.4 ms
# for a 0.43 ms spawn: about 60% of every historical figure in state.md is
# `date`, not kriya, and cross-machine comparisons mostly compared how fast
# `date` forks there.
#
# ⭐ Fix: put the timestamps OUTSIDE a batch of N runs, so the two `date` forks
# are amortised to ~2 µs each at N=300, and subtract a control batch that runs
# the same loop with no kriya call — removing the shell's own per-iteration
# cost. What is left is the spawn.

batch() {   # batch <n> <cmd...>; echoes elapsed ns
    _n=$1; shift
    _t0=$(date +%s%N)
    _i=0
    while [ "$_i" -lt "$_n" ]; do
        "$@" > /dev/null 2>&1
        _i=$((_i + 1))
    done
    _t1=$(date +%s%N)
    echo $((_t1 - _t0))
}

control() { # control <n>; the same loop with no spawn
    _n=$1
    _t0=$(date +%s%N)
    _i=0
    while [ "$_i" -lt "$_n" ]; do
        _i=$((_i + 1))
    done
    _t1=$(date +%s%N)
    echo $((_t1 - _t0))
}

# Warm the page cache; a first-touch exec is not what we are measuring.
i=0
while [ "$i" -lt 20 ]; do "$BIN" true > /dev/null 2>&1; i=$((i + 1)); done

TOTAL=$(batch "$RUNS" "$BIN" true)
CTRL=$(control "$RUNS")
NET=$((TOTAL - CTRL))
PER=$((NET / RUNS))

printf "kriya true cold-start (%s runs, batch-timed):\n" "$RUNS"
printf "  per spawn:   %s ns  (%.3f ms)\n" "$PER" \
    "$(echo "$PER" | awk '{ printf "%.3f", $1 / 1000000 }')"
printf "  loop control: %s ns total (%s ns/iter, subtracted)\n" "$CTRL" "$((CTRL / RUNS))"

# `kriya --list` enumerates all 38 utilities in ONE process. agnoshi reads it at
# shell startup, so its cost is budgeted separately from a plain dispatch.
LIST_TOTAL=$(batch "$RUNS" "$BIN" --list)
LIST_PER=$(((LIST_TOTAL - CTRL) / RUNS))
printf "  kriya --list: %s ns  (%.3f ms)  [+%.3f ms to enumerate 38]\n" "$LIST_PER" \
    "$(echo "$LIST_PER" | awk '{ printf "%.3f", $1 / 1000000 }')" \
    "$(echo "$LIST_PER $PER" | awk '{ printf "%.3f", ($1 - $2) / 1000000 }')"

# ⚠ The pre-1.3.2 per-iteration figures in docs/development/state.md are NOT
# comparable to these: they include one `date` fork each. Compare release to
# release with both binaries measured by the same tool, never an absolute
# against that history.
