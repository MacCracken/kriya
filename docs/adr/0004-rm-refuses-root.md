# 0004 — `rm` refuses to operate on `/` — no escape hatch

**Status**: Accepted
**Date**: 2026-05-17

## Context

`rm -rf /` is the canonical worst case. The command exists in muscle memory, in tutorials, in copy-pasted shell scripts, and in agent training data. The cost of executing it on a running system is the system itself.

GNU `rm` mitigates this with `--preserve-root` (on by default since coreutils 6.2, 2006) and `--no-preserve-root` as the opt-out. The mitigation has a soft underbelly: the opt-out flag exists, it is documented, it shows up in scripts when someone is "sure they know what they're doing," and once it's in a script, it propagates by copy-paste. Several real-world catastrophes (a `cd $A && rm -rf --no-preserve-root /${B:?}` where the variables expanded wrong) trace to the existence of the escape hatch, not to the absence of one.

kriya runs on AGNOS. The expected callers are humans at a shell, package managers (zugot recipes), build systems, schedulers, and LLM agents. Of those, exactly zero have a legitimate need to bulk-delete the running filesystem root:

- **Package managers** delete specific files and replace them — `rm /usr/bin/oldtool && ln -s kriya /usr/bin/oldtool`. The operand is a named file or directory, never `/`.
- **Build systems** operate inside a build tree — `rm -rf build/`, never `rm -rf /`.
- **Humans** who genuinely want to wipe their drive use the OS installer or a live USB. The running system is the wrong tool to unmake itself.
- **Agents** misexpand variables, miscompose paths, and inherit `--no-preserve-root` from shared script libraries. Of all callers, agents benefit most from a hard floor.

The decision is whether kriya preserves the GNU escape hatch ("the user can opt in to disaster if they really mean it") or removes it entirely ("you cannot use kriya to do this — use a different tool"). This ADR takes the second option.

## Decision

**`kriya rm` refuses to operate on `/`. There is no flag, env var, build option, or call shape that bypasses the refusal. The mechanism is a static protected-paths table; the table ships with `/` only.**

### Mechanism

For every operand passed to `rm`:

1. Convert to an absolute path. Relative operands are joined against `getcwd()`.
2. Apply textual canonicalization via `path_normalize` from `src/lib/path.cyr`: collapse `.`, `..`, duplicate slashes; root absorbs leading `..` for absolute paths. **No symlink resolution.** (Per ADR 0003, `rm` never follows symlinks; canonicalization is text-only.)
3. If the result string-equals any entry in `protected_paths[]`, refuse the entire invocation with exit code `2` and the message:

   ```
   kriya rm: refusing to operate on '/'
   ```

4. The check happens **before** any operand is unlinked. If `rm` is called with multiple operands and one of them canonicalizes to a protected path, none of the others are touched. Atomicity is intentional: a script that accidentally generates `/` as one operand of many is exactly the script that should not have any of its other operands acted on either.

### Initial protected-paths table

```cyrius
# src/lib/protected.cyr
var protected_paths = [
    "/",
];
```

The table is one entry today. Extending it (e.g., to also refuse `/etc`, `/usr`, `/boot`) is an implementation choice that does **not** require a new ADR — adding entries makes the protection stricter, never looser, so the ADR-level decision ("there is a static refusal list") covers all future entries.

### What is *not* blocked

This refusal is narrowly scoped. Legitimate operations that touch files inside the protected paths remain fully available:

- `rm /usr/bin/oldtool` — operand canonicalizes to `/usr/bin/oldtool`, not `/`. Allowed.
- `rm -rf /var/cache/zugot/build-1234` — canonicalizes to the named directory. Allowed.
- `rm -rf /tmp/work/$session_id` — provided `$session_id` is non-empty and the path resolves to something under `/tmp/work/`. Allowed.
- `rm -rf /etc/conf.d/legacy.conf` — file-grained removal during a recipe. Allowed.
- `rmdir /var/empty` (M2) — same operand canonicalization, no protection trigger. Allowed.
- Package managers replacing kriya symlinks one at a time during installation, upgrade, or removal. Allowed.

The only thing blocked is operating on the root of the filesystem hierarchy itself.

### Hard rules (No-Gos)

1. **No `--no-preserve-root` flag.** Not under that name, not under any other. The flag does not exist in `kriya rm`'s spec. `kriya rm --no-preserve-root /` exits `2` for "unknown option" before the root-check fires; the safety property holds even if a future maintainer forgets the check.
2. **No env-var bypass.** `KRIYA_ALLOW_ROOT_DELETE=1 rm -rf /` exits `2`. No env var is consulted.
3. **No build-time bypass.** There is no `--features=allow-root-delete` cargo-style knob, no `#ifdef`, no `cyrius build --define`. The check is compiled in unconditionally.
4. **`-f` does not bypass.** The root check sits above `-f`. `kriya rm -rf /` exits `2`, not `0`.
5. **No interactive escape.** `kriya rm -i /` does not prompt "really delete /?" — the root check is hard and prompt-free. (And per ADR 0002, `-i` is itself rejected when stdin is not a tty.)
6. **No partial-progress on multi-operand invocations.** `kriya rm foo /bar /` checks all operands first, finds `/` in the list, refuses the entire invocation. `foo` is not deleted.
7. **Future maintainers do not have authority to add an escape hatch in a non-major version.** Removing or weakening this ADR requires a successor ADR that supersedes it and a major-version bump. The protection is a stability contract with consumers.

### The legitimate path to wiping a drive

A user who genuinely wants to wipe their AGNOS drive does it via:

- **The AGNOS installer** — choose "reinstall" or "wipe disk and install" from the installer menu, which operates on the block device, not the mounted filesystem.
- **An external live USB** — boot another OS, then operate on the unmounted target disk with `mkfs`, `dd`, `wipefs`, or the AGNOS installer.
- **`mkfs` on an unmounted partition** — for a non-root partition, unmount it (the kernel will refuse if it's `/`) and reformat. kriya is not involved.

kriya is a coreutils-equivalent. It is not a disk-management tool. The right tool for unmaking the filesystem is the one that runs outside the filesystem.

### Known weakness: shell-expanded `/*`

`rm -rf /*` is a real attack on this design. The shell expands `*` against `/`, kriya receives operands like `/bin /boot /dev /etc /home /lib /opt /proc /root /run /sbin /sys /tmp /usr /var`. Each operand canonicalizes to a directory under `/`, not to `/` itself. No protected-path entry matches. The protection does not fire.

This is the shell's expansion, not kriya's operand. A defense exists — refuse if the multi-operand argv covers every top-level entry under `/` — but it has nontrivial false-positive risk (a build script that legitimately operates on most-but-not-all top-level dirs would be blocked) and the implementation lives entirely on the kriya side of a shell behavior that other tools (`chmod -R /*`, `chown -R /*`) share.

**Deferred to a follow-up architecture note**, named explicitly: `docs/architecture/003-cross-operand-bulk-root-defense.md` (to be authored when M2 destructive utilities have shipped and we have real-world operand patterns to base the heuristic on). Until then, the weakness is documented here and in `kriya rm --help` ("note: shell-expanded `/*` is not blocked by the root-refusal check").

> ⛔ **RESOLVED AT 1.6.4, AND THE ANSWER IS NO HEURISTIC.**
> [architecture 003](../architecture/003-cross-operand-bulk-root-defense.md) designed four
> cross-operand defenses — a bigger static table, exact root coverage, an operand-fan-out threshold,
> and an inverted-glob pre-flight — measured each against real corpora, attacked each, and rejected
> all four. The gap stays open deliberately.
>
> ⚠ **That note also constrains this ADR's extension point.** The grant above — that adding entries
> to `protected_paths[]` needs no successor ADR because it is "strictly tightening" — holds only
> while the check is per-operand, and only for paths that always exist. A table entry for a path that
> can be absent turns `rm -f` on it from a POSIX no-op into a usage error. See its Hard rules.

## Consequences

- **Positive**
  - **The single most catastrophic command on the system has no kriya call shape.** `kriya rm -rf /` returns exit `2` and changes nothing.
  - **Agents have a hard floor.** Whatever variable misexpansion, prompt injection, or copy-pasted script puts `/` in `rm`'s argv, the result is the same: refusal and exit `2`. No probabilistic safety, no "the agent should know better."
  - **No flag for muscle memory to land on.** A user who learns GNU `rm` and types `--no-preserve-root` gets a clean usage error, not a foot-gun. The unknown-option message is the teaching moment.
  - **Compositional with ADR 0003.** Symlinks pointing at `/` cannot be used to circumvent — `rm` never follows symlinks (ADR 0003), so a `link-to-slash → rm link` invocation unlinks the link, not the target.
  - **No `--preserve-root` flag either** — the protection is not a toggle, so we don't ship a flag whose only purpose is to be the default. One less flag in `--help`.
- **Negative**
  - **No legitimate use case for wiping `/` from within kriya is supported.** This is intentional and stated; the legitimate path is the OS installer or external boot media. Documented in `kriya rm --help` and in the project README.
  - **Cross-utility consistency** — `mkdir`, `rmdir`, `touch`, `cp`, `mv`, `ln` do not check protected paths because they cannot do what `rm -rf /` does. The ADR's scope is `rm` only. Future expansion (e.g., `chmod -R 000 /`, when `chmod` lands) gets its own protected-path check, modeled on this one.
  - **`/*` shell expansion remains a known gap.** Documented above and slated for an architecture-note follow-up.
- **Neutral**
  - **`protected_paths[]` is an extension point.** Future contributors can add `/etc`, `/usr`, `/boot`, `/proc`, `/sys`, `/dev` without ADR overhead. Strictly tightening the policy needs no debate; loosening it (e.g., removing `/`) requires a new ADR.
  - **The check is two `streq`s and a normalize call per operand** — single-digit microseconds per operand on the dispatcher cold-start machine. No measurable impact on the per-utility benchmark budget.

## Alternatives considered

- **GNU model: `--preserve-root` on by default, `--no-preserve-root` opts out.** Rejected — the escape hatch is the failure mode. Once `--no-preserve-root` exists in a script, it propagates by copy-paste and CI inheritance. The very existence of the flag is what causes the catastrophes it nominally prevents.
- **Same as GNU but with a `KRIYA_CONFIRM_ROOT_DELETE=really` interactive double-confirm.** Layering ceremony does not fix the underlying issue: the operation is supported, somebody's automation will perform the ceremony, and the floor is gone. Rejected.
- **Block `/` only when uid 0.** Rejected — agents and CI often run as a regular user with sudo wrappers or in containers as root. Conditioning on uid moves the line in the wrong direction (the privileged caller is exactly the one for whom the bulk-delete is catastrophic).
- **Block `/` and a longer list of system-critical paths (`/etc`, `/usr`, …) by default.** Rejected as a Big Bang change — the false-positive risk needs operational data we don't have. The mechanism is in place via `protected_paths[]`; entries can be added by future maintainers when they have a real consumer complaint or a real incident to point at, without re-opening this ADR.
- **Make `rm` itself refuse to run as uid 0 on `/` and instead delegate to a `kriya-wipe` binary that requires a magic flag.** Same problem as the GNU flag, just renamed. Rejected.

## Precedent

- **NixOS, GuixSD package managers** — never bulk-delete `/` even on full system rebuilds; they manipulate per-package directories. The "package managers replace files, not the world" pattern is the existing norm.
- **macOS System Integrity Protection** — refuses certain deletes regardless of uid 0. Same principle: some operations are off-limits to the running system; the legitimate path is the recovery environment.
- **`mkfs` refusing a mounted filesystem** — kernel-level analogue of the same idea. The legitimate path is to operate from outside.

## References

- ADR 0003 (companion) — symlink-follow policy; `rm` never follows.
- POSIX `rm`: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/rm.html
- GNU coreutils `rm` history: https://git.savannah.gnu.org/cgit/coreutils.git/tree/src/rm.c
- AGNOS installer (forthcoming): owns disk-management operations kriya deliberately doesn't.
