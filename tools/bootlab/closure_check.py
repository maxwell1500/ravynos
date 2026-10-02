#!/usr/bin/env python3
"""Offline closure + Mach-O validity checker for a bootlab manifest.

Why this exists
---------------
mkimage.py verifies an image by hashing bytes.  It never resolves a symbol
and never replays dyld2's load-time validation, so two whole classes of
defect sail straight through mkimage.py and only detonate once the image
boots:

  (a) a staged dylib whose LC_DYLD_EXPORTS_TRIE carries dataoff=0/datasize=0
      against a nonzero __LINKEDIT.fileoff.  dyld2 throws
      "malformed mach-o image: dyld chained fixups info underruns __LINKEDIT"
      at Libraries/dyld/src/ImageLoaderMachO.cpp:487 and the process dies.

  (b) a closure with a non-weak undefined symbol that no staged dylib
      exports.  dyld2 throws at bind time, long after the image "booted".

This tool answers both questions offline, with no QEMU and no build.

The verdict never uses otool.  Mach-O is parsed by walking raw bytes from a
mach_header_64; nm -m is used only as an independent cross-check of the
symbol extraction, and its disagreement is reported, not silently absorbed.

Usage:
    python3 closure_check.py [MANIFEST] [--image IMG] [--nm-check N]

    MANIFEST   path to the manifest JSON (default: manifest_dynamic.json
               next to this script)
    --image    analyse the bytes actually inside a built FAT32 image rather
               than the host files the manifest points at.  Reads each
               staged path out of the image with fat32img.
    --nm-check number of files to cross-check against `nm -m`
               (default 3; 0 disables)

Exit status:
    0  closure complete, no unresolved non-weak undefined symbols, and
       every staged dylib passes the dyld2 validation
    1  otherwise (the report says which, and why)
"""

import argparse
import json
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# --------------------------------------------------------------------------
# Mach-O constants.  Verified in this repo against Libraries/dyld's own
# headers and against ImageLoaderMachO.cpp.
# --------------------------------------------------------------------------

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
FAT_CIGAM = 0xBEBAFECA

CPU_ARCH_ABI64 = 0x01000000
CPU_TYPE_X86_64 = CPU_ARCH_ABI64 | 7
CPU_SUBTYPE_X86_64_ALL = 3

MH_EXECUTE = 0x2
MH_DYLINKER = 0x7
MH_DYLIB = 0x6

FILETYPE_NAMES = {
    0x1: "MH_OBJECT",
    MH_EXECUTE: "MH_EXECUTE",
    0x4: "MH_CORE",
    MH_DYLIB: "MH_DYLIB",
    0x8: "MH_BUNDLE",
    0x9: "MH_DYLIB_STUB",
    0xA: "MH_DSYM",
    0xB: "MH_KEXT_BUNDLE",
    MH_DYLINKER: "MH_DYLINKER",
}

LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_DYSYMTAB = 0xB
LC_LOAD_DYLIB = 0xC
LC_ID_DYLIB = 0xD
LC_LOAD_DYLINKER = 0xE
LC_ID_DYLINKER = 0xF
LC_DYLD_INFO = 0x22
LC_DYLD_INFO_ONLY = 0x80000022
LC_DYLD_EXPORTS_TRIE = 0x80000033
LC_DYLD_CHAINED_FIXUPS = 0x80000034
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_LAZY_LOAD_DYLIB = 0x20
LC_LOAD_UPWARD_DYLIB = 0x80000023

# Dependency-bearing commands.  All four name a dylib that must exist on the
# staged disk for the loader to make progress.
DEP_CMDS = (
    LC_LOAD_DYLIB,
    LC_REEXPORT_DYLIB,
    LC_LAZY_LOAD_DYLIB,
    LC_LOAD_UPWARD_DYLIB,
)
DEP_CMD_NAMES = {
    LC_LOAD_DYLIB: "LC_LOAD_DYLIB",
    LC_REEXPORT_DYLIB: "LC_REEXPORT_DYLIB",
    LC_LAZY_LOAD_DYLIB: "LC_LAZY_LOAD_DYLIB",
    LC_LOAD_UPWARD_DYLIB: "LC_LOAD_UPWARD_DYLIB",
}

# nlist
N_STAB = 0xE0
N_PEXT = 0x10
N_TYPE = 0x0E
N_EXT = 0x01
N_UNDF = 0x0
N_ABS = 0x2
N_SECT = 0xE
N_INDR = 0xA

N_WEAK_REF = 0x0040
N_WEAK_DEF = 0x0080

# dysymtab indirect symbol table magic entries
INDIRECT_SYMBOL_ABS = 0x40000000
INDIRECT_SYMBOL_LOCAL = 0x80000000


class MachOError(Exception):
    pass


def cstr(buf, off):
    """NUL-terminated string at `off`, or None."""
    if off < 0 or off >= len(buf):
        return None
    end = buf.find(b"\0", off)
    if end < 0:
        end = len(buf)
    return buf[off:end].decode("utf-8", "replace")


class MachO(object):
    """A parsed 64-bit Mach-O slice."""

    def __init__(self, data):
        self.data = data
        self.filetype = None
        self.ncmds = 0
        self.segments = []          # (segname, fileoff, filesize)
        self.symtab = None          # (symoff, nsyms, stroff, strsize)
        self.dysymtab = None        # dict of dysymtab fields
        self.exports_trie = None    # (dataoff, datasize) or None
        self.chained_fixups = None  # (dataoff, datasize) or None
        self.id_dylib = None
        self.id_dylinker = None
        self.load_dylinker = None
        self.deps = []              # (cmd, install_name)
        self.linkedit = None        # (fileoff, filesize) or None
        self._parse()

    # -- header / load commands -------------------------------------------

    def _parse(self):
        d = self.data
        if len(d) < 32:
            raise MachOError("shorter than a mach_header_64")
        (magic, cputype, _sub, filetype, ncmds, _sizeofcmds, _flags,
         _res) = struct.unpack_from("<8I", d, 0)
        if magic != MH_MAGIC_64:
            raise MachOError("not a 64-bit Mach-O (magic 0x%08x)" % magic)
        self.filetype = filetype
        self.ncmds = ncmds
        off = 32
        # sizeofcmds lives at +20; walk exactly that many bytes.
        sizeofcmds = struct.unpack_from("<I", d, 20)[0]
        limit = 32 + sizeofcmds
        for _ in range(ncmds):
            if off + 8 > len(d) or off + 8 > limit:
                raise MachOError("load command runs past the header")
            cmd, cmdsize = struct.unpack_from("<II", d, off)
            if cmdsize < 8 or off + cmdsize > limit:
                raise MachOError("load command with bogus cmdsize %d" % cmdsize)
            self._command(cmd, cmdsize, off)
            off += cmdsize

    def _command(self, cmd, cmdsize, off):
        d = self.data
        if cmd == LC_SEGMENT_64:
            # segname[16] at +8; vmaddr,vmsize,fileoff,filesize at +24;
            # maxprot,initprot,nsects,flags at +56.
            segname = cstr(d, off + 8)
            _vmaddr, _vmsize, fileoff, filesize = struct.unpack_from(
                "<4Q", d, off + 24)
            self.segments.append((segname, fileoff, filesize))
            if segname == "__LINKEDIT":
                self.linkedit = (fileoff, filesize)
        elif cmd == LC_SYMTAB:
            symoff, nsyms, stroff, strsize = struct.unpack_from("<4I", d, off + 8)
            self.symtab = (symoff, nsyms, stroff, strsize)
        elif cmd == LC_DYSYMTAB:
            # struct dysymtab_command has 20 uint32_t fields after the
            # 8-byte common header (mach-o/loader.h): the symbol table is
            # grouped local / extdef / undef, and only THEN come toc,
            # modtab, extrefsyms, indirectsyms, extrel and locrel.  Reading
            # nundefsym out of the nextdefsym slot silently under-counts
            # imports, so index all 20 by name.
            f = struct.unpack_from("<20I", d, off)
            self.dysymtab = {
                "ilocalsym": f[2], "nlocalsym": f[3],
                "iextdefsym": f[4], "nextdefsym": f[5],
                "iundefsym": f[6], "nundefsym": f[7],
                "tocoff": f[8], "ntoc": f[9],
                "modtaboff": f[10], "nmodtab": f[11],
                "extrefsymoff": f[12], "nextrefsyms": f[13],
                "indirectsymoff": f[14], "nindirectsyms": f[15],
                "extreloff": f[16], "nextrel": f[17],
                "locreloff": f[18], "nlocrel": f[19],
            }
        elif cmd == LC_DYLD_EXPORTS_TRIE:
            self.exports_trie = struct.unpack_from("<2I", d, off + 8)
        elif cmd == LC_DYLD_CHAINED_FIXUPS:
            self.chained_fixups = struct.unpack_from("<2I", d, off + 8)
        elif cmd == LC_ID_DYLIB:
            self.id_dylib = self._dylib_name(off)
        elif cmd == LC_ID_DYLINKER:
            self.id_dylinker = self._dylib_name(off)
        elif cmd == LC_LOAD_DYLINKER:
            self.load_dylinker = self._dylib_name(off)
        elif cmd in DEP_CMDS:
            self.deps.append((cmd, self._dylib_name(off)))

    def _dylib_name(self, off):
        nameoff = struct.unpack_from("<I", self.data, off + 8)[0]
        # lc_str offsets are relative to the start of the load command.
        return cstr(self.data, off + nameoff)

    # -- symbols -----------------------------------------------------------

    def _nlist(self, index):
        symoff, nsyms, stroff, strsize = self.symtab
        raw = struct.unpack_from("<IBBHQ", self.data, symoff + index * 16)
        n_strx, n_type, n_sect, n_desc, n_value = raw
        if n_strx >= strsize:
            return None
        name = cstr(self.data, stroff + n_strx)
        return {
            "name": name, "type": n_type, "sect": n_sect,
            "desc": n_desc, "value": n_value,
        }

    def defined_globals(self):
        """Defined global symbols: n_type & N_TYPE == N_SECT and N_EXT.

        This is the set a re-exporting dylib actually publishes at a real
        address.  N_ABS externals (n_type 0x03) are deliberately excluded:
        they carry a link-time constant, not code or data dyld can bind a
        client to.  They are counted separately by absolute_globals() so the
        nm -m cross-check stays honest about the difference.
        """
        out = {}
        if not self.symtab:
            return out
        _symoff, nsyms, _stroff, _strsize = self.symtab
        for i in range(nsyms):
            s = self._nlist(i)
            if s is None or not s["name"]:
                continue
            if (s["type"] & N_STAB) or not (s["type"] & N_EXT):
                continue
            if (s["type"] & N_TYPE) != N_SECT:
                continue
            out.setdefault(s["name"], s)
        return out

    def indirect_alias_globals(self):
        """N_INDR externals: {alias: target_name}.

        These are the linker's same-address aliases -- libsystem_c's
        `_memcpy` is one, pointing at `__platform_memmove`.  `dyld_info
        -exports` reports them as

            [re-export] _memcpy (__platform_memmove from libsystem_platform)

        so a re-exporting dylib really does publish them and dyld2 really
        does bind them.  Excluding N_INDR from the export universe makes the
        whole libc string family (_memcpy, _strlen, _memset, _strcmp, ...)
        look unresolved in a closure that is in fact complete.

        N_INDR's n_value is a string-table offset naming the target symbol,
        not a symbol index (measured: _memcpy's n_value is 0x26b5, and
        strtab+0x26b5 is "__platform_memmove").
        """
        out = {}
        if not self.symtab:
            return out
        _symoff, nsyms, stroff, strsize = self.symtab
        for i in range(nsyms):
            s = self._nlist(i)
            if s is None or not s["name"]:
                continue
            if (s["type"] & N_STAB) or not (s["type"] & N_EXT):
                continue
            if (s["type"] & N_TYPE) != N_INDR:
                continue
            target = None
            if s["value"] < strsize:
                target = cstr(self.data, stroff + s["value"])
            out[s["name"]] = target
        return out

    def absolute_globals(self):
        """N_ABS externals: nm -m prints them as "(absolute) external"."""
        out = {}
        if not self.symtab:
            return out
        _symoff, nsyms, _stroff, _strsize = self.symtab
        for i in range(nsyms):
            s = self._nlist(i)
            if s is None or not s["name"]:
                continue
            if (s["type"] & N_STAB) or not (s["type"] & N_EXT):
                continue
            if (s["type"] & N_TYPE) == N_ABS:
                out.setdefault(s["name"], s)
        return out

    def indirect_symbol_counts(self):
        """(referenced_defined, referenced_undefined, magic_entries).

        Walks LC_DYSYMTAB's indirect symbol table, which is where
        `nm -gU` loses symbols: a toolchain can reference an export only
        through a pointer slot here.  INDIRECT_SYMBOL_ABS and
        INDIRECT_SYMBOL_LOCAL are the two magic values dyld itself skips
        (ImageLoaderMachOClassic.cpp:1716-1720).
        """
        counts = [0, 0, 0]
        if not self.symtab or not self.dysymtab:
            return tuple(counts)
        _symoff, nsyms, _stroff, _strsize = self.symtab
        off = self.dysymtab["indirectsymoff"]
        for _ in range(self.dysymtab["nindirectsyms"]):
            if off + 4 > len(self.data):
                break
            (idx,) = struct.unpack_from("<I", self.data, off)
            off += 4
            if idx in (INDIRECT_SYMBOL_ABS, INDIRECT_SYMBOL_LOCAL):
                counts[2] += 1
                continue
            if idx == 0 or idx >= nsyms:
                continue
            s = self._nlist(idx)
            if s is None:
                continue
            t = s["type"] & N_TYPE
            if t == N_SECT and (s["type"] & N_EXT):
                counts[0] += 1
            elif t == N_UNDF and (s["type"] & N_EXT):
                counts[1] += 1
        return tuple(counts)

    def undefineds(self):
        """{(name): is_weak} for every undefined external symbol.

        The whole LC_SYMTAB is scanned, not just LC_DYSYMTAB's
        [iundefsym, +nundefsym) range, and the indirect symbol table is
        unioned on top.  Both widenings are load-bearing: dyld2 binds from
        the symbol table it is given, and a stale or under-declared
        LC_DYSYMTAB range makes an importing dylib look complete when it is
        not.  Measured on the staged usr/lib/libSystem.B.dylib: its
        LC_DYSYMTAB declares nundefsym=27 while the symbol table holds 101
        N_UNDF externals, which is exactly what `nm -m` reports.  Trusting
        the declared range there reports "2 imports" and misses 99.
        """
        out = {}
        if not self.symtab:
            return out

        def consider(i):
            s = self._nlist(i)
            if s is None or not s["name"]:
                return
            if (s["type"] & N_STAB) or not (s["type"] & N_EXT):
                return
            if (s["type"] & N_TYPE) != N_UNDF:
                return
            weak = bool(s["desc"] & (N_WEAK_REF | N_WEAK_DEF))
            out.setdefault(s["name"], weak)

        _symoff, nsyms, _stroff, _strsize = self.symtab
        for i in range(nsyms):
            consider(i)
        if self.dysymtab:
            off = self.dysymtab["indirectsymoff"]
            for _ in range(self.dysymtab["nindirectsyms"]):
                if off + 4 > len(self.data):
                    break
                (idx,) = struct.unpack_from("<I", self.data, off)
                off += 4
                if idx in (INDIRECT_SYMBOL_ABS, INDIRECT_SYMBOL_LOCAL):
                    continue
                if 0 < idx < nsyms:
                    consider(idx)
        return out

    def dysymtab_undef_range(self):
        """The N_UNDF symbols LC_DYSYMTAB claims to describe, and the count
        the symbol table actually holds.  A mismatch is reported, never
        silently resolved in either direction."""
        _symoff, nsyms, _stroff, _strsize = self.symtab
        actual = 0
        for i in range(nsyms):
            s = self._nlist(i)
            if s is None or not s["name"]:
                continue
            if (s["type"] & N_STAB) or not (s["type"] & N_EXT):
                continue
            if (s["type"] & N_TYPE) == N_UNDF:
                actual += 1
        declared = None
        if self.dysymtab:
            declared = self.dysymtab["nundefsym"]
        return declared, actual

    # -- dyld2 validation --------------------------------------------------

    def dyld2_validation(self):
        """Replay ImageLoaderMachO.cpp's linkedit checks.

        Returns (ok, [(line, verdict, arithmetic), ...]) covering
        lines 419-422 (preconditions), 479/481 (chained fixups) and
        487/489 (exports trie), in dyld2's own evaluation order so the
        first throw is the one reported.

        Note the message text at 488/490 is dyld's own copy-paste bug: the
        trie errors also say "chained fixups".  The line numbers are what
        identify the check; this tool names them properly.
        """
        trace = []

        def note(line, ok, text):
            trace.append((line, "PASS" if ok else "REJECT", text))
            return ok

        # 419: some linkedit-consuming command must exist
        ok = note(419,
                  not (self.symtab is None and self.chained_fixups is None),
                  "LC_SYMTAB=%s LC_DYLD_CHAINED_FIXUPS=%s"
                  % (self.symtab is not None,
                     self.chained_fixups is not None))
        # 421: LC_DYSYMTAB must exist
        ok = note(421, self.dysymtab is not None, "LC_DYSYMTAB=%s"
                  % (self.dysymtab is not None)) and ok

        if self.linkedit is None:
            trace.append((424, "REJECT", "no __LINKEDIT segment"))
            return False, trace
        start, size = self.linkedit
        end = start + size
        trace.append((424, "info",
                      "__LINKEDIT fileoff=%d filesize=%d -> [%d, %d)"
                      % (start, size, start, end)))

        if self.chained_fixups is not None:
            off, sz = self.chained_fixups
            # 479: dataoff < linkeditFileOffsetStart -> underruns
            ok = note(479, off >= start,
                      "chained fixups dataoff=%d >= %d  (%d < %d ? %s)"
                      % (off, start, off, start, off < start)) and ok
            # 481: dataoff + datasize > linkeditFileOffsetEnd -> overruns
            ok = note(481, off + sz <= end,
                      "chained fixups dataoff=%d datasize=%d -> end=%d <= %d"
                      % (off, sz, off + sz, end)) and ok

        if self.exports_trie is not None:
            off, sz = self.exports_trie
            # 487: dataoff < linkeditFileOffsetStart -> underruns
            ok = note(487, off >= start,
                      "exports trie dataoff=%d >= %d  (%d < %d ? %s)"
                      % (off, start, off, start, off < start)) and ok
            # 489: dataoff + datasize > linkeditFileOffsetEnd -> overruns
            ok = note(489, off + sz <= end,
                      "exports trie dataoff=%d datasize=%d -> end=%d <= %d"
                      % (off, sz, off + sz, end)) and ok
        else:
            trace.append((485, "info", "no LC_DYLD_EXPORTS_TRIE; 487/489 not evaluated"))

        return ok, trace


# --------------------------------------------------------------------------
# Fat / universal binaries
# --------------------------------------------------------------------------

def select_x86_64(data, label):
    """Return the x86_64 slice of `data`, or raise MachOError.

    Fat headers are always big-endian; a thin mach_header_64 is
    little-endian, so MH_MAGIC_64 (0xfeedfacf) must be compared against the
    little-endian read or every thin dylib looks like magic 0xcffaedfe.
    """
    if len(data) < 8:
        raise MachOError("file shorter than a magic")
    fat = struct.unpack_from(">I", data, 0)[0]
    if fat in (FAT_MAGIC, FAT_MAGIC_64):
        n = struct.unpack_from(">I", data, 4)[0]
        entry_size = 20 if fat == FAT_MAGIC else 32
        have = []
        for i in range(n):
            if fat == FAT_MAGIC:
                cputype, _sub, off, size, _al = struct.unpack_from(
                    ">5I", data, 8 + i * entry_size)
            else:
                cputype, _sub, off, size = struct.unpack_from(
                    ">2I2Q", data, 8 + i * entry_size)[:4]
            have.append(cputype)
            if cputype == CPU_TYPE_X86_64:
                return data[off:off + size]
        raise MachOError("no x86_64 slice (cputypes %s)"
                         % ", ".join("0x%x" % c for c in have))
    thin = struct.unpack_from("<I", data, 0)[0]
    if thin == MH_MAGIC_64:
        return data
    raise MachOError("unrecognised magic (be 0x%08x le 0x%08x)" % (fat, thin))


def looks_like_macho(data):
    if len(data) < 8:
        return False
    if struct.unpack_from(">I", data, 0)[0] in (FAT_MAGIC, FAT_MAGIC_64):
        return True
    return struct.unpack_from("<I", data, 0)[0] == MH_MAGIC_64


# --------------------------------------------------------------------------
# Manifest -> staged file set.  Mirrors mkimage.py's resolution rules
# exactly; if these two ever drift, this tool stops describing the image.
# --------------------------------------------------------------------------

def manifest_staged_files(man, base_dir):
    """Return [(staged_path, source_path_or_None)] for every file entry.

    `base_dir` is tools/bootlab, NOT the manifest's own directory:
    mkimage.py resolves every relative "file"/"asset" against HERE, so a
    manifest living elsewhere still means paths relative to tools/bootlab.
    Diverging here would make this tool describe a different tree than the
    one mkimage.py builds.
    """
    out = []
    for ent in man.get("files", []):
        if "glob" in ent:
            srcdir = os.path.join(base_dir, "assets", ent["asset_prefix"])
            if not os.path.isdir(srcdir):
                raise SystemExit("closure_check: missing asset dir: assets/%s"
                                 % ent["asset_prefix"])
            for name in sorted(os.listdir(srcdir)):
                fp = os.path.join(srcdir, name)
                if os.path.isfile(fp):
                    out.append((os.path.join(ent["glob"], name).lstrip("/"), fp))
        elif "asset" in ent:
            p = os.path.join(base_dir, "assets", ent["asset"])
            if not os.path.isfile(p):
                raise SystemExit("closure_check: missing asset: assets/%s"
                                 % ent["asset"])
            out.append((ent["path"].lstrip("/"), p))
        elif "kernel" in ent:
            # The kernel is staged but is not a dyld-closure participant: it
            # neither imports from nor exports into the userland closure.
            out.append((ent["path"].lstrip("/"), None))
        elif "init" in ent or "init_exec" in ent:
            which = "init_exec" if ent.get("init_exec") else "init"
            out.append((ent["path"].lstrip("/"),
                        os.path.join(base_dir, "work", which)))
        elif "file" in ent:
            p = ent["file"]
            if not os.path.isabs(p):
                p = os.path.join(base_dir, p)
            if not os.path.isfile(p):
                raise SystemExit("closure_check: missing file source: %s" % p)
            out.append((ent["path"].lstrip("/"), p))
        elif "text" in ent:
            out.append((ent["path"].lstrip("/"), None))
        else:
            raise SystemExit("closure_check: manifest entry with no source: %r"
                             % ent)
    return out


# --------------------------------------------------------------------------
# nm -m cross-check
# --------------------------------------------------------------------------

NM_DEF_RE = re.compile(
    r"^[0-9a-fA-F]+\s+\([^)]*\)\s+(weak\s+)?external\s+(\S+)\s*$")
NM_INDR_RE = re.compile(
    r"^\s+\(indirect\)\s+(weak\s+)?external\s+(\S+)")
NM_UNDEF_RE = re.compile(
    r"^\s+\(undefined\)\s+(weak\s+)?external\s+(\S+)")

def nm_m_symbols(path):
    """(defined_globals, undefined_names) per `nm -m`."""
    try:
        out = subprocess.run(["nm", "-m", "-arch", "x86_64", path],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as exc:
        return None, None, str(exc)
    if out.returncode != 0 and not out.stdout:
        return None, None, out.stderr.decode("utf-8", "replace").strip()
    defined = set()
    undef = set()
    for line in out.stdout.decode("utf-8", "replace").splitlines():
        m = NM_UNDEF_RE.match(line)
        if m:
            undef.add(m.group(2))
            continue
        m = NM_INDR_RE.match(line)
        if m:
            # "(indirect) external _memcpy (for __platform_memmove)" -- an
            # N_INDR alias.  nm counts it as an external symbol, so the
            # comparison must too.
            defined.add(m.group(2))
            continue
        m = NM_DEF_RE.match(line)
        if m:
            defined.add(m.group(2))
    return defined, undef, None


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def rule(title):
    print("")
    print(title)
    print("-" * len(title))


def main():
    ap = argparse.ArgumentParser(
        description="Offline dyld-closure and Mach-O validity check.")
    ap.add_argument("manifest", nargs="?",
                    default=os.path.join(HERE, "manifest_dynamic.json"),
                    help="manifest JSON (default: manifest_dynamic.json)")
    ap.add_argument("--image",
                    help="analyse the bytes inside this built FAT32 image "
                         "instead of the host files the manifest names")
    ap.add_argument("--nm-check", type=int, default=3, metavar="N",
                    help="cross-check N files against `nm -m` (default 3, "
                         "0 disables)")
    args = ap.parse_args()

    manifest = args.manifest
    if not os.path.isabs(manifest):
        manifest = os.path.join(HERE, manifest)
    with open(manifest) as fh:
        man = json.load(fh)

    img = None
    if args.image:
        sys.path.insert(0, HERE)
        from fat32img import Fat32Img
        img = Fat32Img(args.image)

    # Manifest-relative paths resolve against tools/bootlab, exactly as
    # mkimage.py resolves them, not against the manifest's own directory.
    staged = manifest_staged_files(man, HERE)

    # ---- parse every staged Mach-O ---------------------------------------
    nodes = {}          # staged_path -> MachO
    skipped = []        # (path, reason)
    errors = []         # (path, reason)
    for spath, src in staged:
        try:
            if img is not None:
                data = img.read_path("/" + spath)
                if data is None:
                    errors.append((spath, "not present in image"))
                    continue
            else:
                if src is None:
                    skipped.append((spath, "manifest supplies no file bytes"))
                    continue
                if not os.path.isfile(src):
                    errors.append((spath, "missing source %s" % src))
                    continue
                with open(src, "rb") as fh:
                    data = fh.read()
        except Exception as exc:                     # noqa: BLE001
            errors.append((spath, "read failed: %s" % exc))
            continue
        if not looks_like_macho(data):
            skipped.append((spath, "not a Mach-O"))
            continue
        try:
            slice_ = select_x86_64(data, spath)
            nodes[spath] = MachO(slice_)
        except MachOError as exc:
            errors.append((spath, str(exc)))

    if img is not None:
        img.close()

    print("closure_check: %s" % manifest)
    if args.image:
        print("image: %s" % args.image)
    print("staged entries: %d   Mach-O x86_64 nodes: %d   non-Mach-O: %d"
          % (len(staged), len(nodes), len(skipped)))

    if errors:
        rule("UNPARSEABLE / MISSING")
        for p, why in sorted(errors):
            print("  %-60s %s" % (p, why))

    # ---- dependency closure ----------------------------------------------
    # A dependency is resolved by basename: dyld records an install name, and
    # the bootlab tree puts each dylib at exactly one path, so the basename is
    # the identity that survives.
    by_basename = {}
    for spath in nodes:
        by_basename.setdefault(os.path.basename(spath), []).append(spath)

    roots = [p for p in nodes if nodes[p].filetype in (MH_EXECUTE, MH_DYLIB)]
    closure = set()
    missing_deps = []       # (from_path, install_name)
    edge_count = 0
    stack = sorted(roots)
    while stack:
        cur = stack.pop()
        if cur in closure:
            continue
        closure.add(cur)
        for cmd, name in nodes[cur].deps:
            if name is None:
                continue
            edge_count += 1
            base = os.path.basename(name)
            hits = by_basename.get(base, [])
            if not hits:
                missing_deps.append((cur, name, DEP_CMD_NAMES[cmd]))
                continue
            for h in hits:
                if h not in closure:
                    stack.append(h)

    # ---- dyld2 validation -------------------------------------------------
    dylibs = sorted(p for p in nodes if nodes[p].filetype == MH_DYLIB)
    rejects = []
    passes = []
    for p in dylibs:
        ok, trace = nodes[p].dyld2_validation()
        (passes if ok else rejects).append((p, trace))

    # ---- symbol resolution ------------------------------------------------
    universe = {}        # symbol -> providing staged path
    dangling_aliases = []  # (path, alias, target)
    for p in sorted(closure):
        for name in nodes[p].defined_globals():
            universe.setdefault(name, p)
    # N_INDR aliases are published only if their target is published.  Adding
    # them before targets resolve would let a dylib vouch for a symbol the
    # closure cannot actually produce.
    for p in sorted(closure):
        for alias, target in sorted(nodes[p].indirect_alias_globals().items()):
            if target is not None and target in universe:
                universe.setdefault(alias, p)
            else:
                dangling_aliases.append((p, alias, target))

    unresolved = []      # (path, [non-weak names])
    weak_unresolved = []  # (path, [weak names])
    for p in sorted(closure):
        nonweak, weak = [], []
        for name, is_weak in sorted(nodes[p].undefineds().items()):
            if name in universe:
                continue
            (weak if is_weak else nonweak).append(name)
        if nonweak:
            unresolved.append((p, nonweak))
        if weak:
            weak_unresolved.append((p, weak))

    distinct_unresolved = sorted({n for _, ns in unresolved for n in ns})
    distinct_weak = sorted({n for _, ns in weak_unresolved for n in ns})

    # ---- report -----------------------------------------------------------

    rule("CLOSURE")
    print("  nodes in closure:          %d" % len(closure))
    print("  dependency edges followed: %d" % edge_count)
    print("  export universe size:      %d symbols" % len(universe))
    print("  unstaged dependencies:     %d" % len(missing_deps))
    for frm, name, cmd in sorted(missing_deps):
        print("    %-58s %s %s" % (frm, cmd, name))
    print("  dangling N_INDR aliases:    %d" % len(dangling_aliases))
    for p, alias, target in sorted(dangling_aliases):
        print("    %-58s %s -> %s" % (p, alias, target if target else "?"))

    rule("dyld2 ImageLoaderMachO.cpp LINKEDIT VALIDATION (%d staged dylibs)"
         % len(dylibs))
    print("  PASS: %d    REJECT: %d" % (len(passes), len(rejects)))
    for p, trace in rejects:
        mo = nodes[p]
        print("")
        print("  REJECT  %s" % p)
        print("          __LINKEDIT fileoff=%d filesize=%d  exports_trie=%s"
              % (mo.linkedit[0], mo.linkedit[1],
                 mo.exports_trie if mo.exports_trie else "absent"))
        for line, verdict, text in trace:
            if verdict == "info":
                print("            line %-4d %s" % (line, text))
            else:
                print("            line %-4d %-6s %s" % (line, verdict, text))
    if not rejects:
        print("  (every staged dylib passes)")

    rule("UNRESOLVED NON-WEAK UNDEFINED SYMBOLS")
    print("  files affected: %d    distinct symbols: %d"
          % (len(unresolved), len(distinct_unresolved)))
    for p, names in unresolved:
        print("")
        print("  %s" % p)
        for n in names:
            print("      %s" % n)

    rule("UNRESOLVED WEAK UNDEFINED SYMBOLS (not a boot blocker)")
    print("  files affected: %d    distinct symbols: %d"
          % (len(weak_unresolved), len(distinct_weak)))
    for p, names in weak_unresolved:
        print("  %-58s %d" % (p, len(names)))

    # LC_DYSYMTAB's declared undefined range must cover every N_UNDF
    # external the symbol table holds.  When it does not, dyld2 iterates the
    # declared range for its bind pass and silently leaves the rest unbound,
    # so an under-declared range is a defect in its own right -- and it is
    # also why this tool scans the whole LC_SYMTAB rather than trusting it.
    rule("LC_DYSYMTAB UNDEFINED-RANGE CONSISTENCY")
    mismatched = []
    for p in sorted(closure):
        declared, actual = nodes[p].dysymtab_undef_range()
        if declared is not None and declared != actual:
            mismatched.append((p, declared, actual))
    print("  nodes whose LC_DYSYMTAB nundefsym != N_UNDF externals: %d"
          % len(mismatched))
    for p, declared, actual in mismatched:
        print("    %-58s nundefsym=%d actual=%d"
              % (p, declared, actual))

    # ---- nm -m cross-check ------------------------------------------------
    nm_report = []
    if args.nm_check > 0 and nodes:
        candidates = [p for p in dylibs]
        for extra in ("usr/lib/dyld",):
            if extra in nodes:
                candidates.append(extra)
        rule("nm -m CROSS-CHECK")
        picked = candidates[:args.nm_check]
        host_of = {sp: sr for sp, sr in staged}
        for p in picked:
            host = host_of.get(p)
            if not host or not os.path.isfile(host):
                continue
            nm_def, nm_undef, err = nm_m_symbols(host)
            if nm_def is None:
                nm_report.append((p, "SKIP", err or "nm failed"))
                print("  SKIP  %s: %s" % (p, err))
                continue
            # nm -m's "external" defined set is N_SECT externals, N_ABS
            # externals ("(absolute) external") and N_INDR aliases
            # ("(indirect) external"), so the comparison unions all three.
            mine_def = (set(nodes[p].defined_globals())
                        | set(nodes[p].absolute_globals())
                        | set(nodes[p].indirect_alias_globals()))
            mine_undef = set(nodes[p].undefineds())
            d_miss = nm_def - mine_def
            d_extra = mine_def - nm_def
            u_miss = nm_undef - mine_undef
            u_extra = mine_undef - nm_undef
            agree = not (d_miss or d_extra or u_miss or u_extra)
            nm_report.append((p, "AGREE" if agree else "DISAGREE", None))
            print("  %-58s %s" % (p, "AGREE" if agree else "DISAGREE"))
            print("      defined:   nm=%d mine=%d" % (len(nm_def), len(mine_def)))
            print("      undefined: nm=%d mine=%d" % (len(nm_undef), len(mine_undef)))
            for label, s in (("only in nm", d_miss), ("only in mine", d_extra)):
                if s:
                    print("      %s: %s" % (label, ", ".join(sorted(s)[:8])))
            for label, s in (("only in nm", u_miss), ("only in mine", u_extra)):
                if s:
                    print("      undefined %s: %s"
                          % (label, ", ".join(sorted(s)[:8])))

    # ---- verdict ----------------------------------------------------------
    ok = (not errors and not missing_deps and not unresolved and not rejects)
    rule("VERDICT")
    if errors:
        print("  FAIL  %d staged file(s) could not be parsed" % len(errors))
    if missing_deps:
        print("  FAIL  %d dependency/dependencies are not staged"
              % len(missing_deps))
    if unresolved:
        print("  FAIL  %d distinct non-weak undefined symbol(s) unresolved"
              % len(distinct_unresolved))
    if rejects:
        print("  FAIL  %d staged dylib(s) rejected by dyld2 validation"
              % len(rejects))
    dis = [p for p, v, _ in nm_report if v == "DISAGREE"]
    if dis:
        print("  WARN  nm -m disagreement on %d file(s)" % len(dis))
    if ok:
        print("  PASS  closure complete, all non-weak undefineds resolve, "
              "all staged dylibs valid")
    print("")
    print("closure_check: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())