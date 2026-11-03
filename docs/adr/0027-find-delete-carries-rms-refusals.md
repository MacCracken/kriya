# 0027 — `find -delete` carries `rm`'s refusals, and deletes from the directory the walk opened

**Status**: Accepted
**Date**: 2026-11-03

## Context

`find -delete` is a second way to delete a tree. kriya's `rm` refuses three shapes that destroy data
outside the tree the user named:

- `/` and anything else protected. [ADR 0004](0004-rm-refuses-root.md) refuses the whole invocation,
  and there is no escape hatch.
- A symlink operand with a trailing slash. [ADR 0010](0010-rm-refuses-a-trailing-slash-symlink-operand.md):
  `link/` resolves to the target, so GNU empties the target and then fails on `link/`.
- Following any symlink at all. [ADR 0003](0003-symlink-follow-policy.md) hard rule 1 says `rm` never
  follows a symlink, and no flag opts in.

GNU `find -delete` has none of these refusals. Measured against findutils 4.9 and 4.10, which agree on
all 18 cases kriya's suite runs:

- `find -L t -delete`, with `t/lnk -> ../real`, **deletes `real/keep`, which is outside `t`**. It then
  reports `cannot delete 't/lnk': Not a directory` and exits 1. That is ADR 0010's shape: data
  destroyed, an error reported, the link still there.
- `find rlink/ -delete` empties `real/` the same way, then fails on `rlink/`.
- `find -H rlink -delete` follows the starting point, with the same result.
- `find / -delete` has no root check at all.

A deletion path that lets these through is a hole in all three ADRs.

There is also a race. kriya's `find` walked by full path: it stat'd and opened `t/a/b` from
`AT_FDCWD`. Suppose a parent such as `t/a` is swapped for a symlink after the walk has entered it.
The next full-path open or unlink then resolves through the symlink and lands outside the tree. That
is the classic `find -delete` race. CLAUDE.md requires the `*at()` calls on destructive paths for
exactly this reason, and `rm -r` already uses them.

## Decision

**`-delete` carries `rm`'s refusals. On Linux it deletes with `unlinkat(parent_fd, name)` from the
descriptor the walk opened the parent with.**

- **`-L` with `-delete` is a usage error** (exit 2): *-delete refuses -L: it would delete through
  symlinks, outside the tree (ADR 0027)*. Nothing is touched.
- **A protected starting point refuses the whole invocation** (exit 2), before anything is touched. It
  is the same `is_protected_path` check, and the same atomicity, as `rm`'s ADR 0004 refusal. `find /`,
  `find .` with `/` as the cwd, and `find t /` are all refused.
- **A slashed symlink starting point is refused per starting point** (ADR 0010; exit 1, the other
  starting points still run). This uses the same check as `rm`, `protected_is_slashed_symlink`, which
  now lives in `src/lib/protected.cyr`. So does a starting point that is a symlink under `-H`, which
  GNU follows to the same end.
- **Under `-P`, a symlink is unlinked as a link** (the walk's stat is an lstat), as GNU does and as
  ADR 0003 requires.
- **The walk is fd-relative on Linux**, for every `find`, not only `-delete`. Each entry is stat'd and
  opened relative to its parent's open directory (`O_NOFOLLOW` unless following), and `-delete`
  unlinks it there with `AT_REMOVEDIR` for a directory. An entry is therefore always the one inside
  the directory the walk actually opened. `smoke-find.sh` pins this with a mid-walk swap: an `-exec`
  replaces `t/a` with a symlink to `../outside` on the first entry. `outside/` keeps all eight files,
  and a mutant that unlinks by full path deletes them.
- **agnos keeps the full path.** It has no open-relative-to-fd and no symlinks, so there is no swap to
  defend against.

Everything else follows GNU, case for case. `-delete` is an action (no implicit `-print`). It turns on
`-depth`. It is true when the entry is gone. A failure is reported and makes `find` exit 1. A starting
point spelled exactly `.` is emptied and kept. `./` and `t/.` get EINVAL from the kernel, as under GNU.
GNU refuses a `-prune` without an explicit `-depth`, and kriya refuses it with GNU's own message, but
exits 2, kriya's usage code, where GNU exits 1. A failure reads `kriya find: t/a: cannot delete:
directory not empty`, in architecture 001's frame.

## Consequences

- **Positive**: kriya has no deletion path that is weaker than `rm`, and `find -delete` cannot be
  raced out of the tree. The fd-relative walk also lifts the `PATH_MAX` ceiling on the walk's own
  stats and opens. The printed path can still be longer than any one call accepts.
- **Negative**: three GNU behaviours are refused rather than reproduced: `-L -delete`, a slashed
  symlink start, and a symlink start under `-H`. A script that relied on GNU deleting through a
  symlink has to name the target directly. That is the same migration ADR 0010 asks of `rm`.
- **Neutral**: the walk holds one descriptor per directory level, as it already did.

## Alternatives considered

- **Follow GNU exactly.** Rejected. Each GNU behaviour refused here is the ADR 0010 shape, and
  CLAUDE.md singles out deletion as the place where correctness is not negotiable.
- **Refuse only a symlink that is actually followed, at the moment it is followed.** It is more
  permissive, but under `-L` the walk would have already deleted inside the target by the time a
  later entry tells it so. Deciding before the walk is the only shape that touches nothing.
- **Make only `-delete` fd-relative.** The unlink would be safe, but the descent opens each child by
  path, and the race is in the descent. One walk for every `find` is simpler than two.
