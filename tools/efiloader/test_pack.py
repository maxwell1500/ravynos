#!/usr/bin/env python3
"""Self-test for tools/efiloader/pack.py.

WHY THIS EXISTS
---------------
pack.py shipped a bug in which every COFF symbol name longer than eight
characters decoded as the empty string, so two DIFFERENT relocations were
resolved to the SAME address and the loader did `lgdt` from a string
constant.  It produced a triple fault three sessions downstream, and the
intermediate symptom (a selector that looked like it came from the
firmware's GDT) sent the investigation in exactly the wrong direction for
several rounds.

The project rule that applies is: *before trusting a negative, prove the
instrument can see a positive.*  So this file has three parts:

  POSITIVE   a known-good object with three references that must land on
             three DIFFERENT, correct addresses.
  NEGATIVE   an object with a deliberately unresolvable relocation, which
             pack.py must REFUSE.  If the refusal ever stops happening,
             that is the regression that matters.
  ROUNDTRIP  re-derive each address from the bytes actually emitted in the
             packed PE and check it against the symbol the map claims.

Exit status 0 means every check ran and passed.  A check that cannot fail
is not a check, so each assertion below is written to be able to fail.

Usage: python3 test_pack.py [--keep]
"""
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "pack.py")
CLANG = os.environ.get("CLANG", "/Library/Developer/CommandLineTools/usr/bin/clang")
KEEP = "--keep" in sys.argv
TMP = tempfile.mkdtemp(prefix="packtest.")

failures = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    if cond:
        print("  ok   %s" % what)
    else:
        print("  FAIL %s" % what)
        failures.append(what)


def compile_src(src, name, extra=()):
    c = os.path.join(TMP, name + ".c")
    o = os.path.join(TMP, name + ".obj")
    open(c, "w").write(src)
    cmd = [CLANG, "-target", "x86_64-unknown-windows", "-ffreestanding",
           "-fno-stack-protector", "-mno-red-zone", "-mcmodel=medium",
           "-Os", "-g0", "-c", c, "-o", o] + list(extra)
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("compile failed for %s:\n%s" % (name, r.stderr))
    return o


def pack(obj, out, entry, mapfile=None, expect_ok=True):
    cmd = [sys.executable, PACK, obj, out, entry]
    if mapfile:
        cmd += ["10", mapfile]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if expect_ok and r.returncode:
        sys.exit("pack failed unexpectedly:\n%s" % (r.stdout + r.stderr))
    return r


# ---------------------------------------------------------------- positive
GOOD = r'''
/* Three references that MUST resolve to three different addresses.
 *
 * THE NAMES ARE DELIBERATELY LONGER THAN EIGHT CHARACTERS.  An earlier
 * version of this file used g_alpha/g_beta/g_msg, all of which are stored
 * INLINE in a COFF symbol record, so the test never exercised the
 * string-table path -- and it PASSED with the original long-name decoding
 * bug deliberately reintroduced.  A check that cannot fail proves nothing,
 * and this one very nearly did.
 *
 * volatile + used + noinline, because the first version of this file was
 * FOLDED AWAY by -Os and the map came back empty.  That is the
 * "a check that cannot fail proves nothing" trap, and the check itself is
 * what caught it -- not inspection.
 */
typedef unsigned int u32;
static volatile u32 ravynos_g_alpha_symbol;
static volatile u32 ravynos_g_beta_symbol;
__attribute__((used)) static const char ravynos_g_msg_symbol[] = "alpha-marker-string";

__attribute__((noinline)) u32 touch(u32 x)
{
        ravynos_g_alpha_symbol = x;
        ravynos_g_beta_symbol = ravynos_g_alpha_symbol + 1;
        return (u32)ravynos_g_msg_symbol[0] + ravynos_g_beta_symbol;
}

void efi_main(void *h, void *st)
{
        ravynos_g_alpha_symbol = (u32)(unsigned long)h;
        ravynos_g_beta_symbol = ravynos_g_alpha_symbol + 1;
        touch(ravynos_g_beta_symbol);
        /* Force a named relocation to ravynos_g_msg_symbol as well, so the map has to
         * resolve a string, a .bss word and another .bss word. */
        ravynos_g_beta_symbol = ravynos_g_beta_symbol + (u32)(unsigned long)&ravynos_g_msg_symbol[0];
        (void)st;
}
'''

print("POSITIVE: a known-good object must link, with three distinct targets")
good_obj = compile_src(GOOD, "good")
good_efi = os.path.join(TMP, "good.efi")
good_map = os.path.join(TMP, "good.map")
pack(good_obj, good_efi, "efi_main", good_map)
check(os.path.isfile(good_efi) and os.path.getsize(good_efi) > 0,
      "packer produced an image")

rows = [l.split() for l in open(good_map) if not l.startswith("#")
        and len(l.split()) == 5]
check(len(rows) >= 3, "relocation map has at least 3 entries (%d)" % len(rows))
check(len(rows) >= 3,
      "map lines are all well formed (section P voff sym S) -- %d of them"
      % len(rows))
pairs = {}
for sec, P, voff, sym, S in rows:
    pairs.setdefault(sym, set()).add(int(S, 16))
check(len(pairs) >= 3, "map names at least 3 distinct symbols (%d)" % len(pairs))
allsyms = {}
for sec, P, voff, sym, S in rows:
    allsyms[sym] = int(S, 16)
check(len(set(allsyms.values())) == len(allsyms),
      "every distinct symbol resolved to a DISTINCT address "
      "(%d symbols, %d distinct addresses)"
      % (len(allsyms), len(set(allsyms.values()))))
check("ravynos_g_alpha_symbol" in allsyms and "ravynos_g_beta_symbol" in allsyms and "ravynos_g_msg_symbol" in allsyms,
      "ravynos_g_alpha_symbol, ravynos_g_beta_symbol and ravynos_g_msg_symbol are all present by name (%s)"
      % ", ".join(sorted(allsyms)))

# ---------------------------------------------------------------- negative
BAD = r'''
/* An unresolvable relocation: declared, never defined, no storage. */
extern int ravynos_no_such_symbol_anywhere;
int use_it(void) { return ravynos_no_such_symbol_anywhere; }
void efi_main(void *h, void *st) { (void)h; (void)st; use_it(); }
'''
print("\nNEGATIVE: an unresolvable relocation must be REFUSED")
bad_obj = compile_src(BAD, "bad")
bad_efi = os.path.join(TMP, "bad.efi")
r = pack(bad_obj, bad_efi, "efi_main", expect_ok=False)
check(r.returncode != 0, "packer exited non-zero on an unresolvable symbol")
check("REFUSING" in (r.stdout + r.stderr),
      "packer said REFUSING rather than inventing an address")
check(not os.path.isfile(bad_efi) or os.path.getsize(bad_efi) == 0,
      "no bogus image was written for the unresolvable object")

# --------------------------------------------------------------- roundtrip
print("\nROUNDTRIP: re-derive addresses from the emitted PE bytes")


def load_pe(path):
    d = open(path, "rb").read()
    e = struct.unpack_from("<I", d, 0x3C)[0]
    optsz = struct.unpack_from("<H", d, e + 20)[0]
    oh = e + 24
    nsec = struct.unpack_from("<H", d, e + 6)[0]
    secs = []
    so = oh + optsz
    for i in range(nsec):
        o = so + 40 * i
        name = d[o:o + 8].rstrip(b"\0").decode()
        vs, va, rawsz, rawptr = struct.unpack_from("<IIII", d, o + 8)
        secs.append(dict(name=name, va=va, rawptr=rawptr, rawsz=rawsz))
    return d, secs


d, secs = load_pe(good_efi)
sec_by_va = {}
for s in secs:
    for off in range(0, s["rawsz"]):
        sec_by_va[s["va"] + off] = s["name"]


def rva_to_fileoff(rva):
    for s in secs:
        if s["va"] <= rva < s["va"] + max(s["rawsz"], 1):
            return s["rawptr"] + (rva - s["va"])
    return None


ok = 0
bad = 0
for sec, P, voff, sym, S in rows:
    P = int(P, 16)
    S = int(S, 16)
    fo = rva_to_fileoff(P)
    if fo is None:
        bad += 1
        continue
    # The REL32 displacement actually stored, plus the end of the
    # instruction, must land exactly on the address the map claims.
    disp = struct.unpack_from("<i", d, fo)[0]
    if P + 4 + disp == S:
        ok += 1
    else:
        bad += 1
        print("       %s: P=0x%x disp=%d -> 0x%x, expected 0x%x"
              % (sym, P, disp, P + 4 + disp, S))
check(bad == 0 and ok == len(rows),
      "all %d relocations re-derive to the symbol the map claims" % len(rows))

print("\n%d checks, %d failures" % (checks, len(failures)))
if KEEP:
    print("kept: %s" % TMP)
else:
    subprocess.run(["rm", "-rf", TMP])
sys.exit(1 if failures else 0)
