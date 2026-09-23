# 0021 — `cp -f` replaces a destination it cannot open

**Status**: Accepted
**Date**: 2026-09-22

## Context

kriya's `cp` refuses to overwrite an existing destination unless `-f` is given (CLAUDE.md: *no silent
file overwrites without `-f`*). So in kriya `-f` has always meant "replacing this is intended". GNU
gives `--force` a second, narrower meaning: *if an existing destination file cannot be opened, remove
it and try again*.

The two diverged exactly where that second meaning applies. Measured against GNU 9.11, all with the
destination directory writable:

| destination | GNU `cp -f` | kriya `cp -f` until 1.6.13 |
|---|---|---|
| a 0400 file | exit 0, replaced | `permission denied`, exit 1 |
| a running executable (ETXTBSY) | exit 0, replaced | `text file busy`, exit 1 |
| a symlink to a 0400 file | exit 0, the link replaced by a file | `permission denied`, exit 1 |
| a 0400 file inside a `-R` copy | exit 0, replaced | `permission denied`, exit 1 |

`mv` inherits the same copy for a cross-filesystem move, so `mv` onto a read-only destination on
another filesystem exited 1 and left the source in place, where GNU's `mv` exits 0.

What makes this a decision rather than a patch: **it deletes a file the caller could not write to.**

## Decision

**`cp -f` removes an existing destination it cannot open for writing, then creates it afresh**, as
GNU's `--force` does:

- The retry happens after a failed open of a destination that existed, for any error **except ENOENT**
  (nothing to remove) **and EISDIR** (`-f` never turns a directory into a file).
- The removal is `unlink` on the name. The re-creation is **`O_CREAT | O_EXCL`**, with `O_NOFOLLOW`
  in the `-R` walk, so anything that reappears at the name in between is refused, not written
  through.
- A removal that fails — the directory is not writable, or it is sticky and the file is not the
  caller's — is reported as `kriya cp: cannot remove 'DST': REASON` and fails the operand, with the
  destination untouched.
- `-v` reports it with GNU's wording, `removed 'DST'`, after the `'SRC' -> 'DST'` line, the order GNU
  uses.

The same rule covers both copy paths (`_cp_one` for an operand, `_cp_file_at` for each entry of a
`-R` walk). It absorbs the one case kriya already retried: a symlink destination that `O_NOFOLLOW`
refused.

## Consequences

- **Positive** — every case in the table matches GNU, and `mv` across filesystems onto a read-only
  destination moves.
- **Positive** — nothing new is granted. Unlinking a name needs write permission on the directory, not
  on the file, which is the same permission that already lets the caller `rm` it. A sticky directory
  such as `/tmp` still protects other users' files: the unlink fails with EPERM and nothing changes.
- **Negative** — **a new inode, not the old one.** Every other name hard-linked to the old destination
  keeps the old bytes. The new file is owned by whoever ran `cp`, with the source's mode, where an
  in-place overwrite keeps the old inode's owner and mode. GNU behaves the same; it is stated here
  because it is the part a caller might not expect.
- **Negative** — not atomic. Between the unlink and the create, the name does not exist, as with GNU.
  A caller who needs the name to exist throughout wants a copy to a temporary name followed by a
  rename, which is `install`'s shape, not `cp`'s.
- **Neutral** — `-b` is unaffected: a backup renames the destination away before the open, so there is
  nothing left to remove. This path never prompts, because in kriya `-f` skips `-i`'s prompt
  (CLAUDE.md: "`-f` overrides"). ⚠ That is itself a pre-existing divergence, not something this ADR
  decides: GNU's `cp -fi` still asks.

## Alternatives considered

- **Keep refusing.** Rejected. `-f` already says "replace this". Refusing a replacement the caller has
  the directory permission to perform is a parity gap with no safety benefit, because `rm` followed
  by `cp` does the same thing in two commands.
- **Retry on EACCES only.** Rejected. ETXTBSY, replacing a binary that is running, is the case
  install-like scripts meet most. GNU retries on every failure except ENOENT, and a narrower rule
  would be a divergence that looks like a bug.
- **Write to a temporary name and rename over the destination.** Rejected for `cp`. It is atomic, but
  it changes the success path too: every overwrite becomes a new inode, and a hard-linked destination
  would never be updated in place. That is `install`'s contract, and `cp` has never had it.
