#!/usr/bin/env python3
"""Normalize DSC-extracted dylibs so dyld3 will load them as plain files.

Transforms applied (nothing else is touched — addresses, symtab, and the
pre-bound GOT must keep their DSC values):

1. Add SG_READ_ONLY (0x10) to __TEXT/__TEXT_EXEC/__DATA_CONST segment flags.
   dyld3 rejects plain-file images whose __DATA_CONST lacks the flag.
2. Reorder LC_SEGMENT_64 commands into ascending vmaddr order.
   The DSC layout has __DATA_DIRTY below __DATA; dyld3 requires segments in
   ascending vmaddr order ("vm address out of order").

Usage: dsc_flagfix.py <file>...   (idempotent, x86_64 slices of fat or thin)
"""
import struct, sys

MH_CIGAM_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
LC_SEGMENT_64 = 0x19
SG_READ_ONLY = 0x10
RO_SEGS = {b"__TEXT", b"__TEXT_EXEC", b"__DATA_CONST"}

def transform_macho(buf, off):
    (magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags_) = \
        struct.unpack_from("<7I", buf, off)
    assert magic == MH_CIGAM_64, hex(magic)
    assert (cputype & 0xFFFF0000) == 0x01000000, "not x86_64"

    pos = off + 32  # dsc_extractor output carries 4 padding bytes after header
    end = pos + sizeofcmds
    blocks = []  # (is_seg, vmaddr, byteblock)
    p = pos
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, p)
        if cmdsize == 0 or p + cmdsize > end:
            raise RuntimeError("bad cmdsize at %x" % p)
        if cmd == LC_SEGMENT_64:
            vmaddr = struct.unpack_from("<Q", buf, p + 24)[0]
            fl = struct.unpack_from("<I", buf, p + 68)[0]
            if bytes(buf[p+8:p+24].rstrip(b"\x00")) in RO_SEGS and not fl & SG_READ_ONLY:
                struct.pack_into("<I", buf, p + 68, fl | SG_READ_ONLY)
            blocks.append((1, vmaddr, bytes(buf[p:p+cmdsize])))
        else:
            blocks.append((0, 0, bytes(buf[p:p+cmdsize])))
        p += cmdsize
    assert p == end, "LC walk did not reach sizeofcmds end"

    segs = sorted((b for b in blocks if b[0]), key=lambda b: b[1])
    rest = [b for b in blocks if not b[0]]
    newregion = b"".join(b[2] for b in segs + rest)
    assert len(newregion) == sizeofcmds
    buf[off+32:off+32+sizeofcmds] = newregion
    return len(segs)

def main():
    for path in sys.argv[1:]:
        with open(path, "r+b") as f:
            buf = bytearray(f.read())
            if buf[:4] == struct.pack("<I", FAT_MAGIC):
                nfat = struct.unpack_from("<I", buf, 4)[0]
                done = 0
                for i in range(nfat):
                    cputype, offset = struct.unpack_from("<II", buf, 8 + i*8)
                    if (cputype & 0xFFFF0000) == 0x01000000:
                        done = transform_macho(buf, offset)
                if done == 0:
                    print(f"{path}: no x86_64 slice")
            else:
                done = transform_macho(buf, 0)
            f.seek(0)
            f.write(buf)
            print(f"{path}: normalized {done} segment(s)")

if __name__ == "__main__":
    main()
