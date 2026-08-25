# 0009 — `mv` never rolls back a completed cross-filesystem copy

**Status**: Accepted
**Date**: 2026-08-25

## Context

`mv` across filesystems cannot use `rename(2)`. kriya implements it the way every `mv` does: copy the
source to the destination, then remove the source. Two steps, either of which can fail.

`_mv_cross_fs` rolled back — deleted the destination — when **either** step failed. The comment
justifying it said the goal was that "the user doesn't end up with two authoritative trees." That
reasoning is sound for one of the two failures and catastrophic for the other, and the difference is
not obvious from the code:

- **The copy failed.** The source is untouched and complete; the destination is a partial, useless
  fragment. Deleting it loses nothing and leaves the filesystem tidy. The rollback is right.
- **The copy succeeded and the source removal failed.** The source removal is `_rm_dir_at`, a
  *recursive* walk that can **partially** succeed — drain most of a tree and then fail on one entry
  it cannot unlink. At that point the destination is the only complete copy of everything already
  removed. Deleting it destroys the data outright.

This is not theoretical. Measured on a source whose *parent* directory is unwritable, so the final
`rmdir` of the source fails after its contents are gone:

```
mkdir -p ro/tree/sub; echo A > ro/tree/a.txt; echo B > ro/tree/sub/b.txt
chmod 555 ro                       # parent unwritable -> the final rmdir fails
kriya mv ro/tree /other-fs/moved
```

Result: `ro/tree` empty, `/other-fs/moved` deleted, **`a.txt` and `b.txt` gone from the filesystem
entirely**. GNU `mv` on the identical tree reports `cannot remove '…/tree': Permission denied`, exits
1, and **keeps both files in the destination**.

The same shape exists for a single regular file, though it is benign there: if `unlink(src)` fails
the source is still whole, so deleting the destination loses nothing. It still diverges from GNU
without buying anything.

## Decision

**Once the copy has completed successfully, `mv` never deletes the destination.** A failure in the
source-removal step is reported and returns non-zero; whatever was copied stays.

The rollback is kept for the case it was written for: **a failed copy**, where the source is intact
and the destination is a fragment.

This applies to both the directory and the regular-file branches of `_mv_cross_fs`, so the rule is
one sentence rather than a per-branch judgement.

## Consequences

- **Positive** — the unbounded failure mode is gone. The worst outcome becomes "two copies exist,
  and `mv` told you it could not remove the source," which is visible, recoverable, and exactly what
  GNU does.
- **Positive** — kriya converges with GNU on `mv` failure semantics, so the smoke suite can use GNU
  as an oracle here instead of asserting kriya-specific behaviour.
- **Negative** — a partially-drained source plus a complete destination is a genuinely messy state
  for the user to clean up. We accept mess over loss.
- **Negative** — the "two authoritative trees" concern the original code named is real and now
  unmitigated. It is the lesser harm: two trees are *visible*, and the user is told.
- **Neutral** — `mv`'s exit status on this path becomes load-bearing (it is how the user learns the
  source survived), so it is asserted in `scripts/smoke-mv.sh` rather than left implicit.

## Alternatives considered

- **Keep the rollback but make the source removal all-or-nothing.** There is no such primitive. A
  recursive removal is inherently partial once it starts, and pre-flighting the whole tree for
  removability is both racy and unbounded in cost.
- **Roll back only when the source removal removed nothing.** Requires the removal to report how far
  it got, and gets the boundary case exactly wrong: one file drained is enough to make the rollback
  destructive. The distinction adds machinery to preserve a behaviour that is wrong anyway.
- **Copy to a temporary name and rename into place at the end.** Solves a different problem (torn
  destinations), not this one — the source-removal failure still happens after the copy is durable.
- **Refuse cross-filesystem directory moves entirely.** Too strict; the operation is routine and
  POSIX-sanctioned, and refusing it would push users to `cp -R && rm -r` by hand, which has the same
  failure mode with no diagnostic at all.
