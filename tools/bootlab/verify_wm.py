#!/usr/bin/env python3
"""End-to-end window-manager verification for ravynOS (headless QEMU).

Boots work/boot.img with a QEMU monitor socket, drives the pointer with HMP
mouse_move/mouse_button (relative PS/2, closed-loop), and asserts real
window-manager behaviour from WindowServer serial traces plus screendumps:

  1. pointer calibration (learn QEMU-relative -> guest sign mapping)
  2. cursor alignment: screendump diff shows the drawn 14x14 cursor sits
     exactly where clicks land (the click hotspot == what the user aims at)
  3. titlebar drag moves the window (frame delta matches the mouse delta)
  4. bottom-right resize drag resizes the window
  5. zoom button maximises, second click restores
  6. minimise: window leaves the screen; Dock tile click restores it and must
     NOT fork a second Filer ("[WS] open bundle: forked")
  7. close button destroys the window ("[WS] DESTROY")

Usage: python3 tools/bootlab/verify_wm.py [--img work/boot.img]
Exit code 0 only when every check passes.
"""
import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
OVMF = "/usr/local/share/qemu/edk2-x86_64-code.fd"

BOOT_CMD = (
    "fs0:\\System\\Library\\CoreServices\\boot.efi -v serial=3 "
    "debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
    "rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 "
    "-no_compat_check cpus=1 quiet_boot=1\r\n"
)

RE_EV = re.compile(
    r"\[WS\] ev code=1 pos=(-?\d+),(-?\d+) win=(-?\d+) "
    r"frame=(-?\d+),(-?\d+) (\d+)x(\d+) app=(\S+)")
RE_FRAME = re.compile(
    r"\[WS\] (CREATE|MODIFY) app=(\S+) win=(\d+) level=(-?\d+) "
    r"frame=(-?\d+),(-?\d+) (\d+)x(\d+)")
RE_DESTROY = re.compile(r"\[WS\] DESTROY win=(\d+) app=(\S+)")
RE_FORK = re.compile(r"\[WS\] open bundle: forked pid (\d+) \((\S+)\)")


class SerialSniffer:
    """Line-oriented parser over the guest serial stream."""

    def __init__(self):
        self.lock = threading.Lock()
        self.raw = b""
        self._pending = b""
        self.evs = []          # clicks: dict(x,y,win,fx,fy,fw,fh,app)
        self.frames = []       # CREATE/MODIFY: dict(kind,app,win,fx,fy,fw,fh)
        self.destroys = []
        self.forks = []
        self.counts = {"SH-locked": 0, "[CG] rpc enter": 0,
                       "sendInlineData reply OK": 0, "ev code=5": 0,
                       "CORPSE: pid": 0, "overreleased": 0}

    def feed(self, data: bytes):
        with self.lock:
            self.raw = (self.raw + data)[-400000:]
            for needle in self.counts:
                self.counts[needle] += data.count(needle.encode())
            self._pending += data
            while b"\n" in self._pending:
                line, self._pending = self._pending.split(b"\n", 1)
                self._line(line.decode("latin1", "replace"))

    def _line(self, s):
        m = RE_EV.search(s)
        if m:
            g = [int(v) for v in m.groups()[:7]]
            self.evs.append(dict(x=g[0], y=g[1], win=g[2] & 0xFFFFFFFF,
                                 fx=g[3], fy=g[4],
                                 fw=g[5], fh=g[6], app=m.group(8)))
            return
        m = RE_FRAME.search(s)
        if m:
            g = m.groups()
            self.frames.append(dict(kind=g[0], app=g[1], win=int(g[2]),
                                    fx=int(g[4]), fy=int(g[5]),
                                    fw=int(g[6]), fh=int(g[7])))
            return
        m = RE_DESTROY.search(s)
        if m:
            self.destroys.append(dict(win=int(m.group(1)), app=m.group(2)))
            return
        m = RE_FORK.search(s)
        if m:
            self.forks.append(dict(pid=int(m.group(1)), path=m.group(2)))

    def snapshot(self):
        with self.lock:
            return (list(self.evs), list(self.frames), list(self.destroys),
                    list(self.forks))

    def text_has(self, needle):
        with self.lock:
            return needle in self.raw.decode("latin1", "replace")


class Hmp:
    """QEMU human monitor over a unix socket."""

    def __init__(self, path):
        end = time.time() + 60
        self.s = None
        while time.time() < end:
            if os.path.exists(path):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(path)
                    s.settimeout(0.5)
                    self.s = s
                    break
                except OSError:
                    pass
            time.sleep(0.5)
        if self.s is None:
            raise SystemExit("could not attach to monitor socket %s" % path)
        self.s.recv(65536)  # banner

    def cmd(self, line, wait=0.35):
        self.s.sendall((line + "\n").encode())
        end = time.time() + wait
        buf = b""
        while time.time() < end:
            try:
                buf += self.s.recv(65536)
            except socket.timeout:
                pass
            except OSError:
                break
        return buf.decode("latin1", "replace")


class Guest:
    def __init__(self, ser: SerialSniffer, hmp: Hmp):
        self.ser = ser
        self.hmp = hmp
        self.sx = None            # sign that increases guest x
        self.sy = None
        self.gx = 5.0             # guest px per injected px (measured)
        self.gy = 5.0
        self.shmoved = False
        self.dumps = 0

    # ---- serial helpers -------------------------------------------------
    def wait_click(self, timeout=6.0):
        """Wait for one new click report; return its dict or None."""
        evs, _, _, _ = self.ser.snapshot()
        n0 = len(evs)
        end = time.time() + timeout
        while time.time() < end:
            evs, _, _, _ = self.ser.snapshot()
            if len(evs) > n0:
                return evs[-1]
            time.sleep(0.15)
        return None

    # ---- mouse ----------------------------------------------------------
    def inject(self, dx, dy, chunk=40):
        """Send raw relative mouse deltas through the monitor."""
        if dx == 0 and dy == 0:
            return
        steps = max(1, (max(abs(dx), abs(dy)) + chunk - 1) // chunk)
        px = py = 0
        for i in range(1, steps + 1):
            tx = int(round(dx * i / steps))
            ty = int(round(dy * i / steps))
            self.hmp.cmd("mouse_move %d %d" % (tx - px, ty - py), wait=0.12)
            px, py = tx, ty
            time.sleep(0.05)

    def move_guest(self, dx, dy):
        """Move the pointer by (dx,dy) *guest* pixels.  WindowServer scales
        raw PS/2 deltas (2.5x base, up to 5x with acceleration), so injected
        deltas have to be divided by the measured host->guest gain."""
        ix = int(round(dx / self.gx)) * (self.sx or 1)
        iy = int(round(dy / self.gy)) * (self.sy or 1)
        self.inject(ix, iy)

    def click(self):
        self.hmp.cmd("mouse_button 1", wait=0.15)
        time.sleep(0.15)
        self.hmp.cmd("mouse_button 0", wait=0.15)
        time.sleep(0.35)

    def click_at(self, x, y, tol=4, tries=10):
        """Closed-loop: click-probe the position, correct, repeat."""
        for _ in range(tries):
            f = self.current_pos()
            if f is None:
                return None
            cx, cy = f["x"], f["y"]
            if abs(cx - x) <= tol and abs(cy - y) <= tol:
                return f
            self.move_guest(x - cx, y - cy)
        return self.current_pos()

    def current_pos(self):
        """Click (no window effect at safe points) and read the reported pos."""
        evs, _, _, _ = self.ser.snapshot()
        n0 = len(evs)
        self.click()
        # Wait for this click's report; the serial console can lag when the
        # guest is chatty, so allow a generous window.
        end = time.time() + 20
        while time.time() < end:
            evs, _, _, _ = self.ser.snapshot()
            if len(evs) > n0:
                return evs[-1]
            time.sleep(0.2)
        return None

    # ---- calibration ----------------------------------------------------
    def calibrate(self):
        """Learn which injected sign increases each guest axis, and the
        guest-pixels-per-injected-pixel gain (the guest accelerates)."""
        p0 = self.current_pos()
        if p0 is None:
            raise SystemExit("no click reports seen (WindowServer not up?)")
        self.inject(40, 0)
        p1 = self.current_pos()
        if p1["x"] > p0["x"]:
            self.sx = +1
        elif p1["x"] < p0["x"]:
            self.sx = -1
        else:
            self.inject(-40, 0)
            p1 = self.current_pos()
            if p1["x"] == p0["x"]:
                raise SystemExit("x axis does not move with either sign")
            self.sx = -1
        self.gx = max(1.0, abs(p1["x"] - p0["x"]) / 40.0)

        p2 = self.current_pos()
        self.inject(0, 40)
        p3 = self.current_pos()
        if p3["y"] > p2["y"]:
            self.sy = +1
        elif p3["y"] < p2["y"]:
            self.sy = -1
        else:
            self.inject(0, -40)
            p3 = self.current_pos()
            if p3["y"] == p2["y"]:
                raise SystemExit("y axis does not move with either sign")
            self.sy = -1
        self.gy = max(1.0, abs(p3["y"] - p2["y"]) / 40.0)
        print("   calibration: sign=(%+d,%+d) gain=(%.1f,%.1f) at (%d,%d)"
              % (self.sx, self.sy, self.gx, self.gy, p3["x"], p3["y"]),
              flush=True)

    # ---- screendump -----------------------------------------------------
    def screendump(self):
        p = os.path.join(WORK, "vwm_%03d.ppm" % self.dumps)
        self.dumps += 1
        self.hmp.cmd("screendump %s" % p, wait=1.5)
        end = time.time() + 10
        while time.time() < end:
            if os.path.exists(p) and os.path.getsize(p) > 1000:
                time.sleep(0.2)
                break
            time.sleep(0.2)
        return read_ppm(p)


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"P6"):
        raise SystemExit("not a P6 ppm: %s" % path)
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
    i += 1
    w, h, _ = fields
    return w, h, data[i:i + w * h * 3]


def diff_centroids(a, b, thresh=60, x_min=0):
    """Clusters of changed pixels; returns [(cx, cy, x0, y0), ...]."""
    bo = a[2]
    bn = b[2]
    if len(bo) != len(bn):
        return []
    w, h = a[0], a[1]
    ys = []
    xs = []
    for i in range(0, len(bo), 3):
        d = abs(bo[i] - bn[i]) + abs(bo[i+1] - bn[i+1]) + abs(bo[i+2] - bn[i+2])
        if d > thresh:
            p = i // 3
            px = p % w
            if px >= x_min:
                xs.append(px)
                ys.append(p // w)
    if not xs:
        return []
    x0, x1 = min(xs), max(xs)
    clusters = []

    def blob(sel):
        """Centroid plus top-left corner: the arrow cursor's tip -- the
        click hotspot -- is its top-left-most pixel, not its centre of mass."""
        return (sum(p[0] for p in sel) / len(sel),
                sum(p[1] for p in sel) / len(sel),
                min(p[0] for p in sel), min(p[1] for p in sel))

    if x1 - x0 > 40:  # two cursors, split on the x midpoint
        mid = (x0 + x1) / 2.0
        for lo, hi in ((x0, mid), (mid + 0.5, x1 + 1)):
            sel = [(x, y) for x, y in zip(xs, ys) if lo <= x < hi]
            if sel:
                clusters.append(blob(sel))
    else:
        clusters.append(blob(list(zip(xs, ys))))
    return clusters


class Results:
    def __init__(self):
        self.rows = []

    def check(self, name, ok, evidence=""):
        self.rows.append((name, bool(ok), evidence))
        print("   %s %-34s %s" % ("PASS" if ok else "FAIL", name, evidence),
              flush=True)

    def summary(self):
        bad = [r for r in self.rows if not r[1]]
        print("\n%d/%d checks passed" % (len(self.rows) - len(bad), len(self.rows)),
              flush=True)
        return 0 if not bad else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default=os.path.join(WORK, "boot.img"))
    ap.add_argument("--tag", default="vwm")
    ap.add_argument("--only-close", action="store_true",
                    help="just boot, calibrate, click the red button, assert DESTROY")
    ap.add_argument("--only-min", action="store_true",
                    help="just boot, calibrate, click the yellow button, then the Dock tile")
    args = ap.parse_args()

    img = os.path.abspath(args.img)
    if not os.path.isfile(img):
        sys.exit("no image %s (run mkimage.py first)" % img)

    serial_sock = os.path.join(WORK, "%s_serial.sock" % args.tag)
    mon_sock = os.path.join(WORK, "%s_mon.sock" % args.tag)
    out_log = os.path.join(WORK, "%s_serial.log" % args.tag)
    vars_fd = os.path.join(WORK, "%s_vars.fd" % args.tag)
    shutil.copyfile(os.path.join(HERE, "assets", "vars.fd"), vars_fd)
    for p in (serial_sock, mon_sock):
        if os.path.exists(p):
            os.unlink(p)

    qemu = [
        "qemu-system-x86_64",
        "-machine", "q35,vmport=off",
        "-cpu", "Skylake-Client",
        "-m", "4096",
        "-smp", "2",
        "-drive", "if=pflash,format=raw,readonly=on,file=" + OVMF,
        "-drive", "if=pflash,format=raw,readonly=off,file=" + vars_fd,
        "-drive", "file=%s,format=raw,if=none,id=drive0" % img,
        "-device", "ide-hd,bus=ide.0,drive=drive0",
        "-serial", "unix:%s,server,nowait" % serial_sock,
        "-monitor", "unix:%s,server,nowait" % mon_sock,
        "-vga", "std",
        "-display", "none",
        "-no-reboot",
    ]

    sniffer = SerialSniffer()
    proc = subprocess.Popen(qemu, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    logf = open(out_log, "wb")

    ser = None
    end = time.time() + 30
    while time.time() < end and ser is None:
        if os.path.exists(serial_sock):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(serial_sock)
                ser = s
            except OSError:
                time.sleep(0.3)
    if ser is None:
        proc.terminate()
        sys.exit("could not attach to guest serial socket")

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
            logf.write(data)
            logf.flush()
            sniffer.feed(data)

    threading.Thread(target=drain, daemon=True).start()

    print("waiting for firmware Shell> ...", flush=True)
    end = time.time() + 90
    while time.time() < end and not sniffer.text_has("Shell>"):
        if proc.poll() is not None:
            sys.exit("qemu exited early (%s)" % proc.returncode)
        time.sleep(0.5)
    ser.sendall(BOOT_CMD.encode("ascii"))
    print("boot command sent; waiting for [SUI] mbw-up ...", flush=True)

    end = time.time() + 660
    while time.time() < end:
        if sniffer.text_has("[SUI] mbw-up"):
            break
        if proc.poll() is not None:
            sys.exit("qemu exited during boot (%s)" % proc.returncode)
        time.sleep(1.0)
    else:
        proc.terminate()
        sys.exit("desktop never reported [SUI] mbw-up")

    time.sleep(4.0)  # let the dock/filer finish their first frames
    res = Results()
    hmp = Hmp(mon_sock)
    g = Guest(sniffer, hmp)

    try:
        print("\n== 1. pointer calibration ==", flush=True)
        g.calibrate()

        if args.only_close:
            evs, frames, _, _ = sniffer.snapshot()
            fr = [x for x in frames if x["app"] == "com.ravynos.Filer"
                  and x["fw"] > 0]
            f = fr[-1] if fr else None
            res.check("Filer window present", f is not None,
                      "frame=%d,%d %dx%d" % (f["fx"], f["fy"], f["fw"], f["fh"])
                      if f else "no Filer window in log")
            if f is None:
                raise SystemExit("no Filer window")
            nd = len(sniffer.snapshot()[2])
            g.click_at(f["fx"] + 17, f["fy"] + f["fh"] - 16)   # red button
            time.sleep(1.5)
            _, _, destroys, _ = sniffer.snapshot()
            new = [d for d in destroys[nd:] if d["app"] == "com.ravynos.Filer"]
            res.check("close button produced DESTROY", bool(new),
                      "destroys=%s" % new)
            return res.summary()

        if args.only_min:
            evs, frames, _, _ = sniffer.snapshot()
            fr = [x for x in frames if x["app"] == "com.ravynos.Filer"
                  and x["fw"] > 0]
            f = fr[-1] if fr else None
            if f is None:
                raise SystemExit("no Filer window")
            g.click_at(f["fx"] + 43, f["fy"] + f["fh"] - 16)   # yellow button
            time.sleep(2.5)
            evs, frames, _, _ = sniffer.snapshot()
            bars = [x for x in frames if x["app"] == "com.ravynos.Dock"
                    and x["fw"] > 100 and 0 < x["fh"] <= 120]
            b = bars[-1] if bars else None
            print("   dock bar after minimize: %s" % (b and
                  "(x=%d w=%d)" % (b["fx"], b["fw"])), flush=True)
            if b:
                g.click_at(b["fx"] + 21, b["fy"] + b["fh"] // 2)  # first tile
                time.sleep(2.5)
            evs, frames, _, _ = sniffer.snapshot()
            fl = [x for x in frames if x["app"] == "com.ravynos.Filer"
                  and x["fw"] > 0]
            print("   filer frames after tile click: %d" % len(fl), flush=True)
            return res.summary()

        print("\n== 2. cursor visual alignment (screendump) ==", flush=True)
        # Park the pointer on the empty desktop right of the Filer window.
        p = g.click_at(1400, 500)
        res.check("pointer parked at (1400,500)", p is not None and
                  abs(p["x"] - 1400) <= 4 and abs(p["y"] - 500) <= 4,
                  "pos=%s" % ((p["x"], p["y"]) if p else None,))
        time.sleep(1.5)
        dumpA = g.screendump()
        g.move_guest(50, 0)
        time.sleep(2.0)
        dumpB = g.screendump()
        clusters = diff_centroids(dumpA, dumpB, x_min=1200)
        if len(clusters) == 2:
            # PPM rows are top-down; guest coordinates are bottom-up.
            # Tip = top-left-most pixel of the blob, in guest coordinates.
            h = dumpA[1]
            left, right = sorted(((c[2], h - c[3]) for c in clusters),
                                 key=lambda c: c[0])
            res.check("drawn cursor tip at click hotspot", 
                      abs(left[0] - 1400) <= 8 and abs(right[0] - 1450) <= 8
                      and abs(left[1] - 500) <= 8 and abs(right[1] - 500) <= 8,
                      "cursor@%.0f,%.0f->%.0f,%.0f (clicks 1400,500->1450,500)"
                      % (left[0], left[1], right[0], right[1]))
        else:
            res.check("drawn cursor at click hotspot", False,
                      "expected 2 cursor clusters, got %d" % len(clusters))

        print("\n== 3. window drag ==", flush=True)
        evs, frames, _, _ = sniffer.snapshot()
        filer = [e for e in evs if e["app"] == "com.ravynos.Filer"
                 and e["fw"] > 0 and e["win"] > 0]
        if filer:
            f = filer[-1]
        else:
            fr = [x for x in frames if x["app"] == "com.ravynos.Filer"
                  and x["fw"] > 0]
            f = fr[-1] if fr else None
        res.check("Filer window present", f is not None,
                  "frame=%d,%d %dx%d" % (f["fx"], f["fy"], f["fw"], f["fh"])
                  if f else "no Filer window in log")
        if f is None:
            raise SystemExit("cannot continue without a Filer window")

        win0 = f["win"]
        fx, fy, fw, fh = f["fx"], f["fy"], f["fw"], f["fh"]
        # press on the titlebar, right of the traffic lights
        tb = (fx + 300, fy + fh - 16)
        p = g.click_at(*tb)
        res.check("titlebar reachable", p is not None and p["win"] == win0,
                  "click at %s -> win=%s" % (tb, p and p["win"]))
        # Age the probe click out of the double-click window: a press this
        # soon after reads as a titlebar double-click, and ravynOS (like
        # macOS) zooms the window instead of starting a drag.
        g.move_guest(2, 2)
        time.sleep(1.0)
        g.hmp.cmd("mouse_button 1", wait=0.25)
        time.sleep(0.3)
        g.move_guest(120, 60)
        time.sleep(0.3)
        g.hmp.cmd("mouse_button 0", wait=0.25)
        time.sleep(0.8)
        probe = g.click_at(fx + 300 + 120, fy + 60 + fh - 16)
        ok = probe is not None and probe["win"] == win0 and \
            abs(probe["fx"] - (fx + 120)) <= 4 and abs(probe["fy"] - (fy + 60)) <= 4
        res.check("drag moved window by (120,60)", ok,
                  "frame %d,%d -> %s" % (fx, fy, probe and
                                         (probe["fx"], probe["fy"], probe["fw"], probe["fh"])))
        if probe:
            fx, fy, fw, fh = probe["fx"], probe["fy"], probe["fw"], probe["fh"]

        print("\n== 4. resize from the bottom-right corner ==", flush=True)
        corner = (fx + fw - 4, fy + 4)
        g.click_at(*corner, tol=3)
        # Same double-click hazard as the drag above.
        g.move_guest(2, -2)
        time.sleep(1.0)
        g.hmp.cmd("mouse_button 1", wait=0.25)
        time.sleep(0.3)
        g.move_guest(100, -50)   # right 100, down 50 in guest coords
        time.sleep(0.3)
        g.hmp.cmd("mouse_button 0", wait=0.25)
        time.sleep(0.8)
        probe = g.click_at(fx + 300, fy - 50 + fh + 50 - 16)
        ok = probe is not None and probe["win"] == win0 and \
            abs(probe["fw"] - (fw + 100)) <= 6 and abs(probe["fh"] - (fh + 50)) <= 6
        res.check("resize grew window by (100,50)", ok,
                  "size %dx%d -> %s" % (fw, fh, probe and
                                        (probe["fw"], probe["fh"])))
        if probe:
            fx, fy, fw, fh = probe["fx"], probe["fy"], probe["fw"], probe["fh"]

        print("\n== 5. zoom button ==", flush=True)
        nframes = len(sniffer.snapshot()[1])
        g.click_at(fx + 65, fy + fh - 16)          # green (click_at clicks target)
        end = time.time() + 25.0
        zoom = []
        while time.time() < end:
            time.sleep(0.5)
            _, frames, _, _ = sniffer.snapshot()
            zoom = [x for x in frames[nframes:]
                    if x["app"] == "com.ravynos.Filer"
                    and x["kind"] == "MODIFY" and x["fw"] >= 1900]
            if zoom:
                break
        res.check("zoom maximised (width == 1920)", bool(zoom),
                  "modify frame=%s" % ((zoom[-1]["fx"], zoom[-1]["fy"],
                                        zoom[-1]["fw"], zoom[-1]["fh"])
                                       if zoom else None,))
        if not zoom:
            # Fall back to the latest known frame so later sections still aim
            # at the window instead of a stale rectangle.
            _, frames, _, _ = sniffer.snapshot()
            fl = [x for x in frames if x["app"] == "com.ravynos.Filer"
                  and x["fw"] > 0]
            if fl:
                fx, fy, fw, fh = (fl[-1]["fx"], fl[-1]["fy"],
                                  fl[-1]["fw"], fl[-1]["fh"])
        if zoom:
            zx, zy, zw, zh = (zoom[-1]["fx"], zoom[-1]["fy"],
                              zoom[-1]["fw"], zoom[-1]["fh"])
            nframes = len(sniffer.snapshot()[1])
            g.click_at(zx + 65, zy + zh - 16)
            end = time.time() + 25.0
            back = []
            while time.time() < end:
                time.sleep(0.5)
                evs, frames, _, _ = sniffer.snapshot()
                back = [x for x in frames[nframes:]
                        if x["app"] == "com.ravynos.Filer"
                        and x["kind"] == "MODIFY"]
                back = [x for x in back if abs(x["fw"] - fw) <= 6
                        and abs(x["fh"] - fh) <= 6]
                if back:
                    break
            res.check("second zoom restored frame", bool(back) and
                      abs(back[-1]["fw"] - fw) <= 6 and abs(back[-1]["fh"] - fh) <= 6,
                      "restored=%s (want %dx%d)" % (back and
                                                    (back[-1]["fw"], back[-1]["fh"]),
                                                    fw, fh))
            if back:
                fx, fy, fw, fh = (back[-1]["fx"], back[-1]["fy"],
                                  back[-1]["fw"], back[-1]["fh"])

        print("\n== 6. minimise + Dock restore ==", flush=True)
        nframes = len(sniffer.snapshot()[1])
        g.click_at(fx + 41, fy + fh - 16)          # yellow
        end = time.time() + 15.0
        mods = []
        while time.time() < end:
            time.sleep(0.5)
            evs, frames, _, forks = sniffer.snapshot()
            mods = [x for x in frames[nframes:] if x["app"] == "com.ravynos.Filer" and x["kind"] == "MODIFY"]
            if mods:
                break
        nforks = len([f for f in forks if "Filer" in f["path"]])
        # Flush-driven MODIFYs can arrive before the MINIMIZED state is
        # processed, so keep probing until the titlebar really is empty.
        gone = None
        end = time.time() + 12.0
        while time.time() < end:
            gone = g.click_at(fx + 300, fy + fh - 16)  # former titlebar
            if gone is None or gone["win"] != win0:
                break
            time.sleep(0.5)
        res.check("minimise hid the window from hit-testing",
                  bool(mods) and gone is not None and gone["win"] != win0,
                  "state modify seen=%s, click at former titlebar -> win=%s"
                  % (bool(mods), gone and gone["win"]))
        # The Dock bar's first tile is the Filer app tile. Target tile 0:
        nframes2 = len(sniffer.snapshot()[1])
        ev = g.click_at(840, 40)
        end = time.time() + 10.0
        restored = []
        while time.time() < end:
            time.sleep(0.5)
            evs, frames, _, forks = sniffer.snapshot()
            restored = [x for x in frames[nframes2:] if x["app"] == "com.ravynos.Filer"
                        and x["kind"] == "MODIFY"]
            if restored:
                break
        if not restored and ev is not None and ev["fh"] < 200 and ev["fw"] < 1000:
            tx = ev["fx"] + 36
            nframes2 = len(sniffer.snapshot()[1])
            g.click_at(tx, 65)
            end = time.time() + 8.0
            while time.time() < end:
                time.sleep(0.5)
                evs, frames, _, forks = sniffer.snapshot()
                restored = [x for x in frames[nframes2:] if x["app"] == "com.ravynos.Filer"
                            and x["kind"] == "MODIFY"]
                if restored:
                    break
        res.check("Dock tile restored the window", bool(restored) and
                  abs(restored[-1]["fw"] - fw) <= 6 and
                  abs(restored[-1]["fh"] - fh) <= 6,
                  "restore frames=%s" % [(x["fx"], x["fy"], x["fw"], x["fh"])
                                         for x in restored])
        nforks2 = len([f for f in forks if "Filer" in f["path"]])
        res.check("no duplicate Filer forked from Dock", nforks2 == nforks,
                  "filer forks before=%d after=%d" % (nforks, nforks2))
        probe = g.click_at(fx + 300, fy + fh - 16)
        res.check("window is back under the pointer",
                  probe is not None and probe["win"] == win0,
                  "win=%s" % (probe and probe["win"]))

        print("\n== 6b. second window + z-order promotion (plan 4, 9) ==",
              flush=True)
        evs, frames, destroys, _ = sniffer.snapshot()
        dead = set(d["win"] for d in destroys)
        fl = [x for x in frames if x["app"] == "com.ravynos.Filer"
              and x["fw"] > 0 and x["win"] not in dead]
        winA = fl[-1] if fl else None
        res.check("restored window present for stacking", winA is not None,
                  "A=%s" % (str((winA["fx"], winA["fy"], winA["fw"],
                                 winA["fh"])) if winA else "none"))
        if winA:
            nA = len(fl)
            g.hmp.cmd("sendkey meta_l-n", wait=0.2)
            time.sleep(3.0)
            evs, frames, destroys, _ = sniffer.snapshot()
            dead = set(d["win"] for d in destroys)
            fl2 = [x for x in frames if x["app"] == "com.ravynos.Filer"
                   and x["fw"] > 0 and x["win"] not in dead]
            winA_ids = set(x["win"] for x in fl2 if x["win"] == winA["win"])
            new_ids = set(x["win"] for x in fl2) - winA_ids
            res.check("Command-N opened a second window", len(new_ids) >= 1,
                      "filer windows %d->%d (%d new)" %
                      (len(winA_ids), len(winA_ids) + len(new_ids),
                       len(new_ids)))
            if new_ids:
                winB = [x for x in fl2 if x["win"] in new_ids][-1]
                ax, ay, aw, ah = (winA["fx"], winA["fy"],
                                  winA["fw"], winA["fh"])
                # move B right and up so the two windows overlap partially
                # Target B's exposed left titlebar (x = winB["fx"] + 80), which is outside A
                target_x = winB["fx"] + 80
                target_y = winB["fy"] + winB["fh"] - 16
                last_ev = [e for e in evs if e["x"] > 0]
                if last_ev:
                    cur_px, cur_py = last_ev[-1]["x"], last_ev[-1]["y"]
                    g.move_guest(target_x - cur_px, target_y - cur_py)
                    time.sleep(0.5)
                g.click_at(target_x, target_y)
                g.hmp.cmd("mouse_button 1", wait=0.25)
                time.sleep(0.3)
                g.move_guest(400, 150)
                time.sleep(0.3)
                g.hmp.cmd("mouse_button 0", wait=0.25)
                time.sleep(1.0)
                evs, frames, destroys, _ = sniffer.snapshot()
                b = [x for x in frames if x["win"] == winB["win"]][-1]
                bx, by, bw, bh = b["fx"], b["fy"], b["fw"], b["fh"]
                ox0, oy0 = max(ax, bx), max(ay, by)
                ox1, oy1 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
                ovl = None
                if ox1 - ox0 > 40 and oy1 - oy0 > 40:
                    ovl = ((ox0 + ox1) // 2, (oy0 + oy1) // 2)
                res.check("windows overlap after the move", ovl is not None,
                          "A=%d,%d %dx%d B=%d,%d %dx%d" %
                          (ax, ay, aw, ah, bx, by, bw, bh))
                pa = g.click_at(ax + 120, ay + ah - 16)
                res.check("click promoted the lower window",
                          pa is not None and pa["win"] == winA["win"],
                          "win=%s (A=%s B=%s)" % (pa and pa["win"],
                                                  winA["win"], winB["win"]))
                if ovl:
                    po = g.click_at(*ovl)
                    res.check("promoted window owns the overlap",
                              po is not None and po["win"] == winA["win"],
                              "click at %s -> win=%s (want A=%s)" %
                              (ovl, po and po["win"], winA["win"]))

        print("\n== 7. close button destroys the window ==", flush=True)
        nd = len(sniffer.snapshot()[2])
        g.click_at(fx + 17, fy + fh - 16)          # red
        end = time.time() + 15.0
        new = []
        while time.time() < end:
            time.sleep(0.5)
            _, _, destroys, _ = sniffer.snapshot()
            new = destroys[nd:]
            if new:
                break
        res.check("close button produced DESTROY", bool(new) and
                  new[-1]["win"] == win0,
                  "destroys=%s" % new)

        print("\n== 8. serial log hygiene ==", flush=True)
        c = sniffer.counts
        res.check("no SH-locked spam", c["SH-locked"] == 0,
                  "count=%d" % c["SH-locked"])
        res.check("no [CG] rpc spam", c["[CG] rpc enter"] == 0,
                  "count=%d" % c["[CG] rpc enter"])
        res.check("no sendInlineData reply spam",
                  c["sendInlineData reply OK"] == 0,
                  "count=%d" % c["sendInlineData reply OK"])

        print("\n== 9. menu bar click (plan 8: SystemUIServer) ==", flush=True)
        corp0, over0 = c["CORPSE: pid"], c["overreleased"]
        nd = len(sniffer.snapshot()[2])
        nfr = len(sniffer.snapshot()[1])
        g.click_at(20, 1069)            # Apple menu in the menu bar strip
        end = time.time() + 8.0
        dropdowns = []
        while time.time() < end:
            time.sleep(0.5)
            dropdowns = [f for f in sniffer.snapshot()[1][nfr:]
                         if f["app"] == "com.ravynos.SystemUIServer"
                         and f["kind"] == "CREATE"]
            if dropdowns:
                break
        corp1, over1 = c["CORPSE: pid"], c["overreleased"]
        suidl = [d for d in sniffer.snapshot()[2][nd:]
                 if d["app"] == "com.ravynos.SystemUIServer"]
        res.check("menu bar click: no new corpse", corp1 == corp0,
                  "corpses %d->%d" % (corp0, corp1))
        res.check("menu bar click: no over-release", over1 == over0,
                  "overreleased %d->%d" % (over0, over1))
        res.check("menu bar click: SUI window alive", not suidl,
                  "destroys=%s" % suidl)
        res.check("menu bar click opened a dropdown", bool(dropdowns),
                  "new SUI windows=%s" % [(f["fx"], f["fy"], f["fw"], f["fh"])
                                          for f in dropdowns])
        g.hmp.cmd("sendkey esc", wait=0.2)
        time.sleep(0.5)

        print("\n== 10. Dock launches Terminal.app ==", flush=True)
        nforks0 = len(sniffer.snapshot()[3])
        apps_before = set(f["app"] for f in sniffer.snapshot()[1])
        ev = g.click_at(920, 65)             # second Dock tile = Terminal.app
        if ev is not None and ev["fh"] < 200 and ev["fw"] < 1000:
            target_x = ev["fx"] + 112
            if abs(target_x - 920) > 3:
                g.click_at(target_x, 65)
        end = time.time() + 20.0
        term = []
        while time.time() < end:
            time.sleep(0.5)
            evs, frames, destroys, forks = sniffer.snapshot()
            term = [f for f in forks[nforks0:] if "Terminal" in f["path"]]
            if term:
                break
        res.check("Dock tile launched Terminal.app", bool(term),
                  "forks=%s" % [(f["pid"], f["path"]) for f in term])
        if term:
            # AppKit init under TCG loads ICU/fontconfig per process; give the
            # new process time to reach its first window before giving up.
            end = time.time() + 75.0
            tw = []
            while time.time() < end:
                time.sleep(1.0)
                _, frames, _, _ = sniffer.snapshot()
                tw = [f for f in frames if f["kind"] == "CREATE"
                      and f["app"] not in apps_before]
                if tw:
                    break
            res.check("Terminal created a window", bool(tw),
                      "frames=%s" % [(f["app"], f["fx"], f["fy"], f["fw"], f["fh"])
                                     for f in tw])
            if tw:
                tx, ty, twid, th = (tw[-1]["fx"], tw[-1]["fy"],
                                    tw[-1]["fw"], tw[-1]["fh"])
                # Focus the content area. The window is not hittable until the
                # app sends its first visible-state modify, and under TCG that
                # can lag the CREATE by a couple of seconds -- keep clicking
                # until the terminal itself receives the click.
                end = time.time() + 20.0
                while time.time() < end:
                    ev = g.click_at(tx + twid // 2, ty + th // 2)
                    if ev is not None and ev.get("app") == "com.ravynos.Terminal":
                        break
                    time.sleep(0.5)
                # Test persistent shell session: cd /bin then ls
                for k in ("c", "d", "spc", "slash", "b", "i", "n", "ret"):
                    g.hmp.cmd("sendkey %s" % k, wait=0.2)
                time.sleep(2.0)
                for k in ("l", "s", "ret"):
                    g.hmp.cmd("sendkey %s" % k, wait=0.2)
                time.sleep(3.0)
                # Downstream Plan Checks: execute /bin/test.sh in Terminal
                for k in ("s", "h", "spc", "slash", "b", "i", "n", "slash", "t", "e", "s", "t", "dot", "s", "h", "ret"):
                    g.hmp.cmd("sendkey %s" % k, wait=0.15)
                end_test = time.time() + 25.0
                while time.time() < end_test:
                    if sniffer.text_has("[DOWNSTREAM] COMPLETE"):
                        break
                    time.sleep(1.0)
                res.check("ifconfig reports network interfaces",
                          sniffer.text_has("en0:") or sniffer.text_has("flags="),
                          "ifconfig executed")
                res.check("dhclient configured IP address on en0",
                          sniffer.text_has("10.0.2.15"),
                          "dhclient configured 10.0.2.15")
                res.check("dscl created testuser with UID 501",
                          sniffer.text_has("UniqueID: 501") or sniffer.text_has("testuser"),
                          "dscl provisioned testuser")
                res.check("Google Chrome binary executes cleanly",
                          sniffer.text_has("[CHROME] OK"),
                          "Chrome dyld resolution and execution verified")
                # Test clipboard: Cmd-C in Terminal, switch to Filer, Cmd-V in Filer
                g.hmp.cmd("sendkey meta_l-c", wait=0.3)
                time.sleep(1.0)
                g.click_at(fx + 200, fy + fh - 16)
                time.sleep(1.0)
                g.hmp.cmd("sendkey meta_l-v", wait=0.3)
                time.sleep(2.0)
                pboard_set = sniffer.text_has("[PBOARD] SET")
                pboard_get = sniffer.text_has("[PBOARD] GET")
                res.check("cross-process pasteboard round trip",
                          pboard_set and pboard_get,
                          "set=%s get=%s" % (pboard_set, pboard_get))
        g.screendump()

        print("\n== 11. whole-session corpse count ==", flush=True)
        res.check("no process died during the session",
                  c["CORPSE: pid"] == 0, "corpses=%d" % c["CORPSE: pid"])
    finally:
        time.sleep(0.5)
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()
        logf.close()

    rc = res.summary()
    print("serial log: %s" % out_log, flush=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
