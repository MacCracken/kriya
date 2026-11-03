#!/bin/sh
# smoke-du.sh — behavioural test for `kriya du`.
#
# Compares output cell-by-cell against GNU `du` for the shipped flag
# matrix. Tree built fresh under WORK with deterministic file sizes
# (small 5-byte text + 4 KiB binary + nested-deep + side-branch).

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

# ⚠ `set -e` is on and this was a bare command, so THREE host dependencies were
# each fatal to the whole script rather than to one assertion: /dev/urandom
# existing (absent in a minimal chroot or an unpopulated initramfs — precisely
# the environments an AGNOS-targeted toolset runs in), `dd` existing, and `dd`
# accepting `status=none` (a GNU extension busybox's dd rejects). Random bytes
# are the better fixture where they are available, so probe rather than assume,
# and fall back to a deterministic payload the shell alone can produce.
gen_payload() {   # gen_payload <path> <kib>
    if [ -r /dev/urandom ] && head -c 1024 /dev/urandom >/dev/null 2>&1; then
        head -c $(( $2 * 1024 )) /dev/urandom > "$1"
    else
        : > "$1"
        _i=0
        while [ "$_i" -lt "$2" ]; do
            printf '%01024d' "$_i" >> "$1"
            _i=$((_i + 1))
        done
    fi
}

# Build a deterministic tree.
mkdir -p a/b/c d
echo "small" > a/file1
head -c 4096 /dev/urandom > a/big
echo "deep" > a/b/c/deeper
echo "side" > d/file
gen_payload big5m 5120
# ⛔ `du` compares st_blocks, which is NOT stable until writeback. Under delayed
# allocation — ext4 delalloc, and far more visibly btrfs and XFS, where a fresh
# file can report 0 blocks — kriya and GNU can sample the same file on opposite
# sides of the flush and disagree about a file neither of them touched.
# Cheap insurance; the fixtures are built once.
sync 2>/dev/null || true

PASS=0
FAIL=0

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nexpected:\n%s\ngot:\n%s\n" "$1" "$2" "$3" >&2
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

# `du`'s subtree-traversal order isn't ABI-stable across filesystems,
# so we sort both outputs by path before comparing.
sorted_check() {
    name=$1
    shift
    k=$("$BIN" du "$@" | sort -k2)
    # ⛔ GNU du's DEFAULT BLOCK SIZE IS ENVIRONMENT-CONTROLLED and kriya's is not.
    # Measured on a 5-byte file: plain `du` prints 4, `POSIXLY_CORRECT=1 du`
    # prints 8 (512-byte units), `BLOCK_SIZE=1 du` prints 4096. kriya prints 4
    # in all three. So on any host exporting one of these — and POSIXLY_CORRECT
    # is not exotic — every one of the ~30 cell-by-cell comparisons below fails
    # at once, blaming kriya for the shell's environment.
    # ⚠ Pin the oracle's environment rather than kriya's: the comparison is
    # about du's ARITHMETIC, not about which units the caller asked for.
    g=$(env -u POSIXLY_CORRECT -u DU_BLOCK_SIZE -u BLOCK_SIZE du "$@" | sort -k2)
    expect_eq "$name" "$g" "$k"
}

# --- Default: per-dir entries only, 1024-byte blocks ---
sorted_check "default ."                .
sorted_check "default a"                a
sorted_check "default a b"              a d
sorted_check "default single file"      a/file1

# --- -s summary ---
sorted_check "du -s ."                  -s .
sorted_check "du -s a d"                -s a d
sorted_check "du -s file"               -s a/file1

# --- -a all entries ---
sorted_check "du -a"                    -a .
sorted_check "du -a -s"                 -a -s .
sorted_check "du -a a"                  -a a

# --- -h human-readable ---
sorted_check "du -h"                    -h .
sorted_check "du -h big5m"              -h big5m
sorted_check "du -h a/big"              -h a/big
sorted_check "du -ah"                   -ah .

# --- -b apparent size ---
sorted_check "du -b a/file1"            -b a/file1
sorted_check "du -b a"                  -b a

# --- -c grand total ---
sorted_check "du -c a d"                -c a d
sorted_check "du -sc a d"               -sc a d
sorted_check "du -c file"               -c a/file1

# --- -d max-depth ---
sorted_check "du -d 0"                  -d 0 .
sorted_check "du -d 1"                  -d 1 .
sorted_check "du -d 2"                  -d 2 .

# --- -S separate-dirs ---
sorted_check "du -S"                    -S .

# --- Symlink policy: -P default (no follow) vs -L follow ---
ln -s a alink
mkdir -p targetdir
echo "x" > targetdir/file
ln -s targetdir lnkdir
# Default -P treats lnkdir as a symlink (size of link text).
sorted_check "du default symlink"       lnkdir
sorted_check "du -L symlink follow"     -L lnkdir

# --- Long-form options ---
sorted_check "--summarize"              --summarize a
sorted_check "--all"                    --all a
sorted_check "--total"                  --total a d
sorted_check "--bytes"                  --bytes a/file1
sorted_check "--human-readable"         --human-readable a
sorted_check "--max-depth=1"            --max-depth=1 .

# --- Exit codes ---
expect_exit "du missing file"       1 "$BIN" du nope
expect_exit "du unknown flag"       2 "$BIN" du -Z .
expect_exit "du unknown long"       2 "$BIN" du --bogus .
expect_exit "du -d no arg"          2 "$BIN" du -d
expect_exit "du --max-depth=bad"    2 "$BIN" du --max-depth=abc .

# --- Default-to-`.` when no operand ---
k=$("$BIN" du | sort -k2)
# ⚠ Same environment pin as `sorted_check` — this one bypassed the helper.
g=$(env -u POSIXLY_CORRECT -u DU_BLOCK_SIZE -u BLOCK_SIZE du | sort -k2)
expect_eq "du with no operand" "$g" "$k"

# --- 1.6.16: -d past 2^63 is refused, not wrapped ---------------------------
#
# ⛔ `du -d 18446744073709551617` RAN AT DEPTH ONE, exit 0, where GNU refuses the
# number. Blanks and a `+` in front are GNU's too. ⚠ Two GNU readings stay
# refused: a negative depth (GNU clamps it to 0) and hex/octal (GNU reads base 0).
mkdir -p d16/a/b/c && printf 'x' > d16/a/b/c/f
d16_same() {   # d16_same <label> <du args...>
    _l=$1; shift
    _grc=0; du "$@" > d16_g.out 2>/dev/null || _grc=$?
    _krc=0; "$BIN" du "$@" > d16_k.out 2>/dev/null || _krc=$?
    if cmp -s d16_g.out d16_k.out && [ "$_grc" = "$_krc" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); printf 'FAIL %s: GNU exit %s, kriya exit %s\n' "$_l" "$_grc" "$_krc" >&2; fi
}
for _v in 0 1 ' 1' '+1' 9223372036854775807; do
    d16_same "du -d '$_v'" -d "$_v" d16
    d16_same "du --max-depth='$_v'" "--max-depth=$_v" d16
done
for _v in 9223372036854775808 18446744073709551616 18446744073709551617 99999999999999999999 '' 1x; do
    expect_exit "du -d '$_v' refused" 2 "$BIN" du -d "$_v" d16
    _grc=0; du -d "$_v" d16 >/dev/null 2>&1 || _grc=$?
    expect_eq "...and by GNU" "yes" "$([ "$_grc" != 0 ] && echo yes || echo no)"
done
expect_exit "du -d -1 refused (GNU clamps to 0)" 2 "$BIN" du -d -1 d16
expect_exit "du -d 0x2 refused (GNU reads hex)"  2 "$BIN" du -d 0x2 d16
err=$("$BIN" du -d 18446744073709551617 d16 2>&1 >/dev/null || true)
expect_eq "du -d diagnostic" "kriya du: 18446744073709551617: invalid maximum depth" "$err"

# --- --exclude, -X, --inodes, -0, -x (1.8.3) ---------------------------
# Measured against coreutils 9.4 and 9.7: identical on every case here.
rm -rf ex; mkdir -p ex/t/a/sub ex/t/b
gen_payload ex/t/x.o 5; gen_payload ex/t/a/y.o 9; gen_payload ex/t/a/sub/z.c 3; : > ex/t/b/k
ln ex/t/x.o ex/t/a/hard
printf '*.o\nsub  \n\n' > ex/pats
cd ex
sorted_check "--exclude='*.o'"                  -a --exclude='*.o' t
sorted_check "--exclude=sub (a directory, not entered)" -a --exclude=sub t
sorted_check "--exclude=a/sub (a path suffix)"  -a --exclude=a/sub t
sorted_check "--exclude=t/a"                    -a --exclude=t/a t
sorted_check "--exclude='*/a' (* crosses /)"    -a --exclude='*/a' t
sorted_check "--exclude='?.o'"                  -a --exclude='?.o' t
sorted_check "--exclude='[xy].o'"               -a --exclude='[xy].o' t
sorted_check "--exclude twice"                  -a --exclude='*.o' --exclude=sub t
sorted_check "--exclude PATTERN (separate word)" -a --exclude '*.o' t
sorted_check "--exclude with -s"                -s --exclude='*.o' t
sorted_check "--exclude='\\*.o' (escaped: literal)" -a --exclude='\*.o' t
sorted_check "--exclude='sub/' (matches nothing)" -a --exclude='sub/' t
sorted_check "--exclude naming the operand prints nothing" --exclude=t t
sorted_check "-X FILE (trailing blanks trimmed, blank lines skipped)" -a -X pats t
sorted_check "--exclude-from=FILE"              -a --exclude-from=pats t
_k=0; "$BIN" du -X nosuch t >/dev/null 2>&1 || _k=$?
expect_eq "-X of a missing file: exit 1, as GNU" "1" "$_k"
sorted_check "--inodes"                         --inodes t
sorted_check "--inodes -a (a hard link once)"   --inodes -a t
sorted_check "--inodes -s"                      --inodes -s t
sorted_check "--inodes -c"                      --inodes -c t t/a
sorted_check "--inodes -l"                      --inodes -sl t
sorted_check "--inodes -S"                      --inodes -S t
sorted_check "--inodes -d 1"                    --inodes -d 1 t
sorted_check "--inodes -b (ignored, with a warning)" --inodes -sb t
_ke=$("$BIN" du --inodes -sb t 2>&1 >/dev/null)
expect_eq "--inodes -b warns in GNU's words" "kriya du: warning: options --apparent-size and -b are ineffective with --inodes" "$_ke"
expect_eq "--inodes -h humanizes the count in powers of 1024, as GNU" \
    "$(env -u POSIXLY_CORRECT -u DU_BLOCK_SIZE -u BLOCK_SIZE du --inodes -sh "$ROOT/src")" "$("$BIN" du --inodes -sh "$ROOT/src")"
expect_eq "-0 ends each line with NUL" "$(du -0 t | od -c)" "$("$BIN" du -0 t | od -c)"
expect_eq "--null -a -c"               "$(du --null -a -c t | od -c)" "$("$BIN" du --null -a -c t | od -c)"
cd ..
# -x needs a mount point inside the tree, without privileges: /dev's pts, shm and mqueue mounts.
if [ "$(stat -c %d /dev)" != "$(stat -c %d /dev/pts 2>/dev/null)" ] 2>/dev/null; then
    expect_eq "du -xa /dev omits the /dev/pts mount, as GNU" "$(du -xa /dev 2>/dev/null | sort)" "$("$BIN" du -xa /dev 2>/dev/null | sort)"
    expect_eq "...which -a without -x lists" "1|0" \
        "$("$BIN" du -a /dev 2>/dev/null | grep -c '/dev/pts$')|$("$BIN" du -xa /dev 2>/dev/null | grep -c '/dev/pts$')"
else
    echo "skip: /dev/pts is not a separate mount here -- du -x is not exercised"
fi

# --- the walk's memory (1.8.3) -----------------------------------------
# ⛔ The walk allocated a 4 KiB getdents buffer per directory and a path per entry and freed
# neither: `du -s /usr` peaked at 72 MB (GNU 7.6). Over 6,000 directories the 1.8.2 walk
# needs over 32 MB of address space and dies of SIGSEGV under that cap; the reusing walk runs
# in under 24 MB.
rm -rf many; mkdir many
seq 1 6000 | sed 's|^|many/d|' | xargs mkdir
_rc=0; ( ulimit -v 32768 2>/dev/null; "$BIN" du -s many >/dev/null 2>&1 ) || _rc=$?
expect_eq "du -s over 6,000 directories fits in 32 MB of address space" "0" "$_rc"
expect_eq "...and its total is GNU's" "$(du -s many | cut -f1)" "$("$BIN" du -s many | cut -f1)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
