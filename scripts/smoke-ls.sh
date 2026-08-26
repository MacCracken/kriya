#!/bin/sh
# smoke-ls.sh — behavioural test for `kriya ls`.
#
# Covers the M3-shipped surface: default listing, -a/-A hidden file
# semantics, -l columns, -h human sizes, -r reverse sort, -F type
# suffix, -i inode, -d list-directory-as-entry, -R recursive, and
# multi-operand mixed-file-and-directory layout.

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
        printf "FAIL %s: expected '%s', got '%s'\n" "$1" "$2" "$3" >&2
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

expect_match() {
    if echo "$3" | grep -q -- "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: pattern '%s' not in output:\n%s\n" "$1" "$2" "$3" >&2
    fi
}

# --- fixture ---
echo abc > regfile
mkdir sub
echo deeper > sub/inside
ln -s regfile mylink
mkdir .hiddendir
echo h > .hidden
chmod 0644 regfile
chmod 0755 sub

# --- default: alphabetical, no hidden ---
out=$("$BIN" ls)
expected="mylink
regfile
sub"
expect_eq "default sort"          "$expected" "$out"

# --- -a includes . .. and .hidden* ---
out=$("$BIN" ls -a)
expect_match "-a includes ."        "^\.\$"          "$out"
expect_match "-a includes .."       "^\.\.\$"        "$out"
expect_match "-a includes .hidden"  "^\.hidden\$"    "$out"
expect_match "-a includes .hiddendir" "^\.hiddendir\$" "$out"

# --- -A includes dotfiles but NOT . / .. ---
out=$("$BIN" ls -A)
if echo "$out" | grep -qE "^\.\$"; then FAIL=$((FAIL + 1)); echo "FAIL -A leaked ." >&2; else PASS=$((PASS + 1)); fi
if echo "$out" | grep -qE "^\.\.\$"; then FAIL=$((FAIL + 1)); echo "FAIL -A leaked .." >&2; else PASS=$((PASS + 1)); fi
expect_match "-A includes .hidden"  "^\.hidden\$" "$out"

# --- -r reverse ---
out=$("$BIN" ls -r)
expected="sub
regfile
mylink"
expect_eq "-r reverse"            "$expected" "$out"

# --- -F type indicators ---
out=$("$BIN" ls -F)
expect_match "-F dir suffix"       "^sub/\$"      "$out"
expect_match "-F symlink suffix"   "^mylink@\$"   "$out"
# regfile has no exec bit → no suffix.
expect_match "-F regfile bare"     "^regfile\$"   "$out"

# Add an executable file → '*' suffix.
cat > script <<'EOF'
#!/bin/sh
echo hi
EOF
chmod 0755 script
out=$("$BIN" ls -F)
expect_match "-F exec suffix"      "^script\*\$"  "$out"
rm script

# --- -i inode column present and numeric ---
out=$("$BIN" ls -i regfile | awk '{print NF}')
expect_eq "-i adds 1 column"      "2" "$out"

# --- -l columns: 7 fields (mode nlink uid gid size DATE TIME name) ---
line=$("$BIN" ls -l regfile)
nf=$(echo "$line" | awk '{print NF}')
expect_eq "-l 8 columns (incl date+time)"  "8" "$nf"
# Date in YYYY-MM-DD form: field 6.
date_field=$(echo "$line" | awk '{print $6}')
case "$date_field" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL -l date format: $date_field" >&2 ;;
esac
# Symbolic mode column 1: starts with '-' for regfile.
mode_field=$(echo "$line" | awk '{print $1}')
case "$mode_field" in
    -*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL -l mode prefix: $mode_field" >&2 ;;
esac

# --- -l on symlink shows ' -> target' ---
line=$("$BIN" ls -l mylink)
expect_match "-l symlink target" "mylink -> regfile" "$line"

# --- -l -h human sizes ---
# Create files of known size and verify the suffix shape.
dd if=/dev/zero of=onek.bin   bs=1024 count=1   status=none
dd if=/dev/zero of=fivek.bin  bs=1024 count=5   status=none
dd if=/dev/zero of=meg.bin    bs=1024 count=1500 status=none

# 1024 bytes → "1.0K"
sz=$("$BIN" ls -l -h onek.bin | awk '{print $5}')
expect_eq "-h 1024B"              "1.0K" "$sz"
# 5120 bytes → "5.0K"
sz=$("$BIN" ls -l -h fivek.bin | awk '{print $5}')
expect_eq "-h 5120B"              "5.0K" "$sz"
# 1500K (~1.46 MiB) → "1.4M" (smart-rounded one decimal)
sz=$("$BIN" ls -l -h meg.bin | awk '{print $5}')
expect_eq "-h ~1.5MiB"            "1.4M" "$sz"
# Under 1024 bytes: bare decimal (no suffix).
real_size=$(stat -c %s regfile)
sz=$("$BIN" ls -l -h regfile | awk '{print $5}')
expect_eq "-h <1024 bare"         "$real_size" "$sz"

# --- -d: list directory operand as entry, not contents ---
out=$("$BIN" ls -d sub)
expect_eq "-d sub"                "sub" "$out"
out=$("$BIN" ls -d . sub)
expected=".
sub"
expect_eq "-d . sub"              "$expected" "$out"

# --- -R recursive ---
out=$("$BIN" ls -R 2>&1)
expect_match "-R contains sub entry"  "^sub" "$out"
expect_match "-R section header"      "^\./sub:" "$out"
expect_match "-R contains inside"     "^inside" "$out"

# -R doesn't follow symlinks into directories.
mkdir realdir
echo "should-not-be-walked-via-symlink" > realdir/target_only
ln -s realdir symdir
out=$("$BIN" ls -R 2>&1)
# realdir should appear as a section
expect_match "-R realdir section"    "^\./realdir:" "$out"
# symdir section should NOT appear (we don't descend through symlinks)
if echo "$out" | grep -qE "^\./symdir:"; then
    FAIL=$((FAIL + 1)); echo "FAIL -R descended into symlink" >&2
else
    PASS=$((PASS + 1))
fi

# --- multi-operand: non-dir entries first, then each dir section ---
out=$("$BIN" ls regfile sub 2>&1)
# regfile printed as a bare entry first; sub as a section header.
expect_match "multi: regfile first"  "^regfile\$" "$out"
expect_match "multi: sub: header"    "^sub:" "$out"
expect_match "multi: sub contents"   "^inside\$" "$out"

# --- errors ---
expect_exit "missing operand"     1 "$BIN" ls ghost_file
expect_exit "no args ok"          0 "$BIN" ls

# Partial-failure: one good, one missing — exit 1, good one printed.
rc=0
out=$("$BIN" ls regfile ghost 2>/dev/null) || rc=$?
expect_eq "partial rc"            "1" "$rc"
expect_match "partial preserves"  "^regfile\$" "$out"

# --- an unstattable entry is `?`, not a fabrication (M17g, v1.2.6) ------
# ⛔ `ls -l` discarded `fs_stat_entry`'s return and rendered the all-zero buffer:
# `---------- 0 0 0 0 1970-01-01 00:00`, exit 0 — a symlink shown as a regular
# file, an epoch-zero date, every field a plausible-looking lie. Reproduced in a
# readable-but-not-searchable directory, where every per-entry stat fails EACCES.
mkdir -p unstat
touch unstat/afile
ln -s /tmp unstat/alink
mkdir unstat/adir
chmod 444 unstat

# ⚠ `|| true` on the capturing assignments is load-bearing under `set -e`: this
# invocation is EXPECTED to exit 1, and a bare assignment would abort the script
# there — before the chmod below, leaving the trap unable to clean up.
# ⛔ ROOT BYPASSES DAC. Mode 444 makes a directory readable-but-not-searchable,
# which is what makes every per-entry stat fail EACCES — but uid 0 holds
# CAP_DAC_READ_SEARCH, so as root every stat SUCCEEDS, `ls -l` exits 0, and the
# five assertions below invert. ⚠ Latent on GitHub's non-root runners.
SKIP_UNSTAT=0
if [ "$(id -u)" = "0" ]; then
    SKIP_UNSTAT=1
    echo "skip: running as root — mode 444 cannot deny a directory search"
fi
out=$("$BIN" ls -l unstat 2>/dev/null || true)
rc=0; "$BIN" ls -l unstat >/dev/null 2>&1 || rc=$?
err=$("$BIN" ls -l unstat 2>&1 >/dev/null || true)
chmod 755 unstat


if [ "$SKIP_UNSTAT" = "1" ]; then
    echo "skip: M17g assertions need a directory search that root cannot be denied"
else
    expect_eq "M17g: exits 1" "1" "$rc"
    # ⭐ The TYPE character survives — it comes from the dirent, not the stat, which
    # is what lets a symlink still read as `l` when it could not be stat'd at all.
    case "$out" in
        *"d?????????"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf "FAIL M17g: dir row not d?????????: %s\n" "$out" >&2 ;;
    esac
    case "$out" in
        *"l?????????"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf "FAIL M17g: symlink row not l?????????: %s\n" "$out" >&2 ;;
    esac
    case "$out" in
        *"-?????????"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf "FAIL M17g: file row not -?????????: %s\n" "$out" >&2 ;;
    esac
    # No fabricated values anywhere in the row.
    case "$out" in
        *"1970-01-01"*) FAIL=$((FAIL + 1)); printf "FAIL M17g: still fabricates an epoch date\n" >&2 ;;
        *) PASS=$((PASS + 1)) ;;
    esac
    case "$err" in
        *"cannot access"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf "FAIL M17g: no 'cannot access' on stderr: %s\n" "$err" >&2 ;;
    esac
    # A healthy listing is untouched — same fields, exit 0.
fi

expect_exit "M17g: healthy listing still exits 0" 0 "$BIN" ls -l .

# --- owner / group NAMES in -l, and -n (1.5.0) --------------------------
#
# ⛔ EVERY assertion here is a RUNTIME COMPARISON against GNU, never a literal.
# The right answer is a property of the MACHINE's /etc/passwd — uid 1000 is
# `macro` on the box this was written on and somebody else on the CI runner — so
# `expect_eq "owner" "macro"` would assert the laptop rather than the code.
#
# ⚠ Only the columns THROUGH the owner and group are compared, because kriya's
# date column is deliberately different: it renders ISO and in UTC (ADR 0007)
# while GNU renders `Mon DD` in local time. Comparing whole lines would fail for
# a reason that has nothing to do with this release.
mkdir -p ownerdir && : > ownerdir/f1 && : > ownerdir/f2
own_cols() { awk '{print $1, $2, $3, $4}'; }

expect_eq "-l shows the owner NAME" \
    "$(ls -l ownerdir/f1 | own_cols)" "$("$BIN" ls -l ownerdir/f1 | own_cols)"
expect_eq "-l owner columns on a directory listing" \
    "$(ls -l ownerdir | tail -n +2 | own_cols)" "$("$BIN" ls -l ownerdir | own_cols)"
# A root-owned path exercises a different passwd entry than the test user's.
expect_eq "-l of a root-owned path" \
    "$(ls -ld / | own_cols)" "$("$BIN" ls -ld / | own_cols)"

# ⚠ `-n` is not merely "don't look up names" — in GNU it also IMPLIES `-l`.
expect_eq "-n forces numeric ids" \
    "$(ls -n ownerdir/f1 | own_cols)" "$("$BIN" ls -n ownerdir/f1 | own_cols)"
expect_eq "-n implies -l" \
    "$(ls -n ownerdir | tail -n +2 | own_cols)" "$("$BIN" ls -n ownerdir | own_cols)"
# ...and the two must actually DIFFER, or the pair above proves nothing. On a
# host where the test user has no passwd entry they legitimately match, so this
# is a comparison against GNU rather than an assertion of difference.
expect_eq "-l vs -n differ exactly as GNU's do" \
    "$(if [ "$(ls -l ownerdir/f1|own_cols)" = "$(ls -n ownerdir/f1|own_cols)" ]; then echo same; else echo differ; fi)" \
    "$(if [ "$("$BIN" ls -l ownerdir/f1|own_cols)" = "$("$BIN" ls -n ownerdir/f1|own_cols)" ]; then echo same; else echo differ; fi)"

# ⛔ The mixed-width alignment quirk — names LEFT-justified, unmapped numeric ids
# RIGHT-justified in the SAME column — needs a file owned by an id with no
# passwd entry, which cannot be created without chown privileges. It is covered
# in the container run instead; noted here so the gap is deliberate.

# --- -t / -S sort keys (1.5.1) -----------------------------------------
#
# ⚠ Compared by ORDER only, via the last field of each line: kriya's `-l` date
# column is deliberately ISO and UTC (ADR 0007) where GNU's is `Mon DD` local,
# and kriya prints no `total N` header. Comparing whole lines would fail for
# reasons that have nothing to do with sorting.
mkdir -p sortdir && cd sortdir
printf 'aaa' > s_big; printf 'b' > s_small; printf 'cc' > s_mid
: > t_new;  touch -d '2030-01-01 00:00:00' t_new
: > t_old;  touch -d '2020-01-01 00:00:00' t_old
# ⛔ An EXACT mtime tie, forced rather than hoped for: the tie-break is the
# whole point, and two files created moments apart may or may not collide
# depending on the filesystem's timestamp granularity.
: > z_tie; : > a_tie; : > m_tie
touch -d '2021-06-01 12:00:00' z_tie a_tie m_tie
cd ..

sort_names() { awk '{ if ($1 == "total") next; print $NF }'; }
sort_same() {
    label=$1; shift
    g=$(cd sortdir && ls "$@" | sort_names)
    k=$(cd sortdir && "$BIN" ls "$@" | sort_names)
    expect_eq "sort: $label" "$g" "$k"
}
sort_same "-t"        -t
sort_same "-S"        -S
sort_same "-tr"       -tr
sort_same "-Sr"       -Sr
sort_same "-t -1"     -t -1
sort_same "-S -1"     -S -1
sort_same "-lt"       -lt
sort_same "-lS"       -lS
sort_same "-ltr"      -ltr
sort_same "-t -a"     -t -a
sort_same "-t -F"     -t -F
# ⛔ BOTH given: GNU takes the RIGHTMOST, so these two differ from each other.
# `flags_get_bool` cannot answer this — it says "was it given", not "which came
# last" — so `ls` scans argv for the order.
sort_same "-tS (size wins)"  -tS
sort_same "-St (time wins)"  -St
sort_same "-t -S separate"   -t -S
sort_same "-S -t separate"   -S -t
# ⚠ ...and they must actually DIFFER, or the pair above proves nothing.
expect_eq "sort: -tS and -St disagree" \
    "$(if [ "$(cd sortdir && ls -tS | sort_names)" = "$(cd sortdir && ls -St | sort_names)" ]; then echo same; else echo differ; fi)" \
    "$(if [ "$(cd sortdir && "$BIN" ls -tS | sort_names)" = "$(cd sortdir && "$BIN" ls -St | sort_names)" ]; then echo same; else echo differ; fi)"
# The exact-tie tie-break, and that -r reverses it too.
expect_eq "sort: exact mtime tie breaks by name" \
    "$(cd sortdir && ls -t a_tie m_tie z_tie)" "$(cd sortdir && "$BIN" ls -t a_tie m_tie z_tie)"
expect_eq "sort: -tr reverses the tie-break" \
    "$(cd sortdir && ls -tr a_tie m_tie z_tie)" "$(cd sortdir && "$BIN" ls -tr a_tie m_tie z_tie)"
expect_eq "sort: equal sizes break by name" \
    "$(cd sortdir && ls -S a_tie m_tie z_tie)" "$(cd sortdir && "$BIN" ls -S a_tie m_tie z_tie)"
# ⚠ And the DEFAULT must still be the plain name sort — a regression there
# would otherwise hide behind all the -t/-S assertions above.
expect_eq "sort: default is still by name" \
    "$(cd sortdir && ls | sort_names)" "$(cd sortdir && "$BIN" ls | sort_names)"
expect_eq "sort: default -r is still by name" \
    "$(cd sortdir && ls -r | sort_names)" "$(cd sortdir && "$BIN" ls -r | sort_names)"

# ⛔ REGRESSION GUARD — a sort flag AFTER the operands. kriya's first cut
# scanned the raw argv only as far as `kriya_argv_option_end`, which stops at
# the first operand, while the PARSER permutes. So `ls aa bb cc -rt` honoured
# the `-r` and SILENTLY DROPPED the `-t` from the same cluster: name order,
# exit 0, empty stderr. ⚠ Every assertion above put the flags FIRST, so none of
# them could have caught it.
sort_same "-t after the operands"   -1 s_big s_small s_mid -t
sort_same "-S after the operands"   -1 s_big s_small s_mid -S
sort_same "-rt after the operands"  -1 s_big s_small s_mid -rt
sort_same "-t between operands"     -1 s_big -t s_small s_mid
sort_same "-tS after the operands"  -1 s_big s_small s_mid -tS
sort_same "-St after the operands"  -1 s_big s_small s_mid -St

# ⛔ REGRESSION GUARD — the DIRECTORY-SECTION list. It was built as raw paths
# and never sorted, so `ls d3 d1 d2` emitted `d3: d1: d2:` where GNU emits
# `d1: d2: d3:`, and `-t`/`-r` changed nothing. ⚠ The flat non-directory list
# WAS sorted correctly, which is why every existing assertion passed.
mkdir -p secdir && cd secdir && mkdir -p s3 s1 s2 && : > s1/x && : > s2/y && : > s3/z
touch -d '2020-01-01' s2; touch -d '2025-01-01' s3; touch -d '2030-01-01' s1
cd ..
sec_same() {
    label=$1; shift
    g=$(cd secdir && ls "$@" 2>&1 | grep ':$')
    k=$(cd secdir && "$BIN" ls "$@" 2>&1 | grep ':$')
    expect_eq "sort: $label" "$g" "$k"
}
sec_same "dir sections sorted"      -1 s3 s1 s2
sec_same "dir sections -t"          -1t s3 s1 s2
sec_same "dir sections -r"          -1r s3 s1 s2
sec_same "dir sections -tr"         -1tr s3 s1 s2
# ⚠ Files and directories together: the flat list comes first, then the
# sections, and BOTH must be ordered.
expect_eq "sort: mixed operands, whole output" \
    "$(cd secdir && ls -1 s3 ../sortdir/s_big s1 2>&1)" \
    "$(cd secdir && "$BIN" ls -1 s3 ../sortdir/s_big s1 2>&1)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
