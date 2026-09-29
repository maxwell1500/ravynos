#!/usr/bin/env python3
"""Headless QEMU boot of a bootlab image; serial log to stdout/work.

  python3 tools/bootlab/boot.py --img work/boot.img --mode full [--window 210]

Modes:  split    boot.efi -s                     (split CR3 user/kernel page tables)
        full     no -s                            (shared CR3)
        fallback boot.efi -s -no_shared_cr3       (legacy workaround)

Always freshly copies assets/vars.fd to a per-run vars file: a stale NVRAM
from another run causes a UEFI #UD at kernel handoff (proven empirically).
Startup: disk BOOTX64.EFI is Clover; this flow ignores firmware boot order —
the harness waits for the OVMF Shell> prompt and types the canonical boot
command itself.
"""
import argparse
import os
import shutil
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
QEMU = "qemu-system-x86_64"
OVMF_CODE = "/usr/local/share/qemu/edk2-x86_64-code.fd"

BOOT_BASE = ("fs0:\\System\\Library\\CoreServices\\boot.efi -v serial=1 "
             "debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
             "rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 "
             "-no_compat_check cpus=1 quiet_boot=1")

def boot_cmd(mode):
    if mode == "split":
        return BOOT_BASE + " -s"
    if mode == "fallback":
        return BOOT_BASE + " -s -no_shared_cr3"
    if mode == "full":
        return BOOT_BASE
    sys.exit("unknown mode: %s" % mode)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default=os.path.join(HERE, "work", "boot.img"))
    ap.add_argument("--mode", default="full", choices=["split", "full", "fallback"])
    ap.add_argument("--window", type=int, default=210,
                    help="seconds to watch serial after boot cmd sent")
    ap.add_argument("--out", default=None,
                    help="serial log path (default work/serial_<mode>.log)")
    args = ap.parse_args()

    work = os.path.join(HERE, "work")
    os.makedirs(work, exist_ok=True)
    img = os.path.abspath(args.img)
    if not os.path.isfile(img):
        sys.exit("no image %s (run mkimage.py)" % img)

    out = args.out or os.path.join(work, "serial_%s.log" % args.mode)
    serial_sock = os.path.join(work, "serial_%s.sock" % args.mode)
    mon_sock = os.path.join(work, "mon_%s.sock" % args.mode)
    qemu_log = os.path.join(work, "qemu_%s.log" % args.mode)
    vars_fd = os.path.join(work, "vars_%s.fd" % args.mode)
    shutil.copyfile(os.path.join(HERE, "assets", "vars.fd"), vars_fd)

    for s in (serial_sock, mon_sock):
        if os.path.exists(s):
            os.unlink(s)

    qemu_cmd = [
        QEMU,
        "-machine", "q35,vmport=off",
        "-cpu", "Skylake-Client",
        "-m", "4096",
        "-smp", "2",
        "-drive", "if=pflash,format=raw,readonly=on,file=" + OVMF_CODE,
        "-drive", "if=pflash,format=raw,readonly=off,file=" + vars_fd,
        "-drive", "file=%s,format=raw,if=none,id=drive0" % img,
        "-device", "ide-hd,bus=ide.0,drive=drive0",
        "-serial", "unix:%s,server,nowait" % serial_sock,
        "-monitor", "unix:%s,server,nowait" % mon_sock,
        "-vga", "std",
        "-display", "none",
        "-no-reboot",
        "-d", "cpu_reset,int",
        "-D", qemu_log,
    ]
    print("launching QEMU mode=%s img=%s" % (args.mode, img), flush=True)
    proc = subprocess.Popen(qemu_cmd)

    cmd = boot_cmd(args.mode).encode() + b"\r\n"
    output = b""
    sent = False
    sock = None
    deadline_connect = time.time() + 30
    while sock is None and time.time() < deadline_connect:
        time.sleep(1)
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(serial_sock)
            sock.settimeout(1)
        except OSError:
            sock.close()
            sock = None
    if sock is None:
        proc.terminate()
        sys.exit("could not attach to serial socket")

    # The window is the KERNEL's budget, not a total for the whole run.
    # It used to start at QEMU launch, which charged the firmware's
    # "Shell>" wait against the kernel's boot time. That wait has been
    # observed at both ~12.5s and 55.7s in one session on the same image
    # with a freshly-copied vars.fd, so a slow firmware prompt could eat
    # ~43s of a 150s window and expire it mid-boot. The result read as
    # "the kernel did not boot" when in fact the kernel was healthy and
    # still coming up (2026-09-27 run, exit 2, truncated at 496 of 777
    # log lines). Charging the firmware wait to the firmware makes the
    # window mean one thing: seconds the kernel gets.
    #
    # Before the command is sent this is still bounded, so a hung firmware
    # cannot run forever; worst case is 2x window, which is correct rather
    # than wasteful because the two phases are genuinely sequential.
    start_time = time.time()
    boot_deadline = None
    while True:
        now = time.time()
        if boot_deadline is None:
            if now - start_time >= args.window:
                break
        elif now >= boot_deadline:
            break
        if proc.poll() is not None:
            print("QEMU exited early code=%s at %.1fs" %
                  (proc.returncode, time.time() - start_time), flush=True)
            try:
                while True:
                    data = sock.recv(4096)
                    if not data:
                        break
                    output += data
            except Exception:
                pass
            break
        try:
            data = sock.recv(4096)
            if data:
                output += data
                if b"Shell>" in output and not sent:
                    time.sleep(5)
                    sock.sendall(cmd)
                    sent = True
                    boot_deadline = time.time() + args.window
                    print("boot command sent at %.1fs (kernel budget %ds "
                          "starts now)" %
                          (time.time() - start_time, args.window), flush=True)
        except socket.timeout:
            continue
        except Exception as e:
            print("socket exception: %s" % e, flush=True)
            break

    if not sent:
        print("WARNING: window expired before the Shell> prompt appeared; "
              "no boot command was sent and the log is a FIRMWARE-stage "
              "truncation, not a kernel verdict", flush=True)
    elif boot_deadline is not None and time.time() >= boot_deadline:
        print("kernel boot budget (%ds from the boot command) expired"
              % args.window, flush=True)
    sock.close()
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    with open(out, "wb") as f:
        f.write(output)
    text = output.decode("utf-8", "replace")
    print("serial bytes: %d -> %s" % (len(output), out), flush=True)
    ticks = sum(1 for L in text.splitlines() if "alive tick" in L)
    traps = sum(1 for L in text.splitlines()
                if "panic" in L.lower().replace("panic_init", "")
                or "Trap Type" in L or "Kernel Panic" in L)
    print("alive-tick lines: %d   panic/trap lines: %d" % (ticks, traps),
          flush=True)
    return 0 if ticks else 1

if __name__ == "__main__":
    sys.exit(main())
