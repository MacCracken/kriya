# 0007 — date defaults to UTC at v0.7.0; local-time tzfile parsing is a named follow-up

**Status**: Accepted
**Date**: 2026-05-18

## Context

POSIX `date(1)` defaults to **local time** — derived from the `TZ` environment variable, or, when `TZ` is unset, from the system's local tzfile (typically `/etc/localtime`, a binary file in the IANA tzdata format). GNU `date` shipped on Arch / Debian / etc. all behave this way. A user typing `date` on a US-East machine sees `EDT` or `EST` in the timezone slot; on a UTC system, `UTC`.

kriya `date` at v0.7.0 (M6 shipment) **defaults to UTC**, not local. The `-u` flag (UTC) is accepted but is a no-op — UTC was the only mode shipped.

The deviation has three causes:

1. **tzfile parsing is non-trivial.** The IANA tzfile format is a documented binary format with a header (`TZif`), transition tables, and POSIX-style fallback string. Parsing it in Cyrius is ~400 LOC of careful work — beyond what M6's "small system-info utilities" milestone budgeted.
2. **`TZ` env parsing is also non-trivial.** POSIX-style TZ strings (e.g. `EST5EDT,M3.2.0/2,M11.1.0/2`) encode DST rules in a compact grammar that needs its own parser. Even the simpler offset form (`UTC+5`) has edge cases.
3. **No tzfile dependency exists in Cyrius stdlib.** `chrono.cyr` ships `epoch_to_date` (UTC arithmetic on epoch seconds) but no timezone application. A reasonable kriya implementation would consume an upstream `chrono_tz.cyr` (or similar) when it lands, rather than re-implement the tzfile parser inline.

The audit catalogs this as the one *documented behavior deviation* among the 38 utilities — a POSIX-defined utility shipping with a different default. Every other utility is either POSIX-conformant for what it ships, or a non-POSIX scope extension (ADR 0006). `date`'s deviation needs its own ADR because the default differs.

## Decision

**`kriya date` defaults to UTC at v0.7.0.** The `-u` / `--utc` / `--universal` flag is accepted as a no-op (so existing scripts that pass `-u` continue to work). The deviation from POSIX's local-time default is documented in:

- `src/cmd/date.cyr` file header.
- `--help` output (when `--help` ships per ADR 0002's spec-renderer).
- The M7 audit deviation index.

**Local-time-aware operation is a named follow-up**, gated on either:

1. An upstream Cyrius stdlib `chrono_tz.cyr` module that parses `/etc/localtime` and applies offsets to epoch seconds, OR
2. A kriya-side `src/lib/tz.cyr` module if upstream doesn't move. The second path is fallback only — we prefer the upstream contribution.

When tzfile parsing lands, `-u` becomes meaningful (UTC vs. local) and the default flips to local time (matching POSIX). That's a behavior change worth a CHANGELOG `Breaking` note plus a deprecation cycle if scripts rely on the v0.7.0 UTC default — but real-world scripts that care about timezone universally pass `-u` explicitly, so the breakage surface is expected to be small.

## Consequences

**Positive:**

- M6 shipped on schedule. `date` is usable for the common scripting cases (`%s` epoch, `%Y-%m-%d` for build stamps, `%T` for log lines) without needing the tzfile machinery.
- UTC is the floor that requires no external state. A kriya init script in an AGNOS boot-burn that has no `/etc/localtime` yet still gets sensible `date` output — important for the boot-burn signal that's M6-adjacent.
- Scripts that pass `-u` work today and will continue to work after the tzfile machinery lands.

**Negative:**

- A user typing `date` on a UTC+8 system sees UTC, not their wall clock. This is a surprise vs. every other Linux `date(1)`.
- The M7 audit shows kriya at v0.7.0 has one POSIX-default deviation. Removes the otherwise-clean "POSIX-conformant for everything we ship" claim, requiring a footnote.

**Neutral:**

- Picks up upstream Cyrius work when it lands. The deferred-feature follow-up names the dependency explicitly (`lib/chrono.cyr` tzfile loader), not a TBD — per the [[concrete-commitments]] memory's "concrete over hedges" rule.

## Alternatives considered

- **Inline tzfile parser in M6.** Would have added ~400 LOC to M6 and pushed the milestone out by a session or two. Rejected: M6 was scoped for "system info + misc," not for "stdlib chrono extension." The work belongs upstream.
- **Read `TZ` env, support only UTC + fixed-offset (`UTC+8`).** Bridges the gap for users in fixed-offset zones (no DST). Considered and deferred: the implementation is ~80 LOC and might happen during the boot-burn cycle if a real consumer asks. v0.7.0 ships without it; the hold-open list will pick it up if it surfaces.
- **Refuse `date` without `-u`.** Forces every invocation to be explicit. Considered and rejected: too restrictive — `date +%s` is common and pure-epoch (timezone-irrelevant); refusing it would break legitimate scripts.
