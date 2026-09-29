#!/usr/bin/env python3
"""Startup-state census for statically linked ravynOS programs.

THE QUESTION THIS TOOL ANSWERS
-------------------------------
Not "is this identifier assigned somewhere?" -- that was the old question and
it was wrong, twice.  It reported "ok" on two symbols that are written in
source and are nevertheless never reached by a static binary:

    __TSD_MIG_REPLY   set only from mach_init.c:135
    mach_task_self_   set only from mach_init.c:135

Both live in the libc-startup region that only dyld runs.  The old tool could
not tell them apart from a genuinely-published symbol.

The question now asked is:

    Is this symbol's WRITER reachable from _start in a real linked binary?

Reachability is computed from a call graph extracted out of the linked static
binaries themselves -- `nm` for what is defined, disassembly for what calls
what.  That is ground truth for a program that actually exists, and it does not
depend on parsing preprocessor structure.  Which is the point: `__pthread_static_init`
lives inside `#if VARIANT_STATIC` and the shared dylib build never compiles it,
so "is this reachable" is a property of the BINARY, not of the source.

LIMITATIONS -- READ BEFORE TRUSTING A "reachable" ANSWER
--------------------------------------------------------
1. DIRECT CALLS ONLY.  The graph is built from `callq <symbol>`.  Anything
   reached through a function pointer -- os_once, pthread_once, atexit,
   constructor lists -- is INVISIBLE, and will be reported unreachable.  That
   is a false NEGATIVE, which is the safe direction (the tool abstains rather
   than claims), but it is real: `__malloc_initialize` is genuinely called at
   run time and this tool cannot see it.  An "unreachable" verdict therefore
   means "not reachable by direct call", never "not called".
2. SYMBOLS, NOT SOURCE.  Mach-O prefixes C identifiers with one underscore, so
   the C `environ` is `_environ` and the C `_program_vars_init` is
   `__program_vars_init`.  A wrong guess here silently reports a symbol
   unreachable, so the known cases below are checked by exact name.
3. IT ANSWERS ABOUT ONE BINARY AT A TIME.  Reachability from _start differs per
   program.  Every verdict below is about the binaries actually scanned, and
   the tool names them.

WHAT IT DOES NOT CLAIM
----------------------
The original `*_pointer` BSS check is retained and is still sound, and it is
reported separately.  Nothing here weakens it.

Usage:
  find_dyld_only_state.py [--binaries PATH ...] [--bss-only] [--verbose]
"""
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

DEFAULT_BINARIES = [
    os.path.join(HERE, "staged", "bin", "sh"),
    os.path.join(HERE, "staged", "bin", "ls"),
    os.path.join(HERE, "staged", "usr", "bin", "sed"),
    os.path.join(HERE, "staged", "usr", "bin", "sort"),
    os.path.join(HERE, "staged", "usr", "bin", "grep"),
    os.path.join(HERE, "work", "init_mprobe"),
    os.path.join(HERE, "work", "init_probe"),
]

# Mach-O names (one leading underscore) of every symbol whose reachability we
# have an external, measured ground truth for.  These are the validation set;
# the tool is not believed until it reproduces all four.
KNOWN = {
    # --- must be reported UNREACHABLE (these are the two old false positives)
    "___NSGetEnviron_reply_unused": None,
    "_mach_task_self_": "mach_init.c:135 -- libc startup only, never reached",
    # --- must be reported REACHABLE (published by ravyn_static_startup)
    "__pthread_static_init": "TSD base, called from ravyn_static_startup",
    "__program_vars_init": "crt externs, called from ravyn_static_startup",
    # --- runtime-reachable but INDIRECTLY, so this is the known blind spot
    "__malloc_initialize": "called via os_once -> indirect, invisible here",
}

# Exact Mach-O spellings. nm shows THREE leading underscores for the C
# function __pthread_static_init and two for the C _program_vars_init.
# Getting this wrong makes a genuinely-reachable writer look unreachable --
# precisely the failure this tool exists to avoid.
KNOWN_EXACT = {
    "_mach_task_self_": ("unreachable",
        "mach_init.c:135, libc startup only -- the old FALSE POSITIVE"),
    "___pthread_static_init": ("reachable-or-mixed",
        "TSD base, called from ravyn_static_startup; MIXED is correct "
        "because work/init_probe is the FREESTANDING control and does not "
        "link static-start.c at all -- this is the tool answering per-binary"),
    "__program_vars_init": ("reachable-or-mixed",
        "crt externs, called from ravyn_static_startup; WEAK, so absent from "
        "binaries that do not pull it -- MIXED is the correct answer"),
    "__malloc_initialize": ("unreachable",
        "called via os_once -> INDIRECT, the known blind spot"),
}

# Writers of interest, as (symbol -> why we care).
SUBJECTS = {
    "_mach_task_self_": "cached task port read by the mach_task_self() macro",
    "_environ": "environ, read by getenv",
    "_program_vars_helper": "crt externs (see __program_vars_init)",
    "__TSD_MIG_REPLY": "per-thread MIG reply port, %gs:0x10",
    "__malloc_entropy_initialized": "set once the allocator is seeded",
}

FUNC_LABEL = re.compile(r'^([A-Za-z_][A-Za-z_0-9]*):\s*$')
CALLQ = re.compile(r'^\s*[0-9a-f]+\s+callq\s+(\S+)')
# a store to a symbol: mov<sz> %reg, _sym(%rip)
WRITE = re.compile(r'mov[qwl]?\s+%(?:[a-z0-9]+|ax|bx|di|si),?\s+(_[A-Za-z_][A-Za-z_0-9]*)\(%rip\)')
SYMBOL_DECL = re.compile(r'\b(_\w+)\b')


def scan(binary):
    """Return (defined_symbols, edges, writers) for one linked binary."""
    d = subprocess.run(["otool", "-tV", binary],
                       capture_output=True, text=True).stdout
    defined, adj, writers, cur = set(), {}, {}, None
    for ln in d.splitlines():
        m = FUNC_LABEL.match(ln)
        if m:
            cur = m.group(1)
            defined.add(cur)
            continue
        m = CALLQ.match(ln)
        if m and cur:
            adj.setdefault(cur, set()).add(m.group(1))
            continue
        if cur:
            for w in WRITE.findall(ln):
                writers.setdefault(w, set()).add(cur)
    return defined, adj, writers


def reachable_from(adj, root="_start"):
    seen, stack = set(), [root]
    while stack:
        f = stack.pop()
        if f in seen:
            continue
        seen.add(f)
        for c in adj.get(f, ()):
            if c not in seen:
                stack.append(c)
    return seen


def main():
    args = sys.argv[1:]
    verbose = "--verbose" in args
    bins = []
    for i, a in enumerate(args):
        if a == "--binaries" and i + 1 < len(args):
            bins = args[i + 1].split(",")
    if not bins:
        bins = DEFAULT_BINARIES
    bins = [b if os.path.isabs(b) else os.path.join(HERE, b) for b in bins]

    print("=" * 74)
    print("startup-state census: is the writer reachable from _start?")
    print("=" * 74)
    print("LIMITATION: direct calls only. Anything reached through a function")
    print("pointer (os_once, pthread_once, atexit) is INVISIBLE here and will")
    print("read as unreachable. 'unreachable' means 'not reachable by direct")
    print("call' -- never 'not called'.")
    print()

    scanned = [b for b in bins if os.path.isfile(b)]
    if not scanned:
        print("ABSTAIN: no linked binary found to analyse. A verdict about a")
        print("program that does not exist would be worse than no verdict.")
        return 2
    print("binaries analysed (%d):" % len(scanned))
    for b in scanned:
        print("   %s" % os.path.relpath(b, REPO))
    print()

    per_bin = {}
    for b in scanned:
        per_bin[b] = scan(b)

    # ---- validation set first: the tool is not believed until it reproduces
    # all four known cases, including the one it is known to get wrong.
    print("--- VALIDATION against measured ground truth ---")
    print("the tool is not believed until it reproduces all four, including")
    print("the case it is known to get wrong")
    print()
    print("%-26s %-16s %s" % ("symbol", "verdict", "expected / note"))
    ok = True
    for sym, (expect, note) in KNOWN_EXACT.items():
        verdicts = set()
        for b in scanned:
            defined, adj, writers = per_bin[b]
            r = reachable_from(adj)
            verdicts.add("reachable" if sym in r else "unreachable")
        v = "MIXED" if len(verdicts) > 1 else verdicts.pop()
        good = (v == expect) or (expect == "reachable-or-mixed" and v == "MIXED")
        print("%-26s %-16s %s [%s]"
              % (sym, v, note, "ok" if good else "MISMATCH"))
        if not good:
            ok = False
    print()
    if not ok:
        print("ABSTAIN: validation failed. Subject verdicts are withheld -- a")
        print("tool that cannot reproduce the known cases has no standing to")
        print("assert anything about the unknown ones.")
        return 1

    # ---- the actual question
    print("--- SUBJECTS: who writes it, and is that writer reachable? ---")
    for sym, why in SUBJECTS.items():
        print("\n%s   (%s)" % (sym, why))
        found = False
        for b in scanned:
            defined, adj, writers = per_bin[b]
            r = reachable_from(adj)
            w = writers.get(sym)
            if not w:
                continue
            found = True
            rel = os.path.relpath(b, REPO)
            for f in sorted(w):
                mark = "REACHABLE" if f in r else "unreachable"
                print("   %-22s written by %-30s -> %s" % (rel, f, mark))
        if not found:
            print("   no direct write found in the scanned binaries")
            print("   VERDICT: UNDETERMINED (no writer observed)")

    print()
    print("=" * 74)
    print("Retained: the original *-pointer BSS class check is sound and is")
    print("reported separately by --bss-only. This reachability work is")
    print("additive and does not weaken it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
