#!/bin/sh
# smoke-ls.sh — behavioural test for `kriya ls`.
#
# Covers the M3-shipped surface: default listing, -a/-A hidden file
# semantics, -l columns, -h human sizes, -r reverse sort, -F type
# suffix, -i inode, -d list-directory-as-entry, -R recursive, and
# multi-operand mixed-file-and-directory layout.

set -e

# ⛔ GNU's `ls` and `stat` honour QUOTING_STYLE and kriya does not, so a host
# exporting it fails every quoted comparison below at once — blaming kriya for
# the shell's environment. ⚠ Same shape as du/df's BLOCK_SIZE and echo's
# POSIXLY_CORRECT: if kriya ignores a variable, the ORACLE must ignore it too.
# ⭐ Caught by the hostile-environment matrix run, not by CI.
unset QUOTING_STYLE
# ⛔ ...and POSIXLY_CORRECT, which STOPS GNU permuting options after operands.
# kriya permutes always, so `ls f1 f2 -rt` is a sort request here and two more
# operands to a POSIX-strict GNU. kriya does not read the variable at all
# (ADR 0011's reasoning), so the oracle must not either.
unset POSIXLY_CORRECT
# ⛔ ...and TIME_STYLE, LS_BLOCK_SIZE and BLOCK_SIZE, which GNU reads for `-l`'s
# date and sizes and kriya does not (TIME_STYLE is roadmap 1.8.4).
unset TIME_STYLE LS_BLOCK_SIZE BLOCK_SIZE

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

# --- -l columns: 9 fields (mode nlink owner group size MON DAY TIME name) ---
# ⚠ The date is POSIX's `%b %e %H:%M` since 1.6.12 (ADR 0020), so it is THREE
# fields, and a file this fresh is inside the six-month window — the time form,
# not the year. The byte-for-byte check against GNU is in the 1.6.12 block.
line=$("$BIN" ls -l regfile)
nf=$(echo "$line" | awk '{print NF}')
expect_eq "-l 9 columns (incl month, day, time)"  "9" "$nf"
date_field=$(echo "$line" | awk '{print $6, $7, $8}')
case "$date_field" in
    [A-S][a-u][b-y]\ [1-9]\ [0-2][0-9]:[0-5][0-9]) PASS=$((PASS + 1)) ;;
    [A-S][a-u][b-y]\ [1-3][0-9]\ [0-2][0-9]:[0-5][0-9]) PASS=$((PASS + 1)) ;;
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
# 1500K (1.46 MiB) → "1.5M". ⛔ GNU ROUNDS UP (gnulib `human_ceiling`), so a
# size never displays smaller than it is; kriya rounded to nearest and printed
# "1.4M" — which is what this assertion expected until 1.6.12.
sz=$("$BIN" ls -l -h meg.bin | awk '{print $5}')
expect_eq "-h ~1.5MiB rounds up"  "1.5M" "$sz"
expect_eq "...and GNU agrees"     "1.5M" "$(ls -l -h meg.bin | awk '{print $5}')"
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
# ⚠ Only the columns THROUGH the owner and group are compared, because they are
# what is under test. kriya's date is GNU's POSIX form since 1.6.12 (ADR 0020)
# but still in UTC (ADR 0007), so a whole-line comparison needs `TZ=UTC` on the
# oracle — the 1.6.12 block below does exactly that.
# ⚠ Both sides open with `total N` since 1.6.12, which `own_cols` passes through
# unchanged; GNU's used to be stripped with `tail -n +2` to line the two up.
mkdir -p ownerdir && : > ownerdir/f1 && : > ownerdir/f2
own_cols() { awk '{print $1, $2, $3, $4}'; }

expect_eq "-l shows the owner NAME" \
    "$(ls -l ownerdir/f1 | own_cols)" "$("$BIN" ls -l ownerdir/f1 | own_cols)"
expect_eq "-l owner columns on a directory listing" \
    "$(ls -l ownerdir | own_cols)" "$("$BIN" ls -l ownerdir | own_cols)"
# A root-owned path exercises a different passwd entry than the test user's.
expect_eq "-l of a root-owned path" \
    "$(ls -ld / | own_cols)" "$("$BIN" ls -ld / | own_cols)"

# ⚠ `-n` is not merely "don't look up names" — in GNU it also IMPLIES `-l`.
expect_eq "-n forces numeric ids" \
    "$(ls -n ownerdir/f1 | own_cols)" "$("$BIN" ls -n ownerdir/f1 | own_cols)"
expect_eq "-n implies -l" \
    "$(ls -n ownerdir | own_cols)" "$("$BIN" ls -n ownerdir | own_cols)"
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

# --- --color (1.5.2) ---------------------------------------------------
#
# ⛔ LS_COLORS IS SET EXPLICITLY ON EVERY CASE, never inherited. It is set in an
# interactive shell and unset in CI, so a test that relied on the ambient value
# would colour here and print plain text on the runner — or vice versa.
#
# ⛔ And the gate matters as much as the table: with LS_COLORS UNSET or EMPTY,
# GNU emits NO escapes at all even under `--color=always`. Set it to any valid
# key and the compiled-in DEFAULTS load and the variable overlays them. Both
# halves are asserted, because implementing only one produces plausible output
# that is wrong in one direction.
mkdir -p cdir && cd cdir && mkdir -p sub && : > plain && : > runme && chmod +x runme
ln -s plain ok_link && ln -s /nonexistent-target bad_link && cd ..

# ⚠ TERM=dumb and no COLORTERM on every call: with LS_COLORS empty, those two
# decide whether the compiled-in defaults load (1.6.12), and the runner's
# values are not this test's business.
col_same() {
    label=$1; lsc=$2; shift 2
    g=$(cd cdir && env -u COLORTERM TERM=dumb LS_COLORS="$lsc" ls --color=always "$@" 2>&1 | od -An -c)
    k=$(cd cdir && env -u COLORTERM TERM=dumb LS_COLORS="$lsc" "$BIN" ls --color=always "$@" 2>&1 | od -An -c)
    expect_eq "color: $label" "$g" "$k"
}
CB='di=01;34:ln=01;36:ex=01;32'
col_same "types"              "$CB" -1 -d sub runme ok_link plain
col_same "-F outside escape"  "$CB" -1 -F -d sub runme
col_same "extension"          "di=01;34:*.c=01;33" -1 -d plain sub
col_same "defaults via rs=0"  "rs=0" -1 -d sub runme ok_link
col_same "di override"        "di=01;35" -1 -d sub
col_same "or on a broken link" "or=01;31:ln=01;36" -1 -d bad_link
# ⚠ WHOLE LINES since 1.6.12 — only the text after `->` was compared while
# kriya's `-l` date was ISO. The date is GNU's form now but still UTC (ADR
# 0007), hence `TZ=UTC` on both sides.
lt_g=$(cd cdir && LS_COLORS='or=01;31' TZ=UTC LC_ALL=C ls --color=always -l -d bad_link | od -An -c)
lt_k=$(cd cdir && LS_COLORS='or=01;31' TZ=UTC LC_ALL=C "$BIN" ls --color=always -l -d bad_link | od -An -c)
expect_eq "color: or colours the -l target" "$lt_g" "$lt_k"
col_same "zero code falls through" "ow=0:di=01;34" -1 -d sub
# ⛔ The gate: unset and empty must produce NO escapes at all — ON A TERMINAL
# TYPE `dircolors` DOES NOT KNOW. Since 1.6.12 an unset LS_COLORS still colours
# with the compiled-in defaults when COLORTERM is non-empty or TERM matches
# GNU's list (the 1.6.12 block tests that half), so this pins TERM=dumb rather
# than trusting the runner's — an xterm running this script would colour.
gu=$(cd cdir && env -u LS_COLORS -u COLORTERM TERM=dumb ls --color=always -1 -d sub plain | od -An -c)
ku=$(cd cdir && env -u LS_COLORS -u COLORTERM TERM=dumb "$BIN" ls --color=always -1 -d sub plain | od -An -c)
expect_eq "color: LS_COLORS unset emits nothing" "$gu" "$ku"
col_same "LS_COLORS empty"    "" -1 -d sub plain
# ⚠ ...and it must really be nothing, not merely equal — a pair of
# both-broken implementations would pass the comparison above.
case "$ku" in
    *033*) FAIL=$((FAIL + 1)); printf 'FAIL color: unset LS_COLORS still emitted an escape\n' >&2 ;;
    *)     PASS=$((PASS + 1)) ;;
esac

# --color=never / the default must never colour.
col_never=$(cd cdir && LS_COLORS="$CB" "$BIN" ls --color=never -1 -d sub | od -An -c)
case "$col_never" in
    *033*) FAIL=$((FAIL + 1)); printf 'FAIL color: --color=never emitted an escape\n' >&2 ;;
    *)     PASS=$((PASS + 1)) ;;
esac
col_default=$(cd cdir && LS_COLORS="$CB" "$BIN" ls -1 -d sub | od -An -c)
case "$col_default" in
    *033*) FAIL=$((FAIL + 1)); printf 'FAIL color: default emitted an escape\n' >&2 ;;
    *)     PASS=$((PASS + 1)) ;;
esac
# ⚠ `--color=auto` off a tty is the CI condition and must be plain.
col_auto=$(cd cdir && LS_COLORS="$CB" "$BIN" ls --color=auto -1 -d sub | od -An -c)
case "$col_auto" in
    *033*) FAIL=$((FAIL + 1)); printf 'FAIL color: --color=auto coloured off a tty\n' >&2 ;;
    *)     PASS=$((PASS + 1)) ;;
esac
# Aliases and a bad value.
for w in always yes force auto tty if-tty never no none; do
    rc=0; (cd cdir && LS_COLORS="$CB" "$BIN" ls --color=$w -1 -d sub) >/dev/null 2>&1 || rc=$?
    expect_eq "color: --color=$w accepted" "0" "$rc"
done
rc=0; (cd cdir && "$BIN" ls --color=bogus -1 -d sub) >/dev/null 2>&1 || rc=$?
expect_eq "color: --color=bogus is a usage error" "2" "$rc"

# --- quoting (1.5.3) ---------------------------------------------------
#
# ⛔ `ls` QUOTES ON A TERMINAL AND NOT THROUGH A PIPE, so the two paths need
# separate tests and the piped one is what every script parsing `ls` depends on.
#
# ⛔ AND THE ALGORITHM IS TESTED THROUGH A PIPE, via `--quoting-style`, NOT
# behind the pty. Before that flag existed the entire quoted-output path sat
# behind `script(1)`, so on a host without it the block skipped — and a mutant
# `ls` that never quoted scored 21 passed / 0 failed. The pty now covers exactly
# one bit: whether a terminal turns quoting on.
#
# ⚠ `QUOTING_STYLE` is UNSET on every oracle call. GNU honours it in both `ls`
# and `stat`, and it overrides the tty/pipe default in both directions — the
# same shape as the `LS_COLORS` and `POSIXLY_CORRECT` lessons: if kriya does not
# read a variable, the oracle must not either, or the test measures the shell.
mkdir -p qdir && cd qdir
: > 'a b'; : > "it's"; : > 'has"quote'; : > plain
nl_name=$(printf 'nl\nX'); : > "$nl_name"
tab_name=$(printf 'tab\there'); : > "$tab_name"
: > 'a=b'; : > 'mid#hash'; : > 'mid~tilde'; : > 'br]ack'; : > 'cur{ly}'
cd ..

qs_same() {
    label=$1; style=$2
    g=$(cd qdir && env -u QUOTING_STYLE LC_ALL=C ls -1 "--quoting-style=$style")
    k=$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1 "--quoting-style=$style")
    expect_eq "quote: $label" "$g" "$k"
}
qs_same "shell-escape matches GNU"        shell-escape
qs_same "shell-escape-always matches GNU" shell-escape-always
qs_same "literal matches GNU"             literal

# ⛔ ABSOLUTES, and they are viable here in a way they were not for passwd: the
# quoting map is byte-identical across coreutils 8.30, 9.4 (CI) and 9.11.
# ⚠ `=` is the correctness-relevant one — an unquoted `a=b` pasted into a shell
# is a variable ASSIGNMENT, not a filename. kriya under-quoted it before 1.5.3.
qa() {
    expect_eq "quote: $1" "$2" \
        "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1d --quoting-style=shell-escape "$3")"
}
qa "= is quoted"          "'a=b'"      'a=b'
qa "mid-word # is bare"   'mid#hash'   'mid#hash'
qa "mid-word ~ is bare"   'mid~tilde'  'mid~tilde'
qa "] is bare"            'br]ack'     'br]ack'
qa "{ } are bare"         'cur{ly}'    'cur{ly}'
# ⛔ ...INSIDE A WORD. Alone, each is shell syntax and GNU quotes it — the case
# the per-byte table above could not see, found by a fuzz at 1.6.12.
cd qdir && : > '{' && : > '}' && : > '{}' && cd ..
qa "a lone { is quoted"   "'{'"        '{'
qa "a lone } is quoted"   "'}'"        '}'
qa "{} is not"            '{}'         '{}'
expect_eq "quote: ...and GNU agrees on all three" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C ls -1d --quoting-style=shell-escape '{' '}' '{}')" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1d --quoting-style=shell-escape '{' '}' '{}')"
qa "space is quoted"      "'a b'"      'a b'
qa "plain stays bare"     'plain'      'plain'
# ...and the position rule: the same bytes quoted at index 0.
cd qdir && : > '#lead' && : > '~lead' && cd ..
qa "leading # is quoted"  "'#lead'"    '#lead'
qa "leading ~ is quoted"  "'~lead'"    '~lead'
# ⛔ ...AND A LEADING `-` IS NOT. 1.5.3 quoted it, from a measurement that gave
# GNU `-X` without `--` — so GNU read an option, not a name. `--` on BOTH sides.
cd qdir && : > ./-lead && : > ./- && cd ..
expect_eq "quote: a leading - is bare, as GNU's is" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C ls -1d --quoting-style=shell-escape -- -lead -)" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1d --quoting-style=shell-escape -- -lead -)"
expect_eq "...and absolutely"  "- -lead " \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1d --quoting-style=shell-escape -- -lead - | tr '\n' ' ')"
# ⚠ shell-escape-always must differ from shell-escape on a name needing nothing,
# or the two style assertions above would both pass for one implementation.
expect_eq "quote: always-quote differs from if-needed" "'plain'" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1d --quoting-style=shell-escape-always plain)"

# An unknown style is REFUSED by name rather than silently defaulted. ⚠ This
# used `c` until 1.6.12, when kriya grew all nine of GNU's styles and `c` became
# a valid answer — the 1.6.12 block compares every one of them against GNU.
# ⚠ Exit 2 is ADR 0008's "invalid value"; GNU exits 1 here (its ARGMATCH_DIE is
# `usage (EXIT_FAILURE)`), so this is asserted as kriya's own answer.
rc=0; (cd qdir && "$BIN" ls --quoting-style=bogus) >/dev/null 2>&1 || rc=$?
expect_eq "quote: unknown style refused" "2" "$rc"

# The piped DEFAULT must stay RAW — the regression that would break scripts.
expect_eq "quote: piped default is raw" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C ls -1)" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1)"
# ⚠ Look for a WRAPPED name, not for a quote character: one fixture is literally
# called `it's`, so raw output contains a `'` legitimately.
praw=$(cd qdir && env -u QUOTING_STYLE "$BIN" ls -1)
case "$praw" in
    *"'a b'"*) FAIL=$((FAIL + 1)); printf 'FAIL quote: piped ls quoted a name\n' >&2 ;;
    *)         PASS=$((PASS + 1)) ;;
esac

# ⚠ The pty now covers ONE bit: does a terminal turn quoting on? `command -v
# script` is satisfied by BusyBox's applet too and `-qec` is util-linux syntax
# it rejects, so probe the FLAGS the way smoke-cp-recursive.sh does.
if script -qec true /dev/null >/dev/null 2>&1; then
    tq=$(cd qdir && env -u QUOTING_STYLE LC_ALL=C script -qec "'$BIN' ls -1d 'a b'" /dev/null 2>/dev/null | tr -d '\r')
    case "$tq" in
        *"'a b'"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf 'FAIL quote: a terminal did not turn quoting on\n' >&2 ;;
    esac
else
    echo "note: no util-linux script(1) — the tty-detection bit is unverified;"
    echo "      the quoting ALGORITHM is still covered above via --quoting-style"
fi

# --- ADR 0017: $COLUMNS sets a width, it does not choose the format ---------
# ⛔ THIS WAS LIVE AND IT BREAKS SCRIPTS. bash exports COLUMNS from interactive
# shells, so `kriya ls | while read f` produced MULTI-COLUMN output — several
# names on one line — purely because of the parent shell, and the reader gets
# "file1  file2" as one filename. GNU ignores COLUMNS off a tty; kriya let it
# force columnation.
#
# ⚠ The comment defending it claimed "$COLUMNS forces columns even off a tty (a
# real GNU affordance)". Measured, GNU does neither that nor the same for -w;
# `-C` is what forces columns. **Fourth release running that a comment asserting
# another tool's behaviour was load-bearing and wrong.**
mkdir -p colw
i=1
while [ "$i" -le 6 ]; do : > "colw/f$i"; i=$((i + 1)); done
expect_eq "COLUMNS does not columnate a pipe" "6" \
          "$(COLUMNS=200 "$BIN" ls colw | wc -l)"
expect_eq "...and GNU agrees"                 "6" \
          "$(COLUMNS=200 ls colw | wc -l)"
expect_eq "...nor does a huge COLUMNS"        "6" \
          "$(COLUMNS=9999 "$BIN" ls colw | wc -l)"
expect_eq "...and an unset COLUMNS is the same" "6" \
          "$(env -u COLUMNS "$BIN" ls colw | wc -l)"
# ⭐ AND `-w` IS A WIDTH, NOT A FORMAT — flipped at 1.6.8, when `-C` arrived.
# 1.6.5 left `-w` forcing columns because it was then the only way to ask for
# them off a tty; removing that without `-C` would have deleted the capability.
expect_eq "-w does NOT force columns"          "6" \
          "$(env -u COLUMNS "$BIN" ls -w 200 colw | wc -l)"
expect_eq "...matching GNU"                    "6" \
          "$(env -u COLUMNS ls -w 200 colw | wc -l)"
expect_eq "-C is what forces them"             "1" \
          "$(env -u COLUMNS "$BIN" ls -C -w 200 colw | wc -l)"
expect_eq "...and GNU agrees"                  "1" \
          "$(env -u COLUMNS ls -C -w 200 colw | wc -l)"

# --- 1.6.8: the format group, byte-for-byte against GNU --------------------
# ⛔ COMPARE BYTES, NOT LINES. Column POSITIONS were already identical before
# this release while the SEPARATORS were not — GNU tabs between columns, kriya
# padded with spaces — so a comparison that ignores whitespace passes over the
# exact defect. Everything below goes through `cat -A`.
same_ls() {   # same_ls <name> <arg...>
    _n=$1; shift
    _g=$(env -u COLUMNS ls "$@" colw 2>&1 | cat -A)
    _k=$(env -u COLUMNS "$BIN" ls "$@" colw 2>&1 | cat -A)
    expect_eq "$_n" "$_g" "$_k"
}
for _w in 5 7 9 13 20 40 80 0; do
    same_ls "-C at width $_w"  -C -w "$_w"
    same_ls "-x at width $_w"  -x -w "$_w"
    same_ls "-m at width $_w"  -m -w "$_w"
done
# ⛔ ONE LAST-WINS GROUP. The flag table keeps a bool per flag with no order, so
# an argv walk decides — over the EXPANDED argv, or `-lC` would be invisible.
same_ls "-C then -1 is one per line" -C -1
same_ls "-1 then -C is columns"      -1 -C
same_ls "-x then -m is commas"       -x -m -w 20
same_ls "-m then -x is across"       -m -x -w 20
same_ls "--format= then -C"          --format=commas -C -w 20
same_ls "-C then --format="          -C --format=commas -w 20
same_ls "a cluster resolves too"     -1C -w 20
# ⚠ `-1` IS THE ONE EXCEPTION: it has no effect after `-l`, in either order,
# which is GNU's own special case rather than a last-wins consequence.
# ⭐ AGAINST GNU'S BYTES since 1.6.12, which gave `-l` its `total N` line and
# GNU's date form; until then this compared kriya to kriya. `TZ=UTC` because
# kriya's dates are UTC by design (ADR 0007) and GNU's are local.
_l_only=$(env -u COLUMNS TZ=UTC LC_ALL=C ls -l colw)
expect_eq "-l then -1 stays long" "$_l_only" "$(env -u COLUMNS TZ=UTC "$BIN" ls -l -1 colw)"
expect_eq "-1 then -l is long"    "$_l_only" "$(env -u COLUMNS TZ=UTC "$BIN" ls -1 -l colw)"
# ⭐ And GNU agrees the two orders are identical, which is the half that pins the
# rule to GNU rather than to kriya's own opinion.
expect_eq "...and GNU agrees the orders match" \
          "$(env -u COLUMNS ls -l -1 colw)" "$(env -u COLUMNS ls -1 -l colw)"
same_ls "-l -1 -C ends columnar"     -l -1 -C -w 20
# ⚠ `-w 0` IS UNLIMITED, NOT AUTO. kriya's help said "0 = auto" and it produced
# one entry per line — the opposite of GNU, which puts everything on one line.
same_ls "-w 0 is unlimited"          -C -w 0

# ⛔ THREE FIXTURES THAT EXIST ONLY TO KILL A MUTANT. Every case above survived
# all three of these mutations — the whole `colw` set is 2-character names, and
# at that size the right answer and the wrong one agree. Each block below names
# the mutation it kills; if you change the fixture, re-run the mutation.
mkdir -p gapw wrapm widew
# (a) the column separator: `to / 8 > (from + 1) / 8` vs `to / 8 > from / 8`.
#     Needs a name ending at column 7 with the next column at 9 — i.e. 7-char
#     names, so the pad is two spaces that STRADDLE a tab stop without reaching
#     the next one. GNU emits two spaces; the off-by-one emits a tab and a space.
for _f in aaaaaaa bbbbbbb ccccccc ddddddd; do : > "gapw/$_f"; done
# (b) the commas wrap: `pos + 2 + ew >= width` vs `> width`. Needs a line whose
#     next entry would land EXACTLY on the width, where `>=` wraps and `>` packs
#     one more. ⚠ 2-char names at width 10; 3-char names at 12 AGREE, and that is
#     what this fixture held first — it read like a boundary case and killed
#     nothing.
_i=0
while [ "$_i" -lt 9 ]; do : > "$(printf 'wrapm/%02d' "$_i")"; _i=$((_i + 1)); done
# (c) the off-a-tty default width, 80. Needs names wide enough that 80 and any
#     larger guess disagree on the column count: 19 chars gives 3 columns at 80
#     and 5 at 120.
_i=0
while [ "$_i" -lt 10 ]; do : > "$(printf 'widew/name-%09d' "$_i")"; _i=$((_i + 1)); done
same_lsd() {  # same_lsd <name> <dir> <arg...>
    _n=$1; _d=$2; shift 2
    expect_eq "$_n" "$(env -u COLUMNS ls "$@" "$_d" 2>&1 | cat -A)" \
                    "$(env -u COLUMNS "$BIN" ls "$@" "$_d" 2>&1 | cat -A)"
}
same_lsd "a pad that straddles a tab stop" gapw  -C -w 20
same_lsd "...and across"                   gapw  -x -w 20
same_lsd "commas wrapping exactly at -w"   wrapm -m -w 10
same_lsd "...and at a narrower one"        wrapm -m -w 6
same_lsd "no -w and no COLUMNS is 80"      widew -C
same_lsd "...across too"                   widew -x

# (d) the fit test itself, and the cap's rounding. ⛔ BOTH NEED MANY SHORT NAMES
#     and nothing above had them — the whole set above tops out at ten entries.
#     GNU seeds every column at 3 and re-tests the fit ONLY when a column grows
#     past that seed, so a directory of uniformly one-character names gets ONE
#     MORE COLUMN than an arithmetic `sum of fields < width` allows: 52 of them
#     at `-x -w 80` is 27 columns, and kriya said 26. The cap rounds UP for the
#     same reason, which `-w 75` (25 columns) against `-w 76` (26) pins.
mkdir -p tiny
for _f in a b c d e f g h i j k l m n o p q r s t u v w x y z \
          A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do : > "tiny/$_f"; done
same_lsd "52 one-char names pack across"   tiny -x -w 80
same_lsd "...and down"                     tiny -C -w 80
same_lsd "the cap rounds up, below"        tiny -x -w 75
same_lsd "...and above"                    tiny -x -w 76
same_lsd "...and -C agrees at both"        tiny -C -w 75
same_lsd "...(the wider one)"              tiny -C -w 76

# ⛔ `-1` IS THE ONE CONDITIONAL SELECTOR, and its long spelling is NOT. Every
# other member of the group overwrites the format unconditionally; `-1` sets
# one-per-line only when the current format is not LONG, so it never overrides
# `-l` in either order — while `--format=single-column` does. Two spellings of
# the same request that are not equivalent, which is why both are pinned.
# ⚠ CLASSIFIES THE FORMAT, IT DOES NOT COMPARE `-l`'s BYTES: the property under
# test is which format won, and the bytes of each format are pinned elsewhere
# (the 1.6.12 block for long).
same_fmt() {  # same_fmt <name> <arg...>
    _n=$1; shift
    # ⚠ CLASSIFIES THE WHOLE OUTPUT, NOT LINE 1. A long listing opens with
    # `total N` — GNU's always did, kriya's since 1.6.12 — so a line-1 test
    # reads long output as "not long" and every comparison inverts.
    _cls() {
        case "$1" in
            *"rw-"*) echo LONG ;;
            *", "*)  echo COMMAS ;;
            *) if [ "$(printf '%s' "$1" | sed -n '$p' | wc -w)" -gt 1 ]
               then echo MULTICOL; else echo SINGLE; fi ;;
        esac
    }
    expect_eq "$_n" "$(_cls "$(env -u COLUMNS ls "$@" colw 2>&1)")" \
                    "$(_cls "$(env -u COLUMNS "$BIN" ls "$@" colw 2>&1)")"
}
same_fmt "-1 loses to -l from the left"   -l -1
same_fmt "...and from the right"          -1 -l
same_fmt "but -C clears long, so -1 wins" -l -C -1
same_fmt "...and -l after -C suppresses"  -C -l -1
same_fmt "--format=single-column DOES win" -l --format=single-column
same_fmt "...and still loses when earlier" --format=single-column -l
# ⛔ `-n` IS A GROUP MEMBER, NOT A COLUMN SWITCH. It implies long and takes its
# turn in the order, so a later `-C` clears it — `ls -n -C` is vertical under
# GNU and was long here, because `-n` forced long AFTER the walk had decided.
same_fmt "-n implies long"               -n
same_fmt "...but -C after it clears"     -n -C
same_fmt "...and -n after -C sets it"    -C -n
same_fmt "the long spelling too"         --numeric-uid-gid -C
same_fmt "...in the other order"         -C --numeric-uid-gid
same_fmt "-1 loses to -n as to -l"       -n -1
same_fmt "...and -C between them frees it" -n -C -1
# ⭐ And GNU's two spellings genuinely DISAGREE after `-l` — the six assertions
# above are only worth having if that is true, so it is stated rather than
# assumed. If a future coreutils makes them agree, THIS is the line that says so.
_s1=$(env -u COLUMNS ls -l -1 colw                    | grep -qc 'rw-' && echo LONG || echo SINGLE)
_s2=$(env -u COLUMNS ls -l --format=single-column colw | grep -qc 'rw-' && echo LONG || echo SINGLE)
expect_eq "GNU: -1 and --format=single-column differ after -l" "LONG/SINGLE" "$_s1/$_s2"

# --- the width VALUE: what is accepted, what is unlimited, what is refused ---
# ⛔ `--width 32` FAILED WITH A DIAGNOSTIC ABOUT `--format`. Two options take a
# separated value and one shared "skip the next token" flag sent both values
# through the format parser, so a valid width was rejected by name of an option
# the caller never typed. All four spellings must agree.
_w32=$(env -u COLUMNS "$BIN" ls -C --width=32 colw)
expect_eq "--width 32 separated"  "$_w32" "$(env -u COLUMNS "$BIN" ls -C --width 32 colw)"
expect_eq "-w 32 separated"       "$_w32" "$(env -u COLUMNS "$BIN" ls -C -w 32 colw)"
expect_eq "-w32 attached"         "$_w32" "$(env -u COLUMNS "$BIN" ls -C -w32 colw)"
same_lsd "...and GNU agrees on it" colw -C --width 32

# ⛔ `COLUMNS=0` IS UNLIMITED, and `atoi` could not tell it from `abc` or from
# the empty string — all three read as 0 and fell through to 80.
for _v in 0 12 200 abc -5 '' ' '; do
    expect_eq "COLUMNS=[$_v] matches GNU" \
      "$(COLUMNS="$_v" ls -C widew 2>/dev/null | cat -A)" \
      "$(COLUMNS="$_v" "$BIN" ls -C widew 2>/dev/null | cat -A)"
done

# ⛔ `-w -5` EXITED 0 and printed one name per line. GNU exits 2. The same guard
# catches the i64 wraparound that made the flag non-monotonic.
expect_exit "-w -5 is a usage error" 2 env -u COLUMNS "$BIN" ls -C -w -5 colw
expect_exit "...and GNU agrees"       2 env -u COLUMNS ls -C -w -5 colw
expect_exit "-w past i64 is refused"  2 env -u COLUMNS "$BIN" ls -C -w 9223372036854775808 colw
# ⚠ TWO DELIBERATE DIVERGENCES, asserted as kriya's OWN answer because GNU's
# differs and kriya's is the safer of the two: GNU parses the width with a
# base-0, unsigned, saturating reader, so it takes `0x20` as 32, `040` as 32,
# and clamps anything past 2^64 instead of refusing. kriya reads decimal only
# and refuses what it cannot represent — it never silently uses a DIFFERENT
# width than the one written, which is the failure mode `040` has under GNU.
expect_exit "-w 0x20 is refused (GNU: 32)" 2 env -u COLUMNS "$BIN" ls -C -w 0x20 colw
expect_eq "-w 040 is FORTY, not 32"      "$(env -u COLUMNS "$BIN" ls -C -w 40 colw)" \
                                         "$(env -u COLUMNS "$BIN" ls -C -w 040 colw)"

# --- ⛔ the ioctl beats $COLUMNS, and only a pty can say so -------------------
# Measured: `stty cols 40; COLUMNS=20 ls -C` is EIGHT columns under GNU and was
# four here. A live terminal knows its own width; an exported COLUMNS survives a
# resize. ⚠ `$COLUMNS` is the FALLBACK — a tty reporting zero columns still uses
# it, which is the third case below.
if script -qec true /dev/null >/dev/null 2>&1; then
    pty_cols() {   # pty_cols <name> <stty-args> <env-assignment>
        _n=$1; _st=$2; _ev=$3
        _g=$(script -qec "stty $_st; env $_ev ls -C colw" /dev/null 2>/dev/null | head -1 | tr -d '\r')
        _k=$(script -qec "stty $_st; env $_ev '$BIN' ls -C colw" /dev/null 2>/dev/null | head -1 | tr -d '\r')
        expect_eq "$_n" "$_g" "$_k"
    }
    pty_cols "the tty width beats COLUMNS"  "cols 40" "COLUMNS=20"
    pty_cols "...in the other direction"    "cols 20" "COLUMNS=40"
    pty_cols "a zero-column tty falls back" "rows 0 cols 0" "COLUMNS=20"
    # ⚠ `-w` beats BOTH, which needs the flag in the command rather than the env.
    _g=$(script -qec "stty cols 56; env COLUMNS=20 ls -C -w 40 colw" /dev/null 2>/dev/null \
         | head -1 | tr -d '\r')
    _k=$(script -qec "stty cols 56; env COLUMNS=20 '$BIN' ls -C -w 40 colw" /dev/null 2>/dev/null \
         | head -1 | tr -d '\r')
    expect_eq "and -w beats both" "$_g" "$_k"
else
    echo "note: no util-linux script(1) — the ioctl-beats-COLUMNS precedence is"
    echo "      unverified here; it cannot be reached without a terminal"
fi
# ⭐ `$COLUMNS` IS READ OFF A TTY NOW, because `-C` means the caller asked for
# columns. That is ADR 0017 working, not a retreat from it: the variable
# configures a feature the command line turned on, and `isatty` was only ever a
# proxy for "did anyone ask".
expect_eq "\$COLUMNS sets the width under -C" \
          "$(COLUMNS=20 ls -C colw | cat -A)" "$(COLUMNS=20 "$BIN" ls -C colw | cat -A)"
expect_eq "...and -w still beats it" \
          "$(COLUMNS=200 ls -C -w 20 colw | cat -A)" "$(COLUMNS=200 "$BIN" ls -C -w 20 colw | cat -A)"
# ⚠ ...but it still cannot CHOOSE the format.
expect_eq "\$COLUMNS alone still does not columnate" "6" \
          "$(COLUMNS=200 "$BIN" ls colw | wc -l)"
expect_exit "an unknown --format value is a usage error" 2 "$BIN" ls --format=bogus

# ⚠ AND `ls` MUST KEEP LEAVING `:` BARE. 1.6.6 gave diagnostics their own
# quoting style precisely so this one did not change: GNU's `ls
# --quoting-style=shell-escape` prints `a:b` bare while its error messages quote
# it, and kriya now does both.
mkdir -p qcol && : > 'qcol/a:b' && : > 'qcol/plainq'
# ⚠ `--quoting-style=shell-escape` EXPLICITLY, not the piped default. Off a tty
# `ls` prints names literally, so a piped listing is bare whatever the quoting
# table says — the first version of this assertion could not tell the two
# answers apart and stayed green against a build that quoted `:` everywhere.
expect_eq "ls leaves a colon bare"  "a:b plainq " \
          "$("$BIN" ls --quoting-style=shell-escape qcol | tr '\n' ' ')"
expect_eq "...and GNU agrees"       "a:b plainq " \
          "$(ls --quoting-style=shell-escape qcol | tr '\n' ' ')"
# ⭐ And a name that DOES need quoting still gets it, so the assertion above is
# about `:` specifically rather than about quoting being off.
: > 'qcol/a b'
expect_eq "...while a space is still quoted" "1" \
          "$("$BIN" ls --quoting-style=shell-escape qcol | grep -c "'a b'")"

# --- 1.6.12: output fidelity, byte for byte against GNU ---------------------
#
# ⛔ ONE SANITISED ENVIRONMENT FOR BOTH SIDES. `TZ=UTC` because kriya's dates
# are UTC by design (ADR 0007); `LC_ALL=C` because GNU localises month names and
# quote marks and kriya has no locale; TIME_STYLE, LS_BLOCK_SIZE and BLOCK_SIZE
# unset because GNU reads them and kriya does not — the QUOTING_STYLE lesson at
# the top of this file. COLUMNS, TABSIZE, LS_COLORS, COLORTERM and TERM are
# pinned because BOTH read them, so the runner's values would pick the answer;
# a case that needs one sets it.
# ⚠ STDERR IS COUNTED, NOT COMPARED: kriya's frame is `kriya ls: <operand>:
# <message>` (architecture 001) and GNU's is `ls: ...`. The count still catches
# a warning one side prints and the other does not.
L612_ENV="-u COLUMNS -u TABSIZE -u TIME_STYLE -u LS_BLOCK_SIZE -u BLOCK_SIZE -u LS_COLORS -u COLORTERM TERM=dumb TZ=UTC LC_ALL=C"
l612() {   # l612 <name> <env-words> <ls-arg...>; LS_COLORS comes from LC612 if set
    _n=$1; _e=$2; shift 2
    _grc=0
    (cd l612 && env $L612_ENV $_e ${LC612+"LS_COLORS=$LC612"} ls "$@" \
        >"$WORK/g.out" 2>"$WORK/g.err") || _grc=$?
    _krc=0
    (cd l612 && env $L612_ENV $_e ${LC612+"LS_COLORS=$LC612"} "$BIN" ls "$@" \
        >"$WORK/k.out" 2>"$WORK/k.err") || _krc=$?
    expect_eq "$_n" \
        "$(od -An -c "$WORK/g.out") rc=$_grc stderr=$(wc -l < "$WORK/g.err" | tr -d ' ')" \
        "$(od -An -c "$WORK/k.out") rc=$_krc stderr=$(wc -l < "$WORK/k.err" | tr -d ' ')"
}
# l612g <name> <GNU's args, one word-split string> <kriya's args...> — the same
# comparison, for a case where the two binaries need different words to mean
# one thing (a GNU version difference kriya has already chosen a side of).
l612g() {
    _n=$1; _ga=$2; shift 2
    _grc=0
    (cd l612 && env $L612_ENV ls $_ga >"$WORK/g.out" 2>"$WORK/g.err") || _grc=$?
    _krc=0
    (cd l612 && env $L612_ENV "$BIN" ls "$@" >"$WORK/k.out" 2>"$WORK/k.err") || _krc=$?
    expect_eq "$_n" \
        "$(od -An -c "$WORK/g.out") rc=$_grc stderr=$(wc -l < "$WORK/g.err" | tr -d ' ')" \
        "$(od -An -c "$WORK/k.out") rc=$_krc stderr=$(wc -l < "$WORK/k.err" | tr -d ' ')"
}
mkdir -p l612 && cd l612
# ⚠ THREE DATES, ONE PER BRANCH of GNU's six-month test: inside the window is
# `%b %e %H:%M`, before it and AFTER NOW are both `%b %e  %Y`.
: > recent; : > old; : > future
touch -d "@$(( $(date +%s) - 2592000 ))" recent
TZ=UTC touch -d '2020-01-02 03:04:05.123456789' old
TZ=UTC touch -d '2099-06-07 08:09:10' future
dd if=/dev/zero of=big bs=1024 count=1500 status=none
mkdir sub empt; : > sub/x
printf '#!/bin/sh\n' > run; chmod 0755 run
ln -s recent lnk; ln -s sub dlnk; ln -s run xlnk; ln -s nowhere dangle
# ⚠ SPARSE, so `-h` sees exact sizes at no disk cost: each pair straddles a
# boundary where rounding up and rounding to nearest disagree.
mkdir sz
for _s in 1 1023 1024 1025 10239 10240 10241 102399 1048575 1048576 1572865 \
          1073741823 1099511627776; do truncate -s "$_s" "sz/s$_s"; done
cd ..

l612 "-l, a whole directory, total line and all" "" -l
l612 "-la: the total counts . and .."            "" -la
l612 "-l on an empty directory is total 0"       "" -l empt
l612 "-lR: a total per section"                  "" -lR
l612 "-li and -ln"                               "" -li -n
# ⛔ FILE OPERANDS SHARE THEIR WIDTHS WITH THE DIRECTORY OPERANDS. GNU sizes the
# columns across every operand before splitting files from directories, so a
# directory's link count widens its files' column; kriya was two spaces short.
l612 "-l over files and a directory"             "" -l old recent big sub
l612 "-l on a device: major, minor"              "" -l /dev/null old big
# ⛔ `-h` ROUNDS UP. A size never displays smaller than it is.
l612 "-lh: ceiling sizes, scaled total"          "" -lh
l612 "-lh at every rounding boundary"            "" -lh sz
for _ts in full-iso long-iso iso locale posix-full-iso posix-long-iso posix-iso \
           posix-locale posix-bogus; do
    l612 "--time-style=$_ts"                     "" -l "--time-style=$_ts" old recent future
done
l612 "--full-time implies -l"                    "" --full-time old recent future
l612 "--time-style is inert without -l"          "" -1 --time-style=bogus
expect_exit "-l --time-style=bogus is a usage error" 2 "$BIN" ls -l --time-style=bogus
expect_exit "...and GNU agrees"                      2 ls -l --time-style=bogus
# ⚠ `+FORMAT` IS REFUSED, NOT IGNORED — roadmap 1.8.4. GNU renders it; a silent
# fallback to the default form would print a date the caller did not ask for.
expect_exit "--time-style=+FORMAT is refused for now" 2 "$BIN" ls -l --time-style=+%Y
# ⛔ `-g` AND `-o` ARE STICKY and ARE format members: each implies long, and a
# later `-l` does not bring the dropped column back.
l612 "-g drops the owner"                        "" -g
l612 "-o drops the group"                        "" -o
l612 "-go drops both"                            "" -go
l612 "-g then -l stays dropped"                  "" -g -l
l612 "-g -n"                                     "" -g -n
l612 "-g then -C is columns"                     "" -g -C
l612 "-C then -g is long"                        "" -C -g
l612 "-o --full-time"                            "" -o --full-time
# ⛔ `--dired` OFFSETS ARE BYTES INTO THE OUTPUT, so one misplaced space anywhere
# on a line moves every offset after it — the whole-listing compare is the test.
l612 "-lR --dired: //SUBDIRED//"                 "" -lR --dired
l612 "--dired over operands"                     "" -l --dired old sub empt
l612 "--dired then -C drops it"                  "" --dired -C
l612 "--dired records a quoting style"           "" -l --dired --quoting-style=c
# ⛔ A BARE `--dired` IMPLIES `-l` SINCE COREUTILS 9.5, and CI's 9.4 predates it:
# there it is ignored and `ls --dired` prints names. kriya follows 9.5+, so its
# answer is compared with the spelling every version agrees on — GNU given its
# own `-l` — and directly as well wherever the oracle has the rule.
# ⭐ Caught by the ubuntu:24.04 container run, not by the host.
l612g "--dired implies long"                     "-l --dired"    --dired
l612g "-D is --dired"                            "-l -D"         -D
l612g "-C then --dired is long"                  "-C --dired -l" -C --dired
if env $L612_ENV ls --dired /dev/null 2>/dev/null | grep -q '//DIRED//'; then
    l612 "...and this GNU agrees with no -l"     "" --dired
    l612 "...-D too"                             "" -D
    l612 "...and after -C"                       "" -C --dired
else
    echo "note: $(ls --version | head -1) predates a bare --dired implying -l (9.5);"
    echo "      those three cases were compared against 'ls -l --dired' only"
fi
# ⛔ `-lF` PUTS THE TARGET'S INDICATOR AFTER THE TARGET, and none on the link.
l612 "-lF"                                       "" -lF
l612 "-lF on link operands"                      "" -lF lnk dlnk xlnk dangle
# ⛔ TAB STOPS: `-T` / `--tabsize` / TABSIZE, read only when something columnates.
for _t in 0 1 4 8 16; do
    l612 "-T $_t"                                "" -C -w 30 -T "$_t" ../gapw
done
l612 "--tabsize=3 across"                        "" -x -w 30 --tabsize=3 ../gapw
l612 "TABSIZE=4"                                 "TABSIZE=4" -C -w 30 ../gapw
l612 "-T beats TABSIZE"                          "TABSIZE=0" -C -w 30 -T 4 ../gapw
l612 "TABSIZE=abc warns"                         "TABSIZE=abc" -C -w 30 ../gapw
l612 "...but not when nothing columnates"        "TABSIZE=abc" -l ../gapw
expect_exit "-T x is a usage error"  2 "$BIN" ls -T x
expect_exit "...and GNU agrees"      2 ls -T x
# ⛔ COLUMNS: warned about when it is READ and invalid — a columnar format, or
# colour REQUESTED (GNU checks before LS_COLORS or TERM can turn colour off).
l612 "COLUMNS=abc warns under -C"                "COLUMNS=abc" -C ../gapw
l612 "...and is not read one per line"           "COLUMNS=abc" -1 ../gapw
l612 "...but a colour request reads it"          "COLUMNS=abc" --color=always -1 ../gapw
l612 "COLUMNS= empty is ignored quietly"         "COLUMNS=" -C ../gapw
# ⛔ ALL NINE QUOTING STYLES, plus the alignment pad: in `-l` and in finite-width
# columns, GNU indents a name that needed no quotes by one space so it lines up
# with the quoted ones beside it.
cd qdir && : > "$(printf 'hi\351x')" && : > "$(printf 'esc\033x')" && : > "$(printf 'del\177x')" && cd ..
for _qs in literal shell shell-always shell-escape shell-escape-always c escape \
           locale clocale; do
    l612 "--quoting-style=$_qs"                  "" -1 "--quoting-style=$_qs" ../qdir
    l612 "--quoting-style=$_qs, -l aligns"       "" -l "--quoting-style=$_qs" ../qdir
    l612 "--quoting-style=$_qs, -C aligns"       "" -C -w 60 "--quoting-style=$_qs" ../qdir
done
# ⛔ SECTION HEADERS ARE QUOTED TOO, where a `:` forces the quotes and a `/` does
# not, and an operand header shares the rule.
mkdir -p 'h612/a b' 'h612/a:b' h612/plain "h612/$(printf 'n\nl')"
: > 'h612/a b/x'; : > 'h612/a:b/y'
for _qs in literal shell shell-escape c escape; do
    l612 "headers, $_qs"                         "" -R "--quoting-style=$_qs" ../h612
done
l612 "operand headers"                           "" --quoting-style=shell-escape '../h612/a b' ../h612/a:b

# ⛔ AN UNREADABLE DIRECTORY LEAVES NO SECTION BEHIND — no blank line, no
# header. GNU writes both only once the directory has opened; kriya wrote them
# first and then the error. ⚠ Root reads anything, so the cases skip there
# rather than pass vacuously.
mkdir -p l612/lk/a l612/lk/locked l612/lk/z && : > l612/lk/a/f && chmod 000 l612/lk/locked
if ! ls l612/lk/locked >/dev/null 2>&1; then
    l612 "-R past an unreadable directory"       "" -R lk
    l612 "...in long form, with --dired"         "" -lR --dired lk
    # ⚠ STDOUT ONLY for an unreadable OPERAND: GNU exits 2 for a command-line
    # argument it cannot open, kriya 1 (ADR 0008 — a per-operand failure).
    expect_eq "...and as an operand among others" \
        "$(cd l612/lk && env $L612_ENV ls z locked a 2>/dev/null || true)" \
        "$(cd l612/lk && env $L612_ENV "$BIN" ls z locked a 2>/dev/null || true)"
    expect_eq "...after a file operand" \
        "$(cd l612/lk && env $L612_ENV ls a/f locked z 2>/dev/null || true)" \
        "$(cd l612/lk && env $L612_ENV "$BIN" ls a/f locked z 2>/dev/null || true)"
else
    echo "note: running as root — the unreadable-directory cases are skipped"
fi
chmod 755 l612/lk/locked
# ⛔ `-R` HEADS THE IMPLIED `.` too — GNU's listing opens with `.:`.
expect_eq "-R with no operand opens with .:" \
    "$(cd l612/lk && env $L612_ENV ls -R)" "$(cd l612/lk && env $L612_ENV "$BIN" ls -R)"

# ⛔ COLOUR: GNU's whole table — 24 keys — and every file type that selects one.
mkdir -p l612/c && cd l612/c
mkfifo pipe; : > suid; chmod u+s suid; : > sgid; chmod g+s sgid
mkdir sticky ow stow dir; chmod +t sticky; chmod o+w ow; chmod +t,o+w stow
: > hard; ln hard hard2; : > plain; : > run; chmod +x run; : > file.c
ln -s plain lnk; ln -s dir dlnk; ln -s run xlnk; ln -s nowhere dangle
: > a-rather-long-name-one; : > a-rather-long-name-two
cd ../..
LC612='rs=0'   # any valid key loads GNU's compiled-in defaults under it
l612 "colour: the default table, one per line"   "" --color=always -1 c
l612 "colour: -l, targets coloured"              "" --color=always -l c
l612 "colour: -F outside the escape"             "" --color=always -F c
l612 "colour: -lF"                               "" --color=always -lF c
# ⚠ CLEAR-TO-EOL: in a non-long format, a coloured name that may wrap is
# followed by `cl`, so a background colour does not bleed to the margin.
l612 "colour: -C emits clear-to-EOL"             "" --color=always -C -w 30 c
l612 "colour: -x"                                "" --color=always -x -w 30 c
l612 "colour: -m"                                "" --color=always -m -w 30 c
LC612='rs=0:mh=44;37:su=0:sg=0'
l612 "colour: mh, once su and sg step aside"     "" --color=always -1 c
LC612='ln=target:di=01;34:ex=01;32:or=01;31:mi=05;37'
l612 "colour: ln=target colours as the referent" "" --color=always -1 c
l612 "...and in -l, with mi on the missing target" "" --color=always -l c
# ⛔ LS_COLORS VALUES CARRY ESCAPES — GNU's get_funky_string. `lc=\e[` was four
# literal characters here before 1.6.12.
LC612='lc=\e[:rc=m:ec=\e[0m:di=1;34'
l612 "colour: \\e escapes"                       "" --color=always -1 c
LC612='lc=^[[:rc=\x6d:di=01;34'
l612 "colour: caret and hex escapes"             "" --color=always -1 c
LC612='lc=\033[:rc=\155:di=\_1\?'
l612 "colour: octal, \\_ and \\?"                "" --color=always -1 c
# ⛔ AN UNKNOWN KEY OR A PARSE ERROR WARNS AND TURNS COLOUR OFF ENTIRELY.
LC612='zz=01'
l612 "colour: an unknown key warns, colour off"  "" --color=always -1 c
LC612='di=01;34:bogus'
l612 "colour: a parse error warns, colour off"   "" --color=always -1 c
# ⛔ THE TERMINAL GATE: with LS_COLORS unset or empty, GNU colours with its
# defaults only for a non-empty COLORTERM or a TERM its dircolors list names.
# ⚠ `vt220` is on 9.11's list and not 9.4's (CI), so it is not asserted here.
unset LC612
l612 "colour: unset, TERM=xterm-256color"        "TERM=xterm-256color" --color=always -1 c
l612 "colour: unset, COLORTERM=truecolor"        "COLORTERM=truecolor" --color=always -1 c
l612 "colour: unset, TERM=dumb"                  "" --color=always -1 c
l612 "colour: unset, COLORTERM empty"            "COLORTERM=" --color=always -1 c
LC612=''
l612 "colour: empty, TERM=screen"                "TERM=screen" --color=always -1 c
unset LC612

# ⛔ `?` FOR A CONTROL BYTE ON A TERMINAL. Only reachable through a pty.
if script -qec true /dev/null >/dev/null 2>&1; then
    pty612() {   # pty612 <name> <ls args, one shell string>
        _g=$(cd qdir && script -qec "env $L612_ENV ls $2" /dev/null 2>/dev/null | tr -d '\r')
        _k=$(cd qdir && script -qec "env $L612_ENV '$BIN' ls $2" /dev/null 2>/dev/null | tr -d '\r')
        expect_eq "$1" "$_g" "$_k"
    }
    pty612 "tty: literal masks control bytes with ?" "-1 --quoting-style=literal"
    pty612 "tty: the default style escapes them"     "-1"
    pty612 "tty: -l masks too"                       "-l --quoting-style=literal"
    pty612 "tty: columns, literal"                   "--quoting-style=literal"
else
    echo "note: no util-linux script(1) — the tty's ? masking is unverified here"
fi

# --- 1.6.16: COLUMNS past the first 8 KB of the environment -------------------
#
# ⚠ The same cliff `src/lib/env.cyr` existed for, retired at 1.6.16 for the
# stdlib `getenv`, which reads the whole environment since cyrius 6.5.36.
mkdir -p big8 && (cd big8 && touch a1 b2 c3 d4 e5 f6 g7 h8 i9 j0)
BIG8=$(head -c 9000 /dev/zero | tr '\0' x)
expect_eq "COLUMNS after 9 KB is honoured" \
    "$(cd big8 && env -i BIG8="$BIG8" COLUMNS=20 LC_ALL=C TERM=dumb ls -C)" \
    "$(cd big8 && env -i BIG8="$BIG8" COLUMNS=20 LC_ALL=C TERM=dumb "$BIN" ls -C)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
