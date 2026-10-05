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

The checks are, in verdict order: parse, staged dependencies, non-weak
undefined symbols, dyld2 LINKEDIT validation, provider reachability through
LC_LOAD_DYLIB, and initializers-without-libSystem.  The last two cover
defects that no amount of symbol resolution can see.
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

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

# Section flags.  S_MOD_INIT_FUNC_POINTERS / S_INIT_FUNC_OFFSETS are the two
# section types dyld's ImageLoaderMachO.cpp scans to decide fHasInitializers
# (src/ImageLoaderMachO.cpp:775-780) and then walks in doModInitFunctions
# (:2306-2380).  A section of either type is exactly what makes dyld throw
# "initializer in image (...) that does not link with libSystem.dylib".
SECTION_TYPE = 0x000000FF
S_MOD_INIT_FUNC_POINTERS = 0x9
S_INIT_FUNC_OFFSETS = 0x16

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
        self.sections = []          # (segname, sectname, size, flags)
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
            # nsects is the uint32 at +64; section_64 is 80 bytes and starts
            # at +72.  Only size (offset +40) and flags (offset +64) are
            # needed here: a S_MOD_INIT_FUNC_POINTERS / S_INIT_FUNC_OFFSETS
            # section of nonzero size is what makes dyld call initializers.
            nsects = struct.unpack_from("<I", d, off + 64)[0]
            for i in range(nsects):
                soff = off + 72 + 80 * i
                if soff + 80 > cmdsize + off:
                    raise MachOError("LC_SEGMENT_64 section runs past the "
                                     "load command")
                sectname = cstr(d, soff)
                ssegname = cstr(d, soff + 16)
                size, sflags = struct.unpack_from("<Q", d, soff + 40)[0], \
                    struct.unpack_from("<I", d, soff + 64)[0]
                self.sections.append((ssegname, sectname, size, sflags))
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

    def initializer_sections(self):
        """[(segname, sectname, size)] of the initializer pointer tables.

        dyld sets fHasInitializers when any section's low byte of flags is
        S_MOD_INIT_FUNC_POINTERS or S_INIT_FUNC_OFFSETS
        (ImageLoaderMachO.cpp:775-780) and then walks exactly those sections
        in doModInitFunctions.  A zero-size one holds no initializer, so it
        cannot trigger anything and is not reported.
        """
        out = []
        for segname, sectname, size, flags in self.sections:
            if (flags & SECTION_TYPE) in (S_MOD_INIT_FUNC_POINTERS,
                                          S_INIT_FUNC_OFFSETS) and size:
                out.append((segname, sectname, size))
        return out

    def has_initializers(self):
        return bool(self.initializer_sections())

    def libsystem_linked(self):
        """True if libSystem appears in this image's LC_LOAD_DYLIB set.

        ravynOS stages the re-exporting dylib as /usr/lib/libSystem.B.dylib,
        Apple ships /usr/lib/system/libSystem.dylib, and both are named only
        by their install name in LC_LOAD_DYLIB, so the identity that has to
        match is the basename containing "libSystem".  Every dependency-
        bearing command counts, not just LC_LOAD_DYLIB: dyld puts all of them
        in the same dependency list it searches for libSystem helpers.
        """
        for _cmd, name in self.deps:
            if name is None:
                continue
            if "libSystem" in os.path.basename(name):
                return True
        return False

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
# Derived intermediates: staged build products that are COPIES of something
# built elsewhere.  mkimage hashes what the manifest points at and the image
# then hashes clean, so a stale copy is invisible to every byte-level check
# this tool makes -- the disk is internally consistent and wrong.  Measured:
# work/WindowServer.app.tar.gz was built at 14:52 while the WindowServer
# binaries it was packed from were rebuilt at 17:19, so the image shipped the
# old WindowServer: `otool -L` showed liblaunch.dylib (linked, never used),
# and __vprocmgr_switch_to_session was absent.  The build output was right in
# the build tree the whole time.
#
# Each entry maps the intermediate, relative to tools/bootlab, to the build
# output it represents and how to find that output.  A staged source under
# work/ that is NOT listed here is reported as UNKNOWN, never passed
# silently: an unmappable intermediate is exactly the case where the tool
# cannot promise the image is current.
# --------------------------------------------------------------------------

DERIVED_INTERMEDIATES = (
    # (intermediate rel path, upstream path or None, why)
    # The intermediate root is the directory the tarball was EXTRACTED INTO,
    # so the upstream root is the directory the tarball was PACKED from --
    # one level up from the .app, which is what makes
    # work/ws_bundle/WindowServer.app/Contents/... line up with
    # <build>/.../WindowServer/WindowServer.app/Contents/...
    ("work/ws_bundle",
     "/Users/max/Projects/build/Users/max/Projects/ravynos/CoreServices"
     "/WindowServer",
     "extracted from work/WindowServer.app.tar.gz, packed from the build tree"),
    ("work/Dock.app",
     "/Users/max/Projects/build/Users/max/Projects/ravynos/CoreServices"
     "/Dock/Dock.app",
     "copied out of the build tree by make_gui_manifest.py"),
    ("work/Filer.app",
     "/Users/max/Projects/build/Users/max/Projects/ravynos/CoreServices"
     "/Filer/Filer.app",
     "copied out of the build tree by make_gui_manifest.py"),
    # The WindowServer job plist is a copy of a TRACKED source file, not of a
    # build output.  It was registered as AUTHORED-AND-DIVERGENT while the
    # staged copy hand-diverged from the tracked original; that divergence was
    # a provenance defect (an untracked edit in gitignored work/) and was
    # resolved upstream in 795ef92e46, which landed the console paths in the
    # tracked file.  It is a content-equality copy now, and the comparison is
    # real enforcement: it is exactly what catches the hand-edit drifting away
    # again, which is how this file went stale in the first place.
    ("work/com.ravynos.WindowServer.json",
     os.path.join(os.path.abspath(os.path.join(HERE, os.pardir, os.pardir)),
                  "SystemLibrary", "LaunchDaemons",
                  "com.ravynos.WindowServer.json"),
     "copy of the tracked source plist; re-derived from it after 795ef92e46"),
    # The stripped kernel is NOT registered here.  It used to be, against
    # <build>/kernel.development, compared by mtime only -- a weak rule that
    # passed for the wrong reason: that build-tree file is dated 08-31 while
    # the staged kernel is dated 10-04, so the comparison was measuring an
    # unrelated artifact.  Its real input is work/new_kernel.development and
    # its recipe is recoverable, so it is checked by REPRODUCING the strip
    # instead (see RECIPE_CHECKS).
)


# --------------------------------------------------------------------------
# Source-built staged products: work/ files that are NOT copies of another
# build output but the build output itself, compiled from sources in this
# repository.  There is no upstream artifact to compare bytes against -- the
# artifact IS the product -- so the freshness question is different: is the
# product at least as new as every source it was compiled from?
#
# Each entry is (work/ path, producer script, source paths).  The producer
# and the source list are both taken from the script that emits the file, not
# guessed:
#
#   work/<u>_dyn   build_dynutils.sh: srcs_for() (the SRCS table it says it
#                  took from BSD/bin/<u>/Makefile), build_one(): compiles
#                  each with $CC and links -o "$HERE/work/${u}_dyn".
#   work/launchd   build_launchd.sh: OUT="$HERE/work/launchd", SRCS_HAND +
#                  SRCS_MIG ("verbatim from BSD/sbin/launchd/Makefile").
#   work/efi/      build_applefree.sh: -c tools/efiloader/src/loader.c then
#     BOOTX64.EFI  pack.py -> work/efi/BOOTX64.EFI.
#
# `sh` also compiles GENERATED sources (nodes.c/syntax.c come from
# mksyntax.c/mknodes.c + nodetypes, token.h from the mktokens script) which
# are not committed; build_dynutils.sh:119-140 documents that, so the
# generators are listed as the sources instead of the generated files.
# --------------------------------------------------------------------------

_DYNUTILS_SRCS = {
    "sh": "bltin/echo.c alias.c arith_yacc.c arith_yylex.c cd.c error.c eval.c"
          " exec.c expand.c histedit.c input.c jobs.c mail.c main.c"
          " memalloc.c miscbltin.c mystring.c options.c output.c parser.c"
          " redir.c show.c trap.c var.c builtins.c shims.c"
          # generated, not committed: see build_dynutils.sh:119-140
          " mksyntax.c mknodes.c nodetypes nodes.c.pat mktokens",
    "ls": "cmp.c ls.c print.c util.c",
    "cp": "cp.c utils.c",
    "echo": "echo.c",
    "cat": "cat.c",
    "mkdir": "mkdir.c",
    "rm": "rm.c",
    "test": "test.c",
    "mv": "mv.c",
    "launchctl": "launchctl.c",
}


def source_built_products():
    """[(work_rel_path, producer, [source paths])] recovered from scripts."""
    repo = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
    out = []
    for util, srcs in sorted(_DYNUTILS_SRCS.items()):
        paths = [os.path.join(repo, "BSD", "bin", util, s)
                 for s in srcs.split()]
        # NOTE on `test`: build_dynutils.sh:80-84 records that test.c is
        # self-contained and must NOT compile the shell's error.c in, so
        # only BSD/bin/test/test.c is listed here.  Listing error.c would
        # make a shell edit look like a reason to rebuild test.
        out.append(("work/%s_dyn" % util, "build_dynutils.sh", paths))
    lsrcs = ("launchd.c core.c kill2.c ktrace.c ipc.c log.c runtime.c"
             " init/init.c")
    out.append(("work/launchd", "build_launchd.sh",
                [os.path.join(repo, "BSD", "sbin", "launchd", s)
                 for s in lsrcs.split()]))
    out.append(("work/efi/BOOTX64.EFI", "build_applefree.sh",
                [os.path.join(repo, "tools", "efiloader", "src", "loader.c")]))
    return out


# --------------------------------------------------------------------------
# Reproducible recipes: staged products whose exact transform is recoverable
# from the producing script, so freshness can be decided by CONTENT rather
# than by mtime.
#
# The stripped kernel is the case.  kernel_build.py:338-339 does
#
#     stripped = os.path.join(WORK, "stripped_kernel.development")
#     run(["strip", "-x", "-o", stripped, out_kernel], WORK)
#
# with out_kernel = work/new_kernel.development (kernel_build.py:315).  Both
# that file and the strip tool are on this machine, so the recipe can simply
# be re-run and the result compared byte for byte.  That is strictly stronger
# than the mtime comparison it replaces, which compared the staged kernel
# against <build>/kernel.development -- a file dated 08-31, months older and
# from a different link, so the "pass" said nothing about this kernel at all.
#
# If the recipe cannot be reproduced (no strip, input missing, tool failure)
# the result is UNKNOWN, never a pass.
# --------------------------------------------------------------------------

RECIPE_CHECKS = (
    # (work rel path, argv builder, why)
    ("work/stripped_kernel.development", "strip_kernel", None),
)


def strip_kernel(staged_path, tmpdir):
    """Re-run `strip -x` over the linked kernel; return the reproduced bytes.

    Returns (path_to_reproduced_file, recipe_text) or raises, in which case
    the caller records UNKNOWN rather than passing.
    """
    linked = os.path.join(HERE, "work", "new_kernel.development")
    if not os.path.isfile(linked):
        raise RuntimeError("strip input missing: %s" % linked)
    out = os.path.join(tmpdir, "repro_stripped_kernel.development")
    subprocess.run(["strip", "-x", "-o", out, linked], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return out, "strip -x work/new_kernel.development"


# --------------------------------------------------------------------------
# Candidate sources: committed files that plausibly produce a staged work/
# intermediate, for which NO mapping is claimed because the staged bytes were
# measured NOT to match.  Listing one here is a statement of evidence, not a
# registration: the report names the candidate and says whether the bytes
# agree, so a human can decide.  Registering a mapping whose content does not
# match would manufacture a staleness failure out of a deliberate edit --
# worse than admitting the tool does not know.
#
# work/com.ravynos.WindowServer.json was this table's only entry, while its
# staged copy hand-diverged from the tracked original.  That divergence was
# never a deliberate variant: it was an untracked edit living in gitignored
# work/ with no commit behind it, on the one file that decides whether
# WindowServer output is visible at all.  Commit 795ef92e46 landed the console
# paths in the tracked original and the staged copy was re-derived from it, so
# the file is a content-equal copy now and is registered in
# DERIVED_INTERMEDIATES instead -- where the comparison actually enforces that
# the two do not drift apart again, which is how it went stale in the first
# place.  The table is retained empty: the pattern is the right one for the
# next file whose bytes genuinely do not match, and dropping the mechanism
# along with its only member is a larger change than this fix calls for.
# --------------------------------------------------------------------------

CANDIDATE_SOURCES = {}


def derived_intermediate(rel_path):
    """(upstream_path, why) if `rel_path` is a known derived intermediate.

    Returns (None, None) for anything else, including a path under a listed
    intermediate's directory that does not exist on disk.
    """
    rel = rel_path.replace(os.sep, "/")
    for prefix, upstream, why in DERIVED_INTERMEDIATES:
        if rel == prefix or rel.startswith(prefix + "/"):
            return upstream, why
    return None, None


def newest_mtime(root):
    """Newest mtime under `root`, or (None, None) -> (mtime, path).

    A bundle's freshness is the freshness of its most recently written
    member: a single rebuilt executable inside an otherwise untouched bundle
    is what ships stale, so the max is the number that has to be compared.
    """
    best_t, best_p = None, None
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            p = os.path.join(dirpath, name)
            try:
                t = os.path.getmtime(p)
            except OSError:
                continue
            if best_t is None or t > best_t:
                best_t, best_p = t, p
    return best_t, best_p


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
    ap.add_argument("--provenance-check", dest="provenance_check",
                    action="store_true", default=True,
                    help="also run provenance_scan over the staged sources "
                         "and report whether any came from the host's dyld "
                         "shared cache (default: on)")
    ap.add_argument("--no-provenance-check", dest="provenance_check",
                    action="store_false",
                    help="skip the provenance verdict entirely (the ~6 GB "
                         "host-cache scan)")
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
    # Bytes read back OUT of the image, keyed by staged path.  Kept because
    # the provenance verdict below must be made about these bytes, not about
    # the files the manifest points at: only the former is evidence about the
    # disk a machine will boot.  Populated only in --image mode.
    readback = {}       # staged_path -> bytes
    for spath, src in staged:
        try:
            if img is not None:
                data = img.read_path("/" + spath)
                if data is None:
                    errors.append((spath, "not present in image"))
                    continue
                readback[spath] = data
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

    # ---- LC_LOAD_DYLIB reachability check -------------------------------
    # A symbol is only resolvable at runtime if its provider is reachable
    # via the consumer's LC_LOAD_DYLIB list (transitively). A staged-but-
    # unlinked provider kills the boot at dyld bind time — the _OBJC_CLASS_$_CALayer
    # and _OBJC_CLASS_$_NSEntityDescription class of defect.
    sym_providers = {}
    for p, node in nodes.items():
        try:
            for sym in node.defined_globals():
                sym_providers.setdefault(sym, set()).add(p)
        except Exception:
            pass

    # Map install names to staged paths for dep resolution
    name_to_path = {}
    for p in nodes:
        base = p.split('/')[-1]
        name_to_path[base] = p
        name_to_path[p] = p

    def transitive_deps(start):
        seen = set()
        stack = [start]
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            if cur in nodes:
                for cmd, iname in nodes[cur].deps:
                    # Resolve dep install name to a staged path
                    base = iname.split('/')[-1]
                    if base in name_to_path:
                        stack.append(name_to_path[base])
                    elif iname in name_to_path:
                        stack.append(name_to_path[iname])
        return seen

    unreachable = []
    for p, names in unresolved:
        if p not in nodes:
            continue
        closure = transitive_deps(p)
        for sym in names:
            if sym in sym_providers:
                providers = sym_providers[sym]
                if not any(prov in closure for prov in providers):
                    unreachable.append((p, sym, sorted(providers)))

    if unreachable:
        rule("UNREACHABLE PROVIDERS (provider NOT in consumer's LC_LOAD_DYLIB)")
        print("  cases: %d" % len(unreachable))
        for consumer, sym, providers in unreachable[:20]:
            print("    %s" % consumer)
            print("      %s  (provider: %s)" % (sym, providers))
        if len(unreachable) > 20:
            print("    ... and %d more" % (len(unreachable) - 20))

    # ---- libSystem link check --------------------------------------------
    # dyld refuses to run any initializer before libSystem's own initializers
    # have run: walking a S_MOD_INIT_FUNC_POINTERS / S_INIT_FUNC_OFFSETS
    # section while gProcessInfo->libSystemInitialized is false throws
    #   dyld: initializer in image (<path>) that does not link with
    #         libSystem.dylib
    # unless that image's install name IS libSystem
    # (ImageLoaderMachO.cpp:2302-2327 and :2343-2362).  Every symbol in such
    # an image can resolve perfectly and the process still dies, so symbol
    # resolution cannot see this defect at all -- CoreFoundation tripped it
    # with a fully resolvable closure.  What is checked is the one property
    # dyld itself looks at: does the image name libSystem among its
    # dependency-bearing load commands?
    #
    # Initializer presence is read out of the image, not assumed: sections are
    # parsed above, so "has initializers" means a real nonzero-size
    # S_MOD_INIT_FUNC_POINTERS / S_INIT_FUNC_OFFSETS table, which is the same
    # predicate that sets fHasInitializers in dyld.  If a node cannot answer
    # the question the section table is not proof for that node, so it is
    # reported in `init_unknown` and counted as a FAIL rather than skipped.
    init_unknown = []
    no_libsystem = []
    with_inits = []
    for p in sorted(nodes):
        node = nodes[p]
        try:
            inits = node.initializer_sections()
        except Exception as exc:                          # noqa: BLE001
            init_unknown.append((p, "initializer scan failed: %s" % exc))
            continue
        if not inits:
            continue
        with_inits.append(p)
        # Two images are exempt, and both for the same reason: they are not
        # run through ImageLoaderMachO::doModInitFunctions at all.
        #   - libSystem itself: dyld's own code allows exactly one image to
        #     run initializers first, and it is libSystem.
        #   - dyld (MH_DYLINKER): loaded by the kernel, not by dyld, so its
        #     initializer walk never sees the libSystemInitialized gate.
        if (node.filetype == MH_DYLINKER
                or "libSystem" in os.path.basename(p)):
            continue
        if not node.libsystem_linked():
            no_libsystem.append((p, inits,
                                 sorted({n for _c, n in node.deps if n})))

    rule("INITIALIZERS WITHOUT libSystem (dyld rejects before running them)")
    print("  staged images with initializers: %d    "
          "initializer presence UNKNOWN:    %d" % (len(with_inits),
                                                   len(init_unknown)))
    print("  of those, NOT linking libSystem: %d" % len(no_libsystem))
    for p, inits, deps in no_libsystem[:20]:
        print("    %s" % p)
        print("      initializer sections: %s"
              % ", ".join("%s,%s (%d bytes)" % (s, n, sz) for s, n, sz in inits))
        print("      LC_LOAD_DYLIB: %s" % (", ".join(deps) or "(none)"))
    if len(no_libsystem) > 20:
        print("    ... and %d more" % (len(no_libsystem) - 20))
    for p, why in init_unknown[:20]:
        print("    !! %s: %s" % (p, why))
    if len(init_unknown) > 20:
        print("    ... and %d more" % (len(init_unknown) - 20))
    if not no_libsystem and not init_unknown:
        print("  (every staged image with initializers links libSystem)")

    # ---- derived-intermediate staleness --------------------------------
    # A manifest entry may name a COPY of a build product rather than the
    # build product itself.  mkimage hashes what the manifest names and the
    # finished image then hashes clean, so a stale copy passes every
    # byte-level check above: the disk is internally consistent and wrong.
    # Measured: work/WindowServer.app.tar.gz was packed at 14:52 from binaries
    # rebuilt at 17:19, and the image shipped the 14:52 WindowServer -- with
    # liblaunch.dylib in its LC_LOAD_DYLIB and no __vprocmgr_switch_to_session
    # import, i.e. linked but never called, which no structural check can
    # distinguish.  The freshness question is therefore asked here, against
    # the build output each intermediate stands for.
    #
    # What counts as stale, per kind of intermediate:
    #
    #   directory intermediate (an extracted or copied bundle tree).  Each
    #   staged file is compared against the file at the SAME relative path
    #   in the build tree, by CONTENT.  A content difference is the finding:
    #   the image carries bytes the build no longer produces.  An mtime
    #   difference alone is not -- `cp -p` and `tar` do not round mtimes,
    #   and a resource that was never rebuilt is not stale merely because a
    #   sibling executable was.  Comparing every file against the newest
    #   file in the tree would report all 90 of them; that is noise, and
    #   noise is how a gate gets ignored.
    #
    #   single-file intermediate (work/stripped_kernel.development is a
    #   stripped copy, so its bytes never match the build's).  Content can
    #   never match, so mtime is the only available signal and is used
    #   directly, with MTIME_SLOP for the same-second case.
    #
    # A relative path with no counterpart in the build tree is UNKNOWN, not
    # a finding: the build may legitimately not produce it.
    MTIME_SLOP = 2.0
    stale = []                # copies that differ from their build output
    fresh = []
    source_stale = []         # source-built products older than a source
    source_fresh = []
    stale_unknown = []
    recipe_stale = []          # reproduced transform does NOT match
    recipe_fresh = []
    source_recipes = {rel: (producer, srcs)
                      for rel, producer, srcs in source_built_products()}
    recipe_checks = {rel: (globals()[builder], why)
                     for rel, builder, why in RECIPE_CHECKS}
    # The kernel is a staged Mach-O that manifest_staged_files maps to NO
    # source (it is not a dyld-closure participant), so it never reaches the
    # loop below.  Resolve it the way mkimage.py's newest_kernel() and
    # provenance_scan.kernel_payload() do, so the strip recipe is actually
    # exercised instead of silently counting zero.
    kernel_rel = None
    try:
        sys.path.insert(0, HERE)
        import provenance_scan
        kernel_src = provenance_scan.kernel_payload(HERE)
    except Exception as exc:                              # noqa: BLE001
        stale_unknown.append(("System/Library/Kernels/kernel.development",
                              "work/stripped_kernel.development",
                              "kernel payload could not be resolved for the "
                             "strip recipe: %s" % exc))
        kernel_src = None
    if kernel_src is not None:
        kernel_rel = os.path.relpath(kernel_src, HERE)
        if kernel_rel in recipe_checks:
            recipe_staged = [
                (sp, kernel_src)
                for sp, _src in staged
                if "kernel.development" in os.path.basename(sp)]
    else:
        recipe_staged = []
    # Recipes are re-run into a scratch directory, never over the staged file.
    reprodir = tempfile.mkdtemp(prefix="closure_check_repro_")


    def content_differs(a, b):
        try:
            if os.path.getsize(a) != os.path.getsize(b):
                return True
            with open(a, "rb") as fa, open(b, "rb") as fb:
                while True:
                    ca, cb = fa.read(1 << 20), fb.read(1 << 20)
                    if ca != cb:
                        return True
                    if not ca:
                        return False
        except OSError:
            return False

    try:
        for spath, src in staged:
            if src is None or not os.path.isfile(src):
                continue
            rel = os.path.relpath(src, HERE)
            if not (rel == "work" or rel.startswith("work" + os.sep)):
                continue

            # A reproducible recipe is the strongest check available and is
            # tried first: the transform is re-run and the result compared
            # byte for byte, so "is this staged artifact the build the tree
            # currently describes?" is answered by CONTENT, not timestamps.
            check = recipe_checks.get(rel)
            if check is not None:
                builder, _why = check
                try:
                    reproduced, recipe_text = builder(src, reprodir)
                except Exception as exc:                  # noqa: BLE001
                    stale_unknown.append((spath, rel,
                                          "recipe could not be reproduced: %s"
                                          % exc))
                    continue
                if content_differs(src, reproduced):
                    recipe_stale.append((spath, rel, recipe_text, reproduced))
                else:
                    recipe_fresh.append((spath, rel, recipe_text))
                continue

            # A source-built product has no upstream artifact to diff
            # against: the artifact IS the output.  Its freshness is instead
            # the question of whether every source it was compiled from is
            # older than it.  Registered from the producing script's own
            # SRCS table (see source_built_products), never guessed.
            recipe = source_recipes.get(rel)
            if recipe is not None:
                producer, srcs = recipe
                missing = [s for s in srcs if not os.path.isfile(s)]
                if missing:
                    stale_unknown.append((spath, rel,
                                          "%s: source(s) missing from the tree:"
                                          " %s" % (producer, missing[0])))
                    continue
                newest_src = max(srcs, key=os.path.getmtime)
                delta = os.path.getmtime(src) - os.path.getmtime(newest_src)
                rec = (spath, rel, producer, delta, newest_src)
                (source_stale if delta < -MTIME_SLOP
                 else source_fresh).append(rec)
                continue

            upstream, why = derived_intermediate(rel)
            if upstream is None:
                # Not a known copy and not a registered build product.  It
                # may still be the product of a script this tool does not
                # know, so this is UNKNOWN rather than a finding -- but it is
                # reported, because an unmappable intermediate is exactly
                # where this check cannot promise the image is current, and a
                # green verdict must not imply that it can.
                note = "no upstream build output registered for this "
                note += "intermediate"
                # If a committed source plausibly produces this file, say so
                # AND say whether the staged bytes match it.  That is not a
                # mapping -- it is the evidence a human needs to decide
                # whether one should be registered.
                cand = CANDIDATE_SOURCES.get(rel)
                if cand:
                    cand_path = os.path.join(
                        os.path.abspath(os.path.join(HERE, os.pardir, os.pardir)),
                        cand)
                    if not os.path.isfile(cand_path):
                        note += "; candidate source absent: %s" % cand
                    elif content_differs(src, cand_path):
                        note += ("; candidate source %s EXISTS but the staged"
                                 " bytes DIFFER from it -- this staged file is"
                                 " a hand-edited variant, not what the"
                                 " committed source produces, so no mapping can"
                                 " be claimed" % cand)
                    else:
                        note += ("; candidate source %s matches byte for byte"
                                 " (safe to register)" % cand)
                stale_unknown.append((spath, rel, note))
                continue
            if os.path.isdir(upstream):
                prefix = next(p for p, _u, _w in DERIVED_INTERMEDIATES
                              if rel == p or rel.startswith(p + os.sep))
                counterpart = os.path.join(
                    upstream, os.path.relpath(rel, prefix))
                if not os.path.isfile(counterpart):
                    stale_unknown.append((spath, rel,
                                          "no counterpart at %s in the build"
                                          " tree" % counterpart))
                    continue
                if content_differs(src, counterpart):
                    stale.append((spath, rel, counterpart,
                                  os.path.getmtime(counterpart)
                                  - os.path.getmtime(src)))
                else:
                    fresh.append((spath, rel))
            else:
                if not os.path.isfile(upstream):
                    stale_unknown.append((spath, rel,
                                          "upstream build output missing: %s"
                                          % upstream))
                    continue
                # Content, not mtime.  The rule printed above says a staged
                # copy "must carry the same bytes as the build output it was
                # copied from", and for a single-file upstream the mtime
                # comparison cannot honour that: a hand-edited copy that was
                # touched LAST is newer than its source and would pass.  That
                # is precisely how work/com.ravynos.WindowServer.json went
                # stale unnoticed.  mtime is kept only as the reported age.
                delta = os.path.getmtime(upstream) - os.path.getmtime(src)
                rec = (spath, rel, upstream, delta)
                (stale if content_differs(src, upstream)
                 else fresh).append(rec)
        # The kernel payload, which carries no source in `staged` and so was
        # never reached above.  Its recipe is re-run here instead.
        if recipe_staged and kernel_rel in recipe_checks:
            builder, _why = recipe_checks[kernel_rel]
            for spath, ksrc in recipe_staged:
                try:
                    reproduced, recipe_text = builder(ksrc, reprodir)
                except Exception as exc:                  # noqa: BLE001
                    stale_unknown.append((spath, kernel_rel,
                                          "recipe could not be reproduced: %s"
                                          % exc))
                    continue
                if content_differs(ksrc, reproduced):
                    recipe_stale.append((spath, kernel_rel, recipe_text,
                                         reproduced))
                else:
                    recipe_fresh.append((spath, kernel_rel, recipe_text))
    finally:
        # Holds re-run recipes; never left behind, and never written over a
        # staged file.
        shutil.rmtree(reprodir, ignore_errors=True)

    # One row per STALE FILE, not per bundle: a bundle is stale because of
    # specific files, and naming those files is the whole value of the
    # check.  (The earlier form compared every file in a bundle against the
    # newest file in the tree and so reported all 90, which is the mtime
    # heuristic this section exists to replace.)
    rule("DERIVED-INTERMEDIATE STALENESS (staged artifact is not the build "
         "the tree currently describes)")
    print("  copies compared:               %d    STALE: %d    "
          "byte-identical: %d    UNKNOWN: %d"
          % (len(stale) + len(fresh), len(stale), len(fresh),
             len(stale_unknown)))
    print("  rule: a staged copy under work/ must carry the same bytes as the "
          "build")
    print("        output it was copied from")
    for spath, rel, counterpart, delta in sorted(stale,
                                                 key=lambda r: -r[3])[:20]:
        print("    STALE  %s" % spath)
        print("      staged copy:  %s" % rel)
        print("      build output: %s" % counterpart)
        print("      contents differ from the build output")
    if len(stale) > 20:
        print("    ... and %d more" % (len(stale) - 20))
    for spath, rel, why in stale_unknown[:20]:
        print("    UNKNOWN  %s" % rel)
        print("      staged as: %s" % spath)
        print("      %s" % why)
    if len(stale_unknown) > 20:
        print("    ... and %d more" % (len(stale_unknown) - 20))

    # Reproduced recipes: the transform was re-run and the bytes compared.
    # This is the strongest evidence the tool can produce -- "the staged
    # artifact is exactly what the tree's own recipe makes right now".
    print("  reproduced recipes:            %d    STALE: %d    "
          "byte-identical: %d"
          % (len(recipe_stale) + len(recipe_fresh), len(recipe_stale),
             len(recipe_fresh)))
    print("  rule: re-running the producing recipe must reproduce the staged "
          "bytes")
    for spath, rel, recipe_text, reproduced in recipe_stale[:20]:
        print("    STALE  %s" % spath)
        print("      staged copy:   %s" % rel)
        print("      recipe:        %s" % recipe_text)
        print("      re-running it produced different bytes than the staged "
              "artifact")
    for spath, rel, recipe_text in recipe_fresh:
        print("    ok     %-32s reproduced byte-for-byte by `%s`"
              % (rel, recipe_text))

    # Source-built products: a different question (product vs its sources),
    # reported under the same heading because it is the same defect class --
    # a staged artifact that is not the build the tree currently describes.
    print("  source-built products compared: %d    STALE: %d    "
          "up to date: %d"
          % (len(source_stale) + len(source_fresh), len(source_stale),
             len(source_fresh)))
    print("  rule: a product built from repo sources must be at least as new "
          "as every source")
    print("        it was compiled from (recipes recovered from the producing "
          "scripts)")
    for spath, rel, producer, delta, newest_src in sorted(
            source_stale, key=lambda r: r[3])[:20]:
        print("    STALE  %s" % spath)
        print("      built by %s, which compiles %s" % (producer, newest_src))
        print("      that source is %.0fs NEWER than the staged product"
              % (-delta))
    if len(source_stale) > 20:
        print("    ... and %d more" % (len(source_stale) - 20))

    # Deduplicated by intermediate: work/efi/BOOTX64.EFI is staged at two
    # paths, and listing the same comparison twice would read as two checks.
    for rel, producer, delta, newest_src in sorted(
            {(r, p, d, n): None for _s, r, p, d, n in source_fresh}):
        print("    ok     %-26s (%s, newest source %s%.0fs older)"
              % (rel, producer, "+" if delta >= 0 else "", abs(delta)))
    if not (stale or source_stale or recipe_stale or stale_unknown):
        print("  (every staged artifact matches the build it was made from)")

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

    # ---- provenance -------------------------------------------------------
    # Is any staged binary lifted out of the HOST Mac's dyld shared cache?
    # Apple mints a fresh LC_UUID per build, so a UUID the host cache also
    # records can only have come out of that Apple build.  This is a property
    # distinct from every check above: a host-extracted dylib can be
    # structurally perfect -- valid load commands, fully resolvable symbols --
    # and still be a binary this repository never built and does not own.
    # See provenance_scan.py and PROVENANCE-PLAN.md sec. 2.
    #
    # WHICH BYTES.  With --image the verdict is made about the bytes read back
    # OUT of the finished image, not about the files the manifest names.  That
    # distinction is the whole claim: "no staged binary came from the host
    # cache" is a statement about a disk only if it was made about the disk.
    # Re-deriving it from the source tree afterwards describes the build tree,
    # and a manifest edited, a stage step re-run, or an image swapped between
    # build and check all make those two answers disagree.
    prov = None
    if args.provenance_check:
        sys.path.insert(0, HERE)
        import provenance_scan
        prov_paths = [(sp, sr) for sp, sr in staged
                      if sr and os.path.isfile(sr)]
        # The kernel is staged but is not a dyld-closure participant, so
        # manifest_staged_files gives it no source.  That is a statement about
        # symbol resolution, not about provenance: it is still a Mach-O the
        # image loads.  Resolve it the way mkimage.py does so the set scanned
        # for provenance is the set staged.  Without this, a swapped kernel --
        # the one payload mkimage picks by mtime from outside the manifest --
        # would never be judged at all.
        try:
            kern_src = provenance_scan.kernel_payload(HERE)
        except provenance_scan.ManifestSourceError:
            kern_src = None
        if kern_src is not None:
            for sp, _ in staged:
                if os.path.basename(sp) == "kernel.development":
                    prov_paths.append((sp, kern_src))
        try:
            uuids, nbytes, nfiles = provenance_scan.cached_host_uuid_set(
                provenance_scan.DEFAULT_CACHE_DIR)
        except Exception as exc:                          # noqa: BLE001
            rule("PROVENANCE (host dyld shared cache)")
            print("  !! NOT SATISFIED: host cache unavailable: %s" % exc)
            print("  !! The provenance check could NOT run.")
            prov = {"ran": False, "hits": None, "n": 0}
        else:
            hits = []
            n = 0
            for sp, sr in prov_paths:
                if readback:
                    # Image mode: judge the image's own bytes.  A staged path
                    # the image did not yield is already recorded in `errors`
                    # above, so there is nothing to invent here.
                    if sp not in readback:
                        continue
                    found, text_vmaddr, _ = \
                        provenance_scan.macho_uuids_and_text_bytes(readback[sp])
                else:
                    found, text_vmaddr, _ = \
                        provenance_scan.macho_uuids_and_text(sr)
                if not found and text_vmaddr is None:
                    continue
                n += 1
                if any(u in uuids for u in found):
                    hits.append(sp)
            prov = {"ran": True, "hits": hits, "n": n}
            rule("PROVENANCE (host dyld shared cache)")
            print("  bytes judged from:       %s"
                  % ("the image, read back out of it" if readback
                     else "the staged source files"))
            print("  staged Mach-O checked:   %d" % n)
            print("  host UUID set:           %d candidates from %d cache "
                  "file(s)" % (len(uuids), nfiles))
            print("  HOST-EXTRACTED:          %d" % len(hits))
            for sp in hits:
                print("    %s" % sp)
            if not hits:
                print("  (every staged binary was built by this repository)")

    # ---- verdict ----------------------------------------------------------
    ok = (not errors and not missing_deps and not unresolved and not rejects
          and not unreachable and not no_libsystem and not init_unknown
          and not stale and not source_stale and not recipe_stale)
    # A host-extracted binary is a FAIL, not a warning: it is a binary this
    # repository did not build, so its passing every structural check above
    # proves nothing about whether it belongs in an image.
    if prov is not None and prov["hits"]:
        ok = False
    # Likewise, a check that could not run is a FAIL, not a silent pass: a
    # green verdict must mean the provenance question was actually answered.
    if prov is not None and not prov["ran"]:
        ok = False
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
    if unreachable:
        print("  FAIL  %d symbol(s) have a provider NOT reachable via the"
              % len(unreachable))
        print("        consumer's LC_LOAD_DYLIB (staged but unlinked — dyld "
              "rejects at bind time)")
    if init_unknown:
        print("  FAIL  initializer presence could not be determined for %d "
              "staged image(s)" % len(init_unknown))
    if no_libsystem:
        print("  FAIL  %d staged image(s) have initializers but do NOT link "
              "libSystem" % len(no_libsystem))
        print("        (dyld throws \"initializer in image (...) that does not "
              "link with")
        print("        libSystem.dylib\" before running them)")
    if stale:
        print("  FAIL  %d staged file(s) come from a derived intermediate "
              "that DIFFERS" % len(stale))
        print("        from the build output it represents (a stale copy still "
              "hashes clean:")
        print("        the image is internally consistent and wrong)")
    if source_stale:
        print("  FAIL  %d staged product(s) are OLDER than a source they were"
              % len(source_stale))
        print("        compiled from (the tree describes a build this image does "
              "not carry)")
    if recipe_stale:
        print("  FAIL  %d staged artifact(s) are NOT reproduced by their own "
              "recipe" % len(recipe_stale))
        print("        (re-running the producing step yields different bytes "
              "than the image)")
    if stale_unknown:
        print("  UNKNOWN  %d staged file(s) source from work/ with no "
              "registered upstream build" % len(stale_unknown))
        print("        output — their freshness could not be determined")
    if prov is not None and not prov["ran"]:
        print("  FAIL  provenance check could not run (host dyld cache "
              "unavailable)")
    elif prov is not None and prov["hits"]:
        print("  FAIL  %d staged binary/ies came from the host dyld shared "
              "cache" % len(prov["hits"]))
    elif prov is not None:
        print("  PASS  no staged binary came from the host dyld shared cache")
    else:
        print("  SKIP  provenance check not run (--no-provenance-check)")
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