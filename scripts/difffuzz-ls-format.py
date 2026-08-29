#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over `ls`'s format x width matrix.

Usage:  python3 scripts/difffuzz-ls-format.py build/kriya [dirs] [seed]

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh` — those run kriya against
itself under the poisoned allocator; this runs kriya against the GNU binary on
the host, so it needs coreutils present and it is only as authoritative as the
version installed. Run it by hand when `ls`'s layout changes, and re-run it in
the `ubuntu:24.04` container as well, because the two coreutils differ.

⭐ It has earned its keep twice: it derived GNU's column separator rule (three
plausible models passed every hand-written case and only this separated them),
and it caught the column-fit model on the pass that widened its entry counts.

⛔ COMPARES BYTES, NOT LINES. The column POSITIONS were already identical before
1.6.8 while the separators were not — GNU tabs between columns and kriya used
spaces — so a comparison that strips whitespace passes over the exact defect
this release fixes. Everything goes through `cat -A`.
"""
import os, random, shutil, subprocess, sys, tempfile

# ⚠ ABSOLUTE. Every comparison runs with cwd set to a throwaway fixture
# directory, so a relative `build/kriya` resolves to nothing there.
KRIYA = os.path.abspath(sys.argv[1])
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 40
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1

FMT = ["-C", "-x", "-m", "-1", "", "--format=vertical", "--format=across",
       "--format=commas", "--format=single-column", "-C -1", "-1 -C", "-x -m", "-m -x"]
WID = ["-w 1", "-w 5", "-w 7", "-w 8", "-w 9", "-w 16", "-w 17", "-w 20", "-w 33",
       "-w 40", "-w 79", "-w 80", "-w 81", "-w 200", "-w 0", ""]
EXTRA = ["", "-i", "-F", "-a", "-r", "-t", "-i -F"]

def run(argv, cwd):
    env = dict(os.environ); env.pop("COLUMNS", None)
    p = subprocess.run(argv, cwd=cwd, capture_output=True, env=env, timeout=20)
    return p.returncode, p.stdout

diff = total = 0
examples = []
for i in range(N):
    rnd = random.Random(SEED * 7919 + i)
    d = tempfile.mkdtemp()
    # ⚠ Name LENGTHS are the variable that moves column boundaries on and off a
    # tab stop, so they are drawn per-entry rather than fixed.
    #
    # ⛔ AND THE COUNT MATTERS AS MUCH AS THE LENGTH. This capped at 26 entries and
    # missed a whole-column divergence: GNU seeds every column at 3 and re-tests the
    # fit only when one GROWS, so a directory of UNIFORMLY SHORT names gets one more
    # column than an arithmetic fit test allows — visible first at 52 one-character
    # names. Both knobs are widened: up to 120 entries, and a uniform-length mode
    # that keeps every column inside the 3-wide seed.
    if rnd.random() < 0.35:
        L = rnd.choice([1, 1, 2, 3])
        pool = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        want = rnd.randint(20, 120)
        seen = set()
        while len(seen) < want:
            nm = "".join(rnd.choice(pool) for _ in range(L))
            if nm in seen or len(seen) >= 62 ** L: break
            seen.add(nm)
        for nm in seen:
            try: open(os.path.join(d, nm), "w").close()
            except OSError: pass
    else:
        for k in range(rnd.randint(1, 120)):
            L = rnd.choice([1, 2, 3, 5, 6, 7, 8, 9, 13, 21])
            nm = "".join(rnd.choice("abcdefghijklmnopqrstuvwxyz0123456789_-.") for _ in range(L))
            if nm in (".", ".."): continue
            try: open(os.path.join(d, nm), "w").close()
            except OSError: pass
    for _ in range(14):
        args = (rnd.choice(FMT) + " " + rnd.choice(WID) + " " + rnd.choice(EXTRA)).split()
        total += 1
        gr, go = run(["ls"] + args, d)
        kr, ko = run([KRIYA, "ls"] + args, d)
        if (gr, go) == (kr, ko):
            continue
        diff += 1
        if len(examples) < 6:
            examples.append((args, gr, kr, go[:120], ko[:120]))
    shutil.rmtree(d)

print("ls format matrix: %d/%d differ (%.2f%%)" % (diff, total, 100.0 * diff / max(total, 1)))
for e in examples: print("DIFF:", e)
sys.exit(1 if diff else 0)
