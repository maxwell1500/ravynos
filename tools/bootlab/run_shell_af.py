#!/usr/bin/env python3
"""A-F sequential shell verification over the serial console, one QEMU.

Purpose
-------
The shell-under-test image (manifest_af_shell.json) must be shown to reach an
interactive prompt and to execute real commands, in order, on the target. The
previous run of this scenario (work/serial_shell_36169_*.log) died in PID 1
startup, so nothing about the interactive shell was ever measured on that
image. This driver measures exactly that, and stops at the first failure.

Why this is not boot.py
-----------------------
boot.py sends one boot command, then only reads. It has no notion of "send a
command, wait for its output, verify the output is real output". It also
cannot distinguish a command's OUTPUT from the tty's ECHO of the command the
driver itself typed -- which is the failure mode that makes a naive harness
report success on a dead shell. This driver therefore does its own socket
plumbing. boot.py, manifest.json and assets/ are read but never written.

Echo-vs-output: the echoed line is consumed, never matched
-------------------------------------------------------
The console is a real tty in canonical mode with ECHO on, so every byte the
driver sends comes straight back. A harness that searches for a substring of
its own command therefore succeeds instantly and proves nothing: waiting for
"hello" after typing `echo hello` matches the ECHO, not the output, and
`/bin/echo external-ok` is worse still because the marker is a substring of
the path-free command text.

So this driver never searches from the point of the send. Each step is three
separate recognitions, in this order, each with its own cursor:

  1. the ECHO line -- the exact command text followed by a line terminator.
     This is what proves the bytes really were typed and reached the tty. It
     is CONSUMED: the cursor moves past its newline, so the command text can
     never satisfy a later check.
  2. the OUTPUT, matched as a WHOLE LINE strictly after the echo line's
     newline. Because the echo is already behind the cursor, a line that
     merely contains the marker cannot come from the command being typed.
  3. the PROMPT, strictly after the output. Output with no prompt after it
     means the child died or the shell wedged, which is a failure.

The A-F command texts are the originals, preserved verbatim:

  A  (no input)  banner "=== RAVYNOS SHELL PID 1 ===" then the initial prompt
  B  echo hello                      -> hello
  C  /bin/echo external-ok           -> external-ok
  D  echo hi | /bin/cat              -> hi
  E1 echo redirected-content > /tmp/f -> no output, prompt returns, NO error
  E2 /bin/cat /tmp/f                  -> redirected-content
  F  echo second-still-alive          -> second-still-alive

The command texts are the originals with no substitutions. That includes the
/tmp redirect, so this throwaway image adds an empty /tmp directory to
manifest_static_init.json's tree -- the only change to it. Without that,
`> /tmp/f` could only exercise ash's failure path, and E1 asserts SUCCESS.
E1's error check is what would catch a wrong path anyway: ash reports a
failed redirect as "<argv0>: cannot create <path>: <strerror>"
(BSD/bin/sh/redir.c:183 via vwarning, error.c:122-130), and those strings are
treated as failures.

Stopping
--------
A-F runs in order and STOPS AT THE FIRST FAILURE. Later steps assume earlier
state (F's file readback assumes E's redirect worked, and the prompt must be
alive for any of them to mean anything), so continuing past a failure would
report results that are not about the shell.

Freshness guards
----------------
assets/vars.fd is copied per run: a stale NVRAM produces a UEFI #UD at
handoff that is indistinguishable from a loader bug (recorded in
BOOT-PLAN.md). The image's own .digests sidecar is re-verified against the
IMAGE BYTES before QEMU starts, and the shell inside the image is checked to
be the static-init build (it must call __ravyn_static_libc_init and must have
zero callers of _init_clock_port). A stale image cannot boot here.

Usage
-----
  ./run_shell_af.py [--window 210] [--img work/af_shell.img]

Exit 0 = all of A-F passed. 1 = a step failed (named in the report).
2 = harness problem (no QEMU, no prompt, image verification failed).
"""
import argparse
import hashlib
import os
import re
import select
import shutil
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
QEMU = "qemu-system-x86_64"
OVMF_CODE = "/usr/local/share/qemu/edk2-x86_64-code.fd"

# The image's own loader bakes this exact string into A->CommandLine
# (tools/efiloader/src/loader.c:353 DEFAULT_CMDLINE), so the kernel's console
# is COM1. The driver types it at the UEFI shell for parity with boot.py; what
# the kernel actually receives is the loader's copy, which is asserted to
# contain serial=3 before booting.
BOOT_CMD = ("fs0:\\System\\Library\\CoreServices\\boot.efi -v serial=3 "
            "debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
            "rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 "
            "-no_compat_check cpus=1 quiet_boot=1")

PROMPT = b"# "

# PID 1's own banner, from tools/bootlab/init/init_shell.c:102. Step A is an
# OBSERVATION: nothing is typed, and both the banner and a prompt must appear
# on their own.
BANNER = b"=== RAVYNOS SHELL PID 1 ==="

# Redirect target: the ORIGINAL text, /tmp/f. This throwaway image therefore
# carries an empty /tmp directory, which is the only thing added to
# manifest_static_init.json's tree. E1 asserts the redirect SUCCEEDS (prompt
# returns, no error) and E2 reads the file back, so the path under test has to
# be one the image can actually create.
REDIRECT_PATH = "/tmp/f"

# ash's own failure strings for a redirect it cannot perform
# (redir.c:183 -> vwarning, error.c:122-130: "<argv0>: cannot create ...").
# E1 is a SUCCESS check, so any of these between the echo and the prompt is a
# failure, not noise.
ERROR_MARKERS = (b"cannot create", b"No such file", b"Permission denied",
                 b"Read-only file system", b"not found", b"Bad file")


# ---------------------------------------------------------------- image gate

def verify_image(img):
    """Re-derive the facts this run is a test OF, from the image bytes.

    The .digests sidecar is written by mkimage.py and can outlive the image it
    describes, so it is evidence about a past run, not this one. Each claim is
    re-checked against the image itself.
    """
    sys.path.insert(0, HERE)
    import fat32img

    problems = []
    fs = fat32img.Fat32Img(img)
    try:
        sh = fs.read_path("bin/sh")
        echo = fs.read_path("bin/echo")
        launchd = fs.read_path("sbin/launchd")
        loader = fs.read_path("EFI/BOOT/BOOTX64.EFI")
        loader2 = fs.read_path("System/Library/CoreServices/BOOT.EFI")
        kern_kc = fs.read_path("System/Library/KernelCollections/"
                               "BootKernelExtensions.kc")
        kern_dev = fs.read_path("System/Library/Kernels/kernel.development")
        for name, blob in (("bin/sh", sh), ("bin/echo", echo),
                           ("sbin/launchd", launchd),
                           ("EFI/BOOT/BOOTX64.EFI", loader),
                           ("System/Library/CoreServices/BOOT.EFI", loader2),
                           ("System/Library/KernelCollections/"
                            "BootKernelExtensions.kc", kern_kc),
                           ("System/Library/Kernels/kernel.development",
                            kern_dev)):
            if not blob:
                problems.append("image is missing %s" % name)
    finally:
        fs.close()

    if problems:
        return None, problems

    want = {
        "bin/sh": "a954602d55653555754562089ece49eb4888d0607120ced5980921254268dbf3",
        "bin/echo": "30b9e09fac930a906fb7611a3c3ad4dcbb8f69f144c3f90f835012938d63b965",
        # work/init_shell rebuilt after the banner was moved to follow the
        # /dev/console dup2 (init/init_shell.c). Same program, same strings;
        # only the position of the banner write changed.
        "sbin/launchd": "6635aedf9e2c301d3d41af87a7ddabf8903a337941005805485de0e2e952a141",
    }
    got = {
        "bin/sh": hashlib.sha256(sh).hexdigest(),
        "bin/echo": hashlib.sha256(echo).hexdigest(),
        "sbin/launchd": hashlib.sha256(launchd).hexdigest(),
    }
    for k, w in want.items():
        if got[k] != w:
            problems.append("%s in image is %s, expected %s"
                            % (k, got[k][:8], w[:8]))

    # BOTH kernel slots, read from the image, must be the one kernel this run
    # is a test OF. boot.efi is invoked with kcsuffix=development and the
    # loader stages the kernel in two places, so checking one slot proves
    # nothing: a mismatch between the two is a silent "the other one booted"
    # that no log line distinguishes. The expected value is hashed from
    # work/stripped_kernel.development at gate time rather than hardcoded, so
    # the assertion cannot drift away from the file the image was built from;
    # the resulting hash is reported so the run says which kernel that was.
    kern_src = os.path.join(HERE, "work", "stripped_kernel.development")
    kern_sha = None
    if not os.path.isfile(kern_src):
        problems.append("missing kernel payload %s" % kern_src)
    else:
        h = hashlib.sha256()
        with open(kern_src, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        kern_sha = h.hexdigest()
        for slot, blob in (("BootKernelExtensions.kc", kern_kc),
                           ("kernel.development", kern_dev)):
            got_sha = hashlib.sha256(blob).hexdigest()
            if got_sha != kern_sha:
                problems.append("kernel slot %s in image is %s, expected %s "
                                "(work/stripped_kernel.development)"
                                % (slot, got_sha[:8], kern_sha[:8]))
        if kern_kc != kern_dev:
            problems.append("the two kernel slots differ")

    # The loader must be in BOTH EFI slots and must carry serial=3, or the
    # kernel console is not the socket this driver is reading.
    if loader != loader2:
        problems.append("the two loader slots differ")
    if b"serial=3" not in loader:
        problems.append("loader does not contain serial=3")

    # The whole point of this run: the shell in the image must be the
    # static-init build. If it calls dynamic __libc_init it will abort in
    # _init_clock_port exactly as the previous run did, so refuse to boot.
    #
    # otool needs a real path, so the shell is spilled to work/ for the
    # disassembly and deleted in the finally: a leftover multi-megabyte copy
    # of a binary in work/ is exactly the kind of artifact that later gets
    # mistaken for a build product and booted.
    tmp = os.path.join(HERE, "work", "sh.from_image.af")
    try:
        with open(tmp, "wb") as f:
            f.write(sh)
        dis = subprocess.run(["otool", "-tvV", tmp], capture_output=True,
                             text=True).stdout
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    n_libc_init = len(re.findall(r"callq\s+___libc_init\b", dis))
    n_static = len(re.findall(r"callq\s+___ravyn_static_libc_init\b", dis))
    n_clock = len(re.findall(r"callq\s+__init_clock_port\b", dis))
    if n_libc_init:
        problems.append("image shell calls dynamic __libc_init x%d -- this is "
                        "the stale pre-fix shell" % n_libc_init)
    if n_static != 1:
        problems.append("image shell calls __ravyn_static_libc_init x%d, "
                        "expected 1" % n_static)
    if n_clock:
        problems.append("image shell calls _init_clock_port x%d" % n_clock)

    facts = dict(got)
    facts["loader_sha"] = hashlib.sha256(loader).hexdigest()
    facts["kernel_sha"] = kern_sha
    facts["static_init_calls"] = n_static
    facts["dynamic_libc_init_calls"] = n_libc_init
    facts["init_clock_port_calls"] = n_clock
    return facts, problems


# ------------------------------------------------------------ serial console

class Serial:
    """Line discipline on one side, prompt/marker matching on the other.

    Everything is matched against a CURSOR into the accumulated stream, and
    the cursor only ever moves forward. A step therefore cannot be satisfied
    by a prompt or marker printed BEFORE it was sent, which is the other way a
    harness reports a pass that did not happen.
    """

    def __init__(self, sock, log):
        self.sock = sock
        self.buf = bytearray()
        self.log = log

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.sock], [], [], 0.2)
            if not r:
                continue
            try:
                data = self.sock.recv(65536)
            except (socket.timeout, BlockingIOError):
                continue
            except OSError:
                return False
            if not data:
                return False
            self.buf.extend(data)
            self.log.write(data)
            self.log.flush()
        return True

    def find(self, needle, start, timeout):
        """(index just past the match, matched?) searching only past `start`.

        The whole buffer is rescanned from `start` on every pass rather than
        resuming near the tail. Resuming near the tail is the obvious
        optimisation and it is wrong: it skips every byte that arrived in the
        same read as the tail, which is exactly where the match usually is
        (one read carries the echoed command, the output and the prompt
        together). Rescanning from `start` is safe because `buf` only ever
        grows, and it still finds a needle split across two reads -- the
        leading bytes are already in `buf` when the rest arrives.
        """
        end = time.time() + timeout
        while True:
            j = self.buf.find(needle, start)
            if j >= 0:
                return j + len(needle), True
            if time.time() >= end:
                return start, False
            if not self.pump(0.3):
                return start, False

    def find_echo(self, command, start, timeout):
        """(index just past the echoed line, matched?) -- real typed input.

        The tty echoes the command and then a line terminator, so the echoed
        line is the exact command text plus CRLF. Matching the TEXT alone
        would be enough to recognise it, but matching the terminator too is
        what makes the returned cursor safe to use: it lands after the
        newline, so everything the driver matches next is necessarily output
        rather than the command being typed.

        The terminator is whatever actually follows the command -- CRLF, a
        lone LF, or a lone CR -- because whether the echo of Enter carries the
        LF depends on the tty's ONLCR/ICRNL settings rather than on anything
        this driver controls.

        One deadline for the whole recognition, and the terminator is read at
        the position immediately after the command rather than by trying
        candidate needles in turn. The obvious alternative -- loop over
        (CRLF, LF, CR) calling find() with the full timeout each time -- is
        wrong twice over: a CR-only echo pays the timeout twice before
        succeeding, and a console that never echoes pays it three times, so
        one step could burn 3x step_timeout and stall the sequential run.
        Here the command is located once, the bytes after it are inspected
        directly, and a single deadline bounds the whole thing.

        Split reads still work: the command is re-searched and the terminator
        re-inspected on every pass, so a command and/or its terminator
        arriving across several reads is still recognised.
        """
        raw = command.encode()
        n = len(raw)
        end = time.time() + timeout
        cmd_at = None
        while True:
            if cmd_at is None:
                j = self.buf.find(raw, start)
                if j >= 0:
                    # Pin the occurrence. Re-searching could latch onto a
                    # LATER copy of the same text once more data arrives, and
                    # then the cursor would skip the real echo's output.
                    cmd_at = j
            if cmd_at is not None:
                k = cmd_at + n
                tail = self.buf[k:k + 2]
                if tail.startswith(b"\r\n"):
                    return k + 2, True
                if tail[:1] in (b"\n", b"\r"):
                    return k + 1, True
            if time.time() >= end:
                return start, False
            if not self.pump(0.3):
                return start, False

    def find_line(self, text, start, timeout):
        """(index just past the line, matched?) for a WHOLE output line.

        Requires `text` to occupy a line by itself: it must begin at a line
        boundary and be followed by a line terminator. Combined with a cursor
        that already sits past the echoed command, this is what makes
        `echo hello` -> `hello` honest -- "hello" as a line can only be the
        shell's output, because the echo of the command is behind the cursor
        and was not a bare "hello" line to begin with.
        """
        raw = text.encode()
        end = time.time() + timeout
        while True:
            j = self.buf.find(raw, start)
            while j >= 0:
                at_line_start = (j == 0) or self.buf[j - 1:j] == b"\n"
                k = j + len(raw)
                if at_line_start and self.buf[k:k + 1] in (b"\r", b"\n"):
                    return k + 1, True
                j = self.buf.find(raw, j + 1)
            if time.time() >= end:
                return start, False
            if not self.pump(0.3):
                return start, False

    def span(self, a, b):
        return bytes(self.buf[a:b]).decode("utf-8", "replace")

    def send(self, text):
        self.sock.sendall(text.encode() + b"\r")

    def tail(self, n=400):
        return bytes(self.buf[-n:]).decode("utf-8", "replace")


# ------------------------------------------------------------------- the run

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default=os.path.join(HERE, "work", "af_shell.img"))
    ap.add_argument("--window", type=int, default=210,
                    help="seconds of kernel boot budget after the boot command")
    ap.add_argument("--step-timeout", type=int, default=25,
                    help="seconds allowed for one step's output + prompt")
    args = ap.parse_args()

    img = os.path.abspath(args.img)
    work = os.path.join(HERE, "work")
    os.makedirs(work, exist_ok=True)

    if shutil.which(QEMU) is None:
        sys.exit("harness: %s not on PATH" % QEMU)
    if not os.path.isfile(img):
        sys.exit("harness: no image %s (run mkimage.py --manifest "
                 "manifest_af_shell.json)" % img)
    if not os.path.isfile(OVMF_CODE):
        sys.exit("harness: missing OVMF at %s" % OVMF_CODE)

    subprocess.run(["pgrep", "-f", QEMU], capture_output=True)
    if subprocess.run(["pgrep", "-f", QEMU],
                      capture_output=True).returncode == 0:
        sys.exit("harness: a QEMU is already running; one run at a time")

    print("[gate] verifying image bytes before boot", flush=True)
    facts, problems = verify_image(img)
    if problems:
        for p in problems:
            print("  PROBLEM: %s" % p, file=sys.stderr)
        sys.exit("harness: image verification failed; refusing to boot")
    print("  bin/sh        %s  (%d static-init call, %d dynamic __libc_init, "
          "%d _init_clock_port)" % (facts["bin/sh"][:16],
                                    facts["static_init_calls"],
                                    facts["dynamic_libc_init_calls"],
                                    facts["init_clock_port_calls"]), flush=True)
    print("  bin/echo      %s" % facts["bin/echo"][:16], flush=True)
    print("  sbin/launchd  %s" % facts["sbin/launchd"][:16], flush=True)
    print("  loader x2     %s  (serial=3 present)" % facts["loader_sha"][:16],
          flush=True)
    print("  kernel x2     %s  (both slots read from image bytes, == "
          "work/stripped_kernel.development)" % (facts["kernel_sha"] or "?"),
          flush=True)

    # Fresh NVRAM per run: a stale vars.fd gives a UEFI #UD at handoff that
    # looks exactly like a loader bug.
    tag = "%d_%d" % (os.getpid(), time.time_ns())
    serial_sock = os.path.join(work, "serial_af_%s.sock" % tag)
    mon_sock = os.path.join(work, "mon_af_%s.sock" % tag)
    qemu_log = os.path.join(work, "qemu_af_%s.log" % tag)
    out_log = os.path.join(work, "serial_af_%s.log" % tag)
    report = os.path.join(work, "af_report_%s.txt" % tag)
    vars_fd = os.path.join(work, "vars_af_%s.fd" % tag)
    shutil.copyfile(os.path.join(HERE, "assets", "vars.fd"), vars_fd)

    cmd = [
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
        "-D", qemu_log,
    ]
    print("[boot] ONE QEMU, %s" % os.path.basename(img), flush=True)
    proc = subprocess.Popen(cmd)

    sock = None
    deadline = time.time() + 30
    while sock is None and time.time() < deadline:
        time.sleep(0.5)
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(serial_sock)
            sock.setblocking(False)
        except OSError:
            if sock:
                sock.close()
            sock = None
    if sock is None:
        proc.terminate()
        sys.exit("harness: could not attach to the serial socket")

    results = []
    rc = 0
    log = open(out_log, "wb")
    con = Serial(sock, log)

    def record(step, ok, detail):
        results.append((step, ok, detail))
        print("  %-3s %-4s %s" % (step, "PASS" if ok else "FAIL", detail),
              flush=True)

    try:
        # ---- firmware -> kernel: the boot command is typed at Shell> ------
        t0 = time.time()
        while time.time() - t0 < 60:
            if proc.poll() is not None:
                record("A", False, "QEMU exited before the UEFI shell prompt "
                                  "(code %s)" % proc.returncode)
                rc = 2
                break
            con.pump(0.5)
            if b"Shell>" in con.buf:
                break
        if rc == 0:
            con.pump(5)
            con.send(BOOT_CMD)
            print("[boot] command sent; kernel budget %ds" % args.window,
                  flush=True)
            pos, got = con.find(b"RL: cmdline=", len(con.buf), args.window)
            if not got:
                _, got2 = con.find(b"procinit:", pos, args.window)
                if not got2:
                    record("A", False, "no kernel boot progress in %ds "
                                      "(last: %r)"
                           % (args.window, con.tail(200)))
                    rc = 2
            if rc == 0:
                # ---- A: OBSERVED, not provoked. Nothing is typed. PID 1's
                # own banner must appear, and then a prompt after it.
                bpos, gotb = con.find(BANNER, pos, args.window)
                if not gotb:
                    record("A", False, "PID 1 banner %r never appeared within "
                                      "%ds (last: %r)"
                           % (BANNER.decode(), args.window, con.tail(300)))
                    rc = 1
                else:
                    ppos, gotp = con.find(PROMPT, bpos, args.window)
                    if not gotp:
                        record("A", False, "banner seen but no prompt followed "
                                          "within %ds (last: %r)"
                               % (args.window, con.tail(300)))
                        rc = 1
                    else:
                        record("A", True, "banner %r then initial prompt %r, "
                                         "both unprompted"
                                % (BANNER.decode(), PROMPT.decode()))

        if rc == 0:
            # ---- B-F: original command texts, in order, stop at first fail.
            # Each step is three recognitions with three cursors: consume the
            # ECHO, then match the OUTPUT as a whole line past the echo, then
            # require the PROMPT after that output.
            steps = [
                ("B", "echo hello", "hello",
                 "builtin echo"),
                ("C", "/bin/echo external-ok", "external-ok",
                 "external binary: real fork+exec, not the builtin"),
                ("D", "echo hi | /bin/cat", "hi",
                 "pipeline: two children, the right one must write"),
                ("E1", "echo redirected-content > " + REDIRECT_PATH, None,
                 "redirect creates %s: prompt returns, no error" % REDIRECT_PATH),
                ("E2", "/bin/cat " + REDIRECT_PATH, "redirected-content",
                 "readback of E1's file"),
                ("F", "echo second-still-alive", "second-still-alive",
                 "shell still alive after E2"),
            ]
            for name, command, expect, why in steps:
                start = len(con.buf)
                con.send(command)

                # 1. the echoed command line -- proof the bytes were typed
                after_echo, got_echo = con.find_echo(command, start,
                                                     args.step_timeout)
                if not got_echo:
                    record(name, False,
                           "typed %r but its echo never came back within %ds "
                           "-- no real input reached the tty (last: %r)"
                           % (command, args.step_timeout, con.tail(200)))
                    rc = 1
                    break

                # 2. the output, as a whole line strictly after the echo
                if expect is not None:
                    out_pos, got_out = con.find_line(expect, after_echo,
                                                     args.step_timeout)
                    if not got_out:
                        record(name, False,
                               "echo of %r seen, but no output line %r after "
                               "it within %ds (saw: %r)"
                               % (command, expect, args.step_timeout,
                                  con.span(after_echo, len(con.buf))[:200]))
                        rc = 1
                        break
                else:
                    out_pos = after_echo

                # 3. the prompt, after the output
                ppos, got_prompt = con.find(PROMPT, out_pos,
                                             args.step_timeout)
                if not got_prompt:
                    record(name, False,
                           "no prompt after the output of %r within %ds "
                           "(last: %r)" % (command, args.step_timeout,
                                           con.tail(200)))
                    rc = 1
                    break

                # E1 is a SUCCESS assertion, so an error line in the gap is
                # a failure even though the prompt did come back.
                between = con.span(after_echo, ppos)
                bad = [e.decode() for e in ERROR_MARKERS if e in
                       between.encode("utf-8", "replace")]
                if bad:
                    record(name, False,
                           "error after %r: %s (saw: %r)"
                           % (command, bad, between[:200]))
                    rc = 1
                    break

                if expect is None:
                    detail = why + " -- silent, prompt returned, no error"
                else:
                    detail = why + " -- echo consumed, output line %r, " \
                                    "then prompt" % expect
                record(name, True, detail)
    finally:
        with open(out_log, "wb") as f:
            f.write(bytes(con.buf))
        log.close()
        try:
            sock.close()
        except OSError:
            pass
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        shutil.copyfile(vars_fd, os.path.join(work, "vars_af_%s.used.fd" % tag))

    with open(report, "w") as f:
        f.write("A-F shell verification\n")
        f.write("image : %s\n" % img)
        f.write("serial: %s\n" % out_log)
        f.write("qemu  : %s\n" % qemu_log)
        f.write("bin/sh: %s\n" % facts["bin/sh"])
        f.write("kernel  : %s  (both slots)\n" % (facts["kernel_sha"] or "?"))
        f.write("loader  : %s  (both slots)\n" % facts["loader_sha"])
        f.write("\n")
        for step, ok, detail in results:
            f.write("%s %s %s\n" % (step, "PASS" if ok else "FAIL", detail))
        f.write("\nexit %d\n" % rc)

    passed = sum(1 for _, ok, _ in results if ok)
    print("\n%d/%d steps passed" % (passed, len(results)), flush=True)
    print("serial -> %s" % out_log, flush=True)
    print("report -> %s" % report, flush=True)
    if rc == 0:
        # Actual panic signatures only. The kernel logs "panic_init: entered",
        # "panic_init: checking boot args", "panic_init: completed
        # successfully" and similar during EVERY normal boot, so a bare
        # "panic" substring flags a clean run as suspicious -- which is what
        # it did on the first passing run, printing a misleading NOTE against
        # 7/7 PASS. These three are the real shapes: xnu's panic header
        # "panic(cpu N caller 0x...)", the initproc abort, and any exit
        # reason reported for a process. Count LINES, not occurrences, so one
        # panic cannot inflate the number.
        log = bytes(con.buf)
        sig = [ln for ln in log.splitlines()
               if re.search(rb"panic\(cpu \d+ caller |initproc failed|"
                            rb"exit reason namespace", ln)]
        if sig:
            print("NOTE: %d PANIC line(s) in the log -- this run is NOT clean:"
                  % len(sig), flush=True)
            for ln in sig[:10]:
                print("     %s" % ln.decode("utf-8", "replace")[:160],
                      flush=True)
        else:
            print("no panic, no initproc failure, no exit reason in the log",
                  flush=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
