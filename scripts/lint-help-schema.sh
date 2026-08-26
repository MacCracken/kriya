#!/bin/sh
# lint-help-schema.sh — the CI lint ADR 0002 promised: a utility whose schema
# does not conform fails the build, so the interface cannot rot silently.
#
# ⚠ This is a LINT, not a behavioural test. It answers "is the declared
# interface internally consistent and complete", which is a property of the
# source tree plus one built binary. Behaviour lives in scripts/smoke-*.sh.
#
# Checks, in order of what they protect:
#   1. src/cmd/*.cyr, the dispatcher table, and `kriya --list` name the SAME
#      38 utilities. Adding a file without a table row (or the reverse) is the
#      way a utility goes missing from the interface.
#   2. Every utility declares a complete `--help=json` document: all fields
#      present, correctly typed, `positional` never null.
#   3. Every utility appears in `kriya --list` with the same summary and
#      synopsis it gives `--help=json`. Two renderers, one declaration.
#   4. ⛔ Every `k_write(fd, "literal", N)` in the tree has N equal to the
#      literal's real byte length. A short N truncates the message; a long N
#      reads past the end of the literal. 44 sites were wrong when this check
#      was written, so it is not hypothetical.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

cd "$ROOT"
BIN="$BIN" python3 - "$@" <<'PY'
import glob, json, os, re, subprocess, sys

BIN = os.environ["BIN"]
fail = []
def bad(msg): fail.append(msg)

# --- 1. one utility set, three places ---------------------------------
from_files = {os.path.basename(f)[:-4] for f in glob.glob("src/cmd/*.cyr")}
main_src = open("src/main.cyr").read()
from_table = set(re.findall(r'_util_add\("(\w+)"', main_src))

listing = subprocess.run([BIN, "--list"], capture_output=True, text=True)
if listing.returncode != 0:
    bad("kriya --list exited %d" % listing.returncode)
    print("\n".join(fail), file=sys.stderr); sys.exit(1)
try:
    doc = json.loads(listing.stdout)
except Exception as e:
    bad("kriya --list is not valid JSON: %s" % e)
    print("\n".join(fail), file=sys.stderr); sys.exit(1)

from_list = {u["name"] for u in doc["utilities"]}

for label, a, b in (("src/cmd/*.cyr", from_files, from_table),):
    if a != b:
        bad("utility sets differ:\n  only in %s: %s\n  only in the dispatcher table: %s"
            % (label, sorted(a - b), sorted(b - a)))
if from_table != from_list:
    bad("dispatcher table vs `kriya --list` differ:\n  only in table: %s\n  only in --list: %s"
        % (sorted(from_table - from_list), sorted(from_list - from_table)))
if doc.get("count") != len(doc["utilities"]):
    bad("--list count %r != %d entries" % (doc.get("count"), len(doc["utilities"])))
if not re.fullmatch(r"kriya-list/v\d+", str(doc.get("schema", ""))):
    bad("--list schema tag is %r" % doc.get("schema"))

# --- 2 + 3. every utility's --help=json conforms, and agrees with --list
REQUIRED = {"schema": str, "name": str, "summary": str, "synopsis": str,
            "notes": (str, type(None)), "destructive": bool,
            "options": (list, type(None)), "positional": dict,
            "exit_codes": dict, "examples": list}
by_name = {u["name"]: u for u in doc["utilities"]}

for u in sorted(from_table):
    r = subprocess.run([BIN, u, "--help=json"], capture_output=True, text=True)
    if r.returncode != 0:
        bad("%s --help=json exited %d" % (u, r.returncode)); continue
    try:
        d = json.loads(r.stdout)
    except Exception as e:
        bad("%s --help=json is not valid JSON: %s" % (u, e)); continue
    for k, ty in REQUIRED.items():
        if k not in d:
            bad("%s --help=json missing field %r" % (u, k))
        elif not isinstance(d[k], ty):
            bad("%s --help=json field %r is %s, want %s"
                % (u, k, type(d[k]).__name__, ty))
    if d.get("name") != u:
        bad("%s --help=json self-names %r" % (u, d.get("name")))
    if not re.fullmatch(r"kriya-help/v\d+", str(d.get("schema", ""))):
        bad("%s --help=json schema tag is %r" % (u, d.get("schema")))
    if not str(d.get("synopsis", "")).startswith(u):
        bad("%s synopsis does not start with its own name: %r" % (u, d.get("synopsis")))

    p = d.get("positional")
    if not isinstance(p, dict):
        # ⛔ null here means the utility never declared its operand contract.
        bad("%s declares no `positional` -- add help_positional(min, max, names)" % u)
    else:
        if not isinstance(p.get("min"), int):
            bad("%s positional.min is %r" % (u, p.get("min")))
        if not (p.get("max") is None or isinstance(p["max"], int)):
            bad("%s positional.max is %r" % (u, p.get("max")))
        if isinstance(p.get("max"), int) and isinstance(p.get("min"), int) and p["min"] > p["max"]:
            bad("%s positional.min %d > max %d" % (u, p["min"], p["max"]))
        if not isinstance(p.get("names"), list) or not all(isinstance(x, str) for x in p["names"]):
            bad("%s positional.names is %r" % (u, p.get("names")))

    ec = d.get("exit_codes")
    if isinstance(ec, dict):
        for k in ec:
            if not re.fullmatch(r"-?\d+", k):
                bad("%s exit_codes key %r is not a numeric string" % (u, k))
        for need in ("0", "2"):
            if need not in ec:
                bad("%s does not document exit %s" % (u, need))

    o = d.get("options")
    if isinstance(o, list):
        for e in o:
            if not isinstance(e, dict):
                bad("%s option entry is %r" % (u, e)); continue
            for k in ("long", "short", "kind", "description"):
                if k not in e: bad("%s option entry missing %r" % (u, k))
            if e.get("kind") not in ("bool", "int", "str"):
                bad("%s option kind %r" % (u, e.get("kind")))
            if not (e.get("long") or e.get("short")):
                bad("%s option entry has neither long nor short form" % u)
            if e.get("short") is not None and len(str(e["short"])) != 1:
                bad("%s short form %r is not one character" % (u, e.get("short")))

    # 3. the two documents are one declaration read twice.
    l = by_name.get(u)
    if l is None:
        bad("%s is missing from --list" % u)
    else:
        for k in ("summary", "synopsis", "destructive"):
            if l.get(k) != d.get(k):
                bad("%s: --list %s=%r but --help=json %s=%r"
                    % (u, k, l.get(k), k, d.get(k)))
        if l.get("exit_codes") != d.get("exit_codes"):
            bad("%s: exit_codes differ between --list and --help=json" % u)

# --- 4. k_write literal lengths ---------------------------------------
LIT = re.compile(r'k_write\(\s*\d+\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*(\d+)\s*\)')
ESC = {"n": b"\n", "t": b"\t", "r": b"\r", "0": b"\0",
       "\\": b"\\", '"': b'"', "'": b"'"}

def literal_bytes(x):
    out, i = b"", 0
    while i < len(x):
        c = x[i]
        if c == "\\":
            n = x[i + 1]
            if n in ESC:  out += ESC[n];                       i += 2; continue
            if n == "x":  out += bytes([int(x[i+2:i+4], 16)]); i += 4; continue
            out += n.encode(); i += 2; continue
        out += c.encode("utf-8"); i += 1
    return len(out)

for f in sorted(glob.glob("src/**/*.cyr", recursive=True)):
    for ln, line in enumerate(open(f), 1):
        for m in LIT.finditer(line):
            want, got = literal_bytes(m.group(1)), int(m.group(2))
            if want != got:
                how = "reads %d byte(s) past the literal" % (got - want) if got > want \
                      else "truncates the message by %d byte(s)" % (want - got)
                bad("%s:%d k_write length %d should be %d -- %s" % (f, ln, got, want, how))

if fail:
    print("lint-help-schema: %d problem(s)\n" % len(fail), file=sys.stderr)
    for m in fail:
        print("  " + m, file=sys.stderr)
    sys.exit(1)

print("lint-help-schema: OK -- %d utilities, one declaration, three readers" % len(from_table))
PY
