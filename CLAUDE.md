# kriya — Claude Code Instructions

> **Core rule**: this file is **preferences, process, and procedures** —
> durable rules that change rarely. Volatile state (current version,
> per-utility status, dispatcher size, test counts, consumers) lives
> in [`docs/development/state.md`](docs/development/state.md).
> Do not inline state here.

## Project Identity

**kriya** (Sanskrit: क्रिया — *action, operation, verb*) — coreutils-equivalent for AGNOS. One repo, many small static utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep`, …) sharing infrastructure. Each utility is one verb the user invokes.

- **Type**: Multi-binary (single `kriya` dispatcher binary + symlinks per utility — BusyBox pattern)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius`)
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)
- **Shared crates**: [shared-crates.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)

## Goal

Own the *small POSIX-style command-line utilities* surface for AGNOS — the `cp` / `mv` / `rm` / `mkdir` / `echo` / `wc` / `find` etc. that the rest of an OS expects to be present, in one repo, with one shared library of primitives (path, errno-message, argument-parsing), one CHANGELOG, one toolchain pin. Each utility is small (~50–400 LOC); they share infrastructure; they ship together.

## Scope boundaries (what is NOT kriya)

These have sovereign first-party homes elsewhere. Do not duplicate:

| Domain | First-party home |
|---|---|
| File content viewing (`cat`) | [owl](https://github.com/MacCracken/owl) — *cat with line numbers, syntax highlighting, pipe-friendly mode* |
| Text editing (`vim`/`nano`) | [cyim](https://github.com/MacCracken/cyim) |
| Version control (`git`) | [sit](https://github.com/MacCracken/sit) |
| Process monitoring (`htop`/`top`) | [chakshu](https://github.com/MacCracken/chakshu) |
| Shell state (`cd`, `pwd`, `alias`, `export`, `jobs`, `fg`, `bg`, `history`) | [agnoshi](https://github.com/MacCracken/agnoshi) builtins |
| Archive (`tar`, `gzip`) | covered by [sankoch](https://github.com/MacCracken/sankoch)-derived tooling (LZ4/DEFLATE/zlib/gzip) — when extracted; until then, NOT kriya scope |
| Networking (`ping`, `curl`, `ssh`, `nc`) | separate domain repos; NOT kriya scope |
| GPU / display / window management | NOT kriya scope |

**If a proposal expands kriya into one of these areas, push back: the right answer is "extract a focused repo," not "swell the multi-tool."**

## Current State

> Volatile state lives in [`docs/development/state.md`](docs/development/state.md) —
> current version, per-utility implementation status, dispatcher size,
> total binary footprint, in-flight utilities, consumers. Refreshed
> every release.

This file (`CLAUDE.md`) is durable rules.

## Scaffolding

Project was scaffolded with `cyrius init kriya`. **Do not manually create project structure** — use the tools. If a tool is missing something, fix the tool.

## Quick Start

```sh
cyrius deps                                    # resolve stdlib deps
cyrius build src/main.cyr build/kriya          # compile dispatcher
cyrius test                                    # run [build].test + tests/*.tcyr
cyrius bench tests/kriya.bcyr                  # benchmarks (per-utility)
```

After build, create symlinks at install time:

```sh
ln -s kriya cp; ln -s kriya mv; ln -s kriya rm; ...
```

Each symlink is a separate command; the dispatcher reads `argv[0]` to determine which utility to run.

## Key Principles

- **Correctness over cleverness** — a wrong `rm` is a catastrophe; correctness is non-negotiable
- **POSIX behavior as floor, sovereign-design as ceiling** — match POSIX semantics where users rely on them (default flags, exit codes, stream behavior); diverge only with an ADR
- **Each utility is one verb** — pure operation, predictable args, well-defined exit codes
- **Shared lib first, per-utility code second** — path handling, errno-to-message, argument parsing live in `src/lib/`. New utilities consume these, don't reinvent them
- **One binary, many symlinks** — the BusyBox pattern. Saves on startup overhead, shared text segment, single security-audit surface
- **Static, zero-dep** — no dynamic linking, no external deps beyond Cyrius stdlib
- **Streaming, not buffering** — utilities that read stdin process it as a stream; don't load whole files into memory unless the semantic demands it (e.g. `sort`)
- Test after every change, not after the feature is "done"
- ONE utility at a time — do not bundle unrelated utility additions

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API if needed
- Do not skip tests before claiming changes work
- **No `sys_system()`** — `kriya` utilities never shell out via `system()`. Use `exec_vec()` with explicit argv where exec is required (e.g. `xargs`, `find -exec`)
- Do not trust external data — every file path from argv is validated, no `../` escape on bounded operations
- Do not use `break` in while loops with `var` declarations — use flag + `continue`
- **Match POSIX exit codes** — `0` success, `1` general failure, `2` usage error, plus utility-specific codes per the POSIX manual page; capture deviations in an ADR
- **No silent file overwrites without `-f`** — `cp`, `mv` prompt or error by default; `-f` overrides
- **`rm` is the most dangerous utility** — extra care: no recursive operation without `-r`, no force without `-f`, refuses to operate on `/` without `--no-preserve-root` even with `-rf`
- Do not hardcode toolchain version in CI YAML — `cyrius = "X.Y.Z"` in `cyrius.cyml` is the source of truth
- **If a utility grows past ~400 LOC**, propose splitting it out as its own repo. Don't let one utility dominate the multi-tool

## Process

### Adding a new utility (the standard work loop)

1. **Roadmap check** — utility is on the roadmap or has an ADR justifying inclusion
2. **POSIX research** — read the POSIX manual page for the utility being implemented. Capture deviations.
3. **Scaffold** — `src/cmd/{util}.cyr` with `fn cmd_{util}(argc, argv) -> i32`
4. **Wire** — add dispatch entry in `src/main.cyr`'s utility table
5. **Tests** — `tests/kriya.tcyr` gains: happy path + at least one error path + one POSIX-compliance check per option
6. **Benchmark** — `tests/kriya.bcyr` gains a perf test for the utility's typical workload
7. **Build + check** — `cyrius build`, `cyrius test`, `cyrius lint`, `cyrius vet`
8. **Documentation** — `CHANGELOG.md` `[Unreleased] / Added`, `docs/development/state.md` per-utility status table
9. **ADR if non-trivial** — option-set decisions, behavior deviations from POSIX, performance trade-offs
10. **Version sync** — `VERSION`, `cyrius.cyml`, CHANGELOG

### Task Sizing

- **Low**: one simple utility (`echo`, `pwd`, `yes`, `true`, `sleep`) — ship in one work loop pass
- **Medium**: file-touching utility (`cp`, `mv`, `mkdir`, `touch`) — separate work loop, careful test coverage
- **Large**: filtering / search utility (`grep`, `find`, `sort`, `xargs`) — multi-session, regex/glob engine, performance characterization

## Cyrius Conventions

- All struct fields are 8 bytes (`i64`), accessed via `load64` / `store64` with offset
- Heap allocation via `fl_alloc()` / `fl_free()` for data with individual lifetimes
- Bump allocation via `alloc()` for long-lived data
- Enum values for constants — don't consume `gvar_toks` slots (4,096 initialized globals limit)
- Counting rule: only a top-level `var NAME = <non-literal>;` (call / identifier / expression initializer) consumes an initialized-globals slot; a bare integer-literal init (`var x = 42;`) takes the static-init fast path and enum members are const-folded, so neither counts. See the cyrius guide's **Global Initializers** section (`docs/guides/cyrius-guide.md` in the cyrius repo)
- `break` in while loops with `var` declarations is unreliable — use flag + `continue`
- No negative literals — write `(0 - N)` not `-N`
- No mixed `&&` / `||` in one expression — nest `if` blocks instead

## Security Hardening (every release)

Standard first-party checklist (see [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md#security-hardening-required-before-every-release)) with kriya-specific emphasis:

- **Path traversal** — every file path from argv passes `path_normalize()` + bounded checks. `rm -rf /` is the canonical example of what NOT to be possible by accident
- **TOCTOU** — `cp`, `mv`, `rm` paths use `*at()` syscall variants where available to avoid time-of-check-to-time-of-use races
- **Buffer safety** — every `var buf[N]` verified: N is BYTES, max access < N
- **Signal handling** — long-running utilities (`find`, `xargs`) handle SIGINT cleanly (don't leave half-modified state)
- **Symlink awareness** — by default, kriya utilities do NOT follow symlinks on destructive operations (`rm`, `mv` of directories); `-L` opts in

## Documentation

- [`docs/adr/`](docs/adr/) — architecture decision records (BusyBox dispatcher choice, POSIX-vs-GNU option-set decisions, per-utility deviations)
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints (errno mapping, signal model, streaming-vs-buffering policy)
- [`docs/guides/`](docs/guides/) — task-oriented how-tos (adding a new utility, running benchmarks)
- [`docs/examples/`](docs/examples/) — runnable examples
- [`docs/development/state.md`](docs/development/state.md) — **live state snapshot**, refreshed every release; includes per-utility status table
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — milestone plan with per-utility ship order
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes

New quirks and constraints land in `docs/architecture/` as numbered items (`NNN-kebab-case.md`). New decisions land in `docs/adr/` using [`template.md`](docs/adr/template.md). **Never renumber either series.**

Full doc-tree convention: [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md).

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). New utilities go under `Added` with a one-line description + the POSIX manual reference. Performance claims **must** include benchmark numbers. Breaking changes (exit-code, option semantics, default behavior) get a **Breaking** section with migration guide.
