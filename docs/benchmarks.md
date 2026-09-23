# kriya — Benchmarks

**Last sampled**: 2026-09-23 (v1.7.0)
**Hardware**: x86_64, Linux
**Comparison baseline**: the host's GNU tools — coreutils 9.11, findutils 4.11, grep 3.12

This document is **descriptive, not promissory**. kriya's bias is "correctness over cleverness"; the
numbers show where that trade-off is visible and where it is not. Every open gap has a roadmap slot,
named below.

## Cold start

End-to-end process spawn cost for `./build/kriya true`: ELF startup, `args_init()`'s
`/proc/self/cmdline` read, the heap bootstrap, the kernel's `execve`, and dispatch through the
`argv[0]` match.

| What | Time |
|---|---|
| `kriya true`, per spawn (100 runs, batch-timed) | **0.549 ms** |
| `kriya --list`, all 38 utilities as JSON | 1.335 ms |

**v1.0 target**: under 2 ms. **Status**: met, with about 70% of the budget to spare.

⚠ **Earlier figures (about 1.2 ms, v0.2.0 to v0.8.0) measured something else.** They timed each run
between two `date` calls, so every sample included a whole `date` process — measured at about
0.57 ms. `scripts/bench-coldstart.sh` now times a batch of runs and subtracts the loop's own cost;
its header records the mistake.

Rerun: `RUNS=100 sh scripts/bench-coldstart.sh`.

## Throughput against GNU (v1.7.0)

Best of three, wall clock. Corpus: 65,536 lines of 16-byte text scaled to 1, 10 and 100 MiB, and a
10,000-entry tree (100 directories × 100 files).

| Utility | Workload | kriya | GNU | Ratio | Roadmap |
|---|---|---|---|---|---|
| `wc -l` | 100 MiB | 0.391 s | 0.014 s | 27.9× slower | — |
| `wc -c` | 100 MiB | 0.397 s | 0.002 s | 198× slower | 1.9.0 |
| `wc -w` | 100 MiB | 0.397 s | 0.099 s | 4.0× slower | — |
| `grep` literal | 10 MiB | 0.091 s | 0.002 s | 45.5× slower | 1.9.2 |
| `grep` regex | 10 MiB | 3.051 s | 0.002 s | 1,526× slower | 1.9.2, upstream |
| `grep -F` | 10 MiB | 0.089 s | 0.002 s | 44.5× slower | 1.9.2 |
| `grep -A 3` / `-B 3` / `-C 3` | 10 MiB | 0.091–0.112 s | 0.002 s | 46–56× slower | 1.9.2 |
| `sort` | 1 MiB | 0.095 s | 0.007 s | 13.6× slower | — |
| `find` | 10K tree | 0.029 s | 0.006 s | 4.8× slower | 1.9.4 |
| `cp` | 10 MiB file | 0.002 s | 0.008 s | 4× **faster** | 1.9.3 |
| `head -n 100` | 10 MiB | 0.002 s | 0.002 s | equal | — |
| `tail -n 100` | 10 MiB | 0.020 s | 0.002 s | 10× slower | 1.9.1 |

## Exec and argument handling

Measured at 1.6.17 and 1.7.0, against GNU on the same box:

| What | kriya | GNU |
|---|---|---|
| `rm -f` of 20,000 missing names (the argument table) | 67 ms | 73 ms |
| `find` over 25,000 files, `-exec true {} +` | 48 ms | 20 ms |
| the same, `-exec true {} ;` (one process per file) | 12,472 ms | — |
| `xargs -n1 true` over 80,000 items: time / peak memory | 42.6 s / 18.4 MB | 52.8 s / 18.3 MB |
| `printf '%100000000d'` through a pipe | 84 ms | 98 ms |

## Where kriya wins, where it loses, and why

**Close to GNU or better:**
- `cp` — a straight read/write loop with 64 KiB buffers; the kernel's copy offload would only matter
  on larger files.
- `head -n N` — both stop at the Nth line.
- process-heavy work — spawning, batching and argument handling now track GNU closely.

**Measurably slower:**
- `wc -c` (198×) — GNU answers a regular file from `stat`; kriya reads every byte (roadmap 1.9.0).
- `grep` — literal, `-F` and context searches take kriya's own byte scanner (about 45×); regular
  expressions go through niyama's Pike VM, linear-time but without GNU's DFA and Boyer-Moore (about
  1,500×). The regex speed is upstream Cyrius work (roadmap 1.9.2).
- `tail -n N` (10×) — kriya reads the input forward, where GNU seeks from the end (roadmap 1.9.1).
- `sort` (13.6×) and `find` (4.8×) — per-record overhead in kriya's comparison and predicate code.
- Line-at-a-time output — `nl`, `printf` and `stat` write each piece in its own system call:
  `nl` over 500,000 lines takes 776 ms against GNU's 42 ms (roadmap 1.9.5).

**Why the design favours correctness:** `grep` uses niyama because regex correctness on adversarial
input matters more than literal-scan speed, and the alternative is a second, hand-written engine —
more code, more attack surface, and a path that diverges from the niyama other Cyrius consumers use.
A consumer that needs `grep` throughput on a hot path today should use GNU `grep`; kriya targets the
correctness-and-policy lane: no `-P` regex denial of service, no symlink-follow surprises,
deterministic exit codes.

## Reproducing

```sh
cyrius build src/main.cyr build/kriya
RUNS=100 sh scripts/bench-coldstart.sh
sh scripts/bench-throughput.sh
```

The throughput script builds its corpus deterministically in a temporary directory; results repeat
within about 5% from run to run, the variance coming from page-cache warmth and scheduler noise.

## What this isn't

- **Not a microbenchmark.** Steady-state, in-process costs live in `tests/kriya.bcyr`
  (`cyrius bench tests/kriya.bcyr`), without process spawn or I/O; they help when optimising one
  helper.
- **Not a regression gate.** Builds do not fail when these numbers move within reason. The cold-start
  target is the only hard gate.
- **Not marketing.** kriya is slower than GNU at hot loops over big inputs, and this page says so,
  so that consumers can choose.
