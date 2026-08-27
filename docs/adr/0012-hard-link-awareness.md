# 0012 — Hard-link awareness: what `cp` preserves, what `du` counts, and which walks are allowed to come back

**Status**: Accepted
**Date**: 2026-08-26

## Context

Two utilities need the same fact — *have I already seen this inode?* — and until v1.6.0 neither could
answer it.

`cp --preserve=links` asks it so that two source names sharing an inode become two names for one
destination file. v1.2.1 made kriya **refuse the flag by name** rather than accept it and quietly
produce independent copies, which was the honest interim answer but left the feature unbuilt.

`du` asks it so that a file reached under several names is counted once. kriya counted at every name,
so `du` over a tree with hard links reported more bytes than the tree occupies. On this machine's
`/usr` the gap is 47,588 KiB out of 20,676,544 — 0.23%, small enough to be invisible and large enough
to be wrong.

Four things make this a real decision rather than a default:

**1. The destination identifier.** kriya's `cp` recursion is fd-anchored: it descends with
`openat(O_NOFOLLOW|O_DIRECTORY)` from an explicit parent dirfd (ADR 0003) and closes each directory fd
as the walk unwinds. To hard-link a second name to the first destination, something must survive that
unwinding, and the natural fd-shaped identifier does not.

**2. GNU's `du` remembers every file it counts, and kriya cannot afford to.** Measured on this
machine, GNU's device-inode set costs about **one bit per counted file** — 200,000 files added 20 KB
to peak RSS, and `/usr`'s 204,110 files added 36 KB. That is a sparse structure. kriya's
`fs_inoset_*` is a 32-byte-per-entry open-addressed hash; the same 200,000 files would cost ~6 MB of
live table plus ~6 MB of tables abandoned by the doubling, against a `du -s /` that could plausibly
walk ten times as many. Matching GNU exactly means either paying that, or building a sparse inode
structure that is its own release.

**3. `du`'s default changes.** GNU dedupes by default and `-l/--count-links` turns it off. Shipping
parity therefore changes what `kriya du` prints for every tree containing a hard link — the first
default-behaviour change in `du` since it shipped.

**4. Two utilities could not survive a symlink that points backwards, and nobody had noticed.**
`kriya du -L` over a symlink pointing at an ancestor **dumped core**; so did `cp -RL`, writing a real
directory at every level on the way down. Nothing remembered which directories the walk had entered.
GNU answers such a tree in milliseconds. The machinery that fixes it is the machinery this ADR is
already about, one structure over.

⚠ The scope grew during the release, and every addition came from a **measurement rather than a
plan**: an adversarial review pass and a differential fuzz against GNU found the two `-L` crashes, a
silent data-loss path that `--preserve=links` had just opened, and three older `du` defects sitting
beside the code being changed. They are in this release rather than deferred because they are the
same walk, the same helper and the same test run.

## Decision

**Two shared structures in `src/lib/fs.cyr` — a `(st_dev, st_ino)` set and a walk-ancestor stack —
serve four callers between them. `cp` stores the first destination PATH as the set's payload and
links later names to it; a second set of the same kind stops it overwriting a destination it just
created. `du` uses membership alone, keys its default on it, and gains `-l/--count-links` to switch
it off. The stack is what makes a following walk terminate, in both utilities. `du` tracks a
deliberately narrower set of inodes than GNU does, and the resulting divergence is measured,
asserted in the smoke suite, and named here.**

### The helper

`fs_inoset_new` / `fs_inoset_find` / `fs_inoset_add` / `fs_inoset_data` / `fs_inoset_count`, plus
`fs_nlink` / `fs_dev` / `fs_ino` accessors on a 144-byte stat buffer. Open addressing, linear
probing, power-of-two capacity, doubling at half load, one i64 payload per entry. **A repeat insert
keeps the FIRST payload** — that is what makes the destination `cp` links to, and the name `du`
charges the bytes to, the one the walk reached first.

⚠ Growth abandons the old table (bump allocator — the bargain `_fs_regrow` in the same file already
takes). The waste is bounded by the live table's own size.

### `cp`: the master destination is a PATH, not a dirfd

Per inode, the set remembers the destination **path string** (`dst_display`, the operand-rooted path
the walk already builds for diagnostics). A later name is created with
`fs_linkat(AT_FDCWD, master, AT_FDCWD, dst, 0)`.

Both dirfds are `AT_FDCWD` deliberately: `fs_linkat` on agnos routes to the path-based `k_link`,
which has no relative resolution and returns `-ENOSYS` the moment either side is a real fd. The dirfd
form would work on Linux and fail mid-walk on the target kriya exists for.

⚠ This re-resolves the master path from the cwd, so every intermediate component is walked again —
the hazard `fs.cyr`'s header names for accumulated paths. It is narrower here than for a descent: the
path names a file *this cp created moments ago*, and `flags = 0` (not `AT_SYMLINK_FOLLOW`) leaves the
final component undereferenced, so a symlink swapped in at the master's own name is linked as the
symlink rather than followed out of the tree.

### `cp`: which inodes are tracked follows the SYMLINK POLICY, not the link count

`st_nlink > 1` proves "cannot be reached twice" only while not dereferencing. Measured: `cp -RL
--preserve=links` over a directory holding one file and two symlinks to it produces **one inode with
three names**, and all three entries report `st_nlink == 1`. So the gate is

```
follow == 1  ||  st_nlink > 1
```

where `follow` is the `_cp_should_follow(policy, top_level)` the caller already computed — 1 under
`-L`, and under `-H` for a command-line operand. Non-recursive `cp` dereferences unconditionally
(POSIX), so it passes `follow = 1`. This is the same rule GNU uses (`1 < st_nlink ||
command-line-arg-with--H || -L`), reached from kriya's own policy enum.

### `cp`: a failed link is a failed copy

If `linkat` fails — cross-device within a destination tree that spans a mount point, a filesystem
without hard links, a permission problem — `cp` reports `cannot create hard link 'X' to 'Y': <errno>`
and fails the operand. **It does not degrade to an independent copy.** Degrading is precisely the
accepts-and-lies shape v1.2.1 went through `cp` to remove: exiting 0 having preserved nothing. GNU
errors here too.

### `cp`: `--preserve=` becomes a bitmask, and `mode` stops implying `timestamps`

`preserve` was one bit meaning "mode AND timestamps", so `--preserve=mode` silently preserved
timestamps and `--preserve=timestamps` silently preserved the mode. Splitting is what makes `links`
expressible at all, and it closes that on the way:

| Form | MODE | TIMES | LINKS |
|---|---|---|---|
| `-p`, bare `--preserve` | ✅ | ✅ | — |
| `--preserve=mode` | ✅ | — | — |
| `--preserve=timestamps` | — | ✅ | — |
| `--preserve=links` | — | — | ✅ |
| `-p --preserve=links` | ✅ | ✅ | ✅ |

⚠ The forms are **cumulative**, matching GNU: a list ORs onto whatever the bare form already set.

`ownership`, `xattr`, `context` and `all` remain refused **by name** with exit 2. Widening the
accepted set is where they land (roadmap 1.6.1), not a loosening of the check.

⚠ `mv` calls into `cp`'s copy path positionally and now passes `CP_PRES_P`, not a literal `1` — which
would mean "mode only" and silently drop the mtime a cross-filesystem move is supposed to carry.

### `du`: dedup is the default; `-l/--count-links` turns it off

A repeat contributes no bytes to any total **and prints no line at all** — not a zero line, no line.
That distinction is measured: GNU omits the entry from `-a` output entirely.

**This changes `du`'s default output.** It is a breaking change in the CHANGELOG's sense, with a
one-flag migration: `-l` restores the pre-1.6.0 accounting exactly.

### `du`: what is tracked, and the one divergence that leaves

Inserted into the set:

- every **command-line operand**, at any link count;
- every **directory** the walk enters — ⚠ the first cut of this rule guarded the link-count test with
  `is_dir == 0`, which reads correctly and left directories out of the table altogether, so
  `du DIR DIR/sub` walked and charged `sub` twice and `-c` reported a total that no printed line
  added up to. There are orders of magnitude fewer directories than files, so the memory argument
  that keeps single-link *files* out does not apply to them;
- every **non-directory with `st_nlink > 1`**;
- **everything**, under `-L`, because dereferencing makes a link count of 1 stop proving anything.

⭐ But the set is **consulted for every entry**, including ones that would not be inserted. A lookup
is one probe into a table the walk is already carrying — measured at **16 ns**, against roughly a
microsecond for the `stat` that precedes it — so checking costs nothing and closes half the
reachable-twice shapes for free.

⚠ **The residual divergence, stated exactly**: an operand that names a *single-link, non-directory*
file which an *earlier* operand's walk already counted — the directory spelling of the same shape is
closed. `du DIR DIR/file` lists the file where GNU omits it. The
reverse order (`du DIR/file DIR`) matches GNU, because the operand went into the set at depth 0 and
the walk consults it. Closing the remaining shape requires inserting every file the walk counts,
which is the 300× memory trade in **Context**. `scripts/smoke-hardlinks.sh` asserts kriya's own answer
for this case, so the day a sparse inode structure lands (roadmap 1.7.3) the assertion flips to a
GNU comparison and says so out loud.

### Cycle detection is a SEPARATE mechanism, it is an ANCESTOR test, and it survives `-l`

A following walk needs to answer a second question — *am I already inside this directory?* — and it
is not the same question as *have I counted this inode?*:

- It must survive `-l`. GNU terminates on a symlink loop with `-l` or without it. Folding the two
  into one flag brings the crash back through the flag that is supposed to make `du` do **less**.
- ⛔ **It must be a STACK, not a set of everywhere the walk has been.** A visited-set also stops the
  recursion, and it is wrong: two symlinks pointing at one directory are not a loop. Measured —
  `du -alL` over `real/`, `link1 -> real`, `link2 -> real` counts **12 blocks** under GNU and the
  visited-set answered **4**, silently dropping two of the three paths. Only membership of the
  **current path** means "descending here would not terminate".

`fs_dirstack_*` in `src/lib/fs.cyr` is that stack — push on descend, pop on unwind, linear scan,
because tree depth is tens and a hash costs more to maintain across push/pop than it saves. Both
`cp -RL` and `du -L` use it, and both now match GNU's message and exit status on a cyclic symlink.

### ⛔ `cp` refuses to descend into its own destination, and GNU does not

There is a second half to the `-L` runaway that the ancestor stack does not reach: a symlink that
escapes the source tree into a directory which **contains the destination**. `ln -s .. t/up`, then
`cp -RL t dst` — the walk goes up out of `t`, back down into `dst`, and copies the destination into
itself.

⚠ **GNU does not close this.** Measured: GNU wrote a **1,536-entry** `dst/up/dst/up/…` tree and
stopped only when the path exceeded the filesystem's limit, **exiting 0**. kriya wrote **11,635
entries and dumped core**.

kriya records the destination root's `(st_dev, st_ino)` per operand and refuses to descend into it,
reporting `not descending into the destination 'PATH'`. On the same input kriya now writes 3 entries
— the real content, and nothing else. This is a deliberate deviation from the oracle in the same
direction the existing in-tree guard already takes (`cp -r dir dir/backup` is refused outright,
after it was measured creating 12,188 directories before crashing); the textual `path_is_under`
check cannot see this one, because the destination is not under the source by NAME, only by
traversal.

### ⛔ `cp` refuses to overwrite a destination it just created

`cp -f a/f b/f dst/` resolves both operands to `dst/f`. kriya copied `a/f` and then silently
overwrote it with `b/f`, exiting 0; GNU refuses the second with `will not overwrite just-created`.
That was a divergence for as long as `cp` has existed here, and `--preserve=links` turned one
spelling of it into **data loss**: with both operands on one inode, the link path unlinked `dst/f`
and then tried to link it to itself, leaving *nothing at all* where a pre-existing file had been.

The guard is a third `(st_dev, st_ino)` set — every non-directory destination this invocation
created — and it is **unconditional**, not part of `--preserve=links`. Making it conditional would
leave `cp` inconsistent with itself in exactly the way the recursive-versus-non-recursive overwrite
split already was. ⚠ Directories are deliberately not recorded: `cp -R a b dst/` is supposed to
merge two trees that share a subdirectory name, and GNU merges them.

⭐ The same guard closes a subtler shape the link map opened: the map stores a destination **path**,
and a later operand could legitimately overwrite that path under `-f`, leaving the entry pointing at
another file's bytes. A third operand sharing the first's inode then linked to the wrong content and
exited 0. Refusing the overwrite that made the entry stale removes the possibility rather than
patching the symptom.

## Consequences

- **Positive** — `cp --preserve=links` does what it says after five releases of refusing to.
  `du` reports what a tree occupies rather than what its names sum to: on `/usr`, 20,676,544 against
  GNU's 20,676,544, exactly, and `-l` gives 20,724,132 against GNU's 20,724,132, exactly. **Two
  core dumps and one silent data-loss path are gone.** `--preserve=mode` and `--preserve=timestamps`
  stop overreaching. Two helpers, four callers, so the next consumer inherits both the code and the
  tests. ⭐ A differential fuzz over 120 random trees — hard-link groups, symlinks to files, to
  directories, dangling, and to ancestors — reports **0 divergences in 7,200 `du` comparisons and 0
  in 720 `cp` comparisons**.
- **Negative** — `du`'s default output changes for any tree with hard links; a script parsing
  totals across the upgrade sees them move. Under `-L`, kriya's set holds every file: 39 MB peak on a
  200,000-file tree against GNU's 10 MB. `cp` now re-resolves a destination path per linked name, a
  TOCTOU surface ADR 0003 otherwise designs out, mitigated but not eliminated.
- **Neutral** — the residual `du` divergence is now a named, asserted, one-shape debt rather than an
  unbounded unknown. A sparse inode structure would close it and shrink the `-L` figure at the same
  time; that is one piece of work, filed against 1.7.3. Two deliberate deviations from the oracle
  now need to be carried forward and re-argued if GNU changes: refusing to descend into the
  destination, and `cp`'s stricter default refusal to overwrite anything without `-f` (ADR 0003),
  which the just-created guard now sits in front of.

## Alternatives considered

**Retain a dirfd for each master destination instead of a path.** Rejected: it means holding one fd
per hard-link group for the whole walk. A tree with 5,000 hard-link groups exhausts `RLIMIT_NOFILE`,
and the failure mode is an unrelated `EMFILE` deep in an unrelated operation.

**Fall back to an independent copy when `linkat` fails.** Rejected: `--preserve=links` exiting 0
having preserved nothing is the exact defect v1.2.1 removed from this utility. GNU errors, and so
should a tool whose users are package managers and agents.

**Track every inode in `du`, matching GNU exactly.** Rejected on the measurement: ~300× GNU's memory
for the default path of a utility people point at whole filesystems. Revisit with a sparse structure,
not with the hash.

**Track only `st_nlink > 1` in `du`, skipping operands and `-L`.** Rejected: it is cheaper still, but
it leaves `du -aL` over a directory with one file and one symlink to it double-counting — a
three-command reproduction, not a corner — and it leaves the `-L` crash unfixed.

**Keep `-p` as one bit and add `links` as a second.** Rejected: `--preserve=mode` would go on
preserving timestamps. The release is *about* an attribute list that means what it says.

**Making the just-created guard conditional on `--preserve=links`.** Rejected: the silent clobber
predates the flag and is not caused by it. A guard that protects one option's users and not the
others leaves `cp` inconsistent with itself, which is the criticism this file already makes of the
recursive-versus-non-recursive overwrite split.

**Matching GNU on the escape-into-the-destination case.** Rejected: GNU's answer there is a
1,536-entry junk tree and exit 0. "POSIX behavior as floor, sovereign-design as ceiling" is what
this project says about exactly this situation, and the floor here is not a floor.

**A separate `src/lib/inodeset.cyr` module.** Rejected: the roadmap names `src/lib/fs.cyr`, the
helper is a filesystem primitive sitting beside the stat accessors it reads, and a new module is
three include-order edits (`src/main.cyr`, `tests/kriya.tcyr`, the bench) for no separation that
matters.
