#!/usr/bin/env python3
import socket
import subprocess
import sys
import time
import os

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
SOCK = os.path.join(WORK, "interactive_monitor.sock")
PPM = "/tmp/qemu_interactive.ppm"
PNG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/qemu_interactive.png"

if not os.path.exists(SOCK):
    print(f"Error: monitor socket not found at {SOCK} (is QEMU running?)", file=sys.stderr)
    sys.exit(1)

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    s.recv(4096)  # consume QEMU banner
    s.sendall(f"screendump {PPM}\n".encode())
    time.sleep(0.3)
    s.close()

    subprocess.run(["ffmpeg", "-y", "-i", PPM, PNG],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    print(PNG)
except Exception as e:
    print(f"Error capturing QEMU screen: {e}", file=sys.stderr)
    sys.exit(1)
