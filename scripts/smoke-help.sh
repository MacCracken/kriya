#!/bin/sh
# smoke-help.sh — `--help` across every utility, per ADR 0002.
#
# ⭐ The OPTIONS table is READ BACK OUT OF THE FLAGS SPEC each utility already
# builds for the parser, so it cannot drift from what the parser accepts. What
# the spec cannot supply — summary, synopsis, operand prose, exit codes,
# examples — is declared per utility next to the flags.
#
# ⚠ `-h` IS NOT HELP and must never become it: ADR 0002 reassigns `-h` per
# utility (`du -h`, `ls -h`, `sort -h` all mean human-readable). That is pinned
# below, because "add -h as an alias" is the obvious-looking change that would
# silently break three utilities.

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

ALL="true false echo pwd yes sleep mkdir rmdir touch ln cp rm mv basename dirname
     realpath readlink which stat ls tee wc head tail nl uniq tr cut sort printf
     grep find xargs seq env date du df"

# --- every utility answers, with the ADR-0002 sections ------------------
for u in $ALL; do
    rc=0
    out=$("$BIN" "$u" --help 2>&1) || rc=$?
    expect_eq "$u --help exits 0" "0" "$rc"
    expect_eq "$u --help starts at NAME" "NAME" "$(printf '%s\n' "$out" | head -1)"
    # NAME must carry the utility's own name, not a stale copy from elsewhere.
    case "$(printf '%s\n' "$out" | sed -n 2p)" in
        *"$u "*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf "FAIL %s: NAME line lacks the utility name\n" "$u" >&2 ;;
    esac
    for sect in SYNOPSIS DESCRIPTION "EXIT CODES" EXAMPLES; do
        case "$out" in
            *"$sect"*) PASS=$((PASS + 1)) ;;
            *) FAIL=$((FAIL + 1)); printf "FAIL %s: no %s section\n" "$u" "$sect" >&2 ;;
        esac
    done
done

# --- the OPTIONS table matches the parser ------------------------------
# ⚠ Sampled rather than exhaustive: the point is that the table comes FROM the
# spec, so one utility proving the wiring proves it for all of them.
help_ls=$("$BIN" ls --help)
case "$help_ls" in
    *"-a, --all"*)   PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL ls: OPTIONS missing '-a, --all'\n" >&2 ;;
esac
# An option with no long form must not render a dangling comma.
case "$help_ls" in
    *"-1,"*) FAIL=$((FAIL + 1)); printf "FAIL ls: short-only option has a dangling comma\n" >&2 ;;
    *) PASS=$((PASS + 1)) ;;
esac
# A value-taking option is marked as such.
case "$help_ls" in
    *"--width VALUE"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL ls: value option not marked\n" >&2 ;;
esac

# --- -h keeps its per-utility meaning (ADR 0002) -----------------------
printf 'x\n' > small.txt
# ⚠ `rc=0; cmd || rc=$?` rather than `$(cmd; echo $?)`: under `set -e` the
# subshell aborts at the non-zero status before it can echo it.
rc=0; "$BIN" du -h . >/dev/null 2>&1 || rc=$?
expect_eq "du -h is human-readable, not help" "0" "$rc"
rc=0; "$BIN" sort -h small.txt >/dev/null 2>&1 || rc=$?
expect_eq "sort -h is a bad option, not help" "2" "$rc"
case "$("$BIN" du -h . 2>&1 | head -1)" in
    NAME*) FAIL=$((FAIL + 1)); printf "FAIL du -h printed help\n" >&2 ;;
    *) PASS=$((PASS + 1)) ;;
esac

# --- no ANSI when stdout is not a tty ----------------------------------
# ⚠ Styling a redirected stream puts escapes into whatever consumes it — the
# agnoshi completer being the immediate consumer here.
case "$("$BIN" ls --help | od -An -c | tr -d ' \n')" in
    *033*) FAIL=$((FAIL + 1)); printf "FAIL ls --help emitted ANSI to a pipe\n" >&2 ;;
    *) PASS=$((PASS + 1)) ;;
esac

# --- `--help` reaches the right program --------------------------------
# ⛔ `xargs --help` is xargs' help; `xargs CMD --help` belongs to CMD. The
# operand-boundary scan has to know `--help` is ours BEFORE the first operand
# and nobody's after it.
expect_eq "xargs --help is xargs'"      "NAME"    "$(printf 'x\n' | "$BIN" xargs --help 2>&1 | head -1)"
expect_eq "xargs CMD --help goes to CMD" "--help x" "$(printf 'x\n' | "$BIN" xargs echo --help 2>&1)"
# Same for an expression rather than a command line.
touch target
expect_eq "find -exec ... --help passes through" "--help ./target" \
    "$("$BIN" find . -name target -exec echo --help {} ';' 2>&1)"
expect_eq "find --help is find's"       "NAME" "$("$BIN" find --help 2>&1 | head -1)"

# --- `--` still terminates option recognition --------------------------
expect_eq "-- guards a literal --help operand" "0" \
    "$(touch -- '--help' 2>/dev/null && "$BIN" ls -- --help >/dev/null 2>&1; echo $?)"

# --- the machine form is named, not rejected as unknown ----------------
# ⚠ `--help=json` lands in 1.3.1. Answering "bad option" would read as "no such
# flag", which is the wrong thing to tell an agent probing for the interface.
rc=0; err=$("$BIN" ls --help=json 2>&1 >/dev/null) || rc=$?
expect_eq "--help=json exits 2" "2" "$rc"
case "$err" in
    *"not implemented yet"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf "FAIL --help=json message: %s\n" "$err" >&2 ;;
esac

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
