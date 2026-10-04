#!/usr/bin/env python3
"""Supplementary pixel capture: prove the KERNEL framebuffer is live.

fb_probe.py drives boot.py's own QEMU (unmodified) and captures the real image,
but with `serial=3` the kernel routes console output to the UART, so the
graphics console (vc_*) is never the active console and the 1024x768 surface
stays black.  That is a property of the boot args, not of the framebuffer.

This script runs its OWN QEMU with the identical boot.py command line except
that the `serial=3` boot-arg is dropped, so the kernel's video console is the
active console and it renders its own kprintf text into the framebuffer handed
over by the loader (boot_args.Video, base 0x80000000, 1024x768).  A screendump
then contains non-trivial pixels, proving the framebuffer is live.

Nothing in boot.py / mkimage.py is touched.  Serial is exposed as a socket
chardev with logfile= so we can both type the boot command and watch the
firmware Shell> prompt incrementally.
"""
import os
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
SER = os.path.join(WORK, "serial_gfx.sock")
SERLOG = os.path.join(WORK, "serial_gfx.log")
MON = os.path.join(WORK, "mon_gfx.sock")
QEMULOG = os.path.join(WORK, "qemu_gfx.log")
OVMF_CODE = "/usr/local/share/qemu/edk2-x86_64-code.fd"

BOOT_CMD = ("fs0:\\System\\Library\\CoreServices\\boot.efi -v "
            "debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
            "rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 "
            "-no_compat_check cpus=1 quiet_boot=1")


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


def logtext():
    try:
        return open(SERLOG, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def main():
    for p in (SER, MON):
        if os.path.exists(p):
            os.unlink(p)
    import shutil
    shutil.copyfile(os.path.join(HERE, "assets", "vars.fd"),
                    os.path.join(WORK, "vars_gfx.fd"))

    qemu_cmd = [
        "qemu-system-x86_64",
        "-machine", "q35,vmport=off",
        "-cpu", "Skylake-Client",
        "-m", "4096",
        "-smp", "2",
        "-drive", "if=pflash,format=raw,readonly=on,file=" + OVMF_CODE,
        "-drive", "if=pflash,format=raw,readonly=off,file=" +
                  os.path.join(WORK, "vars_gfx.fd"),
        "-drive", "file=%s,format=raw,if=none,id=drive0" %
                  os.path.join(WORK, "boot.img"),
        "-device", "ide-hd,bus=ide.0,drive=drive0",
        "-chardev", "socket,id=ser0,path=%s,server=on,wait=off,"
                    "logfile=%s,logappend=off" % (SER, SERLOG),
        "-serial", "chardev:ser0",
        "-monitor", "unix:%s,server,nowait" % MON,
        "-vga", "std",
        "-display", "none",
        "-no-reboot",
        "-D", QEMULOG,
    ]
    print("launching own QEMU (graphics console, no serial=3)", flush=True)
    proc = subprocess.Popen(qemu_cmd)

    # wait for OVMF Shell> prompt in the incremental serial log
    sock = None
    for _ in range(120):
        if proc.poll() is not None:
            print("QEMU exited early code=%s" % proc.returncode)
            return 1
        if "Shell>" in logtext() and os.path.exists(SER):
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.connect(SER)
                break
            except OSError:
                sock = None
        time.sleep(1)
    if sock is None:
        print("ERROR: no Shell> / serial socket")
        proc.terminate()
        return 1
    print("Shell> seen; sending boot command (no serial=3)", flush=True)
    time.sleep(3)
    sock.sendall(BOOT_CMD.encode() + b"\r\n")

    # connect monitor
    ms = None
    for _ in range(30):
        if os.path.exists(MON):
            try:
                ms = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                ms.connect(MON)
                break
            except OSError:
                ms = None
        time.sleep(1)
    if ms is None:
        print("ERROR: no monitor socket")
        proc.terminate()
        return 1
    ms.settimeout(3)
    time.sleep(0.5)
    try:
        ms.recv(4096)
    except socket.timeout:
        pass

    t0 = time.time()
    for t in (40, 60, 90, 120, 150, 180, 210, 240, 270):
        while time.time() - t0 < t:
            if proc.poll() is not None:
                break
            time.sleep(0.5)
        if proc.poll() is not None:
            break
        path = "/tmp/ravyn_gfx_%03d.ppm" % t
        resp = monitor_cmd(ms, "screendump %s" % path)
        ok = os.path.exists(path)
        print("[t=%3ds] %s %s" % (t, "OK" if ok else "FAIL",
                                  os.path.getsize(path) if ok else resp[:120]),
              flush=True)
    try:
        monitor_cmd(ms, "quit")
    except Exception:
        pass
    ms.close()
    try:
        proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    print("done; serial log=%s" % SERLOG)
    return 0


if __name__ == "__main__":
    sys.exit(main())
