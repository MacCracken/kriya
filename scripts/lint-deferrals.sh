#!/bin/sh
# lint-deferrals.sh — enforce the deferral-tracking rule across the WHOLE tree.
#
# ⛔ `cyrius lint` takes ONE FILE and does not follow includes, so the CI "Lint &
# vet" step could only ever cover `src/main.cyr` + `src/lib/`. The 38 files in
# `src/cmd/` — the actual utilities — went unlinted, and carried 56 untracked
# deferrals: comments saying "deferred", "follow-up", "TODO", "not yet" with no
# cross-reference to a roadmap or CHANGELOG entry. That is the bubble-up
# discipline the 1.2.x arc applied everywhere else, unenforced in the one
# directory where most of the code lives.
#
# ⚠ THIS CHECKS DEFERRALS ONLY, ON PURPOSE. cyrlint also warns on lines over 120
# characters, and `src/cmd/` has 45 of those — but **every one is a code line,
# and roughly half are single string literals** (`help_operands("…")`, long
# `k_write` diagnostics) that cannot be split without rewriting user-facing help
# text. Silencing them with `#skip-lint` would be 45 edits that buy nothing and
# make the linter's own signal weaker. The line-length rule is reported here and
# not enforced; the deferral rule is enforced. Enforcing the half that carries
# meaning beats enforcing neither while waiting to agree about the other.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
long_total=0

for f in src/main.cyr src/lib/*.cyr src/cmd/*.cyr; do
    out=$(cyrius lint "$f" 2>&1 || true)
    n=$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\) untracked deferrals$/\1/p')
    w=$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\) warnings$/\1/p')
    [ -n "$n" ] || n=0
    [ -n "$w" ] || w=0
    long_total=$((long_total + w))
    if [ "$n" -gt 0 ]; then
        fail=$((fail + n))
        printf '%s: %s untracked deferral(s)\n' "$f" "$n" >&2
        printf '%s\n' "$out" | grep 'deferral line' | sed 's/^/    /' >&2
    fi
done

if [ "$long_total" -gt 0 ]; then
    printf 'note: %s line-length warning(s) across the tree — reported, not enforced (see this script'"'"'s header)\n' "$long_total"
fi

# ⛔ A CROSS-REFERENCE THAT POINTS AT NOTHING IS WORSE THAN NONE — it satisfies
# the linter while telling a reader to go look somewhere that will not answer
# them. Every `roadmap N.N.N` written into the source must name a real entry.
missing=$(
  grep -rhoE 'roadmap [0-9]+\.[0-9]+\.[0-9]+' src/ 2>/dev/null \
    | sed 's/^roadmap //' | sort -u \
    | while read -r ver; do
        grep -q "\*\*$ver —" docs/development/roadmap.md || echo "$ver"
      done
)
if [ -n "$missing" ]; then
    printf 'dangling roadmap references (no such entry in docs/development/roadmap.md):\n' >&2
    printf '%s\n' "$missing" | sed 's/^/    /' >&2
    fail=$((fail + 1))
fi

if [ "$fail" -gt 0 ]; then
    printf '\nlint-deferrals: %s untracked deferral(s).\n' "$fail" >&2
    printf 'Each must either cross-reference a roadmap/CHANGELOG entry, or be marked #skip-lint\n' >&2
    printf 'when the words appear in an explanation rather than deferring anything.\n' >&2
    exit 1
fi

echo "lint-deferrals: OK — every deferral in the tree is tracked"
