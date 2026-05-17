#!/bin/sh
# smoke-which.sh — behavioural test for `kriya which`.
#
# Builds a controlled $PATH with two bin directories so `-a` /
# shadowing is deterministic. Covers: basic search, multi-operand,
# missing-binary exit code, -a all-matches order, -s silent, -z NUL,
# slash-literal mode (PATH not consulted), non-executable rejection,
# empty $PATH.

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
WORK_REAL=$(readlink -f "$WORK")

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

# --- fixture: two bin dirs with overlapping + unique entries ---
mkdir -p bin1 bin2 not_exec_dir
# `prog_a` is in both — bin1 first wins.
cat > bin1/prog_a <<'EOF'
#!/bin/sh
echo a-from-bin1
EOF
cat > bin2/prog_a <<'EOF'
#!/bin/sh
echo a-from-bin2
EOF
# `prog_only_in_bin2` exists in bin2 only.
cat > bin2/prog_only_in_bin2 <<'EOF'
#!/bin/sh
echo only-bin2
EOF
chmod 0755 bin1/prog_a bin2/prog_a bin2/prog_only_in_bin2

# Non-executable file (in bin1) — must NOT be reported as a match.
echo "not a program" > bin1/not_exec
chmod 0644 bin1/not_exec

# Directory inside bin1 — must NOT match either.
mkdir -p bin1/i_am_a_dir

TEST_PATH="$WORK_REAL/bin1:$WORK_REAL/bin2"

# --- basic single match (first one wins) ---
out=$(PATH="$TEST_PATH" "$BIN" which prog_a)
expect_eq "first match wins"      "$WORK_REAL/bin1/prog_a" "$out"
expect_exit "found returns 0"     0 env PATH="$TEST_PATH" "$BIN" which prog_a

# --- only-in-second-dir ---
out=$(PATH="$TEST_PATH" "$BIN" which prog_only_in_bin2)
expect_eq "second dir match"      "$WORK_REAL/bin2/prog_only_in_bin2" "$out"

# --- -a shows both matches in order ---
out=$(PATH="$TEST_PATH" "$BIN" which -a prog_a)
expected="$WORK_REAL/bin1/prog_a
$WORK_REAL/bin2/prog_a"
expect_eq "-a both matches"       "$expected" "$out"

# --- -a with single match: still 1 line, exit 0 ---
out=$(PATH="$TEST_PATH" "$BIN" which -a prog_only_in_bin2)
expect_eq "-a single match"       "$WORK_REAL/bin2/prog_only_in_bin2" "$out"

# --- non-executable file is skipped ---
expect_exit "non-exec skipped"    1 env PATH="$TEST_PATH" "$BIN" which not_exec

# --- directory entry is skipped ---
expect_exit "dir skipped"         1 env PATH="$TEST_PATH" "$BIN" which i_am_a_dir

# --- missing program ---
expect_exit "missing"             1 env PATH="$TEST_PATH" "$BIN" which definitely_no_such_prog
out=$(PATH="$TEST_PATH" "$BIN" which missing_prog 2>&1 || true)
expect_eq "missing no output"     "" "$out"

# --- multi-operand: exit 1 if any missing, others still printed ---
rc=0
out=$(PATH="$TEST_PATH" "$BIN" which prog_a missing_prog prog_only_in_bin2 2>/dev/null) || rc=$?
expect_eq "partial-failure rc"    "1" "$rc"
expected="$WORK_REAL/bin1/prog_a
$WORK_REAL/bin2/prog_only_in_bin2"
expect_eq "partial-failure out"   "$expected" "$out"

# --- -s silent: no stdout/stderr, exit code reflects ---
out=$(PATH="$TEST_PATH" "$BIN" which -s prog_a)
expect_eq "-s no stdout (found)"  "" "$out"
expect_exit "-s found rc=0"       0 env PATH="$TEST_PATH" "$BIN" which -s prog_a
expect_exit "-s missing rc=1"     1 env PATH="$TEST_PATH" "$BIN" which -s missing_prog

# --- -z NUL terminator ---
nul=$(PATH="$TEST_PATH" "$BIN" which -z -a prog_a | tr -dc '\0' | wc -c | tr -d ' ')
expect_eq "-z -a: 2 NULs"         "2" "$nul"
nl=$(PATH="$TEST_PATH" "$BIN" which -z -a prog_a | tr -dc '\n' | wc -c | tr -d ' ')
expect_eq "-z: 0 newlines"        "0" "$nl"

# --- slash-literal mode bypasses $PATH ---
# Absolute path to existing executable.
out=$(PATH="" "$BIN" which "$WORK_REAL/bin1/prog_a")
expect_eq "abs path bypasses PATH"  "$WORK_REAL/bin1/prog_a" "$out"

# Relative path with '/' also bypasses PATH (we're cd'd to $WORK).
out=$(cd "$WORK_REAL" && PATH="" "$BIN" which ./bin1/prog_a)
expect_eq "rel path bypasses PATH"  "./bin1/prog_a" "$out"

# Slash-literal on non-executable file: exit 1.
expect_exit "slash non-exec"      1 env PATH="" "$BIN" which "$WORK_REAL/bin1/not_exec"

# Slash-literal on missing path: exit 1.
expect_exit "slash missing"       1 env PATH="" "$BIN" which "$WORK_REAL/no/such/path"

# --- empty $PATH ---
expect_exit "empty PATH"          1 env PATH="" "$BIN" which prog_a

# --- empty entry in $PATH means cwd ---
# Build a PATH that includes an empty entry (": :prefix:: " → '.' inside).
mkdir -p cwd_bin
cat > cwd_bin/cwd_prog <<'EOF'
#!/bin/sh
echo cwd
EOF
chmod 0755 cwd_bin/cwd_prog
# PATH with leading empty entry — first segment is cwd-equivalent.
out=$(cd "$WORK_REAL/cwd_bin" && PATH=":/nope" "$BIN" which cwd_prog)
expect_eq "empty PATH entry == cwd"  "./cwd_prog" "$out"

# --- no operands ---
expect_exit "no operands"         2 "$BIN" which

# --- summary ---
TOTAL=$((PASS + FAIL))
printf "%d passed, %d failed (%d total)\n" "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
