# 0006 — Utility scope: six non-POSIX utilities ship in kriya

**Status**: Accepted
**Date**: 2026-05-18

## Context

POSIX.1-2017 Chapter 4 defines the canonical Unix utility set. kriya's stated goal is "coreutils-equivalent for AGNOS — the *small POSIX-style command-line utilities* surface" (CLAUDE.md). The natural read is "POSIX utilities only." But six shipped utilities are not in POSIX.1-2017:

| Utility | Standardization | Why kriya ships it |
|---|---|---|
| `yes` | BSD/GNU | Shell-pipeline ubiquity. `yes | head` is the canonical way to feed an auto-confirm loop; absence would break common scripts. |
| `seq` | BSD/GNU | Shell loop generation (`for i in $(seq 1 10)`). Trivially small, universally expected. |
| `stat` | GNU (POSIX has the `stat(2)` syscall, not the utility) | Inspection-time metadata access from shell. Build scripts, deployment scripts, and `agnoshi` interactive use all rely on it. |
| `realpath` | Added in POSIX.1-2024 (not in POSIX.1-2017) | Canonical path resolution. `realpath -e` / `-m` are dependency-graph-resolution staples. |
| `readlink` | Added in POSIX.1-2024 (not in POSIX.1-2017) | Symlink inspection. Pairs with `ln`; widely scripted. |
| `which` | Third-party shell utility, never POSIX | PATH-walk introspection. Universally expected even though POSIX has `command -v` for the same purpose. |

The M7 POSIX compliance audit (`docs/audit/2026-05-18-posix-compliance.md`) cataloged each as "non-POSIX, intentional kriya extension" and pointed at this ADR. That pointer needs a written decision.

The risk of saying "POSIX-only" and dropping these six: every downstream consumer (agnoshi, zugot, an installed AGNOS userland) would have to either re-implement the same surface or stop expecting it. The risk of saying "ship everything": scope creep into archive (`tar`/`gzip` — out of scope per CLAUDE.md), networking (`curl`/`ssh`), and editor-adjacent (`cat` — owl owns it) territory.

## Decision

**kriya ships exactly these six non-POSIX utilities as scope extensions: `yes`, `seq`, `stat`, `realpath`, `readlink`, `which`.** Each is documented in the file header as "GNU/BSD; not in POSIX-2017 but ships in kriya per ADR 0006."

**Criteria for any future addition of a non-POSIX utility:**

1. **Shell-pipeline ubiquity** — the utility is part of the basic shell vocabulary that downstream scripts assume exists. If a typical bash script breaks without it, that's strong evidence.
2. **Bounded scope** — small (≤ 400 LOC per the kriya split policy), single-verb, no external dep surface beyond Cyrius stdlib.
3. **Stays out of sovereign territory** — does not duplicate functionality owned by owl (`cat`), sit (`git`), cyim (`vim`), chakshu (`htop`), agnoshi (shell builtins), or any future archive/networking sovereign. CLAUDE.md's scope-boundary table is the authoritative reference.
4. **Has a real consumer** — agnoshi, zugot, or an AGNOS init script. "Nice to have someday" is not enough.

A new utility that fails any one of these gets rejected with the answer "extract a focused repo or drop the proposal," per CLAUDE.md's "push back" policy.

**ADR scope:** this ADR covers *which* utilities ship. *How* each shipped non-POSIX utility behaves is the per-utility file header and CHANGELOG — not duplicated here.

## Consequences

**Positive:**

- A shell user invoking any of the six gets the expected result; no surprise gaps that force scripts to vendor in fallback implementations.
- The audit's "non-POSIX, intentional" cells now have a written justification — future readers asking "why does kriya ship `seq`?" find this ADR.
- The four-criteria gate gives future PRs a clear test for "should we add `expr`?" or "should we add `tac`?" — same shape, different answer (likely yes and no respectively, depending on consumer-asks).

**Negative:**

- Six utilities' worth of code outside the POSIX-compliance audit's "conformance against the spec" pillar. Each must be tested against its de-facto-standard (GNU coreutils behavior) instead of a written spec.
- Risk of scope drift: the four criteria are subjective enough that a determined PR author can argue any utility into scope. Mitigated by CLAUDE.md's hard scope-boundary table (archive, networking, GPU, editor — all hard No).

**Neutral:**

- POSIX.1-2024 promoted `realpath` and `readlink`. If kriya later targets 2024, those two move from "ADR-0006 scope extension" to "POSIX-required" — no code change needed, just an audit reclassification. The other four (`yes`, `seq`, `stat`, `which`) stay non-POSIX.

## Alternatives considered

- **POSIX-only — reject all six.** Forces every downstream to vendor in scripts. The agnoshi-pipeline and zugot-recipe surfaces would each grow a workaround layer, which contradicts the "first-party own the stack" doctrine.
- **Ship everything GNU coreutils ships.** Expands kriya past the 400-LOC-per-utility split policy and into territory CLAUDE.md explicitly excludes (archive utilities, locale-aware filters, `expand`/`fold`/`fmt`/`pr`/`paste`/`join`/`comm`/`tsort`/`tac`/`split`/`csplit` … the list is long). Wrong direction.
- **Per-utility ADR for each non-POSIX extension.** Considered and rejected — the six are a cohesive policy decision, not six independent ones. One ADR with criteria scales better than six ADRs that each restate the same logic.
