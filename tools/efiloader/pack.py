#!/usr/bin/env python3
"""Single-object COFF(x86-64) -> PE32+ EFI application linker.

Why this exists: the host has clang (emits COFF objects for
-target x86_64-unknown-windows) but NO PE/COFF linker (no lld-link, no
mingw, Apple ld64 is Mach-O only).  The ravynOS EFI loader is a single
freestanding translation unit, so a full linker is unnecessary: we lay
out sections, resolve the object's own symbols, apply its COFF
relocations, and emit a .reloc base-relocation directory so the DXE core
can rebase the image wherever it loads it.

Usage: pack.py <in.obj> <out.efi> <entry-symbol>
"""
import struct
import sys

SECT_ALIGN = 0x1000
FILE_ALIGN = 0x200
IMAGE_FILE_MACHINE_AMD64 = 0x8664
SUBSYSTEM_EFI_APPLICATION = 10
SUBSYSTEM_EFI_BOOT_SERVICE_DRIVER = 11
SUBSYSTEM_EFI_RUNTIME_DRIVER = 12

# COFF characteristics for a section
SCN_CNT_CODE = 0x00000020
SCN_CNT_IDATA = 0x00000040
SCN_CNT_UADATA = 0x00000080
SCN_MEM_EXEC = 0x20000000
SCN_MEM_READ = 0x40000000
SCN_MEM_WRITE = 0x80000000


class Coff:
    def __init__(self, data):
        self.d = data
        (self.nsec,) = struct.unpack_from('<H', data, 2)
        (self.symoff, self.nsym) = struct.unpack_from('<II', data, 8)
        (self.opthdrsz,) = struct.unpack_from('<H', data, 16)
        self.sections = []
        base = 20 + self.opthdrsz
        self.strtab = data[self.symoff + 18 * self.nsym:]
        for i in range(self.nsec):
            o = base + 40 * i
            name = data[o:o + 8].rstrip(b'\0').decode()
            if name.startswith('/'):
                name = self.strtab[int(name[1:]):].split(b'\0')[0].decode()
            vsize, vaddr, rawsz, rawptr = struct.unpack_from('<IIII', data, o + 8)
            relptr, lineptr, nrel, nline = struct.unpack_from('<IIII', data, o + 24)
            chars, = struct.unpack_from('<I', data, o + 36)
            rels = []
            for r in range(nrel):
                ro = relptr + 10 * r
                # VirtualAddress(4) + SymbolTableIndex(4) + Type(2) = 10
                voff, symidx, typ = struct.unpack_from('<IIH', data, ro)
                rels.append((voff, symidx, typ))
            self.sections.append(dict(name=name, vsize=vsize, vaddr=vaddr,
                                      rawsz=rawsz, rawptr=rawptr,
                                      chars=chars, rels=rels, idx=i + 1))
        self.syms = []
        i = 0
        while i < self.nsym:
            o = self.symoff + 18 * i
            # Names of 8 characters or fewer are stored inline, NUL padded.
            # Longer ones become a string-table offset, and this LLVM COFF
            # writer puts that offset in the SECOND 4-byte half of Name[8]
            # with the first half zeroed.  (I originally assumed the
            # opposite -- offset first, zeros second -- and every long name
            # silently decoded as empty, which is how two handoff
            # relocations ended up pointing at one wrong address.)
            # Try both halves and take whichever yields a real name.
            name = None
            hi, = struct.unpack_from('<I', data, o + 4)
            lo, = struct.unpack_from('<I', data, o)
            for nlen in (hi, lo):
                if lo == 0 and hi == 0:
                    break
                if 0 < nlen < len(self.strtab):
                    cand = self.strtab[nlen:].split(b'\0')[0]
                    if cand and all(32 <= c < 127 for c in cand):
                        name = cand.decode()
                        break
            if name is None:
                name = data[o:o + 8].split(b'\0')[0].decode()
            (val,) = struct.unpack_from('<i', data, o + 8)
            (sec,) = struct.unpack_from('<h', data, o + 12)
            (typ,) = struct.unpack_from('<H', data, o + 16)
            (naux,) = struct.unpack_from('<B', data, o + 17)
            self.syms.append(dict(name=name, val=val, sec=sec, typ=typ, idx=i))

            i += 1 + naux
        self.sym_by_idx = {s['idx']: s for s in self.syms}

    def sec_data(self, s):
        if s['rawptr'] == 0 or s['rawsz'] == 0:
            return b''
        return self.d[s['rawptr']:s['rawptr'] + s['rawsz']]


def group(name):
    """Map a COFF section name to a PE section name + characteristics."""
    if name.startswith('.text'):
        return '.text', SCN_CNT_CODE | SCN_MEM_EXEC | SCN_MEM_READ
    if name.startswith('.rdata') or name.startswith('.rodata'):
        return '.rdata', SCN_CNT_IDATA | SCN_MEM_READ
    if name.startswith('.data'):
        return '.data', SCN_CNT_IDATA | SCN_MEM_READ | SCN_MEM_WRITE
    if name.startswith('.bss'):
        return '.bss', SCN_CNT_UADATA | SCN_MEM_READ | SCN_MEM_WRITE
    if name.startswith('.pdata') or name.startswith('.xdata'):
        return '.pdata', SCN_CNT_IDATA | SCN_MEM_READ
    if name.startswith('.debug') or name.startswith('.llvm') or name == '.drectve':
        return None, 0            # linker directives / metadata: drop
    raise SystemExit('pack.py: unmapped COFF section %r' % name)


def align(v, a):
    return (v + a - 1) & ~(a - 1)


def build(objpath, outpath, entry_sym, subsystem=SUBSYSTEM_EFI_APPLICATION,
          reloc_map=None):
    coff = Coff(open(objpath, 'rb').read())

    # ---- assign RVAs, one page per distinct output section ----
    order = ['.text', '.rdata', '.data', '.bss', '.pdata']
    out = {}
    for s in coff.sections:
        gname, chars = group(s['name'])
        if gname is None:
            continue
        blob = bytearray(coff.sec_data(s))
        size = max(s['vsize'], s['rawsz'])
        out.setdefault(gname, dict(chars=chars, blobs=[], size=0))
        s['rva'] = None
        s['gname'] = gname
        s['off_in_group'] = out[gname]['size']
        out[gname]['size'] = align(out[gname]['size'], 16) + size
        s['gpad'] = align(out[gname]['size'], 16) - (out[gname]['size'] - size)
        out[gname]['blobs'].append((s['off_in_group'], bytes(blob), size))

    present = [g for g in order if g in out]
    hdr_size = align(0x40 + 0x18 + 0xF0 + 40 * (len(present) + 1), FILE_ALIGN)
    rva = hdr_size
    for g in present:
        gsz = align(out[g]['size'], SECT_ALIGN)
        out[g]['rva'] = rva
        out[g]['vsize'] = out[g]['size']
        out[g]['rawsz'] = align(gsz, FILE_ALIGN)
        out[g]['rva_size'] = gsz
        rva += gsz
    # .reloc is appended after the fixups are known; reserve one page for it
    # up front so SizeOfImage covers it, then shrink if it turns out empty.
    reloc_rva = rva
    size_of_image = rva + SECT_ALIGN
    reloc_sect_index = len(present)

    for s in coff.sections:
        if s.get('gname') is None:
            continue
        s['rva'] = out[s['gname']]['rva'] + s['off_in_group']

    # ---- symbol table: name -> RVA ----
    symrva = {}
    for sym in coff.syms:
        if sym['sec'] > 0:
            sec = coff.sections[sym['sec'] - 1]
            if sec.get('rva') is None:      # symbol in a dropped section
                continue
            symrva[sym['name']] = sec['rva'] + sym['val']
        elif sym['sec'] == 0 and sym['val'] == 0:
            pass  # absolute / external: we only link a closed program
        else:
            symrva[sym['name']] = sym['val']

    if entry_sym not in symrva:
        raise SystemExit('pack.py: entry symbol %r not found' % entry_sym)

    # ---- apply relocations ----
    # 64-bit absolute fixups need a base-relocation record.
    abs_fixups = []
    relog = []
    blobs = {g: bytearray(out[g]['rawsz']) for g in present}
    for g in present:
        for off, blob, size in out[g]['blobs']:
            blobs[g][off:off + len(blob)] = blob

    for s in coff.sections:
        if s.get('gname') is None or not s['rels']:
            continue
        g = s['gname']
        for voff, symidx, typ in s['rels']:
            if typ == 0x0:        # IMAGE_REL_AMD64_ABSOLUTE: padding entry
                continue
            sym = coff.sym_by_idx.get(symidx)
            if sym is None:
                raise SystemExit('pack.py: relocation at %s+0x%x names symbol '
                                 'index %d, which is past the end of the symbol '
                                 'table' % (s['name'], voff, symidx))
            #
            # A REL32 against an UNDEFINED symbol is not something a
            # single-object link can satisfy.  Refuse it.
            #
            # This is a bug I already shipped once.  Two statics referenced
            # only from a naked function's inline asm came out of clang as
            # undefined externals with unrecoverable names; the old code
            # looked the (empty) name up in a table that happened to contain
            # it and silently produced ONE WRONG RVA for both instructions.
            # The handoff stub then did lgdt from garbage and far-jumped with
            # a garbage selector, and the CPU triple-faulted with CS=0x38 --
            # a selector that came out of .rdata, not out of a GDT.  I spent
            # a whole debugging cycle blaming the mode switch.
            #
            # A linker that cannot resolve a reference must stop.  It must
            # never invent an answer.
            #
            if sym['sec'] == 0 and (not sym['name'] or sym['name'] not in symrva):
                raise SystemExit(
                    'pack.py: REFUSING to link: relocation at %s+0x%x '
                    'references an unresolvable symbol (index %d, name %r). '
                    'This is what produced a silent wrong address last time.'
                    % (s['name'], voff, symidx, sym['name']))
            if sym['sec'] > 0:
                tsec = coff.sections[sym['sec'] - 1]
                if tsec.get('rva') is None:
                    raise SystemExit('pack.py: reloc into dropped section')
                # A section symbol's value is its offset within the section.
                S = tsec['rva'] + sym['val']
            else:
                S = symrva.get(sym['name'])
                if S is None:
                    raise SystemExit('pack.py: unresolved symbol %r' % sym['name'])
            off = s['off_in_group'] + voff
            b = blobs[g]
            P = out[g]['rva'] + off
            P_field = P
            if reloc_map is not None:
                relog.append((s['name'], P_field, voff, sym['name'], S))
            if typ == 0x4:      # IMAGE_REL_AMD64_REL32
                # PE spec: the base is "the byte following the relocation",
                # which for x86-64 RIP-relative code is P+4.
                A = struct.unpack_from('<i', b, off)[0]
                struct.pack_into('<I', b, off, (S + A - P - 4) & 0xFFFFFFFF)
            elif typ == 0x1:    # IMAGE_REL_AMD64_ADDR64
                P = out[g]['rva'] + off
                struct.pack_into('<Q', b, off, S)
                abs_fixups.append(out[g]['rva'] + off)
            elif typ == 0x2:    # IMAGE_REL_AMD64_ADDR32
                P = out[g]['rva'] + off
                struct.pack_into('<I', b, off, S & 0xFFFFFFFF)
                abs_fixups.append(out[g]['rva'] + off)
            elif typ == 0x3:    # IMAGE_REL_AMD64_ADDR32NB
                P = out[g]['rva'] + off
                struct.pack_into('<I', b, off, (S - P) & 0xFFFFFFFF)
            elif typ == 0xB:    # IMAGE_REL_AMD64_SECTION
                struct.pack_into('<H', b, off, sym['sec'])
            elif typ == 0xC:    # IMAGE_REL_AMD64_SECREL
                struct.pack_into('<I', b, off, sym['val'] & 0xFFFFFFFF)
            else:
                raise SystemExit('pack.py: unhandled COFF reloc type %d' % typ)

    # ---- collision guard ----
    # The fingerprint of the bug this file shipped once: two relocations that
    # reference DIFFERENT symbols resolving to the SAME RVA, because a name
    # lookup silently missed and fell through to a wrong table entry.  Detect
    # it here rather than discovering it as a #GP three sessions later.
    _seen = {}
    for _sec in coff.sections:
        for _voff, _si, _typ in _sec.get('rels', ()):
            _sy = coff.sym_by_idx.get(_si)
            if _sy is None or _sy['sec'] != 0:
                continue
            _prev = _seen.get(_sy['name'])
            if _prev is not None and _prev != _voff:
                raise SystemExit(
                    'pack.py: REFUSING to link: symbol %r is referenced from '
                    'two different places (0x%x and 0x%x). That is the '
                    'fingerprint of the long-name decoding bug.'
                    % (_sy['name'], _prev, _voff))
            _seen[_sy['name']] = _voff

    if reloc_map:
        with open(reloc_map, 'w') as _f:
            _f.write('# section P voff sym_name S\n')
            for _r in relog:
                _f.write('%s %x %s %s %x\n' % _r)

    # ---- build .reloc ----
    reloc = bytearray()
    abs_fixups = sorted(set(abs_fixups))
    page = None
    for a in abs_fixups:
        pg = a & ~0xFFF
        if pg != page:
            page = pg
            reloc += struct.pack('<II', pg, 8)  # SizeOfBlock patched below
        reloc += struct.pack('<HH', (a - pg) // 2, 10)  # IMAGE_REL_BASED_DIR64
    i = 0
    while i < len(reloc):
        _, sz = struct.unpack_from('<II', reloc, i)
        struct.pack_into('<I', reloc, i + 4, sz)
        i += sz
    reloc_raw = align(len(reloc), FILE_ALIGN)
    if abs_fixups:
        size_of_image = reloc_rva + SECT_ALIGN
    else:
        # Fully position-independent image: no base relocations needed, and
        # emitting an empty .reloc would make the DXE core walk garbage.
        reloc_rva = 0
        size_of_image = reloc_rva_base = hdr_size
        for g in present:
            size_of_image = max(size_of_image, out[g]['rva'] + out[g]['rva_size'])
        size_of_image = align(size_of_image, SECT_ALIGN)
    # ---- headers ----
    nsec = len(present) + (1 if abs_fixups else 0)
    optsz = 0xF0
    dos = bytearray(0x40)
    dos[0:2] = b'MZ'
    struct.pack_into('<I', dos, 0x3C, 0x40)
    coffh = struct.pack('<HHIIIHH', IMAGE_FILE_MACHINE_AMD64, nsec, 0, 0, 0,
                        optsz, 0x2022)
    size_of_code = out['.text']['rawsz'] if '.text' in out else 0
    size_of_idata = sum(out[g]['rawsz'] for g in present
                        if g in ('.rdata', '.data')) + reloc_raw
    size_of_udata = out['.bss']['vsize'] if '.bss' in out else 0
    dirs = [(0, 0)] * 16
    dirs[5] = (reloc_rva, len(reloc))          # base relocations
    dirs[12] = (0, 0)                          # IAT
    dd = b''.join(struct.pack('<II', a, b) for a, b in dirs)
    opt = struct.pack('<HBBIIIIIQIIHHHHHHIIIIHHQQQQII',
                      0x20B, 1, 0,
                      size_of_code, size_of_idata, size_of_udata,
                      symrva[entry_sym], out['.text']['rva'] if '.text' in out else 0,
                      0,                      # ImageBase
                      SECT_ALIGN, FILE_ALIGN,
                      0, 0, 0, 0, 0, 0,   # OS / image / subsystem versions
                      0,                      # Win32VersionValue
                      size_of_image, hdr_size, 0,
                      subsystem, 0,
                      0x100000, 0x1000, 0x100000, 0x1000,
                      0, 16)
    assert len(opt) + len(dd) == optsz, (len(opt), len(dd), optsz)
    opt = opt + dd

    sectab = bytearray()
    for g in present:
        sectab += struct.pack('<8sIIIIIIHHI',
                              g.encode().ljust(8, b'\0'),
                              out[g]['vsize'], out[g]['rva'],
                              out[g]['rawsz'], 0,
                              0, 0, 0, 0, out[g]['chars'])
    if abs_fixups:
        sectab += struct.pack('<8sIIIIIIHHI', b'.reloc',
                              len(reloc), reloc_rva, reloc_raw, 0, 0, 0, 0, 0,
                              SCN_CNT_IDATA | SCN_MEM_READ)

    assert len(sectab) == 40 * nsec

    raw = bytearray(hdr_size)
    raw[0:len(dos)] = dos
    o = 0x40
    raw[o:o + 4] = b'PE\0\0'
    raw[o + 4:o + 4 + 20] = coffh
    raw[o + 24:o + 24 + len(opt)] = opt
    raw[o + 24 + len(opt):o + 24 + len(opt) + len(sectab)] = sectab

    rawptr = hdr_size
    for g in present:
        struct.pack_into('<I', raw, 0x40 + 4 + 20 + optsz + 40 * present.index(g) + 20, rawptr)
        raw[rawptr:rawptr + out[g]['rawsz']] = blobs[g][:out[g]['rawsz']]
        rawptr += out[g]['rawsz']
    if abs_fixups:
        struct.pack_into('<I', raw,
                         0x40 + 4 + 20 + optsz + 40 * reloc_sect_index + 20, rawptr)
        raw[rawptr:rawptr + len(reloc)] = reloc
        rawptr += reloc_raw

    open(outpath, 'wb').write(bytes(raw))
    print('pack.py: %s -> %s  SizeOfImage=0x%x entry=0x%x sections=%s relocs=%d'
          % (objpath, outpath, size_of_image, symrva[entry_sym],
             present + ['.reloc'], len(abs_fixups)))


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2], sys.argv[3],
          int(sys.argv[4]) if len(sys.argv) > 4 else SUBSYSTEM_EFI_APPLICATION,
          sys.argv[5] if len(sys.argv) > 5 else None)
