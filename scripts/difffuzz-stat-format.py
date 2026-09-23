#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over `stat -c`'s printf-style directives.

Usage:  python3 scripts/difffuzz-stat-format.py build/kriya [formats] [seed]

Random formats of one to four `%[flags][width][.precision][H|L]C` directives
are rendered for a regular file, an empty file, a directory, a symlink and
`/dev/null`, under `TZ=UTC LC_ALL=C`, and the stdout bytes and the exit
status's zero-ness are compared against the GNU binary on the host.

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh`, for the same reason as
`difffuzz-ls-format.py`: it measures kriya against whatever coreutils is
installed. Run it by hand when `src/cmd/stat.cyr`'s engine changes, and again
in the `ubuntu:24.04` container.

⚠ TWO KNOWN, DELIBERATE DIFFERENCES are skipped rather than counted:
  - atime on the SYMLINK. Printing ` -> target` reads the link, which bumps its
    atime on a strictatime mount, so whichever binary runs second sees the
    other's read. A format with `%x` / `%X` on the link is not comparable.
  - GNU's stray `s` after `%N` on a symlink under the `0`, `#`, `+` or space
    flag (`%0N` prints `'l' -> 'f's`). kriya does not reproduce it: the byte is
    GNU appending its own conversion character to a format it built.
"""
import os, random, shutil, subprocess, sys, tempfile

KRIYA = os.path.abspath(sys.argv[1])
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1

ENV   = {"PATH": "/usr/bin:/bin", "TZ": "UTC", "LC_ALL": "C"}
CONVS = "nNAFUGmxyzwsbBohiugdrafDRtTXYZW"

rnd = random.Random(SEED)

def rand_fmt():
    parts = []
    for _ in range(rnd.randint(1, 4)):
        d = "%" + "".join(rnd.choice("-0+ #'") for _ in range(rnd.randint(0, 2)))
        if rnd.random() < 0.6:
            d += str(rnd.randint(0, 25))
        if rnd.random() < 0.5:
            d += "." + (str(rnd.randint(0, 13)) if rnd.random() < 0.8 else "")
        c = rnd.choice(CONVS)
        # `H` / `L` split a device number, so they only mean something before d/r.
        if c in "dr" and rnd.random() < 0.4:
            d += rnd.choice("HL")
        parts.append(d + c + rnd.choice(["|", " ", ""]))
    return "".join(parts)

# Is `k` exactly `g` with at most `limit` of GNU's stray `s` bytes removed? The
# byte follows the padded target, so it can land anywhere in the line.
def stray_s_only(g, k, limit):
    i = j = dropped = 0
    while i < len(g):
        if j < len(k) and g[i] == k[j]:
            i += 1; j += 1
        elif g[i:i + 1] == b"s" and dropped < limit:
            i += 1; dropped += 1
        else:
            return False
    return j == len(k) and dropped > 0

d = tempfile.mkdtemp()
try:
    with open(os.path.join(d, "f"), "w") as fh:
        fh.write("hello!\n")
    os.chmod(os.path.join(d, "f"), 0o640)
    open(os.path.join(d, "empty"), "w").close()
    os.mkdir(os.path.join(d, "dir"))
    os.symlink("f", os.path.join(d, "ln"))
    ops = ["f", "empty", "dir", "ln", "/dev/null"]
    bad = skipped = 0
    for _ in range(N):
        fmt, op = rand_fmt(), rnd.choice(ops)
        if op == "ln" and ("x" in fmt or "X" in fmt):
            skipped += 1
            continue
        g = subprocess.run(["/usr/bin/stat", "-c", fmt, op], cwd=d, env=ENV,
                           capture_output=True, timeout=20)
        k = subprocess.run([KRIYA, "stat", "-c", fmt, op], cwd=d, env=ENV,
                           capture_output=True, timeout=20)
        if g.stdout == k.stdout and (g.returncode == 0) == (k.returncode == 0):
            continue
        if op == "ln" and "N" in fmt and stray_s_only(g.stdout, k.stdout, fmt.count("N")):
            skipped += 1
            continue
        bad += 1
        if bad <= 10:
            print("DIFF %r %s\n   gnu %r rc=%d\n   kri %r rc=%d" % (
                fmt, op, g.stdout[:120], g.returncode, k.stdout[:120], k.returncode))
finally:
    shutil.rmtree(d, ignore_errors=True)
print("%d formats, %d differ, %d skipped (known, see the header)" % (N, bad, skipped))
sys.exit(1 if bad else 0)
