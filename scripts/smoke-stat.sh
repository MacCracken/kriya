#!/bin/sh
# smoke-stat.sh — behavioural test for `kriya stat`.
#
# Covers the format-string engine: every specifier we ship, the
# escape-handling differences between `-c` and `--printf`, `-L`
# dereference, `-t` terse column order, and the per-operand
# partial-failure exit.

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

# --- fixture ---
echo "hello!" > regfile           # 7 bytes
chmod 0640 regfile
mkdir adir
chmod 0755 adir
ln -s regfile alink

# --- %n, %s, %a, %A, %f, %F ---
expect_eq "%n"        "regfile"               "$("$BIN" stat -c "%n" regfile)"
expect_eq "%s"        "7"                     "$("$BIN" stat -c "%s" regfile)"
expect_eq "%a regfile" "640"                  "$("$BIN" stat -c "%a" regfile)"
expect_eq "%a adir"    "755"                  "$("$BIN" stat -c "%a" adir)"
expect_eq "%A regfile" "-rw-r-----"           "$("$BIN" stat -c "%A" regfile)"
expect_eq "%A adir"    "drwxr-xr-x"           "$("$BIN" stat -c "%A" adir)"
expect_eq "%A alink"   "lrwxrwxrwx"           "$("$BIN" stat -c "%A" alink)"
expect_eq "%F regfile" "regular file"         "$("$BIN" stat -c "%F" regfile)"
expect_eq "%F adir"    "directory"            "$("$BIN" stat -c "%F" adir)"
expect_eq "%F alink"   "symbolic link"        "$("$BIN" stat -c "%F" alink)"

# %f hex raw mode — compare against GNU.
gnu_f=$(stat -c "%f" regfile)
my_f=$("$BIN" stat -c "%f" regfile)
expect_eq "%f matches GNU" "$gnu_f" "$my_f"

# --- numeric fields ---
gnu_uid=$(stat -c "%u" regfile)
gnu_gid=$(stat -c "%g" regfile)
gnu_ino=$(stat -c "%i" regfile)
gnu_h=$(stat -c "%h" regfile)
expect_eq "%u" "$gnu_uid" "$("$BIN" stat -c "%u" regfile)"
expect_eq "%g" "$gnu_gid" "$("$BIN" stat -c "%g" regfile)"
expect_eq "%i" "$gnu_ino" "$("$BIN" stat -c "%i" regfile)"
expect_eq "%h" "$gnu_h"   "$("$BIN" stat -c "%h" regfile)"

# --- epoch times ---
gnu_X=$(stat -c "%X" regfile)
gnu_Y=$(stat -c "%Y" regfile)
gnu_Z=$(stat -c "%Z" regfile)
expect_eq "%X" "$gnu_X" "$("$BIN" stat -c "%X" regfile)"
expect_eq "%Y" "$gnu_Y" "$("$BIN" stat -c "%Y" regfile)"
expect_eq "%Z" "$gnu_Z" "$("$BIN" stat -c "%Z" regfile)"

# --- %B always 512 on Linux ---
expect_eq "%B" "512" "$("$BIN" stat -c "%B" regfile)"

# %o (st_blksize) — compare to GNU.
gnu_o=$(stat -c "%o" regfile)
expect_eq "%o" "$gnu_o" "$("$BIN" stat -c "%o" regfile)"

# %b blocks — compare to GNU.
gnu_b=$(stat -c "%b" regfile)
expect_eq "%b" "$gnu_b" "$("$BIN" stat -c "%b" regfile)"

# --- %% literal ---
expect_eq "%%" "100% done" "$("$BIN" stat -c "100%% done" regfile)"

# --- literal text in format ---
expect_eq "literal mix" "size=7 mode=640" "$("$BIN" stat -c "size=%s mode=%a" regfile)"

# --- -c auto-newline ---
nl=$("$BIN" stat -c "%n" regfile alink | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "-c auto-newlines (2)" "2" "$nl"

# --- --printf interprets escapes, no auto-newline ---
out=$("$BIN" stat --printf="%n=%s\n" regfile)
expect_eq "--printf \\n"    "regfile=7"     "$out"

# Tab escape.
out=$("$BIN" stat --printf="%n\t%s" regfile)
expect_eq "--printf \\t"    "$(printf 'regfile\t7')" "$out"

# No auto-newline: count newlines emitted = the format's own.
nl=$("$BIN" stat --printf="%n" regfile alink | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "--printf no newlines" "0" "$nl"

# --- -L dereferences symlinks ---
expect_eq "-L on alink"     "regular file"   "$("$BIN" stat -L -c "%F" alink)"
expect_eq "no -L on alink"  "symbolic link"  "$("$BIN" stat -c "%F" alink)"

# Size differs under -L (link size is target-path-length; target file is 7).
expect_eq "-L size"         "7"              "$("$BIN" stat -L -c "%s" alink)"

# --- -t terse: 16 space-separated columns, GNU layout ---
cols=$("$BIN" stat -t regfile | awk '{print NF}')
expect_eq "terse 16 columns" "16" "$cols"

# First 14 columns should match GNU (15th is %W birth time which we
# don't have via stat(2) — documented deviation).
mine=$("$BIN" stat -t regfile | awk '{for(i=1;i<=14;i++) printf "%s ", $i; print ""}')
gnu=$(stat -t regfile     | awk '{for(i=1;i<=14;i++) printf "%s ", $i; print ""}')
expect_eq "terse columns 1-14 match GNU" "$gnu" "$mine"

# --- missing file ---
expect_exit "missing"      1 "$BIN" stat ghost
expect_exit "no operands"  2 "$BIN" stat

# --- multi-operand partial failure ---
rc=0
out=$("$BIN" stat -c "%n" regfile ghost alink 2>/dev/null) || rc=$?
expect_eq "partial-failure rc" "1" "$rc"
expected="regfile
alink"
expect_eq "partial-failure out" "$expected" "$out"

# --- unknown vs unimplemented specifiers (v1.2.1) ---
out=$("$BIN" stat -c "%q" regfile)
# ⚠ GNU prints '?' for an unknown specifier, NOT the source bytes — verified
# with `stat -c '%q'`. This case asserted "%q" until v1.2.1 and was wrong; the
# source comment it was written from claimed the literal echo was "GNU
# behaviour". A test that pins the wrong oracle is worse than no test.
# ⚠ Ask GNU rather than freezing its answer. The literal '?' is a parity claim
# about a default branch in GNU's stat.c — exactly the shape that let the
# `find -exec` argv[0] bug hide for two releases, where the local GNU's version
# decided whether the test passed. Comparing at runtime cannot go stale.
expect_eq "unknown %q matches GNU" "$(stat --format="%q" regfile 2>/dev/null)" "$out"

# ⛔ A specifier GNU DEFINES that kriya cannot render must not be echoed back as
# its own source text. `stat -c %y` printed the two bytes "%y" where a timestamp
# belonged and exited 0 — a script substituting that into a filename or a
# comparison got literal garbage with every sign of success.
# ⚠ %x/%y/%z LEFT THIS LIST AT v1.2.5 — they render now. The rest still need a
# passwd/group parser (%U/%G), a quoting helper (%N) or statx(2) (%w).
for spec in %U %G %N %w; do
    rc=0
    out=$("$BIN" stat -c "$spec" regfile 2>/dev/null) || rc=$?
    expect_eq "deferred $spec exits 1"     "1"  "$rc"
    expect_eq "deferred $spec prints none" ""   "$out"
done
# --- %x / %y / %z render (v1.2.5) ---
# ⚠ Compared under TZ=UTC on the GNU side: kriya is UTC-only until tzfile
# parsing lands (ADR 0007) and prints a literal +0000 offset. Under TZ=UTC the
# two are byte-identical; without it GNU renders local time and they differ by
# design, not by defect.
"$BIN" touch -t 202503151030.45 timespec_ref
for spec in %x %y %z; do
    expect_eq "stat $spec matches GNU (UTC)" \
        "$(TZ=UTC stat -c "$spec" timespec_ref)" "$("$BIN" stat -c "$spec" timespec_ref)"
done
expect_eq "combined format with %y" \
    "$(TZ=UTC stat -c '%n %s %y' timespec_ref)" "$("$BIN" stat -c '%n %s %y' timespec_ref)"
# Epoch zero, where the nanosecond padding is most likely to be wrong.
"$BIN" touch -t 197001010000 epoch_zero
expect_eq "stat %y at epoch zero" \
    "$(TZ=UTC stat -c %y epoch_zero)" "$("$BIN" stat -c %y epoch_zero)"

# ...while implemented ones are untouched.
expect_eq "%s still works" "$(stat -c %s regfile)" "$("$BIN" stat -c %s regfile)"
expect_eq "%n still works" "$(stat -c %n regfile)" "$("$BIN" stat -c %n regfile)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
