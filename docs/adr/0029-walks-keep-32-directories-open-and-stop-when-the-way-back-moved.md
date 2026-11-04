# 0029 — A walk keeps 32 directories open, and stops when the way back up has moved

**Status**: Accepted; amended at 1.8.9 (every walk is a loop, and decision 5's stack guard is gone)
**Date**: 2026-11-03

## Context

Every recursive walk in kriya is fd-relative on Linux: it opens a directory from its parent's
descriptor and stats, opens and unlinks entries through it. ADR 0003 asks for that on every
destructive path, and ADR 0027 extended it to `find`. It closes the race in which a parent
directory is swapped for a symlink mid-walk.

The cost was one open directory per level, held until the level was done. Under the default
`ulimit -n 1024`, a tree deeper than **1,020** levels failed with *too many open files*, measured
at 1.8.3 and again at 1.8.5. `find`, `du`, `rm -r` and `grep -r` stopped there. `cp -R`, which
holds a source and a destination per level, stopped at **509**. GNU's `find`, `du`, `rm` and
`grep` (fts) have no depth limit. GNU `cp -R` walks full paths and stops at PATH_MAX, 2,040 levels.

⛔ `rm -r` was the one that mattered. Anyone who could make a 1,021-level tree in a shared
directory made it unremovable by kriya.

With descriptors raised out of the way, the recursion met the next limit, the stack. Under an
8 MiB stack, `cp -R` died of SIGSEGV between 8,000 and 12,000 levels, `du` between 12,000 and
16,000, and `find` and `rm -r` between 20,000 and 40,000. GNU `rm -r` and `du` removed and
measured a 100,000-level tree in 28 and 39 MB.

## Decision

**One walk module, `src/lib/walk.cyr`, holds every walk's open directories. A walk keeps at most
32 open. A directory closed early is reopened as `..` of the child the walk is leaving, and the
walk stops if that is not the directory it closed.**

1. **The budget.** Descending past 32 open directories closes the highest one. First it records
   the directory's identity (`fstat`: `st_dev`, `st_ino`), and it saves what the directory had
   left to read, including the entry the walker is inside. Its entries are then not lost with its
   read position, and the walker can still name the child it will remove or copy.
2. **The way back.** Leaving a level whose parent is closed reopens the parent as `..` of the
   level, before the level itself is closed. ⛔ If the reopened directory is not the recorded
   (`st_dev`, `st_ino`), a directory was moved during the walk. The walk stops, reports
   `kriya <util>: '<dir>': directory moved during the walk; stopping` and the operand fails
   (exit 1, `grep` 2). Carrying on would unlink, copy or report the entries of a directory the
   walk never entered. GNU stops too, measured: `rm: fts_read failed: No such file or
   directory`. ⚠ GNU stops the whole invocation, and kriya stops the operand. The others still
   run, as after any other per-operand failure.
3. **A followed symlink.** `..` of a directory reached through a symlink (`-L`) is its real
   parent, so the directory holding the link is never closed early. A path through more than
   about a thousand symlinked directories still meets the descriptor limit; GNU's `-L` walks stop
   at PATH_MAX there instead.
4. **Out of descriptors.** An open that fails with EMFILE or ENFILE asks every walk for a
   descriptor back, never its current level's, and retries. File opens use the same path. `cp -R`
   needs seven descriptors in all: the three standard streams, a source and a destination
   directory, and a file of each.
5. **The stack.** The recursive walks (`find`, `du`, `cp -R`, `grep -r`) do not enter a
   directory once they have used the soft RLIMIT_STACK, less a quarter for the arguments and
   environment, less 256 KiB for the deepest call's own frames. Such a directory is reported,
   `kriya <util>: '<dir>': directory nested too deeply to walk`, and the operand fails. It is not
   a crash. `rm -r` is a loop, not a recursion: its depth is bounded by memory alone.
   - ⭐ **Amended at 1.8.9: all five walks are loops**, and the guard is removed with the
     recursion. A walker keeps each directory's state in its level's four slots (`wk_u`) and its
     paths in the walk's one buffer (`wk_path_push`). Depth is bounded by memory alone: 100,000
     levels in 21–53 MB for each walk, measured at 1.8.9.
6. **agnos** has no open-relative-to-a-descriptor, so its walks open by path and nothing is
   closed early there.

⛔ **The rule this puts on every walker:** a descriptor, or an entry's name, fetched before a
descent is stale after it. The level may have been closed and reopened under a different
descriptor number, and the old number may by then name a deeper directory. Walkers fetch
`wk_fd`, and `wk_cur_name` where they need the name, again after every call that can descend,
and they iterate with `wk_next` only.

## Consequences

- **Positive**
  - `rm -r` removes a 100,000-level tree under `ulimit -n 1024`: 1.26 s and 20.7 MB, against GNU's
    1.40 s and 28.1 MB.
  - `find`, `du`, `grep -r` and `cp -R` pass the descriptor limit, and `cp -R` copies past
    PATH_MAX, where GNU's stops at 2,040.
  - A deep walk can no longer crash. `smoke-deep.sh` runs every walk under a 1 MiB stack.
  - Walks never hold more than 32 descriptors each. Each open is O_CLOEXEC, so a `find -exec`
    child sees what GNU's sees.
- **Negative**
  - **A kriya limit GNU does not have** (until 1.8.9). `find`, `du`, `cp -R` and `grep -r` stopped
    at the stack guard. Measured under an 8 MiB stack at 1.8.6, on one 25,000-level chain, the
    first directory each one refused was at level **15,701** for `find`, **14,494** for `grep -r`,
    **10,767** for `du` and **5,798** for `cp -R`. Each printed one diagnostic. ⭐ Gone at 1.8.9,
    when the four became loops.
  - A walk deeper than 32 levels does more work for each directory beyond the budget: an
    `fstat` and a read to the end on the way down, and an `openat("..")` and an `fstat` on the
    way back up. A walk within the budget reads exactly as it did.
  - A saved level holds its unread entries in memory. GNU's fts holds every directory on the path
    whole; this holds only the ones it closed.
  - A directory whose permissions change during the walk so that its `..` cannot be looked up
    stops the walk, with the errno reported against `'<dir>/..'`.
- **Neutral**
  - `find -empty` opens the directory relative to its parent, like every other open of the walk.
    It used to open by full path, so past PATH_MAX it failed with *file name too long*.

## Alternatives considered

- **Raise the soft RLIMIT_NOFILE.** The hard limit can equal the soft one, and every `-exec` child
  would inherit the raised limit.
- **Walk by full path**, as GNU `cp` does. That trades the descriptor limit for PATH_MAX, and it
  re-resolves every ancestor on every open, which is the race ADR 0027 closed.
- **Read every directory whole before descending**, as fts does. A walk within the budget would
  pay for memory it does not need. Saving only on close keeps the shallow case as it was.
- **`chdir` into each directory** (fts without FTS_NOCHDIR). kriya never changes its working
  directory: operands, `-execdir` and relative diagnostics all assume it stays put.
- **Make every walk a loop now.** `rm -r` is the one where a limit is a security problem, and it
  is a loop. The other four have recursive shapes their output order depends on, `find`'s
  `-depth` and `-prune` and `du`'s per-level totals. Converting them is a separate change, and
  until then the guard bounds them. ⭐ Done at 1.8.9.
- **Stop the whole invocation on a moved directory**, as GNU does. kriya's error model is per
  operand, and a moved directory is a property of one operand's tree.
