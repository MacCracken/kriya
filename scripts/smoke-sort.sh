#!/bin/sh
# smoke-sort.sh — behavioural test for `kriya sort`.
#
# Compares output and exit status against GNU `sort` for every shipped
# option: the keys, their letters and offsets, every ordering type, `-m`,
# `-c`/`-C`, the errors, and the boundary cases (empty input, no trailing
# newline, multi-file input). scripts/difffuzz-sort.py is the random half.

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

# ⚠ Every kriya call in the helpers runs under `timeout`: at 1.9.1 two mutants
# made `sort` loop for ever (a saturated `-k` count over a separator never
# stepped past, and a version compare that stopped advancing), and the suite
# sat on them. A hang has to be a failure, not a stall.
#
# Compare $BIN sort against GNU sort for the same input + args.
compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | eval "timeout 20 $BIN sort $args")
    gnu=$(printf '%s' "$input" | eval "LC_ALL=C sort $args")
    expect_eq "$name" "$gnu" "$mine"
}

# --- fixtures ---
printf "banana\napple\ncherry\ndate\n" > words
printf "10\n2\n1\n20\n3\n100\n"       > nums
printf "Banana\napple\nCherry\nDate\n" > mixed_case
printf "  hello\nworld\n  foo\n"      > with_blanks
printf "3 c\n1 a\n2 b\n5 e\n4 d\n"    > fielded
printf "a:3\nb:1\nc:2\n"              > csv

# --- default lexicographic ---
compare "default sort"      "$(cat words)"          ""
compare "stable default"    "$(printf 'b\na\nb\nc\nb\n')" ""

# --- -n numeric ---
compare "-n"                "$(cat nums)"           "-n"
compare "-n with negatives" "$(printf '5\n-3\n0\n-10\n7\n')" "-n"

# --- -r reverse ---
compare "-r"                "$(cat words)"          "-r"
compare "-rn"               "$(cat nums)"           "-r -n"

# --- -u unique ---
compare "-u"                "$(printf 'a\na\nb\nb\nc\n')" "-u"
compare "-u with sort"      "$(printf 'z\na\nb\nz\na\n')" "-u"

# --- -f case-fold ---
compare "-f"                "$(cat mixed_case)"     "-f"

# --- -b ignore leading blanks ---
compare "-b"                "$(cat with_blanks)"    "-b"

# --- -t / -k ---
compare "-t ' ' -k 2"       "$(cat fielded)"        "-t ' ' -k 2"
compare "-t ':' -k 2 -n"    "$(cat csv)"            "-t ':' -k 2 -n"

# --- combined ---
compare "-n -r -u"          "$(printf '5\n2\n5\n8\n2\n1\n')" "-n -r -u"

# --- empty input ---
compare "empty"             ""                      ""

# --- no trailing newline ---
compare "no trailing nl"    "$(printf 'b\na\nc')"   ""

# --- multi-file concat ---
printf "x\ny\nz\n" > f1
printf "a\nb\nc\n" > f2
mine=$("$BIN" sort f1 f2)
gnu=$(LC_ALL=C sort f1 f2)
expect_eq "multi-file"      "$gnu" "$mine"

# --- -c check mode ---
expect_exit "-c sorted ok"      0 sh -c "printf 'a\nb\nc\n' | '$BIN' sort -c"
expect_exit "-c unsorted fail"  1 sh -c "printf 'b\na\nc\n' | '$BIN' sort -c"
expect_exit "-c -n unsorted"    1 sh -c "printf '10\n2\n' | '$BIN' sort -c -n"

# --- -o output file ---
"$BIN" sort -o /tmp/sort_out_$$ words
expected=$(LC_ALL=C sort words)
got=$(cat /tmp/sort_out_$$)
expect_eq "-o output"       "$expected" "$got"
rm -f /tmp/sort_out_$$

# --- -z NUL terminator ---
printf 'b\0a\0c\0' > nul_input
mine=$("$BIN" sort -z < nul_input)
expected=$(printf 'a\0b\0c\0')
expect_eq "-z NUL"          "$expected" "$mine"

# --- stable: equal keys keep original order ---
printf "1 z\n2 a\n1 y\n2 b\n1 x\n" > stable_input
mine=$("$BIN" sort -k 1 -s stable_input)
gnu=$(LC_ALL=C sort -k 1 -s stable_input)
expect_eq "stable on equal keys" "$gnu" "$mine"

# --- larger input (1000 lines) ---
seq 1000 -1 1 > big_unsorted
mine=$("$BIN" sort -n big_unsorted)
gnu=$(LC_ALL=C sort -n big_unsorted)
expect_eq "1000 numeric"    "$gnu" "$mine"

# --- ⭐ -k key windows, against GNU -----------------------------------
#
# ⛔ These diverge ONLY when the start field ties, which is why five releases of
# `sort` shipped with both bugs and a comment claiming the range was "verified
# byte-identical to GNU" — the verification used `-k1,1` and `-k2,2`, where
# start == end and truncation cannot show.
#   * a bare `-k F` means field F to END OF LINE in POSIX and GNU; kriya read it
#     as `-k F,F`.
#   * `-k F1,F2` was accepted and silently truncated to F1.
# Both produced exit 0 and plausible-but-wrongly-ordered output.
printf 'a:1:z\nb:1:a\n' > keytie.txt
printf 'p q z\nr q a\n'  > keytie_ws.txt
printf 'a:9:z\nb:1:y\nc:5:x\n' > key3.txt

key_case() {   # key_case <label> <file> <sort args...>
    label=$1; file=$2; shift 2
    g=$(sort "$@" "$file" 2>/dev/null | tr '\n' ' ')
    k=$(timeout 20 "$BIN" sort "$@" "$file" 2>/dev/null | tr '\n' ' ')
    expect_eq "$label" "$g" "$k"
}
key_case "-k2 runs to end of line"        keytie.txt    -t: -k2
key_case "-k2,2 stops at field 2"         keytie.txt    -t: -k2,2
key_case "-k2,3 spans fields 2-3"         keytie.txt    -t: -k2,3
key_case "-k2 to EOL, whitespace fields"  keytie_ws.txt -k2
key_case "-k2,2 whitespace"               keytie_ws.txt -k2,2
key_case "-k2,3 whitespace"               keytie_ws.txt -k2,3
key_case "-k2 with distinct keys"         key3.txt      -t: -k2
key_case "-k1,2 range"                    key3.txt      -t: -k1,2
key_case "-k3 last field"                 key3.txt      -t: -k3
key_case "-k2 -n numeric"                 key3.txt      -t: -k2 -n
key_case "-k2 -r reverse"                 keytie.txt    -t: -k2 -r

# An inverted range is an EMPTY key, as in GNU: every line ties on it and the
# whole line decides. ⚠ Refused (exit 2) until 1.6.16.
key_case "-k3,1 is an empty key"          keytie.txt    -t: -k3,1
key_case "-k3,1 whitespace"               keytie_ws.txt -k3,1

# --- 1.6.16: the key spec, `-n`, and the last-resort comparison -------------
#
# ⭐ Every case is compared with GNU on bytes AND exit status (`gs`), through a
# file so a trailing newline and an empty output count. They were found by a
# 7,000-case differential fuzz of every flag kriya's `sort` supports; each
# block names the wrong answer it pins.
gs() {   # gs <label> <file> <sort args...>
    _l=$1; _f=$2; shift 2
    _grc=0; LC_ALL=C sort "$@" "$_f" > gs_g.out 2>/dev/null || _grc=$?
    _krc=0; timeout 20 "$BIN" sort "$@" "$_f" > gs_k.out 2>/dev/null || _krc=$?
    if cmp -s gs_g.out gs_k.out && [ "$_grc" = "$_krc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s: GNU exit %s, kriya exit %s, output %s\n' "$_l" "$_grc" "$_krc" \
            "$(cmp -s gs_g.out gs_k.out && echo same || echo differs)" >&2
    fi
}

# ⛔ `-n` PARSED EACH KEY INTO AN i64: past 2^63 a number wrapped (9223372036854775808
# sorted FIRST, as a negative) and the parse stopped at the `.`, so `-1.25` and
# `-1.5` tied and came out in the wrong order. GNU compares the digit strings.
printf '18446744073709551617\n2\n99999999999999999999\n9223372036854775808\n-18446744073709551617\n' > n_big
printf -- '-1.25\n-1.5\n1.5\n1.25\n-.5\n-0.50\n-.49\n.5\n0\n-0\n' > n_dec
printf '1e3\n2\n 5\n4\n+5\n1,000\n007\n7\n6\nabc\n-\n.\n-.\n1.10\n1.1\n1.09\n' > n_odd
for _f in n_big n_dec n_odd; do
    for _a in "-n" "-rn" "-un"; do
        # shellcheck disable=SC2086
        gs "sort $_a $_f" "$_f" $_a
    done
done

# ⛔ A FIELD INCLUDES THE BLANKS IN FRONT OF IT without `-t`, and kriya skipped
# them: `sort -k1` of ` b` and `a` put ` b` last, where a space sorts first.
printf ' b 2\na 1\n  c 3\n' > ws_lead
printf 'x  b\ny a\nz   a\n' > ws_cols
for _f in ws_lead ws_cols; do
    for _a in "-k1" "-k2" "-k1,1" "-k2,2" "-b -k2" "-k2 -r"; do
        # shellcheck disable=SC2086
        gs "sort $_a $_f" "$_f" $_a
    done
done

# ⛔ THE LAST-RESORT COMPARISON: when keys tie, GNU compares the whole lines as
# bytes, unless `-u` (equal keys are the duplicates) or `-s` (input order). kriya
# skipped it for `-n -k`, `-f` and `-b`, applied it under `-u` — so `sort -nu` of
# `1`, `01`, `1.0` printed three lines where GNU prints one — and ignored `-s`.
printf 'x b\ny a\nx a\n' > tie1
printf '1\n01\n1.0\n' > tie2
printf 'b\nB\na\nA\n' > tie3
printf ' a\na\n  a\n' > tie4
for _f in tie1 tie2 tie3 tie4; do
    for _a in "-n -k2" "-rn -k2" "-u -k2" "-nu" "-f" "-fu" "-b" "-bu" "-s -k2" "-sr -k2" "-r -f" "-u"; do
        # shellcheck disable=SC2086
        gs "sort $_a $_f" "$_f" $_a
    done
done
# `-c -u` checks STRICT order, as GNU's does: an equal pair is a disorder.
gs "sort -cu on a tie"   tie2 -cu -n
gs "sort -c on a tie"    tie2 -c -n

# ⛔ THE KEY SPEC DROPPED WHATEVER FOLLOWED THE DIGITS until 1.6.16: `sort -k2n`
# sorted field 2 as TEXT at exit 0. From then until 1.9.1 a key's own letters and
# a character offset were refused by name; now they are GNU's, and malformed
# specs are refused in GNU's words.
for _k in "0" "2,0" "-1" "2,-1" "1x" "2,1x" "" "+1" " 1" "2,+1" "99999999999999999999" \
          "2,99999999999999999999" "18446744073709551617" "1.0" "1." "1.x" "2,1." "2,1.x" \
          "1.2.3" "1,2,3" "1n,2,3" "2nx" "2,2nx" "1b.2"; do
    gs "sort -k '$_k'" key3.txt -t: -k "$_k"
done

# --- 1.9.1: every -k, character offsets, and a key's own letters -----------
#
# ⛔ A REPEATED `-k` KEPT ONLY THE LAST KEY: `sort -k2,2 -k1,1` sorted exactly as
# `sort -k1,1` and exited 0, where GNU sorts by field 2, then field 1.
printf 'b 2 x\na 1 y\nc 1 z\nb 1 w\n_ 3 q\nA 2 r\nb 2 a\n' > mk
printf 'ab:cd:9\nab:ce:10\naa:zz:9\n:b:1\nabc:d:01\n' > mkc
for _a in "-k2,2 -k1,1" "-k2,2n -k1,1r" "-k2,2 -k3,3 -k1,1" "-k3 -k1,1" "-k2,2nr -k1" \
          "-r -k2,2 -k1,1" "-k2,2 -k1,1 -u" "-k2,2 -k1,1 -s" "-k1.1,1.1 -k3" "-k1.2" "-k1.2,1.2" \
          "-k2.2,2.2 -k1" "-k1,1.0" "-k1.1,2.1" "-k2.1b,2.2" "-b -k2.2" "-k2b,2.1b" "-k1,1.5" \
          "-k3.1,3.1n" "-n -k2,2" "-n -k2b" "-n -k2,2 -k1,1" "-k2,2 -k1,1 -n" "-r -k1,1r" \
          "-k1,1 -r" "-f -k1,1" "-k1,1f -k2,2" "-u -k2,2n"; do
    # shellcheck disable=SC2086
    gs "sort $_a mk" mk $_a
done
for _a in "-k2,2 -k1,1" "-k1.2,1.2 -k3,3n" "-k3n -k2" "-k2.2" "-k1.3,2.1" "-k2,2.1 -k3" \
          "-k3,3n -k1" "-k3,3nr -k1,1r" "-k1.1,1.2 -k2.1,2.1r"; do
    # shellcheck disable=SC2086
    gs "sort -t: $_a mkc" mkc -t: $_a
done
# An end `F.C` counts C characters from the start of field F to the END OF THE
# LINE, not of the field: `-k1,1.5` of `ab cd` is `ab cd`.
printf 'ab cd\nab ca\nab\n' > endc
gs "sort -k1,1.5 runs past field 1" endc -k1,1.5
gs "sort -k1,1.2 inside field 1"    endc -k1,1.2

# --- 1.9.1: the key types ----------------------------------------------------
printf '10K\n2M\n1G\n500\n-3K\n0K\n1.5K\n-1M\n 7k\n1e3\n2.K\n0.5Q\n1R\n-0\nabc\n' > ty_h
printf 'mar\nJan\n  feb\nxyz\nDEC\nja\nmayday\n\n  Dec x\nAPRIL\n' > ty_m
printf '1.10\n1.2\n1.9\nfoo-1.0.tar.gz\nfoo-1.0a.tar.gz\n.a\n..\n.\n1~rc1\n1\n1.0~\n2a\na2\n1.02\nv1.2\nx.y\n' > ty_v
printf '1e3\n-inf\nnan\n-nan\nabc\n0x10\n2.5\n-0\n0\n1e5000\n-1e5000\n+0\n.5\n5.\nNaN(1)\n  7\n0x1p-16446\n' > ty_g
printf 'b\n_\na\nB\n^\nA\n`\n[\n]\n\\\n' > ty_f
printf 'a-b\nab\na b\n a\n\001b\nb\177\nA\n-a\n' > ty_d
for _f in ty_h ty_m ty_v ty_g ty_f ty_d; do
    for _a in "-h" "-M" "-V" "-g" "-f" "-d" "-i" "-n" "-fh" "-fV" "-dV" "-iV" "-df" "-r -h" "-u -h" \
              "-u -M" "-u -g" "-s -V" "-b -M"; do
        # shellcheck disable=SC2086
        gs "sort $_a $_f" "$_f" $_a
    done
done
# ⛔ `-f` IS NOT A NO-OP UNDER `-h`: GNU folds the key first, so `1e3` is `1E3`,
# an exa, and sorts after `2P`. Found by scripts/difffuzz-sort.py.
printf '1e3\n2P\n3k\n' > ty_fh
gs "sort -fh reads e as E"  ty_fh -fh
gs "sort -h does not"       ty_fh -h
# ⛔ `-f` FOLDED TO LOWER CASE until 1.9.1; GNU folds to upper, and the bytes
# between `Z` and `a` show it: `_` sorts after `a` under `-f`.
printf '_\na\n' > ty_fu
gs "sort -f folds to upper case" ty_fu -f

# --- 1.9.1: -R, salted from --random-source -------------------------------------
printf '0123456789abcdefXXXX' > rsrc
printf 'a\nb\nc\nd\ne\nf\ng\nh\na\nB\nA\n' > ty_r
for _a in "-R" "-R -u" "-R -r" "-k1,1R" "-fR" "-dR" "-R -k1,1" "-k2R -k1" "-R -s"; do
    # shellcheck disable=SC2086
    gs "sort $_a --random-source" ty_r $_a --random-source=rsrc
done
gs "sort -R: a short source is an error"   ty_r -R --random-source=ty_fu
gs "sort -R: /dev/null is an error"        ty_r -R --random-source=/dev/null
gs "sort -R: a missing source is an error" ty_r -R --random-source=nonexistent
gs "sort: a source without -R is unread"   ty_r --random-source=nonexistent
gs "sort: two different sources"           ty_r -R --random-source=rsrc --random-source=ty_r
gs "sort: the same source twice"           ty_r -R --random-source=rsrc --random-source=rsrc
_o1=$("$BIN" sort -R ty_r | tr '\n' ' ')
_o2=$("$BIN" sort -R ty_r | tr '\n' ' ')
_n=0
while [ "$_o1" = "$_o2" ] && [ $_n -lt 5 ]; do _o2=$("$BIN" sort -R ty_r | tr '\n' ' '); _n=$((_n + 1)); done
expect_eq "sort -R without a source is salted afresh" "differ" "$([ "$_o1" != "$_o2" ] && echo differ || echo same)"

# --- 1.9.1: incompatible letters, refused with exit 2 as GNU refuses them -------
for _a in "-nd" "-gn" "-hM" "-Vn" "-Rn" "-k1nd" "-k1,1nM" "-k1g -k2h" "-n -k1M -g"; do
    # shellcheck disable=SC2086
    gs "sort $_a" mk $_a
done
# `-d`, `-i`, `-V` and `-R` count as one between them, so these are fine.
for _a in "-dV" "-iR --random-source=rsrc" "-dR --random-source=rsrc" "-dRV --random-source=rsrc" \
          "-fn" "-bn" "-rn" "-n -k1M"; do
    # shellcheck disable=SC2086
    gs "sort $_a" mk $_a
done

# --- 1.9.1: -t ---------------------------------------------------------------------
printf 'a\000b\nb\000a\n' > nulsep
gs "sort -t '\\0'"           nulsep -t '\0' -k2
gs "sort -t ''"               mk -t ''
gs "sort -t ab"               mk -t ab
gs "sort -t a -t b"           mk -t a -t b
gs "sort -t a -t a"           mk -t a -t a

# --- 1.9.1: -m ------------------------------------------------------------------------
printf 'a\nc\ne\n' > m1
printf 'b\nc\nd\n' > m2
printf 'b\na\n'    > m3
printf 'x'         > m4
: > m5
gsa() {   # gsa <label> <sort args and files...>
    _l=$1; shift
    _grc=0; LC_ALL=C sort "$@" > gs_g.out 2>/dev/null || _grc=$?
    _krc=0; timeout 20 "$BIN" sort "$@" > gs_k.out 2>/dev/null || _krc=$?
    if cmp -s gs_g.out gs_k.out && [ "$_grc" = "$_krc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s: GNU exit %s, kriya exit %s, output %s\n' "$_l" "$_grc" "$_krc" \
            "$(cmp -s gs_g.out gs_k.out && echo same || echo differs)" >&2
    fi
}
gsa "sort -m two sorted"         -m m1 m2
gsa "sort -m -u"                 -m -u m1 m2
gsa "sort -m -r"                 -m -r m2 m1
gsa "sort -m an unsorted file"   -m m3 m2
gsa "sort -m with empty files"   -m m5 m1 m5 m2
gsa "sort -m no final newline"   -m m4 m1
gsa "sort -m one file"           -m m3
_grc=0; LC_ALL=C sort -m - m1 < m2 > gs_g.out 2>/dev/null || _grc=$?
_krc=0; "$BIN" sort -m - m1 < m2 > gs_k.out 2>/dev/null || _krc=$?
expect_eq "sort -m - FILE" "same $_grc" "$(cmp -s gs_g.out gs_k.out && echo same || echo differs) $_krc"
gsa "sort -m -k"                 -m -k1,1 -t: mkc mkc

# ⛔ FILES WERE CONCATENATED BEFORE LINES WERE SPLIT: a file without a final
# newline ran into the next file's first line, so `x` and `a` became `xa`.
gsa "sort: a file's last line ends with the file" m4 m1
gsa "sort: the same, three files"                 m4 m4 m4

# --- 1.9.1: -c, -C and --check ----------------------------------------------------
gsa "sort -C sorted"                  -C m1
gsa "sort -C unsorted"                -C m3
gsa "sort --check=quiet"              --check=quiet m3
gsa "sort --check=silent"             --check=silent m3
gsa "sort --check=q (a prefix)"       --check=q m3
gsa "sort --check=diagnose-first"     --check=diagnose-first m1
gsa "sort -c -C conflict"             -c -C m1
gsa "sort -C --check=quiet agree"     -C --check=quiet m1
gsa "sort -c two files"               -c m1 m2
gsa "sort -C two files"               -C m1 m2
gsa "sort -c -o"                      -c -o gs_x.out m1
gsa "sort -c -k2,2 -k1,1"             -c -k2,2 -k1,1 mk
gsa "sort -C -u on a tie"             -C -u -k2,2 mk
err=$("$BIN" sort -c m3 2>&1 >/dev/null || true)
expect_eq "sort -c names the line" "kriya sort: disorder at line 2" "$err"
err=$("$BIN" sort -C m3 2>&1 >/dev/null || true)
expect_eq "sort -C is silent" "" "$err"

# --- 1.9.1: --sort=WORD ---------------------------------------------------------
for _w in general-numeric human-numeric month numeric version g h m n v hum gen; do
    gsa "sort --sort=$_w" --sort=$_w ty_h
done
gsa "sort --sort=random" --sort=random --random-source=rsrc ty_r
# ⚠ GNU exits 1 for a bad `--check=` or `--sort=` word, its `argmatch` failure,
# which under `-c` is the answer "out of order". kriya keeps 2, its usage error.
for _w in "--sort=x" "--sort=" "--check=x" "--check="; do
    expect_exit "sort $_w is a usage error" 2 "$BIN" sort "$_w" m1
done

# --- 1.9.1: exit status 2 for every error, as POSIX and GNU ------------------------
#
# ⛔ A FILE THAT COULD NOT BE READ EXITED 1, which under `-c` is "not sorted".
gsa "sort a missing file"           nonexistent
gsa "sort -c a missing file"        -c nonexistent
gsa "sort -C a missing file"        -C nonexistent
gsa "sort -m a missing file"        -m m1 nonexistent
gsa "sort a directory"              .
gsa "sort -o into a directory"      -o . m1
gsa "sort -o twice"                 -o gs_y.out -o gs_z.out m1
gsa "sort -o twice, the same file"  -o gs_y.out -o gs_y.out m1
gsa "sort -o onto its own input"    -o gs_w.out gs_w.out </dev/null
"$BIN" sort m3 m1 > own_in
"$BIN" sort -o own_in own_in
expect_eq "sort -o FILE FILE sorts in place" "$(LC_ALL=C sort m3 m1)" "$(cat own_in)"

# ⚠ HUGE CHARACTER OFFSETS: 9.4 and earlier overflowed a pointer adding one and
# answered otherwise (fixed in 9.10's NEWS); kriya gives 9.7's and 9.12's answer,
# asserted rather than compared.
printf 'ab cd\nab ce\naa zz\n b\n' > hugec
expect_eq "sort -k1.SIZE_MAX" " b aa zz ab cd ab ce " \
    "$("$BIN" sort -k 1.18446744073709551615 hugec | tr '\n' ' ')"
expect_eq "sort -k1.2,1.SIZE_MAX" "aa zz  b ab cd ab ce " \
    "$("$BIN" sort -k 1.2,1.18446744073709551615 hugec | tr '\n' ' ')"
expect_eq "sort -k1.SIZE_MAX+1 saturates" " b aa zz ab cd ab ce " \
    "$("$BIN" sort -k 1.18446744073709551616 hugec | tr '\n' ' ')"

# --- 1.9.1: -z, where a newline is a blank ------------------------------------------
printf 'b\na\000a\nb\000 c\000\na\000' > zl
gsa "sort -z -k2"    -z -k2 zl
gsa "sort -z -b"     -z -b zl
gsa "sort -z -n"     -z -n zl

# --- 1.9.1: the cases the mutants asked for ------------------------------------
#
# ⚠ Each fixture below was missing until a mutant survived without it.
# A -t key's end stops AT the separator: with mixed field counts a key that
# took the separator would order `a:b:c` after `x:b`.
printf 'x:b\na:b:c\nb:b\n' > mt_sep
gs "sort -t: -k2,2 stops at the separator" mt_sep -t: -k2,2
# DEL is non-printing: `-i` drops it, and DEL sorts after every letter.
printf '\177a\nb\n' > mt_del
gs "sort -i drops DEL" mt_del -i
# `-d` implies `-i`, so an `i` never overrides a `d`, in either order.
printf 'a-c\nab\n' > mt_di
gs "sort -d -i: -d wins"  mt_di -d -i
gs "sort -i -d: -d wins"  mt_di -i -d
gs "sort -k1di: -d wins"  mt_di -k1di
# `b` after the end position is the END's: the start keeps its blanks.
printf 'a\n b\n' > mt_eb
gs "sort -k1,1b: an end b is the end's" mt_eb -k1,1b
gs "sort -k1b,1: a start b is the start's" mt_eb -k1b,1
# An inverted key is EMPTY, not negative: over unequal field widths a negative
# length would order the lines by it.
printf 'b:111:z\na:1:y\n' > mt_inv
gs "sort -t: -k3,1 over unequal fields" mt_inv -t: -k3,1
# Under -z a newline is a blank, and `-n` skips it before the number.
printf '\n5\0003\000' > mt_zn
gs "sort -z -n skips a newline" mt_zn -z -n
# `-m` gives a tie to the EARLIER file, which shows only when the tie stands, and
# again each time that file's next line goes back among the others: the first
# file needs a second line.
printf '1 y\n1 z\n' > mt_m1
printf '1 x\n' > mt_m2
gsa "sort -m -s: a tie goes to the first file" -m -s -k1,1 mt_m1 mt_m2
gsa "sort -m -u: the first file's line is kept" -m -u -k1,1 mt_m1 mt_m2

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
