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

# --- every -e, not just the last (v1.2.1) ---
# ⛔ `grep -e alpha -e gamma` matched only `gamma`. The spec has ONE value slot,
# so earlier patterns were overwritten during parsing — no diagnostic, exit 0,
# and a filter that silently dropped half its patterns. grep's matcher was
# always multi-pattern (that is how -f works); only the collection was lossy.
printf 'alpha\nbeta\ngamma\ndelta\n' > multi.txt
for form in "-e alpha -e gamma" "--regexp=alpha --regexp=gamma" "-ealpha -egamma"; do
    expect_eq "multi -e [$form]" "$(grep $form multi.txt | tr '\n' ' ')" "$($BIN grep $form multi.txt | tr '\n' ' ')"
done
expect_eq "multi -e with -i"  "$(grep -i -e ALPHA -e GAMMA multi.txt | tr '\n' ' ')" "$($BIN grep -i -e ALPHA -e GAMMA multi.txt | tr '\n' ' ')"
expect_eq "multi -e with -v"  "$(grep -v -e alpha -e gamma multi.txt | tr '\n' ' ')" "$($BIN grep -v -e alpha -e gamma multi.txt | tr '\n' ' ')"
expect_eq "multi -e with -c"  "$(grep -c -e alpha -e gamma multi.txt)" "$($BIN grep -c -e alpha -e gamma multi.txt)"
expect_eq "single -e unchanged" "$(grep -e alpha multi.txt)" "$($BIN grep -e alpha multi.txt)"

# --- -r descends from a parent fd, not by path (v1.2.3) ----------------
# ⛔ Every level used to re-open the ACCUMULATED PATH with openat(AT_FDCWD, …),
# re-resolving every ancestor component. Swap a directory for a symlink to /etc
# mid-walk and the walk follows it out of the tree, reporting /etc's contents
# under the original path. `O_NOFOLLOW` on the file open was no defence — it
# guards the final component only. `rm`, `cp` and `find` have descended from a
# parent fd since M2 (ADR 0003); grep -r was the last path-based walk.
#
# ⭐ A tree DEEPER THAN PATH_MAX is the deterministic discriminator, and it needs
# no race: a path-based descent physically cannot open a 6 KB path, while an
# fd-relative one only ever sees one short component at a time. Measured on the
# pre-fix binary: "file name too long" at depth 14, nothing found.
deep_built=0
if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import os, sys
root = sys.argv[1]
os.makedirs(root, exist_ok=True); os.chdir(root)
for i in range(500):
    d = "dddddddddd%02d" % (i % 100)
    os.mkdir(d); os.chdir(d)
open("needle.txt","w").write("FOUND-AT-DEPTH\n")
' "$WORK/deep" 2>/dev/null && deep_built=1
fi
if [ "$deep_built" = 1 ]; then
    expect_eq "-r walks past PATH_MAX" \
        "$(cd "$WORK" && grep -r FOUND-AT-DEPTH deep 2>/dev/null | wc -l | tr -d ' ')" \
        "$(cd "$WORK" && "$BIN" grep -r FOUND-AT-DEPTH deep 2>/dev/null | wc -l | tr -d ' ')"
    expect_eq "-r deep exit status" "0" "$(cd "$WORK" && "$BIN" grep -r FOUND-AT-DEPTH deep >/dev/null 2>&1; echo $?)"
    find "$WORK/deep" -delete 2>/dev/null || true
else
    echo "skip: could not build the deep tree — PATH_MAX descent case not exercised"
fi

# A symlinked directory inside the tree is SKIPPED, not descended (ADR 0003).
mkdir -p slt/real/sub slt/other
echo SECRET > slt/real/sub/s
echo DECOY  > slt/other/d
ln -s real slt/aslink
expect_eq "-r skips a symlinked dir" "slt/real/sub/s:SECRET" "$("$BIN" grep -r SECRET slt 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"

# --- a literal pattern skips the NFA (M17h, v1.2.6) --------------------
# ⛔ A plain word compiled to an NFA that retained ~320 bytes per INPUT byte:
# `grep -c "line 000005"` over 13.6 MB SEGFAULTED under `ulimit -v 1048576`
# while GNU answered in constant memory. Routing metacharacter-free patterns to
# the already-present fixed engine is behaviour-preserving — `-F` was always a
# full citizen of the match path.
#
# ⚠ The regression this introduced is the interesting part: `fold_active` was
# keyed off the INVOCATION flag (`-E`/`-F`/`-G`) rather than the engine each
# pattern actually compiled to, so `grep -i -E foo` folded the pattern but not
# the input and silently stopped matching `FOO BAR`. These cases pin both halves.
printf 'foo\nFOO BAR\nfoo bar baz\n' > litfold
for form in "-i -E foo" "-i foo" "-i -F foo" "-E foo" "foo" "-F foo" "-i -E -o foo" "-i -E -c foo"; do
    expect_eq "literal/fold [$form]" \
        "$(grep $form litfold 2>&1 | tr '\n' '|')" "$($BIN grep $form litfold 2>&1 | tr '\n' '|')"
done
# Mixed literal + regex under -i: the literal takes the fixed engine, the regex
# stays on RE2, and folding the input must be safe for both.
expect_eq "mixed -e literal + regex" \
    "$(grep -i -e foo -e 'b.r' litfold | tr '\n' '|')" "$($BIN grep -i -e foo -e 'b.r' litfold | tr '\n' '|')"

# The memory fix itself, bounded so a regression fails rather than hangs.
if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import sys
f = open(sys.argv[1], "w")
for i in range(400000):
    f.write("line %06d abcdefghij klmnopqrst\n" % i)
f.close()' bigmem 2>/dev/null || true
    if [ -f bigmem ]; then
        rc=0
        ( ulimit -v 1048576 2>/dev/null; timeout 120 "$BIN" grep -c 'line 000005' bigmem >/dev/null 2>&1 ) || rc=$?
        expect_eq "M17h: literal scan under a 1GiB cap" "0" "$rc"
        rm -f bigmem
    fi
fi

# --- ⭐ context: -A / -B / -C, compared cell-by-cell against GNU ---------
#
# ⛔ The subtleties, each verified against GNU before being encoded here:
#   * a CONTEXT line's field separator is `-`, a MATCHING line's is `:` — that
#     is the only thing telling a reader which lines in a block actually matched;
#   * `--` goes between NON-CONTIGUOUS groups, and appears between FILES too;
#   * `grep -C 0` still separates while a plain `grep` never does, so the
#     trigger is "the option was supplied", not "the value is nonzero";
#   * overlapping windows MERGE into one block with no separator;
#   * an explicit -A or -B overrides the -C that set both;
#   * -c / -l / -L / -q / -o ignore context rather than erroring.
printf 'a1\na2\nMATCH1\na4\na5\na6\na7\nMATCH2\na9\na10\n' > ctx.txt
cp ctx.txt ctx2.txt
printf 'x\nMATCH\ny\n' > ctxv.txt

ctx_same() {           # ctx_same <label> <args...>  — kriya must equal GNU
    label=$1; shift
    # ⚠ `rc=0; cmd || rc=$?` is load-bearing under `set -e`. A no-match case is
    # EXPECTED to exit 1, and `g=$(grep ...)` takes the substitution's status as
    # the assignment's, so a bare form aborts the whole script mid-suite — which
    # it did, silently, on the first run of this block.
    grc=0
    g=$(grep "$@" 2>&1) || grc=$?
    krc=0
    k=$("$BIN" grep "$@" 2>&1) || krc=$?
    expect_eq "context: $label" "$g" "$k"
    expect_eq "context: $label (exit)" "$grc" "$krc"
}
ctx_same "-A 1"                  -A 1 MATCH ctx.txt
ctx_same "-B 1"                  -B 1 MATCH ctx.txt
ctx_same "-C 1"                  -C 1 MATCH ctx.txt
ctx_same "-C 1 -n separators"    -C 1 -n MATCH ctx.txt
ctx_same "-C 3 windows merge"    -C 3 -n MATCH ctx.txt
ctx_same "-C 0 still separates"  -C 0 -n MATCH ctx.txt
ctx_same "no context, no --"     -n MATCH ctx.txt
ctx_same "-C 5 -A 1 precedence"  -C 5 -A 1 -n MATCH ctx.txt
ctx_same "-A 1 -B 2 independent" -A 1 -B 2 -n MATCH ctx.txt
ctx_same "two files"             -C 1 -n MATCH ctx.txt ctx2.txt
ctx_same "-v context"            -v -C 1 -n MATCH ctxv.txt
ctx_same "-c ignores context"    -c -C 2 MATCH ctx.txt
ctx_same "-l ignores context"    -l -C 2 MATCH ctx.txt
ctx_same "no match at all"       -C 1 -n ZZZ ctx.txt
ctx_same "window clipped at BOF" -C 2 -n a1 ctx.txt
ctx_same "window clipped at EOF" -C 2 -n a10 ctx.txt
ctx_same "-i with context"       -i -C 1 -n match ctx.txt
ctx_same "-w with context"       -w -C 1 -n MATCH1 ctx.txt

# stdin, where there is no filename to prefix
sg=$(grep -C1 -n MATCH < ctxv.txt) || true
sk=$("$BIN" grep -C1 -n MATCH < ctxv.txt) || true
expect_eq "context: stdin" "$sg" "$sk"

# ⚠ A context window larger than the file must not fabricate lines.
ctx_same "-C 999 over-large"     -C 999 -n MATCH1 ctx.txt

# --- ⭐ -Z: NUL after the FILE NAME only ---------------------------------
#
# ⛔ Two different rules, both verified against GNU: with -l the NUL REPLACES
# the line terminator (`f\0f2\0`, no newline at all), while with -c it replaces
# the `:` separator and the trailing newline stays (`f\0 2 \n`). And the line
# number keeps its own `:`/`-`, so `grep -HnZ` is `f\0 3 : line`.
z_same() {
    label=$1; shift
    g=$(grep "$@" 2>&1 | od -An -c) || true
    k=$("$BIN" grep "$@" 2>&1 | od -An -c) || true
    expect_eq "-Z: $label" "$g" "$k"
}
z_same "-lZ"            -lZ MATCH ctx.txt ctx2.txt
z_same "-LZ"            -LZ MATCH ctx.txt ctxv.txt
z_same "-Z -c"          -Z -c MATCH ctx.txt ctx2.txt
z_same "-HZ"            -HZ MATCH ctx.txt
z_same "-HnZ keeps :"   -HnZ MATCH ctx.txt
z_same "-HZ with -C1"   -HZ -C1 MATCH ctx.txt

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
