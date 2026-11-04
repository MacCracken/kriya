# 0033 — `sort` compares keys as GNU's `keycompare` does, in the C locale

**Status**: Accepted; amended at 1.9.2 (past memory: temporary runs, `-S`, `-T`)
**Date**: 2026-11-04

## Context

Until 1.9.1 kriya's `sort` had one key, the letters `-n -r -u -f -b`, and refusals for the rest:
a key's own letters (`-k2,2n`), character offsets (`-k1.3`), and the GNU orderings `-g -h -M -V -R`,
with `-d`, `-i` and `-m`. A repeated `-k` kept only the last key, at exit 0. Filling those in is a
choice between three specifications that disagree:

- **POSIX** defines `-b -d -f -i -n -r`, `-k`, `-t`, `-c`, `-C`, `-m`, `-o` and `-u`. It leaves open
  what an end position past its field means (`-k1,1.5` of `ab cd`), says a sort key with both `-d`
  and `-n` is undefined, and has no `-g -h -M -V -R -s -z`.
- **GNU's `sort`** has all of them, and is what scripts on Linux are written against. Its key code
  (`begfield`, `limfield`, `keycompare`, `compare`) has rules no manual states in full: an end
  position counts characters to the end of the LINE, not of the field; a key with no letters of its
  own takes every global one, `-r` included, and a key with any letter takes none; `-d`, `-i`, `-V`
  and `-R` count as one ordering between them, and two orderings are refused.
- **The C locale** is the only one kriya has. GNU's results under `LC_ALL=C` are therefore the ones
  kriya can match.

## Decision

**kriya's `sort` orders lines with GNU's `keycompare` and `compare`, ported function for function,
in the C locale.** Every key, letter and option GNU takes under `LC_ALL=C` gives GNU's order, and
each comparator is the one GNU calls:

- **Fields and keys**: `begfield` and `limfield` as GNU writes them, with GNU's blanks (space, tab
  and, under `-z`, newline). Every `-k` is one more key, in command-line order. A field or offset too
  large for an i64 saturates, as GNU saturates at SIZE_MAX.
- **`-n`**: `strnumcmp`, the digit strings compared, never converted.
- **`-g`**: `strtold`, the x86 `long double` read by `src/lib/xfloat.cyr`
  ([ADR 0032](0032-floats-are-the-x86-extended-format-computed-in-integers.md)): conversion errors
  first, then NaNs (`-nan` before `nan`), then numbers.
- **`-h`**: the unit table, none < K (or k) < M < G < T < P < E < Z < Y < R < Q, then `strnumcmp`.
- **`-M`**: `JAN` to `DEC` in any case after blanks, anything else before them.
- **`-V`**: gnulib's `filenvercmp`, ported in `src/lib/vercmp.cyr`.
- **`-R`**: the MD5 of a 16-byte salt followed by the key, `src/lib/md5.cyr`, ties broken by the
  key's bytes. The salt is `--random-source=FILE`'s first 16 bytes, or `getrandom`.
- **`-d`, `-i`, `-f`**: GNU's tables, and GNU's order of application: the key is copied with the
  ignored bytes dropped and the folded ones mapped before `-h`, `-V` or `-R` reads it.
- **`-m`**: GNU's `mergefps` order: the smallest current line, a tie to the earlier file. Lines are
  not sorted within a file.
- **Refusals**: two orderings on one key (`-nd`, `-k1gM`) are refused with GNU's message, as are
  GNU's malformed specs and its `-t`, `-o`, `--random-source` and `-c`/`-C` conflicts.

Exit status is POSIX's: 0, 1 when `-c` or `-C` finds disorder, and 2 for every error. Until 1.9.1 a
file that could not be read exited 1, which under `-c` is the answer "not sorted".

**Two choices are not GNU 9.4's or not GNU's at all, and both are asserted in `smoke-sort.sh`:**

- A bad `--check=WORD` or `--sort=WORD` exits 2, kriya's usage error
  ([ADR 0008](0008-posix-exit-code-policy.md)). GNU's `argmatch` exits 1, which for `--check` is
  the disorder status.
- A character offset near SIZE_MAX gives GNU 9.7's and 9.12's order. GNU 9.4 overflowed a pointer
  adding it and answered otherwise, which GNU 9.10's NEWS records as fixed.

## Consequences

- **Positive**
  - Byte-identical to GNU in the C locale. `scripts/difffuzz-sort.py` runs random keys, letters and
    modes over inputs of numbers, units, months, versions and control bytes; on 1.9.1's final build,
    36,000 cases against coreutils 9.4, 9.7 and 9.12 gave 0 differences.
  - `sort -R --random-source=FILE` is GNU's shuffle exactly, so a shuffled order can be compared
    against GNU and reproduced, and `-R` keeps lines with equal keys together, as GNU's does.
  - One implementation of each GNU rule, with the GNU function it ports named beside it.
- **Negative**
  - About 2,000 lines to maintain: `sort.cyr` 1,704, `md5.cyr` 182 and `vercmp.cyr` 159, against
    `sort.cyr`'s 928 before. The shuffle uses MD5 because GNU does; it is not a security property.
  - Only the C locale. GNU under a UTF-8 locale collates text and reads locale month names; kriya
    compares bytes and reads `JAN` to `DEC`, whatever the environment says.
  - `-g` and `-R` cost more per key than a byte compare, a parse or a digest; kriya computes the
    first key's once per line, as GNU does.
- **Neutral**
  - The external sort for inputs past the 256 MiB buffer, with `-S` and `-T`, is still roadmap
    1.9.2.

## Amended at 1.9.2: past memory

Until 1.9.2 an input past the 256 MiB buffer was truncated, with a warning, in every mode. Now:

- **`-S SIZE` is a budget for the input's bytes and its line records together**, as GNU's buffer
  is: 56 bytes a line, 72 under `-R`, 96 under `-g`. The default is 512 MiB. GNU's spellings are
  taken, measured on 9.4 to 9.12: K, M, G, T, P, E, Z, Y, R, Q (and `g`, `t`) in powers of 1024,
  `b` for bytes, `N%` of physical memory, KiB for a bare number, the largest of several, 2^64 and
  past refused. It changes how much is held, never the order.
- **Past it, sort writes each full buffer, sorted, to a temporary RUN**, and merges runs sixteen
  at a time as they pile up, then into the output, with GNU's `merge` grouping. `-m` copies each
  input to a run of its own and merges those; `-c` checks a buffer at a time, keeping the last line
  for the next. A tie in a merge goes to the earlier run, so the output is the in-memory sort's.
- **A run is created in the next `-T DIR`** (round robin, as GNU's), or `$TMPDIR`, or /tmp,
  opened twice, to write and to read from the start, and **unlinked at once**. Nothing is left
  behind however `sort` ends, an interrupt included, and agnos needs no lseek to read a run back.
  A directory where no run can be made is GNU's exit 2.
- ⚠ GNU's sixteen-way grouping cannot change the output, even for `-m -u` over unsorted files: a
  line from another group never lands between two equal lines of one. kriya groups as GNU does
  because it bounds the open runs, not for the order.

Measured: 4 million lines (44 MB) sort in 8.79 s in memory, 5.97 s under `-S 10M` and 5.00 s under
`-S 1M`, against GNU's 0.63 s on all its threads; `-S 10M` holds kriya to a 33 MB peak, where in
memory takes 261. The runs are faster because each buffer's sort stays in cache (roadmap 1.10.8).
`difffuzz-sort.py` gives a third of its cases a budget of a few KiB and a `-T` directory, and on
1.9.2's final build 36,000 cases against 9.4, 9.7 and 9.12 differ in none.

## Alternatives considered

- **POSIX's options only.** It leaves out `-g -h -M -V -R -s -z`, which scripts written on Linux use
  and the roadmap committed to. Where POSIX and GNU both define an option they agree, so taking GNU's
  costs no POSIX behaviour.
- **POSIX's reading of an end position, clamped to its field** (the reading Unix `sort` had, kept in
  GNU's source under `POSIX_UNSPECIFIED`). POSIX leaves it open; GNU's reading is what every script
  tested against GNU expects.
- **A shuffle of kriya's own** (Fisher-Yates over lines). It would scatter equal keys, which GNU's
  `-R` groups, and give a different order under the same `--random-source`, which would make the
  option useless for reproducing a GNU run.
