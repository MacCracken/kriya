#!/bin/sh
# check-oracles.sh — verify the tools the smoke suite compares kriya against are
# actually the GNU ones, before any of it runs.
#
# ⛔ EVERY PARITY SCRIPT RESOLVES ITS ORACLE BY BARE NAME THROUGH $PATH and none
# of them check what they got. That is not hypothetical: on this project's dev
# box `find` resolves to **bfs** in an interactive shell, and `grep`/`cat` are
# aliased to ugrep/bat. Under /bin/sh the real GNU tools win — but only because
# of how PATH happens to be ordered, and a BusyBox or toybox image would silently
# substitute a different implementation for every oracle at once.
#
# A parity suite comparing kriya against the wrong reference does not fail; it
# passes against the wrong answer, which is worse. ⚠ 1.3.2 already lost two
# releases to a subtler form of this — the local GNU's VERSION differing from the
# runner's masked a real `find -exec` bug.
#
# ⚠ This checks IDENTITY, not version. Version differences are legitimate and
# unavoidable; identity substitution is not.

set -e

fail=0
note() { printf '  %-10s %s\n' "$1" "$2"; }

check() {   # check <tool> <expected-substring>
    tool=$1
    want=$2
    path=$(command -v "$tool" 2>/dev/null || true)
    if [ -z "$path" ]; then
        note "$tool" "MISSING — the suite cannot compare against it"
        fail=$((fail + 1))
        return
    fi
    ver=$("$tool" --version 2>/dev/null | head -1 || true)
    case "$ver" in
        *"$want"*) note "$tool" "ok ($path)" ;;
        *)
            note "$tool" "NOT $want: $path reports '${ver:-<no --version>}'"
            fail=$((fail + 1))
            ;;
    esac
}

echo "oracle identity:"
for t in cp mv rm ln mkdir rmdir touch ls stat du df date seq env sort tr cut \
         wc head tail nl uniq tee realpath readlink basename dirname sleep; do
    check "$t" "GNU coreutils"
done

# ⚠ `printf` is a SHELL BUILTIN in dash and bash, so `command -v printf` finds
# the builtin and `printf --version` just prints the string "--version". That is
# why scripts/smoke-printf.sh hardcodes /usr/bin/printf as its oracle — and why
# that path needs checking here rather than being assumed. It is absent on
# distributions that expose only a shell builtin plus a store path (NixOS, Guix),
# where the suite would compare against nothing at all.
if [ -x /usr/bin/printf ]; then
    pv=$(/usr/bin/printf --version 2>/dev/null | head -1 || true)
    case "$pv" in
        *"GNU coreutils"*) note "printf" "ok (/usr/bin/printf)" ;;
        *) note "printf" "NOT GNU coreutils: /usr/bin/printf reports '${pv:-<none>}'"
           fail=$((fail + 1)) ;;
    esac
else
    note "printf" "MISSING /usr/bin/printf — smoke-printf.sh's hardcoded oracle"
    fail=$((fail + 1))
fi
check grep "GNU grep"
check find "GNU findutils"
check xargs "GNU findutils"

# ⚠ Not an oracle, but the suite depends on it: GNU `wc -m` counts CHARACTERS
# only in a multibyte locale, and glibc's setlocale fails SILENTLY when the named
# locale is absent — degrading the oracle to a byte count with no diagnostic.
if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then
    note "C.UTF-8" "present (wc -m oracle is character-accurate)"
else
    note "C.UTF-8" "ABSENT — GNU wc -m will silently count BYTES, not characters"
    fail=$((fail + 1))
fi

if [ "$fail" -gt 0 ]; then
    printf '\ncheck-oracles: %s problem(s). The smoke suite would compare kriya against\n' "$fail" >&2
    printf 'something other than the reference it claims, which passes for the wrong reason.\n' >&2
    exit 1
fi
echo "check-oracles: OK"
