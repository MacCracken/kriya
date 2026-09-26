# `k_write`'s stall bound is ~200 s on agnos ≥ 1.57.9

- **Filed**: 2026-09-26
- **Repo**: kriya
- **Found by**: agnos 1.57.9 (end review of its blocking pipe writes)
- **Status**: OPEN

## What happens

`k_write` (`src/lib/sys.cyr`) retries a short/stalled write up to 20,000 times with `sched_yield` (#44) between tries. On agnos
≥ 1.57.7 a `#44` with nothing else READY parks the CPU until the next timer interrupt (~10 ms), and since 1.57.9 it never kicks
another CPU, so the bound is ~200 s, not "a short spin". A producer whose consumer is gone looks hung for minutes.

## Fix

Bound the stall by time, not by an iteration count (e.g. `uptime_ms`#40, a few seconds), and on agnos ≥ 1.57.9 prefer the blocking
pipe write (`write` with a4 = 0 blocks until a reader makes room; it returns the partial count or −1 when no reader is left — act on
that instead of retrying).
