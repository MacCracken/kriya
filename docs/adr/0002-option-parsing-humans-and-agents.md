# 0002 — Option parsing for humans and agents

**Status**: Accepted
**Date**: 2026-05-17

## Context

Every kriya utility takes options on the command line: `cp -r -f src dst`, `wc -l file`, `grep -i -v pattern file`. The dispatcher hands an `argc` and `argv` window to `cmd_<util>(start)`; everything after that is the utility's responsibility.

Two distinct callers exercise this surface:

- **Humans** — shells, scripts, muscle memory. Want short flags (`-r`), clustering (`-rfv`), `--long-form` for readability in scripts, both `--key value` and `--key=value`, friendly error messages, completion-friendly long names.
- **Agents** — LLMs, schedulers, build systems, package managers. Want one canonical form per concept, no silent ambiguity, no prefix matching, no interactive hangs, machine-readable help, stable flag sets across versions, exit codes that distinguish "usage" from "operation failure".

A single utility cannot ship two parsers. The question is which behaviors survive in the one parser, and which we explicitly refuse.

POSIX gives a floor: short flags, `--` terminator, exit 2 on usage error. GNU adds: long flags, `--key=value`, prefix matching, optional values, abbreviations. Neither standard considers agents directly.

## Decision

**One parser, in `src/lib/args.cyr`, supporting POSIX-short + GNU-long with hard restrictions chosen for agent safety. The same parser serves both audiences; agent-friendly choices win where they conflict with GNU permissiveness.**

### Hard rules (No-Gos)

1. **No prefix matching.** `--ver` does not match `--version`. Long names are spelled in full or the parse fails with exit 2. (GNU getopt-long permits abbreviation; we reject it: silent drift across releases.)
2. **No libc-style `getopt` reordering.** `kriya cp src -r dst` is parsed left-to-right with `-r` as a flag and `src`/`dst` as positionals — flags can interleave with positionals — but the relative order of positionals is preserved as written. No silent re-shuffle.
3. **No optional flag values.** `--color` with no value is a boolean; `--color=auto` carries a value. A flag is either a boolean or it requires a value — never both. (Ambiguity here is the single biggest source of agent miscalls.)
4. **No interactive prompts when stdin is not a tty.** Destructive `-i` (interactive) on a pipe is a usage error, not a hang. Detected via `isatty(STDIN_FILENO)` before any prompt.
5. **No prompts in `--dry-run` mode under any circumstance.** Dry-run prints what would happen, exits 0, touches nothing.
6. **No silent option deprecation.** A flag that's been retired must either still parse (with a one-line stderr deprecation note) or fail loudly. Never silently mean something else.
7. **No C, no libc, no `getopt(3)`.** The parser is pure Cyrius, on top of stdlib `lib/args.cyr` (`argc()` / `argv(n)`). Matches kriya's "static, zero-dep" line in `CLAUDE.md`.

### Allowed forms

| Form | Example | Notes |
|---|---|---|
| Short boolean | `-r` | |
| Short cluster | `-rfv` | All but the last must be boolean. |
| Short with value (separate) | `-n 10` | |
| Short with value (attached) | `-n10` | Last in cluster: `-rfvn10`. |
| Long boolean | `--recursive` | |
| Long with value (separate) | `--count 10` | |
| Long with value (attached) | `--count=10` | **Canonical agent form.** |
| Positional terminator | `--` | Everything after is positional, even `-x`. |
| Negative-number positional | `cmd -- -5` | Use the terminator. Raw `-5` is rejected as an unknown short flag. |

### Help and capability discovery

Every utility supports two help forms with the same content, different shape:

- **`-h` / `--help`** — human form. Sections in fixed order: `NAME`, `SYNOPSIS`, `DESCRIPTION`, `OPTIONS`, `EXIT CODES`, `EXAMPLES`. Wrapped at 80 columns. ANSI styling only when stdout is a tty.
- **`--help=json`** — machine form. Schema in [Appendix A](#appendix-a-help-schema). Stable per major version. An agent that has not seen kriya before can `kriya <util> --help=json` and parse the flag table without prior knowledge.

Top-level `kriya --list` returns the full utility table as JSON: one entry per utility, with `name`, `summary`, `exit_codes`. This is the agent's entry point for discovering what kriya can do without grepping docs.

### Destructive-operation rules (cross-utility)

Every utility that modifies persistent state (file content, file metadata, filesystem structure) supports:

- `--dry-run` — print intended actions to stdout, exit 0, mutate nothing.
- Exit 2 on usage error, exit 1 on operation failure. (`grep`-style "no match → 1" is utility-specific and documented in that utility's `--help`.)
- Refusal of `-i` (interactive) when stdin is not a tty — usage error.

### API surface (sketch — full impl lands in a separate commit)

```cyrius
# Spec built once per utility, at the top of src/cmd/<util>.cyr
var spec = spec_new("cp");
spec_add_short(spec, 'r', ARG_BOOL, "recursive");
spec_add_short(spec, 'f', ARG_BOOL, "force");
spec_add_short(spec, 'i', ARG_BOOL, "interactive");
spec_add_long(spec, "dry-run", ARG_BOOL);
spec_set_positional(spec, 2, 0);   # min 2, max unbounded (cp src... dst)

# In cmd_cp(start)
fn cmd_cp(start: i64): i64 {
    if (args_parse(spec, start) != 0) { return EXIT_USAGE; }
    if (args_has("dry-run") == 1) { ... }
    if (args_has("interactive") == 1 && isatty(0) == 0) {
        return usage_error("cp: -i requires stdin to be a terminal");
    }
    ...
}
```

The spec is built at startup (gvar bump-allocated, no `gvar_toks` cost — the spec is heap-resident, pointed to by one global per utility); the parse result lives in a thread-local-style global owned by the parser. `cmd_<util>` reads it through `args_has` / `args_get_*`.

## Consequences

- **Positive**
  - **One parser to audit.** All utilities share the same option grammar; a parser bug fixes propagate to every utility. Per-utility code is tiny — declare a spec, call `args_parse`, read results.
  - **Agents can introspect.** `--help=json` + `kriya --list` give an LLM enough to call any utility correctly without baked-in knowledge of the kriya API.
  - **No silent ambiguity.** Prefix matching, optional values, and silent option reordering — the three GNU features most likely to bite agents — are off.
  - **Interactive correctness.** `cp -i < /dev/null` fails fast instead of hanging in a non-interactive pipeline.
  - **Dry-run is universal.** Every destructive utility has the same dry-run behavior; agents can preview without per-utility logic.
  - **Stable across releases.** The "no silent deprecation" rule means agents written against v0.5 still parse correctly under v1.0, or fail loudly enough to notice.

- **Negative**
  - **No prefix matching costs human ergonomics.** Heavy GNU users will notice that `--ver` no longer works. Mitigation: long names are explicit and tab-completion in the shell handles abbreviation. ADR-worthy tradeoff; we take the agent side.
  - **Help-schema discipline.** Every utility now owes a `--help=json` schema that conforms to Appendix A. Missing entries fail CI (lint rule lands with `src/lib/args.cyr`).
  - **`--help=json` output is a public interface.** Schema changes go through deprecation. Locked behind a `KRIYA_HELP_SCHEMA_VERSION` constant in `src/lib/args.cyr`; major-version bumps require an ADR.
  - **Cyrius gvar limit pressure.** Each utility's spec is one heap pointer in a global — fits in budget — but ~40 utilities means ~40 gvars dedicated to specs. Plenty of headroom (256 limit), counted in `state.md` once M1 lands all six utilities.

- **Neutral**
  - **POSIX vs GNU labeling.** kriya does not claim POSIX-strict on flag handling: `--key=value` is GNU, not POSIX. Each utility's `--help` lists its non-POSIX flags so a strict POSIX consumer sees the boundary.
  - **`-h` collides with `head -h` (human sizes) and `du -h`.** Per-utility, `-h` is reassigned to the utility's meaning and `--help` carries help duty alone. Documented in each utility's `--help`. ADR captures the principle; per-utility deviations don't need separate ADRs.

## Alternatives considered

- **POSIX-only (no long flags).** Maximizes portability and minimizes parser size; rejected — long flags are the agent-friendly form. Without `--recursive`, an agent has to ship a short-flag table per utility.
- **GNU permissive (prefix matching, optional values, getopt reordering).** Familiar to users of GNU coreutils; rejected — the three permissive features are exactly the ones that cause agent miscalls in production. Prefix matching alone has bitten dozens of CI pipelines on GNU coreutils version bumps.
- **Subcommand grammar (`kriya cp --recursive=true src dst`).** Cleanest agent form; rejected — breaks POSIX shape (`cp foo bar` must work as-is from any shell script that exists today).
- **JSON-only input (`kriya call '{"util":"cp","flags":{"recursive":true},"args":["src","dst"]}'`).** Best possible agent form; rejected — humans would revolt. Kept as a possible future addition under a different binary entry, not a replacement.
- **Per-utility custom parsers.** Each `cmd_<util>` owns its own argv walk; rejected — guaranteed inconsistency across the multi-tool, defeats the "one binary, one audit surface" win from ADR 0001.

## Appendix A — `--help=json` schema (v1)

```json
{
  "schema": "kriya-help/v1",
  "name": "cp",
  "summary": "Copy files and directories.",
  "synopsis": "cp [OPTIONS] SOURCE... DEST",
  "options": [
    {
      "long": "recursive",
      "short": "r",
      "kind": "bool",
      "description": "Copy directories recursively."
    },
    {
      "long": "force",
      "short": "f",
      "kind": "bool",
      "description": "Overwrite destination without prompting."
    },
    {
      "long": "dry-run",
      "short": null,
      "kind": "bool",
      "description": "Print actions; do not modify the filesystem."
    }
  ],
  "positional": {
    "min": 2,
    "max": null,
    "names": ["SOURCE", "DEST"]
  },
  "exit_codes": {
    "0": "Success.",
    "1": "Copy failed (permission, disk, target).",
    "2": "Usage error."
  },
  "examples": [
    "cp foo bar",
    "cp -r dir1 dir2",
    "cp --dry-run *.txt /tmp/"
  ]
}
```

Fields are required unless explicitly nullable. Unknown fields are reserved (agents must tolerate forward-additive changes within v1).

## Implementation status (as of v0.2.0 cut)

The first consumer (`src/lib/args.cyr`, used by `pwd` and any future flag-taking utility) wraps stdlib `lib/flags.cyr`. Stdlib `flags.cyr` covers the bulk of this ADR: long flags, `--key=value`, the `--` terminator, positional collection, bool / int / str kinds, error reporting. The following ADR commitments are **not yet implemented** because stdlib `flags.cyr` does not yet support them:

- **Short flag clustering** (`-rfv` = `-r -f -v`). Each short flag must currently be a separate token.
- **Attached short values** (`-n10` = `-n 10`). Short value-taking flags require a separated token.
- **`--help` (human form)** auto-rendered from the spec.
- **`--help=json`** schema emission per Appendix A.
- **`kriya --list`** top-level utility enumeration.
- **`--dry-run` cross-utility enforcement** (lands when the first destructive utility ships in M2).
- **`isatty(0)` check for `-i` flags** (lands with M2 cp/mv/rm).

Each of the above is a separate, named follow-up — not a vague "TBD". The path to closing them: upstream the short-cluster and attached-value features into stdlib `lib/flags.cyr` (one PR against `cyrius`), then re-fit `src/lib/args.cyr` to expose `--help` / `--help=json` rendering on top of the spec.

## Appendix B — error message shape

Every parser error follows:

```
kriya <util>: error: <message>
```

`<message>` is one of a fixed set:

- `unknown option '--<long>'`
- `unknown option '-<c>'`
- `option '--<long>' requires a value`
- `option '-<c>' requires a value`
- `option '--<long>' does not take a value`
- `option '--<long>' value '<v>' is not a valid <kind>`
- `expected <N> positional argument(s), got <M>`
- `-i requires stdin to be a terminal`

Agents can pattern-match these without parsing free-form prose.
