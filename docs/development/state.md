# kriya — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.2.0** — released 2026-05-17. Closes M1: dispatcher + six utilities (`true`/`false`/`echo`/`pwd`/`yes`/`sleep`), four shared lib modules, two architecture notes, dispatcher cold-start benchmark (1.185ms median).

## Role

Coreutils-equivalent for AGNOS — the small POSIX-style utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep` …) in one repo, sharing a `src/lib/` of path / errno / argument-parsing primitives. Each utility is a separate command (via symlink → dispatcher). Sovereign-replacement boundaries documented in `CLAUDE.md` (owl owns `cat`, sit owns `git`, chakshu owns `htop`, cyim owns `vim`, agnoshi owns shell builtins — kriya fills the gaps).

## Toolchain

- **Cyrius pin**: `5.11.54` (in `cyrius.cyml [package].cyrius`)

## Source

M1 fully closed. All six M1 utilities, all four planned `src/lib/` modules, both M1 architecture notes, and the dispatcher cold-start benchmark have shipped. Cold-start median 1.185ms (target ≤2ms per v1.0 acceptance).

| Module | Status |
|---|---|
| `src/main.cyr` | implemented — dispatch by `argv[0]` basename via `path_basename_ptr`, fallback to `argv[1]` when invoked as `kriya` |
| `src/lib/path.cyr` | implemented — `path_basename_ptr`, `path_dirname`, `path_is_absolute`, `path_normalize`, `path_join`, `path_is_under` |
| `src/lib/exit.cyr` | implemented — `EXIT_SUCCESS`/`EXIT_FAILURE`/`EXIT_USAGE` enum |
| `src/lib/errmsg.cyr` | implemented — errnos 1..40 + `errmsg_is_known` |
| `src/lib/args.cyr` | implemented — flat-argv builder + stdlib `flags_parse` wrapper + `kriya_parse_nonneg_int` |
| `src/cmd/*.cyr` | 8 of ~40 — `true.cyr`, `false.cyr`, `echo.cyr`, `pwd.cyr`, `yes.cyr`, `sleep.cyr`, `mkdir.cyr`, `rmdir.cyr` |

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
| `touch` | `src/cmd/touch.cyr` | not started | M2 |
| `cp` | `src/cmd/cp.cyr` | not started | M2 |
| `mv` | `src/cmd/mv.cyr` | not started | M2 |
| `rm` | `src/cmd/rm.cyr` | not started | M2 |
| `ln` | `src/cmd/ln.cyr` | not started | M2 |
| `ls` | `src/cmd/ls.cyr` | not started | M3 |
| `stat` | `src/cmd/stat.cyr` | not started | M3 |
| `basename` | `src/cmd/basename.cyr` | not started | M3 |
| `dirname` | `src/cmd/dirname.cyr` | not started | M3 |
| `realpath` | `src/cmd/realpath.cyr` | not started | M3 |
| `readlink` | `src/cmd/readlink.cyr` | not started | M3 |
| `which` | `src/cmd/which.cyr` | not started | M3 |
| `wc` | `src/cmd/wc.cyr` | not started | M4 |
| `head` | `src/cmd/head.cyr` | not started | M4 |
| `tail` | `src/cmd/tail.cyr` | not started | M4 |
| `cut` | `src/cmd/cut.cyr` | not started | M4 |
| `tr` | `src/cmd/tr.cyr` | not started | M4 |
| `tee` | `src/cmd/tee.cyr` | not started | M4 |
| `sort` | `src/cmd/sort.cyr` | not started | M4 |
| `uniq` | `src/cmd/uniq.cyr` | not started | M4 |
| `nl` | `src/cmd/nl.cyr` | not started | M4 |
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
- `scripts/bench-coldstart.sh` — process-spawn timing. `RUNS=30` baseline: min 1.010ms, **median 1.185ms**, max 1.374ms — under the 2ms v1.0 target.
- `scripts/smoke-mkdir.sh` — behavioural test for `mkdir` (24/24 passing — happy path, `-p` recursion, EEXIST split, `-m` mode bits, partial-failure exit, root operand). Pattern carries forward as each M2 utility ships.
- `scripts/smoke-rmdir.sh` — behavioural test for `rmdir` (24/24 — happy path, `-p` cascade with sibling-halt, `--ignore-fail-on-non-empty`, ENOTEMPTY/ENOENT/ENOTDIR, kernel-EBUSY on `/`, `-v` output).
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
  3. `touch` — pure-create / metadata-update; no traversal.
  4. `ln` — symlink + hard-link; the first user-facing surface of ADR 0003's `-P` semantics for `ln`.
  5. `cp` — recursive copy under ADR 0003's preserve-by-default policy; `O_NOFOLLOW` on destinations.
  6. `mv` — rename / cross-FS copy+unlink; symlink-to-dir refusal from ADR 0003.
  7. `rm` — last, and most carefully — full ADR 0003 (`O_NOFOLLOW` traversal, no follow flag) and ADR 0004 (`protected_paths[]` check) enforcement.
- M2 also introduces `src/lib/fs.cyr` (the `*at()` traversal + `O_NOFOLLOW` discipline lives there, shared across `cp`/`mv`/`rm`) and `src/lib/protected.cyr` (the `protected_paths[]` table from ADR 0004).
- Deferred features tracked against future enablers (each a known-named follow-up, not "TBD"):
  - echo `-e`/`-E` — waits on `lib/str.cyr` escape table.
  - pwd `$PWD` inode-match — waits on `fs.cyr` stat-compare.
  - sleep fractional + suffix (`1.5s`, `1m`, `1h`) — waits on `lib/chrono.cyr` duration-parser.
  - Option-parser short clustering `-rfv` and attached short values `-n10` — waits on stdlib `lib/flags.cyr` upgrade. ADR 0002 honoured end-to-end after that.
  - `--help` / `--help=json` / `kriya --list` per ADR 0002 — waits on the spec-renderer on top of `flags.cyr`.
  - CI / release / build-script review — flagged 2026-05-17 against kindred Cyrius repos (`agnos`, `vidya`, `owl`, `cyim`, `sit`).

## Next

See [`roadmap.md`](roadmap.md).
