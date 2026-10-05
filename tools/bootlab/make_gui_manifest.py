#!/usr/bin/env python3
"""Generate manifest_gui.json: the GUI boot image manifest.

manifest_cpmv.json stages the repo-built libSystem closure but carries the
WindowServer app as work/WindowServer.app.tar.gz -- a gzip tarball at the
path launchd execs, which can never run -- and it stages none of the framework
dylibs WindowServer links.  This generator emits a replacement that stages
the real bundle and its runtime closure:

  * every regular file of the extracted WindowServer.app tree, at
    System/Library/CoreServices/WindowServer.app/<relative> (a real bundle:
    Contents/Info.plist + Contents/ravynOS/WindowServer, the path the
    com.ravynos.WindowServer launchd job execs);
  * every dylib in WindowServer's transitive otool -L closure that
    manifest_cpmv.json does not already stage, at its Darwin install path,
    symlinks flattened to real file copies;
  * System/Library/LaunchAgents/com.ravynos.{Dock,Filer}.json from the
    repo's SystemLibrary/;
  * the var/tmp/private directory tree launchd needs (see DIRS);
  * the Dock/Filer app bundles their LaunchAgents exec, staged from the repo
    or build tree when present and reported MISSING with the paths searched
    when not (they are not built by the CoreServices default path here).

The cpmv entry that stages the bundle as a tar.gz is dropped; every other
cpmv entry is kept verbatim.

Source resolution is repo-first: the in-repo ravynOS SDK
(../../Developer/ravynOS.sdk) is preferred; the out-of-tree build dir
($RAVYN_BUILD_DIR, default /Users/max/Projects/build) is the fallback for
libs the SDK does not carry (libutil, libicucore.A, libicudata).  A closure
member that resolves in neither is reported MISSING and omitted.

Usage: python3 make_gui_manifest.py [--out manifest_gui.json]
Exit 0 when the closure is complete, 1 when anything is MISSING (the
manifest is still written with everything that resolved).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
CPMV = os.path.join(HERE, "manifest_cpmv.json")
BUNDLE_TAR = os.path.join(HERE, "work", "WindowServer.app.tar.gz")
BUNDLE_EXTRACT = os.path.join(HERE, "work", "ws_bundle")
BUNDLE_DST_ROOT = "System/Library/CoreServices/WindowServer.app"
# What the com.ravynos.WindowServer launchd job execs (work/com.ravynos.WindowServer.json).
WS_EXEC = os.path.join(BUNDLE_EXTRACT, "WindowServer.app",
                       "Contents", "ravynOS", "WindowServer")
BUILD = os.environ.get("RAVYN_BUILD_DIR", "/Users/max/Projects/build")
SDK = os.path.join(REPO, "Developer", "ravynOS.sdk")
BUILD_FRAMEWORKS = os.path.join(BUILD, "Users", "max", "Projects", "ravynos", "Frameworks")
BUILD_SDK = os.path.join(BUILD, "Developer", "Platforms", "ravynOS.platform",
                         "Developer", "SDKs", "ravynOS.sdk")
BUILD_SRC = os.path.join(BUILD, "Users", "max", "Projects", "ravynos")
LAUNCHAGENTS = ["com.ravynos.Dock.json", "com.ravynos.Filer.json"]

# Directories the kernel does not create and launchd/the GUI need before any
# job can run.  devfs is mounted over /dev at boot (bsd_init.c
# devfs_kernel_mount("/dev")), so /dev only has to exist as the mountpoint; its
# entries come from devfs.  Everything else is a real (empty) directory:
# launchd cannot open a job's StandardOutPath/StandardErrorPath, and syslogd
# cannot bind its /var/run/log socket, if /var/log and /var/run are absent.
DIRS = [
    "dev",
    "private",
    "private/var",
    "private/var/log",
    "private/tmp",
    "var",
    "var/log",
    "var/run",
    "var/tmp",
    "tmp",
]

# The Dock/Filer LaunchAgents exec these bundles.  Neither is produced by the
# CoreServices default build on this host; they are searched (repo source tree,
# then build tree) and reported MISSING when absent rather than invented.
CS_APPS = ["Dock", "Filer"]

# /etc/bootstrap -- the pre-daemon system setup hook.  launchctl's System
# session calls it via system("/etc/bootstrap") before scanning
# /System/Library/LaunchDaemons.  ravynOS boots from a pre-built image whose
# root is already mounted and configured, so there is no filesystem to check or
# mount (no zfs, no fsck).  The only runtime state that can go stale is the
# nologin marker and the WindowServer rendezvous file, so clear those and
# return success.
#
# The /etc/bootstrap.d hook the FreeBSD bootstrap runs is deliberately NOT
# reproduced here: that directory does not exist in this image, and the shell
# staged as /bin/sh has no '[' builtin and the image has no /bin/[ (only
# /bin/test), so a '[' test fails with "[: not found" -- measured in the boot
# log.  Add the hook with /bin/test if /etc/bootstrap.d is ever populated.
ETC_BOOTSTRAP = """#!/bin/sh
# ravynOS /etc/bootstrap
#
# launchctl's System session calls this before loading LaunchDaemons
# (BSD/bin/launchctl/launchctl.c: system_specific_bootstrap() ->
# system("/etc/bootstrap")).  It is the pre-daemon system setup hook.
#
# ravynOS boots from a pre-built image whose root is already mounted and
# configured, so there is no filesystem to check or mount here (no zfs, no
# fsck).  The only runtime state that can go stale across a reboot is the
# nologin marker and the WindowServer rendezvous file, so clear those and
# return success.
echo "-=- Bootstrap running -=-"
rm -f /var/run/nologin /var/run/windowserver
echo "-=- Bootstrap complete -=-"
exit 0
"""

# /etc/rc -- the post-daemon "runcom" phase.  launchctl's System session runs
# it after the LaunchDaemons are loaded (runcom() -> execl(/bin/sh, "sh",
# "/etc/rc")).  On ravynOS the root is a pre-built image: the filesystems are
# already mounted, there is no fsck, and hostname/network/console settings are
# applied by launchd or compiled in.  There is genuinely nothing to configure
# at this phase, so the correct minimal content is a script that reports it ran
# and returns success -- runcom() waits on it, and the agent scan that starts
# Dock and Filer runs after the System session completes.
ETC_RC = """#!/bin/sh
# ravynOS /etc/rc
#
# launchctl's System session runs this once the LaunchDaemons are loaded
# (BSD/bin/launchctl/launchctl.c: runcom() -> execl(/bin/sh, "sh", "/etc/rc")).
# It is the BSD "runcom" phase: post-daemon system configuration.
#
# On ravynOS the root is a pre-built image: the filesystems are already
# mounted, there is no fsck, and hostname/network/console settings are applied
# by launchd or compiled in.  There is genuinely nothing to configure at this
# phase, so this script reports that it ran and returns success.  Add rc-time
# setup here if ravynOS ever needs it; keep the exit status 0 so the System
# session completes and the agent scan (Dock, Filer) runs.
echo "-=- rc complete -=-"
exit 0
"""


def otool_deps(path):
    """LC_LOAD_DYLIB / LC_REEXPORT_DYLIB paths of a Mach-O, as otool reports them."""
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout
    deps = []
    for line in out.splitlines()[1:]:  # first line is the file's own LC_ID_DYLIB
        line = line.strip()
        if line:
            deps.append(line.split(" ")[0])
    return deps


def install_path(dep):
    """Map a link-time path to the Darwin install path it is staged at.

    Frameworks linked from the build tree
    (.../Frameworks/Foo/Foo.framework/Versions/A/Foo) are staged at their
    canonical /System/Library/Frameworks location; system dylibs already
    carry their install path.
    """
    marker = ".framework/Versions/"
    if marker in dep:
        # The .framework bundle is the path component right before
        # /Versions/ -- in a build tree the framework name appears twice
        # (.../Frameworks/CoreText/CoreText.framework/...) and in an install
        # path once (.../Frameworks/CoreText.framework/...).
        # The marker consumes the ".framework" text, so the path component
        # right before it is the bare framework name.
        fw = dep.split(marker, 1)[0].rsplit("/", 1)[-1]
        tail = dep.split(marker, 1)[1]
        return "/System/Library/Frameworks/%s.framework/Versions/%s" % (fw, tail)
    return dep


def candidates(inst):
    """Possible real-file sources for an install path, repo-first."""
    cands = []
    if inst.startswith("/System/Library/Frameworks/"):
        rel = inst[len("/System/Library/Frameworks/"):]
        cands.append(os.path.join(SDK, "System", "Library", "Frameworks", rel))
        cands.append(os.path.join(BUILD_FRAMEWORKS, rel))
    elif inst == "/usr/lib/system/libutil.dylib":
        cands.append(os.path.join(SDK, "usr", "lib", "libutil.dylib"))
        cands.append(os.path.join(BUILD_SDK, "usr", "lib", "libutil.dylib"))
        cands.append(os.path.join(BUILD_SRC, "BSD", "lib", "libutil", "libutil.dylib"))
    elif inst == "/usr/lib/libicucore.A.dylib":
        cands.append(os.path.join(SDK, "usr", "lib", "libicucore.A.dylib"))
        cands.append(os.path.join(BUILD_SDK, "usr", "lib", "libicucore.A.dylib"))
        cands.append(os.path.join(BUILD_SRC, "Libraries", "ICU", "libicucore.A.dylib"))
    elif inst == "/usr/lib/libicudata.dylib":
        cands.append(os.path.join(SDK, "usr", "lib", "libicudata.dylib"))
        cands.append(os.path.join(BUILD_SDK, "usr", "lib", "libicudata.dylib"))
        cands.append(os.path.join(BUILD_SRC, "Libraries", "ICU", "target", "lib",
                                  "libicudata.dylib"))
    # Generic repo-SDK candidate (e.g. /usr/lib/libsqlite3.dylib ->
    # Developer/ravynOS.sdk/usr/lib/libsqlite3.dylib). The repo SDK now carries
    # the libs the manifest used to source from the out-of-tree build SDK, so
    # every entry can be repo-relative.
    cands.append(os.path.join(SDK, inst.lstrip("/")))
    # Final fallback: the out-of-tree build SDK, used only when the repo SDK
    # does not carry the file.
    cands.append(os.path.join(BUILD_SDK, inst.lstrip("/")))
    return cands


def manifest_source(abs_path):
    """Manifest source string for a real file: repo-relative when inside the
    repo (portable), absolute otherwise (build-tree fallback)."""
    if abs_path.startswith(REPO + os.sep):
        return os.path.relpath(abs_path, HERE)
    return abs_path


def resolve(inst):
    """Real file for an install path (symlinks flattened to the real file).
    Returns (source_string, absolute_path) or (None, None)."""
    for cand in candidates(inst):
        if os.path.isfile(cand) and os.path.getsize(cand) > 0:
            real = os.path.realpath(cand)
            return manifest_source(real), real
    return None, None

def stage_bundle(entries, bundle_root, dst_root, comment, exclude=()):
    """Stage every regular file under bundle_root at dst_root/<relative>.

    Symlinks are flattened to real file copies (manifest_source(realpath)),
    which is what the staged filesystem can hold.  Returns the file count.
    `exclude` is a set of basenames to skip (dead-weight files the bundle
    carries but nothing in the image uses).
    """
    n = 0
    for dirpath, dirnames, filenames in os.walk(bundle_root):
        dirnames.sort()
        for name in sorted(filenames):
            if name in exclude:
                continue
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, bundle_root).replace(os.sep, "/")
            entries.append({
                "path": dst_root + "/" + rel,
                "file": manifest_source(os.path.realpath(src)),
                "comment": comment,
            })
            n += 1
    return n


# WindowServer's bundle carries the vendored libinput/libevdev shared objects
# (both under Contents/Resources/ and the duplicated top-level Resources/).
# They are dead weight: nothing in the image depends on them, WindowServer is
# not linked to them (nm -u shows no libinput/libevdev undefined symbols), and
# the input path has no /dev/input source in the kernel.  Excluded from the
# bundle walk so the manifest does not stage them.
BUNDLE_EXCLUDE = {"libevdev.so", "libevdev.so.2", "libinput.so", "libinput.so.1"}


def expand_closure(exes, staged, entries, closure, seen):
    """BFS the otool -L closure of every executable in exes.

    Each dylib not already staged by the base manifest is staged at its Darwin
    install path; resolve() reports it MISSING when no source exists.  Appends
    (install_path, source_or_None, status) to closure; `seen` dedupes install
    paths across calls so two apps sharing a dylib stage it once.
    """
    queue = list(exes)
    while queue:
        p = queue.pop(0)
        for dep in otool_deps(p):
            if dep.startswith("@"):
                continue
            inst = install_path(dep)
            if inst in seen:
                continue
            seen.add(inst)
            if inst.lstrip("/") in staged:
                closure.append((inst, None, "already staged by manifest_cpmv.json"))
                continue
            src, apath = resolve(inst)
            if src is None:
                closure.append((inst, None, "MISSING"))
                continue
            origin = ("repo-built, staged from the in-repo ravynOS SDK"
                      if src.startswith("../../") else
                      "built by the repo but absent from the repo SDK; "
                      "staged from the build tree (RAVYN_BUILD_DIR)")
            entries.append({
                "path": inst.lstrip("/"),
                "file": src,
                "comment": "dylib closure; " + origin,
            })
            closure.append((inst, src, "staged"))
            queue.append(apath)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(HERE, "manifest_gui.json"))
    args = ap.parse_args()

    with open(CPMV) as f:
        base = json.load(f)
    staged = {e["path"] for e in base["files"]}

    # 1. Extract the bundle fresh so re-runs are deterministic.
    if not os.path.isfile(BUNDLE_TAR):
        sys.exit("missing bundle tarball: %s" % BUNDLE_TAR)
    if os.path.isdir(BUNDLE_EXTRACT):
        shutil.rmtree(BUNDLE_EXTRACT)
    os.makedirs(BUNDLE_EXTRACT)
    subprocess.run(["tar", "-xzf", BUNDLE_TAR, "-C", BUNDLE_EXTRACT], check=True)
    bundle_root = os.path.join(BUNDLE_EXTRACT, "WindowServer.app")
    if not os.path.isfile(WS_EXEC):
        sys.exit("extracted bundle has no executable at Contents/ravynOS/WindowServer")

    # 2. Keep every cpmv entry except the bundle-as-tarball placeholder.
    entries = []
    for e in base["files"]:
        if e["path"] == BUNDLE_DST_ROOT:
            continue
        entries.append(e)

    # 3. Stage every regular file of the bundle tree (symlinks flattened).
    n_bundle = stage_bundle(
        entries, bundle_root, BUNDLE_DST_ROOT,
        "WindowServer.app bundle file (extracted from "
        "work/WindowServer.app.tar.gz)", exclude=BUNDLE_EXCLUDE)

    # 4. Dylib closure of the bundle executable, at Darwin install paths.
    closure = []  # (install_path, source_or_None, status)
    seen = set()
    expand_closure([WS_EXEC], staged, entries, closure, seen)

    # 5. Dock / Filer LaunchAgents.
    for name in LAUNCHAGENTS:
        src = os.path.join(REPO, "SystemLibrary", "LaunchAgents", name)
        dst = "System/Library/LaunchAgents/" + name
        if not os.path.isfile(src):
            closure.append((dst, None, "MISSING"))
            continue
        entries.append({
            "path": dst,
            "file": os.path.relpath(src, HERE),
            "comment": "GUI LaunchAgent from the repo's SystemLibrary/",
        })

    # 6. Dock / Filer application bundles.  Their LaunchAgents exec
    #    System/Library/CoreServices/<name>.app/Contents/ravynOS/<name>; with
    #    no bundle the job cannot start.  Search the repo source tree first,
    #    then the build tree, and report MISSING with the paths searched rather
    #    than invent a bundle.
    for name in CS_APPS:
        dst_root = "System/Library/CoreServices/%s.app" % name
        repo_root = os.path.join(REPO, "CoreServices", name, name + ".app")
        work_root = os.path.join(HERE, "work", name + ".app")
        build_root = os.path.join(BUILD_SRC, "CoreServices", name, name + ".app")
        # A repo-relative source is what keeps the manifest portable. The
        # --frameworks build writes the bundle into the out-of-tree build dir,
        # so if no in-repo bundle exists, copy it under work/ (gitignored,
        # exactly like WindowServer's work/ws_bundle) and stage from there.
        # No absolute build path is then recorded in the manifest.
        if not os.path.isdir(repo_root) and os.path.isdir(build_root):
            if os.path.isdir(work_root):
                shutil.rmtree(work_root)
            shutil.copytree(build_root, work_root, symlinks=True)
        roots = [repo_root, work_root]
        root = next((r for r in roots if os.path.isdir(r)), None)
        exe = os.path.join(root or "", "Contents", "ravynOS", name)
        if root is None or not os.path.isfile(exe):
            closure.append((dst_root, " or ".join(roots), "MISSING"))
            continue
        n_app = stage_bundle(
            entries, root, dst_root,
            "%s.app bundle file (staged from %s)" % (name, root))
        closure.append((dst_root, root, "staged %d files" % n_app))
        expand_closure([exe], staged, entries, closure, seen)
    # 7. launchctl and its libjansson dependency. launchd's hardcoded System
    #    bootstrapper execs /bin/launchctl (BSD/sbin/launchd/core.c:7195), so the
    #    binary must sit at that exact path; launchctl's LC_LOAD_DYLIB requires
    #    libjansson, which is built into the repo SDK.
    entries.append({
        "path": "bin/launchctl",
        "file": "work/launchctl_dyn",
        "comment": "launchd's hardcoded /bin/launchctl (BSD/sbin/launchd/core.c:7195)",
    })
    entries.append({
        "path": "usr/lib/libjansson.dylib",
        "file": "../../Developer/ravynOS.sdk/usr/lib/libjansson.dylib",
        "comment": "libjansson required by launchctl's LC_LOAD_DYLIB",
    })
    # 8. Fonts. CoreText/AppKit resolve fonts through fontconfig, whose
    #    Frameworks/CoreText/fontconfig/fonts.conf searches /System/Library/Fonts
    #    (plus /Library/Fonts, ~/Library/Fonts, xdg fonts, ~/.fonts), and AppKit's
    #    O2Font_FT.m hardcodes /System/Library/Fonts/TTF/NimbusSans-Regular.ttf as
    #    its fallback face. The repo ships the font set in SystemLibrary/Fonts
    #    (TTF/*.ttf plus Inter.ttc), so stage that tree at the path fontconfig
    #    searches. Nothing is taken from the host.
    font_root = os.path.join(REPO, "SystemLibrary", "Fonts")
    if os.path.isdir(font_root):
        # Only font files, not the Makefile that installs them (or any other
        # non-font file the directory happens to carry).
        n_fonts = 0
        for dirpath, dirnames, filenames in os.walk(font_root):
            dirnames.sort()
            for name in sorted(filenames):
                if not name.lower().endswith((".ttf", ".otf", ".ttc")):
                    continue
                src = os.path.join(dirpath, name)
                rel = os.path.relpath(src, font_root).replace(os.sep, "/")
                entries.append({
                    "path": "System/Library/Fonts/" + rel,
                    "file": manifest_source(os.path.realpath(src)),
                    "comment": "font from the repo's SystemLibrary/Fonts",
                })
                n_fonts += 1
        closure.append(("System/Library/Fonts", font_root,
                        "staged %d files" % n_fonts))
    # 9. CoreData and QuartzCore.  Both are built and staged into the repo SDK
    #    by the closure worker; the manifest must reference them repo-relatively.
    #    QuartzCore is what provides _OBJC_CLASS_$_CALayer, which WindowServer
    #    needs at load time.  (Onyx2D is already staged by the WindowServer
    #    closure and its entry already points at the repo SDK, so adding it here
    #    would duplicate the path.)
    for fw in ("CoreData", "QuartzCore"):
        rel = "System/Library/Frameworks/%s.framework/Versions/A/%s" % (fw, fw)
        src = os.path.join(SDK, "System", "Library", "Frameworks",
                           fw + ".framework", "Versions", "A", fw)
        if not os.path.isfile(src):
            closure.append((rel, src, "MISSING"))
            continue
        entries.append({
            "path": rel,
            "file": manifest_source(os.path.realpath(src)),
            "comment": "%s from the repo SDK" % fw,
        })
        closure.append((rel, src, "staged"))

    # 10. /etc/bootstrap and /etc/rc.  launchctl's System session calls
    #     /etc/bootstrap before loading LaunchDaemons and runs /etc/rc after
    #     (BSD/bin/launchctl/launchctl.c: system_specific_bootstrap() does
    #     system("/etc/bootstrap"); runcom() does execl(/bin/sh, "sh", "/etc/rc")).
    #     Both are absent from the image, so the session aborts with
    #     "sh: cannot open /etc/rc" and the agent scan that starts Dock and Filer
    #     never runs.  The image is a pre-built, already-mounted root, so the
    #     correct minimal content is a script that clears the only stale runtime
    #     state (/etc/bootstrap) and one that reports and returns success
    #     (/etc/rc) -- see the comments in the scripts themselves.
    entries.append({
        "path": "etc/bootstrap",
        "text": ETC_BOOTSTRAP,
        "comment": "system bootstrap, run by launchctl's System session before LaunchDaemons",
    })
    entries.append({
        "path": "etc/rc",
        "text": ETC_RC,
        "comment": "system rc, run by launchctl's System session after LaunchDaemons",
    })

    # Dedupe: collapse benign duplicates (same path, same file) to one entry.
    # A genuine conflict (same path, DIFFERENT file) is a real error and exits.
    by_path = {}
    for e in entries:
        p = e["path"]
        if p in by_path:
            if by_path[p].get("file") != e.get("file"):
                sys.exit("conflicting manifest entries for %s: %s vs %s"
                         % (p, by_path[p].get("file"), e.get("file")))
        else:
            by_path[p] = e
    entries = list(by_path.values())
    paths = [e["path"] for e in entries]
    dupes = sorted({p for p in paths if paths.count(p) > 1})
    if dupes:
        sys.exit("duplicate manifest paths: %r" % dupes)

    out = {
        "volume": base.get("volume", "RAVYNOS"),
        "comment": base.get("comment", []) + [
            "",
            "GUI ADDENDUM (make_gui_manifest.py): the cpmv entry that staged",
            "System/Library/CoreServices/WindowServer.app as work/WindowServer.app.tar.gz",
            "is dropped -- a gzip tarball at the path launchd execs cannot run, and no",
            "framework dylibs were staged.  This manifest stages the real bundle tree",
            "(every regular file, symlinks flattened) plus WindowServer's transitive",
            "dylib closure at Darwin install paths, plus the Dock/Filer LaunchAgents.",
            "It also emits the var/tmp/private directory tree launchd needs: with",
            "no /var/log a job's stdio redirect cannot be opened and the job does",
            "not start, and syslogd cannot bind /var/run/log.",
        ],
        "dirs": DIRS,
        "files": entries,
    }
    with open(args.out, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    missing = [c for c in closure if c[2] == "MISSING"]
    print("wrote %s" % args.out)
    print("  bundle files staged: %d" % n_bundle)
    print("  total file entries: %d" % len(entries))
    print("  closure:")
    for inst, src, status in closure:
        line = "    %-64s %s" % (inst, status)
        if src:
            line += "  <- %s" % src
        print(line)
    if missing:
        print("  MISSING (%d):" % len(missing))
        for inst, _, _ in missing:
            print("    %s" % inst)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
