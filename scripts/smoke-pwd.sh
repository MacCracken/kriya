#!/bin/sh
# smoke-pwd.sh — behavioural test for `kriya pwd`.
#
# ⛔ The oracle is `/usr/bin/pwd`, NEVER the shell builtin. `pwd` is a builtin in
# every POSIX shell, so a bare `pwd` in this script measures the shell — and the
# builtin's default is `-L` while GNU's binary defaults to `-P`, which is
# precisely the distinction under test.

set -e

# ⛔ POSIXLY_CORRECT FLIPS GNU `pwd` FROM -P TO -L, which is the exact axis under
# test — a host exporting it turns every default-mode comparison below into a
# comparison of two different modes. kriya matches GNU's DEFAULT and declines
# the variable (ADR 0011's reasoning: an environment variable set for some
# unrelated tool should not silently change what this one prints), so the oracle
# has to decline it too.
unset POSIXLY_CORRECT

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"
GNU=/usr/bin/pwd

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi
if [ ! -x "$GNU" ]; then
    echo "skip: no /usr/bin/pwd to compare against"
    echo "0 passed, 0 failed (0 total)"
    exit 0
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
        printf "FAIL %s:\nexpected: '%s'\ngot:      '%s'\n" "$1" "$2" "$3" >&2
    fi
}

mkdir -p real
ln -s real sym

# Compare kriya against GNU with an explicitly controlled environment.
same() {
    label=$1; shift
    g=$(cd "$WORK/sym" && env "$@" "$GNU" 2>&1)
    k=$(cd "$WORK/sym" && env "$@" "$BIN" pwd 2>&1)
    expect_eq "pwd: $label" "$g" "$k"
}

# ⛔ THE DEFAULT IS PHYSICAL. POSIX says `pwd` defaults to `-L`; GNU deliberately
# does not, and kriya follows GNU — from inside a symlinked directory the
# default prints the RESOLVED path. ⚠ kriya defaulted to LOGICAL before 1.5.3.
same "default from a symlinked dir"  PWD="$WORK/sym"
same "default, PWD unset"            -u PWD
# ⛔ ...and the logical form VALIDATES \$PWD rather than trusting it. All three
# of these must fall back to the physical path: kriya used to echo \$PWD back
# whenever it merely began with a `/`, so `PWD=/etc pwd` printed `/etc` from a
# completely different directory.
same "default, PWD names another dir" PWD=/etc
same "default, PWD relative"          PWD=relative
same "default, PWD contains .."       PWD="$WORK/real/../real"

lsame() {
    label=$1; shift
    g=$(cd "$WORK/sym" && env "$@" "$GNU" -L 2>&1)
    k=$(cd "$WORK/sym" && env "$@" "$BIN" pwd -L 2>&1)
    expect_eq "pwd -L: $label" "$g" "$k"
}
lsame "valid \$PWD is used"      PWD="$WORK/sym"
lsame "\$PWD naming another dir" PWD=/etc
lsame "\$PWD relative"           PWD=relative
lsame "\$PWD with .."            PWD="$WORK/real/../real"
lsame "\$PWD unset"              -u PWD

psame() {
    label=$1; shift
    g=$(cd "$WORK/sym" && env "$@" "$GNU" -P 2>&1)
    k=$(cd "$WORK/sym" && env "$@" "$BIN" pwd -P 2>&1)
    expect_eq "pwd -P: $label" "$g" "$k"
}
psame "ignores a valid \$PWD"    PWD="$WORK/sym"

# ⚠ -L and -P must actually DIFFER here, or every assertion above would pass for
# an implementation that ignored both flags.
lv=$(cd "$WORK/sym" && PWD="$WORK/sym" "$BIN" pwd -L)
pv=$(cd "$WORK/sym" && PWD="$WORK/sym" "$BIN" pwd -P)
if [ "$lv" = "$pv" ]; then
    FAIL=$((FAIL + 1)); printf 'FAIL pwd: -L and -P produced the same path\n' >&2
else
    PASS=$((PASS + 1))
fi

# Operands are a usage error.
rc=0; "$BIN" pwd extra >/dev/null 2>&1 || rc=$?
expect_eq "pwd: an operand is a usage error" "2" "$rc"

TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
