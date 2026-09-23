#!/bin/sh
# smoke-sort.sh — behavioural test for `kriya sort`.
#
# Compares output cell-by-cell against GNU `sort` for every shipped
# flag combination, plus stability + the boundary cases (empty input,
# no trailing newline, very long lines, multi-file concat).

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

# Compare $BIN sort against GNU sort for the same input + args.
compare() {
    name=$1
    input=$2
    args=$3
    mine=$(printf '%s' "$input" | eval "$BIN sort $args")
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
    k=$("$BIN" sort "$@" "$file" 2>/dev/null | tr '\n' ' ')
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
    _krc=0; "$BIN" sort "$@" "$_f" > gs_k.out 2>/dev/null || _krc=$?
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

# ⛔ THE KEY SPEC DROPPED WHATEVER FOLLOWED THE DIGITS: `sort -k2n` sorted field
# 2 as TEXT at exit 0, and `-k2,2.1`, `-k 2,-1` and `-k 2,2x` lost their tails.
# Malformed specs are refused in GNU's words; what GNU accepts and kriya cannot
# honour yet — a key's own letters, a character offset — is refused by name
# (roadmap 1.8.1), never read as something else.
for _k in "0" "2,0" "-1" "2,-1" "1x" "2,1x" "" "+1" " 1" "2,+1" "99999999999999999999" \
          "2,99999999999999999999" "18446744073709551617"; do
    gs "sort -k '$_k'" key3.txt -t: -k "$_k"
done
for _k in "2n" "2,2n" "2r" "2b" "2.1" "2,2.1" "1.2,3"; do
    expect_exit "sort -k $_k refused until 1.8.1" 2 "$BIN" sort -t: -k "$_k" key3.txt
done
err=$("$BIN" sort -t: -k 2n key3.txt 2>&1 >/dev/null || true)
case "$err" in
    *"roadmap 1.8.1"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL -k2n refusal names the slot:\ngot: '%s'\n" "$err" >&2 ;;
esac
# ⭐ The one-key case has an exact spelling today: a key with no letters of its
# own takes the global ones, and the last-resort comparison ignores them.
expect_eq "-n -k2,2 is GNU's -k2,2n" "$(LC_ALL=C sort -t: -k2,2n key3.txt)" "$("$BIN" sort -t: -n -k2,2 key3.txt)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
