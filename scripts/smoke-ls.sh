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

col_same() {
    label=$1; lsc=$2; shift 2
    g=$(cd cdir && LS_COLORS="$lsc" ls --color=always "$@" 2>&1 | od -An -c)
    k=$(cd cdir && LS_COLORS="$lsc" "$BIN" ls --color=always "$@" 2>&1 | od -An -c)
    expect_eq "color: $label" "$g" "$k"
}
CB='di=01;34:ln=01;36:ex=01;32'
col_same "types"              "$CB" -1 -d sub runme ok_link plain
col_same "-F outside escape"  "$CB" -1 -F -d sub runme
col_same "extension"          "di=01;34:*.c=01;33" -1 -d plain sub
col_same "defaults via rs=0"  "rs=0" -1 -d sub runme ok_link
col_same "di override"        "di=01;35" -1 -d sub
col_same "or on a broken link" "or=01;31:ln=01;36" -1 -d bad_link
# ⚠ Only the text AFTER `->` is compared: kriya's `-l` date column is ISO+UTC
# by design (ADR 0007), so a whole-line compare would fail on the date rather
# than on the colour under test.
lt_g=$(cd cdir && LS_COLORS='or=01;31' ls --color=always -l -d bad_link | sed 's/^.* -> //' | od -An -c)
lt_k=$(cd cdir && LS_COLORS='or=01;31' "$BIN" ls --color=always -l -d bad_link | sed 's/^.* -> //' | od -An -c)
expect_eq "color: or colours the -l target" "$lt_g" "$lt_k"
col_same "zero code falls through" "ow=0:di=01;34" -1 -d sub
# ⛔ The gate: unset and empty must produce NO escapes at all.
gu=$(cd cdir && env -u LS_COLORS ls --color=always -1 -d sub plain | od -An -c)
ku=$(cd cdir && env -u LS_COLORS "$BIN" ls --color=always -1 -d sub plain | od -An -c)
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
qa "space is quoted"      "'a b'"      'a b'
qa "plain stays bare"     'plain'      'plain'
# ...and the position rule: the same bytes quoted at index 0.
cd qdir && : > '#lead' && : > '~lead' && cd ..
qa "leading # is quoted"  "'#lead'"    '#lead'
qa "leading ~ is quoted"  "'~lead'"    '~lead'
# ⚠ shell-escape-always must differ from shell-escape on a name needing nothing,
# or the two style assertions above would both pass for one implementation.
expect_eq "quote: always-quote differs from if-needed" "'plain'" \
    "$(cd qdir && env -u QUOTING_STYLE LC_ALL=C "$BIN" ls -1d --quoting-style=shell-escape-always plain)"

# An unsupported style is REFUSED by name rather than silently defaulted.
rc=0; (cd qdir && "$BIN" ls --quoting-style=c) >/dev/null 2>&1 || rc=$?
expect_eq "quote: unsupported style refused" "2" "$rc"

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
# ⚠ COMPARED kriya-TO-kriya, DELIBERATELY. The rule under test is "`-1` has no
# effect after `-l`", and `ls -l`'s BYTES still differ from GNU's for two
# pre-existing reasons this release does not touch — no `total N` line and a
# different mtime format (both filed at roadmap 1.6.10). Comparing full `-l`
# output against GNU would fail for those reasons and say nothing about ordering.
_l_only=$(env -u COLUMNS "$BIN" ls -l colw)
expect_eq "-l then -1 stays long" "$_l_only" "$(env -u COLUMNS "$BIN" ls -l -1 colw)"
expect_eq "-1 then -l is long"    "$_l_only" "$(env -u COLUMNS "$BIN" ls -1 -l colw)"
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
# ⚠ CLASSIFIES THE FORMAT, IT DOES NOT COMPARE `-l`'s BYTES. Those still differ
# from GNU's for two pre-existing reasons out of scope here — no `total N` line
# and a different mtime rendering, both filed at roadmap 1.6.10 — so a byte
# comparison would go red for reasons that say nothing about which format won.
same_fmt() {  # same_fmt <name> <arg...>
    _n=$1; shift
    # ⚠ CLASSIFIES THE WHOLE OUTPUT, NOT LINE 1. GNU's long listing opens with
    # `total N` and kriya's does not (roadmap 1.6.10), so a line-1 test reads
    # GNU's long output as "not long" and every comparison inverts.
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

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
