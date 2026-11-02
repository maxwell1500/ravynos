#!/usr/bin/env python3
"""Static selector coverage for an unmodified macOS app bundle.

dyld reports one missing symbol per launch; the Objective-C message path is
worse, because an unimplemented selector is only discovered when a specific
object receives it.  This tool finds the whole set at once: every selector a
bundle's Mach-O images reference (__objc_selrefs) that no class or category
in the ravynOS SDK implements (method lists in __objc_const, read through
`otool -ov`).

    tests/compat/selector-coverage.py [--app PATH] [--sdk PATH]
                                      [--write-baseline PATH]
                                      [--baseline PATH]

With --baseline the exit status is 1 when a selector is missing now that the
baseline called provided.  The check is by presence, the same granularity as
symbol coverage: a selector implemented by any SDK class counts as provided.
"""
import argparse
import bisect
import json
import os
import re
import struct
import subprocess
import sys

MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")

# otool -ov prints method entries with two addresses; class and ivar names
# have a single address, so this pattern keeps methods only.
# Method entries appear both as "name 0xADDR (0xOFF) sel" (relative lists)
# and "name 0xADDR sel" (absolute lists); the parenthesised part is optional.
METHOD_RE = re.compile(r"^\s+name\s+0x[0-9a-f]+(?: \(0x[0-9a-f]+\))? (\S+)\s*$")
SELREF_RE = re.compile(r"^\s+0x[0-9a-f]+\s+(\S+)\s*$")


def is_macho(path):
    try:
        with open(path, "rb") as handle:
            return handle.read(4) in MACHO_MAGICS
    except OSError:
        return False


def fat_thin_offset(path):
    """Return (file offset of the x86_64 slice, endian) for a Mach-O file."""
    with open(path, "rb") as handle:
        header = handle.read(8)
        if header[:4] == b"\xca\xfe\xba\xbe":
            count = struct.unpack(">I", header[4:8])[0]
            for _ in range(count):
                entry = handle.read(20)
                _cputype, _sub, offset, _size, _align = struct.unpack(">IIIII", entry)
                # x86_64 is CPU_TYPE_X86_64 = 0x01000007
                if _cputype == 0x01000007:
                    return offset
            return None
        if header[:4] == b"\xcf\xfa\xed\xfe":
            return 0
    return None


def otool_objc(path):
    """Full Objective-C metadata for one image, as otool prints it."""
    return subprocess.run(["otool", "-ov", path], capture_output=True,
                          text=True, errors="replace").stdout


def referenced_selectors(path):
    """Selectors named by __objc_selrefs.

    otool resolves chained fixups, so its listing carries the selector
    names directly; reading the section as raw pointers gives garbage in
    any binary linked with DYLD_CHAINED_FIXUPS.
    """
    text = otool_objc(path)
    result = set()
    in_selrefs = False
    for line in text.splitlines():
        if line.startswith("Contents of "):
            in_selrefs = "__objc_selrefs" in line
            continue
        if not in_selrefs:
            continue
        match = SELREF_RE.match(line)
        if match:
            result.add(match.group(1))
    return result


def implemented_selectors(path):
    result = otool_objc(path)
    found = set()
    in_methods = False
    for line in result.splitlines():
        if line.startswith("Contents of "):
            in_methods = False
            continue
        if re.match(r"^\s+(baseMethods|instanceMethods|classMethods)\b", line):
            in_methods = True
            continue
        # A top-level key (exactly four spaces of indent) ends a method list.
        if re.match(r"^    \S", line) and not re.match(r"^\s+(entsize|count|name|types|imp)\b", line):
            in_methods = False
            continue
        if not in_methods:
            continue
        match = METHOD_RE.match(line)
        if match:
            found.add(match.group(1))
    return found


def bundle_images(app):
    for root, _dirs, files in os.walk(app):
        for name in files:
            path = os.path.join(root, name)
            if os.path.isfile(path) and not os.path.islink(path) and is_macho(path):
                yield path


def sdk_images(sdk):
    roots = [os.path.join(sdk, "usr/lib"),
             os.path.join(sdk, "usr/lib/system"),
             os.path.join(sdk, "System/Library/Frameworks")]
    for base in roots:
        for root, _dirs, files in os.walk(base):
            for name in files:
                path = os.path.join(root, name)
                if ".framework/" in path and "/Versions/" not in path:
                    continue
                if os.path.isfile(path) and not os.path.islink(path) and is_macho(path):
                    yield path


def group(selector):
    for prefix, owner in (("_NS", "Foundation/AppKit"), ("NS", "Foundation/AppKit")):
        if selector.startswith(prefix):
            return owner
    return "other"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="tests/apps/Firefox ESR.app")
    parser.add_argument("--sdk", default="Developer/ravynOS.sdk")
    parser.add_argument("--write-baseline")
    parser.add_argument("--baseline")
    args = parser.parse_args()

    if not os.path.isdir(args.app):
        print(f"selector_coverage: no app bundle at {args.app}", file=sys.stderr)
        return 2

    referenced = set()
    provided = set()
    images = 0
    for image in bundle_images(args.app):
        images += 1
        referenced |= referenced_selectors(image)
        provided |= implemented_selectors(image)

    libraries = 0
    for library in sdk_images(args.sdk):
        libraries += 1
        provided |= implemented_selectors(library)

    missing = sorted(referenced - provided)
    print(f"selector_coverage: images={images} referenced={len(referenced)} "
          f"sdk_images={libraries} provided={len(provided)} missing={len(missing)}")
    for selector in missing[:40]:
        print(f"  {selector}")
    if len(missing) > 40:
        print(f"  ... {len(missing) - 40} more")

    if args.write_baseline:
        with open(args.write_baseline, "w") as handle:
            json.dump(missing, handle, indent=1)
        print(f"selector_coverage: baseline written to {args.write_baseline}")

    status = 0
    if args.baseline:
        with open(args.baseline) as handle:
            previous = set(json.load(handle))
        regressions = sorted(set(missing) - previous)
        if regressions:
            print(f"selector_coverage: {len(regressions)} new missing selector(s):")
            for selector in regressions:
                print(f"  {selector}")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
