# 0005 — Regex engine: Cyrius stdlib niyama, BRE + RE2, no PCRE in v1.0

**Status**: Accepted
**Date**: 2026-05-17

## Context

M5 brings kriya's first utilities that need a regular-expression engine: `grep` (and later, niche features in `nl -b p REGEX`, `find -regex`, `xargs -E`-ish patterns if those ship). POSIX `grep` defaults to **Basic Regular Expressions** (BRE — `\(...\)` groups, `\+` extension, `[[:class:]]`, no `+`/`?` literal); `grep -E` switches to **Extended Regular Expressions** (ERE — `(...)`, `+`, `?`, `{n,m}` all literal); `grep -F` is fixed-string and needs no engine. GNU `grep -P` adds PCRE — Perl-compatible with backrefs, lookaround, recursion, the lot.

Three forces shape the choice:

1. **Correctness over cleverness.** A wrong `grep` is "the output of the entire toolchain is wrong" — pipelines downstream of `grep` are everywhere in shell scripts. Linear-time matching guarantees beat constant-factor cleverness on a backtracking engine: a 30s `grep` hang on a 1 KB input is its own catastrophe.
2. **Static, zero-dep.** kriya is `static, zero-dep — no dynamic linking, no external deps beyond Cyrius stdlib` (`CLAUDE.md`). Pulling in PCRE2 the C library breaks both halves of that line.
3. **First-party "own the stack."** AGNOS-side first-party doctrine is: when a feature is in the path, own its implementation. Cyrius stdlib already ships a regex package — `lib/niyama.cyr` (folded v5.9.0) — that's the implementation we contribute to and benefit from upstream.

`niyama` exposes four flavors today:

| Flavor | ABI prefix | Status | Time complexity | Notes |
|---|---|---|---|---|
| BRE | `niyama_bre_*` | stable | linear (Pike NFA) | POSIX BRE, the `grep` default flavor. |
| RE2 | `niyama_re2_*` | stable | linear (Pike NFA) | POSIX ERE + niyama's RE2-flavor (inline flags `(?i)`, named groups). |
| PCRE | `niyama_pcre_*` | stable | exponential worst-case (backtracking) | Perl-compatible. Backref, lookaround, atomic groups, recursion. Has `niyama_pcre_set_step_limit` to cap runaway. |
| fuzzy | `niyama_fuzzy_*` | stable | linear | Levenshtein search. Not a grep flavor — useful for future `find -fuzzy` ideas, out of scope here. |

All four expose the same shape: `compile(pat) → nfa | 0`, `search(nfa, s) → start | -1`, `search_at(nfa, s, len, from) → start | -1`, `match(nfa, s) → 0|1`, `group_start/end(nfa, n) → i64`, and a thread-local `last_error()`. That uniformity lets kriya hot-swap engines per-flag without re-parameterising the call site.

## Decision

**kriya regex is niyama — exclusively. Default `grep` uses `niyama_bre_*`; `grep -E` uses `niyama_re2_*`; `grep -F` uses no engine (direct byte search). PCRE (`grep -P`) is not in v1.0 — deferred behind a named follow-up.**

### Engine mapping

| Caller flag | Engine | Why |
|---|---|---|
| `grep` (default, BRE) | `niyama_bre_*` | POSIX-compliant BRE flavor. Linear matching. |
| `grep -E` | `niyama_re2_*` | RE2 parser accepts the ERE form. Linear matching. |
| `grep -F` | none — byte search | Fixed strings; engines would just be overhead. Implemented as a `memmem`-style scan over the line buffer. |
| `grep -G` (alias for default) | `niyama_bre_*` | GNU-compatibility alias for "use BRE." |
| `grep -P` | **not in v1.0** | PCRE has exponential worst-case backtracking on adversarial input. See "PCRE deferral" below. |

### Case-insensitive (`-i`) handling

Per-engine, since the BRE engine has no inline flag syntax:

- **BRE + `-i`**: pre-transform both the pattern and the input. The pattern walks once, lowercasing literal letter bytes that are NOT inside `\(...\)` capture braces and NOT preceded by `\`. (Bracket-class contents `[A-Z]` are folded too — they're rare in practice and folding gives the user-expected "case-insensitive" semantics for ASCII.) The input lines are lowercased into a parallel byte buffer before each `niyama_bre_search` call. The original (un-lowercased) line is what gets printed.
- **RE2 + `-i`**: prepend `(?i)` to the compiled pattern. niyama's RE2 honors the inline flag.
- **`-F` + `-i`**: case-insensitive byte compare in the fixed-string scan.

The fold is ASCII-only — `A` through `Z` → `a` through `z`, period. Locale-aware folding (Turkish dotless-I, German ß) is deferred. Documented as a known limitation in `--help`.

### Hard rules (No-Gos)

1. **No external regex library.** No PCRE2 C lib, no oniguruma, no RE2 C++ lib. The engine ships in `lib/niyama.cyr` (Cyrius stdlib). If a feature is missing, the path is a niyama proposal against the cyrius repo, not a dep on a C library.
2. **No runtime engine selection by env var.** `KRIYA_REGEX_ENGINE=pcre` is not a thing. The engine is chosen by the user-visible flag (`-E`, `-F`, default). A future maintainer who wants a build-time alternative needs a new ADR.
3. **No silent engine fallback.** If `niyama_bre_compile` returns 0 (compile error), kriya emits a parse-error diagnostic and exits — it does not silently retry as RE2 or PCRE. The user asked for BRE; the user gets BRE-or-error.
4. **No PCRE features sneaking in through niyama_bre.** Backreferences (`\1`-`\9`) ARE POSIX BRE; they're honored. But Perl-isms like `(?=...)`, `(?<!...)`, `\K`, `(*COMMIT)`, etc. are not part of BRE or ERE and the engines reject them at compile time. We don't paper over the rejection.
5. **No catastrophic-backtracking surface.** Both engines we ship (BRE, RE2) are linear-time Pike NFAs. There is no pattern an attacker can craft that makes `grep` (or future `find -regex`) take exponential time on adversarial input. This is a security property, not just a performance one.
6. **No `-P` (PCRE) in v1.0.** See deferral below. The flag itself is rejected with a usage error explaining the choice — not silently mapped to `-E`.

### Mechanism

`grep` chooses its engine once at startup based on flag combinations, then dispatches all per-line searches through a small handle struct (engine kind + nfa pointer + lowercase-fold flag):

```cyrius
# Conceptual sketch.
struct GrepEngine {
    kind: i64,        # 0 = BRE, 1 = RE2, 2 = fixed-string
    nfa:  i64,        # 0 for fixed-string
    pat:  i64,        # raw pattern cstring (or fixed-string)
    pat_len: i64,
    fold: i64,        # 1 if -i (caller pre-folds input)
}

fn grep_match(eng, line, line_len): i64 {
    if (eng.kind == 0) { return niyama_bre_search_at(eng.nfa, line, line_len, 0); }
    if (eng.kind == 1) { return niyama_re2_search_at(eng.nfa, line, line_len, 0); }
    return fixed_string_find(eng.pat, eng.pat_len, line, line_len);
}
```

Multi-pattern (`-e PAT1 -e PAT2`, `-f FILE`) compiles N handles and the per-line check stops at the first match (logical-OR across patterns). All N handles share an engine kind; mixing `-E` and BRE in one invocation is forbidden by the flag parser (only one of `-E`/`-F`/default is allowed).

### PCRE deferral

PCRE (`grep -P`) is **not** in v1.0. The reasons:

- **Exponential worst-case.** PCRE is a backtracking engine. A pattern like `(a+)+$` against `aaaaaaaaaab` takes O(2^n) time. niyama_pcre exposes `set_step_limit` to bound this, but a step-limited PCRE is a half-engine — patterns that need backrefs are exactly the ones that hit step limits, so we'd ship a flag whose advertised capability is also its disclaimer.
- **Surface ratio.** POSIX `grep` is BRE; GNU adds `-E` for ERE. Both are covered. `-P` is GNU-only and used in a minority of `grep` invocations — usually by users who want lookaround. The cost/value tradeoff doesn't justify carrying the surface in v1.0.
- **niyama_pcre is available** for kriya v2.0+ if a real consumer asks. The mechanism is in place; the flag is the gate.

Until then, `kriya grep -P PATTERN` exits `2` with:

```
kriya grep: -P (PCRE) is not supported; use -E for extended regex
            or open an issue if you need PCRE features (backref, lookaround, etc.)
```

That's the teaching moment. We don't silently map to `-E` — `(?=foo)` is meaningless under ERE, and silent remapping would produce subtly wrong matches on a pattern that compiled.

### Multibyte / Unicode

ASCII only at v1.0. niyama operates on bytes. UTF-8 input mostly works for plain literal matches and `[a-z]`-style ASCII ranges (multi-byte sequences pass through as opaque bytes; literal-byte matches are exact). Character classes (`[[:alpha:]]`) match the ASCII subset only. Locale-aware folding, Unicode property classes (`\p{L}` in PCRE-speak), and multi-byte case-fold are deferred — same path as `tr` and `cut`: a UTF-8 decoder lands as a `lib/utf8.cyr` stdlib module, and grep grows the awareness when the decoder is available.

### Allocation lifetime

`niyama_*_compile` returns an `alloc()`-backed NFA pointer. We do NOT `fl_free` it — the NFA lives until process exit, which for `grep` is fine (one process per invocation, ~kilobytes per pattern). When/if kriya gains a persistent daemon mode (it doesn't; out of scope), an NFA destructor will need to ship in niyama.

## Consequences

- **Positive**
  - **One regex story across kriya.** Whatever utility lands later (`find -regex`, `nl -b p REGEX`, `sed`'s eventual sovereign-extraction target) builds on niyama, not on a per-utility hand-rolled engine.
  - **Linear-time matching is a security property.** No `grep` invocation can be made to hang exponentially by adversarial pattern + input. Pipelines, CI, and agents inherit this guarantee for free.
  - **Zero new external deps.** niyama is stdlib; nothing changes for kriya's build, packaging, or audit story.
  - **PCRE remains available for v2.0.** The engine is built into niyama; only the flag is gated. A future major version can flip the switch without redoing the integration.
- **Negative**
  - **`grep -P` is rejected, not graceful.** Some users will encounter the rejection and need to rewrite their pattern. The error message names `-E` as the migration path; we accept the rough edge.
  - **niyama features lag behind PCRE2** — no lookaround, no `\K`, no recursive subroutines. These are GNU-grep extensions via `-P`; absent in POSIX. Documented per-utility.
  - **The `-i` BRE byte-fold is fiddly.** A pattern like `[A-M]` under `-i` against folded input only matches `a-m`, not `A-M` literal — the user-expected semantics happen because the input is folded, but a pattern relying on the literal range stops working. Documented; the cleanest fix is upstream `(?i)` support in niyama_bre, which is a niyama proposal, not a kriya hack.
- **Neutral**
  - **niyama's release cadence matters more now.** A regex bug discovered through `grep` is a niyama bug; the fix path is the cyrius parent repo's stdlib. Our toolchain pin (`5.11.59` today) is the version niyama ships at.
  - **The fixed-string `-F` path is independent.** It uses no engine and is exercised separately in the smoke suite — a niyama outage would not block `-F` matches.

## Alternatives considered

- **PCRE2 (the C library).** Rejected — pulls in a dynamic dep, violates `static, zero-dep`. PCRE2 is also exponential worst-case; we'd own a step-limit story regardless.
- **RE2 (the Google C++ library).** Linear-time, the obvious shape. Rejected — C++ dep is worse than C dep for kriya's static link story. niyama's RE2-flavor engine gives us the same time complexity in-tree.
- **Hand-roll a Thompson NFA in `src/lib/regex.cyr`.** Rejected — niyama already exists, is tested, has POSIX BRE + ERE coverage, and reuses across other Cyrius consumers. Forking would be NIH for its own sake.
- **Use only niyama_re2 and reject `grep -G` (BRE).** Rejected — BRE is the POSIX `grep` default. Users who type `grep '\(foo\)' file` expect group capture; under RE2 the `\(` is a syntax error. Compatibility matters.
- **Ship `-P` mapped to niyama_pcre with `set_step_limit(1_000_000)`.** Rejected for v1.0 — a flag whose semantics depend on a step limit is a flag whose semantics are not stable. Patterns that compile and run on one input may fail on another. The user complaint shape ("grep -P used to work, now it errors out on this input") is one we don't want to own.
- **Defer the regex story entirely and ship `grep -F` only at M5.** Rejected — half of `grep` is the regex half. A `grep` that only does fixed strings would force every consumer to either build patterns up textually with `-e` (no) or to use a different tool, which kills the "kriya is the one toolbox" story.

## References

- ADR 0001 — BusyBox dispatcher (kriya is "one binary, many symlinks"; engine choices apply uniformly).
- ADR 0002 — Option parsing (no prefix matching, no silent fallback — applies here: `-P` rejection is loud).
- `lib/niyama.cyr` — bundled in `cyrius` parent repo, distlib v1.0.2, line 1022 (`niyama_bre_compile`), line 2344 (`niyama_re2_compile`), line 4239 (`niyama_pcre_compile`).
- POSIX `grep`: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/grep.html>
- POSIX BRE: <https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap09.html>
- GNU grep regex docs: <https://www.gnu.org/software/grep/manual/grep.html#Regular-Expressions>
