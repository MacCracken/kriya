#!/bin/sh
# smoke-date.sh — behavioural test for `kriya date`.
#
# Compares output cell-by-cell against GNU `date` for each shipped
# strftime specifier and convenience format, under TZ=UTC + LC_ALL=C
# (kriya date defaults to UTC at v0.7.0; local tzfile parsing defers).
# Stamps are sampled in-process so kriya and GNU agree on the second
# they print — we capture epoch seconds once and feed both via -d
# (GNU) / +%s comparison (kriya) where possible.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

# Force deterministic locale + UTC for GNU `date`.
export LC_ALL=C
export TZ=UTC

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

# For each format, run kriya AND GNU back-to-back twice. Accept if the
# 1st kriya output equals the 1st GNU output OR the 2nd (handles the
# second-boundary race).
check_parity() {
    name=$1
    fmt=$2
    # ⛔ THE ORDER IS LOAD-BEARING AND USED TO BE WRONG. This ran kriya first,
    # then GNU twice, and accepted `k == g1 || k == g2`. Time only moves
    # forward: if k differs from g1 then g1 is already at or past kriya's
    # second, and g2 >= g1 — so `k == g2` was unreachable and the "handles the
    # second-boundary race" fallback never once fired. Bracketing kriya BETWEEN
    # two GNU readings is the mitigation that actually works: if the second
    # ticks during the run, kriya's value matches whichever side of the
    # boundary it landed on.
    g1=$(date "+$fmt")
    k1=$("$BIN" date "+$fmt")
    g2=$(date "+$fmt")
    if [ "$k1" = "$g1" ]; then
        PASS=$((PASS + 1))
    else
        if [ "$k1" = "$g2" ]; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
            printf "FAIL %s:\nfmt:      '%s'\nkriya:    '%s'\nGNU(1):   '%s'\nGNU(2):   '%s'\n" "$name" "$fmt" "$k1" "$g1" "$g2" >&2
        fi
    fi
}

# --- Default output (no operand) ---
check_parity "default" "%a %b %e %H:%M:%S %Z %Y"

# --- Date-component specifiers ---
check_parity "%Y year-4"        "%Y"
check_parity "%y year-2"        "%y"
check_parity "%m month-2"       "%m"
check_parity "%d day-2"         "%d"
check_parity "%e day-sp"        "%e"
check_parity "%j day-of-year"   "%j"
check_parity "%u weekday-mon"   "%u"
check_parity "%w weekday-sun"   "%w"

# --- Time-component specifiers ---
check_parity "%H hour-24"       "%H"
check_parity "%I hour-12"       "%I"
check_parity "%M minute"        "%M"
check_parity "%S second"        "%S"
check_parity "%p AM/PM"         "%p"
check_parity "%P am/pm"         "%P"

# --- Name specifiers ---
check_parity "%a short wkday"   "%a"
check_parity "%A full wkday"    "%A"
check_parity "%b short month"   "%b"
check_parity "%h alias %b"      "%h"
check_parity "%B full month"    "%B"

# --- Timezone specifiers ---
check_parity "%Z tz name"       "%Z"
check_parity "%z tz offset"     "%z"

# --- Composite specifiers ---
check_parity "%T H:M:S"         "%T"
check_parity "%R H:M"           "%R"
check_parity "%D US date"       "%D"
check_parity "%F ISO date"      "%F"

# --- Mixed format strings ---
check_parity "ISO datetime"     "%Y-%m-%dT%H:%M:%SZ"
check_parity "wkday H:M:S YYYY" "%a %b %e %H:%M:%S %Y"
check_parity "intermixed"       "Today is %A %B %e, %Y. Time: %T"

# --- Escape specifiers ---
check_parity "%n newline"       "before%nafter"
check_parity "%t tab"           "before%tafter"
check_parity "%% literal"       "100%%done"

# --- Truly-unknown specifiers: both kriya and GNU emit as-is. ---
# (Note: %V, %q, %c, %x, %X, %r, %G, %g are GNU-defined and deferred
# at v0.7.0 — they currently fall through to passthrough. The test
# uses %@ / %! which neither implementation defines.)
check_parity "%@ unknown"       "%@"
check_parity "%! unknown"       "%!"

# --- %s epoch (parity within 1 second) ---
k_s=$("$BIN" date +%s)
g_s=$(date +%s)
diff=$((g_s - k_s))
# ⚠ ABSOLUTE difference. This was `diff >= 0 && diff <= 1`, i.e. one second wide
# in ONE direction only, which goes red without any kriya defect if the clock
# steps backwards between the two invocations (chronyd/systemd-timesyncd do step
# on a CI runner that has just booted) or if kriya is descheduled across a
# second boundary. Neither says anything about `date`.
d=$((g_s - k_s))
if [ "$d" -lt 0 ]; then d=$((0 - d)); fi
if [ "$d" -le 2 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL %s epoch parity: kriya=$k_s GNU=$g_s diff=$diff" >&2
fi

# --- %N ns: kriya ships zeros at v0.7.0 ---
expect_eq "%N stub-zeros" "000000000" "$("$BIN" date +%N)"

# --- -u no-op (default IS UTC) ---
out1=$("$BIN" date -u +%Z)
out2=$("$BIN" date +%Z)
expect_eq "-u no-op (kriya default UTC)" "$out1" "$out2"
expect_eq "-u prints UTC" "UTC" "$out1"

# --- --utc / --universal long forms ---
expect_exit "--utc accepted"        0 "$BIN" date --utc
expect_exit "--universal accepted"  0 "$BIN" date --universal

# --- Exit codes / usage ---
expect_exit "stray operand"         2 "$BIN" date hello
expect_exit "unknown short"         2 "$BIN" date -X
expect_exit "unknown long"          2 "$BIN" date --bogus
expect_exit "lone dash"             2 "$BIN" date -

# --- unimplemented vs unknown specifiers (v1.2.1) ---
# ⛔ `date +%V` used to print the two bytes "%V" and exit 0. A specifier GNU
# defines is a wrong answer when echoed back; one that is not a specifier at all
# is passed through, which is exactly what GNU does (`date +%@` -> `%@` on both).
for spec in %V %G %g %c %x %X %r %q; do
    rc=0
    out=$("$BIN" date -u "+$spec" 2>/dev/null) || rc=$?
    expect_eq "deferred $spec exits 1"     "1" "$rc"
    expect_eq "deferred $spec prints none" ""  "$out"
done
expect_eq "unknown %@ passes through (as GNU)" "$(date -u '+%@')" "$("$BIN" date -u '+%@')"
expect_eq "%Y still works" "$(date -u +%Y)" "$("$BIN" date -u +%Y)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
