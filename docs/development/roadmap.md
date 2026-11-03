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
| **Arcs** (1.8.x → 1.10.x) | *What ships next?* | Picking up work |
| **Non-goals** | *Why will this never ship?* | Before re-adding something that looks missing |
| **Gated** | *Why isn't this moving?* | Asking why an item is not in an arc |
| **Standing** | *What must I re-check every time?* | Bumping the toolchain pin |

The **Enabler map**, **Out of scope** and **Splitting policy** at the end are reference.

Two rules hold across the arcs:

- **An arc is defined by its enabler, not by its utility.** Most open work is blocked on a small
  number of shared capabilities (§ Enabler map). Shipping the enabler *is* the release; the features
  riding on it are the release notes, and one round of test work serves the whole batch.
- **⚠ Re-check a gate before planning around it — it has been wrong in both directions**
  ([`lessons.md`](lessons.md)). Every gate below was re-verified at pin 6.7.18 (1.8.1).

**M-numbers** (`M0`–`M17`) are the milestone identifiers `CHANGELOG.md` entries use. Two are open,
**M10** and **M11**, both under § Gated, and **M15** is the compiler watchlist in
[`lessons.md`](lessons.md).

## Arc sequence

| Arc | Theme | Open enabler | Next up |
|---|---|---|---|
| **1.8.x** | Traversal, exec, filesystem reporting, syscall portability | — | **1.8.4** — raw syscalls to stdlib wrappers |
| **1.9.x** | Parsers & numerics | float formatting, byte-suffix parser | **1.9.0** — floats |
| **1.10.x** | Performance | niyama regex speed (upstream, filed) | **1.10.0** — `wc -c` fast path |

No arc depends on another; they can be resequenced by consumer demand, and the M10 boot-burn
(§ Gated) is the signal most likely to do it. ⚠ Every arc is **new capability**: it changes what
kriya *does*, so expect an ADR and GNU-comparison work per item.

> **Renumbered 2026-11-03, after 1.8.1.** Versions 1.7.2–1.8.1 shipped out of plan (aarch64 ABI fixes
> and three cyrius pin moves), so every open slot moved up one minor to continue from 1.8.2: the old
> **1.7.2–1.7.4 are 1.8.2–1.8.4**, the old **1.8.0–1.8.5 are 1.9.0–1.9.5**, and the old **1.9.0–1.9.6
> are 1.10.0–1.10.6**. A `CHANGELOG.md` entry from before then cites the old number.

---

## 1.8.x — Traversal, exec, filesystem reporting & syscall portability

Everything here builds on the spawn helper (`src/lib/spawn.cyr`) and the command-line builder
(`src/lib/argbatch.cyr`), which counts as GNU's `buildcmd` does
([ADR 0026](../adr/0026-batched-exec-counts-a-command-line-as-gnu-does.md)).

- **1.8.4 — Raw syscalls to stdlib wrappers.** **43 raw `syscall(N, …)` lines** remain in `src/`
  (37 distinct numbers, agnos arms included; counted at 1.8.1). None misroutes on aarch64 any
  more, since 1.7.2 converted the 24 that did, and `tests/kriya-syscalls.tcyr` pins that. What
  is left is two kinds of work:
  - **The aarch64 xattr declines, now unblocked.** Native aarch64 `fchown` 55, `setxattr` 5,
    `fsetxattr` 7, `lgetxattr` 9 and `fgetxattr` 10 are numbers cyrius renumbers as x86 calls, so
    1.7.2 made `k_fgetxattr`, `k_lgetxattr`, `k_setxattr` and `k_fsetxattr` return -38 there. Since
    cyrius **6.6.12** the stdlib wraps the whole family (`sys_{,l,f}{get,set,list,remove}xattr`,
    `sys_fchown`, `sys_statx`, `sys_getrlimit`; re-verified at 6.7.18). The aarch64 peer issues the
    renumbered ones through a private `1000+N` band (`SYS_GETXATTR = 1008`, `SYS_FCHOWN = 1055`,
    `SYS_STATX = 1291`), and the agnos peer answers -38. Converting `k_*xattr`, `k_fchown`,
    `k_statx` (`stat %w`/`%W`), `k_getxattr` (`ls`'s `ca` colour), `k_lgetxattr` (`stat %C`) and
    `argbatch`'s `getrlimit` ends the declines, and turns `tests/kriya-syscalls.tcyr`'s two aarch64
    `-38` assertions into real answers.
  - **The readability sweep**: the numbers cyrius DOES renumber, `*at()` family included
    (`openat` 257, `newfstatat` 262, `unlinkat` 263, `utimensat` 280, …). The stdlib has wrapped them
    since **6.1.3** (`sys_openat`, `sys_fstatat`, `sys_unlinkat`, `sys_utimensat`, …), and
    converting them puts the per-target numbering where it belongs, in one reviewable pass.
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
- **1.8.5 — Deep trees: a bounded descriptor budget for every `*at()` walk.** Each fd-relative walk
  holds one open directory per level. Under the default `ulimit -n 1024`, a tree deeper than **1,020**
  levels fails with *too many open files* and exits 1: `find` (since 1.8.2's fd-relative walk), `du` and
  `rm -r` all stop there. `cp -R` holds two descriptors per level (source and destination) and stops at
  **509**. GNU's `find`, `du` and `rm -r` (fts) have no depth limit and pass the probe's 2,600-level
  cap; GNU `cp -R` walks full paths and stops at PATH_MAX, 2,040. Measured at 1.8.3 in ubuntu:26.04,
  each on a fresh tree of exactly N single-letter levels. `du` at 1.8.2 stops at the same 1,020.
  - ⛔ **`rm -r` is the one that matters.** Anyone who can make a 1,021-level tree in a shared
    directory makes it unremovable by kriya's `rm`. `du` also prints a partial total after the error.
  - **GNU's answer is fts's.** A directory is read whole before its children are entered, so its
    descriptor is not needed again for reading, and fts keeps a small ring of descriptors. It
    re-enters a parent through `openat(child, "..")`, checked against the parent's recorded
    (dev, ino). ⛔ That check is the security half: a `..` that leads elsewhere (a directory moved
    mid-walk) must stop the walk, never continue it. It is the race the fd-relative walk was
    adopted to close ([ADR 0027](../adr/0027-find-delete-carries-rms-refusals.md)).
  - ⚠ **Raising the soft `RLIMIT_NOFILE` is not the fix.** The hard limit can equal the soft one,
    and an `-exec` child would inherit the raised limit.
  - The four walks are separate code (`find`'s `_f_walk`, `du`'s `_du_walk`, and `rm`'s and `cp`'s in
    `src/cmd/`), so the answer should be one shared descriptor policy, not four.

---

## 1.9.x — Parsers & numerics

**Enablers:** a float-formatting story (1.9.0) and a byte-suffix parser in `src/lib/args.cyr`
(1.9.2).


- **1.9.0 — Floats.** `printf %e` / `%E` / `%f` / `%F` / `%g` / `%G` / `%a` / `%A` — refused by name
  today — plus positional `%N$s`. `seq -f FORMAT` rides directly on it.
  - ⚠ **`%N$s` is GNU 9.11's, not 9.4's** (measured at 1.6.17: 9.4 says *invalid conversion
    specification*, as kriya does), so the container's GNU cannot be its oracle.
  - **GNU's `%q`** — the argument shell-quoted — is refused by name today. GNU uses
    `shell_escape_quoting_style`, which `src/lib/quote.cyr` already renders for `ls`; ⚠ except
    that `ls` never quotes an empty name, and `%q ''` is `''`.
  - **`find -mtime` and `-mmin` take fractions in GNU**, read with `xstrtod`: `-mtime 0.5`,
    `-mtime -0.5`, `-mmin -1.5` and `-mtime 1e1` all run there, and kriya refuses them as bad
    arguments. The float READER `printf %f` needs for its arguments is the one to use; measured at
    1.7.1.
- **1.9.1 — Sort keys.**
  - ⛔ **First, a wrong answer: a repeated `-k` keeps only the LAST key.** `sort -k2,2 -k1,1` sorts
    exactly as `sort -k1,1` does and exits 0, where GNU sorts by field 2 then field 1 (measured at
    1.6.11). Collect every `-k` with `kriya_argv_collect`, the collector `grep -e` already uses — or,
    if multi-key is not ready, refuse a second `-k` rather than drop it.
  - Key TYPES: `-h` (human-numeric), `-V` (version), `-g` (general-numeric), `-M` (month),
    `-d` (dictionary), `-i` (ignore-nonprinting), `-R` (shuffle), `-m` (merge pre-sorted).
  - Character offsets (`-k2.3,4.5`) and per-key option suffixes (`-k2,2n`).
- **1.9.2 — Size limits and follow modes.** The byte-suffix parser (`5K`, `1M`, `1G`) serving
  `head -c 1K`, `tail -c 1K` and `sort -S`; `tail -F` (follow by name, with retry), multi-file `-f`
  (refused today, not merely absent) and `--pid=PID`; `sort`'s external-sort fallback above the
  256 MiB cap, with `-T DIR`.
- **1.9.3 — Date input.** `date -d STR` and `touch -d STR`, free-form. ⚠ Genuinely large — GNU's
  parser is notorious, and chrono's `dt_strptime` needs a format string, so it does not substitute.
  Scope it to a documented subset (ISO 8601, `@epoch`, `now`, `HH:MM[:SS]`) rather than chasing GNU.
- **1.9.4 — `date` output flags and specifiers.** ⚠ Distinct from 1.9.3, which is date *input*.
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
- **1.9.5 — Symbolic file modes.** `mkdir -m` takes only an octal mode
  (`kriya_parse_octal_mode`) and refuses every symbolic one, exit 2, where GNU takes all of them.
  Measured at 1.6.16 with umask 022: `u=rwx,go=` is 700, `a+w` 777, `o-rx` 772, `g+s` 2777, `=` 0,
  and `+t` **1755**; at 1.7.1, `+w` 777 and `=rwx` 755.
  - ⭐ **The parser exists**: `src/lib/mode.cyr`, gnulib's `mode_compile` / `mode_adjust` ported for
    `find -perm` at 1.7.1 and fuzzed against GNU `find` over every mode. What is left is the caller.
  - ⚠ **`mode_adjust` is only half of GNU's answer.** From 0777 under umask 022 it gives `+t`
    01777, yet GNU's directory ends 1755; `+w` and `=rwx` start from the same 0777 and end 777 and
    755. mkdir(2) applies the umask again, and gnulib's `dirchownmod` then chmods back only some of
    what it cleared. ⛔ Read coreutils' `mkdir.c` and gnulib's `mkdir-p.c` / `dirchownmod.c` and
    port them; the eight answers above are the test, and no single "the umask filters X" rule
    produces all of them.
  - ⚠ One parser, then its callers: `mkdir -m` first, and `install -m` / `chmod` if either is ever
    added.

---

## 1.10.x — Performance

Gaps measured against GNU. The first three were re-measured at 1.6.11 on the release box; the
v0.8.0 table in [`docs/benchmarks.md`](../benchmarks.md) is older.

- **1.10.0 — `wc -c` fast path.** Detect a regular file and return `st_size` from `fstat` without
  reading it. Measured on a 141 MB file: **537 ms against GNU's 0.9 ms** — and the gap grows with
  the file, since kriya reads every byte.
- **1.10.1 — `tail` on large input.** ⛔ **Past 16 MiB, every 64 KiB read shifts the whole 16 MiB
  buffer left ONE BYTE AT A TIME** (`_tail_slurp`'s head-discard loop) — about 256 byte-moves per
  input byte. Measured: `tail -n 1` of a 141 MB file takes **68 s against GNU's 0.7 ms**. Two
  fixes, and both are needed: seek from the end for seekable input (which also lifts the 16 MiB cap
  for regular files), and a ring buffer for pipes, which cannot seek. (`src/cmd/tail.cyr` points
  here.)
  - **`head -n -N` wants the same backward scan.** It holds the last N lines in memory for every
    input, which is right for a pipe and unnecessary for a regular file, whose last N
    lines can be found from the end the way GNU's `elide_tail_lines_seekable` does. `head -c -N`
    already uses the file size and holds nothing. (`src/cmd/head.cyr` points here.)
  - **And the pipe's ring buffer should serve `head` too.** `_head_elide`'s hold grows by doubling
    and the bump allocator never frees the buffer it outgrew, so a pipe under
    `head -c -30000000` peaks at **64 MB against GNU's 33 MB** (measured at 1.6.15) — about twice
    the held bytes. A ring sized to what is held is the fix, and it is the structure `tail` needs.
- **1.10.2 — niyama regex speed** — ⚠ upstream Cyrius, **filed 2026-11-03**:
  [`2026-11-03-niyama-search-quadratic-in-line-length.md`](https://github.com/MacCracken/niyama/blob/main/docs/development/issues/2026-11-03-niyama-search-quadratic-in-line-length.md). ⛔ It is not a constant factor. `niyama_bre_search_at` and `niyama_re2_search_at` restart the
  Pike VM at every start offset, so search is O(L²) per line. `a.*b` over 8,000 `a`s takes 6.9 s, and
  every doubling quadruples it, in re2 too, whose ADR 0003 promises linear time. Re-measured at 6.7.18
  against GNU grep 3.12 over 15.9 MB: `line.*005` 6,149 ms against 40. `grep 'line.*005'` over a 13.6 MB fixture
  takes **5.2 s against GNU's 33 ms** (~160×), in constant memory, and a bracket pattern 2.7 s
  against 7 ms. Literal patterns take the byte scanner (119 ms against 6 ms); a Boyer-Moore path
  would close that too. ⚠ `smoke-grep.sh` pins only the literal path under the 1 GiB memory cap —
  pin the regex path as well.
- **1.10.3 — `cp` `copy_file_range(2)`** — accelerated copy with reflink where the filesystem
  supports it. Speculative; check AGNOS kernel availability before committing.
- **1.10.4 — `find` predicate JIT** — compile the predicate AST to a flat eval loop. ⚠ Not committed;
  revisit only if benchmark pressure rises after the consumer burn.
- **1.10.5 — Buffered output for the line utilities.** `nl` writes each line in five system calls
  (number, padding, separator, text, newline): **776 ms against GNU's 42 ms** on 500,000 lines,
  measured at 1.7.0. `printf` writes each literal byte of its FORMAT in its own call, and `stat`
  each literal character of its format; only their padding is buffered (`k_write_fill` in
  `src/lib/sys.cyr`). One shared stdout buffer, flushed at exit and on a write error, serves all
  three.
  - ⛔ **And it is where a stdout write error gets its name.** `kriya head -1 in.txt >/dev/full`
    says *in.txt: no space left on device*, blaming the INPUT; so do `tail`, and `tr` names
    `'(stdin)'`, and `sort` says `'(write)'`. GNU says *write error: No space left on device*
    (`sort`: *fflush failed: 'standard output'*). Measured at 1.7.1, and older than it; `cut`,
    `wc` and every utility the dispatcher's write net reports already say *write error*.
- **1.10.6 — `find` stats only what a test needs, and walks in constant memory.**
  - **The stat.** GNU asks fts for no stat (`FTS_NOSTAT`) and takes an entry's type from
    `d_type`, so a name-only walk stats nothing but directories. kriya stats every entry — the
    4.8× in `docs/benchmarks.md` is partly this — and it is visible as a DIFFERENT ANSWER in a
    readable directory that cannot be searched (chmod 600): GNU lists its entries, runs `-type f`
    on them from `d_type`, and reports only the subdirectory; kriya lists them too since 1.7.1, but
    reports every entry and cannot answer `-type` (`smoke-find.sh` pins the listing). Measured at
    1.7.1 by review.
  - **The memory.** Every entry's path and stat buffer, and a 4 KiB `getdents64` buffer per
    directory, are bump-allocated and never freed: `find /usr -name none` peaks at **99.0 MB
    against GNU's 8.5 MB** (202,664 entries), and at 150.2 MB under `-L` against 8.6 MB (measured at
    1.8.3). `du` had the same defect and 1.8.3 fixed it: a `getdents64` buffer per *depth*, reused by
    every directory at that depth, and one fts-style path buffer. That is the pattern to copy.
  - **The depth** is now roadmap 1.8.5's. Since 1.8.2's fd-relative walk, `find` stops at the
    descriptor limit (1,020 levels under `ulimit -n 1024`) instead of PATH_MAX (2,047 lines at
    1.7.1).

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

These are open, but their trigger is outside kriya. Each was re-verified at pin 6.7.18 (1.8.1).

⛔ **An upstream gate that is not FILED upstream is a gate nobody is working on.** Until 1.8.1 every
upstream gate here was recorded in this file alone. cyrius fixes what is filed, and niyama extends
"only if a consumer asks". niyama ADR 0009 even closed BRE backreferences because it had "no identified
bre consumer", twelve days before kriya's POSIX `grep` shipped. **Every upstream gate names its filing,
in the repo that owns the code.** cyrius's own stdlib (chrono, the syscall peers, the compiler) is filed
in cyrius `docs/development/issues/`. A FOLDED stdlib (niyama, sankoch, patra, sigil and the rest) is
filed in its own repo's `docs/development/issues/`: it is fixed and tagged there, and cyrius re-vendors
the fold byte-identical from the tag. A new upstream gate is filed in the same change that records it
here.

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
features to promote** based on real script usage — which may resequence every arc above. CI builds
the agnos target on every push; what is gated is the consumer.

### M11 — niyama regex gaps (upstream)

Regex-surface gaps whose fix belongs to niyama rather than kriya. niyama is a fold, fixed and tagged in its
own repo and re-vendored by cyrius from the tag, so each is **filed in niyama `docs/development/issues/`**
(2026-11-03). They share a repro, `repros/2026-11-03-niyama-posix-gaps.cyr`, that builds inside niyama
against its own `dist/niyama.cyr`.

- **The GNU BRE operators** — filed: [`2026-11-03-niyama-bre-gnu-operators-read-as-literals.md`](https://github.com/MacCracken/niyama/blob/main/docs/development/issues/2026-11-03-niyama-bre-gnu-operators-read-as-literals.md). `\+` `\?` `\|` `\b` `\B` `\w` `\W` `\s` `\S` compile clean in
  niyama and match the escaped character LITERALLY: `a\+b` matches `a+b` and not `aab`, `\w` matches `w`
  (measured at 6.7.18, calling niyama directly). ⛔ **In `grep` and `find -regex` that is a WRONG ANSWER, not an error**:
  re-measured at pin 6.6.6, at 6.7.9 and at 6.7.18 (niyama 1.1.0, unchanged since 6.7.9) against
  GNU grep 3.12, `kriya grep -c` returns 0 for `a\+b`, `a\?b`,
  `a\|x`, `\w`, `\s` and `\bfoo` where GNU returns 1–4. `nl -b pBRE` REFUSES the same operators, so
  one pattern is a loud exit 2 in one utility and a silent wrong count in another. ⭐ If kriya closes
  it first by refusing in `grep` too, lift `src/cmd/nl.cyr:_nl_rx_unsupported` into a shared lib so
  every utility reads one list — do NOT copy it. Closing it upstream deletes the guard instead.
- ⛔ **niyama is LEFTMOST-FIRST, where POSIX and GNU are leftmost-LONGEST** — filed: [`2026-11-03-niyama-leftmost-first-not-posix-leftmost-longest.md`](https://github.com/MacCracken/niyama/blob/main/docs/development/issues/2026-11-03-niyama-leftmost-first-not-posix-leftmost-longest.md). It is a Pike VM that
  stops at the first alternative to match. Measured at 1.6.14: `grep -oE 'a|ab'` prints `a` where
  GNU prints `ab`, and `grep -oE 'x*|b'` loses the `b` because the empty alternative wins first.
  Line selection is right — `-x` and `-w` are built into the pattern (`_gr_compile`), which a Pike
  VM honours on every alternative — so what is open is `-o`'s extent inside ONE pattern. BRE has no alternation, and there the gap needs contrived repetition
  (`a*\(ab\)*`). `smoke-grep.sh` records the `-oE 'a|ab'` case as a gap, and it flips the day niyama
  is leftmost-longest.
- **niyama reads the POSIX-literal `*` wrongly and `\(^` as a literal** — filed: [`2026-11-03-niyama-bre-posix-literal-star-and-group-anchor.md`](https://github.com/MacCracken/niyama/blob/main/docs/development/issues/2026-11-03-niyama-bre-posix-literal-star-and-group-anchor.md). `^*` came out "zero or more
  anchors" (every line), and `\(*a\)` was refused. kriya works around it in
  `icase_bre_literal_stars`, for `grep`, `nl -b p` and `find -regex`: escaping exactly
  those stars, and hoisting a `^` that opens the leading groups. ⚠ A `^` opening a LATER group is
  POSIX's "may be an anchor": GNU makes it one and niyama a literal, so `x\(^a\)` matches `x^a` here
  and nothing under GNU. Closing that upstream deletes the workaround.
- **BRE backreferences** (`\(a\)\1`) are POSIX-required; kriya refuses them loudly (`bad pattern`,
  exit 2) where GNU matches. ⛔ **This roadmap said niyama ADR 0009 was "a v1 decision, not a permanent
  one". It is permanent**: "bre — permanently out of scope for v1.0 *and* post-fold", and its first
  reason is "No identified bre consumer with a hard backref need". kriya is that consumer and never
  said so. Filed as a reconsideration request: [`2026-11-03-niyama-bre-backreferences-have-a-consumer.md`](https://github.com/MacCracken/niyama/blob/main/docs/development/issues/2026-11-03-niyama-bre-backreferences-have-a-consumer.md). It also explains why the ADR's "migrate to pcre"
  path does not fit a POSIX utility (leftmost-first, backtracking, BRE quirks). ⚠ kriya's [ADR 0005](../adr/0005-regex-engine-niyama.md) says backreferences
  "are honored"; that is not true today. The loud refusal is the right failure until niyama lands
  them.

### Upstream chrono — local time

**Filed 2026-11-03:** cyrius [`2026-11-03-chrono-has-no-local-time.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-11-03-chrono-has-no-local-time.md).

`date` local time, local time in `ls -l` and `stat`'s dates, and `touch -t`'s local-time input need
tzfile parsing (`chrono_tz.cyr`). ⚠ What is gated is the VALUE — every kriya time is UTC — not the spelling:
`ls -l` already prints POSIX's date form
([ADR 0020](../adr/0020-ls-long-format-dates-are-posix.md)). ⚠ This is
the **genuine** chrono gate — re-verified absent at pin 6.7.18 (its only change since 6.7.9 is a cx
sleep) — and the trigger
[ADR 0007](../adr/0007-date-utc-only-at-v0-7-0.md) already names.

### Upstream cyrius — the four syscalls the stdlib does not wrap

**Filed 2026-11-03:** cyrius [`2026-11-03-stdlib-has-no-sys-fchdir.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-11-03-stdlib-has-no-sys-fchdir.md)
(1.8.2) and [`2026-11-03-stdlib-has-no-symlinkat-readlinkat-getcwd-fchmodat2.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-11-03-stdlib-has-no-symlinkat-readlinkat-getcwd-fchmodat2.md)
(1.8.4).

1.8.4 took kriya's numeric `syscall(N, …)` literals from 44 to four, and each of the four is a call the
stdlib has no wrapper for. `fchdir` (`_k_fchdir`, x86 81) has an aarch64 workaround through
`/proc/self/fd/N`, because no literal reaches the native call. `fchmodat2` (`k_fchmodat2`, 452 on every
arch) has no wrapper. `symlinkat` and `readlinkat` (`fs_symlinkat` / `fs_readlinkat`, x86 266 / 267) have
no wrapper either, and x86's table has no name for them. None misroutes: `kriya-syscalls.tcyr` pins each
on x86-64 and aarch64. ⭐ When the wrappers land, the four literals go, and with them the last per-arch
`#ifdef` in kriya's Linux syscall layer.

Filed with them: [`2026-11-03-statfs-names-no-inode-or-fragment-fields.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-11-03-statfs-names-no-inode-or-fragment-fields.md).
Since 1.8.4 `df` reads its statfs buffer through the stdlib's `Statfs`, except for `f_files`, `f_ffree` and
`f_frsize`, which `Statfs` does not name. Those three stay in df's `DfStatfs`, at Linux offsets, until it does.

---

## Standing

### The toolchain pin-bump checklist

⛔ **Run these, do not recall them** — a status established by reading has been wrong before
([`lessons.md`](lessons.md)).

1. `cyrius.cyml` `[package].cyrius` — the source of truth, never the CI YAML.
2. **`cyrius lib sync --full`**, not `cyrius deps`, and ⛔ **right after editing the pin, before any
   `deps` or `build`** — those re-stamp the lock with the new pin but keep the old pin's rows for
   files they do not vendor, and `lib sync` then refuses those rows by name (`--relock` accepts the
   new snapshot explicitly). Since 6.6.17 `lib sync --full` re-locks every file it writes; check with
   `cyrius deps --verify` (all entries, 113 at 6.7.18). ⚠ `deps` resolves without re-vendoring, and
   the build then warns that bundled libs are behind the pin. ⚠ `cyrius build` re-copies the modules
   `[deps].stdlib` DECLARES on every build and never the rest, so the undeclared bundled libs drift
   silently without `--full`.
3. `python3 scripts/watchlist-scan.py` — M15a / M15c / M15d / M15i, exits non-zero on a hit.
4. Re-measure M15a's premise: a two-local probe must still give `|&b - &a|` = 8 / 32 / 144.
5. Build **both** targets, plus every `tests/*.tcyr` and `tests/*.fcyr` subset (M15e). ⛔ **Read the
   build output**: a `duplicate symbol` / `duplicate fn` warning is a collision with the stdlib (M15i),
   not noise — and since 6.6.20 every call binds the LAST definition, so a duplicate changes what
   runs. ⭐ Then the aarch64 build: `cyrius build --aarch64 src/main.cyr` and
   `tests/kriya-syscalls.tcyr` under `qemu-aarch64`, plus `ls` on a pty (`script -qec`). It is the
   only run where that test discriminates; on x86_64 it passes the old layer too.
6. Full smoke suite, both lints, `vet`, fuzz under poison (since 6.6.18 it covers `alloc()` and an
   overwrite exits 86). ⚠ Compare the smoke total against the OLD binary in the same container, not
   against the last release's figure: the skip set moves with the environment.
7. **Re-verify every gate in this file** (§ Gated, and each arc item citing upstream) — a pin bump
   is when an upstream blocker quietly disappears. ⛔ **And check that each upstream gate names its
   filing** in the owning repo's `docs/development/issues/`: cyrius for cyrius's own stdlib, the fold's
   own repo for a folded one (niyama, sankoch, …), or `archived/` once resolved. One that names none
   is filed in the same change: at 1.8.1 none of the six had ever been filed, so for up to six months
   nothing upstream was moving on any of them.

### The compiler watchlist

Lives in [`lessons.md`](lessons.md) § The compiler watchlist — the standing list of ways the Cyrius
compiler and kriya interact badly, M15a–M15i. ⚠ **Re-run every detection in it at each toolchain pin
bump**; a pin move is exactly when a latent instance stops being latent.

---

## Enabler map

What still gates the arcs. Ship the enabler and everything under it becomes small.

| Enabler | Home | Unblocks | Slot |
|---|---|---|---|
| Float formatting | `src/cmd/printf.cyr` | `printf %e/%f/%g/%a`, `seq -f` | 1.9.0 |
| Byte-suffix parser | `src/lib/args.cyr` | `head -c 1K`, `tail -c 1K`, `sort -S` | 1.9.2 |
| niyama regex speed (quadratic search) | **upstream, filed** | `grep` on metacharacter patterns (~150× GNU) | 1.10.2, gated |
| niyama GNU BRE operators, leftmost-longest, literal `*`, backreferences | **upstream, filed** | `grep`, `find -regex`, `nl -b p` | M11, gated |
| chrono tzfile reader | **upstream, filed** | local time in `date`, `ls -l`, `stat`, `touch -t` | gated |

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
propose extracting it into its own repo. ⚠ **Seventeen exceed it** (non-blank, non-comment lines,
measured at 1.7.0); the largest are `ls` (**2,201**), `grep` (1,475), `cp` (1,332) and `find`
(1,006), and none has been split. The threshold is a **prompt to decide**, not an
automatic trigger: the multi-tool is the right home while they share `src/lib/`, and the question is
whether a given utility has stopped sharing.

⛔ **Decided 2026-09-22: no split-outs until AGNOS is running fully, and then only as time permits.**
Until then the threshold is recorded, not acted on — measure the figures at each arc boundary so the
eventual decision starts from numbers, but do not propose an extraction in a release. `ls` will be
first in line when it comes: its GNU output surface (dates, `--dired`, tab stops, nine quoting
styles, the full colour table) makes it half again the next utility, and most of that is rendering
`src/lib/` does not share.

## Adopting cmdit (CLI parsing)

⛔ **Not a candidate today.** This is recorded so nobody has to re-derive it. It is demand-gated, not a forced
sweep, and has no slot on the arc sequence. cmdit's roadmap lists kriya as its `argv[0]` multiplexer case
(`cmdit_basename` + `cmdit_raw_argv`). This note was read against cmdit 1.2.6 source on 2026-10-14. Nothing was
built or run.

**The multiplexer half already has cmdit's caller-side shape.**

- `src/main.cyr:277-288` selects the utility from `path_basename_ptr(argv(0))` and falls back to `kriya <util>`
  with `start = 2`. `:289-318` adds `--list`/`--version`/`--help`, recognised only in that `kriya <util>` form.
  `:93-153` is the one table that both routes and feeds `--list`.
- cmdit would only swap `path_basename_ptr` → `cmdit_basename`. That is one call, and the two differ only on a
  trailing `/`: `src/lib/path.cyr:35` trims it, cmdit returns the empty tail.
- A `cmdit_verb` row has no place for the `*_help_declare` pointer that `--list` needs. Nothing is gained here.

**The per-utility half is a full option grammar ([ADR 0002](../adr/0002-option-parsing-humans-and-agents.md)) that
cmdit lacks.** `src/lib/args.cyr` (1,535 lines) wraps stdlib `flags`. It serves 242 `flags_add_*` registrations
across 38 utilities. 26 of them call `kriya_args_parse*` by grep, although the note at `args.cyr:235` still says
28. Each item below is something kriya ships and cmdit 1.2.6 does not:

- **Clusters and attached values** (`-rf`, `-n5`, `-rfvn10`): ADR 0002 *Allowed forms*, with the expander at
  `args.cyr:216-240` and `:385`. cmdit returns `CMDIT_ERR_BUNDLED` for these. They are on cmdit's v2 backlog, and
  kriya is a second consumer for that item, against the "only darshini needs bundling" line in cmdit's roadmap.
- **Optional-value longs:** `cp --preserve=LIST`, `sort --check=quiet`, `tail --follow=name`, and
  `uniq --group`/`--all-repeated` (`args.cyr:24-30`, `:82-89`, `:800-817`). Also on the v2 backlog.
- **`--bool=VALUE` refused:** `args.cyr:17-22` records that `sort --reverse=nonsense` used to exit 0. cmdit's
  `_cmdit_apply` sets the bool and drops the value, which is the same defect.
- **Option recognition stops at the first operand**, which `xargs`/`env` command lines need (`kriya_argv_option_end`,
  `args.cyr:685-705`). cmdit keeps recognising options after an operand until `--`, and `cmdit_verb_trailing_after`
  only applies to a verb.
- **No positional cap:** `args.cyr:953-957` records that `kriya rm *` over 200 files deleted 128 and exited 0, until
  stdlib 6.6.5 grew the table. cmdit still drops anything past `CMDIT_POS_MAX` (128) silently.
  ⛔ **Adopting cmdit today would bring that back.**
- **Linear argv:** `kriya_argv_flat` (`args.cyr:174-203`) walks `/proc/self/cmdline` once. At 1.6.17 this took
  `rm -f` over 20,000 names from 1,451 ms to 67 ms. `cmdit_argv` calls stdlib `argv(i)` once per argument, which is
  the quadratic form.
- **Flag-table introspection:** two parts of kriya read the stdlib `flags` entry layout directly:
  - the spec-driven expander (`kriya_short_type`/`kriya_long_type`, `args.cyr:248`, `:656`);
  - the help and `--help=json` renderer (`src/lib/help.cyr:197-232`, `:466-484`).
  cmdit's layout is not API, and cmdit exposes verb accessors only (1.2.0), with no flag accessors.
- **Kept in kriya's own code whatever the parser:** grep `-NUM` (`args.cyr:45-54`), head/tail obsolescent counts
  (ADR 0023), order-sensitive queries (`kriya_opt_seq`, `args.cyr:995-1083`), the `--help=json` pre-scan
  (`args.cyr:869`), and GNU-shaped diagnostics.

**What does fit:**

- `-h` and `-V` are deliberately unclaimed (ADR 0002; `ls -h`, `sort -V`).
  `cmdit_help_short(h, 0)`/`cmdit_version_short(h, 0)` free them and keep `--help`/`--version`.
- `cmdit_repeat` covers `kriya_argv_collect` (`args.cyr:1099`).
- Exact-name matching and interleaved operands agree with ADR 0002.

- [ ] **Re-check when cmdit grows positionals and makes `cmdit_argv` linear.** Both are internal fixes. Flag
  introspection and the grammar items would be append-only additions. Gated, no slot. Then:
  - Add the block below. Keep `"args"` and `"io"`, and keep `"flags"` until the last utility leaves it.
  - Migrate one utility at a time behind the expander. `1.3.0` is not tagged yet as of 2026-10-14.
  - The identity bar is the GNU-oracle smoke suite: 41 `scripts/smoke-*.sh`, notably `smoke-option-forms.sh`,
    `smoke-help.sh`, `smoke-help-json.sh` and `smoke-list.sh`.
  - Also run `scripts/lint-help-schema.sh`, plus `tests/kriya.tcyr` (about 120 lines on the parse layer) and
    `tests/kriya.bcyr`. `tests/kriya-posix.tcyr`, `tests/kriya-syscalls.tcyr` and the three `.fcyr` harnesses do
    not touch parsing (checked).

```
[deps.cmdit]
git = "https://github.com/MacCracken/cmdit.git"
tag = "1.3.0"
modules = ["dist/cmdit.cyr"]
```

References: cmdit's [`README.md`](https://github.com/MacCracken/cmdit/blob/main/README.md) (API reference) and
[`docs/development/roadmap.md`](https://github.com/MacCracken/cmdit/blob/main/docs/development/roadmap.md)
(v2 backlog, out of scope). Worked migrations: kii `src/cli.cyr` and anuenue `src/main.cyr`.

**Update — cmdit 1.3.0 / 1.3.1 (2026-10-14).** Three items in the list above are now fixed in cmdit:

- **No positional cap (1.3.1):** the positional array doubles instead of dropping past 128, and a refused growth is
  `CMDIT_ERR_NOMEM`. Adopting cmdit no longer brings back the `rm *` truncation.
- **`--bool=VALUE` refused (1.3.1):** `CMDIT_ERR_UNEXPECTED_VALUE`, so `sort --reverse=nonsense` fails, as GNU's does.
- **Linear argv (1.3.0):** `cmdit_argv` walks `/proc/self/cmdline` once on Linux, the same fix as `kriya_argv_flat`.

The verdict stands. Clusters and attached values, optional-value longs, stopping at the first operand, and
flag-table introspection are still missing, so kriya is not a candidate yet.

**Update — cmdit 1.3.x / 1.4.0 (2026-10-14).** Two more items in the list above are now covered:

- **Option recognition stops at the first operand (1.3.4):** `cmdit_stop_at_positional(h, 1)`. The first operand,
  a lone `-` included, ends the options, and every later token is an operand, flag-shaped or not. A `--` after it
  stays data, unlike `cmdit_verb_trailing_after`, which consumes one; that is the `ls -1 | xargs rm --` case.
- **Flag-table introspection (1.3.7):** `cmdit_flag_count` and `cmdit_flag_short_at` / `_long_at` / `_type_at` /
  `_help_at`, plus `_long_alias_at`, `_default_at`, `_choices_at`, `_metavar_at`, `cmdit_flag_is_required` and
  `cmdit_flag_is_repeat`. They cover what `src/lib/help.cyr:197-232` and `:466-484` read from the stdlib entry
  layout. `cmdit_flag_find_short(h, ch)` and `cmdit_flag_find_long(h, name, len)` return the parser's own `-x` /
  `--name` lookup as an index or -1, span-based, so the `--name=value` bytes up to the `=` need no copy. With
  `cmdit_flag_type_at` they answer the expander's question (`kriya_short_type` / `kriya_long_type`,
  `args.cyr:248`, `:656`) without reading cmdit's layout.

Also since the 1.3.1 update: `cmdit_err_token` / `cmdit_err_value` (1.3.3) give the offending token and value
for GNU-shaped diagnostics, and `cmdit_help_fd(h, 1)` (1.3.5) prints help on stdout. 1.4.0 changes no API or
output; it makes a parse about 2× faster and `--help` over 10× faster.

Still missing, both on cmdit's v2 backlog: **clusters and attached values**, which can stay in kriya's
pre-parse expander now that it can query cmdit's table, and **optional-value longs** (`--preserve[=LIST]`,
`--check[=quiet]`, `--follow[=name]`), which cmdit has no form for. The verdict stands on the second. If the
re-check above happens, pin `tag = "1.4.0"` instead of `"1.3.0"`.
