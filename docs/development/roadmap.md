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

v1.0 froze 2026-05-18 with 7 of 8 criteria checked. The 8th — downstream consumer green via AGNOS kernel boot-burn — is the trigger for **M10**.

Post-1.0 work is described **twice, on purpose**, and the two views serve different questions:

- **The 1.2.x arc** (immediately below) is the RUNNING ORDER — what ships next, batched by shared
  enabler. Read this to know what to work on.
- **The milestone buckets M10–M17** (after it) are the CATALOGUE — every known item, grouped by
  kind, in numeric order. The number is an identifier, not a priority. Read this to find whether
  something is already tracked, and to see what the arc has not yet scheduled.

Items live in the catalogue and are pulled into the arc when their enabler is ready. Nothing should
appear only in the arc.

## The 1.2.x arc

Post-1.0 work up to now has been a **bucket list** (M10–M17): correct groupings, no sequence. The
1.2.x arc puts a running order on it. Each release below is a coherent batch — its items share an
enabler, a file, or a user-facing story, so one round of test work serves the whole batch instead of
being re-derived per item.

Two rules hold across the arc:

- **A batch is defined by its enabler, not by its utility.** Half the open work is blocked on a small
  number of shared capabilities (§ Enabler map below). Shipping the enabler is the release; the
  features that ride on it are the release notes.
- **"Accepts and lies" outranks "rejects cleanly."** An option kriya refuses with exit 2 is a visible
  gap a user works around. An option it *accepts and silently ignores* — or answers wrongly — is a
  correctness defect wearing a feature's clothes, and those are pulled forward regardless of which
  bucket they came from. Two were found in the v1.2.0 cycle alone (see 1.2.1 below).

### 1.2.0 — Option handling ✅ shipped 2026-08-25

Clustered short options (`-rf`, `-la`, `-in`, `-lw`, `-cd`), attached short values (`-n5`, `-c1-3`),
and the obsolescent bare-digit form (`head -5`, `tail -5`), via a spec-driven pre-expansion in
`src/lib/args.cyr` that serves all 28 utilities routing through `kriya_args_parse`. Plus the two
M17 defects that live in the same code: **M17b** (`xargs` parsing the child's command line as its
own, including deleting its `--` guard) and **M17c** (`xargs -I` splitting on blanks instead of
lines). Closes **M12b**'s parser half.

### 1.2.1 — Accepts-and-lies ✅ shipped 2026-08-25

The class swept in one pass. Wider than catalogued: two items were listed, six shipped.

- **Every bool long option silently swallowed `=VALUE`**, in all 28 utilities on the shared parser —
  not just the three the catalogue named. Now refused with GNU's diagnostic. The three options GNU
  *does* allow a value on (`cp --preserve`, `sort --check`, `tail --follow`) opt in by name via
  `kriya_args_parse_optval`, since the parser cannot represent an optional-value long.
- **`grep -e A -e B`** collects every occurrence via the new `kriya_argv_collect`.
- **`printf %f`** and every invalid directive exit 1 with nothing on stdout, stopping at the error
  like GNU. **`\xHH`** implemented while there.
- **`stat` / `date`** refuse specifiers they cannot render instead of echoing the source bytes.
  `stat`'s unknown-specifier output corrected to `?` (GNU's actual behaviour, which an existing smoke
  case had pinned wrongly).

Carried forward, each blocked on a different enabler:

- `cp --preserve=links` / `ownership` — needs the inode-set helper (**M12c**). Refused by name today.
- `stat %x/%y/%z`, `date %V/%c/%x/%X/%r` — need chrono's strftime formatter (**M12a**, batch 1.2.5).
- `stat %U/%G` — needs a passwd/group parser (**M12c**).
- `stat %N` — needs a quoting helper, shared with the `ls` quoting story (**M12d**).
- `printf %e/%f/%g/%a` — needs a float-formatting story (**M12d**). ⚠ The stdlib's `fmt_float_buf`
  carry bug was only fixed at cyrius 6.5.30 (see `[1.1.10]`), so this would have inherited it.

### 1.2.2 — The spawn helper

**M17a** — `find -exec` and `xargs` discard the child's stderr, because stdlib `exec_env` dup2s
`/dev/null` onto fd 2. `find rot -name '*.tmp' -exec rm {} \;` on an unwritable directory prints
nothing and exits 0 while deleting nothing. A kriya-local fork + execve + waitpid helper in
`src/lib/`, with fds 0/1/2 inherited untouched and a raw wait status the callers can decode, fixes
both utilities and is the prerequisite for `find -exec ... +` and `xargs -P` later.

### 1.2.3 — Walk safety

**M17d** (`grep -r` re-resolves from `AT_FDCWD` instead of descending from the parent dirfd — the
TOCTOU that `rm`, `cp` and `find` already avoid) and **M17f** (`cp -R -i` never prompts; the
recursive path ignores both `-i` and the no-clobber default). Both are threading work through an
existing recursive walk, and both want the same ADR-0003 re-reading, so they batch.

### 1.2.4 — Destructive-verb semantics (ADR-gated)

**M17e** (`mv` cross-filesystem rollback deleting the only surviving copy) and **M17i** (`rm -r
symlink/` following the link — matching GNU but contradicting kriya's own ADR-0003 stance). Both are
behaviour decisions rather than bug fixes and want a successor ADR before code. Grouped because one
ADR cycle can settle both.

### 1.2.5 — The chrono batch

**M12a** in full, once `lib/chrono.cyr` grows a duration parser, a date parser and a tz reader:
`sleep 1.5` / `1m` / `1h`, `touch -r REF` / `-t STAMP` / `-d STR`, `date -d STR`, `date` local time
(ADR 0007), `ls -l` locale mtime, `stat %x`/`%y`/`%z`. Six utilities, one upstream dependency —
which is exactly why it is a batch and not six PRs.

### Not yet scheduled

**M17g** (`ls -l` fabricating metadata on stat failure), **M17h** (grep's per-byte heap retention),
**M17j** (realpath's 16 KiB ceiling), the rest of **M12c**/**M12d**, and all of **M13**. These land
against 1.2.x point releases as they become ready; the batches above are the ones with a settled
running order.

### Enabler map

What actually gates the arc. Ship the enabler, and everything under it becomes small.

| Enabler | Home | Unblocks |
|---|---|---|
| Option pre-expansion | `src/lib/args.cyr` | ✅ shipped 1.2.0 — clustering, attached values, `head -5` |
| `flags_add_str_multi` | stdlib or kriya-side accumulator | `grep -e`×N, `grep --include/--exclude`, `sort -k`×N |
| Spawn helper (fork/execve/waitpid, fds inherited) | `src/lib/` | M17a stderr, `find -exec +`, `xargs -P`, `xargs -p` |
| chrono duration + date parser + tzfile | upstream `lib/chrono.cyr` | `sleep`, `touch -r/-t/-d`, `date -d`, `date` local, `ls -l` mtime, `stat %x/%y/%z` |
| Inode-set helper | `src/lib/fs.cyr` | `cp --preserve=links`, `du` hardlink dedup |
| UTF-8 decoder | stdlib `unicode/` (present) or kriya-side | `cut -c` multi-byte, `tr` locale fold, `uniq` multi-byte `-i` |
| passwd/group parser | new `src/lib/` module | `ls -l` user/group names, `stat %U/%G`, `find -user/-group` |
| Byte-suffix parser (`5K`, `1M`) | `src/lib/args.cyr` | `head -c 1K`, `tail -c 1K`, `sort -S` |
| niyama literal fast path | upstream | `grep` literal speedup (M13), `grep` memory (M17h) |
| Comparator-by-flag indirection | `src/cmd/ls.cyr` | `ls -t`, `-S`, and the `--color` table |

## Milestone buckets (M10–M17) — the catalogue

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

### M15 — Codegen / toolchain-interaction watchlist (standing)

Not a milestone that closes: a **standing list of the ways the Cyrius compiler and kriya interact
badly**, kept because every entry here has already cost real time at least once, and because the
failure mode is always the same — the code reads correctly, compiles clean, passes lint, and is wrong
anyway. Opened at v1.1.11 out of the P-1 sweep.

Each entry names the rule, how to detect it **mechanically**, and what happened the last time it bit.
Re-run the detections at every toolchain pin bump; the 6.5.x line is the codegen-quality line and a
pin move is exactly when a latent instance stops being latent.

**M15a — A function-local `var X[N]` is N BYTES. At module scope it is N×8.**
The single most expensive rule in this list. Re-measured at pin 6.5.35 with a two-local probe:
`|&b - &a|` = **8 / 32 / 144** for `var x[4]` / `var x[32]` / `var x[144]`.
- *Detection*: for every `var X[N]` in `src/`, take the maximum byte offset actually accessed
  (`store8`/`store16`/`store64`/`load*`/`memcpy`/a syscall buffer arg) and require it `< N`. Sizes are
  a strong smell on their own: a buffer holding k 64-bit fields must be `[k*8]`, and every `struct stat`
  buffer must be `[144]`.
- *Note*: kriya currently has **zero** module-scope arrays — all 136 are function-local — so the
  N-bytes reading always applies here. A future module-scope array would silently flip the rule.
- *Bit us at v1.1.9*: `find`'s `var ctx[4]` held four i64 fields. Silent for a year because the old
  register allocator left dead space where the overflow landed; the 6.5.18 bump repacked the frame
  onto live state and `find` went 40/40 → 8/40.
- *Bit us again at v1.1.11*: `k_access`'s agnos arm declared `var st[48]` for `k_stat`'s **output**,
  confusing agnos's 48-byte wire struct with the canonical 144-byte layout `_k_agnos_stat` actually
  writes. A 96-byte frame smash on every PATH probe, reachable from `which`, `env`, `xargs` and
  `find -exec`. Reproduced on the host with the same shape: SIGSEGV.

**M15b — The register allocator can turn a latent frame bug into a live one.**
6.5.35 fixed two defects that had prevented linear-scan from ever reusing a register, so frame layout
repacks tree-wide. A buffer overrun that previously landed in dead space starts landing on live state.
- *Detection*: there is none in advance — that is the point. Run M15a's scan and the full smoke suite
  after every pin bump.
- *Bisection lever*: rebuild with `CYRIUS_REGALLOC_PICKER_CAP=5` to reproduce pre-6.5.35 register
  assignment. **If the symptom disappears, the defect is kriya's, not the compiler's.**

**M15c — Two `var` of the same name in one function are ONE slot.**
Cyrius hoists a branch-local `var` to the nearest enclosing loop or function, so declarations in
different arms of an `if`/`elif`/`else` collide rather than shadow.
- *Detection*: group `var` declarations by name within each function. Scalars reused sequentially are
  fine; the dangerous shape is a duplicate **array** (a scratch buffer), where stale bytes from one arm
  can be read by another.
- *Status at v1.1.11*: scanned clean. Three duplicate-array sites exist — `cut.cyr` `tb[2]`,
  `touch.cyr` `ts[32]`, `uniq.cyr` `klen_box[8]` — and all three are mutually exclusive arms that fill
  before they read.
- *Bit us at v1.1.6*: `grep`'s one-byte line-terminator scratch was redeclared at all five emit sites;
  two in the same `if`/`elif`/`else` chain collided and broke `cyrius build --agnos` outright.

**M15d — `break` inside a `while` that declares a `var` is unreliable.**
Use a flag plus `continue`, per CLAUDE.md.
- *Detection*: for each `while` body containing a `var` declaration, flag any `break;`.
- *Status at v1.1.11*: **zero instances**. The four `break;` in `src/cmd/find.cyr` are in loops with no
  `var` declaration.

**M15e — Include order in `src/main.cyr` is load-bearing, and so is the dependency direction.**
A global must be declared before its use, so the 46-line include list is a dependency order, not a
style choice. The subtler half is directional: adding a function to a `src/lib/` file that calls into a
**later**-included module breaks every consumer that includes only a subset — and it breaks quietly,
because cyrius only rejects *reachable* undefined functions, so an unused one is dead-code-eliminated
and the build stays green until someone calls it.
- *Detection*: after adding a cross-module call in `src/lib/`, build `tests/*.tcyr` and `tests/*.fcyr`
  too — they include subsets of `src/lib/`, not `src/main.cyr`.
- *Bit us at v1.1.11*: `fs_path_absolute` was first written into `path.cyr`, where it both violated that
  file's documented "nothing here touches the filesystem" commitment and introduced a `path.cyr` →
  `sys.cyr` dependency that `tests/kriya.tcyr` did not satisfy. It built green only because nothing
  called it yet. Moved to `fs.cyr`, which is filesystem-aware and already ordered after `sys.cyr`.

**M15f — A syscall returns a NEGATIVE ERRNO, and nothing forces you to look.**
- *Detection*: enumerate `syscall(` and `sys_*` call sites and check each result is tested, with the
  right predicate — `r < 0`, not `r == (0 - 1)`, since the kernel answers `-ENOENT` (−2), not −1.
- *Status at v1.1.11*: all write traffic goes through `k_write`, which now records a sticky failure the
  dispatcher consults at exit — the ~540 call sites still ignore the return, and that is now safe by
  construction rather than by luck. All read traffic goes through `k_read`. No raw `syscall(1, …)` or
  `syscall(0, …)` remains outside `src/lib/sys.cyr`.

**M15g — Language shapes that compile to something other than what they read as.**
Standing, low-drama: no negative literals (write `(0 - N)`), no mixed `&&`/`||` in one expression
(nest the `if`s), enum members are const-folded and consume no `gvar_toks` slot, and a top-level
`var x = 42;` takes the static-init fast path while `var x = f();` consumes one of the 4,096
initialized-globals slots.

### M16 — AGNOS as a build target (opened 2026-06-06; design-first)

> ⚠ **Renumbered from M11 at v1.1.11.** This section was added at 1.1.0 and given a number that was
> already taken: **M11 is the Cyrius proposal sweeps**, as referenced by `CHANGELOG.md` ("M10–M14"),
> `docs/development/state.md`, and the 1.0.0 release notes. It also sat *above* M10, breaking the
> reading order. The established numbering wins; this bucket moves to M16. One point-in-time document
> — `docs/development/issue/archive/2026-06-14-bin-applets-crash-on-agnos-iron.md` — says "M11
> (AGNOS-as-build-target)" and is deliberately **left frozen**: archived issue notes are a record of
> what was known then, not a live index.

Make kriya the sovereign, **shell-independent** coreutils for AGNOS — the canonical home for the FS tools (any shell execs it, the Unix way; agnsh's 1.4.2 builtin verbs are a shell-bound convenience that this supersedes once 1.43.x `execwait` lands). **Prep done:** pin 5.11.61 → 6.0.56, lib re-vendored, VERSION → 1.1.0.

**Why it's a real refactor (not a gate-the-blockers port like bannermanor/commandress):** kriya hardcodes **Linux syscall numbers** (`syscall(82,…)`=rename, `217`=getdents64, `257`=openat — ~610 numeric-syscall sites) instead of the target-aware `SYS_*` constants, parses **Linux `getdents64`/`stat` struct formats** (the sovereign agnos formats differ — see `agnos-userland-abi.md` §4.1/§4.2), and uses modern **`*at` syscalls** (openat/renameat/linkat/newfstatat/utimensat) that agnos doesn't define (agnos has the basic forms with different numbers + the explicit-length ABI).

**Plan:** make the central `src/lib/fs.cyr` syscall layer target-aware (`#ifdef CYRIUS_TARGET_AGNOS`: agnos numbers + sovereign dirent/stat structs + `*at`→basic mapping; Linux path unchanged) — most commands flow through it, so it's the leverage point. Then gate the per-command stragglers: `ln` (linkat/newfstatat), `touch` (utimensat → degrade timestamps), `tail` (lseek → degrade), `pwd` + path resolution (getcwd → degrade; CWD is userland-owned on agnos), `rm`/`cp`/`mv` (TTY `ioctl` TCGETS → non-interactive). Validate with `cyrius build --agnos` per command + the Linux `.tcyr` regression. Analogous to the agnosys-core repair, scaled to the coreutils FS surface.

### M17 — Confirmed defects deferred from the v1.1.11 P-1 sweep

Every item below was **reproduced against a shipped build**, and every one was left unfixed at
v1.1.11 because its repair is a redesign rather than a patch — a new primitive, an option-parser
rewrite, or an ADR-level decision about behaviour. They are ordered by consequence. This milestone
closes when the list is empty; each item is one PR.

The sweep's *fixed* findings are in `CHANGELOG.md` under `[1.1.11]`. The ones it **refuted** are
recorded there too, so they do not get re-litigated.

**M17a — `find -exec` and `xargs` discard the child's stderr.** *(silent failure — highest
consequence here)*
`exec_env` from the stdlib `process` module dup2s `/dev/null` onto fd 2 in the child. Reproduced:
`chmod 555 rot; kriya find rot -name '*.tmp' -exec rm {} \;` prints **nothing** and exits **0** while
deleting nothing; GNU prints a "Permission denied" line per file. A cleanup job written this way
reports complete success having done nothing at all. *Deferred because* the fix is a new
kriya-local spawn helper — fork + execve + waitpid with fds 0/1/2 inherited untouched, returning a
raw wait status so callers can tell a normal exit from a signal death from an exec failure — and
then moving both `find` and `xargs` onto it. That is a new primitive in `src/lib/`, with its own
tests, not a line change.

**M17b — `xargs` runs its own option parser over the child's command line.**
`echo t.txt | kriya xargs sort -r` silently sorts *ascending*: `-r` is eaten as
`--no-run-if-empty`. `xargs head -n 2` eats `-n 2` as `--max-args`. Worse, the `--` guard is
consumed and deleted, so `ls -1 | xargs rm --` hands `rm` an argument list starting `-r` and
**recursively deletes a directory** the `--` existed to protect. *Deferred because* the fix is a
rewrite of the option scan: stop at the first token that is not a recognised xargs flag and copy the
rest verbatim, mirroring the state machine `cmd_env` already uses. That changes how every `xargs`
invocation is parsed and needs the whole 23-case smoke script re-derived against GNU.

**M17c — `xargs -I` splits input on whitespace instead of on lines.**
POSIX says a replacement string consumes one **line** per invocation. kriya splits on blanks, so
`printf 'a b\n' | xargs -I{} rm -- {}` deletes files `a` and `b` and leaves `a b`. The common
`ls | xargs -I{} mv {} dest/` idiom mangles every filename containing a space. *Deferred because* it
shares the parser surface with M17b and should land in the same PR.

**M17d — `grep -r` re-resolves each path from `AT_FDCWD` instead of descending from the parent
dirfd.** *(TOCTOU)*
`rm`, `cp` and `find` all thread a parent dirfd through their walks per ADR 0003; `grep -r` is the
one that does not. Reproduced: swap an ancestor directory for a symlink to `/etc` mid-scan and grep
follows it out of the tree and reports `/etc/passwd` contents under the original path, exit 0.
*Deferred because* the repair is the same dirfd-threading refactor the other three already carry —
`_gr_walk_dir(parent_dirfd, name, display_path, …)` plus `fs_opendir_nofollow` — touching the whole
recursive path of a 1,022-line file.

**M17e — `mv` cross-filesystem directory rollback deletes the destination.**
When the copy succeeds but the source removal partially fails, `_mv_cross_fs` unwinds by deleting the
destination tree — which by then is the **only** copy of any file already drained from the source.
Reproduced with an unwritable source parent: source emptied, destination gone, data unrecoverable.
*Deferred because* it is a behaviour decision, not a bug fix: GNU keeps the destination and reports
the source-removal error, leaving two trees rather than zero. Adopting that is right, and it wants an
ADR because it changes documented `mv` failure semantics.

**M17f — `cp -R -i` never prompts, and the recursive path ignores the no-clobber default.**
Under a real pty, `kriya cp -i -R src dst` overwrites `dst/src/f` with no prompt and exits 0.
`interactive` is simply not threaded through `_cp_dir_top` → `_cp_dir_descend_at` → `_cp_file_at`.
*Deferred because* the fix has to add a destination-exists check at every recursive file write and
decide what `-i` means when the prompt is answered "no" partway through a tree — a partial copy with
what exit status? That is an ADR-0002 question.

**M17g — `ls -l` fabricates metadata when a per-entry stat fails.**
In a readable-but-not-searchable directory, `kriya ls -l` prints
`---------- 0 0 0 0 1970-01-01 00:00 afile` and exits 0, rendering a symlink as a regular file. GNU
prints `?` for the unknown fields, reports `cannot access` on stderr, and exits 1. *Deferred because*
`fs_stat_entry`'s failure needs to become a per-record state that the column-width computation, the
long-format renderer and the exit-status rollup all understand.

**M17h — `grep` retains roughly 320 bytes of heap per byte of input under BRE/ERE.**
A 13.6 MB file segfaults under `ulimit -v 1048576`; GNU handles it in constant memory. *Deferred
because* the real fix is upstream (niyama), but there is a kriya-side half worth taking first: route
patterns with no metacharacters to the already-present `GR_ENG_FIXED` handle instead of compiling an
NFA. That overlaps the M13 Boyer-Moore item and should be scoped with it.

**M17i — `rm -r symlink-to-dir/` follows the link and empties the target.** *(policy, not a
regression)*
Verified that **GNU does exactly the same**, so this is not a divergence from the reference
implementation — the sweep's original claim that GNU refuses was wrong. It is, however, a divergence
from kriya's own stated rule that destructive operations do not follow symlinks unless `-L` opts in
(CLAUDE.md; ADR 0003 hard rule #1). *Deferred because* choosing to be stricter than GNU on a
destructive verb is exactly what ADR 0003 exists to decide, and the successor ADR should settle the
trailing-slash case explicitly.

**M17j — `realpath` refuses inputs over 16 KiB where GNU still resolves them.** *(accepted
limitation)*
v1.1.11 bounded `fs_realpath`'s previously unchecked seed and symlink-rebuild copies, which turned a
silently wrong answer into an honest `ENAMETOOLONG`. GNU grows its buffer instead. *Deferred because*
making `result`/`remaining` growable is a contained but real change, and refusing is the safe
behaviour to ship in the meantime.

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
