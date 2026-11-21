#!/usr/bin/env python3
"""Drive the running guest's keyboard through the QEMU monitor.

CGEventPost in the guest is a stub, so programmatic input has to enter at
the emulated keyboard and travel the real path: QEMU -> PS/2 -> kernel
evdev -> WindowServer -> focused window.  That is exactly the path the
address bar needs, so driving it here exercises the shipping code.

  input.py click X Y            move the pointer relatively, then click
  input.py keys ctrl-l h t t p  send a key sequence (HMP sendkey names)
  input.py shot OUT.png         screendump into a PNG

Each action confirms the monitor answered, so a silent guest is not
mistaken for a handled command.
"""
import os
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
SOCK = os.path.join(WORK, "interactive_monitor.sock")
PPM = "/tmp/qemu_interactive.ppm"


def monitor(cmds):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    s.settimeout(2.0)
    try:
        s.recv(4096)  # QEMU banner
    except socket.timeout:
        pass
    out = b""
    for cmd in cmds:
        s.sendall((cmd + "\n").encode())
        time.sleep(0.08)
        try:
            out += s.recv(4096)
        except socket.timeout:
            pass
    s.close()
    return out.decode(errors="replace")


def shot(png):
    monitor(["screendump %s" % PPM])
    time.sleep(0.3)
    subprocess.run(["ffmpeg", "-y", "-i", PPM, png],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=True)
    print(png)


def main(argv):
    if not os.path.exists(SOCK):
        sys.exit("monitor socket missing (is QEMU running?)")
    if not argv:
        sys.exit(__doc__)
    cmd = argv[0]
    if cmd == "keys":
        # QEMU has no "meta": the GUI/Command key is meta_l (and meta_r).
        keys = [k.replace("meta-", "meta_l-").replace("meta", "meta_l") if k.startswith("meta") else k
                for k in argv[1:]]
        reply = monitor(["sendkey %s" % k for k in keys])
        bad = [l for l in reply.splitlines()
               if "unknown" in l.lower() or "invalid" in l.lower()]
        print("sent %d keys%s" % (len(keys), (" errors: " + " ".join(bad)) if bad else ""))
    elif cmd == "click":
        x, y = int(argv[1]), int(argv[2])
        # HMP only moves relatively; converge in steps so a click lands on
        # the window the screenshot showed rather than wherever it drifted.
        steps = 12
        dx, dy = x // steps, y // steps
        monitor(["mouse_move %d %d 0" % (dx, dy)] * steps)
        monitor(["mouse_button 1", "mouse_button 0"])
        print("clicked near %d,%d" % (x, y))
    elif cmd == "shot":
        shot(argv[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
