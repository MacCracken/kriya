# 0034 — `tail -f` follows by polling, as GNU's loop without inotify does

**Status**: Accepted
**Date**: 2026-11-04

## Context

Until 1.9.2 kriya's `tail -f` followed one file, by stat'ing its path every 0.2 s, and refused two,
exit 2. It had no `-F`, `--follow=name`, `--retry` or `--pid`. POSIX defines `-f` for one file and
says nothing of the rest; GNU's `tail` has all of them, and scripts and log tooling rely on them
(`tail -F` across a log rotation, `tail -f --pid=$!`).

GNU has two follow loops:

- **inotify** (`tail_forever_inotify`), its default on Linux. It wakes on events, so it answers
  at once, and some of its messages follow the events: a rotated file is reported as *has become
  inaccessible* and then *has appeared*.
- **polling** (`tail_forever`), used where inotify is not: on remote file systems, for standard
  input, for symbolic links, and under the hidden option `---disable-inotify`. Each round it
  fstats every file, reads what grew, and reopens a followed name after `--max-unchanged-stats`
  quiet rounds; a rotated file is reported as *has been replaced*.

Measured on GNU 9.12 over 22 scenarios (appends to one, two and three files; truncation; removal and
rename under both follow modes; a file missing at the start; a directory; `-n +N`; `-c N`), the two
loops print the same bytes on stdout in every one. Only their wording on stderr differs, and their
latency. Cyrius has no inotify wrapper, and agnos has no inotify at all.

## Decision

**kriya's `tail` follows with GNU 9.12's polling loop, ported function for function: `tail_file`,
`record_open_fd`, `recheck`, `any_live_files`, `some_writers_exist` and `tail_forever`.** It is
compared against GNU run as `tail ---disable-inotify`, which is the same algorithm:

- `-f` / `--follow=descriptor` follows the open file through a rename or removal; `--follow=name`
  reopens the name; `-F` is `--follow=name --retry`; the last of `-f`, `-F` and `--follow` wins.
- Any number of files, with GNU's headers when the output switches between them.
- `--retry`, `--pid=PID` (repeatable, as in GNU 9.5 and later: exit once every PID has gone, after
  one more round), `--max-unchanged-stats=N` and `-s SECONDS` (any non-negative `strtod` number).
- A pipe or FIFO on standard input is not followed, as POSIX requires; a regular file there is.
- When stdout is a pipe whose reader has gone, `tail` dies of SIGPIPE at the next round, as
  GNU's `check_output_alive` does, instead of waiting for data to write.

Three choices differ from GNU, and `smoke-tail-follow.sh` asserts each:

- **The default interval is 0.2 s**, not GNU's 1.0. GNU's interval is its fallback; with inotify it
  answers at once, and 0.2 s keeps kriya close to that. `-s` sets it.
- **A bad `-s`, `--pid`, `--max-unchanged-stats` or `--follow=` value, and `-F` on standard input,
  exit 2**, kriya's usage error ([ADR 0008](0008-posix-exit-code-policy.md)). GNU exits 1.
- **On agnos**, which has no fstat on a descriptor and no lseek, a file is stat'ed by name and a
  truncated file is reopened.

## Consequences

- **Positive**
  - Byte-identical stdout to GNU's polling loop in all 28 scenarios of `smoke-tail-follow.sh`, on
    9.4, 9.7 and 9.12 (on 9.4 one exit status is asserted instead: 9.6 made `--follow=name` exit 1
    once every file is gone, and kriya does); the messages that carry meaning (*file truncated*, *has become
    inaccessible*, *has appeared*, *has been replaced*, *no files remaining*) are GNU's words.
  - Log rotation works: `tail -F app.log` follows the new file, and `--pid` ends a follow when its
    writer exits.
- **Negative**
  - Latency: a change shows up after up to 0.2 s, where GNU's inotify loop shows it at once. A
    rotated name is noticed after `--max-unchanged-stats` quiet rounds (5, so about 1 s).
  - Each round fstats every followed file: 5 system calls a second a file at the default interval.
  - Under rotation kriya says *has been replaced* where GNU's inotify loop says *has become
    inaccessible* and then *has appeared*; its polling loop says what kriya says.
- **Neutral**
  - GNU 9.4 kept only the last `--pid`; scripts that pass one see no difference.

## Alternatives considered

- **inotify.** It would need a Linux-only syscall layer and a second loop with its own rules
  (watches on parent directories for `--follow=name`, symlink and remote-file exclusions), and
  agnos could not use it. The stdout is the same either way; only the latency would improve.
- **Keep the path-stat loop and add files to it.** That loop could not tell a renamed file from a
  replaced one, so `--follow=descriptor` and `--follow=name` would have meant the same thing.
- **GNU's 1.0 s default.** Exactly GNU's polling behaviour, but a regression in responsiveness
  against kriya's own 0.2 s and against what GNU's users see.
