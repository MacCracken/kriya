#!/bin/sh
# smoke-tail-follow.sh — `tail -f`, `-F`, `--follow=name`, `--retry`, `--pid`, against GNU.
#
# ⭐ Each scenario runs GNU and kriya side by side, in two directories given the same files and
# the same changes at the same moments: appends, truncation, removal, renaming, a file that
# appears late. kriya's follow is GNU's POLLING loop ported (1.9.2), so GNU runs as
# `tail ---disable-inotify -s 0.1` and kriya as `tail -s 0.1`; stdout and the exit status are
# compared. stderr is not (its framing is kriya's), but the messages that carry meaning are
# looked for by their words.
#
# ⚠ Wall-clock by nature. One tick is 0.6 s, six polls; a scenario that differs is run again up
# to twice before it counts as a failure, so a loaded runner costs time rather than a red
# result. Every tail runs under `timeout`, so a regression that never exits fails instead of
# hanging the suite.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi
GNU_TAIL=$(command -v tail)
# ⚠ Two answers changed in GNU 9.6, and kriya gives 9.6's (9.12's): `--follow=name` without
# `--retry` exits 1 once every file is gone, and a huge `--max-unchanged-stats` saturates. Before
# 9.6 the first exited 0 and the second was refused; there kriya's answer is asserted instead.
GNU_VER=$("$GNU_TAIL" --version | sed -n '1s/.* \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
GNU_96=0
set -- $GNU_VER
if [ "${1:-0}" -gt 9 ] || { [ "${1:-0}" -eq 9 ] && [ "${2:-0}" -ge 6 ]; }; then GNU_96=1; fi
set --

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0
FAIL=0
TICK=0.6

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nexpected: %s\ngot:      %s\n" "$1" "$2" "$3" >&2
    fi
}

# --- the scenario engine ----------------------------------------------------
# fresh                start a scenario: empty g/ (GNU) and k/ (kriya)
# put F TEXT           write F in both
# go ARGS...           start both tails with ARGS in their directories
# app F TEXT / trunc F TEXT / del F / mv A B   the same change in both
# tick [N]             wait N ticks (1)
# stop                 end both (TERM if still running) and record out/err/rc
fresh() {
    rm -rf g k
    mkdir g k
}
put()   { printf '%b' "$2" > "g/$1"; printf '%b' "$2" > "k/$1"; }
app()   { printf '%b' "$2" >> "g/$1"; printf '%b' "$2" >> "k/$1"; }
trunc() { printf '%b' "$2" > "g/$1"; printf '%b' "$2" > "k/$1"; }
del()   { rm -f "g/$1" "k/$1"; }
mv2()   { mv "g/$1" "g/$2"; mv "k/$1" "k/$2"; }
tick()  { sleep "$(awk -v t="$TICK" -v n="${1:-1}" 'BEGIN { print t * n }')"; }
go() {
    (cd g && exec env LC_ALL=C timeout 30 "$GNU_TAIL" ---disable-inotify -s 0.1 "$@" \
        > ../g.out 2> ../g.err < /dev/null) &
    GP=$!
    (cd k && exec env LC_ALL=C timeout 30 "$BIN" tail -s 0.1 "$@" > ../k.out 2> ../k.err < /dev/null) &
    KP=$!
}
# The obsolescent `-2f` has to be GNU's FIRST argument, so it cannot follow the polling
# options; this starts both at their defaults (GNU on inotify), which print the same bytes.
go_plain() {
    (cd g && exec env LC_ALL=C timeout 30 "$GNU_TAIL" "$@" > ../g.out 2> ../g.err < /dev/null) &
    GP=$!
    (cd k && exec env LC_ALL=C timeout 30 "$BIN" tail "$@" > ../k.out 2> ../k.err < /dev/null) &
    KP=$!
}
stop() {
    kill "$GP" "$KP" 2>/dev/null || true
    GRC=0; wait "$GP" 2>/dev/null || GRC=$?
    KRC=0; wait "$KP" 2>/dev/null || KRC=$?
    # A tail we had to stop is "running"; one that ended on its own keeps its status.
    if [ "$GRC" = 143 ]; then GRC=running; fi
    if [ "$KRC" = 143 ]; then KRC=running; fi
}

# scenario LABEL FUNCTION: run FUNCTION up to three times until stdout and status agree.
scenario() {
    _label=$1
    _fn=$2
    _try=1
    while [ "$_try" -le 3 ]; do
        fresh
        "$_fn"
        if cmp -s g.out k.out && [ "$GRC" = "$KRC" ]; then
            PASS=$((PASS + 1))
            return 0
        fi
        _try=$((_try + 1))
    done
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: GNU %s, kriya %s\n  gnu: %s\n  kri: %s\n' "$_label" "$GRC" "$KRC" \
        "$(od -c g.out | head -5)" "$(od -c k.out | head -5)" >&2
}

# kriya's stderr, for the messages that matter.
err_has() {   # err_has LABEL WORDS
    case "$(cat k.err)" in
        *"$2"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf 'FAIL %s: stderr lacks "%s": %s\n' "$1" "$2" "$(cat k.err)" >&2 ;;
    esac
}

# --- descriptor follow -------------------------------------------------------
s_one()      { put a '1\n2\n'; go -f a; tick; app a '3\n'; tick; app a '4'; tick; stop; }
s_two()      { put a 'a1\n'; put b 'b1\n'; go -f a b; tick; app b 'b2\n'; tick; app a 'a2\n'; tick
               app a 'a3\n'; tick; app b 'b3\n'; tick; stop; }
s_quiet()    { put a 'a1\n'; put b 'b1\n'; go -q -f a b; tick; app a 'a2\n'; tick; app b 'b2\n'; tick; stop; }
s_verbose()  { put a 'a1\n'; go -v -f a; tick; app a 'a2\n'; tick; stop; }
s_three()    { put a 'a\n'; put b 'b\n'; put c 'c\n'; go -f a b c; tick; app c 'c2\n'; tick; app a 'a2\n'
               tick; app b 'b2\n'; tick; stop; }
s_twice()    { put a 'x\n'; go -f a a; tick; app a 'y\n'; tick; stop; }
s_trunc()    { put a '1\n2\n3\n'; go -f a; tick; trunc a 'x\n'; tick; app a 'y\n'; tick; stop; }
s_rm()       { put a '1\n'; go -f a; tick; app a '2\n'; tick; del a; tick 2; put a 'new\n'; tick 2; stop; }
s_mvfd()     { put a '1\n'; go -f a; tick; mv2 a a.1; tick; app a.1 '2\n'; tick; put a 'new\n'; tick 2; stop; }
s_plus()     { put a '1\n2\n3\n'; go -f -n +2 a; tick; app a '4\n'; tick; stop; }
s_bytes()    { put a 'abcdef'; go -f -c 2 a; tick; app a 'gh'; tick; stop; }
s_units()    { put a '1\n2\n3\n'; go -f -c 1K a; tick; app a '4\n'; tick; stop; }
s_obs()      { put a '1\n2\n3\n'; go_plain -2f a; tick; app a '4\n'; tick 2; stop; }
s_missing()  { go -f a; tick 2; stop; }
s_dir()      { go -f .; tick 2; stop; }
s_onemiss()  { put b 'b1\n'; go -f a b; tick; app b 'b2\n'; tick; stop; }
s_retryfd()  { go -f --retry a; tick; put a 'x\n'; tick 3; stop; }
# Without --retry a name that could not be opened is given up on, even when it appears later.
s_latefd()   { put b 'b1\n'; go -f a b; tick; put a 'a1\n'; tick 2; app b 'b2\n'; tick; stop; }
scenario "tail -f one file"                  s_one
scenario "tail -f two files, headers"        s_two
scenario "tail -q -f two files"              s_quiet
scenario "tail -v -f one file"               s_verbose
scenario "tail -f three files"               s_three
scenario "tail -f a a"                       s_twice
scenario "tail -f truncation"                s_trunc
err_has  "tail -f truncation says so"        "file truncated"
scenario "tail -f keeps a removed file"      s_rm
scenario "tail -f keeps a renamed file"      s_mvfd
scenario "tail -f -n +2"                     s_plus
scenario "tail -f -c 2"                      s_bytes
scenario "tail -f -c 1K"                     s_units
scenario "tail -2f (obsolescent)"            s_obs
scenario "tail -f missing: no files remaining" s_missing
err_has  "tail -f missing says so"           "no files remaining"
scenario "tail -f a directory"               s_dir
scenario "tail -f one missing, one present"  s_onemiss
scenario "tail -f --retry (initial open only)" s_retryfd
err_has  "--retry with descriptors warns"    "only effective for the initial open"
scenario "tail -f: a late file without --retry" s_latefd

# --- name follow ---------------------------------------------------------------
s_Frm()      { put a '1\n'; go -F a; tick; del a; tick 2; put a 'new\n'; tick 2; app a 'more\n'; tick; stop; }
s_Frot()     { put a '1\n'; go -F a; tick; app a '2\n'; tick; mv2 a a.1; put a 'fresh\n'; tick 3; app a '3\n'
               tick; stop; }
s_Fmiss()    { go -F a; tick; put a 'hello\n'; tick 2; app a '2\n'; tick; stop; }
s_Ftwo()     { put b 'b1\n'; go -F a b; tick; put a 'a1\n'; tick 2; app b 'b2\n'; tick; stop; }
s_namerm()   { put a '1\n'; go --follow=name a; tick; del a; tick 3; put a 'back\n'; tick 3; stop; }
s_Fdir()     { go -F .; tick 2; stop; }
s_Ffd()      { put a '1\n'; go -F -f a; tick; mv2 a a.1; app a.1 '2\n'; tick; put a 'new\n'; tick 3; stop; }
s_namepfx()  { put a '1\n'; go --follow=n a; tick; mv2 a a.1; put a 'z\n'; tick 3; stop; }
s_mus()      { put a '1\n'; go --follow=name --max-unchanged-stats=1 a; tick; mv2 a a.1; put a 'z\n'; tick 2; stop; }
scenario "tail -F removed, then recreated"   s_Frm
err_has  "tail -F says inaccessible"         "has become inaccessible"
err_has  "tail -F says appeared"             "has appeared;  following new file"
scenario "tail -F rotation"                  s_Frot
err_has  "tail -F says replaced"             "has been replaced;  following new file"
scenario "tail -F missing at the start"      s_Fmiss
scenario "tail -F two, one late"             s_Ftwo
if [ "$GNU_96" = 1 ]; then
    scenario "tail --follow=name without retry"  s_namerm
else
    fresh; s_namerm
    expect_eq "tail --follow=name without retry (9.6's exit 1)" "1 1" "$(cat k.out | tr -d '\n') $KRC"
fi
scenario "tail -F a directory"               s_Fdir
scenario "tail -F -f: the last wins"         s_Ffd
scenario "tail --follow=n (a prefix)"        s_namepfx
scenario "tail --max-unchanged-stats=1"      s_mus

# --- --pid -----------------------------------------------------------------
# ⚠ GNU before 9.5 kept one --pid, the last; kriya keeps them all, as 9.5 and later do.
s_pid()      { put a '1\n'; sleep 1.5 & SP=$!; go -f --pid=$SP a; tick; app a '2\n'; tick 4; stop; wait $SP 2>/dev/null || true; }
scenario "tail -f --pid exits after PID"     s_pid
expect_eq "tail -f --pid exits on its own" "0" "$KRC"
put_one() { printf '1\n' > p.txt; }
put_one
sleep 30 & LIVE=$!
rc=0; timeout 2 "$BIN" tail -s 0.1 -f --pid=$LIVE --pid=999999 p.txt > /dev/null 2>&1 || rc=$?
expect_eq "tail -f --pid waits for every PID" "124" "$rc"
kill $LIVE 2>/dev/null || true
wait $LIVE 2>/dev/null || true
rc=0; timeout 5 "$BIN" tail -s 0.1 -f --pid=999999 p.txt > /dev/null 2>&1 || rc=$?
expect_eq "tail -f --pid of a dead process exits 0" "0" "$rc"

# --- what is not followed ------------------------------------------------------
# POSIX: a pipe on standard input is not followed; a regular file is.
rc=0; out=$(printf 'x\n' | timeout 3 "$BIN" tail -f 2>/dev/null) || rc=$?
expect_eq "tail -f of a pipe ends"      "x 0" "$out $rc"
rc=0; timeout 1 "$BIN" tail -f < p.txt > /dev/null 2>&1 || rc=$?
expect_eq "tail -f of a file on stdin follows" "124" "$rc"
# A reader that goes away ends `tail -f`, without waiting for more data.
rc=0; out=$(timeout 5 sh -c "'$BIN' tail -s 0.1 -f p.txt | head -n 1") || rc=$?
expect_eq "tail -f | head ends with head" "1 0" "$out $rc"

# --- warnings and refusals ----------------------------------------------------
cmp_gnu() {   # cmp_gnu LABEL ARGS... : stdout and status, a usage error being 2 in kriya
    _l=$1; shift
    _g=0; _go=$(LC_ALL=C timeout 3 "$GNU_TAIL" "$@" 2>/dev/null < /dev/null) || _g=$?
    _k=0; _ko=$(timeout 3 "$BIN" tail "$@" 2>/dev/null < /dev/null) || _k=$?
    expect_eq "$_l" "$_go $_g" "$_ko $_k"
}
cmp_gnu "tail --retry without -f"   --retry p.txt
cmp_gnu "tail --pid without -f"     --pid=1 p.txt
cmp_gnu "tail -s 0.5 without -f"    -s 0.5 p.txt
cmp_gnu "tail -s inf"               -s inf p.txt
cmp_gnu "tail -s 1e-3"              -s 1e-3 p.txt
cmp_gnu "tail -s ' 1'"              -s ' 1' p.txt
cmp_gnu "tail --pid=0"              --pid=0 p.txt
cmp_gnu "tail --pid=2147483647"     --pid=2147483647 p.txt
if [ "$GNU_96" = 1 ]; then
    cmp_gnu "tail --max-unchanged-stats=99999999999999999999" --max-unchanged-stats=99999999999999999999 p.txt
else
    rc=0; out=$("$BIN" tail --max-unchanged-stats=99999999999999999999 p.txt 2>/dev/null) || rc=$?
    expect_eq "tail --max-unchanged-stats=99999999999999999999 saturates (9.6)" "1 0" "$out $rc"
fi
err=$("$BIN" tail --retry p.txt 2>&1 >/dev/null) || true
expect_eq "tail --retry warns" "kriya tail: warning: --retry ignored; --retry is useful only when following" "$err"
# ⚠ GNU exits 1 for these, its EXIT_FAILURE; kriya's usage error is 2 (ADR 0008).
for _a in "-s abc" "-s -1" "-s 1s" "-s nan" "-s ''" "--pid=abc" "--pid=-1" "--pid=2147483648" \
          "--pid=" "--max-unchanged-stats=-1" "--max-unchanged-stats=1K" "--follow=x" "--follow=" \
          "-F -" "-F" "--follow=name"; do
    rc=0; eval "timeout 3 '$BIN' tail $_a p.txt" > /dev/null 2>&1 < /dev/null || rc=$?
    case "$_a" in
        "-F"|"--follow=name") rc=0; eval "timeout 3 '$BIN' tail $_a" > /dev/null 2>&1 < /dev/null || rc=$? ;;
    esac
    expect_eq "tail $_a is a usage error" "2" "$rc"
done

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
