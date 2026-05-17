# Changelog

All notable changes to kriya will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Dispatcher**: `src/main.cyr` now reads `argv[0]`, basename-strips, and routes to the matching `cmd_*` function. Both symlink form (`./true`) and explicit form (`kriya true`) dispatch identically. Unknown utilities and missing utility names emit a usage message to stderr and exit `2`. Implements ADR 0001.
- **Shared lib**: `src/lib/exit.cyr` defines `EXIT_SUCCESS=0` / `EXIT_FAILURE=1` / `EXIT_USAGE=2` as an enum (no `gvar_toks` cost per CLAUDE.md Cyrius Conventions).
- **`true`** (`src/cmd/true.cyr`) — POSIX `true(1)`, always exits `0`.
- **`false`** (`src/cmd/false.cyr`) — POSIX `false(1)`, always exits `1`.
- **`args` added to `cyrius.cyml [deps].stdlib`** — dispatcher needs `args_init()` / `argc()` / `argv(n)` for argv access.
- **Tests**: `tests/kriya.tcyr` covers exit-code constants and `cmd_true`/`cmd_false` return values (5/5 passing).

## [0.1.0] — 2026-05-15

### Added

- Initial `cyrius init kriya` scaffold — `VERSION`, `cyrius.cyml`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`, `src/{main,test}.cyr`, `tests/kriya.{tcyr,bcyr,fcyr}`, `docs/{adr,architecture,guides,examples,development}/` per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md).
- Cyrius toolchain pin `5.11.54` in `cyrius.cyml [package].cyrius`.
- README, CLAUDE.md, `docs/development/{state,roadmap}.md`, `docs/guides/getting-started.md` filled with project-specific content per [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md). Sovereign-replacement boundaries documented (owl owns `cat`, cyim owns `vim`, sit owns `git`, chakshu owns `htop`, agnoshi owns shell builtins; kriya fills the gaps).
- Per-utility status table in `docs/development/state.md` covering ~40 planned utilities across M1–M6.

### Identity

`kriya` (Sanskrit: क्रिया — *action, operation, verb*) — coreutils-equivalent for AGNOS. One repo, many small static utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep` …) sharing infrastructure. BusyBox-style dispatcher + symlinks per utility. Each kriya is one verb the user invokes.
