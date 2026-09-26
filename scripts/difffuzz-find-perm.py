#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over `find -perm MODE`.

Usage:  python3 scripts/difffuzz-find-perm.py build/kriya [cases] [seed]

The fixture holds a file of EVERY mode, 0000 to 7777, and a directory of every
mode that is a multiple of 010 or sets a set-id or sticky bit. The directories
are there for `X`, which means execute only for a directory (or a mode that
already has an execute bit), so a mode string can match a directory and not the
file of the same mode. MODEs come from `chmod`'s grammar — octal, one to three
symbolic clauses of who / operator / permissions, copies (`g=u`), octal operands
after an operator — with `-`, `/` and `+` prefixes and malformed strings mixed
in. The listing `find FIX -mindepth 1 -maxdepth 1 -perm MODE` is compared,
sorted, and so is the refusal: GNU exits 1 on an invalid mode and kriya exits 2
(ADR 0008), so any non-zero status with nothing printed counts as a refusal.

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh`, for the same reason as the
other `difffuzz-*.py`: it measures kriya against whatever findutils is
installed. Run it by hand when `src/lib/mode.cyr` or `-perm` changes.

⚠ stderr is not compared: GNU warns that `-perm /000` changed meaning in 2007,
which is its own history and not kriya's (see `src/cmd/find.cyr`'s header).
"""
import os, random, shutil, subprocess, sys, tempfile

KRIYA = os.path.abspath(sys.argv[1])
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1

ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
rnd = random.Random(SEED)

def octal():
    r = rnd.random()
    if r < 0.8:
        s = "%o" % rnd.randint(0, 0o7777)
        if rnd.random() < 0.3:
            s = "0" * rnd.randint(1, 3) + s       # five digits and more mention the set-id bits
        return s
    if r < 0.9:
        return "%o" % rnd.randint(0o10000, 0o77777)   # past 07777: refused
    return rnd.choice(["8", "9", "18", "0x7", "7a", "00000000", "777777"])

def perms():
    if rnd.random() < 0.15:
        return rnd.choice("ugo")                      # a copy: g=u
    return "".join(rnd.choice("rwxXst") for _ in range(rnd.randint(0, 4)))

def clause():
    who = "".join(rnd.choice("ugoa") for _ in range(rnd.choice([0, 0, 1, 1, 2, 3])))
    out = who
    for _ in range(rnd.randint(1, 2)):
        out += rnd.choice("=+-")
        if rnd.random() < 0.07:
            out += octal()                            # valid only with no who, and last
        else:
            out += perms()
    return out

def mode():
    r = rnd.random()
    if r < 0.25:
        body = octal()
    elif r < 0.95:
        body = ",".join(clause() for _ in range(rnd.randint(1, 3)))
    else:
        body = rnd.choice(["", ",", "u+w,", ",u+w", "u+w,,g+w", "u", "z", "u+z", "=,",
                           "+", "-", "/", "a=r+", "go=u+x"])
    prefix = rnd.choice(["", "", "-", "-", "/", "/", "+"])
    return prefix + body

fix = tempfile.mkdtemp(prefix="kriya-perm-")
try:
    for m in range(0o10000):
        p = os.path.join(fix, "f%04o" % m)
        open(p, "w").close()
        os.chmod(p, m)
    for m in range(0o10000):
        if m % 8 == 0 or (m & 0o7000):
            p = os.path.join(fix, "d%04o" % m)
            os.mkdir(p)
            os.chmod(p, m)

    def run(argv0, mode_arg):
        cmd = [argv0] if argv0 == "/usr/bin/find" else [argv0, "find"]
        cmd += [fix, "-mindepth", "1", "-maxdepth", "1", "-perm", mode_arg]
        p = subprocess.run(cmd, env=ENV, capture_output=True, timeout=60)
        out = b"\n".join(sorted(p.stdout.splitlines()))
        return out, p.returncode

    bad = 0
    refused = 0
    for _ in range(N):
        m = mode()
        g_out, g_rc = run("/usr/bin/find", m)
        k_out, k_rc = run(KRIYA, m)
        if g_rc != 0 and k_rc != 0 and not g_out and not k_out:
            refused += 1
            continue
        if g_out == k_out and g_rc == k_rc:
            continue
        bad += 1
        if bad <= 12:
            print("DIFF -perm %r: gnu rc=%d %d lines, kriya rc=%d %d lines" % (
                m, g_rc, len(g_out.splitlines()), k_rc, len(k_out.splitlines())))
    print("%d modes, %d differ, %d refused by both" % (N, bad, refused))
finally:
    for dp, dn, fn in os.walk(fix):
        for d in dn:
            os.chmod(os.path.join(dp, d), 0o700)
    shutil.rmtree(fix)
sys.exit(1 if bad else 0)
