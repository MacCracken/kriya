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
| **1.6.x** | GNU-parity leftovers and cleanup | — | **1.6.17** — `printf` and `stat` numbers |
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

- **1.6.17 — `printf` and `stat` numbers.** Measured at 1.6.16, which fixed the same defect —
  a decimal parser that wraps — everywhere else, and left these two because their number handling
  is a layer of its own:
  - ⛔ **A width or precision wraps past 2^64**: `printf %18446744073709551617d 5` prints `5`, and
    `stat -c %18446744073709551617n f` prints `f`. GNU fails both (glibc refuses a field past
    `INT_MAX`; `printf`'s `*` form says *invalid field width*). ⚠ Below the wrap it is a hang, not
    an answer: `printf %9223372036854775807d 5` never finishes, because `_pf_putc`, `_pf_pad` and
    `stat`'s `_st_pad` write ONE BYTE PER SYSTEM CALL — a width of 100,000,000 takes 50 s against
    GNU's 31 ms. `nl` had the same padding and 1.6.16 buffered it; these two want the same.
  - ⛔ **`%d`'s argument wraps too**: `printf %d 99999999999999999999` prints 7766279631452241919
    at exit 0, where GNU prints 9223372036854775807 with *Numerical result out of range* and exits
    1. `%d 9223372036854775808` prints a bare `-`, and `%u` / `%x` / `%o` of anything from 2^63
    up print NOTHING (`%u 18446744073709551615`), since `_pf_render_int_base` has no unsigned
    path.
  - **GNU's conversion diagnostics are missing**: `%d 5x` is *value not completely converted*,
    and `%d abc` or `%d ''` is *expected a numeric value* — each printed, each exit 1. kriya
    prints `5`, `0` and `0` at exit 0. `%d ' 5'` is 5 in GNU and 0 here.
  - ⚠ **Decide: a negative argument needs `--`.** `printf '%d\n' -5` is *bad option*, exit 2,
    by [ADR 0002](../adr/0002-option-parsing-humans-and-agents.md)'s rule for negative
    positionals — which `seq` is exempt from, and which protects nothing here: `printf` has no
    options but `--help` / `--version`, and POSIX and GNU both take every argument after FORMAT
    as data. `smoke-printf.sh` writes `--` today.
  - **`nl -i` and `-v` refuse a negative**, where GNU counts down and starts below zero
    (`nl -v -1` numbers from -1). The counter is an i64 already; the number emitter is not signed.

---

## 1.7.x — Traversal, exec, filesystem reporting & syscall portability

**Enabler:** ARG_MAX argv chunking, for 1.7.0. Everything here builds on the spawn helper
(`src/lib/spawn.cyr`).

- **1.7.0 — Batched exec.** `find -exec ... +` (ARG_MAX chunking) and `xargs -L N` / `-x` /
  `--show-limits`. All four are the same argv-accounting problem seen from two directions.
- **1.7.1 — `find` predicates.** `-prune`, `-depth` (DFS post-order), `-perm`, `-H` (operand-only
  follow — the one [ADR 0003](../adr/0003-symlink-follow-policy.md) mode still refused).
  - **`-uid` / `-gid` take `+N` and `-N`** in GNU (more than, less than), as `-mtime` and `-size`
    already do here through `_f_parse_signed_int`; kriya refuses them. And `-size Nw` (two-byte
    words) is GNU's too. Both measured at 1.6.16, when `-size` learned GNU's rounding.
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
- **1.7.4 — Raw syscalls to stdlib wrappers.** kriya issues **40 distinct raw `syscall(N, …)`
  numbers across 56 sites** (re-counted at 1.6.12), in x86-64 Linux numbering; 16 of those sites are
  the `*at()` family
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
  - ⚠ **Three of them have no wrapper to convert to.** 1.6.12 added `statx` (332; **291** on
    aarch64) for `stat %w`/`%W` and `getxattr` (191; **8** on aarch64) for `ls`'s `ca` colour, and
    1.6.16 `lgetxattr` (192; **9**) for `stat %C`, as `k_statx` / `k_getxattr` / `k_lgetxattr` in
    `src/lib/sys.cyr`; the 6.6.6 stdlib wraps none of them. Check both
    against cyrius's aarch64 translation table in the same `qemu-aarch64` run; upstream wrappers are
    the fix if either is missing. Both already decline with `-38` on agnos.
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
  - **`ls --time-style=+FORMAT` and the `TIME_STYLE` variable ride on the same renderer.** GNU
    formats `-l` dates with an arbitrary strftime string (`+%F`, and `+OLD<newline>NEW` for the two
    ages); kriya exits 2 naming this slot, and does not read `TIME_STYLE`, so that a half-working
    variable never silently drops a `+FORMAT` ([ADR 0020](../adr/0020-ls-long-format-dates-are-posix.md)).
    ⭐ `TIME_STYLE` passes [ADR 0017](../adr/0017-environment-variables-configure-features-the-caller-turned-on.md)'s
    test — it changes nothing without `-l` — so it lands with `+FORMAT`, not after it.
- **1.8.5 — Symbolic file modes.** `mkdir -m` takes only an octal mode
  (`kriya_parse_octal_mode`) and refuses every symbolic one, exit 2, where GNU takes all of them.
  Measured at 1.6.16 with umask 022: `u=rwx,go=` is 700, `a+w` 777, `o-rx` 772, `g+s` 2777, `=` 0,
  and `+t` **1755**. ⚠ That last one is the rule to get right: a clause with no `u`/`g`/`o`/`a`
  is filtered through the umask, and one that names them is not. The parser's doc comment used to
  promise this "in M3", a milestone that closed at v0.4.0 without it. ⚠ One parser, then its
  callers: `mkdir -m` today, and `install -m` / `chmod` if either is ever added.

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
  - **`head -n -N` wants the same backward scan.** Since 1.6.15 it holds the last N lines in memory
    for every input, which is right for a pipe and unnecessary for a regular file, whose last N
    lines can be found from the end the way GNU's `elide_tail_lines_seekable` does. `head -c -N`
    already uses the file size and holds nothing. (`src/cmd/head.cyr` points here.)
  - **And the pipe's ring buffer should serve `head` too.** `_head_elide`'s hold grows by doubling
    and the bump allocator never frees the buffer it outgrew, so a pipe under
    `head -c -30000000` peaks at **64 MB against GNU's 33 MB** (measured at 1.6.15) — about twice
    the held bytes. A ring sized to what is held is the fix, and it is the structure `tail` needs.
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
- **1.9.5 — Buffered output for the line utilities.** `nl` writes each line in five system calls
  (number, padding, separator, text, newline): **836 ms against GNU's 42 ms** on 500,000 lines,
  measured at 1.6.16. That release buffered `nl`'s padding, which had been one call PER BYTE (a
  20 MB `-w 1000000` run went 7,148 → 3 ms), but the per-line calls remain. `printf` and `stat`
  share the shape (roadmap 1.6.17 has their per-byte padding). One shared stdout buffer, flushed
  at exit and on a write error, serves all three.

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
- **GNU `stat`'s stray `s` after a flagged `%N` on a symlink.** With a `0`, `#`, `+`, space or `'`
  flag, GNU prints `%0N` of a link as `ln -> fs` — its own conversion character, appended to a
  format it assembled. kriya prints `ln -> f`. Measured on 9.4 and 9.11; `scripts/difffuzz-stat-format.py`
  tolerates exactly that byte and nothing else. ⛔ Do not "fix" this toward GNU.
- **Base-0 and saturating parses of `COLUMNS` and `TABSIZE`.** GNU reads both as C integers, so
  `TABSIZE=010` is 8 and `COLUMNS=0x50` is 80; kriya reads decimal, as
  [ADR 0019](../adr/0019-the-line-width-is-a-number-not-a-format.md) decided for `-w`, and warns on
  the rest.
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
- ⛔ **niyama is LEFTMOST-FIRST, where POSIX and GNU are leftmost-LONGEST.** It is a Pike VM that
  stops at the first alternative to match. Measured at 1.6.14: `grep -oE 'a|ab'` prints `a` where
  GNU prints `ab`, and `grep -oE 'x*|b'` loses the `b` because the empty alternative wins first.
  Before 1.6.14 it was a **wrong LINE SELECTION** too — `grep -xE 'a|ab'` rejected `ab`, and
  `grep -wE 'a|ab'` selected nothing — until `-x` and `-w` were built into the pattern
  (`_gr_compile`), which a Pike VM honours on every alternative. ⚠ What is left is `-o`'s extent
  inside ONE pattern. BRE has no alternation, and there the gap needs contrived repetition
  (`a*\(ab\)*`). `smoke-grep.sh` records the `-oE 'a|ab'` case as a gap, and it flips the day niyama
  is leftmost-longest.
- **niyama reads the POSIX-literal `*` wrongly and `\(^` as a literal.** `^*` came out "zero or more
  anchors" (every line), and `\(*a\)` was refused. kriya works around it in
  `icase_bre_literal_stars` since 1.6.14, for `grep`, `nl -b p` and `find -regex`: escaping exactly
  those stars, and hoisting a `^` that opens the leading groups. ⚠ A `^` opening a LATER group is
  POSIX's "may be an anchor": GNU makes it one and niyama a literal, so `x\(^a\)` matches `x^a` here
  and nothing under GNU. Closing that upstream deletes the workaround.
- **BRE backreferences** (`\(a\)\1`) are POSIX-required; kriya refuses them loudly (`bad pattern`,
  exit 2) where GNU matches. niyama's ADR 0009 took them out of its **v1** scope — a v1 decision,
  not a permanent one. ⚠ kriya's [ADR 0005](../adr/0005-regex-engine-niyama.md) says backreferences
  "are honored"; that is not true today. The loud refusal is the right failure until niyama lands
  them.

### Upstream chrono — local time

`date` local time, and local time in `ls -l` and `stat`'s dates, need tzfile parsing
(`chrono_tz.cyr`). ⚠ What is gated is the VALUE — every kriya time is UTC — not the spelling:
`ls -l` has printed POSIX's date form since 1.6.12
([ADR 0020](../adr/0020-ls-long-format-dates-are-posix.md)). ⚠ This is
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
| ARG_MAX argv chunking | `src/lib/` | `find -exec +`, `xargs -L` / `-x` | 1.7.0 |
| Float formatting | `src/cmd/printf.cyr` | `printf %e/%f/%g/%a`, `seq -f` | 1.8.0 |
| Byte-suffix parser | `src/lib/args.cyr` | `head -c 1K`, `tail -c 1K`, `sort -S` | 1.8.2 |
| niyama regex speed | **upstream** | `grep` on metacharacter patterns (~160× GNU) | 1.9.2, gated |
| niyama GNU BRE operators and backreferences | **upstream** | `grep`, `find -regex`, `nl -b p` | M11, gated |
| chrono tzfile reader | **upstream** | local time in `date`, `ls -l` and `stat` | gated |

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
lines at 1.6.12); the largest are `ls` (**2,201**, up from 1,479 at 1.6.11), `grep` (1,124), `cp`
(1,068) and `find` (956), and none has been split. The threshold is a **prompt to decide**, not an
automatic trigger: the multi-tool is the right home while they share `src/lib/`, and the question is
whether a given utility has stopped sharing.

⛔ **Decided 2026-09-22: no split-outs until AGNOS is running fully, and then only as time permits.**
Until then the threshold is recorded, not acted on — measure the figures at each arc boundary so the
eventual decision starts from numbers, but do not propose an extraction in a release. `ls` will be
first in line when it comes: 1.6.12's GNU output surface (dates, `--dired`, tab stops, nine quoting
styles, the full colour table) made it twice the next utility, and most of that growth is rendering
`src/lib/` does not share.
