# kriya

> **क्रिया** (Sanskrit: *action, operation, verb*) — the small, single-purpose utilities of AGNOS. Each program is one kriya.

A coreutils-equivalent for AGNOS, written in [Cyrius](https://github.com/MacCracken/cyrius): one repo,
one CHANGELOG, one toolchain pin — and one static binary that is every utility.

**Status**: released. v1.0.0 froze on 2026-05-18; the current version is in [`VERSION`](VERSION), and
[`docs/development/state.md`](docs/development/state.md) has the release-by-release record.
**License**: GPL-3.0-only.

## What it is

Thirty-eight POSIX-style command-line utilities — `cp`, `mv`, `rm`, `ls`, `find`, `grep`, `sort` and
the rest that an operating system expects to find — sharing one library of primitives:

- **One binary, many names.** `kriya` is a dispatcher that reads `argv[0]`, so a symlink named `cp`
  *is* the `cp` command, and `kriya cp a b` works as well. This is the BusyBox pattern
  ([ADR 0001](docs/adr/0001-busybox-dispatcher-vs-n-binaries.md)).
- **Shared infrastructure** in [`src/lib/`](src/lib/): argument parsing, errno messages, quoting,
  paths, filesystem walks, process spawning, command-line batching.
- **Static and zero-dependency.** No libc; a cold start costs about half a millisecond.
- **POSIX as the floor, GNU where scripts rely on it.** Behaviour is measured against GNU coreutils,
  findutils and grep, byte for byte, on two GNU versions. Every deliberate difference is an
  [ADR](docs/adr/).
- **Written for humans and agents alike.** Every utility answers `--help` and `--help=json`, and
  `kriya --list` describes them all as JSON
  ([ADR 0002](docs/adr/0002-option-parsing-humans-and-agents.md)).
- **Destructive utilities are conservative.** `rm` refuses `/` with no escape hatch
  ([ADR 0004](docs/adr/0004-rm-refuses-root.md)), `cp` will not replace a file unless told how,
  and symlinks are not followed on destructive paths unless asked
  ([ADR 0003](docs/adr/0003-symlink-follow-policy.md)).

## Utilities

| Category | Utilities |
|---|---|
| File operations | `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `touch`, `ln`, `stat` |
| Paths | `basename`, `dirname`, `realpath`, `readlink`, `which`, `pwd` |
| Listing | `ls` |
| Text streams | `echo`, `printf`, `head`, `tail`, `wc`, `cut`, `tr`, `tee`, `sort`, `uniq`, `nl` |
| Search and exec | `grep`, `find`, `xargs` |
| Disk usage | `df`, `du` |
| Miscellaneous | `date`, `sleep`, `yes`, `true`, `false`, `env`, `seq` |

The per-utility status table, with what each one implements and what is deferred to which release,
is in [`state.md`](docs/development/state.md). What comes next is in the
[roadmap](docs/development/roadmap.md).

## What's covered elsewhere

kriya does not re-implement what AGNOS already has a first-party answer for:

| If you want… | Use… |
|---|---|
| `cat` (file content viewer) | [owl](https://github.com/MacCracken/owl) |
| `vim` / `nano` / `vi` (text editor) | [cyim](https://github.com/MacCracken/cyim) |
| `git` (version control) | [sit](https://github.com/MacCracken/sit) |
| `htop` / `top` (process monitor) | [chakshu](https://github.com/MacCracken/chakshu) |
| `cd`, `alias`, `export`, `jobs` (shell state) | [agnoshi](https://github.com/MacCracken/agnoshi) builtins |

`pwd` is both: a shell builtin in agnoshi, and a utility here, as `/bin/pwd` is beside the builtin
elsewhere.

## Build and test

```sh
cyrius deps                                    # resolve the pinned stdlib into lib/
cyrius build src/main.cyr build/kriya          # the dispatcher
cyrius test                                    # unit + POSIX suites (tests/*.tcyr)
for s in scripts/smoke-*.sh; do sh "$s"; done  # behaviour, compared with the local GNU tools
sh scripts/fuzz.sh                             # fuzz harnesses under a poisoned allocator
```

The smoke scripts compare kriya's output and exit status with the GNU tools installed on the host,
so they need GNU coreutils, findutils and grep. `sh scripts/check-oracles.sh` confirms which binary
each comparison will actually run. The agnos target builds with
`cyrius build --agnos src/main.cyr build/kriya_agnos`.

To install, put `kriya` on `PATH` and add a symlink per utility:

```sh
for u in cp mv rm ls find grep sort; do ln -s kriya "$u"; done   # …and the rest
```

## Project layout

```
kriya/
├── VERSION                  # the version, and the only place it is written
├── cyrius.cyml              # the toolchain pin and build configuration
├── CHANGELOG.md             # released changes only
├── CLAUDE.md                # rules and process for agents working here
├── src/
│   ├── main.cyr             # the dispatcher: utility table, argv[0] routing, --list, --help
│   ├── lib/                 # shared primitives, one module per concern
│   └── cmd/                 # one file per utility: cmd_<util>(start)
├── tests/                   # kriya.tcyr (unit), kriya-posix.tcyr, *.fcyr (fuzz), kriya.bcyr (bench)
├── scripts/                 # smoke-*.sh, difffuzz-*.py, lints, benchmarks, version-bump.sh
└── docs/
    ├── adr/                 # decisions and why
    ├── architecture/        # non-obvious constraints
    ├── audit/               # dated audit reports
    ├── guides/              # how-tos
    ├── benchmarks.md        # kriya against GNU, measured
    └── development/         # roadmap.md, state.md, lessons.md
```

## Documentation

- [`docs/guides/getting-started.md`](docs/guides/getting-started.md) — building, the dispatcher, and
  adding a utility
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — open work, by release
- [`docs/development/state.md`](docs/development/state.md) — the current version, per-utility status
  and test totals, refreshed every release
- [`docs/development/lessons.md`](docs/development/lessons.md) — what has cost time before, and the
  compiler watchlist
- [`docs/adr/`](docs/adr/) — architecture decision records
- [`docs/architecture/`](docs/architecture/) — errno messages, signals, the root-deletion defence
- [`docs/benchmarks.md`](docs/benchmarks.md) — throughput and cold start against GNU
- [`CHANGELOG.md`](CHANGELOG.md) — what changed in each release

## Place in the AGNOS ecosystem

kriya sits below the shell (agnoshi) and above the kernel and the Cyrius stdlib. The shell runs a
kriya utility the way it runs any program: `cp foo bar` works because a `cp` symlink on `$PATH`
points at the dispatcher.

Standards: [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md) · [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)

## License

[GPL-3.0-only](LICENSE)
