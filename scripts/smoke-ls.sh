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

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
