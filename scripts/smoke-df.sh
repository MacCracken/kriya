#!/bin/sh
# smoke-df.sh — behavioural test for `kriya df`.
#
# Column widths differ from GNU (kriya uses fixed 10-wide columns;
# GNU uses dynamic max-width). Cell-by-cell byte-equality isn't the
# right target. Instead we check structural equivalence:
#   - The SAME set of mount points is shown under each flag
#   - Numeric values match GNU's for a specific filesystem
#   - Headers carry the right column names
#   - `-h` produces human suffixes (K/M/G/T)
#   - `-T` adds Type column; `-i` switches to inode columns
#   - Operand-filter narrows output to a single row

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

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

# Sorted set of mount points under matching flags.
mount_set_check() {
    name=$1
    shift
    k=$("$BIN" df "$@" | tail -n +2 | awk '{print $NF}' | sort -u)
    g=$(df "$@" | tail -n +2 | awk '{print $NF}' | sort -u)
    expect_eq "$name" "$g" "$k"
}

# --- Default mount-point set matches GNU ---
mount_set_check "default mount set"

# --- -a shows more mounts than default (includes pseudo-FS) ---
n_default=$("$BIN" df | tail -n +2 | wc -l)
n_all=$("$BIN" df -a | tail -n +2 | wc -l)
if [ "$n_all" -gt "$n_default" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL -a should include MORE rows: default=$n_default -a=$n_all" >&2
fi

# --- -h size formatting includes a K/M/G/T suffix on at least one row ---
human_out=$("$BIN" df -h | tail -n +2 | awk '{print $2}')
if echo "$human_out" | grep -Eq '[0-9](\.[0-9])?[KMGT]'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL -h should produce K/M/G/T suffixes; got: $human_out" >&2
fi

# --- -T adds a Type column ---
hdr=$("$BIN" df -T | head -1)
case "$hdr" in
    *Type*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL -T header: $hdr" >&2 ;;
esac

# --- -i switches to inode columns ---
hdr_i=$("$BIN" df -i | head -1)
case "$hdr_i" in
    *Inodes*IUsed*IFree*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL -i header: $hdr_i" >&2 ;;
esac

# --- Operand filter: shows ONLY the requested mount (matched by mp).
#     v0.7.0 caveat: filter is exact-mp-match, not stat-dev-walk.
nrows=$("$BIN" df /home | tail -n +2 | wc -l)
expect_eq "df /home one row" "1" "$nrows"

# --- Numeric parity: for /home, kriya's 1K-blocks / Used / Available
#     match GNU's exactly. ---
k_vals=$("$BIN" df /home | tail -n +2 | awk '{print $2, $3, $4}')
g_vals=$(df /home | tail -n +2 | awk '{print $2, $3, $4}')
expect_eq "df /home numbers match GNU" "$g_vals" "$k_vals"

# --- Headers under different flags ---
hdr_default=$("$BIN" df | head -1)
case "$hdr_default" in
    *Filesystem*1K-blocks*Used*Available*Use%*Mounted*on*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL default header: $hdr_default" >&2 ;;
esac

hdr_human=$("$BIN" df -h | head -1)
case "$hdr_human" in
    *Filesystem*Size*Used*Avail*Use%*Mounted*on*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL -h header: $hdr_human" >&2 ;;
esac

# --- Long-form options ---
hdr_long=$("$BIN" df --human-readable --print-type | head -1)
case "$hdr_long" in
    *Filesystem*Type*Size*Used*Avail*Use%*Mounted*on*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL --human-readable --print-type header: $hdr_long" >&2 ;;
esac

# --- Exit codes ---
expect_exit "df exit 0"             0 "$BIN" df
expect_exit "df -h exit 0"          0 "$BIN" df -h
expect_exit "df unknown short"      2 "$BIN" df -Z
expect_exit "df unknown long"       2 "$BIN" df --bogus

# --- Multi-operand: each operand listed (or stays empty when no match) ---
nrows_multi=$("$BIN" df / /home | tail -n +2 | wc -l)
# Each operand path that maps to a mount point yields a row.
if [ "$nrows_multi" -ge 1 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL df / /home should yield >=1 row; got $nrows_multi" >&2
fi

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
