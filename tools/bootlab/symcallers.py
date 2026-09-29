#!/usr/bin/env python3
"""
symcallers.py -- enumerate the callers of a symbol in a Mach-O image, safely.

WHY THIS EXISTS
    This project has now produced ELEVEN instrument defects, and three of them
    were the same mistake wearing different hats:

      1. `nm -gjU` shows only GLOBAL, defined symbols. Every symbol in
         libsystem_platform's formatter is LOCAL, so the grep returned a clean
         confident zero for symbols that were present and load-bearing. That
         sent a whole investigation hunting for a static BUF that never
         existed, and it later made a correct fix look like it had not worked.

      2. Stripping exactly one underscore. Mach-O prepends '_' to every C
         identifier, so a symbol read out of a Mach-O table and pasted into a
         source grep does not match the source.

      3. THE ONE THIS SCRIPT EXISTS TO STOP. A symbol lookup that returns an
         EMPTY address was used directly as a match target. The target became
         the two-character string '0x', which matched every callq in the
         image, and the tool confidently reported 13,049 callers of a function
         that has two.

    (3) is the dangerous one because it fails LOUDLY with a huge number rather
    than quietly with a zero. Thirteen thousand is a number people believe.

    The guard is therefore an ASSERTION, and it is in this file rather than in
    the head of whoever runs it -- a guard that lives in a throwaway script
    dies with the script, and the next person repeats the mistake.

    This is the general rule the whole effort converged on: a hypothesis that
    has not been measured is not a finding, and an instrument that has not
    been shown capable of failing is not an instrument.

USAGE
    symcallers.py <macho> <symbol>            # callers of <symbol>
    symcallers.py <macho> --inside <symbol>   # disassembly of the function body

    <symbol> is given in MACH-O spelling, e.g. _put_c, __simple_vesprintf.
    A C-spelling alias (put_c) is accepted too, with a note saying which
    spelling resolved -- the underscore count is the thing that keeps biting,
    so the tool refuses to do it silently.


    symcallers.py <macho> --extent <symbol>   # a symbol's true byte extent
    symcallers.py <macho> --disasm <symbol>   # disassemble exactly that extent

THE FOURTH DEFECT THIS TOOL EXISTS TO PREVENT, added after it was paid for:
    a hand-chosen window.  An earlier analysis disassembled "0xa1000 to
    0xa1200" -- 512 bytes I picked -- and concluded from the silence that a
    function never made a call.  It did make the call, past the end of my
    window, and the artifact that refuted it (the object's undefined-symbol
    list) was one nm away the whole time.  A window you type is an instrument
    with an unstated limit, and an unstated limit produces a confident answer
    it cannot support.  So a symbol's extent is COMPUTED from the next
    symbol's address, never typed, and --disasm prints that range and nothing
    else.  If the extent cannot be computed, the tool says so rather than
    falling back to a default size.

ORDERING RULE, learned the same way: for a question about what the source
    said, ask the OBJECT before asking the binary.  The object is closer to
    the source; the binary has been through a linker, a slide and a dozen
    relinks.

EXIT STATUS
    0  ran, and the symbol was found
    2  the symbol was NOT in the symbol table -- reported as such, never
       silently turned into a pattern or an empty match target
"""

import re
import subprocess
import sys


class SymbolNotFound(Exception):
    pass


def load_symbols(macho):
    """Local (t/T) AND global symbols, from a plain `nm -n`.

    Deliberately NOT `nm -gjU`: -g drops local symbols and -U drops undefined
    ones, and this project needs both.  Every symbol that mattered in the
    put_c investigation was local.
    """
    out = subprocess.run(["nm", "-n", macho], capture_output=True, text=True)
    syms = []
    for line in out.stdout.splitlines():
        parts = line.split()
        # Accept the 3-column defined form, and the 2-column undefined form.
        if len(parts) == 3 and parts[1] in "tT":
            syms.append((int(parts[0], 16), parts[2], "defined"))
        elif len(parts) == 2 and parts[0] == "U":
            syms.append((None, parts[1], "undefined"))
    if not syms:
        raise SymbolNotFound("nm produced no symbols at all for %s" % macho)
    return syms


def resolve(macho, name, syms):
    """Find `name` (Mach-O spelling) and return its address.

    Raises SymbolNotFound rather than returning something empty.  An empty
    address is the exact input that caused the 13,049-caller incident, so it
    must never leave this function.
    """
    exact = [s for s in syms if s[1] == name]
    if exact:
        return exact[0]

    # Accept the C spelling (one fewer leading underscore) -- but say so.
    if name.startswith("_"):
        c_style = name[1:]
        alt = [s for s in syms if s[1] == c_style]
        if alt:
            print("note: '%s' not found; resolved via the C spelling '%s'.\n"
                  "      Mach-O prepends one underscore to every C identifier --\n"
                  "      this is the third defect this tool guards against."
                  % (name, c_style), file=sys.stderr)
            return alt[0]

    near = [s for s in syms if name in s[1]][:8]
    hint = ""
    if near:
        hint = ("\nnear matches: "
                + ", ".join(sorted(s[1] for s in near)))
    raise SymbolNotFound(
        "'%s' is not in the symbol table of %s.%s" % (name, macho, hint))


def owner(syms, addr):
    """Name of the function containing `addr`.

    Undefined entries carry no address and must be SKIPPED, not treated as a
    stop condition.  Getting that wrong made every owner come back None --
    a real answer rendered useless rather than an error, which is the same
    failure shape as the empty match target this tool exists to prevent.
    """
    prev = None
    for a, n, _ in syms:
        if a is None:
            continue
        if a > addr:
            break
        prev = n
    return prev


def extent(syms, name):
    """(start, end) of `name`, COMPUTED from the next symbol's address.

    This is the fix for the hand-drawn-window defect.  A caller that types an
    address has created a place to be wrong; a caller that asks the symbol
    table has not.  Returns None rather than guessing if the symbol is the
    last one in the image and its end cannot be derived.
    """
    ordered = sorted([s for s in syms if s[0] is not None])
    for i, (a, n, _) in enumerate(ordered):
        if n != name:
            continue
        if i + 1 < len(ordered):
            return a, ordered[i + 1][0]
        return a, None          # last symbol: no upper bound available
    return None


def disasm_range(macho, start, end):
    """Disassembly of exactly [start, end).  No default size, ever."""
    if end is None:
        raise SymbolNotFound(
            "cannot compute the end of %s: it is the last symbol in %s.\n"
    "       Refusing to substitute a default length -- an unstated limit\n"
    "       produces a confident answer it cannot support." % (name_of(start), macho))
    out = subprocess.run(["otool", "-tv", macho],
                         capture_output=True, text=True).stdout.splitlines()
    body = []
    for line in out:
        m = re.match(r"^([0-9a-f]{16})\s", line)
        if not m:
            continue
        a = int(m.group(1), 16)
        if start <= a < end:
            body.append(line)
    return body


def name_of(addr):
    return hex(addr)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    macho = sys.argv[1]
    mode = None
    if sys.argv[2] in ("--extent", "--disasm"):
        if len(sys.argv) < 4:
            print("FATAL: %s needs a symbol name" % sys.argv[2], file=sys.stderr)
            return 2
        mode, name = sys.argv[2], sys.argv[3]
    else:
        name = sys.argv[2]


    try:
        syms = load_symbols(macho)
    except SymbolNotFound as e:
        print("FATAL: %s" % e, file=sys.stderr)
        return 2

    try:
        target = resolve(macho, name, syms)
    except SymbolNotFound as e:
        # The whole point.  Refuse rather than fall back to a substring.
        print("FATAL: %s" % e, file=sys.stderr)
        print("       Refusing to fall back to a substring match.  A previous\n"
              "       version of this analysis did, and reported 13,049 callers\n"
              "       of a function that has two.", file=sys.stderr)
        return 2

    if target[0] is None:
        print("%s is UNDEFINED in this image (it is an import, not a "
              "definition); there are no callers to enumerate." % name)
        return 0

    addr = target[0]
    print("%s = 0x%x  (%s)" % (name, addr, target[2]))
    if mode in ("--extent", "--disasm"):
        ex = extent(syms, name)
        if ex is None:
            print("FATAL: %s is defined but has no computable extent "
                  "(no following symbol)." % name, file=sys.stderr)
            return 2
        start, end = ex
        print("%s extent: 0x%x - 0x%x  (%d bytes, computed from the next "
              "symbol -- not typed)" % (name, start, end, end - start))
        if mode == "--extent":
            return 0
        for line in disasm_range(macho, start, end):
            print("    " + line)
        return 0

    dis = subprocess.run(["otool", "-tv", macho],
                         capture_output=True, text=True).stdout.splitlines()
    callre = re.compile(r"\bcallq\s+0x%x$" % addr)
    callers = {}
    for line in dis:
        m = re.match(r"^([0-9a-f]{16})\s", line)
        if not m:
            continue
        if callre.search(line.rstrip()):
            a = int(m.group(1), 16)
            callers.setdefault(owner(syms, a), []).append(a)

    if not callers:
        print("no direct callq to %s" % name)
        return 0

    print("\n%d call site(s) in %d function(s):" % (
        sum(len(v) for v in callers.values()), len(callers)))
    for fn in sorted(callers):
        for a in sorted(callers[fn]):
            print("    0x%-9x  in %s" % (a, fn))
    return 0


if __name__ == "__main__":
    sys.exit(main())
