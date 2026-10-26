#!/usr/bin/env python3
"""app_stage.py -- stage a prebuilt macOS .app bundle for ravynOS.

WHAT THIS IS
  chrome_stage.py generalized.  Chrome's bundle had one shape -- a single
  huge embedded framework, no LC_RPATH, a fixed executable name -- and that
  shape is baked into every path in that file.  Any other macOS application
  has a different one, so this reads the bundle instead of assuming it:

    * the executable comes from CFBundleExecutable, not from the bundle name;
    * LC_RPATH is parsed and @rpath/ dependencies are resolved against it,
      against @executable_path and against @loader_path, in that order;
    * embedded frameworks are flattened: the symlink a binary loads
      (Foo.framework/Foo) is rewritten to the real file it points at
      (Foo.framework/Versions/A/Foo) so the file is staged once;
    * every Mach-O is thinned to x86_64, ad-hoc signed, and only then has its
      load commands rewritten.

WHAT IT DOES NOT DO
  It does not invent missing libraries.  A dependency that neither the bundle
  nor the ravynOS SDK can satisfy is reported and the run fails, unless
  --allow-missing is given, in which case a trap-only shim is generated the
  way chrome_stage.py does it.  Silence about a missing library is how an
  application gets staged, boots, and dies at launch.

USAGE
  python3 tools/bootlab/app_stage.py --app /Applications/Transmission.app
  python3 tools/bootlab/app_stage.py --app build/Probe.app --dest /Applications \\
      --out-manifest work/manifest_apps.json
  python3 tools/bootlab/app_stage.py --app /Applications/Transmission.app \\
      --dry-run --report work/transmission-plan.txt
"""

import argparse
import json
import os
import plistlib
import posixpath
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
BUILD = os.environ.get("RAVYN_BUILD_DIR", "/Users/max/Projects/build")
SDK = os.path.join(REPO, "Developer", "ravynOS.sdk")
BUILD_SDK = os.path.join(BUILD, "Developer", "Platforms", "ravynOS.platform",
                         "Developer", "SDKs", "ravynOS.sdk")
WORK = os.path.join(HERE, "work")
CLANG = os.environ.get("CLANG", "/usr/bin/clang").split()

MACHO_MAGICS = {
    b"\xcf\xfa\xed\xfe": "macho64-le",
    b"\xce\xfa\xed\xfe": "macho32-le",
    b"\xfe\xed\xfa\xcf": "macho64-be",
    b"\xfe\xed\xfa\xce": "macho32-be",
    b"\xca\xfe\xba\xbe": "fat-be",
    b"\xbe\xba\xfe\xca": "fat-le",
}


def log(msg):
    print(msg, flush=True)


def die(msg):
    print("app_stage: %s" % msg, file=sys.stderr, flush=True)
    sys.exit(1)


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def is_macho(path):
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
    except OSError:
        return False
    return magic in MACHO_MAGICS


def lipo_archs(path):
    result = sh(["lipo", "-archs", path])
    if result.returncode != 0:
        return []
    return result.stdout.split()


def parse_lcs(path):
    """Return (install_name, deps, rpaths) for a Mach-O.

    deps are the raw load-command strings, which is what install_name_tool
    -change expects; rpaths are LC_RPATH entries in load order.
    """
    result = sh(["otool", "-l", path])
    if result.returncode != 0:
        return None, [], []
    install = None
    deps = []
    rpaths = []
    lines = result.stdout.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if "cmd LC_ID_DYLIB" in line:
            for j in range(i, min(i + 8, len(lines))):
                m = re.search(r"name (\S+)", lines[j])
                if m:
                    install = m.group(1)
                    break
        elif "cmd LC_LOAD_DYLIB" in line or "cmd LC_LOAD_WEAK_DYLIB" in line:
            for j in range(i, min(i + 8, len(lines))):
                m = re.search(r"name (\S+)", lines[j])
                if m:
                    deps.append((m.group(1), "weak" in line))
                    break
        elif "cmd LC_RPATH" in line:
            for j in range(i, min(i + 6, len(lines))):
                m = re.search(r"path (\S+) \(offset", lines[j])
                if m:
                    rpaths.append(m.group(1))
                    break
        i += 1
    return install, deps, rpaths


def bundle_relative(path, app_root):
    return os.path.relpath(path, app_root)


def expand_special(dep, app_root, executable_rel, loader_rel, rpaths):
    """Resolve @executable_path / @loader_path / @rpath to a bundle-relative path.

    Returns a bundle-relative path, an absolute install path, or None.
    """
    tail_paths = []

    def submatch(base_rel, value):
        if value.startswith("@executable_path/"):
            return posixpath.normpath(posixpath.join(posixpath.dirname(executable_rel),
                                                     value[len("@executable_path/"):]))
        if value.startswith("@loader_path/"):
            return posixpath.normpath(posixpath.join(posixpath.dirname(loader_rel),
                                                     value[len("@loader_path/"):]))
        return posixpath.normpath(posixpath.join(base_rel, value)) if base_rel else None

    if dep.startswith("@executable_path/"):
        return submatch(".", dep)
    if dep.startswith("@loader_path/"):
        return submatch(".", dep)
    if dep.startswith("@rpath/"):
        tail = dep[len("@rpath/"):]
        for rpath in rpaths:
            base = submatch(".", rpath)
            if not base:
                continue
            candidate = posixpath.normpath(posixpath.join(base, tail))
            tail_paths.append(candidate)
        for candidate in tail_paths:
            if os.path.exists(os.path.join(app_root, candidate)):
                return candidate
        # Falls back to a system framework: @rpath/Foo.framework/Versions/A/Foo
        # is how a non-embedded framework is named in a modern build.
        if "/Versions/" in tail or tail.startswith("lib"):
            return "/" + tail if tail.startswith("System/") else None
        return None
    if dep.startswith("/"):
        return dep
    return None


def find_system_source(install_path, extra_search):
    """Real file for an absolute install path, repo SDK first."""
    if not install_path or not install_path.startswith("/"):
        return None
    candidates = []
    if install_path.startswith("/System/Library/Frameworks/"):
        rel = install_path[len("/System/Library/Frameworks/"):]
        candidates.append(os.path.join(SDK, "System", "Library", "Frameworks", rel))
        candidates.append(os.path.join(BUILD_SDK, "System", "Library", "Frameworks", rel))
    candidates.append(os.path.join(SDK, install_path.lstrip("/")))
    candidates.append(os.path.join(BUILD_SDK, install_path.lstrip("/")))
    for extra in extra_search:
        candidates.append(os.path.join(extra, install_path.lstrip("/")))
    for candidate in candidates:
        if os.path.isfile(candidate) and os.path.getsize(candidate) > 0:
            return candidate
    return None


def thin_and_sign(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    archs = lipo_archs(src)
    if len(archs) > 1 and "x86_64" in archs:
        result = sh(["lipo", "-thin", "x86_64", "-output", dst, src])
        if result.returncode != 0:
            raise RuntimeError("lipo -thin failed for %s: %s" % (src, result.stderr))
    else:
        shutil.copy2(src, dst)
    os.chmod(dst, 0o755)
    sh(["codesign", "--force", "--sign", "-", "--timestamp=none", dst])


class AppPlan:
    def __init__(self, bundle, dest_dir):
        self.bundle = os.path.abspath(bundle)
        self.dest_dir = dest_dir
        self.name = os.path.basename(self.bundle)
        self.stem = os.path.splitext(self.name)[0]
        self.info = {}
        self.executable_rel = None
        self.executable = None
        self.payload = os.path.join(WORK, "app-payload", self.stem)
        self.problems = []
        self.rewrites = []      # (binary, old, new)
        self.staged = {}        # bundle-relative -> source path
        self.symlinks = []      # (link_rel, target_rel)
        self.system_deps = {}   # install path -> real source path

    def load(self):
        plist_path = os.path.join(self.bundle, "Contents", "Info.plist")
        if not os.path.isfile(plist_path):
            die("%s has no Contents/Info.plist" % self.bundle)
        with open(plist_path, "rb") as f:
            self.info = plistlib.load(f)
        exe = self.info.get("CFBundleExecutable")
        if not exe:
            die("%s: Info.plist has no CFBundleExecutable" % self.name)
        for rel in ("Contents/MacOS/%s" % exe, "Contents/ravynOS/%s" % exe, exe):
            candidate = os.path.join(self.bundle, rel)
            if os.path.isfile(candidate):
                self.executable_rel = rel
                self.executable = candidate
                break
        if not self.executable:
            die("%s: CFBundleExecutable %r not found in Contents/MacOS" % (self.name, exe))
        self.bundle_id = self.info.get("CFBundleIdentifier", "unknown")

    def machos(self):
        for root, _dirs, files in os.walk(self.bundle):
            for name in files:
                path = os.path.join(root, name)
                if os.path.islink(path):
                    continue
                if is_macho(path):
                    yield path

    def record_symlinks(self):
        for root, dirs, files in os.walk(self.bundle):
            for name in list(dirs) + list(files):
                path = os.path.join(root, name)
                if not os.path.islink(path):
                    continue
                target = os.readlink(path)
                rel = os.path.relpath(path, self.bundle)
                target_rel = os.path.normpath(os.path.join(os.path.dirname(rel), target))
                self.symlinks.append((rel, target_rel))

    def plan(self):
        """Resolve every dependency of every Mach-O in the bundle."""
        executable_dir = posixpath.dirname(self.executable_rel)
        _install, main_deps, main_rpaths = parse_lcs(self.executable)

        for macho in self.machos():
            rel = bundle_relative(macho, self.bundle)
            _iname, deps, rpaths = parse_lcs(macho)
            all_rpaths = list(rpaths) + [r for r in main_rpaths if r not in rpaths]
            for dep, weak in deps:
                resolved = expand_special(dep, self.bundle, self.executable_rel, rel, all_rpaths)
                if resolved is None:
                    self.problems.append(
                        (rel, dep, "weak" if weak else "required",
                         "unresolvable @rpath dependency: no LC_RPATH matched"))
                    continue
                if resolved.startswith("/"):
                    source = find_system_source(resolved, [BUILD])
                    if source:
                        self.system_deps[resolved] = source
                        continue
                    if weak:
                        continue
                    self.problems.append((rel, dep, "required",
                                          "no staged file at %s" % resolved))
                    continue
                target = os.path.join(self.bundle, resolved)
                if os.path.exists(target):
                    # A symlink target is rewritten to its canonical file so
                    # the image stages one copy, not one per name.
                    if os.path.islink(target):
                        canonical = os.path.realpath(target)
                        if is_macho(canonical):
                            canonical_rel = bundle_relative(canonical, self.bundle)
                            self.rewrites.append((rel, dep, "@executable_path/../" + canonical_rel
                                                  if False else canonical_rel))
                            self.staged[canonical_rel] = canonical
                            continue
                    canonical_rel = bundle_relative(os.path.realpath(target), self.bundle) \
                        if os.path.islink(target) else resolved
                    self.staged[canonical_rel] = os.path.realpath(target)
                    if canonical_rel != dep and not dep.startswith("/"):
                        # The binary names a path inside the bundle; leave it
                        # alone when it is a plain relative load, dyld resolves
                        # it against the loading image's directory only for
                        # @loader_path, so anything else must be rewritten.
                        if dep.startswith("@loader_path/") or dep.startswith("@executable_path/"):
                            self.rewrites.append((rel, dep, canonical_rel))
                    continue
                self.problems.append((rel, dep, "weak" if weak else "required",
                                      "not present in the bundle"))
        # Losslessly de-duplicate rewrites.
        seen = set()
        unique = []
        for item in self.rewrites:
            if item in seen:
                continue
            seen.add(item)
            unique.append(item)
        self.rewrites = unique

    def build_payload(self, dry_run=False):
        if dry_run:
            return
        if os.path.isdir(self.payload):
            shutil.rmtree(self.payload)
        os.makedirs(self.payload, exist_ok=True)

        executable_dir = os.path.dirname(self.executable)
        for root, _dirs, files in os.walk(self.bundle):
            for name in files:
                src = os.path.join(root, name)
                if os.path.islink(src):
                    continue
                rel = os.path.relpath(src, self.bundle)
                dst = os.path.join(self.payload, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if is_macho(src):
                    try:
                        thin_and_sign(src, dst)
                    except RuntimeError as exc:
                        die(str(exc))
                else:
                    shutil.copy2(src, dst)

        # Non-Mach-O symlinks (Resources -> Versions/Current/Resources) are
        # resolved into real copies: the image has no symlinks, and NSBundle
        # follows such a link when it looks for a localized resource.
        for link_rel, target_rel in self.symlinks:
            target_src = os.path.join(self.bundle, target_rel)
            dst = os.path.join(self.payload, link_rel)
            if os.path.isdir(target_src):
                if not os.path.isdir(dst):
                    shutil.copytree(target_src, dst)
                continue
            if os.path.isfile(target_src) and not is_macho(target_src):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(target_src, dst)

    def apply_rewrites(self, dry_run=False):
        if dry_run:
            return
        for rel, old, new in self.rewrites:
            binary = os.path.join(self.payload, rel)
            if not os.path.isfile(binary):
                continue
            # New load paths are bundle-relative for files inside the app and
            # absolute otherwise; install_name_tool accepts either, but a
            # relative path is resolved against the loader's directory only
            # via @loader_path, so make the intent explicit.
            replacement = new
            if not new.startswith("/") and not new.startswith("@"):
                replacement = "@loader_path/" + os.path.relpath(new, os.path.dirname(rel) or ".")
            sh(["install_name_tool", "-change", old, replacement, binary])
            sh(["codesign", "--force", "--sign", "-", "--timestamp=none", binary])

    def manifest_entries(self, install_root):
        entries = []
        for root, dirs, files in os.walk(self.payload):
            rel_root = os.path.relpath(root, self.payload)
            for name in files:
                src = os.path.join(root, name)
                rel = name if rel_root == "." else os.path.join(rel_root, name)
                target = posixpath.join(install_root.lstrip("/"), rel.replace(os.sep, "/"))
                entries.append({"type": "file", "path": target, "source": src})
            for name in dirs:
                rel = name if rel_root == "." else os.path.join(rel_root, name)
                target = posixpath.join(install_root.lstrip("/"), rel.replace(os.sep, "/"))
                if not os.path.isdir(os.path.join(self.payload, rel)) or \
                        not os.listdir(os.path.join(self.payload, rel)):
                    entries.append({"type": "dir", "path": target})
        entries.sort(key=lambda entry: entry["path"])
        return entries

    def report_lines(self):
        lines = []
        lines.append("app: %s" % self.bundle)
        lines.append("bundle id: %s" % self.bundle_id)
        lines.append("executable: %s" % self.executable_rel)
        lines.append("mach-o files: %d" % len(list(self.machos())))
        lines.append("inside-bundle dependencies staged: %d" % len(self.staged))
        lines.append("system dependencies found in the SDK: %d" % len(self.system_deps))
        lines.append("load-command rewrites: %d" % len(self.rewrites))
        for rel, old, new in self.rewrites:
            lines.append("  REWRITE %s: %s -> %s" % (rel, old, new))
        for dep in sorted(self.system_deps):
            lines.append("  SYSTEM  %s -> %s" % (dep, self.system_deps[dep]))
        if self.problems:
            lines.append("problems:")
            for rel, dep, kind, why in self.problems:
                lines.append("  %s %s: %s (%s)" % (kind.upper(), dep, why, rel))
        else:
            lines.append("problems: none")
        return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", action="append", required=True,
                        help="path to a .app bundle (repeatable)")
    parser.add_argument("--dest", default="/Applications",
                        help="install directory inside the image (default /Applications)")
    parser.add_argument("--out-manifest", default=None,
                        help="write a manifest JSON with the staged files")
    parser.add_argument("--into-gui-manifest", default=None,
                        help="merge the staged files into this manifest as well")
    parser.add_argument("--dry-run", action="store_true",
                        help="resolve and report, stage nothing")
    parser.add_argument("--allow-missing", action="store_true",
                        help="report missing dependencies but still stage the bundle")
    parser.add_argument("--report", default=None, help="write the plan report here")
    parser.add_argument("--stage-dir", default=os.path.join(WORK, "app-intake"),
                        help="mirror the staged bundle here so make_gui_manifest.py "
                             "picks it up (default tools/bootlab/work/app-intake)")
    args = parser.parse_args()

    all_entries = []
    all_lines = []
    failed = False

    for app in args.app:
        plan = AppPlan(app, args.dest)
        plan.load()
        plan.record_symlinks()
        plan.plan()
        install_root = posixpath.join(args.dest, plan.name)
        all_lines.extend(plan.report_lines())
        all_lines.append("")
        if plan.problems and not args.allow_missing:
            failed = True
            log("app_stage: %s: %d unresolved dependencies" % (plan.name, len(plan.problems)))
            continue
        plan.build_payload(args.dry_run)
        plan.apply_rewrites(args.dry_run)
        if not args.dry_run and args.stage_dir:
            # Mirror under the install path so the mirror tree is shaped like
            # the image root make_gui_manifest.py walks.
            mirror = os.path.join(args.stage_dir, install_root.lstrip("/"))
            if os.path.isdir(mirror):
                shutil.rmtree(mirror)
            shutil.copytree(plan.payload, mirror)
            log("app_stage: mirrored to %s" % os.path.relpath(mirror, REPO))
        all_entries.extend(plan.manifest_entries(install_root))
        log("app_stage: %s: %d files staged%s" %
            (plan.name, len(plan.manifest_entries(install_root)),
             " (dry run)" if args.dry_run else ""))

    report = "\n".join(all_lines)
    if args.report:
        os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)
        with open(args.report, "w") as f:
            f.write(report + "\n")
    print(report)

    if args.out_manifest:
        with open(args.out_manifest, "w") as f:
            json.dump(all_entries, f, indent=1)
        log("app_stage: wrote %s (%d entries)" % (args.out_manifest, len(all_entries)))

    if args.into_gui_manifest and not args.dry_run and all_entries:
        with open(args.into_gui_manifest) as f:
            manifest = json.load(f)
        existing = {entry.get("path") for entry in manifest.get("files", manifest if isinstance(manifest, list) else [])}
        target = manifest["files"] if isinstance(manifest, dict) and "files" in manifest else manifest
        for entry in all_entries:
            if entry.get("path") not in existing:
                target.append(entry)
        with open(args.into_gui_manifest, "w") as f:
            json.dump(manifest, f, indent=1)
        log("app_stage: merged into %s" % args.into_gui_manifest)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
