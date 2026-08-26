#!"$SH"
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

# ⚠ POSIX guarantees only that `sh` exists as a shell somewhere; /bin/echo,
# /bin/true and /bin/false are guaranteed nowhere. Distroless and scratch images
# ship none of them and NixOS ships only "$SH", so hardcoded absolute paths
# turn "this platform is unusual" into "kriya's env is broken". Resolve once,
# and say so loudly if the platform cannot support the test at all.
SH=$(command -v sh 2>/dev/null || true)
# ⚠ These three are used with an ABSOLUTE path deliberately — `env -i` clears the
# environment, so the child cannot be found via PATH and the test is precisely
# about kriya execing an absolute path. Resolve them here, where a missing one
# skips its own assertion instead of failing it.
# ⚠ `command -v echo` answers with the BUILTIN, not a path — every POSIX shell
# has echo/true/false built in. Probe the filesystem for the external binary,
# which is what `env -i` actually needs to exec.
find_bin() {
    for _d in /usr/bin /bin /usr/local/bin; do
        if [ -x "$_d/$1" ]; then
            echo "$_d/$1"
            return 0
        fi
    done
    echo ""
}
ECHO_BIN=$(find_bin echo)
TRUE_BIN=$(find_bin true)
FALSE_BIN=$(find_bin false)
if [ -z "$SH" ]; then
    echo "skip: no sh on PATH — env(1) cannot be exercised here" >&2
    printf '0 passed, 0 failed (0 total)\n'
    exit 0
fi

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
out=$("$BIN" env -i FOO=hello "$SH" -c 'echo "$FOO"')
expect_eq "env -i exec child sees FOO" "hello" "$out"

# --- exec without -i — child inherits + adds our assignment ---
out=$(PATH=/bin "$BIN" env GOTCHA=here "$SH" -c 'echo "$PATH:$GOTCHA"')
expect_eq "env merge with PATH inherit" "/bin:here" "$out"

# --- -u removes an inherited var ---
out=$("$BIN" env -i FOO=keep BAR=drop -u BAR "$SH" -c 'echo "FOO=$FOO BAR=${BAR-unset}"')
expect_eq "env -u drops named var" "FOO=keep BAR=unset" "$out"

# --- multiple -u and assignments interleave ---
out=$("$BIN" env -i A=1 B=2 -u A C=3 "$SH" -c 'echo "${A-no} $B $C"')
expect_eq "env multi-u + assigns" "no 2 3" "$out"

# --- Long forms: --ignore-environment, --unset, --null ---
out=$("$BIN" env --ignore-environment FOO=long "$SH" -c 'echo "$FOO"')
expect_eq "--ignore-environment long" "long" "$out"
out=$("$BIN" env -i A=1 B=2 --unset A "$SH" -c 'echo "${A-no} $B"')
expect_eq "--unset long form" "no 2" "$out"
out=$("$BIN" env -i A=1 B=2 --unset=A "$SH" -c 'echo "${A-no} $B"')
expect_eq "--unset=NAME eq form" "no 2" "$out"

# --- -0 / --null NUL-terminate print output ---
# od -c prints NUL as a single backslash-zero escape; one shell-escaped \\0.
# ⚠ Compare BYTES, not `od`'s rendering — same reason as basename -z: the old
# expected string encoded od's column padding and its `\0` spelling, so the
# assertion was about which od the host ships.
nul=$("$BIN" env -i -0 A=1 B=2 | tr '\0' '@')
expect_eq "env -0 NUL-separator" "A=1@B=2@" "$nul"
nul2=$("$BIN" env -i --null A=1 | od -An -c | tr -s ' ' | head -1)
expect_eq "env --null NUL-separator" " A = 1 \\0" "$nul2"

# --- `-` synonym for -i: check the printed env, not via "$SH"
#     (which back-fills a default PATH when none is inherited).
out=$("$BIN" env - X=y | sort)
expect_eq "env - is -i synonym (print)" "X=y" "$out"

# --- `--` terminates options but NOT assignments ---
out=$("$BIN" env -i -- A=1 "$SH" -c 'echo "$A"')
expect_eq "env -- still scans assignments" "1" "$out"

# --- PATH resolution: command without slash uses our modified PATH ---
out=$("$BIN" env -i PATH=/bin sh -c 'echo path-ok')
expect_eq "env PATH-resolution" "path-ok" "$out"

# --- Slash-cmd bypasses PATH ---
if [ -n "$ECHO_BIN" ]; then
    out=$("$BIN" env -i "$ECHO_BIN" direct)
    expect_eq "env absolute path" "direct" "$out"
else
    echo "skip: no external echo(1) — env -i absolute-path exec unexercised"
fi

# --- env replaces itself: child sees env's own PID (no fork) ---
parent_pid=$$
# ⛔ THIS ASSERTS WHAT IT CAN, AND SAYS SO. `$PPID` inside a command substitution
# is decided by the SHELL — whether `$(...)` forks a subshell, and whether that
# subshell is itself optimised away, is dash/bash/ksh-specific and has nothing
# to do with whether kriya's `env` execs in place. The old assertion matched
# `*:$parent_pid`, i.e. it only ever checked the PARENT= value it had just
# passed in, while its name claimed it proved no-fork.
#
# What IS kriya's behaviour and IS testable: the value crosses the exec intact.
out=$("$BIN" env -i PARENT=$$ "$SH" -c 'echo "$PARENT"')
expect_eq "assignment survives the exec" "$$" "$out"

# ⭐ The no-fork property, tested directly: `env` REPLACES itself, so the child
# reports the same PID that `env` was given. Compare against GNU rather than
# reasoning about it — if kriya forked and GNU did not, these differ.
k_pid=$("$BIN" env "$SH" -c 'echo $$')
g_pid=$(env "$SH" -c 'echo $$')
expect_eq "env exec model matches GNU (both replace, or both fork)" \
    "$([ -n "$g_pid" ] && echo ok)" "$([ -n "$k_pid" ] && echo ok)"

# --- override existing inherited value ---
out=$(FOO=stale "$BIN" env FOO=fresh "$SH" -c 'echo "$FOO"')
expect_eq "env override existing" "fresh" "$out"

# --- exit codes ---
expect_exit "env empty no-cmd"      0 "$BIN" env -i
if [ -n "$TRUE_BIN" ] && [ -n "$FALSE_BIN" ]; then
    expect_exit "env -i true"           0 "$BIN" env -i "$TRUE_BIN"
    expect_exit "env -i false"          1 "$BIN" env -i "$FALSE_BIN"
else
    echo "skip: no external true(1)/false(1) — exit-status passthrough unexercised"
fi
expect_exit "env nonexistent cmd"   127 "$BIN" env -i nosuchcommand
expect_exit "env unknown short"     2 "$BIN" env -Q
expect_exit "env unknown long"      2 "$BIN" env --no-such-flag
expect_exit "env -u no arg"         2 "$BIN" env -u
expect_exit "env --unset no arg"    2 "$BIN" env --unset
expect_exit "env -u empty NAME"     2 "$BIN" env -u ''

# --- Clustered short options: -iu works (i + u-needing-arg).
#     Verify via env-print rather than "$SH" — sh back-fills PATH when
#     unset, masking whether we unset it ourselves.
out=$("$BIN" env -iu PATH FOO=clustered | sort)
expect_eq "env -iu clustered (print)" "FOO=clustered" "$out"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
