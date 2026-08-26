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
expect_exit '-H deferred'              2 "$BIN" find -H tree

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

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
