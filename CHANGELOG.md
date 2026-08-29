# Changelog

All notable changes to kriya will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This file is **released items only**. Deferred follow-ups (post-1.0 GNU-parity features, Cyrius proposal sweeps, perf optimizations, the boot-burn signal) live in [`docs/development/roadmap.md`](docs/development/roadmap.md) under **Post-1.0 milestones**.

## [Unreleased]

### Fixed — ⛔ three utilities said "last-wins" and four of them did something else

**`realpath`, `readlink`, `head` and `tail` all resolved a conflicting flag pair by a rule that is
not the one GNU uses.** Measured against GNU coreutils 9.11 on this box:

    $ mkdir -p /tmp/rp/real && ln -s real /tmp/rp/slink
    $ realpath -Ps /tmp/rp/slink          GNU: /tmp/rp/slink     kriya: /tmp/rp/real
    $ readlink -m -e /tmp/rp/nope         GNU: rc=1, no output   kriya: /tmp/rp/nope, rc=0
    $ printf 'abcdefghij\nklmnop\n' > h
    $ head -c 3 -n 1 h                    GNU: abcdefghij        kriya: abc
    $ tail -c 3 -n 1 h                    GNU: klmnop            kriya: op

⚠ **In every case the OTHER order was right.** `-sP`, `-e -m`, `-n 1 -c 3` and `tail -n 1 -c 3` all
agreed with GNU, which is why the suites were green: each pair was asserted once, in the order where
the wrong rule and the right one happen to coincide.

**1. `realpath` scanned the RAW argv and could not see a cluster.**

`_rp_scan_order` walked `argv(i)` under a comment claiming *"Bundled shorts are rejected by the
parser (ADR 0002), so a short option is exactly two bytes here"*, followed by an `if (tlen == 2)`
that acted on it. ⛔ **kriya's parser has accepted clusters since 1.4.0** — `kriya ls -1C` resolves —
so `-Ps` arrives as one three-byte token, fails the length test, and neither letter is seen at all.
`realpath -Ps slink` printed the RESOLVED path where GNU prints the symlink untouched: `-s` was
never applied and `_rp_how` stayed at its `RP_PHYSICAL` default. ⚠ A claim about *kriya's own
parser*, not about GNU — the code the comment described had changed underneath it.

**2. `readlink` implemented a PRECEDENCE LADDER under a comment calling it last-wins.**

*"Precedence (matches GNU last-wins): m > e > f"* — the two halves of that sentence are different
rules, and the ranking is the one that ran. ⛔ A caller testing `readlink -e` for existence got a
path back for a file that is not there, because something earlier in a generated command line
carried `-m`.

**3. `head` and `tail` did the same thing to `-n` and `-c`.**

*"Mode: -c wins over -n (last-wins; GNU same)"*, and the code did the first half. ⭐ **`tail` was not
in the report and has the identical defect** — same block, same comment shape, same divergence. The
two are a pair; fixing one and shipping the other would have left half the bug in place.

### Changed — ⭐ order-sensitive questions are asked of the parser, not of `argv`

`src/lib/args.cyr` gains `kriya_expanded_argv()` / `kriya_expanded_argc()` (accessors for the
normalised argv the parser already builds — clusters split, attached values separated, long forms
normalised, `--` honoured, permutation resolved) and **`kriya_opt_seq(spec, short_ch, long_name)`**,
which answers *where did this option LAST appear* for any spelling: short, clustered, long, attached
`--name=VALUE`, and the obsolescent `head -5`. `kriya_short_seq` — added in 1.5.1 for `ls -tS` — is
now a two-line wrapper over it, so there is **one** implementation of the question instead of four
partial ones.

⚠ **The general scan skips a value-taking option's VALUE and stops at `--`**, both of which the
`ls`-era version did not need and `head` does: `head --lines -c` must not read the `-c` as a byte
count the parser consumed as the line count, and a file named `-n` after `--` is an operand.

⚠ `_rp_scan_order` now reads every letter of a single-dash token rather than only a two-byte one,
and asks the spec — not a list of names — which options swallow a following value, so
`--relative-to DIR` cannot be re-read as flags. The stale ADR-0002 comment is gone.

### Fixed — ⛔ the tests only ever covered the order that agreed

Every new assertion was verified RED against a pre-fix binary built from the previous commit, and
green after: **13** new in `smoke-realpath.sh` (395 total), **18** in `smoke-readlink.sh` (95),
**12** in `smoke-head-tail.sh` (67). All 41 smoke scripts and `cyrius test` (453) green.

⚠ **The gap was structural, not an oversight.** `readlink`'s block was headed *"canonicalize
precedence: -m > -e > -f"* and asserted `-f -e -m` — the one order both rules answer identically.
Every new pair is asserted in BOTH orders and in clustered form, plus the long spellings, a
non-mode flag between the pair, a repeated flag, and past a `--`. ⭐ `head`/`tail` gained a fixture
whose line answer and byte answer differ at both ends (`abcdefghij\nklmnop\n`); on the existing
`seq 1 50` fixture a mode mix-up still looks plausible.

## [1.6.7] - 2026-08-28 — toolchain pin 6.5.36, a sleep that is a deadline, and a watchlist that was wrong

### Changed — toolchain pin 6.5.35 → **6.5.36**

`cyrius.cyml`'s `[package].cyrius` is the source of truth; `lib/` re-synced with `cyrius lib sync
--full` (108 files). ⚠ **`cyrius deps` alone was not enough** — it resolved without re-vendoring, and
the build then warned that three bundled libs were behind the pin (`sigil` 3.12.9 vs 3.12.14,
`sandhi` 1.9.10 vs 1.9.14, `sankoch` 2.7.8 vs 2.7.10). None is in kriya's dependency closure, but a
vendored tree that does not match the pin is a claim that is not true.

Both targets build; every suite green on the new pin before any other change.

### Fixed — ⛔ the compiler watchlist said "zero instances" and there were four

[`lessons.md`](docs/development/lessons.md) § The compiler watchlist exists to be re-run at every pin
bump, and **M15d** — *`break` inside a `while` that declares a `var` is unreliable* — recorded:

> *Status at v1.1.11*: **zero instances**. The four `break;` in `src/cmd/find.cyr` are in loops with
> no `var` declaration.

⛔ **That loop declares `var t` AND `var c0`, and breaks four times.** It is `find`'s start-path/
expression split, it had been correct since 6.5.18, and it violates CLAUDE.md's hard rule outright.
⚠ **The status had been established by reading rather than by running a detection** — which is the
lesson inside the lesson, and it is now written down next to the entry.

Converted to flag + continue. ⭐ **The detections are a script now** —
`scripts/watchlist-scan.py`, covering M15a (stat buffers must be `[144]`), M15c (duplicate array
declarations in one function) and M15d, exiting non-zero on a hit. ⚠ Its first run reported two false
M15c hits from comment text (`# var st[48]`) — **strip comments before scanning**, which is also now
in the entry.

Results at 6.5.36: 176 declarations scanned, **0** off-size stat buffers, **3** duplicate arrays (the
three known and cleared), **0** `break`-in-var-loop. M15a's premise re-measured and unchanged:
`|&b - &a|` is 8 / 32 / 144 for `var x[4]` / `var x[32]` / `var x[144]`.

### Changed — ⭐ `sleep` waits on a DEADLINE, not a countdown

⛔ **The dangerous direction is SHORT, not long.** `sleep_ms` returns 0 whether `poll` timed out or
came back early, so a loop that subtracts the chunk it *asked for* sleeps less than requested and
exits 0. Demonstrated by mutation — a `sleep_ms` returning at 10% of its argument:

| loop | `kriya sleep 2` |
|---|---|
| deadline (now) | **2.00 s** |
| countdown (before) | **0.20 s** |

⚠ **kriya was already exact before this change**, and that is the point: measured against GNU, both
return in 2.00 s through a 1 s `SIGSTOP`, and both survive 36 hammered `SIGWINCH` / `SIGCONT` /
`SIGURG` / `SIGCHLD` unchanged. But the correctness came from an **absence** — kriya installs no
handler, so `poll` is never interrupted — not from a property of the code, and
[architecture 002](docs/architecture/002-signal-handling-model.md)'s trigger table plans flag-based
handlers for the destructive utilities.

⭐ The deadline reads `clock_now_ms()`, which is `CLOCK_MONOTONIC`, so it does not move when the wall
clock is stepped by NTP or `date -s` — which an epoch-based deadline would.

### Fixed — ⚠ a one-in-eight flake in `smoke-ownership-xattr.sh`

One full-suite run reported `109 passed, 1 failed`; seven re-runs were green. ⛔ **It is a
same-second race by construction**: `--preserve=mode` deliberately does not carry timestamps, so the
GNU copy and the kriya copy both get "now" — and the two `cp` calls straddling a second boundary make
`%Y` differ on a difference that means nothing.

The 1.6.1 `cp` fuzz already solved this by collapsing anything within a minute of now to `NOW`; this
script compared the raw `%Y`. ⚠ **A preserved mtime is an OLD stamp** — the fixtures are stamped in
the past — so the collapse only merges the case where the value carries no information. Proven by
mutation: with `-p`'s timestamp restore removed, the normalised comparison still goes red in 7 cases.

### ⭐ How it was checked

⭐ **Two mutations on the sleep loop, both red**: reverting to a countdown under an early return
(17 failures) and reading the deadline once instead of per iteration (7). ⭐ **Four new assertions**
pin the timing directly — a `SIGSTOP` for half the duration must not extend it, and hammered
`SIGWINCH`/`SIGCONT`/`SIGCHLD` must not shorten it — each bounded on **both** sides, because a
one-sided bound cannot see the failure the countdown loop produces.

### Release totals

**5,360 smoke cases across 41 scripts** (from 5,356) — `smoke-sleep.sh` 48 → **52**. **453 unit**,
18 POSIX; fuzz green under poison; four lints clean; `watchlist-scan.py` clean; both targets build;
`vet` reports 56 deps.

Binary 1,121,208 → **1,121,224** bytes on host, 1,117,016 → **1,117,048** on agnos.

## [1.6.6] - 2026-08-27 — one error line, one implementation of it, and `readlink` stops talking

### Breaking — ⛔ `readlink` is silent on failure; add `-v` to keep the diagnostics

[ADR 0018](docs/adr/0018-readlink-is-silent-by-default.md). GNU ships two utilities that answer
nearly the same question and disagree about explaining a failure:

```
$ readlink plain            (nothing)            exit 1
$ realpath plain            realpath: plain: …   exit 1
```

kriya's `readlink` printed a diagnostic, matching neither GNU's `readlink` nor any stated policy — it
matched `realpath`, the utility next door. **Migration: add `-v`.**

⛔ **GNU reaches its verbose mode through `POSIXLY_CORRECT`, and that variable BEATS AN EXPLICIT
`-q`** — measured: `POSIXLY_CORRECT=1 readlink -q plain` still prints. An environment variable
overriding a flag the caller wrote is exactly what [ADR 0017](docs/adr/0017-environment-variables-configure-features-the-caller-turned-on.md)
forbids, so kriya could not copy GNU's mechanism even to reach GNU's default. ⭐ In kriya an explicit
`-q` beats `-v` in either order, which GNU cannot say.

### Added — `readlink -s`/`--silent` and `-v`/`--verbose`

⚠ **`readlink -s` is NOT `realpath -s`.** Here it is a synonym for `-q`; there it means "do not
expand symlinks". One letter, opposite meanings — which is why two utilities that look alike do not
share a flag table.

### Fixed — ⛔ a filename with a newline split one diagnostic across two lines

[architecture 001](docs/architecture/001-errno-message-policy.md) commits in writing to *"one write
per error line"*. Writing the operand raw broke it:

```
kriya realpath: a
b: no such file or directory
```

⚠ It also made `kriya rm: a b: no such file or directory` unreadable — one operand, or two?

The operand is now shell-quoted when it needs it. ⭐ **The style is its own**, `QUOTE_DIAGNOSTIC`,
which is GNU's `quotearg_style_colon` and differs from `ls`'s shell-escape in exactly two bytes:

- ⛔ **`:` is quoted**, because the message is colon-delimited and `a:b` makes the line unparseable
  back into utility, operand and message. `ls` leaves it bare and must keep doing so — asserted on
  both sides.
- ⛔ **`/` is bare**, because every path has one. `ls` names never do, so `/` was never in the
  measured set — reusing it quoted every path in every diagnostic: `kriya tee: '/dev/full': …`.

Measured against GNU across ten shapes — plain, spaces, quotes, tabs, newlines, `=`, `:`, paths and
the empty string — **all ten match**. ⚠ The empty operand is now visible at all: `kriya rm: '': …`
where it used to print a hole, which is how an unset shell variable announces itself.

### Changed — ⭐ twenty-four copies of the error line became one

Every utility carried its own `_xx_report(operand, errno)` — **byte-identical to the others apart
from the name in the prefix**, the same 24 lines including the same errno-to-digits fallback. A
change to the shape meant 24 edits, so the shape never changed and the quoting defect had 24 homes.

`errmsg_report(util, operand, errno)` in `src/lib/report.cyr` is now the only implementation, and
each `_xx_report` is one line. **-401 lines** across 20 files, and architecture 001 gains a rule 5
saying where the shape lives.

### Fixed — ⚠ architecture 001 documented the fields in the wrong order

The note said the framing is `kriya <util>: <message>: <operand>` and gave four examples in that
order. The code has always emitted **operand then message** — GNU's shape — across all 38 utilities,
so the note described something that never shipped. ⭐ **It survived because there was no single
implementation to check it against**, which is the same reason the quoting defect did.

### ⭐ How it was checked

⭐ **Six mutations, and the first pass caught three test gaps rather than three defects.**
"`-s` is not a synonym for `-q`" stayed green because **the default is already silent**, so `-s`
doing nothing looked identical to `-s` working — the assertion now runs it against an explicit `-v`.
"`ls` starts quoting `:` too" stayed green because a piped `ls` prints names literally whatever the
quoting table says — it now passes `--quoting-style=shell-escape` explicitly. And nothing asserted
`:` quoting at all. ⚠ **Third release running that the fixture, not the code, was the thing that
needed fixing first.**

### Fixed — ⛔ green here, red on CI: `POSIXLY_CORRECT` and `readlink` is version-dependent

⚠ **Second time a dev-box-versus-runner coreutils difference has cost a release cycle**, after
`realpath -E` at 1.6.3 — and this time I had already written the rule and not applied it.

| | `POSIXLY_CORRECT=1 readlink plain` |
|---|---|
| coreutils **9.4** (the runner) | silent — the variable is ignored entirely |
| coreutils **9.11** (this box) | `readlink: plain: Invalid argument` |

9.4's `--help` describes `-q`/`-s` as *"suppress most error messages (on by default)"* with no
mention of the variable; 9.11's adds *"(on by default if POSIXLY_CORRECT is not set)"*. The
comparison is probed now, kriya's own answer is asserted either way, and `check-oracles.sh` prints
the capability alongside `realpath -E`.

⭐ **And the whole suite now runs against the runner's coreutils before a release is called green** —
`docker run -v "$PWD":/w -w /w ubuntu:24.04 sh -c 'for s in scripts/smoke-*.sh; …'`. It found this in
one pass. ⚠ Seven other failures in that container are its own missing tooling (`python3`) and its
root uid bypassing DAC, not version differences; the runner passes all of them.

⛔ **ADR 0018 was version-specific where it read as general.** It claimed "GNU reaches its verbose
mode through `POSIXLY_CORRECT`" as a property of GNU. Corrected to name both versions — which
strengthens the decision rather than weakening it: *"as GNU does"* is not a fixed target here, so
copying the mechanism would mean picking a GNU version to be compatible with.

### Release totals

**5,356 smoke cases across 41 scripts** (from 5,322) — `smoke-readlink.sh` 33 → **56** and
`smoke-ls.sh` 128 → **131**. ⚠ **54 passed / 1 skipped on coreutils 9.4**, where the
`POSIXLY_CORRECT` contrast cannot be measured. **453 unit**, 18 POSIX; fuzz green under poison; four lints clean; both
targets build; `vet` reports **56 deps** (`src/lib/report.cyr` is the new one).

⭐ Binary 1,129,504 → **1,121,208** bytes — **8,296 SMALLER**, because 23 copies of one function
became one. The agnos target drops the same amount, 1,125,312 → **1,117,016**.

## [1.6.5] - 2026-08-27 — backups for `cp`, `mv` and `ln`, and the environment-variable rule that had to come first

### ⭐ Decided — [ADR 0017](docs/adr/0017-environment-variables-configure-features-the-caller-turned-on.md): an environment variable may configure a feature the caller turned on; it may never turn one on

kriya had declined behaviour-changing environment variables three times — `POSIXLY_CORRECT` for
`echo` and for `pwd`, `QUOTING_STYLE` for `ls` — and *read* three others: `LS_COLORS`, `COLUMNS`,
`PATH`. Three refusals and three acceptances with no rule between them is a habit, not a policy, and
GNU's backups are governed by `VERSION_CONTROL` and `SIMPLE_BACKUP_SUFFIX`.

⛔ **The distinguishing property is measurable**: *with the feature's flag absent, does the variable
change anything?*

| variable | with no relevant flag | |
|---|---|---|
| `POSIXLY_CORRECT` | `/usr/bin/echo 'a\tb'` prints `a\tb`; with it set, a **real tab** | changes behaviour |
| `QUOTING_STYLE` | `ls` prints `has space`; with it, `has\ space` | changes behaviour |
| `VERSION_CONTROL` | no backup made, in `cp`, `mv` **and** `ln` | **inert** |
| `SIMPLE_BACKUP_SUFFIX` | same | **inert** |
| `LS_COLORS` | no escape sequences without `--color` | **inert** |

So the two backup variables are honoured and the two others stay declined — and ADR 0011's refusal
becomes *required* by the rule rather than merely precedented.

### Fixed — ⛔ applying the rule found `ls` on the wrong side of it

⛔ **`kriya ls | while read f` could produce multi-column output.** `_ls_term_width` consulted
`$COLUMNS` before testing `isatty`, and bash exports `COLUMNS` from interactive shells — so a piped
listing came back as several names per line and the reader got `file1  file2` as one filename.

⚠ **The comment defending it was load-bearing and wrong**: *"An explicit -w or $COLUMNS forces
columns even off a tty (a real GNU affordance + the host test hook)."* Measured, GNU does neither:

```
$ COLUMNS=200 ls | cat     one name per line
$ ls -w 200 | cat          one name per line
$ ls -C | cat              columns          <- -C is what forces them
```

**Fourth release running that a comment asserting another tool's behaviour was load-bearing and
false.** `$COLUMNS` is now read only when stdout is a terminal. ⚠ `-w` still forces columns, which
GNU does not — kriya has no `-C`, and removing `-w`'s behaviour without adding one would delete the
capability. Both are filed at 1.6.8 and the divergence is asserted rather than incidental.

### Added — `-b`, `--backup=CONTROL` and `-S`/`--suffix=SUFFIX` for `cp`, `mv` and `ln`

⭐ **One helper, `src/lib/backup.cyr`, three consumers** — and `cp` alone needed **two hook sites**,
because `_cp_one` handles a single file and `_cp_file_at` handles each entry of a `-R` walk. A
backup wired into only one of them would have made `cp -b` work and `cp -Rb` silently not. That is
the concrete form of the rule the roadmap set: the helper goes in `src/lib/`, not in the first caller.

⛔ **The control is a matrix and it is not guessable.** Every cell measured against GNU:

| control | nothing else | `dst~` present | `dst.~1~` present |
|---|---|---|---|
| `none` / `off` | *(no backup)* | *(no backup)* | *(no backup)* |
| `numbered` / `t` | `dst.~1~` | `dst.~1~` + `dst~` | `dst.~2~` |
| `existing` / `nil` | `dst~` | `dst~` | `dst.~2~` |
| `simple` / `never` | `dst~` | `dst~` *(clobbered)* | `dst~` |

⚠ **`existing` — the default — asks ONE question**: does any `dst.~N~` exist? It does not care
whether `dst~` does. ⚠ **Numbering is HIGHEST + 1, not first gap**: with `.~1~` and `.~3~` present
GNU writes `.~4~`, and a first-gap implementation would write `.~2~` and silently reuse a slot the
user can still see.

⛔ **The backup is a RENAME of the old destination, not a copy** — measured by inode for both
`cp -b` and `mv -b`. A hard link to the old destination therefore follows the **backup**, and the new
destination is a fresh inode. ⭐ Asserted three ways: the inode, the backup's contents, and that
writing the destination afterwards leaves the backup alone. A hard-link implementation passes the
first and fails the last two.

⭐ **`-b` needs no `-f`.** kriya refuses a silent overwrite without `-f`, and a backup is not a silent
overwrite — the old contents survive under a new name. Measured: GNU needs no `-f` either. Without
this the flag would be useless on its own. ⚠ `--backup=none` is *not* a backup and does not grant it.

⚠ **`--backup` requires its value and `-b` has no long form**, because GNU's `--backup[=CONTROL]` is
an optional-value flag and [ADR 0002](docs/adr/0002-option-parsing-humans-and-agents.md) rule 3
forbids those — the same split `tee` got for `-p` and `--output-error=MODE` at 1.6.4. ⛔ **And no
prefix matching**: GNU takes `--backup=num` and rejects `--backup=n` as ambiguous; kriya takes the
eight exact spellings and nothing else, per ADR 0002's no-prefix-matching rule.

### Fixed — ⛔ `cp` wrote through a dangling symlink destination

`k_stat` follows, so a destination symlink pointing at nothing read as *"no destination"* and the
copy created the link's **target**. Measured before the fix: `cp -f src dst` with `dst -> nowhere`
exited **0** and produced a file called `nowhere` — a path the caller never named. GNU refuses with
*"not writing through dangling symlink"*, exit 1, and kriya now does too.

⭐ **`-b` rescues it**, in both implementations: the backup renames the dangling link aside, so there
is nothing left to write through. All three rows — plain, `-f`, `-b` — now match GNU exactly.

### ⭐ How it was checked

⭐ **A 57-case differential run across all three utilities** — every control spelling, every suffix
shape, and the four starting states — reaches **0 divergences**, plus **11 more** for the two
environment variables including both precedence directions.

⚠ **Three divergences are deliberate and asserted so they cannot drift into accidents**: an invalid
control is exit **2** where GNU uses 1 (ADR 0008), an abbreviation is refused (ADR 0002), and
`--backup=none` without `-f` is still an overwrite kriya declines.

⚠ **Two mutations survived the first pass and both were test gaps.** "The backup is a hard link, not
a rename" passed every name assertion — a link shares the inode, so even the inode check held, and
only the *content* assertions catch it. And "a missing destination still backs up" turns out to be
**unreachable from all three call sites**, because each utility hooks the backup inside its own
"destination exists" branch. That guard stays as the helper's documented contract, with a comment
saying plainly that no test stands behind it rather than letting a reader assume one does.

### Release totals

**5,322 smoke cases across 41 scripts** (from 5,223) — `smoke-cp.sh` 26 → **70**, `smoke-mv.sh`
58 → **66**, `smoke-ln.sh` 90 → **98**, `smoke-ls.sh` 122 → **128**. **453 unit** (from 440 — the
control-name mapping and its refusals), 18 POSIX; fuzz green under poison; four lints clean; both
targets build; `vet` reports **55 deps** (`src/lib/backup.cyr` is the new one).

Binary 1,124,496 → **1,129,504** bytes (+5,008) on host, 1,120,304 → **1,125,312** (+5,008) on agnos.

## [1.6.4] - 2026-08-27 — `tee`'s signal flags, and a defense that was designed four ways and then not built

### ⛔ Decided — the cross-operand bulk-root defense is REJECTED, not deferred again

[ADR 0004](docs/adr/0004-rm-refuses-root.md) has named
`docs/architecture/003-cross-operand-bulk-root-defense.md` as a promissory note since v0.3.0:
`rm -rf /*` expands **at the shell** to `/bin /boot /etc …`, every operand individually legal, the
aggregate catastrophic. Four defenses were designed independently, measured against real corpora, and
attacked: a bigger static table, exact root coverage, an operand-fan-out threshold, and an
inverted-glob pre-flight.

**None of them is being built.** [The note](docs/architecture/003-cross-operand-bulk-root-defense.md)
exists now and says so. Three findings killed all four:

- ⭐ **The refusal teaches a strictly worse command.** Measured on one fixture with a `.dockerenv`
  and a `.secrets/` dotdir:

  | command | entries left | files left |
  |---|---|---|
  | `rm -rf FX/*` — **what all four refuse** | 2 | 2 |
  | `for d in FX/*; do rm -rf "$d"; done` | 2 | 2 |
  | `find FX -mindepth 1 -maxdepth 1 -exec rm -rf {} ';'` | **0** | **0** |

  ⛔ The shape every candidate refuses is the **least destructive** of the available ones, because a
  per-operand route enumerates **the dotfiles the glob never matched**. And every candidate's
  headline false positive is a container build, a chroot rootfs assembly or an initramfs teardown —
  populations that automate, have no escape hatch, and whose workaround goes into a Dockerfile and
  then runs everywhere forever.

- ⛔ **Text-only canonicalization is blind to the operand PREFIX and cannot stop being.**
  `/proc/self/root` is a kernel-maintained symlink to `/` on every Linux and in every container.
  `/proc/self/root/*` expands to all 19 root entries and `kriya realpath -s -m /proc/self/root/etc`
  answers `/proc/self/root/etc` — depth 3, matching no table entry and counting as no root child.
  ⭐ The **cwd** form *is* caught (`cd /proc/self/root && kriya pwd -P` is `/`), because `getcwd`
  returns the kernel's physical path. kriya sees through a symlinked cwd and is structurally blind to
  a symlinked operand prefix.

- ⛔ **There is no universal tripwire.** Exporting `agnos-thin:latest` shows the AGNOS rootfs is
  `bin data mirshi`. There is **no `/usr` at all**, and the `/etc` that appears holds exactly
  `hostname hosts mtab resolv.conf`, all four injected by Docker. A `/usr`+`/etc` table has **zero
  coverage on the platform kriya is built for**, and the only name common to every root kriya ships
  onto is `/bin` — a symlink into `usr/` on merged-usr systems, which the usrmerge migration removes.

⚠ **The corpus said the rules would have been nearly free, and that is not evidence of safety.** A
scan of `/usr/share`, `/usr/lib`, `/usr/bin`, `/etc` and `~/Repos` parsed **6,475 `rm` invocations**;
fourteen appeared to name two or more top-level entries and **all fourteen are false** — prose in
documentation describing this very problem (kriya's own ADR 0004 scores the worst), `groff` macro
files where `rm` means *remove macro*, a Go testdata script, a test log. Zero real invocations. ⛔ But
the corpus contains none of the populations that would pay: **a false-positive rate measured where
the false positives do not live is evidence about where you looked.**

The note carries five Hard rules that now bind ADR 0004's extension point. The sharpest:
⛔ **no entry may be added to `protected_paths[]` for a path that can be absent** — a table entry
converts `rm -f` on a nonexistent path from a POSIX no-op into a usage error. Measured:
`kriya rm -f /absent-toplevel-xyz` exits **0** today, matching GNU.

⭐ **The decision is asserted, not just written down.** `smoke-rm.sh` gains the measurement that
decided it (the glob leaves dotfiles, `find -exec` does not), the `rm -f`-is-a-no-op rule, and the
per-operand refusals that must keep firing — so a future aggregate rule shows up as a test edit
rather than as silent drift.

### Added — `tee -i`, `-p` and `--output-error=MODE` ([ADR 0016](docs/adr/0016-tee-signal-dispositions.md))

⚠ **The infrastructure they were waiting on already existed.** `tee.cyr` deferred `-i` for six
releases as needing "the signal-handler infrastructure flagged in architecture 002 — not yet
installed". `lib/syscalls.cyr` has had `signal_ignore(signum)` and `signal_default(signum)`, with
`SIGINT` and `SIGPIPE` enumerated, since v6.4.51. **Second kriya deferral to outlive its blocker**,
after `sleep`'s fractional durations waited on a chrono duration parser that was never coming.

⛔ **Five mode names, two independent bits.** Measured across both a non-pipe failure (`/dev/full`)
and a pipe failure (a closed reader):

| mode | non-pipe error | pipe error |
|---|---|---|
| default | warn, keep other outputs, exit 1 | **killed by SIGPIPE** |
| `-p` | warn, keep going, exit 1 | silent, drop it, exit **0** |
| `warn` | warn, keep going, exit 1 | warn, keep going, exit 1 |
| `warn-nopipe` | warn, keep going, exit 1 | silent, drop it, exit **0** |
| `exit` | warn, **stop at once**, exit 1 | warn, **stop at once**, exit 1 |
| `exit-nopipe` | warn, **stop at once**, exit 1 | silent, drop it, exit **0** |

⛔ **Every non-default row also means SIGPIPE is ignored** — otherwise the kernel kills the process
on the first write to a closed pipe and no row is observable at all. All six match GNU exactly.

⭐ **A disposition is not a handler.** `SIG_IGN` installs no function, uses no stack, needs no
`sa_restorer`, sets no flag for a loop to poll. Architecture 002's four hard rules are about what a
handler may DO; none binds a disposition — which is why these shipped without the flag-based-handler
infrastructure its trigger table anticipates. That table still has no entry that has fired.

Architecture 002's hard rule #1 is amended from "**No utility ignores SIGPIPE**" to "**not by
default, and never without an explicit flag**". The concern it protects — `kriya yes | head -10`
hanging — is untouched: `yes` has no such flag.

⚠ **`--output-error` requires its value**, where GNU accepts a bare form meaning `warn-nopipe`.
[ADR 0002](docs/adr/0002-option-parsing-humans-and-agents.md) rule 3 is *"a flag is either a boolean
or it requires a value — never both"*, and `tee --output-error file` is exactly that ambiguity.
⚠ **`-p` has no long form**, because GNU's does not either — inventing `--pipe-mode` would make a
script written against kriya fail on GNU.

### Fixed — ⛔ two `tee` defects older than this release

- ⛔ **The diagnostic repeated once per 64 KiB.** A failed output was marked `-1` and then handed
  straight back to `write(-1, …)` on the next chunk. Measured on a 200 KiB input: kriya printed
  "no space left on device" **four times** where GNU prints it once.
- ⛔ **The error named the wrong file.** The operand name was recovered as
  `flags_positional(spec, fi - 1)`, which assumes the fd list and the operand list line up — and they
  do not the moment one open fails, because the failed operand is never pushed. Measured:
  `tee nodir/x/y /dev/full ok` reported **"nodir/x/y: no space left on device"**, naming the operand
  that failed to OPEN for an error belonging to `/dev/full`. The reader chases the wrong disk. The
  name travels with the fd now.

### Added — `k_write_forgive(errno)` in `src/lib/sys.cyr`

`k_write` records a sticky write failure and the dispatcher reports it at exit whenever the applet
returned success — right for every other utility, and the exact opposite of what `-p` asks for.
⛔ **Narrow on purpose**: it clears the sticky state only when the RECORDED errno is the one named,
so an applet cannot forgive a failure it never looked at, and a first-recorded ENOSPC still stands.
Verified: `seq`, `echo` and `printf` to `/dev/full` still exit 1 with `write error: no space left on
device`.

### ⭐ How it was checked

⚠ **The first mutation pass found a hole in my own tests, not in the code.** Seven mutations, and
three survived: turning off the SIGPIPE ignore, the EPIPE discount and the write-net forgive all left
the suite fully green — because the `--output-error` block used `/dev/full` for every mode and a
comment claimed it covered the matrix. **A closed-reader pipe is not constructible in portable `sh`,
which is exactly why the coverage was missing.** Adding the pipe half turned all three red; all seven
are red now (1–10 failures apiece).

⭐ **Every claim in architecture 003 was re-measured before it was written down** — the `find -exec`
teardown, the `/proc/self/root` blindness and its cwd counterpart, the `rm -f` no-op, the merged-usr
four-operand kill, and the AGNOS rootfs export. ⚠ **The corpus figure was wrong as first reported**
(a clean "zero matches" that was actually fourteen false ones), and the corrected version — with the
reason each is false — is the one in the note.

### Release totals

**5,223 smoke cases across 41 scripts** (from 5,173) — `smoke-tee.sh` 20 → **49** and `smoke-rm.sh`
82 → **92**. **440 unit**, 18 POSIX; fuzz green under poison; four lints clean; both targets build;
`vet` reports 54 deps.

Binary 1,120,024 → **1,124,496** bytes (+4,472) on host, 1,115,832 → **1,120,304** (+4,472) on agnos.

## [1.6.3] - 2026-08-27 — `realpath`'s flag surface, and a default that had been wrong since v0.4.0

### Fixed — ⛔ `realpath`'s default mode was `-e`, and GNU's is `-E`

GNU's own `--help` says it in one line — *"-E, --canonicalize   all but the last component must exist
(default)"* — and kriya's source comment said the opposite: *"-e / --canonicalize-existing  every
path component must exist (default; alias for the default mode)"* — written when `realpath` shipped
at **v0.4.0** and never questioned since. The tests agreed with the code and
both agreed with a comment nobody had measured.

⛔ **The consequence is not cosmetic.** `realpath build/out` for a file a build is about to create
answers under GNU and **failed here**. So did `realpath dangling-symlink`, and so did any
multi-operand run containing one path whose tail does not exist yet — the whole invocation exited 1.

`-E`/`--canonicalize` did not exist at all; it does now.

### Added — the rest of `realpath`'s flags, and they are TWO axes rather than one list

⛔ **Modelling them as one list of flags is the mistake that makes half of it wrong.**

- **AXIS A — how**: `-P` physical (default), `-L` logical, `-s`/`--strip`/`--no-symlinks`. **One
  mutually exclusive slot, last-wins.** Measured: `-s -P X` prints the resolved path and `-P -s X`
  prints the unresolved one. ⛔ OR-ing `-s` into a separate boolean — the obvious shape, since the
  flag table holds one entry per spelling — makes `-P -s` strip when GNU does not.
- **AXIS B — how hard to look**: `-E` (default), `-e`, `-m`. Also last-wins: `realpath -m -e X` is
  the `-e` answer and `realpath -e -m X` is the `-m` one.

⚠ Neither axis is expressible in the flag table, which keeps a bool per flag with no order, so both
are resolved by an argv walk. ⛔ A precedence rule instead of order only shows up in **generated**
command lines, where a wrapper appends `-e` to a base command that already carried `-m`.

⛔ **`-s` DOES NOT MEAN "DO NOT TOUCH THE FILESYSTEM".** It means "do not expand symlinks in the
OUTPUT". The answer is the lexical form and then that text is `stat`ed unless `-m` is in force:

| | behaviour |
|---|---|
| `-s -m` | the only genuinely lexical combination; nothing is stat'ed |
| `-s -E` | stat the text; ENOENT is forgiven, ELOOP / ENOTDIR / EACCES are not |
| `-s -e` | stat the text; any failure is fatal |

Every one of those is a case a "skip readlink" model gets wrong: `-s -E cycA` is ELOOP, `-s -E
file/q` is ENOTDIR, `-s -E no/such/thing` **succeeds**, and `-s -e dangling` is ENOENT while
`-s -E dangling` is fine. ⛔ `-s -e slink/../f` **fails where plain `-e slink/../f` succeeds** — the
stripped text names a different file than the physical walk does.

`-L` normalises `..` textually FIRST and then canonicalises the result, so `-L slink/../y` is `./y`
where `-P slink/../y` follows `slink` and comes out in its parent. ⚠ The logical treatment is for
`..` in the OPERAND ONLY: a `..` inside a symlink's own target stays physical, measured with a link
whose target is `slink/..`, which both modes answer identically.

### Added — `--relative-to=DIR` and `--relative-base=DIR`

⭐ Both are backed by `path_relative`, the pure-text helper `ln -r` needed at 1.6.2, and by
`path_is_under` — both already component-wise, which is what keeps `/usr/lib` and `/usr/libexec` from
being called common through `lib`.

The decision procedure, measured rather than inferred:

- **`--relative-base=B` alone** — relative to `B` when the operand is under `B` (or equal to it),
  absolute otherwise.
- **Both** — relative to `TO`, but **only when `TO` is itself under `B`**. The manual says it
  plainly: *"DIR1 must be a subdirectory of DIR2. Otherwise, realpath prints absolute file names"* —
  for every operand, including ones that are themselves under `B`.
- ⚠ **An operand equal to `B` does NOT always print `.`**; that only holds when `TO` defaults to `B`.
- ⚠ **A `B` that does not exist still participates in the prefix test** and can silently disable the
  feature.

⛔ **A failing DIR aborts the whole run** — one diagnostic naming the directory, no operands printed,
exit 1. It is the one place `realpath` does not continue past an error, and `--relative-to` is
diagnosed first whatever the argv order. ⚠ **`-q` does not suppress that one**: swallowing it leaves
the caller with no output and no reason.

⚠ **`-e` additionally requires each DIR to BE a directory**, and only `-e`. The check is on the DIRs
alone — an OPERAND that is a regular file is fine in every mode.

### Fixed — ⛔ a trailing slash and a `..` were not directory assertions, and both are

Two defects in the shared `fs_realpath`, so `readlink -f`/`-e` carried them too — and that output is
normally fed straight into the next command:

- ⛔ **`realpath flink/` on a symlink to a REGULAR FILE answered the file, exit 0.** GNU says
  ENOTDIR, and so does `open(2)`.
- ⛔ **`realpath base/plainfile/..` answered `base`, exit 0** — a canonical path built by walking
  THROUGH a regular file. The text was popped unconditionally, with no syscall to contradict it.

⚠ **The assertion only rejects an EXISTING non-directory.** `MISSING/`, `dangling/` and
`real/sub/MISSING/` are all legal; coding it as "a trailing slash means it must be a directory"
refuses three inputs GNU accepts. ⚠ `-m` never asserts either.

⭐ **`df` gets the fix for free, and it had the same defect.** Measured at 1.6.2: `kriya df f/` and
`kriya df f/..` for a regular file `f` both reported a filesystem, exit 0, where GNU errors. `df`
resolves its operands through the same helper, and it now matches GNU on all five shapes.
⚠ **Three utilities, one defect, one fix** — which is the argument for the helper living in
`src/lib/` rather than in whichever utility needed it first.

### Changed — ⭐ `sleep` sums its operands ([ADR 0015](docs/adr/0015-sleep-sums-its-operands.md))

`sleep 1m 30s` is ninety seconds. Every operand is validated **before any sleeping starts** — the
obvious shape, parse one and sleep it, makes `sleep 3600 bogus` block for an hour and THEN report the
bad operand — and every bad operand is named, not just the first.

⛔ **The refusal it replaces rested on a claim not in evidence.** The source said *"POSIX specifies
exactly one"* and the message said *"POSIX sleep takes one integer"*. There is no POSIX text on this
machine to source that from — no `man`, no `man1p`, no `man-pages-posix` — and naming one operand in
a SYNOPSIS constrains what portable callers should write, not what an implementation may accept.
ADR 0011's own test points the other way: kriya ships the binary that `/usr/bin/sleep` is, and that
binary sums and documents summing.

kriya keeps its **decimal-only** grammar rather than inheriting `strtod`. ⛔ **`sleep 0x1d` under
`strtod` is 29 SECONDS, not one day** — the `d` is consumed as a hexadecimal DIGIT and the day suffix
silently disappears. Measured at 29,002 ms. GNU documents the workaround rather than fixing it
(`0x1p-16d` really does sleep 1,320 ms). Inheriting that is a regression dressed as compatibility.

### Fixed — ⛔ three silent `sleep` defects, all pre-existing, all in the dangerous direction

- ⛔ **A 49.7-day sleep returned in 707 milliseconds.** `sleep_ms` hands its argument to `poll(2)`,
  whose timeout is an **`int`**; 2^32 ms truncates to nothing. Measured: `kriya sleep 4294968` — forty
  nine days — returned in **707 ms with exit 0**. ⚠ A retry loop or a boot script believes it waited.
  The total is now slept in one-day chunks, four orders of magnitude below the `int` ceiling.
- ⛔ **A well-formed long duration was reported as malformed.** The accumulator wrapped, the caller
  read the negative result as "not a number", and `kriya sleep 9999999999999999` printed *"DURATION
  must be a non-negative number"* about an operand that was one. Overflow now returns a **distinct
  sentinel** and saturates at ~292 years. ⚠ One error channel for two different failures makes the
  diagnostic lie.
- ⛔ **`--` was counted as an operand.** `kriya sleep -- 0.1` reported *"too many operands"* for a
  command line with exactly one. ⚠ Left unfixed, summing would have turned that usage error into a
  silently wrong TOTAL.

### Fixed — ⚠ and one the summing itself created, caught before release

⛔ **Each operand was truncated to whole milliseconds before being added.** Two thousand `0.0004`
operands are 0.8 s under GNU and were **42 ms** here — every one of them rounded to zero on its own.
`kriya_parse_duration_ms` is now `kriya_parse_duration_us` and the conversion to milliseconds happens
ONCE, on the total. ⚠ Sub-millisecond resolution is still lost at the syscall; it is lost once
instead of per operand. Now measured at 842 ms against GNU's 802.

### ⭐ How it was checked

⭐ **Every rule was MEASURED, not read.** Five parallel research agents probed GNU on this box, and
then five more tried to refute what the first five reported. That second pass changed the
implementation three times — `-s` still stats, `-L`/`-P`/`-s` are one group, and `-e` type-checks the
DIRs are all things the first pass got wrong and the second pass caught with a fresh fixture.

⭐ **A 369-case differential run** over the whole flag matrix — every mode against every how-axis
against a fixture tree of symlinked directories, symlinks to files, dangling links, cycles,
unsearchable directories and paths through a regular file — reaches **0 divergences**, with the
diagnostics normalised for kriya's framing (architecture 001) and GNU's operand quoting.

⚠ **The differential helper was wrong before the code was.** `same_rp` took the test's own
description as `$1` and never shifted it off, so every GNU invocation got that sentence as an extra
operand and returned 1. ⭐ It failed LOUDLY — 65 red assertions — only because the two sides then
disagreed by construction.

⭐ **A differential fuzz over the whole flag matrix**: random trees crossed with every how-axis,
every mode, and the `--relative-*` pair, on operands that include each name bare, with a trailing
slash, with a trailing `..`, and `./`-prefixed. **0 divergences in 4,500 comparisons** across five
seeds, with 1 case in the documented ADR-0014 cycle gap, counted apart rather than compared equal. ⛔ **Its corpus contains the pathological shapes DELIBERATELY** — symlink cycles, unsearchable
directories, symlinks to regular files, dangling links, and paths through a regular file — because
1.6.2's lesson was that a generator which can only build well-formed fixtures is not a fuzzer for
error paths, and those are exactly the shapes these assertions are about.

⭐ **Five mutations, each red in both the fuzz and the smoke suite.** Turning off the `..` assertion
in `fs_realpath` (6/360 fuzz, 2 smoke), turning off the trailing-slash assertion (11/360, 8), making
`-E` behave like `-e` — the defect this release fixes (13/360, 16), making `-s` a boolean beside the
`-L`/`-P` pair instead of the third value of one group (26/360, 7), and turning off the lexical `..`
assertion that `-s` and `-L` share (24/360, 6).

⭐ **Seven more after the review, one per fix, each red again**: the separator assertion (34 smoke),
the symlink-supplied separator (10), the lexical `.` assertion (20), the operand-overflow guard
(3 in `smoke-rm.sh` — the `rm` that used to delete 128 of 200), `df`'s errno (2), `sleep`'s mid-scan
sentinel (3) and its per-unit fraction (1).

### Fixed — ⛔ **`kriya rm *` on 200 files deleted 128 and exited 0**

A five-lens adversarial review found this in shared code, where it had been since the flag table
arrived. `lib/flags.cyr`'s `_flags_push_positional` is `if (pc >= cap) { return 0; }` — the 129th
operand onward is **discarded, with no error, no flag, and success returned**. Measured:

```
$ ls | wc -l          200
$ kriya rm *          (exit 0, silent)
$ ls | wc -l          72
```

⛔ **A `rm` that deletes some of what it was given and reports success is the worst failure this
project can have.** `cp` was worse in a different way: with 200 sources the DESTINATION was among the
discarded tokens, so it reported *"with multiple sources, the last operand must be a directory"* — a
diagnostic about an operand the user did supply.

⚠ **The cap is upstream and stays upstream.** What kriya owes is a refusal rather than a silent
truncation: `kriya_args_parse` now counts what the parser was handed — over the EXPANDED argv, so the
classification is `flags_parse`'s own — compares it with what the table kept, and exits 2 when they
differ. ⭐ Exactly 128 operands still works, and so does 128 plus a flag; the guard is not a
threshold, it is a comparison.

⚠ **A refusal is the safe stopgap, not the destination.** `rm *` on a directory with 200 files is an
ordinary thing to do and GNU has no such limit — kriya now says no where it used to lie. Filed as
**1.6.8**: stop routing operands through the flag table at all, and iterate them from the expanded
argv the parser already builds. That touches every utility, which is why it is not a patch inside
this release.

### Fixed — ⛔ the trailing-slash assertion read the OPERAND, and three spellings say the same thing

The first version of this release's fix looked at the last byte of argv. That caught `flink/` and
missed every one of these, each confirmed against GNU:

- **`realpath dir/file/.`** — a `.` component is the same directory assertion, and there is no
  trailing slash on the operand at all. Answered the FILE, exit 0. So did `dir/file/./.`.
- **A separator arriving from a SYMLINK'S OWN TARGET** — `slashtgt -> base/plainfile/` is ENOTDIR
  under GNU, and argv never sees that slash.
- **A separator arriving AFTER a symlink** — `flink/` expands to the target and the expansion then
  *dropped* the slash, so the assertion had nothing left to see.

⭐ **Moved into the walk, where the separator is visible however it got there.** The rule is now: a
separator after a component asserts that component is a directory — and the stat is the one the walk
already did, so it costs nothing.

⛔ **`-L` and `-s` dropped a trailing `.` outright**, so kriya disagreed with *kriya*: `-P d/nope/.`
refused while `-s d/nope/.` succeeded, and **`-L dang/.` printed `/…/nowhere` — a path that does not
exist — at exit 0.**

### Fixed — ⛔ two more in `sleep`, one of which hangs

- ⛔ **A malformed operand whose digits overflowed first was never fully validated.**
  `sleep 99999999999999999999.1.2` has two decimal points and is plainly broken; the overflow
  sentinel returned mid-scan, so it saturated to ~292 years and **slept**. GNU exits 1. ⚠ A hang is
  the dangerous direction for a typo. Overflow is recorded now and returned after the whole operand
  has been checked.
- ⛔ **The fraction was six digits of the SUFFIX'S UNIT, not of a second.** Six digits of a day is a
  granularity of **86.4 milliseconds**: `sleep 0.0000009d` is 78 ms and returned in **2**. The
  fraction is accumulated in microseconds as it is read, with a running place value that reaches zero
  exactly when the next digit is finer than a microsecond. Now 81 ms against GNU's 81.

### Fixed — ⚠ `df` reported every resolution failure as ENOENT

`fs_realpath` returns ENOTDIR, ELOOP and EACCES too, and `df` printed *"No such file or directory"*
for all of them — so `df somefile/` sent the reader looking for a file that is right there. It also
contradicted [architecture 001](docs/architecture/001-errno-message-policy.md), which says the
message slot is exactly what `errmsg_for` returns.

### Fixed — ⚠ five assertions that could not tell the right answer from the wrong one

The review's most valuable finding was not a defect in the code:

- **The `-L`/`-P` last-wins pair used an operand with no `..`**, so both orders gave the same answer
  and the assertion held against a binary with the ordering scan removed.
- **The `-s -e` vs `-e` contrast pair was ENOENT on both sides** — one file short of distinguishing
  the stripped text from the physical walk. Now `base/onlystrip` and `base/one/onlyphys` exist so
  exactly one path resolves at a time.
- **The ADR-0014 block asserted exit codes only**, so it passed 9/9 against a binary whose
  `realpath -m` printed GNU's stopping point rather than kriya's — the entire subject of that ADR.
- **Nothing combined `-s` or `-L` with a trailing slash**; both slash-preservation paths could be
  deleted with the suite green.
- **ADR 0015 records `sleep 5 --help` and `sleep -- -0` as deliberate divergences and nothing
  asserted either**, so the ADR and the binary could drift apart silently.

⚠ **And the fuzz corpus had `/` and `/..` but not `/.`** — the third spelling of one statement. That
is 1.6.2's lesson exactly, one release later: **a generator that cannot express a shape will never
find the defect in it.**

### Fixed — ⛔ four assertions that were green here and red on CI, for the third time

⛔ **AN OPTION THE ORACLE DOES NOT HAVE LOOKS EXACTLY LIKE A FAILING PATH.** `realpath -E` is present
in this box's coreutils 9.11 and absent from the CI runner's, and GNU rejects an unknown option with
**rc=1 and empty stdout** — byte-identical to *"this path could not be resolved"*. So four
differential comparisons reported kriya as diverging when kriya was right, and one more
(`-m -E nope/deeper`) **agreed by accident**, because an invalid option and a missing parent produce
the same pair.

⚠ **Third time a dev-box-versus-runner version difference has cost this project a release cycle** —
`scripts/check-oracles.sh` already carries the note about 1.3.2 losing two to it, and its header
already says it checks *identity, not version*, because "version differences are legitimate and
unavoidable".

The fix is not to pin a version:

- **`smoke-realpath.sh` probes for `-E` once** and skips those comparisons when the oracle cannot
  play — ⭐ **while still asserting kriya's own answer**, so the flag stays tested exactly where the
  comparison cannot run. Verified by running the whole suite against a shim that rejects `-E` the way
  an older GNU does: 5,163 passed, 0 failed, 5 skipped.
- **`check-oracles.sh` now PRINTS the oracle's version and whether it has `-E`** — informational, not
  a failure, because a version difference is legitimate. ⚠ The next log that shows an inexplicable
  divergence will also show which option surface produced it.

### ⭐ Benchmarks

Three new cases in `tests/kriya.bcyr`, all filesystem-free so the number is the algorithm rather
than the page cache. ⚠ Medians of five runs, because a single run of any of these varies by ~8%:

| bench | avg |
|---|---|
| `path/relative` — `--relative-to`'s whole answer once both operands are canonical | **380 ns** |
| `path/is_under` — the gate `--relative-base` asks per operand | **465 ns** |
| `args/parse_duration_us` — ⚠ now runs ONCE PER OPERAND, a count the caller controls | **42 ns** |

### Release totals

**5,173 smoke cases across 41 scripts** (from 4,795) — `smoke-realpath.sh` 54 → **357**,
`smoke-sleep.sh` 15 → **48**, `smoke-readlink.sh` 24 → **33**, `smoke-df.sh` 18 → **24**,
`smoke-rm.sh` 76 → **82**. ⚠ **5,163 on a runner whose GNU has no `realpath -E`**, where five
comparisons are skipped and kriya's own answer is asserted instead; both shapes are green. **440 unit** (from 406 — the
microsecond parser and both overflow boundaries), 18 POSIX; fuzz green under poison; four lints
clean; both targets build; `vet` reports 54 deps.

Binary 1,111,248 → **1,120,024** bytes (+8,776) on host, 1,107,056 → **1,115,832** (+8,776) on agnos.

⚠ **Cold-start is flat, and the way to know that is to measure both.** Five interleaved rounds of 200
spawns each give medians of **621 µs for 1.6.2 and 605 µs for 1.6.3** — a 2.6% gap inside a per-series
spread of ~50 µs. Flat for four releases running.

⚠ **A pre-existing repo-wide defect measured and filed, not fixed here**: kriya's shared argv layer is
quadratic — 1,000 operands cost 6 ms, 4,000 cost 57 ms and 16,000 cost 826 ms, against GNU's 6 ms. It
affects every utility and predates this release; summing is only what makes a long operand list a
plausible thing to hand `sleep`.

## [1.6.2] - 2026-08-27 — `ln -r`, the target-directory flags, and a comment that was wrong for years

### Added — `ln -r` / `--relative`, and it is not a `..`-counting exercise

⛔ **`-r` CANONICALISES BOTH OPERANDS.** The obvious implementation — count `..` on the strings the
user typed — is wrong in three measurable ways, and every one of them is in the smoke suite:

| input | result |
|---|---|
| `ln -sr slink/sub/f l` where `slink -> real` | `real/sub/f` — the symlinked directory resolves |
| `ln -sr finalsym l` where `finalsym -> real/sub/f` | `real/sub/f` — the target's OWN last component resolves |
| `ln -sr dangling l` where `dangling -> /nowhere` | the relative form of `/nowhere`, not of `dangling` |
| a link created INSIDE a symlinked directory | relative to the REAL directory, not the link's path |

⚠ **ALLOW_MISSING, not REQUIRE_ALL**: `ln -sr nonexistent link` succeeds under GNU and writes
`nonexistent`, so the canonicalisation has to tolerate components that are not there.

⭐ **The algorithm half is a pure helper.** `path_relative(FROM_DIR, TO_PATH)` in `src/lib/path.cyr`
is text only — no filesystem, no symlinks, no normalisation — and `ln` does the resolving before
calling it. That split is what makes it testable: fifteen unit assertions, including the case that
decides the whole thing. ⛔ **The common prefix is COMPONENT-WISE, not byte-wise**: a byte comparison
calls `/usr/lib` and `/usr/libexec` common through `lib` and emits a path into the wrong directory.

⚠ `-r` without `-s` is refused, as GNU does — a flag that rewrites symlink text has nothing to say
about a hard link, and ignoring it would be the accepts-and-lies shape this project keeps removing.

### Added — `ln -T` / `--no-target-directory` and `ln -t DIR` / `--target-directory=DIR`

⛔ **`-T` IS NOT `-n`, and conflating them is the easy mistake.** `-n` asks "is the destination a
symlink TO a directory — if so, replace the link rather than descend into it", and still treats a
REAL directory as a place to link into. `-T` says the destination is a NAME, full stop:
`ln -sT foo existingdir` fails with `File exists` where the bare form creates `existingdir/foo`.
Both halves are asserted.

`-t DIR` makes every operand a source. ⭐ That is the flag's purpose: a command built from a variable
that might expand to one name — or to none — cannot silently reinterpret the last one as a
destination.

### Added — `touch -h` / `--no-dereference`

⛔ **Skipping the create step is the whole point, not an optimisation.** The create is
`open(O_WRONLY|O_CREAT)`, which FOLLOWS a symlink — so without the skip, `touch -h danglinglink`
would create the missing TARGET and then stamp it. Measured: GNU stamps the link and leaves the
target absent, and `touch -h` on a path that is not there at all is an error with no file created.

### Fixed — ⛔ `touch -c` on a missing file exited 1 with a diagnostic, against POSIX *and* GNU

The comment defending it said: *"POSIX says it's still an error (exit 1), GNU agrees"*. Neither is
true. POSIX says **"Do not create a specified file if it does not exist. Do not write any diagnostic
messages concerning this condition."** and GNU exits 0 in silence. The smoke suite asserted the wrong
answer beside the wrong comment.

⚠ **Only the absence is excused.** A `-c` on a file that exists but cannot be stamped — EACCES from
an unsearchable directory — is still an error, because the condition POSIX forgives is the missing
file, not a failure to set the times. ⛔ The first attempt at testing that used a missing file in a
read-only directory, which is still ENOENT and so was excused exactly as it should be: the assertion
said the opposite of what it meant and failed on its first run.

### Fixed — ⛔ six defects an adversarial review found in the flags this release adds

None of them were visible in the cases written beside the feature:

- **`-T` with ONE operand was silently ignored.** `-T` was checked in the two-or-more arm alone, so
  `ln -sT f` fell into the one-operand form and tried to link `f` **to itself**, reporting
  `f: file exists` where GNU says `missing destination file operand after 'f'`.
- **`-t` given twice took the last one.** The flag table keeps only the last value, so a repeat is
  invisible to it — and taking it silently links into a directory the user also named something else
  for. GNU calls it fatal; kriya now does too, via an argv walk.
- ⛔ **A trailing slash on a source operand failed.** `path_basename_ptr` is a pointer-only fast path
  whose own header says *"caller must trim trailing slashes"*, and `cmd_ln` handed it raw operand
  text — so `ln -s f/ dir/` failed with `dir/f/: no such file or directory` where GNU creates
  `dir/f`. ⚠ **Pre-existing in the multi-into-directory arm**, which is why both forms are asserted.
- ⚠ **A `/` source operand aimed at the filesystem ROOT.** `path_join(dir, "/")` yields `/`, so the
  link path became `/` and the attempt reported `/: file exists`. Refused now.
- **`-t` reported every stat failure as ENOENT.** `-t f/sub` where `f` is a file is ENOTDIR, and
  "no such file or directory" sends the reader looking for something that is right there.
- **`-T` with three operands blamed the wrong thing**, saying the last operand must be a directory
  when it *was* one. GNU says `extra operand`.

### Fixed — ⛔ and three more in `touch`, two of them older than this release

- ⛔ **`-h` never reached the `-r` reference lookup.** With `-h`, GNU reads the reference LINK's own
  times rather than its target's — measured, a symlink stamped in 2000 pointing at a file stamped in
  2015 gives 2000 under `touch -h -r` and 2015 without. ⚠ It also makes a **dangling reference
  legal**, which a plain `stat` cannot survive: GNU exits 0 there and kriya exited 1.
- ⛔ **`-r` copied the reference's MTIME into BOTH times.** A single stamp value gave the destination
  an ACCESS time it had never had. Pre-existing, in the function this release edits.
- ⚠ **Every `-h` case in the new tests passed `-t`**, so the plain form — the one that stamps with
  "now" — was untested, and a mutant breaking only that path went unnoticed. The replacement fixture
  stamps the link and the target at DIFFERENT past times, so "moved" and "did not move" are
  distinguishable; with both at "now" the assertion holds whatever the code does. ⚠ **Third release
  running** that a test could not tell the two answers apart.

### Fixed — ⛔ two more, and both reduced to ONE root cause outside `ln`

A third review lens, aimed only at `-r`, found two failures that turned out to be the same defect
seen from two directions — and it was in `fs_realpath`, not in `ln` at all:

- ⛔ **`-r` wrote a WRONG link, silently, with exit 0, whenever canonicalisation failed.** The
  fallback returned the operand text — but operand text is resolved against the **cwd**, while a
  symlink's stored text is resolved against the **link's own directory**. Any link not created in the
  cwd therefore pointed somewhere else, with no diagnostic. ⛔ **The symlink-loop case is the
  damaging one**: `ln -sr loopa out/m` resolved to a *different real file* that happened to sit
  beside the link — the exact failure `-r` exists to prevent.
- ⛔ **`-r` stopped resolving at the first missing component.** A target spelled through a directory
  that is not there — `nonexistent/../slink/sub/f` — yielded a non-canonical link where GNU resolves
  `slink` anyway and answers `real/sub/f`.

**Root cause, one line each.** `FS_REALPATH_ALLOW_MISSING` tolerated **only ENOENT**
(`if (errno != 2) { return sr; }`) and, having tolerated it, **stopped resolving** and appended the
remainder untouched. gnulib's equivalent mode is CAN_MISSING and its rule is simply *a component we
cannot `lstat` is not a symlink* — so commit it and carry on; ENOTDIR and EACCES are ordinary there.
The symlink-loop limit was likewise a hard error in all three modes; under ALLOW_MISSING it now stops
following instead. ⚠ The counter is per-call and never resets, so refusing to follow any further link
still terminates.

⭐ **The blast radius is wider than the report.** `FS_REALPATH_ALLOW_MISSING` is the mode behind
`realpath -m` and `readlink -m` as well, so both carried the same two defects and both are fixed by
the same change — `realpath -m` on a loop now answers the path instead of `too many levels of
symbolic links`, and `realpath -m` through an unsearchable directory answers instead of refusing.
⚠ **The strict modes are untouched and asserted so**: `realpath` and `realpath -e` still refuse a
loop and still refuse EACCES.

### Changed — ⭐ the symlink-traversal limit is now a decided question (ADR 0014)

Extending the `ln -sr` fuzz corpus to contain symlink **cycles** — it had none, which is why 2,363
green comparisons had been sitting on top of a real defect — immediately reported kriya and GNU
landing on different links inside the same cycle. Measuring instead of assuming turned the report
inside out. A cycle's length lets you read the traversal count off the name each side gives up on;
cycles of length 3, 5, 6, 7, 9, 11, 13, 17 and 41 pin it exactly:

| | inside a cycle | a straight chain of N links |
|---|---|---|
| Linux `open(2)` | ELOOP after 40 | ELOOP past 40 |
| kriya `fs_realpath` | stops after 40 | refuses past 40 |
| GNU `realpath` | stops after **20** | resolves **any N** — measured to 121 |

⛔ **The chain column is a GNU defect, not a kriya one.** On a 61-link chain GNU's `realpath` prints
`target` — and GNU's own `cat` cannot open that same name, because the kernel gives up at 40. A
`realpath` answer that no `open(2)` will honour is worse than an error.

kriya keeps **the kernel's 40**, uniformly: an error in the strict modes, a stopping point under
ALLOW_MISSING. The cycle divergence is accepted and written down — every answer inside a cycle is
unresolvable whoever prints it, so only the spelling differs. ⚠ **The fuzz counts those cases apart
rather than comparing them equal**, the way the `cp` fuzz counts the POSIX-ACL gap: loosening the
oracle would hide the next real defect in the same code.

### Changed — a dead function removed from `ln`

`_ln_resolve_dest` had **zero callers** since it was written. It was meant to compose the final
destination for a (target, dest) pair, and `cmd_ln` grew its own inline copy of the same three-way
classification instead — so the file carried two answers to one question, one of them untested and
unreachable. ⚠ Nothing flags this: cyrius reports unreachable functions as a build NOTE with a count
in the hundreds, nearly all stdlib, so one more in the pile says nothing at all.

### ⚠ Scope — `-b`/`--backup` moved out, and it moved for a reason

The roadmap had it in this release. It is not an `ln` flag: `cp`, `mv` and `ln` all take it, its
behaviour is a five-value control matrix rather than a boolean, and it is governed by two environment
variables — `VERSION_CONTROL` and `SIMPLE_BACKUP_SUFFIX`. ⛔ **That last part needs an ADR before any
code.** kriya has declined behaviour-changing environment variables three times (`POSIXLY_CORRECT`
for `echo` and `pwd`, `QUOTING_STYLE` for `ls`), and a backup feature that ignores them is a
different feature from GNU's. Filed as 1.6.5 with the decision named.

`cp -a`/`-d`, `cp -R` of device nodes and `mv --follow` moved out of this release too — they share no
enabler with each other or with `ln`.

### ⭐ How it was checked

⭐ **A differential fuzz for `ln -sr`** over random trees with symlinked directories at several
depths in both operands, dangling targets, targets that are themselves symlinks, targets that do not
exist, and relative/`./`-prefixed/absolute spellings: **0 divergences in 4,935 comparisons** across
four seeds, with 60 cases matching the documented ADR-0014 cycle gap.

⛔ **The corpus could not reach the defect it should have caught, and the reason is structural.**
Every symlink it built pointed at a directory that ALREADY EXISTED and resolved — so a cycle could
never form — and nothing was ever `chmod 000`. ELOOP and EACCES are exactly the two errno families
`FS_REALPATH_ALLOW_MISSING` was mishandling, so 2,363 green comparisons proved nothing about them.
⚠ **A generator that can only build well-formed fixtures is not a fuzzer for error paths**; the
pathological shapes have to be constructed deliberately, because randomness will not stumble into
them. Adding mutual-cycle pairs and one unsearchable directory per tree turned it red on the first
40-case run.

⛔ **The harness was wrong before the code was, for the third release running.** Its fixtures contain
symlinks like `s3 -> ../..`, and several of them COMPOSE — a link name built through three of them
resolves OUT of the tree under test, so both implementations wrote to one shared path, kriya (running
first) created it, and GNU then reported `File exists`. It read as a 2% kriya divergence and reduced,
every time, to identical behaviour in isolation. ⚠ **Nesting the trees deeper only moves the depth at
which it happens**; the sound fix is to notice the escape and not compare that case. 22 were excluded
and counted.

⭐ **Every new feature and every fix was mutation-tested.** Making `-r` textual, making `-h` create,
and making `path_relative` compare bytes instead of components each turned the suite red (6, 4 and 1
failures); so did restoring each of the three `touch` defects (3, 1 and 3) — including the plain-`-h`
path the review had called untestable.

⭐ **The `fs_realpath` fix was mutation-tested in both halves.** Restoring "tolerate ENOENT only"
turned the suite red in 3 realpath cases and 2 `ln` cases; restoring "the loop limit is an error in
every mode" turned it red in 4 and 3 — including the assertion that the loop link does not read as
the unrelated file beside it, which is the damaging shape of the original defect.

### Release totals

**4,795 smoke cases across 41 scripts** — `smoke-ln.sh` 35 → **90**, `smoke-touch.sh` 46 → **80**
and `smoke-realpath.sh` 35 → **54**. ⚠ The measured baseline is **4,687**, not the 4,671 recorded in
1.6.1's note; that figure was taken before the last cases of the release landed. Counted here by
summing each script's own `(N total)` rather than its passing count, so a red case cannot shrink the
corpus silently. **406 unit** (up from 391 —
`path_relative`'s fifteen), 18 POSIX; fuzz green under poison; four lints clean; both targets build;
`vet` reports 54 deps. Cold start 0.813 ms — unchanged, as it has been for three releases.

Binary 1,102,432 → **1,111,248** bytes (+8,816) on host, 1,098,232 → **1,107,056** (+8,824) on agnos.

## [1.6.1] - 2026-08-27 — ownership, extended attributes, and the bit nobody expects

### Added — `cp --preserve=ownership`, and `-p` finally means what GNU's means

⛔ **kriya's `-p` WAS mode + timestamps. GNU's has always been mode + ownership + timestamps.** The
two are indistinguishable until a fixture's group differs from the caller's, which is why six
releases went by without it showing: `cp -p` on a file chgrp'd to a secondary group keeps that group
under GNU and lost it under kriya. `-p` is now `mode | ownership | timestamps`, and the migration for
anyone who wanted the old meaning is `--preserve=mode,timestamps`.

⚠ **A FAILED OWNERSHIP PRESERVATION IS SILENT, and that is GNU's behaviour rather than laziness.**
Measured: `cp --preserve=ownership /etc/hostname out` as a normal user exits **0**, prints nothing,
and produces a copy owned by the caller. GNU only complains when it had the privilege to succeed and
still failed. An implementation that reported an error here would be noisier than the oracle on an
everyday command.

⚠ On `EPERM` the chown is retried as `fchown(fd, -1, gid)` — group only — so a caller who cannot
become the owner still keeps the group when it is one of theirs. ⛔ It does **not** count as
ownership preserved; see the clearing rule below. The retry is reasoned from GNU's source and
confirmed by an independent syscall trace (`fchown(4, 100000, 1000) = -EPERM`, then
`fchown(4, -1, 1000) = 0`, then `fchmod`) rather than by a fixture — constructing one needs a file
owned by someone else whose group the tester is in, which needs root to create.

### Added — `cp --preserve=xattr`, fd-anchored because the audit said so in advance

⭐ **`fgetxattr`/`fsetxattr` between the two open descriptors, never a path.** The M8 security audit
(row 35354, mirroring uutils CVE-2026-35354) wrote the requirement down before the feature existed:
a path-based restore re-resolves every component per call, so a destination substituted between the
write and the restore receives the attributes. The three copy paths were restructured to keep both
descriptors open across the restore rather than the other way round.

⚠ **VALUES ARE BYTES.** An attribute may hold an EMPTY value — which must still be *set*, with size
0 — or embedded NUL bytes. Both round-trip through GNU and both are asserted; nothing in the copy
reaches for `strlen` on a value. ⚠ The kernel's size protocol is used in both halves: `size == 0`
returns the byte count the answer needs, and a short buffer answers `-ERANGE` rather than truncating.

⚠ A source on a filesystem with **no** xattr support answers `ENOTSUP` to the listing, and that is
"nothing to copy", not a failure — otherwise `cp --preserve=xattr` over an ordinary tree would report
an error on every file.

Failures are reported and exit non-zero: `setting attribute 'user.big' for 'DEST': no space left on
device`. ⚠ GNU's own message names the attribute where the filename should be (`for 'user.big'`) —
a formatting bug in libattr's error path, not a rule worth copying. ⚠ GNU is *silent* about the same
failure under `-a`; kriya has no `-a` yet (roadmap 1.6.2), so only the reporting form exists.

### Fixed — ⛔ the set-id bits, and the third one nobody expects

**When ownership was REQUESTED and could not be fully set, the destination's set-id bits come off.**
Otherwise `cp -p /usr/bin/passwd ./mine` yields a setuid binary owned by the copying user, made out
of one that was not. Measured against GNU:

| source `/usr/bin/passwd` (root-owned 4755) | destination mode |
|---|---|
| `cp -p` | **755** — ownership requested, chown failed, bits dropped |
| `cp --preserve=mode,ownership` | **755** |
| `cp --preserve=mode` | **4755** — ownership never requested, nothing to compensate for |

⛔ **THE STICKY BIT GOES TOO.** POSIX names only setuid and setgid; GNU takes S_ISVTX as well, so the
mask is 0o777 and not 0o1777. Measured: `cp -pR /var/spool/mail out` — a root-owned 1777 directory —
yields **777** under GNU, while `cp --preserve=mode -R` of the same source yields **1777**.

⚠ **The first implementation kept sticky, and the test written beside it could not see the
difference**: it used a sticky file the caller *owned*, where the chown succeeds and nothing is
dropped at all. It passed against both masks. An independent syscall-level derivation caught it —
see **How the defects above were found**.

### Fixed — ⛔ cross-filesystem `mv` silently downgraded a file's group and lost its attributes

M8 audit rows 35351 and 35354, measured as live divergences before this release: a file in a
secondary group carrying a `user.*` attribute, moved across a filesystem boundary, arrived with the
caller's group and no attributes under kriya and with both intact under GNU. A move is supposed to
look like a rename, so `mv` now carries mode, ownership, timestamps **and** extended attributes.

### Fixed — ⛔ a plain `cp` carried the sticky bit, and that is older than this release

Found by the differential fuzz, which started generating sticky fixtures only because the new drop
rule needed them: the kernel clears setuid and setgid on an unprivileged `open(O_CREAT)` but **keeps
S_ISVTX**, so a plain `cp` of a 1755 file produced a 1755 destination where GNU produces 755. The
destination file's creation mode is now masked to 0o777 whenever mode is not being preserved.
⚠ Directories are different, and measured: `cp -R` of a 1777 directory keeps the sticky bit under GNU
too, so only the file path masks.

### Changed — every metadata restore now runs on the open descriptor

`_cp_restore_fd` applies **ownership → xattrs → mode → times**, in that order, between the copy loop
and the closes. It replaces three separate path-based restores that ran *after* both descriptors were
closed.

⛔ **The order is the security property, not tidiness.** Ownership before mode, because the reverse
leaves a window in which a file already carrying set-id bits changes owner (audit row 35350). Times
last, so nothing above moves the mtime.

⛔ **And ownership before the XATTRS, which is not obvious and cost a defect.** A chown sets
`ATTR_KILL_PRIV` on every non-directory, so the kernel strips `security.capability` — attributes
written *before* the chown are destroyed *by* it. The first version wrote them first, reasoning that
setting an attribute needs write access. Measured: a file carrying `security.capability` kept it
under GNU and lost it under kriya. ⭐ **A chown that would change nothing is now skipped**, which is
the other half — the strip happens even when the ids are identical, so an unconditional "preserve"
call destroyed a capability it had been asked to keep.

⭐ Directories take the same path: all four calls work on an `O_RDONLY|O_DIRECTORY` descriptor,
because the kernel checks them against the inode's permissions rather than the descriptor's open
mode. The restore still runs after every child is written — it simply runs before the close now.

⚠ **Symlinks are the one exception, by argument.** A symlink has no descriptor to hold, so
`fchownat`/`utimensat` with `AT_SYMLINK_NOFOLLOW` resolve one component against a directory the walk
already has open — the same shape as the `symlinkat` that made the link. Symlinks now carry their own
ownership *and* timestamps under `-p`; they carried neither before. No mode (meaningless on Linux)
and no xattrs (the kernel refuses `user.*` on a symlink outright — measured, EPERM even as the owner).

### Added — `src/lib/sys.cyr` and `src/lib/fs.cyr` grow the primitives

`k_fchown`, `k_fchownat`, `k_fchmod`, `k_flistxattr`, `k_fgetxattr`, `k_fsetxattr`, behind two new
capability flags (`K_HAVE_CHOWN`, `K_HAVE_XATTR`) that are 0 on agnos — which has no ownership model
and no extended attributes — and `fs_xattr_copy` plus the pure `fs_xattr_list_next` walker.

⚠ `flistxattr` returns NUL-terminated names laid END TO END, not an array and not one string;
mis-walking it would read attribute names that are fragments of the previous one. The walk is a pure
function so it can be tested against a synthetic buffer, and its tests are written to fail on an
off-by-one in either direction.

⭐ Every syscall number and argument order was verified against the running kernel before anything was
built on it — including the `-ERANGE` and `-ENODATA` returns, and that `utimensat(fd, NULL, …)` really
is `futimens`.

### Fixed — ⛔ `system.posix_acl_access` was copied, silently granting access

**A POSIX ACL is stored AS an extended attribute**, so a walk that copies every name copies the ACL —
and setting it **changes the destination's effective permissions**. Measured: a 0600 file with
`g:docker:rwx` came out **0670 with the ACL** under kriya and **0650 with none** under GNU, which
excludes the namespace through libattr's `/etc/xattr.conf`. The whole `system.` namespace is now
skipped. ⚠ `security.*` is deliberately **not** excluded — GNU carries `security.capability`.

### Fixed — ⛔ a cross-filesystem `mv` onto a filesystem without xattr support left the file in BOTH places

The restore failed, `_mv_cross_fs` returned before the unlink, and a move did not move.

⚠ GNU has **three** behaviours here where kriya had one, and the third was found only after a review
pass questioned the second. GNU picks its error handler on whether the attribute set was named:

| | reports? | exits |
|---|---|---|
| `cp --preserve=xattr`, any failure | yes | **1** |
| `mv`, ENOTSUP (no xattr support at all) | **no** | 0 |
| `mv`, any other failure | **yes** | 0 |

So a `mv` that merely could not *fit* an attribute warns and still moves the file, while a `mv` onto a
filesystem that has no attributes at all says nothing. "Carry xattrs", "report a failure" and "fail
on a failure" are three separate decisions, and kriya now makes all three the way the oracle does.

### Fixed — ⛔ a cross-filesystem `mv` MERGED into a non-empty destination directory and destroyed data

`mv tree DEST/` where `DEST/tree` already held files: kriya copied the source over it with `-f`,
overwrote same-named files, exited **0** and removed the source. The pre-existing data was gone.
⛔ Worse on failure — the ADR-0009 rollback then recursively deleted `DEST/tree`, a destination this
`mv` had not created.

⚠ **The same command on ONE filesystem already refused.** The same-filesystem arm gets the guard free
from `rename()`, which answers `ENOTEMPTY`; the cross-filesystem arm had none, so `mv` disagreed with
itself depending on which device the operands were on — and the disagreement is what turned a
divergence into data loss. Measured: GNU exits 1 with `unable to remove target: Directory not empty`
and leaves both trees intact. ⚠ An **empty** destination directory is still replaced, which is what
`rename()` allows on one filesystem and what GNU does across two.

### Fixed — ⛔ a set-id destination existed, fully privileged, before a byte was written

`cp -p` of a set-user-ID source created the destination **at the source's full mode** and only dropped
the bits at the end — so for the whole duration of the copy a set-user-ID file owned by the copying
user sat in a directory someone else might reach. The set-id bits are now withheld at create time and
put back by the restore, which `--preserve=mode` guarantees will run.

⚠ **Directories are not masked**, and that is measured rather than an oversight: `cp -R` of a 1777
directory keeps the sticky bit under GNU, and a directory's mode is only restored when
`--preserve=mode` is set, so masking there would drop the bit permanently on a plain recursive copy.
GNU withholds the group and other *write* bits on directories instead and adds them back
unconditionally at the end; kriya has no unconditional restore, so ⛔ **the directory half of this
window is still open** — under a permissive umask a destination directory is world-writable for the
duration of a recursive copy. Filed for 1.6.2 with the ACL work, because both want the same
unconditional-restore machinery.

### Fixed — ⛔ an ownership failure was never reported, even when kriya had the privilege to succeed

`cp -p` returned success on a copy whose owner it had silently changed. ⚠ GNU draws the line at
`geteuid() == 0`, not at whether the call could have worked: an unprivileged `cp -p` of a root-owned
file is an everyday command that cannot preserve ownership, and saying so every time would be noise —
but a root-run backup needs to hear it. kriya now reports `failed to preserve ownership for 'DEST'`
and exits 1 in exactly that case, matching GNU's wording and status.

⭐ **Reachable on an unprivileged runner**: inside `unshare -Ur` the caller is uid 0 while a
root-owned file outside appears as the unmapped 65534, so the chown fails `EINVAL` with full
`CAP_CHOWN` in hand.

### Fixed — ⛔ a cross-filesystem `mv` of a SYMLINK dropped the link's own ownership and timestamps

A third path again: the symlink arm recreates the link with `readlink` + `symlink` rather than going
through `cp`, so it never gained the metadata `cp` learned to carry. A symlink moved across a
filesystem boundary arrived owned by the caller and stamped now — the exact surface M8 audit row
35351 names, one operand type over. Measured against GNU, which keeps both.

### Fixed — three narrower defects in the xattr size protocol

⛔ **The value re-fetch passed the probed size rather than the buffer capacity**, so an attribute that
grew between the probe and the fetch produced an unconditional `-ERANGE` even though the room to hold
it was already allocated. ⛔ **`ENODATA` was exempted at the probe and treated as a hard failure one
syscall later** — the same vanished-attribute race, counted both ways. ⛔ **The list sentinel could
write one byte past its buffer** when the name list grew by exactly the slack available.

### Fixed — ⛔ the diagnostic's reason was empty on the only two errnos this path produces

`errmsg.cyr` covers 1..40 and `cp --preserve=xattr` produces `ENODATA` (61) and `EOPNOTSUPP` (95) —
so the one failure worth reporting printed `…: ` and a newline. Both errnos are now in the table, per
that module's own stated rule that higher numbers land when a utility needs them, and the call site
gained the numeric fallback its header always promised.

### ⚠ Scope — POSIX ACLs are not preserved, and the gap is wider than "an attribute is missing"

⛔ **GNU carries a POSIX ACL as part of MODE preservation** — its own `copy_acl`, a separate path from
the xattr copy — so `cp -p` and `cp --preserve=mode` both carry it while `--preserve=xattr` does not.
kriya has no ACL path, and the `system.*` exclusion above (right for the xattr path) leaves nothing
carrying it.

⚠ **The consequence is a silent over-grant, not merely a missing feature.** The source's `st_mode`
group bits ARE the ACL mask, so copying the mode literally gives the destination's own group the
*mask's* permissions where GNU gives it the *group entry's*. Measured on a 0640 file with
`g:<grp>:rwx`: GNU's copy is `group::r-- group:<grp>:rwx mask::rwx`, kriya's is `group::rwx` — and
**both report `st_mode` 0640**, which is exactly why nothing noticed until a fuzz fixture grew an ACL.
Asserted as kriya's own answer in the smoke suite and counted separately by the fuzz (880 of 3,240
comparisons) rather than hidden. Filed for 1.6.2 with the other `cp` stragglers.

### ⭐ How the defects above were found

⚠ **Not by the smoke suite**, which was green at 76/76 while the sticky bit was wrong. Two passes:

- **An empirical derivation of GNU's behaviour**, run independently of the implementation. `strace` is
  not installed on this machine, so it wrote a `ptrace`-based tracer in C to get the syscall sequence —
  which is what produced the group-only-retry evidence and, in the same matrix, the 1755 → 755 row that
  showed the sticky bit being cleared.
- ⭐ **A differential fuzz over the whole `--preserve=` matrix** — 18 flag combinations × recursive and
  non-recursive, over random trees carrying setuid, setgid and sticky modes, secondary-group
  ownership, past timestamps, empty/binary/long extended attributes, POSIX ACLs, hard-link groups,
  symlinks and symlinks to ancestors — comparing owner, group, mode, mtime, the full attribute set and
  the hard-link partition of every destination path. **0 divergences in 3,240 comparisons**, with
  880 of them classified as the documented ACL gap rather than dropped from the corpus.
- ⛔ **An adversarial review pass, one agent per lens, each finding verified by reproduction before
  being believed.** ⭐ **Fifteen defects, zero refuted: thirteen fixed here, two filed** — including
  the data loss above, the `security.capability` ordering, the ACL copy, and every one in the `Fixed`
  sections that the fuzz did not find. The two filed are the POSIX ACL gap and the directory
  create-mode window, both named in **Scope** above with what closing them needs. ⚠ **Second release
  running** that the review found more than the tests written beside the feature did, and by a wider
  margin than the first.

⛔ **The harness was wrong first, again.** Its initial run reported 0.06% divergence, all of it the
same shape: an unpreserved mtime is "now", the two implementations run seconds apart, and the pair
straddles a second boundary. Normalising a recent mtime to a sentinel took it to zero without a line
of kriya changing. ⚠ Second release running that the fuzz needed a fix before its rate could be
believed.

### ⭐ Verified in the ubuntu:24.04 container again, which had lapsed

⚠ The container condition — the full smoke suite inside `ubuntu:24.04` as a NON-ROOT user, against
coreutils **9.4** rather than this box's 9.11 — was last performed at 1.5.3 and skipped for 1.6.0.
It ran for this release: **4,593 cases across 41 scripts, zero failures.**

⭐ **It is also what proved the new script's probes work**, which is the reason it mattered more than
usual here: the container has no secondary group for the test user, no usable user namespace, no
`/var/spool/mail`, and an overlayfs that refuses an oversized attribute. All four cases **skipped with
a line saying exactly what was left unverified** — 53 passed, 0 failed, 4 skipped — rather than
aborting the script under `set -e` or, worse, passing vacuously.

### Release totals

**4,671 smoke cases across 41 scripts** (up from 4,561/40) — the new `smoke-ownership-xattr.sh`
carries **109**, and it probes for everything it needs rather than assuming: a secondary group, `user.*`
xattr support on the actual filesystem, a user namespace, a second filesystem, and a root-owned setuid
binary. ⭐ `unshare -Ur` is what makes the ownership-SUCCEEDS path testable on an unprivileged runner.

**391 unit** (up from 367 — the xattr name walk, the clearing mask and the two errnos), 18 POSIX; fuzz green under
poison; four lints clean; both targets build; `vet` reports **54 deps** (no new dependency — both new
syscall families are raw wrappers in `src/lib/sys.cyr`).

Binary 1,093,928 → **1,102,432** bytes (+8,504) on host, 1,089,736 → **1,098,232** (+8,496) on agnos.

⚠ **Cold-start is flat, and the way to know that is to measure both.** Five runs of each binary
back to back on the same box give a median of **0.884 ms for 1.6.0 and 0.899 ms for 1.6.1** —
indistinguishable, with the samples interleaving. ⛔ An earlier single run of this release read
0.599 ms and was very nearly written down as an improvement; it was one sample on a quiet moment, and
the previous release reads the same way under the same conditions. **A cold-start number is only
meaningful against the previous binary measured in the same minute**, which is what this project's
"flat from vX" phrasing has always meant and what a single absolute figure quietly stops proving.

## [1.6.0] - 2026-08-26 — hard links, and three walks that could not come back

### Added — `src/lib/fs.cyr` gains a `(st_dev, st_ino)` set, and two utilities share it

⭐ **One helper, two callers.** `cp --preserve=links` needs to know which destination it already
wrote for an inode; `du` needs to know whether it has already counted one. Same question, one
open-addressed hash — `fs_inoset_new` / `_find` / `_add` / `_data` / `_count`, plus `fs_nlink` /
`fs_dev` / `fs_ino` accessors on a 144-byte stat buffer. See
[ADR 0012](docs/adr/0012-hard-link-awareness.md).

⚠ **A repeat insert keeps the FIRST payload.** Not an implementation detail: it is what makes the
destination `cp` links to, and the name `du` charges the bytes to, the one the walk reached first.

⛔ **Every intermediate in the hash has to stay positive.** Cyrius `>>` is an ARITHMETIC shift, so
one multiply overflowing into the sign bit poisons the mask below it and the index comes back
negative — a load off the FRONT of the slot array rather than a wrong-but-harmless bucket. The
multipliers are sized so the widest input (a 32-bit half of `st_ino`) cannot push the running sum
past 2^56, and four assertions pin it at the extremes the kernel can actually produce. Filed as
**M15h** on the standing codegen watchlist, because the shape is not specific to this hash.

### Added — `src/lib/fs.cyr` also gains a walk-ancestor STACK, which is not the same thing

⛔ **A SET OF EVERY DIRECTORY EVER VISITED ALSO STOPS A SYMLINK LOOP, AND IT IS WRONG.** Two
symlinks pointing at one directory are not a loop. Measured: `du -alL` over `real/`, `link1 -> real`
and `link2 -> real` counts **12 blocks** under GNU; the visited-set answered **4**, silently dropping
two of the three paths — and `-l`, whose entire job is to stop deduplicating, could not turn it off.
Only membership of the **current path** means "descending here would not terminate".

`fs_dirstack_*` is that stack: push on descend, pop on unwind, linear scan because tree depth is tens
and a hash costs more to maintain across push/pop than it saves. ⚠ Its unit tests are written to fail
if it is ever "simplified" back into a set — a pushed-and-popped directory must read as absent.

### Added — `cp --preserve=links`, refused by name since v1.2.1

Two source names sharing an inode become two names for **one** destination file. Verified against GNU
on five shapes: two names in one directory, names in different subtrees of one tree, separate
command-line operands (recursive and not), hard-linked **symlinks**, and `-L` folding a file plus two
symlinks to it into a single three-name group.

⛔ **WHICH INODES ARE TRACKED FOLLOWS THE SYMLINK POLICY, NOT THE LINK COUNT.** `st_nlink > 1` proves
"cannot be reached twice" only while you are not dereferencing. Measured: `cp -RL --preserve=links`
over a directory holding one file and two symlinks to it produces one inode with three names — and
all three entries report `st_nlink == 1`. So the gate is `follow || st_nlink > 1`, where `follow` is
the `_cp_should_follow(policy, top_level)` the caller already computed. Non-recursive `cp`
dereferences unconditionally (POSIX) and passes `follow = 1`. GNU's gate is
`1 < st_nlink || command-line-arg-with--H || -L`; this is the same rule reached from kriya's own
policy enum.

⚠ **The master destination is remembered as a PATH, not a dirfd.** The recursion is fd-anchored and
closes each directory fd as it unwinds (ADR 0003), so the fd-shaped identifier does not survive the
walk — and holding one open per hard-link group would exhaust `RLIMIT_NOFILE` on a tree with a few
thousand groups. Both sides of the `linkat` go through `AT_FDCWD` because `fs_linkat` on agnos routes
to the path-based `k_link`, which returns `-ENOSYS` the moment either dirfd is real.

⛔ **A FAILED LINK IS A FAILED COPY.** `cannot create hard link 'X' to 'Y': <errno>`, and the operand
fails. It does **not** quietly fall back to an independent copy — that is exactly the accepts-and-lies
shape v1.2.1 went through `cp` to remove, and GNU errors here too.

### Added — `du` deduplicates by `(st_dev, st_ino)`, and `-l` / `--count-links` turns it off

⭐ **On this machine's `/usr` — 204,110 files, 2,917 of them hard-linked — kriya and GNU now agree to
the byte, in both directions**: `20676544` with the dedup and `20724132` with `-l`, against GNU's
`20676544` and `20724132`. The dedup is worth 47,588 KiB, or 0.23% — small enough to have been
invisible and large enough to have been wrong.

⛔ **A REPEAT PRINTS NO LINE AT ALL, not a zero line.** Under `-a`, the second and third names of a
hard-linked file are absent from the output entirely. Measured; the distinction is invisible until
you diff.

⚠ **This changes `du`'s default output** for any tree containing a hard link — see **Breaking**.

### Fixed — ⛔ `cp -f a/f b/f dst/` overwrote its own first copy, and with `--preserve=links` it DELETED it

Both operands resolve to `dst/f`. kriya copied `a/f`, then silently overwrote it with `b/f` and
exited 0, where GNU refuses the second operand with `will not overwrite just-created`. That was a
divergence for as long as `cp` has existed here — and `--preserve=links` turned one spelling of it
into **data loss**: with both operands on one inode, the link path unlinked `dst/f` and then tried to
link it to itself, leaving *nothing at all* where a pre-existing file had been.

⭐ The guard is a set of every non-directory destination the invocation created, and it is
**unconditional** rather than part of `--preserve=links` — a guard that protects one option's users
and not the others leaves `cp` inconsistent with itself. ⚠ Directories are deliberately not recorded:
`cp -R a b dst/` is supposed to MERGE two trees that share a subdirectory name, and GNU merges them.

⭐ The same guard closes a subtler shape the link map had opened: the map stores a destination PATH,
and a later operand could legitimately overwrite that path under `-f`, leaving the entry pointing at
another file's bytes — after which a third operand sharing the first's inode linked to the **wrong
content** and exited 0. Refusing the overwrite that makes the entry stale removes the possibility
rather than patching the symptom.

### Fixed — ⛔ `cp -RL` and `du -L` over a symlink cycle both DUMPED CORE

Three commands to reproduce either: a directory, a file in it, and `ln -s .. dir/up`. Nothing
remembered which directories the walk had entered, so both recursed until the stack died — and `cp`
wrote a real directory at every level on the way down, leaving the half-built tree on disk. GNU
answers the same tree in milliseconds. ⚠ `cp`'s existing in-tree guard could not see it: that one is a
textual `path_is_under` prefix test, and this cycle is made of a symlink.

Both now match GNU byte for byte — `cannot copy cyclic symbolic link 'dir/up'` and exit 1 for `cp`;
for `du`, a silent skip and exit 0, with `-l` or without it.

### Fixed — ⛔ `cp -RL` also copied its own destination into itself, and GNU does not close this one

The other half of the runaway: a symlink that escapes the source tree into a directory which
**contains** the destination. ⚠ **GNU wrote a 1,536-entry `dst/up/dst/up/…` tree and stopped only
when the path exceeded the filesystem's limit, exiting 0.** kriya wrote **11,635 entries and dumped
core**. kriya now records the destination root's `(st_dev, st_ino)` per operand and refuses to
descend into it — 3 entries on that input, the real content and nothing else. A deliberate deviation
from the oracle (ADR 0012), in the direction the in-tree guard already takes.

### Fixed — ⛔ `--preserve=mode` also preserved timestamps, and `--preserve=timestamps` also preserved the mode

`preserve` was a single bit meaning "mode AND timestamps", so both attributes were accepted and
neither did what it said. It is now a bitmask, which is also what makes `links` expressible at all.
Measured against GNU with a mode of `0777` under umask `022` — the fixture matters, because at `0741`
the umask does not bite and an unpreserved destination comes out `0741` anyway:

| Form | mode | mtime |
|---|---|---|
| `-p`, bare `--preserve` | `777` | preserved |
| `--preserve=mode` | `777` | **now** |
| `--preserve=timestamps` | `755` | preserved |
| `--preserve=links` | `755` | **now** |
| no preserve flag | `755` | now |

⚠ **The forms are CUMULATIVE**, matching GNU: `-p --preserve=links` is all three. ⛔ And that took two
attempts. The first wrote the bare-form bits inside one arm of an `if` and the OR inside the other,
so the list always replaced `-p` rather than accumulating — and `cp -p --preserve=links` silently
dropped mode and timestamps. ⚠ **The smoke case meant to catch it passed anyway**, because it compared
the copy's mtime against a fixture created seconds earlier: both were the current second, so the
assertion held whether or not anything was preserved. Its replacement stamps the fixture in 2020.
⛔ The flag table cannot answer "was a BARE `-p` given" on its own — `-p`, `--preserve` and
`--preserve=LIST` all set the same bool — so `cp` now walks argv once to ask.

`ownership`, `xattr`, `context` and `all` are still refused **by name** with exit 2 — widening the
accepted set is 1.6.1's work, not a loosening of the check. ⚠ **`mv` rides on this path** and now
passes `CP_PRES_P` rather than a literal `1`, which would mean "mode only" and silently drop the
mtime a cross-filesystem move is supposed to carry.

### Fixed — three older `du` defects found beside the code being changed

⛔ **`du *` in a directory of more than 512 entries smashed the heap.** A fixed 512-slot operand array
with no bound check, reachable from a glob. Sized to argv now, so the store cannot overrun by
construction.

⛔ **`du -cS` reported a total that no line in its own output added up to** — 4 where GNU said 12.
`-S` strips subdirectories out of a directory's own line, and the grand total was summing those
stripped values instead of the tree. The walk now carries two running totals: what the line shows,
and what the subtree actually is.

⛔ **A child whose stat failed was dropped in silence, and `du` exited 0** over a tree it could not
read. ⚠ `-L` makes it easy to reach — a broken symlink answers ENOENT and a self-referential one
ELOOP, where the default `-P` lstat succeeds on both. Both are now named on stderr with exit 1, as
GNU does.

### Fixed — ⛔ `cyrius bench tests/kriya.bcyr` had not compiled since v1.3.0, and nothing noticed

Two missing includes: `true.cyr`/`false.cyr` read `HELP_POS_UNBOUNDED` and call `help_begin`, and
`args.cyr` has intercepted `--help` through `help.cyr` since v1.3.0. ⚠ CI runs `cyrius test` and never
`cyrius bench`, which is how a benchmark suite rots for five releases without a red build. The M15e
include trap, for the fourth time. The bench gained `fs/inoset_insert` and `fs/inoset_lookup_miss`.

### Changed — a dead `du` long-option branch

An `nlen == 14` block compared `"separate-dirs"` at length **13** and could never fire (the correct
`nlen == 13` block sits three lines below it, and carried the comment `# 13 — no`). Removed; every
long option `du` accepts is now asserted in the smoke suite.

### Breaking — `du` deduplicates by default

`kriya du` over a tree containing hard links now reports fewer bytes than it did at 1.5.3, because it
stops counting one file once per name. This matches GNU, and it changes the default output of every
such run.

**Migration**: add `-l` (or `--count-links`) to restore the pre-1.6.0 accounting exactly. A script
that parses `du` totals across the upgrade will see them move; one that compares kriya against GNU
will see them stop moving.

### ⚠ Scope — `du` tracks a narrower set than GNU, and here is the measurement that decided it

GNU's device-inode set holds **every file it counts** and costs about **one bit per file**: 200,000
files added 20 KB to peak RSS, and `/usr`'s 204,110 added 36 KB. That is a sparse structure.
`fs_inoset_*` is a 32-byte-per-entry hash — the same set would be ~6 MB live plus ~6 MB abandoned by
the doubling, against a `du -s /` that could plausibly walk ten times as many files. So kriya inserts
only what it must: every command-line operand, every directory, every non-directory with
`st_nlink > 1`, and — under `-L`, where a link count of 1 stops proving anything — everything.

⭐ **But the set is CONSULTED for every entry, including the ones that are never inserted.** A lookup
is one probe into a table the walk is already carrying, benchmarked at **16 ns** against roughly a
microsecond for the `stat` that precedes it. Checking costs nothing, and it closed half the
reachable-twice shapes for free.

⚠ **The residual is one shape, and it is asserted rather than hidden**: an operand naming a
*single-link, non-directory* file that an *earlier* operand's walk already counted. `du DIR DIR/file`
lists the file where GNU omits it; `du DIR/file DIR` matches GNU exactly, and the directory spelling
is closed. `scripts/smoke-hardlinks.sh` pins kriya's own answer for that case, so the day the sparse
structure lands (roadmap 1.7.3) the assertion flips to a GNU comparison and says so out loud.

⚠ Under `-L`, where kriya does track everything, peak RSS on a 200,000-file tree is **39 MB against
GNU's 10 MB**. ⛔ And the larger number in the same measurement is not from this release at all:
`kriya du -s /usr` peaks at **68 MB against GNU's 7.7 MB** with the dedup switched off entirely,
because `_du_walk` bump-allocates a 4 KiB `getdents64` buffer per directory and a joined path per
entry and frees neither. Filed with the sparse structure; both are `du` memory, one pass.

### ⭐ How the defects above were found

⚠ **Not by the smoke suite, which was green at 86/86 while `cp` was deleting files.** Two passes
found everything in the `Fixed` sections:

- **An adversarial review** over the diff, one agent per lens (memory safety, `cp` correctness, `du`
  correctness), each finding independently verified by reproduction before being believed. It caught
  the data-loss path, the non-cumulative `-p`, the visited-set-versus-ancestor-stack error, and the
  three older `du` defects.
- ⭐ **A differential fuzz against GNU** over randomly generated trees — hard-link groups, symlinks to
  files, to directories, dangling, hard-linked symlinks, and symlinks to ancestors — comparing `du`
  across a 20-flag matrix and one-, two- and reversed-operand forms, and comparing `cp`'s destination
  by **inode PARTITION** rather than by name, since which name holds the real copy is readdir-order
  dependent. It found both `-L` runaways.

⭐ **After the fixes: 0 divergences in 22,200 `du` comparisons and 0 in 2,220 `cp` comparisons**,
across two runs at different seeds. ⚠ The one documented `du` shape is classified separately and hit
1,870 times — a residual that is *counted*, not one that is quietly absent from the corpus.

⛔ **The fuzz harness needed fixing before it could be believed, twice.** With both destinations
beside the source, a `..` symlink made each implementation walk into the *other's* output — so the
first run "found" kriya runaways that were kriya faithfully copying a giant tree GNU had just written
next to it. Isolating source and destinations in separate parents took the cp divergence rate from
2.08% to 0.00% without a line of kriya changing.

### Release totals

**4,561 smoke cases across 40 scripts** (up from 4,418/39) — the new `smoke-hardlinks.sh` carries
**138** of them, and `smoke-option-forms.sh` flipped its `--preserve=links` case from "refused" to
"accepted". **367 unit** (up from 322 — the inode set, the ancestor stack), 18 POSIX; fuzz green under
poison; four lints clean; both targets build; `vet` reports **54 deps** (no new module — the roadmap
put the helper in `src/lib/fs.cyr` and that is where it went).

Binary 1,080,848 → **1,093,928** bytes (+13,080) on host, 1,076,656 → **1,089,736** (+13,080) on
agnos. Cold-start median **0.673 ms**, well under the 2 ms v1.0 target.

⭐ **Bench**: `fs/inoset_lookup_miss` **16 ns** — the per-entry cost every `du` walk now pays, against
roughly a microsecond for the `stat` in front of it. `fs/inoset_insert` 286 ns amortised over a
million distinct keys, the spikes being the rehashes. End to end that is **26 ms against 25 ms** for
`du -s` over a 200,000-file tree with the dedup on and off — 4%, on a walk that is syscall-bound.

## [1.5.3] - 2026-08-26 — quoting, and `pwd` stops trusting `$PWD`

### Added — `src/lib/quote.cyr`, shared by `ls` and `stat %N`

⭐ **GNU shell-escape quoting**, derived byte by byte rather than read off a manual: every rule below
came from running `stat -c %N` over all 255 possible single-byte names plus a splice matrix, under
`LC_ALL=C`, on stock coreutils 9.4 in a container as well as 9.11 here.

- 92 printable bytes go inside single quotes; controls, DEL and **every high byte** become an
  ANSI-C `$'...'` run — named escapes where one exists, three-digit octal otherwise.
- ⚠ **Adjacent escaped bytes SHARE one `$'...'` run** (`a<TAB><TAB>b` is `'a'$'\t\t''b'`), a name
  STARTING with an escape emits an empty `''` first, and one ENDING with an escape does not get a
  trailing `''`.
- ⛔ **Quote selection is not "always single quotes".** A name containing `'` uses DOUBLE quotes
  (`it's` → `"it's"`) — but only if every other byte is in a specific safe set, measured by probing
  `a'b<X>` for every printable X. ⚠ That set is **not** the same as "needs no quoting": SPACE and
  `]` are safe there while `=` is not, and `[` forces single-quote style while `]` does not.
- ⛔ **`#` is double-quote-safe ONLY at index 0.** `#a'b` takes double quotes and `a'b#` does not.
  It reads backwards — `#` starts a comment at word start, not mid-word — and it is what quotearg
  does.

⭐ **286 single-byte and splice cases: zero divergences. A 3,000-name fuzz over hostile byte
sequences: 5 divergences (0.17%).**

⚠ **The residual is recorded rather than hidden**: it is names combining a `'` with escaped bytes in
particular positions, where GNU emits a leading empty `''` that kriya does not. ⛔ In at least one of
those cases GNU's own output does not round-trip — `<TAB>kcwA'79hp<NL>` renders with a literal
`'\t'`, which a shell reads as backslash-t rather than a tab. Chasing bit-parity into that corner
was not worth it; the shapes are on the roadmap with the measurement.

⚠ **Locale**: under `LC_ALL=C` GNU escapes every high byte, and that is what this implements. In a
UTF-8 locale GNU renders valid multi-byte sequences bare. kriya is byte-oriented here — more verbose
than GNU under UTF-8, never wrong, since the escaped form round-trips identically.

### Added — `stat %N`, and `ls` quoting on a terminal

`stat -c %N` renders the quoted name plus ` -> quoted target` for a symlink. ⚠ It **always** quotes,
unlike `ls`: `stat -c %N plain` is `'plain'`. Same helper, one flag apart.

⛔ **`ls` quotes on a TERMINAL and not through a pipe** — the same command produces different bytes
depending on where it is pointed. That is deliberate upstream: the terminal form is for a human to
retype, the piped form is what scripts have always parsed. Both directions are asserted, and the
piped assertion looks for a WRAPPED name rather than for a quote character, because one fixture is
literally called `it's`.

Two `-l` details that only a byte-exact comparison finds:
- ⛔ **When any name in a listing is quoted, the unquoted ones get a leading space**, so every name
  starts in the same column as the first character inside a quote. An all-plain listing has no
  padding; adding one quoted name shifts every other name right by one.
- The symlink **target** is quoted by the same rules.
- ⚠ Quoting also changes the COLUMN WIDTH — a quoted name is longer, and the layout reserves the
  width it will actually occupy.

### Fixed — ⛔ `pwd` defaulted to logical and trusted `$PWD` blindly

The roadmap called this "`pwd`'s `$PWD` inode-match, which needs only a stat-compare". The
measurement found a bigger bug in two parts:

    PWD=/etc kriya-1.5.2 pwd     ->  /etc        (from a completely different directory)
    PWD=/etc /usr/bin/pwd        ->  the real cwd

1. ⛔ **The default is PHYSICAL, not logical.** POSIX says `pwd` defaults to `-L`; GNU deliberately
   does not, and only `POSIXLY_CORRECT=1` flips it. kriya defaulted to logical. ⚠ kriya matches
   GNU's default and does NOT honour `POSIXLY_CORRECT`, for the reason ADR 0011 gave for `echo`: an
   environment variable set for some unrelated tool should not silently change what this one prints.
2. ⛔ **`-L` validates `$PWD`; kriya checked only for a leading `/`.** POSIX requires an absolute
   path with no `.` or `..` components that names the current directory — so `PWD=/etc` and a `$PWD`
   full of `..` were both echoed back verbatim. The third test is an **inode compare**, not a string
   compare, which is what lets a symlinked path through while rejecting a same-shaped impostor.

⭐ `pwd` now has its own `scripts/smoke-pwd.sh` (13 cases). ⚠ Its oracle is `/usr/bin/pwd`, never the
shell builtin — `pwd` is a builtin in every POSIX shell and the builtin's default is `-L`, which is
exactly the distinction under test.

### Fixed — ⛔ six bytes wrong in `ls`'s bare-character set, found after the fact

⚠ **A background investigation caught this after the release was first reported green**, and the
`stat %N` fuzz could never have: `%N` **always** quotes, so `_q_needs_quote` — the function deciding
whether `ls` leaves a name bare — was not reached by a single one of those 3,000 names.

Measured over all 94 printable bytes at both positions, via
`ls --quoting-style=shell-escape` (byte-identical to the tty default and needing no pty):

- ⛔ **`=` was UNDER-quoted**, and that one is correctness rather than cosmetics: an unquoted `a=b`
  pasted into a shell is a variable **assignment**, not a filename.
- **`]`, `{`, `}`, `#` and `~` were OVER-quoted** — GNU leaves all five bare mid-word.
- ⛔ **Three bytes are POSITION-SENSITIVE**: `#`, `-` and `~` are bare mid-word and quoted as the
  FIRST byte of a name — comment, option and tilde-expansion respectively, each special only at the
  start of a word. ⚠ One lane reported that a leading `-` is *not* quoted; measuring all 94 bytes at
  both positions showed it is, so that reading did not survive.

### Added — `--quoting-style`, which exists to close a test hole

⛔ **Before this flag, 100% of `ls`'s quoted output sat behind a pty**, so on a host without
`script(1)` the whole quoting block skipped — and a mutant `ls` that never quoted scored **21 passed,
0 failed**. Demonstrated in advance rather than discovered in CI. `--quoting-style` moves the
algorithm onto the pipe path and leaves the pty covering exactly one bit: whether a terminal turns
quoting on. ⭐ Re-checked with the same mutant: it now fails 7 assertions **with `script(1)` hidden**
and 8 with it present.

⚠ Only the three styles kriya's helper implements — `literal`, `shell-escape`,
`shell-escape-always` — are accepted; `shell`, `c`, `escape`, `locale` and `clocale` are **refused by
name** rather than silently treated as the default.

⚠ **`QUOTING_STYLE` and `POSIXLY_CORRECT` are now unset on every affected oracle call**, and the
hostile-environment matrix is what found it — four scripts failed under it after the release was
otherwise green. GNU honours `QUOTING_STYLE` in both `ls` and `stat`, overriding the tty/pipe default
in both directions; and `POSIXLY_CORRECT` does two separate things kriya declines: it flips `pwd`
from `-P` to `-L` — the exact axis `smoke-pwd.sh` tests — and it **stops GNU permuting options after
operands**, so `ls f1 f2 -rt` is a sort request to kriya and two more operands to a POSIX-strict GNU.

⛔ **The rule, now stated three releases running**: if kriya does not read a variable, the ORACLE
must not either, or the test measures the shell rather than the code. It first appeared for
`du`/`df`'s `BLOCK_SIZE`, again for `echo`'s `POSIXLY_CORRECT`, and again here. All five matrix
conditions now yield the identical **4,418** cases.

### Release totals

**4,418 smoke cases across 39 scripts** (up from 4,373/38) — `smoke-ls.sh` 105 → **122**,
`smoke-stat.sh` 53 → **65**, and `smoke-pwd.sh` is new at **13**. 322 unit; 18 POSIX; fuzz green
under poison; four lints clean; both targets build. `vet` reports **54 deps** (new
`src/lib/quote.cyr`). Binary 1,072,424 → 1,080,848 bytes (+8,424).

⭐ **Verified under all five matrix conditions**: baseline, hostile env
(`POSIXLY_CORRECT`+`BLOCK_SIZE`+`QUOTING_STYLE`+`LS_COLORS`), `en_US.UTF-8` and deep `$TMPDIR` all
39/39 **4,418**; simulated root 39/39 4,402 (root-only paths skipping).

⭐ **And inside the `ubuntu:24.04` container as a non-root user** — 39 scripts, 0 failures,
4,396 cases.

## [1.5.2] - 2026-08-26 — `ls --color`, and the environment stops having a cliff

### Added — `src/lib/env.cyr`, which had to come first

⛔ **kriya's environment lookup silently missed anything past 8 KB, and `LS_COLORS` is ~1.9 KB.**
The stdlib `getenv` reads `/proc/self/environ` into an 8 KB **stack** buffer and scans only what
fits, so whether a variable is found depends on where the shell happened to put it. ⚠ **That is not
an oversight upstream** — `io.cyr` documents the reason: a function-local `var[8192]` still reserves
stack in the prologue even when the agnos path returns first, and agnos hands ring-3 only ~12 KB of
init stack. The constraint is real; it simply does not apply to a **heap** buffer, which is what
kriya now uses. On agnos there is no `/proc` and the stdlib reads the init-stack envp with no
window, so that path delegates unchanged.

⛔ **Five call sites were affected and `COLUMNS` was the least of them**: `which`, `xargs` and
`find` all look up **PATH**. Demonstrated against the shipped 1.5.1 binary:

    env BIG=<9KB> PATH=/usr/bin  kriya-1.5.1 which ls   -> (nothing)
    env BIG=<9KB> PATH=/usr/bin  kriya-1.5.2 which ls   -> /usr/bin/ls
    env BIG=<9KB> PATH=/usr/bin  /usr/bin/which ls      -> /usr/bin/ls

A command silently not found, with no diagnostic. Filed at M11 as an upstream gap; fixed here
because the fix belongs on kriya's side of the line.

### Added — `--color=WHEN` with LS_COLORS

`--color[=always|yes|force|auto|tty|if-tty|never|no|none]`; bare `--color` means `always`; an
invalid value is a usage error. `--color=auto` colours iff stdout is a tty — verified in both
directions under a real pty. ⚠ `k_isatty` returns 0 on agnos, so `=auto` means no colour there.

⛔ **THE HEADLINE FINDING FROM 1.5.1 WAS HALF WRONG, AND CHECKING IT IS WHY THIS RELEASE IS RIGHT.**
That entry recorded "there is NO per-type table to ship" because `LS_COLORS` unset produces no
escapes at all. True — and it is not the whole rule. Set `LS_COLORS` to any valid key, even one that
colours nothing (`rs=0`), and directories come out `01;34`: GNU loads a **compiled-in default table**
and overlays the variable on top. So kriya needs both the table **and** the gate; shipping either
half alone produces plausible output that is wrong in one direction.

⚠ **`dircolors -p` is NOT the source of those defaults and disagrees with them** — it gives
`BLK 40;33;01` and `FIFO 40;33` where `ls`'s own defaults are `01;33` and `33`. The values shipped
were measured out of `ls` itself, on stock coreutils 9.4 in a container as well as 9.11 here.

Rules that a careful reading would have got wrong, each found by differential fuzzing:

- ⛔ **A code of `""`, `"0"` or `"00"` means NOT COLOURED — but it gates only the SUB-TYPE
  selection, not the lookup.** `di=0` still emits `ESC[0m` around a directory, while `ow=0` falls
  THROUGH to `di`. Filtering it in the obvious place (the lookup) breaks the first case.
- ⛔ **Extension matching prefers an exact-case match and otherwise takes the LAST** — `*.c` alone
  matches `t.C`, but defining both `*.c` and `*.C` makes each exact.
- ⛔ **A broken symlink's `-l` TARGET is coloured, gated on `or` or `mi` being SET** (not
  colourable — `or=0` still enables it), and a missing target takes `mi` if set, else **`or`**.
- ⚠ The leading `ESC[0m` is emitted **lazily**: once, before the first coloured entry, and not at
  all if nothing is coloured. `rs=` overrides it, at both ends.
- ⚠ The `-F` indicator sits OUTSIDE the escape, and `TERM=dumb` does NOT disable colour.
- ⚠ **Cyrius string literals have no octal escape**: `"\033["` is a NUL followed by `3`, not
  `ESC [`. Caught only because the comparison was byte-exact.

⭐ **2,500 randomised differential comparisons against GNU with realistic `dircolors`-shaped values
— zero divergences.** The fuzz drove the whole implementation: it went 378 → 87 → 42 → 35 → 4 → 0,
and every drop was a rule above that inspection had missed.

### ⚠ One measured gap, deliberately not closed

⛔ **`no=` (the "normal" key) positions its prefix at the START OF THE LINE**, before the `-l`
columns and before the `-i` inode — kriya emits it before the NAME. On pathological input the
residual is 140 of 2,500; on realistic input it is **zero**, because ⚠ **a real `dircolors -b` never
emits `no=` at all** (verified on both coreutils versions). Closing it means moving the prefix from
the name to the line, which is a larger change than the key justifies. Recorded on the roadmap with
the measurement rather than left to be rediscovered.

### Release totals

**4,373 smoke cases across 38 scripts** (up from 4,346) — `smoke-ls.sh` 81 → **105**. 322 unit;
18 POSIX; fuzz green under poison; four lints clean; both targets build. `vet` reports **53 deps**
(new `src/lib/env.cyr`). Binary 1,059,680 → 1,072,424 bytes (+12,744).

⭐ **The `k_write` length lint caught one of my own off-by-ones again — fourth release running.**

⭐ **Verified inside the `ubuntu:24.04` container as a non-root user** — 38 scripts, 0 failures,
4,351 cases.

## [1.5.1] - 2026-08-26 — `ls -t` / `-S`, and the sort stops being quadratic

### Added — `-t` (mtime) and `-S` (size) sort keys

⭐ **`ls` sorts by time and size**, the first alternative keys it has had. Every rule was measured
against GNU rather than assumed:

- **Both sort DESCENDING** — newest first, largest first — and **both break ties by NAME ascending**.
- ⚠ **`-t` compares NANOSECONDS, not just seconds.** Two files one nanosecond apart sort correctly
  in GNU, so comparing `st_mtime` alone would be a silent wrong order on any filesystem with
  sub-second stamps. The tie-break test forces an EXACT tie with `touch -d` rather than hoping two
  files created moments apart collide.
- ⭐ **Every key falls through to the name comparison**, which makes the order TOTAL: two distinct
  entries never compare equal, so `-r` is a true reversal rather than a stable-sort artefact.
  Verified — three files given an exact mtime tie come out `a m z` under `-t` and `z m a` under
  `-tr`, so the tie-break reverses too.
- ⛔ **When BOTH `-t` and `-S` are given, the RIGHTMOST wins**: `ls -tS` is a size sort and
  `ls -St` a time sort. `flags_get_bool` cannot answer that — it says "was it given", not "which
  came last" — so `ls` scans argv for the order, clusters included. ⚠ The smoke test asserts that
  the two forms *disagree with each other*, because a pair that both resolved the same way would
  pass while proving nothing.

### Fixed — ⛔ the sort was O(n²), and it showed

**`ls` over an 8,000-entry directory took 0.755 s against GNU's 0.004 s — a 190× gap** on a
directory size that is not unusual. The cause was an insertion sort. Replacing it with a bottom-up
merge sort takes it to **0.022 s, a 34× improvement**, and closes the gap to roughly 5×.

⚠ **This is a scope call worth stating rather than sliding past.** The comparator had to be
restructured for `-t`/`-S` regardless, and leaving a quadratic sort inside the release that is
*about sorting* would have been an odd place to draw the line. The new `-t`/`-S` tests exercise the
new algorithm directly, including the tie and reversal cases where a merge sort's stability matters.

### Fixed — ⛔ two sort defects found AFTER this release was first reported green

**1. A sort flag AFTER the operands was silently dropped — and this release introduced it.**

    ls -1 aa bb cc -rt      GNU: bb cc aa      kriya: cc bb aa

⛔ The `-r` was honoured and the `-t` from the SAME CLUSTER was not, giving name order with exit 0
and empty stderr. ⚠ The cause is one line: `_ls_scan_sortkey` bounded itself with
`kriya_argv_option_end`, which stops at the first operand — while the flags PARSER permutes. Two
independent notions of "the option window", kept in sync by hand.

⭐ **The fix was not to widen the window but to stop having a second one.** kriya's parser already
produces a NORMALISED EXPANDED ARGV — clusters split, long forms normalised, `--` honoured,
permutation resolved — so `kriya_short_seq(spec, ch)` in `src/lib/args.cyr` asks the parser where a
flag last appeared and `ls` compares two integers. Widening the scan instead would have re-created
the same class of bug at the next value-taking option, since `ls -w -t` must not read `-t` as a flag
the parser consumed as the width. ⚠ **Every existing assertion put the flags FIRST**, so none of
them could have caught this; the guard now covers post-operand, between-operand and clustered forms.

**2. The directory-SECTION list was never sorted** — pre-existing, not from this release.

    ls -1 d3 d1 d2      GNU: d1: d2: d3:      kriya: d3: d1: d2:

⛔ Permanently in argv order under EVERY flag; `-t` and `-r` changed nothing. ⚠ The flat
non-directory list WAS sorted correctly, which is exactly why every existing assertion passed. The
section list is now built as records carrying the stat already in hand, and goes through the same
`_ls_sort`.

⭐ Both guards were negative-controlled: reverting fix 1 fails 18 assertions and reverting fix 2
fails 5.

### ⚠ Scope: `--color` is deferred to 1.5.2, and here is the measured reason

The roadmap paired sort keys with "`--color=auto|always|never` with a per-type table and tty
detection". ⛔ **That description does not survive contact with GNU**, and the measurement changed
the shape of the work rather than just its size:

- ⛔ **There is no per-type table to ship.** With `LS_COLORS` unset, `ls --color=always` emits **no
  escapes at all** — no compiled-in default. The table IS the environment variable, so a built-in
  one would make kriya colour where GNU does not.
- The real surface, all measured: ~17 type keys with a **precedence order** (`tw`/`ow`/`st` override
  `di`; `su`/`sg`/`ex` beat an extension match, which beats `fi` — verified: an executable `run.c`
  takes `ex`, a non-executable `plain.c` takes `*.c`); `*.ext` patterns with a **case-folding
  subtlety** (`*.c` alone matches `t.C`, but defining both `*.c` and `*.C` makes each exact);
  `ln=target` indirection; and a malformed `LS_COLORS` making GNU print diagnostics and disable
  colour entirely.
- Emission is exact and easy to get wrong: a **leading `ESC[0m` once per run**, not per line; the
  `-F` indicator OUTSIDE the escape (`ESC[…m adir ESC[0m /`); symlink targets in `-l` left
  uncoloured.
- ⭐ **Escapes do NOT count toward column width** — verified in a pty at 40 columns, the layout is
  byte-identical with and without colour except for the padding note below.

⛔ **And a constraint that may decide the design outright: kriya's `getenv` cannot read a real
`LS_COLORS` reliably.** Upstream `io.cyr` reads `/proc/self/environ` into an **8 KB** buffer and
scans only what fits. A `dircolors -b` `LS_COLORS` is ~1.9 KB, so whether it is found depends on
where the shell happened to place it. Demonstrated with kriya's EXISTING `COLUMNS` read:

    env COLUMNS=80 BIG=<9KB> kriya ls   -> columns          (COLUMNS early, found)
    env BIG=<9KB> COLUMNS=80 kriya ls   -> one-per-line     (COLUMNS past 8 KB, silently absent)
    env BIG=<9KB> COLUMNS=80 /usr/bin/ls -C -w 80 -> columns (real getenv, correct)

⚠ **That is a live latent bug in shipped behaviour, not just a colour problem** — `COLUMNS` already
degrades this way today. It is upstream and out of bounds to fix here, so it is filed at **M11**.
⛔ It also puts the two obvious colour designs in direct tension: honouring `LS_COLORS` matches GNU
but is position-dependent and silent, while a built-in table is reliable but colours where GNU emits
nothing. **That tension is the ADR 1.5.2 has to settle**, and it is recorded rather than pre-decided.

⚠ That is a release of its own, and this entry records the measurements so 1.5.2 starts from data
rather than from scratch. The roadmap entry has been rewritten with all of it.

### ⚠ Two pre-existing `ls` divergences found while measuring, deliberately NOT fixed here

Both predate this release — confirmed against the 1.4.4 binary — and both are now on the roadmap
rather than absorbed silently:

- **`ls -d` with no operand lists the directory's CONTENTS**; GNU lists `.`.
- **Multi-column padding uses spaces where GNU uses a TAB.** Visible only on a tty and only in the
  bytes — the column positions are identical — which is why the piped smoke comparisons never saw
  it. ⚠ GNU switches to spaces when colouring, so 1.5.2 has to know this rule anyway.

### Release totals

**4,346 smoke cases across 38 scripts** (up from 4,303) — `smoke-ls.sh` 49 → **81**,
`smoke-option-forms.sh` 53 → **55**. 322 unit; 18 POSIX; fuzz green under poison; four lints clean;
both targets build. `vet` reports 52 deps. Binary 1,059,568 → 1,059,680 bytes (+112).

⭐ **An assertion going red was the success signal**: `smoke-option-forms.sh` pinned `ls -lart` as a
usage error *because `-t` did not exist*. It now compares against GNU instead of a frozen exit code,
so it cannot go stale the same way twice.

⭐ **Verified inside the `ubuntu:24.04` container as a non-root user** — 38 scripts, 0 failures,
4,324 cases.

## [1.5.0] - 2026-08-26 — the passwd/group parser; `ls -l`, `stat %U`/`%G`, `find -user` get names

### Added — `src/lib/userdb.cyr`, and the three consumers it unblocks

⭐ **`ls -l` shows names, `stat %U`/`%G` render, and `find` grows `-user`/`-group`/`-uid`/`-gid`/
`-nouser`/`-nogroup`.** Before this, `ls -l` printed `1000 1000` where GNU prints `macro macro`,
`stat -c %U` refused by name on stderr, and the find predicates were an unknown-predicate error.

⛔ **A parser and not a library call, deliberately.** `getpwuid(3)` pulls in NSS, and NSS is dynamic
linking by construction — it `dlopen()`s `libnss_*.so` at runtime. kriya is static and zero-dep, so
parsing the files directly IS the design. ⚠ The cost is real and worth stating rather than hiding:
users who exist only in LDAP / SSSD / systemd-homed have no line in these files and will not
resolve. They degrade to numeric ids, which is the safe direction.

⭐ **One module, three consumers**, the argument that lifted `glob.cyr` out of `find` at 1.4.1, the
escape table into `str.cyr` at 1.4.3 and `icase.cyr` at 1.4.5: two implementations of "what is this
uid called" in one binary would be two sets of edge cases that drift apart silently.

### The grammar, measured against glibc rather than read off a man page

Every rule was checked by building a fixture `/etc/passwd` in a container and asking `stat -c %U` and
`getent` what they made of it, on **both** coreutils 9.4 / glibc 2.39 (ubuntu-24.04, what CI runs)
**and** 9.11 / glibc 2.44 (this box). ⭐ Identical on both, so none of it is version drift.

- ⚠ **A passwd line needs at least FOUR fields and a group line THREE.** `f3:x:7001` does not
  resolve; `f4:x:7002:7002` does. Extra trailing fields are accepted.
- ⛔ **A line beginning `#` IS skipped**, which is widely called a myth and is not one:
  `#hash:x:7201:7201::/tmp:/sh` has seven good fields and a valid uid, and `stat -c %U` on a file
  owned by 7201 still prints `UNKNOWN`. The passwd(5) page documents no comment syntax.
- ⚠ **The id field is decimal and a leading `0` does NOT make it octal** — `0006004` is 6004, not
  3076. A leading `+` is accepted.
- ⛔ **LEADING blanks are stripped and TRAILING blanks are not** — in the NAME *and* in the ID
  field, and the asymmetry is real in both: `   leadws:x:8100:8100` is the user `leadws`, while
  `trail :x:...` really is the five-character name `trail `; `n:x: 8600:8600` resolves and
  `n:x:8601 :8601` does not. ⚠ The strip happens BEFORE the prefix test, so `  #indent:x:...` is a
  comment.
- ⛔ **`#`, `+` and `-` lines are refused BY PREFIX, not by field count.** The short NIS forms
  (`+@netgroup`, `+user::::::`) happen to fail the field and id rules, which makes "no special case
  needed" look true — and it is false for the full-field form: `+plus:x:8102:8102::/h:/s` has four
  good fields and a valid id, and glibc's lookup path still refuses it. ⚠ On a `passwd: compat`
  host a `-name` line means EXCLUDE that user, so resolving it as a positive mapping is the worst
  available shape of the bug. ⚠ glibc's own `fgetpwent(3)` disagrees and returns `+plus`; the
  LOOKUP path is what `ls`/`stat`/`find` take, so it is the oracle.
- ⛔ **A passwd line's GID field is validated too, though nothing reads it.** glibc rejects the whole
  line when field 3 is not an id, so checking only the uid resolves users GNU does not:
  `badgid:x:8300:notanumber`, `emptygid:x:8301:`, `negid:x:8302:-5` are all `UNKNOWN` in GNU.
  Group lines have no second id field and are exempt.
- ⛔ **On a duplicate id the FIRST entry wins** the reverse lookup.
- ⚠ CRLF files and a missing final newline both parse — the `\r` lands on the last field, which is
  neither the name nor the id.

### ⛔ The GNU behaviours that a careful guess would have got wrong

- **`ls -l` left-aligns a NAME and right-aligns an unmapped NUMBER — in the same column.** Every
  other column in `-l` is right-justified, so one rule for the column would be wrong half the time:

      -rw-r--r-- 1 root                  root                   0 ...
      -rw-r--r-- 1                  4242                   4343 0 ...

  Both padded to the widest entry in the listing. Verified byte-identical against GNU on a fixture
  mixing a long name, a short name and an unmapped id.
- **`stat %U` on an id with no entry prints the literal string `UNKNOWN`** — not the number, not an
  empty field. `%u` is the specifier that gives the number.
- ⛔ **Coreutils is inconsistent with ITSELF on an EMPTY name, and kriya has to be too.** For a
  `:x:8104:8104::/h:/s` entry, `ls -l` falls back to the NUMBER (`8104`) while `stat -c %U` prints
  the empty string. gnulib's `idcache.c` ends `return match->name[0] ? match->name : NULL;` so `ls`
  treats a zero-length name as no name; `stat.c` calls getpwuid directly and guards only NULL.
  ⚠ The guard therefore lives at ls's call site — pushing it into `userdb` would make kriya's
  `stat` print `UNKNOWN` and regress a case that already matched.
- **`-n` does not merely suppress lookup; in GNU it IMPLIES `-l`.**
- ⛔ **`find -user` takes a name OR a number, and the NAME wins when both readings are possible.**
  With a user literally named `4242` whose uid is 7777, `find -user 4242` matches the uid-7777
  files. So the order is name-first with number as fallback, not "digits mean a number". `-uid` and
  `-gid` are numeric-only and are the unambiguous form. ⚠ `chown` resolves the same way, which is
  what confounded the first attempt to build a fixture for this.
- ⚠ **`-nouser` means "no entry in the database"**, not "id is zero" and not "lookup failed": with
  `/etc/passwd` removed entirely, GNU's `-nouser` matches every file.

### Fallback, which is where a static tool earns its keep

⛔ **A missing or unreadable file is NOT an error.** GNU degrades silently to numeric ids and exits
0 — verified by moving `/etc/passwd` aside and running `ls -l` (prints `0 0`, rc 0) and `stat -c %U`
(prints `UNKNOWN`, rc 0). ⚠ **The two files degrade INDEPENDENTLY**: with `/etc/passwd` unreadable
and `/etc/group` readable, GNU prints the numeric uid beside the NAMED group, so they are loaded
separately and neither failure poisons the other. ⭐ That is also exactly what the **agnos** target
needs, where there may be no `/etc/passwd` at all — the fallback is the normal path there, not an
error path.

⭐ **Loaded at most once per process, which is a requirement and not an optimisation**: `ls -l` in a
large directory looks up an owner per entry, and re-reading `/etc/passwd` each time would be one
open per file. GNU caches too — `strace -e openat ls -l` over 40 same-owner files shows **two**
passwd opens, not forty.

### Fixed — a segfault caught by the first run, and the constant that caused it

⛔ **`var st[FS_STAT_SIZE]` is a 48-byte buffer for a 144-byte write.** `FS_STAT_SIZE` is the OFFSET
of `st_size`; `FS_STAT_BUFSZ` is the struct's length — and a function-local `var X[N]` is N BYTES
(roadmap M15a). The plausible-looking name is the wrong one, and `stat -c %U` exited **139**
(SIGSEGV) on its first run. ⚠ That was the good outcome: a smaller mismatch would have corrupted the
frame silently.

### ⚠ Six divergences found AFTER this release was first reported complete

⛔ **The parser shipped wrong in six ways and a background investigation caught all of them**, three
of which I had explicitly measured and read backwards. The leading-blank rule is the instructive
one: my own fixture output was `  stat %U : [spaced ]`, and I read the two leading spaces of my
`printf`'s OWN label as data, concluding "whitespace is part of the name". It is not — glibc strips
leading blanks and keeps trailing ones, so the evidence was on screen and misread.

The six: leading blanks not stripped (name); leading blanks not stripped (id field); `+`/`-` lines
resolved as users; `#` not recognised when indented; a passwd line's gid field unvalidated; and
`ls -l` printing a blank column where GNU falls back to the number.

⭐ **A differential fuzz then closed the loop**: 1,200 generated passwd and group lines — random
leading/trailing blanks, `#`/`+`/`-` prefixes, malformed and out-of-range ids, field counts from 2
to 8 — compared against glibc through `stat -c %U`/`%G`. **Zero divergences.** ⚠ The first run of
that fuzz was what found the id-field blank rule, as 21 failures of exactly one shape.

### Release totals

**4,303 smoke cases across 38 scripts** (up from 4,279) — `smoke-find.sh` 78 → **90**,
`smoke-stat.sh` 48 → **53**, `smoke-ls.sh` 43 → **49**. **322 unit** (up from 277); 18 POSIX; fuzz
green under poison; four lints clean; both targets build. `vet` reports **52 deps** (new
`src/lib/userdb.cyr`). Binary 1,046,808 → 1,059,568 bytes (+12,760).

⛔ **Every smoke assertion here is a RUNTIME COMPARISON against GNU, never a literal**, because the
right answer is a property of the machine's `/etc/passwd`: uid 1000 is `macro` on this box and
somebody else on the CI runner. `expect_eq "%U" "macro"` would assert the laptop it was written on.
⚠ The mixed-width alignment quirk and the unmapped-id cases need `chown` privileges to construct, so
they are covered by the unit tests and the container run, and the smoke scripts say so at the point
where the gap is — deliberate rather than forgotten.

⭐ **Verified under all five matrix conditions**: baseline 38/38 4,303; hostile block-size +
`POSIXLY_CORRECT` env 38/38 4,303; `en_US.UTF-8` 38/38 4,303; deep `$TMPDIR` 38/38 4,303; simulated
root 38/38 4,287 (root-only paths skipping).

⭐ **And inside the `ubuntu:24.04` container as a non-root user** — 38 scripts, 0 failures, 4,281
cases — the check that caught 1.4.5's CI failure only after CI did.

## [1.4.5] - 2026-08-26 — the `-i` bracket-class quirk; 1.4.x closes

### Fixed — ⛔ `grep -i` and `find -iregex` mis-matched every bracket expression

⭐ **`kriya grep -i '[[:upper:]]' ` returned NOTHING where GNU returns every alphabetic line**, with no
diagnostic. The last item on the 1.4.x arc, carried since the M7 POSIX audit and never chased down.

⛔ **The cause is one sentence, and it generalises past this bug: a bracket expression is not a byte,
it is a SET, and lower-casing its source TEXT does not lower-case the set it denotes.** Both utilities
implement `-i` by folding the SUBJECT to lower case and folding the pattern alongside it. That is
exactly right for literal bytes — and for `[[:upper:]]`, whose text is *already* lower case, the fold
is a no-op, so the class survived intact and could never fire against a lower-cased subject. ⚠ The
same line of reasoning explains why `[[:lower:]]` looked fine: it was **accidentally** correct, which
is why the bug reads as "one broken class" rather than "the whole mechanism is wrong".

⭐ **The rule GNU actually implements, measured rather than assumed** — and it took four attempts to
state correctly, each earlier one killed by brute force rather than by inspection:

- **`[:upper:]` and `[:lower:]` BOTH behave as `[:alpha:]`.** ⚠ Not "match everything": digits and
  punctuation still do not match, and a fixture without them cannot tell those two readings apart.
  Every other class is unaffected by `-i`.
- **A range `x-y` is an ERROR iff `toupper(x) > toupper(y)`.** ⛔ The gate is the UPPER-case fold, and
  the difference is load-bearing rather than cosmetic: `[A-_]` is **accepted** and `[B-a]` is
  **refused**, though *both* have a reversed lower-case fold. A lower-case gate fits most of the data
  and gets exactly these wrong.
- **Otherwise, if `x > y` raw, it matches NOTHING and is NOT an error.** ⚠ So `-i` can turn an error
  into silence: plain `[b-B]` is a hard error, `-i '[b-B]'` matches nothing and exits 1.
- **Otherwise the RAW span is kept, plus the case-counterpart of every member** — so `[A-z]` still
  covers the six punctuation bytes between `Z` and `a`.

⭐ **Verified by brute force, not by reading**: **41,868 range comparisons — zero divergences.** All
8,281 printable-endpoint ranges in `grep`'s BRE and ERE engines, with `-i` and without, plus all
7,744 in `find -iregex`, plus **5,000 randomised bracket patterns** across seven flag combinations. ⚠ Three earlier models of GNU's behaviour passed every hand-picked example and
died on the sweep; the fourth is the one above.

### ⛔ Two traps in the oracle itself, both of which would have silently mis-taught the fix

**1. The rule is LOCALE-DEPENDENT, and dramatically so.** `grep -i '[>-a]'` gives **three different
answers** under `LC_ALL=C`, `C.UTF-8` and `en_US.UTF-8`, because a bracket range walks **collation**
order rather than byte order. ⚠ An early measurement pass produced a model that fit nothing, purely
because the ambient locale was not what it appeared to be. kriya is byte-ordered and ASCII-only by
design (ADR 0005), so it implements the **C-locale** rule and every comparison pins `LC_ALL=C`.
⭐ The verification matrix gained two locale conditions to keep that honest.

**2. GNU grep CONTRADICTS ITSELF, and kriya deliberately does not follow it.** On a line holding just
`_`, `grep -i '[A-z]'` **matches** — exit 0, and `-c` reports 1 — while `grep -i -o '[A-z]'` exits 0
and prints **nothing**. ⚠ Reproduced identically on grep **3.11** (what CI runs) and **3.12** (this
box), so it is neither version drift nor a local patch. kriya follows the **line matcher** — the
documented semantics, and the half GNU is self-consistent about — which makes kriya's `-o` print what
actually matched. ⛔ The smoke suite therefore does NOT compare `-o` for a range spanning the case
gap, and says why at the assertion.

### Added — `src/lib/icase.cyr`, shared by both callers

⛔ **`find -iregex` had the identical bug** — `find . -iregex '.*[[:upper:]].*'` listed nothing where
GNU lists every path — because it folds both sides exactly the way `grep` does. ⭐ That is what makes
this shared code rather than a `grep`-local patch: two implementations of "match case-insensitively"
in one binary is two sets of edge cases that drift apart silently, the same argument that lifted
`glob.cyr` out of `find` at 1.4.1 and the escape table into `str.cyr` at 1.4.3.

⭐ **One mode bit, two subject conventions**, the shape `str.cyr` already took: `ICASE_MODE_FOLD` for
the BRE path (which lower-cases the subject, so the set is emitted lower-cased) and
`ICASE_MODE_CLOSED` for the ERE path (which does not fold, and relies on niyama's inline `(?i)`).
⚠ **`(?i)` case-closes a RANGE but not a NAMED CLASS** — measured — so `grep -E -i '[[:upper:]]'`
matched upper case only, a *different* wrong answer from the BRE path's. The rewrite supplies both
the class substitution and the range validation `(?i)` never did.

⛔ **GNU `grep` and GNU `find` ARE NOT ONE ORACLE, and sharing the rewriter without saying so made
`find` wrong.** `grep` matches with its own bundled matcher; `find -iregex` calls glibc `regcomp`
with `RE_ICASE`; the two implement **different range rules**:

    grep -i '[b-B]'            matches NOTHING
    find  -iregex '.*[b-B].*'  matches `b` AND `B`

⚠ **They differ in what a range MEANS, not in which ranges are LEGAL** — both refuse exactly when
`toupper(x) > toupper(y)`, so the validity gate is shared and only the membership computation forks.
glibc's rule, verified exact over all **7,744** printable-endpoint ranges in both the posix-basic and
posix-extended dialects: a byte `c` is in `[x-y]` iff `toupper(x) <= toupper(c) <= toupper(y)` — a
translation applied to the **candidate** as well as both endpoints, which is why `[B-{]` excludes `a`
while containing `[`, `\`, `]` and `_`.

⛔ **Getting this right took two wrong answers first, and the second was caused by comparing
DIALECTS rather than implementations.** `find`'s default is `findutils-default` (emacs-flavoured);
kriya's is POSIX BRE (ADR 0005). Measured against GNU's *default*, the shared validity gate looks
like a regression, because the emacs dialect does not refuse a reversed range — it matches nothing.
Measured against `-regextype posix-basic`, which is the like-for-like comparison, GNU refuses it
exactly as kriya does. ⚠ Every `find` regex assertion now pins `-regextype posix-basic`, which costs
no coverage: kriya's default IS posix-basic, so the pinned form exercises the identical path.

⭐ **What makes a pattern rewrite sufficient at all**: every set GNU denotes under `-i` is **closed
under case**, and a case-closed set loses nothing when lower-cased. So matching `lower(S)` against a
lower-cased subject is exactly equivalent, which is what keeps this a pattern-side fix and leaves the
subject fold — and the `-F` engine, which was never wrong — alone.

### Fixed — the bracket parser's own edges, found by the fuzz rather than by design

- ⛔ **An empty set has no bracket spelling.** `[]` is not "matches nothing", it is an
  **unterminated** bracket, because a `]` in first position is a member. And the case is reachable:
  a raw-reversed range that clears the upper-case gate (`[a-B]`) contributes no members at all. ⚠ It
  cannot be dropped either — under a `*`, `x[a-B]*y` still matches `xy`. It is now written as the
  negation of every byte there is; `[^\x01-\xff]` is **not** good enough, because it matches a NUL
  and kriya's line buffer can hold one.
- ⛔ **`[` is only special when it opens `[:`, `[=` or `[.`.** Bare, it is an ordinary member and may
  be a range endpoint: `[Z-[]` is a legal three-byte set and `[[-m]` is a range GNU refuses. Treating
  every `[` as a literal member missed both readings.
- ⛔ **A `-` after a COMPLETED range or class is an error unless it is last** — GNU refuses
  `[a-c-e]` and `[[:digit:]-a]`, and accepts `[a-c-]` and `[a-cd-f]`. A class cannot be a range
  endpoint (`[a-[:digit:]]`), though `[a-[]` is perfectly ordinary.
- ⛔ **`[[=a=]]` and `[[.a.]]` are now REFUSED rather than silently matching nothing** — **with and
  without `-i`**. niyama implements neither and fails them the way it fails the GNU operators in
  `nl -b pBRE`: a wrong answer, not an error. `grep '[[=a=]]'` returned no match where GNU matches,
  `grep '[[.a.]-c]'` returned 0 where GNU returns 3, and `[[=a=]b]` matched nothing where GNU matched
  both lines. Refusing loudly is the same call, and the gap is tracked at **M11**.
  ⚠ **This started as a defect the fix INTRODUCED, not one it found.** Refusing on the `-i` path
  alone left the identical pattern loud one way and silently wrong the other — a worse state than
  the uniform silence it replaced. The scan now runs on every regex pattern, and is deliberately
  narrow: it asks "is this construct present", not "is this bracket well-formed", because niyama
  already agrees with GNU on everything else and a second opinion would be a second source of truth.
- ⭐ **Diagnostics now name the rule that was broken** — "invalid range end", "unterminated `[`",
  "no `[=c=]` / `[.c.]`" — where a flat "bad pattern" sent readers looking for a typo.

### Fixed — ⛔ CI caught what local GNU could not: findutils 4.9.0 has no character classes

⚠ **The first cut of the `find` assertions passed here and failed on CI**, and the cause was not case
folding at all: **findutils 4.9.0** (ubuntu-24.04, what CI runs) does not implement POSIX character
classes in its default dialect, while **4.11.0** (this box) does.

    findutils 4.9.0:  find . -regex '.*[[:alpha:]].*'                        -> nothing
                      find . -regextype posix-basic -regex '.*[[:alpha:]].*' -> every path
    findutils 4.11.0: both forms match every path

⛔ **The `-regex` form proves it is a DIALECT gap and not a `-i` bug** — the class fails there with no
`-i` anywhere in sight. ⚠ **Fourth time this project has been bitten by an oracle whose behaviour is
a property of its VERSION** (`find -exec` argv[0], `cut -c`, `nl -d ''`, now this), and the first
where the fix makes the test *more* honest rather than merely narrower: pinning the dialect compares
kriya's actual default against the same thing on both sides. ⭐ The whole suite is now verified inside
the `ubuntu:24.04` container as a non-root user — 38 scripts, 0 failures — which is the check that
would have caught this before it reached CI, and was not run.

### Fixed — ⛔ the no-`-i` path validated nothing at all

⚠ **Correcting a claim made while this release was in progress: the plain and `-i` paths did NOT
agree.** Without `-i`, no bracket range was ever checked — kriya diverged from GNU on **4,095 of
8,281** ranges, and two of them were **silent wrong answers** rather than mere silence:

    grep '[a-c-e]'        GNU: exit 2       kriya: exit 0, five matches
    grep '[[:digit:]-a]'  GNU: exit 2       kriya: exit 0, twelve matches

⛔ **The gate here is the RAW comparison, not the upper-case fold `-i` uses, and the two give
OPPOSITE answers on the same input**: plain `[Z-a]` is valid while `-i '[Z-a]'` is an error, and
plain `[b-B]` is an error while `-i '[b-B]'` is silently empty. Both are now asserted, which is what
pins the two rules apart rather than letting one stand in for the other.

⚠ Fixing this was not scope creep but the same argument twice: leaving it would have left the
identical pattern **loud with `-i` and silently wrong without it** — the exact trap that made
refusing `[=c=]` on one path only a defect rather than a fix.

### ⚠ On conformance: this was a POSIX violation, and matching GNU does not fully end it

⛔ **The pre-fix behaviour broke the standard, not merely GNU parity.** POSIX.1-2024 (Issue 8) chains
`grep -i` → XBD 9.2 → XBD 4.1 "Case Insensitive Comparisons"; Issue 7 has no XBD 4.1 but its XBD 9.2
independently mandates the same result with a character-level rule ("not only the character, but also
its case counterpart (if any), shall be matched"). ⚠ Cite Issue 8 explicitly — in POSIX.1-2017,
XBD 4.1 is "Concurrent Execution", so the obvious citation points at the wrong section.

⚠ **GNU is not a conformance oracle, and on one case the two goals conflict.** The same rule applied
to `[^[:upper:]]` arguably requires `B` to match under `-i`, since its counterpart `b` is not upper.
GNU returns no-match on 3.11 and 3.12 under all three locales, and POSIX grants no exemption for
complemented brackets. **kriya deliberately mirrors GNU here**, which makes this a behaviour that is
simultaneously a 4.1 violation and a defensible parity choice — recorded rather than papered over.

### Release totals

**4,279 smoke cases across 38 scripts** (up from 4,217) — `smoke-grep.sh` 165 → **213**,
`smoke-find.sh` 64 → **78**. **277 unit** (up from 220); 18 POSIX; fuzz green under poison; four
lints clean; both targets build. `vet` reports **51 deps** (new `src/lib/icase.cyr`).
Binary 1,038,256 → 1,046,808 bytes (+8,552).

⭐ **Verified under all six matrix conditions**, two of them added by this release because a bracket
range walks collation order: baseline 38/38 4,279; hostile block-size + `POSIXLY_CORRECT` env
38/38 4,279; **`en_US.UTF-8` 38/38 4,279**; **`C.UTF-8` 38/38 4,279**; deep `$TMPDIR` 38/38 4,279;
simulated root 38/38 4,263 (root-only paths skipping).

⭐ **And, new at 1.4.5, verified inside the `ubuntu:24.04` container as a NON-ROOT user** — 38
scripts, 0 failures, 4,257 cases (the shortfall against 4,279 is version-conditional coverage that
correctly stands down there). ⚠ Running it as root instead fails two pre-existing `-exec` assertions
that depend on a "Permission denied", which root does not get — so the user matters as much as the
image.

⚠ **Two pre-existing `grep` divergences surfaced by the fuzz and deliberately NOT fixed here** — both
are in paths this release did not touch, and both are now on the roadmap rather than absorbed
silently: a leading `*` in an ERE (`grep -E '*'`) is a literal in GNU and a usage error in kriya, and
`grep -o` emits empty matches for an empty-matchable pattern (`grep -o 'x*'`) where GNU suppresses
them.

## [1.4.4] - 2026-08-26 — `nl` sections, `echo -e`, and one escape table

### Added — `echo -e` / `-E`

⭐ **`echo` interprets backslash escapes on request**, built on the `str_escape_decode` table below
rather than a third copy of it. ⛔ **The decision was never the decoding — it was WHICH `echo`**, and
there are three incompatible answers: POSIX (non-XSI) prints operands literally and has no `-e`; XSI
interprets escapes ALWAYS with no flag either way; and the shell BUILTIN most scripts actually reach
is not one target either (`bash`'s defaults to escapes-off and honours `-e`, `dash`'s interprets
always and has no `-e`). [ADR 0011](docs/adr/0011-echo-matches-the-non-xsi-binary-not-the-shell-builtin.md)
records the pick: **kriya matches GNU `/usr/bin/echo`'s DEFAULT, non-XSI mode.**

⛔ **`POSIXLY_CORRECT` deliberately does NOT flip kriya to XSI, and this is a measured deviation from
GNU.** Under GNU's rule, exporting that variable for some *unrelated* utility silently turns every
`echo -e` in the same shell into a command that prints `-e` as literal data — verified here:
`POSIXLY_CORRECT=1 /usr/bin/echo -e 'x\ty'` emits `-e x<TAB>y`. The environment variable and the
broken `echo` are usually in different files, which is the worst shape a bug can take. kriya keeps
the command line as the only input to its behaviour, which is the property ADR 0002 exists to hold.

Measured against GNU rather than assumed, and the surprises were real:

- ⚠ **`\c` is not "stop this operand" — it cancels the REST OF THE COMMAND.** The remainder of the
  string, **every later operand**, and the trailing newline, still exiting 0: `echo -e 'A\cB' SECOND
  THIRD` prints exactly `A`. It cannot be a local `break` in a per-operand decoder.
- ⚠ **The octal leading zero is OPTIONAL.** The grammar is backslash, an optional `0`, then one to
  three octal digits — and the `0` does not count toward the three. `\101` and `\0101` are both `A`;
  `\10` is a backspace. This is `%b`'s prefix rule, **not** the FORMAT rule.
- ⛔ **`\"` is in `printf`'s table and NOT in `echo`'s.** `printf '\"'` emits `"`; `echo -e '\"'`
  emits `\"`, backslash kept. A shared decoder that hard-codes either answer is wrong for the other
  caller, so this became the fourth mode bit (`STR_ESC_DQUOTE`) rather than a special case.
- ⚠ **Option clusters are all-or-nothing.** A token is options only if it is `-` followed by
  characters that are EVERY one of them `n`, `e` or `E`. `-neE` is three options; `-ex` is the
  four-byte operand `-ex`; a bare `-` is data; and **`--` has no special meaning** — `echo -- x`
  prints `-- x`. The last of `-e`/`-E` wins, inside one cluster as well as across several.

⭐ **130 byte-exact parity cases** in a new `scripts/smoke-echo.sh`, plus **1,400 randomised
differential comparisons** against GNU over escape-dense operands — zero divergences.
⚠ The suite compares `od` output, not `$(...)`: command substitution strips trailing newlines, which
is exactly what `-n` and `\c` exist to remove, so a `$(...)` comparison would pass whether or not
either flag worked at all.

⛔ **The hostile-environment matrix caught that suite failing 99 of 129 cases on its first run** —
because the ORACLE flips under `POSIXLY_CORRECT` while kriya deliberately does not, so every parity
case diverged at once with kriya behaving exactly as ADR 0011 says it should. The GNU side now runs
with the variable unset. ⚠ **Third time a GNU oracle has been environment-controlled where kriya is
not** (`du` and `df` took this treatment for `BLOCK_SIZE`/`POSIXLY_CORRECT` at 1.3.5), and the rule
that generalises is now written into the script: **if kriya ignores a variable by design, the oracle
must ignore it too, or the test measures the environment rather than the code.**

### Added — `nl` sections: `-d`, `-h`, `-f`, `-l`, `-p`, and `-b pBRE`

⭐ **`nl` understands the three-delimiter section model**, replacing the single-section stub. A line
whose ENTIRE content is the delimiter repeated three times starts a header, twice a body, once a
footer; input before the first marker is a body. ⚠ **Whole line, not prefix** — `\:\:\:\:` and
` \:\:\:` are ordinary numbered text, and a run of six is NOT header-plus-footer. A marker line is
replaced on output by a **bare newline** — no number, no separator, no padding, whatever `-w` and
`-s` say. The counter resets to `-v` at every marker unless `-p` is given.

⭐ **One state block replaced a 9-argument emitter.** `-h`/`-b`/`-f` are three parallel style+regex
pairs indexed by the current section, which is what makes the per-section reset and the three
independent regexes fall out rather than being coded three times.

⛔ **`-b pBRE` REFUSES the GNU-only regex operators instead of silently mis-numbering.** GNU's
dialect is POSIX BRE *plus* the GNU operators; niyama implements only the POSIX core, and its
failure mode for the rest is **silent** — `a\+b` compiles clean and then matches nothing, so
`kriya grep -c 'a\+b'` returns **0 where GNU returns 3**. For `nl` that would mean numbering the
wrong lines with no diagnostic, so `\+ \? \| \b \B \w \W \s \S` are rejected at parse time with
exit 2. ⚠ `\< \> \{n,m\} \(…\) [[:class:]]` DO work and are deliberately not refused, and a
backslash inside a bracket expression is a literal — `[\+]` is data, not the operator. The upstream
gap is now tracked as a third M11 item; closing it deletes the guard rather than growing it.

⛔ **`nl -b p` is POSIX BRE, NOT the Emacs dialect `find -regex` takes.** A bare `+` here is a
LITERAL plus and `\+` is one-or-more — the exact opposite of `find`, whose GNU default is Emacs
syntax. GNU `nl` dropped Emacs syntax in coreutils **6.6** (2006). The warning block in `find.cyr`
must not be copied into `nl.cyr`, and now says so in both files.

⛔ **`-d ''` is NOT tested against local GNU, on purpose.** GNU documents it as "disables section
matching" and coreutils **9.4** (what CI runs) does exactly that — but **9.11** (this box) regressed
it: the multi-byte rewrite of `check_section` turned every EMPTY input line into a header marker, so
the oracle contradicts its own `--help` and disagrees with itself across the two versions kriya must
satisfy. ⚠ This is the third time a GNU-parity test could have passed because of the local GNU's
VERSION rather than because kriya was right (`find -exec` argv[0], `cut -c`, now this), so the smoke
script asserts the DOCUMENTED behaviour as an absolute instead. kriya's pre-1.4.4 single-section
`nl` was already a bit-exact implementation of that mode.

Other measured rules now honoured: `-d C` with ONE character implies `:` as the second (so `-d '\'`
reproduces the default and `-d ':'` means `::`), `-d` with three or more characters takes the whole
string as the unit, and `-l N` applies to style `a` ALONE — GNU checks the blank run inside
`case 'a'`, so `t`, `n` and `p` ignore it entirely.

⭐ **4,100 randomised differential comparisons** against GNU — 2,500 across section-heavy inputs and
32 option combinations, plus 1,600 aimed specifically at `-l` crossing a section boundary, since the
blank-run counter and the per-section reset are the two pieces of state that could plausibly
interfere. Zero divergences. `scripts/smoke-nl.sh` 23 → **48** cases.

### Changed — the deferral lint validates M-number cross-references

⚠ **A deferral that outlives its release has to be repointed at something durable**, and `nl -b pBRE`
moved from `roadmap 1.4.4` to `roadmap M11` the moment 1.4.4 shipped. The dangling-reference check
added at 1.3.8 only validated `roadmap N.N.N`, so "repoint it at an M-number" would have been the way
to launder a reference past the very check that exists to catch it. It now validates both.

⭐ **It found a live problem on its first run** — and then a second one in itself. `M12a`/`M12c` are
referenced from `cp.cyr`, `stat.cyr` and `date.cyr` and are legitimately documented, but as TABLE
ROWS rather than `###` headers; and matching `M[0-9]+` truncated `M12a` to `M12`, an entry that does
not exist. ⚠ The suffix letter is load-bearing. All three documented shapes now count: a `###`
header for an open bucket, a table row for a retired one, and a **bold paragraph lead** for an M15
watchlist item. Negative-controlled against a deliberately dangling `M99`.

### Fixed — `printf` escape parity: one decoder where there were two

⭐ **printf's two escape decoders are now one `str_escape_decode` call** in a new
`src/lib/str.cyr`, parameterised by four mode bits. ⛔ **Six divergences from GNU, and NOT ONE is a
flaw in either decoder's logic** — every one is a line present in one copy and missing from the
other, or a rule copied onto the path it does not belong to. That is what two escape tables in one
binary cost, and which half is wrong is invisible until a script hits it. `src/lib/glob.cyr` was
lifted out of `find` at 1.4.1 on exactly this argument.

All six measured byte-for-byte against GNU coreutils **9.11** (this box) and **9.4** (ubuntu:24.04),
which agree with each other — ⚠ so none of this is version drift, the failure mode that made the
`find -exec` argv[0] bug and the `cut -c` tests look green for two releases:

- **`\e` (ESC, 0x1b) was in NEITHER table**, so both paths printed a literal `e`. GNU has had it in
  printf *and* echo since coreutils **8.1** (2009-11-18).
- **`\c` worked in `%b` and printed a literal `c` in FORMAT.** ⚠ It cancels the rest of the output
  and exits 0 — **argument reuse included**, so `printf '%s\c' a b c` prints `a` and stops rather
  than cycling the format over `b` and `c`.
- **`\xHH` worked in FORMAT and printed a literal `x41` in `%b`.** A malformed `\xZ` now fails the
  `%b` path too, where it used to print `xZ` and exit 0.
- **`\0101` in `%b` was decoded by FORMAT's rule** — backspace then a literal `1`, where GNU gives
  `A`. ⛔ **This is the one place the two paths genuinely differ and it is the whole reason the mode
  bit exists**: POSIX defines `%b`'s `\0ddd` with the leading `0` as a **prefix** followed by up to
  three MORE octal digits, while a FORMAT string takes at most three digits **total**. Both readings
  are correct, for different inputs, and GNU implements both — its own decoder is one function with
  one `octal_0` flag. ⚠ **The FORMAT path was right here and was deliberately left alone.**

The two below were **not in the report that prompted this** — they surfaced while unifying the
tables, because writing one decoder forces every case to be answered once:

- ⛔ **Unknown escapes dropped the backslash.** `printf '[\q]'` printed `[q]`; GNU prints `[\q]`,
  both bytes, in both paths. A silent deletion of a byte the user typed is the worst shape this can
  take — a script meaning a literal backslash got no diagnostic and no backslash. ⚠ `\"` **is** in
  GNU's PRINTF named table (so `\"` is `"`) and `\'` is **not** (so `\'` keeps its backslash); the
  asymmetry reads like an upstream oversight and is not one. ⛔ `echo`'s table does not contain `\"`
  at all — see the `echo -e` entry above, and `STR_ESC_DQUOTE`.
- ⛔ **Octal overflow refused the digit instead of truncating.** `\777` is 511; GNU eats all three
  digits and emits `0xff`, while kriya emitted `\77` (`?`) and left a literal `7` in the stream —
  ⚠ **two bytes of output where GNU writes one**, so the damage is not confined to the escape.

⚠ **`\e` and `\x` are GNU extensions, not POSIX**, and no ADR is opened for them: POSIX leaves an
undefined escape's behaviour unspecified, so this makes unspecified input useful rather than
diverging from a defined rule — the same call `\xHH` shipped under in the FORMAT path at 1.2.1.

⭐ **Being in `src/lib/` is what makes the table unit-testable at all.** Both old decoders wrote
straight to fd 1, so the only way to check either was to run the binary and read bytes back;
`str_escape_decode` is pure — bytes in, one verdict out — and takes **35 new assertions** covering
both octal readings, overflow, the mode bits switched off, and the `\"`/`\'` asymmetry.
⚠ The verdict is **four-valued, not two**: an unknown escape is two output bytes and `\c` is none,
so a caller cannot simply "emit the byte".

⭐ **This unblocked `echo -e`/`-E`, which ships in the same release above.** ⚠ The mode named here
while the table was being written — `STR_ESC_OCTAL_PREFIX | STR_ESC_ALLOW_C` — turned out to be
short by one bit and long by another once echo's table was actually measured: GNU echo DOES honour
`\xHH`, and does NOT honour `\"`. echo's real mode is
`STR_ESC_OCTAL_PREFIX | STR_ESC_ALLOW_C | STR_ESC_ALLOW_X`, and `STR_ESC_DQUOTE` was added as a
fourth bit for the one named escape the two callers genuinely disagree about.

`smoke-printf.sh` 68 → 98, ⭐ the new block running the **same case list through both paths**,
byte-exact through `od`, since the bug was never the decoding. ⚠ Its `compare` helper could not be
reused: `$(...)` strips trailing newlines and drops NULs, which is precisely what `\0` and `\c`
produce.

### Release totals

**4,217 smoke cases across 38 scripts** (up from 4,032/37) — `smoke-echo.sh` is new at 130,
`smoke-nl.sh` 23 → 48, and the remaining +30 falls out of `smoke-help.sh` / `smoke-help-json.sh`,
which iterate the option tables and saw seven options added. **220 unit** (up from 178); 18 POSIX;
fuzz green under poison; four lints clean; both targets build. `vet` reports **50 deps**.
Binary 1,029,280 → 1,038,256 bytes (+8,976).

⭐ **Verified under all four matrix conditions**: baseline 38/38 4,217; hostile block-size +
`POSIXLY_CORRECT` env 38/38 **4,217**; deep `$TMPDIR` 38/38 4,217; simulated root 38/38 4,201
(root-only paths skipping).

## [1.4.3] - 2026-08-26 — `uniq` line grouping

⚠ **Scoped down from the roadmap entry.** That entry paired `uniq --group` with `nl` section
delimiters and `echo -e`. `nl`'s sections are a release of their own — three styles across
header/body/footer, delimiter detection, and regex-based numbering whose dialect needs the same
scrutiny `find -regex` got — so they and `echo -e` move to 1.4.4 rather than being rushed alongside.

### Added — `--group[=METHOD]`, `--all-repeated[=METHOD]`, `-D`

⭐ **These emit every line of a group, not the representative N times.** With `-f`/`-s`/`-w` the
comparison key is a *window*, so lines in one group can differ outside it — measured against GNU,
`uniq --group -f 1` on `x a` / `y a` / `z b` prints **both** `x a` and `y a`. ⚠ A fixture of identical
lines cannot tell the two implementations apart, so the one in the suite deliberately has a group
whose members differ.

⭐ **O(1) memory, not O(group).** `--group` prints each line as it arrives, since every line is emitted
and only the *separator* needs to know a group changed. `--all-repeated` must know whether a group
repeats before printing its first line, so it holds exactly **one** line and streams the rest. A group
of a million identical lines costs one line of buffer either way.

⛔ **The two METHOD vocabularies overlap but are not the same** — `--group` takes
`separate|prepend|append|both`, `--all-repeated` takes `none|prepend|separate`. `--group=none` and
`--all-repeated=append` are both errors in GNU, and rejecting by *vocabulary* rather than against a
shared list is what keeps that true.

⛔ **With `-D`, `-u` prints only the LATER lines of each repeat group and `-d` is a no-op.** Measured,
and order-independent — `-u -D` behaves the same. It reads oddly until you see coreutils' internal
flags: `-u` clears "output first repeated" while `-D` sets "output later repeated", so together they
mean "the repeats after the first". ⚠ Unique groups are never printed under `-D` whatever `-u` says.
A first implementation had this wrong and the smoke comparison caught it.

`--group` is refused with `-c`/`-d`/`-D`/`-u`, and `--all-repeated` with `-c`; ⚠ but `--all-repeated -d`
and `-u` **are** accepted by GNU, so they are not rejected here either.

### Fixed — ⛔ the optional-value mechanism held exactly one option

`src/lib/args.cyr` supported one optional-value long per utility, with a note ending *"One slot is
enough — no utility has two."* **`uniq` has two.** Both `--group` and `--all-repeated` are legal bare
*and* with `=METHOD`, and the parser has no way to express that for a second name — registering either
as a string would make the bare form swallow the next operand, which is exactly what happened:
`uniq --group -f 1` consumed `-f` as `--group`'s value.

The slot is now a small registry, and ⛔ **each name keeps its own captured value** — sharing one value
slot across two registered names would hand `--group`'s argument to `--all-repeated` whenever both
appeared, silently. `cp --preserve`, `sort --check` and `tail --follow` are unchanged and still pass.

⚠ **A variable-name collision I introduced there is worth recording**: the rewrite path already used
`oi` as the *expansion output cursor*, and I reused the name for the registry index. The result was a
silently corrupted argv where `--group=separate` behaved as plain `uniq` — every bare form worked, so
only the `=METHOD` cases exposed it.

### Two deliberate divergences from GNU, both recorded in ADR 0002

⚠ **kriya does not accept prefix forms of a METHOD value.** GNU's `argmatch` takes any unambiguous
prefix — `uniq --group=sep`, `--group=b` — and kriya requires the word in full. ADR 0002 already ruled
out prefix matching for long *names* (*"`--ver` does not match `--version`… silent drift across
releases"*), and the same argument applies to their values: a prefix that is unambiguous today becomes
ambiguous the day a method is added. The ADR now says so explicitly rather than leaving it inferred.

⛔ **An empty value (`--group=`) is an error, not the default.** A first implementation treated it as a
bare `--group`, which **accepted an invocation GNU refuses** — the wrong direction for a tool to be
permissive in, since the caller wrote `=` and meant something. GNU calls it *"ambiguous argument ''"*;
kriya now refuses it too.

### Tests

**4,002 smoke cases across 37 scripts** (up from 3,932), 143 unit + 18 POSIX, fuzz green under poison,
four lints clean, both targets build.

`smoke-uniq.sh` gains 88 cases: every method for both options compared against GNU including exit
status, the discriminating `-f 1` group whose members differ, all four `-D` combinations, the conflict
matrix, and each cross-vocabulary method (`--group=none`, `--all-repeated=append`) asserted as an error
**in both implementations** — so the test fails if GNU ever starts accepting one.

⚠ **Separator placement is pinned at the boundaries.** A multi-group fixture cannot tell "before every
group" from "between groups" for the *first* group — a **single-line** input can, and an **empty** one
catches a stray separator with nothing to separate. Both are in the suite for all four methods, along
with an all-unique input under `--all-repeated`, where a `prepend` method must emit nothing at all.

⭐ The `k_write` length lint caught two more of my own off-by-ones (`uniq.cyr:282,288`). Third release
running.

## [1.4.2] - 2026-08-26 — multibyte text: `cut -c`, and `tr`'s missing set syntax

⚠ **This release is smaller than the roadmap entry that prompted it, and deliberately so.** The entry
read *"`cut -c` distinct from `-b`, `tr` locale-aware fold and `[=c=]` and `[c*N]`, `uniq` multi-byte
`-i` — one decoder, four surfaces."* Measuring GNU first turned two of those four surfaces into
**non-goals**, and turned one of the remaining two from a missing feature into a **silent-wrong-output
bug**.

### ⛔ Two of the four surfaces would have been divergences, not fixes

**GNU `tr` is byte-based even in a UTF-8 locale.** Measured, not inferred:

```
printf 'café' | LC_ALL=C.UTF-8 tr 'é' 'e'    ->  cafee
```

Two `e`s, because SET1 `é` is **two bytes** and SET2 `e` is one, so both bytes map to `e`. Likewise
`tr '[:upper:]' '[:lower:]'` on `ÉTÉ` folds only the ASCII `T`. ⚠ Making kriya's `tr` multibyte-aware
would therefore diverge from GNU **in every locale**, silently changing the output of existing scripts
that rely on the byte behaviour.

**GNU `uniq -i` does not fold non-ASCII either** — `café` vs `cafÉ` stays two lines under both
`LC_ALL=C.UTF-8` and `LC_ALL=C`. kriya already matches.

Both are now recorded in their source headers as **deliberate non-goals with the measurement attached**,
not as gaps waiting to be closed. A multibyte `tr` remains possible as a sovereign-design choice, but
it would need its own ADR — it is not a parity fix.

### Added — `cut -c` counts codepoints

`-b` and `-c` shared one emitter, so `-c` was byte-based: `cut -c2` on `aébc` returned the **lead byte
of é**, a broken UTF-8 sequence rather than a character. That is the whole difference the two flags
exist to express.

⚠ **Codepoints, not grapheme clusters** — measured. For `a` + `e` + U+0301 + `b`, GNU places the
combining acute at position 3 in its own right, so `cut -c3` emits the combining mark alone.

⚠ **An invalid byte counts as one character and passes through unchanged.** ⛔ The original bytes are
emitted, never the decoder's U+FFFD substitute — `cut` selects text, it does not repair it.

⛔ **The stdlib decoder is not strict enough on its own, and a first version of this shipped that
gap.** `_uc_decode_utf8` validates continuation-byte **shape** only and never range-checks the
codepoint, so three families of structurally-well-formed-but-illegal sequences came back as one
character where GNU counts each byte separately: **overlong** forms (`C0 80`), **UTF-16 surrogates**
(`ED A0 80`), and values **above U+10FFFF** (`F4 90 80 80`). `cut -c2` on `x\xC0\x80y` emitted two
bytes here and one under GNU.

⚠ Only their *value* is illegal — the shape is fine — which is why shape-checking let them through and
why a fixture of ordinary text can never catch it. `cut` now re-validates the decoded codepoint against
the shortest form for its length, the surrogate range, and the U+10FFFF ceiling. ⚠ The fix lives in
`cut.cyr`, not the stdlib: `lib/unicode/_decode.cyr` is upstream Cyrius, and its documented "skip the
bad byte" contract is honoured by treating a rejected sequence as one byte.

⭐ Confirmed by **differential fuzz against GNU: 4,900 comparisons over random byte strings, zero
divergences.**

⚠ The oracle is GNU under `LC_ALL=C.UTF-8`; under `LC_ALL=C` GNU's `-c` collapses to `-b`. kriya has no
locale and decodes unconditionally, which is exactly what `wc -m` already does — so this makes `cut`
consistent with a decision the codebase had already taken.

### Fixed — ⛔ `tr '[=c=]'` was silently mangling input

`[=e=]` fell through to the **literal** branch, so it was read as the four-character set
`{'[', '=', 'e', ']'}`:

```
echo 'a[b=c]de' | tr '[=e=]' X
GNU:   a[b=c]dX
kriya: aXbXcXdX        (before)
```

⚠ **It looked correct on any input without a bracket or an equals sign in it** — which is most input,
and is why a first check against `eéè` appeared to pass. The fixture that exposes it has to contain the
very characters the bug adds.

⚠ In the C and C.UTF-8 locales an equivalence class holds only the character itself (measured: `[=e=]`
leaves `é` and `è` untouched), and kriya has no locale — so expanding to the single character is both
what GNU does and the only thing it could mean.

### Added — `tr '[c*N]'` repetition

`[x*3]` was read literally, so `tr abc '[x*3]'` emitted `[x*` instead of `xxx`. Now:

- `[c*N]` repeats `c` N times;
- `[c*]` with no count pads SET2 to **SET1's length**;
- ⛔ **a leading zero means octal** — `[x*010]` is eight, not ten;
- ⛔ `[c*]` in SET1 is **refused**, as GNU refuses it (*"the [c*] repeat construct may not appear in
  string1"*).

⚠ kriya exits 2 on that refusal where GNU exits 1 — ADR 0008's usage-error policy, pre-existing:
`tr abc` with a missing SET2 already differs the same way.

### Fixed — ⛔ the new `cut` tests went red on CI while being correct locally

**`cut -c` only became multibyte-aware in coreutils 9.5.** My local build is 9.11; the CI runner ships
**9.4**, where `-c` is byte-based no matter the locale. So the twelve GNU comparisons I used to justify
this feature asserted **my machine's coreutils version**, and CI failed on all nine multibyte cases with
GNU returning lead bytes.

⛔ **This is the `find -exec` argv[0] incident again** — a GNU-parity test that passes because of the
*local GNU's version* rather than because kriya is right. The lesson had been written down twice and
the mechanism still got past me a third time.

⚠ An unusable UTF-8 locale degrades identically and silently: `LC_ALL=invalid.locale cut -c2` emits the
lead byte with **no diagnostic at all**, so the two causes are indistinguishable from outside.

⭐ **The fix is not to skip — it is to assert the specification.** POSIX says `-c` selects *characters*,
so `cut -c2` on `aébc` must yield the two-byte é on every host regardless of what GNU is installed.
`smoke-cut.sh` now carries **nine POSIX absolutes** that hold everywhere, and *additionally* compares
against GNU only after probing that GNU can actually do the job. Verified against a shimmed byte-based
`cut`: the suite prints an honest note, skips the 20 comparisons, and still runs 40 assertions.

⛔ **`check-oracles.sh` should have caught this and could not**, because it tested a locale *name* —
a proxy for the property rather than the property. It now **probes behaviour**: it runs GNU on a known
two-byte character and reports whether `cut -c` and `wc -m` are actually character-capable. ⚠ Reported,
not failed: an older GNU is a legitimate host; it only limits which comparisons are possible.

⚠ Two bugs in that probe on the way, both caught before shipping: the helper never `shift`ed, so `"$@"`
still held the label and expected value, and `wc -m` counts the trailing newline (`a` + `é` + `\n` = 3,
not 2). `smoke-wc.sh` got the same guard — it has never fired, since `wc -m` has been multibyte far
longer than `cut -c`, but it carried the identical latent shape.

### Tests

**3,932 smoke cases across 37 scripts** (up from 3,889), 143 unit + 18 POSIX, fuzz green under poison,
four lints clean, both targets build.

`smoke-cut.sh` gains 20 multibyte cases and `smoke-tr.sh` 13 set-syntax cases. ⚠ Verified under **both**
oracle conditions — 3,932 cases with a multibyte-capable GNU, **3,912 with a byte-based one**, which is
what CI actually has. ⚠ `smoke-tr.sh`'s existing `compare` helper builds its command with `eval`,
which cannot carry a set containing `[`, `*` or `=` safely — the new cases pass argv directly so a set
is never re-parsed by a shell.

⭐ **The `k_write` length lint caught one of my own bugs again** — `src/cmd/tr.cyr:737 length 65 should
be 66 — truncates the message by 1 byte`. Second release running.

## [1.4.1] - 2026-08-26 — shared glob: `grep --include`/`--exclude`, `find -regex`

### ⭐ The glob matcher is now shared

`find`'s fnmatch-style matcher moved out of `src/cmd/find.cyr` into **`src/lib/glob.cyr`**, so
`grep --include` uses the same code `find -name` does. Two implementations of *"does this name match
this pattern"* in one binary is two sets of edge cases to keep in agreement, and they drift silently —
a `[a-z]` range behaving differently in `find` than in `grep` is the kind of thing nobody notices
until it matters.

⚠ It is a **pure** matcher: bytes in, 0/1 out, no filesystem, no path awareness. Deciding whether to
hand it a basename or a whole path is the *caller's* business, and `find` and `grep` answer that
differently — which is why it does not live in `path.cyr`, whose subject is path *structure*.

⭐ **Being in `src/lib/` is what makes it unit-testable at all.** Buried in `find.cyr` it could only be
exercised end-to-end through `find -name`, so its bracket and backtracking edges had no direct
coverage. **26 new unit assertions**, and they found one:

⛔ **`glob_match("", 0, "", 0)` returned 0.** POSIX `fnmatch("", "", 0)` **matches** (verified against
libc) — a pattern exhausted exactly when the text is has matched by definition. The success test sat
*after* the failure branch had already returned, so the one case consuming no input fell through. No
live caller passes an empty pattern (`find -name ''` and `grep --include=` both match nothing because
no file has an empty name), but a shared matcher should hold its contract at the edges rather than
only where today's callers stand.

### Added — `grep --include` / `--exclude`

⛔ **Three of these rules are not what a careful reading would guess, and my first implementation got
all three wrong while passing a nine-case test — because none of those cases discriminated them.**
That is the 1.3.x lesson arriving in a new release: a green test is not a finding.

1. ⛔ **Precedence is RIGHTMOST-WINS, not "exclude beats include".** A later `--include` re-admits a
   file an earlier `--exclude` rejected: `--include='*.h' --exclude=a.c --include='*.c'` searches
   `a.c`.
2. ⛔ **The default for an unmatched name comes from the FIRST option's type.** So
   `--exclude=zzz --include='*.c'` searches **everything**, while the same two options in the other
   order search only `.c` files. Same options, order swapped, opposite result.
3. ⛔ **The subject differs by how grep reached the file.** Under `-r` descent the glob sees the
   **base name** only, so a pattern containing `/` can never match. For a file named on the **command
   line** it sees the operand as typed *and every trailing part beginning after a `/`* — so
   `--exclude='sub/c.c'` and `--exclude=c.c` both skip the operand `sub/c.c`. The identical file is
   filtered differently depending on how it was found.

⚠ Also measured rather than assumed: directories are exempt entirely — never pruned, always descended
(that is `--exclude-dir`, not shipped, roadmap); stdin is never filtered however aggressive the
pattern; and an excluded operand that cannot be **opened** still reports its error and exits 2,
because filtering happens after the open attempt.

⚠ Order matters, so `kriya_argv_collect` could not be used — it gathers one option name at a time and
loses the interleaving that rules 1 and 2 both depend on.

### Added — `find -regex` / `-iregex` / `-regextype`

Matches the **whole path as written**, anchored at both ends, including the leading `./` that `find .`
produces — verified against GNU: `find . -regex 'aab'` finds nothing while `-regex '\./aab\.c'` finds
`./aab.c`. niyama's search is unanchored, so the match is required to start at 0 and end at the subject
length explicitly.

⛔ **kriya's default dialect is POSIX BRE; GNU's is EMACS, and the difference is silent.** They
disagree on exactly the characters people reach for: `-regex '.*a+b'` reads `+` as one-or-more under
GNU and as a **literal plus** under BRE. A pattern does not error — it returns a *different set of
files*, the worst shape a divergence can take. Two consequences, both deliberate and recorded in
[ADR 0005](docs/adr/0005-regex-engine-niyama.md):

- The default is POSIX BRE, matching `grep`'s, so one mental model covers both utilities.
- ⛔ **`-regextype emacs` and `findutils-default` are REFUSED BY NAME**, with a message naming what
  *is* supported. Quietly aliasing them to BRE would be the silent case above. A caller wanting `+`
  writes `-regextype posix-extended`, which GNU also accepts — so a portable invocation exists.

⚠ `-iregex` under ERE folds via niyama's `(?i)` inline flag; BRE has no inline flag, so **both the
pattern and the subject are folded** — the same asymmetry `grep -i` already carries. Folding only one
side is the classic half-fix that makes `-iregex '.*ABC'` match nothing.

⚠ A malformed pattern exits **2**, where GNU exits 1. That is ADR 0008's usage-error policy and is
pre-existing — `find -type` and `find -name` with a missing argument already do the same.

### Fixed

⚠ `scripts/lint-deferrals.sh` reported a **line-length** warning under the summary *"N untracked
deferral(s)"*, sending a reader to look for a deferral that was not there. Two rules share one counter
since 1.3.8; the summary now names both.

### Tests

**3,889 smoke cases across 37 scripts** (up from 3,873), **143 unit** (up from 119), 18 POSIX, fuzz
green under poison, four lints clean, both targets build.

⚠ The `--include`/`--exclude` smoke block was **replaced, not extended**: its original nine cases were
exactly the ones that could not distinguish the three rules above. Every case now present fails if a
rule is dropped — including the pair that differ *only* in option order and must produce different
output.

`vet` now reports **49 deps** (was 48): `src/lib/glob.cyr` is a new module in the closure.

## [1.4.0] - 2026-08-26 — `grep` context

Opens the **1.4.x pattern-and-text arc**, and the first feature release since the 1.3.x discoverability
work. `grep` gains `-A NUM`, `-B NUM`, `-C NUM` and `-Z`.

### Added — `-A` / `-B` / `-C` context

Every rule below was **verified against GNU before being written down**, not inferred from the man
page — several are not what a reasonable reading would guess:

- ⛔ **A context line's field separator is `-`; a matching line's is `:`.** Inside a block that is the
  only thing telling a reader which lines actually matched, so it is not cosmetic.
- **`--` separates non-contiguous groups — and appears between *files* too**, not just within one.
- ⛔ **`grep -C 0` still separates; a plain `grep` never does.** The trigger is *"a context option was
  supplied"*, not *"the value is nonzero"* — which is why the spec defaults are `(0 - 1)` rather than
  `0`. A zero default cannot tell `-C 0` from no flag at all.
- **Overlapping windows merge** into one block with no separator.
- **An explicit `-A` or `-B` overrides the `-C` that set both** — GNU resolves `-C 5 -A 1` to one line
  after and five before.
- **`-c` / `-l` / `-L` / `-q` / `-o` ignore context** rather than erroring, matching GNU.

### Added — `-Z`, NUL after each file name

⛔ **Two different rules, and they are easy to conflate.** With `-l` the NUL **replaces the line
terminator** (`f\0f2\0` — no newline anywhere, which is what `xargs -0` wants). With `-c` it replaces
the `:` separator and **the trailing newline stays** (`f\0 2 \n`). ⚠ And the *line number* keeps its
own separator either way, so `grep -HnZ` emits `f\0 3 : line` — a consumer splitting on NUL gets the
name while one reading the rest still sees the match-vs-context marker.

The documented pipeline works end to end:

```sh
kriya grep -rlZ TODO src/ | kriya xargs -0 wc -l
```

### ⭐ The ring buffer grows by doubling rather than sizing for the worst case

`-B` needs the last N lines before a match arrives. A ring of N slots each big enough for grep's 64 KiB
line cap would be **6.4 MB at `-B 100` and 640 MB at `-B 10000`** — for input whose lines are almost
always short. Each slot instead starts at 256 bytes and doubles when a longer line arrives, so memory
tracks the content actually seen.

⚠ **No cap on `-B`, deliberately.** A cap is a silent divergence the day someone passes a bigger
number, and the growth policy makes one unnecessary. The superseded buffer is not reclaimed — `alloc`
is a bump allocator — but doubling bounds the total discarded per slot below the slot's final size.

### Not implemented

⚠ **GNU's `-NUM` shorthand (`grep -3` for `-C 3`)**. It requires a bare `-DIGIT` to parse as an option
rather than an operand — the shape `seq -5` handles with its own argv walk — and `grep` goes through
the shared parser, where a digit is not a registered short. Named in `--help` and on the roadmap
rather than silently absent.

### Performance

Context costs what its mechanism implies, measured on 2M lines / 66 MB with a single match — close to
worst case, since the ring is fed constantly and flushed once:

| | time | vs plain |
|---|---|---|
| plain | 547 ms | — |
| `-A 3` | 553 ms | +1% |
| `-B 3` | 671 ms | +23% |
| `-C 3` | 679 ms | +24% |

⭐ `-A` is nearly free because it needs no buffering — a countdown, not a ring. `-B`'s 23% is one
`memcpy` per **non-matching** line, which is the cost of not knowing a match is coming.

⚠ **Unrelated and pre-existing, but worth recording since it was measured here:** GNU scans the same
corpus in ~8 ms against kriya's ~543 ms on a literal pattern. GNU uses SIMD `memchr` plus Boyer-Moore;
kriya's literal fast path is a byte scan. Not touched by this release — see roadmap 1.9.x.

### Tests

**3,835 smoke cases across 37 scripts** (up from 3,774), 119 unit + 18 POSIX, fuzz green under poison,
four lints clean, both targets build.

`scripts/smoke-grep.sh` gains 45 cases: every context rule above compared **cell-by-cell against GNU**
including exit status, window clipping at both ends of the file, `-C 999` over-large windows not
fabricating lines, context under `-i`/`-w`/`-v`, stdin with no filename to prefix, and all six `-Z`
shapes diffed as `od -c` byte dumps.

⚠ The block aborted the whole script on its first run: `g=$(grep ...)` takes the substitution's exit
status as the assignment's, and the no-match case is *expected* to exit 1 — so `set -e` killed the
suite mid-file, silently. **Fourth release this has come up**; the `rc=0; cmd || rc=$?` form is now in
this block too, with the reason.

## [1.3.8] - 2026-08-26 — the last two items; 1.3.x closes

⭐ **The discoverability arc is complete.** Nine releases: `--help` (1.3.0), `--help=json` (1.3.1),
`kriya --list` + a CI that can fail (1.3.2), the checks covering the tree (1.3.3), `--version` (1.3.4),
the parity audit in three batches (1.3.5–1.3.6), every utility declaring its option table (1.3.7), and
these two.

### `df`'s tolerance is now evidence-based, not a name list

Since 1.3.2, `smoke-df.sh` has carried `KNOWN_EXTRA_TYPES="devtmpfs"` — a hardcoded allowlist parked
until a CI run could answer whether that release's duplicate-device filter had made it unnecessary.

⛔ **Waiting on an observation nobody was going to write down is how an allowlist becomes permanent.**
The question is now asked at runtime, on whatever host runs the suite.

The open question was: when GNU hides `/dev` and kriya shows it, is dedup the explanation? kriya
implements GNU's rule — one entry per `st_dev` — so an extra mount is now judged on evidence:

- ⛔ if it **shares a device** with something kriya already listed, dedup should have removed it and did
  not. **That is a kriya bug and it fails.**
- ⚠ if its device is **unique**, no dedup rule could have hidden it, and this GNU is applying something
  kriya does not implement. Tolerated, named, and printed with the device number.

⚠ The type name is gone from the check entirely. **A filesystem type is not evidence of anything; a
duplicate device number is.** Verified both branches — the runner's exact condition simulated (GNU
shimmed to hide `/dev`) reports *"device 7 is unique — no dedup rule applies"*, and the failing branch
confirmed against a synthetic device table.

### ⛔ `src/cmd/` is linted in CI, and the earlier judgement was wrong

1.3.3 enforced deferral tracking across the tree but left the 120-column rule reported-only, arguing
that *"roughly half are single string literals"* and that marking them would be "48 edits that buy
nothing".

**That undercounted the wrappable half.** Of the 48 over-long lines, **19 were argument lists that
simply wanted wrapping** — function signatures, call sites, an `if` body — and wrapping them was
mechanical, verified by the compiler and 3,774 smoke cases. Only 29 genuinely cannot be split: each is
one `help_operands(…)` or `k_write` diagnostic whose length *is* the text, and each is now marked
`#skip-lint`.

⚠ **The marker means "this line's length is one string literal".** A new over-long line that is code
should be wrapped, not marked — and CI now enforces that, so both halves of `cyrlint` are live for
every file in the tree.

⭐ Verified the rule bites by inserting a deliberately long line: `warn line 6: line exceeds 120
characters`, failing the step.

### The arc, closed

Worth recording what the nine releases actually produced, since a fair share of it was not the feature:

- **The interface**: `--help`, `--help=json`, `kriya --list`, `--version`, and an option table on all
  38 utilities — every form derived from **one declaration per utility**, with a lint that fails the
  build if a fourth reader ever copies the data instead.
- **Six real kriya bugs**, every one silent-wrong-output rather than a crash: `sort -k F` read as
  `-k F,F`; `sort -k F1,F2` truncated; `find -exec`/`xargs` handing the child the wrong `argv[0]`;
  `df` missing GNU's duplicate-device filter; `df` hiding `hugetlbfs` by name where GNU hides it by
  zero-blocks; and 44 wrong `k_write` lengths, nine of which truncated a message and 35 of which read
  one byte past the literal.
- **A test suite that can now fail for the right reasons**: 1,012 cases at v1.1.10 that had never run
  in CI, against 3,774 today that run on every pull request — plus four lints, an oracle-identity
  check, and a verification matrix that runs the whole suite under a hostile environment, a deep
  `$TMPDIR`, and simulated root.

⛔ And the thing most worth keeping: **three of those six bugs were hidden by something that looked
like evidence** — a comment claiming `-k F1,F2` was "verified byte-identical to GNU" (it named only
the cases where the bug is invisible), a local coreutils version that basenamed `argv[0]`, and a
`du`/`df` type list that matched GNU by coincidence on any ordinary host. A green test is not a
finding. A test that could not have gone red is not a test.

### Tests

**3,774 smoke cases across 37 scripts**, 119 unit + 18 POSIX, fuzz green under poison, four lints clean,
both targets build, and the whole suite green under all four hostile conditions.

## [1.3.7] - 2026-08-26 — every utility declares its option table

The last consumer-facing gap in the 1.3.x arc. ⭐ **No utility renders
`"options": null` any more** — agnoshi can offer flag completion for all 38.

### The constraint that shaped this

Seven utilities — `find`, `date`, `du`, `df`, `env`, `echo`, `seq` — hand-roll their argv walks and so
had no flags spec to read back. The roadmap's rule for closing that was explicit: **either the parser
moves onto the spec, or the utility stays `null`.** ⛔ Declaring a documentation-only spec beside the
real parser is the second source of truth 1.3.0 and 1.3.1 were built to prevent.

⚠ **They still hand-roll, and they should.** Each does it because its *operand* grammar is irregular —
`date`'s `+FORMAT`, `seq`'s bare `-DIGIT` negative operand, POSIX `echo`'s passthrough of everything
after the first operand, `find`'s expression of predicates and operators. A general flags parser handed
`find`'s argv would eat `-name` as an unknown option.

⭐ **What changed is where the option set is written.** Each utility now declares a spec that **its own
walk consults**: the walk asks the spec whether an option exists before dispatching on it, and refuses
anything the spec does not carry. The spec owns *existence*; the walk owns *meaning*. That makes
rendering it honest — it is the parser's data, not a description of it.

### ⛔ `find` carried a dead spec for five releases

`_f_init_spec()` built a `flags_new()` table, assigned three index globals, and stored it in
`_find_spec`. **None of them were ever read, and the function was never called.** Meanwhile the parser
hardcoded the same three letters twenty lines away. Exactly the failure mode the rule above exists to
prevent, sitting in the tree unnoticed since the utility shipped — and the reason `find` rendered
`null`: there was nothing trustworthy to show.

### The invariant, and how it is now checked

The property a completer depends on is that **an advertised option can be typed**. Pinned end-to-end
rather than trusted:

- every advertised boolean short is run against the binary and must not come back as a usage error;
- ⚠ **and the converse** — an unadvertised letter must be *refused*, or "accept everything" would
  satisfy the first check on its own.

⚠ Restricted to utilities whose `positional.min` is 0. `stat -L` exits 2 because `stat` needs an
operand, not because `-L` is unknown — and running every advertised option against `rm` or `mv` to see
whether it parses is not a test, it is a way to lose files.

⭐ **The check found a real one on its first run**: `find -H` is advertised and always refused, because
it is a named deferral (roadmap 1.7.1). Refusing it with *"use -P or -L"* is a better answer than
"unknown option", so it stays listed — but its description now reads `NOT IMPLEMENTED - refused`, and
both halves are pinned so neither drifts.

### Tests

**3,774 smoke cases across 37 scripts** (up from 3,612), 119 unit + 18 POSIX, fuzz green under poison,
four lints clean, both targets build.

⚠ Two expectations encoded the old state and had to be retired, which is the release working as
intended: `smoke-help-json.sh`'s `HAND_ROLLED` set — the utilities required to render `null` — is now
**empty**. The three-way encoding stays in the renderer for a future utility that cannot declare a
spec, and the empty set is what would catch a regression back to an undeclared table.

Binary 1,004,520 → 1,009,576 bytes (+5,056), all of it option descriptions.

## [1.3.6] - 2026-08-26 — the parity audit's low findings; the audit closes

Third and last batch from the 1.3.3 audit. **All 39 findings are now resolved: 11 high at 1.3.4,
19 medium at 1.3.5, 9 low here.**

⚠ As in 1.3.5, nothing in kriya changed. Every fix is to a test that could have passed or failed for a
reason other than kriya's behaviour.

### ⛔ One finding exists to stop a wrong "fix"

`smoke-printf.sh` asserts that `%f`, `%e`, `%g` and `%a` exit 1 and print nothing, under a comment
calling them *"invalid directives"* and claiming *"GNU exits 1 and prints nothing"*. **That comment is
false.** Verified: `/usr/bin/printf '%f' 1.5` prints `1.500000` and exits 0 — they are perfectly valid
floating-point conversions in GNU. kriya refuses them because it has no float formatter yet (roadmap
1.8.0), and refusing loudly beats printing a wrong number.

So the block is a **deliberate divergence, not a parity check**, and the absolutes are the point. The
audit flagged it specifically to prevent someone converting it to a runtime comparison against GNU —
which would have broken a correct test on the strength of a wrong comment. The comment now says what
the block is for. ⚠ `%Z` in the same block genuinely *is* invalid in GNU, and that distinction is now
written down.

### Assertions that measured the host's `od`, not kriya

`basename -z` and `env -0` both piped kriya's output through `od -An -c` and compared against a string
encoding **GNU od's** three-column layout, its padding, and its spelling of NUL as `\0`. busybox od and
BSD od render all three differently, and `od` is absent entirely from a scratch image — so the
assertions were about which `od` was installed. Both now translate NUL with `tr` and compare bytes.

### Fixtures that could kill the whole script

⛔ **`smoke-cp.sh` and `smoke-du.sh` built their payloads from `/dev/urandom` via a bare command under
`set -e`** — three host dependencies, each fatal to the *entire script* rather than to one assertion:
`/dev/urandom` existing (it does not in a minimal chroot or an unpopulated initramfs — **exactly the
environments an AGNOS-targeted toolset runs in**), `dd` existing, and `dd` accepting `status=none`, a
GNU extension busybox rejects. A shared `gen_payload` helper now probes and falls back to a payload
the shell alone can produce. ⚠ Random bytes remain the better fixture where available, so the probe
prefers them rather than replacing them.

⚠ **`du` compares `st_blocks`, which is not stable until writeback.** Under delayed allocation — ext4
`delalloc`, and far more visibly btrfs and XFS where a fresh file can report 0 blocks — kriya and GNU
can sample the same file on opposite sides of the flush and disagree about a file neither touched.
A `sync` after the fixtures is cheap insurance; they are built once.

### Absolutes where the answer was available at runtime

- **`smoke-date.sh`'s epoch window was one second wide in one direction** (`diff >= 0 && diff <= 1`).
  A backwards clock step between the two invocations — chronyd and systemd-timesyncd *do* step on a
  runner that has just booted — turns it red with no kriya defect. Now an absolute difference.
- **`smoke-mv.sh` asserted the preserved subdirectory mode as the literal `750`**, duplicating the
  fixture three lines above it. Change the `chmod` and the test silently starts asserting the old
  value against the new one. Now captured from the source before the move.
- **`smoke-df.sh` asserted GNU's dedup behaviour as an absolute**, three lines after the same property
  was already compared against GNU at runtime — and GNU's duplicate-device filtering is a tie-break,
  not a fixed rule. ⚠ **This was my own code from 1.3.2.** Demoted to an observation; the runtime
  comparisons are the assertions.

### Binaries POSIX does not guarantee

`smoke-env.sh` hardcoded `/bin/sh` sixteen times plus `/bin/echo`, `/bin/true` and `/bin/false`. POSIX
guarantees only that `sh` exists *somewhere*; the other three are guaranteed nowhere, and distroless
and scratch images ship none of them. All resolved once at the top, with a loud skip where the platform
cannot support the test.

⚠ **`command -v echo` answers with the shell BUILTIN**, not a path — so the obvious resolution silently
disabled the very assertions it was meant to protect. `env -i` clears the environment and must exec an
absolute path, so the helper probes the filesystem instead. Caught because the case count dropped from
29 to 26 rather than staying flat.

### Tests

**3,612 smoke cases across 37 scripts**, 119 unit + 18 POSIX, fuzz green under poison, four lints clean,
both targets build.

⚠ The count is slightly *down* from 1.3.5's 3,614: two `df` assertions became observations, which is
the intended effect. **A test count is not a score.**

Verified under the same four conditions as 1.3.5 — baseline, block-size environment variables, a deep
`$TMPDIR`, and simulated root — **37/37 in every one** (3,612 / 3,612 / 3,612 / 3,596, the last
reflecting root-only paths skipping themselves).

### The audit, closed

39 findings over three releases. Worth recording what the pass was actually worth:

- **Two real kriya bugs**, both silent-wrong-output: `sort -k F` reading as `-k F,F`, and `sort -k
  F1,F2` truncating to `F1`.
- **Two assertions that could never fail**, one of them green since the day it was written.
- **One test that could hang CI** rather than fail it.
- **⛔ Three findings that were wrong**, plus **one I wrongly dismissed** — I tested the `sort -k`
  claim with data that could not discriminate it and reported the auditor mistaken. It was not.

⭐ **The lesson worth keeping is the last one.** An audit is a lead list, not a work list, and a
disconfirming test only disconfirms if it could have come out the other way.

## [1.3.5] - 2026-08-25 — the parity audit's medium findings

Second of three batches from the 1.3.3 audit. **All 11 high-risk findings closed at 1.3.4; all 19
medium closed here.** The 9 low findings are 1.3.6.

⚠ Nothing in kriya changed. Every fix is to a test that could pass or fail for a reason other than
kriya's behaviour — which is the same defect class that let the `find -exec` `argv[0]` bug hide for two
releases.

### ⛔ Two assertions could not fail

- **`smoke-option-forms.sh`'s `uniq -cd`.** `uniq` collapses only *adjacent* duplicates, and the
  fixture's two `bravo` lines are not adjacent — so both implementations printed **nothing** and the
  assertion compared `''` to `''`. It has been green since the day it was written and could never have
  been anything else. Given a fixture with a real adjacent run.
- **`smoke-date.sh`'s second-boundary fallback.** `check_parity` ran kriya, then GNU twice, accepting
  `k == g1 || k == g2`. Time only moves forward: if `k` differs from `g1` then `g1` is already at or
  past kriya's second, and `g2 >= g1` — so **`k == g2` was unreachable** and the mitigation never once
  fired. kriya is now bracketed *between* two GNU readings, which is the mitigation that works.

### ⛔ GNU's output units are environment-controlled; kriya's are not

Measured on a 5-byte file: plain `du` prints `4`, `POSIXLY_CORRECT=1 du` prints `8` (512-byte units),
`BLOCK_SIZE=1 du` prints `4096`. kriya prints `4` in all three. The same applies to `df` via
`BLOCK_SIZE` / `DF_BLOCK_SIZE`. On any host exporting one of those — and `POSIXLY_CORRECT` is not
exotic — **~30 `du` comparisons and every `df` numeric comparison fail at once**, blaming kriya for the
caller's shell.

Both oracles now run with those three variables unset. ⚠ The `du` fix needed a second pass because one
invocation bypassed the helper, so `df`'s went through a single `gnu_df` wrapper that every call site
uses — the same mistake was available twice and the shape that prevents it is worth preferring.

### Host-shape assumptions

- ⛔ **`smoke-df.sh` hardcoded `/home` as its probe path.** Not guaranteed to exist (containers,
  minimal images), and on this box not even a separate filesystem. The probe is now discovered from
  GNU's own output. ⚠ It also compared **Used and Available** on a filesystem the test run is itself
  writing to — a build artifact landing between the two invocations moves them. Size only now.
- **`smoke-which.sh`'s fixtures live under `$TMPDIR`**, and kriya's `which` uses `access(X_OK)`. A
  `noexec` `/tmp` — a common hardening default — makes every fixture unexecutable and every assertion
  fail while kriya is correct. The premise is now checked, and the script skips if it does not hold.
- **`smoke-touch.sh`'s century rule asserts a pre-epoch stamp** (`69` → 1969, negative `time_t`), which
  requires the filesystem to store one. GNU is probed first; if GNU cannot store it here either, the
  limitation is the filesystem's. ⚠ Its two `touch` calls were also bare simple commands under
  `set -e` with stderr discarded — a host that refused a stamp would have **aborted the whole script
  silently** rather than failing one assertion.
- **`smoke-mv.sh`'s cross-filesystem guard compared the wrong pair** — `/tmp` against `/dev/shm`, when
  the move under test is `/dev/shm` → `$WORK`, and `$WORK` comes from `mktemp -d`, which honours
  `$TMPDIR`.

### Wall-clock races and harness portability

⛔ **`tail -f` had roughly one poll of slack and no retry.** The writer appends at t≈0.4 s and t≈0.8 s,
kriya polls every 200 ms, `timeout 1.4` killed it. On a loaded runner the writer may not be scheduled
in time and the assertion blames kriya for the scheduler. ⭐ **Retry rather than widen**: a flake passes
on the second attempt in a fraction of what a never-flake budget would cost on *every* run.

**`smoke-sleep.sh`'s two "returns at once" ceilings had no sleep underneath them** — the whole 200 ms
was process overhead (two `date` forks, a `timeout` fork, kriya's exec). Now calibrated against a
measured no-op, so the bound scales with the machine instead of asserting a constant that held on the
box where it was written.

**`smoke-cp-recursive.sh` probed for `script(1)` by name.** `command -v script` is satisfied by
BusyBox's applet, but `-qec` is util-linux syntax BusyBox does not take — so on Alpine the invocation
fails and the assertion blames kriya. It now probes the flags.

### Claims narrowed to what is actually testable

**`smoke-env.sh` asserted `env` execs without forking, via `$PPID` inside `$(...)`** — whose value is
decided by the *shell*, not by kriya. Worse, the pattern it matched (`*:$parent_pid`) only ever checked
the `PARENT=` value the test had just passed in, so the assertion's name and its content disagreed.
Split into what can be tested: that the assignment survives the exec, and that kriya's exec model
matches GNU's.

**`smoke-stat.sh` froze GNU's `?` for an unknown specifier as a literal** — a parity claim about a
default branch in GNU's `stat.c`, which is exactly the shape the `argv[0]` incident took. Now asked at
runtime.

### Two findings audited and deliberately left, with the reason in the code

- **`smoke-wc.sh`'s full-line comparisons.** Flagged for encoding GNU's column padding, which POSIX
  does not specify. Checked: **kriya reproduces it exactly**, multi-file `total` row included.
  Comparing the whole line is the strongest parity assertion available, and a future GNU padding
  change is something worth being told about.
- **`smoke-df.sh`'s `KNOWN_EXTRA_TYPES`.** Stays until the next CI run answers the question 1.3.2
  opened — and if the "additionally shows /dev" note stops appearing, it should be **deleted outright
  rather than maintained**.

### Tests

**3,614 smoke cases across 37 scripts**, 119 unit + 18 POSIX, fuzz green under poison, four lints clean,
both targets build.

⭐ **Verified under each condition these fixes are for**, not just the happy one:

| condition | result |
|---|---|
| baseline | 37/37, 3,614 cases |
| `POSIXLY_CORRECT` + `BLOCK_SIZE` + `DU_BLOCK_SIZE` + `DF_BLOCK_SIZE` | 37/37, 3,614 cases |
| deep `$TMPDIR` (four levels down) | 37/37, 3,614 cases |
| simulated root (`id` shimmed to 0) | 37/37, 3,598 cases — root-only paths skipping |

⚠ The block-size run failed `smoke-df.sh` on the first attempt, after `du` was fixed and `df` was not.
The condition-matrix run is what caught it; a green baseline would not have.

## [1.3.4] - 2026-08-25 — `--version`, and the audit findings worth acting on

Two roadmap items: the dead version string finally gets a reader, and the parity audit's remaining
high-risk findings get fixed rather than filed.

### Added — `--version`, on every utility and on the dispatcher

`ls (kriya) 1.3.4` for a utility, `kriya 1.3.4` for the dispatcher — GNU's `NAME (PACKAGE) VERSION`
shape, accepted everywhere so a caller need not know whether it is talking to a symlink or the
dispatcher.

⭐ **This is the first consumer `src/version_str.cyr` has ever had.** That file is regenerated by
`scripts/version-bump.sh` on every release, is included by `src/main.cyr`, and was **read by nothing** —
its own header named `kriya --version` as the consumer, which was never written. **Thirty releases
faithfully regenerated a string no one could print.** The version comes from `_VERSION_KRIYA`, never a
literal, for the same reason the `--help=json` schema tag is built from its constant.

⛔ **Not `-V`.** GNU gives that to `sort`'s version-string sort and kriya's `sort` header reserves it
for exactly that (roadmap 1.8.1) — claiming it would either collide on arrival or make `sort` the one
utility where a short letter means something else. Same reasoning that keeps `-h` out of help duty,
and it is now pinned by a test.

⛔ **`xargs --version` printed nothing and hung — the 1.3.0 bug, reproduced exactly.** `--version` is
*intercepted*, not declared in any flags spec, so the operand-boundary scan called it the first
operand, making `--version` the command to run — then blocked reading stdin. 1.3.0 fixed this shape
for `--help` and the fix did not generalise because the scan tests for one specific token. Both arms
now sit together with a note that any future intercepted-not-declared option needs one.

### Fixed — the parity audit's remaining high-risk findings

⛔ **Three tests manufactured their failure with mode bits, which do not deny root.** `smoke-mv.sh`
(unwritable parent), `smoke-tee.sh` (mode 0444 file), `smoke-ls.sh` (mode 444 directory, needing
per-entry `stat` to fail EACCES). Under uid 0, `CAP_DAC_OVERRIDE` and `CAP_DAC_READ_SEARCH` make every
one of those operations **succeed**, so the assertions invert and report kriya broken when it is not.
⚠ GitHub's hosted runners are non-root, so this was latent — and "latent until someone runs CI in a
container" is precisely how the `argv[0]` bug survived two releases. Each block now skips honestly as
root. Verified by shimming `id`: the whole suite is green both ways (3,613 cases normally, 3,597 with
the root-only paths skipped).

⚠ **`smoke-realpath.sh` folded stderr into its GNU comparison** (`realpath -m "$P" 2>&1`), so on any
input where GNU fails, kriya had to reproduce GNU's **error wording** byte-for-byte. Error strings are
the part of GNU that changes most freely between releases — pinning them makes the test a version
detector rather than a behaviour check. Now compares stdout, and compares exit status separately,
which is the part that carries meaning.

⛔ **`smoke-rm.sh` assumed its temp directory was exactly two components below `/`.** The ADR-0004
relative-canonicalization case hardcoded `rm ../../` with a comment reasoning *"$WORK is
/tmp/tmp.XXXXXXXX so depth is 2"*. **`mktemp -d` honours `$TMPDIR`** — on a host that points it at
`/var/tmp/build`, `~/tmp`, or a container scratch mount, `../../` lands somewhere that is not `/`,
kriya declines for a different reason, and the test reports the root guard broken. The depth is now
counted from `$PWD`. Verified against a deliberately deep `TMPDIR`.

⚠ **`smoke-tee.sh` used `printf '\x00'`**, a bash / GNU-coreutils extension the POSIX `printf` FORMAT
does not define — under `dash`, which `/bin/sh` is on many CI images, that is not the NUL byte the
test is about. Now `\000`, which means the same byte everywhere. ⚠ Worth noting the test's subject is
NUL fidelity, so the harness was writing the wrong bytes to check the right property.

### Fixed — ⛔ `tests/kriya.tcyr` stopped building. M15e, third occurrence.

`help.cyr` now reads `_VERSION_KRIYA`, and the tcyr includes a **subset** of the tree. Cyrius only
rejects *reachable* undefined symbols, so a missing include stays green until something in the subset
touches it — which is why this fires on the release that adds the first **reference**, never the one
that adds the file. Include added, with the reason written where the next person will hit it.

⚠ A lint guard for this was written and then removed: it just re-ran the tcyr build that the CI Test
step already runs, duplicating the work for a slightly better message. **A check that duplicates an
existing check is not coverage.**

### Notes

⭐ **The `k_write` length lint from 1.3.2 caught one of my own bugs in this release**, immediately and
with the exact correction: `src/main.cyr:216 k_write length 38 should be 39 — truncates the message by
1 byte(s)`. That is the check earning its keep on the release after the one that added it.

### Tests

**3,613 smoke cases across 37 scripts** (up from 3,565), 119 unit + 18 POSIX, fuzz green under poison,
four lints clean, both targets build. `smoke-help.sh` gains 46 cases: every utility's `--version`
string, the dispatcher's own form, `-V` still being a bad option, `--` still terminating, a full
device still exiting 1, and both `--version` routing directions for `find -exec` and `xargs`.

⚠ The whole suite was also run with `id` shimmed to report uid 0: **37/37 green, 3,597 cases**, the
difference being the root-only paths skipping themselves rather than failing.

Binary 1,004,400 → 1,004,520 bytes.

## [1.3.3] - 2026-08-25 — the checks cover the tree, and what they found

1.3.2 turned the smoke suite on in CI and it immediately caught three failures. This release turns on
the checks that were still missing, and fixes what *those* found — including two `sort` bugs that had
shipped for five releases behind a comment claiming they were verified.

### Fixed — ⛔ `sort -k` computed the wrong key window, in both forms

**`-k F` means field F to the END OF THE LINE** in POSIX and GNU. kriya read it as `-k F,F`. And
`-k F1,F2` was accepted and silently truncated to `F1`.

```
printf 'a:1:z\nb:1:a\n' | sort -t: -k2
GNU:   b:1:a  a:1:z          (key "1:z" vs "1:a")
kriya: a:1:z  b:1:a          (key "1" vs "1" — tie, then whole-line fallback)
```

⚠ **Both diverge only when the start field ties**, so ordinary test data never showed them: with
distinct keys, truncation changes nothing. Exit 0, plausible output, wrong order — in the *common*
form of the flag.

⛔ **A comment in `sort.cyr` is what kept this hidden.** It stated the `F1,F2` range *"SHIPS — verified
byte-identical to GNU"* — and the cases it named were `-k1,1` and `-k2,2`, where start equals end and
truncation cannot show. **A verification note that names its cases can still be wrong about what those
cases prove.** The comment now says what was actually checked and what was not.

Fixed in both the delimited and whitespace-field paths, and pinned by 12 new assertions comparing
against GNU across `-k2`, `-k2,2`, `-k2,3`, whitespace fields, `-n`, `-r`, and an inverted range as a
usage error. ⚠ An earlier attempt here *refused* `F1,F2` rather than honouring it; that was the wrong
call — the range is cheap once the window is computed properly, and refusing a flag GNU supports is
its own divergence.

### Fixed — ⛔ three `-i on pipe` assertions never tested a pipe, and could hang CI

`expect_exit` ran `"$@" >/dev/null 2>&1` — **stdin inherited**. So `cp -i` / `mv -i` / `rm -i` saw
whatever stdin the *suite* was launched with. Run from a terminal, `-i` sees a tty, prompts, and
**blocks forever**. Verified by running `smoke-cp.sh` under a pty: it hung until killed. ⚠ A hang is
the worst CI failure shape — it burns the whole job timeout instead of failing. Fixed in the helper,
so every assertion in those scripts is launch-independent, not just the three.

### Added — `scripts/lint-deferrals.sh`, and CI runs it

⛔ **`cyrius lint` takes one file and does not follow includes**, so 1.3.2's lint step could only cover
`src/main.cyr` + `src/lib/`. The 38 files in `src/cmd/` had **never been linted** and carried **56
untracked deferrals** — comments saying "deferred", "follow-up", "TODO" with no cross-reference to
anything. That is the bubble-up discipline the 1.2.x arc applied everywhere else, unenforced in the
directory holding most of the code.

All 56 triaged and resolved:

- ⛔ **5 were stale — the thing they deferred had shipped.** `grep`'s multi-`-e` (1.2.1), `printf`'s
  `\xHH`, `stat`'s `%x`/`%y`/`%z` (1.2.5), `touch -r` and `touch -t` (1.2.5). Each verified against the
  built binary before rewording. **A deferral block that keeps a shipped feature reads as an admission
  of a gap that does not exist.**
- **12 were prose**, where the trigger word appears in an explanation — including three *function
  names* (`_st_is_deferred_spec`) and one `help_example("grep -n TODO src/*.cyr")`. Marked `#skip-lint`.
- **39 were real open work**, now cross-referenced to the roadmap entry that covers them.

⚠ **Deferral tracking is enforced; the line-length rule is not.** `src/cmd/` has 48 over-long lines,
every one a code line and roughly half a single string literal (`help_operands("…")`) that cannot be
split without rewriting user-facing help text. Silencing 48 lines with `#skip-lint` would weaken the
linter's signal to buy nothing. **Enforcing the half that carries meaning beats enforcing neither
while waiting to agree about the other.**

⭐ The lint also rejects a **dangling reference** — a `roadmap 1.4.3` pointing at an entry that does not
exist. A cross-reference to nothing satisfies a linter while sending a reader somewhere that will not
answer them.

Five roadmap entries added for work that had no home: `realpath`'s remaining flags and the `sleep`
multi-operand decision (1.6.3), `rm`'s cross-operand bulk-root defense and `tee -i` (1.6.4, both
blocked on infrastructure), and `date`'s output flags and unrendered specifiers (1.8.4).

### Added — `scripts/check-oracles.sh`, and CI runs it

⛔ **Every parity script resolves its GNU oracle by bare name through `$PATH` and none of them check
what they got.** Not hypothetical: on this dev box `find` resolves to **bfs** in an interactive shell.
A BusyBox or toybox image substitutes a different implementation for every oracle at once, and the
suite would not fail — **it would pass against the wrong answer.**

Checks identity (not version — version differences are legitimate) for all 31 oracles, plus two things
the suite silently depends on: `/usr/bin/printf` existing (`printf` is a *shell builtin*, which is why
`smoke-printf.sh` hardcodes the path — absent on NixOS and Guix), and `C.UTF-8` being installed
(glibc's `setlocale` fails silently, degrading GNU `wc -m` to a byte count with no diagnostic).

### Fixed — `df` type filter now matches GNU by construction

kriya named 11 filesystem types GNU does not — `cgroup`, `cgroup2`, `tracefs`, `pstore`, `bpf`,
`configfs`, `securityfs`, `binfmt_misc`, `ramfs`, `sunrpc`, **`hugetlbfs`**. GNU hides all of them via
the zero-blocks rule instead, and a type-name skip is unconditional where zero-blocks is a property of
the mount. ⛔ **`hugetlbfs` reports `f_blocks` = the number of reserved hugepages**, so on a host with
`vm.nr_hugepages > 0` GNU lists `/dev/hugepages` and kriya **hid** it — kriya omitting a filesystem GNU
shows, the direction a user notices.

The list is now gnulib's `ME_DUMMY_0` verbatim, plus its `type == "none"` clause. ⚠ Every one of the 11
reports zero blocks on an ordinary host, which is exactly why matching by coincidence held for five
releases; local output is unchanged and still byte-identical to GNU. Asserted where it can be — the
hugepages case skips honestly on a host with none.

### Fixed — `k_getdents` used a bare `217`

`SYS_GETDENTS64` is **217 on x86_64 and 61 on aarch64**. ⛔ **All 46 raw numeric syscalls in kriya are
x86_64 numbers** — `openat` 257 vs 56, `unlinkat` 263 vs 35, `write` 1 vs 64, `exit` 60 vs 93. Not a
bug today (kriya builds x86_64 and agnos only), but an aarch64 build would compile clean and call
entirely wrong syscalls. `k_getdents` is converted as the worked example; the sweep is on the roadmap
as one reviewable pass.

⚠ **`k_getdents` must NOT become stdlib `xgetdents`**, which is what cyrlint suggests: `xgetdents`
returns the raw agnos record, while `k_getdents` translates it into `linux_dirent64` so every caller
sees one format. The swap would silently mis-parse every directory entry on agnos. The reason is now
at the call site.

### Tests

**3,565 smoke cases across 37 scripts** (up from 3,553), 119 unit + 18 POSIX, fuzz green under poison,
both targets build, and four separate lints clean.

⚠ **The parity audit produced 39 findings and only the verified ones are fixed here.** The rest —
tests whose failure is manufactured with `chmod` and so does not deny root, oracle output folded
together with stderr, `printf '\x00'` as a bash extension under `dash` — are on the roadmap with file
and line. ⛔ Two audit claims were wrong on inspection and are not acted on; one of *mine* was wrong
too: I dismissed the `sort -k` finding after testing with data that could not discriminate it. **The
finding was right.**

Binary 1,000,192 → 1,004,400 bytes.

## [1.3.2] - 2026-08-25 — `kriya --list`, and a CI that can actually fail

Closes the **1.3.x discoverability arc** and the last of the five items kriya owed agnoshi. Also the
release where the test suite started running in CI — it never had.

### Added — `kriya --list`

The whole utility table as one JSON document: `name`, `summary`, `synopsis`, `destructive`,
`exit_codes` per utility. ⚠ A public interface, versioned by `KRIYA_LIST_SCHEMA_VERSION` in
`src/lib/args.cyr` **separately from** the `--help=json` schema — a consumer may parse one and not the
other, and the two need not break together.

⭐ **One table, two readers.** The 38-branch `streq` chain in `dispatch()` is now a table of
`(name, &cmd_<util>, &<util>_help_declare)` walked by both the dispatcher and `--list`, so **a utility
cannot be reachable but unlisted, or listed but unreachable.** Adding a utility is one row. Cyrius'
`callptr` makes the indirect call; verified on both targets. ⚠ Dispatch cost is unchanged — measured
at the first table row (`true`) and the last (`df`): **+0.0% and −0.9%**.

⭐ **Enumerating 38 utilities costs one process, not 38.** Each utility's help record was declared
inside `cmd_<util>`, so reading it meant running the utility. Those declarations are now
`<util>_help_declare()`, callable without executing anything: **`kriya --list` is 1.402 ms** against
~17 ms for 38 execs, and it is what agnoshi runs at shell startup.

`kriya --help` also answers now, with the dispatcher's own page and the utility list. It previously
said *"unknown utility: --help"*, which is a poor first thing to tell a new caller.

### Fixed — ⛔ 44 wrong `k_write` lengths, 39 of them pre-existing

kriya passes explicit byte lengths to `k_write` rather than calling `strlen` — an intentional choice on
the cold-start path. **44 of 509 hand-counted lengths were wrong.**

- **9 truncated** the message, usually eating the trailing newline, so the error ran into whatever
  came next. `kriya basename a b c` ended mid-sentence at `for multiple paths)` with no newline.
- **35 read past the end of the literal.** ⚠ Bounded: every one overshot by exactly **one byte**,
  landing on the literal's own NUL terminator — so this put a stray NUL in the error stream, **not a
  leak of adjacent `.rodata`.** `kriya sleep` emitted `got 0\n\0`.

All 44 corrected, and the check is now a lint rather than a habit — see below. ⚠ The explicit-length
convention stays; the answer to a hand-counting hazard is a machine that counts, not 509 `strlen`
calls on the startup path.

### Added — the CI lint ADR 0002 promised

`scripts/lint-help-schema.sh`, four checks:

1. **`src/cmd/*.cyr`, the dispatcher table and `kriya --list` name the same 38 utilities.** A file
   without a table row is how a utility silently goes missing from the interface.
2. Every utility declares a complete `--help=json` document — all fields present and typed,
   `positional` never null.
3. `--list` and `--help=json` agree on summary, synopsis, destructive and exit codes. ⚠ Currently
   unfalsifiable by construction — both read one record — so this is a **guard against a future second
   source of truth**, not an active detector. Kept for exactly that reason.
4. Every `k_write(fd, "literal", N)` has N equal to the literal's byte length.

⛔ **A lint that cannot fail is worthless**, so each class was verified by breaking it: a wrong length,
a deleted table row, a missing `help_positional`. All three were caught with the right message.

### Fixed — CI never ran the tests that matter

⛔ **CI built both targets and ran the two `.tcyr` suites. That was all.** No lint, no vet, no smoke
scripts, no fuzz. **3,547 behavioural cases written since v0.2.0 — the ones that compare kriya against
GNU coreutils cell-by-cell — had never run on a pull request**, only at release cuts on this machine.
So "a non-conforming schema fails CI" was not achievable no matter how good the lint was.

CI now runs lint, vet, the schema lint, all 37 smoke scripts and the poisoned-allocator fuzz. **Total
added cost: 13 seconds.**

⚠ **`cyrlint` takes one file and does not follow includes.** The lint step covers `src/main.cyr` and
`src/lib/` only — `src/cmd/` is **not** linted and a green check does not mean the tree is clean.
Those 38 files carry **45 over-long lines and 59 untracked deferrals**; the deferral half is the
valuable one and is its own release (roadmap, 1.3.x). Three false positives in `args.cyr` — prose
*explaining* that work was **not** deferred — are marked `#skip-lint`.

⚠ Verified by replaying every CI step from a clean tree with no vendored `lib/`. GitHub Actions itself
cannot be run locally; the workflow file is the only part of this release not directly verified.

### Fixed — ⛔ `bench-coldstart.sh` has overstated cold start by ~3× since v0.2.0

The loop was the obvious one:

```sh
t0=$(date +%s%N); "$BIN" true; t1=$(date +%s%N)
```

**The span from `t0` to `t1` contains the whole `date` process that produces `t1`** — a fork+exec of
GNU coreutils, measured here at **0.570 ms** against kriya's **0.428 ms**. So roughly **60% of every
cold-start figure in this project's history is `date`, not kriya**, and cross-machine comparisons
largely compared how fast `date` forks there.

⚠ **This also corrects 1.3.1's release note.** That note blamed a reading ~180 µs above the v1.0.0
baseline on the box being loaded. It reproduced at load average **0.48**, which falsifies that
explanation. The real answer is that the metric was never a clean measure of kriya's spawn cost.

Fixed by timing a **batch** of N runs between two timestamps — amortising the two `date` forks to ~2 µs
each — and subtracting a control batch of the same loop with no spawn. 1.3.1 and 1.3.2 measured with
the corrected tool: **0.635 ms → 0.637 ms.** ⚠ The pre-1.3.2 figures in `state.md` are **not**
comparable to these and are labelled as such.

### Fixed — three failures the new CI step immediately caught

⭐ **Turning the smoke suite on in CI paid for itself on the first run.** All three failures were
invisible on the dev box, and one was a real defect that had shipped two releases earlier.

⛔ **`find -exec` and `xargs` handed the child the wrong `argv[0]` — a genuine bug.** Both PATH-resolve
the command and then wrote the resolved path back into `args[0]`, so the child saw
`argv[0] = /usr/bin/rm` where `execvp` gives it `rm`. GNU tools print `argv[0]` as their error prefix,
so every diagnostic from an `-exec`'d program named itself by absolute path:

```
/usr/bin/rm: cannot remove 'x': Permission denied     (kriya)
rm: cannot remove 'x': Permission denied              (GNU)
```

⚠ **The dev box hid this for two releases**: coreutils **9.11 basenames `argv[0]` before printing**, so
it said `rm:` either way. The runner's 9.4 does not. **A GNU-parity test can pass because of the local
GNU's version rather than because kriya is right.**

The resolution itself is correct and stays — a bare name must not be left for the kernel to resolve
against the current directory, which in the `find /shared -exec` shape is attacker-writable. What was
wrong is that **the exec target and `argv[0]` are not the same thing.** New `k_spawn_as(exec_path,
args, env)` separates them; `k_spawn` is now a wrapper passing `args[0]` as both. ⚠ `env` already did
this correctly and was the model. ⚠ agnos keeps the old behaviour: stdlib `exec_vec` takes only the
vector and uses element 0 as both, so the two cannot be separated there — running the right binary
wins over the error prefix. Verified with a purpose-built probe that prints its own `argv[0]`: kriya
and GNU now agree for `find -exec`, `xargs` and `env`.

⚠ **`smoke-write-errors.sh` asserted a hardcoded `141` for `yes` into a closed pipe.** **141 is a
property of the environment, not of `yes`.** If the parent holds SIGPIPE at `SIG_IGN`, `write` returns
EPIPE instead of the kernel killing the writer — and **GNU `yes` exits 1 there too**. `SIG_IGN`
survives `execve` (only installed handlers reset to `SIG_DFL`), and POSIX forbids a non-interactive
shell from resetting a signal ignored at entry, so `trap - PIPE` does not undo it. Measured both ways
here: SIGPIPE default → GNU 141, kriya 141; SIGPIPE ignored → GNU 1, kriya 1. **Parity in both.** The
test now asserts parity with GNU plus "never 0", and checks the absolute only where GNU itself shows
141, skipping honestly otherwise. ⛔ The comment in `src/lib/sys.cyr` claiming *"EPIPE does not reach
here"* was unconditionally false and is what made the hardcoded absolute look safe; corrected.

⛔ **`df` was missing GNU's duplicate-device filter entirely — a second real bug, found while
investigating the third failure.** GNU's `filter_mount_list` stats every mount point, groups by
`st_dev`, and keeps one entry per device. kriya had no equivalent, so **any second mount of the same
filesystem showed twice**:

```
mount --bind /home /tmp/bindtgt
GNU df   -> /tmp/bindtgt absent
kriya df -> /tmp/bindtgt present     (same st_dev as /)
```

That is not exotic — bind mounts, Docker overlays and btrfs subvolume mounts all hit it, and CI
runners are full of them. ⚠ Invisible on a dev box that happens to have none, which is why five
releases of `df` shipped without it.

⭐ **It is also the only GNU filter that can explain the reported symptom.** No GNU rule excludes
`devtmpfs` by *type* — its dummy list has never contained it — so on a host where GNU hides `/dev`
and kriya shows it, dedup is the one mechanism GNU has that kriya lacked. Implemented with GNU's
observable tie-break: shortest mount point wins, earliest line breaks a length tie. ⚠ Default-listing
only, like the pseudo-FS filter — `-a` still shows every duplicate, and naming a path explicitly is a
request for *that* filesystem.

Verified in an unprivileged mount namespace against three bind mounts: kriya's default set and its
`-a` set are now **byte-identical to GNU's**, and pinned by four new assertions that skip honestly
where a namespace is unavailable.

⚠ **`smoke-df.sh` also asserted exact mount-set equality with GNU**, which is fragile independent of
the bug above: kriya's skip list is fixed type names plus "zero blocks", GNU's is a different
algorithm whose dummy list has changed across releases. The two directions are not equally serious and
the test now says so: ⛔ **kriya omitting a filesystem GNU shows is always a failure** — that is the
one a user notices — while an extra virtual filesystem is allowed only for named types, with the type
printed so a new divergence still fails loudly. Verified by shimming `df` three ways: the runner's
exact condition passes with a note, an omission fails, an extra real filesystem fails.

⚠ Whether kriya should *also* hide `devtmpfs` by type is left open, and is now probably moot — the
two GNU versions to hand disagree, so there is no oracle to copy, and dedup likely covers the runner
case. The next CI run settles it: if the "additionally shows /dev" note is absent, it does.

### Tests

**3,553 smoke cases across 37 scripts** (up from 3,030 across 36), 119 unit + 18 POSIX, fuzz green
under poison, lint and schema-lint clean, both targets build.

⚠ Re-run end-to-end under **simulated runner conditions** — SIGPIPE ignored in the parent and a GNU
`df` shimmed to hide `/dev` — all 37 scripts green (3,552 cases; one fewer because the SIGPIPE-death
assertion correctly skips itself).

⚠ The bind-mount check asserts **only the duplicate's fate**, in kriya and in GNU, under each flag. An
earlier version diffed the whole mount set inside the namespace and so re-ran the main assertion
there, inheriting every unrelated GNU-version difference — it went red the moment the surrounding
environment's GNU disagreed about something else. A check should assert what it is about.

- `scripts/smoke-list.sh` — new, 517 cases. Every entry's fields and types; ⭐ **every listed utility
  is invoked to confirm it actually dispatches** — a name in the table that does not route is worse
  than a missing one, because a completer would offer it; `--list` agreeing with `--help=json`
  field-by-field for all 38; the destructive set pinned by name; `kriya --help`'s UTILITIES section
  matching `--list`; ⛔ **dispatcher flags not leaking into utilities** (`ls --list` is ls's bad
  option, and a symlink invocation never sees them at all); argument handling; 80-column wrapping;
  and `> /dev/full` exiting 1.

Binary 995,280 → 1,004,360 bytes (+9,080, +0.9%).

## [1.3.1] - 2026-08-25 — `--help=json`, the machine form

Second of the **1.3.x discoverability arc**, and the ADR-0002 commitment that has been open since
v0.2.0. All 38 utilities now answer `--help=json` with a document conforming to
[ADR 0002 Appendix A](docs/adr/0002-option-parsing-humans-and-agents.md#appendix-a---help=json-schema-v1).

⚠ **This output is a public interface.** agnoshi's tab-completion parses it. Adding a field is allowed
within a major; removing or retyping one bumps `KRIYA_HELP_SCHEMA_VERSION` in `src/lib/args.cyr` and
needs an ADR.

### Added — `--help=json` on every utility

⭐ **The schema tag is built from the version constant, not written as a literal** —
`"kriya-help/v" + KRIYA_HELP_SCHEMA_VERSION` — so the tag cannot claim a version the constant has
moved past. Same discipline as 1.3.0's OPTIONS table: the thing that could drift is derived, not
duplicated.

Options come from the same `flags_new()` spec the parser uses, so **the machine form and the human
form are one source read twice** — pinned by a test that scrapes the OPTIONS section out of `--help`
and diffs it against the JSON array.

### Three schema decisions worth the words

⛔ **`options` is three-way, not two.** An array is the option table; `[]` means the utility genuinely
takes no options; **`null` means the utility hand-rolls its argv walk and its options are not
machine-declared.** Ten utilities parse argv themselves, and seven of them — `find`, `date`, `du`,
`df`, `env`, `echo`, `seq` — have real options that are simply not in a spec to read back. Emitting
`[]` for those would tell an agent that **`du` has no `-h`**, which is false. `null` says "read the
human form". The remaining four (`true`, `false`, `yes`, `sleep`) are genuinely optionless and say so
with `[]`.

⛔ **`notes` was added, because the safety prose was not reaching the machine form.** The JSON carried
`summary` and `synopsis` but not the second DESCRIPTION paragraph — which is exactly where
`rm`'s *"refuses `/` with no escape hatch (ADR 0004)"*, its symlink refusals, and `grep`'s operand
conditions live. **An agent reading only the machine form would never have seen the part of the page
written specifically to stop it doing damage.** Caught by asking the round-trip test where the `⚠`
went.

⚠ **`positional.min` is the smallest count *any valid invocation* may have — not the usual one.**
`grep -e PATTERN` and `rm -f` both take zero operands legitimately, so both declare `min: 0` even
though the bare forms need one. The rule is that a validator using this field must never reject a
correct invocation; the conditions are spelled out in `notes`. The initial survey had `grep` at
`min: 1`, which would have made a completer append a bogus operand to `grep -e foo`.

### `destructive`, the field agnoshi asked for

True when running the utility can modify persistent state, **either directly or by executing a command
the caller supplies**. ⚠ Delegation counts: `xargs`, `env` and `find` (via `-exec`, which kriya
implements) mutate nothing themselves, but **`xargs rm` is precisely the invocation a completer should
warn about**. Thirteen utilities are true: `cp`, `mv`, `rm`, `ln`, `mkdir`, `rmdir`, `touch`,
`sort` (`-o`), `tee`, `uniq` (its `OUTPUT` operand), `env`, `xargs`, `find`.

### Fixed

⛔ **ADR 0002 contradicted itself on `-h`.** The Decision section listed **"`-h` / `--help` — human
form"** while the Consequences section said `-h` is reassigned per utility and `--help` carries help
duty alone. The implementation has always followed the second, and 1.3.0 pinned it with tests; the
first is now corrected rather than left for a reader to pick between.

### The escaping is not optional

⛔ Six help strings already contain a literal backslash — `printf '%s=%d\n'`, `tr -d '\r'`, `stat`'s
`\-escapes`. Emitted raw they produce **invalid JSON that a strict parser rejects outright.** Full
RFC 8259 escaping, with `\u00XX` for the control characters that have no short form. ⚠ UTF-8 passes
through as UTF-8 (`load8` zero-extends — verified — so a lead byte reads as 194..244 and never trips
the control-character test).

### Tests

**3,030 smoke cases across 36 scripts** (up from 1,595 across 35), 119 unit + 18 POSIX, fuzz green
under the poisoned allocator. Both targets build.

- `scripts/smoke-help-json.sh` — new, 1,432 cases. ⭐ **The load-bearing test is not "is it valid
  JSON" — it is boundary enforcement: the `positional.min` and `positional.max` each utility
  advertises are fed back to the real binary and must actually be enforced.** One operand under a
  declared minimum, or one over a finite maximum, has to be a usage error; `grep -e`, `grep -f` and
  `rm -f` have to be accepted with zero operands. **A schema that lies about operand counts is worse
  than no schema, because an agent trusts it.** Plus: every required field present and correctly
  typed, `options` three-way, escaping round-trips, UTF-8 survives, `--help=json` routing for `xargs`
  and `find -exec`, `--` still terminating, unknown formats naming the valid set, and `> /dev/full`
  exiting 1.

⚠ The anti-drift check failed on first run for `--complement`, `--printf` and
`--ignore-fail-on-non-empty` — **the renderer was right and the test was wrong.** A long-only option
indents six spaces so its `--` aligns under the long names beside it; the scraper only understood the
two-space short+long shape.

### Notes

**Cold start is flat, and now actually measured** — the number 1.3.0 could not take. Interleaved A/B
against a 1.3.0 binary built from its own commit, arms swapped each pair, 500 pairs:
**0.474 ms → 0.477 ms** (+0.6%, noise). By `scripts/bench-coldstart.sh`'s own methodology, 300 runs
each: **median 1.382 ms → 1.396 ms**.

⚠ **Both arms read ~180 µs above the 1.196 ms v1.0.0 baseline, and that is the box, not the release.**
The 15-minute load average was still 58 while these ran. The A/B is sound — both binaries measured
under identical conditions, alternating — but **the absolute figure should not be entered in the
history table as a regression.** Binary 986,416 → 995,280 bytes (+8,864, +0.9%).

## [1.3.0] - 2026-08-25 — `--help`, on all 38 utilities

Opens the **1.3.x discoverability arc**. First of the post-defect arcs, and the first release since
1.1.9 that adds capability rather than repairing it.

⚠ **This arc has an external consumer waiting.** agnoshi's tab-completion needs `kriya --list` and
`<util> --help=json` to offer completions without hardcoding kriya's surface. 1.3.0 builds the
renderer and the per-utility prose those forms will serialise; 1.3.1 adds the JSON, 1.3.2 the
top-level list.

### Added — `--help` on every utility

⭐ **The OPTIONS table is read back out of the flags spec**, not written by hand. Every utility already
declares its full option table to `flags_new()` for the parser; nothing read it back. Short letter,
long name, kind and description all come from there, so **the option list cannot drift from what the
parser accepts — it *is* the parser's data.**

What a spec cannot supply is prose: a summary, a synopsis, what the operands are called, what the exit
codes mean, and a couple of examples. Those are declared per utility with `help_begin` /
`help_operands` / `help_exit` / `help_example`, sitting next to the flags they describe.
`help_begin` seeds the [ADR 0008](docs/adr/0008-posix-exit-code-policy.md) three-tier codes, so a
utility only declares what it does *differently* — `grep`'s no-match-is-1, `xargs`' 123–127 ladder,
`env`'s 126/127.

Sections follow [ADR 0002](docs/adr/0002-option-parsing-humans-and-agents.md) exactly: `NAME`,
`SYNOPSIS`, `DESCRIPTION`, `OPTIONS`, `EXIT CODES`, `EXAMPLES`, wrapped at 80 columns.

⚠ **ANSI only on a tty** — verified by a test that pipes `--help` through `od` and fails on an escape
byte. Styling a redirected stream puts escapes into whatever consumes it, and the consumer here is a
shell completer.

### The parts that were not obvious

⛔ **`-h` is not help, and must never become it.** ADR 0002 reassigns it per utility — `du -h`,
`ls -h` and `sort -h` all mean human-readable. "Add `-h` as an alias" is the obvious-looking change
that would silently break three utilities, so the test suite pins `du -h` producing sizes and
`sort -h` being a *bad option*.

⭐ **`--help` renders and exits inside the parser rather than returning a sentinel.** All 28
spec-based utilities have the shape
`if (kriya_args_parse(...) != 0) { report "bad option"; return EXIT_USAGE; }` — so any non-zero return
would print "bad option" for a successful `--help`. Threading a third outcome through 28 call sites is
28 chances to get it wrong, for a path that legitimately terminates the process. ⚠ The write-failure
flag is still checked before exiting, so `kriya ls --help > /dev/full` does not exit 0.

⛔ **`--help` has to reach the right program.** Two utilities take argv that is *someone else's
command line*, and both got this wrong first time:

- `xargs --help` printed **nothing**. `--help` is in no spec, so the operand-boundary scan called it
  the first *operand* — making `--help` the command to run. It is now recognised in that scan, so
  `xargs --help` is xargs' help while **`xargs echo --help` still hands `--help` to `echo`**.
- `find . -exec echo --help {} \;` printed **find's** help. The hand-rolled utilities scanned all of
  argv, finding a `--help` never addressed to them. They now check the **first argument only** — which
  is the shape that means help; anything later belongs to whatever is being expressed or executed.

⚠ **Ten utilities have no OPTIONS section, and that is correct.** `find`, `seq`, `env`, `du`, `df`,
`date`, `echo`, `sleep`, `yes`, `true` and `false` walk argv themselves and have no spec to read back.
Their pages carry every other section; OPTIONS is absent rather than empty.

⚠ **`--help=json` is named, not rejected.** It answers *"not implemented yet; use --help"* and exits 2.
Answering "bad option" would read as "no such flag" — the wrong thing to tell an agent probing for the
interface ADR 0002 promises.

### Fixed — a subset build broke, exactly as the watchlist predicted

⛔ `tests/kriya.tcyr` stopped compiling: `args.cyr` now calls into `help.cyr`, and the tcyr includes a
*subset* of `src/lib/`. This is **roadmap M15e**, written up three releases ago — cyrius only rejects
*reachable* undefined functions, so a missing include stays green until something calls it. The entry
predicted the failure and named the check; the check is now also in the test file's own comment.

### Notes

⚠ **Cold start is unmeasured this release, and that matters for this arc.** agnoshi may spawn kriya on
every `<tab>`, against a 2 ms budget last measured at 1.185 ms. The box was at load average **31**
during the attempt — another workload running 80 processes — and an interleaved A/B gave contradictory
directions across a swap, which is noise, not signal. What *is* stable: the binary grew
**965,144 → 986,416 bytes** (+21 KB, +2.2%) for the help text. Re-measure on a quiet box before 1.3.2.

### Tests

**1,595 smoke cases across 35 scripts** (up from 1,315 across 34), 119 unit + 18 POSIX, 1,529 fuzz
assertions green under the poisoned allocator. Both targets build.

- `scripts/smoke-help.sh` — new, 280 cases. Every one of the 38 utilities is checked for exit 0, a
  `NAME` heading, its own name on the NAME line (catching a stale copy), and all four remaining
  sections. Plus: the OPTIONS table matching the parser, a short-only option rendering no dangling
  comma, a value-taking option marked, `-h` keeping its per-utility meaning, no ANSI down a pipe,
  `--help` routing correctly for `xargs` and `find` in both directions, `--` still terminating option
  recognition, and `--help=json` naming itself.

⚠ Two of those blocks needed `rc=0; cmd || rc=$?` rather than `$(cmd; echo $?)` — under `set -e` the
subshell aborts at the non-zero status before it can echo it. That is the fourth release in a row this
has come up; it is now spelled out in the script.

## [1.2.6] - 2026-08-25 — closing the defect arc

The last three confirmed defects from the v1.1.11 P-1 sweep. **M17 is retired**, and with it the
1.2.x correctness arc: ten reproduced defects, all closed across 1.2.0–1.2.6.

### Fixed — `ls -l` fabricated metadata when a per-entry stat failed (M17g)

⛔ **`fs_stat_entry`'s return was discarded and the all-zero buffer rendered.** In a
readable-but-not-searchable directory (`chmod 444`), where every per-entry stat fails EACCES, `ls -l`
printed `---------- 0 0 0 0 1970-01-01 00:00` and **exited 0** — a symlink shown as a regular file, an
epoch-zero date, every field a plausible-looking lie. GNU prints `?` for what it cannot know, reports
`cannot access` per entry on stderr, and exits 1.

⚠ **The fix was not the renderer.** A failed stat had to become a *per-record state* that three
separate places understand: the column-width pass (a `?` is one column wide, not the width of a
fabricated zero), the long-format emitter, and the exit-status rollup.

⭐ **The type character survives**, because it comes from the **dirent**, not the stat — which is what
lets a symlink still read as `l?????????` when it could not be stat'd at all. That is how GNU does it
too, and it is the one field worth keeping when everything else is unknown.

### Fixed — a literal `grep` pattern compiled to an NFA (M17h, kriya-side half)

⛔ **`grep -c "line 000005"` over a 13.6 MB file SEGFAULTED under `ulimit -v 1048576`** — roughly
320 bytes of heap retained per input byte — while GNU answers in constant memory. The pattern is a
plain word; nothing about it needed a regex engine.

Metacharacter-free patterns now route to the already-present `GR_ENG_FIXED` byte scanner.
⭐ **Behaviour-preserving, not an approximation:** `-F` was always a full citizen of the match path —
verified that `-w`, `-x`, `-i`, `-o`, `-v` and `-c` produce identical output on both engines, so the
only thing that changes is which matcher runs underneath.

Measured on the same 13.6 MB file: **no longer crashes**, and a literal scan went from **6.7 s to
115 ms**. The gap to GNU is now ~23×, not the 2300× the roadmap recorded.

⚠ **The regex path still blows up** — `grep 'line.*005'` still segfaults under the same cap. That is
the upstream niyama half, and it stays in the 1.9.x performance arc. This release fixes the case that
needed no upstream at all.

⛔ **This fix introduced a bug that the smoke suite caught immediately, and it is the interesting
part.** `fold_active` — whether `-i` pre-folds the *input* — was keyed off the **invocation** flag
(`-E`/`-F`/`-G`) rather than the engine each pattern actually compiled to. So `grep -i -E foo` folded
the pattern (fixed-engine behaviour) but not the input (RE2 behaviour) and **silently stopped matching
`FOO BAR`**: a wrong answer with exit 0, from a change meant to be invisible. `fold_active` is now
derived from the compiled handles. ⚠ Folding the input is safe for a mixed pattern set — the fold is
ASCII and length-preserving, so `-o` offsets still line up and `(?i)` matches a folded input fine.

### Fixed — `realpath` refused what GNU resolves (M17j)

⚠ v1.1.11 bounded `fs_realpath`'s previously unchecked seed copies, turning a silently wrong answer
into an honest `ENAMETOOLONG` — but it left kriya **refusing 16 KiB operands GNU handles fine**. The
buffer was never a limit worth having; it was a constant nobody had revisited.

The buffers are **sized from the operand** at entry and **grow** for symlink expansion beyond it.
Verified against GNU at 8 KB, 16 KB, 40 KB and **120 KB** operands. ⚠ Growth does not weaken the cycle
guard — that bound is the ELOOP counter (40), not the buffer size, and a `a -> b -> a` cycle still
exits 1.

### The arc, closed

| Release | What it fixed |
|---|---|
| 1.2.0 | clustered/attached options; `xargs` eating the child's flags and its `--` |
| 1.2.1 | six "accepts and lies" cases — success returned while doing the wrong thing |
| 1.2.2 | the spawn helper: child stderr, and two wrong rungs of the POSIX exit ladder |
| 1.2.3 | `grep -r`'s path-based descent; `cp -R` never prompting |
| 1.2.4 | `mv` deleting the only surviving copy; `rm -r link/` half-completing (ADRs 0009, 0010) |
| 1.2.5 | the chrono batch — and the discovery that two-thirds of it was never blocked |
| **1.2.6** | the last three: fabricated metadata, the literal NFA, the realpath ceiling |

### Tests

**1,315 smoke cases across 34 scripts** (up from 1,295), 119 unit + 18 POSIX, 1,529 fuzz assertions
green under the poisoned allocator. Both targets build.

- `smoke-ls.sh` 36 → 43: the unstattable row asserted per type character, the absence of any
  fabricated date, `cannot access` on stderr, exit 1, and a healthy listing still exiting 0.
- `smoke-grep.sh` 76 → 86: eight literal/fold forms against GNU (the `-i -E` regression above is
  pinned by name), a mixed literal-plus-regex `-e` pair, and the 13.6 MB scan under a 1 GiB cap.
- `smoke-realpath.sh` 30 → 33: operands past the old ceiling compared against GNU, and the cycle
  guard verified still intact.

⚠ Three of these test blocks needed `|| true` on a capturing assignment: the command under test is
*expected* to exit non-zero, and under `set -e` a bare assignment aborts the script — in `smoke-ls.sh`
that happened before the `chmod` restore, leaving the trap unable to clean up.

## [1.2.5] - 2026-08-25 — the chrono batch, minus what is actually blocked

Last scheduled batch of the **1.2.x arc**. The roadmap had all six items gated on upstream
`lib/chrono.cyr` growing a duration parser, a date parser and a tzfile reader. **That framing was
partly stale**, so the first work here was checking rather than waiting.

⭐ **What chrono at pin 6.5.35 actually has**, versus what the roadmap assumed:

- `dt_format` exists — but covers only `%Y %y %m %d %e %H %M %S %j`, **less than kriya's own `date`
  renderer** already does with 40 specifiers. Not the enabler it was filed as.
- `dt_strptime` exists — but takes a format string, so it is not the free-form `-d` parser.
- Duration **constructors** (`dur_seconds`, `dur_minutes`, …) exist; a duration **string parser** does
  not, and never did.
- No tzfile reader.

So four of the six items were never blocked on anything. Two still are, and are named below rather
than half-built.

### Added — `sleep` takes fractions and unit suffixes

`sleep 0.25`, `1.5`, `1s`, `2m`, `1h`, `1d`. A bare number is still seconds, as POSIX requires. The
parser is `kriya_parse_duration_ms` in `src/lib/args.cyr` — shared, ~50 lines, and it works in
**milliseconds** because that is `sleep_ms`'s unit and sub-second waits are the whole point.
Fractions finer than a millisecond truncate rather than round, so `sleep 0.0001` is a no-op instead of
a surprise. Timing verified against GNU across six forms, matching to the millisecond.

⚠ Still one operand. GNU sums `sleep 1m 30s`; POSIX specifies exactly one, and summing would make
`sleep 1 2` silently mean 3 rather than the usage error it is today.

### Added — `touch -r REF` and `touch -t STAMP`

`-r` needs no parser at all — it stats the reference and copies its mtime. `-t` takes the POSIX
`[[CC]YY]MMDDhhmm[.ss]` form, including the century rule (69-99 → 19xx, 00-68 → 20xx). Verified
byte-identical to GNU across six well-formed stamps and rejecting eight malformed ones.

⛔ **The first cut of the stamp parser silently rejected every pre-1970 date.** It returned the epoch
second and used a negative value to mean "malformed" — and a pre-epoch stamp *is* negative, so
`touch -t 6901011200` (a valid 1969 date GNU accepts) exited 2. **A sentinel that overlaps the value
domain is not a sentinel.** The parser now returns status and writes the epoch through an
out-parameter, and `has_explicit` is a flag rather than `explicit_sec >= 0`. Verified back to 1950.

⚠ `-r` and `-t` together are **refused**, where GNU takes the last one given. Silently picking a
winner between two explicit time sources is precisely the "accepts and lies" shape the v1.2.1 sweep
removed.

### Added — `stat %x`, `%y`, `%z`

Full `YYYY-MM-DD HH:MM:SS.nnnnnnnnn +0000`, nanoseconds included. **Byte-identical to `TZ=UTC stat`**,
verified including the epoch-zero edge where the nanosecond padding is most likely to be wrong.

⚠ kriya renders **UTC with a literal `+0000`**, so it differs from GNU's default local-time output by
design (ADR 0007), not by defect — `date` has behaved this way since v0.7.0. Rendering the clock in
UTC while printing a local offset would be a wrong answer; this is a true one that happens to differ.
The smoke case compares under `TZ=UTC`, which is the only comparison that means anything.

v1.2.1 made these *refuse* rather than emit their own source text; they now render, and left the
deferred list.

### Still deferred — and now for the right reason

- **`date -d STR` / `touch -d STR`** — free-form human dates ("now", "yesterday", "2 hours ago"). GNU's
  parser is famously large; `dt_strptime` needs a format string and does not substitute for it. A
  real piece of work, not a missing upstream call.
- **`date` local time / `ls -l` locale mtime** — need tzfile parsing. This is the genuine upstream
  dependency, and it is the trigger ADR 0007 already names.
- **`stat %U` / `%G`** (passwd/group parser), **`%N`** (quoting helper), **`%w`** (`statx(2)`) — each
  still refuses by name.

### Tests

**1,295 smoke cases across 34 scripts** (up from 1,261 across 33), 119 unit + 18 POSIX, 1,529 fuzz
assertions green under the poisoned allocator. Both targets build.

- `scripts/smoke-sleep.sh` — new, 15 cases: six accepted forms timed against a floor and ceiling
  (the point is that the duration *parsed*, not that the scheduler is precise), sub-millisecond
  truncation, and eight rejected forms. ⚠ Each rejection asserts a **usage error**, because a
  mis-parsed duration that returns instantly is a failure with no symptom.
- `smoke-touch.sh` 26 → 46: the stamp forms against GNU under `TZ=UTC`, the century rule, the eight
  malformed stamps, `-r` copying the reference time, `-r` with `-t` refused, and `-a`/`-m` staying
  selective when an explicit time is given.
- `smoke-stat.sh` 53 → 52: `%x`/`%y`/`%z` moved from the refusal list to a GNU comparison, plus the
  epoch-zero case.

## [1.2.4] - 2026-08-25 — destructive-verb semantics

Fifth batch of the **1.2.x arc**, and the ADR-gated one: two cases where a destructive verb destroyed
data and *then* reported failure. Both were behaviour decisions rather than bug fixes, so each gets an
ADR — **[0009](docs/adr/0009-mv-never-rolls-back-a-completed-copy.md)** and
**[0010](docs/adr/0010-rm-refuses-a-trailing-slash-symlink-operand.md)** — and the code follows them.

### Fixed — `mv` deleted the only surviving copy (ADR 0009)

⛔ **Total data loss, and the exit status said nothing.** Cross-filesystem `mv` is copy-then-remove.
`_mv_cross_fs` rolled back — deleted the destination — when **either** step failed, under a comment
explaining that the user shouldn't "end up with two authoritative trees." That reasoning is right for
one of the two failures and catastrophic for the other:

- **Copy failed** → source untouched, destination a useless fragment. Deleting it loses nothing. ✅
- **Copy succeeded, source removal failed** → the removal is a **recursive walk that partially
  succeeds**. Most of the tree is already gone, so the destination is the only complete copy — and
  the rollback deleted it.

Measured with the source's *parent* unwritable, so the final `rmdir` fails after the contents are
gone:

```
mkdir -p ro/tree/sub; echo A > ro/tree/a.txt; echo B > ro/tree/sub/b.txt
chmod 555 ro
kriya mv ro/tree /other-fs/moved
```

`ro/tree` empty, `/other-fs/moved` deleted, **both files gone from the filesystem entirely**. GNU
reports the removal error, exits 1, and keeps both files.

**ADR 0009: once the copy has completed, the destination is never deleted.** The rollback stays for
the failed-copy case it was written for. Applied to the regular-file branch too — benign there (a
single failed `unlink` leaves the source whole) but unified so the rule is one sentence rather than a
per-branch judgement, and so `mv` matches GNU on both shapes.

⚠ The "two authoritative trees" concern is real and now unmitigated. It is the lesser harm: two trees
are **visible**, and `mv` tells you.

### Fixed — `rm -r link/` emptied the target, then reported failure (ADR 0010)

⛔ **Worse than either following or refusing.** A trailing slash on a symlink is POSIX-defined to
resolve to the linked-to directory, so the walk descends and deletes everything — and *then* fails to
unlink `link` itself, because `link/` is not a directory to `unlinkat(AT_REMOVEDIR)`:

```
rm -r link/          # rm: cannot remove 'link/': Not a directory
```

`real/` loses every file, the symlink survives, the exit status is non-zero. **Verified identical in
GNU.** The user sees an error, sees the link still there, and reasonably concludes nothing happened.

⚠ It also sat against kriya's own floor: ADR 0003 hard rule #1 is that `rm` never follows a symlink
and *no flag opts in*. The trailing slash was a POSIX-blessed way to follow one — on the utility
CLAUDE.md singles out as the most dangerous.

**ADR 0010: the shape is refused.** Per-operand, other operands still run, exit 1. `rm link` without
the slash is unchanged. ⚠ **`-f` does not bypass it** — the same stance as ADR 0004's root refusal,
and for the same reason: an escape hatch on a destructive verb propagates by copy-paste. The message
names both intents, because the whole problem is that one character silently chose between them.

⚠ **This is a deliberate divergence from GNU**, which performs the half-completed removal. A script
relying on `rm -r link/` to clear a linked-to directory now fails — it was relying on data
destruction reported as an error. ADR 0003's status is updated to record that 0010 extends it.

### Notes

Both ADRs carry their full alternatives-considered sections — including the readings that *lost*
(making the source removal all-or-nothing; following the link and removing it too), because the next
person to look at these will arrive with exactly those ideas.

One cosmetic gap left standing: when the source removal fails, the message carries a `kriya rm:`
prefix inside an `mv` invocation — accurate, but it leaks the implementation where GNU says
`mv: cannot remove`. One slightly-mislabelled line beat two identical ones; noted in the code.

### Fixed — the POSIX harness could hang forever, and had been blamed on load

⛔ **`tests/kriya-posix.tcyr` redirected the child's fd 1 and fd 2 and left fd 0 inherited.** Any case
running a utility that *reads* stdin therefore blocked on whatever the test process happened to have.
`posix_assert_exit("xargs -r empty -> 0", …)` is exactly that case — `xargs` slurps stdin to EOF — so
under a shell whose stdin is an open pipe that never closes, the entire suite hung at the last
assertion until `cyrius test`'s 300 s timeout killed it.

⚠ **This was misdiagnosed twice before being caught.** It first showed up as an apparent timeout right
after a full smoke run, and the box genuinely was loaded (15-minute average 7.85, then 10.75), so it
was attributed to contention — an explanation that fit the evidence available and was wrong. It
recurred at load 0.24, which falsified it. Reproduced deterministically afterwards: hangs with
inherited stdin, passes in **257 ms** with `< /dev/null`.

⚠ CI runs with stdin already at `/dev/null`, which is why this never fired there. It was a latent
landmine, not a passing test.

### Tests

**1,261 smoke cases across 33 scripts** (up from 1,243), 119 unit + 18 POSIX, 1,529 fuzz assertions
green under the poisoned allocator. Both targets build.

- `smoke-mv.sh` 51 → 58: the unwritable-parent shape for both a directory and a regular file, each
  asserting the failure is *reported* **and** the destination survives with its content intact.
  Skips honestly where `/tmp` and `/dev/shm` share a filesystem.
- `smoke-rm.sh` 67 → 78: `link/` refused with the target, the nested file and the link all verified
  intact; `-f` verified not to bypass; and the three forms that must stay unaffected — `rm -r link`
  without the slash, a *real* directory with a trailing slash, and a plain file.

## [1.2.3] - 2026-08-25 — walk safety

Fourth batch of the **1.2.x arc**. Two recursive walks that were not doing what the rest of kriya
does: one re-resolved paths from the cwd at every descent, the other never asked before overwriting.

### Fixed — `grep -r` descended by path, not from a parent fd

⛔ **Every level re-opened the accumulated path with `openat(AT_FDCWD, …)`**, re-resolving every
ancestor component. Replace a directory with a symlink to `/etc` mid-walk and the walk follows it out
of the tree, reporting what it finds there under the original path. The per-file `O_NOFOLLOW` added
by the M8 audit was no defence — **it guards the final component only**, and it made the walk look
protected.

`rm`, `cp` and `find` have descended from a parent fd since M2 (ADR 0003 hard rule). `grep -r` was
the last path-based walk in the tree.

⭐ **A tree deeper than PATH_MAX is the deterministic discriminator, and it needs no race.** A
path-based descent physically cannot open a 6 KB path; an fd-relative one only ever sees one short
component at a time. Measured on a 500-level tree with a 6,524-byte accumulated path:

| | result |
|---|---|
| before | `…/dddddddddd14: file name too long` at depth 14, nothing found, exit 1 |
| after | needle found at depth 500, exit 0 — byte-identical to GNU |

So this is also a **user-visible fix**, not only a hardening one: `grep -r` now works on deep trees.

⚠ **agnos needed a second shape, not the same one.** `fs_opendir_nofollow(real_dirfd, …)` answers
`-ENOSYS` there — agnos has no dirfd-relative call at all — so a naive dirfd rewrite would have made
`grep -r` fail at depth 1 on the target kriya exists for. The new `fs_open_entry_dir` /
`fs_open_entry_file` take **both** the dirfd and the full path and each target uses the half it can,
following the `fs_stat_entry` precedent already in `fs.cyr`.

### Fixed — `cp -R` never asked before overwriting

⛔ **`cp -i -R src dst` overwrote without a single prompt.** Verified under a real pty: GNU asks,
kriya did not. `interactive` was simply never threaded through
`_cp_dir_top` → `_cp_dir_descend_at` → `_cp_file_at`, which opened every destination with `O_TRUNC`
and never looked.

⛔ **And `cp -R src dst` with no `-f` silently replaced existing files** — while the non-recursive
`_cp_one` immediately above it has always refused exactly that. **cp was inconsistent with itself**,
and the recursive half was the one contradicting CLAUDE.md's *"no silent file overwrites without
`-f`"*. The recursive path now refuses too.

⚠ That is a **deliberate divergence from GNU**, which overwrites in both shapes. It is the project's
stated hard rule and the behaviour the other half of the same utility already had; being consistently
stricter beats being inconsistently permissive on a destructive verb.

**A declined prompt is now exit 1**, matching GNU (verified across three pty runs, in both the
recursive and non-recursive paths). kriya returned 0 — so `cp -i … && next_step` proceeded on a copy
the user had just refused.

### Tests

**1,243 smoke cases across 33 scripts** (up from 1,230), 119 unit + 18 POSIX, 1,529 fuzz assertions
green under the poisoned allocator. Both targets build.

- `smoke-grep.sh` 73 → 76: the PATH_MAX-deep walk against GNU (skipped honestly where the tree cannot
  be built), and a symlinked directory inside the tree being skipped rather than descended.
- `smoke-cp-recursive.sh` 50 → 60: the no-`-f` refusal with the destination verified untouched, `-f`
  still overwriting, a fresh recursive copy unaffected, and — via `script(1)` — the `-i` prompt
  answered both ways with its exit status. ⚠ `script(1)` is what makes that path reachable from a
  shell script at all: kriya refuses `-i` on a non-tty stdin by design (ADR 0002), so a plain pipe
  cannot exercise it. The case skips honestly where `script` is unavailable.

## [1.2.2] - 2026-08-25 — the spawn helper: children can speak again

Third batch of the **1.2.x arc**, and the one the roadmap named as a prerequisite: a kriya-local
`fork` + `execve` + `waitpid` in [`src/lib/spawn.cyr`](src/lib/spawn.cyr), so the two utilities that
run user-named commands stop losing what those commands say and what happens to them.

### Fixed — `find -exec` and `xargs` discarded the child's stderr

⛔ **`chmod 555 rot; kriya find rot -name '*.tmp' -exec rm {} \;` printed NOTHING and exited 0 while
deleting nothing.** GNU prints a "Permission denied" line per file. A cleanup job written that way
reported complete success having done nothing at all — a failure mode with no visible symptom.

The cause is one line in the stdlib: `exec_env`'s Linux arm opens `/dev/null` and **`dup2`s it onto
fd 2** in the child before exec (`lib/process.cyr:277`). Every diagnostic the child writes goes into
the void. kriya now forks and execs itself and simply **does not touch fds 0, 1 or 2** — that
omission is the entire fix. Verified byte-identical to GNU's output on the same tree.

### Fixed — the POSIX exit ladder had two wrong rungs

⛔ `exec_env` returns `WEXITSTATUS` on a normal exit and **−1 for everything else**, so "killed by a
signal" and "fork failed" arrive identically, and a failed exec arrives as the child's own
`sys_exit(127)` — indistinguishable from a child that genuinely exited 127. POSIX `xargs` has to tell
five outcomes apart, and −1 cannot express them. Measured against GNU:

| outcome | POSIX / GNU | kriya before | kriya now |
|---|---|---|---|
| child exited nonzero | 123 | 123 | 123 |
| child exited 255 | 124 | 124 | 124 |
| **killed by a signal** | **125** | **127** | **125** |
| **found, not executable** | **126** | **123** | **126** |
| not found | 127 | 127 | 127 |

⭐ **A CLOEXEC pipe is what makes "exec failed" distinguishable at all.** The child holds the write end
with `FD_CLOEXEC` set: a successful `execve` closes it and the parent reads EOF; a failed one writes
its errno through before exiting. There is no other way to separate an exec failure from a child that
chose to exit with the same status — the exit-code convention alone cannot do it.

### Fixed — `xargs` kept going after a catastrophic child failure

⛔ **POSIX: "if the utility exits with status 255, `xargs` shall write a diagnostic message and
exit."** kriya wrote no message and ran every remaining item. Measured with three items and a child
that dies on SIGTERM: kriya ran all three, GNU ran one. Both the `-I` loop and the batch loop now
abort on 124 and 125, and both outcomes explain themselves —
`kriya xargs: ./kill.sh: terminated by signal 15` and `…: exited with status 255; aborting`, matching
GNU's wording under kriya's prefix. A plain nonzero exit still continues, as it should.

### Notes on the helper

⚠ **agnos has no fork.** It offers `execwait(path, len)` — a blocking load-and-run of a static ELF
with no argv, no envp and no fd control — so that arm delegates to stdlib `exec_vec` and can only
report an exit status. It also never had the `/dev/null` redirect, so **the stderr bug was
Linux-only** to begin with; the exit-ladder half was not.

The result is returned as a small tagged integer (`k_spawn_exited` / `_signalled` / `_execfailed`
decoders) rather than a raw wait status, because agnos cannot produce one and a shared decoder beats
two target-specific ones.

⭐ This is the prerequisite the roadmap flagged: `find -exec ... +` (ARG_MAX chunking), `xargs -P`
(parallel jobs) and `xargs -p` (interactive prompt) all need a spawn primitive that returns more than
an exit code. They are now unblocked.

### Tests

**1,230 smoke cases across 33 scripts** (up from 1,215), 119 unit + 18 POSIX, 1,529 fuzz assertions
green under the poisoned allocator. Both targets build.

- `smoke-xargs.sh` 42 → 54: the child's stderr surviving, every rung of the exit ladder compared
  against GNU, the 124/125 abort rule against the plain-nonzero continue, and both diagnostics.
- `smoke-find.sh` 47 → 50: `-exec` child stderr byte-identical to GNU on an unwritable tree, and an
  unexecutable command reported rather than silently treated as a false predicate.

## [1.2.1] - 2026-08-25 — accepts-and-lies

Second batch of the **1.2.x arc**. Not a feature release: every change here is a place kriya returned
**success while doing the wrong thing**. An option refused with exit 2 is a visible gap a user works
around; one accepted and silently ignored is a correctness defect wearing a feature's clothes, and
those now outrank the clean refusals in the running order.

The sweep found the class to be wider than the roadmap had it. Two items were catalogued; six shipped.

### Fixed — every bool long option silently swallowed `=VALUE`

⛔ **`sort --reverse=nonsense` sorted the file and exited 0.** So did `rm --force=nonsense`,
`grep --count=nonsense`, `wc --lines=nonsense`, `ls --all=nonsense` — **every long option registered
as a bool, in all 28 utilities on the shared parser**. GNU answers `option '--reverse' doesn't allow
an argument` and refuses.

The stdlib parser accepts `--name=value` for a bool and drops the value on the floor. kriya's
pre-expansion pass now catches it and reports GNU's diagnostic, naming the offending option, exit 2.
One fix, whole surface.

⚠ **Three options legitimately take a value** and must not be caught by that: `cp --preserve=LIST`,
`sort --check=quiet`, `tail --follow=name`. The parser has no representation for an optional-value
long — registering one as a string would make the bare `--preserve` swallow the next operand — so the
utility opts in by name via `kriya_args_parse_optval` and reads the value back with
`kriya_long_value()`. One slot; no utility needs two.

- **`cp --preserve=LIST`** — `mode` and `timestamps` are honoured (that is what `-p` does). `links`,
  `ownership`, `all`, `xattr` and anything unrecognised are **refused by name**, because accepting
  them is the exact bug: `--preserve=links` used to exit 0 while turning hard links into independent
  copies. Implementing them waits on the inode-set helper (roadmap M12c).
- **`sort --check=quiet|silent`** now actually suppresses the disorder line it exists to suppress,
  keeping exit 1; `diagnose-first` is the default; anything else is refused.
- **`tail --follow=name|descriptor`** is accepted rather than refused, because scripts pass it
  routinely. ⚠ kriya's follow is a stat-cadence poll on the **path**, so `=name` is exact and
  `=descriptor` is an approximation — the difference only shows under rotation.

### Fixed — `grep -e A -e B` silently used only the last pattern

⛔ **`grep -e alpha -e gamma` matched only `gamma`.** No diagnostic, exit 0 — a filter that quietly
dropped half its patterns. `flags_add_str` has one value slot, so earlier occurrences were overwritten
during parsing and there was nothing left to recover afterwards.

⭐ **grep's matcher was always multi-pattern** — that is how `-f FILE` works. Only the *collection* was
lossy. The new `kriya_argv_collect` walks the **expanded** argv, so `-ealpha`, `-ie alpha` and
`--regexp=alpha` all arrive in one normalised shape. Verified against GNU across eleven spellings,
including combinations with `-i`, `-v`, `-c` and `-E`.

### Fixed — `printf` printed the conversion letter and called it success

⛔ **`printf '%f' 1.5` produced the text `f` and exited 0.** It warned on stderr, then wrote the bare
conversion character to stdout — dropping the `%` — and reported success. GNU exits 1 and prints
nothing for an invalid conversion.

Now: floating-point conversions (`%e %E %f %F %g %G %a %A`) get their own message naming them as a
kriya gap rather than a user typo; anything else gets `invalid conversion specification`. Both exit 1
with nothing on stdout. Output already written before the error is kept and processing **stops** —
`printf 'abc%Zdef'` emits `abc`, byte-for-byte what GNU does.

**`\xHH` also landed** rather than being refused. It was cheap, and it had been falling through to the
unknown-escape path and printing a literal `x41`. Byte-exact with GNU across `\x41`, `\x7a`, `\x4`,
`\x41B`, `\101`, `\n`, `\t`, and `\xZ` (which errors with GNU's own wording).

### Fixed — `stat` and `date` echoed specifiers they could not render

⛔ **`stat -c %y file` printed the two bytes `%y`** where a timestamp belonged, and exited 0. A script
substituting that into a filename or a comparison got literal garbage with every sign of success. Same
for `%x %z %U %G %N %w`, and for `date +%V %G %g %c %x %X %r %q`.

Those are now refused by name with a pointer at the milestone that will render them (chrono for the
times, a passwd/group parser for the names). ⚠ kriya therefore **fails where GNU succeeds** on these —
the honest trade, and tracked.

**A genuinely unknown specifier is a different thing and keeps passing through** — but the two
utilities differ, and the old code had `stat` wrong:

- `date +%@` prints `%@`, matching GNU.
- `stat -c %q` now prints `?`, **which is what GNU does** — verified. The old code emitted the source
  bytes under a comment claiming that *was* GNU behaviour, and `scripts/smoke-stat.sh` had a case
  pinning the mistake. ⛔ A test that pins the wrong oracle is worse than no test; it was corrected
  with the measurement recorded next to it.

### Tests

**1,215 smoke cases across 33 scripts** (up from 1,131), 119 unit + 18 POSIX, 1,529 fuzz assertions
green under the poisoned allocator.

- `smoke-option-forms.sh` 31 → 54: `--bool=VALUE` refused across five utilities with the message
  checked, bare bools and genuine `--opt=value` longs untouched, and the full `cp --preserve` /
  `sort --check` / `tail --follow` matrices including "the refused copy created nothing".
- `smoke-grep.sh` 66 → 73, `smoke-printf.sh` 48 → 68, `smoke-stat.sh` 37 → 53, `smoke-date.sh` 44 → 62.

## [1.2.0] - 2026-08-25 — option handling: `rm -rf` works

Opens the **1.2.x arc** (see [roadmap.md](docs/development/roadmap.md)), which puts a running order on
post-1.0 work by batching it around shared enablers rather than by utility. This is the first batch:
one enabler in `src/lib/args.cyr`, and the two confirmed defects that live in the same code.

### Added — clustered and attached short options, across 28 utilities

⛔ **`rm -rf` exited 2.** So did `ls -la`, `grep -in`, `wc -lw`, `sort -rn`, `cp -rp`, `uniq -cd`,
`tail -n5` and `cut -c1-3`. For a coreutils replacement heading into an OS userland that is the
most-typed gap there is — `rm -rf` alone appears in essentially every shell script ever written, and
kriya answered "bad option".

The stdlib parser puts both forms explicitly out of scope (`lib/flags.cyr`: *"NOT supported … `-xyz`
bundled short bool flags … `-xvalue` attached short value"*), so kriya **expands them before handing
argv over** rather than reaching into upstream. `-rf` becomes `-r -f`; `-n5` becomes `-n 5`.

⭐ **The expansion is spec-driven, not a guess.** It asks the caller's own flags spec whether each
letter is a bool or takes a value — so `-rf` splits into two bools while `-c1-3` splits into an option
and its value, with no per-utility table to drift out of sync. `kriya_short_type` and
`kriya_long_type` read `lib/flags.cyr`'s entry layout, which the stdlib documents as a published
contract in its header. ⚠ That is still a coupling; it is now the first thing to re-read at a pin
bump (roadmap M15).

Also **the obsolescent bare-digit form** — `head -5`, `tail -3` — via
`kriya_args_parse_obsnum(spec, start, 110)`. POSIX marks it obsolescent; every shell script still uses
it. It is only unambiguous because neither utility registers a digit as a short option, which is
exactly the condition the code checks.

⚠ **Eleven utilities are deliberately untouched.** `find`, `seq`, `env`, `du`, `df`, `date`, `echo`,
`sleep`, `yes`, `true` and `false` walk argv themselves. That is *why* `find -name`, `seq -5` and
`du -sh` keep working: a multi-character single-dash token that is a **predicate** or a **negative
number** never reaches the expander. Expansion also only fires when the **first** letter is a
registered short — the one condition that keeps a `printf` format or a `tr` set that merely starts
with a dash byte-identical to what it was.

An unknown letter mid-cluster is emitted as its own `-X` on purpose, so `ls -laZ` names the offending
letter instead of rejecting the whole cluster.

### Fixed — `xargs` was parsing the child's command line as its own

⛔ **`echo t.txt | kriya xargs sort -r` silently sorted ASCENDING.** `-r` was eaten as
`--no-run-if-empty` and `sort` ran with no options at all — wrong output, exit 0.
`xargs head -n 2` ran `head` with no options the same way.

⛔ **And the `--` guard was consumed and deleted.** `ls -1 | xargs rm --` handed `rm` an argument list
beginning `-r` and **recursively deleted a directory the `--` existed to protect**.

POSIX stops option recognition at the first operand, and when the operands *are* another command line
that is not a nicety. `kriya_argv_option_end` finds the boundary and everything from it is passed to
the child **verbatim** — taken from argv directly rather than from `flags_positional`, because the
whole point is that those tokens were never interpreted.

⚠ Value-taking options are the entire difficulty: the scan has to know `-n 5` swallows the following
token while `-n5` does not, or the boundary lands one token off and the child loses its first
argument. That is why it is spec-driven rather than a dash-counting heuristic.

### Fixed — `xargs -I` split on blanks instead of lines

⛔ **`printf 'a b\n' | kriya xargs -I{} rm -- {}` deleted files named `a` and `b`, and left `a b`.**
The wrong files, silently. The everyday `ls | xargs -I{} mv {} dest/` idiom mangled every filename
containing a space the same way.

POSIX gives a replacement string one **line** per invocation. `-I` now splits on newline only.
Verified against GNU across eight shapes: leading blanks stripped, **trailing ones kept**
(`"  a b  "` → `a b  `), quotes and backslashes still honoured, empty lines producing no item, tabs
preserved inside the item. `-0` is unaffected — NUL splitting already means one record per item — and
without `-I`, blank splitting is unchanged.

### Fixed — two stale source comments

Comments rot, and a deferred-item list that lies costs someone a re-investigation:

- `src/cmd/tail.cyr` listed **`-f` as deferred**. It shipped at v0.5.0 and follows a growing file
  correctly. The single-file restriction *is* real and is now described as such, rather than the
  whole feature being written off.
- `src/cmd/sort.cyr` listed **`-k F1,F2` end-field key ranges as deferred**. Verified byte-identical
  to GNU for `-t: -k1,1` and `-t: -k2,2`.

### Added — the 1.2.x arc and an enabler map

[roadmap.md](docs/development/roadmap.md) now carries a **running order** alongside the M10–M17
catalogue, with the two views' jobs stated explicitly so items are not tracked in only one of them.
Batches: 1.2.0 option handling (this release), 1.2.1 accepts-and-lies, 1.2.2 the spawn helper, 1.2.3
walk safety, 1.2.4 destructive-verb semantics (ADR-gated), 1.2.5 the chrono batch.

The **enabler map** is the part that makes the batching non-arbitrary: ten shared capabilities, and
what each unblocks. `flags_add_str_multi` alone gates `grep -e`×N, `grep --include/--exclude` and
multi-key `sort -k`; the chrono additions gate six utilities at once.

⛔ **A new organising rule: "accepts and lies" outranks "rejects cleanly."** An option kriya refuses
with exit 2 is a visible gap a user works around. One it *accepts and silently ignores* is a
correctness defect wearing a feature's clothes. Auditing the deferred markers turned up two
immediately, and they are pulled forward into **1.2.1**:

- **`grep -e A -e B` silently uses only the last pattern** — kriya matches `gamma` where GNU matches
  `alpha` and `gamma`. `-e` is registered as a single string, so earlier occurrences are overwritten
  with no diagnostic.
- **`cp --preserve=links` is accepted and ignored**, exit 0, because `--preserve` is a bool and any
  `=VALUE` is swallowed.

### Tests

**1,131 smoke cases across 33 scripts** (up from 1,081 across 32 — 31 new option-form cases plus 19 in `xargs`), 119 unit + 18 POSIX assertions
unchanged, 1,529 fuzz assertions green under the poisoned allocator.

- `scripts/smoke-option-forms.sh` — 31 new cases pinning **both directions**: what must now be
  accepted (clusters, attached values, `head -3`, `rm -rf` actually removing the tree) and what must
  still be left completely alone (`grep --`, a `printf` format starting with a dash, `find -name`,
  `seq -5` as a negative operand, `ls -laZ` still erroring). GNU is the oracle throughout.
- `scripts/smoke-xargs.sh` grows 23 → 42: the child keeping its `-r` and `-n 2`, the `--` guard
  removing a file literally named `-r` while its sibling directory survives, all eight `-I` splitting
  shapes against GNU, and the destructive `a b` case end to end.

## [1.1.11] - 2026-08-25 — the P-1 sweep: nine repairs, six of them data loss, corruption or disclosure

A priority-one audit across security, hardening, correctness, refactor and performance, and the
repairs that came out of it. **No new utilities and no new flags** — every change here makes an
existing verb stop doing something wrong.

Everything below was **reproduced against a shipped build** before it was touched and **re-verified
against GNU coreutils** after. Ten further defects were confirmed and deliberately **not** fixed here
because each needs a redesign rather than a patch; they are itemised with their reproductions in
[roadmap.md](docs/development/roadmap.md) under **M17**. Three reported findings were **refuted** and
are recorded at the end so nobody re-litigates them.

### Fixed — a failed write exited 0 (every applet, silently truncated output)

⛔ **`seq 1 5 > /dev/full` printed nothing and exited 0.** So did `echo`, `printf`, `wc`, `ls`,
`head`, `nl`, `cut`, `grep` and the rest — all 38 verbs share one writer, and v1.1.8 routed every
site through `k_write` without making any of the **~540 call sites check its return**. A full disk, a
failing device or a quota stop produced truncated output *and* success, which is the worst possible
shape: the caller's `&&` chain proceeds on a lie.

Threading a status back through every applet's emit path is a rewrite, so `k_write` now records the
first failure in sticky state and the **dispatcher consults it once, at exit** (`src/main.cyr`).
Output matches GNU: `kriya seq: write error: no space left on device`, exit 1.

⚠ It is a net, not a replacement. The dispatcher only speaks up when the applet itself returned
success — `sort` and `tr` already detected the failure and keep their own more specific messages.
⚠ EPIPE never reaches it: kriya leaves SIGPIPE at its default disposition, so `kriya yes | head` is
still killed by the signal (141, matching GNU). That is now pinned by a test, because the obvious
version of this fix would have broken it.

**The Linux arm of `k_write` also stopped dropping short writes.** It was a bare `syscall(1, …)`
while the agnos arm looped, so the two targets disagreed about the one thing the function exists to
guarantee. Linux `write(2)` returns short whenever a signal lands mid-transfer, and on a pipe past
`PIPE_BUF`.

### Fixed — `k_access` on agnos smashed 96 bytes of its own stack frame

⛔ **`var st[48]` for a buffer the callee fills with 144 bytes.** The agnos arm confused agnos's
48-byte *wire* struct with the canonical Linux layout `_k_agnos_stat` actually writes — it takes the
wire form in its own `var a[48]` and **translates**, always emitting 144 bytes. Reachable from all
four PATH-probing verbs: `which`, `env`, `xargs` and `find -exec`.

⭐ This is the [M15a](docs/development/roadmap.md) rule biting for the second time in three releases:
**a function-local `var X[N]` is N BYTES**; the ×8 u64 unit applies only at module scope. v1.1.9 lost
`find` to it. Reproduced on the host with the same shape — the next local sits exactly 48 bytes away
and the write walks through it into the return address: **SIGSEGV**. Every other stat buffer in kriya
was already `[144]`; this was the lone outlier, and its `# agnos 48-byte stat` comment is what made
it look deliberate.

### Fixed — `cp -r` into its own subdirectory recursed until it dumped core

⛔ **12,188 directories created, then a core dump, with the half-built tree left on disk.**
`cp -r dir dir/sub` descended into the copy it had just made and made another. One mistyped operand
fills a filesystem and crashes. GNU refuses immediately; now so does kriya, with the same message and
exit code — and it refuses **before creating anything**, where GNU leaves two levels behind.

`cmd_cp` already resolves `cp -r a b/` to `b/a` before the recursive call, so the check compares the
directory that would actually be created. Both operands go through the new
`fs_path_absolute` first, so `cp -r /tmp/x/a a/sub` from `/tmp/x` is caught too. Verified against GNU
across nine shapes, including the four that **must not** be refused.

### Fixed — `rm` deleted the parent when handed a `.` or `..` operand

⛔ **`rm -r parent/sub/..` emptied `parent`** — `keep.txt` and `sub/` both gone — and *then* reported
"no such file or directory": an error message for an operation that had already destroyed the wrong
directory. `rm -r d/.` did the same to `d`'s contents. POSIX requires refusing this shape and GNU
refuses it even under `-f`.

The refusal is **per-operand** (other operands still run, exit 1), unlike the ADR-0004 protected-path
check above it, which is invocation-wide and atomic. Names that merely contain dots — `...`, `a..`,
`..x` — stay ordinary removable names. Verified against GNU across all eight shapes.

### Fixed — `ln -f` destroyed the destination when it could not create the link

⛔ **`ln -f /nonexistent-src keep.txt` reported the error and deleted `keep.txt`.** `-f` unlinked
first and attempted the link second, so every failure after that point left nothing behind. GNU
reports the same error and leaves the file alone.

kriya now links under a temp name in the destination's directory and `rename`s over the target, which
is what GNU does — the destination is never absent.

⛔ **"Unlink only on EEXIST" is not good enough, and the reason is not obvious.** The tempting
shortcut treats EEXIST as proof the source is linkable — but **the kernel checks EEXIST before
EXDEV**. Verified against `linkat(2)` directly: a cross-device link onto an existing path answers
errno 17, not 18. That shortcut still deleted the destination and then failed with "invalid
cross-device link" — the same bug, narrowed rather than fixed. The temp name needs no `getpid`
(which has no agnos peer): `link`/`symlink` are atomic create-if-absent, so a taken name simply
answers EEXIST and the next one is tried.

### Fixed — an unset `PATH` made `xargs` and `find -exec` run a binary from the current directory

⛔ **`env -u PATH xargs ls` executed an attacker-supplied `./ls`.** `execve` does no path search: a
slash-free name is resolved by the **kernel** against the current directory. Both "PATH is unset" and
"searched PATH and found nothing" ended in `execve("ls")`.

An unset PATH now falls back to `/bin:/usr/bin` — the value glibc's `execvp` takes from
`confstr(_CS_PATH)` — and a failed search returns *not found* rather than a bare name, reported as
POSIX exit 127. An empty PATH is left alone: POSIX defines a zero-length prefix as the current
directory, so `PATH=` legitimately means `.` — but it is now resolved explicitly, through the same
access/stat check as any other entry.

⭐ **`xargs` and `find` were carrying byte-identical 45-line copies of the resolver**, so this hole
had to be found and fixed twice. Both now call one `fs_resolve_in_path` in `src/lib/fs.cyr`.

### Fixed — `find -exec` leaked adjacent heap into the child's argv

⛔ **The `{}` rebuild buffer was `tlen + plen * 4`** — a silent assumption of at most four
occurrences in one token. A fifth ran the loop past the allocation:
`find t -name f -exec echo '{}-{}-{}-{}-{}' \;` emitted four copies of the path, a truncated fifth,
and then bytes from the **adjacent heap object** (kriya's own cached PATH string), which went into
the argument handed to `execve`. A heap disclosure straight into a child process, plus corruption of
kriya's own state.

Occurrences are now counted and the size is **exact** — `tlen + count * (plen - 2)`, which stays
correct when `plen < 2` and the result is shorter than the token. Byte-identical to GNU from 1 to 20
occurrences.

### Fixed — `realpath` silently answered the wrong path past 16 KiB

⛔ **A 16,427-byte operand made `kriya realpath -m` print `…/rp/d/.d` where GNU printed `…/rp/d/f`,
and exit 0.** Not a crash — a wrong canonical path reported as success, which is worse, because
`realpath` / `readlink -f` output is normally fed straight into the next command. `fs_realpath`'s
append path had always been bounds-checked, which made the whole function look guarded, while the
seed copied `input` straight from argv into a fixed 16 KiB buffer with no check at all. The
symlink-rebuild path had the same gap, where `tl + rest_len` can approach twice the buffer.

All three copies are now checked and answer `ENAMETOOLONG`. ⚠ kriya therefore **refuses** inputs GNU
still resolves; making the buffers growable is roadmap **M17j**. An honest refusal beats a wrong
answer.

### Fixed — the ADR-0004 root guard failed open when it could not canonicalize

⛔ **A cwd over 4,095 bytes makes `getcwd` fail**, and `protected_canonicalize` then handed back the
*relative* operand, which failed to string-match `/` and let `rm` proceed — the refusal failed open
exactly when it could not do its job. It now fails **closed**: `fs_path_absolute` returns an absolute
path in every success case, so a relative result can only mean the fallback fired, and the operand is
refused (exit 2).

⚠ With the `/`-only table this was near-theoretical — an operand can only resolve to `/` if it ends
in `.` or `..`, which the new `rm` check already refuses. It stops being theoretical the moment the
table grows, and **ADR 0004 explicitly invites maintainers to add `/etc`, `/usr`, `/boot` without a
successor ADR**. `../../etc` from a deep cwd has no dot final component.

### Changed — one shared `fs_path_absolute`, and `path.cyr` keeps its purity

`protected_canonicalize`'s body moved to `fs_path_absolute` in `src/lib/fs.cyr` when `cp`'s new guard
turned out to need the same absolute-and-textually-normalized frame. ⚠ It lives in `fs.cyr` rather
than next to `path_normalize` because it calls `getcwd`, and `path.cyr`'s header commits to "pure
string operations: nothing here touches the filesystem" — a boundary worth more than the convenience.
Writing it into `path.cyr` first also introduced a `path.cyr` → `sys.cyr` dependency that
`tests/kriya.tcyr` does not satisfy, and it **built green anyway** because cyrius only rejects
*reachable* undefined functions. That trap is now [M15e](docs/development/roadmap.md).

### Added — tests, and the roadmap organisation the sweep earned

**137 in-process assertions** (119 unit + 18 POSIX, up from 104) and **1,081 smoke cases across 32
scripts** (up from 1,012 across 31). New coverage:

- **The ADR-0004 root guard is now pinned by 21 unit assertions** — every spelling of `/` a shell can
  produce (`//`, `/.`, `/..`, `/home/../`, `//..//`, `.` through a missing directory) plus the
  names that must **not** be refused. ⚠ There is no safe way to test this end-to-end: exercising it
  through `rm` means running `rm` against `/` and finding out. The predicate is the test surface and
  it carries the whole weight.
- `fs_path_absolute` and `path_is_under` boundary assertions — the latter because `cp`'s guard rides
  on it and a prefix-without-boundary match would make `cp` refuse legitimate copies (`/var` vs
  `/variable`).
- `scripts/smoke-write-errors.sh` — 29 new cases over `/dev/full`, skipping honestly where it is
  unavailable, plus the SIGPIPE regression guard.
- Refusal and non-refusal cases for `rm` dot-operands, `ln -f`, `cp -r` into itself, `find -exec`
  multi-`{}`, and the `xargs` CWD-execution hole.

Roadmap reorganised: **M15** is a new standing codegen/toolchain-interaction watchlist (each entry
with a mechanical detection and the incident that motivated it), **M17** holds the sweep's deferred
defects, and **M16** is the AGNOS-build-target bucket **renumbered from M11**, which collided with
the Cyrius proposal sweeps and sat above M10 in the reading order.

### Not a problem — three findings refuted, recorded so they are not re-litigated

- **`rm -r symlink-to-dir/` follows the link.** It does, and it empties the target — but **GNU does
  exactly the same**. The claim that GNU refuses was wrong. It remains a divergence from kriya's own
  ADR-0003 stance and is tracked as **M17i**, as a policy question rather than a regression.
- **`cp -f` deletes a pre-existing destination when the copy fails.** Not reproducible: under
  `ulimit -f`, kriya and GNU both leave the same 512-byte partial destination.
- **`cp -R A/. A` zeroes every file.** Real before this release; the copy-into-itself guard above
  closes it, with `A/.` refused exactly as GNU refuses it.

## [1.1.10] - 2026-08-25 — toolchain pin 6.5.35; the allocator that finally reuses registers

Toolchain pin moved **6.5.18 → 6.5.35** (`lib sync --full`, 108 stdlib files) — 17 upstream releases.
No kriya source change was required. CI action pins refreshed in the same pass.

### Changed — cyrius pin 6.5.18 → 6.5.35

**Almost nothing kriya consumes actually moved.** Of the 22 declared `[deps].stdlib` modules, 19 are
byte-identical between the two snapshots — including the whole `unicode/` subtree and every
`syscalls*` file on kriya's targets (`syscalls`, `syscalls_x86_64_linux`, `syscalls_x86_64_agnos`,
`syscalls_linux_common`). **Zero functions were removed, renamed, or re-signatured** anywhere in the
closure. The three that differ:

- **`fmt.cyr`** — a `fmt_float_buf` fractional-carry fix (6.5.30): the carry out of a rounded fraction
  was computed *after* the integer part had already been written, so `3 - 1e-7` printed `2.1000000`.
  Unreachable from kriya — there is not one `f64_*` or `fmt_float*` call site in the tree, because
  `printf` ships every conversion **except** `%e`/`%f`/`%g`. It does clear a hazard under that
  deferred work: implementing `%f` against the old pin would have inherited the bug.
- **`niyama.cyr`** — 1.0.6 → 1.0.7. The bundled-distribution version comment, and nothing else; the
  regex engine `grep` and `find` run on is byte-identical.
- **`process.cyr`** — an inert `#host_only` marker (6.5.24) that fails a `CYRIUS_KERNEL=1` bare-metal
  build early instead of faulting at runtime. `#` opens a comment in cyrius, so it is dead text on
  every kriya target; confirmed by the `--agnos` build, which includes `process.cyr` for
  `xargs`/`find -exec` and compiles clean.

⭐ **The one thing in this window that can move emitted code is the register allocator.** 6.5.35 fixed
two defects that had jointly prevented linear-scan from ever reusing a register — live intervals were
force-extended to function end so expire never fired, and the `picked` cap was a hard limit of 5. Frame
layout is therefore repacked tree-wide. **This is a larger instance of exactly the change class that
exposed kriya's year-old `find` stack smash at the previous bump** (`var ctx[4]` holding 32 bytes;
40/40 → 8/40). That is why the verification below is wider than a pin bump normally warrants — not
because anything was expected to break.

⚠ **If a utility ever misbehaves after an allocator-line bump, rebuild with
`CYRIUS_REGALLOC_PICKER_CAP=5` to reproduce the pre-6.5.35 register assignment.** If the symptom
disappears, the defect is a latent frame/buffer bug in kriya (the `find.cyr` class), not a compiler
regression. Recorded here because the next allocator release poses the same question.

**Re-measured, not assumed.** `src/cmd/find.cyr:912` records that the function-local `var X[N]`-is-N-
*bytes* rule (the ×8 u64 unit applies only at module scope) was **measured** at 6.5.18 with a
two-local probe, precisely because the rule is non-uniform enough not to trust across a codegen bump.
Re-taken at 6.5.35: `|&b - &a|` = **8 / 32 / 144** for `var x[4]` / `var x[32]` / `var x[144]`. The
rule holds unchanged. A repo-wide re-scan for the same shape — a function-local buffer written past
its declared byte length — is clean; the three candidates it surfaces (`printf.cyr:197 alt_buf[4]`,
`ls.cyr:274 buf[20]`, `ls.cyr:470 ws[8]`) are all byte- or 16-bit accesses that fit, `ws[8]` being an
exact-size `struct winsize`.

**Verified green at the new pin:** host + `--agnos` builds; **86** unit + **18** POSIX-blessed
assertions; **1529** fuzz assertions (1127 grep + 201 find + 201 printf) — *also* green under 6.5.29's
new `cyrius fuzz --poison` (freelist redzones, `0xA5` fill, quarantine-on-free), which is a strictly
stronger signal than the plain run because out-of-bounds *reads* land in mapped memory and never
fault; **31/31** smoke scripts, **1012** cases, cell-by-cell against GNU; `lint` 0 warnings; `vet`
46 deps / 0 untrusted / 0 missing. The CI recipe was re-run end-to-end from a clean `git archive`
checkout with no `lib/` present, since `./lib/` is gitignored and CI re-vendors via `cyrius deps`.

Cold-start is flat. Measured as an **interleaved A/B** of the two snapshots' binaries on the same box
rather than against a months-old figure: 6.5.35 median **1.185 ms** vs 6.5.18's 1.210 ms, and
**1.218 ms** vs 1.236 ms with the arm order swapped (150 pairs each; ~25 µs of second-slot position
bias, and 6.5.35 wins in both slots). Against v1.0.0's 1.196 ms that is flat. Host binary 931,000 →
935,096 bytes (+4,096, one page).

⚠ **`cyrius lib sync` cannot resolve kriya's `unicode/*` entries in declared-only mode** — it reports
them as "not found in the snapshot" even though `<pin>/lib/unicode/*.cyr` exist. `lib sync --full` and
`cyrius deps` both handle them correctly, and CI uses `cyrius deps`, so nothing is broken; use
`--full` when re-vendoring by hand. The `unicode/*` entries are load-bearing — dropping them fails the
build with 3 reachable undefined functions, pulled in transitively by niyama.

### Changed — CI action pins to current majors

`actions/checkout@v4` → **`@v7`** (both workflows) and `softprops/action-gh-release@v2` → **`@v3`**.
Both majors are Node 20 → Node 24 runtime moves with no input-schema change; `ubuntu-latest` is far
past checkout v7's v2.327.1 minimum runner. v7 additionally refuses to check out fork PRs for
`pull_request_target` / `workflow_run` — kriya triggers on `push`, `pull_request`, `workflow_call` and
tag push, so none of its jobs are in range. Matches vidya, the first-party repo already on these pins.

⚠ These pins are the one part of this release that **cannot be verified locally**. Everything else was
run on this machine.

### Unchanged — both standing Cyrius proposals stay open

Grepping the whole 6.5.19–6.5.35 span for `octal` / `0o` / `openat` / `unlinkat` / `fstatat` /
`mkdirat` / `renameat` returns nothing, and every `syscalls*` file on kriya's targets is byte-identical
across the two snapshots. So: no `0o755` sweep of the decimal POSIX-mode constants, and no `*at()`-family
stdlib wrappers to migrate kriya's raw `syscall(N, …)` sites onto. Both remain follow-ups.

## [1.1.9] - 2026-08-11 — symlinks on agnos; the stack smash cyrius 6.5 uncovered

Toolchain pin moved **6.4.20 → 6.5.18** (`lib sync --full`), which is what surfaced the `find` bug below.

### Added — `ln -s` and `readlink` work on agnos

`K_HAVE_SYMLINK` and the new `K_HAVE_READLINK` are both 1 on the agnos arm. The flags were stale, not
blocked: agnos shipped `symlink`#63 and `readlink`#70 some time ago and kriya kept refusing the verbs.

⛔ **A bare capability-flag flip would have been a serious bug, and the reason is worth keeping.** The
old agnos arms carried dead `syscall(88, …)` / `syscall(89, …)` bodies behind an `#ifdef` — the Linux
numbers. On agnos **88 is `gpu_fill_rect` and 89 is `gpu_caps`**, so an un-gate that merely set the
flag to 1 would have made `ln -s` paint a rectangle and `readlink` return framebuffer geometry. Both
arms now go through the named `SYS_SYMLINK` / `SYS_READLINK`, which resolve per-target. agnos also
takes explicit **lengths** (4-arg, a4 in r10) where Linux takes NUL-terminated pointers.

⚠ **`readlink` is now the only no-follow primitive on agnos.** There is no `lstat`, and path-based
`sys_stat`#33 follows the final component, so kriya's `k_lstat` follows symlinks on that target. The
one shape this gets wrong is telling a symlink-to-directory apart from a directory
(`_ln_is_real_dir`); plain `ln -s a b` does not touch it. agnos carries `lstat` as unslotted pending a
consumer — this is that consumer.

### Fixed — `find` walked one level and stopped (a 32-byte write into a 4-byte local)

`_f_walk` built a 4-field context with `var ctx[4]` and then wrote **32 bytes** into it. A
function-local `var X[N]` is **N bytes** — the ×8 u64 unit applies only at module scope — so this
smashed 24 bytes of neighbouring stack.

⭐ **It was silent for a year and the pin bump is what exposed it.** The old register allocator left
dead space where the overflow landed. cyrius 6.5.x is the codegen-quality line; it repacked the frame,
the clobber started hitting live state — specifically the `st_buf` whose `st_mode` the is-a-directory
test reads — and `find` went from **40/40 to 8/40**, printing the root and never descending.

⚠ The unit rule is non-uniform enough to be worth **measuring** rather than assuming. Measured here at
6.5.18 with a two-local probe: `&b - &a` = 8 for `var x[4]`. A repo-wide scan for the same shape
(small local + 64-bit stores past its end) found this as the only true instance.

### Fixed — `df PATH` printed a header and no rows unless PATH was itself a mount point

`df` matched operands against mountpoints by **exact string equality**, so `df /` worked and
`df /home` produced nothing whenever `/home` was not separately mounted. The file header documented
the correct behaviour and the loop carried a `# TODO: proper "filesystem containing operand path"
match` — the doc was the honest one, and the TODO had been open since v0.7.0.

Operands now resolve by **longest mountpoint prefix**, which is what the kernel's own lookup resolves
to: with `/` and `/home` both mounted, `/home/x` belongs to `/home`, not `/`. Matching breaks on a
component boundary, so `/var` does not cover `/variable`. Verified byte-identical to GNU `df` on `/`,
`/home`, a deep path, and `/dev`.

Naming a path is an unambiguous request for that filesystem, so an operand now bypasses both the
pseudo-FS filter and the zero-blocks drop (`df /dev` used to print an empty table). A nonexistent
operand reports `No such file or directory` and, when no operand resolves, suppresses the header
rather than printing a bare one that reads as "empty filesystem".

### Fixed — the `wc -m` UTF-8 test asserted the wrong thing

`smoke-wc.sh` compared kriya against GNU `wc -m` with no locale set, where GNU silently degrades to
counting **bytes**. kriya decodes UTF-8 unconditionally and has no locale to degrade to, so it
answered 12 for an 11-character-plus-newline string and GNU answered 14 — and the suite blamed kriya.
The oracle now names `LC_ALL=C.UTF-8`. **No kriya code changed; the test was wrong.**

Suite at this cut: **86 unit assertions + 31/31 smoke scripts green** on the host arm.

⚠ The agnos arm builds clean but `ln -s` / `readlink` are **not** verified on agnos by anything above
— host smokes cannot reach that arm by construction. They are carried on the next agnos burn card.

## [1.1.8] - 2026-08-07 — kriya survives a pipe (agnos ipc bite 11)

### Fixed — 542 raw writes ignored short writes, silently dropping data

⛔ **EVERY APPLET WROTE WITH A RAW `syscall(1, …)` AND NEVER LOOKED AT THE RESULT.** agnos 1.56.40's
`pipe_write` refuses to overwrite unread bytes, so a producer faster than its consumer gets back FEWER
bytes than it offered — the POSIX contract. Measured: `grep . /etc/ssl/cert.pem | wc` delivered
**70347 of 185311 bytes**, and the missing 62% looked exactly like a plausible answer.

All 542 sites across 38 files now route through `k_write`, which loops until the whole buffer is
accepted. ⛔ Its stall bound is **not a timeout on success** — every accepted byte resets it, so a
merely-slow consumer never trips it however long it takes. It fires only when the ring stays full with
no progress at all (a reader that died or stopped reading), where the alternative is spinning forever,
since a pipe has no reader-gone signal to test.

### Fixed — `k_read` treated WOULD_BLOCK as EOF

⛔ Callers branch on `n <= 0`, so without a retry a `wc`/`grep`/`tee` reading from a **concurrent**
producer stopped the first moment it out-ran the writer and reported a truncated result. -2 means "not
yet"; 0 means EOF. One chokepoint covers every applet.

⭐ The loop needs no timeout: the kernel returns 0 the instant the last write end closes, which is
exactly what Linux's blocking `read()` does in the same situation.

⛔ Both waits are preemptible spins, never `sleep_ms#41` — that is `preempt_disable; sti; hlt` and
would starve the very peer being waited on.

Result: **185191 bytes / 3112 lines byte-exact against the host's own `grep | wc`**, through a
4080-byte pipe.

⚠ **Pre-existing, untouched by this release:** `cyrius fmt` drift in 12 files and `line exceeds 120
characters` lint warnings in 13, all in code this change did not modify (the drifting blocks contain no
`k_write`, and the long lines are function signatures — the substitution makes lines *shorter*). kriya's
CI gates neither, which is consistent with how long they have been there. Left alone deliberately:
reformatting 12 files inside a release cut would bury the change that matters in unrelated diff.

## [Unreleased]

### Changed

- **`scripts/fuzz.sh` now drives the harnesses through `cyrius fuzz --poison` instead of `cyrius test`.**
  Only the `fuzz` verb injects `CYRIUS_POISON=1` as a compile-time predefine, which enables the freelist
  allocator's redzones, `0xA5` fill, and quarantine-on-free; `cyrius test` does not. Without poison, an
  out-of-bounds **read** lands in mapped memory and never faults — so every `fuzz: no crashes` line the
  script printed was silent about exactly the failure class the harnesses exist to catch. That is the
  whole point of `kriya-grep.fcyr` (the niyama BRE/RE2 engine) and `kriya-printf.fcyr` (kriya's own
  format engine): both are parser surfaces where a read one byte past a bracket class or a conversion
  spec is the realistic bug, not a write. Per-harness output shape is unchanged, plus a
  `poison mode: ... ACTIVE` line per block so a run that quietly lost poison is visible rather than
  inferred. **Raises the script's toolchain floor to cyrius >= 6.5.29**, the release that added the flag;
  older toolchains reject `--poison` outright rather than fuzzing unpoisoned. Noted in the script header.
  Green at pin 6.5.35: **1529** assertions (1127 grep + 201 find + 201 printf), 3 passed / 0 failed.

## [1.1.7] — 2026-07-10 — GNU-style multi-column `ls`

### Added
- **`ls` default output is now GNU-style multi-column** (`src/cmd/ls.cyr`). Entries pack
  column-major (fill down, then across) sized to the terminal — layout byte-identical to
  `ls -C` (only the inter-column gutter differs: spaces vs GNU's tabs). Terminal width comes
  from `ioctl(TIOCGWINSZ)` on Linux (only when stdout is a tty) and the `winsize()` #60 syscall
  on agnos (the console FB grid, as `kii`/`chakshu` use), with `$COLUMNS` and a new `-w`/`--width
  COLS` flag as overrides, falling back to 80. **Off a tty with no width hint it stays
  one-per-line** — script-safe, matching GNU `ls` piped. `-1` now *forces* one-per-line (it was a
  documented no-op when one-per-line was the default). `-l` long form is unchanged (already emits
  size + mtime). New `-w`/`--width` flag.

## [1.1.6] — 2026-07-08

### Fixed

- **agnos build was broken — `duplicate variable` aborted `cyrius build --agnos`.**
  `_gr_process_fd` in `src/cmd/grep.cyr` declared its one-byte line-terminator
  scratch buffer (`var tb[2]; store8(&tb, term_byte);`) separately at all five grep
  emit sites (list / only-match / default / count / list-nomatch). Cyrius hoists a
  branch-local `var` up to the nearest enclosing loop/function scope, so the two
  copies in the same `if/elif/else` chain collided and the compiler aborted with
  `error:src/cmd/grep.cyr:696: duplicate variable`. Since `term_byte` is a constant
  parameter, the buffer is now filled once in the function's top var-block and reused
  at every site — zero behavior change. Unblocks kriya in the agnosticos agnos-dev
  docker image (`docker/build-dev.sh`), which had been skipping it; agnsh's file-verb
  builtins (`cp`/`mv`/`rm`/`ls`/`grep`/…) delegate to kriya. Host + behavior
  unchanged; grep emit paths verified on the agnos artifact under `mirshi`.

### Changed

- **cyrius pin 6.2.24 → 6.4.20 + re-vendored `lib/`.** Aligns the manifest pin
  (`cyrius.cyml [package].cyrius`) to the installed toolchain — the wrapper had
  advanced to 6.4.20 while the pin stayed at 6.2.24 (drift). Host + agnos builds
  compile clean against 6.4.20 (no pin-drift or shadow-lib warnings); 86/86 unit +
  18/18 POSIX assertions pass.

## [1.1.5] — 2026-06-19

### Changed

- **cyrius pin 6.1.39 → 6.2.24 + re-vendored `lib/`.** Aligns the manifest pin
  (`cyrius.cyml [package].cyrius`) to the installed toolchain — the wrapper had
  advanced to 6.2.24 while the pin stayed at 6.1.39 (drift). `cyrius lib sync`
  re-vendored the stdlib snapshot (98 `.cyr` files) to the new pin. Host build +
  behavior unchanged: dispatcher compiles clean, 86/86 unit + 18/18 POSIX
  assertions pass, `lint`/`vet` green (0 warnings, 0 untrusted deps).

## [1.1.4] — 2026-06-14

### Fixed

- **agnos: EVERY applet hung on launch — stale cyrius pin (6.1.14) miscompiled the
  dispatcher binary.** On AGNOS (iron and QEMU) `echo`/`ls`/`mkdir`/`kriya true` —
  all of them — hung the moment they were exec'd from `agnsh`, looping in the first
  `strlen` of `main()` (on the pointer `path_basename_ptr(argv(0))` returns). The
  kernel loaded the 934 KB ELF and entered ring 3 correctly (verified with
  `execwait #37` markers — identical to a working `bnrmr`); the hang was a **codegen
  miscompile** inside kriya, not a logic/kernel/exec bug. It was **size-gated**: the
  same toolchain (cycc 6.2.2) + same pin built a working `bnrmr` (167 KB) but a
  hanging kriya (934 KB, the largest agnos `/bin` tool); doom (589 KB) escaped it by
  riding cyrius 6.1.37. The deciding variable was the stdlib pin — a clean re-vendor
  at **6.1.14 hangs, at 6.1.39 works**. **cyrius pin 6.1.14 → 6.1.39** + re-vendored
  `lib/`. Verified in QEMU (`agnos/scripts/agnsh-delegation-test.py` PASS:
  `echo`/`mkdir`/`cp`/`ls`/`owl` all green; new repro harness
  `agnos/scripts/kriya-crash-probe.py`). The underlying compiler bug is already fixed
  upstream (≥ 6.1.37), so this is a consumer re-pin, not a cyrius-side action. Host
  build + behavior unchanged. Surfaced kriya's M10 consumer-burn signal; details in
  [`docs/development/issue/2026-06-14-bin-applets-crash-on-agnos-iron.md`](docs/development/issue/2026-06-14-bin-applets-crash-on-agnos-iron.md).

## [1.1.3] — 2026-06-13

### Fixed

- **agnos: bare `ls` (no operand) failed.** `cmd_ls` passed the literal `"."` to
  `_ls_list_dir` when given no path argument. The AGNOS VFS hard-requires absolute
  paths (rejects any path whose first byte isn't `/`), so `"."` opened nothing and
  `ls` returned `EXIT_FAILURE` with no output. Now resolves the no-operand case via
  `k_getcwd` first (returns `"/"` on agnos, the real cwd on Linux — both absolute),
  falling back to `"."` only if `getcwd` fails. Surfaced on AGNOS iron burn 3
  (2026-06-13): the QEMU delegation smoke only ever exercised `ls /` (absolute arg),
  so the relative-path default never tripped. Host behavior unchanged. Independent of
  the agnos-kernel keyboard fix shipped the same day.

## [1.1.2] — 2026-06-09

### Fixed

- **agnos: `ls` / `find` / `du` (any vec/heap-using applet) wedged on AGNOS.** The
  vendored `lib/fnptr.cyr` (cyrius pin 6.0.56) carried no `CYRIUS_TARGET_AGNOS` fncall
  branch, so `alloc_via` — the allocator vtable, dispatched through `fncallN` —
  returned 0 on agnos. `vec_new`/`vec_push` then produced null-backed vecs, and `ls`
  infinite-looped on its first `vec_push`. **cyrius pin 6.0.56 → 6.1.14** (ships the
  native agnos fncall branch) + re-vendored `lib/`. Surfaced by AGNOS's
  `agnsh-delegation-test.py` (the 1.44.x agnsh→kriya coreutils-delegation cycle); same
  class as the agnoshi 1.4.9 fnptr fix. Host build + behavior unchanged.

## [1.1.1] — 2026-06-09

### Added

- **AGNOS target support — kriya now builds `--agnos` and its verbs run on the
  sovereign OS** (the M10 consumer-burn substrate; folds into agnoshi next). A new
  portable syscall layer `src/lib/sys.cyr` (`k_*` wrappers + `K_HAVE_*` capability
  flags) routes every syscall per-target: agnos numbers differ from Linux
  (`read`=#5 not #0, `close`=#6 not #3, `open`=#7), paths are length-counted, and
  `k_open` translates Linux open-flags to agnos `AO_*` bits. `k_stat`/`k_lstat`/
  `k_getdents` translate agnos's native 48-byte `stat` / packed dirents into the
  canonical Linux 144-byte `stat` / `linux_dirent64` so `fs.cyr` and every caller
  read one layout unchanged. `fs.cyr`'s `*at` family routes `AT_FDCWD` to
  path-based syscalls and returns `-ENOSYS` for dirfd-relative calls (agnos has no
  `*at`/cwd/symlinks); `fs_stat_entry` stats directory entries by absolute path on
  agnos so `ls -l`/`du` show real metadata. Verbs needing absent primitives
  (`df`→statfs, `ln -s`/`readlink`→symlinks) refuse cleanly via the `K_HAVE_*`
  gates. Host behavior is unchanged (the Linux branch of every wrapper matches the
  prior raw syscall, verified by smoke). Entry point uses a bare top-level call so
  `argv` is captured on agnos.

### Fixed

- **Undersized `stat` buffers** — `grep`/`find`/`xargs` declared `var st[36]`
  (36 *bytes* under the Cyrius function-local-array contract) for a 144-byte `stat`
  write — a latent stack overflow on Linux too. Corrected to `var st[144]`.

## [1.0.0] — 2026-05-18

**v1.0 freeze.** Closes **M9**. Tag `1.0.0`.

kriya at 1.0.0 ships **38 POSIX-style utilities** plus the dispatcher, **eight ADRs** capturing every cross-cutting design choice, two **independent audits** (POSIX compliance + security), **per-utility benchmarks** vs GNU, and **fuzz harnesses** for the three parser-style utilities (`grep`, `find`, `printf`). Cold-start median **1.196 ms** (RUNS=100) — under 60% of the 2 ms v1.0 budget.

### Added (M9 deliverables)

- **`tests/kriya-grep.fcyr`** — niyama regex parser fuzz (1127 assertions over 3000+ random patterns: BRE compile, RE2 compile, bracket-class heavy patterns). Deterministic xorshift seed; replayable.
- **`tests/kriya-find.fcyr`** — find predicate AST fuzz via fork+exec (201 assertions over 200 random argv combinations from find's lexicon).
- **`tests/kriya-printf.fcyr`** — printf format engine fuzz via fork+exec (201 assertions over 200 random format strings + arg permutations).
- **`scripts/fuzz.sh`** — convenience runner for all three harnesses.

### v1.0 criteria — final status

- [x] **Core utility set across M1–M6 ships, each with happy + error-path tests + at least one fuzz harness for parser-style utilities (`grep`, `find`, `printf`).** All 38 utilities. 644 smoke cases. 1529 fuzz assertions across the three parser-style harnesses.
- [x] **POSIX compliance documented per utility (deviations get ADRs)** — M7 audit at `docs/audit/2026-05-18-posix-compliance.md`. 32 of 38 POSIX-defined; 6 intentional scope extensions under ADR 0006.
- [x] **Each destructive utility covered by TOCTOU + symlink-safety test** — smoke-cp-recursive (39), smoke-mv (51), smoke-rm (53); M8 mitigations added F1/F4/F5 NOFOLLOW protections.
- [x] **Dispatcher overhead under 2 ms** — v1.0.0 median 1.196 ms (60% of budget; flat across M2–M9).
- [ ] **One downstream consumer green** — moved to post-1.0 as **M10 (Consumer-burn)** in [roadmap.md](docs/development/roadmap.md). Trigger sequence: AGNOS USB-keyboard-on-boot resolves → AGNOS coreutils integration → first green boot-burn → 1.0.1 release with the consumer-burn audit. The kriya side is ready; this is a parallel signal on the kernel team's timeline.
- [x] **CHANGELOG complete from v0.1.0 onward** — every milestone (M0–M9) has a versioned entry.
- [x] **Security audit pass** — M8 audit at `docs/audit/2026-05-18-security.md`. External CVE/0-day cross-walk against the uutils-coreutils audit (41 CVEs); 34 N/A or already-mitigated, 3 patched in M8, 2 documented as POSIX-conformant.
- [x] **Benchmarks captured** in `docs/benchmarks.md` — cold-start history + per-utility throughput vs GNU + named optimization follow-ups.

**7 of 8 criteria met; the 8th is a parallel signal awaiting external consumer.**

### Test totals at 1.0.0

- **104 in-process assertions** across `tests/kriya.tcyr` (86 unit) + `tests/kriya-posix.tcyr` (18 POSIX-blessed).
- **1529 fuzz assertions** across `kriya-grep.fcyr` + `kriya-find.fcyr` + `kriya-printf.fcyr`.
- **644 smoke cases** across 27 utility-area shell scripts.

Post-1.0 work — boot-burn signal, GNU-parity features, Cyrius sweep cycles, perf optimizations — is sequenced in [`docs/development/roadmap.md`](docs/development/roadmap.md) under Post-1.0 milestones (M10–M14). Each item is one PR against a tagged 1.x.y minor.

## [0.9.0] — 2026-05-18

**Closes M8** — security audit + per-utility benchmarks. Two deliverables under the new convention `docs/audit/<date>-<type>.md`:

1. **`docs/audit/2026-05-18-security.md`** — security audit including external CVE / 0-day research. Primary input: the Canonical-commissioned uutils-coreutils audit (CVE-2026-35338 through CVE-2026-35381) which disclosed 41 CVEs against the exact surface kriya occupies. Cross-walked every CVE to kriya: 34 N/A or already-mitigated, 3 newly exposed and patched in this milestone (**F1/F4/F5**), 2 documented as POSIX-conformant (**F2/F6**). No critical or untracked issues. Findings traced to ADR-0003 / 0004 / 0005 where applicable.
2. **`docs/benchmarks.md`** — per-utility throughput vs GNU (3-run median wall clock) across the full M1-M6 surface. Includes cold-start history table and named optimization follow-ups for the visible gaps (`wc -c` short-circuit, niyama literal Boyer-Moore, `tail` seek-from-end, speculative `find` predicate JIT and `cp` `copy_file_range`).

Cold-start median **1.201ms** (RUNS=100; flat from v0.8.0's 1.201ms — no behavior changes outside the three NOFOLLOW mitigations, which don't touch the dispatcher hot path).

### Added

- **Security audit** at `docs/audit/2026-05-18-security.md` — full path-traversal / TOCTOU / signal-handling / symlink-follow / destructive-op review with the external uutils CVE cross-walk.
- **Per-utility benchmarks** at `docs/benchmarks.md` — kriya vs GNU throughput across `wc`, `grep`, `sort`, `find`, `cp`, `head`, `tail` plus the cold-start history table.
- **`scripts/bench-throughput.sh`** — deterministic-corpus throughput benchmark generator; runs at each release boundary.

### Mitigated (M8 security findings)

- **F1 / CVE-2026-35359-class** — `cp -R` recursive source open lacked `O_NOFOLLOW`. `_cp_file_at` now takes a `follow` parameter; under POLICY_P/H in-walk, source open uses `O_NOFOLLOW`. Closes the TOCTOU window where a regular-file entry could be swapped for a symlink between `lstat`-classify and `openat`. (`src/cmd/cp.cyr` — 39/39 cp-recursive smoke cases pass after fix.)
- **F4 — `find -empty` TOCTOU** — `_f_eval_empty_predicate` now conditionally adds `O_NOFOLLOW` based on `_f_follow_mode`. Mirrors the canonical pattern at the main descent site. (`src/cmd/find.cyr` — 40/40 find smoke cases pass.)
- **F5 — `grep -r` TOCTOU** — recursive file open now uses `O_NOFOLLOW` flag. On `ELOOP` the swapped symlink is reported and skipped rather than read through. (`src/cmd/grep.cyr` — 66/66 grep smoke cases pass.)

### Documented (security findings — POSIX-conformant, no change)

- **F2** — `cp -f` non-recursive destination follows symlinks. POSIX behavior; matches GNU `cp`. Scripts running as root must validate destinations.
- **F6** — non-recursive `grep` on file operands follows symlinks. POSIX behavior; matches GNU `grep`. User-passed paths are trusted.
- **SUID safety** — kriya is NOT designed to be installed SUID. If made SUID, F2/F6/similar POSIX-follow paths become privilege-escalation primitives. Future `docs/guides/deployment-suid.md` will cover this; install kriya as a non-SUID symlink farm.

### v1.0 criteria checked off this milestone

- [x] **Security audit pass** — `docs/audit/2026-05-18-security.md` with external CVE/0-day research.
- [x] **Benchmarks captured** in `docs/benchmarks.md` — cold-start history + per-utility throughput vs GNU.
- [x] **Each destructive utility covered by TOCTOU + symlink-safety test** — smoke-cp-recursive (39), smoke-mv (51), smoke-rm (53) all exercise the ADR-0003 / 0004 paths; M8 mitigations added test-validated NOFOLLOW behavior.

After v0.9.0, **6 of 8 v1.0 criteria are checked**. Remaining: per-utility fuzz harnesses for parser-style utilities (grep, find, printf) and one downstream consumer green (the AGNOS kernel boot burn-in signal).

## [0.8.0] — 2026-05-18

**Closes M7** — POSIX.1-2017 compliance audit. No new utilities; this is the audit-and-document milestone. Three deliverables:

1. **`docs/audit/2026-05-18-posix-compliance.md`** — every shipped utility walked against POSIX.1-2017 with deviation cataloging. 32 of 38 utilities are POSIX-defined; 6 are intentional kriya-scope extensions (`yes`, `seq`, `stat`, `realpath`, `readlink`, `which`). No utility quietly diverges from POSIX for any flag it ships — every gap is either *missing* (deferred behind a named follow-up) or *added* (BSD/GNU extension shipped intentionally).
2. **Three new ADRs** for cross-cutting policy that previously lived in scattered file headers:
   - **ADR 0006** — Utility scope: which six non-POSIX utilities ship and the four-criteria gate for any future addition.
   - **ADR 0007** — `date` defaults to UTC at v0.7.0; local-time tzfile parsing is the named follow-up.
   - **ADR 0008** — POSIX exit-code policy: `EXIT_SUCCESS`/`EXIT_FAILURE`/`EXIT_USAGE` three-tier baseline with POSIX-named overrides (grep no-match=1, xargs 123/124/125/126/127, env 126/127).
3. **`tests/kriya-posix.tcyr`** — POSIX-blessed assertion harness running under `cyrius test`. Fork+execve+pipe-capture helper plus 18 starter cases per pillar utility (`true`/`false`/`echo`/`pwd`/`wc`/`grep`/`cp`/`ls`/`seq`/`env`/`date`/`find`/`xargs`). Population is incremental; this is the scaffold.

Cold-start re-bench (RUNS=100): median **1.201ms** — flat as expected, no new dispatcher entries. 86 unit assertions + 18 POSIX-blessed = 104 in-process test cases; 644 smoke cases across 27 utility-area shell scripts.

### Added

- POSIX.1-2017 compliance audit at `docs/audit/2026-05-18-posix-compliance.md`.
- ADR 0006 — Utility scope: six non-POSIX utilities ship in kriya.
- ADR 0007 — `date` defaults to UTC at v0.7.0; local-time follow-up named.
- ADR 0008 — POSIX exit-code policy: three-tier convention + per-utility specifics.
- `tests/kriya-posix.tcyr` — POSIX-blessed assertion harness (18 starter cases).

## [0.7.0] — 2026-05-18

**Closes M6** — five system-info/misc utilities (`seq`, `env`, `date`, `du`, `df`). M6 ships ahead of the AGNOS kernel boot-burn signal at user direction (same shape as the M5 mid-hold resume) — kriya runs in parallel with kernel work, on kernel's timeline. **168 behavioural smoke cases across the five M6 utilities** (44 seq + 28 env + 44 date + 37 du + 15 df), every flag and shape compared cell-by-cell against GNU coreutils where applicable. Cyrius pin bumped to **5.11.61**. Cold-start re-bench (RUNS=100): median **1.212ms** — still well under the 2ms v1.0 target despite 5 new dispatcher entries.

After v0.7.0 the kriya surface covers every POSIX-essential utility in M1–M6: filesystem ops, listing/path manipulation, text-stream filters, search/filter, system info. **38 shipped utilities** total. The remaining v1.0 work is M7 POSIX-compliance audit, M8 security audit + per-utility benchmarks, M9 freeze + tag.

Includes the cross-FS directory `mv` fix shipped earlier in this cycle (the only remaining M2 follow-up — `_cp_recursive_one` POLICY_P + `_rm_dir_at` with best-effort dest-tree rollback).

### Added

- **Cross-filesystem directory `mv`** — `mv srcdir dstdir` across filesystems (rename(2) returns EXDEV) now falls back to `_cp_recursive_one` with POLICY_P (preserve symlinks per ADR 0003; preserve mode + timestamps) followed by `_rm_dir_at` to drain the source tree. Closes the only outstanding M2 follow-up, unblocked since `rm -r`'s tree-walk shipped at v0.3.0. On either step's failure the destination tree is best-effort rolled back so the user doesn't end up with two authoritative copies — matches the regular-file rollback semantic that already existed for `mv`'s cross-FS file path. `src/main.cyr` include order is now `cp → rm → mv` so mv.cyr can call `_rm_dir_at` (rm.cyr has no cp/mv dependencies, verified). Smoke `scripts/smoke-mv.sh` gains 8 cross-FS dir cases — **51/51** mv smoke cases now pass (up from 43/43).

- **`du`** (`src/cmd/du.cyr`) — POSIX `du(1)`, fourth M6 utility. Flags: `-s`/`--summarize`, `-a`/`--all`, `-c`/`--total`, `-h`/`--human-readable`, `-k` (no-op, default), `-b`/`--bytes` (apparent size), `-L`/`--dereference`, `-P`/`--no-dereference` (default), `-d N`/`--max-depth=N`, `-S`/`--separate-dirs`. **Default block size 1024 bytes** (matches GNU without POSIXLY_CORRECT); st_blocks (512-byte units) divided by 2 with ceiling-round. `-b` reports `st_size` in raw bytes and skips directories' own st_size from the subtree total (apparent-size dir semantic — matches GNU). `-h` picks smallest 1024^N unit (K/M/G/T) with 1-decimal precision under 10 (`5.0M`, `200K`) and integer above (`12M`). Recursive walk reuses the `fs_getdents64` pattern from rm/cp/find; ADR 0003 default is `-P` lstat-only, `-L` switches to stat-with-follow at every level. `-a` and `-s` are mutually exclusive (matches GNU). Missing-file path exit code is 1 per GNU. **Hardlink dedup NOT IMPLEMENTED at v0.7.0** — same inode under multiple names is counted multiple times; documented in the file header as a follow-up against the future inode-set helper that `cp --preserve=links` also needs. `-x` (one-filesystem), `--exclude`/`--exclude-from`, `--inodes`, `-0` NUL output, and POSIXLY_CORRECT 512-byte default are deferred. Smoke `scripts/smoke-du.sh` — **37/37** cell-by-cell against GNU `du`: default + `-s` + `-a` + `-h` (incl. 5 MiB binary) + `-b` + `-c` (multi-operand grand total) + `-d 0/1/2` + `-S` + ADR-0003 `-P`/`-L` symlink-to-dir matrix + long-form options + default-to-`.` + exit codes (0/1/2).
- **`date`** (`src/cmd/date.cyr`) — POSIX `date(1)`, third M6 utility. `+FORMAT` with 28 strftime specifiers: `%Y`/`%y` year, `%m`/`%d`/`%e` date, `%H`/`%I`/`%M`/`%S` time, `%p`/`%P` AM/PM, `%j` day-of-year, `%u`/`%w` weekday, `%a`/`%A` weekday name, `%b`/`%h`/`%B` month name, `%Z`/`%z` timezone, `%s` epoch seconds, `%N` (nanosecond stub — kriya samples `clock_epoch_secs`, not ns), `%T`/`%R`/`%D`/`%F` composite forms, `%n`/`%t`/`%%` escapes, GNU `%_d` pad form. Unknown specifier emits source `%X` verbatim (matches GNU forgiveness). Default format `%a %b %e %H:%M:%S %Z %Y`. **UTC-only at v0.7.0**: `-u`/`--utc`/`--universal` accepted as no-ops (the deviation from GNU's local-time default is documented in the file header — local-time-aware operation defers to a `/etc/localtime` tzfile-parsing follow-up; UTC is the floor that requires no external state). Smoke `scripts/smoke-date.sh` — **44/44** cell-by-cell against GNU `date` under `LC_ALL=C TZ=UTC` (every shipped specifier × default format × composites × escapes × `%s` epoch parity within 1s × `%N` stubbed zeros × unknown-specifier passthrough × exit codes).
- **`env`** (`src/cmd/env.cyr`) — POSIX `env(1)`, second M6 utility. Flags: `-i`/`-`/`--ignore-environment` (start with empty env; `-` alone is the POSIX synonym), `-u NAME`/`--unset NAME`/`--unset=NAME` (repeatable), `-0`/`--null` (NUL-terminated print when no command), `--` (end-of-options; assignments still scanned until first non-assignment). `NAME=VALUE` operands apply in token order; `-u` and assignments interleave freely (matches GNU env): `-u FOO FOO=x` keeps FOO=x, `FOO=x -u FOO` drops it. With a command, PATH-resolves argv[0] (slash-bypass) and **calls `sys_execve` directly** — env(1) REPLACES itself with the target, no fork. Exec failure: exit 127 on ENOENT/ENOTDIR, 126 otherwise — matches GNU. Without a command, prints the (possibly modified) env to stdout. Smoke `scripts/smoke-env.sh` — **28/28** cell-by-cell against GNU `env`: `-i` empty-then-set, `-u` after inherited or after own set, multi-`-u`+assignment interleave, long/`=`-form options, `-0` NUL-sep print via `od -c` byte parity, absolute vs PATH-resolved commands, clustered `-iu`, exit-code matrix (0/1/2/126/127).
- **`seq`** (`src/cmd/seq.cyr`) — first M6 utility (GNU/BSD; not in POSIX). Shapes `seq LAST` / `seq FIRST LAST` / `seq FIRST INCR LAST`. Flags: `-s`/`--separator` (default newline; trailing newline always emitted after final number — matches GNU), `-w`/`--equal-width` (zero-pad to max text-len of FIRST and LAST; sign byte counted; pad lands after sign so `-007` not `00-7`). `-f`/`--format` rejected at exit 2 with a pointer at the deferred printf `%e`/`%f`/`%g` follow-up — integer-only at v0.7.0. Negative-FIRST UX (`seq -3 3`) handled by in-utility argv walk that bypasses the stdlib parser for this utility: `-DIGIT` is positional, not a short option. Supports `--`, `--separator=VAL`, `-sVAL` attached short value, `-s ""` falls back to newline. Empty output when incr-direction disagrees with bounds is exit 0 (matches GNU). Smoke `scripts/smoke-seq.sh` — **44/44** cell-by-cell against GNU `seq` (every shape × every flag × directions × edge cases × the error matrix).
- **Cross-filesystem directory `mv`** — `mv srcdir dstdir` across filesystems (rename(2) returns EXDEV) now falls back to `_cp_recursive_one` with POLICY_P (preserve symlinks per ADR 0003; preserve mode + timestamps) followed by `_rm_dir_at` to drain the source tree. Closes the only outstanding M2 follow-up, now unblocked since `rm -r`'s tree-walk shipped at v0.3.0. On either step's failure the destination tree is best-effort rolled back so the user doesn't end up with two authoritative copies — matches the regular-file rollback semantic that already existed for `mv`'s cross-FS file path. `src/main.cyr` include order is now `cp → rm → mv` so mv.cyr can call `_rm_dir_at` (rm.cyr has no cp/mv dependencies, verified). Smoke `scripts/smoke-mv.sh` gains 8 cross-FS dir cases (round-trip with nested files, nested dirs, preserved symlinks, preserved subdir mode; rollback on cp-failure when destination is a non-dir). **51/51** mv smoke cases now pass (up from 43/43). cp 26/26, cp-R 39/39, rm 53/53 unchanged — confirms the include reorder is harmless.

## [0.6.0] — 2026-05-17

**Closes M5** — three filtering/search utilities (`grep`, `find`, `xargs`) on top of one new shared dependency surface: Cyrius stdlib's `niyama` (regex via ADR 0005), `process` (fork+execve for `-exec`), and the `unicode/*` modules niyama pulls in transitively. **126 behavioural smoke cases across the three M5 utilities** (66 grep + 40 find + 20 xargs), every one compared cell-by-cell against the GNU equivalent. Cyrius pin bumped to **5.11.59**. Cold-start re-bench (RUNS=100, post-find-and-xargs): median **1.192ms** — still flat against v0.5.0's 1.198ms; the three new dispatcher table entries land after `true`'s hot path and contribute essentially nothing.

After v0.6.0 the kriya surface covers every POSIX-essential text/search/filter utility a shell needs to bootstrap. **Next**: AGNOS kernel boot-burn (the M5 hold rationale carried forward through this milestone — `find` and `xargs` were authorised pre-burn because the user signalled to keep moving). The boot-burn is still the gate before M6 (`df`, `du`, `date`, `env`, `seq`) starts.

### Added

- **ADR 0005** — Regex engine choice: Cyrius stdlib `lib/niyama.cyr` (BRE + RE2). PCRE deferred behind a v2.0 flag gate; no external regex deps. `grep -G`/default → `niyama_bre_*`; `grep -E` → `niyama_re2_*`; `grep -F` → in-tree byte scan. `-i` handled per-engine (byte-fold for BRE/F, `(?i)` inline prefix for RE2). ASCII-only at v1.0. Hard rules: no engine env var, no silent engine fallback, no `-P` (rejected with usage error). See `docs/adr/0005-regex-engine-niyama.md`.
- **`grep`** (`src/cmd/grep.cyr`) — POSIX `grep(1)`, first M5 utility. Flags: `-i`/`-v`/`-w`/`-x`/`-c`/`-l`/`-L`/`-n`/`-q`/`-s`/`-h`/`-H`/`-o`/`-r`/`-R`/`-z`/`-E`/`-G`/`-F`/`-e PATTERN`/`-f FILE`. Pattern sources: positional[0] (when no `-e`/`-f`), single `-e PATTERN`, and `-f FILE` (one pattern per line — full multi-pattern path). Engine dispatched per ADR 0005. Streaming 64 KiB line buffer with bounded RAM. Recursive walk (`-r`/`-R`) uses `getdents64` via `src/lib/fs.cyr`, never follows symlinks (ADR 0003), skips non-regular non-directory entries. Filename header rule: on by default for 2+ operands or `-r`; `-h` forces off, `-H` forces on. Exit codes: `0` any match, `1` no match, `2` usage or filesystem error (suppressed to `1` under `-s`). `-P` is rejected with a usage error pointing at `-E` per ADR 0005. Smoke `scripts/smoke-grep.sh` — **66/66** every flag and engine combo compared cell-by-cell against GNU `grep` (literal + bracket + star + dot + escaped-group BRE patterns, ERE `+`/`{n,m}`/group/alternation, `-F` literal-regex-char, `-i` across all three engines, `-v`, `-c`, `-n`, `-l`/`-L` multi-file, `-w` word boundary, `-x` whole-line, `-o` only-matching with multi-match per line, `-h`/`-H`, `-s` suppress missing-file, multi-file headers, stdin via pipe and via `-` operand, `-e`/`-f` patterns, `-z` NUL-separated I/O, `-r` recursive). Niyama bench points added to `tests/kriya.bcyr`: `niyama/bre_search_literal` ~5µs/call and `niyama/re2_search_class` ~5µs/call against a 43-byte line. End-to-end on 10k-line input: kriya grep ~80ms vs GNU grep ~1ms — GNU's Boyer-Moore literal-scan fast path is ~80× faster than the Pike NFA we share with niyama; literal-pattern optimization is a follow-up against niyama, not a kriya hack. Cold-start re-bench (RUNS=100): median **1.210ms** (essentially flat from v0.5.0's 1.198ms — grep's `streq` lands after `true`'s hot path).
- **Cyrius pin → 5.11.59** (was 5.11.54). `cyrius lib sync` now needed before build to populate `lib/unicode/*` for niyama's NFD path (the `cyrius lib sync` creates the directory but doesn't recurse files — manual copy from `~/.cyrius/versions/5.11.59/lib/unicode/` until the lib-sync fix lands upstream).

- **`find`** (`src/cmd/find.cyr`) — POSIX `find(1)`, second M5 utility. Predicates: `-name` (fnmatch-style glob: `*`, `?`, `[abc]`, `[a-z]`, `[!...]`, `\X` escape), `-type` (`f`/`d`/`l`/`s`/`p`/`b`/`c`), `-size [+-]N[cbkMG]` (default 512-byte block units with GNU's round-up-to-next-block on exact match; `c` raw bytes), `-mtime [+-]N` (24h windows), `-mmin [+-]N`, `-empty` (zero-size regular file or no-entry directory), `-newer REF` (mtime newer than REF), `-maxdepth N` (prune descent), `-mindepth N` (skip shallow emits). Actions: `-print` (default when no other action shipped), `-print0` (NUL-terminated for `xargs -0`), `-exec CMD... \;` (fork + execve + waitpid; `{}` substituted as a free-standing argv token or as a substring inside any token). Operators: `!` / `-not`, `-a` / `-and` (implicit between juxtaposed predicates), `-o` / `-or`, `(` / `)` grouping. Symlink policy per ADR 0003: default `-P` (no follow); `-L` follows everywhere (operands + descent + per-entry stat); `-H` (operand-only follow) deferred. Recursive-descent parser builds a small AST (32-byte nodes) keyed by `FindNode` enum; per-entry evaluation short-circuits AND/OR. Tree walk via `fs_getdents64` reuses the grep `-r` pattern. `-exec` env: parent env is read once from `/proc/self/environ` into a vec and passed to `exec_env`; PATH is also cached at startup (the stdlib `getenv` returns empty on every call after the first fork+exec+waitpid in this build — root-caused but not fixed upstream yet; cache sidesteps it). `-exec` PATH-resolves argv[0] in-process before execve since execve itself doesn't search PATH. Smoke `scripts/smoke-find.sh` — **40/40** cell-by-cell against GNU `find`: default print, `-type` matrix, `-name` glob (literal, `*`, `?`, bracket-class, no-match), `-size` exact/`+`/`-`/default-block, `-empty`, `-newer`, `-mtime ±N`, `-maxdepth 0/1/2`, `-mindepth`, AND (implicit + explicit), `-o`, `!`/`-not`, parens, `-print`/`-print0`/`-exec` (with `echo` and `wc -l`), `-L` symlink follow, multi-start-path, exit codes (unknown predicate `2`, bad `-size` `2`, missing `-exec ;` `2`, missing start path `1`, `-H` deferred `2`).

- **`xargs`** (`src/cmd/xargs.cyr`) — POSIX `xargs(1)`, M5 closer. Reads stdin into items, batches them onto a command's argv, exec's. Flags: `-0`/`--null` (NUL-separated input, pairs with `find -print0`), `-n N`/`--max-args=N` (items per exec), `-I REPLSTR`/`--replace` (one exec per item; REPLSTR in any CMD-arg substring is replaced — `-I {}` is the common idiom), `-r`/`--no-run-if-empty` (modern GNU default; we always skip the exec on empty input), `-t`/`--verbose` (trace each command to stderr before running), `-s N`/`--max-chars=N` (argv byte cap, default 128 KiB). Default command is `/bin/echo` when no CMD is given. Item splitting in default (whitespace) mode honors POSIX backslash + single/double-quote rules; in `-0` mode items are NUL-delimited with no escape handling. PATH-resolves argv[0] in-process before execve (same path as find — see the post-fork-getenv caching note). Exit-code rollup follows GNU: `0` all-succeeded, `123` any child non-zero, `124` child exited `255`, `127` fork/exec error. Smoke `scripts/smoke-xargs.sh` — **20/20** cell-by-cell against GNU `xargs`: default echo / explicit CMD, `-n 1`/`-n 2`/`-n 3` batching, `-0` NUL items, `-I {}` replacement with multi-substitution, `-r` empty-stdin guard, quoting (single/double/backslash), `-t` trace, `123` exit on child failure, PATH-resolved commands.

## [0.5.0] — 2026-05-17

**Closes M4** — ten text-stream utilities (`tee`, `wc`, `head`, `tail` incl. follow mode, `nl`, `uniq`, `tr`, `cut`, `sort`, `printf`), the biggest milestone by count. Each utility verified cell-by-cell against GNU coreutils where applicable. The new utilities share a common shape: streaming line buffers (64 KiB chunks, bounded RAM), terminator-aware (`-z` NUL-separated mode where it makes sense), stdin-via-`-` operand convention, partial-failure-preserves-output exit semantics. Highlights:

- `tail -f` adds the first poll-loop utility in kriya (200ms `sys_stat` cadence on a single file; truncation detection on size shrink); SIGINT exits via the kernel default per arch note 002.
- `sort` is a **stable bottom-up iterative merge sort** O(n log n) with 16-byte line records pointing into one 256 MiB-capped input buffer; comparator applies `-b`/`-f`/`-k`/`-t`/`-n` transformations on raw bytes without materialising keys.
- `tr` parses the **full POSIX set grammar** (literals, ranges, all 12 character classes, octal `\NNN`, named escapes); produces both an ordered byte sequence for translate-mode positional pairing and a 256-byte presence table for delete/squeeze/complement.
- `printf` ships **every POSIX conversion except floating-point** (`%d`/`%i`/`%u`/`%o`/`%x`/`%X`/`%c`/`%s`/`%b`/`%%`), full flag matrix (`-`/`+`/space/`#`/`0`), width and precision with `*`, arg reuse when args exceed format specs, and format-string escape handling.

**710 behavioural smoke cases pass across all 23 shipped utilities** (M2+M3+M4: mkdir 24 + rmdir 24 + touch 26 + ln 30 + cp 26 + cp-recursive 39 + mv 43 + rm 53 + basename-dirname 26 + realpath 30 + readlink 24 + which 23 + stat 37 + ls 36 + tee 20 + wc 23 + head-tail 42 + nl 23 + uniq 27 + tr 32 + cut 31 + sort 23 + printf 48); 86/86 unit assertions still green. Cold-start median **1.198ms** (RUNS=30; essentially flat from v0.4.0's 1.208ms despite 10 new dispatcher entries — the `true` hot-path resolves before any new entries).

After M4, kriya covers most of the GNU coreutils text-processing surface a shell needs. **Next milestone: M5** (filtering / search) — `grep`, `find`, `xargs`. M5 introduces the regex story (Cyrius's `lib/niyama.cyr` enters the dependency surface) and the tree-walk-with-execute pattern.

### Added

- **`tee`** (`src/cmd/tee.cyr`) — POSIX `tee(1)`, M4 opener. Reads stdin in 64 KiB chunks, writes each chunk to stdout and every successfully-opened output file. Flags: `-a`/`--append` (O_APPEND instead of O_TRUNC). Per-file open failure is reported but doesn't halt the others; per-file write failure drops that fd from the rotation while remaining outputs continue. Loop terminates early only when ALL outputs have failed. EINTR retried; partial writes looped. Exit `EXIT_FAILURE` if any output failed at open or write time. Deferred: `-i`/`--ignore-interrupts` (needs the signal-handler infrastructure flagged in arch note 002 — not yet installed since no M2 utility needed it), `--output-error=...` (GNU pipe-failure-mode knob). Smoke `scripts/smoke-tee.sh` — 20/20 covering single-file, multi-file fan-out, default-truncate vs `-a`, no-operand pass-through, 200 KiB + 5 MiB fidelity (exercises multi-iteration read/write loop), binary-NUL fidelity, resilient partial-failure (readonly file blocked but sibling outputs still get data), directory operand cleanly fails.
- **`wc`** (`src/cmd/wc.cyr`) — POSIX `wc(1)`. Streaming counter: reads in 64 KiB chunks; one pass tracks lines (newline count), words (whitespace-transition count), bytes (raw count), chars (UTF-8 codepoints — `(byte & 0xC0) != 0x80` per byte), and `-L` max-line-length. Flags: `-l`/`-w`/`-c`/`-m`/`-L`; default = `-l -w -c` (POSIX). Multi-file mode emits a per-file row plus a `total` line. **Column-width matches GNU's quirky three-rule layout**: single-file + single-flag → bare value (no padding); otherwise → width = max digit count across ALL counter fields (including bytes when `-c` isn't set), so dropping `-c` doesn't make columns shrink. Word detection treats any byte `≤ 0x20` as whitespace (matches GNU's effective definition). Bounded RAM regardless of input size. Smoke `scripts/smoke-wc.sh` — 23/23, every case compared cell-by-cell against GNU `wc` including empty file, no-trailing-newline, UTF-8 multi-byte, 200 KiB input, 1000-line file, multi-file total, stdin, partial failure.
- **`head`** + **`tail`** (`src/cmd/head.cyr`, `src/cmd/tail.cyr`) — POSIX `head(1)` / `tail(1)`. Shared shape: `-n N` (default 10 lines), `-c N` (bytes), `-q` / `-v` for `==> FILE <==` header control (auto when 2+ operands), `-` operand reads stdin, multi-operand partial-failure exits `EXIT_FAILURE` but preserves successful output. **`head`** streams forward (64 KiB reads) and stops at the line/byte limit — bounded RAM. **`tail`** buffers the input (up to a 16 MiB cap with stderr warning when exceeded) then back-walks to find the start of the last N lines. The line-search walks backwards from `size-1`; the loop's pre-decrement naturally skips a trailing newline at the EOF position, so a separate skip-trailing branch is unneeded — getting that wrong cost a smoke-cycle's worth of debugging on the first cut. Deferred (each named): GNU `-n -N` / `-c -N` "all but last", `-n +N` / `-c +N` "start-from", `tail -f` follow mode (needs inotify or stat-loop), `tail -F` / `--pid=PID`, `k`/`M`/`G` suffixes on counts (extract a shared byte-suffix parser when `head` + `tail` + `dd` all want it), seek-from-end fast path for huge seekable files (avoids the 16 MiB cap). Smoke `scripts/smoke-head-tail.sh` — 38/38 every case compared cell-by-cell against GNU.
- **`nl`** (`src/cmd/nl.cyr`) — POSIX `nl(1)`, single-section model. Flags: `-b a|t|n` body type (default `t` = number non-empty only), `-i N` increment, `-n ln|rn|rz` number format (left / right unpadded / right zero-padded; default `rn`), `-s SEP` separator (default TAB), `-v N` starting number, `-w N` column width (default 6). Multi-file mode uses continuous numbering (matches GNU). **Load-bearing GNU quirk** discovered + tested: unnumbered lines are padded by `width + sep_len` spaces (not `width` spaces, not 0 spaces) so the line-content column stays aligned regardless of separator length. Streaming line buffer (64 KiB per line cap, stderr warning on truncation; bump when a consumer needs more). Deferred: section delimiters via `-d` with `-h` header / `-f` footer (the `\:\:\:` / `\:\:` / `\:` triple-colon markers), `-b p REGEX` (needs `lib/niyama.cyr` regex), `-l N` empty-line collapse, `-p` (no reset across sections). Smoke `scripts/smoke-nl.sh` — 23/23 every flag combo compared cell-by-cell against GNU, including the unnumbered-padding rule with 1-byte, 2-byte, and 3-byte separators.
- **`uniq`** (`src/cmd/uniq.cyr`) — POSIX `uniq(1)`: filter adjacent matching lines. Flags: `-c` count prefix (GNU's 7-char right-justified format), `-d` repeated-only, `-u` unique-only, `-i` ASCII case-fold, `-f N` skip blank-separated fields before compare, `-s N` skip chars after `-f`, `-w N` cap compare length, `-z` NUL-separated input + output. Positional shape: `uniq [INPUT [OUTPUT]]` — `INPUT` defaults to stdin, `OUTPUT` defaults to stdout; both file operands open via `sys_open`. **Adjacent-only semantics are POSIX** (pipe `sort | uniq` for global dedup). Comparison-key vs output: `-f`/`-s`/`-w`/`-i` only decide equality; the original line is always what gets emitted. Two bugs caught: GNU's count column is 7 chars (not 4); a leftover broken-first-pass loop in `_uq_key_window` infinite-looped on `-f N` (the dead code was left behind after restructuring; the Edit tool's anchor matched a fragment, not the whole block — explicit re-edit deleted it). Deferred: `--all-repeated[=METHOD]`, `--group[=METHOD]`, multi-byte case fold. Smoke `scripts/smoke-uniq.sh` — 27/27 every shipped flag cell-by-cell against GNU including 2-operand input/output mode, NUL-separated I/O via `-z`, comparison-key permutations.
- **`tr`** (`src/cmd/tr.cyr`) — POSIX `tr(1)`: translate, delete, squeeze characters. Modes selected by flag combination: `tr SET1 SET2` translate, `-d` delete, `-s` squeeze, `-c` complement of SET1, `-t` truncate SET1 to len(SET2), `-d -s SET1 SET2` combined (delete SET1, squeeze SET2). **Full POSIX set grammar**: literals; ranges `a-z`; backslash escapes `\\` `\a` `\b` `\f` `\n` `\r` `\t` `\v`; octal `\NNN` (1-3 digits); character classes `[:alpha:]`/`[:alnum:]`/`[:digit:]`/`[:lower:]`/`[:upper:]`/`[:space:]`/`[:blank:]`/`[:punct:]`/`[:print:]`/`[:graph:]`/`[:cntrl:]`/`[:xdigit:]` (ASCII tables). SET2 padding to SET1 length uses SET2's last char (matches GNU; POSIX leaves this undefined). Set parser produces both an ORDERED expansion (for translate-mode positional pairing) and a 256-byte presence table (for delete/squeeze/complement). Operation pipeline: `delete?` → `translate?` → `squeeze?` per byte, with `prev_byte` tracking for run-collapse. Streaming via 64 KiB buffer; bounded RAM regardless of input size. Deferred: `[=c=]` equivalence classes (locale-dependent), `[c*N]` repetition (handy for explicit SET2 padding), locale-aware case folding. Smoke `scripts/smoke-tr.sh` — 32/32 every shipped feature compared cell-by-cell against GNU `tr`, including rot13, every POSIX character class, octal + named escapes, complement+delete, and the combined `-d -s` mode.
- **`cut`** (`src/cmd/cut.cyr`) — POSIX `cut(1)`: extract sections from each line. Modes (exactly one required): `-b LIST` bytes, `-c LIST` chars (ASCII-only at M4; behaves identically to `-b` for now — full multi-byte awareness defers on a UTF-8 decoder), `-f LIST` fields. Flags: `-d DELIM` single-byte field delimiter (default TAB), `-s` only-delimited (skip lines without delim, `-f` only), `--complement` invert LIST, `--output-delimiter=STR` (default = input delimiter), `-z` NUL-separated lines. **LIST grammar fully supported**: `N` single, `N-` open-ended, `-M` 1..M, `N-M` range, comma-separated, all 1-indexed and inclusive. Ranges parsed into a vec of `(lo, hi)` records once; per-line position check iterates the vec (small constant for typical LIST sizes). Streaming line buffer (64 KiB cap, stderr warning on truncation). Multi-file mode concatenates outputs (matches GNU). Smoke `scripts/smoke-cut.sh` — 31/31 every mode and every LIST grammar form compared cell-by-cell against GNU `cut`, including `--complement`, `--output-delimiter`, the `-s` no-delim line behaviour, and the usage-error matrix.
- **`tail -f`** (`src/cmd/tail.cyr`) — follow mode added to the existing `tail`. After the initial last-N output, polls the file every 200 ms via `sys_stat`; emits newly-appended bytes from the open fd (which still sits at the previous EOF after `_tail_slurp`'s read). When the file size shrinks, emits `kriya tail: <name>: file truncated` to stderr and `lseek(fd, 0, SEEK_SET)` so the rewritten content shows up on the next read. SIGINT exits via the kernel default (exit 130) per arch note 002 — no handler installed. **Single-file `-f` only at first ship**; multi-file `-f` exits with a clear usage error pointing at the limitation, since GNU's per-file-header-switching behaviour wants its own pass. Stdin `-f` is silently downgraded to non-follow (pipes have no stat-able path). Same-size full-rewrite is NOT detected as truncation (caught during smoke + documented). Smoke `scripts/smoke-head-tail.sh` grows to 42/42 with 4 new follow-mode cases (append visibility, truncation warning + new content, multi-file rejection).
- **`printf`** (`src/cmd/printf.cyr`) — POSIX `printf(1)`, M4 closer. Conversions `%d` / `%i` / `%u` / `%o` / `%x` / `%X` / `%c` / `%s` / `%b` (escape-processed string) / `%%`. Flags `-` / `+` / space / `#` / `0`. Width and precision both literal and from `*` (consume next arg as integer). **Format-string escapes always honored** (`\n`/`\t`/`\\`/etc., plus octal `\NNN`). **Arg reuse**: when args exceed format specifiers, FORMAT is reapplied from the start until args are exhausted (POSIX); when args are short, missing values default to `0` / `""`. Argument integer-parsing supports decimal, `0x` hex, `0` octal, and POSIX `'X` / `"X` character-constant forms. Deferred: floating-point conversions `%e` / `%E` / `%f` / `%F` / `%g` / `%G` / `%a` / `%A` (Cyrius's float-printing story not yet settled — `%d` and `%s` cover the vast majority of script usage), hex escape `\xHH`, positional args `%N$s`. Smoke `scripts/smoke-printf.sh` — 48/48 every shipped conversion + flag + escape sequence compared cell-by-cell against `/usr/bin/printf`. Lesson: kriya's strict-flag-parser per ADR 0002 requires `--` to terminate option processing before a `-N` numeric arg can be passed — documented as the standard POSIX convention.
- **`sort`** (`src/cmd/sort.cyr`) — POSIX `sort(1)` line sort, in-memory at first ship. Flags: `-n` numeric, `-r` reverse, `-u` unique-after-sort, `-f` ASCII case-fold, `-b` ignore leading blanks, `-t SEP` single-byte field delimiter, `-k F` single-field key (POSIX-style — whitespace-delimited unless `-t`), `-c` check-only mode (verify sorted; exit 1 + line-number diagnostic on first disorder), `-o FILE` output redirect (open with `O_WRONLY|O_CREAT|O_TRUNC`), `-z` NUL-separated lines, `-s` stable (default; merge sort is stable by construction). **Algorithm**: input slurped into one 256 MiB-capped buffer, lines tokenized into 16-byte records (offset + length pointing into the buffer), stable bottom-up iterative merge sort O(n log n) on a pair of record-pointer arrays. Comparator applies `-b`/`-f`/`-k`/`-t`/`-n` transformations on the raw line bytes without materialising key copies. Tiebreak rule: numeric-equal keys fall back to lex compare (matches GNU); key-equal lines fall back to full-line lex. Memory cap: 256 MiB; overflow warns and truncates. Deferred (each a named follow-up): `-h` (human-numeric K/M/G), `-V` (version), `-g` (general-numeric scientific), `-M` (month), `-R` (random), `-m` (merge), `-d`/`-i` (dictionary/ignore-nonprinting), multi-key `-k F1 -k F2 ...`, end-field key range `-k F1,F2`, external-sort fallback for inputs > 256 MiB. Smoke `scripts/smoke-sort.sh` — 23/23 every shipped flag compared cell-by-cell against GNU `LC_ALL=C sort`, including `-c` check mode, `-o` output redirect, `-z` NUL I/O, stable on equal keys, 1000-line numeric input, multi-file concat.

## [0.4.0] — 2026-05-17

Closes M3 — seven listing + path-manipulation utilities (`basename`, `dirname`, `realpath`, `readlink`, `which`, `stat`, `ls`) on top of M2's filesystem foundation. New shared canonicalization helper `fs_realpath` in `src/lib/fs.cyr` (3 modes: `REQUIRE_ALL` / `REQUIRE_PARENT` / `ALLOW_MISSING`) backs both `realpath` and `readlink -f`/`-e`/`-m`. `ls -l` mtime renders via `chrono.epoch_to_date` (the stdlib helper discovered mid-M3 — let us promote ISO-formatted human-readable mtime instead of raw epoch). **441 behavioural smoke cases pass across the 14 M2+M3 utilities** (mkdir 24 + rmdir 24 + touch 26 + ln 30 + cp 26 + cp-recursive 39 + mv 43 + rm 53 + basename-dirname 26 + realpath 30 + readlink 24 + which 23 + stat 37 + ls 36); 86/86 unit assertions remain green. Cold-start at v0.4.0: median **1.208ms** (RUNS=30; ~50µs slower than v0.3.0's 1.159ms — 7 new dispatcher table entries + larger text segment; still well under the 2ms v1.0 target).

After M3, the kriya surface covers every POSIX-essential path/listing tool a shell needs to bootstrap. Next milestone is M4 (text-stream utilities — `wc`, `head`, `tail`, `cut`, `tr`, `tee`, `sort`, `uniq`, `nl`, `printf` — 10 utilities, the largest milestone by count). Cross-FS directory `mv` (the one outstanding M2 follow-up) is also unblocked now that `rm -r`'s tree-walk exists.

### Added

- **`basename`** (`src/cmd/basename.cyr`) — POSIX `basename(1)`. Single-pair shape `basename PATH [SUFFIX]` strips the directory and an optional trailing suffix; suffix is only applied when at least one byte remains after the strip (POSIX). GNU `-a`/`--multiple` accepts multiple paths and emits one per line; `-s SUFFIX`/`--suffix=SUFFIX` implies `-a`. `-z`/`--zero` switches the line terminator from `\n` to `\0` for `find -print0` pipelines. Pure text — no filesystem access.
- **`dirname`** (`src/cmd/dirname.cyr`) — POSIX `dirname(1)`. Accepts one or more paths (GNU/BSD extension; POSIX is strict-one) and emits the directory component of each on its own line. `-z`/`--zero` for NUL termination. Pure text — wraps `path_dirname` from `src/lib/path.cyr`.
- **`realpath`** (`src/cmd/realpath.cyr`) — GNU `realpath(1)`. Walks each operand component-by-component, resolving symlinks and collapsing `.`/`..`/duplicate slashes to a canonical absolute form. Default `-e`/`--canonicalize-existing`: every component must exist (ENOENT → exit 1). `-m`/`--canonicalize-missing`: components may be missing — once an ENOENT is hit, the rest is appended textually (so `realpath -m a/b/nope/../also` correctly yields `…/a/b/also`). `-q`/`--quiet` suppresses error messages (exit code still reflects failure). `-z`/`--zero` for NUL termination. Cycle / pathologically-deep symlink chain returns ELOOP (40-hop cap). Deferred: `-s`/`--no-symlinks`, `--relative-to`, `--relative-base`, explicit `-L`/`-P` ordering.
- **`fs_realpath`** in `src/lib/fs.cyr` — shared canonicalization helper for `realpath` and `readlink -f`/`-e`/`-m`. Three modes (`FS_REALPATH_REQUIRE_ALL` / `_REQUIRE_PARENT` / `_ALLOW_MISSING`) cover all the GNU `realpath`/`readlink` flag combinations. Component walk uses `fs_lstat_at` + `fs_readlinkat` per ADR-0003 hard rule #4; absolute targets reset the result root, relative targets are prepended to the work queue. Returns length on success, `-errno` on failure (`-ENOENT`, `-ENAMETOOLONG`, `-ELOOP` plus propagated lstat/readlink/getcwd errors). Internal helper `_fs_strip_last_component` operates in-place on the result buffer for `..` handling.
- **`readlink`** (`src/cmd/readlink.cyr`) — POSIX `readlink(1)`. Default mode is POSIX raw read-link via `sys_readlink` (prints the symlink's target text; errors EINVAL on non-symlink operand). Canonicalize flags `-f` (`REQUIRE_PARENT`), `-e` (`REQUIRE_ALL`), `-m` (`ALLOW_MISSING`) delegate to `fs_realpath` from the realpath commit. Precedence on mixed flags: `-m` > `-e` > `-f` (GNU last-wins). Display modifiers `-n`/`--no-newline` (suppress newline of final operand only — others still separated), `-z`/`--zero` (NUL terminator, overrides `-n`). `-q`/`--quiet` suppresses error messages. Multi-operand each on own line; partial-failure preserves successful outputs and exits `EXIT_FAILURE`.
- **`which`** (`src/cmd/which.cyr`) — `$PATH` executable search. For each PROGRAM, walks `getenv("PATH")` colon-separated entries (empty entries mean cwd per POSIX), uses `sys_stat` + `fs_is_reg` + `sys_access(X_OK)` to test executability (follows symlinks — what the shell sees). Operands containing `/` bypass `$PATH` and are tested as literal paths. Flags: `-a`/`--all` (print every match in PATH order, useful for shadowing diagnosis), `-s`/`--silent` (no output; exit code only), `-z`/`--zero` (NUL terminator). Exit `EXIT_SUCCESS` only when every operand was found at least once. Deferred: `--read-alias` / `--read-functions` / `--show-dot` / `--show-tilde` / `--skip-tilde` — those are shell-state introspection concerns outside kriya's scope (agnoshi will own the shell-builtin form).
- **`stat`** (`src/cmd/stat.cyr`) — file metadata dump with a printf-style format engine. Default lstat (operand-as-given); `-L`/`--dereference` to follow symlinks. Formats: default multi-line layout, `-c FORMAT` (auto-newline appended), `--printf=FORMAT` (`\n`/`\t`/`\r`/`\\`/`\0` escapes interpreted, no auto-newline), `-t`/`--terse` (16-column space-separated, GNU column order including the `%W` slot we render as `0` since `stat(2)` has no birth time). Specifiers: `%n %s %a %A %f %F %u %g %i %h %d %D %t %T %b %B %o %X %Y %Z %W %%`. Unknown specifiers (`%q`, etc.) emit `%X` literally — matches GNU. Deferred (each named): `%U`/`%G` (need passwd/group parsing), `%x`/`%y`/`%z` (need `lib/chrono.cyr` formatter), `%N` (quoting + symlink target rendering), real `%W` birth time (needs `statx(2)`). Render helpers `_st_render_dec` / `_st_render_oct` / `_st_render_hex` are stat-internal; cross-utility integer renderers stay deferred until a second consumer asks. `src/lib/fs.cyr`'s `FsStat` enum extended with `FS_STAT_RDEV` / `_BLKSIZE` / `_BLOCKS` / `_CTIME` / `_CTIME_NSEC`.
- **`ls`** (`src/cmd/ls.cyr`) — directory listing. Default form: one entry per line, alphabetical, hidden files filtered. Flags: `-a` (include `.`/`..`/dotfiles), `-A` (almost-all — dotfiles but not `.`/`..`), `-l` (long form: symbolic mode, nlink, uid, gid, size, `YYYY-MM-DD HH:MM` mtime via `chrono.epoch_to_date`, name with ` -> target` for symlinks), `-h` (human-readable size suffixes B/K/M/G/T/P with GNU "smart rounding" — one decimal place when result < 10, integer otherwise), `-r` (reverse sort), `-1` (one-per-line; accepted for ergonomics, default behaviour), `-F` (type suffix: `/` dir, `@` symlink, `*` executable, `|` fifo, `=` socket), `-i` (inode column), `-d` (list directory operands as entries themselves), `-R` (recursive descent, never through symlinks — matches GNU default). Per-entry record carries name + 144-byte stat + cached readlink target. Insertion-sort by name (case-sensitive; case-insensitive collation deferred). Two-pass long-form rendering computes per-column widths (nlink, uid, gid, size, inode) for right-justified alignment. Multi-operand layout: non-directory operands print first as a flat sorted list, then each directory as a `path:` section. Deferred (each a named follow-up): multi-column packing on tty stdout (needs `TIOCGWINSZ`), `-t`/`-S` alternate sort keys, `-n` numeric-uid-gid (currently the default), `--color`, human-readable mtime "May 17 13:36" style (chrono lib gives us ISO; deviation noted), `%U`/`%G` name lookup. Cross-utility rendering helpers (`_ls_render_dec`/`_oct`/`_symperm`) duplicate the stat-internal versions; extraction into `src/lib/fmt.cyr` ships when a third consumer asks.
- **`path_basename_len`** (`src/lib/path.cyr`) — companion to `path_basename_ptr` that returns the trimmed basename length. Closes a latent trap: `path_basename_ptr("/a/b/")` returned a pointer to `b` but the buffer past it still held the trailing slash, so `strlen` on the result yielded `2` not `1`. Callers that need a byte count for `write(2)` should use the new helper; the existing dispatcher path (`argv[0]` without trailing slashes) is unaffected. `path_basename_ptr`'s comment now flags the pairing requirement explicitly.
- **Tests**: `tests/kriya.tcyr` gains 8 `path_basename_len` assertions (86/86 passing total). `scripts/smoke-basename-dirname.sh` 26/26. `scripts/smoke-realpath.sh` 30/30. `scripts/smoke-readlink.sh` 24/24. `scripts/smoke-which.sh` 23/23. `scripts/smoke-stat.sh` 37/37. `scripts/smoke-ls.sh` 36/36 covering default sort, `-a`/`-A` hidden-file split, `-r` reverse, `-F` type-suffix matrix incl. `*` exec, `-i` inode column, `-l` 8-column layout with ISO mtime format, `-l` symlink ` -> target`, `-l -h` human-size matrix (1K/5K/1.4M boundaries), `-d` directory-as-entry, `-R` recursion with symlink-no-follow, multi-operand non-dir-first-then-sections layout, partial-failure exit + stdout preservation.

### M3 closeout

All seven planned M3 utilities ship: `basename`, `dirname`, `realpath`, `readlink`, `which`, `stat`, `ls`. The canonicalization helper (`fs_realpath`, 3 modes) and the `epoch_to_date`-driven mtime formatter are the cross-utility additions; the path-text utilities (`basename`/`dirname`) closed a latent trap in `path_basename_ptr`'s usage pattern by adding `path_basename_len`. After M3, the kriya surface covers every POSIX-essential path/listing tool a shell needs to bootstrap. **Cut as v0.4.0.**

## [0.3.0] — 2026-05-17

Closes M2 — seven file-operation utilities (`mkdir`, `rmdir`, `touch`, `ln`, `cp` with the full ADR-0003 `-P`/`-H`/`-L` recursive matrix, `mv`, `rm`) on top of two new shared libs (`src/lib/fs.cyr` for `*at()`-family traversal, `src/lib/protected.cyr` for ADR-0004 root refusal) and two M2 policy ADRs. **265 behavioural smoke cases pass across the M2 utilities** (mkdir 24 + rmdir 24 + touch 26 + ln 30 + cp 26 + cp-recursive 39 + mv 43 + rm 53), with 78/78 unit assertions still green. Cold-start median 1.185ms held (re-bench at M3 close).

Two cross-repo proposals filed during M2 — both await stdlib slot:
- `cyrius/docs/development/proposals/2026-05-17-octal-literal-syntax` — `0o755`-style integer literals (lexer-only ~30 LOC).
- `cyrius/docs/development/proposals/2026-05-17-syscalls-at-family-stdlib` — bundle missing `sys_link`/`sys_lstat`/`sys_rename` + full `*at()`-family wrappers + `AtFlag`/`Utime` enums.

### Added

#### M2 policy lead-in (destructive utilities ship behind these decisions)

- **ADR 0003** — Symlink-follow policy for destructive utilities. POSIX-aligned defaults across `cp`, `mv`, `rm`, `ln`; the kriya-defining choice is `cp -R` preserving symlinks by default (closes the POSIX implementation-defined gap in the safer direction) and `rm` having **no flag, env var, or build option** to follow symlinks under any circumstance. Recursive walks use `openat(O_NOFOLLOW | O_DIRECTORY)` to close TOCTOU windows; destination opens use `O_NOFOLLOW` when policy says preserve. `mv` refuses to overwrite a symlink-to-directory.
- **ADR 0004** — `rm` refuses to operate on `/`, no escape hatch. Every operand is absolute-path-resolved and textually canonicalized (collapse `..`, no symlink resolution); if the result equals `/` the entire invocation exits `2` with `kriya rm: refusing to operate on '/'`. No `--no-preserve-root` flag, no `KRIYA_*` env var, no build-time bypass, no interactive override. Mechanism is a static `protected_paths[]` shipping with `/` only; future entries do not require a new ADR. Legitimate fine-grained removal (`rm /usr/bin/oldtool`, package-manager file replacement, `rm -rf /var/cache/zugot/build-1234`) is fully supported — only the bulk root operand is blocked. Known weakness: shell-expanded `/*` reaches kriya as `/bin /boot …`, none of which match `/`; a cross-operand bulk-root heuristic is deferred to a future architecture note (`003-cross-operand-bulk-root-defense.md`).

#### M2 utilities

- **`mkdir`** (`src/cmd/mkdir.cyr`) — POSIX `mkdir(1)`. Flags `-p`/`--parents` for missing-intermediate creation, `-m`/`--mode MODE` for explicit octal-only mode on the final component (symbolic forms `u+rwx` deferred to `chmod` in M3), `-v`/`--verbose` for created-dir reporting. Mode handling: `sys_mkdir(path, 0777)` always (kernel applies umask), followed by `sys_chmod(path, mode)` when `-m` is set so the requested bits land regardless of caller umask — matches GNU. `-p` walks `path_normalize`d prefixes, treating EEXIST-on-directory as success and EEXIST-on-non-directory as `ENOTDIR`-style failure (exit 1). Each operand is attempted independently; the invocation's exit code is `EXIT_FAILURE` if any operand failed. `mkdir -p /` is a no-op success.
- **`rmdir`** (`src/cmd/rmdir.cyr`) — POSIX `rmdir(1)`. Flags `-p`/`--parents` (cascade up empty parents until one is non-empty), `-v`/`--verbose`, and the GNU `--ignore-fail-on-non-empty` (under `-p`, ENOTEMPTY/EEXIST on a parent halts the cascade silently — exit 0). Operates only on the named entry: on a symlink it returns `sys_rmdir`'s ENOTDIR (no follow, consistent with ADR 0003). **No `protected_paths[]` check** — ADR 0004 is `rm`-only; the kernel returns EBUSY on `rmdir("/")` itself, and legitimate `rmdir /var/empty`-style operations stay available. Each operand attempted independently; exit `EXIT_FAILURE` if any failed.
- **`touch`** (`src/cmd/touch.cyr`) — POSIX `touch(1)` intersection that ships at M2: create-if-missing + bump times to now. Flags `-a` (atime only), `-m` (mtime only), `-c`/`--no-create` (skip the `open(O_CREAT)` step; `utimensat` ENOENT propagates as exit 1). Defaults to updating both atime and mtime; `-a` alone and `-m` alone build a `struct timespec[2]` with the omitted side set to `UTIME_OMIT`. Uses `sys_open(O_WRONLY | O_CREAT, 0666)` for create and a raw `utimensat(AT_FDCWD, path, times, 0)` syscall — the stdlib `syscalls_x86_64_linux.cyr` doesn't expose a wrapper yet. POSIX `-r REF` (copy times from REF), `-t [[CC]YY]MMDDhhmm[.SS]` (explicit stamp), and GNU `-d STR` (human date string) deferred until `lib/chrono.cyr` exposes a stamp-parser. GNU `-h` (no-dereference on symlinks) deferred. Each operand attempted independently; exit `EXIT_FAILURE` if any failed.
- **`ln`** (`src/cmd/ln.cyr`) — POSIX `ln(1)`. Flags `-s`/`--symbolic`, `-f`/`--force`, `-P`/`--physical` (ADR 0003: hard-link the symlink itself; `linkat` flag is `0` not `AT_SYMLINK_FOLLOW`), `-n`/`--no-dereference` (treat existing symlink-to-directory destination as a name to replace — required for the `ln -s -f -n newdir.tmp linkdir` atomic-retarget idiom called out in ADR 0003), `-v`/`--verbose`. Argument shapes: single-arg `ln TARGET` creates `basename(TARGET)` in cwd; two-arg `ln TARGET LINK` is explicit; 2+ args with the last operand resolving to a directory is the multi-source-into-dir form. Uses `sys_symlink` for soft links and a raw `linkat(AT_FDCWD, target, AT_FDCWD, link, AT_SYMLINK_FOLLOW)` for hard links (`AT_SYMLINK_FOLLOW=1024` by default; `0` under `-P`). Per ADR 0003, hard `ln` follows source symlinks by default (POSIX); `-P` flips. Soft `ln -s` is always pure-text — `target` is never opened. `-r` (relative symlink resolution), `-T` (no-target-directory), `-t` (target-directory), `-b`/`--backup` deferred. Each operand attempted independently.
- **`cp`** (`src/cmd/cp.cyr`) — non-recursive POSIX `cp(1)`. Flags `-f`/`--force`, `-i`/`--interactive` (ADR 0002: when stdin is not a tty, exit 2 invocation-wide; when it is, prompt for `y`/`Y`), `-p`/`--preserve` (mode + atime/mtime; ownership preservation deferred — needs root to matter), `-v`/`--verbose`. Argument shapes: single-pair `cp SRC DST` and multi-into-dir `cp SRC... DIR/`. Self-copy refused (same `(st_dev, st_ino)` check). Directory sources without `-R` exit 1 with EISDIR. Copy loop uses a process-lifetime 64 KiB heap buffer; EINTR is retried, partial writes are looped. `-p` builds a `struct timespec[2]` from `st_atime`/`st_mtime` and `utimensat(AT_FDCWD, dst, &ts, 0)` (raw `syscall(280, ...)` pending [[cyrius-at-family-proposal]]). tty detection inline via `ioctl(fd, TCGETS, ...)`.
- **`cp -R` recursive** (`src/cmd/cp.cyr`, `src/lib/fs.cyr`) — full ADR-0003 `-P` / `-H` / `-L` symlink-policy matrix on top of fd-rooted recursion. Default with `-R` is **`-P`** (preserve all symlinks — kriya choice closing POSIX's implementation-defined gap in the safer direction). `-L` follows everywhere. `-H` follows only the command-line operands and preserves links discovered during the walk. Every descent uses `openat(parent_fd, name, O_NOFOLLOW | O_DIRECTORY)` from a parent dirfd per ADR 0003's hard rule — a directory entry swapped for a symlink between the classifying `lstat_at` and the descending `openat` fails ELOOP, no silent follow. When policy *says* follow at the descend, the open omits `O_NOFOLLOW`; the lstat-vs-stat decision is carried into the descend as an `allow_follow` flag. Destination opens use `O_NOFOLLOW`; under `-f` an existing symlink at the destination is unlinked first and the open retried. Source-side `getdents64` (4 KiB buffer) walks one directory at a time; `_cp_dir_descend_at` is the only recursive function and dispatches each entry inline (Cyrius has no forward declarations). `-p` mode and times are restored to each directory after its contents are written, so internal writes don't bump the parent's mtime. Hard-link preservation (`--preserve=links`) deferred. Cycles handled by the kernel's `ELOOP` (path-resolution depth limit 40).
- **`src/lib/fs.cyr`** (new) — kriya filesystem traversal primitives. `fs_openat`, `fs_lstat_at`, `fs_fstatat`, `fs_opendir_nofollow`, `fs_mkdirat`, `fs_unlinkat`, `fs_linkat`, `fs_symlinkat`, `fs_fchmodat`, `fs_utimensat`, `fs_readlinkat`, `fs_rename`, `fs_renameat`, `fs_close`, plus `fs_getdents64` and `linux_dirent64` accessors (`fs_dent_reclen`, `fs_dent_type`, `fs_dent_name`, `fs_dent_is_dotdot`). File-type predicates (`fs_is_reg` / `fs_is_dir` / `fs_is_lnk`) and `fs_perms` work on a 144-byte stat buffer. Constants for AT flags, open flags, `linux_dirent64.d_type` values, `struct stat` field offsets, and `S_IF*` mode-type bits. `AT_FDCWD = -100` is exposed as `fs_at_fdcwd()` since Cyrius enum values reject the `0 - 100` form. Wrappers carry the x86_64 syscall numbers inline; sweep to per-arch stdlib wrappers when [[cyrius-at-family-proposal]] lands.
- **`mv`** (`src/cmd/mv.cyr`) — POSIX `mv(1)`. Same-FS path via `rename(2)` is one atomic syscall. Cross-FS (`EXDEV` / -18) falls back to copy + unlink: regular files via `_cp_one(force=1, preserve=1)` + `sys_unlink`; symlinks via `readlink` + `sys_symlink` + `sys_unlink`. Cross-FS *directory* moves NOT supported in this ship — clear error referencing the forthcoming `rm` tree-walk that will let mv complete the source removal. Flags `-f` (default; explicit overwrite), `-i` (ADR-0002 invocation-wide refusal on non-tty stdin), `-n` (no-clobber, silent skip), `-v` (verbose). **ADR-0003 hard rule #3 enforced**: refuses to overwrite a symlink-to-directory destination regardless of arg-shape — both `mv file linkdir` (single-pair) and `mv file ... linkdir` (multi-into-dir) exit `EXIT_FAILURE` with `refusing to overwrite symbolic link to directory`. Self-move detected via `(st_dev, st_ino)` match. Source lstat'd (POSIX: a source-symlink is renamed as a link). Smoke `scripts/smoke-mv.sh` — 43/43 passing, including cross-FS round-trips when `/tmp` and `/dev/shm` are on different filesystems (file content + inode-differs assertion, symlink-target preservation, directory-cross-FS clear-error path).
- **`rm`** (`src/cmd/rm.cyr`) — POSIX `rm(1)`, M2 close-out. Flags `-f`/`--force`, `-i`/`--interactive` (ADR-0002: invocation-wide usage error on non-tty stdin; `-f` overrides `-i`), `-r`/`-R`/`--recursive`, `-d`/`--dir` (POSIX-2017 empty-dir-only), `-v`/`--verbose`. **ADR-0003 hard rule #1 enforced**: `rm` never follows symlinks. There is no `--follow`, no `-L`, no env var, no build option. A symlink-to-directory is unlinked as a name; the target is untouched. Recursive walks use `openat(parent_fd, name, O_NOFOLLOW \| O_DIRECTORY)` at every descent (hard rule #4) — a directory entry swapped for a symlink between the classifying `lstat_at` and the descending `openat` fails ELOOP, no silent follow. **ADR-0004 hard rule enforced**: every operand is absolute-path-resolved and textually canonicalized (`path_normalize`, no symlink resolution); if any matches a `protected_paths[]` entry, the entire invocation refuses with exit 2 and `kriya rm: refusing to operate on '<path>'`. There is no `--no-preserve-root` flag, no `KRIYA_*` env-var bypass, no build-time toggle, and `-f` does not override the root check. Multi-operand atomicity: `rm survivor /` refuses *all* operands. `-f` semantics: silences ENOENT, suppresses prompts, exits 0 even with no operands. Smoke `scripts/smoke-rm.sh` — 53/53 passing, including: every canonicalization escape route (`rm /`, `rm /.`, `rm /tmp/..`, `rm ////`, `rm /../../../../`, relative `../../`), env-var bypass attempt rejected, `--no-preserve-root` unknown-option, multi-op atomicity preserved, symlink-to-directory `rm` leaves target intact, `rm -r` of a tree containing a symlink-to-dir never descends into the linked target.
- **`src/lib/protected.cyr`** (new) — ADR-0004 protected-paths mechanism. `protected_path_count()` / `protected_path_at(i)` enumerate the table; ships with `/` only. `protected_canonicalize(operand)` returns absolute + `path_normalize`d form (no symlink resolution) — relative operands are joined against `getcwd()`. `is_protected_path(operand)` membership check returns 1/0. The table is the only place to add or remove entries; per ADR 0004 future additions (e.g. `/etc`, `/usr`, `/boot`) tighten the policy and don't need a new ADR, but removing `/` requires a successor ADR and major version bump.

### M2 closeout

All seven planned M2 utilities ship: `mkdir`, `rmdir`, `touch`, `ln`, `cp` (full incl. `-R`), `mv`, `rm`. ADRs 0003 (symlink-follow policy) and 0004 (root refusal) verified end-to-end by behavioural smoke scripts. The TOCTOU-safe traversal foundation (`src/lib/fs.cyr`) and the root-protection mechanism (`src/lib/protected.cyr`) are in place; both are shared infrastructure for the M3 listing/path utilities that come next. Cross-FS directory `mv` is the one M2 follow-up still pending — now unblocked since `rm`'s tree-walk exists.
- **`kriya_parse_octal_mode`** (`src/lib/args.cyr`) — null-terminated cstring → integer in `[0, 4095]` (12-bit POSIX mode space). Rejects empty input, non-octal digits (`8`, `9`), symbolic forms (`u+x`), values ≥ `0o10000`, leading sign. Returns `-1` on any failure. Used by `mkdir -m` today; `install`, `chmod` (symbolic-mode addition), and others will consume it.
- **Tests**: `tests/kriya.tcyr` gains 17 octal-mode-parser assertions (78/78 passing total). `scripts/smoke-mkdir.sh` 24/24, `scripts/smoke-rmdir.sh` 24/24, `scripts/smoke-touch.sh` 26/26, `scripts/smoke-ln.sh` 30/30, `scripts/smoke-cp.sh` 26/26 (non-recursive), `scripts/smoke-cp-recursive.sh` 39/39 (basic `-R`, `-r` alias, into-existing-dir, `-P` explicit, `-H` follow-cmdline-only with inner-link preservation, `-L` follow-everywhere with content materialisation, `-p` mode+mtime preservation, missing-source/dir-over-file/dir-without-R errors, self-copy regression, verbose, symlink-to-`/etc` preserved by default). `tests/kriya.bcyr` gains `args/parse_octal_mode` at **20ns** steady-state.

#### Cross-repo proposals filed during M2

- **Cyrius lang** — [`2026-05-17-octal-literal-syntax`](https://github.com/MacCracken/cyrius/blob/main/docs/development/proposals/2026-05-17-octal-literal-syntax.md): `0o755` integer literals (lexer-only ~30 LOC). Target v6.x. Motivated by `mkdir`/`touch`'s decimal-with-comment POSIX-mode constants.
- **Cyrius stdlib** — [`2026-05-17-syscalls-at-family-stdlib`](https://github.com/MacCracken/cyrius/blob/main/docs/development/proposals/2026-05-17-syscalls-at-family-stdlib.md): bundle missing `sys_link`, `sys_lstat`, `sys_rename`, and the full `*at()`-family (`sys_openat`/`sys_mkdirat`/`sys_unlinkat`/`sys_linkat`/`sys_renameat`/`sys_fchmodat`/`sys_utimensat`/`sys_fstatat`) plus `AtFlag` / `Utime` enums. Motivated by `touch`'s `syscall(280, 0 - 100, …)` and `ln`'s raw `linkat(265, …)` — both retain `# TODO sweep when wrappers land` markers in their source. Required end-to-end for ADR 0003's `openat(O_NOFOLLOW \| O_DIRECTORY)` traversal in the forthcoming `cp`/`mv`/`rm`.

## [0.2.0] — 2026-05-17

Closes M1 — dispatcher + six simplest utilities + four shared lib modules + two architecture notes + cold-start benchmark. Dispatcher cold-start median **1.185ms** (target ≤2ms per v1.0 acceptance in `roadmap.md`).

### Added

#### Dispatcher and shared lib

- **Dispatcher** (`src/main.cyr`) — BusyBox-style: reads `argv[0]`, basename-strips via `path_basename_ptr`, routes to `cmd_*`. Both symlink form (`./true`) and explicit form (`kriya true`) dispatch identically. Unknown utilities and missing utility names emit `kriya: unknown utility: <name>\n` to stderr and exit `2`. Implements ADR 0001.
- **`src/lib/exit.cyr`** — `EXIT_SUCCESS=0` / `EXIT_FAILURE=1` / `EXIT_USAGE=2` as an enum (no `gvar_toks` cost per CLAUDE.md Cyrius Conventions).
- **`src/lib/args.cyr`** — kriya-side argv wrapper. `kriya_argv_flat()` materializes a flat `cstr*` array from stdlib `argv(n)` (one heap alloc per process, cached). `kriya_args_parse(spec, start)` wraps stdlib `flags_parse` with the dispatcher's `start` offset. `kriya_parse_nonneg_int(s)` parses non-negative base-10 integers and reports errors via `-1` (used by `sleep`).
- **`src/lib/path.cyr`** — pure-string path primitives (no filesystem syscalls). `path_basename_ptr` (zero-alloc, pointer-into-source for the canonical trailing-slash-free case), `path_dirname`, `path_is_absolute`, `path_normalize` (collapses `.`/`..`/duplicate slashes, with root absorbing leading `..` for absolute paths), `path_join` (right operand wins when absolute), `path_is_under` (sandbox check used by M2 destructive utilities).
- **`src/lib/errmsg.cyr`** — Linux errno → message table for errnos 1..40 (the POSIX core, ABI-stable across libc-free callers). `errmsg_for(errno)` returns a static cstring; `errmsg_is_known(errno)` distinguishes named from numeric fallback. Unknown errnos do NOT fall back to a wildcard message — see arch note 001.

#### Utilities (six of six M1)

- **`true`** (`src/cmd/true.cyr`) — POSIX `true(1)`, always exits `0`.
- **`false`** (`src/cmd/false.cyr`) — POSIX `false(1)`, always exits `1`.
- **`echo`** (`src/cmd/echo.cyr`) — POSIX `echo(1)` with leading-`-n` recognition per GNU/BSD/bash convention. Only the literal token `-n` is a flag; `-nn`, `-en`, `--` are data. `-e`/`-E` (escape interpretation) deferred until the `lib/str.cyr` escape table lands.
- **`pwd`** (`src/cmd/pwd.cyr`) — POSIX `pwd(1)` with `-L`/`--logical` (default; trusts an absolute `$PWD`) and `-P`/`--physical` (always `getcwd`). The strict POSIX inode-equality check on `$PWD` deferred until `fs.cyr` exposes a stat-compare helper.
- **`yes`** (`src/cmd/yes.cyr`) — POSIX `yes(1)`. No flags. Repeats `y\n` by default, or argv operands joined by spaces, until the write fails (broken pipe). 8 KiB line cap.
- **`sleep`** (`src/cmd/sleep.cyr`) — POSIX `sleep(1)` with a single non-negative integer-seconds operand. GNU fractional seconds and suffixes (`1.5`, `1s`, `1m`, `1h`) deferred until the duration-parser lands in `lib/chrono.cyr`.

#### Decisions and policy

- **ADR 0001** — BusyBox-style dispatcher vs N independent binaries. Accepted.
- **ADR 0002** — Option parsing for humans and agents. One parser, POSIX-short + GNU-long, hard No-Gos on prefix matching, optional values, interactive prompts on non-tty stdin, and silent option deprecation. `--help` (human) and `--help=json` (machine schema, locked behind `KRIYA_HELP_SCHEMA_VERSION`) for capability discovery; `kriya --list` enumerates utilities as JSON. Implementation status section names the deferred-to-stdlib follow-ups (short clustering `-rfv`, attached short values `-n10`).
- **Architecture note 001** — errno → message policy. Pins the framing `kriya <util>: <message>: <operand>\n` on stderr; mandates one-source-of-truth in `errmsg.cyr`; explicit `errno NNN` fallback for unmapped codes (no wildcard message).
- **Architecture note 002** — Signal handling model. Documents the M1 "rely on kernel defaults" stance (SIGPIPE → 141, SIGINT → 130, SIGTERM → 143) and names the M2/M3/M4/M5 triggers for installing flag-based handlers. Hard No-Gos: no utility ignores SIGPIPE; no utility catches SIGSEGV/SIGBUS/SIGFPE; no handler runs before `args_init()`; no handler sleeps.

#### Tests, benchmarks, build tooling

- **`tests/kriya.tcyr`** — 61/61 unit assertions across exit codes, `cmd_true`/`cmd_false`, `path_basename_ptr`, `path_is_absolute`, `path_dirname`, `path_normalize`, `path_join`, `path_is_under`, `errmsg_for`, `errmsg_is_known`, `kriya_parse_nonneg_int`.
- **`tests/kriya.bcyr`** — in-process hot-path benchmarks via stdlib `lib/bench.cyr`. Steady-state (Cyrius 5.11.54, x86_64): `path_basename_ptr` 62ns, `streq` hit/miss 33ns/29ns, `cmd_true`/`cmd_false` 5-6ns, `path_normalize` simple/messy 322ns/498ns, `errmsg_for` 6ns.
- **`scripts/bench-coldstart.sh`** — process-spawn timing for `./build/kriya true`. `RUNS=30` baseline: min 1.010ms, **median 1.185ms**, max 1.374ms.
- **`scripts/version-bump.sh`** — single entry point for bumping versions. Writes `VERSION`, regenerates `src/version_str.cyr` with the computed byte length, and updates the `## Version` line in `docs/development/state.md`. Refuses non-semver inputs.

#### Build

- **`cyrius.cyml [package].version = "${file:VERSION}"`** — single source of truth for version. `src/version_str.cyr` (AUTO-GENERATED) holds `_VERSION_STR_KRIYA` (banner with `\n`), `_VERSION_LEN_KRIYA` (precomputed byte length), `_VERSION_KRIYA` (bare semver). Consumers reference these vars rather than baking the literal in. Pattern mirrors `agnos`, `vidya`, `cyim`, `chakshu`, cyrius itself.
- **`cyrius.cyml [deps].stdlib`** — `args`, `flags`, `chrono`, `fnptr`, `bench` added alongside the M0 baseline (`string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`, `assert`).

## [0.1.0] — 2026-05-15

### Added

- Initial `cyrius init kriya` scaffold — `VERSION`, `cyrius.cyml`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`, `src/{main,test}.cyr`, `tests/kriya.{tcyr,bcyr,fcyr}`, `docs/{adr,architecture,guides,examples,development}/` per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md).
- Cyrius toolchain pin `5.11.54` in `cyrius.cyml [package].cyrius`.
- README, CLAUDE.md, `docs/development/{state,roadmap}.md`, `docs/guides/getting-started.md` filled with project-specific content per [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md). Sovereign-replacement boundaries documented (owl owns `cat`, cyim owns `vim`, sit owns `git`, chakshu owns `htop`, agnoshi owns shell builtins; kriya fills the gaps).
- Per-utility status table in `docs/development/state.md` covering ~40 planned utilities across M1–M6.

### Identity

`kriya` (Sanskrit: क्रिया — *action, operation, verb*) — coreutils-equivalent for AGNOS. One repo, many small static utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep` …) sharing infrastructure. BusyBox-style dispatcher + symlinks per utility. Each kriya is one verb the user invokes.
