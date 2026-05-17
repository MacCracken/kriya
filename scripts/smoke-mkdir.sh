#!/bin/sh
# smoke-mkdir.sh — behavioural test for `kriya mkdir`.
#
# Unit tests in tests/kriya.tcyr cover the pure helpers
# (kriya_parse_octal_mode). End-to-end mkdir behaviour — actually
# creating directories, mode bits, error-path exit codes — needs a
# real filesystem, so it lives here. Modeled on bench-coldstart.sh.
#
# Exit 0 on full pass, non-zero on first failure.

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

# expect_eq <name> <expected> <actual>
expect_eq() {
    name=$1
    expected=$2
    actual=$3
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: expected '%s', got '%s'\n" "$name" "$expected" "$actual" >&2
    fi
}

# expect_exit <name> <expected_exit> <command...>
expect_exit() {
    name=$1
    expected=$2
    shift 2
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}

# expect_dir <name> <path>
expect_dir() {
    if [ -d "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' is not a directory\n" "$1" "$2" >&2
    fi
}

# expect_mode <name> <expected_octal> <path>
expect_mode() {
    actual=$(stat -c %a "$3" 2>/dev/null || stat -f %Lp "$3")
    # Strip leading zeros from comparator
    exp="$2"
    while [ "${exp#0}" != "$exp" ] && [ -n "${exp#0}" ]; do exp="${exp#0}"; done
    [ -z "$exp" ] && exp=0
    while [ "${actual#0}" != "$actual" ] && [ -n "${actual#0}" ]; do actual="${actual#0}"; done
    [ -z "$actual" ] && actual=0
    expect_eq "$1" "$exp" "$actual"
}

# --- happy paths ---
expect_exit "mkdir foo"           0 "$BIN" mkdir foo
expect_dir  "foo exists"          foo

expect_exit "mkdir -p a/b/c"      0 "$BIN" mkdir -p a/b/c
expect_dir  "a/b/c exists"        a/b/c

expect_exit "mkdir -p existing"   0 "$BIN" mkdir -p foo
expect_exit "mkdir -p /"          0 "$BIN" mkdir -p /

# Multiple operands; all succeed.
expect_exit "mkdir m1 m2"         0 "$BIN" mkdir m1 m2
expect_dir  "m1 exists"           m1
expect_dir  "m2 exists"           m2

# --- error paths ---
# Existing directory without -p is a failure (exit 1).
expect_exit "mkdir existing"      1 "$BIN" mkdir foo

# Missing parent without -p (exit 1).
expect_exit "mkdir missing parent" 1 "$BIN" mkdir nope/deep

# No operands (exit 2 — usage error).
expect_exit "no operands"         2 "$BIN" mkdir

# Bad octal mode (exit 2 — usage error).
expect_exit "bad mode"            2 "$BIN" mkdir -m bogus q1
expect_exit "octal 8 rejected"    2 "$BIN" mkdir -m 0888 q2

# Existing non-directory at intermediate component (exit 1).
: > afile
expect_exit "mkdir -p over file"  1 "$BIN" mkdir -p afile/sub

# Multiple operands, one fails — exit 1 but the other still created.
expect_exit "partial failure"     1 "$BIN" mkdir afile good1
expect_dir  "good1 created anyway" good1

# --- mode (-m) ---
expect_exit "mkdir -m 700 sec"    0 "$BIN" mkdir -m 700 sec
expect_mode "sec is 0700"         700 sec

expect_exit "mkdir -m 0755 pub"   0 "$BIN" mkdir -m 0755 pub
expect_mode "pub is 0755"         755 pub

# --p- only applies to the named (final) component, not intermediates.
# Intermediate dirs inherit the umask default; we don't assert their
# exact bits (depends on caller umask) — just that the final is right.
expect_exit "mkdir -p -m 700"     0 "$BIN" mkdir -p -m 700 inter/leaf
expect_mode "leaf is 0700"        700 inter/leaf

# --- verbose ---
out=$("$BIN" mkdir -v vdir 2>&1)
expect_eq "verbose output" "kriya mkdir: created directory 'vdir'" "$out"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
