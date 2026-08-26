#!/bin/sh
# smoke-list.sh — `kriya --list` and `kriya --help`, the dispatcher-level forms.
#
# ⚠ `kriya --list` is a public interface (ADR 0002), versioned by
# KRIYA_LIST_SCHEMA_VERSION separately from the `--help=json` schema. agnoshi
# reads it once at shell startup to seed utility-name completion.
#
# ⭐ The reason it can exist in ONE process rather than 38 execs is that each
# utility's help record is declared by a `<util>_help_declare()` split out of
# `cmd_<util>` — so the dispatcher can populate a utility's record without
# running the utility.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0
FAIL=0
expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: expected '%s', got '%s'\n" "$1" "$2" "$3" >&2
    fi
}

# --- kriya --list ------------------------------------------------------
rc=0; "$BIN" --list >/dev/null 2>&1 || rc=$?
expect_eq "--list exits 0" "0" "$rc"
expect_eq "--list writes nothing to stderr" "" "$("$BIN" --list 2>&1 >/dev/null)"
expect_eq "--list emits no ANSI" "0" "$("$BIN" --list 2>/dev/null | grep -c "$(printf '\033')" || true)"

REPORT="$WORK/report"
BIN="$BIN" python3 - > "$REPORT" <<'PY'
import json, os, re, subprocess
BIN = os.environ["BIN"]
def emit(n, w, g): print("%s\t%s\t%s" % (n, w, g))

r = subprocess.run([BIN, "--list"], capture_output=True, text=True)
d = json.loads(r.stdout)
emit("--list schema tag", "yes",
     "yes" if re.fullmatch(r"kriya-list/v\d+", str(d.get("schema"))) else repr(d.get("schema")))
emit("--list count matches entry count", str(len(d["utilities"])), str(d.get("count")))
emit("--list has 38 utilities", "38", str(len(d["utilities"])))
names = [u["name"] for u in d["utilities"]]
emit("--list names are unique", str(len(names)), str(len(set(names))))

for u in d["utilities"]:
    n = u.get("name", "?")
    for k, ty in (("name", str), ("summary", str), ("synopsis", str),
                  ("destructive", bool), ("exit_codes", dict)):
        emit("%s list entry has %s" % (n, k), "yes",
             "yes" if isinstance(u.get(k), ty) else "no (%r)" % u.get(k))
    emit("%s list summary is non-empty" % n, "yes", "yes" if u.get("summary") else "no")
    emit("%s list synopsis starts with its name" % n, "yes",
         "yes" if str(u.get("synopsis", "")).startswith(n) else "no")
    emit("%s list documents exit 0 and 2" % n, "yes",
         "yes" if {"0", "2"} <= set(u.get("exit_codes", {})) else "no")

# ⭐ Every listed utility must actually dispatch. A name in the table that does
# not route is worse than a missing one: a completer would offer it.
for n in names:
    p = subprocess.run([BIN, n, "--help"], capture_output=True, text=True)
    line = p.stdout.splitlines()[1].strip() if len(p.stdout.splitlines()) > 1 else ""
    emit("%s in --list actually dispatches" % n, "yes",
         "yes" if p.returncode == 0 and line.startswith(n + " ") else "no (%r)" % line)

# ⭐ --list and --help=json are one declaration read twice.
for u in d["utilities"]:
    n = u["name"]
    h = json.loads(subprocess.run([BIN, n, "--help=json"],
                                  capture_output=True, text=True).stdout)
    for k in ("summary", "synopsis", "destructive"):
        emit("%s: --list %s agrees with --help=json" % (n, k), repr(h.get(k)), repr(u.get(k)))
    emit("%s: --list exit_codes agree with --help=json" % n,
         repr(h.get("exit_codes")), repr(u.get("exit_codes")))

# The destructive set, pinned by name rather than by count.
DESTR = {"cp", "mv", "rm", "ln", "mkdir", "rmdir", "touch",
         "sort", "tee", "uniq", "env", "xargs", "find"}
emit("--list destructive set", " ".join(sorted(DESTR)),
     " ".join(sorted(u["name"] for u in d["utilities"] if u["destructive"])))

# The names in `kriya --help`'s UTILITIES section are the same set.
h = subprocess.run([BIN, "--help"], capture_output=True, text=True).stdout
sect, listed = False, []
for line in h.splitlines():
    if line.startswith("UTILITIES"): sect = True; continue
    if sect:
        if not line.strip(): break
        listed += line.split()
emit("kriya --help lists the same utilities", " ".join(sorted(names)), " ".join(sorted(listed)))
PY

while IFS="$(printf '\t')" read -r nm want got; do
    expect_eq "$nm" "$want" "$got"
done < "$REPORT"

# --- argument handling -------------------------------------------------
rc=0; "$BIN" --list extra >/dev/null 2>&1 || rc=$?
expect_eq "--list with an argument is a usage error" "2" "$rc"
rc=0; "$BIN" --help extra >/dev/null 2>&1 || rc=$?
expect_eq "kriya --help with an argument is a usage error" "2" "$rc"
rc=0; "$BIN" --nosuchflag >/dev/null 2>&1 || rc=$?
expect_eq "an unknown dispatcher flag is a usage error" "2" "$rc"

# ⛔ Dispatcher flags must NOT leak into utilities. `ls --list` is ls's option
# to reject, not an enumeration request.
rc=0; "$BIN" ls --list >/dev/null 2>&1 || rc=$?
expect_eq "ls --list is ls's bad option, not the utility table" "2" "$rc"
ln -sf "$BIN" ./ls
rc=0; ./ls --list >/dev/null 2>&1 || rc=$?
expect_eq "a symlink invocation never sees dispatcher flags" "2" "$rc"

# --- kriya --help ------------------------------------------------------
rc=0; "$BIN" --help >/dev/null 2>&1 || rc=$?
expect_eq "kriya --help exits 0" "0" "$rc"
for sec in NAME SYNOPSIS DESCRIPTION OPTIONS UTILITIES; do
    expect_eq "kriya --help has $sec" "1" \
        "$("$BIN" --help 2>/dev/null | grep -c "^$sec$" || true)"
done
expect_eq "kriya --help wraps at 80 columns" "0" \
    "$("$BIN" --help 2>/dev/null | awk 'length > 80' | wc -l | tr -d ' ')"

# --- write failure must not exit 0 -------------------------------------
rc=0; "$BIN" --list >/dev/full 2>/dev/null || rc=$?
expect_eq "--list to a full device exits 1" "1" "$rc"
rc=0; "$BIN" --help >/dev/full 2>/dev/null || rc=$?
expect_eq "kriya --help to a full device exits 1" "1" "$rc"

printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
