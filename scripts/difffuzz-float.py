#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over printf's floating-point conversions, and seq.

Usage:  python3 scripts/difffuzz-float.py build/kriya [cases] [seed]

Each case is one directive (`%e %E %f %F %g %G %a %A` with random flags, width
and precision) over one value, run through `printf` on both sides under
`LC_ALL=C`; stdout and the exit status are compared. Then a tenth as many
`seq FIRST INCREMENT LAST` runs, with -w, -f and -s among them, compare GNU's
`long double` stepping. The values are weighted
toward what decides a rounding: short decimals whose halfway point the extended
format resolves differently from binary64, long digit strings, hex significands
with bits past the 64th, the subnormal edge, the overflow edge, and the
special values.

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh`: it measures kriya against
whatever coreutils is installed, and the x86_64 one at that. GNU's `printf`
uses `long double`, which is the 80-bit extended format only on x86; on aarch64
GNU's is binary128 and its digits differ (ADR 0032). Run it by hand when
`src/lib/xfloat.cyr` changes, and again in the `ubuntu:24.04` container.
"""
import random, subprocess, sys

KRIYA = sys.argv[1]
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1
ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
rnd = random.Random(SEED)

def value():
    r = rnd.random()
    if r < 0.30:     # short decimals: the halfway cases
        ip = rnd.randint(0, 99999)
        fd = rnd.randint(0, 6)
        s = str(ip) if fd == 0 else "%d.%0*d" % (ip, fd, rnd.randint(0, 10 ** fd - 1))
    elif r < 0.45:   # an exponent
        s = "%d.%de%d" % (rnd.randint(0, 9), rnd.randint(0, 999999), rnd.randint(-60, 60))
    elif r < 0.55:   # long digit strings
        s = "".join(rnd.choice("0123456789") for _ in range(rnd.randint(18, 60)))
        k = rnd.randint(0, len(s))
        s = s[:k] + "." + s[k:]
    elif r < 0.65:   # hex, with bits past the 64th
        s = "0x%x.%sp%d" % (rnd.randint(1, 15), "".join(rnd.choice("0123456789abcdef")
                            for _ in range(rnd.randint(1, 20))), rnd.randint(-80, 80))
    elif r < 0.72:   # extremes
        s = rnd.choice(["%d.%de4932", "%d.%de-4931", "%d.%de-4950", "%d.%de308", "%d.%de-320"]) % (
            rnd.randint(1, 9), rnd.randint(0, 9999))
    elif r < 0.78:   # around powers of two and ten
        s = rnd.choice(["0x1p%d", "0x1.fffffffffffffffep%d", "0x1.0000000000000001p%d",
                        "1e%d", "5e%d", "9.999999999999999999e%d"]) % rnd.randint(-70, 70)
    elif r < 0.82:
        s = rnd.choice(["0", "-0", "inf", "-inf", "nan", "-nan", "0x0p0", "1", "-1", "0.5", "2.5"])
    else:            # anything of a moderate size
        s = repr(rnd.uniform(-1e6, 1e6))
    if rnd.random() < 0.15 and s[0] not in "-+":
        s = "-" + s
    return s

def directive():
    flags = "".join(sorted(set(rnd.choice("-+ #0") for _ in range(rnd.randint(0, 3)))))
    width = "" if rnd.random() < 0.6 else str(rnd.randint(1, 40))
    prec = "" if rnd.random() < 0.3 else "." + str(rnd.choice([0, 0, 1, 2, 3, 5, 6, 10, 17, 20, 25, 40, 70]))
    return "%" + flags + width + prec + rnd.choice("eEfFgGaA")

def run(argv):
    p = subprocess.run(argv, env=ENV, capture_output=True, timeout=60)
    return p.stdout, p.returncode

diff = 0
BATCH = 50
cases = [(directive(), value()) for _ in range(N)]
for b in range(0, N, BATCH):
    chunk = cases[b:b + BATCH]
    fmt = "".join(d + "|" for d, _ in chunk)
    args = [v for _, v in chunk]
    g, gr = run(["/usr/bin/printf", "--", fmt] + args)
    k, kr = run([KRIYA, "printf", "--", fmt] + args)
    if g == k and gr == kr:
        continue
    # Narrow it down, one case at a time.
    for d, v in chunk:
        g1 = run(["/usr/bin/printf", "--", d, v])
        k1 = run([KRIYA, "printf", "--", d, v])
        if g1 != k1:
            diff += 1
            if diff <= 15:
                print("DIFF %-14s %-40r gnu %r rc=%d" % (d, v, g1[0][:120], g1[1]))
                print("     %-14s %-40s kri %r rc=%d" % ("", "", k1[0][:120], k1[1]))
print("printf: %d cases, %d differ" % (N, diff))

# --- seq: the same arithmetic, through `first + i * step` --------------------------------
def dec(lo, hi, maxfd):
    v = rnd.uniform(lo, hi)
    fd = rnd.randint(0, maxfd)
    s = "%.*f" % (fd, v)
    if rnd.random() < 0.1:
        s = "%.*e" % (rnd.randint(0, 3), v)
    return s

def seq_case():
    first = dec(-50, 50, 4)
    step = dec(0.001, 7, 4)
    if rnd.random() < 0.3:
        step = "-" + step
    if float(step) == 0:
        step = "1"
    n = rnd.randint(0, 40)
    last_v = float(first) + float(step) * n + rnd.uniform(-0.5, 0.5) * abs(float(step))
    last = "%.*f" % (rnd.randint(0, 5), last_v)
    if rnd.random() < 0.25:     # land exactly on the boundary the fix-up is for
        last = repr(float(first) + float(step) * n)
    args = [first, step, last]
    r = rnd.random()
    if r < 0.15:
        args = ["-w"] + args
    elif r < 0.35:
        fl = "".join(sorted(set(rnd.choice("-+ #0") for _ in range(rnd.randint(0, 2)))))
        args = ["-f", "%" + fl + rnd.choice(["", "8"]) + rnd.choice(["", ".0", ".2", ".7"]) +
                rnd.choice("efgEFGa")] + args
    elif r < 0.45:
        args = ["-s", rnd.choice([",", "", " | "])] + args
    return args

NS = max(1, N // 10)
sdiff = 0
for _ in range(NS):
    a = seq_case()
    g = run(["/usr/bin/seq", "--"] + a) if a[0] not in ("-w", "-f", "-s") else run(["/usr/bin/seq"] + a)
    k = run([KRIYA, "seq"] + a)
    if g != k:
        sdiff += 1
        if sdiff <= 10:
            print("SEQ DIFF %r\n  gnu %r rc=%d\n  kri %r rc=%d" % (a, g[0][:200], g[1], k[0][:200], k[1]))
print("seq: %d cases, %d differ" % (NS, sdiff))
sys.exit(1 if (diff or sdiff) else 0)
