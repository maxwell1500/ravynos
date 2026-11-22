#!/usr/bin/env python3
"""Probe: does a QEMU sendkey reach the guest PS/2 -> WindowServer -> AppKit?

Boots work/boot.img via launch_interactive, waits for the desktop, then sends
plain keys and a Command-N via HMP, and reports which traces appear on the
serial: [WS] key send (WS delivered to an app) and [NSApp] keyDown (AppKit
got it).  Prints a verdict."""
import os
import re
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
SERIAL = os.path.join(WORK, "interactive_serial.log")
MON = os.path.join(WORK, "interactive_monitor.sock")

subprocess.run(["pkill", "-f", "qemu-system-x86_64-hvffix"], capture_output=True)
time.sleep(1)
try:
    os.unlink(SERIAL)
except FileNotFoundError:
    pass

proc = subprocess.Popen(
    [sys.executable, os.path.join(HERE, "launch_interactive.py"),
     "--img", os.path.join(WORK, "boot.img"), "--accel", "hvf",
     "--cpus", "4", "--mem", "4096"],
    cwd=HERE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    start_new_session=True)

def serial_text():
    try:
        with open(SERIAL, "r", errors="replace") as f:
            return f.read()
    except OSError:
        return ""

deadline = time.time() + 240
while time.time() < deadline:
    t = serial_text()
    if "PRESENT front=com.ravynos.Filer" in t:
        break
    if proc.poll() is not None or re.search(r"panic\(|pid 1 exited", t):
        print("boot failed")
        proc.terminate()
        sys.exit(1)
    time.sleep(3)
else:
    print("timeout waiting for desktop")
    proc.terminate()
    sys.exit(1)

print("desktop up; waiting for Filer window focus")
time.sleep(20)

def hmp(cmd, wait=0.3):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(MON)
    s.settimeout(2.0)
    time.sleep(wait)
    s.sendall((cmd + "\n").encode())
    time.sleep(wait)
    try:
        s.settimeout(1.0)
        s.recv(4096)
    except socket.timeout:
        pass
    s.close()
    time.sleep(wait)

mark = len(serial_text())
for k in ("n", "n", "a", "meta_l-n"):
    hmp("sendkey " + k)
    time.sleep(1.5)

time.sleep(3)
new = serial_text()[mark:]
ws = len(re.findall(r"\[WS\] key send", new))
app = len(re.findall(r"\[NSApp\] keyDown", new))
print("after sendkeys: [WS] key send lines=%d  [NSApp] keyDown lines=%d" % (ws, app))
for line in new.splitlines():
    if "key" in line.lower() and ("WS]" in line or "NSApp" in line):
        print("  ", line[:120])

proc.terminate()
try:
    proc.wait(10)
except subprocess.TimeoutExpired:
    proc.kill()
subprocess.run(["pkill", "-f", "qemu-system-x86_64-hvffix"], capture_output=True)
verdict = "KEYS REACH APPKIT" if app else ("KEYS REACH WS" if ws else "KEYS NEVER REACH WINDOWSERVER")
print("VERDICT:", verdict)
