#!/usr/bin/env python3
"""chrome_stage.py -- stage Google Chrome's bundle and generate its dyld closure.

WHAT THIS PRODUCES
  work/chrome-payload/   the app's Contents tree, x86_64-thinned, adhoc-signed,
                         load commands rewritten for deps the guest already
                         stages somewhere else
  work/chrome-shims/     one generated dylib per dependency the guest cannot
                         provide, staged at the exact path Chrome loads it from
  work/chrome_plan.json  machine-readable plan (per binary, per dep)
  work/chrome_report.txt human-readable report, including the push loop's
                         worklist of trapped symbols

RULES (each is load-bearing; see BOOT-PLAN.md 22)
  * Every chained-fixup bind is resolved eagerly at launch, so each image must
    exist at its exact load path and every non-weak import must resolve in it.
  * The host's macOS frameworks are dyld-shared-cache-only: "real" files can
    only come from the repo SDK or the build tree SDK.
  * Occupied dep (the guest already stages a file at P) -> the shim goes to a
    SIDE path S(P) and Chrome's own binaries are rewritten to load S(P).  The
    guest's file is never touched.
  * Unoccupied dep with a real file -> the shim is staged AT P and re-exports
    the real image.  If the real image's install name is not itself staged the
    file is copied to /usr/lib/chrome/real/<Base>.dylib with a rewritten -id,
    because dyld would otherwise be asked for an image path that does not exist.
  * No real file -> trap-only stub at P: every imported symbol is defined
    (functions log once and return 0, other data is a zeroed slot, ObjC
    classes become fake classes so messaging one fails loudly rather than
    silently nil).  A missing symbol must never abort the launch.
"""
import collections
import hashlib
import io
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
APP = "/Applications/Google Chrome.app"
BUILD = os.environ.get("RAVYN_BUILD_DIR", "/Users/max/Projects/build")
SDK = os.path.join(REPO, "Developer", "ravynOS.sdk")
BUILD_SDK = os.path.join(BUILD, "Developer", "Platforms", "ravynOS.platform",
                         "Developer", "SDKs", "ravynOS.sdk")
WORK = os.path.join(HERE, "work")
PAYLOAD = os.path.join(WORK, "chrome-payload")
SHIMS = os.path.join(WORK, "chrome-shims")
OBJ = os.path.join(WORK, "chrome-stage-obj")
THINNED_MAIN = os.path.join(WORK, "chrome_thinned")
BASE_MANIFEST = os.path.join(HERE, "manifest_gui.json")
PLAN_JSON = os.path.join(WORK, "chrome_plan.json")
REPORT = os.path.join(WORK, "chrome_report.txt")
CLANG = os.environ.get("CLANG", "xcrun clang").split()

MAIN_REL = "MacOS/Google Chrome"
CONTENTS_STAGE = "Applications/Google Chrome.app/Contents"
MAIN_STAGE = CONTENTS_STAGE + "/" + MAIN_REL
INFO_STAGE = CONTENTS_STAGE + "/Info.plist"
FRAMEWORK_REL = "Frameworks/Google Chrome Framework.framework"
REAL_DIR = "/usr/lib/chrome/real"
SIDE_DIR = "/usr/lib/chrome"


def chrome_version():
    """The framework version the installed launcher actually loads.

    Chrome's launcher binary hardcodes the framework path
    ("../Frameworks/Google Chrome Framework.framework/Versions/<v>/Google
    Chrome Framework"), and the updater leaves the previous version's
    directory behind.  Staging the wrong version means the launcher cannot
    find the framework at all, so the version is read from the launcher
    instead of being pinned in this script."""
    launcher = os.path.join(APP, "Contents", MAIN_REL)
    try:
        with open(launcher, "rb") as f:
            blob = f.read()
    except OSError:
        blob = b""
    m = re.search(rb"Google Chrome Framework\.framework/Versions/"
                   rb"([0-9][0-9A-Za-z._-]*)/", blob)
    if m:
        return m.group(1).decode()
    cur = os.path.join(APP, "Contents", FRAMEWORK_REL, "Versions", "Current")
    if os.path.islink(cur):
        return os.path.basename(os.readlink(cur))
    die("cannot determine the installed Chrome framework version")


VER = chrome_version()


def stale_version_prefixes():
    """Framework version directories that are NOT the one the launcher loads.

    Chrome's updater leaves the previous version's directory in place.
    Staging it would double the payload and put two frameworks with the same
    class names into the guest."""
    base = os.path.join(APP, "Contents", FRAMEWORK_REL, "Versions")
    out = []
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return out
    for v in names:
        if v in (VER, "Current"):
            continue
        out.append(FRAMEWORK_REL + "/Versions/" + v)
    return out


MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe",
                b"\xbe\xba\xfe\xca", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce")

FUNC_SECTIONS = {"__got", "__auth_got", "__stubs", "__la_symbol_ptr"}
WORKLIST_CAP = 40               # trap symbols printed per dep in the report
# Max staged provider images a dependency may re-export.  The measured worst
# case is 4 (CoreFoundation); the cap exists only so a pathological closure
# cannot produce an unbounded link line, and exceeding it is a hard error
# rather than a silent truncation.
PROVIDER_EDGE_CAP = 8

# Session-measured missing-symbol counts for the framework binary (the numbers
# this script's import/export walk must reproduce; a diff is reported loudly).
EXPECTED_FRAMEWORK_MISSING = {"AppKit": 103, "CoreText": 59, "CoreGraphics": 56,
                              "CoreFoundation": 50, "Foundation": 27,
                              "QuartzCore": 14, "IOSurface": 0, "libobjc": 0}

REPORT_LINES = []


def log(msg):
    print(msg)
    REPORT_LINES.append(msg)


def die(msg):
    sys.exit("FATAL: %s" % msg)


def sh(cmd, check=True):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode != 0:
        die("%s -> rc=%d\n%s%s" % (" ".join(cmd), r.returncode, r.stdout, r.stderr))
    return r.stdout


def sh_both(cmd):
    """stdout+stderr: codesign writes its .dv report to stderr."""
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def codesign_dv(path):
    return sh_both(["codesign", "-dv", path])[1]


def is_dylib(path):
    """True for a shared library Mach-O -- the only file types ld64 accepts as
    a -reexport_library operand.  Staged app bundles carry MH_EXECUTABLE images
    (WindowServer, Dock, ...) that export ObjC class names too; offering one as
    a provider makes ld die with "unsupported mach-o filetype"."""
    r = subprocess.run(["file", "-b", path], capture_output=True, text=True)
    return "dynamically linked shared library" in (r.stdout or "")


def is_macho(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) in MACHO_MAGICS
    except OSError:
        return False


def lipo_archs(path):
    out = sh(["lipo", "-info", path], check=False)
    m = re.search(r"are: (.+)$", out)
    if m:
        return m.group(1).split()
    m = re.search(r"architecture: (\S+)", out)      # "Non-fat file: ... is architecture: arm64"
    return [m.group(1)] if m else []


# ---------------------------------------------------------------- mach-o info

_OTOOL_LINKS = {}


def otool_path(path):
    """A link otool can open for `path`.

    otool parses a trailing "(...)" as an archive member name, so Chrome's
    helper binaries ("... Helper (Alerts)") are unreadable by it: hand otool a
    space/paren-free symlink instead."""
    if "(" not in os.path.basename(path):
        return path
    link = _OTOOL_LINKS.get(path)
    if link is None:
        links_dir = os.path.join(OBJ, "links")
        os.makedirs(links_dir, exist_ok=True)
        link = os.path.join(links_dir, "l%d" % len(_OTOOL_LINKS))
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink(os.path.abspath(path), link)
        _OTOOL_LINKS[path] = link
    return link


def parse_lcs(path):
    """[(kind, name)] for LC_LOAD_DYLIB / LC_REEXPORT_DYLIB /
    LC_LOAD_WEAK_DYLIB / LC_LOAD_UPWARD_DYLIB, self-install-names dropped.  Weak load commands still
    need a real image in this guest: Chrome's framework weak-links SkyLight and ScreenCaptureKit, and the staged
    dyld2 printed "could not find image <path>" for exactly those two before crashing (rc=139), so they get trap-only
    stubs like any other absent dep -- only their *weak import symbols* may stay unresolved, never the image itself.

    Parsed one "Load command" block at a time: a whole-output regex matches
    across command boundaries when an install name contains a space (Chrome's
    framework ID does), and then mistakes a later dependency for the file's
    own ID."""
    out = sh(["otool", "-arch", "x86_64", "-l", otool_path(path)])
    entries = []
    for block in re.split(r"\n(?=Load command \d+)", out):
        m = re.search(r"cmd (LC_(?:LOAD_WEAK|LOAD_UPWARD|REEXPORT|LOAD|ID)_DYLIB)\b", block)
        if not m:
            continue
        n = re.search(r"\n\s*name (.+?) \(offset \d+\)", block)
        if n:
            # "LC_REEXPORT_DYLIB" -> "REEXPORT": callers compare the short form
            entries.append((m.group(1)[3:-6], n.group(1)))
    ids = {name for kind, name in entries if kind == "ID"}
    return [(kind, name) for kind, name in entries
            if kind != "ID" and name not in ids]


def install_name(path):
    out = sh(["otool", "-arch", "x86_64", "-D", otool_path(path)], check=False)
    lines = [l.strip() for l in out.splitlines()
             if l.strip() and not l.endswith(":")]
    return lines[-1] if lines else None


def short_name(dep):
    """dyld_info's (from X) for a path: leaf, minus .dylib, minus one more
    dotted component (libobjc.A.dylib -> libobjc, libbz2.1.0.dylib -> libbz2.1,
    AppKit -> AppKit)."""
    leaf = os.path.basename(dep)
    if leaf.endswith(".dylib"):
        leaf = leaf[:-len(".dylib")]
    if "." in leaf:
        leaf = leaf.rsplit(".", 1)[0]
    return leaf


def imports_by_short(path):
    """({short: set(symbol)}, {pseudo symbols}) for non-weak imports.

    `[weak-import]` symbols need no definition (they resolve to NULL), and a
    `(from <pseudo>)` short is dyld_info's marker for a symbol this image
    itself defines weakly (Rust's alloc-shim, `<weak-def-coalesce>`) -- not an
    import from a dylib, so neither is a missing-symbol candidate."""
    out = sh(["dyld_info", "-arch", "x86_64", "-imports", path])
    d = collections.defaultdict(set)
    pseudo = set()
    for line in out.splitlines():
        m = re.match(r"\s*0x[0-9A-Fa-f]+\s+(\S+)( \[weak-import\])?\s+"
                     r"\(from (.+)\)\s*$", line)
        if not m or m.group(2):
            continue
        if m.group(3).startswith("<"):
            pseudo.add(m.group(1))
            continue
        d[m.group(3)].add(m.group(1))
    return d, pseudo


def exports_of(path):
    """Exported symbols as dyld2 will see them.

    `dyld_info -exports` prints two shapes: offset-bearing definitions
    (`0x1f30  _foo`) and indirect trie entries (`[re-export] _strcmp
    (__platform_strcmp from libsystem_platform)` -- nm calls those
    `I _strcmp (indirect for ...)`).  Only honouring the first shape makes
    every indirect export look missing, so it becomes a trap that SHADOWS
    the real symbol (a stub `_strlen` returning 0 segfaults Chrome).  Union
    with `nm -gU` so both views of the same export trie are honored.
    """
    out = sh(["dyld_info", "-arch", "x86_64", "-exports", path], check=False)
    syms = set()
    for line in out.splitlines():
        m = re.match(r"\s*0x[0-9A-Fa-f]+\s+(\S+)", line)
        if m:
            syms.add(m.group(1))
            continue
        m = re.match(r"\s*\[re-export\]\s+(\S+)", line)
        if m:
            syms.add(m.group(1))
    nmo = sh(["nm", "-gU", path], check=False)
    for line in nmo.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-2] in ("T", "S", "D", "B", "C", "R", "I", "W", "V"):
            syms.add(parts[-1])
    return syms


def fixup_sections(path):
    """{symbol: set(sections)} from dyld_info -fixups bind sites."""
    out = sh(["dyld_info", "-arch", "x86_64", "-fixups", path], check=False)
    d = collections.defaultdict(set)
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 5 and parts[3] == "bind" and "/" in parts[4]:
            d[parts[4].split("/", 1)[1].split(" ")[0]].add(parts[1])
    return d


# ------------------------------------------------------------------- base map

def base_map():
    """{lowercased staged path: source file or None} from manifest_gui.json."""
    with open(BASE_MANIFEST) as f:
        man = json.load(f)
    staged, sources = {}, {}
    for e in man["files"]:
        p = e["path"].lower()
        staged[p] = True
        src = e.get("file")
        if src:
            if not os.path.isabs(src):
                src = os.path.join(HERE, src)
            sources[p] = src
    return staged, sources


# --------------------------------------------------------------- payload tree

def thin_and_sign(src, dst):
    """Copy one file: Mach-O -> x86_64 thin + adhoc signature, else bytes."""
    if is_macho(src):
        arches = lipo_archs(src)
        if "x86_64" not in arches:
            die("%s: no x86_64 slice (%s)" % (src, arches))
        if len(arches) > 1:
            sh(["lipo", "-thin", "x86_64", "-output", dst, src])
        else:
            shutil.copyfile(src, dst)
        sh(["codesign", "--force", "--sign", "-", dst])
        dvinfo = codesign_dv(dst)
        if "flags=0x2(adhoc)" not in dvinfo:
            die("%s: re-sign did not produce adhoc flags:\n%s" % (dst, dvinfo))
    else:
        shutil.copyfile(src, dst)


def build_payload(staged):
    if os.path.isdir(PAYLOAD):
        shutil.rmtree(PAYLOAD)
    os.makedirs(PAYLOAD)
    root = os.path.join(APP, "Contents")
    machos, files = [], []
    stale = stale_version_prefixes()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames
                             if d != "_CodeSignature"
                             and not any(os.path.join(dirpath, d).endswith(p)
                                         for p in stale))
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, root).replace(os.sep, "/")
            if any(rel.startswith(p) for p in stale):
                continue                    # previous Chrome version's tree
            if name == "CodeResources" or name.endswith(".sig") \
                    or name == "embedded.provisionprofile":
                continue
            if os.path.islink(src):
                # FAT32 has no symlinks and nothing links these aliases
                # (the framework's Versions/Current and the unversioned
                # "Google Chrome Framework" alias): skip rather than stage a
                # second 260 MiB copy of the framework binary.
                log("payload: skipping symlink %s -> %s"
                    % (rel, os.readlink(src)))
                continue
            stage = (CONTENTS_STAGE + "/" + rel).lower()
            if stage in staged:
                continue                    # Info.plist, MacOS/Google Chrome
            dst = os.path.join(PAYLOAD, rel)
            if is_macho(src):
                arches = lipo_archs(src)
                if "x86_64" not in arches:
                    # The guest dyld is x86_64-only: an arm64 slice cannot be
                    # loaded at all, so stage nothing rather than something
                    # that fails at dlopen (WidevineCdm/mac_arm64).
                    log("payload: skipping non-x86_64 Mach-O %s (%s)"
                        % (rel, ",".join(arches)))
                    continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            thin_and_sign(src, dst)
            files.append(rel)
            if is_macho(dst):
                machos.append(rel)
    # codesign(1) writes a _CodeSignature/CodeResources pair into every .app it
    # signs.  Those are stale signatures for this payload and the walk above
    # deliberately stages none of them, so drop them before reporting.
    strays = [dp for dp, dn, fn in os.walk(PAYLOAD)
              if os.path.basename(dp) == "_CodeSignature"]
    for dp in strays:
        shutil.rmtree(dp)
    if strays:
        log("payload: removed %d codesign _CodeSignature dirs" % len(strays))
    log("payload: %d files (%d Mach-O), %.1f MiB on disk"
        % (len(files), len(machos),
           sum(os.path.getsize(os.path.join(PAYLOAD, f)) for f in files) / 1048576.0))
    return files, machos


def ensure_thinned_main():
    """Re-thin the launcher when the installed one changed.

    Chrome's updater replaces Contents/MacOS/Google Chrome, and that binary
    hardcodes the framework version it loads
    ("../Frameworks/Google Chrome Framework.framework/Versions/<v>/Google
    Chrome Framework").  A stale staged launcher therefore asks the guest for
    a version directory that was never staged, and the run dies with
    "dyld: could not find image .../Versions/<old-v>/Google Chrome Framework"
    before any of the closure work matters.  The source's digest is recorded
    next to the copy so the check survives an equal-mtime copy."""
    src = os.path.join(APP, "Contents", MAIN_REL)
    stamp = THINNED_MAIN + ".src.md5"
    try:
        with open(src, "rb") as f:
            want = hashlib.md5(f.read()).hexdigest()
    except OSError:
        want = None
    have = None
    if os.path.isfile(stamp):
        with open(stamp) as f:
            have = f.read().strip()
    if (want is not None and have == want and os.path.isfile(THINNED_MAIN)
            and "flags=0x2(adhoc)" in codesign_dv(THINNED_MAIN)):
        return
    log("rebuilding work/chrome_thinned from %s" % src)
    thin_and_sign(src, THINNED_MAIN)
    if want is not None:
        with open(stamp, "w") as f:
            f.write(want + "\n")


def ensure_info_plist():
    """Regenerate work/chrome_info.plist from the installed app's Info.plist.

    The guest needs one thing the host plist does not have:
    RAVYNLaunchArguments -- the launch arguments this guest can actually
    honour (no sandbox, no GPU, no first-run wizard, a writable profile
    directory).  Everything else is the host's, so the app's own metadata
    (version, bundle identifiers, capabilities) stays true; a stale copy
    would report a version the staged framework does not have."""
    src = os.path.join(APP, "Contents", "Info.plist")
    dst = os.path.join(WORK, "chrome_info.plist")
    with open(src, "rb") as f:
        pl = plistlib.load(f)
    pl["RAVYNLaunchArguments"] = ["--no-sandbox", "--disable-gpu",
                                  "--no-first-run",
                                  "--user-data-dir=/tmp/chrome-profile"]
    buf = io.BytesIO()
    plistlib.dump(pl, buf)
    new = buf.getvalue()
    old = None
    if os.path.isfile(dst):
        with open(dst, "rb") as f:
            old = f.read()
    if old == new:
        return
    log("regenerating work/chrome_info.plist from %s" % src)
    with open(dst, "wb") as f:
        f.write(new)


# ------------------------------------------------------------------ dep graph

def find_real(path):
    """A host Mach-O for the install path, or None.

    Literal path in the build SDK then the repo SDK; then, for a framework
    path, any Versions/<dir> of the same bundle -- the SDK keeps AppKit under
    Versions/A while macOS binaries link Versions/C."""
    for root in (BUILD_SDK, SDK):
        cand = os.path.join(root, path.lstrip("/"))
        if os.path.isfile(cand) and is_macho(cand):
            return cand
    if ".framework/" in path:
        bundle, tail = path.split(".framework/", 1)
        leaf = posixpath.basename(tail)
        for root in (BUILD_SDK, SDK):
            vroot = os.path.join(root, (bundle + ".framework").lstrip("/"),
                                 "Versions")
            if not os.path.isdir(vroot):
                continue
            for v in sorted(os.listdir(vroot)):
                cand = os.path.join(vroot, v, leaf)
                if os.path.isfile(cand) and is_macho(cand):
                    return cand
    return None


class Closure:
    """Everything known about the dep set: classification, placement, traps."""

    def __init__(self, staged, sources, files, machos):
        self.staged = staged                  # base manifest: lower(path) -> True
        self.sources = sources                # base manifest: lower(path) -> file
        self.payload_paths = {                       # lower(staged) -> host file
            (CONTENTS_STAGE + "/" + rel).lower():
                os.path.join(PAYLOAD, rel) for rel in files}
        self.binaries = []                    # (staged, host file, label)
        for rel in machos:
            self.binaries.append((CONTENTS_STAGE + "/" + rel,
                                  os.path.join(PAYLOAD, rel), rel))
        self.binaries.append((MAIN_STAGE, THINNED_MAIN, "Contents/" + MAIN_REL))
        self.deps = {}                        # dep path -> record
        self.binary_deps = {}                 # staged binary -> [dep paths]
        self.missing = collections.defaultdict(set)   # dep path -> trapped syms
        self._exp_cache = {}                  # path -> exports closure
        self._exports_cache = {}              # file -> direct exports
        self._lcs_cache = {}                  # file -> [(kind, dep path)]
        self._fixup_cache = {}                # file|dep -> {sym: sections}
        self._real_cache = {}                 # path -> host file or None
        self._real_copies = {}                # staged copy path -> source file

    # -- classification ----------------------------------------------------

    def occupied(self, path):
        # Manifest and payload keys carry no leading slash; load commands do.
        p = path.lower().lstrip("/")
        return p in self.staged or p in self.payload_paths

    def host_file(self, path):
        p = path.lower().lstrip("/")
        if p in self.payload_paths:
            return self.payload_paths[p]
        return self.sources.get(p)

    def record(self, path):
        if path in self.deps:
            return self.deps[path]
        occ = self.occupied(path)
        real = self.find_real_for(path) if not occ else None
        self.deps[path] = {"path": path, "occupied": occ,
                           "real": real, "shim_at": None, "traps": set(),
                           "mode": None, "reexport": None}
        return self.deps[path]

    def find_real_for(self, path):
        """Host file for dep `path`: the staged file when occupied, else SDK."""
        if path in self._real_cache:
            return self._real_cache[path]
        if self.occupied(path):
            f = self.host_file(path)
            if not f or not os.path.isfile(f) or not is_macho(f):
                log("  note: %s is occupied but has no usable host file (%s)"
                    % (path, f))
                f = None
        else:
            f = find_real(path)
            if f is not None:
                # The trap set must be computed from the bytes the GUEST will
                # load.  When the SDK file's own install name is already staged
                # (AppKit is staged at Versions/A while macOS links Versions/C),
                # that staged file is the image dyld will use, not our copy.
                idn = install_name(f)
                if idn and self.occupied(idn):
                    staged_f = self.host_file(idn)
                    if staged_f and os.path.isfile(staged_f) and is_macho(staged_f):
                        f = staged_f
        self._real_cache[path] = f
        return f

    # -- graph walk --------------------------------------------------------

    def walk(self):
        queue = list(self.binaries)
        seen = set()
        while queue:
            staged, host, label = queue.pop(0)
            if staged in seen:
                continue
            seen.add(staged)
            deps = []
            for kind, dep in parse_lcs(host):
                if dep.startswith("@"):
                    target = self.resolve_relative(dep, staged, label)
                    if target is None:
                        continue          # own install name
                    deps.append(target)
                    continue
                deps.append(dep)
            self.binary_deps[staged] = deps
            for dep in deps:
                rec = self.record(dep)
                if rec["real"] and not rec["occupied"]:
                    key = "@real:" + rec["real"]
                    if key not in seen:
                        seen.add(key)
                        queue.append((key, rec["real"], rec["real"]))

    def resolve_relative(self, dep, staged_binary, label):
        """@executable_path / @loader_path dep -> staged path, or None if it is
        the binary's own install name.  @rpath is not supported (fails)."""
        if dep.startswith("@rpath/"):
            die("%s: @rpath dep %s (no rpath support in this tree)" % (label, dep))
        for prefix in ("@executable_path/", "@loader_path/"):
            if dep.startswith(prefix):
                staged_dir = posixpath.dirname("/" + staged_binary)
                target = posixpath.normpath(
                    posixpath.join(staged_dir, dep[len(prefix):])).lstrip("/")
                if target == staged_binary:
                    return None
                if self.occupied(target):
                    return target
                die("%s: relative dep %s -> %s is not staged" % (label, dep, target))
        die("%s: unsupported dep %s" % (label, dep))

    # -- missing symbols ---------------------------------------------------

    def lcs(self, f):
        if f not in self._lcs_cache:
            self._lcs_cache[f] = parse_lcs(f)
        return self._lcs_cache[f]

    def exports_closure(self, path, seen=None, unresolvable=None):
        if seen is None and path in self._exp_cache:
            return self._exp_cache[path]
        top = seen is None
        seen = seen if seen is not None else set()
        unresolvable = unresolvable if unresolvable is not None else self.unresolvable
        f = self.find_real_for(path)
        if f is None:
            unresolvable.add(path)
            syms = set()
        elif f in seen:
            syms = set()
        else:
            seen.add(f)
            syms = set(self._exports_cache.setdefault(f, exports_of(f)))
            for kind, re_path in self.lcs(f):
                if kind != "REEXPORT":
                    continue
                syms |= self.exports_closure(re_path, seen, unresolvable)
        if top:
            self._exp_cache[path] = syms
        return syms

    def sections_for(self, dep):
        """{symbol: set(sections)} for the binaries that import from `dep`."""
        if dep in self._fixup_cache:
            return self._fixup_cache[dep]
        short = short_name(dep)
        secs = collections.defaultdict(set)
        for staged, host, label in self.binaries:
            imps = self.per_binary_missing[staged][0]
            if short not in imps:
                continue
            key = "@f:" + host
            if key not in self._fixup_cache:
                self._fixup_cache[key] = fixup_sections(host)
            for sym, s in self._fixup_cache[key].items():
                secs[sym] |= s
        self._fixup_cache[dep] = secs
        return secs

    def staged_export_files(self):
        """{symbol: [host Mach-Os in the staged image exporting it]}."""
        key = "@all-exports-map"
        m = self._exports_cache.get(key)
        if m is None:
            m = {}
            files = []
            for p in self.staged:
                hf = self.host_file(p)
                if hf and is_macho(hf):
                    files.append(hf)
            for hf in self.payload_paths.values():
                if is_macho(hf):
                    files.append(hf)
            files = [f for f in dict.fromkeys(files) if is_dylib(f)]
            for f in files:
                try:
                    for nm in exports_of(f):
                        m.setdefault(nm, []).append(f)
                except Exception:
                    log("note: exports of %s unreadable" % f)
            self._exports_cache[key] = m
        return m

    def member_paths(self, path, seen=None):
        """Install paths reachable from `path` through its own load commands
        (NEEDED + REEXPORT), transitively -- that is the set of images dyld
        actually has in hand when it resolves an import against this dep."""
        seen = seen if seen is not None else set()
        f = self.find_real_for(path)
        if f is None or path in seen:
            return set()
        seen.add(path)
        out = set()
        for kind, dep in parse_lcs(f):
            if dep in seen:
                continue
            out.add(dep)
            out |= self.member_paths(dep, seen)
        return out

    def data_providers(self, dep, names):
        """Host images in the staged image that export `names` but are NOT the
        dep's own closure -- used to re-export DATA symbols the dep itself
        lacks (dyld2 looks only at the importer's direct NEEDED images plus
        their re-export chains, so an unrelated staged library never helps
        unless we link a re-export edge to it)."""
        exp = self.exports_closure(dep)
        out = []
        for n in names:
            for f in self.staged_export_files().get(n, ()):
                if f not in exp and is_macho(f):
                    out.append(f)
        return sorted(set(out))

    def data_syms_of(self, files):
        """Names defined as DATA (not text) by host images in `files`.

        nm prints "<path>: <hex-addr> <type> <name>"; the type letter decides
        whether a name may legally be replaced by a generated function stub.
        Data globals (D/B/R -- e.g. ___stderrp, _mach_task_self_) are bound by
        the linker into __got/__data slots that must hold the real object, so
        they stay with dyld's own lookup instead of getting trapped."""
        out = set()
        for f in files:
            if not f or not is_macho(f):
                continue
            key = "@data:" + f
            v = self._exports_cache.get(key)
            if v is None:
                import subprocess
                r = subprocess.run(["nm", "-o", "-g", f], capture_output=True,
                                   text=True)
                v = set()
                for line in (r.stdout or "").splitlines():
                    p = line.split()
                    if len(p) < 3:
                        continue
                    name, typ = p[-1], None
                    for k2 in range(len(p) - 2, max(0, len(p) - 5), -1):
                        if re.match(r"^[0-9A-Fa-f]{8,}$", p[k2]) and k2 + 2 < len(p):
                            typ = p[k2 + 1][-1]      # "<path>: <addr> <type> <name>"
                            break
                    if typ in ("D", "B", "R"):     # data / bss / rodata globals
                        v.add(name)
                self._exports_cache[key] = v
            out |= v
        return out

    def compute_missing(self):
        self.unresolvable = set()
        self.per_binary_missing = {}
        providers = {rec["real"] for rec in self.deps.values() if rec["real"]}
        providers |= {host for _, host, _ in self.binaries}
        self.data_syms = self.data_syms_of(providers)
        log("%d provider-defined DATA symbols excluded from trap sets "
            "(e.g. ___stderrp)" % len(self.data_syms))

        all_exports = frozenset(self.staged_export_files())
        log("staged image exports cover %d distinct symbols" % len(all_exports))
        pseudo = set()
        for staged, host, label in self.binaries:
            imps, pseudo_here = imports_by_short(host)
            pseudo |= pseudo_here
            deps = self.binary_deps.get(staged, [])
            by_short = collections.defaultdict(list)
            for d in deps:
                by_short[short_name(d)].append(d)
            miss_here = {}
            for s, syms in imps.items():
                cands = by_short.get(s)
                if not cands:
                    die("%s: imports from %r but has no such dependency" % (label, s))
                if len(cands) > 1:
                    die("%s: dep short name %r is ambiguous: %s" % (label, s, cands))
                dep = cands[0]
                exp = self.exports_closure(dep)
                # DATA symbols must never become function traps: Chrome binds
                # e.g. ___stderrp (a D global inside libsystem_c, re-exported at
                # runtime through libSystem.B's member trie) into a __got slot
                # that has to hold a FILE*, not the address of a stub.  Any name
                # defined as data by one of the real provider images is left to
                # dyld's own search -- if it is truly absent dyld says so loudly
                # rather than us handing back a bogus pointer.
                # DATA symbols are only "already fine" when some staged image
                # really exports them -- then dyld binds the real object.  When
                # nothing in the image exports one (repo builds omit such data
                # globals), it still has to be trapped, but as a plain data
                # slot rather than a callable stub (see gen_stub routing).
                # A DATA global that some staged image does export (___stderrp
                # lives in libsystem_c, which the load graph pulls in through
                # libSystem's member edges) must NOT get a stub of our own --
                # dyld finds the real object by searching the whole loaded
                # graph; our own slot would shadow it with a bogus pointer.
                # Runtime-visible exports for this dep include the members it
                # pulls in through its own load commands -- ld64 re-export
                # dylibs carry no per-symbol attribution (see
                # Libraries/Libsystem/Makefile:37), so a member's DATA globals
                # (___stderrp etc.) are invisible to `exp` yet perfectly
                # resolvable at load time.  Trapping those would hand Chrome a
                # bogus slot that shadows the real object; trapping names that
                # nothing in the dep's graph provides stays correct, and gen_stub
                # emits them as data slots plus a re-export edge when some other
                # staged image does define them.
                runtime = set(exp)
                for m in self.member_paths(dep):
                    hf = self.host_file(m) or find_real(m)
                    if hf and is_macho(hf):
                        runtime |= set(exports_of(hf))
                miss = syms - runtime
                if miss:
                    self.missing[dep] |= miss
                miss_here[dep] = miss
            self.per_binary_missing[staged] = (imps, miss_here)
        if pseudo:
            log("%d weak-definition symbols skipped (not imports): %s"
                % (len(pseudo), ", ".join(sorted(pseudo)[:4])))
        if self.unresolvable:
            log("unresolvable re-export targets (their symbols count as missing):")
            for p in sorted(self.unresolvable):
                log("    %s" % p)

    # -- placement ---------------------------------------------------------

    def side_path(self, path, index):
        """A shorter staged path for a shim whose load path is occupied."""
        base = os.path.basename(path)
        if base.endswith(".dylib"):
            base = base[:-len(".dylib")]
        for cand in ("%s/%s.dylib" % (SIDE_DIR, base),
                     "/usr/lib/%s.dylib" % base,
                     "/usr/lib/c/%d.dylib" % index):
            if len(cand) <= len(path) and cand != path:
                return cand
        die("no side path fits %s" % path)

    def place(self):
        idx = 0
        for path in sorted(self.deps):
            rec = self.deps[path]
            idx += 1
            traps = self.missing.get(path, set())
            occ = rec["occupied"]
            if occ and not traps:
                rec["mode"] = "occupied-complete"      # nothing to do at all
                continue
            if occ:
                rec["shim_at"] = self.side_path(path, idx)
                rec["mode"] = "side-shim"
            else:
                rec["shim_at"] = path
                rec["mode"] = "at-path-shim" if rec["real"] else "trap-only"
            rec["traps"] = traps

    # -- what the shim re-exports ------------------------------------------

    def reexport(self, path):
        rec = self.deps[path]
        if rec["mode"] in ("occupied-complete", "trap-only"):
            return
        real = self.find_real_for(path)
        if real is None:
            return
        idn = install_name(real)
        staged_id = idn and (self.occupied(idn) or idn.lower() in self.payload_paths)
        if staged_id:
            # The real image's own install name is where the guest loads it:
            # re-export it there and stage no copy (one runtime instance).
            rec["reexport"] = idn
            rec["reexport_file"] = real
            return
        base = os.path.basename(real)
        dst_stage = "%s/%s" % (REAL_DIR, base)
        owner = self._real_copies.setdefault(dst_stage, real)
        if owner != real:
            die("real copy path %s wanted by both %s and %s"
                % (dst_stage, owner, real))
        if len(dst_stage) > len(idn or ""):
            die("renamed copy id %s longer than original %s" % (dst_stage, idn))
        dst = os.path.join(SHIMS, dst_stage.lstrip("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(real, dst)
        sh(["install_name_tool", "-id", dst_stage, dst])
        sh(["codesign", "--force", "--sign", "-", dst])
        if "flags=0x2(adhoc)" not in codesign_dv(dst):
            die("%s: re-sign did not produce adhoc flags" % dst)
        rec["reexport"] = dst_stage
        rec["reexport_file"] = dst
        rec["real_copy"] = dst_stage


# -------------------------------------------------------------------- codegen

def c_ident(sym):
    return re.match(r"^[A-Za-z_][A-Za-z0-9_$]*$", sym) is not None


OBJC_CLASS_PREFIX = "_OBJC_CLASS_$_"
OBJC_META_PREFIX = "_OBJC_METACLASS_$_"
# ObjC++ exception machinery: CoreFoundation exports these as DATA (a typeinfo
# pointer the importer binds in a __got/__const slot), so they must be plain
# data slots -- a function stub hands back an address that gets dereferenced.
OBJC_EHTYPE_PREFIX = "_OBJC_EHTYPE_$_"

# ------------------------------------------------------ objc class provider

# Chrome's __objc_classrefs bind to the ADDRESS of _OBJC_CLASS_$_X, and the
# modern Objective-C ABI requires that address to BE the objc_class structure
# (its *value* is the class's isa slot).  A data slot -- the old ".quad 0" trap
# -- can never satisfy that: the runtime reads isa == 0 and bits == 0, so
# data() is null and objc_class::isRealized() faults.  The class trap and the
# objc_allocateClassPair constructor are therefore replaced by ONE shared
# provider image that defines the missing classes as real modern-ABI classes.
#
# One image, not one per dependency: NSURLSession and NSURLSessionConfiguration
# are trapped by two deps (CFNetwork and Foundation), and two class objects
# with one name make the runtime's addNamedClass warn and keep the OLD mapping
# -- so one of the two binds would silently point at the wrong object.
#
# Every dependency Chrome binds a class symbol from re-exports the provider:
# Chrome's binds are library-scoped (two-level namespace), so dyld resolves
# them against the NAMED library's export list and walks that library's
# libReExported chain.  A symbol exported only by an unrelated image in the
# same process does not satisfy them.
PROVIDER_INSTALL = "/usr/lib/chrome/ObjCClassProvider.dylib"
PROVIDER_REL = PROVIDER_INSTALL.lstrip("/")

# The provider's classes are structural placeholders: they fix class lookup
# and realization, not behaviour (the real implementations are the existing
# framework-growth work in USERLAND-PLAN.md section A).
#
# -fobjc-runtime is deliberately NOT passed: the default modern ABI output is
# already byte-identical to macosx-10.8/10.15/11.0/13.0, and the gnustep-2.0
# modes do not compile on Mach-O at all.
PROVIDER_DEFINES = ["-DAPPLE_RUNTIME_4", "-DDARWIN", "-DNULL=0",
                    "-DTARGET_OS_IOSMAC=0", "-DPLATFORM_IS_POSIX",
                    "-DPLATFORM_USES_BSD_SOCKETS", "-DTOLL_FREE_BRIDGING"]


def provider_includes():
    return ["-I" + os.path.join(REPO, "Developer", "ravynOS.sdk", "usr", "local",
                                 "include", "kernel"),
            "-I" + os.path.join(REPO, "Developer", "ravynOS.sdk", "System",
                                 "Library", "Frameworks", "Foundation.framework",
                                 "Headers"),
            "-I" + os.path.join(REPO, "Libraries", "objc4"),
            "-I" + os.path.join(REPO, "Frameworks", "Foundation")]


def platform_clang():
    """The compiler that can build this tree's Objective-C.

    The host's xcrun clang (21) segfaults on it -- see the build-libraries.sh
    header -- so the platform toolchain's clang-17 is pinned explicitly.  The
    provider must not be built by the host compiler: the host's ObjC headers
    and runtime are a different ABI generation."""
    cands = []
    env = os.environ.get("PLATFORM_TOOLCHAIN_BIN")
    if env:
        cands += [os.path.join(env, "clang-17"), os.path.join(env, "clang")]
    tc = os.path.join(BUILD, "Developer", "Platforms", "ravynOS.platform",
                      "Developer", "Toolchains", "Default.xctoolchain",
                      "usr", "bin")
    cands += [os.path.join(tc, "clang-17"), os.path.join(tc, "clang")]
    for c in cands:
        if os.path.isfile(c):
            return [c]
    return sh(["xcrun", "-f", "clang"]).split()


def gen_provider_source(names, path):
    """One @interface/@implementation pair per synthesized class.

    Empty bodies are correct and sufficient: the runtime needs a REALIZABLE
    class object, not behaviour."""
    src = ["/* generated by chrome_stage.py -- Objective-C class provider.",
           " *",
           " * Each class below is a real modern-ABI class object: the exported",
           " * symbol's ADDRESS is the objc_class structure, which is exactly",
           " * what Chrome's __objc_classrefs binds expect.  The bodies are empty",
           " * on purpose -- the runtime needs a realizable class, behaviour",
           " * belongs to the repo frameworks (USERLAND-PLAN.md section A).",
           " */",
           "#import <objc/NSObject.h>",
           ""]
    for n in names:
        src.append("@interface %s : NSObject" % n)
        src.append("@end")
        src.append("")
        src.append("@implementation %s" % n)
        src.append("@end")
        src.append("")
    with open(path, "w") as f:
        f.write("\n".join(src) + "\n")


def provider_export_names(names):
    """The symbol names the provider exports for `names`.

    A class definition emits BOTH the class and its metaclass, which is why
    the five metaclass-only traps (CAMetalLayer, CAOpenGLLayer,
    NSAccessibilityElement, NSTitlebarAccessoryViewController,
    ASAuthorizationController) need no separate stub."""
    out = set()
    for n in names:
        out.add(OBJC_CLASS_PREFIX + n)
        out.add(OBJC_META_PREFIX + n)
    return out


def synth_class_names(cl):
    """The class names the provider must define.

    A name is synthesized when some dependency TRAPS it (imports it and no
    image in that dependency's own closure provides it) AND no staged image
    exports it.  The names a staged image really defines -- Foundation's 21
    (NSArray, NSDictionary, NSDate, NSURL, NSUserDefaults, ...) and
    QuartzCore's CIImage -- keep resolving through the existing provider-edge
    rule instead: redefining them here would put two class objects with one
    name into the process, and the runtime's addNamedClass then warns and
    keeps the OLD mapping, so one bind would silently point at the wrong
    object."""
    trapped = set()
    for rec in cl.deps.values():
        for s in rec.get("traps") or ():
            if s.startswith(OBJC_CLASS_PREFIX):
                trapped.add(s[len(OBJC_CLASS_PREFIX):])
    exported = set()
    for sym in cl.staged_export_files():
        if sym.startswith(OBJC_CLASS_PREFIX):
            exported.add(sym[len(OBJC_CLASS_PREFIX):])
    return sorted(trapped - exported)


def sign_artifact(path):
    """Adhoc-sign one staged image and assert the signature really is adhoc."""
    sh(["codesign", "--force", "--sign", "-", path])
    if "flags=0x2(adhoc)" not in codesign_dv(path):
        die("%s: adhoc signature did not take" % path)


def verify_provider(path, names):
    """Gate the provider image.

    nm -g must show every class and metaclass symbol as S-type (the symbol's
    address IS the class object), otool -ov must show the canonical modern
    layout, and the ObjC sections must be present.  dyld_info -fixups is
    deliberately NOT a gate: it does not faithfully decode staged images'
    bind streams (BOOT-PLAN.md 22, class-provider plan section 8)."""
    syms = {}
    for line in sh(["nm", "-g", path]).splitlines():
        p = line.split(maxsplit=2)
        if len(p) == 3:
            syms[p[2]] = p[1]
    bad = []
    for n in names:
        for sym in (OBJC_CLASS_PREFIX + n, OBJC_META_PREFIX + n):
            if syms.get(sym) != "S":
                bad.append("%s=%s" % (sym, syms.get(sym)))
    if bad:
        die("provider: %d class/metaclass symbols are not S-type: %s"
            % (len(bad), ", ".join(bad[:6])))
    # exactly one class and one metaclass symbol per class, and nothing else
    got_cls = sorted(s for s in syms if s.startswith(OBJC_CLASS_PREFIX))
    got_meta = sorted(s for s in syms if s.startswith(OBJC_META_PREFIX))
    if len(got_cls) != len(names) or len(got_meta) != len(names):
        die("provider: exported %d class and %d metaclass symbols, wanted %d "
            "and %d" % (len(got_cls), len(got_meta), len(names), len(names)))
    secs = sh(["otool", "-l", path])
    for want in ("__objc_classlist", "__objc_imageinfo", "__objc_data"):
        if want not in secs:
            die("provider: section %s missing" % want)
    lines = sh(["otool", "-ov", path]).splitlines()
    for sample in (names[0], names[-1]):
        idx = None
        for i, ln in enumerate(lines):
            if ln.endswith("_OBJC_CLASS_$_" + sample):
                idx = i
                break
        if idx is None:
            die("provider: otool -ov has no classlist entry for %s" % sample)
        blk = "\n".join(lines[idx:idx + 6])
        if (OBJC_META_PREFIX + sample) not in blk:
            die("provider: %s isa is not its own metaclass:\n%s" % (sample, blk))
        if "_OBJC_CLASS_$_NSObject" not in blk:
            die("provider: %s superclass is not NSObject:\n%s" % (sample, blk))
        if "__objc_empty_cache" not in blk:
            die("provider: %s has no empty cache:\n%s" % (sample, blk))


def build_class_provider(names):
    """Build the shared ObjC class provider image.

    Returns (host path, set of exported symbol names)."""
    if not names:
        die("provider: no classes to synthesize")
    odir = os.path.join(OBJ, "objc-class-provider")
    shutil.rmtree(odir, ignore_errors=True)
    os.makedirs(odir)
    src = os.path.join(odir, "provider.m")
    gen_provider_source(names, src)
    cc = platform_clang()
    log("provider: %d classes, compiled by %s" % (len(names), cc[0]))
    cflags = ["-c", "-arch", "x86_64", "-isysroot", BUILD_SDK,
              "-mmacos-version-min=15.0", "-fPIC"] + PROVIDER_DEFINES \
        + provider_includes()
    obj = os.path.join(odir, "provider.o")
    sh(cc + cflags + ["-o", obj, src])
    lflags = ["-arch", "x86_64", "-isysroot", BUILD_SDK, "-dynamiclib",
              "-mmacos-version-min=15.0", "-nostdlib", "-nodefaultlibs",
              "-install_name", PROVIDER_INSTALL,
              # dyld2 refuses an image whose compatibility version is lower than
              # the importer's requirement, and Chrome demands real macOS
              # versions (150.0.0, 1195.14.4, ...).  65535.255.255 is the
              # packed 0xFFFFFFFF wildcard.
              "-Wl,-compatibility_version,65535.255.255",
              "-Wl,-current_version,65535.255.255",
              # libobjc must come from $SDK/usr/lib: that is the one whose
              # LC_ID_DYLIB is /usr/lib/system/libobjc.dylib, which is what the
              # guest loads.  The other path does not exist in this SDK.
              "-L%s/usr/lib" % BUILD_SDK, "-lobjc", "-lSystem"]
    out = os.path.join(SHIMS, PROVIDER_REL)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sh(cc + lflags + ["-o", out, obj])
    idn = install_name(out)
    if idn != PROVIDER_INSTALL:
        die("provider: LC_ID_DYLIB is %r, wanted %r" % (idn, PROVIDER_INSTALL))
    sign_artifact(out)
    verify_provider(out, names)
    log("provider: %s (%d bytes)" % (PROVIDER_INSTALL,
                                     os.path.getsize(out)))
    return out, provider_export_names(names)


def gen_stub(path, traps, sections, rec):
    """Build one shim/stub dylib at work/chrome-shims/<install path>."""
    install = rec["shim_at"]
    out = os.path.join(SHIMS, install.lstrip("/"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    odir = os.path.join(OBJ, re.sub(r"[^A-Za-z0-9_.-]", "_", install))
    if os.path.isdir(odir):
        shutil.rmtree(odir)
    os.makedirs(odir)

    funcs, data, classes, asm_funcs = [], [], {}, []
    for sym in sorted(traps):
        secs = sections.get(sym)
        is_func = secs is None or not secs or set(secs) <= FUNC_SECTIONS
        if sym.startswith(OBJC_CLASS_PREFIX) or sym.startswith(OBJC_META_PREFIX):
            classes.setdefault(sym.split("$_", 1)[1], set()).add(sym)
        elif sym.startswith(OBJC_EHTYPE_PREFIX):
            data.append(sym)     # data slot, not a callable stub
        elif is_func:
            (funcs if c_ident(sym) else asm_funcs).append(sym)
        else:
            data.append(sym)

    c_src = ["/* generated by chrome_stage.py -- trap stubs for %s */" % install,
             "#include <stdio.h>"]
    asm_src = []
    # An Objective-C class symbol must NEVER become a data slot here.  Chrome
    # binds __objc_classrefs to the ADDRESS of _OBJC_CLASS_$_X, and the modern
    # ABI requires that address to BE the objc_class structure; a ".quad 0"
    # slot makes the runtime read isa == 0 and bits == 0, so data() is null
    # and objc_class::isRealized() faults.  The old objc_allocateClassPair
    # constructor had the same defect (it stored a runtime class in a slot
    # instead of making the symbol's address the class object).  Every class
    # symbol must therefore arrive already satisfied -- by a staged image that
    # really defines it, or by the shared class provider -- and the caller
    # drops those names from the trap set before reaching here.
    if classes:
        die("%s: %d Objective-C class symbols reached the stub generator: %s"
            % (install, len(classes),
               ", ".join(sorted(classes)[:6])))
    # Every trap needs an asm label: a plain C definition of `_foo` emits the
    # Mach-O symbol `__foo` (the C decoration is a second underscore), so dyld
    # would never find it under the name the importer asked for.
    for i, sym in enumerate(funcs):
        c_src.append("static int s%d;" % i)
        c_src.append('long trap_%d(void) __asm__("%s");' % (i, sym))
        c_src.append('long trap_%d(void) { if (!s%d++) fprintf(stderr, '
                     '"[CHROME-STUB] %%s\\n", "%s"); return 0; }'
                     % (i, i, sym))
    if asm_funcs:
        asm_src += [".text"] + [
            ".globl %s\n%s:\n\txorl %%eax, %%eax\n\tretq" % (s, s)
            for s in asm_funcs] + [".data"]
    for sym in data:
        asm_src.append(".globl %s" % sym)
        asm_src.append("%s: .quad 0" % sym)

    c_path = os.path.join(odir, "stub.c")
    with open(c_path, "w") as f:
        f.write("\n".join(c_src) + "\n")
    objs = []
    with open(os.path.join(odir, "empty.c"), "w") as f:
        f.write("/* %s */\n" % install)
    cflags = ["-c", "-arch", "x86_64", "-isysroot", BUILD_SDK,
              "-mmacos-version-min=15.0", "-fno-builtin", "-std=gnu11", "-fPIC",
              "-D__unused=", "-Wall", "-Wno-unused-value"]
    for src, obj in ((c_path, os.path.join(odir, "stub.o")),
                     (os.path.join(odir, "empty.c"), os.path.join(odir, "empty.o"))):
        sh(CLANG + cflags + ["-o", obj, src])
        objs.append(obj)
    if asm_src:
        asm_path = os.path.join(odir, "stub_data.s")
        with open(asm_path, "w") as f:
            f.write("/* generated by chrome_stage.py -- data slots for %s */\n"
                    ".data\n" % install)
            f.write("\n".join(asm_src) + "\n")
        obj = os.path.join(odir, "stub_data.o")
        sh(CLANG + cflags + ["-o", obj, asm_path])
        objs.append(obj)

    lflags = ["-arch", "x86_64", "-isysroot", BUILD_SDK, "-dynamiclib",
              "-install_name", install, "-mmacos-version-min=15.0",
              "-nostdlib", "-nodefaultlibs", "-Wl,-no_uuid",
              # dyld2 (ImageLoader.cpp:745) refuses to load an image whose
              # compatibility version is lower than the importer's requirement,
              # and Chrome's load commands demand real macOS versions (150.0.0,
              # 1195.14.4, ...).  65535.255.255 is the packed 0xFFFFFFFF
              # wildcard, so a generated shim satisfies any requirement.
              "-Wl,-compatibility_version,65535.255.255",
              "-Wl,-current_version,65535.255.255"]
    if rec.get("reexport_file"):
        lflags += ["-Wl,-reexport_library,%s" % rec["reexport_file"]]
        # Umbrella re-export alone is not enough for DATA globals (___stderrp
        # etc. live in member images and are absent from the umbrella's own
        # export list), so re-export each staged member too -- dyld then binds
        # Chrome's __got data slots to the real loaded objects, which is what
        # a normal macOS link graph does through libSystem's member edges.
        seen_m = set()
        for kind, mdep in parse_lcs(rec["reexport_file"]):
            if kind != "REEXPORT" or mdep in seen_m:
                continue
            seen_m.add(mdep)
            mf = find_real(mdep)
            if mf and is_macho(mf):
                lflags += ["-Wl,-reexport_library,%s" % mf]
    # A staged image elsewhere in the graph already defines these names (Foundation
    # defines _OBJC_CLASS_$_NSArray/_NSDictionary/..., which real macOS reaches
    # through CoreFoundation's own REEXPORT edge to Foundation).  Link a full-path
    # re-export edge -- dyld2 resolves imports only through an importer's NEEDED
    # images plus their re-export chains, so an unrelated staged library helps
    # exactly when we add that edge.  -Wl,-reexport_library,<path> is the spelling
    # this repo proves works on umbrella libs; -reexport-l<stem> silently does not.
    for extra in rec.get("data_provider_files") or ():
        lflags += ["-Wl,-reexport_library,%s" % os.path.abspath(extra)]
    # The shared Objective-C class provider.  Chrome's class binds are
    # library-scoped (two-level namespace), so dyld resolves
    # Metal/_OBJC_CLASS_$_MTLTextureDescriptor against the NAMED library's
    # export list and walks that library's libReExported chain.  A class object
    # that merely exists elsewhere in the process does not satisfy the bind:
    # the dependency Chrome names has to re-export the provider.  ld64 records
    # the provider's LC_ID_DYLIB (/usr/lib/chrome/ObjCClassProvider.dylib),
    # not the host path it was linked from.
    if rec.get("provider_file"):
        lflags += ["-Wl,-reexport_library,%s" % os.path.abspath(rec["provider_file"])]
    lflags += ["-L%s/usr/lib" % BUILD_SDK, "-L%s/usr/lib/system" % BUILD_SDK,
               "-lSystem"]
    sh(CLANG + lflags + ["-o", out] + objs)

    # verify the artifact
    idline = install_name(out)
    if idline != install:
        die("%s: LC_ID_DYLIB is %r, wanted %r" % (out, idline, install))
    nm = sh(["nm", "-gU", out], check=False)
    defined = set()
    for line in nm.splitlines():
        p = line.split(maxsplit=2)
        if len(p) == 3 and p[1] in ("T", "D", "S", "B"):
            defined.add(p[2])
    missing_defs = sorted(s for s in traps if s not in defined)
    if missing_defs:
        die("%s: %d traps not exported under their own name: %s"
            % (out, len(missing_defs), missing_defs[:6]))
    if os.path.getsize(out) == 0:
        die("%s: empty output" % out)
    return out


# -------------------------------------------------------------------- rewrite

def rewrite_binaries(cl):
    """Point Chrome's own binaries at the side-path shims."""
    changed = []
    for staged, host, label in cl.binaries:
        deps = cl.binary_deps.get(staged, [])
        edits = [(d, cl.deps[d]["shim_at"]) for d in deps
                 if cl.deps[d]["mode"] == "side-shim"]
        if not edits:
            continue
        for old, new in edits:
            if len(new) > len(old):
                die("%s: %s (%d) longer than %s (%d)" % (label, new, len(new), old, len(old)))
            if subprocess.run(["install_name_tool", "-change", old, new,
                              host], capture_output=True).returncode != 0:
                # the binary may already point at an older generated shim name
                # from a previous run -- retarget that string instead
                cur = [l.strip().split("(")[0].strip()
                       for l in sh(["otool", "-L", host], check=False).splitlines()
                       if "/" in l and ".dylib" in l]
                alt = next((c for c in cur if c.endswith(".dylib") and c != new), None)
                if alt:
                    sh(["install_name_tool", "-change", alt, new, host])
                else:
                    die("%s: cannot retarget dep %s -> %s" % (label, old, new))
        sh(["codesign", "--force", "--sign", "-", host])
        if "flags=0x2(adhoc)" not in codesign_dv(host):
            die("%s: re-sign after rewrite is not adhoc" % host)
        after = set(parse_lcs(host))
        after_paths = {n for _, n in after}
        for old, new in edits:
            if new not in after_paths or old in after_paths:
                die("%s: rewrite %s -> %s did not take" % (label, old, new))
        changed.append((label, edits))
    return changed


# ----------------------------------------------------------------------- main

def main():
    shutil.rmtree(SHIMS, ignore_errors=True)
    shutil.rmtree(OBJ, ignore_errors=True)
    os.makedirs(SHIMS, exist_ok=True)
    os.makedirs(OBJ, exist_ok=True)

    staged, sources = base_map()
    if MAIN_STAGE.lower() not in staged or INFO_STAGE.lower() not in staged:
        die("manifest_gui.json no longer stages %s and %s" % (MAIN_STAGE, INFO_STAGE))
    ensure_thinned_main()
    ensure_info_plist()
    files, machos = build_payload(staged)

    cl = Closure(staged, sources, files, machos)
    cl.walk()
    cl.compute_missing()
    cl.place()
    for path in sorted(cl.deps):
        cl.reexport(path)

    log("")
    log("chrome version staged: %s (the launcher's own framework path)" % VER)
    log("deps: %d (%d occupied by the guest, %d with a real file)"
        % (len(cl.deps),
           sum(1 for r in cl.deps.values() if r["occupied"]),
           sum(1 for r in cl.deps.values() if r["real"] and not r["occupied"])))
    log("")

    # sanity: the framework binary's per-dep missing counts vs the session's
    fw_staged = (CONTENTS_STAGE + "/Frameworks/Google Chrome Framework.framework"
                 "/Versions/%s/Google Chrome Framework" % VER)
    _, miss_here = cl.per_binary_missing[fw_staged]
    log("framework-binary missing symbols per dep (session measured in parens):")
    diffs = 0
    for dep in sorted(miss_here, key=lambda p: -len(miss_here[p])):
        n = len(miss_here[dep])
        short = short_name(dep)
        exp = EXPECTED_FRAMEWORK_MISSING.get(short)
        tag = ""
        if exp is not None:
            tag = " OK" if exp == n else " DIFF (session measured %d)" % exp
            diffs += exp != n
        log("  %-6d %-58s%s" % (n, dep, tag))
    log("")

    # generate
    #
    # The Objective-C class provider is built FIRST: every dependency that
    # traps a class symbol links a re-export edge to it, and ld64 records the
    # provider's LC_ID_DYLIB (/usr/lib/chrome/ObjCClassProvider.dylib), which
    # is the path the guest loads it from.
    synth_names = synth_class_names(cl)
    provider_file, provider_syms = build_class_provider(synth_names)
    log("provider: %d class names synthesized, %d symbols exported"
        % (len(synth_names), len(provider_syms)))
    log("")

    built = []
    for path in sorted(cl.deps):
        rec = cl.deps[path]
        if rec["mode"] in (None, "occupied-complete"):
            continue
        traps = list(rec["traps"])
        provs = cl.data_providers(path, traps) if traps else []
        # The cap is a safety valve against a pathological number of provider
        # images; it must never silently drop one, because a dropped provider
        # means a name that no staged image defines stays trapped -- and a
        # trapped class symbol is a zero-quad slot, i.e. the crash this whole
        # provider exists to remove.
        if len(provs) > PROVIDER_EDGE_CAP:
            die("%s: %d staged provider images exceed the cap of %d"
                % (path, len(provs), PROVIDER_EDGE_CAP))
        rec["data_provider_files"] = provs[:PROVIDER_EDGE_CAP]
        if provs:
            provided = set()
            for f in provs[:PROVIDER_EDGE_CAP]:
                provided |= exports_of(f)
            kept = [t for t in traps if t not in provided]
            dropped = sorted(set(traps) - set(kept))
            if dropped:
                log("closure: %s: %d trapped names come from staged providers (%s); "
                    "re-exported instead of stubbed"
                    % (path, len(dropped), ", ".join(dropped[:8])))
            traps = kept
        # Objective-C class symbols are satisfied by the shared provider: the
        # dependency re-exports it and Chrome's library-scoped bind resolves
        # through that chain to a REAL class object.
        covered = [t for t in traps if t in provider_syms]
        if covered:
            traps = [t for t in traps if t not in provider_syms]
            rec["provider_covered"] = sorted(covered)
            rec["provider_file"] = provider_file
        # Nothing may reach the stub generator as a class symbol: every one is
        # either provided by a staged image (re-export edge) or covered by the
        # provider (re-export edge).
        leftover = [t for t in traps
                    if t.startswith(OBJC_CLASS_PREFIX) or t.startswith(OBJC_META_PREFIX)]
        if leftover:
            die("%s: %d Objective-C class symbols are neither staged-provided "
                "nor provider-covered: %s"
                % (path, len(leftover), ", ".join(sorted(leftover)[:6])))
        rec["traps_effective"] = list(traps)
        out = gen_stub(path, traps, cl.sections_for(path), rec)
        built.append((rec["mode"], path, rec["shim_at"], len(traps), out))
    log("generated %d shims/stubs under work/chrome-shims" % len(built))

    changed = rewrite_binaries(cl)
    log("rewrote %d binaries:" % len(changed))
    for label, edits in changed:
        log("  %s" % label)
        for old, new in edits:
            log("      %s\n        -> %s" % (old, new))
    log("")

    # report
    log("%-10s %-5s %-58s %s" % ("mode", "traps", "dep path", "shim path"))
    for mode, path, shim, ntraps, out in built:
        log("%-10s %-5d %-58s %s" % (mode, ntraps, path, shim))
    log("")
    sizes = sum(os.path.getsize(out) for _, _, _, _, out in built)
    log("shim bytes: %d" % sizes)
    log("")
    log("trap worklist (per dep, symbols the guest must provide to stop trapping):")
    for path in sorted(cl.deps):
        rec = cl.deps[path]
        if not rec["traps"]:
            continue
        syms = sorted(rec["traps"])
        log("  %s: %d trapped" % (path, len(syms)))
        for s in syms[:WORKLIST_CAP]:
            log("      %s" % s)
        if len(syms) > WORKLIST_CAP:
            log("      ... %d more (work/chrome_plan.json)" % (len(syms) - WORKLIST_CAP))

    plan = {"binaries": {}, "deps": {}, "unresolvable_reexports": sorted(cl.unresolvable)}
    for staged_, (imps, miss) in cl.per_binary_missing.items():
        plan["binaries"][staged_] = {
            "deps": cl.binary_deps.get(staged_, []),
            "missing": {d: sorted(m) for d, m in miss.items() if m},
        }
    for path, rec in cl.deps.items():
        plan["deps"][path] = {
            "occupied": rec["occupied"], "real": rec["real"], "mode": rec["mode"],
            "shim_at": rec["shim_at"], "reexport": rec.get("reexport"),
            "real_copy": rec.get("real_copy"),
            "traps": sorted(rec["traps"]),
            # traps_effective is what the shim actually traps: the class and
            # metaclass names that a staged image or the class provider
            # satisfies are NOT in it, so a non-empty ObjC entry here would
            # mean a zero-quad class slot went back into the image.
            "traps_effective": sorted(rec.get("traps_effective") or []),
            "provider_covered": sorted(rec.get("provider_covered") or []),
        }
    plan["class_provider"] = {
        "install_name": PROVIDER_INSTALL,
        "host_path": provider_file,
        "classes": synth_names,
        "symbols": sorted(provider_syms),
    }
    # codesign re-creates _CodeSignature/CodeResources sidecars every time a
    # .app binary is re-signed, and the rewrite phase runs after build_payload's
    # cleanup pass -- so prune once more here: make_chrome_manifest walks these
    # trees, and stale signatures must never be staged into the image.
    strays = [dp for root in (PAYLOAD, SHIMS) if os.path.isdir(root)
              for dp, dn, fn in os.walk(root)
              if os.path.basename(dp) == "_CodeSignature"]
    for dp in strays:
        shutil.rmtree(dp)
    if strays:
        log("closure: pruned %d codesign _CodeSignature dirs after signing" % len(strays))
    # The class provider is a new guest file, so it carries an adhoc signature
    # like every other staged image.  Re-sign it after the prune above so the
    # signature cannot have been taken away with a stray _CodeSignature dir,
    # and re-assert the flag (never skip the check: codesign writes its
    # report to stderr).
    sign_artifact(provider_file)
    if "flags=0x2(adhoc)" not in codesign_dv(provider_file):
        die("%s: provider is not adhoc-signed" % provider_file)

    with open(PLAN_JSON, "w") as f:
        json.dump(plan, f, indent=1, sort_keys=True)
    with open(REPORT, "w") as f:
        f.write("\n".join(REPORT_LINES) + "\n")
    log("")
    log("wrote %s and %s" % (PLAN_JSON, REPORT))
    if diffs:
        log("NOTE: %d deps differ from the session's measured missing counts" % diffs)


if __name__ == "__main__":
    main()
