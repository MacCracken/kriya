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

i=0
while [ "$i" -lt "$RUNS" ]; do
    # `time -f %e` is GNU; portable alternative: shell's builtin `time`
    # output is human-formatted. We use `date +%s%N` deltas for ns
    # granularity, which is portable across busybox/coreutils.
    t0=$(date +%s%N)
    "$BIN" true
    t1=$(date +%s%N)
    echo $((t1 - t0)) >> "$TMP"
    i=$((i + 1))
done

# Compute min, median, max from the collected ns values.
sort -n "$TMP" > "$TMP.sorted"
COUNT=$(wc -l < "$TMP.sorted")
MIN=$(head -1 "$TMP.sorted")
MAX=$(tail -1 "$TMP.sorted")
MID=$(( (COUNT + 1) / 2 ))
MEDIAN=$(sed -n "${MID}p" "$TMP.sorted")

printf "kriya true cold-start (%s runs):\n" "$RUNS"
printf "  min:    %s ns  (%.3f ms)\n" "$MIN"    "$(echo "$MIN / 1000000"    | awk '{ printf "%.3f", $1 / 1000000 }')"
printf "  median: %s ns  (%.3f ms)\n" "$MEDIAN" "$(echo "$MEDIAN / 1000000" | awk '{ printf "%.3f", $1 / 1000000 }')"
printf "  max:    %s ns  (%.3f ms)\n" "$MAX"    "$(echo "$MAX / 1000000"    | awk '{ printf "%.3f", $1 / 1000000 }')"
