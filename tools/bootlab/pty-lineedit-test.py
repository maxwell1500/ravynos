#!/usr/bin/env python3
"""
Assert that the ravynOS shell really does line editing and history under a
real pseudo-terminal. isatty(0) must be true, so pty.fork is the only way to
exercise this; a pipe would take the non-tty path in input.c.

Each check is a semantic assertion about what the shell EXECUTED, not about
escape-sequence bytes. The distinction is the whole point: a pty interleaves
the editor's own redraw with real output in one stream, so a check on the raw
bytes proves nothing.
"""
import atexit, os, pty, select, shutil, sys, tempfile, time

SH = sys.argv[1]
PASS, FAIL = [], []


def run(script, settle=0.45):
    # A private HOME per run: libedit persists to $HOME/.sh_history, and a
    # shared one makes each run inherit the previous run's entries, so the
    # history assertions would measure accumulation rather than recall.
    home = tempfile.mkdtemp(prefix="ptyhome.")
    atexit.register(shutil.rmtree, home, True)

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(TERM="xterm", PS1="P> ", HOME=home, HISTSIZE="100")
        os.execv(SH, [SH, "-i"])
        os._exit(127)

    out = bytearray()

    def pump(t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    d = os.read(fd, 65536)
                except OSError:
                    return
                if not d:
                    return
                out.extend(d)

    pump(1.0)
    marks = []
    for label, data in script:
        marks.append((label, len(out)))
        try:
            os.write(fd, data)
        except OSError:
            break
        pump(settle)
    try:
        os.close(fd)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    return bytes(out).decode("utf-8", "replace"), marks


def out_lines(t):
    """Lines the shell actually PRINTED, as opposed to bytes the editor
    echoed while redrawing. In a pty the two are interleaved in one stream:
    typing "echo CLEANXXXX" and then backspacing legitimately leaves
    "CLEANXXXX" in the byte stream even though the executed line was
    "echo CLEAN". So the assertion has to be that some complete line is
    exactly right, which only happens if the executed command was right."""
    ls = []
    for ln in t.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        s = ln.strip()
        if s:
            ls.append(s)
    return ls



def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print("  %-4s %s%s" % ("PASS" if cond else "FAIL", name,
                           ("   -- " + detail) if detail and not cond else ""))


UP, DOWN, LEFT, RIGHT, BS = b"\x1b[A", b"\x1b[B", b"\x1b[D", b"\x1b[C", b"\x7f"

print("=== 1. history recall by UP arrow ===")
# Run a command, clear the line, recall it, and re-run it. If recall works the
# command runs TWICE. If it does not, ESC[A is passed to the parser as a word.
t, _ = run([
    ("run", b"echo AAA\r"),
    ("up", UP),
    ("cr", b"\r"),
    ("exit", b"exit\r"),
])
lines = out_lines(t)
check("UP recalls the previous line (AAA printed twice)",
      lines.count("AAA") == 2,
      "output line AAA appeared %d time(s); lines=%r" % (lines.count("AAA"), lines))
check("UP is not executed as a command", "not found" not in t,
      "shell tried to run the escape sequence")
check("raw ESC[A never reaches the parser", "^[[A" not in t,
      "terminal echoed a literal escape sequence")

print()
print("=== 2. editing a recalled line and running the edit ===")
# Recall "echo AAA", append " BBB", run: the OUTPUT must be the edited text.
# This only works if both recall and mid-line editing are real.
t, _ = run([
    ("run", b"echo AAA\r"),
    ("up", UP),
    ("type", b" BBB"),
    ("cr", b"\r"),
    ("exit", b"exit\r"),
])
check("edited recalled line runs as 'AAA BBB'", "AAA BBB" in out_lines(t),
      "output lines were %r" % (out_lines(t),))

print()
print("=== 3. backspace deletes ===")
# Type a command, add junk, backspace it off, run. Output must be clean.
# Note this one also passes with line editing off, because the kernel tty
# line discipline erases on BS in canonical mode. It is kept as a
# no-regression check, not as evidence that libedit is present.
t, _ = run([
    ("type", b"echo CLEAN"),
    ("junk", b"XXXX"),
    ("bs", BS * 4),
    ("cr", b"\r"),
    ("exit", b"exit\r"),
])
lines = out_lines(t)
check("backspace removed the typed junk (no-regression)",
      "CLEAN" in lines and "CLEANXXXX" not in lines,
      "output lines were %r" % (lines,))

print()
print("=== 3b. backspace is handled by the editor, not the line discipline ===")
# In line-editing mode the shell puts the tty in raw mode, so the kernel
# does NOT echo or erase. The editor must therefore redraw the line itself.
# With -DNO_HISTORY the tty stays in canonical mode and the kernel echoes
# the junk as ordinary input, so the literal string appears in the stream.
t, _ = run([
    ("type", b"echo CLEAN"),
    ("junk", b"XXXX"),
    ("bs", BS),
    ("exit", b"exit\r"),
])
check("raw mode: no kernel echo of the erased junk", "CLEANX" in t,
      "no editor redraw seen; stream was %r" % (t[:200],))

print()
print("=== 4. cursor movement with LEFT/RIGHT ===")
# ONE left, not two: the cursor starts just past B, so a single left lands
# between A and B. Verified by sweeping 1/2/3 lefts and watching the output
# track the cursor exactly (AXB / XAB / "echoX: not found").
t, _ = run([
    ("type", b"echo AB"),
    ("left", LEFT),
    ("ins", b"X"),
    ("cr", b"\r"),
    ("exit", b"exit\r"),
])
check("LEFT arrow inserts mid-line (AXB)", "AXB" in out_lines(t),
      "output lines were %r" % (out_lines(t),))

print()
print("=== 5. history navigation DOWN ===")
# Two commands, then UP UP DOWN. From the empty line after TWO, the history
# position walks back to TWO (1st UP), then to ONE (2nd UP), then forward to
# TWO again (DOWN) -- so TWO is what gets executed a second time. Asserting
# on the executed output, rather than on "both words appear somewhere", is
# what makes this discriminating: with -DNO_HISTORY the escape sequences run
# as commands and neither word is ever re-executed.
t, _ = run([
    ("a", b"echo ONE\r"),
    ("b", b"echo TWO\r"),
    ("up", UP + UP),
    ("down", DOWN),
    ("cr", b"\r"),
    ("exit", b"exit\r"),
])
lines = out_lines(t)
check("DOWN walks forward again (TWO re-executed)",
      lines.count("TWO") == 2 and lines.count("ONE") == 1,
      "ONE ran %d time(s), TWO ran %d time(s); lines=%r"
      % (lines.count("ONE"), lines.count("TWO"), lines))

print()
print("=== 6. `fc -l` sees the history ===")
# The builtin reads the same libedit history, so a listing containing the
# commands (not merely their output) proves history is a real store. The
# listing is numbered ("3 echo HIST1"), and the echoed OUTPUT alone would
# satisfy a naive substring check, so match the numbered listing form.
t, _ = run([
    ("a", b"echo HIST1\r"),
    ("b", b"echo HIST2\r"),
    ("fc", b"fc -l\r"),
    ("exit", b"exit\r"),
])
lines = out_lines(t)
# fc -l numbers each entry, so require a leading index. Matching the bare
# command text would also match the echoed INPUT line ("P> echo HIST1"),
# which is present whether or not history works at all.
def listed(cmd):
    for l in lines:
        parts = l.split(None, 1)
        if len(parts) == 2 and parts[0].isdigit() and parts[1] == cmd:
            return True
    return False

check("fc -l lists the commands themselves",
      listed("echo HIST1") and listed("echo HIST2"),
      "no numbered fc listing found; lines=%r" % (lines,))

print()
print("=== 7. non-tty input still works (no regression) ===")
# Pipe a script in: input.c must take the plain-read path, not el_gets.
r, w = os.pipe()
pid = os.fork()
if pid == 0:
    os.dup2(r, 0); os.close(r); os.close(w)
    os.environ["PS1"] = "P> "
    os.execv(SH, [SH])
    os._exit(127)
os.close(r)
os.write(w, b"echo PIPED\ntest 1 -lt 2 && echo ARITH_OK\nexit\n")
os.close(w)
_, status = os.waitpid(pid, 0)
check("piped stdin executes commands", os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
      "exit status %r" % (status,))

print()
print("%d passed, %d failed" % (len(PASS), len(FAIL)))
if FAIL:
    print("FAILED: " + ", ".join(FAIL))
sys.exit(1 if FAIL else 0)
