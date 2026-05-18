# 0008 — POSIX exit-code policy: three-tier convention + per-utility specifics

**Status**: Accepted
**Date**: 2026-05-18

## Context

Exit codes are part of POSIX's API surface — a shell pipeline's behavior depends on what `if`, `&&`, `||`, and `$?` see. kriya's 38 shipped utilities each emit exit codes through `src/lib/exit.cyr`'s three-value enum:

```
EXIT_SUCCESS = 0      # successful invocation
EXIT_FAILURE = 1      # general failure
EXIT_USAGE   = 2      # usage error
```

This three-tier convention is consistent across every utility — `kriya cp /missing /tmp` exits 1, `kriya cp --bogus` exits 2, `kriya cp valid valid2` exits 0. The convention is good but **POSIX defines per-utility codes that override the generic 1**:

- `grep`: 0 (any match), 1 (no match), 2 (error). 1-on-no-match means "no match" is *not* an error.
- `find`: 0 (all ops succeeded), >0 (any error).
- `xargs`: 0, 123 (any child non-zero), 124 (child exit 255), 125 (xargs killed), 126 (child cannot execute), 127 (child not found).
- `env`: child's exit on success, 126 (cannot execute), 127 (not found).
- `test`/`[`: 0 (true), 1 (false), 2 (error).
- `diff`: 0 (no diff), 1 (diff), 2 (trouble).

Without a written policy, future utilities risk emitting the generic 1 where POSIX names a specific code, or worse — emitting `EXIT_FAILURE` where the POSIX code is *not* failure (grep's "no match" is the canonical trap).

The M7 audit catalogs the shipped utilities as conformant for exit codes, but the policy itself is unwritten. This ADR fixes that.

## Decision

**kriya follows POSIX exit codes everywhere POSIX names them, and uses the three-tier `EXIT_SUCCESS` / `EXIT_FAILURE` / `EXIT_USAGE` convention as the default fallback.**

**Three-tier baseline (applies to every utility unless POSIX overrides):**

| Code | Constant | Meaning |
|---|---|---|
| 0 | `EXIT_SUCCESS` | Successful invocation: every operand processed, no errors. |
| 1 | `EXIT_FAILURE` | General failure: per-operand error (missing file, permission denied) or invocation-wide failure. Multi-operand operations propagate `EXIT_FAILURE` if *any* operand failed. |
| 2 | `EXIT_USAGE` | Usage error: unknown option, missing required argument, invalid value, mutually-exclusive option conflict. **Distinguishable from `EXIT_FAILURE` so scripts can tell "I called it wrong" from "the operation failed."** |

**Per-utility overrides** — when POSIX names specific codes, those win:

| Utility | Code | Meaning |
|---|---|---|
| `grep` | 0 | Any match found across input. |
|  | 1 | No match (NOT an error — pipeline tools depend on this). |
|  | 2 | Filesystem error, regex compile failure, invalid options. `-s` suppresses 2 down to 1. |
| `find` | 0 | All operations succeeded. |
|  | 1 | Any operation failed (missing operand, predicate eval error, `-exec` non-zero return). |
|  | 2 | Usage error (unknown predicate, bad `-size` suffix, missing `-exec ;`). |
| `xargs` | 0 | All child invocations succeeded. |
|  | 123 | Any child exited non-zero. |
|  | 124 | Any child exited with status 255 (xargs convention for "stop processing"). |
|  | 125 | xargs itself was killed by a signal. |
|  | 126 | A child command was found but could not be executed (permission, etc.). |
|  | 127 | A child command was not found. |
|  | 2 | xargs usage error. |
| `env` | child's exit | Successful exec: env returns the child's exit code unchanged. |
|  | 126 | Command found but cannot execute (EACCES, ENOEXEC). |
|  | 127 | Command not found (ENOENT, ENOTDIR). |
|  | 2 | env usage error. |
| `diff` (future) | 0 | No differences. |
|  | 1 | Differences found. |
|  | 2 | Trouble (file not found, invalid options). |
| `test` / `[` (if shipped) | 0 | Expression evaluates to true. |
|  | 1 | Expression evaluates to false (not an error). |
|  | 2 | Syntax error in expression. |

**Multi-operand atomicity policy:** for utilities that take multiple operands (`cp foo bar dst/`, `rm a b c`, `wc a b c`), each operand is attempted independently. The invocation exits 1 if *any* operand failed; the others still get processed. Exception: `rm`'s protected-paths refusal (ADR 0004) is invocation-atomic — if any operand matches a protected path, *no* operand is touched and exit is 2.

**Implementation guidance:**

- Every `cmd_X` returns through one of the `EXIT_*` constants (or a per-utility specific code).
- Use `EXIT_FAILURE` (1), not raw `1`, in source. Same for `EXIT_USAGE`.
- Per-utility specific codes get named constants in the utility's own file (e.g. `_xargs_exit_child_failed = 123`) — don't hardcode magic numbers.
- The three-tier convention is the FLOOR. POSIX-named codes are the CEILING (utility-specific exits the script ecosystem depends on).

## Consequences

**Positive:**

- New utilities have a clear written rule to follow when they ship — read this ADR, find the per-utility table or fall back to the three-tier baseline.
- Scripts that depend on POSIX exit-code distinctions (`grep`'s no-match 1, `xargs`'s 123 vs 124) work against kriya identically to GNU. Pipeline compatibility holds.
- The `EXIT_USAGE` (2) vs. `EXIT_FAILURE` (1) split lets script authors write `if ! foo; then ...; elif [ $? -eq 2 ]; then echo "I called it wrong"; fi` without ambiguity.

**Negative:**

- The per-utility override table needs to grow when new utilities ship. M7 catalogs the current state; future audits (annual or on major-version cuts) must keep it current.
- A junior contributor writing a new utility might miss the per-utility table and ship generic-1 where a specific code applies. Mitigation: the `cyrius lint` rule list could grow a "POSIX exit-code check" for known utilities — deferred work.

**Neutral:**

- The three-tier baseline matches BSD coreutils convention. No conflict with the de facto Unix ecosystem.

## Alternatives considered

- **Generic-1-everywhere, ignore POSIX specifics.** Considered and rejected: would break `grep`-in-pipeline behavior, which is critical-path for thousands of common scripts. Non-starter.
- **Per-utility ADR for each exit-code table** (one ADR per `grep`, `xargs`, `env`, etc.). Considered and rejected: too much ADR surface for what's a single policy decision. The override table belongs in one place where future utilities can find it.
- **No three-tier baseline — just per-utility codes.** Considered: the three-tier `0/1/2` convention is "default unless overridden." Removing it would mean every new utility has to define its own exits. The baseline saves work without conflicting with POSIX overrides.
