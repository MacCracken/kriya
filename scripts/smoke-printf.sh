#!/bin/sh
# smoke-printf.sh — behavioural test for `kriya printf`.
#
# Compares output cell-by-cell against `/usr/bin/printf` (the GNU
# coreutils binary, not the shell builtin which has different escape
# semantics) for every shipped conversion and flag combination.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"
GNU=/usr/bin/printf

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nexpected: %s\ngot:      %s\n" "$1" "$2" "$3" >&2
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

# `compare NAME ARGS...` runs both impls with the same args and diffs.
compare() {
    name=$1
    shift
    mine=$("$BIN" printf "$@" 2>/dev/null || true)
    gnu=$("$GNU" "$@" 2>/dev/null || true)
    expect_eq "$name" "$gnu" "$mine"
}

# `same` compares stdout BYTES and the exit status — `$(...)` strips trailing
# newlines and cannot carry a NUL, and an exit status is half of every answer
# below.
same() {
    name=$1
    shift
    mrc=0; timeout 10 "$BIN" printf "$@" > "$T/m" 2>/dev/null || mrc=$?
    grc=0; "$GNU" "$@" > "$T/g" 2>/dev/null || grc=$?
    if cmp -s "$T/m" "$T/g" && [ "$mrc" = "$grc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: GNU exit %s [%s], kriya exit %s [%s]\n" "$name" "$grc" \
            "$(od -An -c "$T/g" | tr -s ' \n' '  ' | cut -c1-60)" "$mrc" \
            "$(od -An -c "$T/m" | tr -s ' \n' '  ' | cut -c1-60)" >&2
    fi
}
# --- escapes in FORMAT ---
compare "literal text"        "hello"
compare "\\n escape"          "a\nb\n"
compare "\\t escape"          "x\ty"
compare "octal \\012"         "\012"
compare "octal \\110"         "\110\145\154\154\157"   # "Hello"
compare "literal \\\\"        "\\\\"

# --- %s ---
compare "%s simple"           "%s\n" "world"
compare "%s empty"            "%s\n" ""
compare "%s width"            "[%10s]\n" "hi"
compare "%s left"             "[%-10s]\n" "hi"
compare "%s precision"        "[%.3s]\n" "hellothere"
compare "%s width+prec"       "[%10.3s]\n" "hellothere"
compare "%s * width"          "[%*s]\n" "8" "abc"
compare "%s * prec"           "[%.*s]\n" "3" "abcdef"

# --- %d / %i ---
compare "%d"                  "%d\n" "42"
# ⭐ A negative argument is DATA, no `--` needed (ADR 0025, 1.6.17).
compare "%d negative"         "%d\n" "-7"
compare "%d zero"             "%d\n" "0"
compare "%i alias"            "%i\n" "100"
compare "%d width"            "[%5d]\n" "42"
compare "%d zero-pad"         "[%05d]\n" "42"
compare "%d +"                "[%+d]\n" "42"
compare "%d space"            "[% d]\n" "42"
compare "%d left-justify"     "[%-5d|]\n" "42"
compare "%d precision"        "[%.5d]\n" "42"

# --- %u ---
compare "%u positive"         "%u\n" "42"

# --- %o ---
compare "%o"                  "%o\n" "8"
compare "%#o alt"             "%#o\n" "8"
compare "%o width"            "[%5o]\n" "8"

# --- %x / %X ---
compare "%x"                  "%x\n" "255"
compare "%X"                  "%X\n" "255"
compare "%#x"                 "%#x\n" "255"
compare "%#X"                 "%#X\n" "255"
compare "%08x"                "%08x\n" "255"

# --- %c ---
compare "%c first byte"       "%c\n" "abc"
# ⛔ THIS WAS VACUOUS until 1.6.17: GNU prints a NUL byte for an empty `%c`
# argument, kriya printed nothing, and `$(...)` drops NULs — so the two compared
# equal. `same` compares bytes.
same "%c empty"               "%c\n" ""

# --- %b ---
compare "%b with \\n"         "%b" "hello\nworld\n"
compare "%b with \\t"         "%b" "a\tb\tc\n"
compare "%b with octal"       "%b" "\110ello\n"

# --- %% ---
compare "%% literal"          "100%%\n"
compare "%% in middle"        "[%%]\n"

# --- arg reuse: more args than spec, format repeats ---
compare "arg reuse %s"        "%s\n" "a" "b" "c"
compare "arg reuse %d %s"     "%d=%s\n" "1" "one" "2" "two" "3" "three"

# --- arg shortage: missing args = 0 / "" ---
compare "missing %s"          "[%s]\n"
compare "missing %d"          "[%d]\n"

# --- numeric arg parsing: 'X form, 0x hex, 0 octal ---
compare "'X char-constant"    "%d\n" "'A"
compare "0x hex arg"          "%d\n" "0xff"
compare "0 octal arg"         "%d\n" "0177"

# --- errors ---
expect_exit "no FORMAT"  2 "$BIN" printf

# --- unhandled directives fail instead of lying (v1.2.1) ---
# ⛔ printf used to WARN on stderr, write the bare conversion LETTER to stdout
# (dropping the `%`) and exit 0 — so `printf '%f' 1.5` produced the text "f" and
# reported success.
#
# ⛔ THIS BLOCK IS A DELIBERATE DIVERGENCE, NOT A PARITY CHECK — do not "fix" it
# by comparing against GNU at runtime. The comment here used to call
# %f/%e/%g/%a "invalid directives" and claim GNU exits 1 for them. **That is
# false**: they are VALID floating-point conversions in GNU, which prints
# `1.500000` and exits 0. kriya refuses them because it has no float formatter
# yet (roadmap 1.8.0), and refusing loudly beats printing a wrong number. The
# absolutes below are the point.
#
# ⚠ `%Z` on the other hand IS invalid in GNU, so that pair is a real parity
# assertion and could be compared at runtime — it is kept as an absolute only
# for symmetry with the block above it.
for d in %f %e %g %a; do
    rc=0; out=$("$BIN" printf "$d" 1.5 2>/dev/null) || rc=$?
    expect_eq "$d exits 1"       "1" "$rc"
    expect_eq "$d prints nothing" ""  "$out"
done
rc=0; out=$("$BIN" printf '%Z' 2>/dev/null) || rc=$?
expect_eq "%Z exits 1"        "1" "$rc"
expect_eq "%Z prints nothing" ""  "$out"
# Output already written before the error is kept, and processing STOPS —
# byte-for-byte what GNU does.
expect_eq "abc%Zdef stops after abc" "$(/usr/bin/printf 'abc%Zdef' 2>/dev/null)" "$("$BIN" printf 'abc%Zdef' 2>/dev/null)"

# --- \xHH hex escape (v1.2.1) ---
# Used to fall through to the unknown-escape path and print a literal "x41".
for e in '\x41' '\x7a' '\x4' '\x41B' '\101' '\n' '\t'; do
    expect_eq "escape $e" "$(/usr/bin/printf "$e" | od -An -c)" "$("$BIN" printf "$e" | od -An -c)"
done
rc=0; "$BIN" printf '\xZ' >/dev/null 2>&1 || rc=$?
expect_eq "\\xZ exits 1" "1" "$rc"
expect_eq "abc\\xZdef stops after abc" "$(/usr/bin/printf 'abc\xZdef' 2>/dev/null)" "$("$BIN" printf 'abc\xZdef' 2>/dev/null)"

# --- escape parity, byte-exact, BOTH paths (shared decoder) ---
# ⚠ `compare` above goes through `$(...)`, which strips trailing newlines and
# cannot carry a NUL — useless for `\0` and `\c`. These go through `od`.
#
# ⛔ Every case here was a DIVERGENCE before printf's two escape decoders became
# one `str_escape_decode` call. The FORMAT path and the `%b` path are checked
# with the SAME list on purpose: the bug was never the decoding, it was a rule
# living in one copy and not the other.
compare_bytes() {
    name=$1
    shift
    mine=$("$BIN" printf "$@" 2>/dev/null | od -An -tx1 || true)
    gnu=$("$GNU" "$@" 2>/dev/null | od -An -tx1 || true)
    expect_eq "$name" "$gnu" "$mine"
}

for e in 'X\eY' 'X\cY' '[\q]' '[\"]' '[\0101]' '[\101]' '[\0]' '[\777]' '[\400]' '[\18]' '[\x41]' 'a\'; do
    compare_bytes "FORMAT $e" "$e"
    compare_bytes "%b     $e" '%b' "$e"
done
# A backslash before a single quote is NOT in GNU's named table, unlike `\"`.
compare_bytes "FORMAT backslash-quote" '[\'"'"']'
compare_bytes "%b     backslash-quote" '%b' '[\'"'"']'

# `\c` cancels output and exits 0 — in FORMAT too, argument reuse included.
expect_exit "FORMAT \\c exits 0" 0 "$BIN" printf 'X\cY'
expect_exit "%b \\c exits 0"     0 "$BIN" printf '%b' 'X\cY'
expect_eq "FORMAT \\c stops arg reuse" \
    "$("$GNU" '%s\c' a b c | od -An -tx1)" \
    "$("$BIN" printf '%s\c' a b c | od -An -tx1)"

# A malformed `\x` fails in `%b` as well, where it used to print a literal "xZ".
expect_exit "%b \\xZ exits 1" 1 "$BIN" printf '%b' '[\xZ]'

# --- ADR 0025: every argument is data (1.6.17) ---
# ⛔ The shared option parser read printf's arguments: `-5` was *bad option*,
# exit 2, and a `--` among the arguments was DELETED from the output. GNU's rule,
# measured on 9.4 and 9.11: `--help` / `--version` only as the SOLE argument, a
# first `--` dropped, and nothing else an option.
#
same "FORMAT -5"              -5
same "FORMAT -x"              -x
same "FORMAT -"               -
same "FORMAT '-%s|'"          '-%s|' a
same "%d -5"                  '%d|' -5
same "%s -5"                  '%s|' -5
same "%x -1"                  '%x|' -1
same "-- -5"                  -- -5
same "-- '%d|' -3"            -- '%d|' -3
same "a later -- is data"     '%s|' a -- b
same "a lone -- argument"     '%s|' --
same "-- -- x"                -- -- x
same "--help with more"       --help foo
same "--version with more"    --version foo
same "-- --help"              -- --help
same "%s --help"              '%s|' --help
rc=0; out=$("$BIN" printf --help 2>/dev/null) || rc=$?
expect_eq "--help alone is help" "0 yes" "$rc $(printf '%s' "$out" | grep -q '^SYNOPSIS' && echo yes)"
rc=0; out=$("$BIN" printf --version 2>/dev/null) || rc=$?
expect_eq "--version alone"      "0 yes" "$rc $(printf '%s' "$out" | grep -q 'printf (kriya)' && echo yes)"
expect_exit "-- alone: no FORMAT" 2 "$BIN" printf --

# --- numbers are read as GNU reads them (1.6.17) ---
# ⛔ `%d 99999999999999999999` WRAPPED to 7766279631452241919 at exit 0, 2^63
# printed a bare `-`, `%u` past 2^63 printed NOTHING (no unsigned path), and
# `5x`, `abc` and ' 5' were read without a word. GNU's `strtoimax` /
# `strtoumax` now, with its diagnostics and exit 1, output carrying on.
for a in 99999999999999999999 9223372036854775807 9223372036854775808 \
         -9223372036854775808 -9223372036854775809 0x7fffffffffffffff \
         0x8000000000000000 -0x8000000000000000 -0x8000000000000001 \
         5x abc ' 5' '5 ' "$(printf '\t5')" "$(printf '5\t')" 08 0x 0xg 0X1f \
         0x1Fg 099 - + +5 -0 00 -0x10 "'" "'A" "'AB" '"A' +-5 -+5 1e3 3.5; do
    same "%d [$a]" '%d|' "$a"
    same "%i [$a]" '%i|' "$a"
done
for a in 18446744073709551615 18446744073709551616 -1 -18446744073709551615 \
         -18446744073709551616 0xffffffffffffffff 0x10000000000000000 \
         01777777777777777777777 02000000000000000000000 -9223372036854775808 \
         -9223372036854775809 5x zz "'A"; do
    same "%u [$a]" '%u|' "$a"
    same "%o [$a]" '%o|' "$a"
    same "%x [$a]" '%x|' "$a"
    same "%X [$a]" '%X|' "$a"
done
same "%#o of 2^64 - 1"        '%#o|' 18446744073709551615
same "%#x of i64 min"         '%#x|' -9223372036854775808
same "%+d of i64 min"         '%+d|' -9223372036854775808
same "%.25d of i64 min"       '%.25d|' -9223372036854775808
same "%-25u|"                 '%-25u|' 18446744073709551615
same "%025d of -1"            '%025d|' -1
same "diagnostics carry on"   '%d %d %d|' 1 2x 3
same "two diagnostics"        '%d %d\n' 5x abc
same "reused after an error"  '%d|' 1 x 3
# ⚠ Version split: GNU 9.4 takes '' as 0 at exit 0; 9.11 says *expected a
# numeric value*, exit 1. kriya's is 9.11's, asserted directly.
rc=0; out=$("$BIN" printf '%d|' '' 2>/dev/null) || rc=$?
expect_eq "%d '' (9.11's answer)" "1 0|" "$rc $out"
# ⚠ ONE DELIBERATE DIVERGENCE, toward POSIX: a conversion error keeps exit 1
# through a later `\c`. GNU's `\c` exits 0 whatever came before.
rc=0; out=$("$BIN" printf '%d\c' abc 2>/dev/null) || rc=$?
expect_eq "\\c after an error is still 1" "1 0" "$rc $out"
rc=0; out=$("$BIN" printf '%d%b' 5x 'a\c' 2>/dev/null) || rc=$?
expect_eq "%b \\c after an error is still 1" "1 5a" "$rc $out"
# The diagnostics are GNU's words in kriya's frame.
err=$("$BIN" printf '%d' 5x 2>&1 >/dev/null || true)
expect_eq "not completely converted" "kriya printf: 5x: value not completely converted" "$err"
err=$("$BIN" printf '%d' abc 2>&1 >/dev/null || true)
expect_eq "expected a numeric value" "kriya printf: abc: expected a numeric value" "$err"
err=$("$BIN" printf '%d' 99999999999999999999 2>&1 >/dev/null || true)
expect_eq "out of range" "kriya printf: 99999999999999999999: numerical result out of range" "$err"
err=$("$BIN" printf '%d' "'AB" 2>&1 >/dev/null || true)
expect_eq "trailing character warning" \
    "kriya printf: B: warning: character(s) following character constant have been ignored" "$err"

# --- the directive grammar is GNU's table (1.6.17) ---
# ⛔ `%ld` and `%'d` were REFUSED, and `%#d`, `%0s`, `%.3c`, `%5%` and `%-b`
# PRINTED where GNU refuses them.
for f in '%ld|' '%lld|' '%hhd|' '%jd|' '%zd|' '%td|' '%Lx|' '%lhLd|' "%'d|" "%'u|" \
         "%'i|" '%Id|' '%ls|' '%lc|' '%hs|' '%.3ls|' '%-c|' '%5c|' '%-5c|' '%+c|' \
         '% c|' '%+s|' '% s|' '%+u|' '% u|' '%+x|' '%+o|' '%#.0x|' '%#x|' '%#o|' \
         '%#.0o|' '%+.0d|' '% .0d|' '%.0d|' '%#5.3o|' '%#08x|' '%-#8x|' '%+05d|' \
         '% 05d|' '%05.3d|' '%-05d|' '%.d|' '%.s|' '%5.s|'; do
    same "$f" "$f" 42
    same "$f of 0" "$f" 0
done
for f in "%'x" "%'o" "%'s" "%'c" '%#d' '%#i' '%#u' '%#s' '%#c' '%0s' '%0c' \
         '%.3c' '%5%' '%-%' '%5b' '%-5b' '%.1b' '%lb' '%hhb' '%-q' '%I|' "%'|" \
         '%l|' 'abc%' 'abc%-' 'abc%5' 'abc%.' 'abc%*' 'abc%l' 'abc%.*' '%s%' \
         '%1$' '%Z' '%5Z' '%*Z'; do
    same "$f refused" "$f" x
done
same "%c of '' is a NUL"      '%c|' ''
same "%5c of '' pads a NUL"   '%5c|' ''
same "%c with no argument"    '%c|'
same "%c of a UTF-8 byte"     '%c|' "$(printf '\303\251')"
same "missing: %d %s %b %c"   '%d|%s|%b|%c|'
same "%*d with no argument"   '%*d|'
same "%.*d with no argument"  '%.*d|'
same "%*.*d, one argument"    '%*.*d|' 3
# `%q` is GNU's and not kriya's: refused by name, as the floats are.
rc=0; out=$("$BIN" printf '%q' 'a b' 2>/dev/null) || rc=$?
expect_eq "%q refused" "1 " "$rc $out"

# --- widths and precisions (1.6.17) ---
# ⛔ They WRAPPED — `%18446744073709551617d 5` printed `5` — and below the wrap a
# large one HUNG: the padding was one `write(2)` per byte, 50 s for 100,000,000
# columns. ⚠ The limits are GNU printf's, measured on both versions: an integer
# or `%c` field is refused past INT_MAX - 2, `%s` takes a width up to INT_MAX.
# A refused field prints NOTHING, and the rest of the format goes on, exit 1.
for f in '%18446744073709551617d' '%9223372036854775807d' '%2147483648d' \
         '%2147483646d' '%-2147483646d' '%2147483646x' '%.2147483646x' \
         '%2147483646c' '%.2147483648d' '%.18446744073709551617d' '%2147483648s' \
         'ab%2147483648dcd' 'ab%.2147483646ucd'; do
    same "$f" "$f" 5
done
same "*: INT_MAX + 1 is fatal"     'a%*db' 2147483648 5
same "*: INT_MIN - 1 is fatal"     'a%*db' -2147483649 5
same "*: INT_MIN is not printed"   'a%*db' -2147483648 5
same "*: INT_MAX - 1, an integer"  'a%*db' 2147483646 5
same "*: 2^64 + 1"                 'a%*db' 18446744073709551617 5
same "*: 2^66 is fatal, and ERANGE" 'a%*db' 99999999999999999999 5
same ".*: INT_MAX + 1 is fatal"    'a%.*db' 2147483648 5
same ".*: negative is no precision" '%.*d|' -5 5
same ".*: past i64, no precision"  '%.*d|' -99999999999999999999 5
same "*: abc is 0, exit 1"         '%*d|' abc 5
same "*: 5x is 5, exit 1"          '%*d|' 5x 5
same "*: ' 3' is 3"                '%*d|' ' 3' 5
same "*: a character constant"     '%*s|' "'A" x
same "*: negative left-justifies"  '%*d|' -5 5
# ⚠ Version split: 9.11 reads a `%s` precision past INT_MAX as no limit; 9.4
# refuses the field. kriya's is 9.11's, asserted directly.
rc=0; out=$(timeout 10 "$BIN" printf '%.2147483648s|%5.18446744073709551617s|' abc de 2>/dev/null) || rc=$?
expect_eq "%s precision past INT_MAX is no limit (9.11)" "0 abc|   de|" "$rc $out"
# A wide field is written a buffer at a time, and the byte count is GNU's.
expect_eq "%100000000d, fast" "$("$GNU" '%100000000d' 5 | wc -c)" \
    "$(timeout 10 "$BIN" printf '%100000000d' 5 | wc -c)"
expect_eq "%-100000000s|, fast" "$("$GNU" '%-100000000s|' x | wc -c)" \
    "$(timeout 10 "$BIN" printf '%-100000000s|' x | wc -c)"
expect_eq "%.100000000d, fast" "$("$GNU" '%.100000000d' 5 | wc -c)" \
    "$(timeout 10 "$BIN" printf '%.100000000d' 5 | wc -c)"
# ⚠ `timeout` on every call that can pad: a regression is a two-gigabyte hang.
err=$(timeout 10 "$BIN" printf '%2147483648d' 5 2>&1 >/dev/null || true)
expect_eq "the field is named" "kriya printf: %2147483648d: invalid field width" "$err"
err=$(timeout 10 "$BIN" printf '%*d' 2147483648 5 2>&1 >/dev/null || true)
expect_eq "the * value is named" "kriya printf: 2147483648: invalid field width" "$err"

# --- argument reuse, and what is left over (1.6.17) ---
for args in "%s|%s| a b c" "%*s|%s| 3 a" "%*s| 3 a 4 b 5" "%.*d| 3 7 x 8" "%d%%| 1 2"; do
    # shellcheck disable=SC2086
    same "reuse: $args" $args
done
# GNU warns when a pass uses no argument and some are left; so does kriya now.
same "no conversion, arguments left" x a b
same "%% only, arguments left"       '%%' a
err=$("$BIN" printf 'x' a b 2>&1 >/dev/null || true)
expect_eq "the first unused argument is named" \
    "kriya printf: a: warning: ignoring excess arguments, starting with this one" "$err"

# --- 100,000 arguments (1.6.17) ---
# ⛔ QUADRATIC: every argument was fetched with the stdlib's `argv(i)`, a walk
# from the start of the command line each time. 20,000 took 1.4 s; `timeout`
# makes a regression a failure.
n=$(timeout 10 "$BIN" printf '%s\n' $(seq 100000) | wc -l)
expect_eq "printf over 100,000 arguments" "100000" "$n"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
