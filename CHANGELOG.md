# Changelog

All notable changes to kriya will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.2.0] — 2026-05-17

Closes M1 — dispatcher + six simplest utilities + four shared lib modules + two architecture notes + cold-start benchmark. Dispatcher cold-start median **1.185ms** (target ≤2ms per v1.0 acceptance in `roadmap.md`).

### Added

#### Dispatcher and shared lib

- **Dispatcher** (`src/main.cyr`) — BusyBox-style: reads `argv[0]`, basename-strips via `path_basename_ptr`, routes to `cmd_*`. Both symlink form (`./true`) and explicit form (`kriya true`) dispatch identically. Unknown utilities and missing utility names emit `kriya: unknown utility: <name>\n` to stderr and exit `2`. Implements ADR 0001.
- **`src/lib/exit.cyr`** — `EXIT_SUCCESS=0` / `EXIT_FAILURE=1` / `EXIT_USAGE=2` as an enum (no `gvar_toks` cost per CLAUDE.md Cyrius Conventions).
- **`src/lib/args.cyr`** — kriya-side argv wrapper. `kriya_argv_flat()` materializes a flat `cstr*` array from stdlib `argv(n)` (one heap alloc per process, cached). `kriya_args_parse(spec, start)` wraps stdlib `flags_parse` with the dispatcher's `start` offset. `kriya_parse_nonneg_int(s)` parses non-negative base-10 integers and reports errors via `-1` (used by `sleep`).
- **`src/lib/path.cyr`** — pure-string path primitives (no filesystem syscalls). `path_basename_ptr` (zero-alloc, pointer-into-source for the canonical trailing-slash-free case), `path_dirname`, `path_is_absolute`, `path_normalize` (collapses `.`/`..`/duplicate slashes, with root absorbing leading `..` for absolute paths), `path_join` (right operand wins when absolute), `path_is_under` (sandbox check used by M2 destructive utilities).
- **`src/lib/errmsg.cyr`** — Linux errno → message table for errnos 1..40 (the POSIX core, ABI-stable across libc-free callers). `errmsg_for(errno)` returns a static cstring; `errmsg_is_known(errno)` distinguishes named from numeric fallback. Unknown errnos do NOT fall back to a wildcard message — see arch note 001.

#### Utilities (six of six M1)

- **`true`** (`src/cmd/true.cyr`) — POSIX `true(1)`, always exits `0`.
- **`false`** (`src/cmd/false.cyr`) — POSIX `false(1)`, always exits `1`.
- **`echo`** (`src/cmd/echo.cyr`) — POSIX `echo(1)` with leading-`-n` recognition per GNU/BSD/bash convention. Only the literal token `-n` is a flag; `-nn`, `-en`, `--` are data. `-e`/`-E` (escape interpretation) deferred until the `lib/str.cyr` escape table lands.
- **`pwd`** (`src/cmd/pwd.cyr`) — POSIX `pwd(1)` with `-L`/`--logical` (default; trusts an absolute `$PWD`) and `-P`/`--physical` (always `getcwd`). The strict POSIX inode-equality check on `$PWD` deferred until `fs.cyr` exposes a stat-compare helper.
- **`yes`** (`src/cmd/yes.cyr`) — POSIX `yes(1)`. No flags. Repeats `y\n` by default, or argv operands joined by spaces, until the write fails (broken pipe). 8 KiB line cap.
- **`sleep`** (`src/cmd/sleep.cyr`) — POSIX `sleep(1)` with a single non-negative integer-seconds operand. GNU fractional seconds and suffixes (`1.5`, `1s`, `1m`, `1h`) deferred until the duration-parser lands in `lib/chrono.cyr`.

#### Decisions and policy

- **ADR 0001** — BusyBox-style dispatcher vs N independent binaries. Accepted.
- **ADR 0002** — Option parsing for humans and agents. One parser, POSIX-short + GNU-long, hard No-Gos on prefix matching, optional values, interactive prompts on non-tty stdin, and silent option deprecation. `--help` (human) and `--help=json` (machine schema, locked behind `KRIYA_HELP_SCHEMA_VERSION`) for capability discovery; `kriya --list` enumerates utilities as JSON. Implementation status section names the deferred-to-stdlib follow-ups (short clustering `-rfv`, attached short values `-n10`).
- **Architecture note 001** — errno → message policy. Pins the framing `kriya <util>: <message>: <operand>\n` on stderr; mandates one-source-of-truth in `errmsg.cyr`; explicit `errno NNN` fallback for unmapped codes (no wildcard message).
- **Architecture note 002** — Signal handling model. Documents the M1 "rely on kernel defaults" stance (SIGPIPE → 141, SIGINT → 130, SIGTERM → 143) and names the M2/M3/M4/M5 triggers for installing flag-based handlers. Hard No-Gos: no utility ignores SIGPIPE; no utility catches SIGSEGV/SIGBUS/SIGFPE; no handler runs before `args_init()`; no handler sleeps.

#### Tests, benchmarks, build tooling

- **`tests/kriya.tcyr`** — 61/61 unit assertions across exit codes, `cmd_true`/`cmd_false`, `path_basename_ptr`, `path_is_absolute`, `path_dirname`, `path_normalize`, `path_join`, `path_is_under`, `errmsg_for`, `errmsg_is_known`, `kriya_parse_nonneg_int`.
- **`tests/kriya.bcyr`** — in-process hot-path benchmarks via stdlib `lib/bench.cyr`. Steady-state (Cyrius 5.11.54, x86_64): `path_basename_ptr` 62ns, `streq` hit/miss 33ns/29ns, `cmd_true`/`cmd_false` 5-6ns, `path_normalize` simple/messy 322ns/498ns, `errmsg_for` 6ns.
- **`scripts/bench-coldstart.sh`** — process-spawn timing for `./build/kriya true`. `RUNS=30` baseline: min 1.010ms, **median 1.185ms**, max 1.374ms.
- **`scripts/version-bump.sh`** — single entry point for bumping versions. Writes `VERSION`, regenerates `src/version_str.cyr` with the computed byte length, and updates the `## Version` line in `docs/development/state.md`. Refuses non-semver inputs.

#### Build

- **`cyrius.cyml [package].version = "${file:VERSION}"`** — single source of truth for version. `src/version_str.cyr` (AUTO-GENERATED) holds `_VERSION_STR_KRIYA` (banner with `\n`), `_VERSION_LEN_KRIYA` (precomputed byte length), `_VERSION_KRIYA` (bare semver). Consumers reference these vars rather than baking the literal in. Pattern mirrors `agnos`, `vidya`, `cyim`, `chakshu`, cyrius itself.
- **`cyrius.cyml [deps].stdlib`** — `args`, `flags`, `chrono`, `fnptr`, `bench` added alongside the M0 baseline (`string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`, `assert`).

## [0.1.0] — 2026-05-15

### Added

- Initial `cyrius init kriya` scaffold — `VERSION`, `cyrius.cyml`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`, `src/{main,test}.cyr`, `tests/kriya.{tcyr,bcyr,fcyr}`, `docs/{adr,architecture,guides,examples,development}/` per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md).
- Cyrius toolchain pin `5.11.54` in `cyrius.cyml [package].cyrius`.
- README, CLAUDE.md, `docs/development/{state,roadmap}.md`, `docs/guides/getting-started.md` filled with project-specific content per [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md). Sovereign-replacement boundaries documented (owl owns `cat`, cyim owns `vim`, sit owns `git`, chakshu owns `htop`, agnoshi owns shell builtins; kriya fills the gaps).
- Per-utility status table in `docs/development/state.md` covering ~40 planned utilities across M1–M6.

### Identity

`kriya` (Sanskrit: क्रिया — *action, operation, verb*) — coreutils-equivalent for AGNOS. One repo, many small static utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep` …) sharing infrastructure. BusyBox-style dispatcher + symlinks per utility. Each kriya is one verb the user invokes.
