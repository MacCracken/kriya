#!/bin/sh
# smoke-help-json.sh — `--help=json`, the ADR 0002 Appendix A machine form.
#
# ⚠ THIS OUTPUT IS A PUBLIC INTERFACE. agnoshi's tab-completion parses it.
# Adding a field is fine (consumers must tolerate unknown fields within a
# major); removing or retyping one is a break that bumps
# KRIYA_HELP_SCHEMA_VERSION in src/lib/args.cyr and needs an ADR.
#
# ⭐ The load-bearing test here is not "is it valid JSON" — it is
# BOUNDARY ENFORCEMENT: for every utility, the `positional.min` and
# `positional.max` the JSON advertises are fed to the real binary and must
# actually be enforced. A schema that lies about operand counts is worse than
# no schema, because an agent trusts it.

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

ALL="true false echo pwd yes sleep mkdir rmdir touch ln cp rm mv basename dirname
     realpath readlink which stat ls tee wc head tail nl uniq tr cut sort printf
     grep find xargs seq env date du df"

# --- structural conformance, every utility -----------------------------
#
# One python3 pass over all 38 rather than one per utility: the per-utility
# result lines are read back below so a failure still names the utility.
"$BIN" true --help=json > /dev/null    # fail fast if the form is missing entirely

REPORT="$WORK/report"
UTILS_ONE_LINE=$(echo $ALL)
BIN="$BIN" UTILS="$UTILS_ONE_LINE" python3 - > "$REPORT" <<'PY'
import json, os, subprocess

BIN = os.environ["BIN"]
REQUIRED = ["schema", "name", "summary", "synopsis", "notes",
            "destructive", "options", "positional", "exit_codes", "examples"]
# ⛔ Verified by hand against the source, NOT copied from the declarations under
# test -- otherwise this asserts nothing. `env`/`xargs`/`find` are destructive by
# DELEGATION (they run a command the caller supplies); `sort` via -o, `tee` and
# `uniq` via their output operands.
DESTRUCTIVE = {"cp", "mv", "rm", "ln", "mkdir", "rmdir", "touch",
               "sort", "tee", "uniq", "env", "xargs", "find"}
# Utilities that genuinely accept no options, as against a hand-rolled parser
# whose options are not machine-declared (which must render null, never []).
NO_OPTIONS  = {"true", "false", "yes", "sleep", "printf"}
# ⭐ EMPTY AS OF 1.3.7, and that is the point: every utility now declares its
# option table, so nothing renders `"options": null` any more. The three-way
# encoding stays in the renderer — a future hand-rolled utility would need it —
# but no utility uses it today, and this set is what would catch a regression
# back to an undeclared table.
HAND_ROLLED = set()

def emit(name, want, got):
    print("%s\t%s\t%s" % (name, want, got))

for u in os.environ["UTILS"].split():
    r = subprocess.run([BIN, u, "--help=json"], capture_output=True, text=True)
    emit("%s exits 0" % u, "0", str(r.returncode))
    if r.returncode != 0:
        continue
    emit("%s writes nothing to stderr" % u, "", r.stderr.strip())
    emit("%s emits no ANSI" % u, "0", str(r.stdout.count("\x1b")))
    try:
        d = json.loads(r.stdout)
    except Exception as e:
        emit("%s parses as JSON" % u, "yes", "no: %s" % e)
        continue
    emit("%s parses as JSON" % u, "yes", "yes")
    emit("%s has every required field" % u, "", ",".join(k for k in REQUIRED if k not in d))
    emit("%s schema tag" % u, "kriya-help/v1", str(d.get("schema")))
    emit("%s self-names" % u, u, str(d.get("name")))
    emit("%s summary is non-empty" % u, "yes", "yes" if d.get("summary") else "no")
    emit("%s synopsis starts with its own name" % u,
         "yes", "yes" if str(d.get("synopsis", "")).startswith(u) else "no")
    emit("%s destructive" % u, str(u in DESTRUCTIVE), str(d.get("destructive")))

    # ⛔ positional must never be null -- an absent operand contract is a hole in
    # the interface, and 1.3.2's CI lint will reject it too.
    p = d.get("positional")
    emit("%s declares positional" % u, "yes", "no" if p is None else "yes")
    if p is not None:
        emit("%s positional.min is an int" % u, "yes",
             "yes" if isinstance(p.get("min"), int) else "no")
        emit("%s positional.max is int-or-null" % u, "yes",
             "yes" if (p.get("max") is None or isinstance(p.get("max"), int)) else "no")
        emit("%s positional.names is a list of str" % u, "yes",
             "yes" if isinstance(p.get("names"), list)
                      and all(isinstance(x, str) for x in p["names"]) else "no")
        if isinstance(p.get("max"), int) and isinstance(p.get("min"), int):
            emit("%s positional.min <= max" % u, "yes",
                 "yes" if p["min"] <= p["max"] else "no")

    # options: three-way. A hand-rolled parser renders null; genuinely optionless
    # renders []. Collapsing them would tell an agent `du` has no -h.
    o = d.get("options")
    if u in HAND_ROLLED:
        emit("%s hand-rolled options render null" % u, "None", str(o))
    elif u in NO_OPTIONS:
        emit("%s optionless renders []" % u, "[]", json.dumps(o))
    else:
        emit("%s options is a non-empty list" % u, "yes",
             "yes" if isinstance(o, list) and o else "no")
    if isinstance(o, list):
        for e in o:
            bad = [k for k in ("long", "short", "kind", "description") if k not in e]
            emit("%s option entry has all keys" % u, "", ",".join(bad))
            emit("%s option kind is known" % u, "yes",
                 "yes" if e.get("kind") in ("bool", "int", "str") else "no")
            emit("%s option has at least one form" % u, "yes",
                 "yes" if (e.get("long") or e.get("short")) else "no")
            if e.get("short") is not None:
                emit("%s short form is one char" % u, "1", str(len(e["short"])))

    # exit_codes: JSON object keys are strings; ADR 0008's three tiers are floor.
    ec = d.get("exit_codes")
    emit("%s exit_codes is an object" % u, "yes", "yes" if isinstance(ec, dict) else "no")
    if isinstance(ec, dict):
        emit("%s exit_codes keys are numeric strings" % u, "yes",
             "yes" if all(isinstance(k, str) and k.lstrip("-").isdigit() for k in ec) else "no")
        emit("%s documents exit 0" % u, "yes", "yes" if "0" in ec else "no")
        emit("%s documents exit 2" % u, "yes", "yes" if "2" in ec else "no")

    emit("%s examples is a list of str" % u, "yes",
         "yes" if isinstance(d.get("examples"), list)
                  and all(isinstance(x, str) for x in d["examples"]) else "no")

    # ⭐ ANTI-DRIFT: the JSON option table and the human OPTIONS table are the
    # same spec read twice. If they ever disagree, one renderer has gone wrong.
    if isinstance(o, list) and o:
        h = subprocess.run([BIN, u, "--help"], capture_output=True, text=True).stdout
        sect, seen = False, []
        for line in h.splitlines():
            if line.startswith("OPTIONS"):
                sect = True; continue
            if sect and line and not line.startswith(" "):
                break
            if not sect or not line.strip():
                continue
            # ⚠ A short+long row indents 2 ("  -b, --bytes"); a LONG-ONLY row
            # indents 6, so its "--" aligns under the long names above it. An
            # earlier version of this check matched only the first shape and
            # reported drift on every long-only option -- the renderer was fine.
            indent = len(line) - len(line.lstrip())
            if indent not in (2, 6):
                continue
            tok = line.strip().split()[0].rstrip(",")
            # A wrapped description line also indents 2; require a real flag.
            if tok.startswith("--") and len(tok) > 2:
                seen.append(tok)
            elif len(tok) == 2 and tok[0] == "-" and tok[1] != "-":
                seen.append(tok)
        want = ["-" + e["short"] if e["short"] else "--" + e["long"] for e in o]
        emit("%s json options match the human page" % u,
             " ".join(want), " ".join(seen))
PY

while IFS="$(printf '\t')" read -r nm want got; do
    expect_eq "$nm" "$want" "$got"
done < "$REPORT"

BIN="$ROOT/build/kriya"

# --- ⭐ BOUNDARY ENFORCEMENT: the advertised bounds must be real ---------
#
# Feeding one operand FEWER than the advertised min must be a usage error, and
# one MORE than a finite advertised max likewise. Every case below stops at the
# operand check before touching the filesystem.
too_few() {   # util, args... -> want exit 2
    rc=0
    "$BIN" "$@" </dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "$1: one under min is a usage error" "2" "$rc"
}
too_many() {  # util, args... -> want exit 2
    rc=0
    "$BIN" "$@" </dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "$1: one over max is a usage error" "2" "$rc"
}

# min > 0
too_few cp f1
too_few mv f1
too_few ln
too_few mkdir
too_few rmdir
too_few touch
too_few stat
too_few which
too_few realpath
too_few readlink
too_few dirname
too_few basename
too_few printf
too_few seq
too_few sleep
too_few tr

# finite max
too_many basename a b c
too_many date +%Y extra
too_many pwd extra
too_many seq 1 1 5 9
too_many sleep 0 0
too_many tr a b c
: > u1; : > u2
too_many uniq u1 u2 u3

# ⚠ min=0 utilities where an OPTION supplies or waives the operand. These are
# exactly the cases a min=1 declaration would have made a validator reject.
printf 'foo\n' > pat.txt
rc=0; printf 'foo\n' | "$BIN" grep -e foo >/dev/null 2>&1 || rc=$?
expect_eq "grep -e with zero operands is valid (min 0)" "0" "$rc"
rc=0; printf 'foo\n' | "$BIN" grep -f pat.txt >/dev/null 2>&1 || rc=$?
expect_eq "grep -f with zero operands is valid (min 0)" "0" "$rc"
rc=0; "$BIN" rm -f >/dev/null 2>&1 || rc=$?
expect_eq "rm -f with zero operands is valid (min 0)" "0" "$rc"

# max=null utilities must accept many operands
: > m1; : > m2; : > m3; : > m4; : > m5
for u in ls stat wc head tail nl sort; do
    rc=0
    "$BIN" "$u" m1 m2 m3 m4 m5 </dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "$u: five operands accepted (max null)" "0" "$rc"
done

# --- ⭐ every advertised option is actually accepted ---------------------
#
# ⛔ The invariant a completer depends on: **an option in the table can be
# typed.** Before 1.3.7 seven utilities rendered `"options": null` because their
# hand-rolled parsers had no spec to read back; they now declare one that the
# parser itself consults as its acceptance gate, so the two cannot disagree.
# This checks the claim end-to-end rather than trusting the wiring.
#
# ⚠ Restricted to utilities that cannot modify anything when handed a bare flag.
# Running every advertised option against `rm` or `mv` to see whether it parses
# is not a test, it is a way to lose files.
# ⚠ Only utilities whose `positional.min` is 0. `stat -L` exits 2 not because
# `-L` is unknown but because `stat` needs an operand — a usage error for a
# reason that has nothing to do with the option table. Checking those would
# need a per-utility fixture, and this invariant does not need one.
for u in df du date echo ls wc; do
    for o in $("$BIN" "$u" --help=json | python3 -c '
import json, sys
d = json.load(sys.stdin)
for e in (d["options"] or []):
    # bool shorts only: a value-taking option needs an argument, and a missing
    # one is a usage error for a reason that has nothing to do with this check.
    if e["kind"] == "bool" and e["short"] and "NOT IMPLEMENTED" not in (e["description"] or ""):
        print("-" + e["short"])'); do
        rc=0
        "$BIN" "$u" "$o" </dev/null >/dev/null 2>&1 || rc=$?
        if [ "$rc" = "2" ]; then
            FAIL=$((FAIL + 1))
            printf "FAIL %s advertises %s but rejects it as a usage error\n" "$u" "$o" >&2
        else
            PASS=$((PASS + 1))
        fi
    done
done

# ⚠ And the other direction: a letter NOT in the table must be refused. Without
# this, "every advertised option works" would be satisfied by accepting
# everything.
for u in df du date seq env; do
    rc=0
    "$BIN" "$u" -Z </dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "$u rejects an unadvertised short option" "2" "$rc"
    rc=0
    "$BIN" "$u" --definitely-not-an-option </dev/null >/dev/null 2>&1 || rc=$?
    expect_eq "$u rejects an unadvertised long option" "2" "$rc"
done

# ⚠ `find -H` is advertised AND refused, deliberately — it is a named deferral
# (roadmap 1.7.1) and "unknown option" would be a worse answer than naming it.
# Its description says NOT IMPLEMENTED, which is what excludes it above; pin
# both halves so neither drifts.
rc=0; "$BIN" find . -maxdepth 0 -H >/dev/null 2>&1 || rc=$?
expect_eq "find -H is refused, not silently accepted" "2" "$rc"
expect_eq "find -H says so in its description" "yes" \
    "$("$BIN" find --help=json | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("yes" if any("NOT IMPLEMENTED" in (e["description"] or "")
                   for e in (d["options"] or []) if e["short"] == "H") else "no")')"

# --- escaping ----------------------------------------------------------
#
# ⛔ Six help strings carry a literal backslash. Emitted raw they produce
# invalid JSON. printf is the densest case.
RAW=$("$BIN" printf --help=json)
case "$RAW" in
    *'\\n'*) expect_eq "printf backslash is escaped in the raw bytes" "yes" "yes" ;;
    *)       expect_eq "printf backslash is escaped in the raw bytes" "yes" "no" ;;
esac
for u in printf tr stat xargs; do
    rc=0
    "$BIN" "$u" --help=json | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || rc=$?
    expect_eq "$u json survives its backslashes" "0" "$rc"
done
# UTF-8 passes through as UTF-8, not \u-escaped mojibake.
rc=0
"$BIN" rm --help=json | python3 -c '
import json,sys
d=json.load(sys.stdin)
sys.exit(0 if "⚠" in d["notes"] else 1)' || rc=$?
expect_eq "rm notes keeps its UTF-8 warning sign" "0" "$rc"
# The safety prose reaches the machine form at all.
rc=0
"$BIN" rm --help=json | python3 -c '
import json,sys
d=json.load(sys.stdin)
sys.exit(0 if "ADR 0004" in (d["notes"] or "") else 1)' || rc=$?
expect_eq "rm notes carry the refuses-/ rule into json" "0" "$rc"

# --- format negotiation ------------------------------------------------
rc=0; "$BIN" ls --help=yaml >/dev/null 2>&1 || rc=$?
expect_eq "unknown --help format is a usage error" "2" "$rc"
OUT=$("$BIN" ls --help=yaml 2>&1 >/dev/null || true)
case "$OUT" in
    *"valid formats: json"*) expect_eq "unknown format names the valid set" "yes" "yes" ;;
    *)                       expect_eq "unknown format names the valid set" "yes" "no" ;;
esac
rc=0; "$BIN" ls --help= >/dev/null 2>&1 || rc=$?
expect_eq "empty --help format is a usage error" "2" "$rc"

# --- routing: the request must reach the right program -----------------
rc=0; "$BIN" xargs --help=json >/dev/null 2>&1 </dev/null || rc=$?
expect_eq "xargs --help=json is xargs' own" "0" "$rc"
OUT=$("$BIN" find . -maxdepth 0 -exec echo --help=json {} ';' 2>&1 || true)
expect_eq "find -exec passes --help=json through" "--help=json ." "$OUT"
rc=0; "$BIN" ls -- --help=json >/dev/null 2>&1 || rc=$?
expect_eq "-- terminates: --help=json becomes an operand" "1" "$rc"

# --- write failure must not exit 0 -------------------------------------
rc=0; "$BIN" ls --help=json >/dev/full 2>/dev/null || rc=$?
expect_eq "--help=json to a full device exits 1" "1" "$rc"

printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
