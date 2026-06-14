# kriya — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**1.1.4** — released 2026-05-18. **v1.0 freeze.** Closes M9. **38 POSIX-style utilities** + dispatcher; **8 ADRs**; **2 audits** (POSIX compliance + security); per-utility benchmarks vs GNU; fuzz harnesses for the three parser-style utilities. **7 of 8 v1.0 criteria met**; the 8th (downstream-consumer-green via AGNOS boot-burn) is deferred to a post-1.0 consumer-burn cycle per user direction (parallel signal, not blocker). Test totals: **104 in-process assertions** (86 unit + 18 POSIX-blessed), **1529 fuzz assertions** (1127 grep + 201 find + 201 printf), **644 smoke cases** across 27 shell scripts. Cold-start median **1.196 ms** (RUNS=100; 60% of the 2 ms v1.0 budget).

**1.1.4** — released 2026-05-18. **Closes M8** (security audit + per-utility benchmarks). Two deliverables: (1) `docs/audit/2026-05-18-security.md` — security audit with external CVE/0-day research, primary input the Canonical-commissioned uutils-coreutils audit (CVE-2026-35338 through CVE-2026-35381, 41 CVEs against the exact surface kriya occupies). Cross-walk: 34 N/A or already-mitigated, **3 newly exposed and patched here** (F1 cp recursive source NOFOLLOW, F4 find -empty NOFOLLOW, F5 grep -r NOFOLLOW), 2 documented as POSIX-conformant (F2 cp -f dst, F6 non-recursive grep operand). (2) `docs/benchmarks.md` + `scripts/bench-throughput.sh` — per-utility throughput vs GNU with named optimization follow-ups for the visible gaps (`wc -c` short-circuit, niyama literal Boyer-Moore, `tail` seek-from-end). Cold-start median **1.201ms** (RUNS=100; flat from v0.8.0). **6 of 8 v1.0 criteria now checked** — remaining: fuzz harnesses for parser-style utilities, one downstream consumer green (AGNOS kernel boot-burn).

**1.1.4** — released 2026-05-18. **Closes M7** (POSIX.1-2017 compliance audit). No new utilities — three deliverables: (1) `docs/audit/2026-05-18-posix-compliance.md` walks every shipped utility against POSIX with deviation cataloging (32 of 38 POSIX-defined; 6 intentional kriya-scope extensions; no quiet divergences); (2) three new ADRs — **0006** utility scope (`yes`/`seq`/`stat`/`realpath`/`readlink`/`which` and the four-criteria gate), **0007** `date` UTC-only at v0.7.0 with local-time follow-up named, **0008** POSIX exit-code policy (three-tier baseline + per-utility POSIX overrides); (3) `tests/kriya-posix.tcyr` — fork+execve+pipe-capture harness plus 18 starter POSIX-blessed cases per pillar utility. **104 in-process test cases** (86 unit + 18 POSIX) across two tcyr files; 644 smoke cases across 27 shell scripts. Cold-start median **1.201ms** (RUNS=100; flat from v0.7.0's 1.212ms — no new dispatcher entries).

**1.1.4** — released 2026-05-18. **Closes M6** (system info + misc): five utilities (`seq`, `env`, `date`, `du`, `df`) + the cross-FS directory `mv` follow-up earlier in this cycle. **168 behavioural smoke cases across the M6 utilities** (44 seq + 28 env + 44 date + 37 du + 15 df), every flag and shape compared cell-by-cell against GNU coreutils where applicable. Cyrius pin bumped to **5.11.61**. Cold-start re-bench (RUNS=100): median **1.212ms** (RUNS=100; flat-ish from v0.6.0's 1.192ms — the 5 new dispatcher entries land after the `true` hot path). **38 shipped utilities** total (6 M1 + 7 M2 + 7 M3 + 10 M4 + 3 M5 + 5 M6). After v0.7.0 the kriya surface covers every POSIX-essential utility in M1–M6; remaining v1.0 work is M7 POSIX-compliance audit, M8 security audit + per-utility benchmarks, M9 freeze.

**1.1.4** — released 2026-05-17. **Closes M5** (filtering/search): three utilities (`grep`, `find`, `xargs`) on niyama (regex per ADR 0005) + process.cyr (fork+execve). **126 behavioural smoke cases** across the three M5 utilities, every one compared cell-by-cell against GNU. Cyrius pin bumped to **5.11.59**. Cold-start median **1.192ms** (RUNS=100; flat from v0.5.0's 1.198ms — the three new dispatcher entries land after the `true` hot path). **Closes M4** (text-stream utilities) at 0.5.0: ten new utilities (`tee`, `wc`, `head`, `tail` incl. `-f`, `nl`, `uniq`, `tr`, `cut`, `sort`, `printf`) built on streaming-bounded-memory or stable-merge-sort foundations. `tail -f` adds the first poll-loop in kriya (200ms stat cadence, single-file only); `sort` adds an in-memory stable merge sort with a 256 MiB cap; `tr`'s set parser covers all 12 POSIX character classes plus ranges/octal/escapes; `printf` ships the full format engine (every conversion except floating-point — `%e`/`%f`/`%g` named as a deferred follow-up). **710 behavioural smoke cases across all 23 shipped utilities**, every one compared cell-by-cell against GNU coreutils where applicable. 86/86 unit assertions. Cold-start median **1.198ms** (RUNS=30, sampled across 4 trials at 1.225/1.175/1.202/1.193ms; essentially flat from v0.4.0's 1.208ms despite 10 new dispatcher entries — the `true` hot path remains unaffected since matches resolve before the new entries).

## Role

Coreutils-equivalent for AGNOS — the small POSIX-style utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep` …) in one repo, sharing a `src/lib/` of path / errno / argument-parsing primitives. Each utility is a separate command (via symlink → dispatcher). Sovereign-replacement boundaries documented in `CLAUDE.md` (owl owns `cat`, sit owns `git`, chakshu owns `htop`, cyim owns `vim`, agnoshi owns shell builtins — kriya fills the gaps).

## Toolchain

- **Cyrius pin**: `5.11.61` (in `cyrius.cyml [package].cyrius`)

## Source

M1 closed at v0.2.0; M2 closed at v0.3.0; M3 closed at v0.4.0; M4 closed at v0.5.0; M5 closed at v0.6.0; M6 closed at v0.7.0; M7 closed at v0.8.0; M8 closed at v0.9.0; **M9 closed at v1.0.0 — v1.0 freeze**. **Thirty-eight shipped utilities** (six M1 + seven M2 + seven M3 + ten M4 + three M5 + five M6: `seq`, `env`, `date`, `du`, `df`); six shared lib modules in place (`exit`, `path`, `errmsg`, `args`, `fs`, `protected`); **eight** ADRs accepted (0001–0008); two architecture notes (signal model + errno policy); M7 POSIX audit at `docs/audit/2026-05-18-posix-compliance.md`; M8 security audit at `docs/audit/2026-05-18-security.md`; per-utility benchmarks at `docs/benchmarks.md`. Cold-start re-benched at each release boundary: 1.185ms (v0.2.0) → 1.159ms (v0.3.0) → 1.208ms (v0.4.0) → 1.198ms (v0.5.0) → 1.192ms (v0.6.0) → 1.212ms (v0.7.0) → 1.201ms (v0.8.0) → 1.201ms (v0.9.0) → **1.196ms (v1.0.0)** — flat through M7+M8+M9 (no new dispatcher entries; M9 adds three fuzz `.fcyr` files which aren't part of the production binary).

| Module | Status |
|---|---|
| `src/main.cyr` | implemented — dispatch by `argv[0]` basename via `path_basename_ptr`, fallback to `argv[1]` when invoked as `kriya` |
| `src/lib/path.cyr` | implemented — `path_basename_ptr`, `path_dirname`, `path_is_absolute`, `path_normalize`, `path_join`, `path_is_under` |
| `src/lib/exit.cyr` | implemented — `EXIT_SUCCESS`/`EXIT_FAILURE`/`EXIT_USAGE` enum |
| `src/lib/errmsg.cyr` | implemented — errnos 1..40 + `errmsg_is_known` |
| `src/lib/args.cyr` | implemented — flat-argv builder + stdlib `flags_parse` wrapper + `kriya_parse_nonneg_int` |
| `src/cmd/*.cyr` | 38 of ~40 — M1 (6) + M2 (7) + M3 (7) + M4 (10) + M5 (3) + M6 (5: `seq`, `env`, `date`, `du`, `df`) |
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
| `mv` | `src/cmd/mv.cyr` | **implemented** (`-f`/`-i`/`-n`/`-v`; same-FS rename; cross-FS files+symlinks+**directories** via cp -R + rm -r with dest-tree rollback on either-step failure; ADR-0003 symlink-to-dir refusal) | M2 |
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
| `tail` | `src/cmd/tail.cyr` | **implemented** (`-n`/`-c`/`-q`/`-v`/`-f`; buffer-and-back-walk up to 16 MiB cap; single-file `-f` via 200ms stat-poll; defer multi-file `-f`, `-F`, `+N` start-from, suffixes) | M4 |
| `cut` | `src/cmd/cut.cyr` | **implemented** (`-b`/`-c`/`-f` modes, full LIST grammar, `-d`/`-s`/`--complement`/`--output-delimiter`/`-z`; defer multibyte char distinction) | M4 |
| `tr` | `src/cmd/tr.cyr` | **implemented** (translate/delete/squeeze/complement/truncate; full POSIX set grammar incl. 12 character classes; defer [=c=] + [c*N] + locale folding) | M4 |
| `tee` | `src/cmd/tee.cyr` | **implemented** (`-a`; resilient per-file failure; `-i` SIGINT-ignore deferred to signal-handler infra) | M4 |
| `sort` | `src/cmd/sort.cyr` | **implemented** (`-n`/`-r`/`-u`/`-f`/`-b`/`-t`/`-k`/`-c`/`-o`/`-z`/`-s`; in-memory stable merge sort, 256 MiB cap; defer `-h`/`-V`/`-g`/`-M`/`-R`/`-m`/`-d`/`-i`, multi-key, external sort) | M4 |
| `uniq` | `src/cmd/uniq.cyr` | **implemented** (`-c`/`-d`/`-u`/`-i`/`-f`/`-s`/`-w`/`-z`; 2-op input/output; defer `--all-repeated`/`--group`) | M4 |
| `nl` | `src/cmd/nl.cyr` | **implemented** (single-section; `-b`/`-i`/`-n`/`-s`/`-v`/`-w`; defer `-d`/`-h`/`-f`/`-l`/`-p` sections + `-b p REGEX`) | M4 |
| `printf` | `src/cmd/printf.cyr` | **implemented** (every POSIX conversion except float `%e`/`%f`/`%g`; full flag matrix `- + space # 0`; width + precision with `*`; arg reuse; format escapes incl. octal `\NNN`) | M4 |
| `grep` | `src/cmd/grep.cyr` | **implemented** (`-i`/`-v`/`-w`/`-x`/`-c`/`-l`/`-L`/`-n`/`-q`/`-s`/`-h`/`-H`/`-o`/`-r`/`-R`/`-z`/`-E`/`-G`/`-F`/`-e`/`-f`; BRE+RE2 via niyama per ADR 0005; `-P` rejected with usage error; defer multi-`-e`, `-A`/`-B`/`-C`, `--include`/`--exclude`, `--color`, `-Z`) | M5 |
| `find` | `src/cmd/find.cyr` | **implemented** (`-name`/`-type`/`-size`/`-mtime`/`-mmin`/`-empty`/`-newer`/`-maxdepth`/`-mindepth`; `-print`/`-print0`/`-exec ... \\;`; `!`/`-not`/`-a`/`-o`/`(`/`)`; `-P` default, `-L` follow; `-H`/`-prune`/`-delete`/`-exec ... +`/`-regex`/`-perm`/`-user`/`-group`/`-depth` deferred) | M5 |
| `xargs` | `src/cmd/xargs.cyr` | **implemented** (`-0`/`-n`/`-I`/`-r`/`-t`/`-s`; whitespace + backslash + single/double-quote splitting; default `/bin/echo`; GNU-shaped exit-code rollup; defer `-P` parallel, `-p` prompt, `-L` lines-per-cmd, `-x` overflow-exit) | M5 |
| `df` | `src/cmd/df.cyr` | not started | M6 |
| `du` | `src/cmd/du.cyr` | **implemented** (`-s`/`-a`/`-c`/`-h`/`-k`/`-b`/`-L`/`-P`/`-d N`/`-S` + long-form aliases; 1024-byte blocks by default matching GNU; `-b` apparent-size with dir-st_size-skipped semantic; `-h` K/M/G/T with GNU-compatible 1-decimal precision; ADR-0003 default `-P` no-follow; missing-file exit 1; `-a`/`-s` mutex per GNU; hardlink dedup deferred to inode-set follow-up; `-x` one-FS, `--exclude`, `--inodes`, `-0` deferred) | M6 |
| `date` | `src/cmd/date.cyr` | **implemented** (UTC-only at v0.7.0; `-u`/`--utc`/`--universal` accepted as no-ops; `+FORMAT` with 28 strftime specifiers: `%Y`/`%y`/`%m`/`%d`/`%e`/`%H`/`%I`/`%M`/`%S`/`%p`/`%P`/`%j`/`%u`/`%w`/`%a`/`%A`/`%b`/`%h`/`%B`/`%Z`/`%z`/`%s`/`%N` (zeros)/`%T`/`%R`/`%D`/`%F`/`%n`/`%t`/`%%`; GNU `%_d` pad form; `%X` passthrough for unknown — `%V`/`%q`/`%c`/`%x`/`%G`/`%g`/`%r` and tzfile-aware local time deferred behind `localtime`/`/etc/localtime` parsing follow-up) | M6 |
| `env` | `src/cmd/env.cyr` | **implemented** (`-i`/`-`/`--ignore-environment` clear; `-u`/`--unset NAME` repeatable; `-0`/`--null` NUL-sep print; NAME=VALUE assignments; `--` end-of-options with assignments still scanned; in-order op application so `-u FOO FOO=x` keeps FOO=x and `FOO=x -u FOO` drops it; PATH-resolved sys_execve direct replace, no fork; exit 127 ENOENT/126 other on exec failure) | M6 |
| `seq` | `src/cmd/seq.cyr` | **implemented** (1/2/3-operand shapes; `-s SEP` short+long+attached; `-w` equal-width with sign-aware padding; `-- ` and `-DIGIT` negative-FIRST UX via in-utility argv walk; `-f FORMAT` deferred behind printf %f follow-up; integer only) | M6 |

## Binary

- Dispatcher: `kriya` (output in `build/kriya` after `cyrius build`)
- Per-utility commands: symlinks → `kriya` (`cp` → `kriya`, `mv` → `kriya`, etc.)
- Size: TBD (first build pending)

## Tests

- `tests/kriya-posix.tcyr` — POSIX-blessed assertion harness (18/18 passing — fork+execve+pipe-capture helper for `build/kriya`; one starter case per pillar utility: `true`/`false`/`echo`/`pwd`/`wc`/`grep`/`cp`/`ls`/`seq`/`env`/`date`/`find`/`xargs`. Population is incremental).
- `tests/kriya.tcyr` — primary unit suite (78/78 passing — exit codes, cmd routes, path primitives, errmsg table, integer parser, octal-mode parser).
- `tests/kriya.bcyr` — in-process hot-path bench (stdlib `lib/bench.cyr`). Steady-state numbers (Cyrius 5.11.59, x86_64):
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
- `scripts/smoke-mv.sh` — behavioural test for `mv` (51/51 — same-FS rename, overwrite default, `-n` silent skip, `-i`-on-pipe usage error, multi-into-dir, dir rename, ADR-0003 symlink-to-dir refusal in both single-pair and multi-into-dir shapes, self-move detection, partial-failure paths, verbose. Cross-FS round-trips when `/tmp` and `/dev/shm` differ — file with inode-differs assertion, symlink with target preservation, **cross-FS directory round trip via cp -R + rm -r with nested files, nested subdir, preserved symlink, preserved subdir mode 0750; rollback assertion when dest blocker file makes cp -R fail**).
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
- `scripts/smoke-cut.sh` — behavioural test for `cut` (31/31 — `-b`/`-c`/`-f` modes cell-by-cell against GNU; every LIST grammar form `N`/`N-`/`-M`/`N-M` and combinations; default-TAB delim; `-s` only-delim with mixed-input handling; `--complement`; `--output-delimiter`; multi-file; usage-error matrix).
- `scripts/smoke-sort.sh` — behavioural test for `sort` (23/23 — every flag combo cell-by-cell against `LC_ALL=C sort`; default lex, `-n` with negatives, `-r`, `-u`, `-f` case-fold, `-b` blank-skip, `-t`/`-k`, combined flags, empty + no-trailing-newline edges, multi-file concat, `-c` check on sorted + unsorted, `-o` output redirect, `-z` NUL, stability on equal keys, 1000-line numeric sort).
- `scripts/smoke-grep.sh` — behavioural test for `grep` (66/66 — every flag and engine combo cell-by-cell against GNU `grep`: BRE patterns (literal, anchors, bracket-class, star, escaped-group, dot), ERE via `-E` (`+`, `{n,m}`, group, alternation), `-F` fixed-string, `-i` across all three engines, `-v`/`-c`/`-n`/`-w`/`-x`/`-o`/`-h`/`-H`/`-s`, `-l`/`-L` multi-file, `-e`/`-f` patterns, stdin via pipe + `-` operand, `-z` NUL-separated I/O, `-r` recursive, exit codes, `-P` rejection).
- `scripts/smoke-find.sh` — behavioural test for `find` (40/40 — default print, `-type` matrix, `-name` glob coverage (literal, `*`, `?`, bracket-class, no-match), `-size` exact/`+`/`-`/default-block, `-empty`, `-newer`, `-mtime ±N`, `-maxdepth 0/1/2`, `-mindepth`, AND/OR/parens/`!`/`-not`, `-print`/`-print0`/`-exec` (PATH-resolved + with `wc -l`), `-L` symlink follow, multi-start-path, exit codes for unknown predicate / bad `-size` / missing `-exec ;` / missing start path / `-H` deferred).
- `scripts/smoke-xargs.sh` — behavioural test for `xargs` (20/20 — default echo / explicit CMD, `-n 1`/`-n 2`/`-n 3` batching, `-0` NUL items with spaces preserved, `-I {}` and `-I @` substitution including multi-substitution per token, `-r` empty-stdin guard matching `--no-run-if-empty`, quoting (single/double/backslash), `-t` trace to stderr, `123` exit on child failure, PATH-resolved commands).
- `scripts/smoke-du.sh` — behavioural test for `du` (37/37 — every shipped flag and combination compared cell-by-cell against GNU `du`: default 1024-block per-dir, `-s` summarize, `-a` all-entries, `-h` human K/M/G suffix (verified against 5MiB binary), `-b` apparent-size with dir-st_size-skipped semantic, `-c` grand total across multiple operands, `-d` depth limit (0/1/2), `-S` separate-dirs, ADR-0003 `-P` default no-follow + `-L` follow on symlink-to-dir, long forms `--summarize`/`--all`/`--total`/`--bytes`/`--human-readable`/`--max-depth=N`, default-to-`.`, exit 1 on missing file, exit 2 on unknown flag / `-d` missing arg / `--max-depth=` bad value).
- `scripts/smoke-date.sh` — behavioural test for `date` (44/44 — every shipped strftime specifier compared cell-by-cell against GNU `date` under `LC_ALL=C TZ=UTC`; default format `%a %b %e %H:%M:%S %Z %Y`; composite specifiers `%T`/`%R`/`%D`/`%F`; weekday `%a`/`%A`/`%u`/`%w`; month `%b`/`%h`/`%B`; 12-hour `%I`/`%p`/`%P`; epoch `%s` parity within 1 second; `%N` stubbed zeros; `%_d` pad form; truly-unknown specifier `%X` passthrough via `%@`/`%!`; `-u`/`--utc`/`--universal` no-op; exit codes 0/2 matrix).
- `scripts/smoke-env.sh` — behavioural test for `env` (28/28 — env-prints with default + `-i` + `-` + `--ignore-environment`; assignments + `-u`/`--unset`/`--unset=` removals applied in token order so `-u FOO FOO=x` keeps FOO=x and `FOO=x -u FOO` drops it; `--` ends option recognition but scans assignments until first non-assignment; `-0`/`--null` NUL-separated print; PATH resolution via modified env; sys_execve direct replace (no fork); exit 127 ENOENT / 126 EACCES; clustered shorts `-iu PATH`; absolute-path commands bypass PATH; usage errors at exit 2 for unknown options, missing -u argument, empty -u NAME).
- `scripts/smoke-seq.sh` — behavioural test for `seq` (44/44 — every shape (1/2/3 operands) and flag combo (`-s` short/long/attached/`=`-form, `-w` equal-width including width 1/2/3 boundaries) compared cell-by-cell against GNU `seq`; `-DIGIT` bare negative-FIRST UX via in-utility argv walk; `--` terminator; descending direction with negative incr; empty-output cases (incr-direction disagrees with bounds); error matrix (zero incr, no operand, too many operands, unknown short/long option, bad numeric operand) at exit 2; deferred `-f`/`--format` at exit 2).
- `tests/kriya-grep.fcyr` — fuzz harness for grep's regex parser (niyama BRE + RE2 + bracket-class boundary patterns). 1127 assertions over 3000+ random patterns; deterministic xorshift seed for replayability.
- `tests/kriya-find.fcyr` — fuzz harness for find's predicate AST via fork+exec. 201 assertions over 200 random argv combinations from find's lexicon.
- `tests/kriya-printf.fcyr` — fuzz harness for printf's format engine via fork+exec. 201 assertions over 200 random format strings + arg permutations.
- `scripts/fuzz.sh` — convenience runner for all three fuzz harnesses; opt-in (not part of `cyrius test` default discovery).

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`, `args`, `flags`, `chrono`, `fnptr`, `bench`, `assert`, **`niyama`** (regex; pulled by `grep` per ADR 0005), **`process`** (fork+execve for `find -exec`), **`unicode/{_decode,categories,_categories_data,casefold,_casefold_data,normalize,_normalize_data}`** (transitive niyama deps for the fuzzy-engine NFD path).

External: none (and none planned for v1.0).

## Consumers

_None yet._ Expected consumers once M1 ships:

- [agnoshi](https://github.com/MacCracken/agnoshi) — shell relies on `$PATH` lookup of `cp`, `mv`, `rm`, etc.
- [zugot](https://github.com/MacCracken/zugot) — package manager builds will install kriya symlinks at recipe time

## In-flight work

- **M0 ✅ v0.1.0** (scaffold) — `cyrius init kriya`, doc-tree, sovereign-replacement boundaries.
- **M1 ✅ v0.2.0** (2026-05-17) — dispatcher + 6 trivial utilities; ADR 0001 (BusyBox dispatcher) + ADR 0002 (option parsing) accepted; cold-start median 1.185ms.
- **M2 ✅ v0.3.0** (2026-05-17) — 7 file-operation utilities (`mkdir`, `rmdir`, `touch`, `ln`, `cp` incl. full `-R` matrix, `mv`, `rm`); ADR 0003 (symlink-follow policy) + ADR 0004 (`rm` refuses `/`) accepted; new shared libs `src/lib/fs.cyr` (`*at()` traversal) and `src/lib/protected.cyr` (root refusal); 2 Cyrius proposals filed against parent repo (octal literals + at-family stdlib).
- **M3 ✅ v0.4.0** (2026-05-17) — 7 listing/path utilities (`basename`, `dirname`, `realpath`, `readlink`, `which`, `stat`, `ls`); new `fs_realpath` helper (3-mode canonicalization) backs both `realpath` and `readlink -f`/`-e`/`-m`; `ls -l` mtime via `chrono.epoch_to_date`.
- **M4 ✅ v0.5.0** (2026-05-17) — 10 text-stream utilities (`tee`, `wc`, `head`, `tail` incl. `-f`, `nl`, `uniq`, `tr`, `cut`, `sort`, `printf`); 710 behavioural smoke cases across all 23 M2+M3+M4 utilities; cold-start median **1.198ms** (flat from v0.4.0).
- **M6 ✅ v0.7.0** (2026-05-18, user-resumed mid-hold) — 5 system-info/misc utilities (`seq`, `env`, `date`, `du`, `df`) with 168 behavioural smoke cases vs GNU. `seq` integer-only with `-DIGIT` negative-FIRST UX (float `-f FORMAT` deferred behind printf %f/%g). `env` is fork-free `sys_execve` direct replace; in-order op application matches GNU's `-u FOO FOO=x` vs `FOO=x -u FOO` semantics. `date` ships 28 strftime specifiers under UTC (local-time tzfile parsing deferred). `du` reuses `fs_getdents64` walk with `-b` apparent-size + dir-st_size-skip; hardlink dedup deferred. `df` parses `/proc/self/mounts` with octal-escape decoding + builtin pseudo-FS filter. **Cold-start 1.212ms** (RUNS=100; slight uptick from v0.6.0's 1.192ms, well under the 2ms v1.0 target). Cyrius pin bumped to **5.11.61**. Cross-FS directory `mv` also shipped earlier in this cycle — the only remaining M2 follow-up, now closed.
- **M5 ✅ v0.6.0** (2026-05-17, user-resumed mid-hold) — three utilities (`grep`, `find`, `xargs`) with 126 behavioural smoke cases against GNU. grep uses niyama (ADR 0005) with `-i`/`-v`/`-w`/`-x`/`-c`/`-l`/`-L`/`-n`/`-q`/`-s`/`-h`/`-H`/`-o`/`-r`/`-R`/`-z`/`-E`/`-G`/`-F`/`-e`/`-f`; `-P` rejected. find ships POSIX-essential predicates (`-name`/`-type`/`-size`/`-mtime`/`-mmin`/`-empty`/`-newer`/`-maxdepth`/`-mindepth`), actions (`-print`/`-print0`/`-exec`), operators (full boolean grammar with parens), `-P` default + `-L` follow. xargs ships `-0`/`-n`/`-I`/`-r`/`-t`/`-s` with GNU-shaped exit-code rollup. **Cold-start 1.192ms** (flat from v0.5.0).

### Mid-cycle resumes (M5 + M6, 2026-05-17/18)

M5 was resumed on 2026-05-17 by user request, pre-boot-burn. All three utilities (`grep`, `find`, `xargs`) shipped in one session; v0.6.0 cut the same day. M6 was resumed on 2026-05-18 — `seq`, `env`, `date`, `du`, `df` shipped in one session; v0.7.0 cut the same day. M7/M8/M9 all followed on 2026-05-18 in the same momentum window, landing at v1.0.0.

### Post-1.0 — sequenced in roadmap.md

Post-1.0 milestones M10–M14 live in [`roadmap.md`](roadmap.md). Summary:

- **M10 — Consumer-burn** — the last v1.0 criterion. Trigger: AGNOS USB-keyboard-on-boot resolves → AGNOS coreutils integration → first green boot-burn → 1.0.1 with consumer-burn audit. Parallel signal on the kernel team's timeline, not a blocker.
- **M11 — Cyrius proposal sweeps** — octal-literal cleanup, raw-syscall → stdlib-wrapper cleanup. Triggered by upstream Cyrius acceptance.
- **M12 — POSIX-deviation fill-in** — GNU-parity features grouped by enabler dependency (chrono, flags, stdlib helpers, per-utility independent).
- **M13 — Performance optimization** — `wc -c` short-circuit, niyama Boyer-Moore, `tail` seek-from-end, speculative items.
- **M14 — stdlib `getenv` post-fork bug** — upstream Cyrius fix; kriya then strips PATH-cache workaround.

Each can advance independently against a tagged 1.x.y minor.

## Next

See [`roadmap.md`](roadmap.md).
