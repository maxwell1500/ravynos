#!/usr/bin/env python3
"""Normalize Apple DSC-extracted dylibs so dyld3 loads them as plain files.

dsc_extractor keeps DSC-absolute vmaddrs and pre-bound data (GOT/symtab hold
absolute addresses) but zeros every section offset and leaves data segments
in DSC file order (__DATA before __DATA_DIRTY, whose vmaddr is lower).
dyld3 requires:

  1. SG_READ_ONLY on __TEXT/__TEXT_EXEC/__DATA_CONST.
  2. Segments in ascending vmaddr order AND ascending file offset,
     no file-range overlap.
  3. Every section offset valid (0 means not-in-file, e.g. __bss).

This tool: reorders the LCs by vmaddr, repacks the file so segment file
ranges follow vmaddr order contiguously, and rewrites each in-file section
offset as segfileoff + (sectaddr - segvmaddr). LINKEDIT-dependent file
offsets (symtab symoff/strtaboff) shift by the delta. All addresses,
vmsizes and data bytes are untouched. Broken 32-bit LC_STABS artifacts
are dropped.

Usage: dsc_normalize.py <file>...   (idempotent, x86_64 slices of fat or thin)
"""
import struct, sys

MH_CIGAM_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_STABS = 0xB
SG_READ_ONLY = 0x10
RO_SEGS = {b"__TEXT", b"__TEXT_EXEC", b"__DATA_CONST"}
LINKEDIT = b"__LINKEDIT"

def transform_macho(buf, off, log):
    (magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags_) = \
        struct.unpack_from("<7I", buf, off)
    assert magic == MH_CIGAM_64, hex(magic)
    assert (cputype & 0xFFFF0000) == 0x01000000, "not x86_64"

    lcbase = off + 32          # dsc_extractor emits 4 padding bytes after header
    lccend = lcbase + sizeofcmds
    segs = []                  # [name, vmaddr, vmsize, fileoff, filesize, nsects, blk, sects]
    rest = []                  # non-segment LC byte blocks
    dropped = []
    p = lcbase
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, p)
        if cmdsize == 0 or p + cmdsize > lccend:
            raise RuntimeError("bad cmdsize at 0x%x" % p)
        if cmd == LC_STABS:
            dropped.append(cmdsize)          # broken 32-bit artifact from DSC
        elif cmd == LC_SEGMENT_64:
            name = bytes(buf[p+8:p+24].rstrip(b"\x00"))
            vmaddr, vmsize = struct.unpack_from("<QQ", buf, p+24)
            fileoff, filesize = struct.unpack_from("<QQ", buf, p+40)
            nsects = struct.unpack_from("<I", buf, p+64)[0]
            fl = struct.unpack_from("<I", buf, p+68)[0]
            if name in RO_SEGS and not fl & SG_READ_ONLY:
                struct.pack_into("<I", buf, p+68, fl | SG_READ_ONLY)
            sects = []
            sp = p + 72
            for s in range(nsects):
                sectname = bytes(buf[sp:sp+16].rstrip(b"\x00"))
                saddr, ssize = struct.unpack_from("<QQ", buf, sp+32)
                sects.append([sectname, saddr, ssize])
                sp += 80
            segs.append([name, vmaddr, vmsize, fileoff, filesize, nsects,
                         bytes(buf[p:p+cmdsize]), sects])
        else:
            rest.append(bytes(buf[p:p+cmdsize]))
        p += cmdsize
    assert p == lccend

    segs.sort(key=lambda s: s[1])
    oldle = [s for s in segs if s[0] == LINKEDIT][0]

    # repack: contiguous file ranges in vmaddr order (keep each filesize)
    pos = 0
    for sg in segs:
        sg.append(pos)                          # new fileoff (sg[8])
        pos += sg[4]
    newle_off = [s for s in segs if s[0] == LINKEDIT][0][8]
    le_delta = newle_off - oldle[3]
    newlen = pos

    # rebuild file
    hdr = bytearray(buf[:lcbase])
    struct.pack_into("<II", hdr, 16, ncmds - len(dropped),
                     sizeofcmds - sum(dropped))
    out = hdr
    out += b"".join(sg[6] for sg in segs)       # segment LCs in vmaddr order
    out += b"".join(rest)
    for sg in segs:
        out += buf[sg[3]:sg[3] + sg[4]]         # original file bytes
    # rewrite segment LC fields in place inside `out`
    lc = lcbase - off
    for sg in segs:
        newfo = sg[8]
        b2 = bytearray(sg[6])
        struct.pack_into("<QQ", b2, 40, newfo, sg[4])
        for i, s in enumerate(sg[7]):
            rel = s[1] - sg[1]                  # sectaddr - segvmaddr
            if rel > 0 and rel < sg[4]:
                struct.pack_into("<I", b2, 72 + i*80 + 56, newfo + rel)
        out[lc:lc+len(b2)] = b2
        lc += len(b2)
    # shift file-absolute offsets into moved LINKEDIT (symoff AND strtaboff)
    q = lc
    for r in rest:
        cmd = struct.unpack_from("<I", r, 0)[0]
        if cmd == LC_SYMTAB:
            b2 = bytearray(r)
            struct.pack_into("<I", b2, 8,  struct.unpack_from("<I", r, 8)[0]  + le_delta)
            struct.pack_into("<I", b2, 16, struct.unpack_from("<I", r, 16)[0] + le_delta)
            out[q:q+len(b2)] = b2
        q += len(r)
    assert len(out) == (lcbase - off) + sizeofcmds - sum(dropped) + newlen

    if out == buf:
        log.append("  (already normalized)")
        return 0
    buf[:] = out
    log.append("  segments: " + ", ".join(
        f"{s[0].decode()}@{s[1]:#x}->{s[8]:#x}" for s in segs))
    return 1

def main():
    total = 0
    for path in sys.argv[1:]:
        with open(path, "r+b") as f:
            buf = bytearray(f.read())
            log = []
            if buf[:4] == struct.pack("<I", FAT_MAGIC):
                nfat = struct.unpack_from("<I", buf, 4)[0]
                done = 0
                entries = []
                for i in range(nfat):
                    entries.append(list(struct.unpack_from("<5I", buf, 8 + i*20)))
                newoff = 8 + nfat*20
                body = []
                for e in entries:
                    e[2] = newoff
                    body.append(buf[e[2]:e[2]+e[3]])
                    newoff += e[3]
                for i, e in enumerate(entries):
                    if (e[0] & 0xFFFF0000) == 0x01000000:
                        done += transform_macho(body[i], 0, log)
                    e[3] = len(body[i])
                out = struct.pack("<2I", FAT_MAGIC, nfat)
                for e in entries:
                    out += struct.pack("<5I", *e)
                out += b"".join(body)
                buf[:] = out
                f.seek(0)
                f.write(buf)
                total += done
            else:
                done = transform_macho(buf, 0, log)
                f.seek(0)
                f.write(buf)
                total += done
            print(f"{path}: {len(log)} note(s)" if log else f"{path}: ok")
            for l in log:
                print(l)
    print(f"total slices normalized: {total}")

if __name__ == "__main__":
    main()
