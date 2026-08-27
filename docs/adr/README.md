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
- [0005 — Regex engine: Cyrius stdlib niyama, BRE + RE2, no PCRE in v1.0](0005-regex-engine-niyama.md) — `grep` defaults to `niyama_bre_*`; `-E` flips to RE2; `-F` is in-tree byte scan; `-P` rejected with usage error.
- [0006 — Utility scope: six non-POSIX utilities ship in kriya](0006-utility-scope-non-posix.md) — `yes`, `seq`, `stat`, `realpath`, `readlink`, `which` ship as intentional scope extensions; four-criteria gate for any future non-POSIX addition.
- [0007 — `date` defaults to UTC at v0.7.0; local-time tzfile parsing is a named follow-up](0007-date-utc-only-at-v0-7-0.md) — UTC-only at v0.7.0; `-u` accepted as no-op; flips to local time when an upstream `chrono_tz.cyr` ships.
- [0008 — POSIX exit-code policy: three-tier convention + per-utility specifics](0008-posix-exit-code-policy.md) — `EXIT_SUCCESS`/`EXIT_FAILURE`/`EXIT_USAGE` baseline, POSIX-named codes override (grep no-match=1, xargs 123/124/125/126/127, env 126/127).
- [0009 — `mv` never rolls back a completed cross-filesystem copy](0009-mv-never-rolls-back-a-completed-copy.md) — the rollback belongs to a FAILED copy only; after a successful copy the source-removal failure is reported and the destination stays. Two visible trees beat zero.
- [0010 — `rm -r link/` is refused rather than half-completed](0010-rm-refuses-a-trailing-slash-symlink-operand.md) — a trailing slash on a symlink emptied the target and then reported failure (GNU does too); kriya refuses, with no `-f` bypass. Closes the POSIX-shaped hole in ADR 0003.
- [0011 — `echo` matches the non-XSI binary, not the shell builtin](0011-echo-matches-the-non-xsi-binary-not-the-shell-builtin.md) — `-n`/`-e`/`-E` with escapes off by default, GNU's escape set minus `\"`, `\c` cancels all remaining output; `POSIXLY_CORRECT` deliberately does NOT flip it to XSI.
- [0012 — Hard-link awareness: what `cp` preserves, what `du` counts, and which walks are allowed to come back](0012-hard-link-awareness.md) — one `(st_dev, st_ino)` set for `cp --preserve=links` and `du`'s dedup; `cp` remembers the master destination as a PATH and errors rather than degrading when `linkat` fails; `du` dedupes by default with `-l` to opt out; `du` tracks a narrower set than GNU (measured 300x memory) and the one residual divergence is asserted, not hidden.
- [0013 — Ownership and extended attributes: what a copy carries, and what it must drop](0013-ownership-and-extended-attributes.md) — `--preserve=ownership` and `--preserve=xattr` implemented and `-p` gains ownership to match GNU; every metadata restore moves onto the OPEN DESCRIPTOR in the order xattrs → ownership → mode → times; the set-id bits AND the sticky bit are cleared whenever ownership was requested and not fully set; cross-filesystem `mv` carries all four. Closes M8 audit rows 35350, 35351 and 35354.
- [0014 — kriya's symlink-traversal limit is the kernel's, uniformly](0014-symlink-traversal-limit-is-the-kernels.md) — 40, the kernel's number, in every `fs_realpath` mode: an error in the strict modes, a stopping point under ALLOW_MISSING. GNU's limit is not a number — it resolves symlink chains of any length (so `realpath` prints paths its own `cat` cannot open) and stops after 20 inside a cycle. The cycle divergence is accepted, asserted, and counted apart in the `ln -sr` fuzz rather than hidden by loosening the oracle.
