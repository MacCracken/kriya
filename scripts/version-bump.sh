#!/bin/sh
# kriya version-bump — single source of truth for all version references.
#
# Usage: sh scripts/version-bump.sh 0.2.0
#
# Touches:
#   - VERSION                              (the bare semver string)
#   - src/version_str.cyr                  (regenerated; banner + bare-version vars)
#   - docs/development/state.md            (`## Version` line + "Refreshed" date)
#
# Does NOT touch:
#   - cyrius.cyml                          (reads VERSION via ${file:VERSION})
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

# 3. docs/development/state.md — bump the `## Version` line and the
#    "Refreshed every release" footer if it carries a date.
if [ -f "$ROOT/docs/development/state.md" ]; then
    TODAY=$(date +%Y-%m-%d)
    # Match: `**X.Y.Z** — ...` at start of a line.
    sed -i -E "s#^\*\*[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?\*\* — #\*\*$NEW\*\* — #" "$ROOT/docs/development/state.md"
fi

echo "Bumped to $NEW."
echo "Next:"
echo "  - cyrius build src/main.cyr build/kriya"
echo "  - cyrius test"
echo "  - update CHANGELOG.md: add a [$NEW] section, move [Unreleased] entries into it, set the release date"
echo "  - git commit -am 'release: $NEW'"
echo "  - git tag v$NEW"
