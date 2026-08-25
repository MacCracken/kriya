#!/bin/sh
# smoke-option-forms.sh — clustered and attached short options, across utilities.
#
# ⛔ THE GAP THIS CLOSES: until v1.2.0 `rm -rf` exited 2. So did `ls -la`,
# `grep -in`, `wc -lw`, `sort -rn`, `cp -rp`, `uniq -cd`, `tail -n5` and
# `cut -c1-3`. The stdlib parser puts both forms out of scope, so kriya expands
# them itself in `src/lib/args.cyr` before handing argv over.
#
# ⚠ The expansion is SPEC-DRIVEN — it asks each utility's own flags spec whether
# a letter is a bool or takes a value. These cases exist to pin both directions:
# what must now be accepted, and what must still be left completely alone.
#
# GNU is the oracle throughout: every accepted form is compared cell-by-cell.

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

expect_exit() {
    name=$1; expected=$2; shift 2
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}

# same NAME UTIL ARGS... — run kriya and GNU with identical args, compare stdout.
same() {
    name=$1; shift
    util=$1; shift
    k=$(timeout 10 "$BIN" "$util" "$@" 2>/dev/null | tr '\n' ' ') || true
    g=$(timeout 10 "$util" "$@" 2>/dev/null | tr '\n' ' ') || true
    expect_eq "$name" "$g" "$k"
}

printf 'delta\nbravo\nalpha\nbravo\n' > f
printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n' > nums
mkdir -p tree/sub
echo x > tree/a
echo y > tree/sub/b

# --- clustered short bools --------------------------------------------
same "grep -in"          grep -in bravo f
same "grep -i -n"        grep -i -n bravo f
same "wc -lw"            wc -lw f
same "wc -l -w"          wc -l -w f
same "sort -rn"          sort -rn nums
same "sort -r -n"        sort -r -n nums
same "uniq -cd"          uniq -cd f
same "sort -u -f"        sort -uf f
expect_exit "ls -la accepted"      0 "$BIN" ls -la tree
expect_exit "ls -lart accepted?"   2 "$BIN" ls -lart tree   # -t is still deferred (M12d)

# --- clustered bools on destructive verbs -----------------------------
# `rm -rf` is the single most-typed command in Unix; it must work.
mkdir -p victim/sub && echo z > victim/sub/z
expect_exit "rm -rf DIR"           0 "$BIN" rm -rf victim
expect_eq   "rm -rf removed it"    "gone" "$([ -e victim ] && echo present || echo gone)"
mkdir -p cpsrc && echo c > cpsrc/c
expect_exit "cp -rp SRC DST"       0 "$BIN" cp -rp cpsrc cpdst
expect_eq   "cp -rp copied"        "c" "$(cat cpdst/c)"

# --- attached short values --------------------------------------------
same "head -n2"          head -n2 nums
same "head -n 2"         head -n 2 nums
same "tail -n2"          tail -n2 nums
same "head -c5"          head -c5 nums
same "cut -c1-3"         cut -c1-3 f
same "sort -t: -k1"      sort -t: -k1 f

# --- obsolescent bare-digit form (head -5 / tail -5) ------------------
# POSIX marks it obsolescent; every shell script still uses it. Unambiguous
# only because neither utility registers a digit as a short option.
same "head -3"           head -3 nums
same "tail -3"           tail -3 nums
same "head -1"           head -1 nums
same "tail -1"           tail -1 nums

# --- mixed cluster ending in a value-taking option --------------------
same "tail -qn2"         tail -qn2 nums
same "grep -inc"         grep -inc bravo f

# --- what must NOT be touched -----------------------------------------
# ⚠ Expansion only fires when the FIRST letter is a registered short. That one
# condition is what keeps non-option tokens that merely start with a dash
# byte-identical to what they were.
same "grep -- pattern"   grep -- bravo f
expect_eq "printf passes -abc through" "-abc" "$("$BIN" printf -- '-abc')"
expect_exit "unknown cluster still errors" 2 "$BIN" ls -laZ tree

# `find` and `seq` walk argv themselves, which is why their multi-character
# single-dash tokens keep working. Pin that, because routing them through the
# shared parser would break both.
same "find -name"        find tree -name b
expect_eq "seq -5 bare negative" "-5 -4 -3" "$("$BIN" seq -5 -3 | tr '\n' ' ' | sed 's/ $//')"

# --- a bool long option must refuse an argument (v1.2.1) --------------
# ⛔ `--boolopt=VALUE` used to be ACCEPTED WITH THE VALUE THROWN AWAY, in every
# utility. `sort --reverse=nonsense` sorted and exited 0; so did
# `rm --force=nonsense`, `grep --count=nonsense`, `wc --lines=nonsense`. GNU
# answers "option '--x' doesn't allow an argument" and refuses. Accepting a flag
# while discarding what the user attached to it is the worst kind of gap — it
# looks like it worked.
expect_exit "sort --reverse=x refused"  2 "$BIN" sort --reverse=x nums
expect_exit "wc --lines=x refused"      2 "$BIN" wc --lines=x f
expect_exit "grep --count=x refused"    2 "$BIN" grep --count=x bravo f
expect_exit "ls --all=x refused"        2 "$BIN" ls --all=x tree
expect_exit "rm --force=x refused"      2 "$BIN" rm --force=x nosuchfile
# The message names the offending option, as GNU's does.
err=$("$BIN" sort --reverse=x nums 2>&1 >/dev/null | head -1)
case "$err" in
    *"'--reverse'"*"doesn't allow an argument"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL bool= message: %s\n" "$err" >&2 ;;
esac
# Bare bools and genuine value-taking longs are untouched.
same "bare --reverse"   sort --reverse nums
same "bare --lines"     wc --lines f
same "--key= value"     sort --key=1 f
same "--lines= value"   head --lines=2 nums
same "--bytes= value"   cut --bytes=1 f

# --- the three options GNU DOES allow a value on (v1.2.1) -------------
# ⚠ The parser cannot represent an optional-value long (registering one as a
# string would make bare `--preserve` swallow the next operand), so the utility
# opts in by name and reads the value back. These three are the whole set.
echo pv > pv.txt
expect_exit "cp --preserve=mode"            0 "$BIN" cp --preserve=mode pv.txt pv1
expect_exit "cp --preserve=timestamps"      0 "$BIN" cp --preserve=timestamps pv.txt pv2
expect_exit "cp --preserve=mode,timestamps" 0 "$BIN" cp --preserve=mode,timestamps pv.txt pv3
expect_exit "cp --preserve=links refused"   2 "$BIN" cp --preserve=links pv.txt pv4
expect_exit "cp --preserve=all refused"     2 "$BIN" cp --preserve=all pv.txt pv5
expect_exit "cp --preserve bare"            0 "$BIN" cp --preserve pv.txt pv6
expect_eq   "refused preserve copied nothing" "no" "$([ -e pv4 ] && echo yes || echo no)"

printf 'b\na\n' > unsorted.txt
expect_exit "sort --check=quiet exit 1"     1 "$BIN" sort --check=quiet unsorted.txt
expect_eq   "sort --check=quiet is silent"  "" "$("$BIN" sort --check=quiet unsorted.txt 2>&1)"
expect_exit "sort --check=bogus refused"    2 "$BIN" sort --check=bogus unsorted.txt
# ...and the diagnostic still appears without the value.
err=$("$BIN" sort --check unsorted.txt 2>&1 >/dev/null | head -1)
case "$err" in
    *disorder*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL --check diagnostic: %s\n" "$err" >&2 ;;
esac
expect_exit "tail --follow=bogus refused"   2 "$BIN" tail --follow=bogus nums

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
