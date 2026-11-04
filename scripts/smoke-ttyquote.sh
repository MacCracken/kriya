#!/bin/sh
# smoke-ttyquote.sh — what `basename`, `dirname`, `readlink`, `realpath`, `du` and `env` print
# is quoted on a terminal, and only there (1.8.8).
#
# GNU 9.12 NEWS: "'basename', 'dirname', 'du', 'readlink', and 'realpath' now quote output in
# shell-escape style when standard output is a terminal", and "'env' ... now quote[s] printed
# environment variables". Through a pipe nothing changes, and `-z` / `-0` output is never
# quoted, so no script sees it: it is `ls`'s terminal rule, rendered by `quote_shell`.
# `QUOTING_STYLE` stays declined (ADR 0017).
#
# Each case runs on a pseudo-terminal and through a pipe. PROBED: an oracle whose `basename`
# quotes on a terminal is 9.12-style and is compared against; on an older one kriya's answer is
# asserted against 9.12's, measured (docs/audit/2026-11-03-gnu-9.12-parity.md § 7a).
# ⚠ Needs python3 for the terminal; without it the script skips, and says so.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/kriya"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not built. Run: cyrius build src/main.cyr build/kriya" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "0 passed, 0 failed, 1 skipped (0 total) — no python3 for a terminal"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
for u in basename dirname readlink realpath du env; do ln -s "$BIN" "$WORK/bin/$u"; done

BIN_DIR="$WORK/bin" WORK="$WORK" python3 -I - > "$WORK/results" <<'PY'
import os, pty, subprocess, sys

K = os.environ['BIN_DIR']
W = os.environ['WORK']
os.chdir(W)
open('a b', 'w').write('xx\n'); open('plain', 'w').write('x\n')
os.symlink('a b', 'l b'); open('nl\nx', 'w').close()

# (args, 9.12's answer on a terminal, 9.12's answer through a pipe). `D` stands for this
# directory, for the two utilities that print absolute paths.
CASES = [
    (['basename', 'x/a b'],                   b"'a b'\n",                  b'a b\n'),
    (['basename', '-a', 'x/a b', 'y/plain'],  b"'a b'\nplain\n",           b'a b\nplain\n'),
    (['basename', '-z', 'x/a b'],             b'a b\x00',                  b'a b\x00'),
    (['basename', 'x/plain'],                 b'plain\n',                  b'plain\n'),
    (['basename', 'x/nl\nx'],                 b"'nl'$'\\n''x'\n",          b'nl\nx\n'),
    (['basename', "x/it's"],                  b'"it\'s"\n',                b"it's\n"),
    (['dirname', 'a b/x'],                    b"'a b'\n",                  b'a b\n'),
    (['dirname', '-z', 'a b/x'],              b'a b\x00',                  b'a b\x00'),
    (['dirname', 'plain/x'],                  b'plain\n',                  b'plain\n'),
    (['realpath', '--relative-to=.', 'a b'],  b"'a b'\n",                  b'a b\n'),
    (['realpath', '-z', '--relative-to=.', 'a b'], b'a b\x00',             b'a b\x00'),
    (['realpath', '-s', '--relative-to=.', 'plain'], b'plain\n',           b'plain\n'),
    (['readlink', 'l b'],                     b"'a b'\n",                  b'a b\n'),
    (['readlink', '-n', 'l b'],               b"'a b'",                    b'a b'),
    (['readlink', '-z', 'l b'],               b'a b\x00',                  b'a b\x00'),
    (['readlink', '-f', '--', 'l b'],         b"'D/a b'\n",                b'D/a b\n'),
    (['du', '-s', 'a b'],                     b"4\t'a b'\n",               b'4\ta b\n'),
    (['du', '-0', '-s', 'a b'],               b'4\ta b\x00',               b'4\ta b\x00'),
    (['du', '-s', 'plain'],                   b'4\tplain\n',               b'4\tplain\n'),
    (['du', '-sc', 'a b'],                    b"4\t'a b'\n4\ttotal\n",     b'4\ta b\n4\ttotal\n'),
    (['env', '-i', 'X=a b', "Y=it's", 'Z=plain', 'W=a\nb'],
        b'X=\'a b\'\nY="it\'s"\nZ=plain\nW=\'a\'$\'\\n\'\'b\'\n', b"X=a b\nY=it's\nZ=plain\nW=a\nb\n"),
    (['env', '-0', '-i', 'X=a b'],            b'X=a b\x00',                b'X=a b\x00'),
    (['env', '-i', 'A B=1', 'N='],            b"'A B'=1\nN=\n",            b'A B=1\nN=\n'),
]

def on_tty(argv):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['LC_ALL'] = 'C'
        os.execv(argv[0], argv)
    out = b''
    while True:
        try:
            c = os.read(fd, 4096)
        except OSError:
            break
        if not c:
            break
        out += c
    os.waitpid(pid, 0)
    return out.replace(b'\r\n', b'\n')

def piped(argv):
    return subprocess.run(argv, capture_output=True, env={'LC_ALL': 'C', 'PATH': '/usr/bin:/bin'}).stdout

def norm(b):
    return b.replace(W.encode(), b'D')

# ⚠ `du`'s block counts depend on the filesystem; a two-byte file is 4 KiB nearly everywhere,
# and a GNU comparison would agree either way. On an older oracle the size field is the one
# thing asserted against 9.12's numbers, so it is taken from kriya's own pipe output.
gnu_quotes = on_tty(['/usr/bin/basename', 'x/a b']) == b"'a b'\n"
for args, want_tty, want_pipe in CASES:
    name = ' '.join(args).replace('\n', '\\n')
    k_tty = norm(on_tty([os.path.join(K, args[0])] + args[1:]))
    k_pipe = norm(piped([os.path.join(K, args[0])] + args[1:]))
    if gnu_quotes:
        want_tty = norm(on_tty(['/usr/bin/' + args[0]] + args[1:]))
        want_pipe = norm(piped(['/usr/bin/' + args[0]] + args[1:]))
    elif args[0] == 'du':
        size = k_pipe.split(b'\t', 1)[0]
        want_tty = want_tty.replace(b'4\t', size + b'\t')
        want_pipe = want_pipe.replace(b'4\t', size + b'\t')
    for where, got, want in (('terminal', k_tty, want_tty), ('pipe', k_pipe, want_pipe)):
        if got == want:
            print('PASS')
        else:
            print('FAIL %s (%s): expected %r, got %r' % (name, where, want, got))
PY

PASS=$(grep -c '^PASS' "$WORK/results" || true)
FAIL=$(grep -c '^FAIL' "$WORK/results" || true)
grep '^FAIL' "$WORK/results" >&2 || true
TOTAL=$((PASS + FAIL))
printf '%d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ] || [ "$TOTAL" -eq 0 ]; then exit 1; fi
exit 0
