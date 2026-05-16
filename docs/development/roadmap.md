# kriya — Roadmap

> Milestone plan through v1.0. State lives in [`state.md`](state.md);
> this file is the sequencing — what ships, in what order, against
> what dependency gates.

## v1.0 criteria

- [ ] Core utility set across M1–M6 ships, each with happy + error-path tests + at least one fuzz harness for parser-style utilities (`grep`, `find`, `printf`)
- [ ] POSIX compliance documented per utility (deviations get ADRs)
- [ ] Each destructive utility (`rm`, `mv`, `cp -f`) covered by a TOCTOU + symlink-safety test
- [ ] Dispatcher overhead measured (one-call cold start) and held under **2 ms** on Cyrius-current hardware
- [ ] At least one downstream consumer green (agnoshi `$PATH` lookup → kriya symlinks)
- [ ] CHANGELOG complete from v0.1.0 onward
- [ ] Security audit pass (`docs/audit/YYYY-MM-DD-audit.md`) — path traversal, TOCTOU, signal handling, symlink follow policy
- [ ] Benchmarks captured in `docs/benchmarks.md`

## Milestones

### M0 — Scaffold (v0.1.0) — ✅ shipped 2026-05-15

- `cyrius init kriya` scaffold landed
- Doc-tree per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)
- ADR / architecture / guides / examples folders ready
- Sovereign-replacement boundaries documented in CLAUDE.md (owl, cyim, sit, chakshu, agnoshi cover their respective domains; kriya fills the gaps)

### M1 — Dispatcher + simplest utilities (v0.2.0)

The dispatcher pattern lands, plus the simplest possible utilities to prove it end-to-end.

- [ ] **ADR 0001**: BusyBox-style dispatcher vs N independent binaries — capture the size / cold-start / sym-link / `argv[0]` tradeoffs
- [ ] **ADR 0002**: option-parsing approach — POSIX-only, GNU long-opts, or both (recommendation: both, with explicit per-utility manual reference)
- [ ] **Architecture note 001**: errno → message mapping policy
- [ ] **Architecture note 002**: signal handling model (utilities responding to SIGINT mid-operation)
- [ ] `src/lib/path.cyr` — path normalization, traversal-safe join, `path_is_under(root, p)` for safety checks
- [ ] `src/lib/exit.cyr` — exit-code constants per POSIX
- [ ] `src/lib/errmsg.cyr` — errno → human message table
- [ ] `src/lib/args.cyr` — POSIX option-parser supporting `-x`, `-xyz` cluster, `--long-form`, `--` terminator
- [ ] `src/main.cyr` — dispatch: read `argv[0]` (basename), look up in utility table, dispatch to `cmd_{util}`
- [ ] `src/cmd/echo.cyr` — POSIX echo (`-n`, `-e` per BSD/GNU divergence; ADR if controversial)
- [ ] `src/cmd/pwd.cyr` — `getcwd` syscall
- [ ] `src/cmd/true.cyr`, `src/cmd/false.cyr`, `src/cmd/yes.cyr`, `src/cmd/sleep.cyr` — trivial; included to exercise the dispatcher
- [ ] Tests: one happy + one error path per utility
- [ ] Benchmark: dispatcher cold-start time, captured in CSV history

**Acceptance**: `kriya echo hello` prints `hello\n`; `ln -s build/kriya /tmp/echo && /tmp/echo hello` also prints `hello\n`.

### M2 — File operations (v0.3.0)

The dangerous ones — careful.

- [ ] **ADR 0003**: symlink-follow policy default — `cp`/`mv`/`rm` default behavior on encountering symlinks (recommendation: do NOT follow symlinks on destructive operations; `-L` opts in)
- [ ] **ADR 0004**: `rm -rf /` and `--no-preserve-root` semantics
- [ ] `src/cmd/mkdir.cyr` — recursive `-p`, `mode` setting
- [ ] `src/cmd/rmdir.cyr` — empty-dir-only, `-p` for parents
- [ ] `src/cmd/touch.cyr` — create or update atime/mtime
- [ ] `src/cmd/cp.cyr` — single file, `-r` recursive, `-i` interactive, `-f` force; uses `*at()` syscalls for TOCTOU safety
- [ ] `src/cmd/mv.cyr` — rename within FS, copy+unlink across FS; same flag set as cp; TOCTOU-safe
- [ ] `src/cmd/rm.cyr` — single file, `-r` recursive, `-f` force, `-i` interactive, `--no-preserve-root` required to operate on `/`
- [ ] `src/cmd/ln.cyr` — hard + symbolic via `-s`
- [ ] Fuzz: `tests/kriya.fcyr` gains a destructive-op fuzz target (run in a hermetic temp dir)
- [ ] Tests per utility: happy path + at least one error path (nonexistent source, permission denied, target exists without `-f`) + at least one symlink-edge path

**Acceptance**: bash-script-style file operations (`cp foo bar; rm foo; mkdir baz; ...`) all behave POSIX-compliantly.

### M3 — Listing + path manipulation (v0.4.0)

- [ ] `src/cmd/ls.cyr` — non-color minimal first; `-l` long form; `-a` hidden files; `-h` human sizes
- [ ] `src/cmd/stat.cyr` — file metadata dump, formatted
- [ ] `src/cmd/basename.cyr` + `dirname.cyr` — text-only path manipulation (no FS access)
- [ ] `src/cmd/realpath.cyr` + `readlink.cyr` — resolve symlinks, absolute paths
- [ ] `src/cmd/which.cyr` — search `$PATH` for executables

### M4 — Text-stream utilities (v0.5.0)

- [ ] `src/cmd/wc.cyr` — line / word / byte / char counts
- [ ] `src/cmd/head.cyr` + `tail.cyr` — first/last N lines; `tail -f` follow mode
- [ ] `src/cmd/cut.cyr` — column extraction by char range / field
- [ ] `src/cmd/tr.cyr` — character translation (no regex)
- [ ] `src/cmd/tee.cyr` — split stdin to N files + stdout
- [ ] `src/cmd/sort.cyr` — line sort; `-n` numeric; `-r` reverse; `-u` unique; external sort for files > heap budget
- [ ] `src/cmd/uniq.cyr` — adjacent-line dedup
- [ ] `src/cmd/nl.cyr` — line numbering
- [ ] `src/cmd/printf.cyr` — printf-style formatter (subset of POSIX, ADR for divergences)

### M5 — Filtering / search (v0.6.0)

The larger utilities. Each gets per-utility roadmap evaluation — if any outgrows kriya, extract it.

- [ ] **ADR 0005**: regex engine choice — use Cyrius stdlib `lib/niyama.cyr` (folded v5.9.0) per first-party "own the stack" guidance
- [ ] `src/cmd/grep.cyr` — basic regex; `-i`, `-v`, `-c`, `-l`, `-r`, `-E` extended regex; uses niyama
- [ ] `src/cmd/find.cyr` — tree walk, `-name` glob, `-type`, `-mtime`, `-exec` (via `exec_vec()`)
- [ ] `src/cmd/xargs.cyr` — stdin → argv, `-n`, `-I`, `-P` (parallel — defer or include based on complexity)

**LOC review at end of M5**: any utility ≥ 400 LOC gets evaluated for extraction.

### M6 — System info + misc (v0.7.0)

- [ ] `src/cmd/df.cyr` — filesystem usage via `statvfs`
- [ ] `src/cmd/du.cyr` — directory-tree size, `-h` human, `-s` summary
- [ ] `src/cmd/date.cyr` — time print with strftime-like format
- [ ] `src/cmd/env.cyr` — env var print / unset / set-on-exec
- [ ] `src/cmd/seq.cyr` — integer / float sequence generation

### M7 — POSIX-compliance audit (v0.8.0)

- [ ] Per-utility POSIX conformance review against the POSIX manual
- [ ] Capture all deviations in ADRs
- [ ] Build a `tests/kriya-posix.tcyr` suite running POSIX-blessed test cases per utility

### M8 — Security audit + benchmarks (v0.9.0)

- [ ] Full security audit: path traversal, TOCTOU, signal handling, symlink follow, every destructive op
- [ ] Benchmarks finalized — dispatcher cold start, per-utility throughput
- [ ] CHANGELOG complete

### M9 — v1.0 freeze

- [ ] All v1.0 criteria above check off
- [ ] Tag `1.0.0`

## Out of scope (for v1.0)

- **Anything covered elsewhere** — `cat` (owl), `vim` (cyim), `git` (sit), `htop` (chakshu), shell builtins (agnoshi)
- **Archive utilities** (`tar`, `gzip`, `unzip`) — when sankoch extracts a sovereign archive CLI, that's where they go
- **Network utilities** (`ping`, `curl`, `ssh`, `nc`, `wget`) — separate domain repos
- **GPU / display / window management** — wrong layer
- **Compiler tooling** (`make`, `awk`, `sed`) — `awk` and `sed` are big enough to deserve their own repos; `make` is a build system, separate concern entirely
- **Per-utility binaries (no dispatcher)** — explicit choice via ADR 0001; revisit only if dispatcher overhead exceeds budget
- **Windows / non-Linux platforms** — AGNOS-targeted

## Splitting policy

If any single utility crosses **~400 LOC** or develops a non-trivial dep surface, propose extraction into its own repo (e.g. `kriya-find`, or a domain-named repo). The MVP scope stays small; growth signals a new sovereign tool, not bloat to absorb.
