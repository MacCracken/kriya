# 0020 — `ls -l` dates are POSIX's, and ISO is one flag away

**Status**: Accepted
**Date**: 2026-09-22

## Context

From M3 until 1.6.12, `kriya ls -l` rendered every modification time as `2026-08-29 03:53`. That
is neither POSIX's form nor GNU's default; it is GNU's `--time-style=long-iso`. Nobody chose it
against the alternatives, and nothing recorded it: the roadmap carried the gap as *"decide whether to
match GNU or keep ISO-8601 — and if the latter, record it, because it is currently neither chosen nor
documented."*

POSIX does specify the field. From the `ls` STDOUT section:

> In the POSIX locale, the field shall be the equivalent of the output of the following date
> command: `date "+%b %e %H:%M"` if the file has been modified in the last six months, or:
> `date "+%b %e %Y"` (where two <space> characters are used between %e and %Y) if the file has not
> been modified in the last six months or if the modification date is in the future

GNU's default in the C locale is exactly that — `Sep 22 18:50`, `Jan  2  2020` — with "six months"
drawn at half a mean Gregorian year, 15,778,476 seconds, and a clock refresh for a file dated ahead
of it. GNU also offers `--time-style=full-iso|long-iso|iso|locale`, a `posix-` prefix on each, and
`--full-time`.

Three things made the choice real rather than a default:

1. **ISO sorts and parses; POSIX does not.** A recent date has no year, and a file crossing the
   six-month line changes the SHAPE of its column from `HH:MM` to `  YYYY`. That is why ISO was
   attractive in the first place.
2. **`ls -l` is parsed anyway**, however often that is discouraged, and the parsers are written
   against the POSIX form: `$6 $7 $8` is month, day and time-or-year on every system that ships GNU,
   BusyBox or a BSD `ls`. kriya's ISO form was two fields, so every such script read the wrong
   column — and the NAME moved from `$9` to `$8`.
3. **The value is a separate question.** [ADR 0007](0007-date-utc-only-at-v0-7-0.md) keeps every
   kriya time in UTC until a tzfile reader exists. That decides WHICH instant is printed; this ADR
   decides how it is spelled.

## Decision

**`ls -l` prints the date POSIX specifies, byte for byte GNU's `LC_ALL=C` rendering**:
`%b %e %H:%M` for a time strictly after now minus 15,778,476 s and strictly before now, and
`%b %e  %Y` (two spaces) for everything else, the future included. Still in UTC, per ADR 0007.

The other renderings are flags, as GNU's are:

- `--time-style=full-iso` (`2026-09-22 18:50:07.123456789 +0000`), `long-iso` (kriya's old
  default), `iso` (`09-22 18:50`, or `2020-01-02 ` padded to the same width), `locale` (the
  default).
- `posix-STYLE` means "STYLE outside the POSIX locale". kriya has no locale, so it is always inside
  one and every `posix-` style — even an unknown one, as under GNU in the C locale — is the default.
- `--full-time` is `-l --time-style=full-iso`.
- An unknown style under `-l` is a usage error, exit 2. Without `-l` the style is not read at all,
  as GNU's is not.

**Not in scope, and refused rather than approximated**: `--time-style=+FORMAT` and the
`TIME_STYLE` variable. Both need a strftime renderer, which `date` already half-has; they belong
with `date`'s own specifier work at roadmap 1.8.4. `+FORMAT` exits 2 with a message naming that
slot, and `TIME_STYLE` is not read. ⚠ When it lands, `TIME_STYLE` passes
[ADR 0017](0017-environment-variables-configure-features-the-caller-turned-on.md)'s test: it changes
nothing without `-l`.

## Consequences

- **Positive** — `ls -l` is byte-identical to GNU's under `TZ=UTC LC_ALL=C`, and `smoke-ls.sh` now
  says so for whole listings rather than for the columns before the date. Every script written
  against POSIX-shaped `ls -l` reads kriya correctly.
- **Positive** — the rendering that suits machines is still one flag away and is stable across the
  six-month line: `--time-style=long-iso` for the old form, `--full-time` for nanoseconds.
- **Negative — BREAKING.** A script that parsed kriya's ISO date, or took the name from `$8`, reads
  the wrong fields. Migration: add `--time-style=long-iso`, which restores the old date column
  byte for byte. ⚠ Not the old LISTING: the same release added GNU's `total N` line and its
  shared column widths, and those are not behind the flag.
- **Negative** — the POSIX form is ambiguous across years for recent files and changes shape at six
  months. That is the standard's trade-off, accepted here because kriya's floor is POSIX; the ISO
  styles exist for a caller who needs otherwise.
- **Neutral** — month names are always English. There is no locale to translate them with; GNU in
  the C locale agrees.

## Alternatives considered

- **Keep ISO as the default and document it.** Rejected: it is a divergence from POSIX in a
  utility's default output, which CLAUDE.md allows only with a reason, and the only reason on offer
  is parseability — which a flag already provides without breaking every POSIX-shaped parser.
- **POSIX shape, but always with the year.** Rejected: it matches nobody. A third format would break
  scripts written for either of the other two.
- **Honour `TIME_STYLE` now.** Deferred, not rejected: without `+FORMAT` it could only select the
  four named styles, and a variable that half-works — `TIME_STYLE=+%F` silently ignored — is worse
  than one not yet read.
