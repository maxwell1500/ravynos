#!/usr/bin/env python3
"""FAT32 image library for ravynOS boot lab.

Read side: open an existing raw image (GPT + single FAT32 partition at LBA 2048),
walk directories (LFN-aware), read files by cluster chain.

Write side: ImageBuilder creates a fresh image from a committed head/tail template
(protective MBR + GPT + BPB/FSInfo reserved region copied verbatim from the proven
golden disk), then lays out a directory tree with LFN + 8.3 short names.

Layout constants (golden image, BPB at byte 0x100000):
  spc=8  res=32 fats=2 spf=1018  cluster=4096
  fat1=0x104000  fat2=0x183400  data=0x202800
  130301 clusters usable, image = 512 MiB, backup GPT in last 34 sectors.
"""
import struct
from collections import namedtuple

PART_OFF = 0x100000          # start of FAT32 partition (LBA 2048)
FAT1_OFF = 0x104000
FAT2_OFF = 0x183400
DATA_OFF = 0x202800          # cluster 2 lives here
CL = 4096
IMAGE_BYTES = 512 * 1024 * 1024
SPF_BYTES = 1018 * 512       # one FAT
MAX_CLUSTER = 130301         # last usable cluster
HEAD_BYTES = DATA_OFF        # template head: 0 .. 0x202800
TAIL_BYTES = 34 * 512        # template tail: backup GPT header+entries


# ---------------------------------------------------------------- geometry
#
# Every layout number in one value object, so a grown image (mkimage
# --size-mib) is the same code path as the committed 512 MiB image instead of
# a second set of constants.  The module constants above are the DEFAULT
# geometry; geometry_for_size() reproduces them byte for byte (asserted
# immediately below), which is what keeps existing callers unchanged.

Geometry = namedtuple("Geometry", (
    "image_bytes part_off rsvd_sectors cl spf_sectors fat1_off fat2_off "
    "data_off max_cluster head_bytes tail_bytes disk_sectors part_first_lba "
    "part_last_lba"))

PART_FIRST_LBA = 2048
# The golden disk's partition ends 2048 sectors before the disk does (entry
# last LBA 1046527, disk 1048576 sectors): 1 MiB of unused tail.  A grown
# image keeps that shape -- partition [2048, disk-2049] -- so the 512 MiB
# result is the committed constants exactly.
PART_TAIL_SLACK = 4096       # sectors: 2048 before + 2048 after the partition

_GPT_HDR_SIZE = 92           # UEFI HeaderSize for the v1.0 header
_GPT_ENT_LEN = 128 * 128     # 128 entries x 128 bytes


def geometry_for_size(total_bytes):
    """Geometry of a FAT32 image of exactly total_bytes.

    spf_sectors is the smallest FAT whose entries cover every cluster the
    partition yields: fat entries = spf*512/4 = spf*128, data clusters =
    (part_sectors - rsvd - 2*spf)//8.  The start value is the analytic
    solution, so the loops run a step or two for any size.
    """
    disk_sectors = total_bytes // 512
    part_sectors = disk_sectors - PART_TAIL_SLACK
    part_last = PART_FIRST_LBA + part_sectors - 1
    part_off = PART_FIRST_LBA * 512

    def fits(s):
        mc = (part_sectors - 32 - 2 * s) // 8
        return mc >= 2 and s * 128 >= mc + 2

    s = max(1, -(-(part_sectors - 34) // 1026))
    while not fits(s):
        s += 1
    while s > 1 and fits(s - 1):
        s -= 1
    max_cluster = (part_sectors - 32 - 2 * s) // 8
    fat1_off = part_off + 32 * 512
    fat2_off = fat1_off + s * 512
    data_off = fat2_off + s * 512
    assert data_off + max_cluster * 4096 <= (part_last + 1) * 512, \
        "cluster data overruns the partition"
    return Geometry(total_bytes, part_off, 32, 4096, s, fat1_off, fat2_off,
                    data_off, max_cluster, data_off, TAIL_BYTES, disk_sectors,
                    PART_FIRST_LBA, part_last)


DEFAULT_GEOM = geometry_for_size(IMAGE_BYTES)
assert (DEFAULT_GEOM.spf_sectors, DEFAULT_GEOM.fat1_off, DEFAULT_GEOM.fat2_off,
        DEFAULT_GEOM.data_off, DEFAULT_GEOM.max_cluster,
        DEFAULT_GEOM.part_last_lba) == \
    (1018, FAT1_OFF, FAT2_OFF, DATA_OFF, MAX_CLUSTER, 1046527), \
    "geometry_for_size no longer reproduces the golden 512 MiB constants"


def synth_templates(geom, base_head, base_tail):
    """head/tail template pair for a grown image.

    Copies of the committed templates with only the size fields and the two
    GPT CRCs changed: everything else in the firmware-visible geometry stays
    golden.  Offsets are taken from the golden bytes (verified by dump):
    primary GPT header 0x200 (altLBA +0x20, lastLBA +0x30, array CRC +0x58,
    header CRC +0x10), primary entry array 0x400, BPB at the partition start
    (totsec32 +0x20, fatsz32 +0x24), tail entry array +0x200, backup header
    +0x4200 (myLBA +0x18, altLBA +0x20, firstLBA +0x28, lastLBA +0x30,
    entryLBA +0x48).  The non-spec quirk fields at header +0x50/+0x54 are
    deliberately left alone -- the Apple boot.efi path depends on them.
    """
    assert len(base_head) == HEAD_BYTES and len(base_tail) == TAIL_BYTES
    disk_last = geom.disk_sectors - 1
    part_sectors = geom.part_last_lba - geom.part_first_lba + 1
    head = bytearray(base_head[:0x104000] +
                     b"\0" * (geom.data_off - 0x104000))
    tail = bytearray(base_tail)
    HDR, ENT, BHDR, BENT = 0x200, 0x400, 0x4200, 0x200

    struct.pack_into("<I", head, 0x1BE + 12, disk_last)       # MBR sectors
    struct.pack_into("<Q", head, HDR + 0x20, disk_last)       # altLBA
    struct.pack_into("<Q", head, HDR + 0x30, geom.part_last_lba)   # lastLBA
    struct.pack_into("<Q", head, ENT + 0x28, geom.part_last_lba)   # entry0
    struct.pack_into("<I", head, geom.part_off + 0x20, part_sectors)  # BPB
    struct.pack_into("<I", head, geom.part_off + 0x24, geom.spf_sectors)
    struct.pack_into("<Q", tail, BENT + 0x28, geom.part_last_lba)
    struct.pack_into("<Q", tail, BHDR + 0x18, disk_last)      # MyLBA
    struct.pack_into("<Q", tail, BHDR + 0x20, 1)              # altLBA
    struct.pack_into("<Q", tail, BHDR + 0x28, geom.part_first_lba)
    struct.pack_into("<Q", tail, BHDR + 0x30, geom.part_last_lba)
    struct.pack_into("<Q", tail, BHDR + 0x48, geom.disk_sectors - 33)

    arr_crc = _crc32(head[ENT:ENT + _GPT_ENT_LEN])
    struct.pack_into("<I", head, HDR + 0x58, arr_crc)
    struct.pack_into("<I", tail, BHDR + 0x58, arr_crc)
    for buf, off in ((head, HDR), (tail, BHDR)):
        struct.pack_into("<I", buf, off + 0x10, 0)
        struct.pack_into("<I", buf, off + 0x10,
                         _crc32(buf[off:off + _GPT_HDR_SIZE]))
    # read back what was written, and cross-check the two CRCs
    assert struct.unpack_from("<I", head, 0x1BE + 12)[0] == disk_last
    assert struct.unpack_from("<Q", head, HDR + 0x20)[0] == disk_last
    assert struct.unpack_from("<Q", head, HDR + 0x30)[0] == geom.part_last_lba
    assert struct.unpack_from("<I", head, geom.part_off + 0x20)[0] == part_sectors
    assert struct.unpack_from("<I", head, geom.part_off + 0x24)[0] == geom.spf_sectors
    assert struct.unpack_from("<Q", head, ENT + 0x28)[0] == geom.part_last_lba
    assert struct.unpack_from("<I", head, HDR + 0x58)[0] == arr_crc
    assert struct.unpack_from("<I", tail, BENT + 0x28)[0] == geom.part_last_lba
    assert struct.unpack_from("<Q", tail, BHDR + 0x18)[0] == disk_last
    assert struct.unpack_from("<Q", tail, BHDR + 0x20)[0] == 1
    assert struct.unpack_from("<Q", tail, BHDR + 0x28)[0] == geom.part_first_lba
    assert struct.unpack_from("<Q", tail, BHDR + 0x30)[0] == geom.part_last_lba
    assert struct.unpack_from("<Q", tail, BHDR + 0x48)[0] == geom.disk_sectors - 33
    assert struct.unpack_from("<I", tail, BHDR + 0x58)[0] == arr_crc
    from gpt_conform import _crc32 as _spec_crc32   # same polynomial, slow ref
    assert _spec_crc32(bytes(head[HDR:HDR + _GPT_HDR_SIZE])) == \
        _crc32(head[HDR:HDR + _GPT_HDR_SIZE])
    return bytes(head), bytes(tail)


def _crc32(data):
    """UEFI GPT CRC-32 (IEEE 802.3, the usual reflected polynomial)."""
    import zlib
    return zlib.crc32(bytes(data)) & 0xffffffff

# Fixed timestamp for deterministic builds: 2026-01-01 00:00:00
_FTIME = 0
_FDATE = ((2026 - 1980) << 9) | (1 << 5) | 1

_OK83 = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$%'-@~`(){!}#&^")


# ---------------------------------------------------------------- read side

class Fat32Img:
    """Random-access reader over a raw GPT+FAT32 image."""

    def __init__(self, path, geom=None):
        self.geom = geom or DEFAULT_GEOM
        self.f = open(path, "rb")

    def close(self):
        self.f.close()

    def fat(self, clus):
        self.f.seek(self.geom.fat1_off + clus * 4)
        return struct.unpack("<I", self.f.read(4))[0] & 0x0FFFFFFF

    def chain(self, start):
        ch, c, seen = [], start, set()
        while 2 <= c < 0x0FFFFFF8:
            if c in seen:
                raise RuntimeError("FAT chain loop at cluster %d" % c)
            seen.add(c)
            ch.append(c)
            c = self.fat(c)
        return ch

    def read_clusters(self, start, size=0):
        buf = b""
        for c in self.chain(start):
            self.f.seek(self.geom.data_off + (c - 2) * self.geom.cl)
            buf += self.f.read(self.geom.cl)
        return buf[:size] if size else buf

    def listdir(self, start_clus):
        """Return [(long_name_or_None, short_name, start_cluster, size, is_dir)]."""
        data = self.read_clusters(start_clus)
        out, lfn = [], []
        for i in range(0, len(data) - 31, 32):
            e = data[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5:
                continue
            attr = e[11]
            if attr == 0x08:                      # volume label
                lfn = []
                continue
            if attr == 0x0F:                      # long-name fragment
                lfn.append(e)
                continue
            start = (struct.unpack_from("<H", e, 20)[0] << 16) | struct.unpack_from("<H", e, 26)[0]
            size = struct.unpack_from("<I", e, 28)[0]
            s8 = e[0:8].rstrip(b" \x00").decode("ascii", "ignore")
            sx = e[8:11].rstrip(b" \x00").decode("ascii", "ignore")
            short = s8 + ("." + sx if sx else "")
            long = None
            if lfn:
                chars = b""
                for le in sorted(lfn, key=lambda x: x[0] & 0x3F):
                    chars += le[1:11] + le[14:26] + le[28:32]
                long = chars.decode("utf-16-le", "ignore").split("\x00")[0]
                lfn = []
            if short in (".", ".."):
                lfn = []
                continue
            out.append((long, short, start, size, bool(attr & 0x10)))
        return out

    def _find(self, entries, part):
        for ent in entries:
            cand = ent[0] if ent[0] else ent[1]
            if cand.lower() == part.lower():
                return ent
        return None

    def path_lookup(self, path):
        """Resolve '/'-separated path from root; returns entry tuple or None."""
        cur = self.listdir(2)
        parts = [p for p in path.strip("/").split("/") if p]
        hit = None
        for i, part in enumerate(parts):
            hit = self._find(cur, part)
            if hit is None:
                return None
            if i + 1 < len(parts):
                if not hit[4]:
                    return None
                cur = self.listdir(hit[2])
        return hit

    def read_path(self, path):
        ent = self.path_lookup(path)
        if ent is None or ent[4]:
            return None
        return self.read_clusters(ent[2], ent[3])

    def walk(self, prefix="", start=2, out=None):
        if out is None:
            out = []
        for long, short, clus, size, is_dir in self.listdir(start):
            name = long if long else short
            out.append((prefix + name, clus, size, is_dir))
            if is_dir:
                self.walk(prefix + name + "/", clus, out)
        return out


# --------------------------------------------------------------- entry build

def _gen83(name, used):
    """Unique 8.3 (stem, ext) pair for `name` inside one directory.

    Collision suffixes must fit the 8-char stem field: slice-assigning a
    9-char stem into a bytearray(32) EXTENDS the entry to 33 bytes and
    silently corrupts the whole directory (n>=10 collisions). Truncate the
    stem to make room for `~n`."""
    up = name.upper()
    if "." in up:
        stem, ext = up.rsplit(".", 1)
    else:
        stem, ext = up, ""
    clean = lambda s: "".join(c if c in _OK83 else "_" for c in s)
    ext = clean(ext)[:3]
    stem = clean(stem)
    if stem and len(stem) <= 8 and (stem, ext) not in used:
        used.add((stem, ext))
        return stem, ext
    n = 1
    while True:
        suffix = "~%d" % n
        base = (stem[:8 - len(suffix)] or "FILE") + suffix
        if (base, ext) not in used:
            used.add((base, ext))
            return base, ext
        n += 1


def _lfn_checksum(short_entry):
    s = 0
    for b in short_entry[0:11]:
        s = ((s >> 1) + ((s & 1) << 7) + b) & 0xFF
    return s


def _lfn_entries(long, chk):
    """Long-name entries in on-disk order (highest sequence first)."""
    padded = long + "\x00"
    nchunks = max(1, (len(padded) + 12) // 13)
    ents = []
    for i in range(nchunks):
        chunk = (padded[i * 13:(i + 1) * 13]).ljust(13, "\uFFFF")
        e = bytearray(32)
        e[0] = (i + 1) | (0x40 if i == nchunks - 1 else 0)
        e[11] = 0x0F                       # attr: LFN
        e[13] = chk                       # checksum (MS spec byte 13)
        e[14] = 0x00                      # Unicode name start flag (reserved)
        for idx, off in ((0, 1), (1, 3), (2, 5), (3, 7), (4, 9),
                         (5, 14), (6, 16), (7, 18), (8, 20), (9, 22), (10, 24),
                         (11, 28), (12, 30)):
            struct.pack_into("<H", e, off, ord(chunk[idx]))
        ents.append(bytes(e))
    return list(reversed(ents))


def dir_entries(name, start_clus, size, is_dir, used):
    """On-disk 32-byte entries (LFN group + short entry) for one item."""
    stem, ext = _gen83(name, used)
    e = bytearray(32)
    e[0:8] = stem.ljust(8, " ").encode("ascii")
    e[8:11] = ext.ljust(3, " ").encode("ascii")
    e[11] = 0x10 if is_dir else 0x20
    e[20:22] = struct.pack("<H", (start_clus >> 16) & 0xFFFF)
    e[26:28] = struct.pack("<H", start_clus & 0xFFFF)
    e[28:32] = struct.pack("<I", size)
    e[16:18] = e[22:24] = struct.pack("<H", _FTIME)
    e[18:20] = e[24:26] = struct.pack("<H", _FDATE)
    return _lfn_entries(name, _lfn_checksum(bytes(e))) + [bytes(e)]


def _dot(name_bytes, clus):
    e = bytearray(32)
    e[0:8] = name_bytes.ljust(8, b" ")
    e[11] = 0x10
    e[20:22] = struct.pack("<H", (clus >> 16) & 0xFFFF)
    e[26:28] = struct.pack("<H", clus & 0xFFFF)
    e[16:18] = e[22:24] = struct.pack("<H", _FTIME)
    e[18:20] = e[24:26] = struct.pack("<H", _FDATE)
    return bytes(e)


# --------------------------------------------------------------- write side

class Node:
    def __init__(self, name, is_dir, data=b""):
        self.name = name
        self.is_dir = is_dir
        self.data = data
        self.children = [] if is_dir else None
        self.clus = 0
        self.nclus = 0


def _entries_size(node, is_root):
    """Bytes of directory data `node` itself stores (own . / .. + children)."""
    n = 0 if is_root else 2                       # . and ..
    if is_root:
        n += 1                                    # volume label
    used = set()
    for ch in node.children:
        n += len(dir_entries(ch.name, 0, 0, ch.is_dir, used))
    return n * 32


class ImageBuilder:
    """Build a fresh boot image from committed head/tail + a manifest tree."""

    def __init__(self, head_path, tail_path, out_path, volume="RAVYNOS",
                 geom=None):
        with open(head_path, "rb") as f:
            self.head = f.read()
        with open(tail_path, "rb") as f:
            self.tail = f.read()
        self.geom = geom or DEFAULT_GEOM
        assert len(self.head) == self.geom.head_bytes, \
            "head size %d" % len(self.head)
        assert len(self.tail) == self.geom.tail_bytes, \
            "tail size %d" % len(self.tail)
        self.out = out_path
        self.volume = volume
        self.root = Node("/", True)
        self._next = 3            # cluster 2 is the root dir, pinned
        self._fat = {2: 0x0FFFFFFF}

    def alloc(self, n):
        if n == 0:
            return 0
        start = self._next
        if start + n - 1 > self.geom.max_cluster:
            raise RuntimeError("image full")
        for i in range(n - 1):
            self._fat[start + i] = start + i + 1
        self._fat[start + n - 1] = 0x0FFFFFFF
        self._next += n
        return start

    def mkdir(self, path):
        node = self.root
        for part in [p for p in path.strip("/").split("/") if p]:
            for ch in node.children:
                if ch.name.lower() == part.lower():
                    node = ch
                    break
            else:
                n = Node(part, True)
                node.children.append(n)
                node = n
        return node

    def add(self, path, data):
        segs = path.strip("/").split("/")
        name = segs[-1]
        parent = self.mkdir("/" + "/".join(segs[:-1])) if len(segs) > 1 else self.root
        for ch in parent.children:
            if ch.name.lower() == name.lower():
                ch.data = data
                return ch
        n = Node(name, False, data)
        parent.children.append(n)
        return n

    # -- layout ------------------------------------------------------------

    def _dir_blob(self, node, parent_clus, is_root):
        used = set()
        items = []
        if is_root:
            lab = bytearray(32)
            lab[0:11] = self.volume.ljust(11, " ").encode("ascii")
            lab[11] = 0x08
            lab[16:18] = lab[22:24] = struct.pack("<H", _FTIME)
            lab[18:20] = lab[24:26] = struct.pack("<H", _FDATE)
            items.append(bytes(lab))
        items.append(_dot(b".", node.clus))
        items.append(_dot(b"..", parent_clus))
        for ch in node.children:
            size = 0 if ch.is_dir else len(ch.data)
            items += dir_entries(ch.name, ch.clus, size, ch.is_dir, used)
        return b"".join(items)

    def build(self):
        # Directory entry byte size does not depend on child cluster values
        # (fixed-width fields), so dirs first, then files, is safe.
        self.root.clus, self.root.nclus = 2, 1
        if _entries_size(self.root, True) > self.geom.cl:
            raise RuntimeError("root dir needs > 1 cluster")

        def alloc_dirs(node):
            for ch in node.children:
                if ch.is_dir:
                    n = max(1, (_entries_size(ch, False) + self.geom.cl - 1)
                            // self.geom.cl)
                    ch.clus = self.alloc(n)
                    ch.nclus = n
                    alloc_dirs(ch)
        alloc_dirs(self.root)

        def alloc_files(node):
            for ch in node.children:
                if ch.is_dir:
                    alloc_files(ch)
                elif ch.data:
                    ch.nclus = (len(ch.data) + self.geom.cl - 1) // self.geom.cl
                    ch.clus = self.alloc(ch.nclus)
        alloc_files(self.root)

        # Emit -----------------------------------------------------------------
        with open(self.out, "wb") as f:
            f.write(self.head)
            f.truncate(self.geom.image_bytes)
            f.seek(0, 2)
            # FATs: zeroed, media descriptor, chain entries in both mirrors
            for base in (self.geom.fat1_off, self.geom.fat2_off):
                f.seek(base)
                f.write(b"\x00" * self.geom.spf_sectors * 512)
                f.seek(base)
                f.write(struct.pack("<II", 0x0FFFFFF8, 0x0FFFFFFF))
                for c, v in self._fat.items():
                    f.seek(base + c * 4)
                    f.write(struct.pack("<I", v))
            # directory payloads
            def write_dirs(node, parent_clus, is_root):
                blob = self._dir_blob(node, parent_clus, is_root)
                need = max(1, (len(blob) + self.geom.cl - 1) // self.geom.cl)
                if need > node.nclus:
                    raise RuntimeError("dir %s needs %d clus has %d" % (node.name, need, node.nclus))
                f.seek(self.geom.data_off + (node.clus - 2) * self.geom.cl)
                f.write(blob.ljust(node.nclus * self.geom.cl, b"\x00"))
                for ch in node.children:
                    if ch.is_dir:
                        write_dirs(ch, node.clus, False)
            write_dirs(self.root, 2, True)
            # file payloads
            def write_files(node):
                for ch in node.children:
                    if ch.is_dir:
                        write_files(ch)
                    elif ch.data:
                        f.seek(self.geom.data_off + (ch.clus - 2) * self.geom.cl)
                        f.write(ch.data.ljust(ch.nclus * self.geom.cl, b"\x00"))
            write_files(self.root)
            # backup GPT tail
            f.seek(self.geom.image_bytes - self.geom.tail_bytes)
            f.write(self.tail)
            # FSInfo free count / next free (LBA1 of partition)
            f.seek(self.geom.part_off + 512 + 488)
            f.write(struct.pack("<II",
                                (self.geom.max_cluster - (self._next - 2)) & 0x0FFFFFFF,
                                self._next))

    def payload_clusters(self):
        return self._next - 2

    def verify(self):
        """Reopen the built image and return a Fat32Img for tree walking."""
        return Fat32Img(self.out, geom=self.geom)
