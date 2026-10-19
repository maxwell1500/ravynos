#!/usr/bin/env python3
"""Launch interactive ravynOS desktop session in QEMU with native Cocoa display and VNC."""

import os
import re
import shutil
import socket
import subprocess
import argparse
import threading
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))

# Prefer the locally built QEMU when present.  The stock 11.0.1 HVF backend
# maps the VGA vram writable, so the dirty-log protect never lands on the
# mapped section and the display never refreshes under -accel hvf (black
# window; fine under tcg).  qemu-system-x86_64-hvffix is that build plus the
# fix in tools/bootlab/qemu-hvf-dirty-tracking.patch.
QEMU = os.environ.get("QEMU_BIN")
if not QEMU:
    QEMU = ("qemu-system-x86_64-hvffix"
            if shutil.which("qemu-system-x86_64-hvffix")
            else "qemu-system-x86_64")
WORK = os.path.join(HERE, "work")
IMG = os.path.join(WORK, "boot.img")
VARS = os.path.join(WORK, "vars_interactive.fd")
OVMF = "/usr/local/share/qemu/edk2-x86_64-code.fd"

def supported_accels():
    try:
        r = subprocess.run([QEMU, "-accel", "?"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2)
        return set(line.strip() for line in r.stdout.decode("utf-8", "replace").splitlines())
    except Exception:
        return {"tcg"}

parser = argparse.ArgumentParser(description="Launch interactive ravynOS desktop session in QEMU")
parser.add_argument("--accel", choices=("auto", "tcg", "hvf", "kvm"), default="auto", help="QEMU accelerator; auto prefers HVF on macOS when available")
parser.add_argument("--cpus", type=int, default=None, help="number of CPU cores to expose to the kernel and QEMU (default: all host CPUs when accelerated, 1 under TCG, where extra vCPUs measured slower)")
args = parser.parse_args()

accels = supported_accels()
if args.accel == "auto":
    if sys.platform.startswith("darwin"):
        accel = "hvf" if "hvf" in accels else "tcg"
    else:
        accel = "kvm" if "kvm" in accels else "tcg"
else:
    accel = args.accel
    if accel not in accels:
        sys.exit(f"Accelerator {accel} is not available; QEMU reports: {' '.join(sorted(accels))}")

# CPU count.  With a hardware accelerator every host CPU is a real vCPU, so
# default to all of them; under TCG extra vCPUs measured SLOWER (menubar
# 90s -> 128s, settle 124s -> 170s), so TCG stays at one.
ncpu = os.cpu_count() or 1
if args.cpus is None:
    cpus = 1 if accel == "tcg" else ncpu
else:
    cpus = args.cpus
if cpus < 1 or cpus > ncpu:
    sys.exit("Use --cpus between 1 and %d for this bootlab harness." % ncpu)

if not os.path.isfile(IMG):
    sys.exit(f"Image not found: {IMG}")

serial_sock_path = os.path.join(WORK, "interactive_serial.sock")
serial_log_path = os.path.join(WORK, "interactive_serial.log")
monitor_sock_path = os.path.join(WORK, "interactive_monitor.sock")

def cleanup():
    for p in (serial_sock_path, monitor_sock_path):
        if os.path.exists(p):
            try: os.unlink(p)
            except: pass

cleanup()
shutil.copyfile(os.path.join(HERE, "assets", "vars.fd"), VARS)

qemu_cmd = [
    QEMU,
    "-machine", "q35,vmport=off",
    # Under a hardware accelerator the real CPU is the right model (and the
    # only one that produces no "host doesn't support requested feature"
    # warnings); TCG keeps the fixed model it was tuned with.
    "-cpu", ("host" if accel != "tcg" else "Skylake-Client"),
    "-m", "4096",
    "-smp", str(cpus),
    "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF}",
    "-drive", f"if=pflash,format=raw,readonly=off,file={VARS}",
    "-drive", f"file={IMG},format=raw,if=none,id=drive0",
    "-device", "ide-hd,bus=ide.0,drive=drive0",
    "-serial", f"unix:{serial_sock_path},server,nowait",
    "-monitor", f"unix:{monitor_sock_path},server,nowait",
    "-vga", "std",
    "-display", "cocoa",
    "-vnc", "127.0.0.1:0",
    "-no-reboot",
]
if accel != "tcg":
    qemu_cmd += ["-accel", accel]

print("Launching QEMU with native Cocoa window and VNC (127.0.0.1:5900) [%s, %d cpu%s]..." % (accel, cpus, "s" if cpus > 1 else ""), flush=True)
proc = subprocess.Popen(qemu_cmd)

def wait_sock(p, timeout=20.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if os.path.exists(p):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                s.connect(p)
                return s
            except Exception:
                time.sleep(0.1)
        time.sleep(0.1)
    raise RuntimeError(f"timeout waiting for {p}")

serial_sock = wait_sock(serial_sock_path, 20.0)
serial_sock.setblocking(False)
log_f = open(serial_log_path, "wb")
accum = bytearray()
accum_lock = threading.Lock()

# Drain the serial socket on its own thread.  Polling it once a second (the
# old shape) could not keep up with the boot log: the socket buffer filled,
# qemu dropped the overflow, and the log lost whatever happened during the
# gap -- including, in one case, most of /etc/rc's output.
def _serial_reader():
    while True:
        try:
            c = serial_sock.recv(4096)
        except BlockingIOError:
            time.sleep(0.005)
            continue
        except Exception:
            break
        if not c:
            break
        log_f.write(c)
        log_f.flush()
        with accum_lock:
            accum.extend(c)

threading.Thread(target=_serial_reader, daemon=True).start()

def read_serial():
    with accum_lock:
        return accum.decode("latin1", errors="replace")

print("Waiting for UEFI firmware Shell> prompt...", flush=True)
t0 = time.time()
while time.time() - t0 < 90.0:
    txt = read_serial()
    if "Shell>" in txt:
        print("Firmware Shell> detected, sending boot command...", flush=True)
        break
    time.sleep(0.5)
else:
    print("Shell prompt not seen within timeout, sending boot command anyway...", flush=True)

boot_cmd = (
    "fs0:\\System\\Library\\CoreServices\\boot.efi -v serial=3 "
    "debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
    "rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 "
    f"-no_compat_check cpus={cpus} quiet_boot=1\r\n"
)
serial_sock.sendall(boot_cmd.encode("ascii"))

print("Booting ravynOS kernel and launching desktop GUI...", flush=True)
t_ready = time.time() + 600
ready = False
while time.time() < t_ready:
    txt = read_serial()
    if "[SUI] mbw-up" in txt:
        ready = True
        break
    if proc.poll() is not None:
        sys.exit(f"QEMU exited early with code {proc.returncode}")
    time.sleep(1.0)

if ready:
    print("\n" + "="*68, flush=True)
    print("RAVYNOS_DESKTOP_READY", flush=True)
    print("The ravynOS Desktop is now running and live for interactive testing!", flush=True)
    print("  1. Native Cocoa Window: Look for the 'QEMU' window on your screen.", flush=True)
    print("  2. Screen Sharing / VNC: Connect via vnc://127.0.0.1:5900", flush=True)
    print("="*68 + "\n", flush=True)
else:
    print("Warning: Timed out waiting for [SUI] mbw-up, but QEMU is still running.", flush=True)

# Keep process alive and monitor serial
try:
    while proc.poll() is None:
        read_serial()
        time.sleep(1.0)
except KeyboardInterrupt:
    print("\nShutting down interactive QEMU session...", flush=True)
finally:
    proc.terminate()
    try: proc.wait(timeout=5)
    except: proc.kill()
    cleanup()
