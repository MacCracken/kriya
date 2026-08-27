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

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
