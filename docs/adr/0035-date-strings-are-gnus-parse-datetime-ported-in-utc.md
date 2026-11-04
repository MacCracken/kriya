# 0035 — Date strings are GNU's `parse_datetime`, ported, in UTC

**Status**: Accepted
**Date**: 2026-11-04

## Context

Until 1.9.3, neither kriya's `date` nor its `touch` took `-d`; both refused it, exit 2.
- POSIX gives `touch` a `-d date_time`, an ISO 8601 stamp (`YYYY-MM-DDThh:mm:SS[.frac][Z]`). It gives `date` no `-d`.
- GNU gives both utilities `-d STRING`, a free-form date read by gnulib's `parse_datetime`.
- Scripts use its phrases: `date -d yesterday +%F`, `date -d '1 day ago'`, `date -d @1700000000`,
  `touch -d '2 days ago' stamp`.

`parse_datetime` is a bison grammar with a hand-written lexer and word tables (`parse-datetime.y`, 2,473 lines as
coreutils 9.12 builds it). Many of its answers are not what a reader would guess:
- `2024` alone is 20:24 today.
- A lone `x` is the military zone X, UTC−11.
- `+90 minutes` right after a time is read as a zone offset, and refused.
- `next friday` on a Friday is a week away.
- `Feb 30` is refused.
- A two-digit year falls in 1969–2068.

Between 9.4 and 9.12 the grammar changed once. 9.11 added `DD.MM.YYYY` and `DD.MM.` dates (its
NEWS); the rest of the diff is `--debug` messages. Cyrius's `dt_strptime` needs a format string, so
it cannot stand in.

The roadmap advised a documented subset instead: ISO 8601, `@epoch`, `now`, `HH:MM[:SS]`.

## Decision

**kriya reads a date string with gnulib's `parse_datetime`, as coreutils 9.12 builds it, ported rule
for rule into `src/lib/datetime.cyr`, with UTC as the local time zone.** `date -d STRING` and
`touch -d STRING` use it, as GNU's do.

The port covers:
- the lexer;
- `lookup_word`'s tables: months, days, units, the relative words, GNU's 47 zones and the
  military letters;
- every grammar item, each making bison's shift choice with one token of look-ahead;
- the arithmetic of `parse_datetime_body`:
  - defaults taken from now, nanoseconds included;
  - `mktime`'s rule that every field is already in range;
  - a weekday applied only without a date;
  - relative years, months and days added and then normalized;
  - the zone;
  - then relative hours, minutes, seconds and nanoseconds.

Output follows glibc's `strftime` for the years `-d` can now reach. `%Y` pads to four characters,
the sign counted among them (`-001`). `%F` writes a `+` past 9999. A year outside glibc's `tm_year`
range is *time … is out of range*, exit 1, as in GNU.

For `touch`:
- `-d` sets both times, and `-a` or `-m` selects one.
- With `-r`, the string is read relative to the reference's atime and mtime, each separately, as in
  GNU.
- `-d` with `-t`, and `-t` with `-r`, are refused (GNU: *cannot specify times from more than one
  source*).
- `-d now` without `-a` or `-m` is the current time set by the kernel, as GNU arranges.

Four choices differ from GNU, and `smoke-date.sh` and `smoke-touch.sh` assert each:

- **The local zone is UTC** ([ADR 0007](0007-date-utc-only-at-v0-7-0.md)). A string without a zone is read
  as UTC, where GNU uses `TZ` or `/etc/localtime`. Under `TZ=UTC`, which is what every test sets,
  the two agree.
- **A leading `TZ="ZONE"` is refused**, exit 2, with a message naming ADR 0007. GNU loads that
  zone from tzdata, which kriya does not read. It is refused rather than skipped, because skipping
  it would print a wrong time at exit 0.
- **An invalid date exits 2**, kriya's usage error ([ADR 0008](0008-posix-exit-code-policy.md)), as
  do the conflicting `touch` sources; GNU exits 1. A valid date whose year is out of range exits 1,
  as in GNU.
- **`DD.MM.YYYY` is read on every host.** kriya follows 9.12; GNU before 9.11 refuses those strings.

`--debug` is not implemented. It is refused as an unknown option, exit 2.

## Consequences

- **Positive**
  - GNU's answer, to the nanosecond, on every string tested:
    - 106 of the 107 probe strings agree with GNU 9.12; the 107th is the `TZ=` refusal;
    - 18,000 fuzz cases on 9.12 show 0 differences;
    - on 9.4 and 9.7 the only differences are the dotted dates those releases predate.
  - `touch` gains POSIX's `-d`, and GNU's phrases with it, including `-r FILE -d '+1 day'`.
  - `date +%N` prints the real nanoseconds; it printed nine zeros. `touch -r` copies the
    reference's nanoseconds; it dropped them.
- **Negative**
  - 1,197 lines of parser, where the subset would have been a few hundred.
  - GNU's surprising answers come with the port, on purpose. The alternative is a different
    surprising answer, which a script written against GNU would not expect.
  - On a host whose local zone is not UTC, `date -d 10:30` differs from GNU's answer by the offset.
    This is the deviation `date` already has (ADR 0007).
- **Neutral**
  - Local time (roadmap § Gated, chrono) plugs in where GNU's parser asks for the local zone: its
    zone names, its daylight rule, and `TZ="…"`.

## Alternatives considered

- **The roadmap's subset.** A subset must refuse the strings scripts use (`yesterday`,
  `1 day ago`, `next monday`, `2024-01-15 +1 day`). Otherwise it grows toward GNU one case at a
  time, with rules of its own that can differ from GNU's at exit 0.
  - Even the strings a subset keeps carry GNU's rules: `2024-01-15 10:30 +05` is a zone, and
    `10:30 +90 minutes` is refused.
  - A port can be fuzzed against GNU down to zero differences; an independent subset can only
    be compared over the strings someone thought of.
- **chrono's `dt_strptime`.** It needs a format; GNU's input has none.
- **9.4's grammar, without dotted dates, to match ubuntu 24.04.** Rejected: 9.12 is GNU's current
  release. The two differ only where old GNU refuses a string and kriya reads it. They never
  disagree on a string both accept.
