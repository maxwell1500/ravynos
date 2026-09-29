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

# Fixed timestamp for deterministic builds: 2026-01-01 00:00:00
_FTIME = 0
_FDATE = ((2026 - 1980) << 9) | (1 << 5) | 1

_OK83 = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$%'-@~`(){!}#&^")


# ---------------------------------------------------------------- read side

class Fat32Img:
    """Random-access reader over a raw GPT+FAT32 image."""

    def __init__(self, path):
        self.f = open(path, "rb")

    def close(self):
        self.f.close()

    def fat(self, clus):
        self.f.seek(FAT1_OFF + clus * 4)
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
            self.f.seek(DATA_OFF + (c - 2) * CL)
            buf += self.f.read(CL)
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

    def __init__(self, head_path, tail_path, out_path, volume="RAVYNOS"):
        with open(head_path, "rb") as f:
            self.head = f.read()
        with open(tail_path, "rb") as f:
            self.tail = f.read()
        assert len(self.head) == HEAD_BYTES, "head size %d" % len(self.head)
        assert len(self.tail) == TAIL_BYTES, "tail size %d" % len(self.tail)
        self.out = out_path
        self.volume = volume
        self.root = Node("/", True)
        self._next = 3            # cluster 2 is the root dir, pinned
        self._fat = {2: 0x0FFFFFFF}

    def alloc(self, n):
        if n == 0:
            return 0
        start = self._next
        if start + n - 1 > MAX_CLUSTER:
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
        if _entries_size(self.root, True) > CL:
            raise RuntimeError("root dir needs > 1 cluster")

        def alloc_dirs(node):
            for ch in node.children:
                if ch.is_dir:
                    n = max(1, (_entries_size(ch, False) + CL - 1) // CL)
                    ch.clus = self.alloc(n)
                    ch.nclus = n
                    alloc_dirs(ch)
        alloc_dirs(self.root)

        def alloc_files(node):
            for ch in node.children:
                if ch.is_dir:
                    alloc_files(ch)
                elif ch.data:
                    ch.nclus = (len(ch.data) + CL - 1) // CL
                    ch.clus = self.alloc(ch.nclus)
        alloc_files(self.root)

        # Emit -----------------------------------------------------------------
        with open(self.out, "wb") as f:
            f.write(self.head)
            f.truncate(IMAGE_BYTES)
            f.seek(0, 2)
            # FATs: zeroed, media descriptor, chain entries in both mirrors
            for base in (FAT1_OFF, FAT2_OFF):
                f.seek(base)
                f.write(b"\x00" * SPF_BYTES)
                f.seek(base)
                f.write(struct.pack("<II", 0x0FFFFFF8, 0x0FFFFFFF))
                for c, v in self._fat.items():
                    f.seek(base + c * 4)
                    f.write(struct.pack("<I", v))
            # directory payloads
            def write_dirs(node, parent_clus, is_root):
                blob = self._dir_blob(node, parent_clus, is_root)
                need = max(1, (len(blob) + CL - 1) // CL)
                if need > node.nclus:
                    raise RuntimeError("dir %s needs %d clus has %d" % (node.name, need, node.nclus))
                f.seek(DATA_OFF + (node.clus - 2) * CL)
                f.write(blob.ljust(node.nclus * CL, b"\x00"))
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
                        f.seek(DATA_OFF + (ch.clus - 2) * CL)
                        f.write(ch.data.ljust(ch.nclus * CL, b"\x00"))
            write_files(self.root)
            # backup GPT tail
            f.seek(IMAGE_BYTES - TAIL_BYTES)
            f.write(self.tail)
            # FSInfo free count / next free (LBA1 of partition = PART_OFF+512)
            f.seek(PART_OFF + 512 + 488)
            f.write(struct.pack("<II",
                                (MAX_CLUSTER - (self._next - 2)) & 0x0FFFFFFF,
                                self._next))

    def payload_clusters(self):
        return self._next - 2

    def verify(self):
        """Reopen the built image and return a Fat32Img for tree walking."""
        return Fat32Img(self.out)
