# 0014 — kriya's symlink-traversal limit is the kernel's, uniformly

**Status**: Accepted
**Date**: 2026-08-27

## Context

`fs_realpath` follows symlinks. Something has to stop it, because a cycle never
terminates. The obvious choice is "whatever GNU does", and 1.6.2's `ln -sr`
differential fuzz — once its corpus was extended to contain symlink cycles at
all — reported kriya and GNU landing on *different* links inside the same cycle.

Measuring both implementations rather than assuming produced a result that is
not the shape the divergence report suggested. Cycles of length 3, 5, 6, 7, 9,
11, 13, 17 and 41 pin the stopping point exactly, because the name a
canonicalisation gives up on identifies the traversal count modulo the cycle
length:

| | inside a cycle | a straight chain of N links |
|---|---|---|
| Linux `open(2)` | ELOOP after 40 | ELOOP past 40 |
| kriya `fs_realpath` | stops after 40 | refuses past 40 |
| GNU `realpath` / `realpath -m` | stops after **20** | resolves **any N** — measured to 121 |

⛔ **The chain column is the important one, and it is a GNU defect, not a kriya
one.** For a 61-link chain, GNU's `realpath` prints `target` — and GNU's own
`cat` cannot open that same name, because the kernel refuses at 40. `realpath`
exists to answer *what does this name refer to*; an answer that no `open(2)`
will honour is worse than an error.

The cycle column is the harmless one. Every answer inside a cycle is a name that
cannot be resolved by anybody; the two implementations disagree only about which
unresolvable name they print.

## Decision

kriya's symlink-traversal limit is **40, the kernel's**, applied uniformly to
every `fs_realpath` mode.

- **Strict modes** (`FS_REALPATH_REQUIRE_ALL`, `FS_REALPATH_REQUIRE_PARENT`) —
  exceeding it is `ELOOP`. So `realpath`, `realpath -e` and `readlink -f`/`-e`
  refuse exactly the names the kernel refuses.
- **`FS_REALPATH_ALLOW_MISSING`** — exceeding it stops the traversal and keeps
  the path resolved so far, which is what `realpath -m`, `readlink -m` and
  `ln -sr` need in order to answer at all. ⚠ The counter is per call and never
  resets, so declining to follow any further link still terminates.

The consequence we accept: for a name inside a symlink cycle, `realpath -m`,
`readlink -m` and `ln -sr` print a different unresolvable name than GNU does.

## Consequences

- **Positive** — `realpath` never reports a path the kernel will not open. The
  answer and `open(2)` agree, which is the property the utility is for.
- **Positive** — one limit, one constant, three modes. GNU's behaviour is not
  expressible as a single number: it is unbounded in one direction and 20 in the
  other.
- **Negative** — a documented divergence from GNU, and the `ln -sr` differential
  fuzz has to count it apart rather than assert equality. That is a corpus the
  next person must not "fix" by loosening the oracle everywhere.
- **Neutral** — if a consumer ever needs GNU-identical cycle output, the change
  is one constant in `fs_realpath` plus the strict-mode error boundary, and this
  ADR is the thing to supersede.

## Alternatives considered

- **Match GNU exactly (unbounded chains, 20 in a cycle).** Rejected: it requires
  reproducing a behaviour whose chain half prints unopenable paths. Copying a
  defect to score a fuzz run green is the wrong trade.
- **Match GNU's 20 in cycles only, keep 40 for chains.** Rejected: "20 inside a
  cycle" is not implementable as a rule, only as an outcome — you cannot know
  you are in a cycle without detecting the cycle, and if you detect it you stop
  at the repeat, not at 20.
- **Detect the cycle and stop at the first repeated component.** Rejected for
  this release: it is strictly better than a counter *and* diverges from GNU
  more than the counter does, so it buys a second divergence to remove one. It
  also needs a visited-set allocation on a path that currently allocates
  nothing. Worth revisiting if `fs_realpath` ever grows one for another reason.
- **Weaken the fuzz oracle so any two answers inside a cycle compare equal.**
  Rejected: that hides the next real defect in the same code. Counted apart
  instead, the way the `cp` fuzz counts the POSIX-ACL gap.
