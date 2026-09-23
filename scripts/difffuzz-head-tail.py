#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over `head` / `tail` count forms.

Usage:  python3 scripts/difffuzz-head-tail.py build/kriya [cases] [seed]

Draws command lines from the count grammars 1.6.15 implemented: the obsolescent
first argument (`head -3kv`, `tail +5c`, `tail -b`) and signed `-n` / `-c`
values with GNU's optional blanks and extra signs (`-n -+3`, `-c ' +3'`). Each
runs over five fixtures (ten lines, an unended last line, blank lines, an empty
file, and 1.2 MB of lines, past one read window), with stdin closed, and is
compared with the GNU binaries on the host on stdout bytes and exit status.

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh`, for the same reason as
`difffuzz-ls-format.py`: it measures kriya against whatever coreutils is
installed. Run it by hand when `src/cmd/head.cyr`, `src/cmd/tail.cyr` or the
count parser in `src/lib/args.cyr` changes. Built for GNU 9.11; under 9.4, which
REFUSES the oversized counts that 9.11 saturates, expect those to differ.

⭐ It found three GNU `tail` behaviours at 1.6.15 that the hand-written cases
did not: the `-n 0` early exit, the same exit for a `+N` of 2^63-1 or more, and
a negative zero (`-n --0`). kriya does not reproduce any of them
(`smoke-head-tail.sh` asserts its own answers), so each has a class below. Each
difference is put in a documented class, or counted as unexplained. The exit
status is 1 when any are unexplained.

⚠ Follow forms (`-f`, a trailing `f`) are left out: they never exit, so every
one would cost the timeout twice, and `smoke-head-tail.sh` compares three.
"""
import os, random, re, shutil, subprocess, sys, tempfile

KRIYA = os.path.abspath(sys.argv[1])
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1

ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
FILES = ["ten", "nonl", "blanks", "empty", "big"]
rnd = random.Random(SEED)


def digits():
    # ⚠ Twenty digits on purpose: past 2^64, where kriya used to wrap.
    k = rnd.choice([0, 1, 1, 2, 3, 20])
    return "".join(rnd.choice("0123456789") for _ in range(k))


def obs_head():
    letters = "".join(rnd.choice("cbkmlqvxn") for _ in range(rnd.choice([0, 1, 1, 2, 3])))
    return "-" + (digits() or "5") + letters


def obs_tail():
    t = rnd.choice("+-") + digits()
    if rnd.random() < 0.6:
        t += rnd.choice("bcl")
    if rnd.random() < 0.15:
        t += rnd.choice("xcl1")
    return t


def value():
    v = ""
    if rnd.random() < 0.15:
        v += rnd.choice([" ", "\t", "  "])
    if rnd.random() < 0.6:
        v += rnd.choice(["+", "-", "-", "+", "-+", "+-", "++"])
    if rnd.random() < 0.1:
        v += " "
    v += digits()
    if rnd.random() < 0.1:
        v += rnd.choice(["x", " "])
    return v


def run(argv, cwd):
    try:
        p = subprocess.run(argv, cwd=cwd, env=ENV, stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=10)
        return p.stdout, p.returncode
    except subprocess.TimeoutExpired:
        return b"<timeout>", -1


def documented(argv, g, k):
    """The class of a difference kriya chose (ADR 0023, smoke-head-tail.sh), or None."""
    u, first = argv[0], argv[1]
    ops = [a for a in argv[2:] if a != "--"]
    text = " ".join(argv[1:])
    # Both refuse; GNU says 1, kriya 2 (ADR 0008).
    if g[1] == 1 and k[1] == 2 and g[0] == b"" and k[0] == b"":
        return "both refuse"
    if u == "tail" and re.fullmatch(r"-[0-9]*[bcl]?", first) and len(ops) > 1 \
            and g[1] == 1 and g[0] == b"":
        return "a - form with 2+ operands (ADR 0023)"
    if u == "tail" and g == (b"", 0) and k[1] == 0 and len(ops) > 1:
        return "GNU's -n 0 / +HUGE early exit"
    if u == "tail" and g[1] == 0 and k[1] == 2 and re.search(r"(^|\s)-?\s*-0+(\s|$)", text):
        return "GNU tail's negative zero"
    return None


d = tempfile.mkdtemp()
try:
    with open(os.path.join(d, "ten"), "w") as f:
        f.write("".join("%d\n" % i for i in range(1, 11)))
    with open(os.path.join(d, "nonl"), "w") as f:
        f.write("a\nb\nc")
    with open(os.path.join(d, "blanks"), "w") as f:
        f.write("\n\n\n")
    open(os.path.join(d, "empty"), "w").close()
    with open(os.path.join(d, "big"), "w") as f:
        f.write("".join("%d\n" % i for i in range(1, 200001)))

    classes = {}
    unexplained = 0
    for _ in range(N):
        u = rnd.choice(["head", "tail"])
        fs = rnd.sample(FILES, rnd.choice([1, 1, 1, 2]))
        if rnd.random() < 0.45:
            tok = obs_head() if u == "head" else obs_tail()
            argv = [u, tok] + fs
            if rnd.random() < 0.2:
                argv = [u, tok, "--"] + fs[:1]
        else:
            opt = rnd.choice(["-n", "-c", "--lines=", "--bytes="])
            v = value()
            argv = [u, opt + v] + fs if opt.endswith("=") else [u, opt, v] + fs
        g = run(["/usr/bin/" + u] + argv[1:], d)
        k = run([KRIYA] + argv, d)
        if g == k:
            continue
        c = documented(argv, g, k)
        if c:
            classes[c] = classes.get(c, 0) + 1
            continue
        unexplained += 1
        if unexplained <= 10:
            print("DIFF %r: GNU exit %d, %d bytes; kriya exit %d, %d bytes"
                  % (argv, g[1], len(g[0]), k[1], len(k[0])))
finally:
    shutil.rmtree(d, ignore_errors=True)

for c, n in sorted(classes.items()):
    print("%6d  documented: %s" % (n, c))
print("%d cases, %d unexplained differences" % (N, unexplained))
sys.exit(1 if unexplained else 0)
