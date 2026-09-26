# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides (those live in [`../guides/`](../guides/)). An item here describes *how the world is*, not *what we chose* or *how to do something*.

## Items

- [001 — errno → message policy](001-errno-message-policy.md) — every kriya error line is `kriya <util>: <operand>: <message>\n` on stderr, the operand shell-quoted when it needs it; one implementation, `errmsg_report` / `report_note` in `src/lib/report.cyr`, and one table, `src/lib/errmsg.cyr`.
- [002 — Signal handling model](002-signal-handling-model.md) — kernel defaults everywhere (SIGPIPE → 141, SIGINT → 130); no utility installs a handler. `tee -i` / `-p` set `SIG_IGN` dispositions, and only on request ([ADR 0016](../adr/0016-tee-signal-dispositions.md)). agnos has no SIGPIPE: a write to a readerless pipe answers -1, recorded as EPIPE, and a write with no progress for 5 s is ENOSPC (1.7.1).
- [003 — Cross-operand bulk-root defense](003-cross-operand-bulk-root-defense.md) — the shell-expanded `rm -rf /*` gap ADR 0004 left to this note: four defenses designed, measured and attacked, and none built — a decision, not an omission.
