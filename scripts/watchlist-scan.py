#!/usr/bin/env python3
"""watchlist-scan.py — the mechanical half of lessons.md § The compiler watchlist.

⛔ RUN THIS AT EVERY TOOLCHAIN PIN BUMP. A pin move is exactly when a latent
frame bug stops being latent, and the entries here are the shapes that compile
clean, pass lint and are wrong anyway.

⚠ It exists because the M15d status was recorded as "zero instances" while four
sat in `find.cyr` — the detection had been run by eye. A status established by
reading is not a status.

Covers M15a (stat buffers must be [144]), M15c (duplicate array declarations in
one function), M15d (`break` in a `while` that declares a `var`) and M15i (a
top-level name defined by both kriya and its stdlib closure). M15b has no
advance detection by construction; M15e is covered by building the .tcyr/.fcyr
subsets. Exits non-zero if M15a, M15d or M15i finds anything.
"""
import re, glob, collections, os

files = sorted(glob.glob('src/**/*.cyr', recursive=True))
decl = re.compile(r'\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*(\d+)\s*\]')
fnre = re.compile(r'^fn\s+([A-Za-z_][A-Za-z0-9_]*)')

# --- M15a: a stat buffer must be [144]; flag any buffer handed to a stat call
statfns = ('k_stat','k_lstat','fs_lstat_at','fs_fstatat','fs_stat_entry','k_fstat')
bad_stat, all_decls = [], []
for f in files:
    lines = [re.sub(r'#.*$', '', l) for l in open(f).read().split('\n')]
    sizes = {}
    fn = '?'
    for i, l in enumerate(lines, 1):
        m = fnre.match(l)
        if m: fn, sizes = m.group(1), {}
        for d in decl.finditer(l):
            sizes[d.group(1)] = (int(d.group(2)), i)
            all_decls.append((f, fn, d.group(1), int(d.group(2))))
        for s in statfns:
            if s + '(' in l:
                for name, (n, ln) in sizes.items():
                    if ('&' + name) in l and n != 144:
                        bad_stat.append((f, i, fn, name, n, s))
print("M15a — declarations scanned:", len(all_decls))
print("M15a — stat buffers not [144]:", len(bad_stat))
for b in bad_stat: print("   ", b)

# --- M15c: duplicate var names in one function (arrays are the dangerous shape)
dups = []
for f in files:
    lines = [re.sub(r'#.*$', '', l) for l in open(f).read().split('\n')]
    fn, seen = '?', collections.Counter()
    arrs = collections.defaultdict(list)
    for i, l in enumerate(lines, 1):
        m = fnre.match(l)
        if m:
            for nm, occ in arrs.items():
                if len(occ) > 1: dups.append((f, fn, nm, occ))
            fn, arrs = m.group(1), collections.defaultdict(list)
        for d in decl.finditer(l):
            arrs[d.group(1)].append(i)
    for nm, occ in arrs.items():
        if len(occ) > 1: dups.append((f, fn, nm, occ))
print("M15c — duplicate ARRAY declarations in one function:", len(dups))
for d in dups: print("   ", d)

# --- M15d: `break` inside a while whose body declares a var
hits = []
for f in files:
    lines = [re.sub(r'#.*$', '', l) for l in open(f).read().split('\n')]
    depth = None; has_var = False; start = 0; fn='?'
    for i, l in enumerate(lines, 1):
        m = fnre.match(l)
        if m: fn = m.group(1)
        if re.search(r'\bwhile\s*\(', l):
            depth = l.count('{') - l.count('}'); has_var = False; start = i; continue
        if depth is not None:
            if decl.search(l) or re.search(r'\bvar\s+\w+\s*[:=]', l): has_var = True
            if 'break;' in l and has_var: hits.append((f, i, fn, start))
            depth += l.count('{') - l.count('}')
            if depth <= 0: depth = None
print("M15d — `break` in a while that declares a var:", len(hits))
for h in hits: print("   ", h)

# --- M15i: a top-level name kriya defines that its stdlib closure ALSO defines.
# cyrius merges a duplicate definition with only a warning ("last definition
# wins"), so a stdlib function can end up calling kriya's code or reading kriya's
# initializer. 6.5.36 gave lib/io.cyr `_env_load`/`_env_len` — names
# src/lib/env.cyr already used — and the stdlib `getenv` then answered "unset" or
# segfaulted. The build printed the warning from 1.6.7 on; the one audit that read
# it filed it as harmless. The stdlib gains names at a pin bump, which is when
# this runs.
# ⚠ The closure follows every `include "lib/…"`, including other targets' peers
# behind an #ifdef, so it over-approximates: a hit there is still worth a rename.
def toplevel_names(path):
    names, in_enum = set(), False
    for l in open(path, encoding='utf-8', errors='replace').read().split('\n'):
        if in_enum:
            if l.startswith('}'): in_enum = False; continue
            m = re.match(r'\s+([A-Za-z_][A-Za-z0-9_]*)\s*=', l)
            if m: names.add(m.group(1))
            continue
        m = re.match(r'(?:fn|var)\s+([A-Za-z_][A-Za-z0-9_]*)', l)
        if m: names.add(m.group(1))
        if re.match(r'enum\s+\w+\s*\{', l): in_enum = '}' not in l
    return names

cyml = open('cyrius.cyml').read()
declared = re.search(r'^stdlib\s*=\s*\[(.*)\]', cyml, re.M)
todo = ['lib/%s.cyr' % s for s in re.findall(r'"([^"]+)"', declared.group(1))] if declared else []
closure = set()
while todo:
    p = todo.pop()
    if p in closure or not os.path.exists(p): continue
    closure.add(p)
    for l in open(p, encoding='utf-8', errors='replace').read().split('\n'):
        m = re.match(r'\s*include\s+"(lib/[^"]+)"', l)
        if m: todo.append(m.group(1))
stdlib_names = collections.defaultdict(list)
for p in sorted(closure):
    for n in toplevel_names(p): stdlib_names[n].append(p)
clashes = []
for f in files:
    for n in sorted(toplevel_names(f)):
        if n in stdlib_names: clashes.append((f, n, stdlib_names[n][0]))
print("M15i — stdlib closure: %d files; kriya names also defined there: %d"
      % (len(closure), len(clashes)))
for c in clashes: print("   ", c)
if not closure:
    print("M15i — no stdlib closure found (run from the repo root after `cyrius deps`)")

import sys
fail = len(bad_stat) + len(hits) + len(clashes) + (0 if closure else 1)
if dups and sorted(d[2] for d in dups) != ['klen_box', 'tb', 'ts']:
    print("M15c — the duplicate-array set CHANGED; re-verify each is mutually exclusive")
    fail += 1
print("watchlist-scan:", "OK" if fail == 0 else "%d problem(s)" % fail)
sys.exit(1 if fail else 0)
