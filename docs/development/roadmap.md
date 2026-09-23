# kriya — Roadmap

> **Open work only, and forward-facing.** Anything shipped is removed from this file — what landed
> and why lives in [`CHANGELOG.md`](../../CHANGELOG.md), the current snapshot in
> [`state.md`](state.md), and what it taught in [`lessons.md`](lessons.md). This file answers one
> question: *what next, in what order, against what gate.*
>
> ⚠ **Every open item names the release it can land in**, and source comments cite that slot as
> `roadmap X.Y.Z`. `scripts/lint-deferrals.sh` fails on a citation with no entry, so renumbering a
> slot means moving its citations in the same change.

## How this file is organised

| Section | Answers | Use it when |
|---|---|---|
| **Arcs** (1.6.x → 1.9.x) | *What ships next?* | Picking up work |
| **Non-goals** | *Why will this never ship?* | Before re-adding something that looks missing |
| **Gated** | *Why isn't this moving?* | Asking why an item is not in an arc |
| **Standing** | *What must I re-check every time?* | Bumping the toolchain pin |

The **Enabler map**, **Out of scope** and **Splitting policy** at the end are reference.

Two rules hold across the arcs:

- **An arc is defined by its enabler, not by its utility.** Most open work is blocked on a small
  number of shared capabilities (§ Enabler map). Shipping the enabler *is* the release; the features
  riding on it are the release notes, and one round of test work serves the whole batch.
- **⚠ Re-check a gate before planning around it — it has been wrong in both directions.** At 1.6.11,
  two of the three "upstream-gated" sweeps turned out to have been unblocked since June, and a
  performance item recorded as a crash no longer crashed. Every gate below was re-verified at pin
  6.6.6.

**M-numbers** (`M0`–`M17`) are historical milestone identifiers that `CHANGELOG.md` entries use.
Two are still live here — **M10** and **M11**, both under § Gated — and **M15** is the compiler
watchlist in [`lessons.md`](lessons.md). The rest are shipped or dissolved into the arcs.

## Arc sequence

| Arc | Theme | Open enabler | Next up |
|---|---|---|---|
| **1.6.x** | GNU-parity leftovers and cleanup | — | **1.6.12** — `ls` / `stat` output fidelity |
| **1.7.x** | Traversal, exec, filesystem reporting, syscall portability | ARG_MAX argv chunking | **1.7.0** — batched exec |
| **1.8.x** | Parsers & numerics | float formatting, byte-suffix parser | **1.8.0** — floats |
| **1.9.x** | Performance | niyama regex speed (upstream) | **1.9.0** — `wc -c` fast path |

No arc depends on another; they can be resequenced by consumer demand, and the M10 boot-burn
(§ Gated) is the signal most likely to do it. ⚠ **1.6.x is repair** — small, measured against GNU,
test-first. **1.7.x onward is new capability**, a different kind of risk: it changes what kriya
*does*, so expect an ADR and GNU-comparison work per item.

---

## 1.6.x — GNU-parity leftovers and cleanup

What the closed arcs and the release audits left open. One release per entry; every item was
measured against GNU when it was filed and re-confirmed open at 1.6.11.

- **1.6.12 — `ls` / `stat` output fidelity** (roughly in priority order). Small, well-bounded, and
  none of it blocks another arc:
  - **`ls -d` with no operand lists the directory's CONTENTS**; GNU lists `.`. Small and clearly
    wrong. ⚠ It needs a test that would have caught it, not just the fix.
  - ⛔ **`ls -l` omits the `total N` line entirely.** GNU prints `total 8` before a directory's
    entries — 1K blocks, and absent for a plain FILE operand. A script doing `ls -l | head -1` or
    counting lines gets a different answer.
  - ⚠ **The `-l` mtime format differs**: GNU writes `Aug 28 20:53` (and `Mon DD  YYYY` past six
    months), kriya writes `2026-08-29 03:53`. Distinct from
    [ADR 0007](../adr/0007-date-utc-only-at-v0-7-0.md)'s UTC-only decision, which is about the
    VALUE; this is the rendering. Decide whether to match GNU or keep ISO-8601 — and if the latter,
    record it, because it is currently neither chosen nor documented.
  - **GNU WARNS on an invalid `$COLUMNS` and kriya is silent.** `ls: ignoring invalid width in
    environment variable COLUMNS: 'abc'` — the fallback to 80 already matches; only the diagnostic
    is missing. ⚠ It is a NEW stderr shape (not the operand/message pair), so it has to answer to
    [architecture 001](../architecture/001-errno-message-policy.md) before it lands.
  - **`-g`, `-o`, `--full-time` and `--dired` are unimplemented.** All four imply LONG format and
    behave as ordinary last-wins members of the format group (measured), so `_ls_scan_format`
    already has the shape to hold them. ⚠ `-g` omits the OWNER column and `-o` the GROUP one — not
    synonyms, and the difference is invisible unless owner != group.
  - **`-T`/`--tabsize` is unimplemented.** The column separator hard-codes 8. ⚠ `-T 0` disables tab
    packing entirely, which is the same switch `-w 0` already flips internally.
  - **`--quoting-style` accepts only the three styles kriya implements** — `literal`,
    `shell-escape`, `shell-escape-always`. `shell`, `c`, `escape`, `locale` and `clocale` are
    REFUSED by name; adding them is small and well-bounded. (`src/cmd/ls.cyr` points here.)
  - **An unknown two-letter `LS_COLORS` key is IGNORED where GNU errors.** GNU prints
    `ls: unrecognized prefix: 'zz'` and disables colour ENTIRELY; kriya skips the item and colours
    the rest. ⚠ Decide which is right before changing it — refusing the whole variable because one
    key is unknown is arguably worse for a user whose `dircolors` is newer than their `ls`.
  - **`no=` positions its colour prefix at the START OF THE LINE** — before the `-l` columns and the
    `-i` inode — where kriya emits it before the NAME. 140 of 2,500 pathological comparisons and
    **zero** on realistic input, because a real `dircolors -b` never emits `no=`.
  - **A 0.17% quoting residual** over a 3,000-name hostile fuzz: names combining a `'` with escaped
    bytes in particular positions, where GNU emits a leading empty `''` kriya does not. ⛔ In at
    least one of those GNU's own output does not round-trip (`'\t'` reads as backslash-t). Worth
    revisiting only if a consumer hits it.
  - **`stat %w`** — file BIRTH time, the last specifier kriya knows about and does not render (it is
    refused by name today). Needs `statx(2)`, which the stdlib does not wrap at 6.6.6 — a raw syscall
    or an upstream wrapper. ⚠ Not every filesystem records it; GNU prints `-` then.

- **1.6.13 — `cp` completeness.** All measured against GNU while fixing the 1.6.9 mode protocol, and
  each a different mechanism:
  - ⛔ **`cp -R` cannot descend into a pre-existing destination subdirectory that has write and
    search but no READ** (0300, 0311, 0333). kriya opens every destination directory
    `O_RDONLY|O_DIRECTORY`, which needs the read bit; GNU only ever creates entries in it and needs
    write+search. GNU exits 0 with the file copied, kriya exits 1 with nothing copied. ⚠ The fix is
    an open-flags change on the hottest path in `cp -R` (an `O_PATH` descriptor is a valid `dirfd`
    but cannot be `fchmod`ed), so it wants its own measurement.
  - **`cp -f` has no unlink-and-retry.** GNU's `--force` removes a destination it cannot open for
    writing and creates it afresh; kriya reports EACCES and exits 1 (mode-0400 destination: GNU 0,
    kriya 1). ⚠ kriya's `-f` already unlinks an existing SYMLINK, so the gap is specifically the
    EACCES-on-open path for a regular file. ⚠ It DELETES a file the caller could not otherwise
    write — that deserves an ADR, not just a patch.
  - **`-a`, `--preserve=all` and `--no-preserve=` are unimplemented** — all three are refused by
    name, which is the right failure, but `-a` is the spelling most scripts reach for.

- **1.6.14 — `grep` parity leftovers.** Two deliberate omissions and two divergences a fuzz found:
  - **`grep -NUM` shorthand** (`grep -3` for `-C 3`) needs a bare `-DIGIT` to parse as an OPTION
    rather than an operand, and `grep` goes through the shared parser, where a digit is not a
    registered short. `seq` solves the same problem with a dedicated argv walk
    (`_seq_token_is_negnum`); lifting that into `src/lib/args.cyr` would serve both. ⛔ Do not
    special-case it inside `grep` — that is the second-source-of-truth shape.
  - **`grep --exclude-dir`.** `--exclude` does NOT prune directories (measured against GNU: a
    directory matching `--exclude` is still descended), so `--exclude-dir` is a genuinely separate
    flag whose subject is the directory name during descent. ⭐ The ordered
    rightmost-wins/first-option-default machinery in `_gr_name_allowed` is the part to reuse; the
    matcher (`src/lib/glob.cyr`) is already shared.
  - **A leading `*` in an ERE.** `grep -E '*'` (and `'*a'`, `'a**'`) is a LITERAL asterisk in GNU
    and a usage error in kriya. ⚠ Check POSIX before matching GNU: a leading `*` in an ERE is
    undefined by the standard, so this may be a deliberate divergence rather than a bug — decide,
    then record the decision either way.
  - ⛔ **`grep -o` emits empty matches.** `grep -o 'x*'` on `abc` prints empty lines in kriya and
    nothing in GNU. ⚠ Related but distinct: kriya's `-o` also disagrees with GNU on a case-gap range
    under `-i`, and there kriya is the CORRECT one — GNU's `-o` contradicts GNU's own line matcher.
    Do not "fix" that second case toward GNU.

- **1.6.15 — `head` / `tail` count forms.** All three are refusals today, never wrong answers:
  - **Negative counts**: `head -n -5` (all but the last five lines) and `head -c -3` are
    GNU-supported, and kriya requires a non-negative integer. The diagnostic already names the
    count; what is left is the feature — a single buffer plus a tail-like backward scan.
  - **`tail -n +N` / `-c +N`** (start FROM line or byte N) is unimplemented, same message.
  - **The obsolescent unit suffix `-5c` / `-5l`** is refused where GNU accepts it.

- **1.6.16 — cleanup, and the leftovers nothing else claims.**
  - **`xargs` treats an unrecognised numeric short as the COMMAND.** `echo hi | xargs -5 echo` is
    *invalid option* / exit 1 under GNU and `-5: command not found` / **exit 127** here. ⚠ 127 is
    "command not found", so a caller cannot tell a typo'd flag from a missing binary.
  - **The octal-literal sweep.** Cyrius has lexed `0o755` since **6.0.62** — the proposal kriya
    filed on 2026-05-17, archived upstream as done. Sweep the decimal POSIX-mode constants
    (`511  # 0o777`) back to octal across `mkdir.cyr`, `touch.cyr`, `cp.cyr`, `tee.cyr`, `fs.cyr`
    and `protected.cyr`, and correct the comments that still say Cyrius has no octal syntax
    (`src/cmd/mkdir.cyr`). Zero behaviour change; the smoke suite is the check.
  - **Retire `src/lib/env.cyr`, or decide to keep it.** It exists to route around the stdlib
    `getenv`'s 8 KB window, which cyrius 6.5.36 removed (heap buffer, read to EOF, cached once), and
    `find` and `xargs` cache PATH at startup to dodge a stack clobber in that same old buffer.
    ⚠ Not a drop-in swap: the stdlib copies every hit to a fresh heap buffer where `kriya_getenv`
    returns a pointer into its cached block. Pure cleanup either way.
  - **Four doc blocks in `src/lib/args.cyr` sit 100–190 lines above the functions they document**
    (`kriya_parse_nonneg_int`, `kriya_argv_collect`, `kriya_parse_octal_mode`).

---

## 1.7.x — Traversal, exec, filesystem reporting & syscall portability

**Enabler:** ARG_MAX argv chunking, for 1.7.0. Everything here builds on the spawn helper
(`src/lib/spawn.cyr`).

- **1.7.0 — Batched exec.** `find -exec ... +` (ARG_MAX chunking) and `xargs -L N` / `-x` /
  `--show-limits`. All four are the same argv-accounting problem seen from two directions.
- **1.7.1 — `find` predicates.** `-prune`, `-depth` (DFS post-order), `-perm`, `-H` (operand-only
  follow — the one [ADR 0003](../adr/0003-symlink-follow-policy.md) mode still refused).
- **1.7.2 — Destructive and parallel.** ⛔ `find -delete` **must inherit the
  [ADR-0004](../adr/0004-rm-refuses-root.md) `/` refusal and the
  [ADR-0010](../adr/0010-rm-refuses-a-trailing-slash-symlink-operand.md) trailing-slash-symlink
  refusal** — a second deletion path that does not is a hole in both. `xargs -P N` (job-table
  management) and `-p` (interactive prompt, which must honour ADR 0002's no-hang-on-non-tty rule).
- **1.7.3 — Usage reporting.** `du -x` (one-filesystem), `--exclude` / `--exclude-from`,
  `--inodes` and `-0`; `df -t TYPE` (POSIX-required); `env -S` split-string and `-C DIR`.
  - **The sparse inode set.** GNU's device-inode set costs about **one bit per counted file** —
    200,000 files measured at 20 KB, `/usr`'s 204,110 at 36 KB — where `fs_inoset_*` is a
    32-byte-per-entry hash. It closes `du`'s last dedup divergence and cuts `du -L`'s memory.
  - ⛔ **`du`'s walk never frees, and that is the bigger number.** `_du_walk` bump-allocates a
    4 KiB `getdents64` buffer per directory and a joined path per entry and frees neither, so
    `kriya du -s /usr` peaks at **68 MB against GNU's 7.7 MB** with dedup switched off entirely.
    Measure it in the same pass.
- **1.7.4 — Raw syscalls to stdlib wrappers.** kriya issues **38 distinct raw `syscall(N, …)`
  numbers across 54 sites**, in x86-64 Linux numbering; 16 of those sites are the `*at()` family
  (`openat` 257, `mkdirat` 258, `newfstatat` 262, `unlinkat` 263, `utimensat` 280, …). ⭐ **The
  wrappers kriya asked for exist**: the stdlib has exposed `sys_openat`, `sys_mkdirat`,
  `sys_fstatat`, `sys_unlinkat`, `sys_linkat`, `sys_renameat`, `sys_fchmodat`, `sys_fchownat`,
  `sys_utimensat` and `sys_execveat` since cyrius **6.1.3** — the at-family proposal filed on
  2026-05-17, archived upstream as done. Converting the sites removes the magic numbers and puts the
  per-target numbering where it belongs, in one reviewable pass.
  - ⚠ **Measure before scheduling it as a portability fix.** cyrius renumbers raw x86-64 syscalls
    per target (`ESYSXLAT`, `src/backend/aarch64/emit.cyr` in the cyrius repo), and its
    aarch64-Linux arm already maps at least `write` 1→64, `exit` 60→93, `fcntl` 72→25,
    `getdents64` 217→61 and `unlinkat` 263→35; 6.6.6 added `statfs` 137. `openat` and `mkdirat`
    were not checked. A `qemu-aarch64` run of the smoke suite says whether an aarch64 build is
    broken today or only hard to read.
  - ⚠ **agnos keeps its own arms.** The agnos syscall peer wraps only `sys_fchownat` of this set
    (plus the `stat` family), so kriya's `CYRIUS_TARGET_AGNOS` branches in `src/lib/sys.cyr` and
    `src/lib/fs.cyr` stay; the sweep is the Linux side.
  - ⛔ **Do not "fix" `k_getdents` by switching to stdlib `io.cyr`'s `xgetdents`**, which is what
    cyrlint suggests: `xgetdents` returns the RAW agnos record on agnos, while `k_getdents`
    translates it into `linux_dirent64` so every caller sees one format. The swap would silently
    mis-parse every directory entry on agnos. The reason is written at the call site.
  - **`df`'s private `DfStatfs` offset table** (`src/cmd/df.cyr`, commented *"Linux x86_64, 64-bit
    struct statfs64"*) becomes a shim over 6.6.6's per-OS `Statfs` enums and the `statfs_bsize`
    accessor. ⚠ An accessor, not a convenience: the field differs by OS, which is why a private
    table is the wrong long-term answer. The agnos `-38` decline stays.

---

## 1.8.x — Parsers & numerics

**Enablers:** a float-formatting story (1.8.0) and a byte-suffix parser in `src/lib/args.cyr`
(1.8.2).

- **1.8.0 — Floats.** `printf %e` / `%E` / `%f` / `%F` / `%g` / `%G` / `%a` / `%A` — refused by name
  today — plus positional `%N$s`. `seq -f FORMAT` rides directly on it.
- **1.8.1 — Sort keys.**
  - ⛔ **First, a wrong answer: a repeated `-k` keeps only the LAST key.** `sort -k2,2 -k1,1` sorts
    exactly as `sort -k1,1` does and exits 0, where GNU sorts by field 2 then field 1 (measured at
    1.6.11). Collect every `-k` with `kriya_argv_collect`, the collector `grep -e` already uses — or,
    if multi-key is not ready, refuse a second `-k` rather than drop it.
  - Key TYPES: `-h` (human-numeric), `-V` (version), `-g` (general-numeric), `-M` (month),
    `-d` (dictionary), `-i` (ignore-nonprinting), `-R` (shuffle), `-m` (merge pre-sorted).
  - Character offsets (`-k2.3,4.5`) and per-key option suffixes (`-k2,2n`).
- **1.8.2 — Size limits and follow modes.** The byte-suffix parser (`5K`, `1M`, `1G`) serving
  `head -c 1K`, `tail -c 1K` and `sort -S`; `tail -F` (follow by name, with retry), multi-file `-f`
  (refused today, not merely absent) and `--pid=PID`; `sort`'s external-sort fallback above the
  256 MiB cap, with `-T DIR`.
- **1.8.3 — Date input.** `date -d STR` and `touch -d STR`, free-form. ⚠ Genuinely large — GNU's
  parser is notorious, and chrono's `dt_strptime` needs a format string, so it does not substitute.
  Scope it to a documented subset (ISO 8601, `@epoch`, `now`, `HH:MM[:SS]`) rather than chasing GNU.
- **1.8.4 — `date` output flags and specifiers.** ⚠ Distinct from 1.8.3, which is date *input*.
  `-r FILE` (format FILE's mtime rather than now — `touch -r` already ships the reference-stat
  pattern to copy), `-R` (RFC 5322) and `-I[=FMT]` (ISO 8601), plus the strftime specifiers `date`
  refuses by name today: `%V` / `%G` / `%g` (ISO week-date) and the rest of `_date_is_deferred_spec`.
  ⚠ Most want no locale data and no tzfile — they are arithmetic on a broken-down time — so they do
  **not** belong behind the Gated chrono item the way local time does.

---

## 1.9.x — Performance

Gaps measured against GNU. The first three were re-measured at 1.6.11 on the release box; the
v0.8.0 table in [`docs/benchmarks.md`](../benchmarks.md) is older.

- **1.9.0 — `wc -c` fast path.** Detect a regular file and return `st_size` from `fstat` without
  reading it. Measured on a 141 MB file: **537 ms against GNU's 0.9 ms** — and the gap grows with
  the file, since kriya reads every byte.
- **1.9.1 — `tail` on large input.** ⛔ **Past 16 MiB, every 64 KiB read shifts the whole 16 MiB
  buffer left ONE BYTE AT A TIME** (`_tail_slurp`'s head-discard loop) — about 256 byte-moves per
  input byte. Measured: `tail -n 1` of a 141 MB file takes **68 s against GNU's 0.7 ms**. Two
  fixes, and both are needed: seek from the end for seekable input (which also lifts the 16 MiB cap
  for regular files), and a ring buffer for pipes, which cannot seek. (`src/cmd/tail.cyr` points
  here.)
- **1.9.2 — niyama regex speed** — ⚠ upstream Cyrius. ⭐ **The crash is gone**: at pin 6.6.6,
  `grep 'line.*005'` over the 13.6 MB fixture that used to segfault under `ulimit -v 1048576`
  completes in constant memory (~8 MB peak) with GNU's count. What remains is speed — **5.2 s
  against GNU's 33 ms** (~160×), and a bracket pattern 2.7 s against 7 ms. Literal patterns already
  take the byte scanner (119 ms against 6 ms); a Boyer-Moore path would close that too.
  ⚠ `smoke-grep.sh` pins only the literal path under the 1 GiB cap — pin the regex path as well, now
  that it passes.
- **1.9.3 — `cp` `copy_file_range(2)`** — accelerated copy with reflink where the filesystem
  supports it. Speculative; check AGNOS kernel availability before committing.
- **1.9.4 — `find` predicate JIT** — compile the predicate AST to a flat eval loop. ⚠ Not committed;
  revisit only if benchmark pressure rises after the consumer burn.

---

## Non-goals — settled, do not re-open as unfinished work

⚠ These are not deferrals. Each was measured or decided; re-adding one to an arc means re-opening a
decision, which needs an ADR rather than a roadmap line.

- ⛔ **Multibyte `tr` and `uniq -i`.** `tr` is byte-based in every GNU locale (`tr 'é' 'e'` on
  `café` yields `cafee`, because SET1 is two bytes) and `uniq -i` does not fold non-ASCII. kriya
  matches both. Changing either would **diverge from GNU and silently alter existing scripts**, so
  it is sovereign design needing its own ADR — not a gap.
- ⛔ **`nl -b pBRE` refuses niyama's missing GNU operators — the fix is upstream.** niyama compiles
  `\+ \? \| \b \B \w \W \s \S` clean and then matches nothing, so `nl` refuses them at parse time
  rather than number the wrong lines. The fix belongs to niyama (§ Gated, M11), and closing it there
  deletes `_nl_rx_unsupported` rather than growing it. ⚠ Do not re-implement these inside `nl`.
- **Users who exist only in LDAP / SSSD / systemd-homed.** They have no line in `/etc/passwd` and
  resolve to numeric ids. Closing that means NSS, which means dynamic linking — a **No-Go** for a
  static tool.
- **UTF-8-locale quoting.** kriya is byte-oriented and escapes every high byte, matching GNU under
  `LC_ALL=C`; GNU under a UTF-8 locale renders valid multi-byte bare. More verbose, never wrong —
  the escaped form round-trips identically. Changing it means decoding UTF-8 in the quoter (the
  `cut` / `wc` precedent exists) and wants an ADR. (`src/lib/quote.cyr` points here.)
- **`QUOTING_STYLE`, and `POSIXLY_CORRECT` as a switch.**
  [ADR 0017](../adr/0017-environment-variables-configure-features-the-caller-turned-on.md): an
  environment variable may configure a feature the caller turned on and may never turn one on. GNU
  lets `QUOTING_STYLE` override the tty/pipe default and `POSIXLY_CORRECT` change behaviour with no
  flag — `echo`'s escapes, `du`'s 512-byte blocks — and kriya declines both. Revisit only with an
  ADR.
- **`which`'s shell-state flags** — `--read-alias`, `--read-functions`, `--show-dot`,
  `--show-tilde`, `--skip-tilde`, `--skip-dot`, `--skip-functions`. Shell state belongs to agnoshi
  (CLAUDE.md scope boundaries), decided when `which` shipped (CHANGELOG `[0.4.0]`).

---

## Gated — not on the arc sequence

These are open, but their trigger is outside kriya. Each was re-verified at pin 6.6.6.

### M10 — Consumer-burn (closes the last v1.0 criterion)

The only unchecked v1.0 criterion: one downstream consumer green. **Trigger sequence:**

1. AGNOS USB-keyboard-on-boot resolves (tracked at agnos, out of kriya scope).
2. AGNOS coreutils integration — kriya symlinks in the init userland, agnoshi `$PATH` resolving to
   them.
3. First green boot-burn with kriya in init.
4. Incident log at `docs/audit/<date>-consumer-burn.md`.
5. Release checkboxing the criterion.

⭐ **Boot-burn is a parallel signal, not a blocking gate.** It will tell us which utilities early
boot actually hits, whether the [ADR-0003](../adr/0003-symlink-follow-policy.md)/0004/0005 policies
hold up in practice, whether cold start matters in aggregate over a real init sequence, and **which
features to promote** based on real script usage — which may resequence every arc above. The agnos
build itself is done and CI builds it on every push; what is gated is the consumer.

### M11 — niyama regex gaps (upstream)

Two regex-surface gaps whose fix belongs to niyama rather than kriya.

- **The GNU BRE operators** — `\+` `\?` `\|` `\b` `\B` `\w` `\W` `\s` `\S` compile clean in niyama
  and then match NOTHING. ⛔ **In `grep` and `find -regex` that is a WRONG ANSWER, not an error**:
  re-measured at pin 6.6.6 against GNU grep 3.12, `kriya grep -c` returns 0 for `a\+b`, `a\?b`,
  `a\|x`, `\w`, `\s` and `\bfoo` where GNU returns 1–4. `nl -b pBRE` REFUSES the same operators, so
  one pattern is a loud exit 2 in one utility and a silent wrong count in another. ⚠ **Not yet filed
  at niyama** — filing it is the next step; niyama's roadmap does not mention it. ⭐ If kriya closes
  it first by refusing in `grep` too, lift `src/cmd/nl.cyr:_nl_rx_unsupported` into a shared lib so
  every utility reads one list — do NOT copy it. Closing it upstream deletes the guard instead.
- **BRE backreferences** (`\(a\)\1`) are POSIX-required; kriya refuses them loudly (`bad pattern`,
  exit 2) where GNU matches. niyama's ADR 0009 took them out of its **v1** scope — a v1 decision,
  not a permanent one. ⚠ kriya's [ADR 0005](../adr/0005-regex-engine-niyama.md) says backreferences
  "are honored"; that is not true today. The loud refusal is the right failure until niyama lands
  them.

### Upstream chrono — local time

`date` local time and `ls -l` locale-aware mtime need tzfile parsing (`chrono_tz.cyr`). ⚠ This is
the **genuine** chrono gate — re-verified absent at pin 6.6.6 — and the trigger
[ADR 0007](../adr/0007-date-utc-only-at-v0-7-0.md) already names.

---

## Standing

### The toolchain pin-bump checklist

⛔ **Run these, do not recall them.** M15d was recorded as "zero instances" for five releases while
four sat in `find.cyr`, because the status had been established by reading.

1. `cyrius.cyml` `[package].cyrius` — the source of truth, never the CI YAML.
2. **`cyrius lib sync --full`**, not `cyrius deps`. ⚠ `deps` resolves without re-vendoring, and the
   build then warns that bundled libs are behind the pin. ⚠ `cyrius build` re-copies the modules
   `[deps].stdlib` DECLARES on every build and never the rest, so the undeclared bundled libs drift
   silently without `--full` — eleven had, by the 1.6.11 bump.
3. `python3 scripts/watchlist-scan.py` — M15a / M15c / M15d / M15i, exits non-zero on a hit.
4. Re-measure M15a's premise: a two-local probe must still give `|&b - &a|` = 8 / 32 / 144.
5. Build **both** targets, plus every `tests/*.tcyr` and `tests/*.fcyr` subset (M15e). ⛔ **Read the
   build output**: a `duplicate symbol` / `duplicate fn` warning is a collision with the stdlib (M15i),
   not noise — 1.6.7 to 1.6.10 shipped one that broke the stdlib `getenv`, unreached only by luck.
6. Full smoke suite, both lints, `vet`, fuzz under poison.
7. **Re-verify every gate in this file** (§ Gated, and each arc item citing upstream) — a pin bump
   is when an upstream blocker quietly disappears.

### The compiler watchlist

Lives in [`lessons.md`](lessons.md) § The compiler watchlist — the standing list of ways the Cyrius
compiler and kriya interact badly, M15a–M15i. ⚠ **Re-run every detection in it at each toolchain pin
bump**; a pin move is exactly when a latent instance stops being latent.

---

## Enabler map

What still gates the arcs. Ship the enabler and everything under it becomes small.

| Enabler | Home | Unblocks | Slot |
|---|---|---|---|
| Shared `-DIGIT` option walk | `src/lib/args.cyr`, lifted from `seq`'s `_seq_token_is_negnum` | `grep -NUM`; `seq` reuses it | 1.6.14 |
| ARG_MAX argv chunking | `src/lib/` | `find -exec +`, `xargs -L` / `-x` | 1.7.0 |
| Float formatting | `src/cmd/printf.cyr` | `printf %e/%f/%g/%a`, `seq -f` | 1.8.0 |
| Byte-suffix parser | `src/lib/args.cyr` | `head -c 1K`, `tail -c 1K`, `sort -S` | 1.8.2 |
| niyama regex speed | **upstream** | `grep` on metacharacter patterns (~160× GNU) | 1.9.2, gated |
| niyama GNU BRE operators and backreferences | **upstream** | `grep`, `find -regex`, `nl -b p` | M11, gated |
| chrono tzfile reader | **upstream** | `date` local time, `ls -l` locale mtime | gated |

---

## Out of scope

Fixed boundaries. A new utility that passes the [ADR-0006](../adr/0006-utility-scope-non-posix.md)
four-criteria gate can land as a 1.x.y, but the list below does not move.

- **Anything with a sovereign home** — `cat` (owl), `vim` (cyim), `git` (sit), `htop` (chakshu),
  shell builtins (agnoshi).
- **Archive** (`tar`, `gzip`, `unzip`) — goes wherever sankoch extracts a sovereign archive CLI.
- **Networking** (`ping`, `curl`, `ssh`, `nc`, `wget`) — separate domain repos.
- **GPU / display / window management** — wrong layer.
- **Compiler tooling** — `awk` and `sed` are big enough to deserve their own repos; `make` is a build
  system.
- **Per-utility binaries** — explicit choice via ADR 0001; revisit only if dispatcher overhead
  exceeds budget.
- **Windows / non-Linux** — AGNOS-targeted. ⚠ If that ever changes, the pin floor is **6.6.6**:
  before it, a PE `O_APPEND` overwrote from offset 0 and `O_TRUNC` left the old tail behind, which
  is `tee -a` and `tee` (`src/cmd/tee.cyr`) failing at the only two things they do.

## Splitting policy

If a single utility crosses **~400 lines of code** or grows a non-trivial dependency surface,
propose extracting it into its own repo. ⚠ **Fifteen already exceed it** (non-blank, non-comment
lines at 1.6.11); the largest are `ls` (1,479), `grep` (1,124), `cp` (1,068) and `find` (956), and
none has been split. The threshold is a **prompt to decide**, not an automatic trigger: the
multi-tool is the right home while they share `src/lib/`, and the question is whether a given
utility has stopped sharing. Revisit at each arc boundary.
