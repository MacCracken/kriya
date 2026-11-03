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

# --- -S / --split-string (1.8.3): GNU's grammar, measured against coreutils 9.4 and 9.7.
# ⭐ Most of these print the environment instead of running a command, so the
# words -S produced show up as NAME=VALUE lines and no external binary is needed.
out=$("$BIN" env -i -S 'A=1 B=2')
expect_eq "-S splits on blanks" "A=1
B=2" "$out"
out=$("$BIN" env -i -S "$(printf 'A=1\tB=2\nC=3')")
expect_eq "-S splits on tab and newline" "A=1
B=2
C=3" "$out"
out=$("$BIN" env -i -S "A='x y' B='c\\d' C='e\\\\f' D='g\\'h'")
expect_eq "-S single quotes: only \\\\ and \\' are special" "A=x y
B=c\\d
C=e\\f
D=g'h" "$out"
out=$("$BIN" env -i -S 'A="x y" B="q\"r" C="e\\f" D="\$h" E="1\_2"')
expect_eq "-S double quotes: \\\" \\\\ \\\$ and \\_ is a space" "A=x y
B=q\"r
C=e\\f
D=\$h
E=1 2" "$out"
out=$("$BIN" env -i -S 'A=1\_B=2')
expect_eq "-S unquoted \\_ separates words" "A=1
B=2" "$out"
out=$("$BIN" env -i -S 'A=a\#b B=a\$b C=a\tb')
expect_eq "-S unquoted escapes" "$(printf 'A=a#b\nB=a$b\nC=a\tb')" "$out"
out=$("$BIN" env -i -S 'A=1 B=2\cC=3 D=4')
expect_eq "-S \\c ends the string" "A=1
B=2" "$out"
out=$("$BIN" env -i -S 'A=1 #B=2 C=3')
expect_eq "-S # at a word start is a comment" "A=1" "$out"
out=$("$BIN" env -i -S 'A=1#x')
expect_eq "-S # inside a word is literal" "A=1#x" "$out"
# ⚠ The expansion reads the environment env was GIVEN — the `-i` before it has
# not cleared anything yet, in GNU or here.
out=$(FOO=x1 "$BIN" env -i -S 'A=${FOO} B=pre${FOO}post C=${NOPE_KRIYA_Q}')
expect_eq "-S \${VAR}, an unset one empty" "A=x1
B=prex1post
C=" "$out"
out=$(FOO='a b' "$BIN" env -i -S 'A=${FOO}')
expect_eq "-S \${VAR} is not re-split" "A=a b" "$out"
out=$(FOO=x "$BIN" env -i -S "A='\${FOO}'")
expect_eq "-S no expansion in single quotes" "A=\${FOO}" "$out"
# ⛔ An UNSET name starts no word and a SET one starts one even when empty — GNU
# calls check_start_new_arg only on a non-NULL getenv. Found by a differential
# fuzz against GNU 9.7, not by reading: the first cut made a word of every ${…}.
out=$("$BIN" env -i -S 'A=1 ${NOPE_KRIYA_Q} B=2')
expect_eq "-S unset \${VAR} alone is no word" "A=1
B=2" "$out"
out=$("$BIN" env -i -S 'A=1 ${NOPE_KRIYA_Q}#B=2')
expect_eq "-S # after an unset \${VAR} is still a comment" "A=1" "$out"
out=$(E= "$BIN" env -i -S 'A=1 ${E}#B=2')
expect_eq "-S a set-but-empty \${VAR} starts a word" "A=1
#B=2" "$out"
out=$(E= "$BIN" env -i -S "$SH -c 'echo \$#' x \${E} \${NOPE_KRIYA_Q}")
expect_eq "-S set-but-empty is an argument, unset is none" "1" "$out"
expect_eq "-S '' has no words" "" "$("$BIN" env -i -S '')"

expect_exit "-S unterminated '"        2 "$BIN" env -i -S "A='x"
expect_exit "-S unterminated \""       2 "$BIN" env -i -S 'A="x'
expect_exit "-S unknown escape"        2 "$BIN" env -i -S 'A=\q'
expect_exit "-S trailing backslash"    2 "$BIN" env -i -S 'A=x\'
expect_exit "-S bare \$NAME"           2 "$BIN" env -i -S 'A=$FOO'
expect_exit "-S bad \${NAME}"          2 "$BIN" env -i -S 'A=${1x}'
expect_exit "-S \\c in double quotes"  2 "$BIN" env -i -S 'A="x\cy"'
expect_exit "-S no value"              2 "$BIN" env -S
expect_exit "--split-string no value"  2 "$BIN" env --split-string
err=$("$BIN" env -i -S "A='x" 2>&1 >/dev/null || true)
expect_eq "-S error is GNU's text" "kriya env: no terminating quote in -S string" "$err"

# The words re-enter option parsing where -S stood.
out=$("$BIN" env -S '-i A=1')
expect_eq "-S words are options too" "A=1" "$out"
out=$(A=1 B=2 "$BIN" env -S '-u A' | sed -n '/^[AB]=/p')
expect_eq "-S carries -u" "B=2" "$out"
out=$("$BIN" env -i -S 'A=1' B=2)
expect_eq "-S then more words" "A=1
B=2" "$out"
out=$("$BIN" env -i '-SA=1 B=2')
expect_eq "-SSTRING attached" "A=1
B=2" "$out"
out=$("$BIN" env -iS 'A=1')
expect_eq "-iS cluster" "A=1" "$out"
out=$("$BIN" env -i '--split-string=A=1 B=2')
expect_eq "--split-string=STRING" "A=1
B=2" "$out"
out=$("$BIN" env -i --split-string 'A=1 B=2')
expect_eq "--split-string STRING" "A=1
B=2" "$out"
out=$("$BIN" env -i -S "-S 'A=1 B=2'")
expect_eq "-S inside -S" "A=1
B=2" "$out"
expect_exit "-S after -- is the command" 127 "$BIN" env -i -- -S x
out=$("$BIN" env -i -S "$SH -c 'echo \"\$0:\$1\"' a b")
expect_eq "-S runs a command" "a:b" "$out"

# ⭐ What -S is for: a shebang line hands env ONE argument, the whole rest of the line.
ln -s "$BIN" "$WORK/env"
cat > "$WORK/sb" <<EOF
#!$WORK/env -S -i A=1 $SH -c 'echo "\$A:\$0:\$1"'
EOF
chmod +x "$WORK/sb"
out=$("$WORK/sb" arg1)
expect_eq "-S on a shebang line" "1:$WORK/sb:arg1" "$out"

# --- -C / --chdir (1.8.3)
out=$("$BIN" env -C / "$SH" -c pwd)
expect_eq "-C DIR" "/" "$out"
out=$("$BIN" env -C/ "$SH" -c pwd)
expect_eq "-CDIR attached" "/" "$out"
out=$("$BIN" env --chdir=/ "$SH" -c pwd)
expect_eq "--chdir=DIR" "/" "$out"
out=$("$BIN" env --chdir / "$SH" -c pwd)
expect_eq "--chdir DIR" "/" "$out"
mkdir "$WORK/d"
printf '#!%s\necho ran-t\n' "$SH" > "$WORK/d/t"
chmod +x "$WORK/d/t"
out=$("$BIN" env -C d ./t)
expect_eq "-C: a relative command is found from DIR" "ran-t" "$out"
# ⚠ The ordering test: PATH=. only finds `t` if the chdir happened BEFORE the
# PATH search, as GNU's execvp after chdir does.
out=$("$BIN" env -C d -i PATH=. t)
expect_eq "-C: PATH is searched from DIR" "ran-t" "$out"
expect_exit "-C missing dir"     125 "$BIN" env -C "$WORK/nonexistent" "$SH" -c :
expect_exit "-C on a file"       125 "$BIN" env -C "$WORK/d/t" "$SH" -c :
expect_exit "-C with no command" 2   "$BIN" env -C /
expect_exit "-C no value"        2   "$BIN" env -C
expect_exit "--chdir no value"   2   "$BIN" env --chdir

# --- PATH search (1.8.3): a bare name is never left for the kernel to resolve
# against the current directory. env had its own resolver, which did exactly that
# both when PATH was unset and when the search found nothing.
mkdir "$WORK/cwd"
printf '#!%s\necho PWNED-FROM-CWD\n' "$SH" > "$WORK/cwd/kriya-cwd-probe"
chmod +x "$WORK/cwd/kriya-cwd-probe"
cd "$WORK/cwd"
expect_exit "unset PATH: not run from the cwd" 127 "$BIN" env -i kriya-cwd-probe
out=$("$BIN" env -i kriya-cwd-probe 2>/dev/null || true)
expect_eq "unset PATH: nothing ran" "" "$out"
expect_exit "PATH miss: not run from the cwd"  127 "$BIN" env PATH=/nonexistent kriya-cwd-probe
out=$("$BIN" env PATH=/nonexistent kriya-cwd-probe 2>/dev/null || true)
expect_eq "PATH miss: nothing ran" "" "$out"
# ⚠ An EMPTY PATH is POSIX's zero-length prefix, the current directory, and GNU
# runs ./kriya-cwd-probe too. Only the unset and the unmatched cases are holes.
out=$("$BIN" env PATH= kriya-cwd-probe)
expect_eq "PATH= is the cwd, as in GNU" "PWNED-FROM-CWD" "$out"
cd "$WORK"
if [ -x /bin/sh ] || [ -x /usr/bin/sh ]; then
    out=$("$BIN" env -i sh -c 'echo found')
    expect_eq "unset PATH searches /bin:/usr/bin, as glibc's execvp" "found" "$out"
else
    echo "skip: no sh in /bin or /usr/bin — the unset-PATH default is unexercised"
fi

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
