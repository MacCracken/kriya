#!/bin/sh
# smoke-vanish.sh — an entry that vanishes mid-walk is not an error, in `ls` and `du` (1.8.7).
#
# GNU 9.12 NEWS: "'du', 'ls' ... no longer fail merely because files may be being removed in
# parallel". An entry a directory read returned, and that is gone (ENOENT) by the time it is
# stat'd or opened, is left out in silence. A command-line operand still fails. kriya said
# *cannot access* and exited 1: 17 runs in 200 of `ls -l` over a churned directory, 22 of `du -a`,
# against GNU 9.12's none.
#
# ⭐ DETERMINISTIC, NOT ONLY STATISTICAL. `scripts/vanish.py` runs the command under ptrace and
# removes the entry at the command's first stat (or open) of its name, so the race is lost every
# time. Each case asserts against kriya's own listing of the same tree once the entry is gone:
# "left out" means exactly that output, with nothing on stderr and exit 0.
# ⚠ Not against GNU: CI's oracle is 9.7, which reports and exits 1. GNU 9.12 was measured with the
# same hook and gives these answers; see CHANGELOG [1.8.7].
#
# A fixed-count churn follows, asserting zero failures. ⚠ The hook needs x86_64 and ptrace, the
# churn needs nothing; skipped cases are counted.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"
HOOK="$ROOT/scripts/vanish.py"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
# Links named for the utility: `kriya ls` would do, but a link is what users run.
mkdir bin; ln -s "$BIN" bin/ls; ln -s "$BIN" bin/du
LS="$WORK/bin/ls"; DU="$WORK/bin/du"

PASS=0
FAIL=0
SKIP=0

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s:\nexpected: %s\ngot:      %s\n' "$1" "$2" "$3" >&2
    fi
}

# The fixture: three files, a subdirectory holding one, a symlink and a dangling one.
mk() {
    rm -rf d; mkdir d
    echo a > d/a; echo bb > d/b; echo vvv > d/v
    mkdir d/s; echo x > d/s/x
    ln -s a d/l; ln -s nowhere d/dang
}

HAVE_HOOK=0
if [ "$(uname -m)" = x86_64 ] && command -v python3 >/dev/null 2>&1; then
    if python3 -I "$HOOK" stat zz /nonexistent -- /bin/true 2>/dev/null; then HAVE_HOOK=1; fi
fi

# hook ON NAME VICTIM CMD... — CMD under the hook. Sets OUT, ERR (without the hook's own line),
# RC, and FIRED (1 when the entry was removed under it).
hook() {
    on=$1; nm=$2; vic=$3; shift 3
    RC=0
    OUT=$(python3 -I "$HOOK" "$on" "$nm" "$vic" -- "$@" 2>"$WORK/err") || RC=$?
    ERR=$(grep -v '^vanish: ' "$WORK/err" || true)
    FIRED=0
    if grep -q '^vanish: fired' "$WORK/err"; then FIRED=1; fi
}

# gone LABEL ON NAME VICTIM CMD... — the entry vanishes under CMD, and the result must be CMD's own
# answer for the tree without it: nothing said, exit 0.
gone() {
    lab=$1; on=$2; nm=$3; vic=$4; shift 4
    mk
    hook "$on" "$nm" "$vic" "$@"
    after=$("$@" 2>&1) || true
    expect_eq "$lab: left out" "1 0 [] $after" "$FIRED $RC [$ERR] $OUT"
}

if [ "$HAVE_HOOK" = 1 ]; then
    # --- ls: a format that needs the stat leaves the entry out -----------------
    gone "ls -l, gone at its stat"      stat v d/v "$LS" -l --time-style=long-iso d
    gone "ls -n, gone at its stat"      stat v d/v "$LS" -n --time-style=long-iso d
    gone "ls -F, gone at its stat"      stat v d/v "$LS" -F d
    gone "ls -i, gone at its stat"      stat v d/v "$LS" -i d
    gone "ls -t, gone at its stat"      stat v d/v "$LS" -t d
    gone "ls -S, gone at its stat"      stat v d/v "$LS" -S d
    # ⚠ The `total` too: GNU's leaves the entry's blocks out, and so must the row count.
    gone "ls -l, a link gone at its readlink" readlink l d/l "$LS" -l --time-style=long-iso d
    gone "du -a, a file gone at its stat"     stat v d/v "$DU" -a d
    gone "du -a, a directory gone at its stat" stat s d/s "$DU" -a d
    gone "du -a, a directory gone at its open" open s d/s "$DU" -a d
    gone "du -a, a file below gone at its stat" stat x d/s/x "$DU" -a d
    gone "du -s, a directory gone at its open" open s d/s "$DU" -s d
    # ⚠ `du` stats a subdirectory twice: in its parent's loop, and again as it enters it.
    gone "du -a, a directory gone at its second stat" stat:2 s d/s "$DU" -a d

    # --- ls: a format that needs no stat keeps the name the directory read returned ---
    # GNU never stats here, so it lists the name; kriya stats every entry, and keeps it.
    mk; hook stat v d/v "$LS" d
    expect_eq "ls, gone at its stat: the name stands" "1 0 [] a b dang l s v" "$FIRED $RC [$ERR] $(echo $OUT)"
    mk; hook stat v d/v "$LS" -1 d
    expect_eq "ls -1, gone at its stat: the name stands" "1 0 [] a b dang l s v" "$FIRED $RC [$ERR] $(echo $OUT)"
    # -R: kept from the read, so it is entered, and gone: no section, nothing said.
    mk; hook stat s d/s "$LS" -R d
    expect_eq "ls -R, a directory gone at its stat" "1 0 [] d: a b dang l s v" "$FIRED $RC [$ERR] $(echo $OUT)"
    mk; hook open s d/s "$LS" -R d
    expect_eq "ls -R, a directory gone at its open" "1 0 [] d: a b dang l s v" "$FIRED $RC [$ERR] $(echo $OUT)"

    # --- what still fails ----------------------------------------------------------
    # ⛔ An OPERAND that vanishes is an error, as in GNU: it is not an entry a read returned.
    mk; hook stat v d/v "$LS" -l d/v
    expect_eq "ls: a vanished operand still fails" "1 1 1" "$FIRED $([ "$RC" -ne 0 ] && echo 1 || echo 0) $([ -n "$ERR" ] && echo 1 || echo 0)"
    mk; hook open d d "$LS" d
    expect_eq "ls: a vanished directory operand still fails" "1 1 1" "$FIRED $([ "$RC" -ne 0 ] && echo 1 || echo 0) $([ -n "$ERR" ] && echo 1 || echo 0)"
    mk; hook stat v d/v "$DU" d/v
    expect_eq "du: a vanished operand still fails" "1 1 1" "$FIRED $RC $([ -n "$ERR" ] && echo 1 || echo 0)"
    # ⚠ Under -L a DANGLING link answers ENOENT too, and it is still there: still reported. A link
    # that has gone is not.
    mk; hook stat l d/l "$DU" -L -a d
    expect_eq "du -L: a dangling link still reported, a gone link not" \
        "1 1 kriya du: cannot access 'd/dang': no such file or directory" "$FIRED $RC $ERR"
    # ⚠ ENOENT only: a stat that fails for another reason still fails. A directory that can be
    # read and not searched (0600) lists its names, and every stat below it is EACCES.
    # ⛔ First cut used `chmod 000`, and a mutant that forgave EVERY errno survived it: a 000
    # directory fails at its open, which never asked the vanish rule.
    mk; chmod 600 d/s
    if [ "$(id -u)" != 0 ]; then
        rc=0; "$DU" -a d >/dev/null 2>&1 || rc=$?
        expect_eq "du: EACCES below an unsearchable directory still fails" "1" "$rc"
        rc=0; "$LS" -l d/s >/dev/null 2>&1 || rc=$?
        expect_eq "ls -l: EACCES in an unsearchable directory still fails" "1" "$rc"
    else
        SKIP=$((SKIP + 2))
    fi
    chmod 755 d/s
else
    SKIP=$((SKIP + 23))
fi

# --- the churn: a second process keeps adding and removing entries ---------------
# ⚠ Statistical, so a fixed count and a zero: 100 listings per mode while ten files, then ten
# directories each holding a file, appear and vanish. 1.8.6 failed about one run in twelve.
churn() { # churn KIND LABEL CMD...
    kind=$1; lab=$2; shift 2
    rm -rf c; mkdir c
    i=0; while [ $i -lt 200 ]; do : > "c/k$i"; i=$((i + 1)); done
    if [ "$kind" = f ]; then
        ( while :; do for j in 0 1 2 3 4 5 6 7 8 9; do : > c/c$j; done; rm -f c/c?; done ) &
    else
        ( while :; do for j in 0 1 2 3 4 5 6 7 8 9; do mkdir c/c$j; : > c/c$j/x; done; rm -rf c/c?; done ) &
    fi
    pid=$!
    bad=0; k=0
    while [ $k -lt 100 ]; do
        rc=0; "$@" c >/dev/null 2>cerr || rc=$?
        if [ $rc -ne 0 ]; then bad=$((bad + 1)); fi
        if [ -s cerr ]; then bad=$((bad + 1)); fi
        k=$((k + 1))
    done
    kill $pid; wait $pid 2>/dev/null || true
    expect_eq "churn ($kind): $lab" "0" "$bad"
}
for kind in f d; do
    churn $kind "ls -l"  "$LS" -l
    churn $kind "ls"     "$LS"
    churn $kind "ls -lR" "$LS" -lR
    churn $kind "du -a"  "$DU" -a
done

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed, %d skipped (%d total)\n' "$PASS" "$FAIL" "$SKIP" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
