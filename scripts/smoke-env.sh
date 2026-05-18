#!/bin/sh
# smoke-env.sh — behavioural test for `kriya env`.
#
# Compares output cell-by-cell against GNU `env` for the shipped
# flag matrix (-i, -u, -0, --, NAME=VALUE assignments) and exec
# semantics (env REPLACES itself; exit 127 on ENOENT, 126 elsewhere).

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
        printf "FAIL %s:\nexpected: '%s'\ngot:      '%s'\n" "$1" "$2" "$3" >&2
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

# --- empty-env case: env -i with no command prints nothing ---
expect_eq "env -i prints nothing" "" "$("$BIN" env -i)"
expect_exit "env -i exit 0" 0 "$BIN" env -i

# --- env -i with assignments prints those assignments in order ---
out=$("$BIN" env -i A=1 B=2 C=3)
expect_eq "env -i ordered assignments" "A=1
B=2
C=3" "$out"

# --- exec with -i + assignments — child sees only what we set ---
out=$("$BIN" env -i FOO=hello /bin/sh -c 'echo "$FOO"')
expect_eq "env -i exec child sees FOO" "hello" "$out"

# --- exec without -i — child inherits + adds our assignment ---
out=$(PATH=/bin "$BIN" env GOTCHA=here /bin/sh -c 'echo "$PATH:$GOTCHA"')
expect_eq "env merge with PATH inherit" "/bin:here" "$out"

# --- -u removes an inherited var ---
out=$("$BIN" env -i FOO=keep BAR=drop -u BAR /bin/sh -c 'echo "FOO=$FOO BAR=${BAR-unset}"')
expect_eq "env -u drops named var" "FOO=keep BAR=unset" "$out"

# --- multiple -u and assignments interleave ---
out=$("$BIN" env -i A=1 B=2 -u A C=3 /bin/sh -c 'echo "${A-no} $B $C"')
expect_eq "env multi-u + assigns" "no 2 3" "$out"

# --- Long forms: --ignore-environment, --unset, --null ---
out=$("$BIN" env --ignore-environment FOO=long /bin/sh -c 'echo "$FOO"')
expect_eq "--ignore-environment long" "long" "$out"
out=$("$BIN" env -i A=1 B=2 --unset A /bin/sh -c 'echo "${A-no} $B"')
expect_eq "--unset long form" "no 2" "$out"
out=$("$BIN" env -i A=1 B=2 --unset=A /bin/sh -c 'echo "${A-no} $B"')
expect_eq "--unset=NAME eq form" "no 2" "$out"

# --- -0 / --null NUL-terminate print output ---
# od -c prints NUL as a single backslash-zero escape; one shell-escaped \\0.
nul=$("$BIN" env -i -0 A=1 B=2 | od -An -c | tr -s ' ' | head -1)
expect_eq "env -0 NUL-separator" " A = 1 \\0 B = 2 \\0" "$nul"
nul2=$("$BIN" env -i --null A=1 | od -An -c | tr -s ' ' | head -1)
expect_eq "env --null NUL-separator" " A = 1 \\0" "$nul2"

# --- `-` synonym for -i: check the printed env, not via /bin/sh
#     (which back-fills a default PATH when none is inherited).
out=$("$BIN" env - X=y | sort)
expect_eq "env - is -i synonym (print)" "X=y" "$out"

# --- `--` terminates options but NOT assignments ---
out=$("$BIN" env -i -- A=1 /bin/sh -c 'echo "$A"')
expect_eq "env -- still scans assignments" "1" "$out"

# --- PATH resolution: command without slash uses our modified PATH ---
out=$("$BIN" env -i PATH=/bin sh -c 'echo path-ok')
expect_eq "env PATH-resolution" "path-ok" "$out"

# --- Slash-cmd bypasses PATH ---
out=$("$BIN" env -i /bin/echo direct)
expect_eq "env absolute path" "direct" "$out"

# --- env replaces itself: child sees env's own PID (no fork) ---
parent_pid=$$
out=$("$BIN" env -i PARENT=$$ /bin/sh -c 'echo "$PPID:$PARENT"')
# We can't trivially assert PID equality from a subshell, but we can
# verify the child inherited PARENT and exists.
case "$out" in
    *:$parent_pid) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL parent-pid passthrough: got '$out'" >&2 ;;
esac

# --- override existing inherited value ---
out=$(FOO=stale "$BIN" env FOO=fresh /bin/sh -c 'echo "$FOO"')
expect_eq "env override existing" "fresh" "$out"

# --- exit codes ---
expect_exit "env empty no-cmd"      0 "$BIN" env -i
expect_exit "env -i true"           0 "$BIN" env -i /bin/true
expect_exit "env -i false"          1 "$BIN" env -i /bin/false
expect_exit "env nonexistent cmd"   127 "$BIN" env -i nosuchcommand
expect_exit "env unknown short"     2 "$BIN" env -Q
expect_exit "env unknown long"      2 "$BIN" env --no-such-flag
expect_exit "env -u no arg"         2 "$BIN" env -u
expect_exit "env --unset no arg"    2 "$BIN" env --unset
expect_exit "env -u empty NAME"     2 "$BIN" env -u ''

# --- Clustered short options: -iu works (i + u-needing-arg).
#     Verify via env-print rather than /bin/sh — sh back-fills PATH when
#     unset, masking whether we unset it ourselves.
out=$("$BIN" env -iu PATH FOO=clustered | sort)
expect_eq "env -iu clustered (print)" "FOO=clustered" "$out"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
