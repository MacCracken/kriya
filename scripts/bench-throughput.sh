#!/bin/sh
# bench-throughput.sh — per-utility throughput comparison vs GNU.
#
# Builds a deterministic test corpus under WORK, runs kriya and GNU
# against representative workloads, reports best-of-3 wall clock plus
# ratio. Feeds docs/benchmarks.md at each release boundary.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CORPUS_100M="$WORK/corpus_100m.txt"
CORPUS_10M="$WORK/corpus_10m.txt"
CORPUS_1M="$WORK/corpus_1m.txt"

python3 -c '
for i in range(65536):
    print(f"line-{i:010d}")
' > "$CORPUS_1M"

for i in $(seq 1 10);  do cat "$CORPUS_1M" >> "$CORPUS_10M"; done
for i in $(seq 1 100); do cat "$CORPUS_1M" >> "$CORPUS_100M"; done

TREE="$WORK/tree"
mkdir -p "$TREE"
for i in $(seq 1 100); do
    mkdir -p "$TREE/d$i"
    for j in $(seq 1 100); do
        : > "$TREE/d$i/f$j"
    done
done

# Time a single run via date +%s%N (ns precision), return seconds with
# 3-decimal precision.
time_one() {
    t0=$(date +%s%N)
    "$@" >/dev/null 2>&1 || true
    t1=$(date +%s%N)
    awk -v t0="$t0" -v t1="$t1" 'BEGIN { printf "%.3f\n", (t1-t0)/1000000000.0 }'
}

# Median of 3 runs.
time_med3() {
    t1=$(time_one "$@")
    t2=$(time_one "$@")
    t3=$(time_one "$@")
    printf "%s\n%s\n%s\n" "$t1" "$t2" "$t3" | /usr/bin/sort -n | sed -n '2p'
}

ratio() {
    awk -v k="$1" -v g="$2" 'BEGIN { if (g+0 > 0) printf "%.2fx\n", k/g; else print "n/a" }'
}

bench_pair() {
    label=$1
    shift
    util=$1
    shift
    k=$(time_med3 "$BIN" "$util" "$@")
    g=$(time_med3 /usr/bin/"$util" "$@")
    r=$(ratio "$k" "$g")
    printf "  %-32s kriya %ss  GNU %ss  ratio %s\n" "$label" "$k" "$g" "$r"
}

echo "kriya throughput vs GNU (best of 3, wall clock, seconds)"
echo "========================================================"
echo "build/kriya: $(stat -c %y "$BIN")"
echo ""

echo "[wc]"
bench_pair "wc -l 100M"    wc -l "$CORPUS_100M"
bench_pair "wc -c 100M"    wc -c "$CORPUS_100M"
bench_pair "wc -w 100M"    wc -w "$CORPUS_100M"
echo ""

echo "[grep]"
bench_pair "grep literal 10M"   grep "line-0000005678" "$CORPUS_10M"
bench_pair "grep regex 10M"     grep -E "line-0+5678"  "$CORPUS_10M"
bench_pair "grep -F fixed 10M"  grep -F "line-0000005678" "$CORPUS_10M"
echo ""

echo "[sort]"
bench_pair "sort 1M"       sort "$CORPUS_1M"
echo ""

echo "[find]"
bench_pair "find 10K-tree" find "$TREE"
echo ""

echo "[cp]"
CP_DST="$WORK/cp_dst"
bench_pair "cp 10M file"   cp "$CORPUS_10M" "$CP_DST"
echo ""

echo "[head/tail]"
bench_pair "head -n 100 10M" head -n 100 "$CORPUS_10M"
bench_pair "tail -n 100 10M" tail -n 100 "$CORPUS_10M"
echo ""

echo "done"
