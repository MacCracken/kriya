# 0001 — One dispatcher binary + symlinks, not N independent binaries

**Status**: Accepted
**Date**: 2026-05-15

## Context

`kriya` ships ~40 small utilities (`cp`, `mv`, `rm`, `mkdir`, `echo`, `wc`, `find`, `grep`, etc.). Each is a separate command from the user's perspective: `cp foo bar`, `rm -rf /tmp/x`, etc. The packaging question is how those commands map to binaries on disk.

Three options:

1. **One binary per utility** — `bin/cp`, `bin/mv`, `bin/rm`, … forty separate static binaries
2. **One dispatcher binary + symlinks** (BusyBox pattern) — `bin/kriya` is the binary; `bin/cp`, `bin/mv`, … are symlinks → `kriya`. The dispatcher reads `argv[0]` to determine which utility to run
3. **One binary, no symlinks** — `kriya cp foo bar`, `kriya rm /tmp/x` — multi-tool with explicit subcommand

Each has real trade-offs at scale.

## Decision

**Option 2: one dispatcher binary + symlinks per utility.** The user-facing commands (`cp`, `mv`, `rm`, …) are POSIX-shaped: a name in `$PATH`, no subcommand prefix. The symlinks make them feel like normal independent binaries; the single underlying binary keeps code, data, and audit surface unified.

Internally, `src/main.cyr` is the dispatcher: it reads `argv[0]`, basename-strips, looks up in the utility table, calls `cmd_{util}(argc, argv)`. Utilities live in `src/cmd/{util}.cyr`.

For convenience and testing, the dispatcher also supports `option 3` invocation: `kriya cp foo bar` works the same as `cp foo bar`. This is the form used in tests + benchmarks where symlinks would add fixture complexity.

## Consequences

- **Positive**
  - **One binary to audit, sign, verify** — security review covers the whole set in one pass; reproducible-build proofs cover all utilities together
  - **Shared text segment** — `src/lib/{path,exit,errmsg,args}.cyr` is loaded once, not 40×. RSS savings are real on a small AGNOS box (~40 × startup overhead → ~1 ×)
  - **Single CHANGELOG, single CI, single release** — drastically lower per-utility overhead vs option 1
  - **Cold-start** — one shared dispatcher binary means the kernel can keep one page-cache entry warm; subsequent kriya commands are near-zero cost vs the 40-binary version which thrashes
  - **Cross-utility consistency** — error messages, exit codes, argument parsing all come from `src/lib/`; no drift between `cp`'s `--help` and `rm`'s `--help`
- **Negative**
  - **One bug crashes them all** — a dispatcher bug or shared-lib bug takes out every utility. Mitigation: dispatcher itself is tiny + heavily tested; shared lib has the most rigorous test coverage of any module
  - **Binary size grows with utility count** — `kriya` will be larger than any single utility would be. Tradeoff: still much smaller than 40 separate binaries combined (shared text)
  - **Slight argv[0] obscurity** — a curious user `ls -l /usr/local/bin/cp` sees it's a symlink, which is mildly surprising vs an independent binary. Documented in README + `--help`
  - **Install-time symlink management** — installation step has to create N symlinks. zugot recipe handles this in [marketplace](https://github.com/MacCracken/zugot)
- **Neutral**
  - **`argv[0]` becomes load-bearing** — the dispatcher MUST handle missing / malformed argv[0]. ADR-worthy edge case; mitigation in dispatcher.

## Alternatives considered

- **Option 1 — N independent binaries**: simpler mental model, isolated failure modes, but 40 × the CI / packaging / changelog / release overhead. For a v0.1 → v1.0 progression where utilities ship monthly, this overhead compounds intolerably. **Rejected**.
- **Option 3 — single binary, explicit subcommand only (`kriya cp foo bar`)**: cleanest internal model, no symlink fuss, but breaks POSIX user expectations (shell scripts everywhere assume `cp foo bar`). **Rejected**.
- **Hybrid (build-time choice)**: some users get separate binaries, others get the dispatcher. Adds complexity for marginal benefit. **Rejected** until a real consumer asks.

## Precedent

- **BusyBox** — the canonical reference for this pattern. ~400 utilities, single binary, symlink install. The pattern has held for 25+ years.
- **toybox** — same pattern, BSD-licensed alternative.
- **The opposite (GNU coreutils)** — 40 separate binaries. The contrast lets each project's tradeoffs show: GNU optimizes for per-utility autonomy and development velocity at scale; BusyBox optimizes for embedded footprint and unified audit. kriya is closer to BusyBox in goals.

## References

- BusyBox: https://busybox.net/
- toybox: https://landley.net/toybox/
- POSIX utilities: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/contents.html
