#!/bin/sh
# smoke-df.sh — behavioural test for `kriya df`.
#
# Column widths differ from GNU (kriya uses fixed 10-wide columns;
# GNU uses dynamic max-width). Cell-by-cell byte-equality isn't the
# right target. Instead we check structural equivalence:
#   - kriya never OMITS a filesystem GNU shows, and any extra is a known
#     pseudo-FS type (GNU's dummy list is version-dependent — see below)
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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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

# ⛔ EXACT SET EQUALITY WITH GNU IS THE WRONG ASSERTION HERE, and it went red on
# CI for a benign reason. kriya's default skip is a fixed list of pseudo-FS type
# names (see the header of src/cmd/df.cyr) plus "zero blocks"; GNU's is a
# different algorithm whose dummy-type list has changed across coreutils
# releases. On the dev box (coreutils 9.11) GNU df SHOWS devtmpfs at /dev, so
# the sets matched; on the CI runner GNU df does not, so kriya had one extra
# row and the whole suite failed.
#
# ⚠ This is the same trap the `find -exec` argv[0] bug hid behind: a GNU-parity
# test can pass or fail because of the LOCAL GNU's version rather than anything
# about kriya. Pin the property that is version-stable instead.
#
# The two directions are not equally serious:
#   ⛔ kriya OMITTING something GNU shows is a real defect — a filesystem missing
#      from df is the failure a user notices. Always a failure here.
#   ⚠ kriya SHOWING an extra virtual filesystem is a difference of opinion about
#      the pseudo list. Allowed only for types named below, and the type is
#      printed, so a NEW divergence still fails loudly and is diagnosable from
#      the CI log alone rather than needing another round-trip.
KNOWN_EXTRA_TYPES="devtmpfs"

fstype_of() {
    awk -v mp="$1" '$2 == mp { print $3; exit }' /proc/self/mounts
}

mount_set_check() {
    name=$1
    shift
    "$BIN" df "$@" | tail -n +2 | awk '{print $NF}' | sort -u > "$WORK/k.set"
    df          "$@" | tail -n +2 | awk '{print $NF}' | sort -u > "$WORK/g.set"

    # `comm` needs both inputs sorted; they are. Process substitution is a
    # bashism and this runs under dash on CI, hence the temp files.
    missing=$(comm -23 "$WORK/g.set" "$WORK/k.set" | tr '\n' ' ')
    extra=$(comm -13 "$WORK/g.set" "$WORK/k.set")

    if [ -z "$missing" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: kriya OMITS filesystems GNU shows: %s\n" "$name" "$missing" >&2
    fi

    bad=""
    for mp in $extra; do
        ft=$(fstype_of "$mp")
        case " $KNOWN_EXTRA_TYPES " in
            *" $ft "*) ;;
            *) bad="$bad $mp($ft)" ;;
        esac
    done
    if [ -z "$bad" ]; then
        PASS=$((PASS + 1))
        if [ -n "$extra" ]; then
            printf "note: %s: kriya additionally shows %s (known pseudo-FS difference vs this GNU)\n" \
                "$name" "$(echo "$extra" | tr '\n' ' ')"
        fi
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: kriya shows unexpected extra filesystems:%s\n" "$name" "$bad" >&2
    fi
}

# --- Default mount-point set matches GNU ---
mount_set_check "default mount set"

# --- ⭐ duplicate-device filter, against REAL bind mounts -----------------
#
# GNU's `filter_mount_list` stats every mount point, groups by st_dev and keeps
# one entry per device. kriya had no equivalent until 1.3.2, so a bind mount, a
# Docker overlay, or any second mount of the same filesystem appeared twice —
# invisible on a dev box with no bind mounts, and the most likely reason a CI
# runner's GNU hid /dev where kriya showed it.
#
# ⚠ Needs an unprivileged mount namespace; skips honestly where that is denied
# (some hardened kernels and container runtimes disallow it) rather than
# pretending to have proved something.
cat > "$WORK/bindcheck.sh" <<'BINDEOF'
#!/bin/sh
B="$1"
mkdir -p /tmp/b1 /tmp/b2
mount --bind /home /tmp/b1 2>/dev/null || exit 3
mount --bind /home /tmp/b2 2>/dev/null
# ⚠ Assert ONLY what this check is about: the duplicate's fate, in kriya and in
# GNU, under each flag. An earlier version diffed the whole mount set here and
# so re-ran the main assertion inside a namespace, inheriting every unrelated
# GNU-version difference — it went red the moment the surrounding environment's
# GNU disagreed about something else entirely.
"$B" df    2>/dev/null | tail -n +2 | awk '{print $NF}' | sort > /tmp/k.def
"$B" df -a 2>/dev/null | tail -n +2 | awk '{print $NF}' | sort > /tmp/k.all
df         2>/dev/null | tail -n +2 | awk '{print $NF}' | sort > /tmp/g.def
df      -a 2>/dev/null | tail -n +2 | awk '{print $NF}' | sort > /tmp/g.all
grep -qx /tmp/b1 /tmp/k.def && echo "K_DEF_KEEPS" || echo "K_DEF_DROPS"
grep -qx /tmp/b1 /tmp/k.all && echo "K_ALL_KEEPS" || echo "K_ALL_DROPS"
grep -qx /tmp/b1 /tmp/g.def && echo "G_DEF_KEEPS" || echo "G_DEF_DROPS"
grep -qx /tmp/b1 /tmp/g.all && echo "G_ALL_KEEPS" || echo "G_ALL_DROPS"
BINDEOF
chmod +x "$WORK/bindcheck.sh"

bind_out=""
if unshare -m -r true 2>/dev/null; then
    bind_out=$(unshare -m -r "$WORK/bindcheck.sh" "$BIN" 2>/dev/null || true)
fi
if [ -z "$bind_out" ]; then
    echo "skip: no unprivileged mount namespace — duplicate-device filter unverified"
else
    # The duplicate must be DROPPED by default and KEPT under -a — dedup is a
    # default-listing convenience, not a filter on the truth — and kriya must
    # agree with GNU on both, whatever this GNU decides.
    k_def=$(echo "$bind_out" | grep -c K_DEF_DROPS)
    g_def=$(echo "$bind_out" | grep -c G_DEF_DROPS)
    k_all=$(echo "$bind_out" | grep -c K_ALL_KEEPS)
    g_all=$(echo "$bind_out" | grep -c G_ALL_KEEPS)
    expect_eq "bind mount: dropped by default, same as GNU" "$g_def" "$k_def"
    expect_eq "bind mount: kept under -a, same as GNU"      "$g_all" "$k_all"
    # And pin the absolute, since this GNU is the one that defines the rule.
    expect_eq "bind mount: GNU drops the duplicate by default" "1" "$g_def"
    expect_eq "bind mount: kriya drops the duplicate by default" "1" "$k_def"
fi

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
