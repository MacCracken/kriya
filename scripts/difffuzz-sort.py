#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over sort's keys, orderings and modes.

Usage:  python3 scripts/difffuzz-sort.py build/kriya [cases] [seed]

Each case is a random input — fields of numbers, decimals, floats, hex, NaNs,
unit suffixes, month names, version strings, punctuation, control and high
bytes, with blanks in front and duplicate lines — and a random command line:
the global letters (`-b -d -f -g -h -i -M -n -r -R -V`), up to three `-k` keys
with character offsets and letters of their own, `-t`, `-s`, `-u`, `-z`,
`--sort=WORD`, and the modes `-c`, `-C` and `-m` over several files. A third of
the cases set a budget of a few KiB (`-S`) with a `-T` directory and inputs of
up to 400 lines, which sends them through temporary runs and merges (1.9.2),
and `-m` sometimes takes 17 or 20 files, past GNU's sixteen-way merge passes. Both
sides run under `LC_ALL=C` in the same directory; stdout and the exit status
are compared, never stderr, whose framing is kriya's own. Every case carries
`--random-source=FILE`, which makes GNU's shuffle reproducible wherever `R` is.

Incompatible letter sets (`-nd`, `-k1gM`) are generated on purpose now and
then: both sides must refuse them with exit 2.

⚠ NOT part of `cyrius test` or `scripts/fuzz.sh`: it measures kriya against
whatever coreutils is installed. Run it by hand when `src/cmd/sort.cyr`,
`src/lib/md5.cyr` or `src/lib/vercmp.cyr` changes, and again in the
`ubuntu:24.04` container. Character offsets stay small: GNU before 9.10 read
a byte out of bounds for offsets near SIZE_MAX, which `smoke-sort.sh`
pins against the local GNU instead.
"""
import os, random, shutil, subprocess, sys, tempfile

KRIYA = os.path.abspath(sys.argv[1])
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1
GNU   = os.environ.get("GNU_SORT", "/usr/bin/sort")
ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
rnd = random.Random(SEED)

def digits(lo, hi):
    return "".join(rnd.choice("0123456789") for _ in range(rnd.randint(lo, hi)))

def token():
    r = rnd.random()
    if r < 0.14:     # integers, with signs and leading zeros
        s = rnd.choice(["", "", "-", "+", "0", "00"]) + digits(1, 4)
    elif r < 0.24:   # decimals
        s = rnd.choice(["", "-"]) + digits(0, 3) + "." + digits(0, 3)
    elif r < 0.32:   # floats for -g
        s = rnd.choice(["1e3", "-2.5e-3", "0x1p4", "0X1A", "inf", "-inf", "INF", "nan", "-nan",
                        "NaN(12)", "1e5000", "-0", "+0", ".5", "5.", "e5", "0x", "1e", "1e+"])
    elif r < 0.42:   # human sizes
        s = rnd.choice(["", "-"]) + digits(1, 3) + rnd.choice(["", ".5", ".0"]) + \
            rnd.choice("KkMGTPEZYRQxb ")
        s = s.rstrip()
    elif r < 0.52:   # months
        m = rnd.choice(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct",
                        "nov", "dec", "ja", "mayday", "xyz", "j"])
        s = "".join(c.upper() if rnd.random() < 0.5 else c for c in m)
    elif r < 0.62:   # versions
        s = rnd.choice(["1.2", "1.10", "1.9", "1.2.3", "1.02", "1~rc1", "1.0~", "2a", "a2",
                        "foo-1.0.tar.gz", "foo-1.0a.tar.gz", "foo-1.10.tar.xz", ".a", "..", ".",
                        ".b1", "v1.2", "1.2-3", "1.2.3~beta", "x.y", "a.~b"])
    elif r < 0.85:   # short words, to make ties
        s = "".join(rnd.choice("aAbB_z-.,") for _ in range(rnd.randint(0, 3)))
    elif r < 0.92:   # control and high bytes, for -i and -d
        s = "".join(rnd.choice(["a", "\x01", "\x7f", "\xe9", "\x1b", "b", "!", "~"])
                    for _ in range(rnd.randint(1, 3)))
    else:
        s = ""
    return s

def line(seps):
    nf = rnd.randint(1, 4)
    out = rnd.choice(["", "", "", " ", "  ", "\t"])
    for i in range(nf):
        if i:
            out += rnd.choice(seps)
        out += token()
    return out

def make_input(seps, term, big=False):
    lines = []
    for _ in range(rnd.randint(0, 400 if big else 25)):
        if lines and rnd.random() < 0.2:
            lines.append(rnd.choice(lines))
        else:
            lines.append(line(seps))
    if term == "\0" and rnd.random() < 0.3:      # under -z a newline is a blank
        lines = [l.replace(" ", "\n", 1) for l in lines]
    s = term.join(lines)
    if lines and rnd.random() < 0.85:
        s += term
    return s.encode("latin-1")

TYPES = "nghMVR"

def letters():
    s = ""
    t = ""
    if rnd.random() < 0.55:
        t = rnd.choice(TYPES)
        s += t
        if rnd.random() < 0.03:                 # incompatible on purpose
            s += rnd.choice(TYPES + "di")
    for c in "bdfir":
        if c in "di" and t in "nghM" and t:     # -d and -i do not combine with these
            continue
        if rnd.random() < 0.12:
            s += c
    return "".join(rnd.sample(s, len(s)))

def pos(end):
    f = str(rnd.randint(1, 4))
    if rnd.random() < 0.3:
        f += "." + str(rnd.randint(0 if end else 1, 5))
    return f

def keyspec():
    s = pos(False)
    if rnd.random() < 0.3:
        s += letters()
    if rnd.random() < 0.75:
        s += "," + pos(True)
        if rnd.random() < 0.3:
            s += letters()
    return s

def case(tmp):
    args = []
    tsep = None
    if rnd.random() < 0.4:
        tsep = rnd.choice([":", " ", ",", "\t", "a"])
        args += [rnd.choice(["-t", "--field-separator"]), tsep] if rnd.random() < 0.8 else ["-t" + tsep]
    seps = [" ", "  ", "\t", ":", ","] if tsep is None else [tsep, tsep, " ", tsep + tsep]
    g = letters()
    for c in g:
        args.append("-" + c)
    if rnd.random() < 0.05:
        args.append("--sort=" + rnd.choice(["general-numeric", "human", "month", "n", "random", "version"]))
    for _ in range(rnd.choice([0, 0, 1, 1, 1, 2, 2, 3])):
        k = keyspec()
        args += rnd.choice([["-k", k], ["-k" + k], ["--key=" + k], ["--key", k]])
    if rnd.random() < 0.15:
        args.append("-s")
    if rnd.random() < 0.2:
        args.append("-u")
    term = "\n"
    if rnd.random() < 0.08:
        args.append("-z")
        term = "\0"
    # Always: GNU reads the file only when some key is random, `-k2R` included.
    args.append("--random-source=rs")
    # 1.9.2: a budget small enough to send the input through temporary runs and merges.
    big = False
    if rnd.random() < 0.3:
        args += ["-S", rnd.choice(["1", "1K", "2", "3", "1500b", "4K"]), "-T", "tdir"]
        big = rnd.random() < 0.7
    mode = rnd.random()
    files = []
    if mode < 0.08:
        args.append(rnd.choice(["-c", "--check", "--check=diagnose-first"]))
        files = ["f0"]
    elif mode < 0.13:
        args.append(rnd.choice(["-C", "--check=quiet", "--check=silent"]))
        files = ["f0"]
    elif mode < 0.25:
        args.append("-m")
        # Past sixteen files GNU merges in groups first (it cannot change the order).
        files = ["f%d" % i for i in range(rnd.choice([1, 2, 3, 4, 17, 20]))]
    else:
        files = ["f%d" % i for i in range(rnd.choice([1, 1, 1, 2, 3]))]
    for f in files:
        with open(os.path.join(tmp, f), "wb") as fh:
            fh.write(make_input(seps, term, big))
    if "-m" in args and rnd.random() < 0.6:
        # Mostly merge real sorted runs: sort each file with GNU under the same options first.
        pre = [a for a in args if a != "-m"]
        for f in files:
            p = subprocess.run([GNU] + pre + [f], cwd=tmp, env=ENV, capture_output=True)
            if p.returncode == 0:
                with open(os.path.join(tmp, f), "wb") as fh:
                    fh.write(p.stdout)
    if rnd.random() < 0.2 and len(files) == 1:
        return args, None, open(os.path.join(tmp, files[0]), "rb").read()
    return args, files, None

def run(cmd, tmp, stdin):
    p = subprocess.run(cmd, cwd=tmp, env=ENV, input=stdin, capture_output=True, timeout=60)
    return p.stdout, p.returncode

tmp = tempfile.mkdtemp(prefix="dfsort.")
os.mkdir(os.path.join(tmp, "tdir"))
with open(os.path.join(tmp, "rs"), "wb") as fh:
    fh.write(bytes(rnd.randrange(256) for _ in range(64)))
diff = 0
refused = 0
for i in range(N):
    args, files, stdin = case(tmp)
    operands = files or []
    g = run([GNU] + args + operands, tmp, stdin)
    k = run([KRIYA, "sort"] + args + operands, tmp, stdin)
    if g[1] == 2:
        refused += 1
    if g != k:
        diff += 1
        keep = os.path.join(tmp, "fail%d" % diff)
        os.mkdir(keep)
        for f in operands + ["rs"]:
            shutil.copy(os.path.join(tmp, f), keep)
        with open(os.path.join(keep, "args"), "w") as fh:
            fh.write(repr(args) + "\n")
        if stdin is not None:
            with open(os.path.join(keep, "stdin"), "wb") as fh:
                fh.write(stdin)
        if diff <= 12:
            print("DIFF %r files=%r" % (args, operands))
            print("  gnu rc=%d %r" % (g[1], g[0][:300]))
            print("  kri rc=%d %r" % (k[1], k[0][:300]))
            if stdin is not None:
                print("  stdin %r" % stdin[:300])
            else:
                for f in operands:
                    print("  %s %r" % (f, open(os.path.join(tmp, f), "rb").read()[:300]))
left = os.listdir(os.path.join(tmp, "tdir"))
if left:
    print("temporary files left behind:", left[:5])
    diff += 1
print("sort: %d cases, %d refused by both, %d differ" % (N, refused, diff))
if diff:
    print("inputs kept in", tmp)
else:
    shutil.rmtree(tmp)
sys.exit(1 if diff else 0)
