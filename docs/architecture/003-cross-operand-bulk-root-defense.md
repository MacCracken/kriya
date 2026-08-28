# 003 — Cross-operand bulk-root defense

[ADR 0004](../adr/0004-rm-refuses-root.md) refuses `/` per operand and names *this file* as the place
a defense against shell-expanded `rm -rf /*` would be specified. Four defenses were designed
independently — a bigger static table, exact root coverage, an operand-fan-out threshold, and an
inverted-glob pre-flight — each measured against real corpora and then attacked.

**None of them is being built.** The gap stays open. That is the decision, not an omission, and this
note is what ADR 0004 asked for.

## What happens today, measured

A fixture with five visible entries, six files, a `.dockerenv` and a `.secrets/` dotdir:

| command | entries left | files left |
|---|---|---|
| *(before)* | 5 | 6 |
| `kriya rm -rf FX/*` | 2 | 2 |
| `for d in FX/*; do kriya rm -rf "$d"; done` | 2 | 2 |
| `find FX -mindepth 1 -maxdepth 1 -exec kriya rm -rf {} ';'` | **0** | **0** |
| `kriya rm -rf FX/*/*` | 5 | 3 |

No refusal, no warning, exit `0`. ADR 0004's own check is intact and fires on every spelling of the
root operand — `/`, `//`, `/.`, `/..`, `/usr/..`, `////` all exit `2`. The gap is exactly and only the
aggregate.

## The decision

⛔ **`cmd_rm`'s pre-unlink pass is, and stays, exactly the per-operand ADR 0004 loop.** Stated
mechanically, so an implementer needs no further judgement:

1. For each positional operand `op`, in argv order: `canon = fs_path_absolute(op)` — relative
   operands joined against `getcwd`, `.`/`..` collapsed textually, **no symlink resolution**, per
   [ADR 0003](../adr/0003-symlink-follow-policy.md).
2. If `path_is_absolute(canon) == 0` — the `getcwd` fallback fired — refuse the invocation.
3. If `canon` string-equals any `protected_path_at(i)`, refuse the whole invocation with exit `2`.
4. Otherwise proceed to the removal loop.

**There is no step 5.** No operand counting, no `readdir("/")`, no coverage test, no shared-parent
test, no inverted-glob test. The pre-pass issues no syscall it does not issue today.

## Why — the four candidates, and what killed each

| candidate | rule | what killed it |
|---|---|---|
| **Static tripwire** | add `/usr` and `/etc` to `protected_paths[]` | ⛔ **AGNOS's rootfs is `bin data mirshi`.** Measured by exporting `agnos-thin:latest`: no `/usr` at all, and the `/etc` that appears holds exactly `hostname hosts mtab resolv.conf` — all four injected by Docker. Zero coverage on the platform kriya is built for. |
| **Root cover** | refuse when the operands name every non-dot directory in `/` | Exact cover means one survivor is a free pass. A staged teardown is *allowed* at every destructive step and refused only at the last, when the least is left. |
| **Fan-out threshold** | refuse ≥5 operands whose canonical parent is `/` | ⛔ One operand from its own worst case. Measured in a merged-usr fixture: `rm -f bin sbin lib lib64` — **four operands, no `-r`** — unlinks four symlinks, exits `0`, and leaves every binary unreachable. On this box `/bin`, `/sbin`, `/lib` and `/lib64` are exactly those symlinks. |
| **Deglob pre-flight** | refuse when the operand vector holds a complete expansion of `P/*` | Best of the four: bounded by the table, zero syscalls on a normal `rm`, and the only one that fires in a container, because it mirrors the shell's dot rule. ⚠ Killed by the three findings below rather than by its own false positives. |

Three findings apply to all four. They are why this is a rejection rather than a fifth attempt.

### ⭐ 1. The refusal teaches a strictly worse command

Read the table at the top again. **The shape every candidate refuses is the least destructive of the
four.** The two a refused caller reaches for next — the `for` loop and `find -exec`, which are what
anyone types when a batched `rm` "stops working" — are equal or strictly worse, because a per-operand
route enumerates the **dotfiles the glob never matched**. `find -exec` took the fixture to zero.

⚠ That is not an abstract bypass argument. Every candidate's headline false positive is a container
build, a chroot rootfs assembly, or an initramfs teardown — populations that automate, that have no
escape hatch by construction, and whose fix goes into a Dockerfile or a boot script and then runs
everywhere forever. **A hard refusal manufactures demand for a workaround it cannot see, and the
workaround is worse than what was refused.**

### ⛔ 2. Text-only canonicalization is blind to the operand prefix, and cannot stop being

ADR 0003 governs the **final** component: `rm` unlinks the name, it does not follow it. It says
nothing about **intermediate** components, which the kernel always resolves.

`/proc/self/root` is a kernel-maintained symlink to `/`, present on every Linux and inside every
container, readable unprivileged, needing no setup. Measured:

```
$ set -- /proc/self/root/*        # 19 operands, first = /proc/self/root/bin
$ kriya realpath -s -m /proc/self/root/etc
/proc/self/root/etc               # depth 3 — not /etc, not a root child
```

Every candidate is a function of that canonical text. Every one counts zero, covers nothing, and
matches no table entry.

⭐ **The asymmetry is the mechanism, not a tuning gap.** The *cwd* form is caught, because `getcwd`
returns the kernel's physical path:

```
$ cd /proc/self/root && kriya pwd -P
/
$ cd /proc/self/root && kriya realpath -s -m etc
/etc
```

kriya sees through a symlink in the **cwd** and is structurally blind to one in the **operand
prefix**. Closing that needs `st_dev`/`st_ino` identity, which is a different note and a different
cost — and one that would have to answer to ADR 0003 first.

### 3. There is no universal tripwire

Top-level names across the roots kriya must run on — this box (19 entries, zero dotfiles), the common
container bases, and AGNOS (`bin data mirshi`) — intersect in `{bin}`. And `/bin` is precisely the
name that must not be added: it is a symlink into `usr/` on every merged-usr root, so `rm /bin` is
one `unlinkat`, and the usrmerge migration is a real caller that removes it. **Beyond `/` itself, no
path exists on every root kriya ships onto.**

### What the corpus says, stated against the conclusion

A scan of `/usr/share`, `/usr/lib`, `/usr/bin`, `/etc` and `/home/macro/Repos` parsed **6,475 `rm`
invocations**. Distinct depth-1 absolute operands per invocation: `{0: 6116, 1: 345, 2: 6, 3: 5,
4: 2, 15: 1}`.

⚠ **All fourteen of the ≥2 matches are false.** Inspected one by one, they are: prose in
documentation describing this very problem (kriya's own ADR 0004 scores the 15), `groff` macro files
where `rm` is a groff request meaning *remove macro*, a Go testdata script, and a test log. **Zero
real shell invocations name two or more top-level entries of `/`.**

So the aggregate rules would have been nearly free *on this corpus*. They are rejected anyway,
because the corpus does not contain the populations that pay: container `RUN` steps, chroot rootfs
assembly, initramfs teardown. ⛔ **A false-positive rate measured where the false positives do not
live is evidence about where you looked, not evidence of safety.**

## Hard rules (No-Gos)

1. **No aggregate rule may be added to `rm` without a successor to this note.** Not operand counting,
   not coverage of `readdir("/")`, not a shared-canonical-parent test, not an inverted-glob test, not
   a mount-point census. The decision here is that the aggregate is not a safe object to reason
   about; a patch reintroducing one is reopening the decision, not implementing it.
2. **No entry may be added to `protected_paths[]` for a path that can be absent.** ⛔ A table entry
   converts `rm -f` on a nonexistent path from a POSIX no-op into a hard usage error. Measured:
   `kriya rm -f /absent-toplevel-xyz` exits **0** today, matching GNU, and would exit **2** if that
   name were in the table. `/` always exists; nothing on the list ADR 0004 suggested (`/etc`, `/usr`,
   `/boot`, `/proc`, `/sys`, `/dev`) is guaranteed to, and none of them is on AGNOS.
3. **The table stays a per-operand exact-string test.** ADR 0004 grants free table growth on the
   reasoning that adding entries is "strictly tightening". ⚠ **That grant holds only while the check
   is per-operand.** Under any aggregate rule the entries amplify: adding `/tmp` to stop
   `rm -rf /tmp` would, under a deglob or coverage rule, also refuse `rm -rf /tmp/*` — a weekly
   command. Rules 1 and 3 together are what keep ADR 0004's no-ADR-required extension point honest.
4. **A new table entry must be argued as a platform-specific tripwire, with the platform named** —
   not as a defense against `/*`. No name other than `/` is present on every root kriya ships onto,
   so any entry protects some machines and not others, and the commit message must say which.
5. **The refusal message must name the canonical path, not only the operand as typed.** Today the
   `/`-only table makes this cosmetic. It stops being cosmetic the moment rule 4 is exercised:
   `cd / && rm -rf etc` would print `refusing to operate on 'etc'`, which does not tell the reader
   which protected path was hit.

## What this note does NOT catch, by name

- `rm -rf /*` and every spelling of it — the subject of the note, deliberately unguarded.
- `rm -rf /usr`, `rm -rf /etc`, `rm -rf /var` — single operands, each fatal, out of scope by
  construction.
- `rm -rf /usr/* /etc/* /var/*` — empties the system without ever naming a root child.
- `rm -f /bin /sbin /lib /lib64` on a merged-usr root — four symlinks, no `-r`, exit `0`.
- `rm -rf /proc/self/root/*` and any other route through a symlinked operand prefix.
- `rm -rf /mnt/host/*` where `/mnt/host` is a bind mount of `/`.

## False positives already paid, and left alone

- ⚠ **`kriya rm victim` from a working directory longer than 4095 bytes.** `getcwd` fails,
  `is_protected_path`'s fail-closed arm fires, and an ordinary local file is refused with exit `2`.
  A live false positive, inherited unchanged from 1.5.x. Correct in direction — without a cwd there
  is no way to know what a relative operand names — and not free.
- `rm -rf .` and `rm -rf foo/.` — per-operand skip, exit `1`, POSIX-mandated, and regularly misread
  as the root guard firing.
- `chroot /build/rootfs kriya rm -rf /` — clearing a staging root from inside it. ADR 0004 refuses
  it and this note declines to add the escape hatch; the rewrite from outside is allowed.

## Where the effort should go instead

Not into a cleverer aggregate. The measurements point elsewhere:

- **`st_dev`/`st_ino` identity for protected paths**, which would close the `/proc/self/root`,
  bind-mount and symlinked-prefix families at once — and which has to answer to ADR 0003 before it
  can answer to this note.
- **`find -delete` and `find -exec rm`**, already named at roadmap 1.7.2, which the table above shows
  is the *more* destructive route and currently has no guard at all.
