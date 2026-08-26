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
# ⭐ AS OF 1.3.8 BOTH RULES ARE ENFORCED. This checked deferrals only while
# `src/cmd/` still carried 48 over-long lines. Nineteen of those were argument
# lists that simply wanted wrapping — the earlier judgement that "roughly half
# are single string literals" undercounted the wrappable half, and wrapping them
# turned out to be mechanical and verified by the compiler plus 3,774 smoke
# cases. The 29 that genuinely cannot be split are marked `#skip-lint`, each one
# a single `help_operands(…)` or `k_write` diagnostic whose length IS the text.
#
# ⚠ The marker is for a line whose length comes from ONE string literal. A new
# over-long line that is code should be WRAPPED, not marked.

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
    if [ "$w" -gt 0 ]; then
        fail=$((fail + w))
        printf '%s: %s line-length warning(s)\n' "$f" "$w" >&2
        printf '%s\n' "$out" | grep 'warn line' | sed 's/^/    /' >&2
    fi
    if [ "$n" -gt 0 ]; then
        fail=$((fail + n))
        printf '%s: %s untracked deferral(s)\n' "$f" "$n" >&2
        printf '%s\n' "$out" | grep 'deferral line' | sed 's/^/    /' >&2
    fi
done

# ⛔ A CROSS-REFERENCE THAT POINTS AT NOTHING IS WORSE THAN NONE — it satisfies
# the linter while telling a reader to go look somewhere that will not answer
# them. Every `roadmap N.N.N` written into the source must name a real entry.
#
# ⚠ M-numbers are checked too, and were NOT until 1.4.4. A deferral that outlives
# its release has to be repointed at something durable, and the gated sections are
# where it goes — `nl -b pBRE` moved from `roadmap 1.4.4` to `roadmap M11` the
# moment 1.4.4 shipped. Leaving M-numbers unchecked would have made "repoint it at
# an M-number" the way to launder a reference past this very check.
#
# ⚠ The suffix letter is load-bearing: `M12a` is a live reference while `M12` is
# not an entry at all, so matching only `M[0-9]+` truncates the first into the
# second and reports a dangling reference that is nothing of the kind. The three
# documented shapes all count: a `###` header for an open bucket, a TABLE ROW for
# a retired one, and a BOLD paragraph lead for an M15 watchlist item.
missing=$(
  grep -rhoE 'roadmap [0-9]+\.[0-9]+\.[0-9]+' src/ 2>/dev/null \
    | sed 's/^roadmap //' | sort -u \
    | while read -r ver; do
        grep -q "\*\*$ver —" docs/development/roadmap.md || echo "$ver"
      done
  grep -rhoE 'roadmap M[0-9]+[a-z]?' src/ 2>/dev/null \
    | sed 's/^roadmap //' | sort -u \
    | while read -r m; do
        grep -q "^### $m —" docs/development/roadmap.md && continue
        grep -q "\*\*$m —" docs/development/roadmap.md && continue
        grep -q "^| $m " docs/development/roadmap.md || echo "$m"
      done
)
if [ -n "$missing" ]; then
    printf 'dangling roadmap references (no such entry in docs/development/roadmap.md):\n' >&2
    printf '%s\n' "$missing" | sed 's/^/    /' >&2
    fail=$((fail + 1))
fi

if [ "$fail" -gt 0 ]; then
    # ⚠ Two rules share this counter, so the summary must not name only one of
    # them — it used to say "untracked deferral(s)" for a line-length warning,
    # which sent a reader looking for a deferral that was not there.
    printf '\nlint-deferrals: %s problem(s) above.\n' "$fail" >&2
    printf '  deferral   — cross-reference a roadmap/CHANGELOG entry, or mark #skip-lint when\n' >&2
    printf '               the words appear in an explanation rather than deferring anything.\n' >&2
    printf '  line >120  — wrap it. Mark #skip-lint only when the length is ONE string literal.\n' >&2
    exit 1
fi

echo "lint-deferrals: OK — every deferral tracked, every line within 120 columns"
