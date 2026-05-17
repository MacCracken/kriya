# kriya — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.1.0** — scaffolded 2026-05-15 via `cyrius init`. No releases yet.

## Role

Coreutils-equivalent for AGNOS — the small POSIX-style utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep` …) in one repo, sharing a `src/lib/` of path / errno / argument-parsing primitives. Each utility is a separate command (via symlink → dispatcher). Sovereign-replacement boundaries documented in `CLAUDE.md` (owl owns `cat`, sit owns `git`, chakshu owns `htop`, cyim owns `vim`, agnoshi owns shell builtins — kriya fills the gaps).

## Toolchain

- **Cyrius pin**: `5.11.54` (in `cyrius.cyml [package].cyrius`)

## Source

M1 walking skeleton landed — dispatcher routes `argv[0]` basename (or `kriya <util>`) to the registered `cmd_*` functions. Two utilities wired; the remaining M1 utilities and lib modules are pending.

| Module | Status |
|---|---|
| `src/main.cyr` | implemented — dispatch by `argv[0]` basename, fallback to `argv[1]` when invoked as `kriya` |
| `src/lib/path.cyr` | not started — path manipulation primitives |
| `src/lib/exit.cyr` | implemented — `EXIT_SUCCESS`/`EXIT_FAILURE`/`EXIT_USAGE` enum |
| `src/lib/errmsg.cyr` | not started — errno → message |
| `src/lib/args.cyr` | not started — POSIX-style argument parsing (on top of stdlib `lib/args.cyr`) |
| `src/cmd/*.cyr` | 2 of ~40 — `true.cyr`, `false.cyr` |

## Per-utility status (will grow with each milestone)

| Utility | Module | Status | Roadmap milestone |
|---|---|---|---|
| `echo` | `src/cmd/echo.cyr` | not started | M1 |
| `pwd` | `src/cmd/pwd.cyr` | not started | M1 (note: agnoshi has a builtin; kriya provides the binary form) |
| `true` | `src/cmd/true.cyr` | **implemented** (walking skeleton) | M1 |
| `false` | `src/cmd/false.cyr` | **implemented** (walking skeleton) | M1 |
| `yes` | `src/cmd/yes.cyr` | not started | M1 |
| `sleep` | `src/cmd/sleep.cyr` | not started | M1 |
| `mkdir` | `src/cmd/mkdir.cyr` | not started | M2 |
| `rmdir` | `src/cmd/rmdir.cyr` | not started | M2 |
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

- `tests/kriya.tcyr` — primary suite (scaffold stub)
- `tests/kriya.bcyr` — benchmark stub
- `tests/kriya.fcyr` — fuzz stub

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`, `args`, `assert`

External: none (and none planned for v1.0).

## Consumers

_None yet._ Expected consumers once M1 ships:

- [agnoshi](https://github.com/MacCracken/agnoshi) — shell relies on `$PATH` lookup of `cp`, `mv`, `rm`, etc.
- [zugot](https://github.com/MacCracken/zugot) — package manager builds will install kriya symlinks at recipe time

## In-flight work

- Roadmap M1 (v0.2.0) — walking skeleton landed (dispatcher + `src/lib/exit.cyr` + `true`/`false`). Remaining: `src/lib/{path,errmsg,args}.cyr`, utilities `echo`/`pwd`/`yes`/`sleep`, ADR 0002 (option-parsing), arch notes 001 (errno→message) and 002 (signal handling), benchmark for dispatcher cold-start. See [`roadmap.md`](roadmap.md).

## Next

See [`roadmap.md`](roadmap.md).
