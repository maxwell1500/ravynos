#!/usr/bin/env python3
"""Generate manifest_shellpid1.json: base tree + our static userspace + shell PID 1.

Why a generated manifest instead of an edit
-------------------------------------------
tools/bootlab/assets/ holds local-only Apple interop binaries that are not in
git and not reproducible, and manifest.json drives the verified working Apple
boot path.  Both are off limits here.  So this script READS manifest.json and
manifest_userspace.json and emits a new file; it never writes either of them,
and never writes to assets/.

The substitution rule, and why it is auditable
----------------------------------------------
manifest.json stages /bin/cat, /bin/echo and /bin/ls from assets/.  Those are
APPLE product binaries: fat universal Mach-Os that link
/usr/lib/libSystem.B.dylib (current version 1356.0.0) and carry
LC_CODE_SIGNATURE.  They run on the target only because the dynamic-linker
payload is staged alongside them.  Meanwhile staged/ holds our own statically
linked equivalents, built by build-ravynos-utils.sh.

So base-manifest and staged paths collide.  The rule is: OUR BUILD WINS.  The
substitution is driven by walking staged/ itself, NOT by trusting
manifest_userspace.json to declare every path -- that file names 11 entries
while staged/ holds 27 files, and keying off the declaration list makes the
rule appear to work while silently substituting nothing.

Every replacement is printed and recorded, because a preference rule that
quietly decides which binary executes is exactly the kind of thing that should
not be silent.  Pass --no-prefer-staged to see the un-preferred list.

This image is for a STATIC terminal, so the Apple dynamic-linker payload is
dropped outright: /usr/lib/dyld, libSystem.B.dylib, libobjc.A.dylib and the
46-file usr/lib/system/ glob.  Nothing static can use them, and leaving them in
would put Apple product binaries in userland paths.

Finally the result is verified rather than assumed: every userland entry is
classified structurally, and any Apple product binary left in a userland path
is a hard error, not a warning.
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = json.load(open(os.path.join(HERE, "manifest.json")))
USER = json.load(open(os.path.join(HERE, "manifest_userspace.json")))

PREFER_STAGED = "--no-prefer-staged" not in sys.argv

# Which binary becomes PID 1 at /sbin/launchd.  Defaults to the shell init.
# --init-file is how a diagnostic binary (work/init_probe, the Mach IPC
# probe) is run as PID 1 without editing this script or touching manifest.json.
INIT_FILE = "work/init_shell"
for _a in sys.argv:
    if _a.startswith("--init-file="):
        INIT_FILE = _a.split("=", 1)[1]

# Paths under these prefixes make up "userland": programs and the libraries
# they load.  The boot chain (System/Library/CoreServices, EFI/BOOT) is
# deliberately NOT userland and is left alone.
USERLAND_PREFIXES = ("bin/", "usr/bin/", "usr/lib/", "sbin/", "etc/")

# Apple dynamic-linker payload.  Unusable by a static binary, and the only
# reason the Apple /bin/* binaries appear to work at all.
DROP_APPLE_DYNAMIC = {
    "usr/lib/dyld", "usr/lib/libSystem.B.dylib", "usr/lib/libobjc.A.dylib",
}

# assets/etc/rc is 32 bytes of raw x86-64 that is not an object file, has no
# LC_CODE_SIGNATURE, and is not a program: it is a vestige of the Sep-26
# MINI-SHELL, which init_exec_dynamic.c records as gone from the tree ("only
# its serial log survives").  Nothing in the current boot reads it -- neither
# this shell PID 1 nor the kernel references /etc/rc.  It is untracked and
# local-only, so it is not ours and not reproducible.
#
# It is dropped here rather than shipped as dead weight in an image that is
# otherwise 100% our userland.  NOTE: manifest_dynamic.json and
# manifest_applefree.json still reference it; those are not this script's to
# change, and the same reasoning would apply to them.
DROP_VESTIGIAL = {"etc/rc"}

# The static userspace links libpthread_static.a.  When that archive is
# rebuilt -- as it was at 22:30 for the TSD-base fix -- every already-linked
# static binary built before it is STALE and will fault on the first %gs read,
# even though it still looks perfectly well-formed: right size, no dylibs, no
# undefined symbols.  Shape checks cannot catch that; only mtime can.
#
# This has already bitten once (the shell was relinked but the 26 utilities
# were not), so it is a hard error here rather than a note in the log.  A
# stale binary that passes every other check is the most expensive kind to
# debug, because nothing about it looks wrong.
STALE_AFTER = [
    os.path.join(HERE, "..", "..", "Libraries", "Libsystem",
                 "libsystem_pthread", "static", "libpthread_static.a"),
    os.path.join(HERE, "..", "..", "Libraries", "Libsystem",
                 "libSystem.B.a"),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def is_apple_product(path):
    """Structural test for 'this is an Apple binary', not a guess.

    Apple product binaries in assets/ are either MH_DYLIB (extracted from the
    shared cache) or fat Mach-Os that link Apple's libSystem and carry
    LC_CODE_SIGNATURE.  Ours are static, single-architecture, unsigned, and
    have no LC_LOAD_DYLIB at all.
    """
    kind = subprocess.run(["file", "-b", path], capture_output=True,
                          text=True).stdout
    if "dynamic library" in kind:
        return True, "MH_DYLIB (Apple shared-cache extract)"
    # otool -L on a fat binary prints nothing without -arch; ask per-arch.
    dylibs = subprocess.run(["otool", "-arch", "x86_64", "-L", path],
                            capture_output=True, text=True).stdout
    if "/usr/lib/libSystem.B.dylib" in dylibs:
        return True, "links Apple /usr/lib/libSystem.B.dylib"
    codesig = subprocess.run(["otool", "-l", path], capture_output=True,
                             text=True).stdout.count("LC_CODE_SIGNATURE")
    if codesig:
        return True, "carries LC_CODE_SIGNATURE"
    return False, "static, unsigned, no dylibs (ours)"


# ------------------------------------------------- staged inventory (by dir)
staged_root = os.path.join(HERE, "staged")
staged, staged_abs = {}, {}
for root, _dirs, names in os.walk(staged_root):
    for n in names:
        abs_p = os.path.join(root, n)
        rel = os.path.relpath(abs_p, staged_root).replace(os.sep, "/")
        staged[rel] = rel
        staged_abs[rel] = abs_p

# ------------------------------------------------------------- substitution
files, subs, drops = [], [], []

for ent in BASE["files"]:
    if "glob" in ent:
        prefix = ent.get("asset_prefix", "")
        if prefix.startswith("usr/lib/"):
            drops.append((prefix,
                          "Apple dynamic-linker payload glob: unusable by a "
                          "static binary, and it is what makes the Apple "
                          "/bin/* look runnable"))
        else:
            files.append(ent)
        continue

    path = ent.get("path")
    if path in DROP_APPLE_DYNAMIC:
        drops.append((path, "Apple dynamic-linker payload: unusable by a "
                            "static binary"))
        continue
    if "init" in ent:
        drops.append((path, "tick-only init_static PID 1; replaced by the "
                            "shell PID 1 below"))
        continue
    if path == "bin/sh":
        drops.append((path, "assets/bin/sh is a 4,280-byte tick stub, not a "
                            "shell; replaced by the real static build"))
        continue
    if PREFER_STAGED and path in staged:
        subs.append((path, "staged/%s" % staged[path]))
        files.append({"path": path, "file": "staged/" + staged[path],
                      "comment": "SUBSTITUTED: our static build preferred "
                                 "over the assets/ Apple binary"})
        continue
    files.append(ent)

# A base-manifest userland entry that is an Apple product binary and has NO
# staged file at that same path is dropped rather than kept.  We must not ship
# an Apple binary in a userland path, and where our equivalent already exists
# at a different path the drop is free: that is the case for bin/echo, whose
# static build is staged at usr/bin/echo (and which the shell also has as a
# builtin, so nothing loses the ability to run it).
dropped_apple = set()
substituted_paths = {p for p, _s in subs}
for ent in BASE["files"]:
    path = ent.get("path")
    if not path or not path.startswith(USERLAND_PREFIXES) or "asset" not in ent:
        continue
    # Already handled by the staged-preference pass above. Listing such a path
    # here as "dropped" as well would print two contradictory lines for one
    # path, which is exactly the kind of misleading audit this script exists
    # to prevent.
    if path in substituted_paths:
        continue
    src = os.path.join(HERE, "assets", ent["asset"])
    if not os.path.isfile(src):
        continue
    apple, why = is_apple_product(src)
    if not apple:
        continue
    equiv = [p for p in staged if os.path.basename(p) == os.path.basename(path)]
    where = ("our equivalent is staged at %s" % equiv[0]) if equiv else \
            ("no static replacement exists; the capability is simply absent")
    drops.append((path, "Apple product binary (%s) with no static "
                        "replacement at this path -- dropped; %s"
                        % (why, where)))
    dropped_apple.add(path)

for _p in sorted(DROP_VESTIGIAL):
    if any(e.get("path") == _p for e in files):
        drops.append((_p, "vestigial: 32 bytes of raw x86-64 left by the "
                            "Sep-26 MINI-SHELL, which is gone from the tree; "
                            "not a program, not read by any current PID 1"))
files = [e for e in files if e.get("path") not in DROP_VESTIGIAL]

# Two rules can reach the same path (libSystem.B.dylib is both in
# DROP_APPLE_DYNAMIC and an Apple userland asset). One line per path.
seen, uniq = set(), []
for _p, _w in drops:
    if _p in seen:
        continue
    seen.add(_p)
    uniq.append((_p, _w))
drops = uniq

# Now actually remove them from the file list: the loop above appended the
# base-manifest entry before this pass ran.
if dropped_apple:
    files = [e for e in files
             if not (e.get("path") in dropped_apple and "asset" in e)]

# Anything staged that the base manifest did not mention is still ours and
# still belongs on the image (mkdir, ln, rm, sed, grep, ...).
for rel in sorted(staged):
    if any(e.get("path") == rel for e in files):
        continue
    files.append({"path": rel, "file": "staged/" + rel,
                  "comment": "our static build from staged/"})

files.append({
    "path": "sbin/launchd",
    "file": INIT_FILE,
    "comment": "PID 1. This is the init path load_init_program() tries "
               "first. NOT assets/bin/sh (a 4,280-byte tick stub). Source: "
               + INIT_FILE,
})

dirs = list(BASE["dirs"])
for d in USER["dirs"]:
    if d not in dirs:
        dirs.append(d)

out = {
    "volume": BASE.get("volume", "RAVYNOS"),
    "comment": [
        "GENERATED by make_shell_manifest.py -- do not hand-edit.",
        "manifest.json and manifest_userspace.json are read-only inputs.",
        "Every userspace entry uses the additive \"file\" key, which",
        "mkimage.py resolves relative to tools/bootlab/, so staged/ is",
        "reachable without copying anything into assets/.",
        "",
        "SUBSTITUTED (our static build preferred over the assets/ Apple one):",
    ] + ["  %s <- %s" % (p, s) for p, s in subs] + [
        "", "DROPPED:",
    ] + ["  %s -- %s" % (p, w) for p, w in drops] + [
        "",
        "No Apple product binary remains in a userland path (sbin/, bin/,",
        "usr/bin/, usr/lib/, etc/); the generator fails if one does.",
    ],
    "dirs": dirs,
    "files": files,
}

dest = os.path.join(HERE, "manifest_shellpid1.json")
with open(dest, "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")

# ------------------------------------------------------------------- audit
print("staged/ holds %d files" % len(staged))
print("wrote %s: %d files, %d dirs" % (dest, len(files), len(dirs)))

print("\n=== SUBSTITUTIONS (our static build preferred over assets/ Apple) ===")
for p, s in subs:
    print("  %-16s <- %s" % (p, s))
if not subs:
    print("  (none)")

print("\n=== DROPPED ===")
for p, w in drops:
    print("  %-28s %s" % (p, w))

print("\n=== USERLAND AUDIT (every entry classified structurally) ===")
bad, stale_paths = [], []
for ent in files:
    path = ent.get("path")
    if not path or not path.startswith(USERLAND_PREFIXES):
        continue
    if "file" in ent:
        src = os.path.join(HERE, ent["file"])
    elif "asset" in ent:
        src = os.path.join(HERE, "assets", ent["asset"])
    else:
        continue
    if not os.path.isfile(src):
        print("  %-22s MISSING %s" % (path, src))
        bad.append(path)
        continue
    apple, why = is_apple_product(src)
    # mtime, not shape: a binary linked before a library rebuild still passes
    # every structural check and still crashes on first use.  Scoped to
    # staged/, because those are the binaries that actually link
    # libpthread_static.a -- work/init_shell is freestanding (-nostdlib) and
    # etc/rc is a 32-byte blob, so neither can be stale with respect to it.
    # A false positive that blocks the build is its own failure mode.
    newest = max((os.path.getmtime(a) for a in STALE_AFTER
                  if os.path.isfile(a)), default=0)
    links_libsystem = ent.get("file", "").startswith("staged/")
    stale = (links_libsystem and newest
             and os.path.getmtime(src) < newest)
    if stale:
        why += "  *** STALE: linked before its library archive ***"
    print("  %-22s %s %9d  %s"
          % (path, "APPLE" if apple else "ours ", os.path.getsize(src), why))
    if apple:
        bad.append(path)
    if stale:
        stale_paths.append(path)

print("\n=== KEY BINARIES (size, sha256[:16]) ===")
for want in ("sbin/launchd", "bin/sh", "bin/cat", "bin/ls", "bin/echo"):
    for ent in files:
        if ent.get("path") == want:
            src = (os.path.join(HERE, ent["file"]) if "file" in ent
                   else os.path.join(HERE, "assets", ent["asset"]))
            print("  %-14s %9d  %s"
                  % (want, os.path.getsize(src), sha256(src)[:16]))

if stale_paths:
    print("\nERROR: %d userland binaries are STALE -- linked before "
          "libpthread_static.a was rebuilt, so they will fault on the first "
          "%%gs read despite looking well-formed:\n  %s"
          % (len(stale_paths), ", ".join(sorted(stale_paths))),
          file=sys.stderr)
    print("Rebuild them (build-ravynos-utils.sh, then --stage) and re-run.",
          file=sys.stderr)
    sys.exit(1)

if bad:
    print("\nERROR: Apple product binary (or missing file) in userland: %s"
          % ", ".join(bad), file=sys.stderr)
    sys.exit(1)
print("\nOK: no Apple product binary in any userland path.")
