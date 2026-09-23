# Getting started with kriya

kriya ships thirty-eight utilities in one static binary. This guide covers building it, how the
dispatcher routes a command, the shared library, and the loop for changing or adding a utility.
The current version and per-utility status are in [`../development/state.md`](../development/state.md).

## Build and test

```sh
cyrius deps                                    # resolve the pinned stdlib into lib/
cyrius build src/main.cyr build/kriya          # the dispatcher, for Linux x86-64
cyrius build --agnos src/main.cyr build/kriya_agnos
cyrius test                                    # tests/kriya.tcyr and tests/kriya-posix.tcyr
cyrius bench tests/kriya.bcyr                  # in-process micro-benchmarks
for s in scripts/smoke-*.sh; do sh "$s"; done  # behaviour, compared with the local GNU tools
sh scripts/fuzz.sh                             # the *.fcyr harnesses under a poisoned allocator
```

⚠ The smoke scripts compare kriya against the GNU coreutils, findutils and grep on the host, byte
for byte and exit status included, so those must be installed. `sh scripts/check-oracles.sh` prints
which binary each comparison will really run; a `find` that is secretly `bfs`, or a `printf` that is
the shell builtin, would make a wrong answer look right.

## The dispatcher

```sh
ln -s "$(pwd)/build/kriya" /usr/local/bin/cp   # a symlink per utility
cp a b                                         # argv[0] is `cp`: the cp utility runs
./build/kriya cp a b                           # or name it: argv[1] is the utility
./build/kriya --list                           # every utility, as JSON
./build/kriya cp --help                        # the page; --help=json for agents
```

```
shell ──exec(cp)──→ cp (symlink → kriya)
                        ↓
                    src/main.cyr: dispatch("cp", start)
                        ↓
                    the utility table: _util_add("cp", &cmd_cp, &cp_help_declare)
                        ↓
                    cmd_cp(start) in src/cmd/cp.cyr
```

`start` is where the utility's own arguments begin in argv: 1 for the symlink form, 2 for
`kriya cp`. This is the BusyBox pattern, [ADR 0001](../adr/0001-busybox-dispatcher-vs-n-binaries.md).

## The shared library

Each utility is one file in `src/cmd/`, and what they have in common lives in `src/lib/`:

| Module | What it holds |
|---|---|
| `args.cyr` | the option parser around the stdlib's flags, and number parsers that never wrap |
| `help.cyr` | `--help`, `--help=json` and `--version`, from each utility's declaration |
| `exit.cyr` | `EXIT_SUCCESS` / `EXIT_FAILURE` / `EXIT_USAGE` ([ADR 0008](../adr/0008-posix-exit-code-policy.md)) |
| `errmsg.cyr` | errno → message |
| `report.cyr` | the one diagnostic line, `kriya <util>: <operand>: <message>` ([architecture 001](../architecture/001-errno-message-policy.md)) |
| `quote.cyr` | GNU's shell-escape quoting, for `ls`, `stat %N` and every diagnostic |
| `str.cyr` | backslash escapes, and unsigned digits |
| `sys.cyr` | the syscall layer, both targets, and the write-failure net |
| `fs.cyr` | `*at()` traversal, stat helpers, `fs_realpath` |
| `path.cyr` | path primitives |
| `glob.cyr` | fnmatch-style matching |
| `icase.cyr` | ASCII case folding for BRE patterns |
| `protected.cyr` | the `/` refusal ([ADR 0004](../adr/0004-rm-refuses-root.md)) |
| `backup.cyr` | `-b` / `--backup=CONTROL` / `-S`, for `cp`, `mv` and `ln` |
| `userdb.cyr` | `/etc/passwd` and `/etc/group`, parsed directly |
| `spawn.cyr` | fork, exec and wait, keeping stderr and every exit outcome distinct |
| `argbatch.cyr` | command lines that fit, counted as GNU counts ([ADR 0026](../adr/0026-batched-exec-counts-a-command-line-as-gnu-does.md)) |

## Adding or changing a utility

The loop CLAUDE.md § *Process* describes, in the shape the code takes:

1. **Roadmap check.** The work has a slot in the [roadmap](../development/roadmap.md), or an ADR
   justifies it.
2. **Measure first.** Read the POSIX page, then measure GNU — on the host and in the
   `ubuntu:24.04` container, since GNU versions disagree — before writing anything.
   [`lessons.md`](../development/lessons.md) is the list of ways this has gone wrong.
3. **The utility.** `src/cmd/<util>.cyr` holds a flags spec (`flags_new()`, `flags_add_bool`,
   `flags_add_str`), a `<util>_help_declare()` record (`help_begin`, `help_positional`,
   `help_exit`, `help_example`) and `fn cmd_<util>(start: i64): i64`, which parses with
   `kriya_args_parse(spec, start)` and reports through `errmsg_report` or `report_note`.
4. **Wire it.** `include "src/cmd/<util>.cyr"` in `src/main.cyr`, and one `_util_add` line in
   `util_table_init`.
5. **Tests.** `tests/kriya.tcyr` for pure helpers, and `scripts/smoke-<util>.sh` comparing stdout
   bytes and the exit status with GNU. ⚠ Run the new assertions against the previous release's
   binary as well: an assertion that passes on both has proved nothing.
6. **The gate.** Build both targets; `cyrius test`; `cyrius lint` on each touched file;
   `cyrius vet src/main.cyr`; `sh scripts/lint-deferrals.sh`; `sh scripts/lint-help-schema.sh`; every
   smoke script; `sh scripts/fuzz.sh`; `python3 scripts/watchlist-scan.py`.
7. **Documentation.** An ADR for an option-set decision or a deviation from POSIX or GNU. At
   release: the CHANGELOG entry (released items only), the `state.md` entry and rows, and the
   roadmap slot removed.
8. **Version.** `sh scripts/version-bump.sh X.Y.Z` writes `VERSION` and `src/version_str.cyr` and
   inserts the `state.md` stub.

## Safety defaults for destructive utilities

- **`rm` refuses `/`, with no escape hatch.** There is no `--no-preserve-root`
  ([ADR 0004](../adr/0004-rm-refuses-root.md)); `rm -r link/` on a symlink to a directory is refused
  too ([ADR 0010](../adr/0010-rm-refuses-a-trailing-slash-symlink-operand.md)).
- **No recursion without `-r`, no force without `-f`.**
- **`cp` will not replace an existing file** unless `-f`, `-i`, `-n` or a backup says how
  ([ADR 0024](../adr/0024-cp-and-mv-resolve-force-interactive-and-no-clobber-as-gnu-does.md)); `mv`
  replaces, as POSIX says.
- **Symlinks are not followed on destructive paths** unless `-L` asks
  ([ADR 0003](../adr/0003-symlink-follow-policy.md)).
- **`-i` needs a terminal.** With no tty on stdin it is a usage error rather than a hang
  ([ADR 0002](../adr/0002-option-parsing-humans-and-agents.md)).

## Next

The [roadmap](../development/roadmap.md) for what is open, and [`../adr/template.md`](../adr/template.md)
for writing a decision record.
