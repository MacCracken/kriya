# kriya — Roadmap

> **Open work only.** Anything shipped has been removed from this file — the record of what
> landed and why lives in [`CHANGELOG.md`](../../CHANGELOG.md) (per release) and
> [`state.md`](state.md) (current snapshot); what it taught lives in [`lessons.md`](lessons.md).
> This file answers one question: *what next, in what order, against what gate.*
>
> ⚠ **That promise had drifted by 1.6.6** — seven shipped milestones and three closed arcs were
> still here, carrying their own retrospectives, while four open items sat under `✅ CLOSED`
> headings with no version to ship in. Cleaned up at 1.6.6: every item below now names a release
> it can land in, and `scripts/lint-deferrals.sh` scans `scripts/` and `tests/` as well as `src/`
> so a source comment can no longer cite a version that has already gone by.

## How this file is organised

Three sections, each answering a different question:

| Section | Answers | Use it when |
|---|---|---|
| **Arcs** (1.6.x → 1.9.x) | *What ships next?* | Picking up work |
| **Non-goals** | *Why will this never ship?* | Before re-adding something that looks missing |
| **Gated** | *Why isn't this moving?* | Asking why an item never appears in an arc |
| **Standing** | *What must I re-check every time?* | Bumping the toolchain pin |

⭐ **Two companion files, and neither belongs here.** [`lessons.md`](lessons.md) holds the durable
process knowledge — what has already cost time and how not to pay it again, including the compiler
watchlist. [`CHANGELOG.md`](../../CHANGELOG.md) holds what landed and why. ⚠ **Every open item below
names a release it can land in.** An item with no version is how three of them ended up cited from
`src/` as `roadmap 1.5.4` and `roadmap 1.4.x` — versions that had already closed.

### A note on the M-numbers

Earlier revisions of this file tracked work as milestone buckets **M0–M17**, and `CHANGELOG.md`
entries reference them. Those numbers are **historical identifiers, not a live index** — the arcs
above are the running order now. Where a bucket is still open and still has a natural name, the
number is kept (**M10** consumer-burn, **M11** proposal sweeps, **M14** getenv, **M15** watchlist,
**M16** agnos target). The rest are shipped or dissolved into the arcs:

| Old bucket | Where it went |
|---|---|
| M0–M9 | shipped; see `CHANGELOG.md` |
| M12a (chrono) | 1.8.3 (`date -d`), 1.8.4 (ISO-week specifiers) + Gated (tzfile); the rest shipped in 1.2.5 |
| M12b (flags upgrade) | 1.2.0 (clustering, shipped) + 1.3.x (`--help`/`--list`) |
| M12c (stdlib helpers) | distributed across 1.4.x–1.6.x by enabler; `stat`'s unrendered specifiers are 1.6.10 |
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

| Arc | Theme | Enabler | Next up |
|---|---|---|---|
| **1.6.x** | File-op completeness, then the parity leftovers | inode-set ✅, xattr API ✅, backup helper ✅, one error line ✅ | **1.6.7** — `sleep` under interruption |
| **1.7.x** | Traversal, exec & FS reporting | spawn helper ✅, ARG_MAX chunking | ready |
| **1.8.x** | Parsers & numerics | float formatting, byte-suffix parser | ready |
| **1.9.x** | Performance | niyama literal fast path (upstream, partial) | partly gated |

⭐ **1.3.x (discoverability), 1.4.x (pattern & text parity) and 1.5.x (identity & listing) are
closed** — 1.3.8, 1.4.5 and 1.5.3. What each shipped is in `CHANGELOG.md`; what each taught is in
`lessons.md`; the handful of items they closed *without* is pinned above at 1.6.9–1.6.11. ⚠ All five
things kriya owed agnoshi shipped at 1.3.8; that consumer is blocked only on agnoshi gaining
interactive input.

No arc depends on another — they are independent and can be resequenced by consumer demand. The
order below reflects **who is waiting**: 1.3.x first because agnoshi has a named, external need for
it.

⚠ **The 1.2.x correctness arc closed at 1.2.6.** Everything below is new capability rather than
defect repair, which is a different kind of risk: these change what kriya *does*, not what it gets
wrong. Expect more ADRs and more GNU-comparison work per item than 1.2.x needed.

---

## 1.6.x — File-op completeness, then the parity leftovers

**Enablers:** an inode-set helper in `src/lib/fs.cyr` ✅ (1.6.0), an fd-anchored xattr API ✅ (1.6.1),
a shared backup helper ✅ (1.6.5) and one error-line implementation ✅ (1.6.6). ⚠ The M8 security
audit named the safe xattr pattern in advance and it was followed rather than reinvented —
`fgetxattr`/`fsetxattr` on the two descriptors, never a path.

⚠ **1.6.9 onward are the leftovers of the closed 1.4.x and 1.5.x arcs**, re-homed here at 1.6.6
because they were sitting under `✅ CLOSED` headings with no version to ship in — which is how three
of them ended up cited from `src/` as `roadmap 1.5.4` and `roadmap 1.4.x`, versions that can never
arrive. Every open item now names a release it can land in.

- **1.6.8 — `ls -C`, and `-w` as a width-only flag.**
    ⚠ **`ls` has no `-C`, and `-w` forces columns off a tty where GNU's does not.** 1.6.5 stopped
    `$COLUMNS` from choosing the output format (ADR 0017) and left `-w` alone, because `-w` is
    currently the only way to ask for columns off a tty and removing that without adding `-C` would
    delete the capability. Add `-C`, then make `-w` a width-only flag as GNU has it. The divergence
    is asserted in `smoke-ls.sh` today, so the change is a test edit.

- **1.6.9 — `cp` mode-restore parity.** GNU withholds the group and other WRITE bits on directories
  during a recursive copy and adds them back unconditionally at the end; kriya has no such restore,
  so a `cp -R` into a directory tree can leave modes that GNU would have repaired. ⚠ Measured and
  documented at `src/cmd/cp.cyr`'s `_cp_create_mode`, which points here. Small, and it interacts with
  `--preserve=mode` — decide the ordering before writing it.

- **1.6.10 — `ls` / `stat` output fidelity** (the leftovers, roughly in priority order). Small,
  well-bounded, and none of it blocks another arc:
  - **`ls -d` with no operand lists the directory's CONTENTS**; GNU lists `.`. Pre-existing (confirmed
    against the 1.4.4 binary), small and clearly wrong. ⚠ It needs a test that would have caught it,
    not just the fix.
  - ⛔ **Multi-column padding uses spaces where GNU uses a TAB** — the LAST known `ls` output
    divergence on a terminal. Column POSITIONS are identical, so only a byte-exact tty comparison sees
    it, which is why every piped smoke comparison passed. ⚠ GNU's own rule switches on whether colour
    is active, so the two interact.
  - **`no=` positions its colour prefix at the START OF THE LINE** — before the `-l` columns and before
    the `-i` inode — where kriya emits it before the NAME. 140 of 2,500 pathological comparisons and
    **zero** on realistic input, because a real `dircolors -b` never emits `no=`. Closing it means
    moving the prefix from the name to the line.
  - **A 0.17% quoting residual** over a 3,000-name hostile fuzz: names combining a `'` with escaped
    bytes in particular positions, where GNU emits a leading empty `''` kriya does not. ⛔ In at least
    one of those GNU's own output does not round-trip (`'\t'` reads as backslash-t). Worth revisiting
    only if a consumer hits it.
  - **An unknown two-letter `LS_COLORS` key is IGNORED where GNU errors.** GNU prints
    `ls: unrecognized prefix: 'zz'` and disables colour ENTIRELY; kriya skips the item and colours the
    rest. ⚠ Decide which is right before changing it — refusing the whole variable because one key is
    unknown is arguably worse for a user whose `dircolors` is newer than their `ls`.
  - **`stat %w`** — file BIRTH time, the last specifier kriya knows about and does not render. Needs
    `statx(2)`, which is a raw syscall on this target (**M11**'s at-family sweep is the natural place
    to add it). ⚠ Not every filesystem records it; GNU prints `-` when it is unavailable.
  - **`--quoting-style` accepts only the three styles kriya implements** — `literal`, `shell-escape`,
    `shell-escape-always`. `shell`, `c`, `escape`, `locale` and `clocale` are REFUSED by name. Adding
    them is small and well-bounded.
  - **`--quoting-style` accepts only the three styles kriya implements.** `shell`, `c`, `escape`,
    `locale` and `clocale` are REFUSED by name. Small and well-bounded. (`src/cmd/ls.cyr` points
    here.)

- **1.6.11 — `grep` parity leftovers.** Four items the 1.4.x arc closed without: two deliberate
  omissions and two divergences its own fuzz found.
  - **`grep -NUM` shorthand.** ⚠ Left out of 1.4.0 deliberately: `grep -3` for `-C 3` needs a
    bare `-DIGIT` to parse as an OPTION rather than an operand, and `grep` goes through the shared
    parser where a digit is not a registered short. `seq` solves the same problem with a dedicated argv
    walk (`_seq_token_is_negnum`); lifting that into `src/lib/args.cyr` would serve both. ⛔ Do not
    special-case it inside `grep` — that is the second-source-of-truth shape the 1.3.x arc spent nine
    releases removing.
  - **`grep --exclude-dir`.** ⚠ Deliberately not in 1.4.1. `--exclude` does NOT prune
    directories (measured against GNU: a directory matching `--exclude` is still descended), so
    `--exclude-dir` is a genuinely separate flag with its own subject — the directory name during
    descent — rather than a variation on the file filter now shipped. ⭐ The ordered
    rightmost-wins/first-option-default machinery in `_gr_name_allowed` is the part to reuse; the
    matcher (`src/lib/glob.cyr`) is already shared.
  - ⛔ **Two divergences found by 1.4.5's fuzz and NOT fixed there** — both predate it, both sit
    in paths that release did not touch, and neither is about `-i`:
    - **A leading `*` in an ERE.** `grep -E '*'` (and `'*a'`, `'a**'`) is a LITERAL asterisk in GNU and
      a usage error in kriya. ⚠ Check POSIX before matching GNU: a leading `*` in an ERE is undefined
      by the standard, so this may be a deliberate divergence rather than a bug — decide, then record
      the decision either way.
    - **`grep -o` emits empty matches.** `grep -o 'x*'` on `abc` prints four empty lines in kriya and
      nothing in GNU. ⚠ Related but distinct: kriya's `-o` also disagrees with GNU on a case-gap range
      under `-i`, and there kriya is the CORRECT one — GNU's `-o` contradicts GNU's own line matcher
      (1.4.5). Do not "fix" that second case toward GNU.

- **1.6.12 — 128 operands is a REFUSAL now, and it should be a non-issue.** ⛔ 1.6.3 turned the
  stdlib flag table's silent truncation into an honest error, because `kriya rm *` on 200 files was
  deleting 128 and exiting 0. ⚠ **A refusal is the safe stopgap, not the destination**: `rm *` on a
  directory with 200 files is an ordinary thing to do, GNU has no such limit, and kriya now says no.
  - The cap is `FLAGS_POS_MAX = 128` in `lib/flags.cyr`, which is UPSTREAM and stays upstream.
  - The kriya-side fix is to stop routing operands through the flag table at all — parse options
    from the expanded argv (which `kriya_args_parse` already builds) and let each utility iterate
    operands directly from argv, unbounded. ⚠ That touches every utility, which is why it is its own
    release and not a patch inside 1.6.3.
  - ⭐ Keep the overflow guard until then, and keep its `smoke-rm.sh` assertion afterwards: the test
    that says "200 operands must not silently become 128" stays true whichever way it is satisfied.

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
  ⚠ **Plus the sparse inode structure 1.6.0 deferred here**, which is what closes `du`'s last dedup
  divergence and cuts `du -L`'s memory. GNU's device-inode set costs about **one bit per counted
  file** — 200,000 files measured at 20 KB, `/usr`'s 204,110 at 36 KB — where `fs_inoset_*` is a
  32-byte-per-entry hash. ⛔ `du` is also carrying a pre-existing, UNRELATED allocation problem that
  the same pass should measure: `_du_walk` bump-allocates a 4 KiB `getdents64` buffer per directory
  and a joined path per entry and frees neither, which is why `kriya du -s /usr` peaks at **68 MB
  against GNU's 7.7 MB** with the dedup switched off entirely. ⚠ That is the bigger number of the two
  and it predates 1.6.0.

- **1.7.4 — The aarch64 syscall-number sweep.** kriya's raw `syscall(N, …)` numbers are x86_64-only:
  `openat` 257 vs **56**, `mkdirat` 258 vs **34**, `unlinkat` 263 vs **35**, `write` 1 vs **64**,
  `exit` 60 vs **93**, `fcntl` 72 vs **25**, `getdents64` 217 vs **61**. ⚠ Not a bug today — kriya
  builds x86_64 Linux and agnos only — but an aarch64 Linux build would **compile clean and call
  entirely wrong syscalls**, which is the worst failure shape available. The stdlib already defines
  the named constants per target (`syscalls_aarch64_linux.cyr`), so the sweep is mechanical; do it as
  one reviewable pass, not opportunistically. `k_getdents` was converted at 1.3.3 as the worked
  example. ⛔ **Do not "fix" `k_getdents` by switching to stdlib `io.cyr`'s `xgetdents`**, which is
  what cyrlint suggests: `xgetdents` returns the RAW agnos record on agnos, while `k_getdents`
  translates it into `linux_dirent64` so every caller sees one format. The swap would silently
  mis-parse every directory entry on agnos. The reason is written at the call site.

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

- **1.9.0 — `wc -c` fast path** — detect a regular-file fd and return `st_size` without reading.
  ~20 LOC, closes a 200× gap.
- **1.9.1 — `tail` seek-from-end** — `lseek(SEEK_END)` + backward scan in 8 KiB chunks for seekable
  input. Removes the 16 MiB cap and closes most of a 12× gap. (`src/cmd/tail.cyr` points here.)
- **1.9.2 — niyama regex memory + speed** — ⚠ upstream Cyrius. ⛔ **This is still a crash, not just a slow
  path:** `grep 'line.*005'` over 13.6 MB segfaults under `ulimit -v 1048576`, because the NFA retains
  roughly 320 bytes per input byte. 1.2.6 fixed the half that needed no upstream — metacharacter-free
  patterns now take the byte scanner (6.7 s → 115 ms, no crash) — but any pattern with a
  metacharacter still compiles an NFA and still blows up. A literal Boyer-Moore path would also close
  the remaining ~23× gap on the fast path.
- **1.9.3 — `cp` `copy_file_range(2)`** — accelerated copy with reflink where the filesystem
  supports it. Speculative; check AGNOS kernel availability before committing.
- **1.9.4 — `find` predicate JIT** — compile the predicate AST to a flat eval loop. ⚠ Not committed;
  revisit only if benchmark pressure rises after the consumer burn.

---

## Non-goals — settled by measurement, do not re-open as unfinished work

⚠ These are not deferrals. Each was measured against GNU and decided; re-adding any of them to an
arc means re-opening a decision, which needs an ADR rather than a roadmap line.

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
- **Users who exist only in LDAP / SSSD / systemd-homed.** They have no line in `/etc/passwd` and
  resolve to numeric ids. Closing that means NSS, which means dynamic linking — a **No-Go** for a
  static tool, not a deferral.
- **UTF-8-locale quoting.** kriya is byte-oriented and escapes every high byte, matching GNU under
  `LC_ALL=C`; GNU under a UTF-8 locale renders valid multi-byte bare. More verbose, never wrong —
  the escaped form round-trips identically. Changing it means decoding UTF-8 in the quoter (the
  `cut`/`wc` precedent exists) and wants an ADR.
- **`QUOTING_STYLE`.** GNU lets it override the tty/pipe default in both directions; kriya declines
  it for the reason [ADR 0011](../adr/0011-echo-matches-the-non-xsi-binary-not-the-shell-builtin.md)
  gave for `echo`. Revisit only with an ADR.

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

⛔ **Related and NOT gated: kriya's raw syscall numbers are x86_64-only.** Pinned at **1.7.4** and
described under M16 — an aarch64 Linux build would compile clean and call entirely wrong syscalls.

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

### M16 — AGNOS as a build target ✅ DONE as a build; the CONSUMER is what is gated

⭐ **`cyrius build --agnos src/main.cyr` builds a complete kriya today** — 1,117,016 bytes at 1.6.6,
built by CI on every push alongside the host target. `src/lib/fs.cyr` carries 32 `CYRIUS_TARGET_AGNOS`
branches; the sovereign dirent/stat translation, the `*at`→basic mapping and the per-command
degradations all landed.

⚠ **This entry described that work as ahead of it for several releases after it shipped.** Its
"Why it's a real refactor" paragraph counted "~610 numeric-syscall sites" — there are **38 distinct
raw `syscall(N` numbers** in `src/` now, all behind the target-aware layer it proposed building. The
plan is done; the paragraph outlived it.

**What remains is not a build problem:** making kriya the sovereign, shell-independent coreutils for
AGNOS — kriya symlinks in the init userland, agnoshi `$PATH` resolving to them, and the first green
boot with kriya in init. ⛔ **That is M10, not this entry**, and it is gated on AGNOS's keyboard
work rather than on anything in this repo.

⚠ **One genuine portability gap survives and it is NOT agnos**: kriya's raw syscall numbers are
x86_64-only, so an **aarch64 Linux** build would compile clean and call entirely wrong syscalls
(`openat` 257 vs 56, `write` 1 vs 64, `exit` 60 vs 93). Not a bug today — kriya builds x86_64 Linux
and agnos only — but it is the worst failure shape available. The stdlib already defines the named
constants per target, so the sweep is mechanical; do it as one reviewable pass. `k_getdents` was
converted at 1.3.3 as the worked example. **Pinned at 1.7.4.**

---

## Standing

### The toolchain pin-bump checklist

⛔ **Run these, do not recall them.** M15d was recorded as "zero instances" for five releases while
four sat in `find.cyr`, because the status had been established by reading.

1. `cyrius.cyml` `[package].cyrius` — the source of truth, never the CI YAML.
2. **`cyrius lib sync --full`**, not `cyrius deps`. ⚠ `deps` resolves without re-vendoring, and the
   build then warns that bundled libs are behind the pin.
3. `python3 scripts/watchlist-scan.py` — M15a / M15c / M15d, exits non-zero on a hit.
4. Re-measure M15a's premise: a two-local probe must still give `|&b - &a|` = 8 / 32 / 144.
5. Build **both** targets, plus every `tests/*.tcyr` and `tests/*.fcyr` subset (M15e).
6. Full smoke suite, both lints, `vet`, fuzz under poison.

### The compiler watchlist

⭐ **Moved to [`lessons.md`](lessons.md) § The compiler watchlist** at 1.6.6. It is not a milestone
that closes and it is not open work — it is the standing list of ways the Cyrius compiler and kriya
interact badly, and it belongs with the other durable process knowledge. ⚠ **Re-run every detection
in it at each toolchain pin bump**; a pin move is exactly when a latent instance stops being latent.

---

## Enabler map

What actually gates the arcs. Ship the enabler and everything under it becomes small.

| Enabler | Home | Unblocks | Status |
|---|---|---|---|
| Option pre-expansion | `src/lib/args.cyr` | clustering, attached values, `head -5` | ✅ 1.2.0 |
| Repeatable-option collector | `src/lib/args.cyr` | `grep -e`×N, `sort -k`×N, `grep --include/--exclude` | ✅ 1.2.1 (as `kriya_argv_collect`) |
| Spawn helper | `src/lib/spawn.cyr` | child stderr, `find -exec +`, `xargs -P`/`-p` | ✅ 1.2.2 |
| Duration parser | `src/lib/args.cyr` | `sleep` fractions + suffixes | ✅ 1.2.5 |
| Spec-renderer on `flags.cyr` | `src/lib/args.cyr` | `--help`, `--help=json`, `kriya --list` | ✅ 1.3.x |
| UTF-8 decoder | stdlib `unicode/_decode` (already vendored) | `cut -c`, `tr` fold, `uniq -i` multi-byte | ✅ 1.4.x |
| Shared glob matcher | `src/lib/glob.cyr` | `grep --include/--exclude`, `find -name` reuse | ✅ 1.4.x |
| passwd/group parser | `src/lib/userdb.cyr` | `ls -l` names, `stat %U/%G`, `find -user/-group` | ✅ 1.5.x |
| Quoting helper | `src/lib/quote.cyr` | `stat %N`, `ls` quoting, **diagnostics** | ✅ 1.5.3, extended 1.6.6 |
| Comparator-by-flag indirection | `src/cmd/ls.cyr` | `ls -t`, `-S`, `--color` table | ✅ 1.5.x |
| `(st_dev, st_ino)` set | `src/lib/fs.cyr` (as `fs_inoset_*`) | `cp --preserve=links`, `du` dedup, `du -L` cycle detection | ✅ 1.6.0 |
| fd-anchored xattr API | `src/lib/fs.cyr` | `cp`/`mv` xattr preservation | ✅ 1.6.1 |
| Backup control helper | `src/lib/backup.cyr` | `-b`/`--backup`/`-S` for `cp`, `mv`, `ln` | ✅ 1.6.5 |
| One error-line implementation | `src/lib/report.cyr` | every diagnostic in every utility | ✅ 1.6.6 |
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
