#!/bin/sh
# smoke-nl.sh — behavioural test for `kriya nl`.
#
# Compares output cell-by-cell against GNU `nl` for every shipped
# flag combination. The "unnumbered padding = width + sep_len spaces"
# rule is the load-bearing GNU quirk and gets explicit coverage.

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
        printf "FAIL %s:\nexpected: '%s'\ngot:      '%s'\n" "$1" "$2" "$3" >&2
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

# --- fixture: mix of empty + non-empty lines ---
printf "alpha\n\nbeta\ngamma\n\n\ndelta\n" > mix
printf "x\ny\nz\n" > short
seq 1 50 > nums
printf "no trailing nl"                   > nonl
printf ""                                 > empty

# --- default -b t (number non-empty) ---
expect_eq "default mix"   "$(nl mix)"             "$($BIN nl mix)"
expect_eq "default short" "$(nl short)"           "$($BIN nl short)"
expect_eq "default empty" "$(nl empty)"           "$($BIN nl empty)"
expect_eq "default nonl"  "$(nl nonl)"            "$($BIN nl nonl)"

# --- -b a (number all) ---
expect_eq "-b a mix"      "$(nl -b a mix)"        "$($BIN nl -b a mix)"

# --- -b n (number none) ---
expect_eq "-b n mix"      "$(nl -b n mix)"        "$($BIN nl -b n mix)"

# --- -n FORMAT ---
expect_eq "-n rz"         "$(nl -n rz mix)"       "$($BIN nl -n rz mix)"
expect_eq "-n ln"         "$(nl -n ln mix)"       "$($BIN nl -n ln mix)"
expect_eq "-n rn explicit" "$(nl -n rn mix)"      "$($BIN nl -n rn mix)"

# --- -w width ---
expect_eq "-w 3"          "$(nl -w 3 mix)"        "$($BIN nl -w 3 mix)"
expect_eq "-w 10"         "$(nl -w 10 mix)"       "$($BIN nl -w 10 mix)"

# --- -s separator (the unnumbered-padding interaction is the key test) ---
expect_eq "-s ': '"       "$(nl -s ': ' mix)"     "$($BIN nl -s ': ' mix)"
expect_eq "-s 'XXX'"      "$(nl -s XXX mix)"      "$($BIN nl -s XXX mix)"

# --- -v starting number ---
expect_eq "-v 100"        "$(nl -v 100 short)"    "$($BIN nl -v 100 short)"

# --- -i increment ---
expect_eq "-i 5"          "$(nl -i 5 short)"      "$($BIN nl -i 5 short)"

# --- combined flags ---
expect_eq "-b a -n rz -w 4" \
    "$(nl -b a -n rz -w 4 short)" \
    "$($BIN nl -b a -n rz -w 4 short)"

# --- stdin ---
expect_eq "stdin"         "$(nl < mix)"           "$($BIN nl < mix)"
expect_eq "stdin -b a"    "$(nl -b a < mix)"      "$($BIN nl -b a < mix)"

# --- larger input ---
expect_eq "50 lines"      "$(nl nums)"            "$($BIN nl nums)"

# --- errors ---
expect_exit "bad -b"      2 "$BIN" nl -b xyz mix
expect_exit "bad -n"      2 "$BIN" nl -n abc mix
expect_exit "missing file" 1 "$BIN" nl ghost

# --- multi-file (GNU continuous numbering) ---
expect_eq "multi-file"    "$(nl short mix)"       "$($BIN nl short mix)"

# --- sections (1.4.4) ---------------------------------------------------
#
# Fixture uses the DEFAULT delimiter `\:`, plus deliberate near-misses: four
# reps and a leading space must both number as ordinary text.
printf '\\:\\:\\:\nHEADER\n\\:\\:\nBODY1\nBODY2\n\nafter\n\\:\nFOOTER\n' > sect
printf '\\:\\:\\:x\nA\n \\:\\:\\:\nB\n\\:\\:\\:\\:\nC\n' > nearmiss
printf 'a\n\n\n\nb\n\n\nc\n' > blanks
printf 'ABABAB\nH\nABAB\nB\nAB\nF\n' > abdelim
printf '@:@:@:\nH\n@:@:\nB\n@:\nF\n' > atdelim

expect_eq "sections default"   "$(nl sect)"                "$($BIN nl sect)"
expect_eq "sections -ha -fa"   "$(nl -ha -fa -ba sect)"    "$($BIN nl -ha -fa -ba sect)"
expect_eq "near-miss is text"  "$(nl -ba nearmiss)"        "$($BIN nl -ba nearmiss)"
expect_eq "counter resets"     "$(nl -v10 -i5 -ha -fa -ba sect)" \
                               "$($BIN nl -v10 -i5 -ha -fa -ba sect)"
expect_eq "-p no renumber"     "$(nl -p -ha -fa -ba sect)" "$($BIN nl -p -ha -fa -ba sect)"
# ⚠ A marker line is a BARE newline — no number, no separator, no padding —
# whatever -w and -s say. That is the rule most easily got wrong.
expect_eq "marker ignores -w/-s" "$(nl -w9 -s'@@@' -ha -fa -ba sect)" \
                                 "$($BIN nl -w9 -s'@@@' -ha -fa -ba sect)"
expect_eq "-d two chars"       "$(nl -d AB -ha -fa -ba abdelim)" \
                               "$($BIN nl -d AB -ha -fa -ba abdelim)"
# One character implies ':' as the second (coreutils 9.0).
expect_eq "-d one char"        "$(nl -d @ -ha -fa -ba atdelim)" \
                               "$($BIN nl -d @ -ha -fa -ba atdelim)"
expect_eq "-d backslash = default" "$(nl -d '\' -ha -fa -ba sect)" \
                                   "$($BIN nl -d '\' -ha -fa -ba sect)"
expect_eq "-l 2 joins blanks"  "$(nl -ba -l2 blanks)"      "$($BIN nl -ba -l2 blanks)"
expect_eq "-l ignored by -bt"  "$(nl -bt -l2 blanks)"      "$($BIN nl -bt -l2 blanks)"
expect_eq "-b p regex"         "$(nl -b pBODY sect)"       "$($BIN nl -b pBODY sect)"
expect_eq "-b p empty = all"   "$(nl -b p blanks)"         "$($BIN nl -b p blanks)"
expect_eq "-h/-b/-f own regex" "$(nl -h pHEADER -b pBODY -f pFOOTER -ha -fa sect)" \
                               "$($BIN nl -h pHEADER -b pBODY -f pFOOTER -ha -fa sect)"

# ⛔ `-d ''` IS NOT COMPARED AGAINST LOCAL GNU, and that is deliberate. GNU
# documents it as "disables section matching" and coreutils 9.4 does exactly
# that, but 9.11's multi-byte rewrite of `check_section` regressed it into
# treating every EMPTY line as a header marker. The oracle contradicts its own
# `--help` and disagrees with itself across the two versions kriya must satisfy,
# so this asserts the DOCUMENTED behaviour as an absolute instead.
expect_eq "-d '' disables sections" \
    "$(printf '     1\tHEADER\n     2\tBODY1\n')" \
    "$(printf 'HEADER\nBODY1\n' | $BIN nl -d '' -ba)"
# The load-bearing half: a line that WOULD be a marker is numbered as text.
expect_eq "-d '' numbers a marker line" \
    "$(printf '     1\t\\:\\:\\:\n     2\tHEADER\n')" \
    "$(printf '\\:\\:\\:\nHEADER\n' | $BIN nl -d '' -ba)"

# ⛔ The GNU-only BRE operators are REFUSED, not silently mis-numbered. niyama
# compiles `a\+b` clean and then matches nothing (roadmap M11), so numbering
# would be wrong with no error. Exit 2 is the whole point of the guard.
expect_exit "-b p refuses \\+"  2 "$BIN" nl -b 'pa\+b' sect
expect_exit "-b p refuses \\|"  2 "$BIN" nl -b 'pa\|b' sect
expect_exit "-b p refuses \\w"  2 "$BIN" nl -b 'p\wx'  sect
expect_exit "-b p bad regex"    2 "$BIN" nl -b 'p\('    sect
expect_exit "bad -h"            2 "$BIN" nl -h zzz sect
expect_exit "bad -f"            2 "$BIN" nl -f zzz sect
# ⚠ `-l 0` is GNU 9.11's too, and means what `-l 1` means; refused until 1.6.16.
# Compared with GNU's `-l 1`, because GNU 9.4 (CI's) still refuses `-l 0`.
expect_eq "-l 0 is -l 1" "$(nl -l 1 -b a mix)" "$($BIN nl -l 0 -b a mix)"
# ⚠ Supported constructs must NOT trip the guard — a false refusal is a bug too.
expect_exit "-b p allows \\<"   0 "$BIN" nl -b 'p\<B' sect
expect_exit "-b p allows [\\+]" 0 "$BIN" nl -b 'p[\+]' sect

# --- 1.6.16: the counts, and the counter ------------------------------------
#
# ⛔ `-i`, `-v`, `-w` and `-l` WRAPPED past 2^64 — `-v 99999999999999999999`
# started at 7766279631452241919 — and an EMPTY value was skipped as if absent.
# ⛔ And the counter itself wrapped: `nl -v 9223372036854775807` printed that
# number and then BLANK number fields, at exit 0. GNU says *line number overflow*
# and exits 1 when the overflowed number is needed. Compared with GNU on bytes and
# exit status; where GNU says 1 for a usage error, kriya says 2 (ADR 0008).
nl_same() {   # nl_same <label> <file> <nl args...>
    _l=$1; _f=$2; shift 2
    _grc=0; nl "$@" "$_f" > nl_g.out 2>/dev/null || _grc=$?
    _krc=0; timeout 10 "$BIN" nl "$@" "$_f" > nl_k.out 2>/dev/null || _krc=$?
    if cmp -s nl_g.out nl_k.out && [ "$_grc" = "$_krc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s: GNU exit %s, kriya exit %s, output %s\n' "$_l" "$_grc" "$_krc" \
            "$(cmp -s nl_g.out nl_k.out && echo same || echo differs)" >&2
    fi
}
printf 'a\nb\nc\n' > three
printf 'a\n\\:\\:\nb\n' > reset
nl_same "-v MAX, one line"          short -v 9223372036854775807 -b n
nl_same "-v MAX overflows"          three -v 9223372036854775807
nl_same "-v MAX-1 prints two"       three -v 9223372036854775806
nl_same "-i MAX overflows"          three -i 9223372036854775807
nl_same "a new section resets it"   reset -v 9223372036854775807
nl_same "-v ' 5' (GNU's blanks)"    three -v ' 5'
nl_same "-i +2 (GNU's plus)"        three -i +2
# ⚠ GNU 9.11 saturates an oversized `-l`; 9.4 refuses it. Compared with a finite
# `-l` no blank run in the fixture reaches, which both versions take.
expect_eq "-l huge saturates"   "$(nl -l 1000000 -b a mix)" "$($BIN nl -l 99999999999999999999 -b a mix)"
expect_eq "-l 2^64+1 saturates" "$(nl -l 1000000 -b a mix)" "$($BIN nl -l 18446744073709551617 -b a mix)"
for _o in -i -v -w -l; do
    for _v in 9223372036854775808 18446744073709551617 99999999999999999999 '' 1x; do
        [ "$_o" = "-l" ] && case "$_v" in 9*|18*) continue ;; esac
        # ⚠ `timeout`: a wrapped width is a hang, and a regression must FAIL here.
        expect_exit "nl $_o '$_v' refused" 2 timeout 10 "$BIN" nl $_o "$_v" three
        _grc=0; nl $_o "$_v" three >/dev/null 2>&1 || _grc=$?
        expect_eq "...and by GNU" "yes" "$([ "$_grc" != 0 ] && echo yes || echo no)"
    done
done
expect_exit "nl -w 0 refused"          2 timeout 10 "$BIN" nl -w 0 three
expect_exit "nl -w 2147483648 refused" 2 timeout 10 "$BIN" nl -w 2147483648 three
# ⛔ A NEGATIVE -i OR -v WAS REFUSED, exit 2, until 1.6.17. GNU counts down and
# starts below zero, formatting with printf's `%*jd`: the width counts the sign
# and `rz` puts the zeros after it.
nl_same "-v -1"                          three -v -1
nl_same "-v -1 rz (sign, then zeros)"    three -v -1 -n rz -w 4
nl_same "-v -1 ln"                       three -v -1 -n ln -w 4
nl_same "-v -2 rn, the sign fills -w 2"  three -v -2 -n rn -w 2
nl_same "-i -1 counts down"              three -i -1
nl_same "-i -5 -v 3"                     three -i -5 -v 3
nl_same "-i -1 -v 0 rz"                  three -i -1 -v 0 -n rz -w 3
nl_same "-v ' -1' (blanks, then a sign)" three -v ' -1'
nl_same "-v -0 is zero"                  three -v -0 -n rz
nl_same "-v i64 min, counting up"        three -v -9223372036854775808
nl_same "-v i64 min rz"                  three -v -9223372036854775808 -n rz -w 30
# ⚠ The overflow runs BOTH ways now, and the number that fits still prints.
nl_same "-v min+1 -i -1 overflows below" three -v -9223372036854775807 -i -1
nl_same "-v min -i -1, one line"         three -v -9223372036854775808 -i -1 -n rz
nl_same "-i min from 0"                  three -i -9223372036854775808 -v 0
nl_same "-i min from -1"                 three -i -9223372036854775808 -v -1
nl_same "-i min from 1"                  three -i -9223372036854775808
nl_same "a section resets it, below"     reset -v -9223372036854775808 -i -1 -n ln -w 30
for _v in -9223372036854775809 -99999999999999999999 '- 1' +-1 -+1 -; do
    for _o in -i -v; do
        expect_exit "nl $_o '$_v' refused" 2 timeout 10 "$BIN" nl $_o "$_v" three
        _grc=0; nl $_o "$_v" three >/dev/null 2>&1 || _grc=$?
        expect_eq "...and by GNU" "yes" "$([ "$_grc" != 0 ] && echo yes || echo no)"
    done
done
# ⛔ THE PADDING WAS ONE WRITE PER BYTE: `-w 2147483647`, which GNU prints, never
# finished. A wide field is a buffer at a time now.
nl_same "-w 100000 pads in chunks"  three -w 100000
nl_same "-w 100000, unnumbered"     three -w 100000 -b n

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
