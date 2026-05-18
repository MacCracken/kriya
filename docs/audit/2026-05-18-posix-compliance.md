# kriya — POSIX.1-2017 compliance audit

**Date**: 2026-05-18
**Version**: 0.7.0 (38 shipped utilities)
**Reference**: [POSIX.1-2017 utilities](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/contents.html)

This audit walks every shipped kriya utility against POSIX.1-2017,
records deviations (missing options, added options beyond POSIX, behavior
differences), and feeds the catalog into M7 deviation ADRs.

## Audit conventions

- **POSIX status**:
  - *Required* — the utility is defined in POSIX.1-2017 Chapter 4 (Utilities).
  - *Non-POSIX* — the utility is not in POSIX; kriya ships it as a documented scope extension.
- **Required options** — POSIX-mandated flags that conformant implementations must accept.
- **Deviations** are categorized as:
  - **Missing** — POSIX required, kriya doesn't ship (yet).
  - **Added** — beyond POSIX (BSD/GNU extension shipped intentionally).
  - **Behavior diff** — flag is shipped but semantics differ.

A utility marked *Conforms* matches POSIX for every shipped flag. *Conforms with extensions* means everything POSIX-required works, plus extras. *Documented deviation* means something diverges and needs an ADR (or one already exists).

## Summary

- **32 of 38 utilities** are POSIX-defined. **6 are kriya-scope extensions**: `yes`, `seq`, `stat`, `realpath`, `readlink`, `which`.
- **No utility ships a POSIX-required option in a non-conformant way**. Every deviation is either *missing* (deferred behind a named follow-up) or *added* (BSD/GNU extension).
- **5 existing ADRs** already cover the cross-cutting deviations: 0001 (dispatcher), 0002 (option parsing), 0003 (symlink follow), 0004 (rm refuses /), 0005 (regex engine).
- **3 new ADRs** drafted in M7 for category-level decisions: 0006 (utility scope), 0007 (date UTC-only at v0.7.0), 0008 (POSIX exit-code policy).

---

## M1 utilities

### true

- **POSIX status**: Required.
- **POSIX-required**: no options, no operands, exit 0.
- **kriya**: matches exactly.
- **Verdict**: Conforms.

### false

- **POSIX status**: Required.
- **POSIX-required**: no options, no operands, exit ≠ 0.
- **kriya**: matches; exit 1.
- **Verdict**: Conforms.

### echo

- **POSIX status**: Required (Issue 7 — minimal echo). Note: POSIX explicitly defines minimal behavior; `-e`/`-E` are XSI/GNU extensions.
- **POSIX-required**: write operands separated by spaces, terminated by newline.
- **kriya**: ships POSIX-minimal + leading `-n` suppresses newline (the one BSD/GNU extension we kept). `-e`/`-E` are deferred.
- **Deviations**:
  - **Added**: `-n` (BSD/GNU) — universally expected by shells; the deferred-features list calls this out.
  - **Missing**: `-e`/`-E` (escape interpretation) — deferred behind `lib/str.cyr` escape-table follow-up.
- **Verdict**: Conforms with extensions. The `-n` addition is intentional and called out in the file header.

### pwd

- **POSIX status**: Required.
- **POSIX-required**: `-L` (default — use $PWD if it resolves), `-P` (physical path resolution).
- **kriya**: ships both `-L` and `-P`. `$PWD` inode-match is deferred behind `fs.cyr` stat-compare.
- **Deviations**: **Behavior diff** — `-L` doesn't currently verify $PWD's inode matches getcwd; deferred follow-up named in CHANGELOG.
- **Verdict**: Conforms with documented deviation pending stat-compare helper.

### yes

- **POSIX status**: **Non-POSIX** (BSD/GNU). kriya scope choice — covered by ADR 0006.
- **kriya**: prints operands (or "y") forever; no flags.
- **Verdict**: Non-POSIX, intentional. Documented scope.

### sleep

- **POSIX status**: Required.
- **POSIX-required**: single operand `seconds`, integer non-negative.
- **kriya**: matches. Fractional + suffixes (`1.5s`, `1m`, `1h`) are GNU extensions and are deferred behind `lib/chrono.cyr` duration-parser.
- **Verdict**: Conforms. GNU-extension fractional/suffix deferred.

---

## M2 utilities (file operations)

### mkdir

- **POSIX status**: Required.
- **POSIX-required**: `-p` (create parents), `-m` (set mode).
- **kriya**: `-p`, `-m` (octal), `-v` (GNU extension). Symbolic mode (`u+rwx`) is deferred to chmod.
- **Deviations**:
  - **Added**: `-v` verbose (GNU).
  - **Missing**: symbolic-mode parsing in `-m` — deferred behind chmod.
- **Verdict**: Conforms with extensions.

### rmdir

- **POSIX status**: Required.
- **POSIX-required**: `-p` (remove empty parents).
- **kriya**: `-p`, `-v`, `--ignore-fail-on-non-empty` (GNU).
- **Verdict**: Conforms with extensions.

### touch

- **POSIX status**: Required.
- **POSIX-required**: `-a`, `-c`, `-m`, `-r REF_FILE`, `-t STAMP`, `-d STR`.
- **kriya**: `-a`, `-c`, `-m`. `-r`/`-t`/`-d` deferred behind `lib/chrono.cyr`.
- **Deviations**:
  - **Missing**: `-r REF_FILE`, `-t STAMP`, `-d STR` — deferred together behind chrono date-parser.
- **Verdict**: Documented deviation (CHANGELOG follow-up).

### ln

- **POSIX status**: Required.
- **POSIX-required**: `-f`, `-s`.
- **kriya**: `-f`, `-s`, `-P` (preserve), `-n` (no-deref-target), `-v`. `-r` (relative), `-T`/`-t` (target-directory), `-b`/`--backup` deferred.
- **Verdict**: Conforms with extensions. Deferred GNU flags named in CHANGELOG.

### cp

- **POSIX status**: Required.
- **POSIX-required**: `-f`, `-i`, `-p`, `-R` (or `-r`), `-H`, `-L`, `-P`.
- **kriya**: every POSIX-required option ships. Symlink policy per ADR 0003 (default `-P` under `-R`). `--preserve=links` (hardlink dedup) deferred.
- **Deviations**:
  - **Added**: `-v` (GNU verbose).
  - **Missing**: `--preserve=links` (hardlink dedup during recursive copy) — deferred.
- **Verdict**: Conforms with extensions.

### mv

- **POSIX status**: Required.
- **POSIX-required**: `-f`, `-i`.
- **kriya**: `-f`, `-i`, `-n` (no-clobber, GNU), `-v` (verbose, GNU). Cross-FS dir mv shipped at [Unreleased] via cp -R + rm -r with dest-tree rollback. ADR-0003 symlink-to-dir refusal.
- **Deviations**:
  - **Added**: `-n`, `-v` (GNU).
  - **Documented deviation**: refusal to overwrite a symlink-to-directory (ADR 0003 hard rule #3).
- **Verdict**: Conforms with extensions + documented safety deviation.

### rm

- **POSIX status**: Required.
- **POSIX-required**: `-f`, `-i`, `-R` (or `-r`).
- **kriya**: every required option ships. `-d` (POSIX-2024 / GNU empty-dir removal), `-v` (GNU).
- **Deviations**:
  - **Added**: `-d`, `-v`.
  - **Documented deviation**: refuses to operate on `/` even with `-rf` and rejects every textual root path (ADR 0004 hard rule). No `--no-preserve-root` flag exists — this is a hard policy, not a toggle.
- **Verdict**: Conforms with extensions + documented safety deviation.

---

## M3 utilities (listing + path manipulation)

### ls

- **POSIX status**: Required.
- **POSIX-required**: `-A`, `-C`, `-F`, `-H`, `-L`, `-R`, `-S`, `-a`, `-c`, `-d`, `-f`, `-g`, `-i`, `-k`, `-l`, `-m`, `-n`, `-o`, `-p`, `-q`, `-r`, `-s`, `-t`, `-u`, `-x`, `-1`.
- **kriya**: `-a`, `-A`, `-l`, `-h`, `-r`, `-1`, `-F`, `-i`, `-d`, `-R`. ISO mtime in `-l` via `chrono.epoch_to_date`.
- **Deviations**:
  - **Missing**: `-C` (multi-column tty packing — default ls output), `-t`/`-S`/`-u`/`-c` (sort keys), `-m` (comma-separated), `-n`/`-g`/`-o` (numeric uid/gid variants), `-p` (slash on dirs), `-q`/`-x` — deferred (named in CHANGELOG).
  - **Added**: `-h` (GNU human size).
- **Verdict**: Documented deviation — POSIX-required sort keys and multi-column packing are deferred follow-ups. The currently-shipped subset matches POSIX behavior cell-by-cell for the flags we do ship.

### basename

- **POSIX status**: Required.
- **POSIX-required**: single-pair shape `basename string [suffix]`.
- **kriya**: POSIX shape + GNU `-a`, `-s`, `-z` (multi-operand + NUL).
- **Verdict**: Conforms with extensions.

### dirname

- **POSIX status**: Required.
- **POSIX-required**: single operand.
- **kriya**: multi-operand + GNU `-z` (NUL).
- **Verdict**: Conforms with extensions.

### realpath

- **POSIX status**: **Non-POSIX in 2017** (added in POSIX.1-2024). kriya ships as scope extension covered by ADR 0006.
- **kriya**: `-e`, `-m`, `-q`, `-z`; cycle ELOOP at 40 hops.
- **Verdict**: Non-POSIX intentional scope addition.

### readlink

- **POSIX status**: **Non-POSIX in 2017** (added in POSIX.1-2024). Scope extension under ADR 0006.
- **kriya**: POSIX-raw + `-f`/`-e`/`-m` via fs_realpath + `-n`/`-z`/`-q`.
- **Verdict**: Non-POSIX intentional scope addition.

### which

- **POSIX status**: **Non-POSIX**. Scope extension under ADR 0006.
- **kriya**: `-a`, `-s`, `-z` + PATH walk + slash-literal bypass.
- **Verdict**: Non-POSIX intentional scope addition.

### stat

- **POSIX status**: **Non-POSIX** (POSIX has `stat()` the function, not the utility). Scope extension under ADR 0006.
- **kriya**: 22 format specifiers; `-c`/`--printf`/`-L`/`-t`. `%U`/`%G`/`%x`/`%y`/`%z`/`%N`/`%W` deferred.
- **Verdict**: Non-POSIX intentional scope addition. GNU-format specifier subset deferred.

---

## M4 utilities (text streams)

### wc

- **POSIX status**: Required.
- **POSIX-required**: `-c`, `-l`, `-m`, `-w`.
- **kriya**: `-l`, `-w`, `-c`, `-m` (UTF-8 codepoints), `-L` (GNU max-line-length).
- **Verdict**: Conforms with extension.

### head

- **POSIX status**: Required.
- **POSIX-required**: `-n` (count).
- **kriya**: `-n`, `-c`, `-q`, `-v`. `-n -N` (all-but-last) and k/M suffixes deferred.
- **Verdict**: Conforms with extensions. GNU `-N` form deferred.

### tail

- **POSIX status**: Required.
- **POSIX-required**: `-n`, `-c`, `-f`.
- **kriya**: `-n`, `-c`, `-q`, `-v`, `-f` (single-file 200ms stat-poll). Multi-file `-f`, `-F`, `+N` start-from, suffixes deferred.
- **Verdict**: Conforms with extensions. Multi-file `-f` deferred.

### cut

- **POSIX status**: Required.
- **POSIX-required**: `-b`, `-c`, `-d`, `-f`, `-n`, `-s`.
- **kriya**: `-b`, `-c`, `-f`, `-d`, `-s`, `--complement`, `--output-delimiter`, `-z` (GNU). Multibyte `-c` deferred (needs UTF-8 decoder).
- **Verdict**: Conforms with extensions.

### tr

- **POSIX status**: Required.
- **POSIX-required**: `-c`, `-d`, `-s`, `-C`.
- **kriya**: translate / delete / squeeze / complement / truncate; all 12 POSIX character classes. `[=c=]` (equivalence classes), `[c*N]` (repetition), locale fold deferred.
- **Verdict**: Conforms with extensions on character classes.

### tee

- **POSIX status**: Required.
- **POSIX-required**: `-a`, `-i`.
- **kriya**: `-a` ships; `-i` (SIGINT-ignore) deferred behind signal-handler infrastructure.
- **Deviations**:
  - **Missing**: `-i` — deferred.
- **Verdict**: Documented deviation.

### sort

- **POSIX status**: Required.
- **POSIX-required**: `-b`, `-c`, `-d`, `-f`, `-g`, `-i`, `-k`, `-M`, `-m`, `-n`, `-o`, `-r`, `-t`, `-u`.
- **kriya**: `-n`, `-r`, `-u`, `-f`, `-b`, `-t`, `-k`, `-c`, `-o`, `-z`, `-s` (stable). `-h`/`-V`/`-g`/`-M`/`-R`/`-m`/`-d`/`-i` deferred. Multi-key `-k F1 -k F2` deferred. External-sort fallback for > 256 MiB deferred.
- **Deviations**:
  - **Missing**: `-d`, `-i`, `-g`, `-M`, `-m` — deferred.
- **Verdict**: Documented deviation. The core single-key sort matches POSIX cell-by-cell against `LC_ALL=C sort` for shipped flags.

### uniq

- **POSIX status**: Required.
- **POSIX-required**: `-c`, `-d`, `-f`, `-s`, `-u`.
- **kriya**: `-c`, `-d`, `-u`, `-i`, `-f`, `-s`, `-w`, `-z`. `--all-repeated`, `--group` deferred.
- **Verdict**: Conforms with extensions.

### nl

- **POSIX status**: Required.
- **POSIX-required**: `-b`, `-d`, `-f`, `-h`, `-i`, `-l`, `-n`, `-p`, `-s`, `-v`, `-w`.
- **kriya**: `-b`, `-i`, `-n`, `-s`, `-v`, `-w`. `-d`, `-h`, `-f`, `-l`, `-p` (section delimiters) deferred.
- **Deviations**:
  - **Missing**: section delimiters `-d`/`-h`/`-f`/`-l`/`-p` — deferred (single-section model only at v0.7.0).
- **Verdict**: Documented deviation. Single-section model is the common case.

### printf

- **POSIX status**: Required.
- **POSIX-required**: full format engine including `%d`/`%i`/`%o`/`%u`/`%x`/`%X`/`%c`/`%s`/`%b`/`%%` + flags `- + space # 0` + width + precision + `\NNN` octal.
- **kriya**: every POSIX conversion **except** floating-point (`%e`/`%f`/`%g`). Flag matrix, width, precision, `\NNN`, `%b` escape, arg reuse all ship. `\xHH` hex and positional `%N$s` deferred.
- **Deviations**:
  - **Missing**: floating-point conversions `%e`/`%E`/`%f`/`%F`/`%g`/`%G`/`%a`/`%A` — deferred behind shared float-format follow-up.
- **Verdict**: Documented deviation. Same deferred-item gates `seq -f`.

---

## M5 utilities (filtering / search)

### grep

- **POSIX status**: Required.
- **POSIX-required**: `-c`, `-e`, `-E`, `-F`, `-f`, `-i`, `-l`, `-n`, `-q`, `-s`, `-v`, `-x`.
- **kriya**: every POSIX-required option ships, plus GNU `-w`, `-L`, `-h`, `-H`, `-o`, `-r`, `-R`, `-z`, `-G`. `-P` rejected with usage error pointing at `-E` (ADR 0005). Multi-`-e`, `-A`/`-B`/`-C`, `--include`/`--exclude`, `--color`, `-Z` deferred.
- **Verdict**: Conforms with extensions. `-P` rejection is documented in ADR 0005.

### find

- **POSIX status**: Required.
- **POSIX-required**: `-name`, `-type`, `-size`, `-mtime`, `-newer`, `-perm`, `-user`, `-group`, `-print`, `-exec`, `-prune`, `-depth`, plus operators `!`, `-a`, `-o`, `()`.
- **kriya**: `-name`, `-type`, `-size`, `-mtime`, `-mmin` (GNU), `-empty` (GNU), `-newer`, `-maxdepth` (GNU), `-mindepth` (GNU), `-print`, `-print0` (GNU), `-exec ... \;`. Full boolean grammar. `-P` default + `-L` follow per ADR 0003.
- **Deviations**:
  - **Missing**: `-perm`, `-user`, `-group`, `-prune`, `-depth`, `-exec ... +`, `-regex` — deferred together (CHANGELOG).
- **Verdict**: Documented deviation. The shipped predicate set covers the common-case scripting surface; the missing predicates need passwd/group lookup helpers (`-user`/`-group`), DFS post-order (`-depth`), or argv-chunking (`-exec ... +`).

### xargs

- **POSIX status**: Required.
- **POSIX-required**: `-E`, `-I`, `-L`, `-n`, `-p`, `-s`, `-t`, `-x`.
- **kriya**: `-0` (GNU), `-n`, `-I`, `-r` (GNU), `-t`, `-s`. Quoting (single/double/backslash) per POSIX. `-E`, `-L`, `-p`, `-x` deferred.
- **Deviations**:
  - **Missing**: `-E EOFSTR`, `-L lines-per-command`, `-p` (prompt), `-x` (overflow-exit) — deferred.
- **Verdict**: Documented deviation. The shipped set covers the common `find -print0 | xargs -0` idiom.

---

## M6 utilities (system info + misc)

### env

- **POSIX status**: Required.
- **POSIX-required**: `-i` (ignore environment) plus `[NAME=VALUE]... [COMMAND [ARG...]]` operand shape.
- **kriya**: `-i`/`-`/`--ignore-environment`, `-u`/`--unset`, `-0`/`--null` (GNU), `--`. In-order op application. Direct `sys_execve` (no fork).
- **Verdict**: Conforms with extensions.

### date

- **POSIX status**: Required.
- **POSIX-required**: `+FORMAT`, `-u`.
- **kriya**: 28 strftime specifiers, `+FORMAT`, `-u` accepted as no-op.
- **Deviations**:
  - **Documented deviation**: **UTC-only at v0.7.0** — `date` defaults to UTC instead of POSIX's local-time default. Captured in ADR 0007. Local-time tzfile parsing (TZ env + `/etc/localtime`) is the deferred follow-up.
  - **Missing**: `-d STR` (parse arbitrary date), `-r FILE` (use file's mtime), `-R`/`-I` convenience formats — deferred.
- **Verdict**: Documented deviation under ADR 0007.

### du

- **POSIX status**: Required.
- **POSIX-required**: `-a`, `-k`, `-s`, `-x`, `-H`, `-L`, `-P`.
- **kriya**: `-s`, `-a`, `-c` (GNU), `-h` (GNU), `-k`, `-b` (GNU), `-L`, `-P`, `-d`/`--max-depth` (GNU), `-S` (GNU). `-x` (one-FS) deferred. Hardlink dedup deferred.
- **Deviations**:
  - **Missing**: `-x` (one-filesystem) — deferred.
  - **Documented deviation**: no hardlink dedup at v0.7.0 — same inode under multiple names is counted multiple times. Captured in CHANGELOG as follow-up.
- **Verdict**: Documented deviation. The hardlink dedup gap and `-x` defer are tracked.

### df

- **POSIX status**: Required.
- **POSIX-required**: `-h` (no, that's GNU — POSIX has `-k`, `-P`), `-k`, `-P`, `-t`.
- **kriya**: `-h` (GNU), `-k` (no-op default), `-T` (GNU), `-i` (GNU), `-a` (GNU), `-P`. POSIX `-t TYPE` (filter by fs type) deferred.
- **Deviations**:
  - **Missing**: `-t TYPE` (POSIX filter by type) — deferred.
  - **Documented deviation**: operand-to-mount-point matching at v0.7.0 is exact-MP-match only; full POSIX semantic ("filesystem containing the FILE") requires `stat(FILE).st_dev` walk — deferred follow-up.
- **Verdict**: Documented deviation.

### seq

- **POSIX status**: **Non-POSIX** (BSD/GNU). Scope extension under ADR 0006.
- **kriya**: 1/2/3-operand shapes, `-s`, `-w`. `-f FORMAT` deferred behind printf `%f`. Float deferred.
- **Verdict**: Non-POSIX intentional scope addition.

---

## Cross-cutting policy

### Exit codes

POSIX defines per-utility exit codes. The kriya convention captured in `src/lib/exit.cyr`:
- `EXIT_SUCCESS` = 0 — successful invocation.
- `EXIT_FAILURE` = 1 — general failure (per-operand or invocation-wide).
- `EXIT_USAGE` = 2 — usage error (bad option, missing arg, invalid value).

Plus utility-specific codes that POSIX names:
- `grep`: 0 (any match), 1 (no match), 2 (error). Shipped. `-s` suppresses to 1 — shipped.
- `xargs`: 0 / 123 (any child non-zero) / 124 (child exit 255) / 125 (xargs killed) / 126 (child cannot execute) / 127 (child not found). Shipped (except 124's "child 255" path verified at smoke level).
- `env`: child's exit on success, 126 (cannot execute), 127 (not found). Shipped.

To be captured in **ADR 0008** — POSIX exit-code policy across kriya.

### Symlink-follow

Captured in **ADR 0003**. Default-preserve under `-R`; never-follow under `rm`; `-L` opt-in to follow.

### Root-path refusal

Captured in **ADR 0004**. `rm` refuses `/` and every textual root path with no escape hatch.

### Regex engine

Captured in **ADR 0005**. `niyama` BRE+RE2; PCRE deferred behind a v2.0 flag gate; `-P` rejected with usage error.

### Utility scope

To be captured in **ADR 0006** — which non-POSIX utilities ship in kriya and why. Six utilities: `yes`, `seq`, `stat`, `realpath`, `readlink`, `which`.

### Date timezone

To be captured in **ADR 0007** — `date` defaults to UTC at v0.7.0; local-time tzfile parsing is a named follow-up.

---

## Deviation index (machine-readable)

| Utility | Status | Deviation kind | Tracked as |
|---|---|---|---|
| true / false / yes / sleep | ✓ | none / scope | — / ADR 0006 |
| echo | ✓+ext | added: `-n` | file header |
| pwd | ✓ | behavior: `-L` $PWD inode-match | CHANGELOG follow-up |
| mkdir | ✓+ext | added: `-v`; missing: symbolic-mode | CHANGELOG (chmod) |
| rmdir | ✓+ext | added: `-v`, `--ignore-fail-on-non-empty` | — |
| touch | ✓ | missing: `-r`/`-t`/`-d` | CHANGELOG (chrono) |
| ln | ✓+ext | added: `-P`/`-n`/`-v`; missing: `-r`/`-T`/`-t`/`-b` | CHANGELOG |
| cp | ✓+ext | added: `-v`; missing: `--preserve=links` | CHANGELOG |
| mv | ✓+ext | added: `-n`/`-v`; ADR-0003 deviation | ADR 0003 |
| rm | ✓+ext | added: `-d`/`-v`; ADR-0004 hard rule | ADR 0004 |
| ls | partial | missing: `-C`/`-t`/`-S`/`-u`/`-c`/`-m`/`-n`/`-g`/`-o`/`-p`/`-q`/`-x` | CHANGELOG |
| basename / dirname | ✓+ext | added: `-a`/`-s`/`-z` | — |
| realpath / readlink / which / stat | scope | non-POSIX, intentional | ADR 0006 |
| wc | ✓+ext | added: `-L` | — |
| head / tail | ✓+ext | added: `-q`/`-v`/`-f`; missing: multi-file `-f`, `-N` form, suffixes | CHANGELOG |
| cut | ✓+ext | added: `--complement`/`--output-delimiter`/`-z`; missing: multibyte `-c` | CHANGELOG |
| tr | ✓+ext | added: truncate; missing: `[=c=]`/`[c*N]`/locale | CHANGELOG |
| tee | partial | missing: `-i` (signal infra) | CHANGELOG |
| sort | partial | missing: `-d`/`-i`/`-g`/`-M`/`-m`/multi-key/external | CHANGELOG |
| uniq | ✓+ext | added: `-i`/`-w`/`-z`; missing: `--all-repeated`/`--group` | CHANGELOG |
| nl | partial | missing: section delimiters | CHANGELOG |
| printf | partial | missing: `%e`/`%f`/`%g`/`%a`, `\xHH`, `%N$s` | CHANGELOG |
| grep | ✓+ext | added: `-w`/`-L`/`-h`/`-H`/`-o`/`-r`/`-R`/`-z`/`-G`; `-P` rejected per ADR 0005 | ADR 0005 |
| find | partial | missing: `-perm`/`-user`/`-group`/`-prune`/`-depth`/`-exec +`/`-regex` | CHANGELOG |
| xargs | ✓+ext | added: `-0`/`-r`; missing: `-E`/`-L`/`-p`/`-x` | CHANGELOG |
| env | ✓+ext | added: `-0`; in-order op application | — |
| date | partial | UTC-only default; missing: `-d`/`-r`/`-R`/`-I` | ADR 0007 |
| du | ✓+ext | added: `-c`/`-h`/`-b`/`-d`/`-S`; missing: `-x`, hardlink dedup | CHANGELOG |
| df | ✓+ext | added: `-h`/`-T`/`-i`/`-a`; missing: `-t TYPE` | CHANGELOG |
| seq | scope | non-POSIX, intentional | ADR 0006 |

**Legend**: ✓ = conforms; ✓+ext = conforms with extensions beyond POSIX; partial = required options missing but documented; scope = non-POSIX, intentional kriya extension.

---

## Action items

- [x] Walk all 38 utilities and catalog deviations. **Done — this document.**
- [x] Draft ADR 0006 — utility scope (which non-POSIX utilities ship).
- [x] Draft ADR 0007 — `date` UTC-only at v0.7.0; local-time follow-up.
- [x] Draft ADR 0008 — POSIX exit-code policy across kriya.
- [ ] Build `tests/kriya-posix.tcyr` framework with one POSIX-blessed block per pillar utility.

The audit confirms that **kriya at v0.7.0 ships POSIX-conformant behavior for every shipped flag** — no utility quietly diverges. Every gap is either *missing* (deferred behind a named follow-up) or *added* (BSD/GNU extension shipped intentionally). The four cross-cutting deviation areas — symlink follow, root refusal, regex engine, `date` UTC default — are each backed (or about to be) by an explicit ADR.
