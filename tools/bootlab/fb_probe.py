#!/usr/bin/env python3
"""Pixel proof of the live framebuffer, driven through boot.py's own QEMU.

boot.py is NOT modified.  It already passes
    -monitor unix:work/mon_<mode>.sock,server,nowait
so while boot.py owns QEMU we attach to that monitor socket from this second
process and issue QEMU's `screendump` command, which writes a PPM of the
current VGA surface.  This works with `-display none` because the std-VGA
device still owns a display surface.

Timing note (important): boot.py buffers the whole serial stream in memory and
writes the --out log ONLY after it terminates QEMU (boot.py lines 175-176), so
the log file cannot be polled while the guest is running.  The reliable live
anchor is therefore boot.py's own stdout line
"boot command sent at <t>s (kernel budget ...)", after which the loader and
then the kernel run; initialize_screen happens early in kernel boot.  We take
screendumps on a dense schedule after that anchor so the exact moment is
covered regardless of how long the kernel takes.

Usage:
  fb_probe.py                       # work/boot.img -> work/serial_fbprobe.log
  fb_probe.py --img work/boot_gui.img --out work/serial_gui.log \
              --prefix /tmp/ravyn_gui
"""
import argparse
import os
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
LOG = os.path.join(WORK, "serial_fbprobe.log")

# Schedule of screendumps after the boot command is sent (seconds).
SCHEDULE = [20, 35, 50, 65, 80, 95, 110, 125, 150, 180, 210, 240]

anchor = threading.Event()
boot_lines = []


def pump_boot_stdout(proc):
    for line in proc.stdout:
        boot_lines.append(line.rstrip("\n"))
        if "boot command sent" in line:
            anchor.set()
        print("[boot.py] " + line.rstrip("\n"), flush=True)


def monitor_cmd(sock, cmd, wait=3.0):
    sock.sendall(cmd.encode() + b"\n")
    sock.settimeout(wait)
    buf = b""
    try:
        while True:
            d = sock.recv(4096)
            if not d:
                break
            buf += d
            if buf.rstrip().endswith(b"(qemu)"):
                break
    except socket.timeout:
        pass
    return buf.decode("utf-8", "replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default=os.path.join(WORK, "boot.img"))
    ap.add_argument("--out", default=LOG)
    ap.add_argument("--mode", default="full")
    ap.add_argument("--window", type=int, default=300)
    ap.add_argument("--prefix", default="/tmp/ravyn_fb")
    ap.add_argument("--schedule",
                    default="20,35,50,65,80,95,110,125,150,180,210,240")
    ap.add_argument("--regs", action="store_true",
                    help="also issue info registers/threads and x/12i $rip")
    args = ap.parse_args()

    mon = os.path.join(WORK, "mon_%s.sock" % args.mode)
    prefix = args.prefix
    schedule = [int(x) for x in args.schedule.split(",")]
    first = min(schedule, key=lambda t: abs(t - 65))
    second = min(schedule, key=lambda t: abs(t - 125))

    for p in ("%s.ppm" % prefix, "%s2.ppm" % prefix):
        if os.path.exists(p):
            os.unlink(p)

    proc = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "boot.py"),
         "--img", args.img,
         "--mode", args.mode, "--window", str(args.window),
         "--out", args.out],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1)
    threading.Thread(target=pump_boot_stdout, args=(proc,), daemon=True).start()

    print("waiting for boot command anchor...", flush=True)
    while not anchor.wait(1.0):
        if proc.poll() is not None:
            print("boot.py exited before anchor (code %s)" % proc.returncode)
            return 1
    t0 = time.time()
    print("anchor at %.1fs; starting screendump schedule %s" % (0.0, schedule),
          flush=True)

    # connect to QEMU monitor
    sock = None
    for _ in range(30):
        if os.path.exists(mon):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(mon)
                sock = s
                break
            except OSError:
                pass
        time.sleep(1)
    if sock is None:
        print("ERROR: could not connect to monitor socket %s" % mon)
        proc.terminate()
        return 1
    sock.settimeout(3)
    time.sleep(0.5)
    try:
        print("[monitor banner] " + repr(sock.recv(4096)[:200]))
    except socket.timeout:
        pass

    dumped = []
    for t in schedule:
        while time.time() - t0 < t:
            if proc.poll() is not None:
                break
            time.sleep(0.5)
        if proc.poll() is not None:
            print("boot.py/QEMU exited before t=%ds" % t)
            break
        path = "%s_%03d.ppm" % (prefix, t)
        resp = monitor_cmd(sock, "screendump %s" % path)
        ok = os.path.exists(path)
        sz = os.path.getsize(path) if ok else -1
        print("[t=%3ds] screendump %s -> %s (exists=%s size=%s) resp=%r"
              % (t, path, "OK" if ok else "FAIL", ok, sz, resp.strip()[:160]),
              flush=True)
        if args.regs:
            monitor_cmd(sock, "stop")
            outs = {}
            for cpu in ("0", "1"):
                monitor_cmd(sock, "cpu %s" % cpu)
                for mc in ("info registers", "info cpus",
                           "x/32i $rip", "x/48gx $rsp"):
                    mout = monitor_cmd(sock, mc, wait=5.0)
                    outs[(cpu, mc)] = mout
                    print("[t=%3ds][cpu%s][monitor] %s -> %s"
                          % (t, cpu, mc, mout.strip()[:3000]), flush=True)
            # Derive image bases from user-stack markers / current RIP and read
            # the Mach-O magic.  MUST run in cpu0's address space.
            import re as _re
            monitor_cmd(sock, "cpu 0")
            cands = {}
            def _addcand(v, off, what):
                if v > 0x100000000 and v < 0x800000000000 and (v & 0xFFF) == (off & 0xFFF):
                    cands.setdefault(v - off, what)
            for src, tag in ((outs.get(("0", "x/48gx $rsp"), ""), "stack"),
                             (outs.get(("0", "info registers"), ""), "rip")):
                for m in _re.finditer(r"(?:0x)?([0-9a-fA-F]{16})", src):
                    v = int(m.group(1), 16)
                    _addcand(v, 0x27FAF, "launchd(%s, _waitpid_loop+0x1f)" % tag)
                    _addcand(v, 0xBAD82, "libsystem_c(%s, _waitpid+0x22)" % tag)
            for base, what in cands.items():
                for mc in ("x/4gx 0x%x" % base, "x/8i 0x%x" % base):
                    mout = monitor_cmd(sock, mc, wait=5.0)
                    print("[t=%3ds][%s base=0x%x][monitor] %s -> %s"
                          % (t, what, base, mc, mout.strip()[:1200]), flush=True)
            monitor_cmd(sock, "cont")
        if ok:
            dumped.append((t, path))
            if t == first:
                subprocess.run(["cp", path, "%s.ppm" % prefix])
            if t == second:
                subprocess.run(["cp", path, "%s2.ppm" % prefix])

    # terminate boot.py's QEMU cleanly
    try:
        monitor_cmd(sock, "quit")
    except Exception as e:
        print("quit error: %s" % e)
    sock.close()
    try:
        proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    print("boot.py exited code=%s; log=%s" % (proc.returncode, args.out))
    print("dumps:", dumped)
    return 0


if __name__ == "__main__":
    sys.exit(main())
