#!/usr/bin/env python3
"""verify_compat.py -- boot the image and check the ABI conformance report.

The fixtures are stock Mach-O binaries built by Apple's toolchain
(tests/compat/build-fixtures.sh) and run inside the guest by the
com.ravynos.compat launchd job, which writes /var/log/compat.log.

A fixture counts as passed only when its line "FIXTURE <name> rc=0" is
present.  A missing line is a failure: a fixture that never started must
not look like a pass.

    python3 tools/bootlab/verify_compat.py [--img work/boot.img]
                                           [--boot-timeout 300]
"""

import argparse
import atexit
import os
import re
import shutil
import socket
import subprocess
import signal
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
FIXTURES = ("posix", "malloczone", "autorelease", "plist", "backup", "passwd", "accounts", "cocoa", "launch",
            "pasteboard", "net", "icmp", "tcp", "dns", "dns_external", "download", "openurl",
            "foundation", "dmesg", "sandbox", "perms", "spinkill", "printf",
            "screeninfo", "dictkeys")
TCP_PORT = 8123
TCP_MARKER = "RAVYN-TCP-OK"




def kill_guest(proc):
    # The old code swept every qemu-system-x86_64 on the host here; that
    # killed unrelated guests (e.g. an interactive session).  We own the
    # whole session group instead (Popen start_new_session=True below):
    # the wrapper is launch_interactive.py, whose finally-block teardown
    # only runs on KeyboardInterrupt -- a plain SIGTERM to the wrapper
    # orphaned the QEMU child, which kept drawing on screen for hours.
    if proc is not None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=10)
        except Exception:                       # noqa: BLE001
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except Exception:                   # noqa: BLE001
                pass



WEB_BG = (127, 63, 191)        # background of the served http-index.html
# Measured 2026-11-21: with the page at #00a0c0 the teal desktop
# wallpaper matched the +-20 tolerance, and web_check PASSed at
# 34950 px on a screendump with NO Firefox window at all -- the
# false positive masked a real regression (Firefox again never
# opens a browser window, plan item 32).  A magenta/violet page
# colour cannot appear in the wallpaper, so a count > threshold
# can only be a rendered page.


def page_pixels(dump_path):
    """How many pixels of a screendump match the test page's background.

    The page is one flat colour precisely so that "did the browser render it"
    is arithmetic, not image understanding."""
    try:
        with open(dump_path, "rb") as f:
            data = f.read()
    except OSError:
        return 0
    fields = []
    i = 2
    while len(fields) < 3:
        while i < len(data) and data[i:i+1].isspace():
            i += 1
        if data[i:i+1] == b"#":
            while data[i:i+1] != b"\n":
                i += 1
            continue
        j = i
        while j < len(data) and not data[j:j+1].isspace():
            j += 1
        fields.append(int(data[i:j]))
        i = j
    if len(fields) != 3 or not data.startswith(b"P6"):
        return 0
    w, h, _ = fields
    buf = data[i + 1:i + 1 + w * h * 3]
    page_pixels.last_bbox = None
    n = 0
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for k in range(0, len(buf) - 2, 3):
        if (abs(buf[k] - WEB_BG[0]) <= 20 and abs(buf[k + 1] - WEB_BG[1]) <= 20
                and abs(buf[k + 2] - WEB_BG[2]) <= 20):
            n += 1
            px = (k // 3) % w
            py = (k // 3) // w
            x0, x1 = min(x0, px), max(x1, px)
            y0, y1 = min(y0, py), max(y1, py)
    page_pixels.last_bbox = (x0, y0, x1, y1) if n else None
    return n


class Monitor:
    """Just enough of the QEMU human monitor to take a screendump."""

    def __init__(self, path):
        for _ in range(60):
            if os.path.exists(path):
                try:
                    self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    self.s.connect(path)
                    self.s.settimeout(2.0)
                    return
                except OSError:
                    pass
            time.sleep(0.5)
        self.s = None

    def cmd(self, line, wait=1.0):
        if self.s is None:
            return None
        try:
            self.s.sendall((line + "\n").encode())
        except OSError:
            return None
        time.sleep(wait)
        try:
            return self.s.recv(65536)
        except OSError:
            return None


def firefox_rendered_page(monitor_path, out_dir):
    """Wait for the browser to paint the test page; return the best pixel
    count seen.  openurl hands the URL over during the fixture run, so the
    page arrives some seconds later and the first dump can be too early."""
    mon = Monitor(monitor_path)
    best = 0
    box = None
    for i in range(20):
        p = os.path.join(out_dir, "web_%d.ppm" % i)
        mon.cmd("screendump %s" % p, wait=1.5)
        n = page_pixels(p)
        if n > best:
            best, box = n, page_pixels.last_bbox
        if n >= 500:
            break
        time.sleep(8)
    page_pixels.last_bbox = box
    return best


def read_report(img):
    sys.path.insert(0, HERE)
    from fat32img import Fat32Img
    disk = Fat32Img(img)
    try:
        data = disk.read_path("/var/log/compat.log")
    finally:
        disk.close()
    return data.decode("utf-8", "replace") if data else None


def start_tcp_server():
    """Serve the marker on the host so the guest's TCP fixture has a peer.

    QEMU's SLIRP presents 10.0.2.2 as the host, so a guest connection to
    10.0.2.2:TCP_PORT is answered by whatever listens on the host's loopback
    at that port.  Without a listener the fixture can only prove a reset.
    """
    root = tempfile.mkdtemp(prefix="ravyn-tcp-")
    with open(os.path.join(root, "marker.txt"), "w") as f:
        f.write(TCP_MARKER + "\n")
    # A page for the browser to load (plan 3.4).  It is deliberately a solid
    # colour with nothing else on it, so "did the page render" is a single
    # pixel test on a screendump rather than a text-recognition exercise.
    with open(os.path.join(root, "http-index.html"), "w") as f:
        f.write("<!doctype html><html><head><title>ravynOS</title></head>"
                "<body style='margin:0;background:#7f3fbf'>"
                "<h1 style='color:#ffffff;font:48px sans-serif;margin:40px'>"
                "ravynOS web test</h1></body></html>\n")
    proc = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(TCP_PORT),
         "--bind", "127.0.0.1", "--directory", root],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _stop():
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:                       # noqa: BLE001
            proc.kill()
        shutil.rmtree(root, ignore_errors=True)

    atexit.register(_stop)
    return proc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default=os.path.join(WORK, "boot.img"))
    ap.add_argument("--boot-timeout", type=int, default=300)
    args = ap.parse_args()

    serial_path = os.path.join(WORK, "interactive_serial.log")
    try:
        os.unlink(serial_path)
    except FileNotFoundError:
        pass

    # A previous run's report is not evidence for this one: remember it and
    # require the guest to produce a different report (it carries its pid).
    try:
        baseline = read_report(args.img)
    except Exception:                           # noqa: BLE001
        baseline = None

    start_tcp_server()
    proc = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "launch_interactive.py"),
         "--img", os.path.abspath(args.img),
         "--accel", "hvf", "--cpus", "8", "--mem", "8192", "--fixtures"],
        cwd=HERE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        # Own session: kill_guest must be able to reap the QEMU grandchild
        # (the wrapper's finally-block teardown does not run on SIGTERM).
        start_new_session=True)

    deadline = time.time() + args.boot_timeout
    desktop = False
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        try:
            with open(serial_path, "r", errors="replace") as f:
                text = f.read()
        except OSError:
            text = ""
        if "PRESENT front=com.ravynos.Filer" in text or "RAVYNOS_DESKTOP" in text:
            desktop = True
            break
        if re.search(r"panic\(|pid 1 exited", text):
            break
        time.sleep(2)

    # The compat job runs once at boot and can take a while (the DHCP test
    # retries with timeouts).  Wait for it to report completion *before*
    # stopping the guest: once QEMU is gone the image can no longer change,
    # so a report read after the kill can never become complete.
    if desktop:
        deadline = time.time() + 120
        while time.time() < deadline:
            try:
                t = read_report(args.img)
            except Exception:                   # noqa: BLE001
                t = None
            if t and "fixtures done" in t:
                break
            if proc.poll() is not None:
                break
            time.sleep(2)

    # Before the guest goes away: did the browser actually paint the page that
    # the openurl fixture asked for?  The fixture only proves the URL was
    # accepted; this is the only evidence that a web page rendered (plan 3.4).
    web_px = 0
    if desktop:
        web_px = firefox_rendered_page(os.path.join(WORK, "interactive_monitor.sock"),
                                       WORK)

    kill_guest(proc)

    report = None
    for _ in range(30):
        try:
            candidate = read_report(args.img)
        except Exception:                       # noqa: BLE001
            candidate = None
        if candidate and "fixtures done" in candidate and candidate != baseline:
            report = candidate
            break
        time.sleep(2)
    if report is None and baseline is not None:
        print("FAIL the guest produced no new report (baseline unchanged)")
        return 1

    print("=== compat report")
    if not report:
        print("FAIL no report: the guest wrote no /var/log/compat.log")
        return 1
    print(report)

    failures = 0
    # The guest appends (never truncates) compat.log so earlier boots stay
    # readable; judge THIS boot only: everything after the last boot banner.
    # Pre-banner images have no banner, so fall back to the whole report.
    boots = report.split("=== compat boot ")
    section, lines = boots[-1], boots[-1].splitlines()
    # A fixture may record a defect that is known and open rather than pass or
    # fail: "FIXTURE <name> KNOWN-CRASH".  It is reported, loudly, but it does
    # not turn every other result into a failure -- an always-red gate stops
    # being a gate.
    known = []
    for m in re.finditer(r"^FIXTURE (\w+) KNOWN-CRASH(?: \((.*)\))?", section, re.M):
        known.append((m.group(1), m.group(2) or "known crash"))
    for name, why in known:
        print("KNOWN %-10s %s" % (name, why))

    for name in FIXTURES:
        if ("FIXTURE %s rc=0" % name) in lines:
            print("PASS %s" % name)
        else:
            print("FAIL %s" % name)
            failures += 1
    # A fixture the kernel-side list does not know about must not be able to
    # fail silently: the earlier split that added "icmp" to the guest runner
    # still reported compat_check: PASS because only FIXTURES was consulted.
    for line in lines:
        m = re.match(r"FIXTURE (\S+) rc=(\d+)$", line)
        if m and m.group(1) not in FIXTURES and m.group(2) != "0":
            print("FAIL unknown fixture %s rc=%s" % (m.group(1), m.group(2)))
            failures += 1

    # Reported separately: the fixtures are a stock-binary ABI suite, the page
    # render is plan 3.4.  Folding one into the other made a green suite look
    # red, or a red browser look like an ABI regression.
    print("%s firefox rendered the test page   %d px bbox=%s"
          % ("PASS" if web_px >= 500 else "FAIL", web_px,
             getattr(page_pixels, "last_bbox", None)))
    print("web_check: %s" % ("PASS" if web_px >= 500 else "FAIL"))

    print("compat_check: %s" % ("PASS" if failures == 0 else "FAIL"))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
