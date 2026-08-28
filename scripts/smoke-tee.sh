#!/bin/sh
# smoke-tee.sh — behavioural test for `kriya tee`.
#
# Covers single-file copy, multi-file fan-out, -a append vs default
# truncate, no-operand pass-through, large-input fidelity (>64KiB
# exercises the read/write loop), and resilient per-file failure
# semantics (one bad output doesn't break the others).

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

expect_exit() {
    name=$1
    expected=$2
    shift 2
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    expect_eq "$name" "$expected" "$rc"
}

expect_file_match() {
    if cmp -s "$2" "$3"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL %s: '%s' and '%s' differ\n" "$1" "$2" "$3" >&2
    fi
}

# --- basic single-file ---
stdout=$(echo "hello" | "$BIN" tee out1)
expect_eq "stdin echoed to stdout"  "hello" "$stdout"
expect_eq "file contains hello"     "hello" "$(cat out1)"

# --- multi-file fan-out ---
echo "fan" | "$BIN" tee a b c >/dev/null
expect_eq "a got content"  "fan" "$(cat a)"
expect_eq "b got content"  "fan" "$(cat b)"
expect_eq "c got content"  "fan" "$(cat c)"

# --- default truncates ---
echo "OLD" > truncme
echo "NEW" | "$BIN" tee truncme >/dev/null
expect_eq "default truncates"  "NEW" "$(cat truncme)"

# --- -a appends ---
echo "first" > app
echo "second" | "$BIN" tee -a app >/dev/null
expected="first
second"
expect_eq "-a appends"  "$expected" "$(cat app)"

# --- no operands: stdout pass-through ---
stdout=$(echo "pass" | "$BIN" tee)
expect_eq "no operands pass-through"  "pass" "$stdout"
# Exit 0 even with no operands.
expect_exit "no operands rc=0"  0 sh -c "echo x | '$BIN' tee"

# --- large input (>64KiB buffer; exercises read/write loop) ---
dd if=/dev/urandom of=big.in bs=1024 count=200 status=none
"$BIN" tee big.out < big.in > big.stdout
expect_file_match "200KB stdout matches"  big.in big.stdout
expect_file_match "200KB file matches"    big.in big.out

# Even larger — 5MiB — to confirm many-iteration loop.
dd if=/dev/urandom of=huge.in bs=1024 count=5000 status=none
"$BIN" tee huge.out < huge.in > huge.stdout
expect_file_match "5MiB stdout matches"   huge.in huge.stdout
expect_file_match "5MiB file matches"     huge.in huge.out

# --- resilient per-file failure: one bad doesn't break the others ---
# ⛔ ROOT BYPASSES DAC. Mode 0444 does not deny uid 0 — CAP_DAC_OVERRIDE means
# open(O_WRONLY|O_TRUNC) succeeds, tee writes both files, and every assertion
# below inverts. ⚠ Latent on GitHub's non-root runners; a root container would
# report kriya broken when it is not.
touch readonly
chmod 0444 readonly
if [ "$(id -u)" = "0" ]; then
    echo "skip: running as root — mode 0444 cannot deny a write"
else
    rc=0
    echo "blocked" | "$BIN" tee readonly survivor >/dev/null 2>&1 || rc=$?
    expect_eq "partial fail rc"         "1" "$rc"
    expect_eq "survivor got data"       "blocked" "$(cat survivor)"
    expect_eq "readonly unchanged"      "" "$(cat readonly)"
fi

# --- writing to a directory operand fails cleanly ---
mkdir somedir
rc=0
echo "no" | "$BIN" tee somedir >/dev/null 2>&1 || rc=$?
expect_eq "dir target fails"        "1" "$rc"

# --- binary fidelity (NULs preserved) ---
# ⚠ `\xHH` is a bash / GNU-coreutils extension; the POSIX `printf` FORMAT
# defines only octal `\ddd`. Under dash (which /bin/sh is on many CI images)
# `\x00` is not the NUL this test is about. `\000` means the same byte
# everywhere, and this test is precisely about NUL fidelity.
printf 'one\000two\000three' > bin.in
"$BIN" tee bin.out < bin.in >/dev/null
expect_file_match "binary fidelity"  bin.in bin.out

# --- -a creates a new file if missing (open with O_CREAT|O_APPEND) ---
expect_exit "-a creates new"        0 sh -c "echo x | '$BIN' tee -a brand_new >/dev/null"
expect_eq "-a new file content"     "x" "$(cat brand_new)"

# --- 1.6.4: -i, -p and --output-error ------------------------------------
# ⛔ THE INFRASTRUCTURE THESE WAITED ON ALREADY EXISTED. tee.cyr's header said
# they "need the signal-handler infrastructure flagged in architecture 002 — not
# yet installed"; the Cyrius stdlib has had `signal_ignore`/`signal_default` with
# SIGINT and SIGPIPE enumerated all along. Second deferral to outlive its blocker.

# ⭐ SIGINT NEEDS A FRESH DISPOSITION TO TEST AT ALL. A background job started
# from a non-interactive shell inherits SIG_IGN, so every variant "survives" and
# the assertion holds whatever the code does. The first version of this probe did
# exactly that and reported gnu, gnu -i and kriya as identical.
sigint_survives() {   # sigint_survives <cmd...> -> prints yes/no
    python3 - "$@" <<'PYEOF' 2>/dev/null || echo "unavailable"
import os, signal, subprocess, sys, tempfile, time
d = tempfile.mkdtemp(); r, w = os.pipe()
def pre():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    os.setpgrp()
p = subprocess.Popen(sys.argv[1:] + [os.path.join(d, "out")], stdin=r,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=pre)
os.close(r); time.sleep(0.25); os.kill(p.pid, signal.SIGINT); time.sleep(0.25)
alive = p.poll() is None
try: os.write(w, b"hi\n")
except OSError: pass
os.close(w)
try: p.wait(timeout=5)
except subprocess.TimeoutExpired: p.kill()
print("yes" if alive else "no")
PYEOF
}
SI=$(sigint_survives "$BIN" tee)
if [ "$SI" = "unavailable" ]; then
    echo "skip: no python3 — the SIGINT disposition cases are unverified"
else
    expect_eq "plain tee DIES on SIGINT, as GNU does"  "no"  "$SI"
    expect_eq "-i survives it"                         "yes" "$(sigint_survives "$BIN" tee -i)"
    expect_eq "--ignore-interrupts survives it"        "yes" "$(sigint_survives "$BIN" tee --ignore-interrupts)"
    expect_eq "...and GNU agrees on both"              "no yes" \
              "$(printf '%s %s' "$(sigint_survives tee)" "$(sigint_survives tee -i)")"
fi

# --- --output-error: two independent bits, not five modes ------------------
# ⚠ A NON-PIPE failure exercises the warn/exit bit; only a PIPE failure
# exercises the nopipe bit. Asserting one without the other tests half a matrix.
mkdir -p oe
big_in() { head -c 200000 /dev/zero | tr '\0' x; }

# /dev/full is ENOSPC on every write — the non-pipe half.
oe_full() {   # oe_full <flag...> -> "<rc>:<lines>:<got-good>"
    rm -f oe/good
    _l=$(big_in | "$BIN" tee "$@" /dev/full oe/good 2>&1 >/dev/null | wc -l)
    _r=0; big_in | "$BIN" tee "$@" /dev/full oe/good >/dev/null 2>&1 || _r=$?
    _g=no; [ -s oe/good ] && _g=yes
    printf '%s:%s:%s' "$_r" "$_l" "$_g"
}
expect_eq "default: warn, keep the other outputs, exit 1" "1:1:yes" "$(oe_full)"
expect_eq "warn: same"            "1:1:yes" "$(oe_full --output-error=warn)"
expect_eq "warn-nopipe: same"     "1:1:yes" "$(oe_full --output-error=warn-nopipe)"
expect_eq "-p: same"              "1:1:yes" "$(oe_full -p)"
# ⛔ `exit` STOPS MID-CHUNK — the good file gets nothing, because /dev/full comes
# first in argv order. Writing to the rest of the outputs and only then stopping
# is the nearly-correct version that this asserts against.
expect_eq "exit: stop at once"       "1:1:no" "$(oe_full --output-error=exit)"
expect_eq "exit-nopipe: also stops"  "1:1:no" "$(oe_full --output-error=exit-nopipe)"

# ⛔ ONE DIAGNOSTIC, NOT ONE PER 64 KiB. The dead fd was set to -1 and then
# handed straight back to `write(-1, …)` on the next chunk: 200 KiB of input
# printed the "no space left" line FOUR times where GNU prints it once.
expect_eq "a dead output is not written to again" "1" \
          "$(big_in | "$BIN" tee /dev/full oe/g2 2>&1 >/dev/null | wc -l)"
expect_eq "...and GNU prints one too"             "1" \
          "$(big_in | tee /dev/full oe/g3 2>&1 >/dev/null | wc -l)"

# ⛔ THE OPERAND NAME TRAVELS WITH THE FD. It was recovered by index into the
# positional list, which shifts the moment one open fails — so this reported
# "nodir/x/y: no space left on device", naming the operand that failed to OPEN
# for an error belonging to /dev/full. The reader chases the wrong disk.
expect_eq "each error names its own output" "1" \
          "$(big_in | "$BIN" tee oe/nodir/x/y /dev/full oe/g4 2>&1 >/dev/null \
             | grep -c '/dev/full: no space left on device')"
expect_eq "...and the open failure names its own" "1" \
          "$(big_in | "$BIN" tee oe/nodir/x/y /dev/full oe/g5 2>&1 >/dev/null \
             | grep -c 'oe/nodir/x/y: no such file or directory')"

# ⛔ AND THE PIPE HALF, WHICH IS THE ONLY HALF THAT EXERCISES THE `nopipe` BIT.
# The block above uses /dev/full for every mode and a comment claimed it covered
# the matrix; mutation-testing proved otherwise — turning off the SIGPIPE ignore,
# the EPIPE discount AND the write-net forgive each left the suite fully green.
# ⚠ A closed-reader pipe is not constructible in portable `sh`, which is exactly
# why the coverage was missing.
oe_pipe() {   # oe_pipe <flag...> -> "<rc>:<lines>:<got-good>"
    python3 - "$BIN" "$@" <<'PYEOF' 2>/dev/null || echo "unavailable"
import os, signal, subprocess, sys, tempfile
d = tempfile.mkdtemp(); good = os.path.join(d, "good")
r, w = os.pipe()
def pre():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
p = subprocess.Popen([sys.argv[1], "tee"] + sys.argv[2:] + [good], stdin=subprocess.PIPE,
                     stdout=w, stderr=subprocess.PIPE, preexec_fn=pre)
os.close(w); os.close(r)
try: _, err = p.communicate(input=b"payload\n" * 200, timeout=10)
except subprocess.TimeoutExpired: p.kill(); err = b"hung"
try: g = "yes" if os.path.getsize(good) > 0 else "no"
except OSError: g = "no"
print("%s:%s:%s" % (p.returncode, len(err.decode(errors="replace").strip().splitlines()), g))
PYEOF
}
if [ "$(oe_pipe)" = "unavailable" ]; then
    echo "skip: no python3 — the closed-pipe half of the matrix is unverified"
else
    # ⛔ NO FLAG MEANS THE KERNEL KILLS IT. -13 is death by SIGPIPE, and it is
    # what makes every other row observable only when the disposition changes.
    expect_eq "default: killed by SIGPIPE"        "-13:0:no"  "$(oe_pipe)"
    # ⚠ The `-nopipe` rows are SILENT and exit 0: a broken pipe is not an error.
    expect_eq "-p: silent, keeps going, exit 0"   "0:0:yes"   "$(oe_pipe -p)"
    expect_eq "warn-nopipe: same as -p"           "0:0:yes"   "$(oe_pipe --output-error=warn-nopipe)"
    expect_eq "exit-nopipe: also silent, exit 0"  "0:0:yes"   "$(oe_pipe --output-error=exit-nopipe)"
    # ⚠ Without `-nopipe` a broken pipe IS an error, diagnosed and counted.
    expect_eq "warn: diagnosed, keeps going, exit 1" "1:1:yes" "$(oe_pipe --output-error=warn)"
    expect_eq "exit: diagnosed, stops, exit 1"       "1:1:no"  "$(oe_pipe --output-error=exit)"
    # ⭐ And GNU agrees on all six, which is the point of the table.
    gnu_pipe() { PATH_BIN=tee; python3 - "$@" <<'PYEOF' 2>/dev/null || echo "unavailable"
import os, signal, subprocess, sys, tempfile
d = tempfile.mkdtemp(); good = os.path.join(d, "good")
r, w = os.pipe()
def pre():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL); signal.signal(signal.SIGINT, signal.SIG_DFL)
p = subprocess.Popen(["tee"] + sys.argv[1:] + [good], stdin=subprocess.PIPE, stdout=w,
                     stderr=subprocess.PIPE, preexec_fn=pre)
os.close(w); os.close(r)
try: _, err = p.communicate(input=b"payload\n" * 200, timeout=10)
except subprocess.TimeoutExpired: p.kill(); err = b"hung"
try: g = "yes" if os.path.getsize(good) > 0 else "no"
except OSError: g = "no"
print("%s:%s:%s" % (p.returncode, len(err.decode(errors="replace").strip().splitlines()), g))
PYEOF
    }
    for m in "" "-p" "--output-error=warn" "--output-error=warn-nopipe" "--output-error=exit" "--output-error=exit-nopipe"; do
        # shellcheck disable=SC2086
        expect_eq "GNU parity on the pipe half [$m]" "$(gnu_pipe $m)" "$(oe_pipe $m)"
    done
fi

# --- ADR 0002: --output-error REQUIRES its value --------------------------
# ⚠ GNU accepts a bare `--output-error` and reads it as warn-nopipe. kriya
# refuses: ADR 0002 rule 3 is "a flag is either a boolean or it requires a value,
# never both", and `tee --output-error file` is exactly that ambiguity.
expect_exit "a bare --output-error is a usage error" 2 "$BIN" tee --output-error
expect_exit "an unknown mode is too"                 2 "$BIN" tee --output-error=bogus
expect_eq "...and the message names the modes" "1" \
          "$(printf x | "$BIN" tee --output-error=bogus 2>&1 >/dev/null | grep -c 'warn-nopipe')"

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
