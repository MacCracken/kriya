# Getting started with kriya

> **Status**: M0 scaffold — `kriya` has no utility implementations yet. This guide covers the build + dispatcher model. Real per-utility usage lands at M1 (v0.2.0).

## Build

```sh
cyrius deps                                    # resolve stdlib deps
cyrius build src/main.cyr build/kriya          # compile dispatcher
cyrius test                                    # run [build].test + tests/*.tcyr
cyrius bench tests/kriya.bcyr                  # benchmarks
```

The output binary is `build/kriya` — a **dispatcher**. To use individual utilities, create symlinks:

```sh
# Per-utility commands as symlinks → dispatcher
ln -s "$(pwd)/build/kriya" /usr/local/bin/cp
ln -s "$(pwd)/build/kriya" /usr/local/bin/mv
ln -s "$(pwd)/build/kriya" /usr/local/bin/rm
# ... etc
```

When you invoke `cp` (which is a symlink to `kriya`), the dispatcher reads `argv[0]`, sees `cp`, and routes to the `cp` utility code.

This is the **BusyBox pattern**. ADR 0001 captures the decision (single binary + symlinks vs N independent binaries).

## Conceptual model

```
shell ──exec(cp)─→ /usr/local/bin/cp (symlink → kriya)
                       ↓
                    dispatcher (src/main.cyr)
                       ↓
                    reads argv[0] = "cp"
                       ↓
                    looks up utility table → cmd_cp(argc, argv)
                       ↓
                    cp implementation in src/cmd/cp.cyr
                       ↓
                    exit
```

Each utility (`src/cmd/{util}.cyr`) is a self-contained function. Utilities share infrastructure from `src/lib/`:

- `lib/path.cyr` — path normalization, traversal-safe join
- `lib/exit.cyr` — POSIX exit-code constants
- `lib/errmsg.cyr` — errno → human-readable message
- `lib/args.cyr` — POSIX-style option parsing

## Layout

- `src/main.cyr` — dispatcher entry point. Reads `argv[0]`, dispatches to the named utility.
- `src/lib/*.cyr` — shared primitives used by every utility.
- `src/cmd/{util}.cyr` — one file per utility. Exports `cmd_{util}(argc, argv) -> i32`.
- `src/test.cyr` — top-level test entry referenced by `cyrius.cyml [build].test`.
- `tests/kriya.tcyr` — primary test suite (`cyrius test` auto-discovers).
- `tests/kriya.bcyr` — benchmarks (`cyrius bench`).
- `tests/kriya.fcyr` — fuzz harness (`cyrius fuzz`).

## Adding a new utility

The standard work loop (also captured in [`../../CLAUDE.md`](../../CLAUDE.md) § *Process*):

1. **Roadmap check** — utility is on the roadmap, or an ADR justifies inclusion
2. **POSIX research** — read the POSIX manual page for the utility. Capture any planned deviations in an ADR.
3. **Scaffold** — create `src/cmd/{util}.cyr`:

   ```cyrius
   include "../lib/path.cyr"
   include "../lib/exit.cyr"
   include "../lib/errmsg.cyr"
   include "../lib/args.cyr"

   fn cmd_{util}(argc, argv) -> i32 {
       // parse args, do the operation, return exit code
       return EXIT_OK;
   }
   ```

4. **Wire** — register in `src/main.cyr`'s dispatcher table:

   ```cyrius
   if (streq(util_name, "{util}")) { return cmd_{util}(argc, argv); }
   ```

5. **Tests** — `tests/kriya.tcyr` gains:
   - happy path
   - at least one error path (nonexistent input, permission denied, malformed args)
   - POSIX-compliance check per documented option
   - For destructive utilities (`rm`, `mv`, `cp -f`): TOCTOU test + symlink-safety test

6. **Benchmark** — `tests/kriya.bcyr` gains a perf test for the utility's typical workload

7. **Build + check** — `cyrius build`, `cyrius test`, `cyrius lint`, `cyrius vet` all clean

8. **Documentation** —
   - `CHANGELOG.md` `[Unreleased] / Added` — one-line entry with POSIX manual reference
   - `docs/development/state.md` per-utility status table — mark as ✅
   - If non-trivial: ADR for option-set decisions, behavior deviations, performance trade-offs

9. **Version sync** — bump `VERSION`, `cyrius.cyml`, CHANGELOG header at release time

## Running standalone (without symlinks)

If you don't want to create symlinks:

```sh
./build/kriya echo hello world      # dispatcher form — first arg is the utility name
./build/kriya cp foo bar
./build/kriya rm -rf /tmp/scratch
```

## Safety notes for destructive utilities

`rm`, `mv`, `cp` are the most dangerous tools in the toolbox. kriya's defaults are conservative:

- **No recursive without `-r`** — `rm directory/` is an error; `rm -r directory/` is the operation
- **No force without `-f`** — `rm file` against a read-only file or `cp` to an existing target prompts (interactive) or errors (non-interactive) by default
- **No following symlinks on destructive ops** — `cp /a /b` where `/a` is a symlink copies the symlink, not the target. `-L` opts in to follow.
- **`rm` refuses to operate on `/`** — `rm -rf /` requires `--no-preserve-root`. Even then, an extra confirmation prompt fires in interactive contexts.

ADR 0003 (M2) captures these defaults; deviations require an ADR amendment.

## Next

See [`../development/roadmap.md`](../development/roadmap.md) for the milestone plan and [`../adr/template.md`](../adr/template.md) for writing decision records.
