#!/bin/sh
# smoke-find.sh — behavioural test for `kriya find`.
#
# Compares kriya find against GNU find cell-by-cell across the shipped
# predicate set + operators + actions.

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

# Sort outputs before compare — find's traversal order is not specified.
compare_sorted() {
    name=$1
    args=$2
    mine=$(eval "$BIN find $args" | sort)
    gnu=$( eval "find $args" | sort)
    expect_eq "$name" "$gnu" "$mine"
}

# --- fixture tree ---
mkdir -p tree/a tree/b tree/a/deep
echo small   > tree/small.txt
echo medium  > tree/a/medium.log
:            > tree/a/empty.txt
seq 1 100    > tree/a/deep/big.txt
mkdir tree/empty_dir
ln -s small.txt tree/a/lnk
touch -d '2 days ago' tree/old.txt
touch -d '1 minute ago' tree/recent.txt

# --- default action: print tree ---
compare_sorted 'default print'       'tree'
compare_sorted 'subdir start'        'tree/a'

# --- -type ---
compare_sorted '-type f'             'tree -type f'
compare_sorted '-type d'             'tree -type d'
compare_sorted '-type l'             'tree -type l'

# --- -name (glob) ---
compare_sorted '-name *.txt'         "tree -name '*.txt'"
compare_sorted '-name *.log'         "tree -name '*.log'"
compare_sorted '-name [se]*'         "tree -name '[se]*'"
compare_sorted '-name ?ig.txt'       "tree -name '?ig.txt'"
compare_sorted '-name no-match'      "tree -name 'zzzzz'"

# --- size ---
compare_sorted '-size 0c'            'tree -size 0c'
compare_sorted '-size +5c'           'tree -size +5c'
compare_sorted '-size -10c'          'tree -size -10c'
compare_sorted '-size +1c default block' 'tree -size +0'

# --- -empty ---
compare_sorted '-empty'              'tree -empty'

# --- -newer ---
compare_sorted '-newer ref'          'tree -newer tree/old.txt'

# --- -mtime ---
compare_sorted '-mtime +1'           'tree -mtime +1'
compare_sorted '-mtime -1'           'tree -mtime -1'

# --- depth limits ---
compare_sorted '-maxdepth 1'         'tree -maxdepth 1'
compare_sorted '-maxdepth 0'         'tree -maxdepth 0'
compare_sorted '-mindepth 2'         'tree -mindepth 2'
compare_sorted '-maxdepth 2 -type f' 'tree -maxdepth 2 -type f'

# --- operators ---
compare_sorted 'AND implicit'        "tree -type f -name '*.txt'"
compare_sorted '-a explicit'         "tree -type f -a -name '*.txt'"
compare_sorted '-o alternation'      "tree -name '*.log' -o -name '*.txt'"
compare_sorted '! invert'            "tree ! -type f"
compare_sorted '-not invert'         "tree -not -type d"
compare_sorted 'parens'              "tree '(' -type f -o -type l ')'"

# --- actions ---
compare_sorted '-print explicit'     'tree -type f -print'

# -print0: compare via od since the separator is NUL.
mine=$($BIN find tree -type f -print0 | od -An -c | tr -s ' ')
gnu=$( find tree -type f -print0 | od -An -c | tr -s ' ')
expect_eq '-print0' "$gnu" "$mine"

# -exec — `echo hit {}` via PATH-resolved echo, sorted output.
mine=$($BIN find tree -type f -exec echo hit {} \; | sort)
gnu=$( find tree -type f -exec echo hit {} \; | sort)
expect_eq '-exec echo {}' "$gnu" "$mine"

mine=$($BIN find tree -name '*.txt' -exec wc -l {} \; | sort)
gnu=$( find tree -name '*.txt' -exec wc -l {} \; | sort)
expect_eq '-exec wc -l' "$gnu" "$mine"

# -L follow symlinks: lnk → small.txt (regular file).
mine=$($BIN find -L tree -type f | sort)
gnu=$(  find -L tree -type f | sort)
expect_eq '-L type f follows' "$gnu" "$mine"

# Multiple start paths.
compare_sorted 'multi-start'         'tree/a tree/empty_dir'

# --- error / exit codes ---
expect_exit 'no operand defaults to .' 0 "$BIN" find -maxdepth 0
expect_exit 'unknown predicate'        2 "$BIN" find tree -frobnicate
expect_exit 'bad -size'                2 "$BIN" find tree -size abc
expect_exit 'missing -exec ;'          2 sh -c "$BIN find tree -exec echo"
expect_exit 'missing start path'       1 "$BIN" find /no/such/path
expect_exit '-H accepted (1.7.1)'      0 "$BIN" find -H tree

# --- -exec {} expansion is sized exactly (v1.1.11) ----------------------
# ⛔ The rebuild buffer was `tlen + plen * 4`, silently assuming at most four
# `{}` in one token. A fifth ran the loop past the allocation: kriya emitted four
# copies of the path, a truncated fifth, then bytes from the ADJACENT HEAP OBJECT
# (its own cached PATH) — a heap disclosure straight into the child's argv.
# Compared against GNU, which is the oracle for the expected text.
mkdir -p brace/a_reasonably_long_directory_name
touch brace/a_reasonably_long_directory_name/target_file.txt

for n in 1 2 4 5 8 20; do
    tok=$(awk -v n="$n" 'BEGIN{s="{}"; for(i=1;i<n;i++) s=s "-{}"; print s}')
    k=$("$BIN" find brace -name 'target*' -exec echo "$tok" \; 2>&1)
    g=$(find      brace -name 'target*' -exec echo "$tok" \; 2>&1)
    expect_eq "-exec with $n {} matches GNU" "$g" "$k"
done

# plen < 2 makes the per-occurrence delta NEGATIVE (the result is shorter than
# the token) — the arithmetic has to stay correct there too.
mkdir -p br2
touch br2/x
k=$(cd br2 && "$BIN" find . -name x -exec echo 'A{}B{}C{}D{}E{}F' \; 2>&1)
g=$(cd br2 && find      . -name x -exec echo 'A{}B{}C{}D{}E{}F' \; 2>&1)
expect_eq "-exec with a short path matches GNU" "$g" "$k"

# --- -exec no longer swallows the child's stderr (v1.2.2) ---
# ⛔ `find rot -name '*.tmp' -exec rm {} \;` on an unwritable directory printed
# NOTHING and exited 0 while deleting nothing — a cleanup job reporting complete
# success having done nothing at all. stdlib `exec_env` dup2s /dev/null onto
# fd 2; kriya now forks and execs itself with fds 0/1/2 inherited.
mkdir -p gag && touch gag/x.tmp gag/y.tmp && chmod 555 gag
kerr=$("$BIN" find gag -name '*.tmp' -exec rm {} \; 2>&1 | sort | tr '\n' '|')
chmod 755 gag && rm -f gag/*.tmp && touch gag/x.tmp gag/y.tmp && chmod 555 gag
gerr=$(find      gag -name '*.tmp' -exec rm {} \; 2>&1 | sort | tr '\n' '|')
chmod 755 gag
expect_eq "-exec child stderr matches GNU" "$gerr" "$kerr"
case "$kerr" in
    *"Permission denied"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL -exec stderr was swallowed: [%s]\n" "$kerr" >&2 ;;
esac

# A command that cannot be executed is reported, not silently treated as false.
expect_exit "-exec missing command -> 1" 1 "$BIN" find gag -name '*.tmp' -exec ./nosuchcmd {} \;

# --- ⭐ -regex / -iregex / -regextype, against GNU ------------------------
#
# ⛔ kriya's DEFAULT DIALECT IS POSIX BRE; GNU's is EMACS. They disagree on the
# characters people actually reach for — `-regex '.*a+b'` is one-or-more under
# GNU and a LITERAL PLUS here — so the cases below use patterns valid in BOTH,
# and the dialect divergence is asserted separately as a named refusal rather
# than pretended away. See ADR 0005.
#
# ⭐ The pattern matches the WHOLE PATH AS WRITTEN, anchored both ends: `find .`
# yields `./aab.c` with the leading `./` included, so `-regex 'aab'` finds
# nothing. That is GNU's behaviour, verified.
mkdir -p rx/sub
: > rx/aab.c; : > rx/sub/x.c

rx_same() {
    label=$1; shift
    g=$(cd rx && find "$@" 2>&1 | sort); k=$(cd rx && "$BIN" find "$@" 2>&1 | sort)
    expect_eq "regex: $label" "$g" "$k"
}
rx_same "whole path"              . -regex '.*aab.*'
rx_same "substring does not match" . -regex 'aab'
rx_same "anchored literal"        . -regex '\./aab\.c'
rx_same "leading ./ is part of it" . -regex 'aab\.c'
rx_same "-iregex folds"           . -iregex '.*AAB.*'
rx_same "posix-basic explicit"    . -regextype posix-basic -regex '.*aab.*'
rx_same "posix-extended"          . -regextype posix-extended -regex '.*aab.*'
rx_same "ERE + quantifier"        . -regextype posix-extended -regex '\./a+b\.c'
rx_same "combined with -type"     . -regex '.*\.c' -type f
rx_same "negated"                 . -type f ! -regex '.*aab.*'

# ⛔ `-iregex` WITH A BRACKET EXPRESSION — the 1.4.5 bug. `-iregex` folds the
# SUBJECT to lower case, and the pattern was folded alongside it. That is right
# for literal bytes and wrong for a bracket expression, which is a SET rather
# than a byte: lower-casing the text `[[:upper:]]` leaves it unchanged, so
# against a lower-cased subject it matched NOTHING where GNU matches every
# path. ⚠ `grep -i` had the identical bug; the fix is shared in
# `src/lib/icase.cyr` precisely so the two cannot drift apart again.
: > rx/MiXeD.c

# ⛔ `-regextype posix-basic` IS PINNED ON EVERY CASE BELOW, and it is not
# decoration. GNU's DEFAULT dialect is `findutils-default` (emacs-flavoured) and
# its support for POSIX character classes changed between the two findutils
# releases kriya must satisfy:
#
#   findutils 4.9.0 (ubuntu-24.04, what CI runs):
#       find . -regex '.*[[:alpha:]].*'                       -> nothing
#       find . -regextype posix-basic -regex '.*[[:alpha:]].*' -> every path
#   findutils 4.11.0 (this box): both forms match every path.
#
# ⚠ So the class is not implemented at all in 4.9's default dialect — with or
# without `-i`, which is what proves this is a DIALECT gap and not a
# case-folding difference. An earlier version of this block compared kriya's
# default (POSIX BRE, per ADR 0005) against GNU's default (emacs) and passed
# here while failing on CI. ⭐ Pinning costs no kriya coverage: kriya's default
# IS posix-basic, so `-regextype posix-basic` exercises the identical path.
RXB="-regextype posix-basic"
rx_same "-iregex [[:upper:]]"     . $RXB -iregex '.*[[:upper:]].*'
rx_same "-iregex [[:lower:]]"     . $RXB -iregex '.*[[:lower:]].*'
rx_same "-iregex range lower"     . $RXB -iregex '.*[a-c].*'
rx_same "-iregex range upper"     . $RXB -iregex '.*[A-C].*'
rx_same "-iregex negated class"   . $RXB -iregex '.*[^[:upper:]].*'
rx_same "-iregex ERE class"       . -regextype posix-extended -iregex '.*[[:upper:]].*'
# ⚠ The control: plain `-regex` must be unaffected, or a bug there would hide
# behind the `-iregex` assertions above.
rx_same "-regex [[:upper:]] control" . $RXB -regex '.*[[:upper:]].*'

# ⛔ REGRESSION GUARD — GNU `find` IS NOT GNU `grep`, and 1.4.5 briefly assumed
# it was. `find -iregex` goes through glibc `regcomp` with `RE_ICASE`; `grep`
# uses its own bundled matcher; the two implement DIFFERENT range rules, so
# sharing one rewriter without a mode bit silently broke four mixed-case cases
# that had agreed with GNU since the predicate shipped:
#
#   grep -i '[b-B]'           matches NOTHING
#   find  -iregex '.*[b-B].*' matches `b` AND `B`
#   grep -i '[Z-a]'           is an ERROR, exit 2
#   find  -iregex '.*[Z-a].*' is silently empty, exit 0 — find has NO error
#                             path for a bracket expression at all
#
# glibc's rule, verified exact over all 7,744 printable-endpoint ranges: a byte
# `c` is in `[x-y]` iff `toupper(x) <= toupper(c) <= toupper(y)`. ⚠ None of
# these cases involves a character class, so the class assertions above cannot
# catch a regression here — they need their own block.
: > rx/bB.c
rx_same "-iregex [b-B] mixed range"  . $RXB -iregex '.*[b-B].*'
rx_same "-iregex [a-B] mixed range"  . $RXB -iregex '.*[a-B].*'
rx_same "-iregex [A-c] mixed range"  . $RXB -iregex '.*[A-c].*'
rx_same "-iregex [B-{] translation"  . $RXB -iregex '.*[B-{].*'

# ⚠ Compared by EXIT CLASS, not by output: both refuse these, but the wording
# differs ("find: failed to compile ..." vs "kriya find: -iregex has an invalid
# range end") and the message is not the thing under test.
# ⛔ These two are the cases that separate the DIALECTS: under `posix-basic`
# GNU refuses them, and under its emacs default GNU accepts them and matches
# nothing. kriya's default dialect is POSIX BRE, so posix-basic is the honest
# comparison — measuring against the emacs default is what made an earlier
# reading of this call it a regression.
# ⚠ Compared as REFUSED-or-NOT, never as a raw exit code. GNU `find` uses 1 for
# a fatal error and kriya uses 2 for a usage error (ADR 0008), a deliberate
# pre-existing divergence — and `find` returns 0 when it simply matches nothing,
# so any non-zero status here IS the refusal.
rx_rc() {
    label=$1; shift
    grc=0; (cd rx && find "$@") >/dev/null 2>&1 || grc=$?
    krc=0; (cd rx && "$BIN" find "$@") >/dev/null 2>&1 || krc=$?
    [ "$grc" -ne 0 ] && grc=refused || grc=ok
    [ "$krc" -ne 0 ] && krc=refused || krc=ok
    expect_eq "regex: $label" "$grc" "$krc"
}
rx_rc "-iregex [Z-a] refused" . $RXB -iregex '.*[Z-a].*'
rx_rc "-iregex [W-b] refused" . $RXB -iregex '.*[W-b].*'
rx_rc "-iregex [b-B] accepted" . $RXB -iregex '.*[b-B].*'
rx_same "no match at all"         . -regex '.*zzz.*'

# ⛔ `-regextype emacs` is REFUSED BY NAME. GNU's default and its emacs type
# read `a+` as one-or-more; kriya's engines are POSIX (ADR 0005), where an
# unescaped `+` is a literal. Silently aliasing emacs to BRE would return
# different files with no diagnostic.
rc=0; "$BIN" find rx -regextype emacs -regex 'x' >/dev/null 2>&1 || rc=$?
expect_eq "regex: -regextype emacs refused" "2" "$rc"
err=$("$BIN" find rx -regextype emacs -regex 'x' 2>&1 >/dev/null || true)
case "$err" in
    *"posix-basic"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL regex: refusal does not name what IS supported: %s\n" "$err" >&2 ;;
esac
rc=0; "$BIN" find rx -regex >/dev/null 2>&1 || rc=$?
expect_eq "regex: missing argument is a usage error" "2" "$rc"

# --- -user / -group / -uid / -gid / -nouser / -nogroup (1.5.0) ----------
#
# ⛔ Runtime comparisons against GNU, never literals: the test user's name and
# uid differ between this box and CI. ⚠ `rx_same` already compares kriya's and
# GNU's output for the same argv, which is exactly the shape needed.
mkdir -p ownerdir && : > ownerdir/f1 && : > ownerdir/f2
ME_U=$(id -un); ME_G=$(id -gn); ME_UI=$(id -u); ME_GI=$(id -g)
own_same() {
    label=$1; shift
    g=$(cd ownerdir && find "$@" 2>&1 | sort)
    k=$(cd ownerdir && "$BIN" find "$@" 2>&1 | sort)
    expect_eq "owner: $label" "$g" "$k"
}
own_same "-user NAME"        . -user "$ME_U"
own_same "-group NAME"       . -group "$ME_G"
own_same "-uid N"            . -uid "$ME_UI"
own_same "-gid N"            . -gid "$ME_GI"
# ⚠ `-user` accepts a NUMBER too, and resolves it as a NAME first when both
# readings are possible — with a user literally named `4242` at uid 7777,
# `find -user 4242` matches the uid-7777 files. That fixture needs privileges,
# so the container run covers it; this only pins the numeric fallback.
own_same "-user accepts a UID"  . -user "$ME_UI"
own_same "-group accepts a GID" . -group "$ME_GI"
own_same "-nouser"           . -nouser
own_same "-nogroup"          . -nogroup
own_same "-user with -type"  . -user "$ME_U" -type f
own_same "negated -user"     . ! -user "$ME_U"

# ⚠ Refusal compared as refused-or-not: GNU exits 1 and kriya exits 2 for a
# usage error (ADR 0008), a deliberate pre-existing divergence.
for badarg in nosuchuser___x; do
    grc=0; (cd ownerdir && find . -user "$badarg") >/dev/null 2>&1 || grc=$?
    krc=0; (cd ownerdir && "$BIN" find . -user "$badarg") >/dev/null 2>&1 || krc=$?
    [ "$grc" -ne 0 ] && grc=refused || grc=ok
    [ "$krc" -ne 0 ] && krc=refused || krc=ok
    expect_eq "owner: -user $badarg refused" "$grc" "$krc"
done
rc=0; (cd ownerdir && "$BIN" find . -user) >/dev/null 2>&1 || rc=$?
expect_eq "owner: -user with no argument is a usage error" "2" "$rc"

# --- 1.6.16: no number wraps, and -size counts in its unit -------------------
#
# ⛔ `-maxdepth`, `-mindepth`, `-uid`, `-gid`, `-mmin`, `-mtime` and `-size` all
# WRAPPED past 2^64 — `-mmin -18446744073709551617` asked for "under a minute".
# ⛔ And `-size` compared BYTES for `k`, `M` and `G`, so `-size -1M` matched every
# file under a megabyte. GNU rounds the file's size up to the unit: `-size -1M` is
# only the empty files, and `-size 1k` includes a one-byte file.
mkdir -p d16s d16d/a/b
# ⚠ OLD mtimes, or the time cases cannot tell a huge `-mmin -N` from the
# wrapped "under one minute": a file made a moment ago is under a minute old.
touch -t 202001010000 d16d d16d/a d16d/a/b
: > d16s/s0
head -c 1 /dev/zero > d16s/s1
head -c 1024 /dev/zero > d16s/s1024
head -c 1025 /dev/zero > d16s/s1025
head -c 2048 /dev/zero > d16s/s2048
head -c 1048577 /dev/zero > d16s/s1m1
for _a in "-size -1M" "-size 1M" "-size +1M" "-size -1k" "-size 1k" "-size 2k" "-size -2k" \
          "-size 1" "-size 2" "-size -3" "-size 1025c" "-size +1024c" "-size -1G" "-size 1G" \
          "-size 0" "-size +0" "-size 0c" "-size -1"; do
    # shellcheck disable=SC2086
    compare_sorted "find $_a" "d16s -type f $_a"
done
for _a in "-mmin -18446744073709551617" "-mmin +18446744073709551617" "-mtime -99999999999999999999" \
          "-mtime +9223372036854775808" "-maxdepth 2147483647" "-mindepth 2147483647" "-maxdepth 1"; do
    # shellcheck disable=SC2086
    compare_sorted "find $_a" "d16d $_a"
done
for _a in "-maxdepth 2147483648" "-mindepth 2147483648" "-maxdepth 18446744073709551617" \
          "-mindepth 18446744073709551617" "-uid 18446744073709551617" "-gid 18446744073709551617" \
          "-user 4294967296" "-group 4294967296" "-user 18446744073709551617" \
          "-size -18446744073709551617c" "-size 99999999999999999999k"; do
    # shellcheck disable=SC2086
    expect_exit "find $_a refused" 2 "$BIN" find d16d $_a
    _grc=0
    # shellcheck disable=SC2086
    find d16d $_a >/dev/null 2>&1 || _grc=$?
    expect_eq "...and by GNU" "yes" "$([ "$_grc" != 0 ] && echo yes || echo no)"
done

# --- 1.7.0: -exec … {} + ---------------------------------------------------
#
# ⭐ ONE COMMAND PER BATCH, counted as GNU's `buildcmd` counts: strlen + 1 per
# argument, the command's own words included, up to 131,072 bytes. It was
# refused ("missing ';'") until 1.7.0. `xp_same` compares the SORTED output and
# the exit status: the order of paths inside a batch is the walk's.
xp_same() {
    _n=$1; shift
    _k=0; timeout 60 "$BIN" find "$@" 2>/dev/null | sort > xp_k.out || true
    timeout 60 "$BIN" find "$@" >/dev/null 2>&1 || _k=$?
    _g=0; find "$@" 2>/dev/null | sort > xp_g.out || true
    find "$@" >/dev/null 2>&1 || _g=$?
    if cmp -s xp_k.out xp_g.out && [ "$_k" = "$_g" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s: GNU exit %s, kriya exit %s, output %s\n' "$_n" "$_g" "$_k" \
            "$(cmp -s xp_k.out xp_g.out && echo same || echo differs)" >&2
    fi
}
mkdir -p x17/sub && touch x17/a x17/b x17/sub/c
xp_same "-exec echo {} +"              x17 -exec echo {} +
xp_same "initial arguments"            x17 -exec echo X {} +
xp_same "with a test before it"        x17 -name a -exec echo {} +
xp_same "nothing matches: no command"  x17 -name zzz -exec echo {} +
xp_same "{} + then another test"       x17 -exec echo {} + -name a
xp_same "two batches"                  x17 -exec echo A {} + -exec echo B {} +
xp_same "; and + together"             x17 -exec echo {} ';' -exec echo {} +
xp_same "{} + -o -print"               x17 -exec echo {} + -o -print
# The predicate is TRUE whatever the command does; its failure is the exit status.
xp_same "a failing command, exit 1"    x17 -exec false {} +
xp_same "...and -print still prints"   x17 -exec false {} + -print
xp_same "exit 3 is a failure"          x17 -exec sh -c 'exit 3' sh {} +
xp_same "killed by a signal"           x17 -exec sh -c 'kill -9 $$' sh {} +
xp_same "not found"                    x17 -exec nosuch-cmd-1-7-0 {} +
xp_same "no command word: {} runs"     x17 -exec {} +
# ⚠ `+` ends the command ONLY straight after a bare `{}` (GNU 4.10's rule);
# otherwise it is an argument and a `;` is still owed.
xp_same "a + that is data"             x17 -name a -exec echo + ';'
for _a in "-exec echo {} Y +" "-exec echo {}x +" "-exec echo x{} +" "-exec echo +" \
          "-exec +" "-exec echo {} {} +" "-exec sh -c 'echo {}' sh {} +"; do
    # shellcheck disable=SC2086
    eval "expect_exit \"find $_a refused\" 2 \"$BIN\" find x17 $_a"
    _grc=0
    eval "find x17 $_a" >/dev/null 2>&1 || _grc=$?
    expect_eq "...and by GNU" "yes" "$([ "$_grc" != 0 ] && echo yes || echo no)"
done
# Order: a batch runs when it fills, and whatever is left after the walk, in
# expression order — after `-print`'s lines.
expect_eq "batches after -print" "$(find x17 -exec echo {} + -print | tail -1 | wc -w)" \
    "$("$BIN" find x17 -exec echo {} + -print | tail -1 | wc -w)"
expect_eq "A before B" "$(find x17 -exec echo A {} + -exec echo B {} + | cut -c1)" \
    "$("$BIN" find x17 -exec echo A {} + -exec echo B {} + | cut -c1)"
# ⭐ THE BATCH SIZES ARE GNU's: 25,000 same-length paths, in a pinned environment
# (the environment is part of the ceiling).
mkdir -p x17b && (cd x17b && seq -f 'f%08g' 1 25000 | xargs touch)
for _v0 in sh sh-with-a-long-argv0-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx; do
    expect_eq "batch sizes, argv0 $_v0" \
        "$(env -i PATH=/usr/bin:/bin find x17b -type f -exec sh -c 'echo $#' $_v0 {} + | tr '\n' ' ')" \
        "$(env -i PATH=/usr/bin:/bin "$BIN" find x17b -type f -exec sh -c 'echo $#' $_v0 {} + | tr '\n' ' ')"
done
expect_eq "two -exec + batches interleave" \
    "$(env -i PATH=/usr/bin:/bin find x17b -type f -exec sh -c 'echo A$#' sh {} + -exec sh -c 'echo B$#' sh {} + | tr '\n' ' ')" \
    "$(env -i PATH=/usr/bin:/bin "$BIN" find x17b -type f -exec sh -c 'echo A$#' sh {} + -exec sh -c 'echo B$#' sh {} + | tr '\n' ' ')"
# Every path arrives, once.
expect_eq "25,000 paths, each once" "25000" \
    "$("$BIN" find x17b -type f -exec sh -c 'for f; do echo "$f"; done' sh {} + | sort -u | wc -l)"

# --- 1.7.1: -prune, -depth, -perm, -H, `,`, -uid/-gid ±N, -size Nw -------------
#
# Every case runs the SAME argv through GNU and kriya. `f17_same` compares stdout
# BYTES UNSORTED and the exit status — ⛔ order is the point of -depth, and both
# walks visit entries in readdir order, so an unsorted comparison is sound here.
# `f17_err` adds the number of stderr lines: the wording differs (architecture
# 001), the count must not. `f17_refused`: GNU exits 1 on a bad argument, kriya 2
# (ADR 0008), and neither prints anything.
f17_same() {
    _n=$1; shift
    _g=0; find "$@" > f17_g.out 2>/dev/null </dev/null || _g=$?
    _k=0; timeout 30 "$BIN" find "$@" > f17_k.out 2>/dev/null </dev/null || _k=$?
    if cmp -s f17_g.out f17_k.out && [ "$_g" = "$_k" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s: GNU exit %s, kriya exit %s, stdout %s\n' "$_n" "$_g" "$_k" \
            "$(cmp -s f17_g.out f17_k.out && echo same || echo differs)" >&2
    fi
}
f17_err() {
    _n=$1; shift
    f17_same "$_n" "$@"
    _ge=$(find "$@" 2>&1 >/dev/null </dev/null | wc -l || true)
    _ke=$(timeout 30 "$BIN" find "$@" 2>&1 >/dev/null </dev/null | wc -l || true)
    expect_eq "$_n (stderr lines)" "$_ge" "$_ke"
}
f17_refused() {
    _n=$1; shift
    _k=0; _ko=$(timeout 30 "$BIN" find "$@" 2>/dev/null </dev/null) || _k=$?
    _g=0; _go=$(find "$@" 2>/dev/null </dev/null) || _g=$?
    expect_eq "$_n: kriya refuses, exit 2, prints nothing" "2|" "$_k|$_ko"
    expect_eq "$_n: ...and GNU refuses" "yes|" "$([ "$_g" != 0 ] && echo yes || echo no)|$_go"
}

mkdir -p p17/a/b p17/c p17/skip/deep
for _m in 644 755 600 4755 2755 1777 000 666 640 711 6750 700; do
    : > "p17/f$_m"; chmod "$_m" "p17/f$_m"
done
: > p17/a/x; : > p17/a/b/y; : > p17/skip/deep/z; : > p17/c/w
chmod 755 p17/a; chmod 700 p17/c; chmod 1777 p17/skip
printf 'abc' > p17/s3; printf 'abcd' > p17/s4; printf 'abcde' > p17/s5; printf 'a' > p17/s1
ln -s a p17/la; ln -s nowhere p17/ldang; ln -s f644 p17/lf
ln -s p17 p17l; ln -s p17/a p17la

# ⭐ -prune: true, and a directory it matches is not entered. The implicit
# -print still applies (GNU: "no actions other than -prune or -print").
f17_same "-prune: the classic exclusion"      p17 -name a -prune -o -print
f17_same "-prune: implicit -print"            p17 -name a -prune
f17_same "-prune on a file is only true"      p17 -name f644 -prune
f17_same "-prune on the starting point"       p17 -prune -o -print
f17_same "-prune -print"                      p17 -maxdepth 2 -name skip -prune -print
f17_same "-prune in a group"                  p17 '(' -name a -o -name c ')' -prune -o -type f -print
f17_same "-prune under -L, on a followed link" -L p17 -name la -prune -o -print
# ⛔ The prune flag outlived its entry: cleared only on the way into the
# expression, it was still set when the NEXT starting point, above -mindepth,
# came to be entered — so `b` was never walked, at exit 0.
mkdir -p p17m/a/x p17m/b/y
f17_same "-prune does not reach the next starting point" p17m/a p17m/b -mindepth 1 -name x -prune -o -print
f17_same "...nor a sibling directory above -mindepth"   p17m -mindepth 2 -name x -prune -o -print
# ⛔ POSIX: "If the -depth primary is specified, the -prune primary shall have no
# effect." Everything under p17/a is listed; p17/a itself is what -o skips.
f17_same "-prune is inert under -depth"       p17 -depth -name a -prune -o -print

# ⭐ -depth / -d: a directory after its entries, in the walk's own order.
f17_same "-depth post-order"                  p17 -depth
f17_same "-d is -depth"                       p17 -d
f17_same "-depth with -maxdepth 1"            p17 -maxdepth 1 -depth
f17_same "-depth with -mindepth"              p17 -mindepth 2 -depth
f17_same "-depth after a test (global)"       p17 -name a -depth
f17_same "-depth is true where it stands"     p17 -depth -o -print
f17_same "-depth -type d"                     p17 -depth -type d

# ⛔ -mindepth and -maxdepth are GLOBAL. -mindepth was a test evaluated where it
# stood, so `-print -mindepth 2` printed every entry and `-mindepth 2 -o -print`
# the shallow ones, both at exit 0; -maxdepth was first-wins, GNU's is last.
f17_same "-mindepth is global"                p17 -print -mindepth 2
f17_same "-mindepth -o -print"                p17 -mindepth 2 -o -print
f17_same "-mindepth hides a -prune above it"  p17 -mindepth 2 -name a -prune -o -print
f17_same "-maxdepth: the last wins"           p17 -maxdepth 2 -maxdepth 1
f17_same "-maxdepth: the last wins, reversed" p17 -maxdepth 1 -maxdepth 2
f17_same "-mindepth: the last wins"           p17 -mindepth 1 -mindepth 3

# ⭐ -perm: exact, -all-of, /any-of, octal and symbolic (`src/lib/mode.cyr`, a
# port of gnulib's modechange.c). `scripts/difffuzz-find-perm.py` covers every
# mode; these pin the forms people write.
for _p in 644 0644 00644 -644 /111 -4000 /6000 -2000 /u+s,g+s -u=rw u=rw,go=r /o+w -o+w \
          +w a+x -g+s -+t /+t /u=X -a=X -u=x,g=u =644 -ug+w -o= -u+w-x 0 000 -000 /000 /u= \
          -+222 /+222 u=rwx,g=rx,o=rx u=rwxs,g=rxs -a+st -o+s 7777 6750; do
    f17_same "-perm $_p" p17 -maxdepth 1 -perm "$_p"
done
f17_same "-perm on directories: X"            p17 -type d -perm -u=X
f17_same "-perm on symlinks (-P: 0777)"       p17 -maxdepth 1 -type l -perm 777
f17_same "-perm on followed links (-L)"       -L p17 -maxdepth 1 -name 'l*' -perm 644
# ⛔ `+` before an octal digit was GNU's old "any of", removed in 2005 because
# `chmod` reads it as "add": refused rather than guessed.
for _p in +222 +0 10000 8 u+z '' - / u ,u+w u+w, u+w,,g+w u=644 644,u+s =644+w; do
    f17_refused "-perm '$_p'" p17 -perm "$_p"
done
f17_refused "-perm with no argument" p17 -perm

# ⭐ -H: a starting point that is a symlink is followed, nothing below it is.
f17_same "-H follows the starting point"      -H p17l
f17_same "-H: the start is a directory"       -H p17l -maxdepth 0 -type d
f17_same "-H: the start is not a link"        -H p17l -maxdepth 0 -type l
f17_same "-H: links below are not followed"   -H p17 -name 'l*' -type l
f17_same "-H: a link below is not entered"    -H p17l -name la -type d
f17_same "-H: a dangling start is the link"   -H p17/ldang -type l
f17_same "-H: a start link to a file"         -H p17/lf -type f
f17_same "-H -empty follows the start"        -H p17la -empty
f17_same "-H -prune on the start"             -H p17l -prune
f17_same "-H then -P: the last wins"          -H -P p17l
f17_same "-P then -H: the last wins"          -P -H p17l
f17_same "-L then -H: the last wins"          -L -H p17l -name la -type d
f17_same "-H then -L: the last wins"          -H -L p17l -name la -type d
f17_refused "-H after a starting point is a test GNU does not have" p17 -H
f17_refused "-HL is not a cluster"            -HL p17

# ⛔ -newer's reference is FOLLOWED under -H and -L, as a starting point is; it
# was always lstat'ed. And it compares NANOSECONDS: whole seconds missed
# everything written in the reference's own second.
mkdir -p n17
touch -d '2020-01-01 00:00:00' n17/old
touch -d '2023-01-01 00:00:00' n17/mid
ln -s old n17/lnew; touch -h -d '2025-01-01 00:00:00' n17/lnew
for _o in -P -H -L; do
    f17_same "-newer a link under $_o" "$_o" n17 -newer n17/lnew
done
touch -d '2024-05-05 05:05:05.100000000' n17/ns1
touch -d '2024-05-05 05:05:05.600000000' n17/ns2
f17_same "-newer within one second"           n17 -newer n17/ns1
f17_same "-newer within one second, reversed" n17 -newer n17/ns2

# ⭐ GNU's `,`: both sides always run, the value is the right one's, and it binds
# looser than -o.
f17_same ", keeps the right side's value"     p17 -maxdepth 1 -name 'f6*' , -name 's*'
f17_same ", runs the left side's action"      p17 -maxdepth 1 -name 'f6*' -print , -name 's*'
f17_same ", with actions on both sides"       p17 -maxdepth 1 -name 'f6*' -print , -name 's*' -print
f17_same ", is looser than -o (left)"         p17 -maxdepth 1 -name 'f6*' -o -name s3 , -name 's*'
f17_same ", is looser than -o (right)"        p17 -maxdepth 1 -name 'f6*' , -name s3 -o -name 'f7*'
f17_same ", inside parentheses"               p17 -maxdepth 1 '(' -name 'f6*' , -name s3 ')' -print
f17_same ", after a global option"            p17 -maxdepth 1 , -print
f17_same ", with -exec {} + on both sides"    p17 -maxdepth 0 -exec echo A {} + , -exec echo B {} +
f17_same ", with -prune"                      p17 -name a -prune , -name x -print
f17_refused ", with nothing after it"         p17 -maxdepth 1 -print ,
f17_refused ", , with nothing between"        p17 -maxdepth 1 -print , , -print

# ⭐ -uid / -gid take +N and -N, and GNU's number shape.
_u=$(id -u); _gi=$(id -g)
for _a in "$_u" "+$((_u - 1))" "-$((_u + 1))" "+$_u" "-$_u" "++$((_u - 1))" "-+$((_u + 1))" \
          " $_u" "+ $((_u - 1))" -0 +0 18446744073709551615 -18446744073709551615 \
          +18446744073709551615 4294967296 -4294967296 +4294967295; do
    f17_same "-uid '$_a'" p17 -maxdepth 1 -uid "$_a"
done
for _a in "$_gi" "+$((_gi - 1))" "-$((_gi + 1))" "-$_gi" "+$_gi"; do
    f17_same "-gid '$_a'" p17 -maxdepth 1 -gid "$_a"
done
for _a in +-1 --1 18446744073709551616 -18446744073709551616 0x10 '' + 12a; do
    f17_refused "-uid '$_a'" p17 -uid "$_a"
    f17_refused "-gid '$_a'" p17 -gid "$_a"
done

# ⭐ -size Nw — two-byte words — and GNU's number shape for -size.
for _a in 0w 1w 2w 3w -2w +1w -3w +2w "++1c" " 3c" "-+4c" "+ 2c" 18446744073709551615c \
          -18446744073709551615c; do
    f17_same "-size '$_a'" p17 -maxdepth 1 -type f -size "$_a"
done
for _a in w 2ww 2W 2x +c -c '' 18446744073709551616c; do
    f17_refused "-size '$_a'" p17 -size "$_a"
done

# ⛔ -L: a directory the walk is already inside is a LOOP — reported, not
# entered, exit 1. It went forty levels deep, listing the tree forty times —
# and on THIS fixture, where `self` and two `up`s compose, it branches at every
# level: 1.7.0 grew past 25 GB before it was killed. ⚠ Every call has `timeout`.
mkdir -p l17/a/b && ln -s .. l17/a/up && ln -s . l17/self && ln -s ../.. l17/a/b/up
f17_err "-L names a loop and does not enter it" -L l17
f17_err "-L loop under -depth"                  -L l17 -depth
f17_err "-L loop with -prune"                   -L l17 -name up -prune -o -print
f17_err "-P never follows, so never loops"      l17
expect_eq "-L loop: no path goes round" "0" \
    "$(timeout 30 "$BIN" find -L l17 2>/dev/null | grep -c 'up/' || true)"

# ⛔ A link through a non-directory (ENOTDIR): reported, exit 1, and below a
# starting point still listed as the link — GNU's `fallback_stat`. At a starting
# point it is not listed.
ln -s f644/x p17/lnotdir
f17_err "-L: a link through a file"             -L p17 -name lnotdir
f17_err "-L: ...is the link itself"             -L p17 -name lnotdir -type l
f17_err "-H: as a starting point"               -H p17/lnotdir
rm -f p17/lnotdir

# ⭐ An unreadable directory: its error, and under -depth still the directory
# itself, after its error — GNU's FTS_DNR handling.
mkdir -p u17/ok u17/no/in && : > u17/ok/g && : > u17/no/in/f && chmod 000 u17/no
f17_err "an unreadable directory"               u17
f17_err "an unreadable directory under -depth"  u17 -depth
f17_err "...and -depth -name"                   u17 -depth -name no
f17_same "...pruned, it is never opened"        u17 -name no -prune -o -print
chmod 755 u17/no

# --- 1.7.1: what the adversarial review found ---------------------------------
#
# ⛔ An entry below a starting point that cannot be stat'd is still EVALUATED, as
# GNU does: reported once, exit 1, its name tested, and a test that needs its
# metadata false. -L used to skip a link into an unsearchable directory.
mkdir -p r17/t r17/locked/in && : > r17/locked/in/z
ln -s ../locked/in r17/t/lin && ln -s ../locked/in/z r17/t/linz && chmod 000 r17/locked
f17_err "-L: an unsearchable target is still listed"   -L r17/t
f17_err "-L: ...and its name tested"                   -L r17/t -name 'lin*'
f17_err "-L: ...but not a test that needs its stat"    -L r17/t -type l
f17_err "-L: ...either side of -o"                     -L r17/t -name 'lin*' -o -type l
f17_err "-L: ...-size, -perm, -newer, -empty"          -L r17/t -size -1 -o -perm -000 -o -empty
f17_err "-H: an unsearchable starting point is not"    -H r17/t/lin
chmod 755 r17/locked
# ⚠ A readable directory that cannot be searched (chmod 600): the listing is
# GNU's; the ERRORS are not — GNU stats only what a test needs (`d_type`), so it
# reports the subdirectory alone where kriya reports every entry (roadmap 1.9.6).
mkdir -p r17/dnx/in && : > r17/dnx/q && chmod 600 r17/dnx
f17_same "an unsearchable directory's entries are listed" r17/dnx
chmod 755 r17/dnx

# ⛔ -empty reports a directory it cannot open, and the exit is 1. It was
# silently "not empty" at exit 0.
mkdir -p r17/e/d000 r17/e/d300 r17/e/ok && chmod 000 r17/e/d000 && chmod 300 r17/e/d300
f17_err "-empty on directories it cannot open"         r17/e -maxdepth 1 -empty
f17_err "...as starting points"                        r17/e/d000 r17/e/d300 r17/e/ok -maxdepth 0 -empty
chmod 755 r17/e/d000 r17/e/d300

# ⛔ -name sees a starting point without its trailing slashes, as GNU's
# base_name does: `find dir/ -name dir -prune` listed the tree it was told to prune.
mkdir -p r17/s/sub && ln -s s r17/sl
f17_same "-name on 'dir/'"                             r17/s/ -maxdepth 0 -name s
f17_same "-name on 'dir//'"                            r17/s// -maxdepth 0 -name s
f17_same "-name on './'"                               ./ -maxdepth 0 -name .
f17_same "-name on '//'"                               // -maxdepth 0 -name /
f17_same "-prune on 'link/'"                           r17/sl/ -name sl -prune -o -print
f17_same "-regex still sees the path as written"       r17/s/ -maxdepth 0 -regex '.*/s/'

# ⛔ -regextype is an option, true where it stands, and each -regex keeps the
# dialect it was compiled in: a second -regextype ran an ERE through the BRE
# engine, and `-regextype X -not …` and a trailing -regextype were usage errors.
f17_same "a later -regextype leaves an earlier -regex"  r17/s -maxdepth 1 -regextype posix-extended -regex '.*/(sub|x)' -regextype posix-basic -name '*'
f17_same "-regextype before -not"                       r17/s -maxdepth 1 -regextype posix-extended -not -regex '.*/sub'
f17_same "a trailing -regextype"                        r17/s -maxdepth 0 -regextype posix-extended
f17_same "-regextype is true where it stands"           r17/s -maxdepth 1 -regextype posix-extended -o -print

# ⛔ Starting points GNU takes that kriya refused: `--` ends -H/-L/-P, and a bare
# `-` or a leading `)` is a file.
( cd r17 && : > ./- && mkdir -p ')' )
f17_same "-- ends the options"                          -- r17/s -maxdepth 0
f17_same "-L -- ..."                                    -L -- r17/sl -maxdepth 0
( cd r17 && f17_same "'-' is a file"                    - -maxdepth 0 )
( cd r17 && f17_same "')' is a starting point"          ')' -maxdepth 0 )
( cd r17 && f17_same "...among others"                  s ')' -maxdepth 0 )

# ⛔ Deep expressions died of SIGSEGV. A chain of any length is walked in a loop;
# parentheses nest to half the stack, and deeper is a usage error — never a
# signal. The chain is built in a file (a shell variable of 50,000 words is slow)
# and compared with GNU at 2,000 terms; at 50,000 — past where 1.7.0 crashed —
# kriya's answer is asserted directly, because GNU takes 33 s over it.
for _n in 2000 50000; do
    awk -v n="$_n" 'BEGIN { print "r17/s"; print "-maxdepth"; print "0"; print "-name"; print "x0";
        for (i = 1; i < n; i++) { print "-o"; print "-name"; print "x" i } print "-o"; print "-print" }' \
        > r17/chain.args
    _k=0; _ko=$(tr '\n' '\0' < r17/chain.args | timeout 60 xargs -0 -x -s 2000000 "$BIN" find 2>/dev/null) || _k=$?
    if [ "$_n" = 2000 ]; then
        _g=0; _go=$(tr '\n' '\0' < r17/chain.args | timeout 60 xargs -0 -x -s 2000000 find 2>/dev/null) || _g=$?
        expect_eq "a $_n-term -o chain, against GNU" "$_g|$_go" "$_k|$_ko"
    else
        expect_eq "a $_n-term -o chain runs (it died of SIGSEGV)" "0|r17/s" "$_k|$_ko"
    fi
done
_p=""; _q=""; _i=0
while [ "$_i" -lt 1000 ]; do _p="$_p ("; _q="$_q )"; _i=$((_i + 1)); done
# shellcheck disable=SC2086
f17_same "1,000 nested parentheses"                     r17/s -maxdepth 0 $_p -print $_q
_i=0
while [ "$_i" -lt 5000 ]; do _p="$_p ( ( ( ("; _q="$_q ) ) ) )"; _i=$((_i + 1)); done
_k=0
# shellcheck disable=SC2086
timeout 60 "$BIN" find r17/s -maxdepth 0 $_p -print $_q >/dev/null 2>&1 || _k=$?
expect_eq "21,000 nested parentheses: refused, not a signal" "2" "$_k"
_n=""; _i=0
while [ "$_i" -lt 5001 ]; do _n="$_n !"; _i=$((_i + 1)); done
# shellcheck disable=SC2086
f17_same "5,001 negations are one"                     r17/s -maxdepth 0 $_n -name zz

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
