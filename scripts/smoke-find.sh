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

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
