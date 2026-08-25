#!/bin/sh
# smoke-xargs.sh — behavioural test for `kriya xargs`.
#
# Compares against GNU xargs cell-by-cell across input modes, batch
# shapes, the `-I` replace token, the `-r` no-run-if-empty default,
# and exit-code rollup conventions.

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
        printf 'FAIL %s:\nexpected: %s\ngot:      %s\n' "$1" "$2" "$3" >&2
    fi
}

expect_exit() {
    name=$1
    expected=$2
    shift 2
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}

compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | eval "$BIN xargs $args" 2>&1 || true)
    gnu=$( printf '%s' "$input" | eval "xargs $args"      2>&1 || true)
    expect_eq "$name" "$gnu" "$mine"
}

# --- default behaviour: no command → /bin/echo --------------------------

compare 'default echo'         "a b c"            ""
compare 'default echo lines'   "$(printf 'a\nb\nc\n')" ""
compare 'with command'         "a b c"            "echo HIT"

# --- -n batches --------------------------------------------------------

compare '-n 1 batches'         "a b c d"          "-n 1 echo X"
compare '-n 2 batches'         "a b c d"          "-n 2 echo X"
compare '-n 3 batches'         "a b c d e"        "-n 3 echo X"

# --- -0 NUL-separated --------------------------------------------------

mine=$(printf 'a\0b\0c\0' | $BIN xargs -0 echo)
gnu=$( printf 'a\0b\0c\0' | xargs    -0 echo)
expect_eq '-0 NUL items'       "$gnu" "$mine"

mine=$(printf 'a b\0c d\0' | $BIN xargs -0 echo)
gnu=$( printf 'a b\0c d\0' | xargs    -0 echo)
expect_eq '-0 preserves spaces' "$gnu" "$mine"

# --- -I replace -------------------------------------------------------

compare '-I {}'                "$(printf 'one\ntwo\nthree\n')" "-I {} echo '[{}]'"
compare '-I @ custom'          "$(printf 'one\ntwo\n')"        "-I @ echo before @ after"
compare '-I {} multi-sub'      "$(printf 'X\n')"                "-I {} echo {} and {}"

# --- -r no-run-if-empty (modern GNU default) --------------------------

mine=$(printf '' | $BIN xargs -r echo NOPE 2>&1 || true)
gnu=$( printf '' | xargs    -r echo NOPE 2>&1 || true)
expect_eq '-r empty'           "$gnu" "$mine"

mine=$(printf '' | $BIN xargs    echo NOPE 2>&1 || true)
gnu=$( printf '' | xargs    --no-run-if-empty echo NOPE 2>&1 || true)
expect_eq 'default empty matches --no-run-if-empty' "$gnu" "$mine"

# --- quoting / backslash ----------------------------------------------

compare 'single quotes'        "'a b' c"          "echo"
compare 'double quotes'        '"a b" c'          "echo"
compare 'backslash escape'     "a\\ b c"          "echo"

# --- -t trace ---------------------------------------------------------

mine=$(printf 'a b\n' | $BIN xargs -t echo HIT 2>&1)
gnu=$( printf 'a b\n' | xargs    -t echo HIT 2>&1)
expect_eq '-t trace'           "$gnu" "$mine"

# --- exit codes ------------------------------------------------------

expect_exit 'all succeed'       0 sh -c "printf 'a\n' | $BIN xargs true"
expect_exit 'child failure 123' 123 sh -c "printf 'a\n' | $BIN xargs false"

# --- PATH resolution --------------------------------------------------

mine=$(printf 'a\n' | $BIN xargs basename)
gnu=$( printf 'a\n' | xargs    basename)
expect_eq 'PATH resolves'      "$gnu" "$mine"

# --- a command that cannot be found must not fall back to the CWD (v1.1.11) ---
# ⛔ `execve` does NO path search: a slash-free name is resolved by the KERNEL
# against the CURRENT DIRECTORY. xargs used to hand the bare name over whenever
# PATH was unset or the search came up empty, so a stray `./ls` in the working
# directory got executed instead of the real one. Demonstrated: `env -u PATH
# xargs ls` ran an attacker-supplied ./ls. Now an unset PATH falls back to
# /bin:/usr/bin (what glibc's execvp does) and a failed search exits 127.
mkdir -p cwdexec
printf '#!/bin/sh\necho PWNED-FROM-CWD\n' > cwdexec/ls
chmod +x cwdexec/ls

expect_eq "unset PATH does not run ./ls" "" \
    "$(cd cwdexec && printf 'ITEM\n' | env -u PATH "$BIN" xargs ls 2>/dev/null | grep PWNED)"
expect_exit "missing command exits 127" 127 \
    sh -c "printf 'ITEM\n' | '$BIN' xargs definitely-not-a-real-command"
# A real command still resolves and runs.
expect_eq "PATH lookup still works" "a b" "$(printf 'a\nb\n' | "$BIN" xargs echo)"

# --- option recognition stops at the first operand (v1.2.0) -------------
# ⛔ xargs used to parse the CHILD's command line as its own. `xargs sort -r`
# silently sorted ASCENDING (`-r` eaten as --no-run-if-empty) and
# `xargs head -n 2` ran head with no options at all — wrong output, exit 0.
# Worst of all the `--` GUARD WAS CONSUMED AND DELETED, so `ls -1 | xargs rm --`
# handed rm a list beginning `-r` and recursively deleted what `--` protected.
printf 'c\nb\na\n' > sortme.txt
printf '1\n2\n3\n4\n5\n' > fivelines.txt

expect_eq "child keeps -r" \
    "$(echo sortme.txt | xargs sort -r | tr '\n' ' ')" \
    "$(echo sortme.txt | "$BIN" xargs sort -r | tr '\n' ' ')"
expect_eq "child keeps -n 2" \
    "$(echo fivelines.txt | xargs head -n 2 | tr '\n' ' ')" \
    "$(echo fivelines.txt | "$BIN" xargs head -n 2 | tr '\n' ' ')"

# The `--` guard reaches the child. A file literally named `-r` must be removed
# as a FILE, and the sibling directory must survive untouched.
mkdir -p guard/keep
touch guard/keep/important
touch "guard/-r"
( cd guard && ls -1 | "$BIN" xargs rm -- ) >/dev/null 2>&1 || true
expect_eq "-- guard: directory survived"  "yes" "$([ -d guard/keep ] && echo yes || echo no)"
expect_eq "-- guard: its contents too"    "yes" "$([ -f guard/keep/important ] && echo yes || echo no)"
expect_eq "-- guard: the -r FILE removed" "no"  "$([ -e "guard/-r" ] && echo yes || echo no)"

# xargs' own options are still recognised, in both spellings.
expect_eq "own -n 1 still works"  "a b c" "$(printf 'a\nb\nc\n' | "$BIN" xargs -n 1 echo | tr '\n' ' ' | sed 's/ $//')"
expect_eq "own -n1 attached"      "a b c" "$(printf 'a\nb\nc\n' | "$BIN" xargs -n1 echo | tr '\n' ' ' | sed 's/ $//')"

# --- -I splits on LINES, not blanks (v1.2.0) ---------------------------
# ⛔ POSIX gives a replacement string one LINE per invocation. Splitting on
# blanks meant `printf 'a b\n' | xargs -I{} rm -- {}` deleted files named `a`
# and `b` and left `a b` — the wrong files, silently. Same shape mangled every
# spaced filename in the everyday `ls | xargs -I{} mv {} dest/` idiom.
for spec in 'a b\n' '  a b  \n' 'a b\nc\n' '"a b"\n' 'a\\ b\n' 'a\n\nb\n' 'a\tb\n'; do
    expect_eq "-I split [$spec]" \
        "$(printf "$spec" | xargs      -I{} echo "[{}]" | tr '\n' ' ')" \
        "$(printf "$spec" | "$BIN" xargs -I{} echo "[{}]" | tr '\n' ' ')"
done

# The destructive shape, end to end: only the spaced file goes.
mkdir -p ispace && ( cd ispace && touch a b "a b" && printf 'a b\n' | "$BIN" xargs -I{} rm -- "{}" )
expect_eq "-I: 'a' survives"   "yes" "$([ -f ispace/a ] && echo yes || echo no)"
expect_eq "-I: 'b' survives"   "yes" "$([ -f ispace/b ] && echo yes || echo no)"
expect_eq "-I: 'a b' removed"  "no"  "$([ -e "ispace/a b" ] && echo yes || echo no)"

# -0 still splits on NUL even with -I.
expect_eq "-0 with -I unaffected" \
    "$(printf 'a b\0c\0' | xargs      -0 -I{} echo "[{}]" | tr '\n' ' ')" \
    "$(printf 'a b\0c\0' | "$BIN" xargs -0 -I{} echo "[{}]" | tr '\n' ' ')"
# ...and without -I, blank splitting is unchanged.
expect_eq "non -I still blank-splits" \
    "$(printf 'a b\nc\n' | xargs      echo | tr '\n' ' ')" \
    "$(printf 'a b\nc\n' | "$BIN" xargs echo | tr '\n' ' ')"

# --- summary ---------------------------------------------------------

TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
