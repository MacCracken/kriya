#!/usr/bin/env python3
"""watchlist-scan.py — the mechanical half of lessons.md § The compiler watchlist.

⛔ RUN THIS AT EVERY TOOLCHAIN PIN BUMP. A pin move is exactly when a latent
frame bug stops being latent, and the entries here are the shapes that compile
clean, pass lint and are wrong anyway.

⚠ It exists because the M15d status was recorded as "zero instances" while four
sat in `find.cyr` — the detection had been run by eye. A status established by
reading is not a status.

Covers M15a (stat buffers must be [144]), M15c (duplicate array declarations in
one function) and M15d (`break` in a `while` that declares a `var`). M15b has no
advance detection by construction; M15e is covered by building the .tcyr/.fcyr
subsets. Exits non-zero if M15a or M15d finds anything.
"""
import re, glob, collections

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

import sys
fail = len(bad_stat) + len(hits)
if dups and sorted(d[2] for d in dups) != ['klen_box', 'tb', 'ts']:
    print("M15c — the duplicate-array set CHANGED; re-verify each is mutually exclusive")
    fail += 1
print("watchlist-scan:", "OK" if fail == 0 else "%d problem(s)" % fail)
sys.exit(1 if fail else 0)
