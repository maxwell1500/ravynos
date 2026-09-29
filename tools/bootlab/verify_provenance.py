#!/usr/bin/env python3
"""Prove every object linked into the kernel is a build of the committed source.

WHY THIS EXISTS
  `kernel_build.py` recompiles a ~43-object allowlist and links the remaining
  ~1035 objects straight out of the build tree, unverified. So a hand-edited
  object is indistinguishable from a built one, and it survives every rebuild.
  That is not hypothetical: `vm_unix.o` carried an uncommitted local edit
  through the whole dyld campaign (BOOT-PLAN 12.5), and more objects still do
  (12.5a). A green build changed nothing.

  This is the check that finds those: for each object, recompile it from
  committed source with its own recorded <obj>.o.json command and compare the
  result. Same command => byte-identical code is the expected, achievable
  result, so any difference means the object was not built from this tree.

WHAT IS COMPARED, AND WHY NOT THE WHOLE FILE
  Everything except the debug sections, excluded by SECTION NAME wherever they
  live. A source that differs only in comments or whitespace produces
  byte-identical code and a different line table, because the line table
  records line numbers -- that is the ordinary way an object gets recompiled,
  and a byte-exact check reports it as drift.

  The exclusion has to be per-section, not per-segment. Both shapes occur here:
    - DWARF in its own `__DWARF` segment (lock_ticket, locks, vm_fault,
      pal_routines): 83-95 differing bytes, all debug.
    - DWARF folded INSIDE the `__TEXT` segment (kern_csr, panic_hooks,
      pe_bootargs): __debug_str grows 16 bytes, __debug_info 11,
      __debug_str_offs 4, which pushes the segment's vmsize/filesize and every
      reloff by 32. A segment-offset cut misses these completely and reports a
      "32-byte divergence" that is entirely debug info.
  In every one of those cases, every function is instruction-identical.

  A gate that cries wolf on seven innocent objects is a gate that gets switched
  off, and then it catches nothing, including the next real one.

WHY IT IS NOT WIRED INTO kernel_build.py
  Because objects genuinely diverge today. An inline gate would be red on
  arrival and would be reporting a backlog, not a regression. This reports and
  exits 0 by default; --strict is the gate. It is also slow (one compile per
  object, ~10 min for the whole tree), so it stays off the `run.sh full` path.

  Usage:
    tools/bootlab/verify_provenance.py                 # report, exit 0
    tools/bootlab/verify_provenance.py --strict        # gate, exit 1 on drift
    tools/bootlab/verify_provenance.py --only kern_exit,vm_unix
    tools/bootlab/verify_provenance.py --limit 40      # cheap spot check
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD_DIR = os.environ.get("RAVYN_BUILD_DIR",
                           "/Users/max/Projects/build/DEVELOPMENT_X86_64")


def load_cmd(obj_path):
    """The object's own recorded compile command, or None if it has no .o.json."""
    jp = obj_path[:-2] + ".o.json"
    if not os.path.isfile(jp):
        return None
    try:
        with open(jp) as f:
            return json.loads(f.read().strip().rstrip(","))
    except (ValueError, OSError):
        return None

def _sections(path):
    """[(segname, sectname, file_offset, size)] for every section.

    otool prints `size` in hex and `offset` in decimal, and also prints a
    reloff/nreloc pair per section that must not be mistaken for the offset."""
    out = subprocess.run(["otool", "-l", path],
                         capture_output=True, text=True).stdout
    res, seg, cur = [], None, None
    for line in out.splitlines():
        s = line.strip()
        m = re.match(r"^segname (\S+)$", s)
        if m:
            seg = m.group(1)
            continue
        m = re.match(r"^sectname (\S+)$", s)
        if m:
            cur = {"seg": seg or "?", "name": m.group(1),
                   "off": None, "size": None}
            res.append(cur)
            continue
        m = re.match(r"^size (0x[0-9a-fA-F]+|\d+)$", s)
        if m and cur is not None and cur["size"] is None:
            cur["size"] = int(m.group(1), 0)
            continue
        m = re.match(r"^offset (\d+)$", s)
        if m and cur is not None and cur["off"] is None:
            cur["off"] = int(m.group(1))
    return [(s["seg"], s["name"], s["off"], s["size"]) for s in res
            if s["off"] is not None and s["size"]]


def code_bytes(path):
    """{sectname: [contents]} for every non-debug, file-backed section.

    Three things are deliberately ignored, each because it produced a measured
    false positive on this tree:

    1. Debug sections. A source differing only in comments yields identical code
       and a different line table; that is how objects normally get recompiled.
    2. Load-command bookkeeping. It is not free-standing: when a debug section
       grows, the enclosing segment's vmsize/filesize and every following
       reloff move with it. kern_csr/panic_hooks/pe_bootargs differ by exactly
       32 bytes that way, entirely from __debug_str growing 16, __debug_info 11
       and __debug_str_offs 4.
    3. The containing SEGMENT name. bcopy/bzero/WKdm* put their code in xnu's
       hibernate segment `__HIB` where a plain replay yields `__TEXT`, with
       byte-identical section contents. That is a build-configuration
       difference, not a source edit.

    Sections at file offset 0 are skipped: that is S_ZEROFILL (__bss), which has
    no file content, and slicing blob[0:size] there would compare the Mach-O
    header and load commands as if they were the section's data.
    """
    with open(path, "rb") as f:
        blob = f.read()
    out = {}
    for _seg, name, off, size in _sections(path):
        if off <= 0 or name.startswith("__debug") or off + size > len(blob):
            continue
        out.setdefault(name, []).append(blob[off:off + size])
    return out


def rebuilds_identical(obj_path, scratch):
    """True if recompiling from source reproduces the object's code exactly.

    Returns None when it cannot be decided (no .o.json, or the recorded
    command does not point at a source file we can rebuild)."""
    cmd = load_cmd(obj_path)
    if cmd is None:
        return None
    args = cmd.get("arguments")
    if not args or "-o" not in args or cmd.get("file") not in args:
        return None
    if not os.path.isfile(cmd["file"]):
        return None

    out = os.path.join(scratch, os.path.basename(obj_path))
    new = list(args)
    new[new.index("-o") + 1] = out
    new = [a for a in new if not a.startswith("-MF")]
    try:
        r = subprocess.run(new, cwd=cmd["directory"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        return None
    if r.returncode != 0 or not os.path.isfile(out):
        return None
    return code_bytes(obj_path) == code_bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if any object does not reproduce (a gate)")
    ap.add_argument("--only", help="comma-separated object basenames to check")
    ap.add_argument("--limit", type=int, default=0,
                    help="check at most N objects (0 = all)")
    args = ap.parse_args()

    link = os.path.join(BUILD_DIR, "link.filelist")
    if not os.path.isfile(link):
        sys.exit("no link.filelist at %s" % link)
    with open(link) as f:
        objs = [l.strip() for l in f if l.strip()]

    if args.only:
        want = {w.strip() for w in args.only.split(",")}
        objs = [o for o in objs if os.path.basename(o)[:-2] in want]

    print("provenance: %d object(s) in %s" % (len(objs), link))

    undecidable, drifted, ok = [], [], 0
    with tempfile.TemporaryDirectory(prefix="provcheck.") as scratch:
        for i, o in enumerate(objs, 1):
            if args.limit and i > args.limit:
                print("  ... stopping at --limit %d" % args.limit)
                break
            if not os.path.isfile(o):
                undecidable.append((o, "missing"))
                continue
            verdict = rebuilds_identical(o, scratch)
            if verdict is None:
                undecidable.append((o, "no usable .o.json"))
            elif verdict:
                ok += 1
            else:
                drifted.append(o)
            if i % 50 == 0:
                print("  ...%d/%d (%d ok, %d drifted)"
                      % (i, len(objs), ok, len(drifted)), flush=True)

    print("\nreproduces committed source : %d" % ok)
    print("DIVERGENT                   : %d" % len(drifted))
    for o in drifted:
        print("   !! %s" % o)
    print("undecidable (no .o.json)    : %d" % len(undecidable))
    if undecidable and args.limit == 0:
        print("   (these are objects the real build system recorded no command"
              " for; they are NOT verified by this check)")

    if drifted:
        print("\nThese objects are in the kernel but are not builds of the"
              " committed source.\nSee BOOT-PLAN.md 12.5a-i/ii/iii before"
              " trusting any measurement that used them.")
    if args.strict and (drifted or undecidable):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
