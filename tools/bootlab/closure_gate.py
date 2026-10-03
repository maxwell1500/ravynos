#!/usr/bin/env python3
"""Build gate: refuse to build an image whose closure or provenance fails.

What it is
----------
One entry point that every runner calls before it builds a disk, so "was this
image allowed to exist?" has exactly one answer and one implementation.  It is
a thin wrapper around closure_check.py -- no second checker, no second
opinion, no second thing to drift.  The runner's exit status is the wrapper's
exit status, so `set -e` scripts stop and `|| fail` scripts report.

    python3 tools/bootlab/closure_gate.py <manifest> [--image IMG]

Runners use it in the pre-build form, on the SAME manifest argument they hand
to mkimage.py.  That is a claim about the SOURCES that will be staged, not
about a finished disk: it is cheap (no image is built yet) and it is where a
borrow can still be prevented.  `--image` is the other form -- it judges the
bytes read back out of an already-built image -- and only
`run_dynamic_gate.sh --no-build` uses it automatically.  Nothing gates the
image a normal run just built; doing so costs another full pass over the
image, so it is opt-in by hand.

Why it exists
-------------
P1 (deleting the borrowed host binaries) is deferred by explicit decision, so
the 31 host-extracted dylibs are still in assets/.  With P1 deferred, this
gate IS the defence against staging them: the rejection happens before a
512 MB image exists rather than as a dyld abort inside QEMU.

Fail-closed
-----------
closure_check.py runs the provenance scan by default and fails when the scan
cannot run, so a host machine without the dyld shared cache cannot be read as
a clean result.  This wrapper inherits that and adds nothing of its own: it
does not re-interpret the verdict, and it has no quiet mode.

Relocatability, and what this gate cannot fix
----------------------------------------------
Every manifest entry resolves against tools/bootlab, which is how mkimage.py
reads them -- and mkimage.py is protected and expands no variables, so a
manifest cannot name $RAVYN_SDKROOT or $RAVYN_BUILD_DIR.  That is why some
entries are spelled "../../..": they are *relative*, but not *relocatable*,
because they still assume the layout the path describes.

The gate treats every one of those as fatal, whether or not the path exists
on the machine running the gate: portability is a property of the manifest,
not of this workstation's directory layout.  It fails BY NAME and prints the
offending paths -- "missing file source: <path>" sends an operator looking at
the wrong thing.  What it cannot do is make a manifest portable; that needs a
producer for the missing libraries, or a variable-aware manifest resolver,
and neither exists.  See PROVENANCE-PLAN.md P0.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))


def manifest_sources_outside_repo(manifest_path):
    """[(staged_path, resolved_source)] for entries outside the repo.

    Returns a plain string instead if the manifest itself cannot be read --
    a gate that cannot read its input must not report that its input is fine.
    """
    try:
        with open(manifest_path) as fh:
            man = json.load(fh)
    except (IOError, OSError, ValueError) as exc:
        return "cannot read manifest %s: %s" % (manifest_path, exc)
    out = []
    for ent in man.get("files", []):
        src = ent.get("file")
        if src is None:
            continue
        if not os.path.isabs(src):
            src = os.path.join(HERE, src)
        src = os.path.normpath(src)
        if not (src == REPO or src.startswith(REPO + os.sep)):
            out.append((ent.get("path", "?"), src))
    return out


def preflight_relocatability(manifest_path):
    """Refuse any entry whose source resolves outside the repository.

    0 = every source resolves inside the repo; 1 = the manifest is not
    relocatable, or cannot be read at all.

    Existence is deliberately NOT a pass.  An out-of-repo path that happens
    to exist on the machine running the gate says nothing about the manifest
    being portable -- it is exactly how a repo-relative manifest can look
    clean on the workstation that produced it and fail on a fresh checkout.
    So the question is never "is it there", only "is it inside", and a
    manifest carrying sibling build-tree borrows is refused by name.
    """
    outside = manifest_sources_outside_repo(manifest_path)
    if isinstance(outside, str):
        print("closure gate: %s" % outside)
        return 1
    if not outside:
        return 0
    present = [(sp, src) for sp, src in outside if os.path.isfile(src)]
    absent = [(sp, src) for sp, src in outside if not os.path.isfile(src)]
    print("closure gate: relocatability -- %d staged file(s) resolve OUTSIDE"
          " the repository." % len(outside))
    print("  A portable manifest resolves every source inside the repo, so")
    print("  this one is not portable -- whether or not the paths happen to")
    print("  exist on this machine.  Their presence here would only prove")
    print("  that THIS checkout's sibling layout is populated.")
    print("")
    for sp, src in present:
        print("    %-44s %s" % (sp, src))
        print("    %-44s %s" % ("", "<-- exists here, still refused"))
    for sp, src in absent:
        print("    %-44s %s   <-- MISSING" % (sp, src))
    print("")
    print("  FATAL: %d entry/entries (%d present on this host, %d missing)"
          % (len(outside), len(present), len(absent)))
    print("  resolve outside the repository.  Typical cause: entries spelled")
    print("  \"../../../build/...\", which assume the default")
    print("      RAVYN_BUILD_DIR=${RAVYN_BUILD_DIR:-/Users/max/Projects/build}")
    print("  in tools/bootlab/build-libraries.sh.  mkimage.py expands no")
    print("  variables, so a manifest cannot follow RAVYN_BUILD_DIR.")
    print("  Fix: build the producer's output into the repository (the")
    print("  Libraries/* producers) and point the manifest there, or copy the")
    print("  artifact in-tree.  This is the P0 portability requirement named")
    print("  in PROVENANCE-PLAN.md; it is not something this gate can paper")
    print("  over, and no host-side workaround is offered.")
    return 1


def main():
    ap = argparse.ArgumentParser(
        description="Run closure_check.py as a build gate.  Exits nonzero -- "
                    "so the caller never reaches mkimage.py -- when the "
                    "manifest's closure or provenance verdict is not PASS.")
    ap.add_argument("manifest", help="manifest JSON, exactly as passed to "
                                     "mkimage.py --manifest")
    ap.add_argument("--image", metavar="IMG",
                    help="judge the bytes read back out of this built image "
                         "instead of the staged source files.  Only used "
                         "automatically by run_dynamic_gate.sh --no-build.")
    ap.add_argument("--nm-check", type=int, default=3, metavar="N",
                    help="cross-check N files against `nm -m`.  The gate "
                         "keeps closure_check.py's own default of 3 rather "
                         "than disabling it: a gate must never be the weaker "
                         "of the two, even for a check that cannot affect "
                         "the verdict.")
    ap.add_argument("--no-provenance-check", action="store_true",
                    help="skip the host-cache verdict.  Off by default and "
                         "deliberately awkward: the provenance question is "
                         "the one this gate exists to answer, and "
                         "closure_check.py already defaults it ON and fails "
                         "closed.")
    args = ap.parse_args()

    print("=== closure gate: %s ==="
          % ("image bytes read back out of %s" % args.image if args.image
             else "staged sources of %s" % os.path.basename(args.manifest)))

    rc = preflight_relocatability(args.manifest)
    if rc:
        print("")
        print("=== closure gate: REFUSED (relocatability preflight) ===")
        print("The image was NOT built.")
        return rc

    cmd = [sys.executable, os.path.join(HERE, "closure_check.py"),
           args.manifest, "--nm-check", str(args.nm_check)]
    if args.image:
        cmd += ["--image", args.image]
    if args.no_provenance_check:
        cmd.append("--no-provenance-check")

    rc = subprocess.call(cmd)

    if rc == 0:
        print("=== closure gate: PASS -- continuing ===")
        return 0
    print("")
    print("=== closure gate: REFUSED ===")
    print("closure_check.py exited %d.  The image was NOT built." % rc)
    print("Read the report above: it names the unresolved symbols, the")
    print("unstaged dependencies, the dylibs dyld2 rejects, or the binaries")
    print("that came out of the host's dyld shared cache.  Each of those is")
    print("a reason the disk would not boot, found here instead of inside")
    print("QEMU.  A host-extracted binary cannot be repaired by rebuilding")
    print("it -- see PROVENANCE-PLAN.md P1.  Nothing is waived here.")
    return rc if rc > 0 else 1


if __name__ == "__main__":
    sys.exit(main())