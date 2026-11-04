#!/usr/bin/env python3
"""vanish.py ON NAME VICTIM -- CMD...

The hook between a directory read and the examination of an entry (1.8.7). Runs CMD under ptrace
(x86_64 Linux only). At the first syscall of class ON whose path argument's last component is
NAME, it removes VICTIM (a file or a directory tree) and lets the call proceed, so the call fails
with ENOENT: the entry existed when the directory was read and is gone when it is looked at,
EVERY time. A churning second process only makes that likely.

ON is `stat` (newfstatat, statx, stat, lstat, readlinkat, readlink), `open` (openat, open) or
`readlink` (readlinkat, readlink), optionally `:N` for the Nth such call instead of the first. Exits with CMD's status, and prints `vanish: fired` or
`vanish: never fired` on stderr, so a case can tell a hook that missed from a rule that held.

Two traps, found writing it: a `/proc/PID/mem` handle opened before the child's exec names the
OLD address space, so every read from it is empty; and a read into an unmapped page comes back
EMPTY rather than raising, so a loop that waits for a NUL spins for ever.
"""
import ctypes, os, shutil, signal, sys

STAT = {262, 332, 4, 6, 267, 89}      # newfstatat statx stat lstat readlinkat readlink
OPEN = {257, 2}                       # openat open
PATH_ARG = {262: "rsi", 332: "rsi", 267: "rsi", 257: "rsi", 4: "rdi", 6: "rdi", 2: "rdi", 89: "rdi"}

class Regs(ctypes.Structure):
    _fields_ = [(n, ctypes.c_ulonglong) for n in (
        'r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi orig_rax rip cs eflags '
        'rsp ss fs_base gs_base ds es fs gs').split()]

def main():
    on, name, victim = sys.argv[1], sys.argv[2], sys.argv[3]
    assert sys.argv[4] == '--'
    cmd = sys.argv[5:]
    nth = 1
    if ':' in on:
        on, nth = on.split(':')[0], int(on.split(':')[1])
    want = {'stat': STAT, 'open': OPEN, 'readlink': {267, 89}}[on]
    seen = 0
    libc = ctypes.CDLL(None, use_errno=True)
    libc.ptrace.restype = ctypes.c_long
    libc.ptrace.argtypes = [ctypes.c_long, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]
    pid = os.fork()
    if pid == 0:
        libc.ptrace(0, 0, None, None)                      # PTRACE_TRACEME
        os.kill(os.getpid(), signal.SIGSTOP)
        os.execv(cmd[0], cmd)
    os.waitpid(pid, 0)
    libc.ptrace(0x4200, pid, None, ctypes.c_void_p(0x1 | 0x100000))   # TRACESYSGOOD | EXITKILL
    entering, fired, sig = True, False, 0
    while True:
        libc.ptrace(24, pid, None, ctypes.c_void_p(sig))  # PTRACE_SYSCALL
        sig = 0
        _, st = os.waitpid(pid, 0)
        if os.WIFEXITED(st) or os.WIFSIGNALED(st):
            break
        s = os.WSTOPSIG(st)
        if s != (signal.SIGTRAP | 0x80):
            if s != signal.SIGTRAP:
                sig = s                                    # deliver real signals
            continue
        if entering and not fired:
            r = Regs()
            libc.ptrace(12, pid, None, ctypes.byref(r))   # PTRACE_GETREGS
            nr = r.orig_rax
            if nr in want:
                addr = getattr(r, PATH_ARG[nr])
                raw = b''
                a = addr
                # ⚠ Opened per read: a handle taken before the child's exec names the OLD address
                # space, and every read from it comes back empty.
                mem = open('/proc/%d/mem' % pid, 'rb', buffering=0)
                while len(raw) < 4096:
                    n = 4096 - (a % 4096)          # never read across a page boundary
                    try:
                        mem.seek(a)
                        chunk = mem.read(n)
                    except OSError:
                        break
                    if not chunk:
                        break                          # unmapped: an empty read, not an error
                    if b'\0' in chunk:
                        raw += chunk.split(b'\0', 1)[0]
                        break
                    raw += chunk
                    a += n
                mem.close()
                if raw.rstrip(b'/').rsplit(b'/', 1)[-1] == name.encode():
                    seen += 1
                if seen == nth:
                    seen += 1
                    if os.path.isdir(victim) and not os.path.islink(victim):
                        shutil.rmtree(victim)
                    else:
                        os.unlink(victim)
                    fired = True
        entering = not entering
    print('vanish: fired' if fired else 'vanish: never fired', file=sys.stderr)
    sys.exit(os.waitstatus_to_exitcode(st))

main()
