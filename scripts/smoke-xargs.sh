#!/bin/sh
# smoke-xargs.sh — behavioural test for `kriya xargs`.
#
# Compares against GNU xargs cell-by-cell across input modes, batch
# shapes, the `-I` replace token, `-r` and empty input, `-L`, `-x`,
# `--show-limits`, and exit-code rollup conventions.

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

# --- -r, and empty input ----------------------------------------------

mine=$(printf '' | $BIN xargs -r echo NOPE 2>&1 || true)
gnu=$( printf '' | xargs    -r echo NOPE 2>&1 || true)
expect_eq '-r empty'           "$gnu" "$mine"

# ⛔ THIS PINNED A FALSEHOOD until 1.7.0: it compared kriya's default with GNU's
# `--no-run-if-empty`, under a comment calling that "modern GNU". GNU 4.9 and
# 4.11 run the command ONCE on empty input unless -r, and POSIX says "one or
# more times".
mine=$(printf '' | $BIN xargs    echo ONCE 2>&1 || true)
gnu=$( printf '' | xargs    echo ONCE 2>&1 || true)
expect_eq 'empty input runs the command once' "$gnu" "$mine"

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

# --- the child is no longer gagged, and the exit ladder is POSIX (v1.2.2) ---
# ⛔ stdlib `exec_env` dup2s /dev/null onto fd 2, so every diagnostic the child
# wrote was DISCARDED. It also collapses every non-exit outcome to -1, which made
# "killed by a signal" indistinguishable from "fork failed" — so a signalled
# child reported 127 (should be 125) and a non-executable one reported 123
# (should be 126). kriya now forks and execs itself (`src/lib/spawn.cyr`),
# inheriting fds 0/1/2 and reporting exec failure through a CLOEXEC pipe.
mkdir -p spawn && cd spawn
printf '#!/bin/sh\necho OUT\necho ERRMSG >&2\nexit 3\n' > sc.sh   ; chmod +x sc.sh
printf '#!/bin/sh\necho RAN "$1"\nkill -TERM $$\n'       > kill.sh ; chmod +x kill.sh
printf '#!/bin/sh\necho RAN "$1"\nexit 255\n'            > e255.sh ; chmod +x e255.sh
printf '#!/bin/sh\necho RAN "$1"\nexit 3\n'              > e3.sh   ; chmod +x e3.sh
printf '#!/bin/sh\nexit 0\n'                              > ok.sh   ; chmod +x ok.sh
printf 'not a program\n'                                   > noexec.sh; chmod 644 noexec.sh

# The child's stderr reaches the terminal — this is the whole point.
expect_eq "child stderr survives" "OUT|ERRMSG|" "$(echo foo | "$BIN" xargs ./sc.sh 2>&1 | tr '\n' '|')"

# The POSIX ladder, each rung against GNU.
led() {
    k=0; ( echo foo | "$BIN" xargs "$1" ) >/dev/null 2>&1 || k=$?
    g=0; ( echo foo | xargs      "$1" ) >/dev/null 2>&1 || g=$?
    expect_eq "exit ladder $1" "$g" "$k"
}
led ./sc.sh          # 123 — child exited nonzero
led ./kill.sh        # 125 — killed by a signal
led ./e255.sh        # 124 — exited 255
led ./noexec.sh      # 126 — found, not executable
led ./ok.sh          # 0
led ./nosuch.sh      # 127 — not found

# ⛔ 124 and 125 ABORT the invocation; a plain nonzero does not. kriya used to
# keep feeding items to a command that had already died — three ran where GNU
# ran one.
expect_eq "exit 255 aborts"     "$(printf 'a\nb\nc\n' | xargs -n1 ./e255.sh 2>/dev/null | tr '\n' '|')" "$(printf 'a\nb\nc\n' | "$BIN" xargs -n1 ./e255.sh 2>/dev/null | tr '\n' '|')"
expect_eq "signal aborts"       "$(printf 'a\nb\nc\n' | xargs -n1 ./kill.sh 2>/dev/null | tr '\n' '|')" "$(printf 'a\nb\nc\n' | "$BIN" xargs -n1 ./kill.sh 2>/dev/null | tr '\n' '|')"
expect_eq "plain nonzero continues" "$(printf 'a\nb\nc\n' | xargs -n1 ./e3.sh 2>/dev/null | tr '\n' '|')" "$(printf 'a\nb\nc\n' | "$BIN" xargs -n1 ./e3.sh 2>/dev/null | tr '\n' '|')"

# The aborting outcomes explain themselves, as GNU's do.
case "$(printf 'a\n' | "$BIN" xargs ./kill.sh 2>&1 >/dev/null)" in
    *"terminated by signal 15"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL signal diagnostic missing\n" >&2 ;;
esac
case "$(printf 'a\n' | "$BIN" xargs ./e255.sh 2>&1 >/dev/null)" in
    *"exited with status 255"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL 255 diagnostic missing\n" >&2 ;;
esac
cd ..

# --- 1.6.16: an unknown option is refused, not run ---------------------------
#
# ⛔ AN UNKNOWN OPTION BECAME THE COMMAND: `echo hi | xargs -5 echo` ran a program
# named `-5` and exited 127, "command not found", where GNU says *invalid option*.
# 127 cannot tell a typo'd flag from a missing binary. Before the command, a word
# that starts with `-` is an option, known or not — GNU's rule, and POSIX's.
for _c in "-5 echo" "-Z echo" "-n1 -5 echo" "-5" "--bogus echo" "-x5 echo"; do
    # shellcheck disable=SC2086
    expect_exit "xargs $_c refused" 2 sh -c "echo hi | \"$BIN\" xargs $_c"
    _grc=0
    # shellcheck disable=SC2086
    sh -c "echo hi | xargs $_c" >/dev/null 2>&1 || _grc=$?
    expect_eq "...and by GNU (1, not 127)" "1" "$_grc"
done
# The command still starts at the first word without a `-`, or after `--`.
expect_eq "xargs echo -5"      "$(echo hi | xargs echo -5)"      "$(echo hi | "$BIN" xargs echo -5)"
expect_eq "xargs -- echo -r"   "$(echo hi | xargs -- echo -r)"   "$(echo hi | "$BIN" xargs -- echo -r)"
expect_exit "xargs -- -5 runs '-5'" 127 sh -c "echo hi | \"$BIN\" xargs -- -5"

# --- 1.7.0: GNU's buildcmd, streaming, -L, -x, --show-limits -----------------
#
# `xsame NAME INPUT ARGS...`: stdout BYTES and the exit status, against GNU.
# INPUT is a printf format. ⚠ Only for cases GNU does not call a usage error:
# kriya exits 2 for those (ADR 0008) and GNU 1, so they are asserted apart.
xsame() {
    _n=$1; _i=$2; shift 2
    _k=0; printf "$_i" | timeout 60 "$BIN" xargs "$@" > xs_k.out 2>/dev/null || _k=$?
    _g=0; printf "$_i" | xargs "$@" > xs_g.out 2>/dev/null || _g=$?
    if cmp -s xs_k.out xs_g.out && [ "$_k" = "$_g" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s: GNU exit %s [%s], kriya exit %s [%s]\n' "$_n" "$_g" \
            "$(od -An -c xs_g.out | tr -s ' \n' '  ' | cut -c1-70)" "$_k" \
            "$(od -An -c xs_k.out | tr -s ' \n' '  ' | cut -c1-70)" >&2
    fi
}
# ⛔ The item grammar is GNU's `read_line`. VT, FF and CR SPLIT items here until
# 1.7.0; GNU splits on blanks and newline only, and skips the others only
# before an item begins.
xsame "VT inside an item"        'a\vb\n'        printf '[%s]'
xsame "FF inside an item"        'a\fb\n'        printf '[%s]'
xsame "CR inside an item"        'a\rb\n'        printf '[%s]'
xsame "VT before an item"        '\va\n'         printf '[%s]'
xsame "TAB splits"               'a\tb\n'        printf '[%s]'
xsame "NUL truncates the item"   'a\0b\n'        printf '[%s]'
# ⛔ -0 dropped EMPTY items; each NUL ends an argument in GNU, empty or not.
xsame "-0 keeps empty items"     'a\0\0b\0'      -0 printf '[%s]'
xsame "-0 lone NUL"              '\0'            -0 printf '[%s]'
xsame "-0 without a final NUL"   'a\0b'          -0 printf '[%s]'
xsame "-0 keeps blanks"          'a b\n'         -0 printf '[%s]'
# ⛔ An unmatched quote was taken as ending at EOF, and ran, exit 0. GNU refuses
# it, exit 1 — after running what it had read before it.
xsame "unmatched single quote"   "'a b\n"        printf '[%s]'
xsame "unmatched double quote"   '"a b\n'        printf '[%s]'
xsame "unmatched at EOF"         "'a b"          printf '[%s]'
xsame "unmatched after items"    "a b 'c\n"      echo
xsame "backslash newline"        'a\\\nb\n'      printf '[%s]'
xsame "backslash at EOF"         'a\\'           printf '[%s]'
xsame "quotes join"              "a'b'c\n"       printf '[%s]'
xsame "empty quotes are an item" "''\n"          printf '[%s]'
xsame "empty quotes, then x"     "'' x\n"        printf '[%s]'
xsame "quotes inside"            "a''b\n"        printf '[%s]'
xsame "a quote in quotes"        "\"a'b\"\n"     printf '[%s]'
xsame "backslash blank"          'a\\ b\n'       printf '[%s]'
xsame "-I leading blanks go"     '  a b  \n'     -I{} printf '[%s]' {}
xsame "-I backslash blank"       '  a\\ b  \n'   -I{} printf '[%s]' {}
xsame "-I quotes"                "  'a  b'  c\n" -I{} printf '[%s]' {}
xsame "-I keeps a TAB"           'a\tb\n'        -I{} printf '[%s]' {}
# ⚠ `|| true` on every captured diagnostic: under `set -e` an assignment takes the
# substitution's status, and against a binary that refuses the options below a
# failing capture ENDED THE SUITE instead of failing one assertion.
err=$(printf 'a\0b\n' | "$BIN" xargs printf '[%s]' 2>&1 >/dev/null || true)
case "$err" in
    *"NUL character occurred"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf 'FAIL NUL warning: %s\n' "$err" >&2 ;;
esac
# -L N: N non-blank lines per command; a trailing blank continues the line.
xsame "-L 2"                     'a b\nc\nd e f\n'      -L 2 echo
xsame "-L 1, trailing blank"     'a \nb\nc\n'           -L 1 echo
xsame "-L 1, trailing TAB"       'a\t\nb\nc\n'          -L 1 echo
xsame "-L 2 skips blank lines"   'a\n\nb\n\n\nc\n'      -L 2 echo
xsame "-L 1, a blanks-only line" 'a\n   \nb\n'          -L 1 echo
xsame "-L with -0"               'a\0b\0c\0'            -0 -L 2 echo
xsame "--max-lines="             'a b\n'                --max-lines=1 echo
# ⚠ Deliberate: GNU's `--max-lines` is the long form of the deprecated `-l`,
# whose value is OPTIONAL, so `--max-lines 1 echo` runs a command named `1`.
# ADR 0002 has no optional values: here the next word is the value.
expect_eq "--max-lines VALUE (ADR 0002)" "a b|c|" \
    "$(printf 'a b\nc\n' | "$BIN" xargs --max-lines 1 echo | tr '\n' '|')"
# -n, -L and -I: the last one wins, as in GNU, with its warnings.
xsame "-L then -n"               'a b c d e\n'          -L 1 -n 2 echo
xsame "-n then -L"               'a b c d e\n'          -n 2 -L 1 echo
xsame "-I then -L"               'a b\nc d\n'           -I{} -L 1 echo {}
xsame "-L then -I"               'a b\nc d\n'           -L 1 -I{} echo {}
xsame "-I then -n 2"             'a b\nc d\n'           -I{} -n 2 echo {}
xsame "-n 2 then -I"             'a b\nc d\n'           -n 2 -I{} echo {}
xsame "-I then -n 1 stays -I"    'a b\nc d\n'           -I{} -n 1 echo {}
for _w in "-L 1 -n 2" "-n 2 -L 1" "-I{} -L 1" "-L 1 -I{}" "-I{} -n 2" "-n 2 -I{}"; do
    # shellcheck disable=SC2086
    err=$(printf 'a\n' | "$BIN" xargs $_w echo 2>&1 >/dev/null || true)
    case "$err" in
        *"mutually exclusive, ignoring previous"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf 'FAIL %s warns: %s\n' "$_w" "$err" >&2 ;;
    esac
done
expect_eq "-I then -n 1 says nothing" "" "$(printf 'a\n' | "$BIN" xargs -I{} -n 1 echo {} 2>&1 >/dev/null)"
for _v in 0 -1 x ''; do
    expect_exit "-L '$_v' refused" 2 sh -c "printf 'a\n' | \"$BIN\" xargs -L '$_v' echo"
    expect_exit "-n '$_v' refused" 2 sh -c "printf 'a\n' | \"$BIN\" xargs -n '$_v' echo"
done
xsame "-n past 2^63 is just large" 'a b\n'              -n 99999999999999999999 echo
# -x: stop rather than split — and only with -n, -L or -I, as GNU's does.
xsame "-x -n 5 -s 12"            '1 2 3 4 5 6 7 8 9 10\n' -x -n 5 -s 12 echo
xsame "-n 5 -s 12 splits"        '1 2 3 4 5 6 7 8 9 10\n' -n 5 -s 12 echo
xsame "-x alone splits"          '1 2 3 4 5 6 7 8 9 10\n' -x -s 12 echo
xsame "--exit -n 1"              'a b\n'                  --exit -n 1 echo
xsame "-L 1 -s 11 fits"          '1 2 3\n4 5 6\n'         -L 1 -s 11 echo
xsame "-L 1 -s 10 is too long"   '1 2 3\n4 5 6\n'         -L 1 -s 10 echo
xsame "-I -s 12 too long"        'aaaaaaaa\n'             -I{} -s 12 echo {}
xsame "-I -s 13 too long"        'aaaaaaaa\n'             -I{} -s 13 echo {}
xsame "-I -s 14 fits"            'aaaaaaaa\n'             -I{} -s 14 echo {}
xsame "empty -I string"          'a\n'                    -I '' echo x
# -s: the size of a command line, strlen + 1 per argument, the command's own
# included; exactly equal fits.
for _s in 12 11 7 6 5 1 0 4095 99999999 99999999999999999999; do
    xsame "-s $_s" '1\n2\n3\n4\n5\n' -s "$_s" echo
done
expect_exit "-s abc refused" 2 sh -c "printf 'a\n' | \"$BIN\" xargs -s abc echo"
# ⭐ BATCHES, counted as GNU counts them: `$#` per command, under a pinned
# environment, since the environment is part of the ceiling.
xbatch() {
    _n=$1; _gen=$2; shift 2
    _k=$(sh -c "$_gen" | env -i PATH=/usr/bin:/bin timeout 60 "$BIN" xargs "$@" | tr '\n' ' ')
    _g=$(sh -c "$_gen" | env -i PATH=/usr/bin:/bin xargs "$@" | tr '\n' ' ')
    expect_eq "$_n" "$_g" "$_k"
}
xbatch "default buffer, 60,000 items" "seq -w 1 60000" sh -c 'echo $#' sh
xbatch "-s 1000"                      "seq -w 1 3000"  -s 1000 sh -c 'echo $#' sh
xbatch "-s 20"                        "seq -w 1 30"    -s 20 sh -c 'echo $#' sh
xbatch "-n 7000 under the buffer"     "seq -w 1 60000" -n 7000 sh -c 'echo $#' sh
# ⭐ E2BIG: past what the kernel takes, GNU halves and then bisects, remembering
# across batches. The port is exact: these are GNU's own numbers.
xbatch "E2BIG bisection, -s 2000000"  "seq 1 500000"   -s 2000000 sh -c 'echo $#' sh
# --show-limits: GNU's six lines, byte for byte, in a pinned environment.
for _e in "" "A=1" "A=1 B=22"; do
    # shellcheck disable=SC2086
    expect_eq "--show-limits [$_e]" "$(env -i $_e xargs --show-limits </dev/null 2>&1)" \
        "$(env -i $_e "$BIN" xargs --show-limits </dev/null 2>&1)"
done
expect_eq "--show-limits -s 5000" "$(env -i A=1 xargs -s 5000 --show-limits </dev/null 2>&1)" \
    "$(env -i A=1 "$BIN" xargs -s 5000 --show-limits </dev/null 2>&1)"
expect_eq "--show-limits, 256 KiB of stack" \
    "$(sh -c 'ulimit -s 256; env -i xargs --show-limits -r </dev/null' 2>&1)" \
    "$(sh -c "ulimit -s 256; env -i '$BIN' xargs --show-limits -r </dev/null" 2>&1)"
# ⛔ STREAMED: the input was read to EOF before anything ran, so this never ended.
expect_eq "yes | xargs -n1 | head" "y y y" \
    "$(timeout 10 sh -c "yes | '$BIN' xargs -n1 echo 2>/dev/null | head -3" | tr '\n' ' ' | sed 's/ $//')"
# The child's stdin is /dev/null — so a `cat` cannot eat the input still to come.
xsame "the child reads /dev/null" 'a\nb\nc\n'  -n1 sh -c 'cat; echo "arg=$1"' sh
# -t quotes each argument as `ls` would, and the default command is `echo`.
expect_eq "-t quoting" "$(printf 'a\\ b\nc\n""\n' | xargs -t true 2>&1)" \
    "$(printf 'a\\ b\nc\n""\n' | "$BIN" xargs -t true 2>&1)"
expect_eq "-t default echo" "$(echo x | xargs -t 2>&1)" "$(echo x | "$BIN" xargs -t 2>&1)"
# ⛔ -I NEVER SUBSTITUTES INTO THE COMMAND NAME — POSIX inserts "in arguments".
# kriya did, so the INPUT chose the program.
xsame "-I leaves the command alone" 'echo\n'   -I{} {} hi
xsame "-I on empty input runs nothing" ''      -I{} echo X{}Y
xsame "-I substitutes in arguments"  'x\n'     -I{} echo {} a{}b {}{}
# ⛔ A failed exec STOPS xargs, as in GNU; kriya went on to the next batch.
xsame "exec failure stops"        'a\nb\n'     -n 1 nosuch-cmd-1-7-0
xsame "exit 3 carries on, 123"    'a\nb\n'     -n 1 sh -c 'echo $1; exit 3' sh

# --- -d, -E, -a, -o (1.8.2) --------------------------------------------
# Measured against findutils 4.9 and 4.10: identical on every case here.
xsame "-d , keeps an empty item"     'p,q,,r,'       -d , printf '[%s]'
xsame "-d , last item unterminated"  'p,q'           -d , printf '[%s]'
xsame "-d '\\n' keeps blanks"         'a b\n\nc\n'    -d '\n' printf '[%s]'
xsame "-d: quotes are bytes"         "'a' \"b\""     -d ' ' printf '[%s]'
xsame "-d '\\t'"                      'a\tb'          -d '\t' printf '[%s]'
xsame "-d '\\x41' (hex)"              'aAbAc'         -d '\x41' printf '[%s]'
xsame "-d '\\101' (octal)"            'aAbAc'         -d '\101' printf '[%s]'
xsame "-d '\\0' is -0"                'a\000b'        -d '\0' printf '[%s]'
xsame "-d '\\\\' (backslash)"          'a\\b'          -d '\\' printf '[%s]'
xsame "-d '\\x' alone is NUL (GNU's quirk)" 'a'       -d '\x' printf '[%s]'
xsame "-d with -n 2"                 'a,b,c'         -d , -n 2 printf '[%s]'
xsame "-0 then -d: last wins"        'a,b'           -0 -d , printf '[%s]'
xsame "-d then -0: last wins"        'a\000b'        -d , -0 printf '[%s]'
xsame "-d backslash in the input stays" 'a\\\nb\n'    -d '\n' printf '[%s]'
for _d in ab '' '\q' '\x1ff' '\400' '\xg' '\x41z' '\8'; do
    _k=0; printf 'a' | "$BIN" xargs -d "$_d" echo >/dev/null 2>&1 || _k=$?
    _g=0; printf 'a' | xargs -d "$_d" echo >/dev/null 2>&1 || _g=$?
    expect_eq "-d '$_d' is refused (GNU too; usage exit 2)" "refused|2" \
        "$( [ "$_g" -ne 0 ] && echo refused || echo ran)|$_k"
done
xsame "-E ends the input"            'a\nb\nSTOP\nc\n' -E STOP echo
xsame "-E mid-line"                  'a STOP b\nc\n'   -E STOP echo
xsame "-E matches a quoted item"     "a 'STOP' b\n"    -E STOP echo
xsame "-E with -I compares the line" 'a\nSTOP\nb\n'    -E STOP -I{} echo x{}
xsame "-E '' is none"                'a\n\nb\n'        -E '' echo
xsame "-E as the first item still runs once" 'STOP\na\n' -E STOP echo
xsame "-E first item under -r runs nothing"  'STOP\na\n' -r -E STOP echo
xsame "-E, last wins"                'a\nX\nb\n'       -E STOP -E X echo
xsame "-E has no effect under -0"    'a\000STOP\000b\000' -0 -E STOP echo
_ke=$(printf 'a' | "$BIN" xargs -0 -E STOP echo 2>&1 >/dev/null)
expect_eq "-E under -0 warns, as GNU" "kriya xargs: warning: the -E option has no effect if -0 or -d is used." "$_ke"
# ⚠ The deliberate divergence: GNU passes the string through as the last item of an
# unterminated line after another item; kriya stops (POSIX's "logical end-of-file").
expect_eq "-E at an unterminated end of input stops (GNU passes it)" "a" \
    "$(printf 'a STOP' | "$BIN" xargs -E STOP echo)"
printf 'a b\nc d\n' > xa_in1; printf 'x\ny\n' > xa_in2
xsame "-a FILE"                      ''              -a xa_in1 echo
xsame "-a, last wins"                ''              -a xa_in1 -a xa_in2 echo
xsame "-a - is stdin"                'z\n'           -a - echo
xsame "--arg-file="                  ''              --arg-file=xa_in2 echo
xsame "--delimiter="                 'a,b'           --delimiter=, printf '[%s]'
xsame "--eof="                       'a\nX\nb\n'     --eof=X echo
_k=$(printf 'FROMSTDIN\n' | "$BIN" xargs -a xa_in2 sh -c 'cat; echo $0' 2>&1)
_g=$(printf 'FROMSTDIN\n' | xargs -a xa_in2 sh -c 'cat; echo $0' 2>&1)
expect_eq "-a FILE: the command keeps xargs's stdin, as GNU's" "$_g" "$_k"
_k=$(printf 'x\n' | "$BIN" xargs -a - sh -c 'cat; echo done' 2>&1)
expect_eq "-a -: the command reads /dev/null" "done" "$_k"
_k=0; "$BIN" xargs -a xa_nosuch echo >/dev/null 2>&1 || _k=$?
expect_eq "-a of a missing file: exit 1, as GNU" "1" "$_k"
# -o: the command reads the terminal. With none, kriya fails before running anything (GNU's
# child dies of an assertion); on one, the command's stdin is the terminal.
_k=0; _ke=$(printf 'a\n' | setsid "$BIN" xargs -o echo 2>&1) || _k=$?
expect_eq "-o with no terminal: exit 1, nothing runs" "1|kriya xargs: /dev/tty: no such device or address" "$_k|$_ke"
_k=0; (printf '' | setsid "$BIN" xargs -o -r echo >/dev/null 2>&1) || _k=$?
expect_eq "-o with -r and no input never needs the terminal" "0" "$_k"
if script -qec true /dev/null >/dev/null 2>&1; then
    # ⚠ xargs reads its items from a PIPE inside the terminal session, so without -o the
    # command would get /dev/null; only -o can make its stdin the terminal. (Under -a, or with
    # xargs on the terminal itself, the case would pass with no -o at all.)
    # shellcheck disable=SC2016
    _o=$(script -qec "printf 'a\\n' | '$BIN' xargs -o sh -c '[ -t 0 ] && echo stdin-is-a-tty || echo not-a-tty'" /dev/null < /dev/null 2>&1 | tr -d '\r')
    expect_eq "-o on a terminal: the command's stdin is the terminal" "stdin-is-a-tty" "$_o"
    # shellcheck disable=SC2016
    _o=$(script -qec "printf 'a\\n' | '$BIN' xargs sh -c '[ -t 0 ] && echo stdin-is-a-tty || echo not-a-tty'" /dev/null < /dev/null 2>&1 | tr -d '\r')
    expect_eq "...and without -o it is not" "not-a-tty" "$_o"
fi

# --- -P, -p (1.8.2) ----------------------------------------------------
# -P's concurrency, measured rather than timed: each command logs `+` when it starts and `-`
# when it ends, and sleeps long enough to overlap; the peak of the running sum is how many ran
# at once. (Timing bounds would flake on a loaded runner; the peak does not.)
xp_peak() {
    rm -f xp.log
    # shellcheck disable=SC2016
    printf '1\n2\n3\n4\n5\n6\n' | "$BIN" xargs "$@" -n1 sh -c 'echo + >> xp.log; sleep 0.3; echo - >> xp.log' sh
    awk 'BEGIN{n=0;m=0} /\+/{n++; if(n>m)m=n} /-/{n--} END{print m}' xp.log
}
expect_eq "-P 2 runs two at once"            "2" "$(xp_peak -P 2)"
expect_eq "-P 0 runs them all at once"       "6" "$(xp_peak -P 0)"
expect_eq "-P 1 runs one at a time"          "1" "$(xp_peak -P 1)"
expect_eq "--max-procs=3"                    "3" "$(xp_peak --max-procs=3)"
xp_sorted() {
    _n=$1; _i=$2; shift 2
    _k=0; _ko=$(printf "$_i" | timeout 60 "$BIN" xargs "$@" 2>/dev/null | sort) || _k=$?
    _g=0; _go=$(printf "$_i" | xargs "$@" 2>/dev/null | sort) || _g=$?
    expect_eq "$_n (exit|sorted stdout)" "$_g|$_go" "$_k|$_ko"
}
xp_sorted "-P: exit 3 everywhere is 123"      'a\nb\nc\n'   -P 3 -n1 sh -c 'exit 3' sh
# ⚠ 255 stops new starts, but the command already running finishes first. The 255 exits at
# once and the others sleep, so which one is reaped first is not a race: exactly one `ran 0`.
# shellcheck disable=SC2016
xp_sorted "-P: a 255 lets the running one finish, 124" '255\n0\n0\n0\n' -P 2 -n1 sh -c '[ "$1" = 255 ] && exit 255; sleep 0.5; echo ran $1' sh
# shellcheck disable=SC2016
# ...and xargs EXITS only once that command has finished. (Captured output cannot show it: a
# command left running keeps the pipe open, so the output arrives either way.)
for _x in xargs "$BIN"; do
    rm -f xp255.out
    # shellcheck disable=SC2016
    ( printf '255\n0\n0\n0\n' | if [ "$_x" = xargs ]; then xargs -P 2 -n1 sh -c '[ "$1" = 255 ] && exit 255; sleep 0.5; : > xp255.out' sh; else "$_x" xargs -P 2 -n1 sh -c '[ "$1" = 255 ] && exit 255; sleep 0.5; : > xp255.out' sh; fi >/dev/null 2>&1 ) || true
    if [ "$_x" = xargs ]; then _gw=$( [ -e xp255.out ] && echo waited || echo did-not-wait ); else _kw=$( [ -e xp255.out ] && echo waited || echo did-not-wait ); fi
done
expect_eq "-P: after a 255, xargs exits once the running command is done (GNU too)" "waited|waited" "$_gw|$_kw"
xp_sorted "-P: a signal is 125"               'a\nb\n'      -P 2 -n1 sh -c 'kill -9 $$' sh
xp_sorted "-P: a missing command is 127"      'a\nb\nc\nd\n' -P 2 -n1 nosuch-cmd-1-8-2
xp_sorted "-P with -I"                        'a\nb\nc\n'   -P 3 -I{} echo x{}
xp_sorted "-P with -t"                        'a\nb\n'      -P 1 -t -n1 echo
xp_sorted "-P with -n 2"                      'a b c d e\n' -P 2 -n 2 echo
for _v in -1 x 99999999999 2147483648; do
    _k=0; printf 'a\n' | "$BIN" xargs -P "$_v" echo >/dev/null 2>&1 || _k=$?
    _g=0; printf 'a\n' | xargs -P "$_v" echo >/dev/null 2>&1 || _g=$?
    expect_eq "-P $_v is refused (GNU too; usage exit 2)" "refused|2" "$( [ "$_g" -ne 0 ] && echo refused || echo ran)|$_k"
done
xsame "-P 2147483647 is INT_MAX, taken"       'a\n'          -P 2147483647 echo
# -p: answers come from /dev/tty, never from a pipe (ADR 0002); with no terminal, xargs fails
# before asking or running anything (GNU prints the command first, then fails).
_k=0; _ke=$(printf 'a\n' | setsid "$BIN" xargs -p echo 2>&1) || _k=$?
expect_eq "-p with no terminal: exit 1, nothing asked or run" "1|kriya xargs: /dev/tty: no such device or address" "$_k|$_ke"
_k=0; (printf '' | setsid "$BIN" xargs -p -r echo >/dev/null 2>&1) || _k=$?
expect_eq "-p with -r and no input never needs the terminal" "0" "$_k"
if script -qec true /dev/null >/dev/null 2>&1; then
    xp_tty() {
        _ans=$1; shift
        printf "$_ans" | script -qec "printf 'a\\nb\\nc\\n' | $*" /dev/null 2>&1 | tr -d '\r' | grep -v '^y$\|^n$\|^yes$\|^$'
    }
    expect_eq "-p on a terminal: GNU's prompt and answers, byte for byte" \
        "$(xp_tty 'y\nn\nyes\n' xargs -p -n1 echo RAN)" "$(xp_tty 'y\nn\nyes\n' "'$BIN'" xargs -p -n1 echo RAN)"
    expect_eq "-p: declining the only command asks nothing more, as GNU" \
        "$(xp_tty 'n\nn\n' xargs -p echo RAN)" "$(xp_tty 'n\nn\n' "'$BIN'" xargs -p echo RAN)"
    expect_eq "-p with -t prints the line once, as the prompt" \
        "$(xp_tty 'y\n' xargs -p -t echo)" "$(xp_tty 'y\n' "'$BIN'" xargs -p -t echo)"
    expect_eq "-p: when every command is declined, GNU asks once more for the bare one" \
        "$(xp_tty 'n\nn\nn\nn\n' xargs -p -n1 echo RAN)" "$(xp_tty 'n\nn\nn\nn\n' "'$BIN'" xargs -p -n1 echo RAN)"
    # ⚠ Under -P a child can write INTO a prompt (both GNU's and kriya's go out in pieces), so
    # the children write to a file and the terminal holds the prompts alone.
    printf 'echo "RAN $1" >> xp_par.out\n' > xp_par.sh
    xp_par() {
        rm -f xp_par.out
        _t=$(xp_tty 'y\ny\ny\n' "$@" xargs -p -P 2 -n1 sh xp_par.sh)
        printf '%s|%s' "$(printf '%s' "$_t" | grep -o 'sh xp_par.sh [abc]?\.\.\.' | wc -l | tr -d ' ')" \
            "$(sort xp_par.out 2>/dev/null | tr '\n' ' ')"
    }
    expect_eq "-p with -P 2: asks in turn, runs them all" "$(xp_par)" "$(xp_par "'$BIN'")"
else
    echo "skip: no usable script(1) -- the -p terminal cases are not exercised"
fi

# --- summary ---------------------------------------------------------

TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
