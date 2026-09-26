# kriya — Lessons

> **Durable process knowledge, not a plan.** The roadmap answers *what next*;
> [`CHANGELOG.md`](../../CHANGELOG.md) answers *what landed*. This file answers the third question:
> *what has already cost us time, and how do we not pay it again.*
>
> Every entry here was written the release after it bit. They are kept because the failure mode is
> always the same — the code reads correctly, compiles clean, passes lint, and is wrong anyway.

Split out of `roadmap.md` at 1.6.6, which had accumulated them inside shipped milestone entries the
roadmap's own header says should not be there ("Open work only. Anything shipped has been removed
from this file"). Removing the shipped entries would have deleted the lessons with them.

---

## How to use this file

- **Before a release**, skim § Testing and § Measuring against GNU. Most of what is here is about
  *evidence* rather than code, and evidence is what gets skipped under time pressure.
- **After a toolchain pin bump**, re-run every detection in § The compiler watchlist.
- **When something bites twice**, add it here rather than to the release notes. A lesson that only
  exists in one CHANGELOG entry is a lesson nobody will read again.

---

## Testing and evidence

### Fixtures see only the shapes you built into them

- ⛔ *A guard the kernel gives one code path for free is a guard the other path does not have.*
  `mv`'s same-filesystem arm inherits `ENOTEMPTY` from `rename()`; its cross-filesystem arm is a
  `cp -R -f` plus an `rm -r` and inherits nothing. **Where one arm is implemented by a syscall and
  the other by hand, list what the syscall was enforcing.**

- ⛔ *A green branch is a claim about its base, not about main.* Three branches merged at 1.6.9 were
  each green in isolation and each written against an older base. The merge was clean, every
  existing suite passed, and it still shipped a **wrong answer at exit 0**: an expander that split a
  cluster sitting in a value position, so `realpath --relative-base -em nodir/leaf` returned a
  fabricated absolute path where GNU exits 1. **Re-audit the merged whole, not the branches.**
  ⚠ The tell is a branch that touches SHARED code — `src/lib/args.cyr` here — where "conflict-free"
  and "compatible" are different properties.

- ⛔ *A fix that stops one line short leaves the same bug wearing the same clothes.* The branch that
  replaced `head`/`tail`'s `-n`/`-c` precedence ladder with a real last-wins rule left the `-q`/`-v`
  ladder **twenty lines below it**, in the same function, in the same shape — and that one ran in
  BOTH directions, so `head -q -v a b` concatenated two files with no delimiter at exit 0.
  **When you fix an instance of a pattern, grep for the pattern.**

- ⛔ *A probe that can abort the suite is worse than no probe.* The only test of `cp`'s group/other
  withhold polls a running copy, because the withhold has no final-state signature at all. Under
  `set -e` in the CI container it died silently and took **108 real assertions** with it, reporting
  nothing — the suite printed no summary and the runner saw an empty result. Every step of a
  best-effort probe needs `|| true`, and a miss has to SKIP WITH A NOTE rather than pass quietly.

- ⛔ *A fuzz varies the axes you thought of, and is blind along the rest.* `ls`'s format fuzz drew
  name LENGTHS per entry — the axis that moves column boundaries on and off a tab stop — and capped
  the entry COUNT at 26. Both are inputs to the layout, and the second one was fixed. It reported
  0/560 against a column-fit model that gets a whole column wrong on 52 short names; widened to 120
  entries it reports 15/560 against the same build. **List the inputs the code reads, then check
  which of them the generator actually moves.** ⚠ The tell is a generator whose comment explains
  why ONE variable is varied: that comment is also the record of what was not considered.

- ⛔ *Three plausible models can pass every case you would think to write.* GNU's column separator
  had three candidate rules; each matched every hand-built fixture, and only a 560-case randomised
  differential separated them. **When a rule is inferred rather than read, hand-written cases
  confirm the inference instead of testing it** — the cases and the model come from the same guess.

- ⛔ *Widening a fuzz's fixtures finds what the fixtures never contained.* Adding ACLs found the
  ACL gap in one run; adding setuid/setgid/sticky modes found a plain-`cp` divergence older than
  the release. **The corpus is the coverage.**

- ⛔ *A test whose fixture the caller OWNS cannot see a rule about failing to own it.* The
  sticky-bit case passed against a mask that kept sticky and against the mask that does not,
  because a chown of your own file to yourself always succeeds. ⚠ **Third release running** that a
  green assertion was measuring nothing — 1.5.3's fuzz never reached the function under test,
  1.6.0's mtime comparison used a fixture created seconds earlier, and this one used a fixture
  whose ownership could not fail. **The fixture has to be able to produce the wrong answer.**

- ⭐ *`unshare -Ur` is a real privilege fixture and it is already in the tree.* `smoke-df.sh` used
  it for mount namespaces; ownership needs the user-namespace half. It makes the
  ownership-SUCCEEDS path testable on an unprivileged runner, which is the half that no amount of
  care with `id` shims can reach.

- ⛔ *A fixture whose entries are all short cannot see a rule about width.* Three mutations survived
  1.6.8's first pass — a tab-stop off-by-one, a wrap boundary, and the default terminal width — and
  all three survived for one reason: every existing `ls` fixture holds 2-character names, and at
  that size the right answer and the wrong one agree. ⚠ **Fourth release running that the first
  mutation pass found holes in the TESTS rather than defects in the code.** The fixtures added to
  kill them each name the mutant they kill, because a fixture whose purpose is not written down
  gets "simplified" back to the shape that killed nothing — ⚠ one of them did exactly that in
  draft, holding 3-character names at width 12, which reads like a boundary case and is not one.

- ⚠ *The "simulated root" release condition shims `id` to answer 0 and cannot make a chown
  succeed.* Guarding a privileged assertion on `[ "$(id -u)" = 0 ]` would skip it in exactly the
  condition whose name suggests it should run.

- ⭐ *Widening a fuzz's fixtures finds bugs older than the release.* Generating setuid, setgid and
  sticky modes to test the new drop rule immediately surfaced a plain-`cp` divergence that predated
  it — the kernel clears setuid and setgid on `open(O_CREAT)` and keeps sticky, and nothing had
  ever copied a sticky regular file in a test.

- ⛔ *A generator that can only build WELL-FORMED fixtures is not a fuzzer for error paths.* This
  harness ran 2,363 green comparisons over a real defect because it could not construct the two
  shapes that trigger it: every symlink it built pointed at a directory that ALREADY EXISTED and
  resolved — so a cycle could never form — and nothing was ever `chmod 000`. ELOOP and EACCES were
  exactly the errno families the code mishandled. ⚠ **Randomness will not stumble into a
  pathological shape the generator cannot express**; the shapes have to be added deliberately.
  Adding mutual-cycle pairs and one unsearchable directory per tree turned it red on the first
  40-case run.

- ⚠ *A fixture where two branches agree asserts nothing.* A symlink pointing at a directory in the
  CWD makes `-L` and `-P` give the same answer for `link/..`; the first `-L` probe used exactly
  that and concluded the flags were identical. **Fourth release running** that a test could not
  tell two answers apart.

- ⚠ *A test corpus is a list of shapes you thought of.* The fuzz had `/` and `/..` and not `/.`,
  so 4,500 green comparisons sat on top of `realpath dir/file/.` answering the file at exit 0.
  **Second release running** that the generator, not the code, was the thing that needed fixing
  first.

- ⭐ *"What would the refused caller do instead?" is the question a safety feature has to answer.*
  Four independent designs all refused the same shape, and measuring the alternatives showed that
  shape was the least destructive one available. A guard that cannot see the workaround it creates
  can raise expected damage while looking like it lowers it.

- ⚠ *One utility, two code paths, one feature.* `cp` needed the backup hook in BOTH `_cp_one` and
  `_cp_file_at`; the second is only reachable under `-R`, so wiring one would have shipped
  `cp -b` working and `cp -Rb` silently not.

- ⛔ *A quoting table measured for one caller is not measured for the next.* `ls` names can never
  contain `/`, so `/` was never in the set — and reusing it for diagnostics quoted every path in
  every message. ⚠ **The bytes a caller cannot produce are the bytes its test set does not cover.**

- ⛔ *An assertion cannot see a flag whose effect matches the default.* `-s` silences, and the
  default is already silent, so the test stayed green against a build that ignored `-s` entirely.
  ⭐ **Test a flag against its OPPOSITE, not against the default** — `-v -s` discriminates where
  `-s` alone cannot. **Third release running.**

- ⚠ *A piped listing prints literally whatever the quoting table says.* The `ls` half of the same
  assertion needed `--quoting-style=shell-escape` explicitly; without it, the test could not fail.

---

- ⛔ *An option every test writes FIRST cannot show that it is positional.* `find -mindepth` was
  a test evaluated where it stood, and every smoke case put it before the other tests — where a
  positional reading and GNU's global one agree. `find t -print -mindepth 2` printed every entry and
  `-mindepth 2 -o -print` the shallow ones, both at exit 0, for as long as `find` had had
  `-mindepth` (1.7.1). **A global option is tested after an action and across `-o`.**

- ⛔ *A fixture whose files are seconds apart cannot see a sub-second rule.* `find -newer`
  compared whole seconds where GNU compares nanoseconds, and every fixture built its reference with
  `touch -d '2 days ago'`. `touch stamp; make; find . -newer stamp` missed everything written in
  stamp's own second, at exit 0 (1.7.1). `touch -d '… 05.100'` against `… 05.600` sees it.

### Testing the tests: mutation and adversarial review

- ⛔ **A new block that passes against the OLD binary has proved nothing, and three kinds of block
  do.** 1.6.16's run of every changed script against 1.6.15 found each of them in one pass:
  - a helper that adds its own command word: `compare_sorted` prepends `find`, so passing it
    `find d16s …` ran `find find d16s …`, which fails the same way on both sides and scores a pass;
  - a regression that HANGS instead of failing: a wrapped `nl -w` padded for ever, so the suite
    timed out where it should have reported. Wrap the call in `timeout`;
  - a fixture that cannot tell the answers apart: files made a moment ago are under a minute old,
    so a wrapped `-mmin -N` ("under a minute") and GNU's huge one match the same files. Backdate it.
- ⭐ **A zero-behaviour sweep is proven by the binary, not by the suite.** The octal sweep and the
  `FS_S_*` substitutions were built before the version bump and compared byte for byte with the
  committed 1.6.15 binary, on both targets, after every file: identical. A suite can only sample
  behaviour, while `cmp` covers every byte. It works only before the version string changes.
- ⛔ **`set -e` swallowed a suite a THIRD time (1.6.15, 1.6.16, 1.7.0).** An `err=$(…)` that
  captures a diagnostic takes the substitution's exit status; against a binary that refuses the
  option under test, the capture fails and the WHOLE SCRIPT ends, printing no summary — which the
  mutation run reports as an empty line, not as failures. Write `|| true` inside every capture of
  a command that is allowed to fail.
- ⛔ **A test compared against a DIFFERENT GNU invocation pins a belief, not a behaviour.**
  `smoke-xargs.sh` checked kriya's `xargs echo` on empty input against GNU's `xargs
  --no-run-if-empty echo`, beside a code comment saying modern GNU does not run the command. Both
  were wrong: 4.9 and 4.11 run it once, as POSIX says. The test could only ever agree with the
  comment. Compare the same command line on both sides; where kriya differs on purpose, assert
  kriya's answer and say why.
- ⛔ **`$(...)` drops NUL bytes, so a comparison through it can be vacuous.** `smoke-printf.sh`'s
  `%c empty` case passed from the day it was written: GNU prints a NUL for an empty `%c`
  argument, kriya printed nothing, and both came back from `$(...)` as the empty string. Found at
  1.6.17 when kriya started printing the NUL and bash warned about it. Compare bytes through a
  file, as `same` does, whenever the output can hold a NUL or end in a newline that matters.
- ⛔ **A mutation run is the scripts of NOW against the binary of THEN, and nothing may swap both.**
  1.6.17's first attempt used `git stash`, which put the OLD scripts back with the old source: the
  old suite passed against the old binary, 98 of 98, a verdict on nothing. Copy `scripts/` and
  `git show HEAD:kriya` into a scratch directory instead, as 1.6.16 did, and leave git alone.
  ⚠ The second run then hung: three new `err=$(...)` lines captured a diagnostic without
  `timeout`, and the old binary padded two gigabytes a byte at a time. Every call that can pad needs
  `timeout`, the diagnostic-capturing ones included. ⚠ And `pkill -f PATTERN` kills the shell
  running it when PATTERN is in that shell's own command line. Kill by PID.

- ⛔ *An adversarial review pass is worth more than the tests written beside the feature, again.*
  **Fifteen** real defects and none refuted — thirteen fixed in the release, two filed as follow-ups —
  of which the 76-case suite could see exactly none: attributes written before the
  chown that strips `security.capability`; `system.posix_acl_access` copied, silently granting
  access; a cross-filesystem `mv` onto a filesystem without xattr support failing the restore and
  leaving the file in BOTH places; an empty reason on the only two errnos this path produces; and
  three narrower races in the size protocol. ⛔ And the worst of them was **data loss**: a
  cross-filesystem `mv` merged into a non-empty destination directory, overwrote same-named files,
  exited 0 and removed the source — while the SAME command on one filesystem refused, because
  `rename()` gave that arm the guard for free. ⚠ **Second release running** that the review found
  more than the suite did, and by a wider margin.

- ⛔ *A differential fuzz harness is wrong before the code is — for the THIRD release running.*
  This one's fixtures contain symlinks like `s3 -> ../..`, and several of them COMPOSE: a link
  name built through three of them resolves OUT of the tree under test, so both implementations
  wrote to one shared path, kriya (running first) created it, and GNU then reported `File exists`.
  It read as a 2% kriya divergence. ⚠ **Nesting the trees deeper only moves the depth at which it
  happens** — the sound fix is to notice the escape and not compare that case. 0/4,935 afterwards
  across four seeds, with escapes counted and excluded.

- ⛔ *An adversarial review found ELEVEN more defects, and the tests written beside the feature
  found none of them.* Six in the new flags, three in `touch` — two of those older than the
  release — and two more from a third lens aimed only at `-r`, which reduced to one root cause in
  `fs_realpath`. ⚠ **Third release running.** ⭐ The lens aimed at ONE flag found the deepest
  defect: a narrow reviewer beats a broad one for a feature with a shared helper underneath.

- ⛔ *THE WORST DEFECT IN THE RELEASE WAS IN CODE NOBODY WAS LOOKING AT.* An adversarial review
  aimed at `realpath` found that the stdlib flag table keeps 128 positionals and DISCARDS the rest
  while returning success — so `kriya rm *` on 200 files deleted 128, left 72, and exited 0. It had
  been true since the flag table arrived. ⚠ **A cap that silently truncates is worse than one that
  refuses**, and the place to notice it is a review of something else entirely. ⭐ Fixed upstream at
  cyrius 6.6.5 (the table grows); 1.6.11 retired kriya's refusal and kept the assertion — every
  operand must be PROCESSED, which stays true however it is satisfied.

- ⛔ *A MUTANT THAT NEVER REACHES THE BINARY LOOKS EXACTLY LIKE A TEST THAT CANNOT SEE THE BUG.*
  `cyrius build` re-copies every module `[deps].stdlib` declares from the pinned snapshot before
  it compiles — `--no-deps` too — so the pre-6.6.5 positional drop written into `lib/flags.cyr` was
  gone before `cycc` read it. The "mutant" was byte-identical to the real build and every
  assertion stayed green, which reads as a verdict on the TESTS. ⭐ **`cmp` the mutant against the
  real build before believing either answer.** Mutate stdlib code in a scratch copy with the module
  taken out of `[deps].stdlib` and included explicitly; that one turned three assertions red.

- ⛔ *A GATE WHOSE COMMAND IS PIPED INTO A FILTER REPORTS THE FILTER'S STATUS.* `scripts/fuzz.sh`
  piped `cyrius fuzz` into `grep | sed` from the day it was written, so it exited 0 with every
  harness failing and with a harness that did not compile — CI's fuzz step could not go red. Found
  at 1.6.11. ⭐ **Prove a gate can fail**: a stub on `PATH` that fails is a one-minute mutant for any
  script that shells out, and it is the only way to see a status that is thrown away.

- ⛔ *AN OPTION THE ORACLE LACKS LOOKS EXACTLY LIKE A FAILING PATH, and this is the THIRD release
  cycle lost to a dev-box-versus-runner version difference.* GNU rejects an unknown option with
  rc=1 and empty stdout, which is byte-identical to "this path could not be resolved" — so
  `realpath -E`, present here and absent on the runner, turned four correct comparisons red and
  made a fifth pass for the wrong reason. ⭐ **Probe the oracle's option surface, skip the
  comparison, and still assert kriya's own answer** — skipping the whole case would leave the flag
  untested precisely where the comparison could not run. ⚠ `check-oracles.sh` prints the version
  and the surface now; it does not fail on them, because a version difference is legitimate.

- ⚠ *A clean number is a reason to look harder.* The corpus was first reported as a flat zero
  multi-root-child invocations. Re-running it found fourteen, and inspecting all fourteen found
  them false — documentation prose about this very problem, `groff` files where `rm` means *remove
  macro*. The conclusion held; the evidence for it did not, until it was checked.

- ⚠ *Mutation testing found a hole in the TESTS three times running now.* Three of seven mutations
  survived because a whole axis of the matrix — the closed-pipe half — had no fixture, under a
  comment claiming it did. **The axis that is hard to construct in `sh` is the axis that will be
  missing.**

- ⭐ *A decision to build nothing still needs assertions.* `smoke-rm.sh` pins the measurement that
  decided it, so reintroducing an aggregate rule is a visible test edit.

- ⚠ *A guard no caller reaches is worth keeping only if the comment says so.* The helper's
  missing-destination check is unreachable from all three utilities, which hook inside their own
  existence branch. It stays as the contract, with the unreachability written down rather than
  left for a reader to assume a test covers it. `-b`/`--backup[=CONTROL]` and

- ⛔ **A fixture built to catch an unbounded walk makes the OLD binary unbounded.** 1.7.1's `-L`
  loop fixture (`self -> .` beside two `up -> ..` links) branches at every level under a walk that
  cannot see loops, and the 1.7.0 binary reached **25 GB** in the mutation run through the one call
  written without `timeout` — a `$(… | grep -c …)` that counted its output. The shape of 1.6.17's
  padding hang, one release on: the fixture was designed to misbehave, so against the old code it did.
- ⛔ **A refusal test must refuse for the reason it names.** `smoke-help-json.sh` pinned "`find -H`
  is refused" with `find . -maxdepth 0 -H` — -H AFTER a starting point, which is an unknown test in
  kriya and GNU alike. It passed because of the argument's position, not the deferral, and would
  have gone on passing once `-H` shipped. Write the refused form the way a user would type it.

- ⛔ **A change to what a shared function RETURNS is a change to every policy that reads the
  value.** 1.7.1 taught `k_write` to call agnos's bare -1 EPIPE — right for the stdout pipe it was
  written for — and `tee -p`, whose whole meaning is "forgive EPIPE", then forgave a FAT file's
  failure at 4 KiB and exited 0. Neither half was wrong alone; the defect sat at the join, and the
  review found it by being told to read the CALLERS. **Grep for the value (`errno == 32`), not the
  function name.**

### Measuring: the number, and the thing beside it

- ⛔ *A cold-start number means nothing without the previous binary measured beside it.* One run of
  1.6.1 read 0.599 ms against a recorded 1.6.0 of 0.599 — and building 1.6.0 and re-measuring both
  in the same minute gave 0.884 and 0.899, indistinguishable. **Build the previous release and
  measure the pair**; an absolute figure compared against a number from another day is comparing
  machine states.

- ⛔ *Measure both implementations before calling a divergence a defect.* The fuzz reported `ln -sr`
  disagreeing with GNU inside symlink cycles. Cycles of length 3/5/6/7/9/11/13/17/41 pin each
  side's traversal count exactly — and the answer was that **GNU has no chain limit at all**, so
  its `realpath` prints paths its own `cat` cannot open, while kriya matches the kernel's 40.
  [ADR 0014](../adr/0014-symlink-traversal-limit-is-the-kernels.md). ⚠ **The fix for a divergence
  you decide to keep is to count it apart in the oracle, never to loosen the comparison** — the
  `cp` fuzz's POSIX-ACL counter is the precedent.

- ⛔ *Measure the tool, then measure the measurement.* Five research agents probed GNU and five
  more tried to refute them. The second pass changed the implementation THREE times — `-s` still
  stats the filesystem, `-L`/`-P`/`-s` are one last-wins group rather than a flag plus a pair, and
  `-e` type-checks the DIR arguments. ⚠ Each of those would have shipped as a plausible-looking
  divergence found later by a user.

- ⛔ *A false-positive rate measured where the false positives do not live is evidence about where
  you looked.* 6,475 parsed `rm` invocations said the aggregate rules were nearly free; the corpus
  contained no container build, no chroot assembly, no initramfs teardown — the three populations
  that would have paid.

- ⭐ *The env-var question had a measurable answer all along.* "Does the variable change anything
  with the feature's flag absent?" separates `VERSION_CONTROL` (inert) from `POSIXLY_CORRECT` (not)
  in one command, and it turns three precedents plus three unexplained acceptances into one rule.

- ⚠ *A note with no single implementation to check it against drifts.* architecture 001 had the
  operand and message fields the wrong way round, with four examples to match, describing something
  that never shipped in 38 utilities. It was caught by writing the one function the note describes.

### A comment is a claim, and claims expire

- ⛔ *A comment can be confidently wrong for years.* `touch -c`'s said "POSIX says it's still an
  error (exit 1), GNU agrees"; POSIX says *"Do not write any diagnostic messages concerning this
  condition"* and GNU exits 0 in silence. The smoke suite asserted the wrong answer beside it.
  **A comment citing a standard is a claim to check, not a citation to trust.**

- ⛔ *A comment asserting what another tool does is a claim to check, not a citation to trust —
  SECOND RELEASE RUNNING.* 1.6.2 caught `touch -c`'s "POSIX says it's still an error (exit 1), GNU
  agrees"; this one caught `realpath`'s "-e … (default; alias for the default mode)" and `sleep`'s
  "POSIX sleep takes one integer". ⚠ All three were load-bearing, all three were wrong, and in
  every case **the tests had been written to agree with the comment**.

- ⚠ *Arithmetic in a comment is a claim too.* "Four orders of magnitude below the int ceiling" was
  24.9x, and a test comment said the duration ceiling was 292,000 years where the value asserted on
  the next line is 292. Neither changed any behaviour; both would have misled the next reader.

- ⛔ *A SECOND deferral outlived its blocker.* `tee -i` waited six releases on infrastructure that
  already existed, exactly as `sleep`'s fractional durations waited on a chrono duration parser
  that was never coming. ⚠ **A deferral naming a blocker is a claim with an expiry date** — the
  cost of re-checking is one grep, and the cost of not re-checking is measured in releases.

- ⛔ *Applying a new rule to the EXISTING code is where it earns its keep.* `$COLUMNS` was forcing
  multi-column output down a pipe — a live script-breaker, eleven releases old, found by asking the
  rule's question of code nobody had complained about.

- ⛔ *A comment asserting another tool's behaviour was load-bearing and false — FOURTH release
  running.* `touch -c`'s POSIX claim, `realpath`'s default mode, `sleep`'s operand count, and now
  `ls`'s "$COLUMNS forces columns even off a tty (a real GNU affordance)". ⚠ **The pattern is
  specific enough to grep for**: a comment that says what GNU or POSIX does, with no measurement
  beside it, is the highest-yield place to look for a defect in this codebase.

- ⛔ *A comment can be a claim about KRIYA'S OWN CODE, and those expire too.* `realpath`'s order
  scan said "Bundled shorts are rejected by the parser (ADR 0002), so a short option is exactly two
  bytes here" and had an `if (tlen == 2)` acting on it. The parser has accepted clusters since
  1.4.0; `realpath -Ps slink` resolved the symlink GNU leaves alone, because neither letter of the
  three-byte token was ever seen. ⚠ **The GNU/POSIX-claim grep does not find these** — the claim
  names an internal ADR, and the code it described changed underneath it. **A comment that says
  "X is impossible here, so this shortcut is safe" is the same shape and the same risk.**

- ⛔ *A comment and the code under it can be two different rules, and the comment wins the review.*
  `readlink` said "Precedence (matches GNU last-wins): m > e > f" and `head` said "Mode: -c wins
  over -n (last-wins; GNU same)". Precedence is not last-wins; both sentences contradict themselves
  in eight words, both were read as documentation of correct behaviour for releases, and in both
  the ranking is what ran. ⚠ **When a comment names two rules, the code implements at most one of
  them** — and the tests get written to agree with whichever half the author had in mind.
  ⛔ **Third instance, 1.6.13**: `cp`'s "last-one-wins by precedence L > H > P (matches GNU cp)".
  `cp -R -L -P` dereferenced where GNU keeps the symlinks. Found only because `-a` had to join the
  group and its ORDER against `-L` was measured first. **Grep for "precedence" beside "wins".**

- ⭐ *Twenty-four byte-identical copies of one function is a defect with twenty-four homes.* The
  error line could not change shape without 24 edits, so it never did — and the quoting bug lived
  in all of them. Collapsing them removed **401 lines** and made the binary **8 KiB smaller**.
  ⚠ **Duplication is not just a tidiness problem; it is why the bug was unfixable.**

### Shape of the code, shape of the bug

- ⛔ *The expanded argv is the one option window, but it had a hole.* A bool long that opts into a
  value (`cp --preserve=LIST`) reached it as a bare `--preserve`: the expander strips the value so
  `flags_parse` accepts the token, and keeps only the LAST value per name. The first order-aware
  reader (`cp`'s option walk) therefore treated `--preserve=ownership` as a bare `-p` and preserved
  the mode as well. `kriya_expanded_optval(i)` now carries the value beside its token. ⚠ **Whatever
  the expander rewrites, an order-aware reader has to be able to read back.**
- ⚠ *An `O_PATH` descriptor is a dirfd, not a file descriptor.* It creates entries like any other
  (`openat`, `mkdirat`, `symlinkat`, `unlinkat` all work), and it is the only descriptor a directory
  without the read bit will give. But `fchmod`, `fchown`, `futimens` and `fsetxattr` refuse it with
  EBADF. The route in is AT_EMPTY_PATH (`fchmodat2` from Linux 6.6, `fchownat`, `utimensat`), else
  `/proc/self/fd/N`, and `fs_fd_*` does it once. Measured on Linux 7.2, not read.

- ⛔ *A fallback that returns the operand text changes the FRAME OF REFERENCE.* `ln -sr`'s fallback
  returned what the user typed, which resolves against the CWD — but a symlink's stored text
  resolves against the LINK's directory. Every link created outside the cwd pointed somewhere
  else, at exit 0, with no diagnostic. ⚠ **A silent fallback in a path-rewriting utility is worse
  than an error**, because the wrong answer is indistinguishable from the right one.

- ⭐ *Two review findings, one root cause, and it was not in the file under review.* Both `-r`
  findings reduced to `FS_REALPATH_ALLOW_MISSING` tolerating only ENOENT and then stopping.
  Fixing it also fixed `realpath -m` and `readlink -m`, which share the mode. **When two findings
  in one feature look unrelated, check whether the shared helper is the defect.**

- ⚠ *Dead code hides in a build note.* `_ln_resolve_dest` had zero callers since it was written.
  Cyrius reports unreachable functions as a NOTE with a count in the hundreds — nearly all stdlib
  — so one more in the pile says nothing, and no lint will ever raise it.

- ⛔ *A helper's contract is a precondition somebody has to enforce.* `path_basename_ptr`'s header
  says "caller must trim trailing slashes"; `cmd_ln` handed it raw operand text and had done so
  since the multi-into-directory form existed, so `ln -s f/ dir/` failed where GNU succeeds.
  **A documented precondition with no enforcement is a bug waiting for its first caller** — and it
  had three.

- ⛔ *An `int` in a syscall ABI is a silent truncation waiting for a big argument.* `sleep_ms`
  passes its argument to `poll(2)`; a 49.7-day request is 2^32 ms and returned in **707 ms with
  exit 0**. ⚠ The dangerous direction — the caller believes it waited. Chunking is the fix, and
  the same question is worth asking of every other stdlib call kriya hands a large number to.

- ⚠ *One error channel cannot carry two failures.* `kriya_parse_duration_ms` returned -1 for
  "malformed" and, on overflow, a wrapped negative that the caller also read as "malformed" — so a
  legal 317-million-year duration was diagnosed as not-a-number. A distinct sentinel is three
  lines and makes the message true.

- ⚠ *A differential helper that never shifts its own test name into `$@` compares nothing to
  something.* It failed loudly here (65 red assertions) only because the two sides then disagreed
  by construction; a helper that swallowed the extra operand would have passed everything.

- ⛔ *One statement, three spellings — and a check that reads argv only sees one of them.* A
  trailing slash, a trailing `.`, and a separator arriving from a SYMLINK'S OWN TARGET all assert
  "this component is a directory". The first fix read the last byte of the operand and caught
  exactly one. ⭐ **Assert where the thing is visible, not where it was typed** — moved into the
  walk, the rule covers all three and the stat is already in hand.

- ⛔ *Five assertions could not tell the right answer from the wrong one, and the review found them
  by MUTATING rather than reading.* The `-L`/`-P` last-wins pair used an operand where both orders
  agree; the `-s -e` contrast was ENOENT on both sides; the ADR-0014 block compared exit codes
  only; nothing paired `-s`/`-L` with a trailing slash; ADR 0015's recorded divergences had no
  assertion at all. ⭐ **"Which mutation would this test catch?" is a better review question than
  "is this test correct?"**

- ⛔ *A SECOND SCANNER OF ARGV IS A SECOND OPINION ABOUT WHAT THE USER TYPED.* 1.5.1 learned this
  once — `ls` bounded its sort-key scan with `kriya_argv_option_end` while the parser permuted, and
  dropped `-t` from `-rt` after an operand. ⚠ **Three more utilities were still doing it**:
  `realpath` walked the raw argv and could not see `-Ps`; `readlink` and `head`/`tail` did not walk
  it at all and substituted a fixed precedence. The fix each time is the same — ask
  `kriya_opt_seq()` where a flag last appeared in the parser's own EXPANDED argv, where clusters are
  already split, values already separated and `--` already honoured. ⭐ **`kriya_short_seq` from
  1.5.1 should have been generalised then rather than left as `ls`'s private helper**; a fix that
  stays in one utility is an invitation for the next three to re-derive it wrong.

- ⛔ *"Last-wins" and "x beats y" agree on exactly half the orders, and half the orders is what gets
  tested.* Every conflicting pair in `realpath`, `readlink`, `head` and `tail` was asserted ONCE —
  `-sP`, `-f -e -m`, `-n 1 -c 3` — and each of those is an order where the wrong rule and the right
  one coincide. ⭐ **A pair whose members conflict needs BOTH orders and the clustered spelling, or
  it proves nothing**: the assertion that catches the bug is the one nobody thought to write,
  because writing it feels like testing the same thing twice.

- ⚠ *The sibling utility has the same bug.* `head` was reported; `tail` had the identical block,
  the identical comment and the identical divergence, and was not. **When a defect is found in one
  of a pair — `head`/`tail`, `cp`/`mv`, `realpath`/`readlink` — grep the other before closing.**

- ⛔ *An inode assertion does not prove a rename.* A hard link shares the inode, so the
  "is it a rename?" test passed a link-based mutation; only asserting the backup's CONTENT — and
  that it stays independent when the destination is rewritten — catches it.

- ⛔ *SECOND release cycle lost to a dev-box-versus-runner coreutils difference, and this time the
  rule was already written.* 1.6.3 established "probe the oracle's option surface, skip the
  comparison, still assert kriya's own answer" after `realpath -E`; 1.6.6 then added three
  un-probed GNU-dependent assertions and one of them — `POSIXLY_CORRECT` making `readlink`
  verbose — is honoured on 9.11 and **ignored entirely on 9.4**. ⭐ **The fix is a habit, not a
  patch: run the suite against the runner's coreutils in a container before calling a release
  green.** `docker run -v "$PWD":/w -w /w ubuntu:24.04 sh -c '…'` found it in one pass, and
  `check-oracles.sh` now prints the capability so a future log carries its own explanation.
  ⚠ **Again at 1.6.12**: a bare `ls --dired` implies `-l` since coreutils 9.5 and is ignored by 9.4.
  Where kriya has chosen a side, compare against the spelling every version agrees on
  (`-l --dired`) and gate the direct comparison on a probe of the oracle.

- ⛔ *A function that loops internally must not hand its caller a short count.* `k_write`
  retried a short write itself and, when it gave up, returned what it had written — and seven
  utilities wrap it in their own "write the rest" loop, which added the short count and called again.
  After one give-up every later call took nothing and returned 0, and the caller looped for ever: on
  agnos, 200 s a round (1.7.1). **Loop inside, or report partial progress — never both.** It
  returns `n` or a negative errno now.
- ⛔ *A timeout per call is not a timeout per stream, and only the symptom can tell them apart.*
  The issue asked for `k_write`'s stall to be bounded by time, and it was: 5 s. Measured in QEMU on
  the kernel shape the issue described, the pipeline still hung past 40 s — `grep` writes each line
  in two calls and never looks at the result, so every call paid its own 5 s. The fix that holds is
  a mark on the DESCRIPTOR (1.7.1). **Verify a fix on the symptom that was reported, not on the
  function that was named.**
- ⛔ *An iteration count is a time bound only while an iteration costs the same.* `k_write` gave
  up after 20,000 rounds of `sched_yield`: a short spin, until agnos 1.57.7 made the yield park the
  CPU for a 10 ms tick when nothing else was ready, and the bound became **200 s**. Nothing in kriya
  changed. **Bound a wait by the clock**; keep a count only as the backstop for a clock that does not
  move (before 1.57.7 `uptime_ms` stood still for a foreground program).
- ⭐ *When the reference answers one question on two paths, port both.* GNU `find` stats a
  followed link twice over: fts's walk stat, where only ENOENT falls back to the link and any other
  error is reported (and, below a starting point, the entry still visited), and its tests' stat,
  `fallback_stat`, where ENOTDIR falls back too. Porting the second for both hid a link through a
  file behind exit 0 — `find -L t -name l` — where GNU says *Not a directory* and exits 1 (1.7.1).

### Cyrius specifics

- ⛔ *`match` is a reserved keyword in Cyrius.* Costs one build. Worth knowing before naming a
  variable in a comparison loop, which is exactly where the word wants to be used. ⛔ *So is `mod`*
  (1.6.12, one more build) — the natural name for a `%H`/`%L` modifier.
- ⛔ **C's `unsigned int` truncates for free; Cyrius's i64 does not.** glibc's `gnu_dev_minor` is
  `(dev & 0xff) | ((dev >> 12) & ~0xff)` returned as `unsigned int`, so the mask is effectively
  32 bits. Ported literally to i64 it carries the MAJOR's top bits into the minor. Spell the width
  (`0xffffff00`), and test with both halves at full width — the realistic values never set the bits.
- ⛔ **A mechanical rewrite must not reach its own wrapper.** Replacing every `k_write( 1, ` in
  `ls.cyr` with `_ls_out(` also rewrote `_ls_out`'s body into a call to itself, and every `ls` hung.
  Exclude the wrapper from the substitution, then read the wrapper.
- ⛔ **A stdlib accessor's cost is part of its contract, and `argv(i)` is O(argv bytes) on Linux.**
  It walks `/proc/self/cmdline` from its first byte to the i-th NUL on every call. kriya built its
  argument table with one call per argument, so EVERY utility was quadratic in its argument count:
  `rm -f` over 20,000 names took 1.45 s against GNU's 73 ms, and `echo`, which then indexed that way
  again, 2.8 s. Found at 1.6.17 only because a rewrite of `printf` that switched to `argv(i)` came
  out twice as slow as the code it replaced. ⭐ Time a change against the binary it replaces, at a
  size where a complexity class shows, not only at the size the tests use. `kriya_arg(i)` is the
  O(1) accessor.

- ⛔ **An argument you do not pass is still an argument if the kernel reads its register.** A
  three-argument `syscall(1, fd, buf, n)` leaves `r10` as the last code set it, and agnos reads a4
  from `r10` for `write` and `read`: zero blocks, anything else is O_NONBLOCK. So one call site
  blocked on one pass and spun on the next (1.7.1). Pass the argument; the five-argument form
  compiles to `xor eax,eax; push rax; pop r10` — disassemble a two-line probe to see it.

## Discoverability and single sources of truth

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

## Measuring against GNU, and against the environment

- **If kriya does not read an environment variable, the ORACLE must not either** — or the test
  measures the shell rather than the code. Cost three separate repairs: `BLOCK_SIZE` for `du`/`df`,
  `POSIXLY_CORRECT` for `echo` and `pwd`, `QUOTING_STYLE` for `ls`/`stat`. ⚠ `POSIXLY_CORRECT` also
  stops GNU permuting options after operands, which is not obvious from its name. 1.6.12 added
  `TIME_STYLE`, `LS_BLOCK_SIZE` and `BLOCK_SIZE` for `ls -l`.
- ⛔ **...and a variable BOTH read must be PINNED.** 1.5.2's "an unset `LS_COLORS` emits nothing"
  was true only because the runner's `TERM` was not on GNU's `dircolors` list; from an xterm it
  fails, since GNU then colours with its defaults — and so, since 1.6.12, does kriya. `TERM=dumb`
  and no `COLORTERM`, on every call where they decide the answer.
- ⛔ **A name that parses as an option measures the option parser.** Put every name after `--`, on
  BOTH sides. 1.5.3's table said a leading `-` is quoted because GNU `ls` was handed `-a` without
  `--`, listed with `-a`, and printed something else — and the difference was recorded as a quoting
  rule, shipped in every diagnostic until 1.6.12. The 1.6.12 fuzz made the same mistake first, which
  is how it was recognised.
- ⛔ **Measure the behaviour a roadmap entry ASSERTS before deciding against it.** 1.6.14's entry
  said GNU reads a leading ERE `*` as a literal and asked whether to match it. GNU 3.11 and 3.12
  do neither: they warn and DROP the operator. The decision (ADR 0022) was about a behaviour
  that does not exist until it was measured. It is the comment-is-a-claim rule applied to the
  roadmap.
- ⭐ **When the behaviour is an ALGORITHM, read the reference's source, then prove the port on its
  output.** GNU xargs's E2BIG retry produces batches of 130,938, 130,941, 98,202, 98,203 and
  41,716 for one input — no measurement suggests that sequence, and no guess reproduces it. Read in
  `lib/buildcmd.c` (halve until something runs, then bisect, remembering across batches) and ported
  line for line, it matched on the first run, including the odd `130939 2 14363` tail of a larger
  case. The sequence is now a smoke assertion: a port that drifts shows up as numbers.
- ⛔ **Moving from slurping to streaming changes who owns stdin.** Once xargs reads its input as it
  goes, a child that inherits stdin — `sh -c 'cat'` — reads the input meant for the commands after
  it. GNU gives every child `/dev/null` (`prep_child_for_exec`); the old kriya never needed to,
  because it had read everything first. Check what else inherits a descriptor whenever the reading
  pattern changes.
- ⚠ **A wrapper script changes the environment you are measuring.** `--show-limits` and the `-s`
  ceiling depend on the environment's size, and running kriya through a `#!/bin/sh` wrapper added
  106 bytes of `PWD`/`SHLVL` that GNU, run directly, did not have. Anything whose answer depends on
  the environment is compared under `env -i`, with both binaries run directly.
- ⛔ **...for EVERY utility the entry names, not the first.** 1.6.17's entry said GNU "fails both"
  `printf` and `stat` past INT_MAX. `printf` does, exit 1. GNU `stat` prints nothing for the field
  and EXITS 0, because it never checks `printf`'s result. The claim had been measured on one of the
  two and written down for both. kriya's `stat` prints GNU's bytes and exits 1, by decision.
- ⛔ **A limit is not INT_MAX until each conversion has been measured at its edge.** GNU `printf`
  refuses an integer or `%c` field past INT_MAX − 2 (`%2147483645d` prints two gigabytes,
  `%2147483646d` nothing) and takes a `%s` width up to INT_MAX. 9.11 reads a `%s` precision past
  INT_MAX as no limit where 9.4 refuses the field. GNU `stat` takes every field up to exactly
  INT_MAX. None of it was among the hand-written cases: the 3,000-case differential fuzz
  (`scripts/difffuzz-printf.py`) found the first two in one run. Probe a boundary's neighbours,
  one conversion at a time, on both versions.
- ⛔ **A terminator is data in a utility that has no options.** The shared parser consumed a `--`
  wherever it stood, so `printf '%s|' a -- b` lost the `--` at exit 0. That is a silent change to
  the DATA, and it hid because every test put `--` first, where it is an option.
  [ADR 0025](../adr/0025-printf-takes-every-argument-as-data.md) takes `printf` off the parser.
- ⭐ **Where GNU and POSIX disagree, POSIX is the floor.** GNU's `\c` exits 0 after a conversion
  error; POSIX says such an error *shall not exit with a zero exit status*. kriya exits 1, the
  suite asserts it, and the fuzz skips that one class by name rather than loosening its oracle.
- ⛔ **A check made after the search inherits the engine's choice of match.** `grep -x` and `-w`
  asked "is THIS match the whole line / a word" of the one match niyama returned, and niyama is
  leftmost-first. So a line where a LATER alternative qualified was rejected, silently
  (`-xE 'a|ab'` on `ab`). A constraint the engine must satisfy belongs IN the pattern (`^(…)$`),
  where every alternative is tried against it.
- ⛔ **A defect found through one function is a CLASS, and the class is found by pattern, not by
  callers.** The roadmap filed "fifteen options wrap past 2^64", counted through the callers of
  `kriya_parse_nonneg_int`. Searching for the SHAPE instead (`n * 10 + d`, `v * base + d`) found
  the same unbounded accumulator in eight more parsers: `cut`, `seq`, `find` twice, `sort -n`'s
  comparator, `printf` and `stat`. Some of them gave worse answers than the ones filed, such as
  `seq` printing forever and `cut -f 1-18446744073709551616` printing everything.
- ⛔ **Measure an edge on BOTH GNU versions before comparing against "the local GNU".** GNU 9.4, in
  CI's container, refuses `head -n 99999999999999999999` (*Value too large*). GNU 9.11 on the host
  saturates it. A `ht_same`-style comparison would pass on one box and fail on the other, whichever
  answer kriya gave. Where the versions split, assert kriya's answer directly and name both
  versions in the comment. 1.6.12's `--dired` split was the first case and 1.6.15's oversized
  counts the second. 1.6.16 found three more in one release: `mv -n`'s exit status on a skip,
  `-n` with `-b`, and `nl -l 0`. Look for a split on any flag whose GNU behaviour changed in
  9.2 through 9.5, the releases that reworked `-n`.
- ⛔ **A utility that stops before EOF owes the next reader the rest.** `head` read 64 KiB, kept
  one line, and closed over the rest. So `{ head -n 1 >/dev/null; cat; } < file`, the idiom for
  consuming a header line, printed nothing more at exit 0. No test looked, because every test
  compared what `head` PRINTED. POSIX XCU 1.4 (INPUT FILES) asks that a seekable input be left just
  past the last byte processed. Test the shared descriptor with a second reader, as
  `smoke-head-tail.sh`'s `ht_offset` does. Any future early-stopping reader (a `grep -m`) owes the
  same.
- ⭐ **A grammar fuzz finds the behaviours nobody thought to write down.** 1.6.15's hand-written
  cases covered every form the roadmap named and matched GNU. 8,500 generated command lines then
  found three GNU `tail` behaviours outside any form: the `-n 0` early exit that never opens its
  files, the same exit for a `+N` past 2^63, and a negative zero. They were not kriya defects, but
  each needed a decision, and a hand-written case would never have asked. The fuzzer sorts each
  difference into a named class and fails only on the rest (`scripts/difffuzz-head-tail.py`).
- **A per-byte table cannot see a whole-name rule.** `{` and `}` are bare anywhere in a word and
  quoted when they ARE the word; a table measured byte by byte at two positions records them as bare.
  One-byte names are a fuzz stratum of their own.
- ⭐ **Compare the whole output, not the columns you are working on.** 1.6.12's comparisons were
  written for the new features and, run over whole listings, found four `ls` defects nobody had filed
  — devices printing `st_size`, a missing `.:`, an empty section for an unreadable directory, and a
  dropped exit status. The partial comparisons before them ("the columns through the owner", "the
  text after `->`") were written to step around the date column, and stepped around those too.
- **The host's filesystem can order two runs.** On a strictatime mount every read of a symlink bumps
  its atime, so `stat LINK` under GNU changes what kriya's `stat LINK` reports next. Anything read
  twice in sequence cannot have its atime compared.
- **A test that cannot go red is not a test, and it is worth PROVING with a mutant.** All of `ls`'s
  quoted output once sat behind a pty; on a host without `script(1)` the block skipped and an `ls`
  that never quoted scored 21 passed / 0 failed. `--quoting-style` exists to move the algorithm onto
  the pipe path.
- **A fuzz only covers the path it reaches.** A 3,000-name `stat %N` fuzz found zero defects in
  `ls`'s bare-character set — because `%N` ALWAYS quotes, so the function deciding whether to quote
  was never called. Six bytes were wrong, including `=`, where an unquoted `a=b` pasted into a shell
  is an assignment.
- **Confidence is not correctness.** "There is NO per-type colour table to ship" was written down
  with as much certainty as the rules that were right, and was half wrong: with `LS_COLORS` unset
  there are no escapes at all, but set it to any valid key and GNU loads a compiled-in default table
  and overlays the variable.

---

- ⚠ **A measured answer of a whole utility is not the answer of one function inside it.**
  The roadmap recorded GNU's `mkdir -m +t` as 1755 under umask 022 and called it "the rule" for
  the mode parser, and a unit test written from it failed against a correct port: gnulib's
  `mode_adjust` gives 01777, and the 1755 is mkdir(2) applying the umask again afterwards, with
  `dirchownmod` restoring only some of what that cleared (`+w` ends 777, `=rwx` 755). The test
  had to be re-derived from `find -perm`, where GNU calls `mode_adjust` and nothing else (1.7.1).

## The compiler watchlist

Not a milestone that closes: a **standing list of the ways the Cyrius compiler and kriya interact
badly**, kept because every entry here has already cost real time at least once, and because the
failure mode is always the same — the code reads correctly, compiles clean, passes lint, and is wrong
anyway. Opened at v1.1.11 out of the P-1 sweep.

Each entry names the rule, how to detect it **mechanically**, and what happened the last time it bit.
Re-run the detections at every toolchain pin bump; the 6.5.x line is the codegen-quality line and a
pin move is exactly when a latent instance stops being latent.

**M15a — A function-local `var X[N]` is N BYTES. At module scope it is N×8.**
The single most expensive rule in this list. Re-measured at pin 6.5.35 with a two-local probe:
`|&b - &a|` = **8 / 32 / 144** for `var x[4]` / `var x[32]` / `var x[144]` — and again at **6.6.6**
(1.6.11), unchanged.
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
- *Detection*: for each `while` body containing a `var` declaration, flag any `break;`. ⚠ **Strip
  comments first** — an explanatory `# var st[48]` reads as a declaration and produces false hits.
- ⛔ *Status at 6.5.36*: **the recorded status was wrong, and the pin bump is what caught it.** This
  entry said "zero instances. The four `break;` in `src/cmd/find.cyr` are in loops with no `var`
  declaration" — that loop declares `var t` AND `var c0`, and breaks four times. It had been correct
  since 6.5.18 and the detection had evidently been run by eye rather than mechanically. Converted to
  flag + continue at the 6.5.36 bump; the scan now reports zero for real.
- ⭐ *The lesson inside the lesson*: **a watchlist entry whose status was established by reading is
  not a status.** Every detection here should be a script you can run, and the run should be part of
  the pin-bump checklist rather than a memory of having looked.

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

**M15h — `>>` is an ARITHMETIC shift, so one multiply into the sign bit poisons every mask below it.**
Opened at v1.6.0, writing the `(st_dev, st_ino)` hash. The shape is `h = a * K; idx = (h >> S) & MASK`
— which reads as "take some middle bits" and, the moment `a * K` overflows into bit 63, produces a
NEGATIVE `h` whose masked index addresses off the FRONT of the array rather than into it.
- *Detection*: for every `>>` in `src/`, ask whether the left operand can have bit 63 set. Two sources
  do it: an unsigned kernel value read with `load64` (`st_dev`, `st_ino`, `st_size` on a sparse file),
  and any multiply whose operands are not individually bounded. Size the multipliers so the running
  sum cannot pass 2^62, or mask the operand down before multiplying.
- *Note*: `& MASK` does not save you — masking a negative gives a positive, so the bug surfaces as a
  wrong bucket (harmless) right up until the shift count and mask happen to keep the sign bit, and then
  it is an out-of-bounds load. It will never fail a test that uses small inode numbers.
- *Status at v1.6.0*: `_fs_inoset_hash` is sized so the widest input (a 32-bit half of `st_ino`) cannot
  push the sum past 2^56, and `tests/kriya.tcyr` pins it non-negative at four extremes including
  `st_ino = 2^63 - 1`. No other `>>` in `src/` takes an unbounded left operand.

**M15i — A name kriya defines that the stdlib ALSO defines is merged, not shadowed.**
Opened at 1.6.11. Cyrius resolves a duplicate top-level definition across two non-private files as
ONE symbol — *"last definition wins"* — and says so only in a warning, so the stdlib's own functions
can end up running kriya's code, or reading kriya's initializer for a variable the stdlib owns.
- *Detection*: `scripts/watchlist-scan.py` M15i resolves `[deps].stdlib` through every
  `include "lib/…"` and intersects its top-level `fn` / `var` / enum-member names with `src/`. The
  build's own `duplicate symbol` / `duplicate fn` warning names the same thing — read it.
- *Why at a pin bump*: kriya's names do not move when the pin does; the stdlib's do. A name that was
  kriya's alone becomes a collision the day upstream adds it.
- *Bit us from 1.6.7 to 1.6.10*: cyrius 6.5.36 gave `lib/io.cyr` `_env_load` / `_env_len`, the names
  `src/lib/env.cyr` used. The stdlib `getenv` then answered "unset" for every name when it ran first
  and segfaulted when it ran after `kriya_getenv`. Latent only because nothing in kriya calls the
  stdlib `getenv` on Linux — and ⚠ **the 1.6.9 audit read the warning and filed it as cosmetic**;
  a twenty-line probe said otherwise. Renamed to `_kriya_env_*`.
- *Status at 1.6.11*: 0 names over a 39-file closure; the scan reports exactly the two above when
  run against the 1.6.10 `env.cyr`.

