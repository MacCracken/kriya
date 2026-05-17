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

### Post-M4 hold — AGNOS kernel boot burn-in

**M5+ work is paused until kriya gets exercised in a real AGNOS kernel boot**. The 30 shipped utilities cover the POSIX-essential surface a shell needs to bootstrap; the next signal of value is whether they actually hold up when an OS uses them in anger. The boot-burn produces the consumer feedback that should shape M5's priorities:

- Which utilities are hit in early boot, and which surface gaps appear?
- Are the ADR-0003 (symlink-follow) / ADR-0004 (`/` refusal) policies right in practice, or do real boot scripts work against them?
- Does the 1.198ms cold-start matter in aggregate over a real init sequence, or is it dominated by other costs?
- Which deferred features get promoted to "next" based on real script usage?

**Trigger to resume**: agnos kernel completes a boot-burn run with kriya in the init userland. The trigger is concrete: a green AGNOS boot using kriya symlinks for `cp`/`mv`/`rm`/`mkdir`/etc., either by zugot recipe or direct install, and a written incident log (even if empty) capturing what was hit. The trigger lives outside this repo (it's an AGNOS-side milestone); kriya tracks it as a project-memory item with the boot-burn dashboard / PR link, not a kriya-internal task.

During the hold, kriya is open for:

- **Bug fixes** discovered in the existing 30 utilities.
- **Cross-FS directory `mv`** — the one remaining M2 follow-up, now unblocked since `rm -r`'s tree-walk exists.
- **Cyrius proposal sweeps** when accepted (octal literals → decimal-with-comment cleanup; `*at()`-family wrappers → raw `syscall(N, ...)` cleanup).
- **`printf` floating-point** — `%e` / `%f` / `%g` if a consumer asks before M5 resumes.
- **`tail -f` multi-file follow** — same shape.

NOT M5 work (grep / find / xargs) — that waits for the boot-burn signal.

### M5 — Filtering / search (v0.6.0) — paused pre-start

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
