#!/usr/bin/env python3
"""Static symbol coverage for an unmodified macOS app bundle.

The runtime oracle (boot the guest, read dyld's first "Symbol not found")
finds one missing symbol per launch.  This tool finds the whole list at
once: every undefined symbol in the bundle's Mach-O images that neither the
bundle itself nor the ravynOS SDK libraries export.

    tests/compat/symbol-coverage.py [--app PATH] [--sdk PATH]
                                    [--write-baseline PATH]
                                    [--baseline PATH]
                                    [--max-missing N]

With --baseline the exit status is 1 when a symbol is missing now that the
baseline called provided (regression), which is how CI can gate a new
Firefox build without booting anything.
"""
import argparse
import collections
import json
import os
import subprocess
import sys

MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def is_macho(path):
    try:
        with open(path, "rb") as handle:
            return handle.read(4) in MACHO_MAGICS
    except OSError:
        return False


def symbols(path, flag):
    """Return the underscore-prefixed symbols of one image.

    flag is '-u' (undefined) or '-gU' (externally defined).  Fat binaries are
    read as x86_64; the product targets Intel Macs.
    """
    result = subprocess.run(["nm", "-arch", "x86_64", flag, "-j", path],
                            capture_output=True, text=True)
    return {line.strip() for line in result.stdout.splitlines()
            if line.strip().startswith("_")}


def bundle_images(app):
    images = []
    for root, _dirs, files in os.walk(app):
        for name in files:
            path = os.path.join(root, name)
            if os.path.isfile(path) and not os.path.islink(path) and is_macho(path):
                images.append(path)
    return images


def sdk_libraries(sdk):
    imports = [os.path.join(sdk, "usr/lib"), os.path.join(sdk, "usr/lib/system")]
    imports += [os.path.join(sdk, "System/Library/Frameworks")]
    for base in imports:
        for root, _dirs, files in os.walk(base):
            for name in files:
                path = os.path.join(root, name)
                if ".framework/" in path and "/Versions/" not in path:
                    continue  # only the versioned binary is the library
                if os.path.isfile(path) and not os.path.islink(path) and is_macho(path):
                    yield path


# First matching prefix wins.  The order matters: CT before C, CF before C.
FRAMEWORKS = [
    ("_AX", "Accessibility"),
    ("_CA", "QuartzCore"),
    ("_CT", "CoreText"),
    ("_CG", "CoreGraphics"),
    ("_CF", "CoreFoundation"),
    ("_NS", "Foundation/AppKit"),
    ("_objc", "objc4"),
    ("_dispatch", "libdispatch"),
    ("_xpc", "libxpc"),
    ("_Sec", "Security"),
    ("_Audio", "CoreAudio"),
    ("_CV", "CoreVideo"),
    ("_VT", "VideoToolbox"),
    ("_MTL", "Metal"),
    ("_IO", "IOKit"),
    ("_LS", "LaunchServices"),
    ("_PM", "PrintCore"),
    ("_cups", "CUPS"),
    ("_Pasteboard", "Pasteboard"),
    ("_FS", "Carbon"),
    ("_UC", "Carbon"),
    ("_MD", "Metadata"),
    ("_UT", "UniformTypeIdentifiers"),
]


def classify(symbol):
    for prefix, framework in FRAMEWORKS:
        if symbol.startswith(prefix):
            return framework
    return "other"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="tests/apps/Firefox ESR.app")
    parser.add_argument("--sdk", default="Developer/ravynOS.sdk")
    parser.add_argument("--write-baseline")
    parser.add_argument("--baseline")
    parser.add_argument("--max-missing", type=int)
    args = parser.parse_args()

    if not os.path.isdir(args.app):
        print(f"symbol_coverage: no app bundle at {args.app}", file=sys.stderr)
        return 2

    images = bundle_images(args.app)
    undefined, exported = set(), set()
    for image in images:
        undefined |= symbols(image, "-u")
        exported |= symbols(image, "-gU")
    for library in sdk_libraries(args.sdk):
        exported |= symbols(library, "-gU")

    missing = sorted(undefined - exported)
    counts = collections.Counter(classify(symbol) for symbol in missing)

    print(f"symbol_coverage: images={len(images)} undefined={len(undefined)} "
          f"provided={len(exported)} missing={len(missing)}")
    for framework, count in counts.most_common():
        print(f"  {count:5d}  {framework}")

    if args.write_baseline:
        with open(args.write_baseline, "w") as handle:
            json.dump(missing, handle, indent=1)
        print(f"symbol_coverage: baseline written to {args.write_baseline}")

    status = 0
    if args.baseline:
        with open(args.baseline) as handle:
            previous = set(json.load(handle))
        regressions = sorted(set(missing) - previous)
        if regressions:
            print(f"symbol_coverage: {len(regressions)} new missing symbol(s):")
            for symbol in regressions:
                print(f"  {symbol}")
            status = 1
    if args.max_missing is not None and len(missing) > args.max_missing:
        print(f"symbol_coverage: {len(missing)} missing exceeds {args.max_missing}")
        status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
