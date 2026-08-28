# 0017 — An environment variable may configure a feature the caller turned on; it may never turn one on

**Status**: Accepted
**Date**: 2026-08-27

## Context

kriya has declined behaviour-changing environment variables three times — `POSIXLY_CORRECT` for
`echo` ([ADR 0011](0011-echo-matches-the-non-xsi-binary-not-the-shell-builtin.md)) and for `pwd`,
`QUOTING_STYLE` for `ls` — each time on ADR 0011's reasoning:

> …costs a hidden environmental input in the most common one. The failure it enables is silent and
> acts at a distance — the environment variable and the broken `echo` are usually in different files.

But kriya also *reads* the environment: `LS_COLORS`, `COLUMNS`, `PATH`. Three refusals and three
acceptances with no stated rule between them is not a policy, it is a habit — and 1.6.5's backup
feature forces the question, because GNU's backups are governed by `VERSION_CONTROL` and
`SIMPLE_BACKUP_SUFFIX`. The roadmap has carried "decide it in an ADR, then build it" since 1.6.2.

⛔ **The distinguishing property is measurable, and measuring it found kriya on the wrong side of its
own line.** Ask: *with the feature's flag absent, does the variable change anything?*

| variable | with no relevant flag | |
|---|---|---|
| `POSIXLY_CORRECT` | `/usr/bin/echo 'a\tb'` prints a literal `a\tb`; with it set, a **real tab** | changes behaviour |
| `QUOTING_STYLE` | `ls` prints `has space`; with `QUOTING_STYLE=escape`, `has\ space` | changes behaviour |
| `LS_COLORS` | `kriya ls` emits no escape sequences whatever the variable says | **inert** |
| `VERSION_CONTROL` | `cp src dst`, `mv`, `ln` — no backup made, all three | **inert** |
| `SIMPLE_BACKUP_SUFFIX` | same — no backup made, all three | **inert** |
| `COLUMNS` | ⛔ **was NOT inert in kriya** — see below | fixed here |
| `PATH` | POSIX requires it to locate an executable; not a behaviour switch | out of scope |

All of it measured on this box, with the other variables explicitly unset.

## Decision

**An environment variable may configure a feature the command line has already turned on. It may
never turn one on, and it may never change what a command does when the feature's flag is absent.**

Applied:

- **`VERSION_CONTROL` and `SIMPLE_BACKUP_SUFFIX` are honoured**, because they are inert without
  `-b`/`--backup=` or `-S`/`--suffix=`. A caller who has not asked for backups cannot be given them
  by their environment. ⚠ This is not a softening of ADR 0011 — under the rule above, ADR 0011's
  refusal is *required*, because `POSIXLY_CORRECT` changes `echo` with no flag at all.
- **`POSIXLY_CORRECT` and `QUOTING_STYLE` stay declined**, now for a stated reason rather than a
  precedent.
- **`LS_COLORS` stays honoured.** It is inert without `--color`, measured.
- ⛔ **`COLUMNS` stops deciding the output format.** It sets the WIDTH of a columnar listing; it does
  not make a listing columnar. See below.

⚠ **Precedence is always: command line beats environment.** Measured against GNU and matched:
`VERSION_CONTROL=numbered cp --backup=simple` makes a simple backup, and
`VERSION_CONTROL=simple cp --backup=numbered` makes a numbered one.

### The violation this ADR found

⛔ **`kriya ls | while read f` could produce multi-column output.** `_ls_term_width` consulted
`$COLUMNS` before testing `isatty`, so an exported `COLUMNS` — bash sets and exports one in
interactive shells — turned a piped listing into several names per line. A script reading that gets
`file1  file2` as a single filename.

⚠ **The comment defending it was wrong, and it was load-bearing**: *"An explicit -w or $COLUMNS
forces columns even off a tty (a real GNU affordance + the host test hook)."* Measured — GNU does
neither:

```
$ COLUMNS=200 ls | cat     one name per line
$ ls -w 200 | cat          one name per line
$ ls -C | cat              columns          <- -C is what forces them
```

`$COLUMNS` is now read only when stdout is a terminal. ⚠ `-w` still forces columns, which GNU does
not, because kriya has no `-C` and removing `-w`'s behaviour without adding one would delete the
capability. Both are named at roadmap 1.6.8 and the divergence is asserted rather than incidental.

### What the rule does NOT license

- A variable that turns a feature on, however narrow. `KRIYA_RM_ALLOW_ROOT` would be refused by
  ADR 0004 and by this rule independently.
- A variable that changes a DEFAULT. `VERSION_CONTROL` selects among backup styles for a caller who
  asked for a backup; a hypothetical `KRIYA_CP_PRESERVE=all` would change what plain `cp` does, and
  is refused.
- Reading a variable a caller cannot see. Anything honoured under this rule must appear in the
  utility's `--help` next to the flag it configures.

## Consequences

- **Positive** — a testable rule replaces three precedents and one habit. "Is it inert without the
  flag?" is a question a reviewer can answer with a command.
- **Positive** — GNU parity on the backup feature, which is otherwise a *different feature* wearing
  the same flag names.
- **Positive** — a live script-breaking defect in `ls` is fixed, and it was found by applying the
  rule to the existing code rather than by a bug report.
- **Negative** — kriya's environment surface grows by two variables, and every one is a hidden input
  a reader of the command line cannot see. Mitigated by the inertness requirement: the flag is always
  present in the command that the variable affects, so the reader has a pointer.
- **Negative** — the rule has to be applied by hand to each new variable. There is no lint for it.
  ⚠ The smoke suites for the affected utilities carry the inertness assertion instead, which is where
  it would go red.
- **Neutral** — `PATH` sits outside the rule. It is not a behaviour switch; POSIX requires it to
  locate an executable at all, and `fs_resolve_in_path` already documents its own handling.

## Alternatives considered

- **Decline both backup variables and ship a kriya-only backup feature.** Rejected: `cp -b` whose
  style cannot be selected the way every script and every `~/.profile` selects it is a different
  feature with the same name, which is worse than either implementing it or omitting it. The roadmap
  said as much before the measurement did.
- **Honour them but only when the value is well-formed, ignoring a bad one.** Rejected: GNU exits 1
  with `invalid argument 'bogus' for '$VERSION_CONTROL'` and performs no copy. Silently ignoring a
  typo'd style is how a caller ends up with no backups and no message.
- **Keep the habit and decide case by case.** Rejected — that is what produced a `COLUMNS` violation
  nobody noticed for eleven releases, defended by a comment asserting a GNU behaviour that does not
  exist.
