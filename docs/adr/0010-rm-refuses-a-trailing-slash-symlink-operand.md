# 0010 — `rm -r link/` is refused rather than half-completed

**Status**: Accepted
**Date**: 2026-08-25

## Context

A trailing slash on a symlink is POSIX-defined to resolve to the linked-to directory, so `link/`
names the directory, not the link. `rm -r link/` therefore reads as "remove the directory `link`
points at."

What actually happens — in GNU `rm` and, until this ADR, in kriya — is worse than either "follow" or
"refuse":

```
ln -s real link
rm -r link/          # rm: cannot remove 'link/': Not a directory
```

The command **empties `real/`** and then fails to unlink `link` itself, because `link/` is not a
directory to `unlinkat(AT_REMOVEDIR)`. Verified identical in both implementations: `real/` loses
`data.txt` and `sub/x.txt`, the symlink survives, and the exit status is non-zero.

So the operation reports failure *after* having destroyed the data. The user sees an error, checks
that `link` is still there, and reasonably concludes nothing happened.

This also sits directly against kriya's own rule. ADR 0003 hard rule #1 is that `rm` never follows
symlinks and that no flag opts in. CLAUDE.md states it as a project-wide constraint: *"by default,
kriya utilities do NOT follow symlinks on destructive operations."* The trailing slash is a
POSIX-blessed way to follow one, and kriya was honouring the letter of POSIX over its own stated
safety floor — on the utility its own rules single out as "the most dangerous."

## Decision

**`rm` refuses an operand whose final component, after stripping trailing slashes, is a symlink and
whose original form carried a trailing slash.** It is reported per-operand and skipped; other
operands still run; the invocation exits 1.

`rm -r link` (no trailing slash) is unchanged and unlinks the link itself, which is both POSIX and
ADR 0003.

The refusal is not conditional on `-r`, `-f` or `-i`. There is no flag that opts in — the same shape
as ADR 0004's root refusal, and for the same reason: an escape hatch on a destructive verb
propagates by copy-paste.

## Consequences

- **Positive** — the half-completed destruction is gone. `rm -r link/` now either does nothing and
  says so, or is rewritten by the user into something unambiguous.
- **Positive** — kriya's behaviour and kriya's documented symlink policy agree. ADR 0003 stops having
  a POSIX-shaped hole in it.
- **Negative** — **a deliberate divergence from GNU**, which performs the half-completed removal. A
  script that relied on `rm -r link/` to clear a linked-to directory now fails. That script was
  relying on data destruction reported as an error, so we consider breaking it correct; the
  diagnostic names the alternative explicitly.
- **Negative** — one more shape a user has to know about. Mitigated by the error message spelling out
  both intents: remove the link with `rm link`, or the target with `rm -r <target>`.
- **Neutral** — creates a small asymmetry with `cp -R link/` and `ls link/`, which still follow. That
  is intended: ADR 0003 scopes the no-follow rule to *destructive* operations, and `cp`/`ls` do not
  destroy the target.

## Alternatives considered

- **Match GNU exactly (status quo).** Rejected: it destroys data and then reports failure. Every
  other decision in this repo about `rm` has chosen the safe side of exactly this trade (ADR 0004).
- **Follow the link and remove the target's contents *and* the link.** This is the "do what POSIX
  says the path means" reading, and it makes the operation complete rather than half-done. Rejected
  because it makes `rm -r link/` a whole-tree deletion whose reach is invisible at the call site —
  the operand names a link, and one character decides whether a directory somewhere else is emptied.
  ADR 0003 exists to prevent precisely that.
- **Refuse only under `-r`.** Rejected: `rm link/` without `-r` fails today anyway, and a rule that
  applies sometimes is a rule nobody remembers. Uniform is cheaper to reason about.
- **Warn and proceed.** Rejected: a warning on a destructive operation that has already been decided
  is decoration. kriya's `-i` exists for the case where the user wants to be asked.
