# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides (those live in [`../guides/`](../guides/)). An item here describes *how the world is*, not *what we chose* or *how to do something*.

## Items

- [001 — errno → message policy](001-errno-message-policy.md) — every kriya error line is `kriya <util>: <message>: <operand>\n` to stderr; the table lives in `src/lib/errmsg.cyr`.
- [002 — Signal handling model](002-signal-handling-model.md) — kernel defaults at M1 (SIGPIPE → 141, SIGINT → 130); M2 destructive utilities install a flag-based SIGINT handler.
