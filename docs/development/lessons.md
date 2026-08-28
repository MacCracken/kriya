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

### Testing the tests: mutation and adversarial review

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
  refuses**, and the place to notice it is a review of something else entirely.

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

- ⭐ *Twenty-four byte-identical copies of one function is a defect with twenty-four homes.* The
  error line could not change shape without 24 edits, so it never did — and the quoting bug lived
  in all of them. Collapsing them removed **401 lines** and made the binary **8 KiB smaller**.
  ⚠ **Duplication is not just a tidiness problem; it is why the bug was unfixable.**

### Shape of the code, shape of the bug

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

### Cyrius specifics

- ⛔ *`match` is a reserved keyword in Cyrius.* Costs one build. Worth knowing before naming a
  variable in a comparison loop, which is exactly where the word wants to be used.

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
  stops GNU permuting options after operands, which is not obvious from its name.
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

