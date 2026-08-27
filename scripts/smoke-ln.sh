#!/bin/sh
# smoke-ln.sh — behavioural test for `kriya ln`.
#
# Covers symbolic + hard link creation, -f overwrite, -n no-dereference
# (the ln -s -f -n deploy-retarget idiom in ADR 0003), -P hard-link
# the symlink itself, multi-into-dir, and the verbose form.

set -e

# ⛔ GNU's `ls` and `stat` honour QUOTING_STYLE and kriya does not, so a host
# exporting it fails every quoted comparison below at once — blaming kriya for
# the shell's environment. ⚠ Same shape as du/df's BLOCK_SIZE and echo's
# POSIXLY_CORRECT: if kriya ignores a variable, the ORACLE must ignore it too.
# ⭐ Caught by the hostile-environment matrix run, not by CI.
unset QUOTING_STYLE

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

expect_symlink() {
    if [ -L "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' is not a symlink\n" "$1" "$2" >&2
    fi
}

expect_target() {
    actual=$(readlink "$2")
    expect_eq "$1" "$3" "$actual"
}

# --- symbolic links ---
echo "src content" > src.txt

expect_exit "ln -s create"           0 "$BIN" ln -s src.txt link1
expect_symlink "link1 is a symlink"  link1
expect_target "link1 -> src.txt"     link1 src.txt

# Existing dest without -f — error.
expect_exit "ln -s clobber w/o -f"   1 "$BIN" ln -s src.txt link1

# Existing dest with -f — overwrites.
expect_exit "ln -s -f overwrite"     0 "$BIN" ln -s -f src.txt link1
expect_symlink "link1 still symlink" link1

# --- single-arg form (link name = basename of target) ---
mkdir other && echo "data" > other/payload
expect_exit "ln -s single-arg"       0 "$BIN" ln -s other/payload
expect_symlink "payload created"     payload
expect_target "payload -> other/payload"  payload other/payload

# --- hard links ---
expect_exit "ln (hard)"              0 "$BIN" ln src.txt hardlink1
src_inode=$(stat -c %i src.txt)
hard_inode=$(stat -c %i hardlink1)
expect_eq "hard inode matches src"   "$src_inode" "$hard_inode"

# Hard link to a symlink without -P: follows the symlink — hardlink
# points at src.txt's inode, NOT link1's symlink inode.
expect_exit "ln (hard, follow)"      0 "$BIN" ln link1 hardThroughLink
through_inode=$(stat -c %i hardThroughLink)
expect_eq "follow: same inode as src"  "$src_inode" "$through_inode"

# Hard link to a symlink WITH -P: link the symlink itself.
link1_inode=$(stat -c %i link1)
expect_exit "ln -P (no follow)"      0 "$BIN" ln -P link1 hardOfLink
of_link_inode=$(stat -c %i hardOfLink)
expect_eq "-P: hardlink to symlink"  "$link1_inode" "$of_link_inode"

# --- ADR 0003 deploy-retarget idiom: ln -s -f -n NEW LINK ---
mkdir current.v1 current.v2
expect_exit "first deploy"           0 "$BIN" ln -s current.v1 current
expect_target "current -> v1"        current current.v1

# Without -n, ln -s -f NEW LINK would create current/current.v2 inside
# the symlinked dir. With -n, it replaces the symlink.
expect_exit "retarget with -n"       0 "$BIN" ln -s -f -n current.v2 current
expect_target "current -> v2"        current current.v2
expect_symlink "current still link"  current
# current.v1 must still exist (we didn't traverse into it).
if [ -d current.v1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL current.v1 vanished" >&2; fi

# --- multi-source-into-dir ---
mkdir bindir
echo a > a.bin && echo b > b.bin
expect_exit "ln -s a b bindir/"      0 "$BIN" ln -s ../a.bin ../b.bin bindir/
expect_symlink "bindir/a.bin"        bindir/a.bin
expect_symlink "bindir/b.bin"        bindir/b.bin

# Multi-source with non-directory final arg — usage error.
expect_exit "multi non-dir final"    2 "$BIN" ln -s ../a.bin ../b.bin notadir

# --- errors ---
expect_exit "no operands"            2 "$BIN" ln

# Hard link to a non-existent target without -s: ENOENT (kernel-level).
expect_exit "hard to missing"        1 "$BIN" ln nope deadhard

# Symbolic link to a non-existent target is FINE (POSIX) — the target
# is just text.
expect_exit "symlink to missing"     0 "$BIN" ln -s nope dangling
expect_symlink "dangling exists"     dangling

# --- verbose ---
out=$("$BIN" ln -s -v src.txt vlink 2>&1)
expected="kriya ln: 'vlink' -> 'src.txt'"
expect_eq "verbose -s output" "$expected" "$out"

# --- -f must not destroy the destination on failure (v1.1.11) -----------
# ⛔ `-f` used to unlink the destination and THEN attempt the link, so any
# failure afterwards left nothing behind. Measured: `ln -f /nonexistent-src
# keep.txt` reported "no such file or directory" and DELETED keep.txt. Now the
# link is made under a temp name in the same directory and renamed over the
# target, so the destination is only replaced once a replacement exists.
#
# ⚠ The obvious shortcut — unlink only on EEXIST, since that "proves" the source
# is linkable — is NOT enough: the kernel reports EEXIST before EXDEV, so a
# cross-device link onto an existing path still answered 17 and still deleted.
mkdir -p ffail
echo IMPORTANT > ffail/keep.txt
echo SRC       > ffail/src.txt

expect_exit "ln -f missing src fails"    1 "$BIN" ln -f /nonexistent-src ffail/keep.txt
expect_eq   "destination survives"       "IMPORTANT" "$(cat ffail/keep.txt)"
expect_exit "ln -f valid src replaces"   0 "$BIN" ln -f ffail/src.txt ffail/keep.txt
expect_eq   "destination replaced"       "SRC" "$(cat ffail/keep.txt)"
# No temp file is left behind on either path.
expect_eq   "no stray temp files"        "0" "$(ls -A ffail | grep -c 'kriya-ln-tmp')"

# =====================================================================
# -r / --relative, -T / --no-target-directory, -t / --target-directory
# =====================================================================

# ⭐ EVERY `-r` CASE IS DIFFERENTIAL AGAINST GNU, because the rule is not
# guessable: `-r` does NOT count `..` on the strings you typed. It canonicalises
# BOTH operands — the target and the link's directory — and only then computes
# the relative form. Asserting a hand-written expected string would be asserting
# whatever the author assumed.
same_rel() {   # same_rel <name> <target> <link-basename> [subdir]
    name=$1; tgt=$2; lnk=$3; sub=$4
    rm -rf rel; mkdir -p rel/k rel/g
    [ -n "$sub" ] && mkdir -p "rel/k/$sub" "rel/g/$sub"
    ( cd rel/k && mkdir -p a/b real/sub ldir && echo t > a/b/target && echo o > other.txt \
        && echo x > real/sub/f && ln -s real slink && ln -s ldir lslink \
        && ln -s real/sub/f finalsym && ln -s /nowhere dangling
      "$BIN" ln -sr "$tgt" "${sub:+$sub/}$lnk" 2>/dev/null || true )
    ( cd rel/g && mkdir -p a/b real/sub ldir && echo t > a/b/target && echo o > other.txt \
        && echo x > real/sub/f && ln -s real slink && ln -s ldir lslink \
        && ln -s real/sub/f finalsym && ln -s /nowhere dangling
      ln -sr "$tgt" "${sub:+$sub/}$lnk" 2>/dev/null || true )
    expect_eq "$name" "$(readlink "rel/g/${sub:+$sub/}$lnk" 2>/dev/null)" \
                      "$(readlink "rel/k/${sub:+$sub/}$lnk" 2>/dev/null)"
}
same_rel "-r same directory"           a/b/target l
same_rel "-r plain name"               other.txt  l
same_rel "-r into a subdirectory"      a/b/target l  c/d
same_rel "-r from deeper up"           other.txt  l  a/b
# ⛔ THE CASES THAT DECIDE THE ALGORITHM. A symlinked directory in the TARGET's
# path, the target being a symlink ITSELF, and a DANGLING target — all three
# resolve, and a textual implementation gets all three wrong.
same_rel "-r through a symlinked dir"  slink/sub/f l
same_rel "-r target IS a symlink"      finalsym    l
same_rel "-r dangling target"          dangling    l
same_rel "-r link inside a symlinked dir" real/sub/f l lslink
# ⚠ A target that does not exist at all still produces a link — GNU exits 0.
same_rel "-r nonexistent target"       nonexistent l

# An ABSOLUTE target comes back relative.
rm -rf abs; mkdir -p abs/k abs/g
echo o > abs/k/t; echo o > abs/g/t
( cd abs/k && "$BIN" ln -sr "$PWD/t" l )
( cd abs/g && ln -sr "$PWD/t" l )
expect_eq "-r absolute target becomes relative" "$(readlink abs/g/l)" "$(readlink abs/k/l)"
expect_eq "...and it really is relative"        "t" "$(readlink abs/k/l)"

# ⚠ `-r` has nothing to say about a hard link, and GNU refuses rather than
# ignoring the flag. ⛔ kriya exits 2 where GNU exits 1 — the ADR-0008 usage-error
# convention this file already asserts for the multi-source error below.
rm -rf rr; mkdir rr; echo x > rr/t
expect_exit "-r without -s is refused"      2 "$BIN" ln -r rr/t rr/h
expect_eq "...with GNU's wording"           "1" \
          "$("$BIN" ln -r rr/t rr/h2 2>&1 | grep -c 'cannot do --relative without --symbolic')"
expect_eq "...and no link was made"         "no" "$([ -e rr/h ] && echo yes || echo no)"

# --- -T: the destination is a NAME, never a directory to descend into -------
# ⛔ `-T` IS NOT `-n`. `-n` asks "is the destination a symlink TO a directory";
# `-T` refuses to descend into a REAL directory too. The pair below is the whole
# difference, and it is the reason the two cannot share an implementation.
rm -rf tt; mkdir -p tt/dd; echo o > tt/other
expect_exit "no -T descends into a real dir" 0 "$BIN" ln -s ../other tt/dd
expect_eq "...creating a link inside it"     "other" "$(ls tt/dd)"
rm -rf tt; mkdir -p tt/dd; echo o > tt/other
expect_exit "-T refuses to descend"          1 "$BIN" ln -sT ../other tt/dd
expect_eq "...leaving the directory alone"   "yes" "$([ -d tt/dd ] && echo yes || echo no)"
expect_eq "...and matching GNU's exit"       "$(ln -sT ../other tt/dd 2>/dev/null; echo $?)" \
                                             "$("$BIN" ln -sT ../other tt/dd 2>/dev/null; echo $?)"
# With -f a symlink-to-directory IS replaced, which is the deploy-retarget idiom.
rm -rf tt; mkdir -p tt/e; echo o > tt/other
( cd tt && ln -s e sdd && "$BIN" ln -sfT other sdd )
expect_eq "-sfT replaces a symlink-to-dir"   "other" "$(readlink tt/sdd)"
expect_eq "...and it is still a symlink"     "symbolic link" "$(stat -c %F tt/sdd)"

# --- -t DIR: every operand is a source --------------------------------------
# ⭐ The flag exists so a command built from a variable that might expand to one
# name — or to none — cannot silently reinterpret the last one as a destination.
rm -rf td; mkdir -p td/dir; echo a > td/a; echo b > td/b
expect_exit "-t links every operand"         0 "$BIN" ln -s -t td/dir ../a ../b
expect_eq "...into the target directory"     "a b" "$(ls td/dir | tr '\n' ' ' | sed 's/ $//')"
rm -rf td2; mkdir -p td2/dir; echo a > td2/a
expect_exit "--target-directory= long form"  0 "$BIN" ln -s --target-directory=td2/dir ../a
expect_eq "...also works"                    "a" "$(ls td2/dir)"
# ⚠ ONE operand only — the shape that is ambiguous without `-t` and is not with it.
rm -rf td3; mkdir -p td3/dir; echo a > td3/a
expect_exit "-t with a single source"        0 "$BIN" ln -s -t td3/dir ../a
expect_eq "...still links into the dir"      "a" "$(ls td3/dir)"

# Error shapes, matching GNU's wording.
rm -rf te; mkdir te; echo x > te/f
expect_exit "-t on a missing directory"      1 "$BIN" ln -s -t te/nodir te/f
expect_exit "-t on a non-directory"          1 "$BIN" ln -s -t te/f te/f
expect_eq "...with GNU's wording"            "1" \
          "$("$BIN" ln -s -t te/f te/f 2>&1 | grep -c "is not a directory")"
expect_exit "-t and -T together are refused" 2 "$BIN" ln -s -t te -T te/f
expect_eq "...with GNU's wording"            "1" \
          "$("$BIN" ln -s -t te -T te/f 2>&1 | grep -c 'cannot combine --target-directory and --no-target-directory')"

# =====================================================================
# What an adversarial review pass found in the first cut of these flags
# =====================================================================

# ⛔ `-T` MEANS "THE DESTINATION IS A NAME", which only makes sense for a PAIR.
# It was checked in the two-or-more arm alone, so `ln -sT f` fell into the
# ONE-operand form and tried to link `f` to itself.
rm -rf ta; mkdir ta; echo x > ta/f
expect_exit "-T with one operand is refused"   2 "$BIN" ln -sT ta/f
expect_eq "...with GNU's wording"              "1" \
          "$("$BIN" ln -sT ta/f 2>&1 | grep -c "missing destination file operand after")"
expect_eq "...and creates nothing"             "f" "$(ls ta)"
expect_exit "-T with three operands is refused" 2 "$BIN" ln -sT ta/f ta/f ta
expect_eq "...with GNU's wording"              "1" \
          "$("$BIN" ln -sT ta/f ta/f ta 2>&1 | grep -c "extra operand")"

# ⛔ A REPEATED `-t` IS FATAL, not last-one-wins. The flag table keeps only the
# last value, so taking it would silently link into a directory the user also
# named something else for.
rm -rf tb; mkdir -p tb/one tb/two; echo x > tb/f
expect_exit "-t twice is refused"              2 "$BIN" ln -s -t tb/one -t tb/two tb/f
expect_eq "...with GNU's wording"              "1" \
          "$("$BIN" ln -s -t tb/one -t tb/two tb/f 2>&1 | grep -c 'multiple target directories specified')"
# ⚠ `ls DIR1 DIR2` prints HEADERS, so an empty pair is not the empty string —
# count the entries instead.
expect_eq "...and neither directory was used"  "0" \
          "$(find tb/one tb/two -mindepth 1 | wc -l | tr -d ' ')"

# ⛔ A TRAILING SLASH ON A SOURCE OPERAND. `path_basename_ptr` is a pointer-only
# fast path whose own header says "caller must trim trailing slashes", and
# `cmd_ln` handed it raw operand text — so `ln -s f/ dir/` failed with
# `dir/f/: no such file or directory` where GNU creates `dir/f`.
# ⚠ PRE-EXISTING in the multi-into-directory arm, which is why both forms are
# asserted here and not just the new one.
rm -rf tc; mkdir -p tc/dir; echo x > tc/f
expect_exit "-t with a trailing-slash source"  0 "$BIN" ln -s -t tc/dir ../f/
expect_eq "...creates the trimmed name"        "f" "$(ls tc/dir)"
rm -rf td4; mkdir -p td4/dir; echo x > td4/f
expect_exit "multi-into-dir, trailing slash"   0 sh -c "cd '$WORK/td4' && '$BIN' ln -s f/ dir/"
expect_eq "...also creates the trimmed name"   "f" "$(ls td4/dir)"

# ⚠ `/` HAS NO BASENAME, and `path_join(dir, "/")` yields `/` — so the first cut
# tried to create a link at the filesystem ROOT and reported `/: file exists`.
rm -rf te2; mkdir -p te2/dir
expect_exit "a / source operand is refused"    1 "$BIN" ln -s -t te2/dir /
expect_eq "...and nothing lands in the dir"    "" "$(ls te2/dir)"

# ⛔ `-r` USED TO WRITE A WRONG LINK, SILENTLY, WHENEVER CANONICALISATION FAILED.
# The fallback returned the operand text — which is resolved against the CWD,
# while a symlink's text is resolved against the LINK's own directory — so any
# link not in the cwd pointed somewhere else, with exit 0 and no diagnostic.
# ⛔ The ELOOP case is the damaging one: it resolved to a DIFFERENT REAL FILE,
# which is the exact failure `-r` exists to prevent. Root cause was in
# `fs_realpath`'s ALLOW_MISSING mode (see smoke-realpath.sh), so `realpath -m`
# had it too.
rm -rf fb; mkdir -p fb/out fb/priv/sub
echo WRONG > fb/out/loopa
( cd fb && ln -s loopb loopa && ln -s loopa loopb && echo x > plain && echo REAL > priv/sub/f )
# ⚠ Two trees, not two names in one: the link goes in a SUBDIRECTORY (that is
# the whole point — the fallback is only wrong when the link is not in the cwd),
# so a `g_` prefix on the path would name a directory that does not exist. The
# first version of this helper did exactly that and compared nothing to
# something.
same_fb() {   # same_fb <name> <target> <link>
    rm -rf fbk fbg
    cp -a fb fbk 2>/dev/null; cp -a fb fbg 2>/dev/null
    ( cd fbk && "$BIN" ln -sr "$2" "$3" 2>/dev/null ) || true
    ( cd fbg && ln -sr "$2" "$3" 2>/dev/null ) || true
    expect_eq "$1" "$(readlink "fbg/$3" 2>/dev/null)" "$(readlink "fbk/$3" 2>/dev/null)"
}
same_fb "-r through a symlink LOOP"     loopa      out/m
same_fb "-r through a plain file"       plain/sub  out/l
# ⚠ `cp -a` of an unsearchable directory fails, and the copy leaves one behind
# that the trap cannot remove — so the EACCES case chmods inside the two copies
# rather than in the source tree.
rm -rf fbk fbg
cp -a fb fbk; cp -a fb fbg
chmod 000 fbk/priv fbg/priv
( cd fbk && "$BIN" ln -sr priv/sub/f out/p 2>/dev/null ) || true
( cd fbg && ln -sr priv/sub/f out/p 2>/dev/null ) || true
chmod 755 fbk/priv fbg/priv
expect_eq "-r through an unsearchable dir" "$(readlink fbg/out/p 2>/dev/null)" "$(readlink fbk/out/p 2>/dev/null)"
# ⭐ And the ELOOP link must not resolve to the unrelated file beside it.
same_fb "-r through a symlink LOOP again" loopa out/m
expect_eq "...and the loop link does not read as another file" "no" \
          "$([ "$(cat fbk/out/m 2>/dev/null)" = "WRONG" ] && echo yes || echo no)"

# ⚠ The REAL errno, not a hardcoded ENOENT: `-t f/sub` where `f` is a file is
# ENOTDIR, and "no such file or directory" sends the reader looking for
# something that is right there.
rm -rf tf; mkdir tf; echo x > tf/f
expect_eq "-t reports ENOTDIR as itself"       "1" \
          "$("$BIN" ln -s -t tf/f/sub tf/f 2>&1 | grep -c 'not a directory')"

# The introspection interface knows about all three.
expect_eq "--help names --relative"          "1" "$("$BIN" ln --help 2>&1 | grep -c -- '--relative')"
expect_eq "--help names --target-directory"  "1" "$("$BIN" ln --help 2>&1 | grep -c -- '--target-directory')"
expect_eq "--help names --no-target-directory" "1" \
          "$("$BIN" ln --help 2>&1 | grep -c -- '--no-target-directory')"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
