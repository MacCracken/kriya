# Architecture Decision Records

Decisions about kriya — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | `docs/adr/` | *Why did we choose X over Y?* |
| Architecture note | `docs/architecture/` | *What non-obvious constraint is true about the code?* |
| Guide | `docs/guides/` | *How do I do X?* |

## Index

- [0001 — BusyBox-style dispatcher vs N independent binaries](0001-busybox-dispatcher-vs-n-binaries.md) — one binary, symlinks per utility; `argv[0]` selects the command.
- [0002 — Option parsing for humans and agents](0002-option-parsing-humans-and-agents.md) — one parser, POSIX-short + GNU-long, agent-safe restrictions (no prefix matching, no optional values, no interactive hangs, `--help=json` for capability discovery).
- [0003 — Symlink-follow policy for destructive utilities](0003-symlink-follow-policy.md) — POSIX-aligned defaults; `cp -R` preserves symlinks; `rm` never follows (no flag opts in).
- [0004 — `rm` refuses to operate on `/` — no escape hatch](0004-rm-refuses-root.md) — hard No-Go on bulk root deletion; no `--no-preserve-root`, no env var, no build flag. Wiping a drive belongs to the OS installer or external boot.
