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
expect_exit "-l 0 refused"      2 "$BIN" nl -l 0 sect
# ⚠ Supported constructs must NOT trip the guard — a false refusal is a bug too.
expect_exit "-b p allows \\<"   0 "$BIN" nl -b 'p\<B' sect
expect_exit "-b p allows [\\+]" 0 "$BIN" nl -b 'p[\+]' sect

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
