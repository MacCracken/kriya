# 0028 — `df -t` is GNU's type filter, not XSI's totals option

**Status**: Accepted
**Date**: 2026-11-03

## Context

`df -t` means two incompatible things.

- **POSIX** (POSIX.1-2024, Issue 8, `df`): the synopsis is `df [-k] [-P|-t] [file...]`, with `-t`
  XSI-shaded and taking no argument: *"Include total allocated-space figures in the output."* The
  STDOUT section adds *"The output format is unspecified when -t is used."* Nothing in the standard
  selects file systems by type.
- **GNU coreutils**: `-t TYPE` / `--type=TYPE` lists only file systems of TYPE, is repeatable, and
  has a companion `-x TYPE` / `--exclude-type=TYPE`. On Linux this is the `-t` that scripts and users
  write (`df -t ext4`, `df -x tmpfs -x devtmpfs`).

The two cannot coexist, because GNU's `-t` takes an argument and XSI's does not. kriya's roadmap had
listed `df -t TYPE` as "POSIX-required", which was wrong on both counts. GNU's is not POSIX's, and
POSIX's is an XSI option, not part of the base.

## Decision

**kriya's `df -t` is GNU's type filter**, with `-x` / `--exclude-type` beside it. Measured against
coreutils 9.4 and 9.7 and reproduced:

- `-t` repeats, and the types are ORed. `-x` repeats. Names compare exactly (case-sensitive).
- An operand's file system is filtered too: `df -t tmpfs /` on an overlay root lists nothing.
- The pseudo-file-system filter still applies, so `-t proc` lists nothing without `-a`.
- A type named by both `-t` and `-x` is refused in GNU's words (*file system type 'X' both selected
  and excluded*).
- A filter that leaves nothing prints GNU's *no file systems processed*, with **no header**, and exits
  1.
- Usage errors exit 2, kriya's code (GNU's is 1).

XSI's `-t`, total allocated space with an unspecified format, is not implemented. A script written for
it would pass `-t` with no TYPE, which kriya refuses as a usage error rather than reinterpreting.

## Consequences

- **Positive**: `df -t`/`-x` behave the way a Linux user expects, and AGNOS's consumers (agnoshi
  scripts, package hooks) need not special-case kriya.
- **Negative**: kriya does not offer XSI's `-t`. A strictly XSI-conforming `df` script gets a usage
  error, not totals.
- **Neutral**: if XSI totals are ever wanted, the GNU-compatible spelling is `--total`, which is a
  separate, listed deferral.

## Alternatives considered

- **XSI `-t`.** Rejected. Nothing on Linux implements it, its output is unspecified, and taking it
  would make the common `df -t ext4` a usage error or, worse, read `ext4` as a file operand.
- **Both, decided by whether the next word looks like a type.** Rejected. It is a guessing parser
  where ADR 0002 wants one canonical form, and `df -t /mnt` would be ambiguous.
