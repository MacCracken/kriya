#!/bin/sh
# smoke-ownership-xattr.sh — behavioural test for `--preserve=ownership` and
# `--preserve=xattr` (v1.6.1), and for the `mv` cross-filesystem carry that
# rides on them.
#
# ⛔ THE HARD PART OF THIS FILE IS THE ENVIRONMENT, NOT THE ASSERTIONS. Three
# things it cannot assume, each of which would otherwise abort the whole script
# under `set -e` rather than skip one case:
#
#   - **Privilege.** A non-root caller cannot chown to another user, so the
#     interesting half of ownership is unreachable... except inside a user
#     namespace, where `unshare -Ur` makes the caller uid 0 and a `chown 0:0`
#     succeeds. Probed, used when present, skipped loudly when not.
#     ⚠ The release matrix's "simulated root" condition shims `id` to answer 0.
#     That CANNOT make a chown succeed — so nothing here is guarded on
#     `id -u`, which would skip these cases in the one condition whose name
#     suggests it should run them.
#   - **`user.*` extended attributes.** They need the `attr` tools AND a
#     filesystem that supports the namespace. `$TMPDIR` is frequently tmpfs, and
#     tmpfs only gained `user.*` support in Linux 6.6.
#   - **A second filesystem.** The `mv` cross-filesystem path only exists when
#     there are two devices to move between.
#
# ⭐ What survives all three: a non-root caller CAN chgrp to a group they are
# already in, and that is a real ownership difference kriya has to carry. It is
# the assertion that runs on every runner.

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
SKIP=0

expect_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s:\nexpected:\n%s\ngot:\n%s\n" "$1" "$2" "$3" >&2
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

skip() {
    SKIP=$((SKIP + 1))
    echo "skip: $1"
}

# owner/group/mode/mtime of a path, as one comparable string.
meta() { stat -c '%u:%g %a %Y' "$1" 2>/dev/null; }

# Sorted attribute names, or the empty string. ⚠ python3 rather than getfattr:
# it is always present, it needs no parsing, and it reports an unsupported
# filesystem as an exception rather than as silence.
xa() {
    python3 - "$1" <<'PY' 2>/dev/null || true
import os, sys
try:
    print(",".join(sorted(os.listxattr(sys.argv[1]))))
except OSError:
    print("XATTR-ERR")
PY
}
xget() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import os, sys
try:
    print(repr(os.getxattr(sys.argv[1], sys.argv[2])))
except OSError as e:
    print("ERR")
PY
}
xset() {
    python3 - "$1" "$2" "$3" <<'PY' 2>/dev/null
import os, sys
os.setxattr(sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode())
PY
}

# ---------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------

# (a) a group we belong to that is NOT our primary — a real ownership
#     difference an unprivileged caller is allowed to create.
SECGROUP=""
for g in $(id -G 2>/dev/null); do
    if [ "$g" != "$(id -g)" ]; then SECGROUP="$g"; break; fi
done

# (b) `user.*` xattr support on THIS filesystem, established by actually
#     setting one rather than by guessing from the mount type.
: > xprobe
HAVE_XATTR=no
if xset xprobe user.probe v 2>/dev/null; then
    if [ "$(xa xprobe)" = "user.probe" ]; then HAVE_XATTR=yes; fi
fi

# (c) a user namespace we can become uid 0 in.
HAVE_USERNS=no
if command -v unshare >/dev/null 2>&1; then
    if unshare -Ur true 2>/dev/null; then HAVE_USERNS=yes; fi
fi

# (d) a second filesystem to move across.
OTHERFS=""
WORKDEV=$(stat -c %d . 2>/dev/null)
for cand in /tmp /var/tmp "$HOME/.cache" /dev/shm; do
    [ -d "$cand" ] || continue
    [ -w "$cand" ] || continue
    d=$(stat -c %d "$cand" 2>/dev/null) || continue
    if [ -n "$d" ] && [ "$d" != "$WORKDEV" ]; then OTHERFS="$cand"; break; fi
done

# (e) a root-owned setuid binary to prove the bit-clearing rule against.
SUIDSRC=""
for cand in /usr/bin/passwd /usr/bin/sudo /bin/su /usr/bin/su /usr/bin/newgrp; do
    if [ -u "$cand" ] && [ -r "$cand" ]; then
        if [ "$(stat -c %u "$cand")" = "0" ]; then SUIDSRC="$cand"; break; fi
    fi
done

# ---------------------------------------------------------------------
# Ownership — the part that runs everywhere
# ---------------------------------------------------------------------

echo own > own.txt
chmod 0644 own.txt
touch -t 202001010000.00 own.txt

# ⭐ The no-op chown. A caller setting their OWN uid/gid on their OWN file
# always succeeds, so this runs on every runner — and it is not a tautology: it
# is what catches a wrong syscall number, a swapped argument order, and the u32
# packing trap where `st_uid` and `st_gid` share one 64-bit load and an unmasked
# read yields `uid | gid << 32`.
expect_exit "--preserve=ownership on our own file" 0 "$BIN" cp --preserve=ownership own.txt own.k
cp --preserve=ownership own.txt own.g
expect_eq "...owner matches GNU"      "$(stat -c '%u:%g' own.g)" "$(stat -c '%u:%g' own.k)"
expect_eq "...and is still ours"      "$(id -u):$(id -g)" "$(stat -c '%u:%g' own.k)"

if [ -n "$SECGROUP" ]; then
    echo sec > sec.txt
    chgrp "$SECGROUP" sec.txt
    chmod 0644 sec.txt
    touch -t 202001010000.00 sec.txt
    SRCG=$(stat -c %g sec.txt)
    expect_eq "the fixture really has a non-primary group" "no" \
              "$([ "$SRCG" = "$(id -g)" ] && echo yes || echo no)"

    # ⛔ THIS IS THE CASE THAT PROVES `-p` INCLUDES OWNERSHIP. kriya's `-p` was
    # mode+timestamps for six releases; GNU's has always been
    # mode+ownership+timestamps, and the two are indistinguishable until the
    # fixture's group differs from the caller's.
    for f in "-p" "--preserve=ownership" "--preserve=mode,ownership,timestamps"; do
        rm -f g_k g_g
        "$BIN" cp $f sec.txt g_k
        cp $f sec.txt g_g
        expect_eq "cp $f keeps the group"        "$SRCG" "$(stat -c %g g_k)"
        expect_eq "cp $f matches GNU"            "$(meta g_g)" "$(meta g_k)"
    done
    for f in "--preserve=mode,timestamps" "--preserve=mode"; do
        rm -f n_k n_g
        "$BIN" cp $f sec.txt n_k
        cp $f sec.txt n_g
        expect_eq "cp $f does NOT keep the group" "$(id -g)" "$(stat -c %g n_k)"
        expect_eq "cp $f matches GNU"             "$(meta n_g)" "$(meta n_k)"
    done
    rm -f p_k p_g
    "$BIN" cp p_k 2>/dev/null || true
    "$BIN" cp sec.txt p_k
    cp sec.txt p_g
    expect_eq "plain cp does NOT keep the group"  "$(id -g)" "$(stat -c %g p_k)"
    expect_eq "...and matches GNU"                "$(stat -c '%u:%g %a' p_g)" "$(stat -c '%u:%g %a' p_k)"
else
    skip "the caller belongs to no secondary group — group preservation unverified"
fi

# ⚠ THE CASE ALMOST EVERY REAL CALLER HITS: preserving ownership you do not have
# the privilege to set. GNU exits 0 and says nothing — it only complains when it
# had the privilege to succeed and still failed — so a kriya that reported an
# error here would be noisier than the oracle on an everyday command.
if [ -r /etc/hostname ] && [ "$(stat -c %u /etc/hostname 2>/dev/null)" = "0" ]; then
    for f in "--preserve=ownership" "-p"; do
        rm -f e_k e_g
        krc=0; "$BIN" cp $f /etc/hostname e_k 2>e_kerr || krc=$?
        grc=0; cp $f /etc/hostname e_g 2>e_gerr || grc=$?
        expect_eq "cp $f on an unownable source: exit matches GNU" "$grc" "$krc"
        expect_eq "cp $f on an unownable source: exit 0"           "0"    "$krc"
        expect_eq "cp $f on an unownable source: silent like GNU"  "$([ -s e_gerr ] && echo noisy || echo silent)" \
                  "$([ -s e_kerr ] && echo noisy || echo silent)"
        expect_eq "cp $f on an unownable source: copy exists"      "yes"  "$([ -e e_k ] && echo yes || echo no)"
    done
else
    skip "/etc/hostname is not a readable root-owned file — the EPERM path is unverified"
fi

# ⛔ THE SETUID RULE, WHICH IS THE SECURITY PROPERTY OF THIS RELEASE.
# The bits are cleared when ownership was REQUESTED and could not be fully set —
# and kept when it was never requested. The difference is a setuid binary owned
# by the copying user, made out of one that was not. Measured against GNU:
# `cp -p /usr/bin/passwd out` is 755 and `cp --preserve=mode ... out` is 4755.
if [ -n "$SUIDSRC" ]; then
    for f in "-p" "--preserve=mode,ownership" "-a-not-used --preserve=ownership,mode,timestamps"; do
        case "$f" in -a-not-used*) f="--preserve=ownership,mode,timestamps" ;; esac
        rm -f s_k s_g
        "$BIN" cp $f "$SUIDSRC" s_k 2>/dev/null || true
        cp $f "$SUIDSRC" s_g 2>/dev/null || true
        expect_eq "cp $f drops setuid when ownership failed" "755" "$(stat -c %a s_k)"
        expect_eq "...matching GNU"                          "$(stat -c %a s_g)" "$(stat -c %a s_k)"
    done
    # ⚠ ...and does NOT drop it when ownership was never asked for. Same source,
    # same privilege, opposite answer — which is what makes this a rule about the
    # REQUEST rather than about the caller.
    rm -f m_k m_g
    "$BIN" cp --preserve=mode "$SUIDSRC" m_k 2>/dev/null || true
    cp --preserve=mode "$SUIDSRC" m_g 2>/dev/null || true
    expect_eq "--preserve=mode keeps setuid"  "4755" "$(stat -c %a m_k)"
    expect_eq "...matching GNU"               "$(stat -c %a m_g)" "$(stat -c %a m_k)"
else
    skip "no readable root-owned setuid binary — the bit-clearing rule is unverified against a real one"
fi

# The same rule from the other side: a setuid file we DO own keeps its bits,
# because the chown succeeds. Runs everywhere.
echo mine > mine.txt
chmod 6755 mine.txt
for f in "-p" "--preserve=mode" "--preserve=mode,ownership"; do
    rm -f o_k o_g
    "$BIN" cp $f mine.txt o_k
    cp $f mine.txt o_g
    expect_eq "cp $f keeps setuid on a file we own" "6755" "$(stat -c %a o_k)"
    expect_eq "...matching GNU"                     "$(stat -c %a o_g)" "$(stat -c %a o_k)"
done

# ⛔ THE STICKY BIT IS CLEARED TOO, and the first version of this case could not
# see it: it used a sticky file the CALLER OWNED, where the chown succeeds and
# nothing is dropped at all — so it passed against a mask that kept sticky and
# against the mask that does not. The fixture has to be FOREIGN-OWNED.
#
# ⚠ Two halves, and only together do they pin the mask:
#   ours     → the chown succeeds, everything survives, including sticky;
#   foreign  → the chown fails, and setuid, setgid AND sticky all go.
echo sticky > sticky.txt
chmod 1755 sticky.txt
rm -f st_k st_g
"$BIN" cp -p sticky.txt st_k
cp -p sticky.txt st_g
expect_eq "sticky survives on a file we own"  "1755" "$(stat -c %a st_k)"
expect_eq "...matching GNU"                   "$(stat -c %a st_g)" "$(stat -c %a st_k)"

STICKYSRC=""
for cand in /var/spool/mail /tmp /var/tmp; do
    if [ -d "$cand" ] && [ -r "$cand" ]; then
        m=$(stat -c %a "$cand" 2>/dev/null)
        o=$(stat -c %u "$cand" 2>/dev/null)
        case "$m" in
            1*) if [ "$o" != "$(id -u)" ]; then STICKYSRC="$cand"; break; fi ;;
        esac
    fi
done
if [ -n "$STICKYSRC" ]; then
    # ⚠ `-d`: the DIRECTORY itself, not its contents — /tmp would otherwise be
    # copied wholesale, and the mode of the top-level entry is the whole point.
    rm -rf sk sg; mkdir sk sg
    "$BIN" cp -pR -d "$STICKYSRC" sk/ 2>/dev/null || "$BIN" cp -pR "$STICKYSRC" sk/ 2>/dev/null || true
    cp -pR -d "$STICKYSRC" sg/ 2>/dev/null || cp -pR "$STICKYSRC" sg/ 2>/dev/null || true
    base=$(basename "$STICKYSRC")
    if [ -e "sk/$base" ] && [ -e "sg/$base" ]; then
        expect_eq "sticky is DROPPED on a foreign-owned source" "$(stat -c %a sg/$base)" "$(stat -c %a sk/$base)"
        expect_eq "...and the dropped mode has no id bits at all" "yes" \
                  "$(case "$(stat -c %a sk/$base)" in [0-7][0-7][0-7]) echo yes ;; *) echo no ;; esac)"
        # The control: no ownership requested, so nothing is dropped.
        rm -rf sk2 sg2; mkdir sk2 sg2
        "$BIN" cp --preserve=mode -R "$STICKYSRC" sk2/ 2>/dev/null || true
        cp --preserve=mode -R "$STICKYSRC" sg2/ 2>/dev/null || true
        if [ -e "sk2/$base" ] && [ -e "sg2/$base" ]; then
            expect_eq "--preserve=mode keeps sticky on the same source" \
                      "$(stat -c %a sg2/$base)" "$(stat -c %a sk2/$base)"
        fi
    else
        skip "the sticky source could not be copied — the sticky-drop rule is unverified"
    fi
else
    skip "no foreign-owned sticky directory — the sticky-drop rule is unverified"
fi

# --- symlinks carry their own ownership and timestamps under -p ------
if [ -n "$SECGROUP" ]; then
    rm -rf sl; mkdir sl
    echo target > sl/target
    ln -s target sl/lnk
    chgrp -h "$SECGROUP" sl/lnk
    touch -h -t 202001010000.00 sl/lnk 2>/dev/null || true
    rm -rf sl_k sl_g
    "$BIN" cp -pR sl sl_k
    cp -pR sl sl_g
    expect_eq "a symlink keeps its group under -p" "$(stat -c '%u:%g' sl_g/lnk)" "$(stat -c '%u:%g' sl_k/lnk)"
    expect_eq "...and its mtime"                   "$(stat -c %Y sl_g/lnk)"      "$(stat -c %Y sl_k/lnk)"
    rm -rf sn_k sn_g
    "$BIN" cp -R sl sn_k
    cp -R sl sn_g
    expect_eq "without -p a symlink does not"      "$(stat -c '%u:%g' sn_g/lnk)" "$(stat -c '%u:%g' sn_k/lnk)"
fi

# --- the privileged half, inside a user namespace --------------------
# ⭐ `unshare -Ur` makes the caller uid 0 INSIDE the namespace, so a `chown 0:0`
# really succeeds and the positive path — ownership preserved, setuid KEPT
# because nothing failed — becomes testable without any privilege outside.
if [ "$HAVE_USERNS" = yes ]; then
    nsout=$(unshare -Ur sh -c '
        set -e
        cd "$1"
        rm -rf ns; mkdir ns; cd ns
        echo payload > s
        chown 0:0 s
        chmod 4755 s
        "$2" cp -p s k
        cp -p s g
        printf "%s|%s\n" "$(stat -c "%u:%g %a" k)" "$(stat -c "%u:%g %a" g)"
    ' _ "$WORK" "$BIN" 2>/dev/null) || nsout=""
    if [ -n "$nsout" ]; then
        k_side=${nsout%%|*}
        g_side=${nsout##*|}
        expect_eq "in a userns, -p preserves root ownership" "0:0 4755" "$k_side"
        expect_eq "...and matches GNU there"                 "$g_side"  "$k_side"
    else
        skip "the user namespace could not be set up — the ownership-succeeds path is unverified"
    fi
else
    skip "no usable user namespace — the ownership-succeeds path is unverified"
fi

# ---------------------------------------------------------------------
# Extended attributes
# ---------------------------------------------------------------------

if [ "$HAVE_XATTR" = yes ]; then
    echo xa > xa.txt
    xset xa.txt user.one A
    xset xa.txt user.two B

    expect_exit "--preserve=xattr"            0 "$BIN" cp --preserve=xattr xa.txt xa_k
    cp --preserve=xattr xa.txt xa_g
    expect_eq "both attributes are carried"   "user.one,user.two" "$(xa xa_k)"
    expect_eq "...matching GNU"               "$(xa xa_g)"        "$(xa xa_k)"
    expect_eq "...and so are the values"      "$(xget xa_g user.one)" "$(xget xa_k user.one)"

    # ⚠ The matrix that says which flag carries them. ⛔ `-p` does NOT — GNU's
    # `-p` is mode+ownership+timestamps and stops there.
    for f in "-p" "--preserve=mode,timestamps" "--preserve=ownership"; do
        rm -f nx_k nx_g
        "$BIN" cp $f xa.txt nx_k
        cp $f xa.txt nx_g
        expect_eq "cp $f carries no attributes"  ""            "$(xa nx_k)"
        expect_eq "...matching GNU"              "$(xa nx_g)"  "$(xa nx_k)"
    done
    rm -f px_k px_g
    "$BIN" cp xa.txt px_k
    cp xa.txt px_g
    expect_eq "plain cp carries none"            ""            "$(xa px_k)"
    expect_eq "...matching GNU"                  "$(xa px_g)"  "$(xa px_k)"

    # ⛔ VALUES ARE BYTES, NOT STRINGS. An EMPTY value must still be SET, and a
    # value with embedded NULs must survive intact — either one would be lost by
    # an implementation that reached for `strlen`.
    echo edge > edge.txt
    python3 - edge.txt <<'PY'
import os, sys
p = sys.argv[1]
os.setxattr(p, b"user.empty", b"")
os.setxattr(p, b"user.bin", bytes([0, 1, 2, 255, 0, 9]))
os.setxattr(p, b"user.big", b"Z" * 2000)
PY
    rm -f ed_k ed_g
    "$BIN" cp --preserve=xattr edge.txt ed_k
    cp --preserve=xattr edge.txt ed_g
    expect_eq "empty, binary and long values all arrive" "user.big,user.bin,user.empty" "$(xa ed_k)"
    expect_eq "...matching GNU"                          "$(xa ed_g)"    "$(xa ed_k)"
    expect_eq "an EMPTY value is set, not skipped"       "b''"           "$(xget ed_k user.empty)"
    expect_eq "a value with NUL bytes is intact"         "$(xget ed_g user.bin)" "$(xget ed_k user.bin)"
    expect_eq "a 2000-byte value is intact"              "$(xget ed_g user.big)" "$(xget ed_k user.big)"

    # --- a tree: directories carry them too --------------------------
    rm -rf xt; mkdir -p xt/sub
    echo f > xt/f
    echo g > xt/sub/g
    xset xt      user.dir  D
    xset xt/f    user.file F
    xset xt/sub  user.sub  S
    rm -rf xt_k xt_g
    "$BIN" cp -R --preserve=xattr xt xt_k
    cp -R --preserve=xattr xt xt_g
    expect_eq "the directory itself carries one"  "user.dir"  "$(xa xt_k)"
    expect_eq "so does the file"                  "user.file" "$(xa xt_k/f)"
    expect_eq "so does the subdirectory"          "user.sub"  "$(xa xt_k/sub)"
    expect_eq "...all matching GNU"               "$(xa xt_g),$(xa xt_g/f),$(xa xt_g/sub)" \
                                                  "$(xa xt_k),$(xa xt_k/f),$(xa xt_k/sub)"
    # ⚠ And a -R WITHOUT the flag carries none, on any of the three.
    rm -rf xn_k
    "$BIN" cp -R xt xn_k
    expect_eq "-R alone carries none"             ",,"        "$(xa xn_k),$(xa xn_k/f),$(xa xn_k/sub)"

    # --- combined with everything else -------------------------------
    if [ -n "$SECGROUP" ]; then
        echo all > all.txt
        chgrp "$SECGROUP" all.txt
        chmod 0640 all.txt
        touch -t 202001010000.00 all.txt
        xset all.txt user.all Z
        rm -f al_k al_g
        "$BIN" cp -p --preserve=xattr all.txt al_k
        cp -p --preserve=xattr all.txt al_g
        expect_eq "mode, ownership, times and xattrs together" "$(meta al_g) $(xa al_g)" \
                                                               "$(meta al_k) $(xa al_k)"
    fi

    # --- a failure that is reported rather than swallowed -------------
    # ⚠ Needs a destination filesystem that rejects an attribute the source
    # accepted. tmpfs takes a 64 KiB value where ext4's one-block limit does not,
    # so the pair is constructible exactly when the two filesystems differ.
    if [ -n "$OTHERFS" ]; then
        bigdir=$(mktemp -d "$OTHERFS/kriya-xattr-XXXXXX" 2>/dev/null) || bigdir=""
        if [ -n "$bigdir" ]; then
            echo big > big.txt
            if python3 - big.txt <<'PY' 2>/dev/null
import os, sys
os.setxattr(sys.argv[1], b"user.big", b"X" * 65536)
PY
            then
                krc=0; "$BIN" cp --preserve=xattr big.txt "$bigdir/out_k" 2>bigerr || krc=$?
                grc=0; cp --preserve=xattr big.txt "$bigdir/out_g" 2>/dev/null || grc=$?
                if [ "$grc" != "0" ]; then
                    expect_eq "an unsettable attribute exits non-zero like GNU" "$grc" "$krc"
                    expect_eq "...and says which attribute"  "1" "$(grep -c "user.big" bigerr)"
                    expect_eq "...and names the DESTINATION" "1" "$(grep -c "out_k" bigerr)"
                    expect_eq "...but the file is still copied" "big" "$(cat "$bigdir/out_k")"

                    # ⛔ THE THIRD BEHAVIOUR, which a review pass found after the
                    # first two were written. GNU picks its error handler on
                    # whether the attribute set was named: `mv` reports everything
                    # EXCEPT ENOTSUP and still exits 0. So a `mv` that merely
                    # could not fit one attribute WARNS and moves the file, where
                    # a `mv` onto a filesystem with no xattr support at all says
                    # nothing. The first draft was silent for both.
                    echo bigmv > bigmv.txt
                    python3 - bigmv.txt <<'PY2' 2>/dev/null
import os, sys
os.setxattr(sys.argv[1], b"user.big", b"X" * 65536)
PY2
                    mrc=0
                    "$BIN" mv bigmv.txt "$bigdir/mv_k" 2>mverr || mrc=$?
                    expect_eq "mv warns about an attribute it could not set" "1" \
                              "$(grep -c "user.big" mverr)"
                    expect_eq "...and still exits 0"                        "0"     "$mrc"
                    expect_eq "...and still MOVES the file"                 "moved" \
                              "$([ -e bigmv.txt ] && echo LEFT || echo moved)"
                    expect_eq "...and the file arrives"                     "bigmv" "$(cat "$bigdir/mv_k")"
                else
                    skip "the second filesystem accepted the oversized attribute — failure path unverified"
                fi
            else
                skip "could not set an oversized attribute — failure path unverified"
            fi
            rm -rf "$bigdir"
        else
            skip "could not create a directory on a second filesystem — failure path unverified"
        fi
    else
        skip "only one filesystem available — the xattr failure path is unverified"
    fi
else
    skip "this filesystem does not support user.* xattrs — the whole xattr half is unverified"
fi

# ---------------------------------------------------------------------
# mv across a filesystem boundary
# ---------------------------------------------------------------------
# ⛔ M8 audit rows 35351 and 35354, measured as live divergences before this
# release: GNU's cross-filesystem `mv` preserved group and extended attributes
# and kriya's dropped both. `mv` has no `--preserve` flag — a move is supposed to
# look like a rename, so it carries everything it can.
if [ -n "$OTHERFS" ]; then
    mvdir=$(mktemp -d "$OTHERFS/kriya-mv-XXXXXX" 2>/dev/null) || mvdir=""
    if [ -n "$mvdir" ]; then
        for impl in kriya gnu; do
            rm -f "$mvdir/out"
            echo moved > mv_src
            chmod 0640 mv_src
            [ -n "$SECGROUP" ] && chgrp "$SECGROUP" mv_src
            touch -t 202001010000.00 mv_src
            [ "$HAVE_XATTR" = yes ] && xset mv_src user.mv M
            before=$(stat -c '%u:%g %a %Y' mv_src)
            if [ "$impl" = kriya ]; then "$BIN" mv mv_src "$mvdir/out"; else mv mv_src "$mvdir/out"; fi
            eval "after_$impl=\"\$(stat -c '%u:%g %a %Y' '$mvdir/out') \$(xa "$mvdir/out")\""
            eval "want_$impl=\"\$before\""
        done
        expect_eq "cross-filesystem mv carries everything, as GNU does" "$after_gnu" "$after_kriya"

        # ⚠ And the DIRECTORY form, which takes a different path entirely — a
        # recursive copy followed by a recursive remove, rather than one
        # `_cp_one`. The metadata has to survive on the directory itself as well
        # as on what is inside it.
        for impl in kriya gnu; do
            rm -rf "$mvdir/tree"
            rm -rf mvt; mkdir -p mvt/sub
            echo df > mvt/f
            echo dg > mvt/sub/g
            chmod 2750 mvt
            chmod 0640 mvt/f
            [ -n "$SECGROUP" ] && chgrp "$SECGROUP" mvt mvt/f
            touch -t 202001010000.00 mvt/f mvt
            if [ "$HAVE_XATTR" = yes ]; then xset mvt user.d D; xset mvt/f user.f F; fi
            if [ "$impl" = kriya ]; then "$BIN" mv mvt "$mvdir/tree"; else mv mvt "$mvdir/tree"; fi
            eval "tree_$impl=\"\$(stat -c '%u:%g %a %Y' "$mvdir/tree") \$(xa "$mvdir/tree") \$(stat -c '%u:%g %a %Y' "$mvdir/tree/f") \$(xa "$mvdir/tree/f")\""
        done
        expect_eq "a cross-filesystem DIRECTORY move carries it too" "$tree_gnu" "$tree_kriya"

        # ⛔ AND THE SYMLINK FORM, which takes a third path — a readlink and a
        # symlink, not a copy — and so missed the metadata `cp` learned to carry.
        # A cross-filesystem move of a symlink arrived owned by the caller and
        # stamped now, which is the exact surface M8 audit row 35351 names.
        if [ -n "$SECGROUP" ]; then
            for impl in kriya gnu; do
                rm -f "$mvdir/lnk"
                ln -sf some-target mvl
                chgrp -h "$SECGROUP" mvl
                touch -h -t 202001010000.00 mvl 2>/dev/null || true
                if [ "$impl" = kriya ]; then "$BIN" mv mvl "$mvdir/lnk"; else mv mvl "$mvdir/lnk"; fi
                eval "lnk_$impl=\"\$(stat -c '%u:%g %Y' "$mvdir/lnk") \$(readlink "$mvdir/lnk")\""
            done
            expect_eq "a cross-filesystem SYMLINK move keeps its own metadata" "$lnk_gnu" "$lnk_kriya"
            expect_eq "...and really carries the secondary group"             "$SECGROUP" \
                      "$(echo "$lnk_kriya" | cut -d: -f2 | cut -d' ' -f1)"
        fi
        expect_eq "...and it really is the source's metadata"           "$want_kriya $([ "$HAVE_XATTR" = yes ] && echo user.mv || echo "")" \
                                                                       "$after_kriya"
        rm -rf "$mvdir"
    else
        skip "could not create a directory on a second filesystem — cross-filesystem mv unverified"
    fi
else
    skip "only one filesystem available — cross-filesystem mv is unverified"
fi

# ---------------------------------------------------------------------
# What an adversarial review pass found, none of which the cases above
# could see. Every one reproduced before it was fixed.
# ---------------------------------------------------------------------

# ⛔ A CHOWN STRIPS `security.capability`, EVEN A CHOWN THAT CHANGES NOTHING.
# The kernel sets ATTR_KILL_PRIV on every non-directory chown, so writing
# attributes BEFORE the ownership step destroyed the one attribute that carries
# privilege — and an unconditional "preserve" call destroyed it even when the
# ids already matched. Ownership now runs first, and a chown that would change
# nothing is skipped.
# ⚠ Setting `security.*` needs privilege, so this needs the user namespace.
if [ "$HAVE_USERNS" = yes ]; then
    capout=$(unshare -Ur sh -c '
        set -e
        cd "$1"
        rm -rf cap; mkdir cap; cd cap
        echo payload > c.bin
        python3 -c "import os; os.setxattr(\"c.bin\", b\"security.capability\", bytes.fromhex(\"01000002\") + bytes(16))"
        "$2" cp -p --preserve=xattr c.bin k
        cp -p --preserve=xattr c.bin g
        printf "%s|%s\n"             "$(python3 -c "import os; print(sorted(os.listxattr(\"k\")))")"             "$(python3 -c "import os; print(sorted(os.listxattr(\"g\")))")"
    ' _ "$WORK" "$BIN" 2>/dev/null) || capout=""
    if [ -n "$capout" ]; then
        expect_eq "security.capability survives the chown" "${capout##*|}" "${capout%%|*}"
        expect_eq "...and is actually there"               "['security.capability']" "${capout%%|*}"
    else
        skip "could not set security.capability — the ATTR_KILL_PRIV case is unverified"
    fi
else
    skip "no user namespace — the security.capability case is unverified"
fi

# ⛔ `system.posix_acl_access` IS AN EXTENDED ATTRIBUTE, so a walk that copies
# everything copies the ACL — and setting it CHANGES THE DESTINATION'S EFFECTIVE
# PERMISSIONS. Measured before the fix: a 0600 file with `g:<grp>:rwx` came out
# 0670 with the ACL under kriya and 0650 with none under GNU.
if [ "$HAVE_XATTR" = yes ] && command -v setfacl >/dev/null 2>&1 && [ -n "$SECGROUP" ]; then
    echo secret > acl.txt
    chmod 600 acl.txt
    if setfacl -m "g:$SECGROUP:rwx" acl.txt 2>/dev/null; then
        rm -f acl_k acl_g
        "$BIN" cp --preserve=xattr acl.txt acl_k
        cp --preserve=xattr acl.txt acl_g
        expect_eq "the ACL attribute is NOT copied"   "$(xa acl_g)"          "$(xa acl_k)"
        expect_eq "...and the mode is not widened"    "$(stat -c %a acl_g)"  "$(stat -c %a acl_k)"
        expect_eq "...which means no system.* at all" ""                     "$(xa acl_k)"

        # ⚠ ONE DOCUMENTED GAP, asserted so it cannot drift silently. GNU carries
        # a POSIX ACL as part of MODE preservation — its own `copy_acl`, a
        # separate path from the xattr copy — and kriya has no ACL path at all.
        # ⛔ The consequence is not only a missing ACL: the source's st_mode group
        # bits ARE the ACL mask, so copying the mode literally grants the
        # destination's own group the MASK's permissions where GNU grants the
        # group entry's. Measured on a 0640 file with `g:<grp>:rwx`: GNU's copy is
        # `group::r-- group:<grp>:rwx mask::rwx`, kriya's is `group::rwx`.
        # This asserts kriya's OWN answer; the day an ACL path lands it flips to a
        # GNU comparison and says so out loud.
        rm -f am_k am_g
        "$BIN" cp --preserve=mode acl.txt am_k
        cp --preserve=mode acl.txt am_g
        # ⚠ `-n`: getfacl prints group NAMES by default and $SECGROUP is a
        # numeric gid, so the grep matched nothing and the case reported the gap
        # backwards on its first run.
        expect_eq "recorded gap: GNU carries the ACL through --preserve=mode" "1" \
                  "$(getfacl -cn am_g 2>/dev/null | grep -c "^group:$SECGROUP:")"
        expect_eq "...and kriya does not"                                    "0" \
                  "$(getfacl -cn am_k 2>/dev/null | grep -c "^group:$SECGROUP:")"
        expect_eq "...while st_mode still matches, which is what hides it"   \
                  "$(stat -c %a am_g)" "$(stat -c %a am_k)"
    else
        skip "setfacl failed on this filesystem — the system.* exclusion is unverified"
    fi
else
    skip "no setfacl, no xattrs or no secondary group — the system.* exclusion is unverified"
fi

# ⛔ A DESTINATION FILESYSTEM WITH NO XATTR SUPPORT MADE `mv` LEAVE THE FILE IN
# BOTH PLACES. The restore failed, `_mv_cross_fs` returned before the unlink, and
# a move did not move. GNU says nothing there and removes the source; only an
# explicit `--preserve=xattr` reports.
if [ "$HAVE_USERNS" = yes ] && [ "$HAVE_XATTR" = yes ]; then
    ramout=$(unshare -Urm sh -c '
        cd "$1"
        rm -rf ram; mkdir ram
        mount -t ramfs r ram 2>/dev/null || exit 7
        echo cpp > c.txt
        python3 -c "import os; os.setxattr(\"c.txt\", b\"user.k\", b\"V\")"
        krc=0; "$2" cp --preserve=xattr c.txt ram/k 2>kerr || krc=$?
        grc=0; cp --preserve=xattr c.txt ram/g 2>/dev/null || grc=$?
        echo mvv > m.txt
        python3 -c "import os; os.setxattr(\"m.txt\", b\"user.k\", b\"V\")"
        mrc=0; "$2" mv m.txt ram/m 2>merr || mrc=$?
        printf "%s|%s|%s|%s|%s|%s\n" "$krc" "$grc" "$mrc"             "$([ -e m.txt ] && echo left || echo moved)"             "$([ -e ram/m ] && echo yes || echo no)"             "$([ -s kerr ] && echo reported || echo silent)"
    ' _ "$WORK" "$BIN" 2>/dev/null) || ramout=""
    if [ -n "$ramout" ]; then
        k_rc=$(echo "$ramout" | cut -d'|' -f1)
        g_rc=$(echo "$ramout" | cut -d'|' -f2)
        m_rc=$(echo "$ramout" | cut -d'|' -f3)
        m_src=$(echo "$ramout" | cut -d'|' -f4)
        m_dst=$(echo "$ramout" | cut -d'|' -f5)
        k_msg=$(echo "$ramout" | cut -d'|' -f6)
        expect_eq "cp --preserve=xattr onto no-xattr: exit matches GNU" "$g_rc"     "$k_rc"
        expect_eq "...and it is reported, not swallowed"                "reported"  "$k_msg"
        expect_eq "mv onto the same destination still MOVES"            "moved"     "$m_src"
        expect_eq "...and arrives"                                      "yes"       "$m_dst"
        expect_eq "...and exits 0, as GNU does"                         "0"         "$m_rc"
    else
        skip "could not mount a ramfs in a namespace — the no-xattr destination is unverified"
    fi
else
    skip "no user namespace or no xattrs — the no-xattr destination is unverified"
fi

# ⛔ A FAILED OWNERSHIP PRESERVATION IS REPORTED WHEN WE HAD THE PRIVILEGE TO
# SUCCEED, and was not — so a root-run backup got exit 0 on a copy whose owner it
# had silently changed. ⚠ GNU draws the line at `geteuid() == 0`, not at whether
# the call could have worked.
# ⭐ Reachable unprivileged: inside `unshare -Ur` the caller is uid 0 while a
# root-owned file outside appears as the UNMAPPED 65534, so the chown fails
# EINVAL with full CAP_CHOWN in hand.
if [ "$HAVE_USERNS" = yes ] && [ -r /etc/hostname ]; then
    privout=$(unshare -Ur sh -c '
        cd "$1"
        rm -rf priv; mkdir priv; cd priv
        krc=0; "$2" cp -p /etc/hostname k 2>kerr || krc=$?
        grc=0; cp        -p /etc/hostname g 2>gerr || grc=$?
        printf "%s|%s|%s|%s
" "$krc" "$grc"             "$(grep -c "failed to preserve ownership" kerr)"             "$(grep -c "failed to preserve ownership" gerr)"
    ' _ "$WORK" "$BIN" 2>/dev/null) || privout=""
    if [ -n "$privout" ]; then
        expect_eq "privileged ownership failure: exit matches GNU" \
                  "$(echo "$privout" | cut -d'|' -f2)" "$(echo "$privout" | cut -d'|' -f1)"
        expect_eq "...and it exits 1"      "1" "$(echo "$privout" | cut -d'|' -f1)"
        expect_eq "...and says so, as GNU does" \
                  "$(echo "$privout" | cut -d'|' -f4)" "$(echo "$privout" | cut -d'|' -f3)"
        expect_eq "...and the line is actually there" "1" "$(echo "$privout" | cut -d'|' -f3)"
    else
        skip "the user namespace could not be set up — the privileged report is unverified"
    fi
else
    skip "no user namespace — the privileged ownership report is unverified"
fi

# ⛔ A CROSS-FILESYSTEM `mv` MERGED INTO A NON-EMPTY DESTINATION DIRECTORY,
# overwrote same-named files, exited 0 and removed the source — while the
# SAME-filesystem `mv` of the same operands refused. `mv` disagreed with itself
# depending on which device the operands were on, and the disagreement destroyed
# data. ⚠ An EMPTY destination directory is still replaced, which is what
# `rename()` allows on one filesystem and what GNU does across two.
if [ -n "$OTHERFS" ]; then
    mgdir=$(mktemp -d "$OTHERFS/kriya-merge-XXXXXX" 2>/dev/null) || mgdir=""
    if [ -n "$mgdir" ]; then
        for impl in kriya gnu; do
            rm -rf mtree "$mgdir/mtree"
            mkdir -p mtree "$mgdir/mtree"
            echo FROM-SOURCE > mtree/shared.txt
            echo PRE-EXISTING > "$mgdir/mtree/shared.txt"
            rc=0
            if [ "$impl" = kriya ]; then "$BIN" mv mtree "$mgdir/" 2>/dev/null || rc=$?
            else mv mtree "$mgdir/" 2>/dev/null || rc=$?; fi
            eval "mg_$impl=\"\$rc \$(cat "$mgdir/mtree/shared.txt") \$([ -e mtree ] && echo intact || echo GONE)\""
        done
        expect_eq "a non-empty destination directory is refused, as GNU does" "$mg_gnu" "$mg_kriya"
        expect_eq "...and the pre-existing file survives"  "1 PRE-EXISTING intact" "$mg_kriya"
        # ...and the same operands on ONE filesystem already refused, which is
        # the inconsistency that made this a bug rather than a divergence.
        rm -rf sfa sfb; mkdir -p sfa/t sfb/t
        echo S > sfa/t/f; echo D > sfb/t/f
        expect_exit "the same-filesystem form refuses too" 1 "$BIN" mv sfa/t sfb/
        expect_eq "...leaving its file alone"              "D" "$(cat sfb/t/f)"
        # An EMPTY destination is still replaced.
        for impl in kriya gnu; do
            rm -rf etree "$mgdir/etree"
            mkdir -p etree "$mgdir/etree"
            echo NEW > etree/f
            if [ "$impl" = kriya ]; then "$BIN" mv etree "$mgdir/"; else mv etree "$mgdir/"; fi
            eval "em_$impl=\"\$(cat "$mgdir/etree/f") \$([ -e etree ] && echo LEFT || echo moved)\""
        done
        expect_eq "an EMPTY destination directory is still replaced" "$em_gnu" "$em_kriya"
        rm -rf "$mgdir"
    else
        skip "could not create a directory on a second filesystem — the merge guard is unverified"
    fi
else
    skip "only one filesystem available — the cross-filesystem merge guard is unverified"
fi

# ⛔ THE REASON WAS EMPTY on exactly the two failures worth reporting: ENODATA
# (61) and EOPNOTSUPP (95) are outside `errmsg.cyr`'s 1..40 block, and the call
# site had no fallback. Both are named now.
expect_eq "the xattr diagnostic never ends in a bare colon" "0" \
          "$("$BIN" cp --preserve=nosuch own.txt zz2 2>&1 | grep -c ": $")"

# --- the introspection interface knows about the new attributes ------
expect_eq "cp --help names ownership" "1" \
          "$("$BIN" cp --help 2>&1 | grep -c -- 'ownership')"
expect_eq "the refusal message lists all five" "1" \
          "$("$BIN" cp --preserve=nosuch own.txt zz 2>&1 | grep -c 'mode, ownership, timestamps, links, xattr')"

printf "%d passed, %d failed, %d skipped (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
