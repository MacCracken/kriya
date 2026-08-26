#!/bin/sh
# smoke-cut.sh — behavioural test for `kriya cut`.
#
# Compares output cell-by-cell against GNU `cut` for every shipped
# mode (-b/-c/-f) + LIST grammar form (N, N-, -M, N-M, N,M, mixed).

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

# Compare $BIN cut against GNU cut for the same args+input.
compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | eval "$BIN cut $args")
    gnu=$(printf '%s' "$input" | eval "cut $args")
    expect_eq "$name" "$gnu" "$mine"
}

# --- fixtures ---
printf "a,b,c,d,e\nf,g,h,i,j\nk,l,m,n,o\n" > csv
printf "abcdef\nghijkl\n123456\n"           > raw
printf "a:b:c\nnocolon\nd:e:f\n"            > mixed
printf "field1\tfield2\tfield3\n"           > tabs

# --- -f field mode ---
compare "-f 1 -d ,"           "$(cat csv)"   "-f 1 -d ','"
compare "-f 2 -d ,"           "$(cat csv)"   "-f 2 -d ','"
compare "-f 1,3 -d ,"         "$(cat csv)"   "-f 1,3 -d ','"
compare "-f 1-3 -d ,"         "$(cat csv)"   "-f 1-3 -d ','"
compare "-f 3- -d ,"          "$(cat csv)"   "-f 3- -d ','"
compare "-f -3 -d ,"          "$(cat csv)"   "-f -3 -d ','"
compare "-f 1,3,5 -d ,"       "$(cat csv)"   "-f 1,3,5 -d ','"
compare "-f 2-4 -d ,"         "$(cat csv)"   "-f 2-4 -d ','"
compare "-f 99 -d ,"          "$(cat csv)"   "-f 99 -d ','"

# --- default TAB delimiter ---
compare "-f 2 default delim"  "$(cat tabs)"  "-f 2"

# --- -s only-delimited ---
compare "-f 1 -s with no-delim line" "$(cat mixed)" "-f 1 -d ':' -s"
compare "-f 1 default (no -s)"       "$(cat mixed)" "-f 1 -d ':'"

# --- -b byte mode ---
compare "-b 1 raw"            "$(cat raw)"   "-b 1"
compare "-b 1-3 raw"          "$(cat raw)"   "-b 1-3"
compare "-b 3- raw"           "$(cat raw)"   "-b 3-"
compare "-b -3 raw"           "$(cat raw)"   "-b -3"
compare "-b 1,3,5 raw"        "$(cat raw)"   "-b 1,3,5"

# --- -c char mode (ASCII-only — same as -b for our smoke) ---
compare "-c 1-3 raw"          "$(cat raw)"   "-c 1-3"
compare "-c 2-4 raw"          "$(cat raw)"   "-c 2-4"

# --- --complement ---
compare "-f --complement"     "$(cat csv)"   "-f 1 -d ',' --complement"
compare "-c --complement"     "$(cat raw)"   "-c 1-3 --complement"

# --- --output-delimiter ---
compare "-f w/ output-delim"  "$(cat csv)"   "-f 1,3,5 -d ',' --output-delimiter='|'"

# --- stdin ---
compare "stdin -f"            "$(cat csv)"   "-f 2 -d ','"

# --- empty / partial inputs ---
compare "empty input"         ""             "-f 1 -d ','"
compare "single line"         "a,b,c"        "-f 2 -d ','"
compare "no trailing newline" "a,b,c"        "-f 1 -d ','"

# --- errors ---
expect_exit "no mode"         2 "$BIN" cut /dev/null
expect_exit "two modes"       2 "$BIN" cut -c 1 -f 1 /dev/null
expect_exit "-s without -f"   2 "$BIN" cut -c 1 -s /dev/null
expect_exit "multibyte delim" 2 "$BIN" cut -f 1 -d ',,' /dev/null
expect_exit "missing file"    1 "$BIN" cut -f 1 ghost_file

# --- ⭐ -c counts CODEPOINTS, -b counts bytes ---------------------------
#
# ⛔ These shared one emitter until 1.4.2, so `-c` was byte-based and
# `cut -c2` on `aébc` returned the LEAD BYTE of é — a broken UTF-8 sequence
# rather than a character. That is the whole difference the two flags exist to
# express.
#
# ⚠ The oracle is GNU under LC_ALL=C.UTF-8. Under LC_ALL=C GNU's `-c` collapses
# to `-b`, and kriya has no locale to switch on — it decodes UTF-8
# unconditionally, exactly as `wc -m` already does.
printf 'aébc\n'        > mb.txt
printf 'a\377bc\n'     > mbbad.txt
printf 'ae\314\201b\n' > mbcomb.txt
printf '日本語x\n'      > mbcjk.txt
printf 'x\300\200y\n'         > mbover2.txt
printf 'x\340\200\200y\n'     > mbover3.txt
printf 'x\355\240\200y\n'     > mbsurr.txt
printf 'x\364\220\200\200y\n' > mbrange.txt
printf 'x\370\200\200\200\200y\n' > mbfive.txt
printf 'x\346\227y\n'         > mbtrunc.txt

# ⛔ GNU IS ONLY AN ORACLE HERE IF IT CAN COUNT CHARACTERS AT ALL. `cut -c`
# gained multibyte support in coreutils 9.5; 9.4 — which Ubuntu 24.04 ships, and
# which CI runs — is byte-based no matter the locale, and an unavailable locale
# degrades to the same thing silently. This suite went red on CI for exactly
# that reason while being correct locally: the same shape as the `find -exec`
# argv[0] incident, where the LOCAL GNU's version decided whether a test passed.
#
# ⭐ So the oracle is PROBED, not assumed — and, more importantly, kriya's
# behaviour is asserted against POSIX rather than against whichever GNU is
# installed. POSIX says `-c` selects CHARACTERS; that is a specification, and
# `cut -c2` on `aébc` must yield the two-byte é on every host. The absolute
# assertions below therefore keep their teeth on an old-GNU runner, and the
# GNU comparison is an extra check where it can be had.
MB_ORACLE=no
if [ "$(printf 'aé\n' | LC_ALL=C.UTF-8 cut -c2 2>/dev/null | od -An -tx1 | tr -d ' ')" = "c3a90a" ]; then
    MB_ORACLE=yes
fi
[ "$MB_ORACLE" = "yes" ] || echo "note: this GNU cut is byte-based (pre-9.5 or no UTF-8 locale) — comparing kriya against POSIX only"

# Assert kriya's own bytes, always. `want` is an `od -An -tx1` hex string.
mb_is() {
    label=$1; want=$2; shift 2
    got=$("$BIN" cut "$@" 2>&1 | od -An -tx1 | tr -s ' ' | sed 's/^ //;s/ $//')
    expect_eq "multibyte: $label" "$want" "$got"
}

# Compare against GNU too, but only where GNU can actually do the job.
mb_same() {
    label=$1; shift
    [ "$MB_ORACLE" = "yes" ] || return 0
    g=$(LC_ALL=C.UTF-8 cut "$@" 2>&1 | od -An -c) || true
    k=$("$BIN" cut "$@" 2>&1 | od -An -c) || true
    expect_eq "multibyte vs GNU: $label" "$g" "$k"
}
# ⭐ POSIX absolutes — these hold on ANY host, old GNU or none at all.
mb_is "-c2 is the whole é"        "61 c3 a9 62 63 0a" -c1-5 mb.txt
mb_is "-c2 alone"                 "c3 a9 0a"          -c2 mb.txt
mb_is "-b2 is one byte"           "c3 0a"             -b2 mb.txt
mb_is "-c1,3 skips the é"         "61 62 0a"          -c1,3 mb.txt
mb_is "-c CJK second char"        "e6 9c ac 0a"       -c2 mbcjk.txt
mb_is "-c invalid byte passes"    "ff 0a"             -c2 mbbad.txt
mb_is "-c combining mark alone"   "cc 81 0a"          -c3 mbcomb.txt
mb_is "-c overlong is 2 chars"    "c0 0a"             -c2 mbover2.txt
mb_is "-c surrogate is 3 chars"   "ed 0a"             -c2 mbsurr.txt

mb_same "-c2 takes the whole é"   -c2 mb.txt
mb_same "-b2 still takes a byte"  -b2 mb.txt
mb_same "-c1-2 range"             -c1-2 mb.txt
mb_same "-c2- open range"         -c2- mb.txt
mb_same "-c-2 open start"         -c-2 mb.txt
mb_same "-c1,3 list"              -c1,3 mb.txt
mb_same "-c CJK 3-byte"           -c2 mbcjk.txt
mb_same "-c CJK range"            -c1-3 mbcjk.txt
mb_same "--complement -c2"        --complement -c2 mb.txt
# ⚠ An invalid byte counts as ONE character and passes through UNCHANGED —
# `cut` selects text, it does not repair it. Never the decoder's U+FFFD.
mb_same "-c over an invalid byte" -c2 mbbad.txt
mb_same "-c range spanning it"    -c1-3 mbbad.txt
# ⛔ CODEPOINTS, NOT GRAPHEME CLUSTERS: for a + e + U+0301 + b, GNU puts the
# combining acute at position 3 in its own right.
mb_same "-c combining mark alone" -c3 mbcomb.txt
mb_same "-c after a combiner"     -c4 mbcomb.txt

# ⛔ MALFORMED-BUT-WELL-SHAPED sequences. The stdlib decoder checks
# continuation-byte SHAPE only and never range-checks the codepoint, so it
# accepted three families GNU rejects — overlong forms, UTF-16 surrogates, and
# values above U+10FFFF. `cut -c2` on `x\xC0\x80y` emitted TWO bytes here and
# one under GNU, because kriya had counted the pair as a single character.
# ⚠ These sequences are structurally valid UTF-8; only their VALUE is illegal,
# which is why shape-checking alone let them through and why a fixture of
# ordinary text can never catch it.
mb_same "overlong 2-byte C0 80"   -c2 mbover2.txt
mb_same "overlong 3-byte E0 80"   -c2 mbover3.txt
mb_same "UTF-16 surrogate ED A0"  -c2 mbsurr.txt
mb_same "above U+10FFFF F4 90"    -c2 mbrange.txt
mb_same "5-byte lead F8"          -c2 mbfive.txt
mb_same "truncated 3-byte"        -c2 mbtrunc.txt
mb_same "range over a bad seq"    -c1-3 mbsurr.txt

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
