# kriya — Benchmarks

**Last sampled**: 2026-05-18 (v0.8.0)
**Hardware**: x86_64
**Comparison baseline**: GNU coreutils (`/usr/bin/wc` etc.)

This document is **descriptive, not promissory**. kriya's bias is "correctness over cleverness" — the numbers below show where that trade-off is visible and where it isn't. Known gaps have named follow-ups; nothing here is "TBD."

## Cold-start dispatcher latency

End-to-end process spawn cost for `./build/kriya true`. Captures ELF startup, `args_init()`'s `/proc/self/cmdline` read, the heap bootstrap, the kernel `execve`, and dispatch through `argv[0]`-basename matching.

| Version | Median | Min | Max | Notes |
|---|---|---|---|---|
| v0.2.0 (M1 close) | 1.185 ms | — | — | 6 utilities |
| v0.3.0 (M2 close) | 1.159 ms | — | — | 13 utilities |
| v0.4.0 (M3 close) | 1.208 ms | — | — | 20 utilities |
| v0.5.0 (M4 close) | 1.198 ms | — | — | 30 utilities |
| v0.6.0 (M5 close) | 1.192 ms | — | — | 33 utilities |
| v0.7.0 (M6 close) | 1.212 ms | — | — | 38 utilities |
| **v0.8.0 (M7 close)** | **1.201 ms** | 1.036 ms | 1.379 ms | 38 utilities; no new dispatch entries |

**v1.0 target**: median under 2 ms. **Status**: comfortably under (1.2 ms, 60% of budget).

The flat trend across milestones is by design — the dispatcher resolves matches sequentially with `true` first, so new utilities land *after* the hot path and don't shift the common-case latency.

Rerun: `RUNS=100 scripts/bench-coldstart.sh`.

## Per-utility throughput vs GNU (v0.8.0, M8)

3-run median wall clock. Corpus: 65,536 lines × deterministic 16-byte text scaled to 1/10/100 MiB; 10,000-entry directory tree (100 dirs × 100 files).

| Utility | Workload | kriya | GNU | Ratio | Notes |
|---|---|---|---|---|---|
| `wc -l` | 100 MiB | 0.402 s | 0.011 s | **36.6×** slower | byte-by-byte newline scan; SIMD not used |
| `wc -c` | 100 MiB | 0.401 s | 0.002 s | **200×** slower | GNU `-c` short-circuits to `stat().st_size` for regular files |
| `wc -w` | 100 MiB | 0.404 s | 0.177 s | **2.3×** slower | byte-by-byte word-boundary detection |
| `grep` literal | 10 MiB | 4.648 s | 0.002 s | **2324×** slower | niyama BRE Pike NFA; GNU uses Boyer-Moore for literals |
| `grep -E` regex | 10 MiB | 4.951 s | 0.002 s | **2476×** slower | same Pike-NFA gap |
| `grep -F` fixed | 10 MiB | 0.085 s | 0.002 s | **42.5×** slower | in-tree byte-scan (no regex engine); still buffer-bound |
| `sort` | 1 MiB | 0.100 s | 0.080 s | **1.25×** slower | in-memory stable merge sort; comparable to GNU |
| `find` | 10K-tree | 0.029 s | 0.006 s | **4.8×** slower | `fs_getdents64` walk + predicate AST eval |
| `cp` | 10 MiB file | 0.001 s | 0.004 s | **0.25×** (faster) | 64 KiB read/write loop wins for small files |
| `head -n 100` | 10 MiB | 0.001 s | 0.002 s | **0.5×** (faster) | early-exit on line count |
| `tail -n 100` | 10 MiB | 0.025 s | 0.002 s | **12.5×** slower | buffer-and-back-walk; GNU uses seek-from-end |

## Where kriya wins, where it loses, and why

**Wins** (kriya equal-to-better than GNU):
- `cp` for small/medium files — straightforward read/write with 64 KiB buffers. No syscall overhead from Linux-specific copy-on-write (`copy_file_range`) but the gap is invisible at this size.
- `head -n N` — early-exit on line count; both implementations are limited by the I/O floor.
- `sort` (within 25%) — in-memory stable merge sort is competitive with GNU's quicksort-with-merge-spill for inputs that fit RAM.

**Losses** (kriya measurably slower):
- `wc -c` (200×) — GNU short-circuits to `stat().st_size` for regular files. kriya's read-and-count works for stdin pipes but pays this cost on file operands too. Named follow-up: `wc -c` short-circuit for regular-file operands.
- `grep` literal/regex (2300-2500×) — kriya uses niyama's Pike NFA engine (linear-time, no backtracking). GNU uses Boyer-Moore for literals (skip-table-driven, sub-linear on miss). niyama doesn't ship a literal-fast-path. Named follow-up: `niyama_bre_compile_literal` detection + Boyer-Moore in the engine (upstream Cyrius work, not kriya).
- `grep -F` (42×) — even fixed-string scan is byte-by-byte. GNU `-F` uses Aho-Corasick or skip-table. Same upstream follow-up.
- `tail -n N` (12.5×) — kriya buffers up to 16 MiB and walks backwards. GNU uses `lseek(SEEK_END)` then back-scan in 8 KiB chunks. Named follow-up: seek-from-end fast path for seekable inputs (also called out in tail.cyr's header).
- `find` (4.8×) — predicate AST eval has overhead per entry; GNU is highly optimized. Acceptable for a v0.8 implementation.

**Why the design favors correctness:** the M5 grep ships niyama because (a) regex correctness on adversarial input matters more than literal-scan speed for the common case, and (b) the alternative is a hand-coded second engine — more code, more attack surface, and a divergent path against the niyama-upstream that other Cyrius consumers also use. The 2300× literal-scan ratio is real, and we document it. A consumer who needs `grep -F` throughput on a hot path today should use GNU `grep`; kriya targets the **correctness-and-policy** lane (no `-P` regex DoS, no symlink-follow surprises, deterministic exit codes).

## Named optimization follow-ups

Each of these has a concrete enabler — none is "TBD."

1. **`wc -c` regular-file fast path** — `wc.cyr` detects regular-file fd, returns `st_size` without reading. ~20 LOC, no architectural change.
2. **`niyama_*` literal/fixed-string fast path** — upstream Cyrius. When `niyama_bre_compile` is asked for a pattern with no special chars, build a Boyer-Moore skip table and use it in `search_at`. Affects `grep` and any other future niyama consumer (`find -regex`, `sed`).
3. **`tail` seek-from-end fast path** — for seekable input, `lseek(SEEK_END)`, then back-scan in 8 KiB chunks. Removes the 16 MiB cap on regular files and closes most of the 12× gap. `tail.cyr` header already names this.
4. **`find` predicate JIT (speculative)** — compile the predicate AST to a flat eval loop. Not committed to v1.0; speculative if benchmark pressure rises.
5. **`cp` `copy_file_range(2)`** — Linux-specific accelerated copy that lets the kernel reflink on supporting filesystems (btrfs, XFS reflink). Drops cp from O(bytes) to O(1) on same-FS. Speculative; check kernel availability assumption against AGNOS target.

## Reproducing

```sh
cyrius build src/main.cyr build/kriya
RUNS=100 scripts/bench-coldstart.sh
scripts/bench-throughput.sh
```

The throughput script generates its corpus deterministically under a tempdir; results are reproducible run-to-run within ~5%. Variance comes from page-cache warmth and kernel scheduler noise. Numbers in this document are best-of-3 from a freshly-built binary.

## What this isn't

- **Not a microbenchmark.** Steady-state in-process bench points live in `tests/kriya.bcyr` (`cyrius bench tests/kriya.bcyr`) — `path_basename_ptr` at 65 ns, `streq` at 31-34 ns, `cmd_true` at 6 ns, etc. Those measure pure-function cost without process-spawn or I/O; they help when optimizing a specific helper.
- **Not a regression gate.** kriya does not fail builds when these numbers move within reason. The v1.0 cold-start target (≤ 2 ms median) is the only hard gate, and it currently has 40% headroom.
- **Not a marketing exercise.** kriya is slower than GNU at hot loops on big inputs. That's a true statement and we document it here so consumers can choose accordingly.
