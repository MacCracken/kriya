# kriya `/bin` applets hang on AGNOS — stale 6.1.14 stdlib pin miscompiles the binary

- **Filed**: 2026-06-14
- **Repo**: kriya
- **kriya**: 1.1.4 (the fix; was broken through 1.1.3)
- **Status**: FIXED in **1.1.4** — cyrius pin 6.1.14 → 6.1.39, re-vendored, VERIFIED in QEMU (delegation PASS). Pending: iron mount-copy of the new `/bin/kriya` onto the agnos-fs data partition (`install-usb.sh --update` is ESP-only).
- **Companion**: [agnoshi `2026-06-14-bin-tool-launch-crashes-on-iron.md`](https://github.com/MacCracken/agnoshi/blob/main/docs/development/issue/2026-06-14-bin-tool-launch-crashes-on-iron.md) — exonerated (see there).

## Symptom

On AGNOS (iron **and** QEMU), every kriya `/bin` applet hangs the moment it's run from `agnsh` — `echo "Hello"`, `ls`, `mkdir`, `kriya true`, all of them. The shell + keyboard themselves are fine (the agnos 1.44.25 xHCI keyboard fix); the hang is the kriya child, and because agnos is single-core cooperative, the wedged child takes the prompt with it.

## Root cause (TESTED — not theory)

**kriya is pinned to cyrius `6.1.14`, and the 6.1.14-era vendored stdlib miscompiles the kriya binary** — the largest agnos `/bin` tool at **934 KB**. The miscompile manifests as an **infinite loop in the first `strlen`** call in `main()` (on the pointer `path_basename_ptr(argv(0))` returns). Re-vendoring/rebuilding against a **newer stdlib (≥ 6.1.37)** fixes it completely.

It is **size-gated**: smaller bins built with the *same* toolchain are fine. That's why it looked like "only the newer bins break" — the real axis is binary size, and kriya is the outlier.

### Evidence chain (all reproduced in QEMU, `qemu-system-x86_64` TCG, agnos 1.44.26)

1. **Reproduced** — not a stale on-disk binary, not iron-only, not getdents-specific. `agnsh-delegation-test.py` (claimed "QEMU-green" in agnos state.md) actually **FAILS**: the kernel serial dead-stops at the first kriya exec.
2. **Kernel exonerated** — temporary kernel markers around `execwait #37` showed `load-begin → load-done → ring3-enter` then hang, *identical* to `bnrmr` (which also prints `ring3-exit`). The kernel loads the 934 KB ELF and enters ring 3 correctly; kriya hangs in its **own ring-3 execution**.
3. **Localized inside kriya** — temporary markers in `main()` showed: reaches `main`, `alloc_init()` OK, `args_init()` OK, `argv(0)` OK, `path_basename_ptr` OK — then **hangs on the very next `strlen`** (`K:slen-name` prints, `K:slen-ok` never does). Note `path_basename_ptr` *internally* calls `strlen` successfully, so `strlen` the function is fine — it's a **miscompiled use** of the basename pointer, a codegen symptom, not a logic bug.
4. **Same toolchain, size-gated** — `bnrmr` (167 KB, pin 6.1.14) and doom (589 KB, pin 6.1.37) run fine through the exact same `execwait #37` path; only kriya (934 KB) hangs.
5. **The deciding variable is the stdlib pin** — clean re-vendor + rebuild, same compiler (cycc 6.2.2) both times:
   - pin **6.1.14** → kriya **HANGS** at `strlen`
   - pin **6.1.39** → kriya **WORKS**: `kriya true` exits clean, `echo Hello` prints `Hello`, `owl -p` prints `OWLPROOF`, `ls`/`mkdir`/`cp` all run (full `agnsh-delegation-test.py` green).
6. The 6.1.14 → 6.1.39 vendored stdlib differs across `alloc_agnos.cyr` (3458→4578 B), `alloc.cyr`, `atomic.cyr`, `str.cyr`, `vec.cyr`, `syscalls_x86_64_agnos.cyr`, etc. The underlying cyrius bug is already fixed upstream (≥ 6.1.37, the band doom rides), so this is a **consumer re-pin**, not a cyrius-side action item.

## Fix

1. **Bump the cyrius pin** in `cyrius.cyml`: `6.1.14` → `6.1.39` (verified) or current (`6.2.2`). doom proves the ≥6.1.37 band on a large agnos binary. *(This is a justified consumer bump to fix a real miscompile — not pin-drift chasing.)*
2. `rm lib/*.cyr && cyrius deps` (clean re-vendor) + `cyrius build --agnos src/main.cyr build/kriya_agnos`.
3. Re-stage into the AGNOS rootfs (`agnos/scripts/stage-tools.sh`) and, for iron, **mount-copy** the new `/bin/kriya` onto the agnos-fs data partition — `install-usb.sh --update` is ESP-only, so the agnos-fs `/bin` is otherwise untouched.

## Notes

- **owl was never broken.** Its "wedge" in the delegation test was collateral: the test ran `mkdir` (kriya) first, kriya hung, and everything after it (owl/cat/ls) never executed. With kriya fixed, `owl -p /hello.txt` prints `OWLPROOF` immediately.
- This is kriya's **M10 consumer-burn** signal landing for real: the first AGNOS boot-burn exercising kriya surfaced a toolchain-pin bug invisible to host smokes. The lesson for M11 (AGNOS-as-build-target): pin freshness needs to track the agnos-target codegen band, not lag it.
- A repro harness is checked in at `agnos/scripts/kriya-crash-probe.py` (graduated bareword ladder over the delegation image).
