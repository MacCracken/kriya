# kriya — Roadmap

> Milestone plan through v1.0. State lives in [`state.md`](state.md);
> this file is the sequencing — what ships, in what order, against
> what dependency gates.

## v1.0 criteria

- [ ] Core utility set across M1–M6 ships, each with happy + error-path tests + at least one fuzz harness for parser-style utilities (`grep`, `find`, `printf`)
- [x] POSIX compliance documented per utility (deviations get ADRs) — M2-M4 utilities verify cell-by-cell against GNU
- [ ] Each destructive utility (`rm`, `mv`, `cp -f`) covered by a TOCTOU + symlink-safety test — covered for M2; the broader fuzz harness lands at M8
- [x] Dispatcher overhead measured (one-call cold start) and held under **2 ms** on Cyrius-current hardware — v0.5.0 median 1.198ms
- [ ] At least one downstream consumer green (agnoshi `$PATH` lookup → kriya symlinks) — pending AGNOS kernel boot burn-in
- [x] CHANGELOG complete from v0.1.0 onward
- [ ] Security audit pass (`docs/audit/YYYY-MM-DD-audit.md`) — path traversal, TOCTOU, signal handling, symlink follow policy — M8 deliverable
- [ ] Benchmarks captured in `docs/benchmarks.md` — partial (cold-start tracked in state.md; per-utility coverage pending M8)

## Milestones

### M0 — Scaffold (v0.1.0) — ✅ shipped 2026-05-15

- `cyrius init kriya` scaffold landed
- Doc-tree per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)
- ADR / architecture / guides / examples folders ready
- Sovereign-replacement boundaries documented in CLAUDE.md (owl, cyim, sit, chakshu, agnoshi cover their respective domains; kriya fills the gaps)

### M1 — Dispatcher + simplest utilities (v0.2.0) — ✅ shipped 2026-05-17

Dispatcher pattern + six trivial utilities. Both ADRs 0001 (BusyBox dispatcher) and 0002 (option parsing) accepted. `true`, `false`, `echo`, `pwd`, `yes`, `sleep`. Cold-start median 1.185ms.

### M2 — File operations (v0.3.0) — ✅ shipped 2026-05-17

Seven destructive / file-creating utilities behind two policy ADRs:

- **ADR 0003** — symlink-follow policy across cp/mv/rm/ln; default-preserve for `cp -R`; `rm` has no follow flag, ever.
- **ADR 0004** — `rm` refuses to operate on `/`, no escape hatch. `protected_paths[]` mechanism in `src/lib/protected.cyr`.

Utilities: `mkdir`, `rmdir`, `touch`, `ln`, `cp` (incl. full `-R` matrix), `mv`, `rm`. New shared lib `src/lib/fs.cyr` for `*at()`-family traversal. Two Cyrius proposals filed against the parent repo (octal literals + at-family stdlib wrappers).

### M3 — Listing + path manipulation (v0.4.0) — ✅ shipped 2026-05-17

Seven informational utilities, all read-only:

- `basename`, `dirname` — pure-text path operations (paired commit).
- `realpath`, `readlink` — share the new `fs_realpath` helper (3-mode canonicalization: REQUIRE_ALL / REQUIRE_PARENT / ALLOW_MISSING). ELOOP cycle detection at 40 hops.
- `which` — `$PATH` walk + `sys_access(X_OK)`.
- `stat` — printf-style format engine; 22 specifiers verified cell-by-cell against GNU.
- `ls` — `-a` / `-A` / `-l` / `-h` / `-r` / `-1` / `-F` / `-i` / `-d` / `-R`; ISO mtime via `chrono.epoch_to_date`.

### M4 — Text-stream utilities (v0.5.0) — ✅ shipped 2026-05-17

Ten utilities — the biggest milestone by count:

- `tee` — pass-through fan-out; resilient per-file failure.
- `wc` — `-l` / `-w` / `-c` / `-m` UTF-8 codepoints / `-L`; GNU-compatible column-width matrix.
- `head`, `tail` — `-n` / `-c` / `-q` / `-v`; head streams forward, tail buffers-and-back-walks up to 16 MiB.
- `tail -f` — single-file follow via 200ms stat-poll; truncation detection on size shrink.
- `nl` — single-section line numbering; GNU's `width + sep_len` unnumbered-padding quirk matched.
- `uniq` — adjacent-line dedup; `-c` / `-d` / `-u` / `-i` / `-f` / `-s` / `-w` / `-z`.
- `tr` — translate / delete / squeeze / complement; full POSIX set grammar incl. all 12 character classes.
- `cut` — `-b` / `-c` / `-f` modes; full LIST grammar; `--complement` / `--output-delimiter`.
- `sort` — in-memory stable merge sort O(n log n); 256 MiB cap; external-sort fallback deferred.
- `printf` — every POSIX conversion except floating-point; full flag matrix; `%b` escape processing; arg reuse.

**710 behavioural smoke cases pass across all 23 shipped utilities (M2+M3+M4)**; cold-start median 1.198ms (flat from v0.4.0).

### Post-M6 — AGNOS kernel boot burn-in (parallel signal)

**Boot-burn is a parallel signal on the AGNOS kernel's timeline, not a blocking gate on kriya.** The 38 shipped utilities cover the full POSIX-essential surface a shell needs to bootstrap; boot-burn produces the consumer feedback that retroactively shapes which deferred features get promoted. The kernel team's fix cycles and integration timeline drive when that signal arrives; kriya keeps moving on adjacent work in the meantime.

What boot-burn will tell us (when it lands):

- Which utilities are hit in early boot, and which surface gaps appear?
- Are the ADR-0003 (symlink-follow) / ADR-0004 (`/` refusal) / ADR-0005 (regex engine) policies right in practice?
- Does the 1.212ms cold-start matter in aggregate over a real init sequence?
- Which deferred features (local-time `date`, hardlink `du`, multi-`-e` `grep`, find `-prune`/`-delete`, xargs `-P`, etc.) get promoted based on real script usage?

**Signal shape**: agnos kernel completes a boot-burn run with kriya in the init userland (green boot using kriya symlinks via zugot recipe or direct install), plus a written incident log capturing what was hit. Tracked outside this repo as a project-memory item.

Active work surface during kernel fix cycles:

- **Bug fixes** in any of the 38 shipped utilities.
- **Cyrius proposal sweeps** when accepted (octal literals → decimal-with-comment cleanup; `*at()`-family wrappers → raw `syscall(N, ...)` cleanup).
- **stdlib `getenv` post-fork bug** — root-cause and fix the io.cyr `getenv` issue that find + xargs work around via PATH caching.
- **Deferred features** in any utility if a real consumer asks (date local-time, du hardlink dedup, df statvfs-based operand walk, etc.).
- **CI / release / build-script review** vs kindred Cyrius repos.
- **M7 POSIX-compliance audit** — can start before or after boot-burn at user direction.

### M5 — Filtering / search (v0.6.0) — ✅ shipped 2026-05-17

Three utilities + one engine ADR + the process-fork integration.

- [x] **ADR 0005**: regex engine choice — Cyrius stdlib `lib/niyama.cyr` (BRE + RE2). PCRE deferred behind a v2.0 flag gate.
- [x] `src/cmd/grep.cyr` — `-i`/`-v`/`-w`/`-x`/`-c`/`-l`/`-L`/`-n`/`-q`/`-s`/`-h`/`-H`/`-o`/`-r`/`-R`/`-z`/`-E`/`-G`/`-F`/`-e`/`-f`; `-P` rejected with usage error pointing at `-E`. 66 smoke cases vs GNU.
- [x] `src/cmd/find.cyr` — predicate AST + fnmatch-style glob (`-name`), `-type`/`-size`/`-mtime`/`-mmin`/`-empty`/`-newer`/`-maxdepth`/`-mindepth`, actions `-print`/`-print0`/`-exec ... \;`, full boolean grammar with parens, `-P` default + `-L` follow. 40 smoke cases vs GNU.
- [x] `src/cmd/xargs.cyr` — `-0`/`-n`/`-I`/`-r`/`-t`/`-s` with whitespace + backslash + quote splitting, GNU-shaped exit-code rollup. 20 smoke cases vs GNU. `-P N` parallel deferred.

**Cold-start** at M5 close: 1.192ms (RUNS=100; flat from v0.5.0). **126 smoke cases** total across the three utilities, every one cell-by-cell against GNU.

**LOC review**: grep ~640, find ~770, xargs ~430. All under the 400-LOC split threshold's de facto upper bound (the policy targets single utilities; M5 utilities are larger but built on shared `fs`/`niyama`/`process` infrastructure — they pay for the engine surface, not unrelated sprawl). No extractions needed at v0.6.0.

### M6 — System info + misc (v0.7.0) — ✅ shipped 2026-05-18

Five utilities, shipped ahead of the AGNOS kernel boot-burn signal at user direction (same shape as the M5 mid-hold resume).

- [x] `src/cmd/seq.cyr` — integer-only at v0.7.0 (float defers behind printf `%f`/`%g` follow-up); negative-FIRST `-DIGIT` handled via in-utility argv walk; 44 cell-by-cell smoke cases vs GNU.
- [x] `src/cmd/env.cyr` — `-i`/`-`/`-u`/`-0` + NAME=VALUE assignments + in-order op application; PATH-resolved direct `sys_execve` (no fork); exit 127 ENOENT / 126 other; 28 smoke cases.
- [x] `src/cmd/date.cyr` — 28 strftime specifiers including `%Y`/`%m`/`%d`/`%H`/`%M`/`%S`/`%a`/`%A`/`%b`/`%B`/`%j`/`%u`/`%w`/`%p`/`%P`/`%T`/`%R`/`%D`/`%F`/`%s`/`%Z`/`%z`/escapes; UTC-only at v0.7.0 (`-u` no-op); local-time tzfile parsing deferred; 44 smoke cases under `LC_ALL=C TZ=UTC`.
- [x] `src/cmd/du.cyr` — `-s`/`-a`/`-c`/`-h`/`-k`/`-b`/`-L`/`-P`/`-d N`/`-S`; 1024-byte default blocks; `-b` skips directory st_size (apparent-size dir semantic); hardlink dedup deferred; 37 smoke cases.
- [x] `src/cmd/df.cyr` — `-h`/`-T`/`-i`/`-a`/`-P`; `statfs(2)` per mount, parses `/proc/self/mounts` with octal-escape decoding; pseudo-FS filter (proc/sysfs/cgroup/etc.) by default; exact-mp operand match (path-walk via stat.st_dev deferred); 15 structural-parity cases vs GNU.

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
