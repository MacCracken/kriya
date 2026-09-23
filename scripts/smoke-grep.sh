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
# `-r` with no operand searches `.` since 1.6.16, as GNU's does — the `g16`
# block below compares it; it used to be refused here.
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

# --- ⭐ --include / --exclude, against GNU -------------------------------
#
# ⛔ THREE RULES HERE ARE NOT WHAT A CAREFUL READING WOULD GUESS. The first
# implementation of this filter got all three wrong AND passed a nine-case
# test — because none of those cases discriminated them. Every case below is
# chosen to fail if a rule is dropped.
#
#  1. PRECEDENCE IS RIGHTMOST-WINS, not "exclude beats include".
#  2. THE DEFAULT FOR AN UNMATCHED NAME comes from the FIRST option's type, so
#     `--exclude=zzz --include='*.c'` searches EVERYTHING while the same two
#     options in the other order search only .c files.
#  3. THE SUBJECT DIFFERS BY HOW THE FILE WAS REACHED: base name under -r
#     descent, operand-as-typed plus every '/'-suffix on the command line.
mkdir -p inc/sub
printf 'hit\n' > inc/a.c; printf 'hit\n' > inc/b.h
printf 'hit\n' > inc/sub/c.c; printf 'hit\n' > inc/sub/d.h

inc_same() {
    label=$1; shift
    grc=0; g=$(cd inc && grep "$@" 2>&1 | sort) || grc=$?
    krc=0; k=$(cd inc && "$BIN" grep "$@" 2>&1 | sort) || krc=$?
    expect_eq "include: $label" "$g" "$k"
    expect_eq "include: $label (exit)" "$grc" "$krc"
}
# 1 — rightmost wins. ⚠ The third case is the one that fails under an
# "exclude always wins" implementation.
inc_same "rightmost: inc exc inc"      -rl --include=*.h --exclude=a.c --include=*.c hit .
inc_same "rightmost: inc then exc"     -rl --include=*.c --exclude=a.c hit .
inc_same "rightmost: exc inc same glob" -rl --exclude=*.c --include=*.c hit .
inc_same "rightmost: inc exc same glob" -rl --include=*.c --exclude=*.c hit .

# 2 — default set by the FIRST option. ⚠ These two differ ONLY in order and
# must produce different output; an implementation that ignores order passes
# one and fails the other.
inc_same "default from first: inc,exc" -rl --include=*.c --exclude=zzz hit .
inc_same "default from first: exc,inc" -rl --exclude=zzz --include=*.c hit .

# 3 — subject depends on how the file was reached.
inc_same "operand: full path suffix"   --exclude=sub/c.c hit sub/c.c
inc_same "operand: bare basename"      --exclude=c.c hit sub/c.c
inc_same "operand: glob with slash"    --exclude=*/c.c hit sub/c.c
inc_same "operand: non-suffix misses"  --exclude=sub hit sub/c.c
inc_same "descent: slash never matches" -rl --include=sub/*.c hit .

# Directories are exempt entirely — never pruned, always descended.
inc_same "dirs exempt from --exclude"  -rl --exclude=sub hit .
inc_same "dir operand still descended" -rl --include=*.c hit sub

inc_same "repeatable includes OR"      -rl --include=*.c --include=*.h hit .
inc_same "no filters"                  -rl hit .
inc_same "all filtered out"            -rl --include=*.nomatch hit .

# ⚠ stdin is never filtered, however aggressive the pattern.
sg=$(echo hit | grep --exclude='*' hit) || true
sk=$(echo hit | "$BIN" grep --exclude='*' hit) || true
expect_eq "include: stdin is never filtered" "$sg" "$sk"

# ⚠ Filtering happens AFTER the open attempt, so an excluded operand that
# cannot be opened still reports and exits 2.
grc=0; (cd inc && grep --exclude='nosuch.c' hit nosuch.c) >/dev/null 2>&1 || grc=$?
krc=0; (cd inc && "$BIN" grep --exclude='nosuch.c' hit nosuch.c) >/dev/null 2>&1 || krc=$?
expect_eq "include: excluded-but-missing operand still errors" "$grc" "$krc"

# --- `-i` and bracket expressions (1.4.5) ------------------------------
#
# ⛔ LC_ALL=C IS LOAD-BEARING HERE, not hygiene. A bracket RANGE walks COLLATION
# order, so `grep -i '[>-a]'` gives three different answers under `C`,
# `C.UTF-8` and `en_US.UTF-8`. kriya is byte-ordered and ASCII-only by design
# (ADR 0005), so it implements the C-locale rule and the oracle must be pinned
# to it. `compare` already exports LC_ALL=C; the raw calls below do so too.
#
# ⛔ `-o` IS DELIBERATELY NOT COMPARED for a range spanning the case gap.
# GNU CONTRADICTS ITSELF there: on a line holding just `_`, `grep -i "[A-z]"`
# matches (exit 0, and `-c` says 1) while `grep -i -o "[A-z]"` exits 0 and
# prints NOTHING. Verified identical on grep 3.11 and 3.12. kriya follows the
# LINE MATCHER — the documented semantics, and the half GNU is self-consistent
# about — so its `-o` prints what actually matched.
printf 'lower\nUPPER\nMiXeD\n12345\n!@#$%%\n_\n' > icase_mix

# The headline bug: this returned NOTHING before 1.4.5.
compare 'i: [[:upper:]] is [[:alpha:]]'  "$(cat icase_mix)" "-i '[[:upper:]]' icase_mix"
compare 'i: [[:lower:]] is [[:alpha:]]'  "$(cat icase_mix)" "-i '[[:lower:]]' icase_mix"
compare 'i: [[:alpha:]] unchanged'       "$(cat icase_mix)" "-i '[[:alpha:]]' icase_mix"
# ⚠ Digits and punctuation must still NOT match — the rule is "both cases",
# not "everything". A fixture without them cannot tell those two apart.
compare 'i: [[:digit:]] unaffected'      "$(cat icase_mix)" "-i '[[:digit:]]' icase_mix"
compare 'i: [[:punct:]] unaffected'      "$(cat icase_mix)" "-i '[[:punct:]]' icase_mix"
compare 'i: negated class'               "$(cat icase_mix)" "-i '[^[:upper:]]' icase_mix"
compare 'i: class + digits'              "$(cat icase_mix)" "-i '[[:upper:]0-9]' icase_mix"
compare 'i: ranges both cases'           "$(cat icase_mix)" "-i '[a-c]' icase_mix"
compare 'i: ranges both cases (upper)'   "$(cat icase_mix)" "-i '[A-C]' icase_mix"
compare 'i: negated literal'             "$(cat icase_mix)" "-i '[^a]' icase_mix"
# The same rules under the ERE engine, which reaches them by a different path:
# niyama'''s inline `(?i)` case-closes a RANGE but not a NAMED CLASS.
compare 'i -E: [[:upper:]]'              "$(cat icase_mix)" "-i -E '[[:upper:]]' icase_mix"
compare 'i -E: ranges'                   "$(cat icase_mix)" "-i -E '[A-C]' icase_mix"
compare 'i -E: negated class'            "$(cat icase_mix)" "-i -E '[^[:upper:]]' icase_mix"

# Range validity. ⚠ The gate is the UPPER-case fold: `[A-_]` is ACCEPTED and
# `[B-a]` is REFUSED, though both have a reversed lower-case fold.
icase_rc() {
    grc=0; LC_ALL=C grep -i "$2" icase_mix >/dev/null 2>&1 || grc=$?
    krc=0; LC_ALL=C "$BIN" grep -i "$2" icase_mix >/dev/null 2>&1 || krc=$?
    # Collapse to match / no-match / error so the two diagnostics need not agree.
    [ "$grc" -ge 2 ] && grc=2
    [ "$krc" -ge 2 ] && krc=2
    expect_eq "$1" "$grc" "$krc"
}
icase_rc 'i: [Z-a] refused'        '[Z-a]'
icase_rc 'i: [W-d] refused'        '[W-d]'
icase_rc 'i: [B-a] refused'        '[B-a]'
icase_rc 'i: [A-_] accepted'       '[A-_]'
icase_rc 'i: [A-z] accepted'       '[A-z]'
# ⚠ A raw-reversed range that clears the gate matches NOTHING and is NOT an
# error — so `-i` turns what is a hard error without it into silence.
icase_rc 'i: [b-B] is empty not an error' '[b-B]'
icase_rc 'i: [a-B] is empty not an error' '[a-B]'
icase_rc 'i: [a-c-e] refused'      '[a-c-e]'
icase_rc 'i: [a-c-] accepted'      '[a-c-]'
icase_rc 'i: [[-m] refused'        '[[-m]'
icase_rc 'i: [Z-[] accepted'       '[Z-[]'
icase_rc 'i: class cannot end a range' '[a-[:digit:]]'

# ⛔ `[=c=]` / `[.c.]` are REFUSED — with AND without `-i`. niyama implements
# neither and fails both SILENTLY: `grep '[[=a=]]'` returned no match where GNU
# matches, and `grep '[[.a.]-c]'` returned 0 where GNU returns 3. ⚠ Refusing on
# the `-i` path alone would leave the same pattern loud one way and silently
# wrong the other, which is worse than uniform silence. This is a deliberate
# divergence from GNU in the direction of a loud error (roadmap M11).
for icf in '' '-i'; do
    for icp in '[[=a=]]' '[[.a.]]' '[[=a=]b]' '[[.a.]-c]'; do
        rc=0; LC_ALL=C "$BIN" grep $icf -c "$icp" icase_mix >/dev/null 2>&1 || rc=$?
        expect_eq "i: $icf $icp refused loudly" "2" "$rc"
    done
done
# ⚠ And must NOT fire on an ordinary bracket that merely contains `.` or `[`.
for icp in '[.]' '[a.b]' '[[:alpha:]x]' '[]a]'; do
    rc=0; LC_ALL=C "$BIN" grep -c "$icp" icase_mix >/dev/null 2>&1 || rc=$?
    grc=0; LC_ALL=C grep -c "$icp" icase_mix >/dev/null 2>&1 || grc=$?
    [ "$rc" -ge 2 ] && rc=2
    [ "$grc" -ge 2 ] && grc=2
    expect_eq "i: $icp is an ordinary bracket" "$grc" "$rc"
done

# ⛔ Bracket RANGES are validated on the no-`-i` path too. Nothing checked them
# before 1.4.5: kriya diverged from GNU on 4,095 of 8,281 ranges, and two were
# SILENT WRONG ANSWERS rather than mere silence — `grep '[a-c-e]'` matched five
# lines and `grep '[[:digit:]-a]'` matched twelve, where GNU exits 2.
# ⚠ The gate here is the RAW comparison, NOT the upper-case fold that `-i` uses,
# and the two give OPPOSITE answers on the same input: plain `[Z-a]` is valid
# while `-i '[Z-a]'` is an error, and plain `[b-B]` is an error while
# `-i '[b-B]'` is silently empty. Asserting both is what pins them apart.
plain_rc() {
    grc=0; LC_ALL=C grep "$2" icase_mix >/dev/null 2>&1 || grc=$?
    krc=0; LC_ALL=C "$BIN" grep "$2" icase_mix >/dev/null 2>&1 || krc=$?
    [ "$grc" -ge 2 ] && grc=2
    [ "$krc" -ge 2 ] && krc=2
    expect_eq "$1" "$grc" "$krc"
}
plain_rc 'plain: [a-c-e] refused'       '[a-c-e]'
plain_rc 'plain: [[:digit:]-a] refused' '[[:digit:]-a]'
plain_rc 'plain: [b-B] refused'         '[b-B]'
plain_rc 'plain: [a-Z] refused'         '[a-Z]'
plain_rc 'plain: [Z-a] ACCEPTED'        '[Z-a]'
plain_rc 'plain: [A-z] accepted'        '[A-z]'
plain_rc 'plain: [a-c] accepted'        '[a-c]'
plain_rc 'plain: [a-] accepted'         '[a-]'

# ⚠ Without `-i` nothing above changes: the control matters, because a bug that
# broke plain bracket matching would otherwise hide behind the -i assertions.
compare 'plain [[:upper:]] control'  "$(cat icase_mix)" "'[[:upper:]]' icase_mix"
compare 'plain [[:lower:]] control'  "$(cat icase_mix)" "'[[:lower:]]' icase_mix"
compare 'plain [A-C] control'        "$(cat icase_mix)" "'[A-C]' icase_mix"

# --- 1.6.14: -NUM, --exclude-dir, and what measuring them found -------------
#
# ⭐ EVERY CASE ASKS GNU, with stdin closed: a case that lost its file operand to
# a misparse would otherwise sit reading the terminal. `g14` compares stdout and
# the exit status; stderr is dropped, since GNU's frame is `grep:` and kriya's
# `kriya grep:`.
g14() {   # g14 <label> <args...>
    _l=$1; shift
    _grc=0; _g=$(cd g14 && LC_ALL=C grep "$@" < /dev/null 2>/dev/null | sort) || _grc=$?
    _krc=0; _k=$(cd g14 && LC_ALL=C "$BIN" grep "$@" < /dev/null 2>/dev/null | sort) || _krc=$?
    expect_eq "1.6.14: $_l" "$_grc|$_g" "$_krc|$_k"
}
mkdir -p g14/t/sub/deep g14/t/keep/sub g14/t/.git g14/t/sub2
for _p in t/a t/sub/b t/sub/deep/c t/keep/d t/keep/sub/e t/.git/g t/sub2/h; do
    printf 'hit\n' > "g14/$_p"
done
seq 1 30 | sed 's/^/line /' > g14/f

# ⛔ `-NUM` IS `-C NUM`, and it was a usage error. The shared parser expands it
# (`kriya_set_digit_option`): digits accumulate within a run, a new run
# restarts, it permutes like any option, and -A / -B still override it.
for _o in "-2" "-12" "-0" "-21" "-2i" "-i2" "-in2" "-n2" "-2n" "-1i2" "-2c"; do
    g14 "grep $_o" $_o 'line 15' f
done
g14 "-1 -2: the later run wins"       -1 -2 'line 15' f
g14 "-2 -1"                           -2 -1 'line 15' f
g14 "-2 -A 0: -A overrides"           -2 -A 0 'line 15' f
g14 "-A 0 -2: in either order"        -A 0 -2 'line 15' f
g14 "-C 1 -3: last of -C/-NUM wins"   -C 1 -3 'line 15' f
g14 "-3 -C 1"                         -3 -C 1 'line 15' f
g14 "-1e: the e still takes a value"  -1e 'line 15' f
g14 "-e -2: a value, not an option"   -e -2 f
g14 "-- -2: an operand"               -- -2 f
g14 "after the operands"              'line 15' f -2
g14 "leading zeros"                   -0000000000000000000000002 'line 15' f

# ⛔ A HUGE CONTEXT SEGFAULTED. The ring was sized to -B up front, so
# `-C 2147483648` asked for 64 GiB. ⚠ GNU 3.12 HANGS from about INTMAX_MAX, so
# past that the answer is asserted as the equivalent finite request.
g14 "-C 2147483648 (was a segfault)"  -C 2147483648 'line 15' f
g14 "-2147483648"                     -2147483648 'line 15' f
expect_eq "1.6.14: -C past i64 is everything, not a wrap" \
  "$(cd g14 && LC_ALL=C grep -C 1000 'line 15' f)" \
  "$(cd g14 && "$BIN" grep -C 18446744073709551617 'line 15' f < /dev/null)"
expect_eq "1.6.14: -B past i64 likewise" \
  "$(cd g14 && LC_ALL=C grep -B 1000 'line 15' f)" \
  "$(cd g14 && "$BIN" grep -B 99999999999999999999 'line 15' f < /dev/null)"
# ⛔ `-C -1` WAS THE FLAG'S OWN "NOT GIVEN" DEFAULT, and silently ignored.
for _v in -1 -3; do
    expect_exit "1.6.14: -C $_v is refused" 2 "$BIN" grep -C "$_v" x g14/f
    expect_exit "1.6.14: ...and GNU agrees"  2 grep -C "$_v" x g14/f
done
case "$("$BIN" grep -A -1 x g14/f 2>&1)" in
    *"invalid context length argument"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf 'FAIL 1.6.14: -A -1 names the rule\n' >&2 ;;
esac

# ⭐ --exclude-dir: the base name under -r, the path or any `/`-suffix for an
# operand, silently, and never an --include/--exclude side effect.
g14 "-r (control)"                        -r hit t
for _x in sub 'sub*' deep .git t 's?b' '[s]ub' sub/ '' a '*'; do
    g14 "-r --exclude-dir='$_x'"          -r "--exclude-dir=$_x" hit t
done
g14 "operand t/ keeps its slash"          -r --exclude-dir=t hit t/
g14 "a / never matches a base name"       -r --exclude-dir=t/sub hit t
g14 "operand: t/sub by its suffix"        -r --exclude-dir=sub hit t/sub
g14 "operand: t/sub/ not"                 -r --exclude-dir=sub hit t/sub/
g14 "operand: keep/sub"                   -r --exclude-dir=keep/sub hit t/keep/sub
g14 "operand: eep/sub is not a suffix"    -r --exclude-dir=eep/sub hit t/keep/sub
g14 "operand: * crosses / there"          -r '--exclude-dir=t*' hit t/keep/sub
g14 "operand: ."                          -r --exclude-dir=. hit .
g14 "--exclude never prunes a directory"  -r --exclude=sub hit t
g14 "two of them"                         -r --exclude-dir=sub --exclude-dir=keep hit t
g14 "separated value"                     -r --exclude-dir sub hit t
g14 "with --include"                      -r --exclude-dir=sub --include=b hit t
g14 "without -r: silent, not Is a dir"    --exclude-dir=t hit t
g14 "...beside a file"                    --exclude-dir=t hit t t/a
g14 "-c"                                  -c -r --exclude-dir=t hit t
g14 "-l"                                  -l -r --exclude-dir=sub hit t
g14 "-L"                                  -L -r --exclude-dir=sub hit t
# ⛔ THE FILTER WALK READ `-e`'S VALUE AS AN OPTION. `grep -e --exclude=x x`
# excluded the file `x` and exited 1; GNU searches it.
printf -- '--exclude=x\n' > g14/x
g14 "-e --exclude=x is a pattern"         -e --exclude=x x
g14 "-e --exclude-dir=sub likewise"       -r -e --exclude-dir=sub t

# ⛔ -r WITH ONE OPERAND NAMES ONLY WHAT IT FINDS INSIDE A DIRECTORY.
g14 "-r one file: no prefix"              -r hit t/a
g14 "-rc one file"                        -rc hit t/a
g14 "-r two files"                        -r hit t/a t/keep/d
g14 "-rH one file"                        -rH hit t/a

# ⛔ -x AND -w HOLD FOR EVERY ALTERNATIVE. niyama is leftmost-first, and the
# check ran on the one alternative it tried: `-xE 'a|ab'` rejected the line
# `ab` and `-wE 'a|ab'` selected nothing — silently.
printf 'ab\nab cd\nabc\nx ab y\n' > g14/xw
for _o in "-xE a|ab" "-xE ab|a" "-wE a|ab" "-wE ab|a" "-xE (a|ab)(c|)" "-wE a|abc" \
          "-cxE a|ab" "-cwE a|ab" "-owE a|ab" "-oxE a|ab"; do
    _flags=${_o%% *}; _pat=${_o#* }
    g14 "grep $_o" "$_flags" "$_pat" xw
done
g14 "-x -e a -e ab"                       -x -e a -e ab xw
g14 "-w -e a -e ab"                       -w -e a -e ab xw

# ⛔ -o: NO EMPTY MATCHES, NOTHING UNDER -v, LEFTMOST-LONGEST ACROSS -e.
printf 'abc\nbaaac\nxyz\n\naa\n' > g14/o
for _pat in 'x*' 'a*' '^' '$' ''; do
    g14 "-o '$_pat'"                      -o "$_pat" o
done
g14 "-on 'a*'"                            -on 'a*' o
g14 "-o -v 'x*'"                          -o -v 'x*' o
g14 "-o -v zzz"                           -o -v zzz o
g14 "-oE 'a?'"                            -oE 'a?' o
g14 "-o -e 'x*' -e a"                     -o -e 'x*' -e a o
g14 "-o -e a -e ab"                       -o -e a -e ab xw
g14 "-o -e b -e abc"                      -o -e b -e abc xw
g14 "-oF -e a -e ab"                      -oF -e a -e ab xw
# ⚠ RECORDED, NOT FIXED: inside ONE pattern the extent is still niyama's first
# alternative. Line selection no longer depends on it; `-o`'s text does.
# Roadmap M11 — the day this flips, niyama is leftmost-longest and it goes.
expect_eq "1.6.14: recorded gap: GNU -oE 'a|ab' prints ab" "ab" \
  "$(cd g14 && LC_ALL=C grep -oE 'a|ab' xw | head -1)"
expect_eq "1.6.14: ...and kriya prints a" "a" \
  "$(cd g14 && "$BIN" grep -oE 'a|ab' xw < /dev/null | head -1)"

# ⛔ A POSIX-LITERAL `*` IN A BRE: after a leading `^`, and first in a group.
printf '*a\nb*c\nxa\n**\n^*a\n' > g14/st
for _pat in '^*' '^*a' '\(*a\)' '\(^*a\)' '\(\(^*a\)\)' 'b\(*c\)' '^\(*a\)' '*' '**' '[*]a'; do
    g14 "BRE '$_pat'"                     "$_pat" st
done
expect_eq "1.6.14: nl -b 'p^*' numbers only the * line" \
  "$(cd g14 && nl -b 'p^*' st)" "$(cd g14 && "$BIN" nl -b 'p^*' st)"
mkdir -p g14/fr && : > 'g14/fr/*a' && : > g14/fr/xa
expect_eq "1.6.14: find -regex 'fr/\(*a\)'" \
  "$(cd g14 && find fr -regex 'fr/\(*a\)')" "$(cd g14 && "$BIN" find fr -regex 'fr/\(*a\)')"

# ⛔ ADR 0022: an ERE repetition operator with nothing to repeat is REFUSED,
# where GNU warns and drops it. Asserted as kriya's own answer, with the rule
# named rather than a bare "bad pattern".
for _pat in '*' '*a' 'x|*' '(*a)' '+' '?' '{2}'; do
    expect_exit "1.6.14: grep -E '$_pat' is refused" 2 "$BIN" grep -E "$_pat" g14/o
done
case "$("$BIN" grep -E '*a' g14/o 2>&1)" in
    *"repeats nothing"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf 'FAIL 1.6.14: the refusal names the rule\n' >&2 ;;
esac
case "$("$BIN" grep -E 'a**' g14/o 2>&1)" in
    *"repeats a repetition"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf 'FAIL 1.6.14: a** names its rule too\n' >&2 ;;
esac
# ...and a literal is one backslash away, as the message says.
g14 "ERE '\\*a' is the literal"           -E '\*a' st

# --- 1.6.16: `grep -r` with no operand searches `.` --------------------------
#
# ⛔ IT WAS REFUSED, "-r requires file operands". GNU (since 2.11) searches the
# working directory and names what it finds WITHOUT a `./` — `sub/b:hit` — and
# exempts that implied `.` from `--exclude-dir`: `--exclude-dir=.` still
# searches, and `--exclude-dir='*'` still reads the top level's files.
# ⚠ Exit statuses are compared too, which the `g14` helper above cannot do: its
# `$(… | sort)` reports sort's status, not grep's.
g16() {   # g16 <label> <args...>: in g14/t, no operand; GNU and kriya agree
    _l=$1; shift
    _grc=0; (cd g14/t && LC_ALL=C grep "$@" < /dev/null > ../../g16_g.raw 2>/dev/null) || _grc=$?
    _krc=0; (cd g14/t && LC_ALL=C "$BIN" grep "$@" < /dev/null > ../../g16_k.raw 2>/dev/null) || _krc=$?
    expect_eq "1.6.16: $_l" "$_grc|$(tr '\0' '\n' < g16_g.raw | sort)" "$_krc|$(tr '\0' '\n' < g16_k.raw | sort)"
}
printf 'miss\n' > g14/t/m
g16 "-r PAT"                     -r hit
g16 "-rl"                        -rl hit
g16 "-rL"                        -rL hit
g16 "-rc"                        -rc hit
g16 "-rh"                        -rh hit
g16 "-rH"                        -rH hit
g16 "-rn"                        -rn hit
g16 "-rZl"                       -rZl hit
g16 "-rv"                        -rv hit
g16 "-rq"                        -rq hit
g16 "-r, no match"               -r nomatch
g16 "--exclude-dir=. keeps ."    -r --exclude-dir=. hit
g16 "--exclude-dir='*'"          -r "--exclude-dir=*" hit
g16 "--exclude-dir=sub"          -r --exclude-dir=sub hit
g16 "--exclude-dir=.git"         -r --exclude-dir=.git hit
g16 "--include"                  -r "--include=a" hit
g16 "-r -e"                      -r -e hit
g16 "-r PAT . keeps ./"          -r hit .
# `-` is still standard input, operand or not.
expect_eq "1.6.16: -r PAT - reads stdin" "$(echo hit | grep -r hit -)" "$(echo hit | "$BIN" grep -r hit -)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
