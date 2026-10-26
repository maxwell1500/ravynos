#!/usr/bin/env python3
"""Daily-driver desktop verification for ravynOS.

The plan's seven phases are checked in two ways:

  * IMAGE checks -- what the boot image actually contains.  They read the
    GUI manifest (the file list the image is built from) and assert that
    every application bundle, the canonical macOS aliases, the pasteboard
    daemon and its launchd job are staged with a real executable.

  * BOOT checks -- what the running system does.  The image is booted under
    QEMU with the serial console attached and the guest's own log is
    inspected: the desktop stack comes up, the pasteboard daemon serves both
    its native and its canonical name, no application dies and no Mach
    symbol fault is reported.

Usage:
    python3 tools/bootlab/verify_daily_driver.py --phase 1
    python3 tools/bootlab/verify_daily_driver.py --all

Exit code 0 only when every check of the selected phase(s) passes.
"""
import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
WORK = os.path.join(HERE, "work")
MANIFEST = os.path.join(HERE, "manifest_gui.json")
OVMF = "/usr/local/share/qemu/edk2-x86_64-code.fd"

BOOT_CMD = (
    "fs0:\\System\\Library\\CoreServices\\boot.efi -v serial=3 "
    "debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
    "rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 "
    "-no_compat_check cpus=1 quiet_boot=1\r\n"
)


# --------------------------------------------------------------------------
# The checks
# --------------------------------------------------------------------------

# (path, kind) where kind is "app" (a bundle with an executable) or "file".
PHASE_IMAGE_CHECKS = {
    1: [
        ("System/Library/CoreServices/pasteboardd", "file"),
        ("System/Library/LaunchDaemons/com.ravynos.pasteboardd.json", "file"),
        ("usr/bin/open", "file"),
        ("System/Library/Frameworks/LaunchServices.framework/Versions/A/LaunchServices", "file"),
        ("Applications/Utilities/Terminal.app", "app"),
    ],
    2: [
        ("System/Library/CoreServices/Filer.app", "app"),
        ("System/Library/CoreServices/Finder.app", "app"),
        ("Applications/Utilities/Terminal.app", "app"),
        ("Applications/TextEdit.app", "app"),
        ("Applications/Calculator.app", "app"),
    ],
    3: [
        ("Applications/Preview.app", "app"),
        ("Applications/Font Book.app", "app"),
        ("Applications/Utilities/Screenshot.app", "app"),
    ],
    4: [
        ("Applications/Utilities/Activity Monitor.app", "app"),
        ("Applications/Utilities/Disk Utility.app", "app"),
        ("Applications/Utilities/Console.app", "app"),
    ],
    5: [
        ("Applications/Utilities/Keychain Access.app", "app"),
        ("System/Library/CoreServices/Archive Utility.app", "app"),
    ],
    6: [
        ("System/Library/CoreServices/System Preferences.app", "app"),
        ("Applications/System Settings.app", "app"),
        ("Applications/System Preferences.app", "app"),
    ],
    7: [
        ("System/Library/CoreServices/WindowServer.app", "app"),
        ("System/Library/CoreServices/Dock.app", "app"),
        ("System/Library/CoreServices/Filer.app", "app"),
        # The macOS runtime frameworks a bundled application links against.
        # Each one has to be a real staged dylib, not just a framework
        # directory: staging the directory without the binary is exactly the
        # failure this check exists to catch.
        ("System/Library/Frameworks/Security.framework/Versions/A/Security", "file"),
        ("System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", "file"),
        ("System/Library/Frameworks/CoreVideo.framework/Versions/A/CoreVideo", "file"),
        ("System/Library/Frameworks/SystemConfiguration.framework/Versions/A/SystemConfiguration", "file"),
        ("System/Library/Frameworks/CFNetwork.framework/Versions/A/CFNetwork", "file"),
        ("System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices", "file"),
        ("usr/lib/libSDL2-2.0.0.dylib", "file"),
        # The two intake proof targets.
        ("Applications/MacOSIntakeProbe.app", "app"),
        ("Applications/SDLBlocks.app", "app"),
    ],
}

# The bundle identifiers the fleet must carry.  They are read from the
# Info.plist of the staged bundle in the image.
PHASE_BUNDLE_IDS = {
    2: [("Applications/TextEdit.app", "com.ravynos.TextEdit"),
        ("Applications/Calculator.app", "com.ravynos.Calculator"),
        ("System/Library/CoreServices/Filer.app", "com.ravynos.Filer")],
    3: [("Applications/Preview.app", "com.ravynos.Preview"),
        ("Applications/Font Book.app", "com.ravynos.FontBook"),
        ("Applications/Utilities/Screenshot.app", "com.ravynos.Screenshot")],
    4: [("Applications/Utilities/Activity Monitor.app", "com.ravynos.ActivityMonitor"),
        ("Applications/Utilities/Disk Utility.app", "com.ravynos.DiskUtility"),
        ("Applications/Utilities/Console.app", "com.ravynos.Console")],
    5: [("Applications/Utilities/Keychain Access.app", "com.ravynos.KeychainAccess"),
        ("System/Library/CoreServices/Archive Utility.app", "com.ravynos.ArchiveUtility")],
    6: [("System/Library/CoreServices/System Preferences.app", "com.ravynos.Preferences")],
}

# Phrases the guest's serial log must contain once the desktop is up.
PHASE_BOOT_CHECKS = {
    1: [("[pboardd] serving com.ravynos.pasteboardd and com.apple.pboard",
         "the pasteboard daemon serves both its native and canonical name")],
    2: [("bundleID=com.ravynos.Filer", "the Filer registers with the WindowServer")],
    3: [],
    4: [],
    5: [],
    6: [],
    7: [("[WS] WindowServer", "the WindowServer starts")],
}

# The screenshots the fleet launch has to produce, in launch order.
EXPECTED_SCREENSHOTS = [
    "01_desktop_dock",
    "02_Filer_app",
    "03_TextEdit_app",
    "04_Calculator_app",
    "05_Preview_app",
    "06_Font_Book_app",
    "07_Terminal_app",
    "08_Activity_Monitor_app",
    "09_Disk_Utility_app",
    "10_Console_app",
    "11_Keychain_Access_app",
    "12_System_Preferences_app",
    "13_Screenshot_app",
    "14_Archive_Utility_app",
]


class Results:
    def __init__(self):
        self.checks = []
        self.screenshots_checked = False

    def check(self, name, ok, evidence=""):
        self.checks.append((name, bool(ok), evidence))
        print("%-6s %s%s" % ("PASS" if ok else "FAIL", name,
                              ("  -- " + evidence) if evidence else ""),
              flush=True)
        return bool(ok)

    def summary(self):
        failed = [c for c in self.checks if not c[1]]
        print("\n%d checks, %d failed" % (len(self.checks), len(failed)),
              flush=True)
        for name, _, evidence in failed:
            print("  FAILED: %s %s" % (name, evidence))
        return 0 if not failed else 1


def load_manifest(path):
    if not os.path.isfile(path):
        return None
    with open(path) as f:
        return json.load(f)


def manifest_index(manifest):
    """path -> entry, for the files the image will contain."""
    index = {}
    for entry in manifest.get("files", []):
        index[entry["path"]] = entry
    return index


def check_image(phase, results, index):
    """Every bundle and file the phase needs must be in the image.

    A bundle is staged as its individual files, so it is present when the
    manifest lists any path below it.
    """
    for path, kind in PHASE_IMAGE_CHECKS.get(phase, []):
        if kind == "app":
            names = sorted(p for p in index if p.startswith(path + "/"))
            if not names:
                results.check("image: %s is staged" % path, False,
                              "no file of the bundle is in the manifest")
                continue
            missing = [p for p in names
                       if not os.path.exists(
                           os.path.normpath(os.path.join(
                               HERE, index[p].get("file", ""))))]
            has_plist = any(p.endswith("/Contents/Info.plist") for p in names)
            has_exec = any("/Contents/ravynOS/" in p or "/Contents/MacOS/" in p
                           for p in names)
            results.check("image: %s is a complete bundle" % path,
                          has_plist and has_exec and not missing,
                          "Info.plist=%s executable=%s missing=%d" %
                          (has_plist, has_exec, len(missing)))
        else:
            entry = index.get(path)
            if entry is None:
                results.check("image: %s is staged" % path, False,
                              "not in the manifest")
                continue
            abs_src = os.path.normpath(os.path.join(HERE, entry.get("file", "")))
            if not os.path.exists(abs_src):
                results.check("image: %s is staged" % path, False,
                              "source %s is missing" % entry.get("file"))
                continue
            results.check("image: %s is staged" % path, True, entry.get("file"))


def check_current_build(results, index):
    """The Dock and Filer in the image must be the binaries just built.

    An in-repo CoreServices/<name>/<name>.app is stale output from an older
    build; staging it shipped the Oct 16 Dock (two tiles) and Filer while every
    "is a complete bundle" check passed.
    """
    build = os.path.join(os.path.expanduser("~"), "Projects", "build",
                         REPO.lstrip("/"), "CoreServices")
    for name in ("Dock", "Filer"):
        built = os.path.join(build, name, name + ".app", "Contents", "ravynOS", name)
        entry = index.get("System/Library/CoreServices/%s.app/Contents/ravynOS/%s"
                          % (name, name))
        if entry is None or not os.path.isfile(built):
            continue  # not built here; the staged-bundle checks already speak
        staged = os.path.normpath(os.path.join(HERE, entry["file"]))
        with open(staged, "rb") as a, open(built, "rb") as b:
            same = a.read() == b.read()
        results.check("image: %s is the current build" % name, same, entry["file"])


def check_bundle_ids(phase, results, index):
    """The staged Info.plist must carry the canonical bundle identifier."""
    for path, bundle_id in PHASE_BUNDLE_IDS.get(phase, []):
        plist = index.get(path + "/Contents/Info.plist")
        if plist is None:
            results.check("bundle id: %s" % bundle_id, False,
                          "%s/Contents/Info.plist is not staged" % path)
            continue
        abs_src = os.path.normpath(os.path.join(HERE, plist.get("file", "")))
        found = ""
        try:
            with open(abs_src) as f:
                for line in f:
                    if "<string>%s</string>" % bundle_id in line:
                        found = bundle_id
                        break
        except OSError as e:
            results.check("bundle id: %s" % bundle_id, False, str(e))
            continue
        results.check("bundle id: %s in %s" % (bundle_id, path),
                      found == bundle_id,
                      "" if found else "identifier not found in the plist")


# make_gui_manifest.py's ALIASES table: the image format has no symlinks, so
# the canonical macOS path is staged as a copy of the ravynOS bundle.  A copy
# is only an alias while it is still the same bundle.  Rebuild one side and not
# the other and the image ships two versions of one application under two
# names, with every "is a complete bundle" check still passing.
ALIAS_BUNDLES = [
    ("System/Library/CoreServices/Filer.app",
     "System/Library/CoreServices/Finder.app"),
    ("System/Library/CoreServices/System Preferences.app",
     "Applications/System Settings.app"),
    ("System/Library/CoreServices/System Preferences.app",
     "Applications/System Preferences.app"),
]


def _bundle_files(index, bundle):
    """relative path inside the bundle -> manifest entry"""
    prefix = bundle + "/"
    return {p[len(prefix):]: e for p, e in index.items() if p.startswith(prefix)}


def _same_file(entry_a, entry_b):
    a = os.path.normpath(os.path.join(HERE, entry_a.get("file", "")))
    b = os.path.normpath(os.path.join(HERE, entry_b.get("file", "")))
    try:
        with open(a, "rb") as fa, open(b, "rb") as fb:
            return fa.read() == fb.read()
    except OSError:
        return False


def check_aliases(results, index):
    for canonical, alias in ALIAS_BUNDLES:
        a = _bundle_files(index, canonical)
        b = _bundle_files(index, alias)
        if not a and not b:
            continue
        if not a or not b:
            results.check("alias: %s is a copy of %s" % (alias, canonical), False,
                          "only %s is staged" % (canonical if a else alias))
            continue
        missing = sorted(set(a) - set(b))
        extra = sorted(set(b) - set(a))
        differing = [rel for rel in sorted(set(a) & set(b))
                     if not _same_file(a[rel], b[rel])]
        ok = not (missing or extra or differing)
        detail = "missing=%d extra=%d differing=%d" % (
            len(missing), len(extra), len(differing))
        if not ok:
            detail += " (%s)" % ", ".join(
                sorted(set(missing + extra + differing))[:3])
        results.check("alias: %s is a byte copy of %s" % (alias, canonical),
                      ok, detail)


def check_alias_agents(results, index):
    """One agent per application: an alias must not bring its own."""
    agents = set(p for p in index
                 if "/LaunchAgents/" in p and p.endswith(".json"))
    for name, expected in (("Filer", 1), ("Finder", 0)):
        staged = sorted(p for p in agents
                        if p.endswith("/com.ravynos.%s.json" % name))
        results.check("alias: %d launch agent(s) for %s" % (expected, name),
                      len(staged) == expected,
                      ", ".join(staged) if staged else "none")


# --------------------------------------------------------------------------
# Boot
# --------------------------------------------------------------------------

class SerialSniffer:
    """Collects the guest's serial output."""

    def __init__(self):
        self.lock = threading.Lock()
        self.raw = b""

    def feed(self, data):
        with self.lock:
            self.raw += data

    def text(self):
        with self.lock:
            return self.raw.decode("utf-8", "replace")


def qemu_binary():
    for name in ("qemu-system-x86_64-hvffix", "qemu-system-x86_64"):
        path = shutil.which(name)
        if path:
            return path
    return None


class HmpMonitor:
    """QEMU human monitor over its unix socket, for screendump."""

    def __init__(self, path, timeout=30.0):
        self.sock = None
        deadline = time.time() + timeout
        while time.time() < deadline:
            if os.path.exists(path):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(path)
                    s.settimeout(0.5)
                    self.sock = s
                    break
                except OSError:
                    time.sleep(0.2)
            else:
                time.sleep(0.2)
        if self.sock is not None:
            try:
                self.sock.recv(65536)      # banner
            except OSError:
                pass

    def command(self, line, wait=0.6):
        if self.sock is None:
            return False
        try:
            self.sock.sendall((line + "\n").encode())
            end = time.time() + wait
            while time.time() < end:
                try:
                    self.sock.recv(65536)
                except socket.timeout:
                    pass
                except OSError:
                    break
            return True
        except OSError:
            return False

    def close(self):
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None


# The launch marker the in-guest self test prints before every application.
# The serial line can end in "\n", "\r\n" or "\r", so the marker is anchored
# on any of them.
# Wall budget for the in-guest fleet (13 applications, each activated and then
# held until the harness has its frame).  Bigger than any planned run: 13 apps
# at 60 s of hold plus six 30 s activation retries each is ~1170 s, and the
# boot plus the settle pass add a few hundred more.
FLEET_BUDGET = 7200

MARKER_RE = re.compile(r"(?:^|[\r\n])\[ddtest\] launch (\d+) ([^\r\n]+)")


def find_markers(text):
    """The launch markers in the serial log and the offset just past each.

    Only a line that arrived in full counts: a half received marker would
    name the wrong application.  The offsets are into the raw log, which
    only ever grows, so they stay valid for the tail search.
    """
    found = {}
    for m in MARKER_RE.finditer(text):
        if m.end() == len(text) and not text.endswith("\n"):
            continue                        # the last line is still arriving
        found.setdefault(m.group(1), (m.group(2), m.end()))
    return found


def capture_screen(monitor, outdir, name):
    """screendump the guest and convert the PPM to PNG (host sips)."""
    os.makedirs(outdir, exist_ok=True)
    ppm = os.path.join(outdir, name + ".ppm")
    png = os.path.join(outdir, name + ".png")
    if os.path.exists(ppm):
        os.unlink(ppm)
    if not monitor.command("screendump " + ppm, wait=1.2):
        return None
    end = time.time() + 5.0
    while time.time() < end and not os.path.exists(ppm):
        time.sleep(0.1)
    if not os.path.exists(ppm):
        return None
    try:
        subprocess.run(["sips", "-s", "format", "png", ppm, "--out", png],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=25)
    except subprocess.TimeoutExpired:
        # A hung image converter must not stop the rest of the fleet: drop
        # the frame and let the retry (or the missing file) report it.
        try:
            os.unlink(ppm)
        except OSError:
            pass
        return None
    if os.path.exists(png):
        os.unlink(ppm)
        return png
    return None


def boot_and_collect(img, tag, timeout, screenshots_dir=None):
    """Boot the image and return the guest's serial output.

    ``timeout`` is the wall budget for the guest to reach the desktop and for
    the fleet to finish, so it must be positive: 0 (or a negative value) used
    to become an already expired deadline and the fleet then got whatever the
    300 s floor allowed, which is how a 200 s-per-app hold produced a run with
    a single missing screenshot and no fleet-done.  Treat it as "no explicit
    budget" instead of as "no time at all".

    The invocation is the one the window-manager harness uses: OVMF with the
    repository's variable store, the boot command typed into the firmware
    shell over the serial line, and the desktop detected by the SystemUI
    server's "mbw-up" trace.
    """
    if timeout <= 0:
        print("boot: --boot-timeout %d is not a budget; using %d s" % (timeout, FLEET_BUDGET))
        timeout = FLEET_BUDGET

    serial_sock = os.path.join(WORK, "%s_dd_serial.sock" % tag)
    mon_sock = os.path.join(WORK, "%s_dd_mon.sock" % tag)
    out_log = os.path.join(WORK, "%s_dd_serial.log" % tag)
    vars_fd = os.path.join(WORK, "%s_dd_vars.fd" % tag)
    for p in (serial_sock, mon_sock):
        if os.path.exists(p):
            os.unlink(p)

    qemu = qemu_binary()
    if qemu is None:
        return None, "no qemu-system-x86_64 binary"
    if not os.path.isfile(OVMF):
        return None, "no OVMF firmware at %s" % OVMF

    shutil.copyfile(os.path.join(HERE, "assets", "vars.fd"), vars_fd)

    cmd = [
        qemu,
        "-machine", "q35,vmport=off",
        "-cpu", "Skylake-Client",
        "-m", "4096", "-smp", "2",
        "-drive", "if=pflash,format=raw,readonly=on,file=" + OVMF,
        "-drive", "if=pflash,format=raw,readonly=off,file=" + vars_fd,
        "-drive", "file=%s,format=raw,if=none,id=drive0" % img,
        "-device", "ide-hd,bus=ide.0,drive=drive0",
        "-serial", "unix:%s,server,nowait" % serial_sock,
        "-monitor", "unix:%s,server,nowait" % mon_sock,
        "-vga", "std", "-display", "none", "-no-reboot",
    ]

    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    sniffer = SerialSniffer()
    logfile = open(out_log, "wb")

    ser = None
    deadline = time.time() + 30
    while time.time() < deadline and ser is None:
        if os.path.exists(serial_sock):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(serial_sock)
                ser = s
            except OSError:
                time.sleep(0.3)
    if ser is None:
        proc.kill()
        return None, "could not attach to the guest serial socket"

    ser.setblocking(False)

    def drain():
        while True:
            try:
                data = ser.recv(8192)
            except BlockingIOError:
                time.sleep(0.05)
                continue
            except OSError:
                return
            if not data:
                return
            logfile.write(data)
            logfile.flush()
            sniffer.feed(data)

    threading.Thread(target=drain, daemon=True).start()

    # The firmware shell takes the boot command.
    deadline = time.time() + 90
    while time.time() < deadline and "Shell>" not in sniffer.text():
        if proc.poll() is not None:
            logfile.close()
            return None, "qemu exited early (%s)" % proc.returncode
        time.sleep(0.5)
    ser.sendall(BOOT_CMD.encode("ascii"))

    # The bundle identifiers the fleet's windows carry, read from the
    # staged Info.plists.
    app_bundles = {}
    try:
        import plistlib
        sys.path.insert(0, HERE)
        from make_gui_manifest import APPS, ALIASES, CS_APPS
        candidates = []
        for build_rel, bundle_name, install in APPS:
            candidates.append((bundle_name, install))
        for build_rel, bundle_name, install in ALIASES:
            candidates.append((bundle_name, install))
        for entry in load_manifest(os.path.join(HERE, "manifest_gui.json")).get("files", []):
            path = entry["path"]
            if path.endswith("/Contents/Info.plist") and entry.get("file"):
                src = entry["file"]
                if not os.path.isabs(src):
                    src = os.path.join(HERE, src)
                try:
                    with open(src, "rb") as f:
                        info = plistlib.load(f)
                except Exception:
                    continue
                bundle_id = info.get("CFBundleIdentifier")
                exe = info.get("CFBundleExecutable")
                if bundle_id and exe:
                    app_bundles[exe + ".app"] = bundle_id
    except Exception:
        app_bundles = {}

    monitor = HmpMonitor(mon_sock) if screenshots_dir else None
    seen_markers = set()
    captured = set()
    abandoned = set()
    attempts = {}

    if screenshots_dir:
        os.makedirs(screenshots_dir, exist_ok=True)

    # Wait for the desktop.
    deadline = time.time() + timeout
    while time.time() < deadline:
        text = sniffer.text()
        if "[SUI] mbw-up" in text:
            break
        if proc.poll() is not None:
            logfile.close()
            return sniffer.text(), out_log
        time.sleep(1.0)

    if screenshots_dir:
        # The menu bar is up: let the first frame settle, then capture the
        # bare desktop before the fleet puts its windows on top of it.
        time.sleep(2.0)
        capture_screen(monitor, screenshots_dir, "01_desktop_dock")

    # The in-guest self test launches every application and announces each
    # one on the console; screendump the window that just came up.
    # The fleet needs its own budget: each application is activated (with up
    # to three 45 s paint retries), then held frontmost for 200 s.
    fleet_deadline = max(deadline, time.time() + FLEET_BUDGET)
    fleet_started = None
    while time.time() < fleet_deadline:
        text = sniffer.text()
        if fleet_started is None and "[ddtest] launch " in text:
            fleet_started = time.time()
        # The self test announces its first launch within a minute of the desktop
        # coming up.  If it never does, the guest's test died (a corpse on the
        # console is the usual reason) and waiting the whole fleet budget only
        # hides that: report it and stop, so the missing screenshots fail the
        # gate instead of a 50-minute wait on a guest that is not running them.
        if fleet_started is None and time.time() > deadline + 300:
            print("boot: the in-guest fleet never announced a launch; stopping")
            break
        if screenshots_dir:
            for marker, (name, offset) in sorted(find_markers(text).items(),
                                                 key=lambda kv: int(kv[0])):
                label = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")
                shot = "%02d_%s" % (int(marker) + 2, label)
                if shot in captured or shot in abandoned:
                    continue
                wanted = app_bundles.get(name)
                # The guest announces "[ddtest] holding <name> 0" only after
                # WindowServer has confirmed a fresh paint for this very
                # application, and it re-raises the window every ten seconds
                # for the next 200 s.  Waiting for that line (rather than for
                # "[WS] PAINTED", which is emitted before the raise settles
                # and whose position in the serial stream lags the guest)
                # makes the dump land inside a window during which this
                # application is provably frontmost.
                holding = "[ddtest] holding %s " % name
                nopaint = "[ddtest] nopaint %s" % name
                if marker not in seen_markers:
                    end = time.time() + 300.0
                    while time.time() < end:
                        log = sniffer.text()
                        tail = log[offset:]
                        if holding in tail or nopaint in tail:
                            break
                        time.sleep(0.25)
                    seen_markers.add(marker)
                    if nopaint in sniffer.text()[offset:]:
                        # The guest never got a fresh paint for this app, so
                        # no dump would show it: leave the shot missing and
                        # let the gate fail instead of writing a wrong image.
                        abandoned.add(shot)
                        break
                    # The scanout trails the guest by about 25 s (measured:
                    # with a 20 s hold a dump 2 s after the marker showed the
                    # previous application).  Dump 45 s into the hold: past
                    # that trail, and far enough from the end of a 120 s hold
                    # that a slow host still lands inside it.
                    time.sleep(45.0)
                t_capture = time.time()
                path = capture_screen(monitor, screenshots_dir, shot)
                print("boot: capture %s -> %s in %.1fs" % (shot, bool(path), time.time() - t_capture))
                if path:
                    captured.add(shot)
                else:
                    # A screendump that failed three times in a row is not
                    # going to succeed; move on so the rest of the fleet is
                    # still captured.  The missing file fails the gate.
                    attempts[shot] = attempts.get(shot, 0) + 1
                    if attempts[shot] >= 3:
                        abandoned.add(shot)
                # One application per pass: the next window must not be on
                # top of the one that was just captured.
                break
        if proc.poll() is not None:
            break
        done = "[ddtest] fleet-done" in sniffer.text()
        if screenshots_dir:
            # Every application the guest announced has to be accounted for
            # before the guest is stopped: the last window would be a half
            # drawn one.  Count the markers instead of hardcoding 13, so a
            # short fleet (a diagnostic run) also terminates.
            expected = len(find_markers(sniffer.text()))
            done = done and len(captured) + len(abandoned) >= expected
        if done:
            break
        time.sleep(0.5)

    if monitor is not None:
        monitor.close()

    text = sniffer.text()
    # Stop QEMU gracefully: it flushes the guest's disk writes, and the
    # harness reads the guest's self test report out of the image.
    proc.terminate()
    try:
        proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
    logfile.close()
    return text, out_log


def read_guest_report(img, path="/var/log/daily-driver-selftest.txt"):
    """Read a file out of the guest image (the image is a FAT32 disk image).

    The guest writes its self test report into the image; reading it back on
    the host is how the harness sees what the running system actually did.
    """
    try:
        sys.path.insert(0, HERE)
        from fat32img import Fat32Img
    except ImportError as e:
        return None, "no fat32img reader: %s" % e
    try:
        disk = Fat32Img(img)
        try:
            data = disk.read_path(path)
        finally:
            disk.close()
    except Exception as e:                      # noqa: BLE001 - report it
        return None, "%s: %s" % (path, e)
    if data is None:
        return None, "%s is not in the image" % path
    return data.decode("utf-8", "replace"), path


def check_guest_report(results, img, serial=None):
    """The in-guest self test must have run and passed.

    The self test prints its report to the console; the copy it leaves in
    /var/log is read from the image when the guest's file system has been
    flushed, and the console output is used otherwise.
    """
    text, where = read_guest_report(img)
    console = None
    if serial is not None:
        console = "\n".join(l for l in serial.splitlines()
                             if l.startswith("PASS ") or l.startswith("FAIL "))
    if (text is None or "PASS " not in text) and console:
        # The guest's file system may not have flushed the report to the
        # image; its console output carries the same lines.
        text = console
        where = "the guest console"
    if text is None:
        results.check("guest: the in-guest self test ran", False, where)
        return
    failed = [l for l in text.splitlines() if l.startswith("FAIL")]
    passed = [l for l in text.splitlines() if l.startswith("PASS")]
    results.check("guest: the in-guest self test ran", len(passed) > 0,
                  "%d checks in the guest" % len(passed))
    results.check("guest: every in-guest self test check passed", not failed,
                  "; ".join(failed[:3]))
    for needle, description in (
            ("same=1", "the pasteboard daemon answers under both names on one port"),
            ("a UTF-8 paste written by one process is read by another",
             "a paste crosses process boundaries"),
            ("a file URL paste written by one process is read by another",
             "a file URL paste crosses process boundaries"),
            ("a global capture writes a screenshot file",
             "a global capture writes a screenshot file"),
            ("Finder.app and Filer.app carry one bundle identifier",
             "the canonical macOS path is the same bundle"),
            ("opening Finder.app activates that process instead of forking a second copy",
             "Finder.app activates Filer instead of forking a second copy"),
            ("Objective-C blocks execute and support copy/release",
             "Objective-C blocks execute and support copy/release"),
    ):
        results.check("guest: %s" % description, needle in text,
                      "" if needle in text else "not in the report")


def check_boot(phase, results, img, tag, timeout, booted=None, screenshots_dir=None):
    """Check the guest's log.  `booted` carries the serial output of an
    earlier boot so that --all boots the image only once."""
    if booted is not None:
        text, where = booted
    else:
        if not os.path.isfile(img):
            results.check("boot: the image exists", False, img)
            return None
        text, where = boot_and_collect(img, tag, timeout, screenshots_dir)
        if text is None:
            results.check("boot: the guest boots", False, where)
            return None
        results.check("boot: the guest boots", True, where)

    for needle, description in PHASE_BOOT_CHECKS.get(phase, []):
        results.check("boot: %s" % description, needle in text,
                      "" if needle in text else "not in the serial log")

    desktop = "[SUI] mbw-up" in text
    results.check("boot: the desktop comes up", desktop,
                  "" if desktop else "the SystemUI server never reported mbw-up")

    corpses = len(re.findall(r"CORPSE", text))
    results.check("boot: no application corpse", corpses == 0,
                  "%d CORPSE lines" % corpses)

    faults = len(re.findall(r"symbol fault|Symbol fault|dyld\[\d+\]: error",
                            text))
    results.check("boot: no dyld symbol fault", faults == 0,
                  "%d fault lines" % faults)

    bad = re.findall(r"(NSInvalidArgumentException|NSRangeException|"
                     r"unrecognized selector sent to)", text)
    results.check("boot: no uncaught Objective-C exceptions", not bad,
                  " ".join(sorted(set(bad))[:3]))

    missing = re.findall(r"\[WS\] open bundle: no executable for (\S+)", text)
    results.check("boot: every launched bundle has an executable",
                  not missing, " ".join(missing[:3]))

    if screenshots_dir and not results.screenshots_checked:
        results.screenshots_checked = True
        blank = []
        for name in EXPECTED_SCREENSHOTS:
            path = os.path.join(screenshots_dir, name + ".png")
            if not os.path.isfile(path) or os.path.getsize(path) == 0:
                blank.append(name + ".png")
        results.check("boot: every application was screenshotted",
                      not blank, " ".join(blank))

    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", type=int, choices=range(1, 8),
                    help="run the gate of one phase")
    ap.add_argument("--all", action="store_true",
                    help="run every phase gate and the boot check")
    ap.add_argument("--manifest", default=MANIFEST)
    ap.add_argument("--img", default=os.path.join(WORK, "boot.img"))
    ap.add_argument("--tag", default="ddverify")
    ap.add_argument("--boot", action="store_true",
                    help="also boot the image and check the guest log")
    ap.add_argument("--boot-timeout", type=int, default=180)
    ap.add_argument("--screenshots-dir", default=None,
                    help="screendump every app the self test launches into this directory")
    args = ap.parse_args()

    if args.phase is None and not args.all:
        ap.error("one of --phase or --all is required")

    manifest = load_manifest(args.manifest)
    if manifest is None:
        print("missing manifest %s: run make_gui_manifest.py first" %
              args.manifest, file=sys.stderr)
        return 2
    index = manifest_index(manifest)

    results = Results()
    phases = list(range(1, 8)) if args.all else [args.phase]
    booted = None
    if (args.boot or args.all) and len(phases) > 1:
        # One boot serves every phase: the guest's log is read once.
        if not os.path.isfile(args.img):
            results.check("boot: the image exists", False, args.img)
        else:
            booted = boot_and_collect(args.img, args.tag, args.boot_timeout,
                                      args.screenshots_dir)
    for phase in phases:
        print("\n== phase %d ==" % phase, flush=True)
        check_image(phase, results, index)
        if phase == 7:
            check_current_build(results, index)
            check_aliases(results, index)
            check_alias_agents(results, index)
        check_bundle_ids(phase, results, index)
        if args.boot or args.all:
            text = check_boot(phase, results, args.img, "%s%d" % (args.tag, phase),
                              args.boot_timeout, booted, args.screenshots_dir)
            if text is not None:
                booted = (text, "the guest console")
    if args.boot or args.all:
        # The guest wrote its self test report into the image (and to the
        # console); read it back.
        print("\n== guest self test ==", flush=True)
        serial = booted[0] if booted is not None else None
        check_guest_report(results, args.img, serial)

    return results.summary()


if __name__ == "__main__":
    sys.exit(main())
