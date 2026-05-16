# kriya

> **क्रिया** (Sanskrit: *action, operation, verb*) — the small, single-purpose utilities of AGNOS. Each program is one kriya.

A coreutils-equivalent repository for AGNOS, in [Cyrius](https://github.com/MacCracken/cyrius). One repo, one CHANGELOG, one toolchain pin — many small static binaries.

**Status**: pre-release scaffold (v0.1.0, 2026-05-15). **License**: GPL-3.0-only.

## What it is

A collection of small POSIX-style command-line utilities — the `cp` / `mv` / `rm` / `mkdir` / `echo` / `wc` / `find` etc. that the rest of an OS expects to be present. Each utility is a separate binary; all share the kriya repo, build pipeline, and release cadence.

Think GNU coreutils, but:

- Each utility is small (~50–400 LOC Cyrius)
- All share infrastructure (path handling, output formatting, errno → message, argument parsing)
- One repo, not 20 — saves CHANGELOG / CI / docs duplication
- Static, zero-dep, fast cold start
- Verbs in the user's hands — every kriya is one verb the user invokes

## What's already covered elsewhere

`kriya` deliberately avoids re-implementing what AGNOS already has a sovereign answer for:

| If you want… | Use… | Not kriya |
|---|---|---|
| `cat` (file content viewer) | [owl](https://github.com/MacCracken/owl) | — |
| `vim` / `nano` / `vi` (text editor) | [cyim](https://github.com/MacCracken/cyim) | — |
| `git` (version control) | [sit](https://github.com/MacCracken/sit) | — |
| `htop` / `top` / `btop` (process monitor) | [chakshu](https://github.com/MacCracken/chakshu) | — |
| `cd`, `pwd`, `alias`, `export` (shell state) | [agnoshi](https://github.com/MacCracken/agnoshi) builtins | — |

These are mature first-party tools. `kriya` fills the gaps between them.

## In scope (planned)

The initial utility set (M1–M4 of the roadmap):

| Category | Utilities |
|---|---|
| File operations | `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `touch`, `ln`, `stat` |
| Path | `basename`, `dirname`, `realpath`, `readlink`, `which` |
| Listing | `ls` |
| Text streams | `echo`, `printf`, `head`, `tail`, `wc`, `cut`, `tr`, `tee`, `sort`, `uniq`, `nl` |
| Filtering | `grep`, `find`, `xargs` |
| Disk info | `df`, `du` |
| Time/misc | `date`, `sleep`, `yes`, `true`, `false`, `env`, `seq` |

Bigger utilities (`grep`, `find`, `sort` on giant inputs) may split into their own repos later — they start here; if a single one outgrows the "small, single-purpose" framing, it earns extraction. Until then, the per-repo overhead beats the splitting cost.

## Build

```sh
cyrius deps                                    # resolve stdlib deps
cyrius build src/main.cyr build/kriya          # compile dispatch entry
cyrius test                                    # run [build].test + tests/*.tcyr
```

The `kriya` binary itself is a **dispatcher** — it reads `argv[0]` (or `argv[1]` when invoked directly) and routes to the requested utility. Symlinks `cp`, `mv`, `rm`, etc. → `kriya` make each utility a first-class command. This is the BusyBox pattern; ADR 0001 captures the decision and the alternatives considered.

## Project layout

```
kriya/
├── VERSION
├── cyrius.cyml
├── CLAUDE.md, CHANGELOG.md, README.md, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, LICENSE
├── src/
│   ├── main.cyr                              # dispatcher entrypoint
│   ├── lib/
│   │   ├── path.cyr                          # path manipulation primitives
│   │   ├── exit.cyr                          # exit-code conventions
│   │   ├── errmsg.cyr                        # errno → human message
│   │   └── args.cyr                          # POSIX-ish argument parsing
│   └── cmd/
│       ├── cp.cyr, mv.cyr, rm.cyr, ...       # one file per utility
│       └── ...
├── tests/
│   ├── kriya.tcyr                            # unit suite
│   ├── kriya.bcyr                            # benchmark stub
│   └── kriya.fcyr                            # fuzz stub
└── docs/
    ├── adr/, architecture/, guides/, examples/
    └── development/
        ├── roadmap.md
        └── state.md
```

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — agent instructions for this repo
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — utility-by-utility milestone plan
- [`docs/development/state.md`](docs/development/state.md) — current version, sizes, in-flight utilities
- [`docs/guides/getting-started.md`](docs/guides/getting-started.md) — build, dispatcher model, adding a new utility
- [`docs/adr/`](docs/adr/) — architectural decisions

## Place in the AGNOS ecosystem

`kriya` sits below shells (agnoshi) and above the kernel + stdlib. The shell invokes kriya utilities the same way it invokes any other binary — `cp foo bar` works because there's a `cp` symlink in `$PATH` pointing at the kriya dispatcher.

Standards: [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md) · [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)

## License

[GPL-3.0-only](LICENSE)
