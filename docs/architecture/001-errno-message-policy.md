# 001 — errno → message policy

Every kriya utility that surfaces a kernel error to the user does so via the same shape. This note pins the shape so output stays predictable for both human readers and agents pattern-matching stderr.

## Invariants

1. **One source of truth for the table.** Errno → message mapping lives in `src/lib/errmsg.cyr` (`errmsg_for(errno) -> cstring`, static, no alloc). No utility opens its own table.

2. **Coverage is errnos 1..40** — the POSIX core. The Linux ABI fixes these numbers across all syscalls; a libc-free caller can compare numerically without translation. Higher errnos (network, capability) land when a utility actually needs them. Unmapped errnos do NOT fall back to a wildcard message: they print as `errno N` so the user can grep them and we can grow the table later without losing fidelity.

3. **The framing is fixed.** Every kriya error line, written to **stderr**, follows:

   ```
   kriya <util>: <message>: <operand>
   ```

   With `<operand>` optional (omitted with the preceding `: ` when no path/argument context is relevant). Examples:

   ```
   kriya cp: no such file or directory: /no/such/file
   kriya rm: permission denied: /etc/passwd
   kriya sleep: invalid argument
   kriya wc: errno 87: /weird/fs/path
   ```

   The leading `kriya ` is literal — not the utility's argv[0] — so symlink-form invocation (`./cp`) and dispatcher-form invocation (`kriya cp`) produce identical output. Agents pattern-match on this prefix.

4. **Trailing newline is mandatory.** One write per error line; no buffering, no batching. Utility code may write multiple error lines per invocation when iterating (`cp` over many sources, `rm -r` walking a tree); each ends with `\n`.

5. **No localisation.** Messages are ASCII, lowercase except for proper nouns, no terminating period. This matches GNU coreutils style and keeps grep patterns short.

6. **`<message>` is exactly what `errmsg_for(errno)` returns.** Utilities do not paraphrase. If a utility wants extra context (e.g. "while reading from"), it goes in the operand slot, not the message slot.

## Where this binds

- `src/lib/errmsg.cyr` — the table, plus `errmsg_is_known(errno)` for the "named vs `errno N`" pick.
- Per-utility code emits the prefix and operand directly via `write(2)` (`syscall(1, 2, ...)`). No `fmt` involvement — fmt is for stdout payloads, not error framing.
- M2 destructive utilities (`cp`, `mv`, `rm`) are the first heavy consumers. Errors from `unlinkat`, `renameat`, `openat` route through this policy.

## Out of scope

- Translating signal numbers to messages — that's `signal_for(signo)` and lives in a sibling note when M2 lands. Different surface, different table.
- Multi-line error explanations (e.g. "this happened because…"). kriya errors are single-line. Long explanations belong in `--help` output or man pages.
- Coloured stderr. Errors go to stderr unstyled. ANSI is reserved for stdout payloads on a tty (M3 `ls`).
