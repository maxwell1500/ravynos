#!/usr/bin/env python3
"""Same keyboard probe as probe_keyboard.py but with verify_wm's exact QEMU
invocation (plain binary, TCG, -display none) to isolate why verify_wm sees
zero key events while the hvffix boot sees them all."""
import os
import re
import shutil
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
OVMF = "/usr/local/share/qemu/edk2-x86_64-code.fd"

img = os.path.join(WORK, "boot.img")
serial_sock = os.path.join(WORK, "kb2_serial.sock")
mon_sock = os.path.join(WORK, "kb2_mon.sock")
out_log = os.path.join(WORK, "kb2_serial.log")
vars_fd = os.path.join(WORK, "kb2_vars.fd")
shutil.copyfile(os.path.join(HERE, "assets", "vars.fd"), vars_fd)
for p in (serial_sock, mon_sock, out_log):
    if os.path.exists(p):
        os.unlink(p)

subprocess.run(["pkill", "-f", "qemu-system-x86_64"], capture_output=True)
time.sleep(1)

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
    "-display", "none",
    "-no-reboot",
]
proc = subprocess.Popen(qemu, stdout=subprocess.DEVNULL,
                        stderr=open(os.path.join(WORK, "kb2_qemu.err"), "wb"))
logf = open(out_log, "wb")


def connect(path):
    end = time.time() + 30
    while time.time() < end:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
            s.settimeout(0.5)
            return s
        except OSError:
            time.sleep(0.5)
    return None


ser = connect(serial_sock)
mon = connect(mon_sock)
deadline = time.time() + 600  # TCG boots slow


def pump_serial():
    try:
        ser.settimeout(0.2)
        data = ser.recv(65536)
        if data:
            logf.write(data)
            logf.flush()
    except socket.timeout:
        pass


booted = False
# TCG boots via the UEFI shell: wait for the prompt, type the boot command.
while time.time() < deadline:
    pump_serial()
    try:
        with open(out_log, "r", errors="replace") as f:
            t = f.read()
    except OSError:
        t = ""
    if "Shell>" in t:
        BOOT_CMD = (
            "fs0:\\System\\Library\\CoreServices\\boot.efi -v serial=3 "
            "debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
            "rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 "
            "-no_compat_check cpus=1 quiet_boot=1 nofleet=1\r\n"
        )
        if ser:
            ser.sendall(BOOT_CMD.encode("ascii"))
        print("boot command sent")
        break
    if proc.poll() is not None:
        break

while time.time() < deadline:
    pump_serial()
    try:
        with open(out_log, "r", errors="replace") as f:
            t = f.read()
    except OSError:
        t = ""
    if "PRESENT front=com.ravynos.Filer" in t:
        booted = True
        break
    if proc.poll() is not None:
        break

if not booted:
    print("no desktop in 600s (TCG)")
    proc.kill()
    sys.exit(1)

print("TCG desktop up; settling 30s")
time.sleep(30)
mark = os.path.getsize(out_log)

for k in ("n", "n", "a", "meta_l-n"):
    mon.sendall(("sendkey " + k + "\n").encode())
    t_end = time.time() + 3
    while time.time() < t_end:
        pump_serial()
        time.sleep(0.2)

time.sleep(5)
end = time.time() + 5
while time.time() < end:
    pump_serial()

with open(out_log, "r", errors="replace") as f:
    f.seek(mark)
    new = f.read()
ws = len(re.findall(r"\[WS\] key send", new))
app = len(re.findall(r"\[NSApp\] keyDown", new))
print("TCG sendkeys: [WS] key send=%d  [NSApp] keyDown=%d" % (ws, app))
for line in new.splitlines():
    if "key" in line.lower() and ("WS]" in line or "NSApp" in line):
        print("  ", line[:120])

proc.kill()
subprocess.run(["pkill", "-f", "qemu-system-x86_64"], capture_output=True)
print("VERDICT:", "KEYS REACH APPKIT (TCG)" if app else
      ("KEYS REACH WS (TCG)" if ws else "KEYS NEVER REACH WINDOWSERVER (TCG)"))
