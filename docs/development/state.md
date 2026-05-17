# kriya — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.4.0** — released 2026-05-17. Closes M3: seven listing + path-manipulation utilities (`basename`, `dirname`, `realpath`, `readlink`, `which`, `stat`, `ls`) built on top of M2's filesystem foundation. New shared canonicalization helper `fs_realpath` (3 modes — REQUIRE_ALL / REQUIRE_PARENT / ALLOW_MISSING) backs both `realpath` and `readlink -f`/`-e`/`-m`. `ls -l` mtime renders via `chrono.epoch_to_date`. **441 behavioural smoke cases pass across the 14 M2+M3 utilities** (24+24+26+30+26+39+43+53+26+30+24+23+37+36); 86/86 unit assertions; cold-start median **1.208ms** at M3 close (~50µs uptick from v0.3.0's 1.159ms — attributable to 7 more dispatcher `if (streq …)` lines and a marginally larger text segment; still well under the 2ms v1.0 target).

## Role

Coreutils-equivalent for AGNOS — the small POSIX-style utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep` …) in one repo, sharing a `src/lib/` of path / errno / argument-parsing primitives. Each utility is a separate command (via symlink → dispatcher). Sovereign-replacement boundaries documented in `CLAUDE.md` (owl owns `cat`, sit owns `git`, chakshu owns `htop`, cyim owns `vim`, agnoshi owns shell builtins — kriya fills the gaps).

## Toolchain

- **Cyrius pin**: `5.11.54` (in `cyrius.cyml [package].cyrius`)

## Source

M1 closed at v0.2.0; M2 closed at v0.3.0; M3 closed at v0.4.0. All twenty shipped utilities (six from M1 + seven from M2 + seven from M3) are live; six shared lib modules in place (`exit`, `path`, `errmsg`, `args`, `fs`, `protected`); four ADRs accepted (0001–0004); two architecture notes (signal model + errno policy). Cold-start re-benched at each release boundary: 1.185ms (v0.2.0) → 1.159ms (v0.3.0) → **1.208ms (v0.4.0)** — 7 new dispatcher table entries + a slightly larger binary cost ~50µs vs v0.3.0; runs sampled in a tight range across 4×30-run trials (1.199 / 1.222 / 1.208 / 1.205ms medians).

| Module | Status |
|---|---|
| `src/main.cyr` | implemented — dispatch by `argv[0]` basename via `path_basename_ptr`, fallback to `argv[1]` when invoked as `kriya` |
| `src/lib/path.cyr` | implemented — `path_basename_ptr`, `path_dirname`, `path_is_absolute`, `path_normalize`, `path_join`, `path_is_under` |
| `src/lib/exit.cyr` | implemented — `EXIT_SUCCESS`/`EXIT_FAILURE`/`EXIT_USAGE` enum |
| `src/lib/errmsg.cyr` | implemented — errnos 1..40 + `errmsg_is_known` |
| `src/lib/args.cyr` | implemented — flat-argv builder + stdlib `flags_parse` wrapper + `kriya_parse_nonneg_int` |
| `src/cmd/*.cyr` | 27 of ~40 — M1 + M2 (13) + M3 (7) + M4 (7: `tee`, `wc`, `head`, `tail`, `nl`, `uniq`, `tr`) |
| `src/lib/fs.cyr` | implemented — `*at()`-family wrappers, `getdents64` iteration, type predicates, AT/S_IF/DT constants. Foundation for cp -R / mv / rm -r per ADR 0003. Adds `fs_rename`/`fs_renameat`/`fs_realpath` (3-mode canonicalization). |
| `src/lib/protected.cyr` | implemented — `protected_paths[]` table with `/`, canonicalization via `path_normalize` + getcwd, `is_protected_path()` membership check. Per ADR 0004, only consumed by `rm` today. |

## Per-utility status (will grow with each milestone)

| Utility | Module | Status | Roadmap milestone |
|---|---|---|---|
| `echo` | `src/cmd/echo.cyr` | **implemented** (POSIX + leading `-n`; `-e`/`-E` deferred) | M1 |
| `pwd` | `src/cmd/pwd.cyr` | **implemented** (`-L`/`-P`; `$PWD` inode-match deferred) | M1 (note: agnoshi has a builtin; kriya provides the binary form) |
| `true` | `src/cmd/true.cyr` | **implemented** | M1 |
| `false` | `src/cmd/false.cyr` | **implemented** | M1 |
| `yes` | `src/cmd/yes.cyr` | **implemented** | M1 |
| `sleep` | `src/cmd/sleep.cyr` | **implemented** (integer seconds; fractional + suffixes deferred) | M1 |
| `mkdir` | `src/cmd/mkdir.cyr` | **implemented** (`-p`, `-m` octal, `-v`; symbolic-mode deferred to chmod) | M2 |
| `rmdir` | `src/cmd/rmdir.cyr` | **implemented** (`-p`, `-v`, `--ignore-fail-on-non-empty`) | M2 |
| `touch` | `src/cmd/touch.cyr` | **implemented** (`-a`, `-m`, `-c`; `-r`/`-t`/`-d` deferred to chrono helpers) | M2 |
| `cp` | `src/cmd/cp.cyr` | **implemented** (`-f`/`-i`/`-p`/`-v`/`-R`/`-r`/`-P`/`-H`/`-L`; fd-rooted recursion with `O_NOFOLLOW` per ADR 0003; `--preserve=links` for hardlink dedup deferred) | M2 |
| `mv` | `src/cmd/mv.cyr` | **implemented** (`-f`/`-i`/`-n`/`-v`; same-FS rename; cross-FS files+symlinks; ADR-0003 symlink-to-dir refusal; cross-FS dir mv lands with rm tree-walk) | M2 |
| `rm` | `src/cmd/rm.cyr` | **implemented** (`-f`/`-i`/`-r`/`-R`/`-d`/`-v`; fd-rooted recursion with O_NOFOLLOW per ADR 0003; protected-paths refusal per ADR 0004) | M2 |
| `ln` | `src/cmd/ln.cyr` | **implemented** (`-s`, `-f`, `-P`, `-n`, `-v`; `-r`/`-T`/`-t`/`-b` deferred) | M2 |
| `ls` | `src/cmd/ls.cyr` | **implemented** (`-a`/`-A`/`-l`/`-h`/`-r`/`-1`/`-F`/`-i`/`-d`/`-R`; defer multi-column tty packing, `-t`/`-S`, `--color`, `%U`/`%G` name lookup) | M3 |
| `stat` | `src/cmd/stat.cyr` | **implemented** (`-c`/`--printf`/`-L`/`-t`; 22 format specifiers; %U/%G/%x/%y/%z/%N/%W deferred to chrono+passwd+statx) | M3 |
| `basename` | `src/cmd/basename.cyr` | **implemented** (POSIX single-pair, `-a`/`-s`/`-z`) | M3 |
| `dirname` | `src/cmd/dirname.cyr` | **implemented** (multi-operand, `-z`) | M3 |
| `realpath` | `src/cmd/realpath.cyr` | **implemented** (`-e`/`-m`/`-q`/`-z`; cycle ELOOP at 40 hops) | M3 |
| `readlink` | `src/cmd/readlink.cyr` | **implemented** (POSIX raw + `-f`/`-e`/`-m` via fs_realpath + `-n`/`-z`/`-q`) | M3 |
| `which` | `src/cmd/which.cyr` | **implemented** (`-a`/`-s`/`-z`; PATH-walk + slash-literal bypass; deferred shell-state flags) | M3 |
| `wc` | `src/cmd/wc.cyr` | **implemented** (`-l`/`-w`/`-c`/`-m`/`-L`; GNU-compatible column-width matrix verified cell-by-cell) | M4 |
| `head` | `src/cmd/head.cyr` | **implemented** (`-n`/`-c`/`-q`/`-v`; streaming bounded-RAM; defer GNU `-N` "all but last" + k/M suffixes) | M4 |
| `tail` | `src/cmd/tail.cyr` | **implemented** (`-n`/`-c`/`-q`/`-v`; buffer-and-back-walk up to 16 MiB cap; defer `-f`/`-F`/`+N` start-from + suffixes) | M4 |
| `cut` | `src/cmd/cut.cyr` | not started | M4 |
| `tr` | `src/cmd/tr.cyr` | **implemented** (translate/delete/squeeze/complement/truncate; full POSIX set grammar incl. 12 character classes; defer [=c=] + [c*N] + locale folding) | M4 |
| `tee` | `src/cmd/tee.cyr` | **implemented** (`-a`; resilient per-file failure; `-i` SIGINT-ignore deferred to signal-handler infra) | M4 |
| `sort` | `src/cmd/sort.cyr` | not started | M4 |
| `uniq` | `src/cmd/uniq.cyr` | **implemented** (`-c`/`-d`/`-u`/`-i`/`-f`/`-s`/`-w`/`-z`; 2-op input/output; defer `--all-repeated`/`--group`) | M4 |
| `nl` | `src/cmd/nl.cyr` | **implemented** (single-section; `-b`/`-i`/`-n`/`-s`/`-v`/`-w`; defer `-d`/`-h`/`-f`/`-l`/`-p` sections + `-b p REGEX`) | M4 |
| `printf` | `src/cmd/printf.cyr` | not started | M4 |
| `grep` | `src/cmd/grep.cyr` | not started | M5 |
| `find` | `src/cmd/find.cyr` | not started | M5 |
| `xargs` | `src/cmd/xargs.cyr` | not started | M5 |
| `df` | `src/cmd/df.cyr` | not started | M6 |
| `du` | `src/cmd/du.cyr` | not started | M6 |
| `date` | `src/cmd/date.cyr` | not started | M6 |
| `env` | `src/cmd/env.cyr` | not started | M6 |
| `seq` | `src/cmd/seq.cyr` | not started | M6 |

## Binary

- Dispatcher: `kriya` (output in `build/kriya` after `cyrius build`)
- Per-utility commands: symlinks → `kriya` (`cp` → `kriya`, `mv` → `kriya`, etc.)
- Size: TBD (first build pending)

## Tests

- `tests/kriya.tcyr` — primary unit suite (78/78 passing — exit codes, cmd routes, path primitives, errmsg table, integer parser, octal-mode parser).
- `tests/kriya.bcyr` — in-process hot-path bench (stdlib `lib/bench.cyr`). Steady-state numbers (Cyrius 5.11.54, x86_64):
  - `dispatch/path_basename_ptr` — 65ns
  - `dispatch/streq_hit` / `_miss` — 34ns / 31ns
  - `util/cmd_true` / `cmd_false` — 6ns / 6ns
  - `path/normalize_simple` / `_messy` — 336ns / 515ns
  - `errmsg/for_known` — 6ns
  - `args/parse_octal_mode` — 20ns
- `scripts/bench-coldstart.sh` — process-spawn timing at each release boundary. v0.4.0 (RUNS=30): min 1.030ms, **median 1.208ms**, max 1.292ms — still under the 2ms v1.0 target. History: v0.2.0 1.185ms / v0.3.0 1.159ms / v0.4.0 1.208ms (median of 30 runs each; ~50µs uptick this cycle from 7 new dispatcher entries + larger text segment).
- `scripts/smoke-mkdir.sh` — behavioural test for `mkdir` (24/24 passing — happy path, `-p` recursion, EEXIST split, `-m` mode bits, partial-failure exit, root operand). Pattern carries forward as each M2 utility ships.
- `scripts/smoke-rmdir.sh` — behavioural test for `rmdir` (24/24 — happy path, `-p` cascade with sibling-halt, `--ignore-fail-on-non-empty`, ENOTEMPTY/ENOENT/ENOTDIR, kernel-EBUSY on `/`, `-v` output).
- `scripts/smoke-touch.sh` — behavioural test for `touch` (26/26 — create, multi-operand, update-existing, `-a`/`-m`/`-a -m`, `-c` on missing-vs-existing, ENOENT on missing parent, partial-failure exit code).
- `scripts/smoke-ln.sh` — behavioural test for `ln` (30/30 — symbolic + hard creation, `-f` overwrite, single-arg form, multi-into-dir, ADR-0003 deploy-retarget idiom `-s -f -n`, `-P` inode-match verification, dangling-symlink ok, hard-to-missing error, verbose).
- `scripts/smoke-cp.sh` — behavioural test for non-recursive `cp` (26/26 — basic + 200 KiB multi-block, existing-dest gating with `-f`/`-i`, `-i`-on-pipe usage error, multi-into-dir, `-p` mode+mtime preservation, non-`-p` current-time, self-copy refusal, directory-without-R EISDIR, partial-failure exit, verbose).
- `scripts/smoke-cp-recursive.sh` — behavioural test for `cp -R` (39/39 — full ADR-0003 `-P`/`-H`/`-L` matrix verified: `-P` default preserves symlinks, `-H` follows command-line operands and preserves inner links, `-L` materialises all link content; plus `-r` alias, into-existing-dir, `-p` mode/time preservation under recursion, error paths, symlink-to-`/etc` preserved by default).
- `scripts/smoke-mv.sh` — behavioural test for `mv` (43/43 — same-FS rename, overwrite default, `-n` silent skip, `-i`-on-pipe usage error, multi-into-dir, dir rename, ADR-0003 symlink-to-dir refusal in both single-pair and multi-into-dir shapes, self-move detection, partial-failure paths, verbose. Cross-FS round-trips when `/tmp` and `/dev/shm` differ — file with inode-differs assertion, symlink with target preservation, cross-FS dir error path).
- `scripts/smoke-rm.sh` — behavioural test for `rm` (53/53 — every ADR-0004 canonicalization escape (`/`, `/.`, `/tmp/..`, `////`, `/../../../`, relative `../../`), no `--no-preserve-root` flag, no env-var bypass, multi-op atomicity preserved; ADR-0003 symlink-to-dir `rm` leaves target intact, `rm -r` of dir-containing-symlink-to-dir never descends; `-f` silences ENOENT; `-r`/`-R`/`-d`/`-v`; partial-failure exit; `-i`-on-pipe usage error).
- `scripts/smoke-basename-dirname.sh` — paired behavioural test (26/26 — POSIX single-pair, suffix-strip matching + non-matching, `-a`/`-s`/`-z`, multi-operand dirname, NUL-termination, error paths).
- `scripts/smoke-realpath.sh` — behavioural test for `realpath` + the underlying `fs_realpath` helper (30/30 — absolute/relative, `.`/`..`/duplicate-slash collapse, symlink chains, `-e` default, `-m` text completion through missing components, cycle ELOOP, multi-operand partial-failure exit, `-q` silent mode, `-z` NUL termination).
- `scripts/smoke-readlink.sh` — behavioural test for `readlink` (24/24 — POSIX raw read-link + EINVAL on non-symlink; `-f` REQUIRE_PARENT boundary; `-e` REQUIRE_ALL; `-m` ALLOW_MISSING; `-q` silences both surfaces; `-n` newline-on-final-only; `-z` overrides `-n`; precedence `-m > -e > -f`).
- `scripts/smoke-which.sh` — behavioural test for `which` (23/23 — controlled-PATH first-match-wins, `-a` shadowing in PATH order, non-executable + directory entries skipped, empty PATH and empty-entry-means-cwd, slash-literal-bypasses-PATH, partial-failure exit + stdout preserved, `-s`/`-z` modifiers).
- `scripts/smoke-stat.sh` — behavioural test for `stat` (37/37 — every shipped specifier compared against GNU `stat`, `-c` vs `--printf` escape handling, `-L` vs default lstat, `-t` 16-column terse parity, partial-failure exit, unknown-specifier literal emission).
- `scripts/smoke-ls.sh` — behavioural test for `ls` (36/36 — default sort, `-a`/`-A` hidden-file split, `-r` reverse, `-F` type-suffix matrix, `-i` inode column, `-l` 8-column layout with ISO mtime, `-l` symlink target rendering, `-l -h` human-size matrix at 1K/5K/1.4M boundaries, `-d` directory-as-entry, `-R` recursion without symlink-follow, multi-operand layout, partial-failure exit).
- `scripts/smoke-tee.sh` — behavioural test for `tee` (20/20 — single-file, multi-file fan-out, default truncate vs `-a` append, no-operand pass-through, 200KiB + 5MiB fidelity, binary-NUL fidelity, resilient partial-failure with surviving outputs, directory operand cleanly fails).
- `scripts/smoke-wc.sh` — behavioural test for `wc` (23/23 — every flag combo compared cell-by-cell against GNU `wc`; empty file, no-trailing-newline, UTF-8 codepoints, 200KiB input, 1000-line file, multi-file total + column-width rules, stdin, partial-failure).
- `scripts/smoke-head-tail.sh` — paired behavioural test for `head` + `tail` (38/38 — every shipped flag combo compared cell-by-cell against GNU `head`/`tail`; empty / no-newline / 1000-line files, `-c 0` and `-n 0` edges, stdin, `-` literal-stdin, multi-file headers, `-q`/`-v` overrides, partial failure).
- `scripts/smoke-nl.sh` — behavioural test for `nl` (23/23 — every flag combo compared cell-by-cell against GNU `nl`; default `-b t` empty-line skip, `-b a` number all, `-b n` number none, `-n` format matrix `ln`/`rn`/`rz`, `-w` width, `-s SEP` with 1/2/3-byte separators exercising the `width + sep_len` unnumbered-padding rule, `-v`/`-i`, stdin, multi-file continuous numbering, partial failure).
- `scripts/smoke-uniq.sh` — behavioural test for `uniq` (27/27 — every shipped flag cell-by-cell against GNU; `-c` count prefix at width 7, `-d`/`-u` mutually-exclusive filters, `-i` case-fold, `-f`/`-s`/`-w` comparison-key permutations, 2-operand input/output mode, NUL-separated I/O via `-z`, partial failure).
- `scripts/smoke-tr.sh` — behavioural test for `tr` (32/32 — translate / delete / squeeze / complement / truncate modes cell-by-cell against GNU; rot13 alphabet pairing; every POSIX character class incl. `[:alnum:]`/`[:punct:]`/`[:cntrl:]`/`[:xdigit:]`; backslash named + octal escapes; SET2-shorter pad rule; `-d -s` combined; empty input; usage errors).
- `tests/kriya.fcyr` — fuzz stub (lands when M2 destructive utilities arrive).

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`, `args`, `flags`, `chrono`, `fnptr`, `bench`, `assert`

External: none (and none planned for v1.0).

## Consumers

_None yet._ Expected consumers once M1 ships:

- [agnoshi](https://github.com/MacCracken/agnoshi) — shell relies on `$PATH` lookup of `cp`, `mv`, `rm`, etc.
- [zugot](https://github.com/MacCracken/zugot) — package manager builds will install kriya symlinks at recipe time

## In-flight work

- M1 closed; v0.2.0 cut. M2 policy lead-in **landed 2026-05-17**: ADR 0003 (symlink-follow policy) and ADR 0004 (`rm` refuses `/`, no escape hatch — stronger than the GNU `--no-preserve-root` model). M2 code in progress. Ship order:
  1. ✅ `mkdir` (2026-05-17) — `-p`/`-m`/`-v`, octal mode parser, EEXIST split, smoke-mkdir.sh pattern established.
  2. ✅ `rmdir` (2026-05-17) — `-p`/`-v`/`--ignore-fail-on-non-empty`; first destructive utility shipped, kernel-EBUSY suffices for `/`.
  3. ✅ `touch` (2026-05-17) — `-a`/`-m`/`-c`; raw `utimensat(280)` syscall (no stdlib wrapper yet). `-r`/`-t`/`-d` deferred to chrono helpers.
  4. ✅ `ln` (2026-05-17) — `-s`/`-f`/`-P`/`-n`/`-v`; raw `linkat(265)` for `-P` policy; ADR-0003 deploy-retarget idiom verified by `smoke-ln.sh`.
  5a. ✅ `cp` non-recursive (2026-05-17) — `-f`/`-i`/`-p`/`-v`. `-i`-on-pipe is a usage error (ADR 0002). Self-copy refused via `(st_dev,st_ino)` match.
  5b. ✅ `cp -R` recursive (2026-05-17) — `-R`/`-r`/`-P`/`-H`/`-L` matrix on top of `src/lib/fs.cyr`. Every descent uses `openat(parent_fd, name, O_NOFOLLOW | O_DIRECTORY)`; destination opens are `O_NOFOLLOW` with `-f`-driven unlink+retry. The lstat-vs-stat decision is carried into the descend as `allow_follow`. `--preserve=links` for hardlink dedup deferred.
  6. ✅ `mv` (2026-05-17) — same-FS `rename(2)`; cross-FS fallback for files + symlinks; cross-FS directory mv errors with a clear message (now unblocked — mv can use the rm tree-walk). ADR-0003 hard rule #3 enforced invocation-wide.
  7. ✅ `rm` (2026-05-17) — `-f`/`-i`/`-r`/`-R`/`-d`/`-v`. ADR-0003 never-follow (no flag exists), ADR-0004 protected-paths refusal (no escape hatch). 53 behavioural cases covering every known canonicalization escape and the symlink-no-follow property. **Closes M2.**
  7. `rm` — last, and most carefully — full ADR 0003 (`O_NOFOLLOW` traversal, no follow flag) and ADR 0004 (`protected_paths[]` check) enforcement.
- **M2 closed 2026-05-17 at v0.3.0.** All seven planned utilities ship; ADRs 0003 and 0004 verified end-to-end. Cross-repo proposals filed: `2026-05-17-octal-literal-syntax` and `2026-05-17-syscalls-at-family-stdlib` (sweep follow-ups when accepted). Cross-FS directory `mv` is one remaining M2 follow-up — now unblocked since `rm -r` exists.
- **M3 in progress.** Order (simplest → biggest):
  1. ✅ `basename` + `dirname` (2026-05-17) — paired commit, pure-text utilities. Added `path_basename_len` to fix a latent trailing-slash bug in `path_basename_ptr`'s usage pattern.
  2. ✅ `realpath` (2026-05-17) — built on a new `fs_realpath` helper (3-mode canonicalization) in `src/lib/fs.cyr`. Default `-e` requires every component, `-m` allows missing tails, `-q` silent, `-z` NUL. Cycle ELOOP at 40 hops.
  3. ✅ `readlink` (2026-05-17) — POSIX raw read-link + canonicalize via shared `fs_realpath`. Display modifiers `-n`/`-z`/`-q`.
  4. ✅ `which` (2026-05-17) — `$PATH` walk with `-a`/`-s`/`-z`; slash-literal bypasses PATH.
  5. ✅ `stat` (2026-05-17) — printf-style format engine, `-c`/`--printf`/`-L`/`-t`; 22 specifiers verified cell-by-cell against GNU.
  6. ✅ `ls` (2026-05-17) — `-a`/`-A`/`-l`/`-h`/`-r`/`-1`/`-F`/`-i`/`-d`/`-R`; two-pass long-form with right-justified column alignment; ISO mtime via `chrono.epoch_to_date`. **Closes M3.**
- **M3 closed 2026-05-17 at v0.4.0.** All seven planned utilities ship. Cold-start at v0.4.0 median 1.208ms (~50µs uptick from v0.3.0 — still well under the 2ms v1.0 target).
- **M4 in progress** (text-stream utilities; 10 utilities — largest milestone by count). Order (simplest → biggest):
  1. ✅ `tee` (2026-05-17) — pass-through fan-out; `-a` append; resilient per-file failure. M4 opener.
  2. ✅ `wc` (2026-05-17) — streaming `-l`/`-w`/`-c`/`-m`/`-L`; GNU-compatible column-width matrix verified cell-by-cell.
  3. ✅ `head` + `tail` (2026-05-17, paired) — `-n`/`-c`/`-q`/`-v`; head streams forward, tail buffers up to 16 MiB and back-walks. `-f` follow mode deferred.
  4. ✅ `nl` (2026-05-17) — single-section line numbering; `-b`/`-i`/`-n`/`-s`/`-v`/`-w`. GNU's `width + sep_len` unnumbered-padding quirk matched and tested.
  5. ✅ `uniq` (2026-05-17) — adjacent-line dedup; `-c`/`-d`/`-u`/`-i`/`-f`/`-s`/`-w`/`-z`; 2-op INPUT OUTPUT.
  6. ✅ `tr` (2026-05-17) — translate/delete/squeeze/complement; full POSIX set grammar incl. all 12 character classes.
  7. `cut` — column extraction by char range / field. Next.
  8. `tail -f` — follow mode (inotify-driven).
  9. `sort` — line sort; in-memory + external-sort fallback.
  10. `printf` — printf-style format engine (largest M4 utility; reuses concepts from `stat`'s format parser).
- Deferred features tracked against future enablers (each a known-named follow-up, not "TBD"):
  - echo `-e`/`-E` — waits on `lib/str.cyr` escape table.
  - pwd `$PWD` inode-match — waits on `fs.cyr` stat-compare.
  - sleep fractional + suffix (`1.5s`, `1m`, `1h`) — waits on `lib/chrono.cyr` duration-parser.
  - touch `-r REF` / `-t STAMP` / `-d STR` — same `lib/chrono.cyr` dependency; `-h` (no-dereference) deferred until symlink-aware utimensat wrapper.
  - ln `-r` (relative symlink resolution), `-T`/`-t` (target-directory disambiguation), `-b`/`--backup` — separate-PR work in M3.
  - mkdir / touch decimal POSIX-mode constants (`511 # 0o777`, `1073741823 # UTIME_NOW`) — sweep to octal once Cyrius proposal `2026-05-17-octal-literal-syntax` lands.
  - touch `syscall(280, ...)` and ln `syscall(265, ...)` — sweep to `sys_utimensat`/`sys_linkat` once Cyrius proposal `2026-05-17-syscalls-at-family-stdlib` lands.
  - Option-parser short clustering `-rfv` and attached short values `-n10` — waits on stdlib `lib/flags.cyr` upgrade. ADR 0002 honoured end-to-end after that.
  - `--help` / `--help=json` / `kriya --list` per ADR 0002 — waits on the spec-renderer on top of `flags.cyr`.
  - CI / release / build-script review — flagged 2026-05-17 against kindred Cyrius repos (`agnos`, `vidya`, `owl`, `cyim`, `sit`).

## Next

See [`roadmap.md`](roadmap.md).
