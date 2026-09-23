#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over name quoting, in six renderings.

Usage:  python3 scripts/difffuzz-quote.py build/kriya [names] [seed]

Each name is rendered by `stat -c %N` and by `ls -1d --quoting-style=X` for
shell-escape, shell, c, escape and locale, under `LC_ALL=C`, and the bytes are
compared against the GNU binaries on the host.

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh`, for the same reason as
`difffuzz-ls-format.py`: it measures kriya against whatever coreutils is
installed. Run it by hand when `src/lib/quote.cyr` changes, and again in the
`ubuntu:24.04` container.

⭐ It found two defects at 1.6.12 that 286 hand-derived cases and a 3,000-name
`%N` fuzz had not: a name that is exactly `{` or `}` is shell syntax and GNU
quotes it, and a leading `-` is NOT quoted — the 1.5.3 table said it was.

⛔ EVERY NAME GOES AFTER `--`, on both sides. The leading-`-` defect was born
from a harness that handed GNU `ls` a `-X` name without it: GNU parsed an
option, printed something else, and the difference was recorded as a quoting
rule. A name that parses as an option measures the option parser, not quoting.
"""
import os, random, shutil, subprocess, sys, tempfile

# ⚠ ABSOLUTE. Every comparison runs with cwd set to a throwaway directory.
KRIYA = os.path.abspath(sys.argv[1])
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1

ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
RENDER = [["stat", "-c", "%N"]] + [["ls", "-1d", "--quoting-style=" + s]
          for s in ("shell-escape", "shell", "c", "escape", "locale")]
# ⚠ Weighted toward the bytes the quoting rules are ABOUT. A uniform draw over
# 1-255 almost never produces a one-byte `{` or a `'` next to a control byte.
SPECIAL = [ord(c) for c in "'\"\\$`!#~ =[]{}*?;&|<>()\t\n-^%:,@"]

rnd = random.Random(SEED)
names = set()
while len(names) < N:
    # ⚠ ONE-BYTE NAMES ON PURPOSE: whether a byte is special can depend on it
    # being the whole name (`{`), which a length drawn from 1-12 rarely tests.
    length = 1 if rnd.random() < 0.2 else rnd.randint(1, 12)
    b = bytearray()
    for _ in range(length):
        r = rnd.random()
        if r < 0.35:
            b.append(rnd.choice(SPECIAL))
        elif r < 0.6:
            b.append(rnd.randint(97, 122))
        else:
            c = rnd.randint(1, 255)
            while c == 47:
                c = rnd.randint(1, 255)
            b.append(c)
    if bytes(b) not in (b".", b".."):
        names.add(bytes(b))

d = tempfile.mkdtemp()
diff = 0
try:
    for nm in sorted(names):
        path = os.path.join(d.encode(), nm)
        open(path, "wb").close()
        bad = []
        for cmd in RENDER:
            argv = [c.encode() for c in cmd] + [b"--", nm]
            g = subprocess.run([b"/usr/bin/" + argv[0]] + argv[1:], cwd=d, env=ENV,
                               capture_output=True, timeout=20).stdout
            k = subprocess.run([KRIYA.encode()] + argv, cwd=d, env=ENV,
                               capture_output=True, timeout=20).stdout
            if g != k:
                bad.append((" ".join(cmd), g, k))
        if bad:
            diff += 1
            if diff <= 10:
                print("DIFF", repr(nm))
                for c, g, k in bad:
                    print("   %-30s gnu %r" % (c, g))
                    print("   %-30s kri %r" % ("", k))
        os.unlink(path)
finally:
    shutil.rmtree(d, ignore_errors=True)
print("%d names x %d renderings, %d names differ" % (len(names), len(RENDER), diff))
sys.exit(1 if diff else 0)
