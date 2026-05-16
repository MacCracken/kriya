# kriya — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.1.0** — scaffolded 2026-05-15 via `cyrius init`. No releases yet.

## Toolchain

- **Cyrius pin**: `5.11.54` (in `cyrius.cyml [package].cyrius`)

## Source

Initial scaffold only.

## Tests

- `tests/kriya.tcyr` — primary suite (smoke + math; passes on `cyrius test`)
- `tests/kriya.bcyr` — benchmark stub (no-op)
- `tests/kriya.fcyr` — fuzz stub

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — string, fmt, alloc, io, vec, str, syscalls, assert

## Consumers

_None yet._

## Next

See [`roadmap.md`](roadmap.md).
