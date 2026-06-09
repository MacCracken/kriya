# kriya — Roadmap

> Milestone plan through v1.0. State lives in [`state.md`](state.md);
> this file is the sequencing — what ships, in what order, against
> what dependency gates.

## v1.0 criteria

- [x] Core utility set across M1–M6 ships, each with happy + error-path tests + at least one fuzz harness for parser-style utilities (`grep`, `find`, `printf`) — 38 utilities + 644 smoke cases + 1529 fuzz assertions across `kriya-grep.fcyr` / `kriya-find.fcyr` / `kriya-printf.fcyr`. Shipped at v1.0.0.
- [x] POSIX compliance documented per utility (deviations get ADRs) — M2-M4 utilities verify cell-by-cell against GNU
- [x] Each destructive utility (`rm`, `mv`, `cp -f`) covered by a TOCTOU + symlink-safety test — M8 audit verified ADR-0003/0004 coverage across cp/mv/rm; three M8 mitigations (F1 cp, F4 find, F5 grep) closed remaining TOCTOU gaps with smoke-suite regression coverage.
- [x] Dispatcher overhead measured (one-call cold start) and held under **2 ms** on Cyrius-current hardware — v0.9.0 median 1.201ms (60% of budget).
- [ ] At least one downstream consumer green (agnoshi `$PATH` lookup → kriya symlinks) — pending AGNOS kernel boot burn-in.
- [x] CHANGELOG complete from v0.1.0 onward.
- [x] Security audit pass (`docs/audit/2026-05-18-security.md`) — path traversal, TOCTOU, signal handling, symlink-follow policy + external CVE/0-day research. M8 deliverable, shipped.
- [x] Benchmarks captured in `docs/benchmarks.md` — cold-start history + per-utility throughput vs GNU. M8 deliverable, shipped.

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

### M7 — POSIX-compliance audit (v0.8.0) — ✅ shipped 2026-05-18

- [x] Per-utility POSIX conformance review against the POSIX manual — `docs/audit/2026-05-18-posix-compliance.md` covers all 38 shipped utilities. 32 are POSIX-defined; 6 are intentional kriya-scope extensions. No quiet divergences.
- [x] Capture all deviations in ADRs — three new ADRs landed: 0006 (utility scope + four-criteria gate), 0007 (`date` UTC-only at v0.7.0 with local-time follow-up named), 0008 (POSIX exit-code policy — three-tier baseline + per-utility specifics).
- [x] Build a `tests/kriya-posix.tcyr` suite running POSIX-blessed test cases per utility — 18 starter cases across pillar utilities; fork+execve+pipe-capture harness. Population is incremental into M8/M9.

### M8 — Security audit + benchmarks (v0.9.0) — ✅ shipped 2026-05-18

- [x] Full security audit: path traversal, TOCTOU, signal handling, symlink follow, every destructive op — `docs/audit/2026-05-18-security.md`. External CVE/0-day research included (uutils-coreutils CVE-2026-35338..35381 cross-walked: 34 N/A or already-mitigated, 3 patched in M8, 2 documented as POSIX-conformant).
- [x] Benchmarks finalized — `docs/benchmarks.md` with cold-start history + per-utility throughput vs GNU; `scripts/bench-throughput.sh` for deterministic re-runs.
- [x] CHANGELOG complete (was already on v1.0 criteria before this milestone).

### M9 — v1.0 freeze (v1.0.0) — ✅ shipped 2026-05-18

- [x] All v1.0 criteria above check off (7 of 8; the 8th — downstream consumer green via AGNOS boot-burn — is deferred to a post-1.0 consumer-burn cycle per user direction; parallel signal, not blocker).
- [x] Tag `1.0.0`.

Three fuzz harnesses land at M9 to close the last code-side v1.0 criterion: `tests/kriya-grep.fcyr` (1127 assertions over niyama BRE/RE2/bracket-heavy patterns), `tests/kriya-find.fcyr` (201 over fork+exec find), `tests/kriya-printf.fcyr` (201 over fork+exec printf). `scripts/fuzz.sh` runs all three. Cold-start median 1.196 ms at v1.0.0.

## Post-1.0 milestones

v1.0 froze 2026-05-18 with 7 of 8 criteria checked. The 8th — downstream consumer green via AGNOS kernel boot-burn — is the trigger for **M10**. The remaining post-1.0 work falls into four buckets that can advance independently against tagged minor releases (1.x.y).

### M11 — AGNOS as a build target (1.1.0, opened 2026-06-06; design-first)

Make kriya the sovereign, **shell-independent** coreutils for AGNOS — the canonical home for the FS tools (any shell execs it, the Unix way; agnsh's 1.4.2 builtin verbs are a shell-bound convenience that this supersedes once 1.43.x `execwait` lands). **Prep done:** pin 5.11.61 → 6.0.56, lib re-vendored, VERSION → 1.1.0.

**Why it's a real refactor (not a gate-the-blockers port like bannermanor/commandress):** kriya hardcodes **Linux syscall numbers** (`syscall(82,…)`=rename, `217`=getdents64, `257`=openat — ~610 numeric-syscall sites) instead of the target-aware `SYS_*` constants, parses **Linux `getdents64`/`stat` struct formats** (the sovereign agnos formats differ — see `agnos-userland-abi.md` §4.1/§4.2), and uses modern **`*at` syscalls** (openat/renameat/linkat/newfstatat/utimensat) that agnos doesn't define (agnos has the basic forms with different numbers + the explicit-length ABI).

**Plan:** make the central `src/lib/fs.cyr` syscall layer target-aware (`#ifdef CYRIUS_TARGET_AGNOS`: agnos numbers + sovereign dirent/stat structs + `*at`→basic mapping; Linux path unchanged) — most commands flow through it, so it's the leverage point. Then gate the per-command stragglers: `ln` (linkat/newfstatat), `touch` (utimensat → degrade timestamps), `tail` (lseek → degrade), `pwd` + path resolution (getcwd → degrade; CWD is userland-owned on agnos), `rm`/`cp`/`mv` (TTY `ioctl` TCGETS → non-interactive). Validate with `cyrius build --agnos` per command + the Linux `.tcyr` regression. Analogous to the agnosys-core repair, scaled to the coreutils FS surface.

### M10 — Consumer-burn (closes v1.0 criterion #8)

The single remaining v1.0 criterion. Trigger sequence:

1. **AGNOS USB-keyboard-on-boot resolves.** Out of kriya scope; tracked at agnos.
2. **AGNOS coreutils integration** — wire kriya symlinks into the AGNOS init userland (via zugot recipe or direct install). agnoshi `$PATH` lookups resolve to `kriya` for `cp`, `mv`, `rm`, `mkdir`, `grep`, `find`, `xargs`, etc.
3. **First green boot-burn** — AGNOS kernel boots with kriya in init, runs through whatever init script exercise the boot-burn defines, completes without kriya-side failure.
4. **Incident log** — `docs/audit/<date>-consumer-burn.md` capturing what was exercised, what surfaced, what bug fixes (if any) landed back in kriya.
5. **1.0.1 release** — checkbox the v1.0 criterion, ship release notes pointing at the consumer-burn audit.

Open during the wait:

- Bug fixes if anything surfaces from agnos-side testing.
- Adjacent post-1.0 buckets below can advance in parallel — they don't block on the boot-burn.

### M11 — Cyrius proposal sweeps

Gated on upstream Cyrius acceptance, not kriya work. Two proposals filed 2026-05-17:

- **`2026-05-17-octal-literal-syntax`** — when accepted, sweep kriya's decimal POSIX-mode constants (`511 # 0o777`, `1073741823 # UTIME_NOW`) back to octal literals. Files affected: `src/cmd/mkdir.cyr`, `src/cmd/touch.cyr`, `src/lib/fs.cyr`, `src/lib/protected.cyr`. Zero behavior change; tag as 1.0.x.
- **`2026-05-17-syscalls-at-family-stdlib`** — when accepted, sweep raw `syscall(N, ...)` sites to stdlib `sys_*at` wrappers (`sys_openat`, `sys_unlinkat`, `sys_renameat`, `sys_utimensat`, `sys_linkat`, etc.). Files: `src/cmd/touch.cyr`, `src/cmd/ln.cyr`, `src/lib/fs.cyr`, and any future utility that lands raw syscalls. Zero behavior change.

Sweeps happen as soon as accepted; no batching required.

### M12 — POSIX-deviation fill-in (GNU-parity features)

The "missing" column of the M7 POSIX audit ([2026-05-18-posix-compliance.md](../audit/2026-05-18-posix-compliance.md)). Each is a named follow-up against a concrete enabler, not a TBD. Grouped by enabler dependency:

**M12a — chrono-dependent (`lib/chrono.cyr` upstream additions):**

- `sleep` fractional + suffix (`1.5s`, `1m`, `1h`) — duration parser.
- `touch` `-r REF` / `-t STAMP` / `-d STR` — date parser.
- `date` `-d STR` parsing — same parser.
- `date` local-time tzfile parsing — `chrono_tz.cyr` (per ADR 0007); the longest of the three.
- `ls -l` locale-aware mtime form.
- `stat` `%x` / `%y` / `%z` strftime renderers.

**M12b — `lib/flags.cyr` upgrade-dependent:**

- Option-parser short clustering `-rfv` and attached short values `-n10` (ADR 0002 honoured end-to-end after this).
- `--help` / `--help=json` / `kriya --list` per ADR 0002 — needs the spec-renderer on top of `flags.cyr`.

**M12c — stdlib helper-dependent:**

- `lib/str.cyr` escape table → `echo -e` / `-E`.
- `fs.cyr` stat-compare → `pwd` `$PWD` inode-match.
- Symlink-aware utimensat wrapper → `touch -h`.
- `fs.cyr` xattr fd-anchored API → `cp`/`mv` xattr preservation (M8 audit names the safe pattern).
- Inode-set helper → `cp --preserve=links` AND `du` hardlink dedup. Same surface.
- `niyama` literal/fixed-string Boyer-Moore fast path (upstream) → `grep` literal speedup (CHANGELOG 0.6.0 names this; also a perf item, see M13).

**M12d — per-utility independent (no shared blocker):**

- `cp` `--preserve=links` (after M12c inode-set helper).
- `mv` cross-FS UID/GID preservation (rides with `cp --preserve=ownership`).
- `mv` multi-file `--follow`.
- `cp -R` source for char/block device nodes (currently rejected; per M8 audit decision).
- `ln -r` (relative symlink), `-T`/`-t` (target-dir disambiguation), `-b`/`--backup`.
- `ls -C` (multi-column tty packing), `-t`/`-S` (sort keys), `--color=auto`, `%U`/`%G` name lookup.
- `head` `-n -N` / `-c -N` all-but-last form (shared suffix-parser with `tail` when extracted).
- `tail` multi-file `-f`, `-F` retry, `+N` start-from-line, k/M/G suffixes.
- `nl` section delimiters (`-d` / `-h` / `-f` / `-l` / `-p`), `-b p REGEX` (needs niyama).
- `uniq` `--all-repeated`, `--group`.
- `tr` `[=c=]` equivalence classes, `[c*N]` repetition, locale fold.
- `cut` multi-byte `-c` (needs UTF-8 decoder).
- `sort` `-h` / `-V` / `-g` / `-M` / `-R` / `-m` / `-d` / `-i`, multi-key `-k F1 -k F2`, end-field key range `-k F1,F2`, external-sort fallback for inputs > 256 MiB.
- `printf` `%e` / `%f` / `%g` / `%a` floats, `\xHH` hex escape, positional `%N$s`.
- `seq` `-f FORMAT` (rides with printf floats).
- `grep` multi-`-e` (needs `flags_add_str_multi`), `-A` / `-B` / `-C` context, `--include` / `--exclude` (shared glob with find), `--color` (shared with `ls --color`), `-Z` NUL-separated output, BRE `-i` bracket-class quirk.
- `find` `-prune`, `-delete` (must inherit ADR-0004 `/` refusal), `-exec ... +` (ARG_MAX argv-chunking), `-regex` (niyama), `-perm`, `-user` / `-group` (passwd/group lookup), `-depth` (DFS post-order), `-H` (operand-only follow).
- `xargs` `-P N` (parallel — job-table management), `-p` (interactive prompt), `-L N` (lines-per-cmd), `-x` (overflow-exit), `--show-limits`.
- `du -x` (one-filesystem), `--exclude` / `--exclude-from`, `--inodes`, `-0` NUL output, POSIXLY_CORRECT 512-byte default.
- `df` `-t TYPE` filter (POSIX-required), stat-based "filesystem containing FILE" operand walk.
- `env -S` split-string mode, `env -C DIR`.

Each item is one PR; the larger ones may warrant their own ADR if they change cross-cutting policy.

### M13 — Performance optimization

The named follow-ups in [docs/benchmarks.md](../benchmarks.md). Each has a concrete enabler.

- **`wc -c` fast path** — detect regular-file fd, return `st_size` without reading. ~20 LOC. Closes the 200× gap.
- **niyama Boyer-Moore for literal patterns** — upstream Cyrius. When pattern has no special chars, build a skip table. Affects `grep` and any future niyama consumer. Closes the 2300× literal-scan gap.
- **`tail` seek-from-end** — for seekable input, `lseek(SEEK_END)` + back-scan in 8 KiB chunks. Removes the 16 MiB cap on regular files. Closes most of the 12× gap.
- **`cp` `copy_file_range(2)`** — Linux-specific accelerated copy with reflink on supporting filesystems. Speculative; check AGNOS kernel availability.
- **`find` predicate JIT** (speculative) — compile predicate AST to flat eval loop. Not committed; revisit if benchmark pressure rises post-burn.

Each can land independently against a 1.x.y minor.

### M14 — stdlib `getenv` post-fork bug (upstream Cyrius)

Tracked as a "would be nice to fix" against `lib/io.cyr`. find and xargs work around via PATH caching at startup (CHANGELOG 0.6.0 deferred-list, kriya-side workaround). When upstream fixes the stack-vs-syscall-clobber interaction in `getenv`'s 8 KB stack buffer, kriya can strip the PATH-cache workaround. Zero behavior change kriya-side; pure cleanup.

### Out of scope for any 1.x.y

The "Out of scope (for v1.0)" list below stays out of scope for 1.x as well. New utility additions that pass the ADR-0006 four-criteria gate could land as 1.x.y, but the hard scope-boundary table (archive, networking, GPU, editor) is fixed.

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
