#!/bin/sh
# smoke-write-errors.sh — a failed write must never exit 0.
#
# ⛔ THE BUG THIS PINS: every applet shares one writer (`k_write`), none of the
# ~540 call sites check its return, and the dispatcher used to exit on whatever
# the applet returned. So a full disk produced TRUNCATED OUTPUT AND EXIT 0 — the
# worst shape available, because the caller's `&&` chain proceeds on a lie.
# Fixed at v1.1.11 by a sticky flag in `k_write` that `main()` consults once.
#
# `/dev/full` is the portable way to force ENOSPC on every write. It exists on
# Linux and in GitHub's ubuntu-latest runners; where it does not, the script
# skips rather than failing, so it stays honest about what it actually proved.
#
# ⚠ EPIPE is deliberately NOT covered here. kriya leaves SIGPIPE at its default
# disposition, so `kriya yes | head` is killed by the signal (141, matching GNU)
# and the write never returns an error at all. That is tested below as a
# regression guard, because the obvious "fix" to this class — reporting every
# write failure — would have broken it.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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

# expect_full NAME UTIL [ARGS...] — run with stdout on /dev/full; expect exit 1
# and a "write error" line on stderr.
# stdin is always redirected from a real file: applets that ignore it are
# unaffected, and `tr` (which reads it) would otherwise block on the terminal.
# Every invocation is bounded so a regression fails the suite instead of
# hanging it.
expect_full() {
    name=$1
    shift
    rc=0
    err=$(timeout 10 "$BIN" "$@" <"$WORK/f" 2>&1 >/dev/full) || rc=$?
    expect_eq "$name exit 1" "1" "$rc"
    # Either message is correct. `sort` and `tr` already noticed the failed
    # write themselves and report it in their own vocabulary ("(write): no
    # space left on device"); the dispatcher's generic "write error" line is
    # the net under every applet that does not. What must never happen is
    # silence.
    case "$err" in
        *"write error"*)               PASS=$((PASS + 1)) ;;
        *"no space left on device"*)   PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf "FAIL %s: stderr reported nothing: %s\n" "$name" "$err" >&2 ;;
    esac
}

if [ ! -w /dev/full ]; then
    echo "skip: /dev/full unavailable — write-error cases not exercised"
else
    printf 'alpha\nbeta\ngamma\n' > "$WORK/f"

    # ⚠ `head -n 2` / `cut -c 1-3` are spelled with a SEPARATE value on purpose.
    # kriya's option parser does not yet take attached short values (`-n2`) or
    # the obsolescent bare-digit form (`head -2`) — both are named follow-ups
    # under roadmap M12b. Using them here would test the parser, not the writer.

    expect_full "echo"    echo hello
    expect_full "printf"  printf 'hi\n'
    expect_full "seq"     seq 1 5
    expect_full "wc"      wc -l "$WORK/f"
    expect_full "ls"      ls "$WORK"
    expect_full "head"    head -n 2 "$WORK/f"
    expect_full "sort"    sort "$WORK/f"
    expect_full "uniq"    uniq "$WORK/f"
    expect_full "nl"      nl "$WORK/f"
    expect_full "cut"     cut -c 1-3 "$WORK/f"
    expect_full "tr"      tr a-z A-Z
    expect_full "grep"    grep alpha "$WORK/f"

    # Matches GNU: same exit status, same message shape.
    gnu_rc=0; timeout 10 seq 1 5 >/dev/full 2>/dev/null || gnu_rc=$?
    kri_rc=0; timeout 10 "$BIN" seq 1 5 >/dev/full 2>/dev/null || kri_rc=$?
    expect_eq "seq matches GNU exit status" "$gnu_rc" "$kri_rc"

    # A utility that already detected its own failure keeps its own exit code —
    # the sticky flag is a net under success, not an override.
    rc=0; timeout 10 "$BIN" cp /nonexistent "$WORK/dst" >/dev/null 2>&1 || rc=$?
    expect_eq "cp keeps its own failure code" "1" "$rc"

    # Success on a healthy fd is untouched.
    rc=0; timeout 10 "$BIN" echo ok >/dev/null 2>&1 || rc=$?
    expect_eq "healthy write still exits 0" "0" "$rc"
fi

# --- SIGPIPE regression guard -----------------------------------------
# The producer must do whatever GNU does. ⚠ At the DEFAULT SIGPIPE disposition
# that is death by signal (128+13=141) and a flip to 1 would mean the sticky flag
# had started swallowing EPIPE. But when the parent IGNORES SIGPIPE the write
# returns EPIPE, nothing is killed, and GNU exits 1 as well — so the test asserts
# parity with GNU and checks the absolute only when GNU shows 141.
# Getting the PRODUCER's status out of a pipeline, in POSIX sh. Process
# substitution (`> >(...)`) is a bashism and every other smoke script here runs
# under /bin/sh, which is dash on the CI runner; a plain pipeline reports only
# the LAST command's status. So the producer records its own status into a file
# from inside the pipeline, and we read it afterwards.
# ⚠ `|| st=$?` is load-bearing, not defensive style. This script runs under
# `set -e`, the producer is EXPECTED to die on SIGPIPE (141), and a bare
# `timeout ...` would abort the subshell at that non-zero status before it could
# record it — leaving the status file absent and the assertion comparing against
# an empty string. Making it the left side of `||` takes it out of `set -e`'s
# reach and captures the value in the same step.
run_producer() {
    rm -f "$WORK/rc"
    { st=0; timeout 10 "$@" 2>/dev/null || st=$?; echo "$st" > "$WORK/rc"; } | head -1 > /dev/null
}

# ⛔ GNU FIRST — it is both the oracle AND the probe for this environment's
# SIGPIPE disposition. 141 is a property of the ENVIRONMENT, not of `yes`: if the
# parent has SIGPIPE at SIG_IGN, write() returns EPIPE instead of the kernel
# killing the writer, and GNU `yes` exits 1 there too. SIG_IGN survives execve
# (only installed handlers reset to SIG_DFL) and POSIX forbids a non-interactive
# shell from resetting a signal ignored at entry — so `trap - PIPE` does NOT
# undo it. This script asserted a hardcoded 141 and went red on a CI runner whose
# parent process ignores SIGPIPE, while kriya was matching GNU exactly.
#
# Verified both ways on the dev box: SIGPIPE default -> GNU 141, kriya 141;
# SIGPIPE ignored -> GNU 1, kriya 1. Parity in both; the absolute only in one.
run_producer yes
gnu_rc=$(cat "$WORK/rc" 2>/dev/null || echo MISSING)

run_producer "$BIN" yes
rc=$(cat "$WORK/rc" 2>/dev/null || echo MISSING)

# The invariant that holds in ANY signal environment: kriya does what GNU does.
expect_eq "yes into closed pipe matches GNU" "$gnu_rc" "$rc"

# ...and never the silent lie the sticky flag exists to prevent.
if [ "$rc" = "0" ]; then
    FAIL=$((FAIL + 1)); printf "FAIL yes into closed pipe exited 0\n" >&2
else
    PASS=$((PASS + 1))
fi

# The strong form, only where the signal is actually deliverable. Skipping
# honestly beats asserting an absolute the environment controls — the same
# idiom this script already uses for an absent /dev/full.
if [ "$gnu_rc" = "141" ]; then
    expect_eq "yes into closed pipe dies on SIGPIPE" "141" "$rc"
else
    echo "skip: parent ignores SIGPIPE (GNU yes exited $gnu_rc) — signal-death path not exercised"
fi

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
