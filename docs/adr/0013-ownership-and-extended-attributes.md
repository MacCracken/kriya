# 0013 — Ownership and extended attributes: what a copy carries, and what it must drop

**Status**: Accepted
**Date**: 2026-08-27

## Context

[ADR 0012](0012-hard-link-awareness.md) turned `cp`'s `--preserve` into a bitmask and made `links`
mean what it says. Two of GNU's seven attributes were still refused by name: `ownership` and `xattr`.
Refusing was the honest interim answer — v1.2.1 established that accepting an attribute and silently
dropping it is worse than declining it — but it left three things unfinished, and the M8 security
audit had named all three as deferred rather than absent:

- **Row 35351** — cross-filesystem `mv` drops UID/GID to the caller's. Measured against GNU before
  this release: a file in a secondary group, moved across a filesystem boundary, keeps its group
  under GNU and loses it under kriya.
- **Row 35354** — cross-filesystem `mv` drops extended attributes, and the audit specifies the fix in
  advance: *"the implementation must use `fgetxattr`/`fsetxattr` on the source fd + destination fd,
  NEVER path-based `*at()` family with fresh lookups per call."*
- **Row 35350** — `cp` applying mode bits after a failed chown. Audited as "not exposed" in M8
  precisely *because* chown was not implemented. Implementing it exposes it.

Four things make this a real decision rather than a default:

**1. `-p` has to change meaning.** GNU's `-p` is `--preserve=mode,ownership,timestamps` and always
has been; kriya's was mode and timestamps. The two are indistinguishable until a fixture's group
differs from the caller's, which is why six releases went by without anyone noticing.

**2. The restore has to move.** kriya applied mode and timestamps *after* closing both descriptors,
re-resolving the destination by path. That is exactly the shape row 35354 forbids, and xattrs cannot
be added to it without inheriting the flaw. The descriptors have to stay open across the restore.

**3. The failure case is the common case, and it is silent.** A non-root caller cannot chown to
another user. Measured: `cp --preserve=ownership /etc/hostname out` exits **0** with **no output**
and a destination owned by the caller. GNU only complains when it had the privilege to succeed and
still failed. An implementation that reported an error here would be noisier than the oracle on an
everyday command.

**4. And the silence has a price that must be paid.** ⛔ When ownership was requested and could not be
set, the set-id bits must come off. Otherwise `cp -p /usr/bin/passwd ./mine` yields a **setuid binary
owned by the copying user, made out of one that was not.** Measured: GNU yields mode 755 there, and
mode 4755 for `cp --preserve=mode` of the same file. The difference is not cosmetic and it is not
optional.

## Decision

**`--preserve=ownership` and `--preserve=xattr` are implemented; `-p` gains ownership to match GNU;
and every metadata restore moves to the OPEN DESCRIPTOR, applied in the order ownership → xattrs →
mode → times, with the set-id bits cleared whenever ownership was requested and not fully set.
Cross-filesystem `mv` carries all four, best-effort. The `system.` namespace is excluded from the
xattr copy, and POSIX ACLs — which GNU carries through MODE preservation, not through xattrs — are a
named gap rather than a silent one.**

### The restore is fd-anchored, and the order is the security property

`_cp_restore_fd(dst_fd, src_fd, src_st, preserve, …)` runs between the copy loop and the closes, in
`_cp_one`, `_cp_file_at` and `_cp_dir_descend_at` alike:

1. **ownership**, `fchown` — *before* the mode. After it, a file already carrying set-id bits would
   change owner, which is row 35350.
   ⛔ **And before the xattrs, which is not obvious and cost a defect.** A chown sets
   `ATTR_KILL_PRIV` on every non-directory, so the kernel strips `security.capability` — meaning
   attributes written *before* the chown are destroyed *by* it. The first version of this function
   wrote them first, on the reasoning that setting an attribute needs write access; measured, a file
   carrying `security.capability` kept it under GNU and lost it under kriya.
   ⭐ **A chown that would change nothing is skipped**, which is the other half: the strip happens
   even when the ids are identical, so an unconditional "preserve" call destroys a capability it was
   asked to keep. GNU guards on `SAME_OWNER_AND_GROUP` for its own reasons and gets this for free.
2. **xattrs**, `fgetxattr`/`fsetxattr` from source fd to destination fd — the audit's requirement.
3. **mode**, `fchmod` — with the clearing rule below.
4. **times**, `utimensat(fd, NULL, …)` — the `futimens` form, last so nothing above moves the mtime.

⭐ Directories take the same path. All four calls work on an `O_RDONLY|O_DIRECTORY` descriptor: the
kernel checks them against the inode's permissions, not the descriptor's open mode. And the restore
still runs after every child is written, so the directory's own mtime is not bumped — it simply runs
before the close instead of after.

⚠ **Symlinks are the one exception, by argument.** A symlink has no descriptor to hold — `open`
follows it — so `_cp_symlink_meta` uses `fchownat`/`utimensat` with `AT_SYMLINK_NOFOLLOW`. That is
still anchored: `(dirfd, name)` resolves exactly one component against a directory the walk already
has open, the same shape as the `symlinkat` that created the link. Symlinks carry ownership and
timestamps, and neither mode (meaningless on Linux) nor xattrs (the kernel refuses `user.*` on a
symlink outright — measured, EPERM even as the owner).

### The set-id clearing rule, and the bit nobody expects

**Clear S_ISUID, S_ISGID *and* S_ISVTX when ownership was REQUESTED and could not be fully set.**
Mask `511` (0o777).

⛔ The sticky bit is in that list, and it was not obvious. POSIX names only setuid and setgid; GNU
takes the third as well. Measured: `cp -pR /var/spool/mail out` — a root-owned 1777 directory —
yields **777** under GNU, while `cp --preserve=mode -R` of the same source yields **1777**.

⚠ The first implementation masked with 1023 (0o1777) and kept sticky, and **the test written beside
it could not see the difference**: it used a sticky file the caller *owned*, where the chown succeeds
and nothing is dropped at all. That test passed against both masks. The fixture has to be
foreign-owned for the assertion to mean anything.

⚠ The rule keys on the REQUEST, not on the caller. `--preserve=mode` of the same unownable file keeps
4755, because no chown was attempted and there is nothing to compensate for.

### An ownership failure is silent, and a group-only retry happens first

On `EPERM`, `fchown(fd, uid, gid)` is retried as `fchown(fd, -1, gid)` — a caller who cannot become
the owner still keeps the group when it is one of theirs. ⛔ It does **not** count as ownership
preserved: the set-id bits still come off.

⚠ The retry is **reasoned from GNU's source and confirmed by an independent syscall trace**, not by a
fixture of our own: constructing the case needs a file owned by someone else whose group the tester
is in, which needs root to create. A `ptrace`-based tracer written for this release recorded GNU
doing exactly `fchown(4, 100000, 1000) = -EPERM` followed by `fchown(4, -1, 1000) = 0` and then
`fchmod`, which also confirms chown-before-chmod at the syscall level.

### A plain copy carries no set-id or sticky bits either

⛔ Found by the differential fuzz, and older than this release: the kernel drops setuid and setgid on
an unprivileged `open(O_CREAT)` but **keeps S_ISVTX**, so a plain `cp` of a 1755 file produced a 1755
destination where GNU produces 755. The destination file's creation mode is now masked to 0o777
whenever mode is not being preserved. ⚠ Directories are different and measured: `cp -R` of a 1777
directory keeps the sticky bit under GNU too, so only the file path masks.

### ⛔ `system.*` is excluded, and an xattr failure is only an error when asked for by name

**`system.posix_acl_access` IS an extended attribute**, so a walk that copies every name copies the
ACL — and setting it **changes the destination's effective permissions**. Measured: a 0600 file with
`g:docker:rwx` copied with `--preserve=xattr` came out **0670 with the ACL** under kriya and **0650
with none** under GNU, which excludes the namespace through libattr's `/etc/xattr.conf`. The whole
`system.` namespace is skipped. ⚠ `security.*` is **not** excluded — GNU carries
`security.capability`, measured.

**"Carry xattrs" and "an xattr failure is an error" are separate bits**, because GNU treats the two
spellings differently and the difference loses data. `cp --preserve=xattr` onto a filesystem with no
xattr support reports and exits 1; `mv` across the same boundary says **nothing**, exits 0 and
removes the source. Without the split, kriya's `mv` failed the restore, returned before the unlink,
and **left the file in both places** — a move that did not move. Measured against a ramfs
destination.

### xattr failures are reported and exit non-zero

⚠ Measured asymmetry in GNU: an unsettable attribute under an explicit `--preserve=xattr` prints
`cp: setting attribute 'user.big' for '…': No space left on device` and exits **1**, while the same
failure under `-a` is silent and exits 0. kriya has no `-a` yet (roadmap 1.6.2), so only the explicit
form exists and it reports.

⚠ kriya's message names the DESTINATION where GNU's names the attribute twice
(`for 'user.big'` where the filename should be) — a formatting bug in libattr's error path, not a
rule worth copying.

⚠ A source on a filesystem with no xattr support answers `ENOTSUP` to the listing, and that is "there
is nothing to copy", not a failure — otherwise `cp --preserve=xattr` over an ordinary tree would
report an error on every file.

### `context` and `all` stay refused

`--preserve=all` implies SELinux `context`, which kriya does not carry. Accepting `all` and quietly
skipping the security label would be the v1.2.1 lie in a more dangerous place. Both remain exit 2
with the attribute named.

### Two guards that had nothing to do with attributes, and one that did

⛔ **A cross-filesystem `mv` merged into a non-empty destination directory** — overwriting same-named
files, exiting 0 and removing the source — while the *same command on one filesystem refused*. The
same-filesystem arm inherits `ENOTEMPTY` from `rename()`; the cross-filesystem arm is a `cp -R -f`
plus an `rm -r` and inherited nothing. ⚠ The lesson generalises past this bug: **where one arm is
implemented by a syscall and the other by hand, list what the syscall was enforcing.**

⛔ **A set-id destination existed, fully privileged, before a byte was written.** The bits are now
withheld at create time and put back by the restore. Safe precisely because `--preserve=mode`
guarantees an `fchmod` at the end — starting narrower costs nothing when the widening is certain.

⭐ **An ownership failure is reported when `geteuid() == 0`.** GNU draws the line at privilege, not at
whether the call could have worked: an unprivileged `cp -p` of a root-owned file is an everyday
command that cannot preserve ownership, while a root-run backup that silently changed an owner needs
to hear about it. ⚠ Testable on an unprivileged runner — inside `unshare -Ur` the caller is uid 0
while a root-owned file outside appears as the unmapped 65534, so the chown fails `EINVAL` with full
`CAP_CHOWN` in hand.

### What kriya does NOT carry: POSIX ACLs

⛔ **GNU copies a POSIX ACL as part of MODE preservation** — its own `copy_acl`, a separate path from
the xattr copy — so `cp -p` and `cp --preserve=mode` both carry it while `--preserve=xattr` does not.
kriya has no ACL path, and the `system.*` exclusion above (which is right for the xattr path) leaves
nothing carrying it.

⚠ **The consequence is a silent over-grant, not merely a missing feature.** The source's `st_mode`
group bits ARE the ACL mask, so copying the mode literally gives the destination's own group the
*mask's* permissions where GNU gives it the *group entry's*. Measured on a 0640 file with
`g:<grp>:rwx`: GNU's copy is `group::r-- group:<grp>:rwx mask::rwx`, kriya's is `group::rwx` — and
**both report `st_mode` 0640**, which is exactly why nothing noticed until a fuzz fixture grew an
ACL. Asserted as kriya's own answer in the smoke suite and counted separately by the fuzz rather than
hidden; closing it wants its own ADR, because the mode↔mask interaction is the whole difficulty.

## Consequences

- **Positive** — three M8 audit rows close. `cp -p` means what GNU's means. Cross-filesystem `mv`
  stops silently downgrading a file's group and losing its attributes, which is the shape that makes
  a move differ from a rename. The restore path is fd-anchored throughout, which removes a class of
  substitution race rather than one instance. ⭐ A differential fuzz over the full `--preserve=`
  matrix — 18 flag combinations × recursive and not, over 90 random trees carrying setuid, setgid,
  sticky, secondary-group ownership, past timestamps, extended attributes and hard-link groups —
  reports **0 divergences in 3,240 comparisons**, with 880 of them classified as the documented POSIX
  ACL gap rather than dropped from the corpus.
- **Negative** — `-p` now changes ownership where it did not, which is a behaviour change for any
  script relying on the old meaning; the migration is `--preserve=mode,timestamps`. Two new syscall
  families (`fchown`/`fchownat`/`fchmod`, and the three xattr calls) are now kriya's to keep working
  on both targets, and agnos supports neither — both gate on new `K_HAVE_*` flags and return
  `-ENOSYS` there. The xattr copy allocates two scratch buffers that grow to the largest attribute
  seen in a walk and are never released.
- **Neutral** — the destination *directory* is still created at the source's full mode, so a
  permissive umask leaves it world-writable for the duration of a recursive copy. The file half of
  that window is closed (set-id bits withheld at create, restored by the `fchmod` that
  `--preserve=mode` guarantees); the directory half needs an unconditional restore kriya does not
  have, and is filed rather than half-done.

## Alternatives considered

**Keep the restore path-based and add xattrs to it.** Rejected outright: it is the exact pattern the
M8 audit names in advance, and the fix was written down before the feature was.

**Leave `-p` as mode+timestamps and expose ownership only as `--preserve=ownership`.** Rejected: `-p`
is the spelling almost everyone uses, GNU has always included ownership in it, and a `-p` that
quietly means less than the oracle's is the same accepts-and-lies shape one level up.

**Clear only setuid and setgid, as POSIX says.** Rejected on measurement: GNU clears the sticky bit
too, and the oracle is what this project matches. POSIX is the floor.

**Report ownership failures.** Rejected on measurement: GNU is silent for an unprivileged caller, and
`cp -p` of a root-owned file is an everyday command. Being noisier than the oracle on the common path
is a worse failure than being quiet on the rare one.

**Copying every attribute `flistxattr` returns.** Rejected on measurement: it carries the POSIX ACL,
which changes the destination's permissions. ⚠ The exclusion is by namespace rather than by an
allow-list of known names, because an allow-list would silently drop attributes nobody thought of —
and `security.capability`, which GNU does carry, would have been one of them.

**Implement `--preserve=all` by treating `context` as a no-op.** Rejected: silently skipping a
security label is the one place the accepts-and-lies pattern is actively dangerous.
