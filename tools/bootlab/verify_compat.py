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
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
FIXTURES = ("posix", "malloczone", "passwd", "accounts", "cocoa", "launch", "pasteboard", "net",
            "icmp", "tcp")
TCP_PORT = 8123
TCP_MARKER = "RAVYN-TCP-OK"


def qemu_pids():
    try:
        out = subprocess.run(["pgrep", "-f", "qemu-system-x86_64"],
                             capture_output=True, text=True).stdout
    except OSError:
        return []
    return [int(x) for x in out.split()]


def kill_guest(proc):
    if proc is not None:
        try:
            proc.terminate()
            proc.wait(timeout=10)
        except Exception:                       # noqa: BLE001
            try:
                proc.kill()
            except Exception:                   # noqa: BLE001
                pass
    for pid in qemu_pids():
        try:
            os.kill(pid, 15)
        except OSError:
            pass


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
         "--accel", "hvf", "--cpus", "8", "--mem", "8192"],
        cwd=HERE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

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
    lines = report.splitlines()
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

    print("compat_check: %s" % ("PASS" if failures == 0 else "FAIL"))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
