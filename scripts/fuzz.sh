#!/bin/sh
# fuzz.sh — run all kriya fuzz harnesses.
#
# Each harness uses a deterministic xorshift PRNG with a fixed seed,
# so failures are replayable. The harnesses live in `tests/kriya-*.fcyr`
# and are NOT picked up by `cyrius test` default discovery — they're
# opt-in via this script (or a direct `cyrius test path` invocation).
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

echo "=== kriya fuzz suite ==="
echo ""

for f in kriya-grep kriya-find kriya-printf; do
    echo "--- $f ---"
    cyrius test "tests/$f.fcyr" 2>&1 | grep -E "passed|FAIL|fuzz:" | sed 's/^/  /'
    echo ""
done

echo "=== fuzz suite complete ==="
