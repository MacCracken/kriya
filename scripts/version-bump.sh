#!/bin/sh
# kriya version-bump — single source of truth for all version references.
#
# Usage: sh scripts/version-bump.sh 0.2.0
#
# Touches:
#   - VERSION                              (the bare semver string)
#   - src/version_str.cyr                  (regenerated; banner + bare-version vars)
#   - docs/development/state.md            (INSERTS a stub `## Version` entry above the
#                                           newest one; syncs the `## Toolchain` Cyrius-pin
#                                           line from cyrius.cyml)
#
# Does NOT touch:
#   - existing `## Version` entries        (released history is APPEND-ONLY — see §3a; the
#                                           inserted entry's prose is written by hand)
#   - cyrius.cyml                          (version comes from `${file:VERSION}`; the
#                                           `[package].cyrius` pin is READ here, never written)
#   - CHANGELOG.md                         (manual; per-release section is human-curated)
#   - ADRs / arch notes                    (point-in-time docs; references stay frozen)
#
# Mirrors the cyrius `scripts/version-bump.sh` pattern (single SoT,
# regenerated files marked AUTO-GENERATED in their header).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Current: $(cat "$ROOT/VERSION")"
    exit 1
fi

NEW="$1"
OLD=$(cat "$ROOT/VERSION" | tr -d '[:space:]')

# Validate semver (X.Y.Z with optional -prerelease suffix).
echo "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$' || {
    echo "error: '$NEW' is not valid semver" >&2
    exit 1
}

if [ "$NEW" = "$OLD" ]; then
    echo "Already at $OLD"
    exit 0
fi

echo "Bumping $OLD -> $NEW"

# 1. VERSION file — source of truth. cyrius.cyml reads this via
#    `version = "${file:VERSION}"`; no edit needed there.
echo "$NEW" > "$ROOT/VERSION"

# 2. src/version_str.cyr — regenerated each bump. Byte length computed
#    inline so the writer never needs strlen() at the print site.
KSTR="kriya $NEW"
KSTR_NL="$KSTR
"
# `wc -c` on the newline-bearing string gives total bytes including
# the trailing \n that we hand to write(2).
KLEN=$(printf "%s\n" "$KSTR" | wc -c | tr -d '[:space:]')
cat > "$ROOT/src/version_str.cyr" <<EOF
# src/version_str.cyr — AUTO-GENERATED from \`VERSION\` by
# \`scripts/version-bump.sh\`. Do NOT edit by hand; the next bump
# will overwrite. To regenerate without bumping, run:
#
#   sh scripts/version-bump.sh "\$(cat VERSION)"
#
# Single source of truth for the kriya version string. Consumers
# (\`kriya --version\`, dispatcher banner, future help-text headers)
# reference these vars instead of baking the literal in. Mirrors the
# cyrius \`src/version_str.cyr\` pattern (which exists because
# pre-v5.6.39 the per-binary literals drifted across hotfix bumps).
#
# \`_VERSION_LEN_KRIYA\` is the BYTE length of \`_VERSION_STR_KRIYA\`
# including the trailing \`\\n\` — used directly with \`syscall(1, fd,
# &str, len)\` so the writer never needs \`strlen()\` at the version
# print site.

var _VERSION_STR_KRIYA = "$KSTR\\n";
var _VERSION_LEN_KRIYA = $KLEN;
var _VERSION_KRIYA     = "$NEW";
EOF

# 3. docs/development/state.md — two independent edits (3a entry, 3b pin).
STATE="$ROOT/docs/development/state.md"

# Shape of a `## Version` entry line: `**X.Y.Z** — released DATE. …`.
# Written with bracket expressions rather than backslash escapes so the same
# pattern is safe through `awk -v` (which runs escape processing over the
# assignment, and would eat `\*`) as well as `grep -E`.
ENTRY_RE='^[*][*][0-9]+[.][0-9]+[.][0-9]+(-[a-zA-Z0-9.]+)?[*][*] — '

if [ -f "$STATE" ]; then
    TODAY=$(date +%Y-%m-%d)

    # 3a. `## Version` — INSERT a stub entry above the newest one.
    #
    # ⛔ THE `## Version` SECTION IS APPEND-ONLY RELEASE HISTORY, NOT A "current version"
    # FIELD. It is a REVERSE-CHRONOLOGICAL LIST of *released* entries — newest on top, every
    # prior release below it, each opening with the same `**X.Y.Z** — released DATE.` shape.
    # Two consecutive cuts were damaged by editing it with `sed s###`, the second a narrower
    # instance of the first:
    #
    #   at 1.1.9  — an UNADDRESSED `s###` applied to EVERY line it matched, so each bump
    #               silently renumbered all of history to the new version, leaving a run of
    #               identically-numbered entries carrying different dates and different
    #               content. By the time it was caught, seven headings had been flattened;
    #               they were reconstructed from CHANGELOG.md, which is hand-curated and was
    #               therefore untouched. Fixed by bounding the substitution with `0,/re/`.
    #   at 1.1.10 — `0,/re/` correctly stopped the flattening, but the substitution still
    #               REWROTE THE FIRST heading IN PLACE: `**1.1.9** — released 2026-08-11.`
    #               became `**1.1.10** — released 2026-08-11.` still sitting above 1.1.9's
    #               prose, and 1.1.9 disappeared from the file entirely. Repaired by hand in
    #               the 1.1.10 commit.
    #
    # Both are invisible at bump time (the script prints "Bumped to X" and exits 0) and only
    # surface when a human next reads the file. So the fix targets the family, not the
    # instance: this script only ever INSERTS a new entry above the current top one and never
    # edits a line it did not just write. The stub's prose is a TODO for the human — release
    # summaries are hand-curated from CHANGELOG.md. If the top entry is already $NEW the
    # insert is skipped, so re-running the bump is safe.
    TOP=$(awk -v re="$ENTRY_RE" '$0 ~ re { v = $1; gsub(/[*]/, "", v); print v; exit }' "$STATE")
    STUB="**$NEW** — released $TODAY. **TODO: release summary.** Write it by hand from CHANGELOG.md \`[$NEW]\` — \`scripts/version-bump.sh\` inserts the entry, never the prose."

    if [ "$TOP" = "$NEW" ]; then
        echo "  state.md: '## Version' already opens with $NEW — nothing inserted"
    else
        TMP="$STATE.bump.$$"
        if [ -n "$TOP" ]; then
            # Normal path: insert above the newest existing entry.
            awk -v re="$ENTRY_RE" -v stub="$STUB" '
                !ins && $0 ~ re { print stub; print ""; ins = 1 }
                { print }
            ' "$STATE" > "$TMP" || { rm -f "$TMP"; exit 1; }
        elif grep -q '^## Version[[:space:]]*$' "$STATE"; then
            # Empty history: anchor on the section heading instead, absorbing the
            # blank line that follows it so spacing stays one-blank-between-entries.
            awk -v stub="$STUB" '
                !ins && /^## Version[[:space:]]*$/ {
                    print; print ""; print stub; print ""
                    ins = 1; eatblank = 1
                    next
                }
                eatblank { eatblank = 0; if ($0 == "") next }
                { print }
            ' "$STATE" > "$TMP" || { rm -f "$TMP"; exit 1; }
        else
            rm -f "$TMP"
            echo "  ⚠ state.md: no '## Version' section found — add the $NEW entry by hand" >&2
            TMP=""
        fi

        if [ -n "$TMP" ]; then
            # Copy back through the original file (not `mv`) so its mode, ownership
            # and inode survive; $TMP is already a complete, valid file here.
            cat "$TMP" > "$STATE" || { rm -f "$TMP"; exit 1; }
            rm -f "$TMP"
            NOW_TOP=$(awk -v re="$ENTRY_RE" '$0 ~ re { v = $1; gsub(/[*]/, "", v); print v; exit }' "$STATE")
            if [ "$NOW_TOP" = "$NEW" ]; then
                if [ -n "$TOP" ]; then
                    echo "  state.md: inserted a $NEW entry above $TOP (prose is yours to write)"
                else
                    echo "  state.md: inserted a $NEW entry under '## Version' (prose is yours to write)"
                fi
            else
                echo "  ⚠ state.md: $NEW entry insert did not take — add it by hand" >&2
            fi
        fi
    fi

    # 3b. `## Toolchain` Cyrius pin — a MIRROR of cyrius.cyml `[package].cyrius`, which is
    # the single source of truth (CI derives the installer version from it). Nothing kept the
    # two in sync and nothing failed when they diverged, so the doc line sat at `6.4.20` through
    # BOTH the 1.1.9 bump (6.4.20 → 6.5.18) and the 1.1.10 bump (6.5.18 → 6.5.35) — two pin
    # bumps stale, caught only by eye at the 1.1.10 cut. Read the manifest and rewrite the doc
    # line to match; the manifest itself is never written here.
    PIN=$(awk -F'"' '
        /^[[:space:]]*\[/ { in_pkg = ($0 ~ /^[[:space:]]*\[package\][[:space:]]*$/) }
        in_pkg && /^[[:space:]]*cyrius[[:space:]]*=/ { print $2; exit }
    ' "$ROOT/cyrius.cyml")
    DOC_PIN=$(sed -n -E 's/^- \*\*Cyrius pin\*\*: `([^`]*)`.*/\1/p' "$STATE" | head -1)

    if [ -z "$PIN" ]; then
        echo "  ⚠ state.md: no [package].cyrius pin in cyrius.cyml — pin line left alone" >&2
    elif ! echo "$PIN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
        echo "  ⚠ state.md: cyrius.cyml pin '$PIN' is not semver — pin line left alone" >&2
    elif [ -z "$DOC_PIN" ]; then
        echo "  ⚠ state.md: no '- **Cyrius pin**: \`X.Y.Z\`' line under ## Toolchain — add it by hand ($PIN)" >&2
    elif [ "$DOC_PIN" = "$PIN" ]; then
        echo "  state.md: Cyrius pin already in sync ($PIN)"
    else
        # `0,/re/`-bounded like every other substitution in this file — the line is unique
        # today, and an unaddressed `s###` is exactly how §3a's history got flattened.
        sed -i -E "0,/^- \*\*Cyrius pin\*\*: /s|(^- \*\*Cyrius pin\*\*: \`)[^\`]*|\1$PIN|" "$STATE"
        NOW_PIN=$(sed -n -E 's/^- \*\*Cyrius pin\*\*: `([^`]*)`.*/\1/p' "$STATE" | head -1)
        if [ "$NOW_PIN" = "$PIN" ]; then
            echo "  state.md: Cyrius pin $DOC_PIN -> $PIN (from cyrius.cyml)"
        else
            echo "  ⚠ state.md: Cyrius pin rewrite did not take ($DOC_PIN, want $PIN)" >&2
        fi
    fi
fi

echo "Bumped to $NEW."
echo "Next:"
echo "  - cyrius build src/main.cyr build/kriya"
echo "  - cyrius test"
echo "  - update CHANGELOG.md: add a [$NEW] section, move [Unreleased] entries into it, set the release date"
echo "  - fill in the docs/development/state.md [$NEW] entry (stub inserted above the previous release; prose is hand-written)"
echo "  - git commit -am 'release: $NEW'"
echo "  - git tag v$NEW"
