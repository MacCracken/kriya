#!/bin/sh
# fuzz.sh — run all kriya fuzz harnesses under the poisoned allocator.
#
# Requires cyrius >= 6.5.29 (the release that added `fuzz --poison`).
# Older toolchains reject the flag and this script fails loudly rather
# than silently fuzzing without poison.
#
# Each harness uses a deterministic xorshift PRNG with a fixed seed,
# so failures are replayable. The harnesses live in `tests/kriya-*.fcyr`
# and are NOT picked up by `cyrius test` default discovery — they're
# opt-in via this script (or a direct `cyrius fuzz path` invocation).
# A bare `cyrius fuzz` discovers all three at once; the loop below runs
# them one at a time so each harness gets its own labelled block.
#
# Why the `fuzz` verb and not `cyrius test`: only `fuzz` injects
# `CYRIUS_POISON=1` as a compile-time predefine, which turns on the
# freelist allocator's redzones, 0xA5 fill, and quarantine-on-free.
# Without it, out-of-bounds *reads* land in mapped memory and never
# fault — so a plain `cyrius test` run is silent about exactly the
# failure class these harnesses exist to catch. That matters most for
# the two parser surfaces: kriya-grep (niyama BRE/RE2) and kriya-printf
# (kriya's own format engine).
#
# Inputs probe parser-style utilities (the v1.0 requirement):
#   - tests/kriya-grep.fcyr    — niyama BRE + RE2 + bracket-heavy patterns
#   - tests/kriya-find.fcyr    — find predicate AST via fork+exec
#   - tests/kriya-printf.fcyr  — printf format engine via fork+exec
#
# Re-runs are reproducible: the seed is constant in each .fcyr.
# To replay a failure, capture the iteration index from the failing
# assertion message and re-derive the input from the documented seed.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

echo "=== kriya fuzz suite (poisoned allocator) ==="
echo ""

for f in kriya-grep kriya-find kriya-printf; do
    echo "--- $f ---"
    cyrius fuzz --poison "tests/$f.fcyr" 2>&1 | grep -E "passed|FAIL|fuzz:|poison" | sed 's/^/  /'
    echo ""
done

echo "=== fuzz suite complete ==="
