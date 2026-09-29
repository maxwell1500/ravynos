#!/usr/bin/env python3
"""Symbolize a ravynOS dyld backtrace using the loader's own DYLD-LOAD-BASE print.

    python3 tools/bootlab/symbolize_anchored.py <serial.log> <loader-binary>

WHY THIS IS A SCRIPT AND NOT A ONE-LINER
  The loader slide is different on every boot, so a backtrace from one run cannot
  be symbolized against another. The loader prints `DYLD-LOAD-BASE: 0x...` in
  dyldbootstrap::start() immediately before rebaseDyld(), which is where every
  fault we have seen is. That print is the ONLY sound anchor, and reading it by
  eye is how a nearest-plausible symbol gets attached to the wrong address.

  Two refusals are built in, because both failure modes have been paid for:
    * no DYLD-LOAD-BASE in the log  -> exit, never guess a slide
    * address outside the loader's own image extent -> report it, never name it
"""
import bisect
import re
import subprocess
import sys


def load_base(path):
    for line in open(path, errors="replace"):
        m = re.search(r"DYLD-LOAD-BASE:\s*0x([0-9a-fA-F]+)", line)
        if m:
            return int(m.group(1), 16)
    sys.exit("no DYLD-LOAD-BASE in %s -- refusing to guess a slide" % path)


def symbols(binary):
    out = subprocess.run(["nm", "-n", binary], capture_output=True, text=True).stdout
    syms = []
    for line in out.splitlines():
        p = line.split()
        if len(p) == 3 and p[1] in "tT":
            syms.append((int(p[0], 16), p[2]))
    syms.sort()
    return syms


def image_extent(binary):
    """Highest vmaddr+vmsize over the image's segments.

    Symbolizing outside this range produces a confident-looking name with a
    nonsense offset -- _abort_with_payload+0x7fff69816fc90 -- which is the
    exact failure this project has already paid for once.
    """
    out = subprocess.run(["otool", "-l", binary], capture_output=True, text=True).stdout
    top, vm = 0, None
    for line in out.splitlines():
        p = line.split()
        if len(p) == 2 and p[0] == "vmaddr":
            vm = int(p[1], 16)
        elif len(p) == 2 and p[0] == "vmsize" and vm is not None:
            top = max(top, vm + int(p[1], 16))
            vm = None
    return top


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    log, binary = sys.argv[1], sys.argv[2]
    base = load_base(log)
    syms = symbols(binary)
    top = image_extent(binary)
    print("anchored base : 0x%x" % base)
    print("binary        : %s" % binary)
    print("symbols       : %d" % len(syms))
    print("image extent  : 0x%x" % top)
    print()

    inside, outside = set(), set()
    for line in open(log, errors="replace"):
        for tok in re.findall(r"0x([0-9a-fA-F]{6,16})", line):
            v = int(tok, 16)
            (inside if base <= v < base + top else outside).add(v)

    print("  %-14s %-10s %s" % ("raw", "offset", "symbol"))
    for v in sorted(inside):
        off = v - base
        i = bisect.bisect_right(syms, (off, "\xff")) - 1
        if i < 0:
            print("  0x%012x  +0x%-8x <below first symbol>" % (v, off))
        else:
            a, name = syms[i]
            print("  0x%012x  +0x%-8x %s+0x%x" % (v, off, name, off - a))
    print()
    print("  %d further addresses in the log lie OUTSIDE the loader image and"
          " are deliberately not named." % len(outside))
    print()

    print("  register file (verbatim):")
    for line in open(log, errors="replace"):
        if re.match(r"^\s*R[A-Z0-9]{1,2}:", line):
            print("   ", line.strip())


if __name__ == "__main__":
    main()
