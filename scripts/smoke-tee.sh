#!/bin/sh
# smoke-tee.sh — behavioural test for `kriya tee`.
#
# Covers single-file copy, multi-file fan-out, -a append vs default
# truncate, no-operand pass-through, large-input fidelity (>64KiB
# exercises the read/write loop), and resilient per-file failure
# semantics (one bad output doesn't break the others).

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

expect_file_match() {
    if cmp -s "$2" "$3"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' and '%s' differ\n" "$1" "$2" "$3" >&2
    fi
}

# --- basic single-file ---
stdout=$(echo "hello" | "$BIN" tee out1)
expect_eq "stdin echoed to stdout"  "hello" "$stdout"
expect_eq "file contains hello"     "hello" "$(cat out1)"

# --- multi-file fan-out ---
echo "fan" | "$BIN" tee a b c >/dev/null
expect_eq "a got content"  "fan" "$(cat a)"
expect_eq "b got content"  "fan" "$(cat b)"
expect_eq "c got content"  "fan" "$(cat c)"

# --- default truncates ---
echo "OLD" > truncme
echo "NEW" | "$BIN" tee truncme >/dev/null
expect_eq "default truncates"  "NEW" "$(cat truncme)"

# --- -a appends ---
echo "first" > app
echo "second" | "$BIN" tee -a app >/dev/null
expected="first
second"
expect_eq "-a appends"  "$expected" "$(cat app)"

# --- no operands: stdout pass-through ---
stdout=$(echo "pass" | "$BIN" tee)
expect_eq "no operands pass-through"  "pass" "$stdout"
# Exit 0 even with no operands.
expect_exit "no operands rc=0"  0 sh -c "echo x | '$BIN' tee"

# --- large input (>64KiB buffer; exercises read/write loop) ---
dd if=/dev/urandom of=big.in bs=1024 count=200 status=none
"$BIN" tee big.out < big.in > big.stdout
expect_file_match "200KB stdout matches"  big.in big.stdout
expect_file_match "200KB file matches"    big.in big.out

# Even larger — 5MiB — to confirm many-iteration loop.
dd if=/dev/urandom of=huge.in bs=1024 count=5000 status=none
"$BIN" tee huge.out < huge.in > huge.stdout
expect_file_match "5MiB stdout matches"   huge.in huge.stdout
expect_file_match "5MiB file matches"     huge.in huge.out

# --- resilient per-file failure: one bad doesn't break the others ---
touch readonly
chmod 0444 readonly
rc=0
echo "blocked" | "$BIN" tee readonly survivor >/dev/null 2>&1 || rc=$?
expect_eq "partial fail rc"         "1" "$rc"
expect_eq "survivor got data"       "blocked" "$(cat survivor)"
expect_eq "readonly unchanged"      "" "$(cat readonly)"

# --- writing to a directory operand fails cleanly ---
mkdir somedir
rc=0
echo "no" | "$BIN" tee somedir >/dev/null 2>&1 || rc=$?
expect_eq "dir target fails"        "1" "$rc"

# --- binary fidelity (NULs preserved) ---
printf 'one\x00two\x00three' > bin.in
"$BIN" tee bin.out < bin.in >/dev/null
expect_file_match "binary fidelity"  bin.in bin.out

# --- -a creates a new file if missing (open with O_CREAT|O_APPEND) ---
expect_exit "-a creates new"        0 sh -c "echo x | '$BIN' tee -a brand_new >/dev/null"
expect_eq "-a new file content"     "x" "$(cat brand_new)"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
