#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over `printf`'s directives and number arguments.

Usage:  python3 scripts/difffuzz-printf.py build/kriya [cases] [seed]

Random FORMATs of literal text, escapes and `%[flags][width][.precision][len]C`
directives — `*` widths and precisions included, and fields past INT_MAX — are
run with random arguments drawn from number-shaped strings: edge values of i64
and u64 and just past them, hex and octal, signs, blanks, character constants,
junk after digits, the empty string. stdout bytes and the exit status are
compared against GNU's `/usr/bin/printf` under `LC_ALL=C`.

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh`, for the same reason as the
other `difffuzz-*.py`: it measures kriya against whatever coreutils is
installed. Run it by hand when `src/cmd/printf.cyr` changes.

⚠ KNOWN, DELIBERATE DIFFERENCES are skipped rather than counted:
  - `\\c` after a conversion error: GNU exits 0, kriya 1, as POSIX requires.
  - GNU 9.11's `%N$` positional arguments (roadmap 1.8.0); 9.4 refuses them, as
    kriya does. Never generated.
  - The floats and `%q`, which kriya refuses by name. Never generated.
  - No FORMAT at all (`printf --`): a usage error, exit 2 by ADR 0008, where
    GNU's *missing operand* exits 1.
"""
import os, random, subprocess, sys

KRIYA = os.path.abspath(sys.argv[1])
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1

ENV   = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
rnd   = random.Random(SEED)

NUMS = [
    "0", "1", "-1", "5", "-5", "+5", "42", "255", "-255", "007", "08", "010",
    "0x", "0x1f", "0X1F", "-0x10", "0xg", "0x1Fg", "099", "-0", "00",
    "9223372036854775807", "9223372036854775808", "-9223372036854775808",
    "-9223372036854775809", "18446744073709551615", "18446744073709551616",
    "-18446744073709551615", "-18446744073709551616", "99999999999999999999",
    "0x7fffffffffffffff", "0x8000000000000000", "-0x8000000000000000",
    "0xffffffffffffffff", "0x10000000000000000", "01777777777777777777777",
    "02000000000000000000000", "2147483648", "-2147483648",
    "-2147483649", "4294967296", " 5", "\t7", "\n9", "5 ", "5x", "abc", "", " ", "-", "+",
    "+-5", "-+5", "'A", "'AB", '"z', "'", "'\t", "12abc", "1e3", "3.5",
]
STRS = ["", "a", "abc", "hello world", "-x", "--", "%", "a\\nb", "x\\cy", "\\101"]

def rand_width():
    r = rnd.random()
    if r < 0.45:
        return ""
    if r < 0.8:
        return str(rnd.randint(0, 20))
    if r < 0.9:
        return "*"
    # Past INT_MAX: the field is not printed, never two gigabytes.
    return rnd.choice(["2147483648", "9223372036854775807", "18446744073709551617"])

def rand_prec():
    r = rnd.random()
    if r < 0.6:
        return ""
    if r < 0.85:
        return "." + rnd.choice(["", str(rnd.randint(0, 12))])
    if r < 0.95:
        return ".*"
    return "." + rnd.choice(["2147483648", "18446744073709551617"])

def rand_directive():
    if rnd.random() < 0.06:
        return rnd.choice(["%%", "%b", "%5%", "%-b", "%"])
    d = "%" + "".join(rnd.choice("-+ #0'") for _ in range(rnd.randint(0, 2)))
    d += rand_width() + rand_prec()
    if rnd.random() < 0.15:
        d += rnd.choice(["l", "ll", "h", "hh", "j", "z", "t", "L"])
    d += rnd.choice("diouxXdiuxcs") if rnd.random() < 0.95 else rnd.choice("Zk")
    return d

def rand_fmt():
    parts = []
    for _ in range(rnd.randint(1, 3)):
        r = rnd.random()
        if r < 0.7:
            parts.append(rand_directive())
        elif r < 0.9:
            parts.append(rnd.choice(["|", " ", "x", "\\n", "-"]))
        else:
            parts.append(rnd.choice(["\\t", "\\101", "\\x41", "\\c", "\\\\"]))
    return "".join(parts)

def rand_args():
    out = []
    for _ in range(rnd.randint(0, 4)):
        if rnd.random() < 0.8:
            out.append(rnd.choice(NUMS))
        elif rnd.random() < 0.5:
            out.append(rnd.choice(STRS))
        else:
            # A width-sized number for a `*`, small or out of int range.
            out.append(rnd.choice(["3", "-4", "0", "20", "-2147483648", "2147483648"]))
    return out

bad = skipped = 0
for _ in range(N):
    fmt, args = rand_fmt(), rand_args()
    g = subprocess.run(["/usr/bin/printf", fmt] + args, env=ENV,
                       capture_output=True, timeout=20)
    k = subprocess.run([KRIYA, "printf", fmt] + args, env=ENV,
                       capture_output=True, timeout=20)
    if g.stdout == k.stdout and g.returncode == k.returncode:
        continue
    cancelled = "\\c" in fmt or any("\\c" in a for a in args)
    if (cancelled and g.stdout == k.stdout and g.returncode == 0
            and k.returncode == 1 and g.stderr):
        skipped += 1
        continue
    if (b"missing operand" in g.stderr and g.stdout == k.stdout
            and k.returncode == 2):
        skipped += 1
        continue
    bad += 1
    if bad <= 12:
        print("DIFF %r %r\n   gnu %r rc=%d %r\n   kri %r rc=%d %r" % (
            fmt, args, g.stdout[:100], g.returncode, g.stderr[:160],
            k.stdout[:100], k.returncode, k.stderr[:160]))
print("%d cases, %d differ, %d skipped (known, see the header)" % (N, bad, skipped))
sys.exit(1 if bad else 0)
