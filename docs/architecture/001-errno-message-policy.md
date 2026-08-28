# 001 — errno → message policy

Every kriya utility that surfaces a kernel error to the user does so via the same shape. This note pins the shape so output stays predictable for both human readers and agents pattern-matching stderr.

## Invariants

1. **One source of truth for the table.** Errno → message mapping lives in `src/lib/errmsg.cyr` (`errmsg_for(errno) -> cstring`, static, no alloc). No utility opens its own table.

2. **Coverage is errnos 1..40** — the POSIX core. The Linux ABI fixes these numbers across all syscalls; a libc-free caller can compare numerically without translation. Higher errnos (network, capability) land when a utility actually needs them. Unmapped errnos do NOT fall back to a wildcard message: they print as `errno N` so the user can grep them and we can grow the table later without losing fidelity.

3. **The framing is fixed.** Every kriya error line, written to **stderr**, follows:

   ```
   kriya <util>: <operand>: <message>
   ```

   With `<operand>` optional (omitted with the following `: ` when no path/argument context is relevant). Examples:

   ```
   kriya cp: /no/such/file: no such file or directory
   kriya rm: /etc/passwd: permission denied
   kriya sleep: invalid argument
   kriya wc: /weird/fs/path: errno 87
   ```

   ⚠ **THIS NOTE HAD THE TWO FIELDS THE WRONG WAY ROUND until 1.6.6**, and every one of the four examples was written in the reversed order. The code has always emitted operand-then-message — GNU's shape — across all 38 utilities, so the note was describing something that never shipped. Corrected against the implementation rather than the other way round, because the implementation is what agents and scripts already match on. ⭐ It survived because there was no single implementation to compare it against; see rule 5.

   The leading `kriya ` is literal — not the utility's argv[0] — so symlink-form invocation (`./cp`) and dispatcher-form invocation (`kriya cp`) produce identical output. Agents pattern-match on this prefix.

4. **Trailing newline is mandatory.** One write per error line; no buffering, no batching. Utility code may write multiple error lines per invocation when iterating (`cp` over many sources, `rm -r` walking a tree); each ends with `\n`.

   ⛔ **AND THE OPERAND IS SHELL-QUOTED WHEN IT NEEDS IT, which is what makes rule 4 true rather than aspirational.** Writing the operand raw let a filename containing a newline split one diagnostic across two lines — measured at 1.6.5, `kriya realpath: a` / `b: no such file or directory`. ⚠ It also made `kriya rm: a b: no such file or directory` unreadable: one operand, or two?

   The style is `QUOTE_DIAGNOSTIC` in `src/lib/quote.cyr`, which is GNU's `quotearg_style_colon` and differs from `ls`'s shell-escape in exactly two bytes: `:` is quoted (the message itself is colon-delimited, so `a:b` would be unparseable) and `/` is bare (every path has one; `ls` names never do, which is why `/` was never in the measured set). Measured against GNU across ten shapes — plain, spaces, quotes, tabs, newlines, `=`, `:`, paths and the empty string — all ten match.

5. **One implementation, not one per utility.** `errmsg_report(util, operand, errno)` in `src/lib/report.cyr` is the only place the shape above is written. ⛔ There were **twenty-four byte-identical copies** of it in `src/cmd/`, differing solely in the utility name — so the shape could not be changed without twenty-four edits, and therefore never was. Collapsing them removed 401 lines and is what let the quoting rule land in one place.

6. **No localisation.** Messages are ASCII, lowercase except for proper nouns, no terminating period. This matches GNU coreutils style and keeps grep patterns short.

7. **`<message>` is exactly what `errmsg_for(errno)` returns.** Utilities do not paraphrase. If a utility wants extra context (e.g. "while reading from"), it goes in the operand slot, not the message slot.

## Where this binds

- `src/lib/errmsg.cyr` — the table, plus `errmsg_is_known(errno)` for the "named vs `errno N`" pick.
- Per-utility code emits the prefix and operand directly via `write(2)` (`syscall(1, 2, ...)`). No `fmt` involvement — fmt is for stdout payloads, not error framing.
- M2 destructive utilities (`cp`, `mv`, `rm`) are the first heavy consumers. Errors from `unlinkat`, `renameat`, `openat` route through this policy.

## Out of scope

- Translating signal numbers to messages — that's `signal_for(signo)` and lives in a sibling note when M2 lands. Different surface, different table.
- Multi-line error explanations (e.g. "this happened because…"). kriya errors are single-line. Long explanations belong in `--help` output or man pages.
- Coloured stderr. Errors go to stderr unstyled. ANSI is reserved for stdout payloads on a tty (M3 `ls`).
