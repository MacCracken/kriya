# 0018 — `readlink` is silent by default, and `-v` is the only way back

**Status**: Accepted
**Date**: 2026-08-27

## Context

GNU ships two utilities that answer nearly the same question and disagree about whether to explain a
failure. Measured:

```
$ readlink plain            (nothing)          exit 1
$ realpath plain            realpath: plain: … exit 1
```

kriya's `readlink` printed `kriya readlink: plain: invalid argument`, matching neither GNU's
`readlink` nor any stated policy — it matched `realpath`, which is the utility next door.

⛔ **GNU reaches its verbose mode through `POSIXLY_CORRECT`, and that variable BEATS AN EXPLICIT
`-q`.** Measured:

```
$ POSIXLY_CORRECT=1 readlink -q plain
readlink: plain: Invalid argument
```

An environment variable overriding a flag the caller wrote is exactly what
[ADR 0017](0017-environment-variables-configure-features-the-caller-turned-on.md) forbids, so kriya
cannot copy GNU's mechanism even if it wanted GNU's default. The choice is therefore which of GNU's
two behaviours to be, with `-v` as the only door between them.

## Decision

**`kriya readlink` is silent on failure. `-v`/`--verbose` opts into the diagnostic.
`-q`/`--quiet` and `-s`/`--silent` request the default explicitly, and an explicit quiet flag beats
`-v` in either order. `POSIXLY_CORRECT` is not consulted.**

- ⚠ **`readlink -s` is NOT `realpath -s`.** Here it is a synonym for `-q`; there it means "do not
  expand symlinks". One letter, opposite meanings — which is why the two utilities do not share a
  flag table, however alike they look.
- The exit code is unchanged: 1 on failure, 0 on success, 2 for a usage error.

### Why silent, and not kriya's old verbose default

- `readlink` is the utility script authors wrap: `target=$(readlink -f "$x")`. A stray stderr line
  there is noise in a context that usually has nowhere to put it.
- GNU's asymmetry is not an accident of implementation; `realpath` is the *interactive* tool and
  `readlink` the *scripted* one, and the two defaults follow that.
- kriya's old default matched neither GNU utility exactly — it had `realpath`'s verbosity with
  `readlink`'s name.

## Consequences

- **Breaking.** A caller relying on kriya's diagnostic must add `-v`. Named in the CHANGELOG's
  Breaking section with that one-word migration.
- **Positive** — an explicit `-q` cannot be overridden by the environment, which GNU's can. That is
  ADR 0017 paying out rather than costing.
- **Negative** — a human running `kriya readlink foo` interactively now gets exit 1 and no
  explanation. Mitigated only by `--help`, which names `-v`. ⚠ This is the real cost and it is worth
  naming: silence is right for the scripted case and wrong for the interactive one, and the utility
  cannot tell them apart.
- **Neutral** — `realpath` stays verbose, so kriya now reproduces GNU's asymmetry deliberately rather
  than diverging from half of it accidentally.

## Alternatives considered

- **Keep the verbose default and add `-q`-family flags only.** Rejected: it leaves kriya diverging
  from GNU on the common invocation, in the direction that adds output to a pipeline.
- **Honour `POSIXLY_CORRECT` as GNU does.** Rejected twice over: ADR 0017 forbids a variable that
  changes behaviour with no flag present, and this particular variable additionally beats an explicit
  `-q`, which is worse than the general case the rule was written for.
- **Be silent only when stdout is not a tty.** Rejected: a tty test changes behaviour between an
  interactive run and the same command in a script, which is the failure mode `-i` already has to
  guard against elsewhere (ADR 0002). A flag the caller writes is legible; a tty test is not.
