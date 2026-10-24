#!/usr/bin/env python3
"""Replace/add staged files inside an existing boot image, in place.

Between staging runs only the generated closure layer changes -- same staged
paths, different dylib bytes, occasionally a new path -- so rewriting files
inside the FAT32 volume (seconds) replaces re-running mkimage over a grown
image (tens of minutes).  Geometry is read off the image's own BPB and
asserted equal to fat32img.geometry_for_size; both FAT copies stay in sync;
cluster chains are extended with free clusters when content grows and trimmed
when it shrinks; brand-new paths get directory entries built by fat32img.dir_entries
(so the 8.3 + LFN layout matches what mkimage would have written).  Every
touched file is then read back through Fat32Img.read_path and compared
byte-for-byte, which doubles as the self-verify of this edit.

usage: shimpatch.py [--dry] [--img PATH] [--tree DIR]
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fat32img as F

HERE = os.path.dirname(os.path.abspath(__file__))
# FAT32 reserves 0x0FFFFFF8-0x0FFFFFFF as end-of-chain markers; fat32img.ImageBuilder
# writes 0x0FFFFFFF, so use the same value or the reader would walk past the chain.
EOF_MARK = 0x0FFFFFFF


def bpb_from_image(path):
    """FAT32 layout fields straight off the boot sector at PART_OFF."""
    part_off = F.PART_FIRST_LBA * 512
    with open(path, "rb") as f:
        f.seek(part_off)
        b = f.read(62)
    d = dict(part_off=part_off,
             bytes_per_sec=struct.unpack_from("<H", b, 0x0B)[0],
             spc=b[0x0D],
             rsvd=struct.unpack_from("<H", b, 0x0E)[0],
             nfats=struct.unpack_from("<I", b, 0x10)[0],
             totsec32=struct.unpack_from("<I", b, 0x20)[0],
             fatsz=struct.unpack_from("<I", b, 0x24)[0],
             rootclus=struct.unpack_from("<H", b, 0x2C)[0])
    d["fat1_off"] = part_off + d["rsvd"] * 512
    d["fat2_off"] = d["fat1_off"] + d["fatsz"] * 512
    d["data_off"] = d["fat1_off"] + d["nfats"] * d["fatsz"] * 512
    return d


class Img:
    """Writable image handle with a cached FAT1 buffer and free-cluster list."""

    def __init__(self, path, geom):
        self.g = geom
        self.cl = geom.cl
        self.f = open(path, "r+b")
        self.f.seek(geom.fat1_off)
        self.fat = bytearray(self.f.read(geom.spf_sectors * 512))
        self.free = []

    def close(self):
        self.f.seek(self.g.fat2_off)
        self.f.write(bytes(self.fat))
        self.f.seek(self.g.fat1_off)
        self.f.write(bytes(self.fat))
        self.f.flush()
        self.f.close()

    def fat_get(self, c):
        return struct.unpack_from("<I", self.fat, c * 4)[0] & 0x0FFFFFFF

    def fat_set(self, c, val):
        hi = struct.unpack_from("<I", self.fat, c * 4)[0] & 0xF0000000
        struct.pack_into("<I", self.fat, c * 4, hi | val)

    def chain(self, start):
        """Cluster chain with a loop guard -- an interrupted earlier run can
        leave aliased/cyclic FAT entries; looping here would hang forever."""
        ch, c, seen = [], start, set()
        while 2 <= c < 0x0FFFFFF8:
            if c in seen:
                raise RuntimeError("FAT chain loop at cluster %d" % c)
            seen.add(c)
            ch.append(c)
            c = self.fat_get(c)
        return ch

    def data_off_of(self, c):
        return self.g.data_off + (c - 2) * self.cl

    def read_clusters(self, clus_list_or_start, size=0, is_chain=False):
        ch = clus_list_or_start if is_chain else self.chain(clus_list_or_start)
        buf = b""
        for c in ch:
            self.f.seek(self.data_off_of(c))
            buf += self.f.read(self.cl)
        return buf[:size] if size else buf

    def write_clusters(self, chain, data, zero_tail=True):
        for i, c in enumerate(chain):
            chunk = data[i * self.cl:(i + 1) * self.cl]
            self.f.seek(self.data_off_of(c))
            self.f.write(chunk)
            if len(chunk) < self.cl and zero_tail:
                self.f.write(b"\0" * (self.cl - len(chunk)))

    def alloc(self, n):
        ch = self.free[:n]
        del self.free[:n]
        for i in range(n - 1):
            self.fat_set(ch[i], ch[i + 1])
        self.fat_set(ch[-1], EOF_MARK)
        return ch

    # ---- directory handling -------------------------------------------------
    def dir_blob(self, dstart):
        return self.read_clusters(dstart)

    def find_entry_index(self, blob, name):
        """Index of the entry whose displayed name == `name` (LFN-aware)."""
        want = name.lower()
        lfn = []
        for i in range(0, len(blob) - 31, 32):
            e = blob[i:i + 32]
            if e[0] == 0:
                break
            attr = e[11]
            if attr == 0x08:
                lfn = []
                continue
            if attr == 0x0F:
                lfn.append(e)
                continue
            if e[0] == 0xE5:
                lfn = []
                continue
            long = None
            if lfn:
                chars = b""
                for le in sorted(lfn, key=lambda x: x[0] & 0x3F):
                    chars += le[1:11] + le[14:26] + le[28:32]
                long = chars.decode("utf-16-le", "ignore").split("\x00")[0]
            lfn = []
            s8 = e[0:8].rstrip(b" \x00").decode("ascii", "ignore")
            sx = e[8:11].rstrip(b" \x00").decode("ascii", "ignore")
            if (long or s8 + ("." + sx if sx else "")).lower() == want:
                return i
        return None

    def short_used(self, blob):
        used = set()
        for i in range(0, len(blob) - 31, 32):
            e = blob[i:i + 32]
            if e[0] in (0x00, 0xE5) or (e[11] & 0x0F) == 0x0F or e[11] == 0x08:
                continue
            used.add((e[0:8].decode("ascii", "ignore").rstrip(" "),
                      e[8:11].decode("ascii", "ignore").rstrip(" ")))
        return used

    def free_slot(self, blob, need):
        run, start = 0, None
        for i in range(0, len(blob) - 31, 32):
            if blob[i] in (0x00, 0xE5):
                if run == 0:
                    start = i
                run += 1
                if run >= need:
                    return start
            else:
                run = 0
        return None

    def dir_child_cluster(self, dstart, name):
        blob = self.dir_blob(dstart)
        i = self.find_entry_index(blob, name)
        if i is None:
            raise LookupError("no child %r at cluster %d" % (name, dstart))
        e = blob[i:i + 32]
        return (struct.unpack_from("<H", e, 20)[0] << 16) | struct.unpack_from("<H", e, 26)[0]

    def set_entry_size(self, dstart, name, newsize):
        blob = bytearray(self.dir_blob(dstart))
        i = self.find_entry_index(blob, name)
        if i is None:
            raise LookupError("no dir entry %r at cluster %d" % (name, dstart))
        struct.pack_into("<I", blob, i + 28, newsize)
        self.write_clusters(self.chain(dstart), bytes(blob), zero_tail=False)
        return i

    def create_file(self, dstart, name, data):
        """Add a brand-new file to the directory at `dstart`."""
        chain = self.chain(dstart)
        blob = bytearray(self.dir_blob(dstart))
        entries = F.dir_entries(name, 0, len(data), False, self.short_used(blob))
        slot = self.free_slot(blob, len(entries))
        while slot is None:                      # dir needs more clusters
            extra = self.alloc(1)
            self.fat_set(chain[-1], extra)
            chain.append(extra)
            blob += b"\0" * self.cl
            slot = self.free_slot(blob, len(entries))
        newclus = self.alloc((len(data) + self.cl - 1) // self.cl or 1)
        start = newclus[0]
        patched = b""
        for e in entries:
            ee = bytearray(e)
            if (ee[11] & 0x0F) != 0x0F and ee[11] == 0x20:      # short entry
                struct.pack_into("<H", ee, 20, (start >> 16) & 0xFFFF)
                struct.pack_into("<H", ee, 26, start & 0xFFFF)
            patched += bytes(ee)
        blob[slot:slot + len(entries) * 32] = patched
        self.write_clusters(chain, bytes(blob), zero_tail=False)
        self.write_clusters(self.chain(start), data, zero_tail=True)
        return start


def main(argv):
    dry = "--dry" in argv
    img = os.path.join(HERE, "work/boot.img")
    tree = os.path.join(HERE, "work/chrome-shims")
    for i, a in enumerate(argv):
        if a == "--img":
            img = argv[i + 1]
        elif a == "--tree":
            tree = os.path.join(HERE, argv[i + 1]) if not argv[i + 1].startswith("/") else argv[i + 1]

    b0 = bpb_from_image(img)
    g = F.geometry_for_size(os.path.getsize(img))   # size the image actually is
    print("BPB: part_off=0x%x rsvd=%d spc=%d nfats=%d fatsz=%d rootclus=%d "
          "-> fat1=0x%x fat2=0x%x data_off=0x%x" % (b0["part_off"], b0["rsvd"],
                                                    b0["spc"], b0["nfats"], b0["fatsz"],
                                                    b0["rootclus"], b0["fat1_off"],
                                                    b0["fat2_off"], b0["data_off"]))
    print("geometry_for_size(2GiB): fat1=0x%x fat2=0x%x data_off=0x%x max_cluster=%d cl=%d"
          % (g.fat1_off, g.fat2_off, g.data_off, g.max_cluster, g.cl))
    if not (b0["fat1_off"] == g.fat1_off and b0["fat2_off"] == g.fat2_off
            and b0["data_off"] == g.data_off and b0["spc"] * 512 == g.cl
            and b0["nfats"] == 2 and b0["rootclus"] == 2):
        print("MISMATCH: image geometry is not geometry_for_size(2 GiB) -- abort")
        return 2

    want = {}
    for dp, dn, fn in os.walk(tree):
        dn.sort()
        for nm in sorted(fn):
            fp = os.path.join(dp, nm)
            want[os.path.relpath(fp, tree).replace(os.sep, "/")] = fp
    print("tree files: %d" % len(want))

    # A crashed or interrupted earlier run can leave a directory entry whose
    # start cluster has a zero FAT entry (an unlinked orphan).  Treat every
    # cluster that any directory entry names as claimed so the free list never
    # hands such a cluster to a second file.
    rd0 = F.Fat32Img(img, geom=g)
    claimed = {e[1] for e in rd0.walk("", 2)}
    rd0.close()
    w = Img(img, g)
    w.free = [c for c in range(2, g.max_cluster + 1)
              if w.fat_get(c) == 0 and c not in claimed]
    print("free clusters: %d of %d" % (len(w.free), g.max_cluster - 1))

    touched, grew, shrank, created = [], 0, 0, 0
    for rel, fp in sorted(want.items()):
        newbytes = open(fp, "rb").read()
        parts = rel.split("/")
        dstart = 2
        missing_dir = False
        for p in parts[:-1]:
            try:
                dstart = w.dir_child_cluster(dstart, p)
            except LookupError:
                missing_dir = True
                break
        if missing_dir:
            print("MISSING PARENT DIR (unsupported here): %s" % rel)
            return 4
        blob = w.dir_blob(dstart)
        i = w.find_entry_index(blob, parts[-1])
        if i is None:
            print("NEW FILE: %-70s (%d bytes)" % (rel, len(newbytes)))
            created += 1
            touched.append((rel, fp))
            if not dry:
                w.create_file(dstart, parts[-1], newbytes)
            continue
        e = blob[i:i + 32]
        start = (struct.unpack_from("<H", e, 20)[0] << 16) | struct.unpack_from("<H", e, 26)[0]
        oldsize = struct.unpack_from("<I", e, 28)[0]
        if w.read_clusters(start, oldsize) == newbytes:
            continue
        chain = w.chain(start)
        need = (len(newbytes) + g.cl - 1) // g.cl
        print("patch %-70s %8d -> %8d clusters %4d -> %4d"
              % (rel, oldsize, len(newbytes), len(chain), need))
        touched.append((rel, fp))
        if dry or need == len(chain):
            if not dry and need == len(chain):
                w.write_clusters(chain[:need], newbytes)
                if oldsize != len(newbytes):
                    w.set_entry_size(dstart, parts[-1], len(newbytes))
            continue
        if need > len(chain):
            grew += 1
            extra = w.alloc(need - len(chain))
            w.fat_set(chain[-1], extra[0])
            chain = chain + extra
            w.write_clusters(extra, b"")           # data written below
        elif need < len(chain):
            shrank += 1
            for c in chain[need:]:
                w.fat_set(c, 0)
            if need:
                w.fat_set(chain[need - 1], EOF_MARK)
        if need:
            w.write_clusters(chain[:need], newbytes)
        else:
            w.fat_set(start, EOF_MARK)
        w.set_entry_size(dstart, parts[-1], len(newbytes))

    print("touched %d files (%d grew, %d shrank, %d created)"
          % (len(touched), grew, shrank, created))
    w.close()
    if dry:
        return 0

    rd = F.Fat32Img(img, geom=g)
    bad = []
    for rel, fp in touched:
        host = open(fp, "rb").read()
        got = rd.read_path(rel)
        if got != host:
            bad.append((rel, len(host), len(got) if got is not None else None))
    collateral = []
    for probe in ("bin/sh", "usr/lib/libsystem.b.dylib",
                  "applications/google chrome.app/contents/macos/google chrome",
                  "frameworks/google chrome framework.framework/"
                  "versions/155.0.8059.82/google chrome framework"):
        try:
            b = rd.read_path(probe)
            collateral.append((probe, None if b is None else "%d bytes" % len(b)))
        except Exception as exc:
            collateral.append((probe, str(exc)))
    rd.close()
    print("read-back mismatches: %s" % (bad or "none"))
    for c0 in collateral:
        print("  collateral %-62s -> %s" % c0)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
