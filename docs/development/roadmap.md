# kriya — Roadmap

> **Open work only.** Anything shipped has been removed from this file — the record of what
> landed and why lives in [`CHANGELOG.md`](../../CHANGELOG.md) (per release) and
> [`state.md`](state.md) (current snapshot). This file answers one question: *what next, in
> what order, against what gate.*

## How this file is organised

Three sections, each answering a different question:

| Section | Answers | Use it when |
|---|---|---|
| **Arcs** (1.2.6 → 1.9.x) | *What ships next?* | Picking up work |
| **Gated** | *Why isn't this moving?* | Asking why an item never appears in an arc |
| **Standing** | *What must I re-check every time?* | Bumping the toolchain pin |

### A note on the M-numbers

Earlier revisions of this file tracked work as milestone buckets **M0–M17**, and `CHANGELOG.md`
entries reference them. Those numbers are **historical identifiers, not a live index** — the arcs
above are the running order now. Where a bucket is still open and still has a natural name, the
number is kept (**M10** consumer-burn, **M11** proposal sweeps, **M14** getenv, **M15** watchlist,
**M16** agnos target). The rest are shipped or dissolved into the arcs:

| Old bucket | Where it went |
|---|---|
| M0–M9 | shipped; see `CHANGELOG.md` |
| M12a (chrono) | 1.8.3 (`date -d`) + Gated (tzfile); the rest shipped in 1.2.5 |
| M12b (flags upgrade) | 1.2.0 (clustering, shipped) + 1.3.x (`--help`/`--list`) |
| M12c (stdlib helpers) | distributed across 1.4.x–1.6.x by enabler |
| M12d (per-utility) | distributed across 1.4.x–1.8.x by theme |
| M13 (performance) | 1.9.x |
| M17 (all of a–j) | shipped across 1.2.0–1.2.6; the bucket is retired |

Two rules hold across the arcs, both learned the hard way:

- **An arc is defined by its enabler, not by its utility.** Most open work is blocked on a small
  number of shared capabilities (§ Enabler map). Shipping the enabler *is* the release; the features
  riding on it are the release notes. Batching by enabler means one round of test work serves the
  whole batch instead of being re-derived per item.
- **⚠ Re-check the enabler before scheduling around it.** The 1.2.5 chrono batch was filed as fully
  upstream-gated and turned out two-thirds actionable — the assumed blockers either did not exist or
  were weaker than the local code already was. Verify the gate before you plan around it.

## Arc sequence

| Arc | Theme | Enabler | Gate |
|---|---|---|---|
| **1.3.x** | Discoverability | spec-renderer atop `flags.cyr` | ready; **consumer waiting** (agnoshi) |
| **1.4.x** | Pattern & text parity | repeatable-option collector, UTF-8 decoder | ✅ closed at 1.4.5 |
| **1.5.x** | Identity & listing | passwd/group parser, comparator indirection | ready |
| **1.6.x** | File-op completeness | inode-set helper, xattr API | ready |
| **1.7.x** | Traversal, exec & FS reporting | spawn helper ✅, ARG_MAX chunking | ready |
| **1.8.x** | Parsers & numerics | float formatting, byte-suffix parser | ready |
| **1.9.x** | Performance | niyama literal fast path (upstream, partial) | partly gated |

No arc depends on another — they are independent and can be resequenced by consumer demand. The
order below reflects **who is waiting**: 1.3.x first because agnoshi has a named, external need for
it.

⚠ **The 1.2.x correctness arc closed at 1.2.6.** Everything below is new capability rather than
defect repair, which is a different kind of risk: these change what kriya *does*, not what it gets
wrong. Expect more ADRs and more GNU-comparison work per item than 1.2.x needed.

---

## 1.3.x — Discoverability ✅ CLOSED at 1.3.8

⭐ **Complete.** `--help` (1.3.0), `--help=json` (1.3.1), `kriya --list` + a CI that can fail (1.3.2),
the checks covering the tree (1.3.3), `--version` (1.3.4), the parity audit in three batches
(1.3.5–1.3.7 incl. option tables), and the last two items (1.3.8). All five items kriya owed agnoshi
ship; the kriya side is unblocked and waiting only on agnoshi gaining interactive input.

⛔ **Carry these forward, they are not arc-specific:**
- **One declaration per utility, three readers.** `<util>_help_declare()` in `src/cmd/` feeds the human
  page, the JSON schema and `kriya --list`; the dispatcher table in `src/main.cyr` drives both routing
  and enumeration. `scripts/lint-help-schema.sh` fails the build if a fourth reader copies the data
  instead of deriving it.
- **A spec the parser does not consult is a second source of truth.** `find` carried one for five
  releases — built, never read, never called. The seven hand-rolled utilities now declare specs their
  own walks use as the acceptance gate.
- **Cold start: report the release-over-release delta, never an absolute.** The pre-1.3.2 history is
  mismeasured (it timed kriya plus a whole `date` fork). Name any reference binary `kriya` or the
  dispatcher rejects it on `argv[0]`.
- **A green test is not a finding.** Three of the arc's six bugs hid behind something that looked like
  evidence: a comment naming only the cases where the bug is invisible, a local GNU version, and a
  type list that matched by coincidence.
---

## 1.4.x — Pattern & text parity ✅ CLOSED at 1.4.5

**Enablers:** the repeatable-option collector (`kriya_argv_collect`, shipped 1.2.1) and a UTF-8
decoder. ⚠ Check `unicode/_decode` in the vendored stdlib before writing one — it is already in
kriya's dependency closure for niyama.

- **1.4.x — `grep -NUM` shorthand.** ⚠ Left out of 1.4.0 deliberately: `grep -3` for `-C 3` needs a
  bare `-DIGIT` to parse as an OPTION rather than an operand, and `grep` goes through the shared
  parser where a digit is not a registered short. `seq` solves the same problem with a dedicated argv
  walk (`_seq_token_is_negnum`); lifting that into `src/lib/args.cyr` would serve both. ⛔ Do not
  special-case it inside `grep` — that is the second-source-of-truth shape the 1.3.x arc spent nine
  releases removing.
- **1.4.x — `grep --exclude-dir`.** ⚠ Deliberately not in 1.4.1. `--exclude` does NOT prune
  directories (measured against GNU: a directory matching `--exclude` is still descended), so
  `--exclude-dir` is a genuinely separate flag with its own subject — the directory name during
  descent — rather than a variation on the file filter now shipped. ⭐ The ordered
  rightmost-wins/first-option-default machinery in `_gr_name_allowed` is the part to reuse; the
  matcher (`src/lib/glob.cyr`) is already shared.
- ⛔ **Multibyte `tr` and `uniq -i` are NON-GOALS, not pending work** — settled at 1.4.2 by measuring
  GNU. `tr` is byte-based in every locale (`tr 'é' 'e'` on `café` yields `cafee`, two e's, because
  SET1 is two bytes) and `uniq -i` does not fold non-ASCII. kriya matches both. Changing either would
  **diverge from GNU and silently alter existing scripts**, so it is sovereign design needing its own
  ADR — not a gap. ⚠ Do not re-add them to this arc as if they were unfinished.
- ⛔ **`nl -b pBRE`'s GNU-only operators are a NON-GOAL here — the gap is upstream.** Shipped at
  1.4.4 with `\+ \? \| \b \B \w \W \s \S` REFUSED at parse time, because niyama compiles them
  clean and then matches nothing: the failure mode is a wrong line number, not an error. The fix
  belongs to niyama (**M11**, third item), and closing it there deletes `_nl_rx_unsupported` rather
  than growing it. ⚠ Do not re-implement these inside `nl`.
- ⛔ **Two `grep` divergences found by 1.4.5's fuzz and NOT fixed there** — both predate it, both sit
  in paths that release did not touch, and neither is about `-i`:
  - **A leading `*` in an ERE.** `grep -E '*'` (and `'*a'`, `'a**'`) is a LITERAL asterisk in GNU and
    a usage error in kriya. ⚠ Check POSIX before matching GNU: a leading `*` in an ERE is undefined
    by the standard, so this may be a deliberate divergence rather than a bug — decide, then record
    the decision either way.
  - **`grep -o` emits empty matches.** `grep -o 'x*'` on `abc` prints four empty lines in kriya and
    nothing in GNU. ⚠ Related but distinct: kriya's `-o` also disagrees with GNU on a case-gap range
    under `-i`, and there kriya is the CORRECT one — GNU's `-o` contradicts GNU's own line matcher
    (1.4.5). Do not "fix" that second case toward GNU.

---

## 1.5.x — Identity & listing

**Enablers:** a passwd/group parser (new `src/lib/` module) and a comparator-by-flag indirection in
`ls`.

- ✅ **1.5.0 — passwd/group parser** (shipped). `src/lib/userdb.cyr`; `ls -l` names + `-n`,
  `stat %U`/`%G`, and `find -user`/`-group`/`-uid`/`-gid`/`-nouser`/`-nogroup`. ⚠ **What it does NOT
  do, and will not**: users who exist only in LDAP / SSSD / systemd-homed have no line in
  `/etc/passwd` and resolve to numeric ids. Closing that means NSS, which means dynamic linking —
  a **No-Go** for a static tool, not a deferral. Do not re-open it as unfinished work.
- ✅ **1.5.1 — `ls` sort keys** (shipped). `-t` and `-S`, descending with a name tie-break,
  nanosecond precision, rightmost-of-`-t`/`-S` wins. ⭐ The insertion sort became a merge sort in
  the same pass: 8,000 entries went 0.755 s → 0.022 s (GNU 0.004 s).
- ✅ **1.5.2 — `ls --color`** (shipped). `--color=WHEN` with `LS_COLORS`, GNU's compiled-in defaults,
  extension patterns, the full type precedence, and tty detection for `=auto`. ⭐ Enabled by
  `src/lib/env.cyr`, which removed an 8 KB cliff in kriya's environment lookup that was also
  silently breaking **PATH** in `which`/`xargs`/`find`.
  - ⚠ **One measured gap remains**: `no=` (the "normal" key) positions its prefix at the START OF
    THE LINE — before the `-l` columns and before the `-i` inode — where kriya emits it before the
    NAME. 140 of 2,500 pathological comparisons; **zero** on realistic input, because a real
    `dircolors -b` never emits `no=`. Closing it means moving the prefix from the name to the line.
  - ⛔ **1.5.1's note here claimed "there is NO per-type table to ship". That was half wrong.** With
    `LS_COLORS` unset there are no escapes at all — but set it to any valid key and GNU loads a
    compiled-in default table and overlays the variable. Both halves are needed. Left recorded
    because the wrong half was written down with as much confidence as the right one.
- ⛔ **Two pre-existing `ls` divergences found while measuring 1.5.1**, both confirmed against the
  1.4.4 binary and neither caused by it:
  - **`ls -d` with no operand lists the directory's CONTENTS**; GNU lists `.`. Small and clearly
    wrong; it needs a test that would have caught it, not just the fix.
  - **Multi-column padding uses spaces where GNU uses a TAB.** ⚠ Column POSITIONS are identical, so
    only a byte-exact tty comparison sees it — which is why every piped smoke comparison passed.
    Pairs with the colour work above, since GNU's own rule switches on whether colour is active.
- ✅ **1.5.3 — Quoting** (shipped). `src/lib/quote.cyr`; `stat %N`, `ls` tty quoting with the `-l`
  alignment rule, and `pwd`. ⚠ The `pwd` half was BIGGER than this entry said — "needs only a
  stat-compare" missed that kriya's DEFAULT was logical where GNU's is physical, and that `-L`
  validated nothing beyond a leading `/`, so `PWD=/etc kriya pwd` printed `/etc`.
  - ⚠ **Residual quoting divergence, measured at 0.17%** over a 3,000-name hostile fuzz: names
    combining a `'` with escaped bytes in particular positions, where GNU emits a leading empty `''`
    kriya does not. ⛔ In at least one of those GNU's own output does not round-trip (`'\t'` reads
    as backslash-t). Worth revisiting only if a consumer hits it.
  - ⚠ **UTF-8 locales**: kriya is byte-oriented and escapes every high byte, matching GNU under
    `LC_ALL=C`; GNU under a UTF-8 locale renders valid multi-byte bare. More verbose, never wrong.
    Changing it would mean decoding UTF-8 in the quoter — the `cut`/`wc` precedent exists.
  - ⚠ **`--quoting-style` accepts only `literal`, `shell-escape` and `shell-escape-always`** — the
    three kriya's helper implements. `shell`, `c`, `escape`, `locale` and `clocale` are REFUSED by
    name. Adding them is a small, well-bounded follow-up if a consumer asks.
  - ⚠ **`QUOTING_STYLE` is read by GNU and NOT by kriya.** GNU lets it override the tty/pipe default
    in both directions. kriya declines it for the reason ADR 0011 gave for `echo`; the smoke oracle
    unsets it so the tests measure the code rather than the shell. Revisit only with an ADR.
  - ⛔ **STILL OPEN from 1.5.1: multi-column padding uses spaces where GNU uses a TAB.** Column
    POSITIONS are identical, so only a byte-exact tty comparison sees it. Now the LAST known `ls`
    output divergence on a terminal.

---

## 1.6.x — File-op completeness

**Enablers:** an inode-set helper in `src/lib/fs.cyr` and an fd-anchored xattr API. ⚠ The M8 security
audit names the safe xattr pattern — follow it rather than reinventing.

- **1.6.0 — Hard-link awareness.** The inode-set helper serves two callers: `cp --preserve=links`
  (which v1.2.1 made refuse **by name** rather than silently ignore) and `du` hardlink dedup. Same
  surface, one implementation.
- **1.6.1 — Ownership and xattrs.** `cp`/`mv` xattr preservation, and `mv` cross-FS UID/GID
  preservation (which rides with `cp --preserve=ownership`). ⚠ Both extend `--preserve=`'s accepted
  attribute list, which v1.2.1 deliberately made a closed set — widen it there, not by loosening the
  check.
- **1.6.2 — `ln` and the stragglers.** `ln -r` (relative symlink), `-T`/`-t` (target-dir
  disambiguation), `-b`/`--backup`; `touch -h` (symlink-aware utimensat); `cp -R` of char/block
  device nodes, currently rejected per the M8 audit decision; `mv` multi-file `--follow`.
- **1.6.3 — `realpath` flags, and the `sleep` operand decision.** `realpath -s`/`--strip`/
  `--no-symlinks` (text-only canonicalization), `--relative-to=DIR`, `--relative-base=DIR`, and the
  `-L`/`-P` pair (POSIX `cd -L` semantics vs the current physical default). ⚠ Also settle `sleep`:
  GNU sums several DURATIONs (`sleep 1m 30s`), POSIX specifies exactly one, and kriya rejects the
  second operand today. **It is a decision, not an omission** — either implement the summing or
  record the POSIX-strict refusal in an ADR, but stop carrying it as an unnamed follow-up.
- **1.6.4 — Defenses that need infrastructure first.** Two items blocked on the same kind of gap:
  - ⛔ **`rm` cross-operand bulk-root defense.** [ADR 0004](../adr/0004-rm-refuses-root.md) refuses `/`
    per operand, but `rm -rf /*` expands **at the shell** to `/bin /boot /etc …` — every operand
    individually legal, the aggregate catastrophic. Needs `docs/architecture/003-*.md` to define the
    heuristic (operand count against a threshold of top-level directories?) before any code, because
    a false positive here refuses a legitimate `rm -rf ./*`. ⚠ Design first; this is the one place a
    wrong guess is worse than the gap.
  - **`tee -i`/`--ignore-interrupts`** and `-p`/`--output-error=`. Gated on the signal-handler
    infrastructure named in [`docs/architecture/002-signal-handling-model.md`](../architecture/002-signal-handling-model.md),
    whose trigger row has never fired — `tee -i` would be its first real consumer.

---

## 1.7.x — Traversal, exec & filesystem reporting

**Enabler:** the spawn helper (`src/lib/spawn.cyr`, shipped 1.2.2) plus ARG_MAX argv chunking.
⭐ The spawn helper was the prerequisite the P-1 sweep flagged; everything here was blocked on it.

- **1.7.0 — Batched exec.** `find -exec ... +` (ARG_MAX chunking) and `xargs -L N` / `-x` /
  `--show-limits`. All four are the same argv-accounting problem seen from two directions.
- **1.7.1 — `find` predicates.** `-prune`, `-depth` (DFS post-order), `-perm`, `-H` (operand-only
  follow — the one [ADR 0003](../adr/0003-symlink-follow-policy.md) mode still deferred).
- **1.7.2 — Destructive and parallel.** ⛔ `find -delete` **must inherit the [ADR-0004](../adr/0004-rm-refuses-root.md) `/` refusal and
  the [ADR-0010](../adr/0010-rm-refuses-a-trailing-slash-symlink-operand.md) trailing-slash-symlink refusal** — a second deletion path that does not is a hole in
  both. `xargs -P N` (job-table management) and `-p` (interactive prompt, which must honour ADR 0002's
  no-hang-on-non-tty rule).
- **1.7.3 — Usage reporting.** `du -x` (one-filesystem), `--exclude`/`--exclude-from`, `--inodes`,
  `-0`, POSIXLY_CORRECT 512-byte blocks; `df -t TYPE` (POSIX-required) and the stat-based
  "filesystem containing FILE" operand walk; `env -S` split-string and `-C DIR`.

---

## 1.8.x — Parsers & numerics

**Enablers:** a float-formatting story and a byte-suffix parser in `src/lib/args.cyr`.

⚠ The stdlib's `fmt_float_buf` carry bug was only fixed at cyrius 6.5.30 (see CHANGELOG `[1.1.10]`) —
implementing floats before that pin would have inherited it. The pin is past it now.

- **1.8.0 — Floats.** `printf %e` / `%E` / `%f` / `%F` / `%g` / `%G` / `%a` / `%A` — which v1.2.1 made
  **fail honestly** rather than print the conversion letter — plus positional `%N$s`. `seq -f FORMAT`
  rides directly on it.
- **1.8.1 — Sort keys.** `-h` (human-numeric), `-V` (version), `-g` (general-numeric), `-M` (month),
  `-d` (dictionary), `-i` (ignore-nonprinting), `-R` (shuffle), `-m` (merge pre-sorted), and multi-key
  `-k F1 -k F2`. ⚠ The repeatable-`-k` half needs the same collector `grep -e` uses. ⭐ The key
  *window* itself is correct as of 1.3.3 — `-k F` runs to end of line and `-k F1,F2` honours the end
  field — so this entry is now only about additional key TYPES and multiple keys, not about what one
  key spans. Still absent: character offsets (`-k2.3,4.5`) and per-key option suffixes (`-k2,2n`).
- **1.8.2 — Size limits.** The byte-suffix parser (`5K`, `1M`, `1G`) serving `head -c 1K`,
  `tail -c 1K` and `sort -S`; `head -n -N` / `-c -N` (all-but-last); `tail` `+N` start-from-line,
  `-F` retry, and multi-file `-f` (single-file is enforced today, not merely absent); `sort`'s
  external-sort fallback above the 256 MiB cap, with `-T DIR`.
- **1.8.4 — `date` output flags and specifiers.** ⚠ Distinct from 1.8.3, which is date *input*.
  `-r FILE` (format FILE's mtime rather than now — `touch -r` already ships the reference-stat
  pattern to copy), `-R` (RFC 5322) and `-I[=FMT]` (ISO 8601), plus the strftime specifiers `date`
  refuses by name today: `%V`/`%G`/`%g` (ISO week-date), and the rest of `_date_is_deferred_spec`.
  ⚠ Most want no locale data and no tzfile — they are arithmetic on a broken-down time — so they do
  **not** belong behind the Gated chrono item the way local time does.
- **1.8.3 — Date input.** `date -d STR` and `touch -d STR`, free-form. ⚠ Genuinely large — GNU's
  parser is notorious, and chrono's `dt_strptime` needs a format string so it does not substitute.
  Scope it to a documented subset (ISO 8601, `@epoch`, `now`, `HH:MM[:SS]`) rather than chasing GNU.

---

## 1.9.x — Performance

The named gaps in [`docs/benchmarks.md`](../benchmarks.md), each with a measured cost.

- **`wc -c` fast path** — detect a regular-file fd and return `st_size` without reading. ~20 LOC,
  closes a 200× gap.
- **`tail` seek-from-end** — `lseek(SEEK_END)` + backward scan in 8 KiB chunks for seekable input.
  Removes the 16 MiB cap and closes most of a 12× gap.
- **niyama regex memory + speed** — ⚠ upstream Cyrius. ⛔ **This is still a crash, not just a slow
  path:** `grep 'line.*005'` over 13.6 MB segfaults under `ulimit -v 1048576`, because the NFA retains
  roughly 320 bytes per input byte. 1.2.6 fixed the half that needed no upstream — metacharacter-free
  patterns now take the byte scanner (6.7 s → 115 ms, no crash) — but any pattern with a
  metacharacter still compiles an NFA and still blows up. A literal Boyer-Moore path would also close
  the remaining ~23× gap on the fast path.
- **`cp` `copy_file_range(2)`** — accelerated copy with reflink where the filesystem supports it.
  Speculative; check AGNOS kernel availability before committing.
- **`find` predicate JIT** — compile the predicate AST to a flat eval loop. ⚠ Not committed; revisit
  only if benchmark pressure rises after the consumer burn.

---

## Gated — not on the arc sequence

These are open, but their trigger is outside kriya.

### M10 — Consumer-burn (closes the last v1.0 criterion)

The only unchecked v1.0 criterion: one downstream consumer green. **Trigger sequence:**

1. AGNOS USB-keyboard-on-boot resolves (tracked at agnos, out of kriya scope).
2. AGNOS coreutils integration — kriya symlinks in the init userland, agnoshi `$PATH` resolving to
   them.
3. First green boot-burn with kriya in init.
4. Incident log at `docs/audit/<date>-consumer-burn.md`.
5. Release checkboxing the criterion.

⭐ **Boot-burn is a parallel signal, not a blocking gate.** What it will tell us: which utilities early
boot actually hits, whether the [ADR-0003](../adr/0003-symlink-follow-policy.md)/0004/0005 policies hold up in practice, whether cold start
matters in aggregate over a real init sequence, and **which deferred features to promote** based on
real script usage rather than guesswork. That last one may resequence every arc above.

### M11 — Cyrius proposal sweeps

Gated on upstream acceptance, not kriya work. The first two were filed 2026-05-17 and are both
zero-behaviour-change; the third is a correctness gap and is not filed yet.

- **`2026-05-17-octal-literal-syntax`** — sweep decimal POSIX-mode constants (`511 # 0o777`) back to
  octal. Files: `mkdir.cyr`, `touch.cyr`, `fs.cyr`, `protected.cyr`.
- **`2026-05-17-syscalls-at-family-stdlib`** — sweep raw `syscall(N, …)` sites to named `sys_*at`
  wrappers. Files: `touch.cyr`, `ln.cyr`, `fs.cyr`. ⚠ Re-verified at pin 6.5.35: still absent, so the
  gate is real.
- **niyama BRE is missing the GNU operators** — ⛔ NOT YET FILED, unlike the two above; filing it is
  the next step. `\+` `\?` `\|` `\b` `\B` `\w` `\W` `\s` `\S` all compile clean and then match
  NOTHING. ⚠ The failure mode is a WRONG ANSWER, not an error: `kriya grep -c 'a\+b'` returns 0
  where GNU returns 3. Measured at pin 6.5.35; `\<` `\>` `\{n,m\}` `\(…\)` `[[:class:]]` do work.
  `nl -b pBRE` (1.4.4) REFUSES these operators rather than mis-number lines; `grep` and `find -regex`
  still accept them and return the wrong answer silently. ⛔ **Re-measured at 1.4.5 and the asymmetry
  is now INSIDE one binary**: the identical pattern is a loud exit-2 in `nl` and a silent wrong count
  in `grep`. On the fixture `abc/A1/foo bar/aa/aA`, `grep '\w'` `'\W'` `'\s'` `'\S'` `'\B'` `'a\+'`
  `'a\?'` `'a\|b'` all return 0 matches where GNU returns 1-5, and `grep '\b'` returns **exit 0 with
  a count of 2 where GNU says 5** — a wrong answer that does not even signal no-match. ⚠ Deliberately
  left out of 1.4.5, whose scope was bracket expressions: this is the regex-OPERATOR surface, it
  predates that release, and the real fix is upstream. ⭐ If it is closed in kriya first, lift
  `src/cmd/nl.cyr:_nl_rx_unsupported` into a shared lib so all three utilities read one list —
  do NOT copy it. Closing it upstream deletes the guard rather than growing it.

- **stdlib `getenv` silently misses variables past 8 KB** — ⚠ upstream Cyrius. ⭐ **WORKED AROUND
  kriya-side at 1.5.2** by `src/lib/env.cyr`, which reads `/proc/self/environ` into a HEAP buffer with
  no window and delegates to the stdlib on agnos; all five kriya call sites now use it. Still worth
  filing upstream, since every other Cyrius program has the same cliff. What follows is the original
  finding, kept because it is the evidence: `io.cyr` reads `/proc/self/environ` into an
  8 KB buffer and scans only what fits (agnos instead caps at 256 envp entries). Demonstrated with
  kriya's existing `COLUMNS` read, 40 directories, a 9 KB variable:
  `env COLUMNS=80 BIG=<9KB> kriya ls` columns correctly, `env BIG=<9KB> COLUMNS=80 kriya ls`
  degrades to one-per-line, and `/usr/bin/ls -C -w 80` under the same environment columns fine.
  ⛔ The failure is SILENT and POSITION-DEPENDENT — the same command works or does not depending on
  where the shell placed an unrelated variable. ⚠ It gates `ls --color` (1.5.2), because a real
  `LS_COLORS` is ~1.9 KB; and it already affects `COLUMNS` today. Not filed upstream yet.

⛔ **Related and NOT gated: kriya has 46 raw numeric syscalls, and every number is x86_64-only.**
Found at 1.3.3 while resolving cyrlint's raw-`getdents` note. The numbers genuinely differ:
`openat` 257 vs **56**, `mkdirat` 258 vs **34**, `unlinkat` 263 vs **35**, `write` 1 vs **64**,
`exit` 60 vs **93**, `fcntl` 72 vs **25**, `getdents64` 217 vs **61** (x86_64 vs aarch64). ⚠ Not a
bug today — kriya builds x86_64 Linux and agnos only — but **an aarch64 Linux build would compile
clean and call entirely wrong syscalls**, which is the worst failure shape available. The stdlib
already defines the named constants per target (`syscalls_aarch64_linux.cyr`), so the sweep is
mechanical; do it as one reviewable pass, not opportunistically. `k_getdents` was converted at 1.3.3
as the worked example.

⚠ **Do not "fix" `k_getdents` by switching to stdlib `io.cyr`'s `xgetdents`**, which is what cyrlint
suggests. `xgetdents` returns the RAW agnos record on agnos; `k_getdents` translates it into
`linux_dirent64` so every caller sees one format. The swap would silently mis-parse every directory
entry on agnos. The reason is now written at the call site.

### M14 — stdlib `getenv` post-fork bug

`find` and `xargs` cache PATH at startup to work around a stack-vs-syscall clobber in `getenv`'s 8 KB
stack buffer. When upstream fixes it, the workaround comes out. Pure cleanup, zero behaviour change.

### Upstream chrono — local time

`date` local-time and `ls -l` locale-aware mtime need tzfile parsing (`chrono_tz.cyr`). ⚠ This is the
**genuine** chrono gate — verified absent at pin 6.5.35 — and the trigger [ADR 0007](../adr/0007-date-utc-only-at-v0-7-0.md) already names.

### M16 — AGNOS as a build target (design-first)

Make kriya the sovereign, **shell-independent** coreutils for AGNOS — the canonical home for the FS tools (any shell execs it, the Unix way; agnsh's 1.4.2 builtin verbs are a shell-bound convenience that this supersedes once 1.43.x `execwait` lands). **Prep done:** pin 5.11.61 → 6.0.56, lib re-vendored, VERSION → 1.1.0.

**Why it's a real refactor (not a gate-the-blockers port like bannermanor/commandress):** kriya hardcodes **Linux syscall numbers** (`syscall(82,…)`=rename, `217`=getdents64, `257`=openat — ~610 numeric-syscall sites) instead of the target-aware `SYS_*` constants, parses **Linux `getdents64`/`stat` struct formats** (the sovereign agnos formats differ — see `agnos-userland-abi.md` §4.1/§4.2), and uses modern **`*at` syscalls** (openat/renameat/linkat/newfstatat/utimensat) that agnos doesn't define (agnos has the basic forms with different numbers + the explicit-length ABI).

**Plan:** make the central `src/lib/fs.cyr` syscall layer target-aware (`#ifdef CYRIUS_TARGET_AGNOS`: agnos numbers + sovereign dirent/stat structs + `*at`→basic mapping; Linux path unchanged) — most commands flow through it, so it's the leverage point. Then gate the per-command stragglers: `ln` (linkat/newfstatat), `touch` (utimensat → degrade timestamps), `tail` (lseek → degrade), `pwd` + path resolution (getcwd → degrade; CWD is userland-owned on agnos), `rm`/`cp`/`mv` (TTY `ioctl` TCGETS → non-interactive). Validate with `cyrius build --agnos` per command + the Linux `.tcyr` regression. Analogous to the agnosys-core repair, scaled to the coreutils FS surface.

---

## Standing

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

---

## Enabler map

What actually gates the arcs. Ship the enabler and everything under it becomes small.

| Enabler | Home | Unblocks | Status |
|---|---|---|---|
| Option pre-expansion | `src/lib/args.cyr` | clustering, attached values, `head -5` | ✅ 1.2.0 |
| Repeatable-option collector | `src/lib/args.cyr` | `grep -e`×N, `sort -k`×N, `grep --include/--exclude` | ✅ 1.2.1 (as `kriya_argv_collect`) |
| Spawn helper | `src/lib/spawn.cyr` | child stderr, `find -exec +`, `xargs -P`/`-p` | ✅ 1.2.2 |
| Duration parser | `src/lib/args.cyr` | `sleep` fractions + suffixes | ✅ 1.2.5 |
| Spec-renderer on `flags.cyr` | `src/lib/args.cyr` | `--help`, `--help=json`, `kriya --list` | 1.3.x |
| UTF-8 decoder | stdlib `unicode/_decode` (already vendored) | `cut -c`, `tr` fold, `uniq -i` multi-byte | 1.4.x |
| Shared glob matcher | lift `_f_glob_match` into `src/lib/` | `grep --include/--exclude`, `find -name` reuse | 1.4.x |
| passwd/group parser | new `src/lib/` module | `ls -l` names, `stat %U/%G`, `find -user/-group` | 1.5.x |
| Quoting helper | `src/lib/` | `stat %N`, `ls` quoting | 1.5.x |
| Comparator-by-flag indirection | `src/cmd/ls.cyr` | `ls -t`, `-S`, `--color` table | 1.5.x |
| Inode-set helper | `src/lib/fs.cyr` | `cp --preserve=links`, `du` hardlink dedup | 1.6.x |
| fd-anchored xattr API | `src/lib/fs.cyr` | `cp`/`mv` xattr preservation | 1.6.x |
| ARG_MAX argv chunking | `src/lib/` | `find -exec +`, `xargs -L`/`-x` | 1.7.x |
| Float formatting | `src/cmd/printf.cyr` | `printf %e/%f/%g/%a`, `seq -f` | 1.8.x |
| Byte-suffix parser | `src/lib/args.cyr` | `head -c 1K`, `tail -c 1K`, `sort -S` | 1.8.x |
| niyama regex memory + speed | **upstream** | `grep` on metacharacter patterns — still segfaults under a 1 GiB cap | 1.9.x, gated |
| chrono tzfile reader | **upstream** | `date` local time, `ls -l` locale mtime | gated |

---

## Out of scope

Fixed boundaries. A new utility that passes the [ADR-0006](../adr/0006-utility-scope-non-posix.md) four-criteria gate can land as a 1.x.y, but
the table below does not move.

- **Anything with a sovereign home** — `cat` (owl), `vim` (cyim), `git` (sit), `htop` (chakshu),
  shell builtins (agnoshi).
- **Archive** (`tar`, `gzip`, `unzip`) — goes wherever sankoch extracts a sovereign archive CLI.
- **Networking** (`ping`, `curl`, `ssh`, `nc`, `wget`) — separate domain repos.
- **GPU / display / window management** — wrong layer.
- **Compiler tooling** — `awk` and `sed` are big enough to deserve their own repos; `make` is a build
  system.
- **Per-utility binaries** — explicit choice via ADR 0001; revisit only if dispatcher overhead
  exceeds budget.
- **Windows / non-Linux** — AGNOS-targeted.

## Splitting policy

If a single utility crosses **~400 LOC** or grows a non-trivial dependency surface, propose extracting
it into its own repo. ⚠ Five already exceed it — `find` (1087), `grep` (1022), `ls` (906),
`sort` (726), `cp` (693) — and none has been split. The threshold is a **prompt to decide**, not an
automatic trigger: the multi-tool is the right home while they share `src/lib/`, and the question is
whether a given utility has stopped sharing. Revisit at each arc boundary.
