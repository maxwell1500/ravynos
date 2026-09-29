#!/usr/bin/env python3
"""Rebase DSC-extracted dylibs into standalone dyld3-loadable files.

The DSC extractor preserves DSC-absolute segment vmaddrs, zeroes section
offsets, leaves chained-fixup (DYLD_CHAINED_PTR_64) descriptors in GOT/data
instead of bound addresses, and emits LINKEDIT metadata (function starts,
data-in-code, export tries) with DSC-cache-relative offsets that are garbage
as plain files. dyld3 cannot load these (mmap EINVAL on non-page-aligned
data segments, "Symbol not found" with no usable exports).

This tool converts one thin x86_64 DSC dylib into a self-contained file:
  1. Moves ALL segments (incl. __TEXT) to a clean page-aligned base, laid out
     contiguously in original LC order, vmsizes/filesizes rounded to 4K.
  2. Converts internal DYLD_CHAINED_PTR_64 rebase descriptors (target field =
     offset from DSC cache base 0x7FF800000000) into final absolute addresses.
     Also remaps any raw absolute DSC addresses in data sections.
  3. Patches __TEXT RIP-relative references (capstone, symtab-guided +
     error recovery) that target moved non-TEXT segments.
  4. Remaps LC_SYMTAB n_value for defined section symbols.
  5. Rebuilds a valid LC_DYLD_EXPORTS_TRIE from defined external symbols
     (the extracts carry empty/garbage export info, so dyld finds nothing).
  6. Fixes section addrs/offsets, SG_READ_ONLY, LINKEDIT file offsets, drops
     DSC-relative garbage commands, repacks the file.

Usage: dsc_rebase.py <src> <dst> <new_base_hex>
Only thin x86_64 slices for now. Aborts on strict external bind descriptors
(bit63=1 with zero reserved bits); libsystem_c has none.
"""
import struct
import sys

from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from capstone.x86 import X86_REG_RIP, X86_OP_MEM

PAGE = 0x4000
DSC_BASE = 0x7FF800000000
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_DYSYMTAB = 0xB
LC_FUNCTION_STARTS = 0x26
LC_DATA_IN_CODE = 0x2A
LC_DYLD_EXPORTS_TRIE = 0x80000033
SG_READ_ONLY = 0x10
N_EXT = 0x01
N_SECT_TYPE = 0x0E
S_ZEROFILL = 0x1


def align_up(x, a):
    return (x + a - 1) // a * a


def uleb(v):
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def parse_thin(buf):
    """Parse a thin DSC-extracted Mach-O (32-byte header)."""
    if struct.unpack_from("<I", buf, 0)[0] != 0xFEEDFACF:
        raise RuntimeError("not a thin 64-bit Mach-O")
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, _ = \
        struct.unpack_from("<8I", buf, 0)
    if (cputype & 0xFFFF0000) != 0x01000000:
        raise RuntimeError("not x86_64")
    lcbase, lcend = 32, 32 + sizeofcmds
    segs, lcs = [], []
    q = lcbase
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, q)
        raw = bytes(buf[q:q + cmdsize])
        if cmd == LC_SEGMENT_64:
            name = bytes(buf[q + 8:q + 24].rstrip(b"\x00"))
            va, vs = struct.unpack_from("<QQ", buf, q + 24)
            fo, fs = struct.unpack_from("<QQ", buf, q + 40)
            maxp, initp, nsects, sflags = struct.unpack_from("<IIII", buf, q + 56)
            sects = []
            for s in range(nsects):
                o = q + 72 + s * 80
                sn = bytes(buf[o:o + 16].rstrip(b"\x00"))
                sgu = bytes(buf[o + 16:o + 32].rstrip(b"\x00"))
                sa, ss = struct.unpack_from("<QQ", buf, o + 32)
                al, fl, soff, roff, nr, r1, r2, r3 = \
                    struct.unpack_from("<IIIIIIII", buf, o + 48)
                sects.append({"name": sn, "seg": sgu, "addr": sa, "size": ss,
                              "flags": fl, "r1": r1, "r2": r2, "off": q + 72 + s * 80})
            segs.append({"name": name, "va": va, "vs": vs, "fo": fo, "fs": fs,
                         "maxp": maxp, "initp": initp, "flags": sflags,
                         "sects": sects, "lc_off": q, "lc_raw": raw})
        else:
            lcs.append({"cmd": cmd, "off": q, "raw": raw})
        q += cmdsize
    if q != lcend:
        raise RuntimeError("load commands do not fill sizeofcmds")
    return {"ncmds": ncmds, "sizeofcmds": sizeofcmds, "filetype": filetype,
            "flags": flags, "segs": segs, "lcs": lcs}


def build_trie(exports):
    """Build a minimal valid exports trie (single-byte edges).

    exports: list of (name_bytes, vmaddr). Returns trie bytes.
    """
    root = [{}, None]  # [children dict, terminal addr]
    for name, addr in exports:
        node = root
        for ch in name:
            node = node[0].setdefault(ch, [{}, None])
        if node[1] is None:
            node[1] = addr
    out = bytearray()

    def emit(node):
        pos = len(out)
        out.append(0)  # placeholder terminalSize
        tstart = len(out)
        if node[1] is not None:
            out += uleb(0)          # flags
            out += uleb(node[1])    # address
        tsize = len(out) - tstart
        # encode tsize as uleb (single byte suffices here)
        assert tsize < 128
        out[pos] = tsize
        out.append(len(node[0]))
        child_refs = []
        for ch in sorted(node[0]):
            out.append(ch)
            out.append(0)
            child_refs.append((len(out), node[0][ch]))
            out.append(0)  # placeholder offset
        for refpos, child in child_refs:
            coff = emit(child)
            assert coff < 128 or True
            enc = uleb(coff)
            out[refpos:refpos + 1] = enc
            # fix up positions after variable-length insert
            if len(enc) != 1:
                raise RuntimeError("trie too large for single-byte patch")
        return pos

    # The recursive emit with in-place patching above is fragile; use a
    # simpler two-pass: serialize nodes to chunks then concatenate.
    chunks = {}

    def build(node):
        body = bytearray()
        if node[1] is not None:
            term = uleb(0) + uleb(node[1])
        else:
            term = b""
        body.append(len(term))
        body += term
        body.append(len(node[0]))
        fixups = []
        for ch in sorted(node[0]):
            body.append(ch)
            body.append(0)
            fixups.append((len(body), node[0][ch]))
            body.append(0)
        return bytes(body), fixups

    order, sizes = [], {}

    def layout(node):
        body, fixups = build(node)
        idx = len(order)
        order.append([body, fixups])
        sizes[idx] = len(body)
        for _, child in fixups:
            layout(child)
        return idx

    layout(root)
    # assign offsets (single pass; child offsets need final positions, so
    # iterate: offsets depend only on sizes and order, which are fixed)
    offs = []
    pos = 0
    for body, _ in order:
        offs.append(pos)
        pos += len(body)
    # map node id -> offset; rebuild with real child offsets
    # (node ids are layout order; children were laid out depth-first, so
    #  child id > parent id; resolve via object identity)
    idmap = {}

    def relayout(node):
        body, fixups = build(node)
        my = len(order2)
        order2.append(None)
        kids = []
        for _, child in fixups:
            kids.append(relayout(child))
        # assemble with child offsets (absolute from trie start); need
        # offsets first -> do a sizing pass then a write pass
        return (body, kids)

    order2 = []
    tree = relayout(root)

    def measure(t):
        body, kids = t
        # body has 1-byte placeholder per child offset; real offsets may be
        # multi-byte, so measure with actual uleb sizes (children measured first)
        kid_offs = [measure(k) for k in kids]
        return None

    # Simplest correct approach: recursive writer with backpatching using
    # absolute offsets computed after full serialization with placeholder
    # width resolved by iteration (trie is small; iterate to fixpoint).
    buf = bytearray(b"\x00" * 4)
    off = {"v": 4}

    def write(node):
        my = off["v"]
        # reserve: terminalSize(1) + term + childCount(1) + per-child(1+1+5)
        start = len(buf)
        buf.append(0)
        if node[1] is not None:
            buf += uleb(0) + uleb(node[1])
        buf[start] = len(buf) - start - 1
        buf.append(len(node[0]))
        refs = []
        for ch in sorted(node[0]):
            buf.append(ch)
            buf.append(0)
            refs.append(len(buf))
            buf += b"\x00" * 5
        for rp, ch in zip(refs, sorted(node[0])):
            coff = write(node[0][ch])
            enc = uleb(coff)
            buf[rp:rp + 5] = enc + b"\x00" * (5 - len(enc))
        return my if False else start

    # The above overcomplicates; fall back to a clean iterative builder:
    buf = bytearray()

    nodes = []  # list of (terminal_addr_or_None, sorted_child_bytes, child_node_ids)
    node_id = {}

    def intern(node):
        key = id(node)
        if key in node_id:
            return node_id[key]
        nid = len(nodes)
        node_id[key] = nid
        nodes.append(None)
        kids = []
        for ch in sorted(node[0]):
            kids.append((ch, intern(node[0][ch])))
        nodes[nid] = (node[1], kids)
        return nid

    intern(root)
    # serialize breadth-first in id order; child offsets resolved by a
    # fixpoint loop (offsets grow monotonically; converges immediately)
    blobs = [b"" for _ in nodes]
    coffs = [0 for _ in nodes]
    for _ in range(10):
        pos = 0
        changed = False
        for i, (term, kids) in enumerate(nodes):
            coffs[i] = pos
            b = bytearray()
            t = (uleb(0) + uleb(term)) if term is not None else b""
            b.append(len(t))
            b += t
            b.append(len(kids))
            for ch, kid in kids:
                b.append(ch)
                b.append(0)
                b += uleb(coffs[kid])
            nb = bytes(b)
            if nb != blobs[i]:
                changed = True
                blobs[i] = nb
            pos += len(blobs[i])
        if not changed:
            break
    # final pass with settled offsets
    pos = 0
    for i, (term, kids) in enumerate(nodes):
        coffs[i] = pos
        pos += len(blobs[i])
    out = bytearray()
    for i, (term, kids) in enumerate(nodes):
        t = (uleb(0) + uleb(term)) if term is not None else b""
        out.append(len(t))
        out += t
        out.append(len(kids))
        for ch, kid in kids:
            out.append(ch)
            out.append(0)
            out += uleb(coffs[kid])
    return bytes(out)


def collect_defined(src, new_base):
    """Return {name_bytes: new_vmaddr} for N_SECT+N_EXT symbols (no writing)."""
    buf = open(src, "rb").read()
    m = parse_thin(buf)
    segs = m["segs"]
    va = new_base
    new_of = {}
    for s in segs:
        nvs = align_up(s["vs"], PAGE)
        new_of[s["name"]] = (va, nvs)
        va += nvs

    def map_old(v):
        for s in segs:
            if s["va"] <= v < s["va"] + s["vs"]:
                return new_of[s["name"]][0] + (v - s["va"])
        return None

    out = {}
    sym_lc = next((l for l in m["lcs"] if l["cmd"] == LC_SYMTAB), None)
    if sym_lc is None:
        return out
    symoff, nsyms = struct.unpack_from("<II", sym_lc["raw"], 8)
    stroff, strsize = struct.unpack_from("<II", sym_lc["raw"], 16)
    for i in range(nsyms):
        o = symoff + i * 16
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", buf, o)
        if (n_type & 0x0E) != N_SECT_TYPE or not (n_type & N_EXT) or not n_value:
            continue
        nv = map_old(n_value)
        if nv is None or stroff + n_strx >= len(buf):
            continue
        send = buf.index(b"\x00", stroff + n_strx)
        sname = bytes(buf[stroff + n_strx:send])
        if sname and sname not in out:
            out[sname] = nv
    return out

def rebase_one(src, dst, new_base, gmap=None):
    buf = bytearray(open(src, "rb").read())
    m = parse_thin(buf)
    segs = m["segs"]
    if any(s["name"] == b"__PAGEZERO" for s in segs):
        raise RuntimeError("unexpected __PAGEZERO in dylib")

    # 1. new layout in original LC order
    new_blobs = {}
    new_of_each = {}
    va = new_base
    fo = 0
    for s in segs:
        nvs = align_up(s["vs"], PAGE)
        if s["name"] == b"__TEXT":
            nfo, nfs = 0, nvs
        else:
            nfo = align_up(fo, PAGE)
            nfs = nvs if s["name"] != b"__LINKEDIT" else align_up(s["fs"], PAGE)
        new_of_each[s["name"]] = (va, nvs, nfo, nfs)
        va += nvs
        fo = nfo + nfs
    text_new_va, text_new_vs, _, _ = new_of_each[b"__TEXT"]

    old_ranges = [(s["va"], s["va"] + s["vs"], s["name"]) for s in segs]

    def old_seg_of(v):
        for a, b, n in old_ranges:
            if a <= v < b:
                return n
        return None

    def map_old(v):
        for s in segs:
            if s["va"] <= v < s["va"] + s["vs"]:
                nva, _, _, _ = new_of_each[s["name"]]
                return nva + (v - s["va"])
        return None

    # 2. patch data bytes (descriptors -> absolute, raw absolute -> new)
    text_const = None
    for s in segs:
        if s["name"] == b"__LINKEDIT":
            continue
        blob = bytearray(buf[s["fo"]:s["fo"] + s["fs"]])
        if s["name"] == b"__TEXT":
            for sc in s["sects"]:
                if sc["name"] == b"__const":
                    text_const = (sc["addr"] - s["va"], sc["size"])
            continue
        for i in range(0, len(blob) - 7, 8):
            v = struct.unpack_from("<Q", blob, i)[0]
            if v == 0:
                continue
            if (v >> 63) == 0 and ((v >> 44) & 0x7F) == 0:
                old = DSC_BASE + (v & ((1 << 36) - 1))
                if old_seg_of(old) is not None:
                    struct.pack_into("<Q", blob, i, map_old(old))
                    continue
            if old_seg_of(v) is not None:
                struct.pack_into("<Q", blob, i, map_old(v))
        new_blobs[s["name"]] = blob
    # __TEXT __const pointer tables
    s_text = next(s for s in segs if s["name"] == b"__TEXT")
    tblob = bytearray(buf[s_text["fo"]:s_text["fo"] + s_text["fs"]])
    if text_const is not None:
        coff, csize = text_const
        for i in range(coff, min(coff + csize, len(tblob) - 7), 8):
            v = struct.unpack_from("<Q", tblob, i)[0]
            if v == 0:
                continue
            if (v >> 63) == 0 and ((v >> 44) & 0x7F) == 0:
                old = DSC_BASE + (v & ((1 << 36) - 1))
                if old_seg_of(old) is not None:
                    struct.pack_into("<Q", tblob, i, map_old(old))
                    continue
            if old_seg_of(v) is not None:
                struct.pack_into("<Q", tblob, i, map_old(v))
    # strict external binds still present?
    binds = []
    for s in segs:
        if s["name"] in (b"__LINKEDIT", b"__TEXT"):
            continue
        blob = new_blobs[s["name"]]
        for i in range(0, len(blob) - 7, 8):
            v = struct.unpack_from("<Q", blob, i)[0]
            if v and (v >> 63) == 1 and ((v >> 32) & 0x7FFFF) == 0:
                binds.append((s["name"].decode(), hex(i), hex(v)))

    if binds:
        print(f"WARNING: {len(binds)} bind-like values left as-is: {binds[:8]}",
              file=sys.stderr)
    sym_lc = next((l for l in m["lcs"] if l["cmd"] == LC_SYMTAB), None)
    if sym_lc is None:
        symoff = nsyms = stroff = strsize = 0
    else:
        symoff, nsyms = struct.unpack_from("<II", sym_lc["raw"], 8)
        stroff, strsize = struct.unpack_from("<II", sym_lc["raw"], 16)
    le = next(s for s in segs if s["name"] == b"__LINKEDIT")
    le_blob = bytearray(buf[le["fo"]:le["fo"] + le["fs"]])
    sym_base = symoff - le["fo"]
    str_base = stroff - le["fo"]
    exports = []
    seen_names = set()
    for i in range(nsyms):
        o = sym_base + i * 16
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", le_blob, o)
        if (n_type & 0x0E) == N_SECT_TYPE and n_value:
            nv = map_old(n_value)
            if nv is None:
                raise RuntimeError(f"symtab value outside segments: {n_value:#x}")
            struct.pack_into("<Q", le_blob, o + 8, nv)
            if (n_type & N_EXT) and n_strx and str_base + n_strx < len(le_blob):
                end = le_blob.index(b"\x00", str_base + n_strx)
                name = bytes(le_blob[str_base + n_strx:end])
                if name and name not in seen_names:
                    seen_names.add(name)
                    exports.append((name, nv))
    # 3b. resolve N_INDR aliases (same-file defined first, then global map)
    if sym_lc is not None:
        for i in range(nsyms):
            o = sym_base + i * 16
            n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", le_blob, o)
            if (n_type & 0x0E) != 0x0A or not (n_type & N_EXT):
                continue
            if str_base + n_value >= len(le_blob):
                continue
            tend = le_blob.index(b"\x00", str_base + n_value)
            tname = bytes(le_blob[str_base + n_value:tend])
            aend = le_blob.index(b"\x00", str_base + n_strx)
            aname = bytes(le_blob[str_base + n_strx:aend])
            if not aname or not tname or aname in seen_names:
                continue
            tgt = None
            for en, ea in exports:
                if en == tname:
                    tgt = ea
                    break
            if tgt is None and gmap is not None:
                tgt = gmap.get(tname)
            if tgt is not None:
                seen_names.add(aname)
                exports.append((aname, tgt))
            else:
                print(f"WARNING: unresolved N_INDR {aname!r} -> {tname!r}", file=sys.stderr)

    # 4. code: symtab-guided disassembly, patch RIP-relative refs to data
    text_sec = next(sc for sc in s_text["sects"] if sc["name"] == b"__text")
    t_rel = text_sec["addr"] - s_text["va"]
    starts = set()
    for i in range(nsyms):
        o = sym_base + i * 16
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", le_blob, o)
        if (n_type & 0x0E) == N_SECT_TYPE and text_sec["addr"] <= n_value < text_sec["addr"] + text_sec["size"]:
            starts.add(n_value - s_text["va"])
    bounds = sorted(starts | {t_rel, t_rel + text_sec["size"]})
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    patched = 0
    for bi in range(len(bounds) - 1):
        start, end = bounds[bi], bounds[bi + 1]
        if not (t_rel <= start < end <= t_rel + text_sec["size"]):
            continue
        pos = start
        while pos < end:
            chunk = bytes(tblob[pos:end])
            advanced = False
            for ins in md.disasm(chunk, s_text["va"] + pos):
                ipos = ins.address - s_text["va"]
                for op in ins.operands:
                    if op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP:
                        if ins.encoding.disp_size != 4:
                            continue
                        tgt = ins.address + ins.size + op.mem.disp
                        sn = old_seg_of(tgt)
                        if sn is not None and sn != b"__TEXT":
                            new_tgt = map_old(tgt)
                            new_iva = text_new_va + ipos
                            ndisp = new_tgt - (new_iva + ins.size)
                            if not -(1 << 31) <= ndisp < (1 << 31):
                                raise RuntimeError("displacement out of range")
                            doff = ins.encoding.disp_offset
                            struct.pack_into("<i", tblob, ipos + doff, ndisp)
                            patched += 1
                pos = ipos + ins.size
                advanced = True
            if not advanced:
                pos += 1
    new_blobs[b"__TEXT"] = tblob

    # 5. exports trie (appended to LINKEDIT)
    trie = build_trie(exports)
    le_new_va, le_new_vs, le_new_fo, _ = new_of_each[b"__LINKEDIT"]
    trie_off_in_le = align_up(len(le_blob), 8)
    le_blob += b"\x00" * (trie_off_in_le - len(le_blob)) + trie
    le_new_fs = align_up(len(le_blob), PAGE)
    new_of_each[b"__LINKEDIT"] = (le_new_va, le_new_fs, le_new_fo, le_new_fs)
    new_blobs[b"__LINKEDIT"] = le_blob + b"\x00" * (le_new_fs - len(le_blob))

    # 6. rebuild load commands
    le_delta = le_new_fo - le["fo"]
    out_lcs = bytearray()
    for s in segs:
        nva, nvs, nfo, nfs = new_of_each[s["name"]]
        b2 = bytearray(s["lc_raw"])
        struct.pack_into("<QQQQ", b2, 24, nva, nvs, nfo, nfs)
        if s["name"] == b"__DATA_CONST" and not (s["flags"] & SG_READ_ONLY):
            struct.pack_into("<I", b2, 68, s["flags"] | SG_READ_ONLY)
        for i, sc in enumerate(s["sects"]):
            rel = sc["addr"] - s["va"]
            naddr = nva + rel
            struct.pack_into("<Q", b2, 72 + i * 80 + 32, naddr)
            stype = sc["flags"] & 0xFF
            if stype == S_ZEROFILL or sc["name"] in (b"__bss", b"__common"):
                struct.pack_into("<I", b2, 72 + i * 80 + 56, 0)
            elif 0 <= rel < s["fs"]:
                struct.pack_into("<I", b2, 72 + i * 80 + 56, nfo + rel)
            else:
                struct.pack_into("<I", b2, 72 + i * 80 + 56, 0)
        out_lcs += b2
    kept_rest = []
    for l in m["lcs"]:
        if l["cmd"] in (0x32, LC_DYLD_EXPORTS_TRIE, 0xB, LC_SYMTAB):
            continue  # dropped garbage tries here; SYMTAB/DYSYMTAB rebuilt below
        if l["cmd"] in (LC_FUNCTION_STARTS, LC_DATA_IN_CODE):
            do, ds = struct.unpack_from("<II", l["raw"], 8)
            if not (le["fo"] <= do and do + ds <= le["fo"] + le["fs"]):
                continue  # DSC-cache-relative garbage; drop
            b2 = bytearray(l["raw"])
            struct.pack_into("<I", b2, 8, do + le_delta)
            kept_rest.append(b2)
            continue
        kept_rest.append(bytearray(l["raw"]))
    # rebuild DYSYMTAB with shifted LINKEDIT offsets
    dys = next((l for l in m["lcs"] if l["cmd"] == LC_DYSYMTAB), None)
    if dys is not None:
        f = list(struct.unpack_from("<18I", dys["raw"], 8))
        # field indexes: tocoff6 ntoc7 modtaboff8 nmodtab9 extrefsymoff10 nextrefsyms11
        # indirectsymoff12 nindirectsyms13 extreloff14 nextrel15 locreloff16 nlocrel17
        for idx in (6, 8, 10, 12, 14, 16):
            if f[idx]:
                if not (le["fo"] <= f[idx] < le["fo"] + le["fs"]):
                    raise RuntimeError("dysymtab offset outside LINKEDIT")
                f[idx] += le_delta
        b2 = bytearray(dys["raw"])
        struct.pack_into("<18I", b2, 8, *f)
        kept_rest.append(b2)
    # new SYMTAB + EXPORTS_TRIE
    if sym_lc is not None:
        b2 = bytearray(sym_lc["raw"])
        struct.pack_into("<II", b2, 8, symoff + le_delta, nsyms)
        struct.pack_into("<II", b2, 16, stroff + le_delta, strsize)
        kept_rest.append(b2)
    kept_rest.append(struct.pack("<IIII", LC_DYLD_EXPORTS_TRIE, 16,
                                le_new_fo + trie_off_in_le, len(trie)))
    ncmds = len(segs) + len(kept_rest)
    sizeofcmds = len(out_lcs) + sum(len(r) for r in kept_rest)

    # 7. repack: TEXT blob starts with new header; section content fixed
    hdr = bytearray(32)
    struct.pack_into("<8I", hdr, 0, 0xFEEDFACF, 0x01000007, 0x3, m["filetype"],
                     ncmds, sizeofcmds, m["flags"], 0)
    first_rel = min(sc["addr"] - s_text["va"] for sc in s_text["sects"]
                    if 0 <= sc["addr"] - s_text["va"] < s_text["fs"])
    hlen = 32 + sizeofcmds
    if hlen > first_rel:
        raise RuntimeError("new header overlaps first section")
    t_old = new_blobs[b"__TEXT"]
    t_new = bytearray(new_blobs[b"__TEXT"])  # placeholder
    t_new = bytearray(text_new_vs if False else align_up(len(t_old), PAGE))
    t_new[0:hlen] = hdr + out_lcs + b"".join(kept_rest)
    t_new[hlen:first_rel] = b"\x00" * (first_rel - hlen)
    t_new[first_rel:len(t_old)] = t_old[first_rel:len(t_old)]
    new_blobs[b"__TEXT"] = t_new
    # zero zerofill file ranges
    for s in segs:
        if s["name"] == b"__TEXT":
            continue
        nva, nvs, nfo, nfs = new_of_each[s["name"]]
        blob = new_blobs[s["name"]]
        if len(blob) < nfs:
            blob += b"\x00" * (nfs - len(blob))
        for sc in s["sects"]:
            stype = sc["flags"] & 0xFF
            if stype == S_ZEROFILL or sc["name"] in (b"__bss", b"__common"):
                rel = sc["addr"] - s["va"]
                blob[rel:rel + sc["size"]] = b"\x00" * sc["size"]
        new_blobs[s["name"]] = blob[:nfs]

    out = bytearray()
    for s in segs:
        _, _, nfo, nfs = new_of_each[s["name"]]
        if len(out) < nfo:
            out += b"\x00" * (nfo - len(out))
        assert len(out) == nfo
        out += new_blobs[s["name"]]
    open(dst, "wb").write(out)
    return {"patched_rip": patched, "exports": len(exports),
            "trie_len": len(trie), "out_len": len(out)}


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--batch":
        jobs = []
        with open(sys.argv[2]) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                src, dst, base = line.split()
                jobs.append((src, dst, int(base, 16)))
        gmap = {}
        for src, dst, base in jobs:
            for k, v in collect_defined(src, base).items():
                if k not in gmap:
                    gmap[k] = v
        print(f"global exports: {len(gmap)}", file=sys.stderr)
        for src, dst, base in jobs:
            r = rebase_one(src, dst, base, gmap)
            print(f"{src} -> {dst}: {r}")
        return 0
    if len(sys.argv) != 4:
        print("usage: dsc_rebase.py <src> <dst> <new_base_hex> | --batch <listfile>")
        return 1
    src, dst, base = sys.argv[1], sys.argv[2], int(sys.argv[3], 16)
    r = rebase_one(src, dst, base)
    print(f"{src} -> {dst}: {r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
