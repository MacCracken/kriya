#!/bin/sh
# smoke-grep.sh — behavioural test for `kriya grep`.
#
# Compares kriya grep against GNU grep cell-by-cell across every
# shipped flag and engine (BRE default, -E ERE, -F fixed). See
# docs/adr/0005-regex-engine-niyama.md for the engine map.

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

# Compare kriya grep against GNU grep on the same args+input.
# `mode` is the engine selector; LC_ALL=C keeps GNU's locale-independent
# behaviour aligned with ours.
compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | LC_ALL=C eval "$BIN grep $args" 2>&1 || true)
    gnu=$(printf  '%s' "$input" | LC_ALL=C eval "grep $args"      2>&1 || true)
    expect_eq "$name" "$gnu" "$mine"
}

# --- fixtures ---
printf 'foo\nbar\nFOO BAR\nfoo bar baz\nbaz\nthe foo of bar\n' > basic
printf 'apple\nbanana\ncherry\nApple\nBanana\n'                > fruit
printf 'line1\nline2\nline3\nline4\nline5\n'                   > lines
printf 'aaa\naaaa\naaab\nbaaa\nb\n'                            > a_seq
printf 'foo123\nfoo\n123foo\nfoo bar\n'                        > mixed
printf 'a-b-c\nx-y-z\na b c\n'                                 > dashed
printf ''                                                       > empty
printf 'one line no newline'                                    > nonewline

# Files for multi-file mode.
printf 'red\nblue\ngreen\n' > colors_a
printf 'red\nyellow\n'      > colors_b

# --- BRE default — basic match ---
compare 'BRE literal'              "$(cat basic)"   "foo basic"
compare 'BRE no match'             "$(cat basic)"   "xyz basic"
compare 'BRE anchored ^'           "$(cat basic)"   "'^foo' basic"
compare 'BRE anchored $'           "$(cat basic)"   "'bar$' basic"
compare 'BRE bracket class'        "$(cat basic)"   "'[Ff]oo' basic"
compare 'BRE star'                 "$(cat a_seq)"   "'a*b' a_seq"
compare 'BRE escaped group'        "$(cat basic)"   "'\\(foo\\)' basic"
compare 'BRE dot'                  "$(cat basic)"   "'f.o' basic"

# --- -E (ERE / niyama_re2) ---
compare 'ERE plus'                 "$(cat a_seq)"   "-E 'a+b'"
compare 'ERE bare group'           "$(cat basic)"   "-E '(foo|bar)' basic"
compare 'ERE alternation'          "$(cat fruit)"   "-E 'apple|cherry' fruit"
compare 'ERE quantifier'           "$(cat a_seq)"   "-E 'a{2,3}b' a_seq"

# --- -F (fixed-string) ---
compare 'F literal regex chars'    "$(cat basic)"   "-F 'foo' basic"
compare 'F dot is literal'         "$(cat basic)"   "-F '.' basic"
compare 'F multi-byte string'      "$(cat basic)"   "-F 'foo bar baz' basic"

# --- -i (case-insensitive) ---
compare 'BRE -i'                   "$(cat basic)"   "-i FOO basic"
compare 'ERE -i'                   "$(cat basic)"   "-i -E 'foo' basic"
compare 'F -i'                     "$(cat fruit)"   "-i -F 'APPLE' fruit"
compare '-i mixed case input'      "$(cat fruit)"   "-i banana fruit"

# --- -v invert ---
compare '-v basic'                 "$(cat basic)"   "-v foo basic"
compare '-v no match (all in)'     "$(cat basic)"   "-v xyz basic"

# --- -c count ---
compare '-c basic'                 "$(cat basic)"   "-c foo basic"
compare '-c zero'                  "$(cat basic)"   "-c xyz basic"
compare '-c with -i'               "$(cat basic)"   "-c -i FOO basic"
compare '-c with -v'               "$(cat basic)"   "-c -v foo basic"

# --- -n line numbers ---
compare '-n basic'                 "$(cat basic)"   "-n foo basic"
compare '-n with -v'               "$(cat lines)"   "-n -v line3 lines"

# --- -l / -L files-with/without-matches ---
compare '-l multi-file'            ''               "-l red colors_a colors_b"
compare '-L multi-file'            ''               "-L red colors_a colors_b"
compare '-l no-match'              ''               "-l zzz colors_a colors_b"
compare '-L all-match'             ''               "-L red colors_a"

# --- -w word boundary ---
compare '-w on/off'                "$(cat mixed)"   "-w foo mixed"
compare '-w with embedded'         "$(cat mixed)"   "-w 'foo' mixed"

# --- -x whole-line ---
compare '-x match'                 "$(cat basic)"   "-x foo basic"
compare '-x no'                    "$(cat basic)"   "-x bar basic"

# --- -o only-matching ---
compare '-o single'                "$(cat basic)"   "-o foo basic"
compare '-o with -E plus'          "$(cat a_seq)"   "-o -E 'a+' a_seq"

# --- -h / -H ---
compare '-h multi-file'            ''               "-h foo basic mixed"
compare '-H single-file'           ''               "-H foo basic"

# --- -s suppress fs errors ---
mine=$($BIN grep -s foo /no/such/file 2>&1 || true)
gnu=$(grep -s foo /no/such/file 2>&1 || true)
expect_eq '-s suppress'            "$gnu"           "$mine"

# --- multi-file ---
compare 'multi-file no flags'      ''               "red colors_a colors_b"
compare 'multi-file -n'            ''               "-n red colors_a colors_b"
compare 'multi-file -c'            ''               "-c red colors_a colors_b"

# --- stdin (- operand and piped) ---
compare 'stdin via pipe'           "$(cat basic)"   "foo"
compare 'stdin via dash'           "$(cat basic)"   "foo -"

# --- -e pattern ---
compare '-e basic'                 "$(cat basic)"   "-e foo basic"
compare '-e empty operand'         "$(cat basic)"   "-e '' basic"

# --- -f patterns from file ---
printf 'foo\nbaz\n' > patfile
compare '-f multi-pattern'         "$(cat basic)"   "-f patfile basic"
compare '-f -i'                    "$(cat basic)"   "-f patfile -i basic"

# --- edge cases ---
compare 'empty input'              ""               "foo"
compare 'no trailing newline'      "$(cat nonewline)" "line nonewline"
compare 'empty pattern via -e'     "$(cat basic)"   "-e '' basic"

# --- -z NUL-separated ---
# Use printf since `compare`'s eval-quoting is fine for -z too.
printf 'foo\0bar\0baz\0' > nul_in
mine=$(LC_ALL=C $BIN grep -z foo < nul_in | od -An -tx1 | tr -s ' ' | sed 's/^ //')
gnu=$( LC_ALL=C grep    -z foo < nul_in | od -An -tx1 | tr -s ' ' | sed 's/^ //')
expect_eq '-z NUL output'          "$gnu"           "$mine"

# --- -r recursive ---
mkdir -p tree/sub
printf 'top-foo\n'   > tree/top
printf 'deep-foo\n'  > tree/sub/deep
printf 'no-match\n'  > tree/sub/skip
# Sort to make order independent of dirent iteration order.
mine=$($BIN grep -r foo tree | sort)
gnu=$(grep    -r foo tree | sort)
expect_eq '-r recursive'           "$gnu"           "$mine"

# -r with -l listing.
mine=$($BIN grep -r -l foo tree | sort)
gnu=$(grep    -r -l foo tree | sort)
expect_eq '-r -l listing'          "$gnu"           "$mine"

# --- Exit codes ---
expect_exit 'no match exit 1'      1 "$BIN" grep zzz basic
expect_exit 'match exit 0'         0 "$BIN" grep foo basic
expect_exit '-P rejected'          2 "$BIN" grep -P foo basic
expect_exit '-E and -F clash'      2 "$BIN" grep -E -F foo basic
expect_exit 'no pattern'           2 "$BIN" grep
expect_exit '-r no operand'        2 "$BIN" grep -r foo
expect_exit 'missing file'         2 "$BIN" grep foo no_such_file
expect_exit 'directory no -r'      2 "$BIN" grep foo tree
expect_exit '-q match exit 0'      0 "$BIN" grep -q foo basic
expect_exit '-q no match exit 1'   1 "$BIN" grep -q zzz basic
expect_exit '-s missing file'      1 "$BIN" grep -s foo no_such_file

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
