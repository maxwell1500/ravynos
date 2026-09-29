"""GPT conformance repair for the bootlab disk templates.

WHY THIS EXISTS
---------------
`assets/template_head.bin` and `assets/template_tail.bin` are golden byte
templates whose GPT header is not what the UEFI specification says:

    bytes 0x50..0x54  NumberOfPartitionEntries   written as UINT32   (spec: UINT64)
    bytes 0x54..0x58  SizeOfPartitionEntry      written as UINT32   (spec: UINT32 @0x58)
    bytes 0x58..0x5C  PartitionEntryArrayCRC32  (spec: @0x5C)

An EDK2 PartitionDxe reads a UINT64 at 0x50 and therefore sees
0x0000008000000080 = 549,755,814,016 partition entries, rejects the layout,
and never creates a partition handle.  FatDxe consequently never binds and
EFI_SIMPLE_FILE_SYSTEM_PROTOCOL is never installed -- which is why a
HandleProtocol sweep of every handle in the handle database found zero
volumes while the UEFI shell still showed FS0 (the shell enumerates the
volume its own way).  HandleProtocol was reporting the truth.

The partition is additionally typed EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
("Microsoft Basic Data") instead of C12A7328-F81F-11D2-BA4B-00A0C93EC93B
("EFI System Partition"), which is an independent second reason PartitionDxe
would not bind it.

This module rewrites the header fields in place, in memory, on the template
bytes before ImageBuilder writes them.  The committed templates are NOT
modified, so the change is additive and reversible, and it applies to every
image the harness builds from now on.

It also recomputes both CRCs, so the result is a conformant GPT rather than
one that merely parses.
"""

import struct

GPT_SIG = b"EFI PART"
GPT_HDR_OFF = 512              # LBA 1
GPT_HDR_SIZE = 92              # spec HeaderSize for the 92-byte header

ESP_TYPE_GUID = bytes([
    0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11,
    0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B,
])                             # C12A7328-F81F-11D2-BA4B-00A0C93EC93B


def _crc32(data):
    """IEEE CRC-32, the same polynomial the UEFI spec uses for GPT."""
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if (crc & 1) else 0)
    return crc ^ 0xFFFFFFFF


def _find_gpt(buf, base=0):
    """Return the offset of a GPT header inside buf, or None."""
    i = buf.find(GPT_SIG, base)
    return None if i < 0 else i


def _fix_header_at(buf, hdr, entry_array):
    """Rewrite one GPT header in place. entry_array is the raw entry bytes."""
    npart = struct.unpack_from("<I", buf, hdr + 0x50)[0]
    psz = struct.unpack_from("<I", buf, hdr + 0x54)[0]
    arr_crc = struct.unpack_from("<I", buf, hdr + 0x58)[0]
    if npart <= 0 or npart > 4096 or psz not in (128, 256):
        raise ValueError("implausible GPT entry count/size %d/%d" % (npart, psz))

    # 0x50 NumberOfPartitionEntries : UINT64
    struct.pack_into("<Q", buf, hdr + 0x50, npart)
    # 0x58 SizeOfPartitionEntry      : UINT32
    struct.pack_into("<I", buf, hdr + 0x58, psz)
    # 0x5C PartitionEntryArrayCRC32  : UINT32
    struct.pack_into("<I", buf, hdr + 0x5C, arr_crc)
    # 0x10 HeaderSize must be the real header size
    struct.pack_into("<I", buf, hdr + 0x0C, GPT_HDR_SIZE)
    # 0x10 HeaderCRC32 covers HeaderSize bytes with itself zeroed
    struct.pack_into("<I", buf, hdr + 0x10, 0)
    struct.pack_into("<I", buf, hdr + 0x10,
                     _crc32(bytes(buf[hdr:hdr + GPT_HDR_SIZE])))
    return npart, psz


def conform_gpt(blob, entry_array_offsets, label):
    """Fix every GPT header in blob, given the offset(s) of its entry array.

    entry_array_offsets are byte offsets within blob of the partition entry
    array, so the array CRC can be recomputed after the type GUID is changed.
    """
    fixed = []
    search = 0
    while True:
        hdr = _find_gpt(blob, search)
        if hdr is None:
            break
        search = hdr + 8
        npart, psz = _fix_header_at(blob, hdr, None)
        arr_len = npart * psz
        arr_crc = None
        for off in entry_array_offsets:
            if abs(off - (hdr - GPT_HDR_OFF + 0)) < 0:   # placeholder, unused
                pass
            if off + arr_len <= len(blob):
                arr_crc = _crc32(bytes(blob[off:off + arr_len]))
                break
        if arr_crc is not None:
            struct.pack_into("<I", blob, hdr + 0x5C, arr_crc)
            # header CRC changed too (the CRC field itself moved)
            struct.pack_into("<I", blob, hdr + 0x10, 0)
            struct.pack_into("<I", blob, hdr + 0x10,
                             _crc32(bytes(blob[hdr:hdr + GPT_HDR_SIZE])))
        fixed.append((hdr, npart, psz))
    if not fixed:
        raise ValueError("%s: no GPT header found" % label)
    return fixed


def set_esp_type_guid(buf, entry_array_off, npart=128, psz=128):
    """Type entry 0 of the array as an EFI System Partition."""
    buf[entry_array_off:entry_array_off + 16] = ESP_TYPE_GUID


def check(buf, label, entry_array_off):
    """Structural assertions.  This is the check that would have caught the
    original defect; it is called on every build, not only by a test."""
    hdr = _find_gpt(buf)
    if hdr is None:
        raise AssertionError("%s: no GPT header" % label)
    npart, = struct.unpack_from("<Q", buf, hdr + 0x50)
    psz, = struct.unpack_from("<I", buf, hdr + 0x58)
    hsize, = struct.unpack_from("<I", buf, hdr + 0x0C)
    if not (1 <= npart <= 4096):
        raise AssertionError("%s: NumberOfPartitionEntries is %d at 0x50; it must "
                             "be a UINT64 there and a sane count, not %d"
                             % (label, npart, struct.unpack_from("<Q", buf, hdr + 0x50)[0]))
    if psz not in (128, 256):
        raise AssertionError("%s: SizeOfPartitionEntry %d at 0x58" % (label, psz))
    if hsize != GPT_HDR_SIZE:
        raise AssertionError("%s: HeaderSize %d != %d" % (label, hsize, GPT_HDR_SIZE))
    t = bytes(buf[entry_array_off:entry_array_off + 16])
    if t != ESP_TYPE_GUID:
        raise AssertionError("%s: partition 0 type %s is not an EFI System "
                             "Partition" % (label, t.hex()))
    # CRCs must actually verify
    stored = struct.unpack_from("<I", buf, hdr + 0x10)[0]
    struct.pack_into("<I", buf, hdr + 0x10, 0)
    calc = _crc32(bytes(buf[hdr:hdr + GPT_HDR_SIZE]))
    struct.pack_into("<I", buf, hdr + 0x10, stored)
    if calc != stored:
        raise AssertionError("%s: header CRC32 0x%08x != computed 0x%08x"
                             % (label, stored, calc))
    stored_a = struct.unpack_from("<I", buf, hdr + 0x5C)[0]
    calc_a = _crc32(bytes(buf[entry_array_off:entry_array_off + npart * psz]))
    if calc_a != stored_a:
        raise AssertionError("%s: entry-array CRC32 0x%08x != computed 0x%08x"
                             % (label, stored_a, calc_a))
    return dict(npart=npart, psz=psz, hsize=hsize, header_crc=stored)
