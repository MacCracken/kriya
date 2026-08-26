# Changelog

All notable changes to kriya will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This file is **released items only**. Deferred follow-ups (post-1.0 GNU-parity features, Cyrius proposal sweeps, perf optimizations, the boot-burn signal) live in [`docs/development/roadmap.md`](docs/development/roadmap.md) under **Post-1.0 milestones**.

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
