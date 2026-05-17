# 0003 — Symlink-follow policy for destructive utilities

**Status**: Accepted
**Date**: 2026-05-17

## Context

M2 lands `cp`, `mv`, `rm`, `ln` — the utilities that turn symlinks from "a thing on disk" into a load-bearing security boundary. Every one of these can either operate on a symlink itself or on the target the link points to, and the choice of default is the single most consequential security knob in the multi-tool.

The threat is concrete: an attacker who controls a directory the utility traverses can drop a symlink pointing at any file the process can reach (`/etc/passwd`, `~/.ssh/authorized_keys`, the SQLite DB the agent just wrote). A "follow by default" policy turns `rm -rf workdir/` into "delete whatever any of those links point at." A "preserve by default" policy turns the same command into "delete the links; leave the targets untouched."

POSIX is uneven across the four utilities:

| Utility | POSIX default | Override flags |
|---|---|---|
| `cp` (single source) | follow the link, copy target contents | `-P` preserves |
| `cp -R` (recursion) | **implementation-defined** | `-H`, `-L`, `-P` |
| `mv` | operate on the link itself | (none) |
| `rm` | operate on the link itself; never recurse into a symlinked directory | (none) |
| `ln` (hard) | follow — hard-link the target | `-P` to link the symlink (where supported) |

GNU `cp -R` defaults to `-P` (preserve). BSD `cp -R` follows command-line symlinks (`-H`). The "implementation-defined" gap is where the kriya-defining choice goes.

ADR 0002 already committed kriya to an agent-safety bias on parsing. This ADR extends the same bias to filesystem semantics: when in doubt between "do what the path text says" and "do what the resolved target says," the path text wins.

## Decision

**Kriya follows POSIX where POSIX is specified; where POSIX is implementation-defined, kriya preserves symlinks. `rm` has no flag to follow symlinks under any circumstance.**

### Default behavior matrix

| Op | Symlink as single source argument | Symlink encountered during recursion | Symlink as destination |
|---|---|---|---|
| `cp` | **follow** (copy target's contents) — POSIX | **preserve** (copy the link, don't dereference) — kriya choice; matches GNU `cp -R` | follow (write through to target file) |
| `mv` | preserve (rename the link itself) — POSIX | n/a (rename is a single fs op) | follow if regular file; refuse to overwrite a symlink-to-directory |
| `rm` | preserve (unlink the link itself, never the target) — POSIX | preserve (unlink links; **never recurse into a symlinked directory**) — POSIX | n/a |
| `ln` (hard) | follow — hard-link the target — POSIX | n/a | n/a |
| `ln -s` | n/a (the source is text, not a path that's opened) | n/a | n/a |

### Override flags (POSIX-aligned)

- **`cp -P`** — preserve symlinks everywhere. With single-source `cp`, flips the default from "follow" to "copy the link itself." With `cp -R`, this is the default and `-P` is a no-op (accepted, idempotent).
- **`cp -L`** — follow all symlinks, including during recursion. The user has explicitly accepted the cross-link traversal.
- **`cp -H`** — follow only command-line symlinks during recursion; preserve those discovered by the walk. BSD-style.
- **`ln -P`** — hard-link the symlink itself instead of its target.
- **`mv`** — no follow/preserve flag. Rename always operates on the named entry. To "move a target," the user composes `cp -L src dst && rm src`.
- **`rm`** — **no flag exists to follow symlinks**. Not `-L`, not `--follow`, not any future addition. Documented as a Hard No-Go below.

### Hard rules (No-Gos)

1. **`rm` never follows.** Every `rm` operand is unlinked as a name. A symlink-to-directory is unlinked, not descended. A symlink-to-file is unlinked, not opened. `-r`/`-R` controls recursion into *real* directories only. There is no compile-time, runtime, env-var, or flag opt-in. The principle: a utility named `rm` should never be the cause of a target it doesn't textually name being destroyed.
2. **`cp -R` defaults to preserve.** The POSIX implementation-defined gap is closed in the safer direction. Agents and scripts can rely on `cp -R src/ dst/` not dereferencing links inside `src/`.
3. **`mv` refuses to overwrite a symlink-to-directory.** `mv foo bar` where `bar` is a symlink whose target is a directory exits with `EXIT_FAILURE` and a clear error. The user must `rm bar && mv foo bar` to express the intent. (Rationale: silent replacement of "the link points to a directory" with "now it's a regular file at the same name" surprises every consumer of the directory.)
4. **No `*at()` race on traversal.** Recursive walks use `openat(O_NOFOLLOW | O_DIRECTORY)` for each step, never `chdir` + relative open. This closes the TOCTOU window where a directory entry could be replaced with a symlink between the `lstat` that decided "this is a directory" and the `open` that descended into it.
5. **`O_NOFOLLOW` on destructive opens.** `rm`'s `unlink`/`unlinkat` paths are not vulnerable (unlink operates on names), but `cp`'s and `mv`'s open-for-write paths use `O_NOFOLLOW` on the final component when the policy says "preserve." A symlink at the destination is an error, not a silent target-write.
6. **No "warn on follow" mode.** Agents miscall on warnings. Either the operation follows (and the contract is clear) or it doesn't.

### Error messages

Per ADR 0002 Appendix B, parser errors have a fixed shape. Symlink-policy violations are operation errors, not parser errors, and use this form:

```
kriya <util>: <operand>: <message>
```

where `<message>` is one of:

- `is a symbolic link; -L required to follow` (cp without `-L` told to follow)
- `refusing to overwrite symbolic link to directory` (mv)
- `is a symbolic link; not descending` (informational, only emitted with `-v`)

Exit code on operation refusal: `EXIT_FAILURE` (1). Symlink policy is operation-semantic, not usage-error.

## Consequences

- **Positive**
  - **Agents can reason about destructive ops without seeing the filesystem.** `rm -rf workdir/` operates on names the agent generated. Whatever symlinks an adversarial process plants inside `workdir/` cannot turn the operation into a write outside `workdir/`.
  - **`cp -R` is safe to script.** A backup script that does `cp -R /home/user/project /backup/` does not silently inflate the copy by following symlinks to large external trees. The user can opt into `-L` when they specifically want the dereferenced content.
  - **No "did `rm` follow my symlink?" question.** The answer is always no. Removes a category of bug reports.
  - **`*at()` discipline is uniform.** Every traversal uses `openat(O_NOFOLLOW | O_DIRECTORY)`. One audit, one implementation in `src/lib/fs.cyr` (lands with M2).
- **Negative**
  - **Loss of GNU `cp` muscle memory for single-source.** Single-source `cp` still follows (POSIX), so `cp link target` copies the underlying file — same as everywhere. But `cp -R dir target` no longer follows, where some users expect GNU-coreutils-default behavior. Documented in `cp --help`.
  - **`mv` refusing to overwrite symlink-to-dir breaks one shell idiom.** Specifically: `mv newdir.tmp linkdir` where `linkdir` was a deploy-style "current" pointer. The user must explicitly `rm linkdir && mv newdir.tmp linkdir`, or use `ln -sfn newdir.tmp linkdir` to atomically retarget the link. ADR-worthy tradeoff; we take the explicit side.
  - **No escape hatch on `rm` follow.** A user who genuinely wants to delete a symlink target writes `rm "$(readlink -f link)"` or `rm "$(realpath link)"`. The verbosity is intentional — it forces the user to name the actual file being removed.
- **Neutral**
  - **`O_NOFOLLOW` on the final component of `cp` destinations** prevents the symlink-races but also rejects a workflow where the destination is itself a symlink the user wants to write through. The user opts in with `-L`. Documented per-utility.
  - **`find -print0 | xargs rm` (M5) inherits this policy** — `xargs` execs `rm`, which never follows. No cross-utility surprise.

## Alternatives considered

- **Follow by default, opt out with `-P` (GNU `cp` single-source default extended to recursion).** Rejected: implementation-defined POSIX gap is closed in the *more* dangerous direction; agent-callable destructive utilities cannot afford "the link points somewhere unexpected."
- **`rm --follow` flag, off by default.** Rejected: the flag exists eventually, the flag gets used in a CI script, the CI script runs against a directory an attacker controls, and the safety property is gone. The cost of having no flag at all is a small ergonomic loss against a real adversarial threat.
- **Per-invocation `KRIYA_FOLLOW=1` env var.** Same failure mode as a flag, plus env-var inheritance makes it accidentally apply to child processes. Rejected — ADR 0002 already rejected env-var bypasses for the same reason.
- **`rm --dereference` only when explicitly asked, gated by `--i-know-what-im-doing`.** Compounding flags as safety theatre. Either the operation is safe or it isn't; a long flag does not make a dangerous default acceptable. Rejected.
- **Match GNU `cp -R` (default to `-P`)** — this is the choice. It happens to match GNU for `cp` in particular; the broader principle ("preserve when POSIX is silent, refuse to follow on `rm`") is kriya's.

## Precedent

- **OpenBSD `rm`** — never follows symlinks; matches the kriya choice on `rm`. The OpenBSD reasoning ("the user named the link, not the target") is the same we adopt.
- **GNU `cp -R`** — defaults to `-P` since fileutils 4.0 (2000). Our `cp -R` matches.
- **POSIX `mv`** — operates on the name, not the target. We match POSIX and add the "refuse to overwrite symlink-to-dir" guard, which POSIX permits but does not mandate.

## References

- POSIX `cp`: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/cp.html
- POSIX `mv`: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/mv.html
- POSIX `rm`: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/rm.html
- POSIX `ln`: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/ln.html
- `openat(2)` / `O_NOFOLLOW`: https://man7.org/linux/man-pages/man2/openat.2.html
- ADR 0004 (companion): `rm` refuses to operate on `/` regardless of flags.
