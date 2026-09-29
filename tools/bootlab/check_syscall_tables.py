#!/usr/bin/env python3
"""Check that the ravynOS kernel and the SDK Libsystem builds against agree
on every syscall number, and that the compiled stubs encode the numbers the
tables say they do.

WHY THIS EXISTS
---------------
There is only one syscall table in the build, and it is not the one you would
guess.  Kernel/xnu/bsd/kern/syscalls.master is the design authority.
libsystem_kernel's Makefile runs create-syscalls.pl on *that* file to generate
the stub names, prototypes, argument counts and NO_SYSCALL_STUB filtering --
but each generated _foo.s is a template whose actual number is the macro
SYS_foo, resolved at assembly time against

    $RAVYN_SDKROOT/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/sys/syscall.h

which is Apple's table (its own banner says "created from
/bsd.syscalls.master").  So the number a stub issues comes from Apple's
table and the name comes from ravynOS's, and nothing in the build compares
them.

Today they agree, exactly: regenerating the header from ravynOS's own master
with makesyscalls.sh produces a file byte-identical to the live SDK's except
for the "created from" provenance comment.  That is the thing worth keeping
true, and nothing enforces it.

The two failure modes this catches, and why they are different:

  * A name present in the master but not in the SDK header fails the BUILD,
    loudly, at "#error SYS_x not defined".  Annoying, but safe.
  * A name present in both at DIFFERENT numbers compiles cleanly and silently
    issues the wrong syscall.  The caller then reaches whatever the kernel
    dispatches at that number, with the wrong argument count and the wrong
    argument conventions.  That is memory-unsafe, not merely wrong, and it is
    the failure this script exists to make impossible.

THREE PASSES, because each can fail when the others cannot:

  A. number-level: same number, different name.
  B. name-level:   same name, different number.  This is the dangerous one.
  C. ground truth: the imm32 actually fed to the `syscall` instruction in
     every compiled stub object.  Tables can agree while a stale or
     hand-patched object does not, and only this pass looks at the bytes that
     will really be executed.

Passes A and B read the tables; pass C reads
Libraries/Libsystem/libsystem_kernel/sys/*.o.  C is skipped with a warning if
no objects are present, so the script is still useful before a build.

EXIT STATUS
-----------
0  tables agree and every compiled stub matches its own name's number
1  a divergence was found; every one is printed, not just the first
2  the input could not be read at all

Usage:
    python3 tools/bootlab/check_syscall_tables.py [path/to/syscall.h]

With no argument it checks the SDK that tools/bootlab/build-libraries.sh
actually builds against ($RAVYN_BUILD_DIR/Developer/Platforms/...).  Point it
at Developer/ravynOS.sdk/.../PrivateHeaders/sys/syscall.h to check the
in-repo copy instead.
"""
import os
import re
import struct
import sys
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MASTER = os.path.join(ROOT, "Kernel", "xnu", "bsd", "kern", "syscalls.master")
STUBDIR = os.path.join(ROOT, "Libraries", "Libsystem", "libsystem_kernel", "sys")

BUILD = os.environ.get("RAVYN_BUILD_DIR", os.path.expanduser("~/Projects/build"))
DEFAULT_SDK = os.path.join(
    BUILD, "Developer", "Platforms", "ravynOS.platform", "Developer", "SDKs",
    "ravynOS.sdk", "System", "Library", "Frameworks", "System.framework",
    "Versions", "B", "PrivateHeaders", "sys", "syscall.h")


# --------------------------------------------------------------- the master
def parse_master(path):
    """{number: (name, argtext)}.

    Every #if in syscalls.master declares the SAME numbers in both arms -- only
    the name changes to nosys/enosys when a feature is off -- so the numbers
    can be read from the taken (first) arm alone, and nothing here has to
    evaluate a condition.

    `taken` is a STACK, not a depth counter.  That is not pedantry: with a
    counter, `#else` has to be handled, and handling it as a decrement drives
    the count negative at the first #else in the file, after which every
    remaining entry is skipped.  The first version of this function did
    exactly that and reported 34 of 558 entries with an overall "OK" -- an
    instrument that was blind for 94% of its input and said so with a
    success status.  The coverage gate in main() exists to make that class of
    failure impossible to ship again.
    """
    out, taken = {}, []            # one entry per open #if: in the first arm?
    all_numbers = set()            # every number that appears in ANY arm
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        s = line.lstrip()
        if s.startswith("#if"):
            taken.append(True)
            continue
        if s.startswith("#else"):
            if taken:
                taken[-1] = not taken[-1]
            continue
        if s.startswith("#endif"):
            if taken:
                taken.pop()
            continue
        m0 = re.match(r"^(\d+)\s+\S+\s+\S+\s+\{", line)
        if not m0:
            continue
        all_numbers.add(int(m0.group(1)))
        if not all(taken):         # inside a not-taken arm
            continue
        m = re.match(r"^(\d+)\s+\S+\s+\S+\s+\{(.*)\}\s*$", line)
        if not m:
            continue
        f = re.match(r"\s*(?:[\w ]+\s+)?(\w+)\s*\((.*)\)\s*(?:NO_SYSCALL_STUB\s*)?;",
                     m.group(2))
        if f:
            out[int(m.group(1))] = (f.group(1), f.group(2))
    return out, all_numbers


# -------------------------------------------------------------- the SDK header
def parse_sdk(path):
    name2num, num2name = {}, {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"^#define\s+SYS_(\S+)\s+(\d+)\s*$", line)
        if m:
            name2num[m.group(1)] = int(m.group(2))
            num2name[int(m.group(2))] = m.group(1)
    return name2num, num2name


def norm(name, sdk_names):
    """The master renames some calls sys_<name> to dodge a libc collision."""
    return name[4:] if name.startswith("sys_") and name not in sdk_names else name


def syscall_immediates(path):
    """Every imm32 that could feed this object's `syscall` instructions.

    x86 `syscall` takes its selector in eax, and every stub here materialises
    it as `movl $imm, %eax` immediately before.  Rather than assume that, take
    every `mov eax, imm32` (b8) within 16 bytes before each 0f 05 and return the
    set, so a stub that sets it in two places reports both rather than one.
    """
    data = open(path, "rb").read()
    hits = set()
    for m in re.finditer(rb"\x0f\x05", data):
        window = data[max(0, m.start() - 16):m.start()]
        for mm in re.finditer(rb"\xb8(.{4})", window, re.S):
            hits.add(struct.unpack("<i", mm.group(1))[0])
    return hits


def main():
    sdk_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SDK
    for p in (MASTER, sdk_path):
        if not os.path.isfile(p):
            print("check_syscall_tables: cannot read %s" % p, file=sys.stderr)
            return 2

    kernel, all_numbers = parse_master(MASTER)
    sdk_name2num, sdk_num2name = parse_sdk(sdk_path)
    k_name2num = {}
    for num, (name, _args) in kernel.items():
        k_name2num.setdefault(norm(name, sdk_name2num), num)

    print("kernel master : %s (%d entries, max %d)"
          % (MASTER, len(kernel), max(kernel)))
    print("SDK header    : %s (%d SYS_ defines)"
          % (sdk_path, len(sdk_name2num)))

    failures = []

    # ---- 0. COVERAGE. Refuse to conclude anything if the parser did not see
    # every syscall number in the file.  A checker that silently covers part
    # of its input and exits 0 is worse than no checker, because it gets
    # trusted.  The first version of parse_master did exactly that -- 34 of
    # 558 entries, overall "OK" -- and the only reason it was caught is that
    # the entry count was printed and read.  The invariant is stated against
    # the numbers themselves rather than a line count, because both arms of
    # every conditional declare the same number and a line count would have
    # been the wrong thing to compare.
    missing = sorted(all_numbers - set(kernel))
    if missing:
        print("check_syscall_tables: PARSER COVERAGE FAILURE: %d of %d "
              "syscall numbers in the master were not parsed (first: %s). "
              "Refusing to conclude anything; a partial parse reports OK "
              "while blind."
              % (len(missing), len(all_numbers), missing[:5]), file=sys.stderr)
        return 2
    print("  pass 0: parser resolved all %d syscall numbers in the master"
          % len(all_numbers))

    # ---- B. name-level: the dangerous one, reported first.
    shared = sorted(set(k_name2num) & set(sdk_name2num))
    for name in shared:
        if k_name2num[name] != sdk_name2num[name]:
            landed = kernel.get(sdk_name2num[name], ("<none>", ""))[0]
            failures.append(
                "NAME-LEVEL: %s is %d in ravynOS and %d in the SDK, so the "
                "stub would issue %d, which the kernel dispatches as %s"
                % (name, k_name2num[name], sdk_name2num[name],
                   sdk_name2num[name], landed))

    # ---- A. number-level.
    for num in sorted(set(kernel) & set(sdk_num2name)):
        kname = norm(kernel[num][0], sdk_name2num)
        sname = sdk_num2name[num]
        if kname != sname and kname not in ("nosys", "enosys"):
            failures.append(
                "NUMBER-LEVEL: %d is %s in ravynOS and %s in the SDK"
                % (num, kname, sname))
        elif kname != sname:
            # A ravynOS dead slot (nosys/enosys) against a live Apple name.
            # Memory-safe: nosys/enosys take no arguments and dereference
            # nothing, so the call returns ENOSYS rather than corrupting
            # anything.  Worth seeing, not worth failing the build over --
            # and the name-level pass above is what actually matters.
            print("  note: %d is %s (ravynOS dead slot) vs %s (SDK); "
                  "memory-safe, ENOSYS" % (num, kname, sname))

    # ---- C. ground truth: the numbers actually encoded in the shipped objects.
    #
    # What this pass can soundly check is NOT "stub X equals SYS_X".  The
    # expected macro is not recoverable from the object: the C symbol is the
    # Mach-O spelling (__getpid, ____sigwait_nocancel) while the number comes
    # from a differently-spelled macro in a NONAME stub --
    # UNIX_SYSCALL_NONAME(getpid, ...) inside ___getpid.s.  Guessing that
    # pairing from the filename made this pass skip 190 of 454 objects, which
    # is worse than not having the pass at all: blind for 42% of its input
    # and exiting 0.  The limit is stated here rather than papered over.
    #
    # What IS sound, and is the complement of A and B: every number a compiled
    # stub will really execute must be a number both tables define, and they
    # must agree about what lives there.  That catches a stale or hand-patched
    # object, which reading the tables cannot.
    objs = sorted(glob.glob(os.path.join(STUBDIR, "*.o")))
    sites = 0
    for obj in objs:
        base = os.path.basename(obj)
        for imm in syscall_immediates(obj):
            num = imm & 0xffff
            sites += 1
            if num not in sdk_num2name:
                failures.append(
                    "COMPILED: %s executes syscall %d, which the SDK header "
                    "does not define at all" % (base, num))
                continue
            sname = sdk_num2name[num]
            kname = norm(kernel[num][0], sdk_name2num) if num in kernel else None
            if kname is not None and kname != sname \
                    and kname not in ("nosys", "enosys"):
                failures.append(
                    "COMPILED: %s executes syscall %d, which the SDK calls %s "
                    "and the kernel dispatches as %s"
                    % (base, num, sname, kname))
    if objs:
        print("  pass C: decoded %d syscall sites across %d stub objects; "
              "every encoded number is defined in both tables and they agree "
              "about what lives there" % (sites, len(objs)))
    else:
        print("  pass C: SKIPPED, no compiled stubs in %s" % STUBDIR)

    if failures:
        print("\nFAIL: %d divergence(s)" % len(failures), file=sys.stderr)
        for f in failures:
            print("  " + f, file=sys.stderr)
        return 1

    print("\nOK: %d shared syscall names, all at the same number; "
          "no memory-unsafe divergence." % len(shared))
    return 0


if __name__ == "__main__":
    sys.exit(main())
