#!/bin/sh
# smoke-deep.sh — deep trees, and the descriptor budget every walk shares (1.8.6).
#
# ⛔ Until 1.8.6 every fd-relative walk held one open directory per level, so under
# `ulimit -n 1024` a tree deeper than 1,020 levels failed with "too many open files": `find`,
# `du`, `rm -r` and `grep -r` stopped there and `cp -R` at 509. `rm -r` was the one that
# mattered — a 1,021-level tree in a shared directory was unremovable by kriya. Now a walk keeps
# at most 32 directories open (src/lib/walk.cyr), reopens a closed one as `..` of the child it
# leaves, and STOPS when that `..` is not the directory it closed.
#
# ⚠ THE LIMIT IS SET HERE, NOT INHERITED. CI runners allow far more than 1,024 descriptors, so a
# test that only made a 1,100-level tree would pass against the old walks there. Every budget
# case runs under `ulimit -n 64` (or 8) with a tree deeper than that.
#
# ⚠ Needs python3 to build trees deeper than PATH_MAX and to drive `rm -i` on a terminal; those
# cases are skipped, and counted, without it.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi

WORK=$(mktemp -d)
cleanup() {
    # ⚠ GNU's rm, which has no depth limit: a failed case may have left a tree no shell path
    # can name, and a broken kriya must not be what cleans up after itself.
    chmod -R u+rwx "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
cd "$WORK"

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

HAVE_PY=0
if command -v python3 >/dev/null 2>&1; then HAVE_PY=1; fi

# lim N CMD... — run CMD with the soft descriptor limit at N, for at most $T seconds.
# ⛔ The timeout is not decoration. A walk that loses its place when a level is closed and
# reopened reads that level again from the start, and walks the same subtree for ever: the first
# mutation run of 1.8.6 sat on one `find` for sixteen minutes, at 1.5 GB and growing.
T=${SMOKE_DEEP_TIMEOUT:-120}   # seconds; the mutation harness shortens it
lim() {
    n=$1; shift
    sh -c 'ulimit -n "$1"; shift; exec timeout "$0" "$@"' "$T" "$n" "$@"
}

# chain DIR N — DIR and N nested `a` directories under it, `f` (holding "hit") at the bottom.
# Built fd-relative in python3 (no path is ever longer than one name), or by `mkdir -p` when
# the path fits.
# ⚠ Each builder clears its target first (GNU's rm): a failed case can leave the last tree.
chain() {
    rm -rf "$1"
    if [ "$HAVE_PY" = 1 ]; then
        python3 -I - "$1" "$2" <<'PY'
import os, sys
root, n = sys.argv[1], int(sys.argv[2])
os.mkdir(root)
fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
for i in range(n):
    os.mkdir('a', dir_fd=fd)
    nfd = os.open('a', os.O_RDONLY | os.O_DIRECTORY, dir_fd=fd)
    os.close(fd); fd = nfd
w = os.open('f', os.O_WRONLY | os.O_CREAT, 0o644, dir_fd=fd)
os.write(w, b'hit\n'); os.close(w); os.close(fd)
PY
    else
        p=$1; i=0
        while [ "$i" -lt "$2" ]; do p="$p/a"; i=$((i + 1)); done
        mkdir -p "$p"; echo hit > "$p/f"
    fi
}

# wide DIR DEPTH — a chain DEPTH deep whose every level also holds two files, a symlink, an
# empty directory and a three-level side branch: a walk deeper than its budget must close
# levels, save what they had left to read, and come back up through `..` to read it.
wide() {
    rm -rf "$1"
    p=$1; i=0
    mkdir "$p"
    while [ "$i" -lt "$2" ]; do
        echo hit > "$p/f1"; : > "$p/f2"; ln -s f1 "$p/l"; mkdir "$p/e"
        mkdir -p "$p/s/s/s"; echo hit > "$p/s/g"; echo hit > "$p/s/s/s/g"
        p="$p/a"; mkdir "$p"; i=$((i + 1))
    done
}

# --- 1. deeper than the descriptor limit (ulimit -n 64, 300 levels) ---------
# Each of these failed before 1.8.6 with "too many open files" 60-odd levels down.
chain t 300
expect_eq "find past the limit"        "$(find t | wc -l)"     "$(lim 64 "$BIN" find t | wc -l)"
expect_eq "find -depth past the limit" "$(find t -depth | wc -l)" "$(lim 64 "$BIN" find t -depth | wc -l)"
expect_eq "du -s past the limit"       "$(du -s t)"            "$(lim 64 "$BIN" du -s t)"
expect_eq "du -a past the limit"       "$(du -a t | cksum)"    "$(lim 64 "$BIN" du -a t | cksum)"
expect_eq "grep -r past the limit"     "$(grep -r hit t)"      "$(lim 64 "$BIN" grep -r hit t)"
rc=0; lim 64 "$BIN" cp -R t c 2>/dev/null || rc=$?
expect_eq "cp -R past the limit: exit" "0" "$rc"
expect_eq "cp -R past the limit: copy" "$(cd t && find . -printf '%p %y %m\n' | sort)" "$(cd c && find . -printf '%p %y %m\n' | sort)"
rc=0; lim 64 "$BIN" rm -r c t 2>/dev/null || rc=$?
expect_eq "rm -r past the limit: exit" "0" "$rc"
expect_eq "rm -r past the limit: gone" "no" "$([ -e t ] || [ -e c ] && echo yes || echo no)"

# --- 2. deeper than the budget, with something left to read at every level ---
# ⭐ Line for line against GNU: the order is the directory's, so a level whose saved entries
# were lost, repeated or reordered shows up here. ⚠ A copy's listing is SORTED: `cp` creates in
# the source's read order, and a directory need not read back in creation order (tmpfs reverses).
wide t 80
wide g 80
expect_eq "find over the budget"        "$(find t)"            "$(lim 64 "$BIN" find t)"
expect_eq "find -depth over the budget" "$(find t -depth)"     "$(lim 64 "$BIN" find t -depth)"
expect_eq "find -empty over the budget" "$(find t -empty)"     "$(lim 64 "$BIN" find t -empty)"
expect_eq "du -a over the budget"       "$(du -a t)"           "$(lim 64 "$BIN" du -a t)"
expect_eq "grep -r over the budget"     "$(grep -r hit t)"     "$(lim 64 "$BIN" grep -r hit t)"
rc=0; lim 64 "$BIN" cp -R t c 2>/dev/null || rc=$?
expect_eq "cp -R over the budget: exit" "0" "$rc"
expect_eq "cp -R over the budget: copy" "$(cd t && find . -printf '%p %y %m %s %l\n' | sort)" "$(cd c && find . -printf '%p %y %m %s %l\n' | sort)"
# ⚠ Both the same tree under another name, so the -v lines differ by that name only.
# ⚠ `|| true`: an assignment takes the command's status, and `set -e` would end the script on
# the very failure the case exists to report.
gv=$(rm -rv g | sed "s|'g|'t|")
kv=$(lim 64 "$BIN" rm -rv t 2>/dev/null || true)
expect_eq "rm -rv over the budget" "$gv" "$kv"
expect_eq "rm -rv over the budget: gone" "no" "$([ -e t ] && echo yes || echo no)"
rm -rf c g
# ⛔ -delete and -execdir act through the PARENT's descriptor after a descent, which the walk may
# have closed and reopened as another number in between.
wide t 80
wide g 80
expect_eq "find -execdir over the budget" "$(find g -name f1 -execdir pwd \; | sed 's|/g/|/t/|; s|/g$|/t|')" "$(lim 64 "$BIN" find t -name f1 -execdir pwd \;)"
rc=0; lim 64 "$BIN" find t -depth -delete 2>/dev/null || rc=$?
expect_eq "find -depth -delete over the budget" "0 no" "$rc $([ -e t ] && echo yes || echo no)"
rm -rf g

# --- 3. hardly any descriptors at all (ulimit -n 8) ----------------------------
# ⭐ An open that meets EMFILE asks the walks for a descriptor back, files included: `cp -R`
# needs a source and a destination directory and a file of each, and failed every file 33
# levels down under `ulimit -n 64` before its file opens asked.
wide t 40
expect_eq "find under ulimit -n 8"  "$(find t)"        "$(lim 8 "$BIN" find t)"
expect_eq "du -a under ulimit -n 8" "$(du -a t)"       "$(lim 8 "$BIN" du -a t)"
expect_eq "grep -r under ulimit -n 8" "$(grep -r hit t)" "$(lim 8 "$BIN" grep -r hit t)"
rc=0; lim 8 "$BIN" cp -R t c 2>/dev/null || rc=$?
expect_eq "cp -R under ulimit -n 8: exit" "0" "$rc"
expect_eq "cp -R under ulimit -n 8: copy" "$(cd t && find . -printf '%p %y %m\n' | sort)" "$(cd c && find . -printf '%p %y %m\n' | sort)"
rc=0; lim 8 "$BIN" rm -r t c 2>/dev/null || rc=$?
expect_eq "rm -r under ulimit -n 8" "0 no" "$rc $([ -e t ] || [ -e c ] && echo yes || echo no)"

# --- 4. a reopened directory is not leaked into a child -------------------------
# The `..` reopen is O_CLOEXEC like every walk open: a child run at the bottom of a tree deeper
# than the budget sees what GNU's sees.
chain t 80
expect_eq "find -exec child fds past the budget" \
    "$(find t -name f -exec sh -c 'ls /proc/$$/fd' \;)" \
    "$(lim 64 "$BIN" find t -name f -exec sh -c 'ls /proc/$$/fd' \;)"
rm -rf t

# --- 5. -L through a symlink: the directory the walk came from stays open --------
# ⛔ `..` of a directory reached through a symlink is its REAL parent, so the walk must never
# close the directory holding the link. Closed and reopened, it would be reported as "moved"
# and the walk would stop half way.
rm -rf lt lc real; mkdir -p lt; p=lt; i=0
while [ "$i" -lt 25 ]; do p="$p/a"; i=$((i + 1)); done
mkdir -p "$p"; chain real 40; ln -s "$WORK/real" "$p/s"
rc=0; lim 64 "$BIN" find -L lt >/dev/null 2>&1 || rc=$?
expect_eq "find -L through a link, over the budget" "$(find -L lt | wc -l) 0" "$(lim 64 "$BIN" find -L lt | wc -l) $rc"
expect_eq "du -L through a link, over the budget"   "$(du -L -s lt)"     "$(lim 64 "$BIN" du -L -s lt)"
rc=0; lim 64 "$BIN" cp -RL lt lc 2>/dev/null || rc=$?
expect_eq "cp -RL through a link, over the budget" "0 $(find -L lt | wc -l)" "$rc $(find lc | wc -l)"
rm -rf lt lc real

# --- 6. past PATH_MAX (2,100 levels) --------------------------------------------
# ⛔ `find -empty` opened each directory by its whole path until 1.8.6, so past PATH_MAX it said
# "file name too long" for each one; every other open of the walk was already fd-relative.
# ⚠ GNU cp walks by path and stops at PATH_MAX, so its copy is checked against the source. Under
# `ulimit -n 64` too, so these are budget cases as well.
if [ "$HAVE_PY" = 1 ]; then
    chain t 2100
    expect_eq "find past PATH_MAX"        "$(find t | cksum)"        "$(lim 64 "$BIN" find t | cksum)"
    rc=0; lim 64 "$BIN" find t -empty >/dev/null 2>&1 || rc=$?
    expect_eq "find -empty past PATH_MAX" "$(find t -empty | cksum) 0" "$(lim 64 "$BIN" find t -empty | cksum) $rc"
    expect_eq "du -s past PATH_MAX"       "$(du -s t)"               "$(lim 64 "$BIN" du -s t)"
    expect_eq "grep -r past PATH_MAX"     "$(grep -r hit t | cksum)" "$(lim 64 "$BIN" grep -r hit t | cksum)"
    rc=0; lim 64 "$BIN" cp -R t c 2>/dev/null || rc=$?
    expect_eq "cp -R past PATH_MAX" "0 $(find t | sed 's|^t|c|' | cksum)" "$rc $(find c | cksum)"
    rc=0; lim 64 "$BIN" rm -r t c 2>/dev/null || rc=$?
    expect_eq "rm -r past PATH_MAX" "0 no" "$rc $([ -e t ] || [ -e c ] && echo yes || echo no)"
else
    SKIP=$((SKIP + 6))
fi

# --- 7. a directory moved during the walk stops it ------------------------------
# ⛔ THE SECURITY HALF. Level 3 of a 45-level chain is moved into `elsewhere/` while the walk is
# at level 40, with levels 0-13 closed. Coming back up, `..` of level 3 is `elsewhere`, not
# level 2: carrying on would remove `elsewhere/a` and then whatever level 2 had left to read,
# by name, from `elsewhere`. The walk must stop, exit 1, and leave `elsewhere` alone.
# ⚠ `elsewhere/a` is the moved level itself, emptied by the walk (it was inside it); removing
# it is the first thing a walk that did not check would do, whatever the directory order.
mkmoved() {
    rm -rf t elsewhere; mkdir -p elsewhere; echo outside > elsewhere/keep.txt
    p=t; i=0; mkdir t
    while [ "$i" -lt 45 ]; do
        if [ "$i" = 2 ]; then echo inside > "$p/keep.txt"; fi
        if [ "$i" = 39 ]; then p="$p/m"; else p="$p/a"; fi
        mkdir "$p"; i=$((i + 1))
    done
}
mkmoved
rc=0
lim 1024 "$BIN" find t -depth -name m -exec mv t/a/a/a elsewhere/a \; -delete -o -delete 2>err || rc=$?
expect_eq "find -delete, moved mid-walk: exit"      "1" "$rc"
expect_eq "find -delete, moved mid-walk: stopped"   "1" "$(grep -c 'directory moved during the walk; stopping' err || true)"
expect_eq "find -delete, moved mid-walk: elsewhere" "outside yes" "$(cat elsewhere/keep.txt) $([ -d elsewhere/a ] && echo yes || echo no)"
if [ "$HAVE_PY" = 1 ]; then
    mkmoved
    # `rm -ri` on a terminal: at the prompt for level 41, move level 3, then answer yes to all.
    out=$(BIN="$BIN" python3 -I - <<'PY'
import os, pty, sys, signal
signal.alarm(120)       # a walk that loops must fail the case, not hang the suite
target = "descend into directory 't" + "/a" * 39 + "/m'"
pid, fd = pty.fork()
if pid == 0:
    os.execv(os.environ['BIN'], [os.environ['BIN'], 'rm', '-ri', 't'])
buf = b''; log = b''; moved = False
while True:
    try: data = os.read(fd, 65536)
    except OSError: break
    if not data: break
    buf += data; log += data
    while b'? ' in buf:
        prompt, buf = buf.split(b'? ', 1)
        if not moved and prompt.decode(errors='replace').endswith(target):
            os.rename('t/a/a/a', 'elsewhere/a'); moved = True
        os.write(fd, b'y\n')
_, st = os.waitpid(pid, 0)
stopped = b'directory moved during the walk; stopping' in log
print(os.waitstatus_to_exitcode(st), moved, stopped)
PY
) || true
    expect_eq "rm -ri, moved mid-walk: exit, moved, stopped" "1 True True" "$out"
    expect_eq "rm -ri, moved mid-walk: elsewhere" "outside yes" "$(cat elsewhere/keep.txt) $([ -d elsewhere/a ] && echo yes || echo no)"
else
    SKIP=$((SKIP + 2))
fi
rm -rf t elsewhere err

# --- 8. the stack guard (ulimit -s 1024) -----------------------------------------
# ⛔ A recursive walk that no longer runs out of descriptors runs out of stack, and the kernel's
# answer is SIGSEGV: exit 139, no message. Under a 1 MiB stack a 3,000-level tree is far past
# what `du`, `find`, `cp` and `grep` can hold; each must say so and exit 1 (`grep` 2). `rm -r`
# is a loop and must remove the tree all the same.
if [ "$HAVE_PY" = 1 ]; then
    chain t 3000
    for u in "du -s t" "find t" "cp -R t c" "grep -r hit t"; do
        rc=0
        # shellcheck disable=SC2086
        sh -c 'ulimit -s 1024; exec timeout "$0" "$@"' "$T" "$BIN" $u >/dev/null 2>err || rc=$?
        want=1; [ "${u%% *}" = grep ] && want=2
        expect_eq "stack guard: $u" "$want 1" "$rc $(grep -c 'directory nested too deeply to walk' err || true)"
    done
    rm -rf c
    rc=0; sh -c 'ulimit -s 1024; exec timeout "$0" "$@"' "$T" "$BIN" rm -r t 2>/dev/null || rc=$?
    expect_eq "rm -r under a 1 MiB stack" "0 no" "$rc $([ -e t ] && echo yes || echo no)"
else
    SKIP=$((SKIP + 5))
fi

# --- summary ---
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed, %d skipped (%d total)\n' "$PASS" "$FAIL" "$SKIP" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
