# 0024 — `cp` and `mv` resolve `-f`, `-i` and `-n` as GNU does

**Status**: Accepted
**Date**: 2026-09-23

## Context

Three flags decide what `cp` and `mv` do with a destination that already exists: `-f` (replace
it), `-i` (ask) and `-n` (leave it). GNU resolves them differently in its two utilities. Measured
on coreutils 9.11, under a pty so that `-i` really asks:

| flags | GNU `cp` | GNU `mv` |
|---|---|---|
| `-fi`, `-if` | asks, both orders | `-fi` asks, `-if` replaces: the last flag wins |
| `-ni`, `-in` | the last flag wins | the last flag wins |
| `-nf`, `-fn` | leaves it, both orders | `-nf` replaces, `-fn` leaves it |
| declined prompt | exit 1 | exit 1 |
| `-n` skip | exit 0 | exit 0 (9.4 said 1) |
| `-n` with `-b` | refused (9.4 took it and made no backup) | refused |

So "match GNU" means two rules. In `cp`, `-f` means "replace, and remove what cannot be
opened" (ADR 0021), and it is independent of whether to ask. Only `-i` and `-n` compete. In `mv`,
all three are one choice, and the last flag written wins.

kriya matched neither rule:
- `cp -f` cancelled `-i` in either order, so `cp -fi src dst` replaced the file without the
  prompt the caller asked for.
- `cp` had no `-n` at all.
- `mv` applied a fixed precedence, where the flags' order ought to decide. Its header comment
  described that precedence wrongly: it said `-f` beat `-n`, while the code let `-n` win.
- A declined `mv` prompt exited 0.

The header gave a reason for the precedence: the parser "doesn't surface" the order. It has done
so since 1.6.9 (`kriya_opt_seq`).

The roadmap asked for the choice to be made before anything changed, because each utility needs
its own rule.

## Decision

**Each utility resolves the three flags as its GNU namesake does.**

- **`cp`**: `-i` and `-n` are last-wins against each other, and `-f` cancels neither. `-n` /
  `--no-clobber` is added: an existing destination is skipped, silently, with exit 0. The order
  of the checks is `-n`, then `-i`, then `-f` or a backup, in all three copy paths (a file
  operand, a file in a `-R` walk, and a symlink in one). The symlink arm had never looked at
  `-i`; it now asks too.
- **`mv`**: `-f`, `-i` and `-n` are last-wins. A declined prompt exits 1.
- **Both**: an effective `-n` with a backup is a usage error, as in GNU 9.11: nothing `-n`
  protects would ever be backed up.

**Unchanged:**
- kriya's defaults. `cp` still refuses to replace an existing destination unless `-f`, `-i`, `-n`
  or a backup says what to do (CLAUDE.md). `mv` still replaces it silently, as POSIX says.
- An effective `-i` with no terminal on stdin is still a usage error (ADR 0002).

## Consequences

- **Positive**: every cell of the table matches GNU, under a pty and without one
  (`smoke-cp.sh`, `smoke-mv.sh`).
- **Positive**: the safer reading wins in `cp`. A command that says `-i` is asked, whatever else
  it says.
- **Negative — breaking**:
  - `cp -fi` and `cp -if` now ask. Without a terminal they are now a usage error; they used to
    replace the file.
  - `mv -fi` now asks.
  - `mv -nf` now replaces the destination.
  - A declined `mv -i` now exits 1.
  - `cp -nb` and `mv -nb` now refuse; `mv -nb` used to skip with no backup made.
  - A script that meant "replace" writes `-f` alone, or last.
- **Neutral**: `mv -n`'s exit status on a skip follows GNU 9.11 (0), not CI's 9.4 (1), so that
  one assertion checks kriya's answer rather than the local GNU's.

## Alternatives considered

- **One rule for both, last-wins everywhere.** Rejected. `cp -fi` would then replace without
  asking, which is the bug this fixes, and it would diverge from GNU's `cp` in the unsafe
  direction.
- **One rule for both, `-f` never cancels anything.** Rejected. `mv -if` would then ask where
  GNU's `mv` replaces. Scripts write `mv -f` precisely to turn an earlier `-i` off.
- **Keep kriya's precedences.** Rejected. They were neither GNU's rules nor what kriya's own
  comments said, and `cp`'s version skipped a prompt that had been asked for.
