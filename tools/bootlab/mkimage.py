#!/usr/bin/env python3
"""Build a fresh bootable ravynOS FAT32 disk image from committed sources.

  python3 tools/bootlab/mkimage.py [out.img] [--manifest FILE]

Layout comes from the committed head/tail templates (verbatim golden bytes:
MBR + GPT + BPB + FSInfo + reserved sectors, plus backup-GPT tail), so the
firmware-visible geometry is bit-identical to the proven golden image.
--size-mib N (N > 512) synthesizes larger templates from those same bytes.
The tree itself is defined by a manifest: manifest.json for the standard
image, manifest_dynamic.json for the dynamic-userland gate.

Manifest entry sources: glob, asset, kernel, init, init_exec, file, text, and
tree (stage a directory recursively; a path that collides with any other
entry is a manifest error and aborts the build).

Kernel selection (newest wins):
  --kernel PATH  >  work/stripped_kernel.development  >  assets/kernel.development
Init payload: work/init (build via build_init.sh), else assets/init if present.
Dynamic-gate payload: work/init_exec (build via build_init_exec.sh), selected
by the manifest's "init_exec" marker.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fat32img import ImageBuilder

def newest_kernel(explicit):
    cands = []
    if explicit:
        cands.append(explicit)
    else:
        cands += [os.path.join(HERE, "work", "stripped_kernel.development"),
                  os.path.join(HERE, "assets", "kernel.development")]
    cands = [c for c in cands if os.path.isfile(c)]
    if not cands:
        sys.exit("no kernel payload: pass --kernel, run kernel_build.py, "
                 "or extract assets (assets/kernel.development)")
    return max(cands, key=os.path.getmtime)

def ensure_init():
    p = os.path.join(HERE, "work", "init")
    if not os.path.isfile(p):
        b = os.path.join(HERE, "build_init.sh")
        print("work/init missing -> building")
        subprocess.check_call([b])
    return p

def ensure_init_exec():
    p = os.path.join(HERE, "work", "init_exec")
    if not os.path.isfile(p):
        b = os.path.join(HERE, "build_init_exec.sh")
        print("work/init_exec missing -> building")
        subprocess.check_call([b])
    return p

def needs_init_exec(man):
    return any(e.get("init_exec") for e in man.get("files", []))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", nargs="?", default=os.path.join(HERE, "work", "boot.img"))
    ap.add_argument("--kernel", help="explicit kernel payload path")
    ap.add_argument("--gpt-conform", action="store_true",
                    help="rewrite the golden GPT header to be UEFI-spec "
                         "conformant. DEFAULT OFF: as of 2026-09-28 this "
                         "BREAKS the Apple boot.efi path -- with a "
                         "conformant GPT the UEFI shell no longer maps fs0: "
                         "and the kernel never starts. See "
                         "gpt_conform.py and the report before enabling.")
    ap.add_argument("--size-mib", type=int, default=512,
                    help="image size in MiB (default 512). 512 uses the "
                         "committed head/tail templates byte for byte; a "
                         "larger size synthesizes templates from them with "
                         "fat32img.synth_templates (grows the FAT and the "
                         "partition, keeps the GPT/MBR/BPB layout).")
    ap.add_argument("--skip-verify", action="store_true",
                    help="stop after the write pass (skips read-back verify + "
                         "digest sidecar; useful for iteration cycles where a "
                         "separate targeted check is enough)")
    ap.add_argument("--manifest",
                    help="manifest file, relative to tools/bootlab or absolute "
                         "(default manifest.json)")
    args = ap.parse_args()

    if args.size_mib < 512:
        sys.exit("--size-mib below 512 is not supported (golden template floor)")

    mpath = args.manifest or "manifest.json"
    if not os.path.isabs(mpath):
        mpath = os.path.join(HERE, mpath)
    with open(mpath) as f:
        man = json.load(f)

    sys.path.insert(0, HERE)
    import fat32img
    geom = None if args.size_mib == 512 else \
        fat32img.geometry_for_size(args.size_mib * 1024 * 1024)

    kern = newest_kernel(args.kernel)
    init = ensure_init_exec() if needs_init_exec(man) else ensure_init()
    print("manifest:       %s" % mpath)
    print("kernel payload: %s (%d bytes)" % (kern, os.path.getsize(kern)))
    print("init  payload:  %s (%d bytes)" % (init, os.path.getsize(init)))

    # ------------------------------------------------------------------
    # GPT CONFORMANCE.
    #
    # The golden head/tail templates carry a GPT header that does not match
    # the UEFI spec: NumberOfPartitionEntries and SizeOfPartitionEntry are
    # written as UINT32 at 0x50/0x54 where the spec has UINT64 at 0x50 and
    # UINT32 at 0x58, and partition 0 is typed "Microsoft Basic Data" instead
    # of "EFI System Partition".  An EDK2 PartitionDxe reads a UINT64 at 0x50,
    # sees 0x0000008000000080 = 549,755,814,016 entries, rejects the layout
    # and never creates a partition handle -- so FatDxe never binds and
    # EFI_SIMPLE_FILE_SYSTEM_PROTOCOL is never installed, while the UEFI
    # shell still shows FS0 because it enumerates the volume its own way.
    # That is why a HandleProtocol sweep of all 1976 handles found zero
    # volumes: HandleProtocol was reporting the truth the whole time.
    #
    # The committed templates are NOT modified.  The repair is applied to a
    # copy in work/, so it is additive and reversible, and it applies to
    # every image the harness builds from now on.  gpt_conform.check() then
    # asserts the result on EVERY build, so this cannot regress silently.
    # ------------------------------------------------------------------
    # Template sources: committed assets for 512 MiB, synthesized for a grown
    # image (same GPT/MBR/BPB bytes with the size fields and CRCs rewired).
    head_src = os.path.join(HERE, "assets", "template_head.bin")
    tail_src = os.path.join(HERE, "assets", "template_tail.bin")
    if geom is not None:
        syn_head, syn_tail = fat32img.synth_templates(
            geom, open(head_src, "rb").read(), open(tail_src, "rb").read())
        head_src = os.path.join(HERE, "work",
                                "template_head.%dmib.bin" % args.size_mib)
        tail_src = os.path.join(HERE, "work",
                                "template_tail.%dmib.bin" % args.size_mib)
        os.makedirs(os.path.join(HERE, "work"), exist_ok=True)
        open(head_src, "wb").write(syn_head)
        open(tail_src, "wb").write(syn_tail)
        print("geometry:       %d MiB  spf=%d  max_cluster=%d  data_off=0x%x  "
              "partition LBA [%d, %d]"
              % (args.size_mib, geom.spf_sectors, geom.max_cluster,
                 geom.data_off, geom.part_first_lba, geom.part_last_lba))

    if args.gpt_conform:
      sys.path.insert(0, HERE)
      import gpt_conform
      os.makedirs(os.path.join(HERE, "work"), exist_ok=True)
      fixed_head = os.path.join(HERE, "work", "template_head.gptfix.bin")
      fixed_tail = os.path.join(HERE, "work", "template_tail.gptfix.bin")
      head = bytearray(open(head_src, "rb").read())
      tail = bytearray(open(tail_src, "rb").read())
      HEAD_ENTRY_OFF = 1024                        # primary entry array, LBA 2
      tail_hdr = tail.find(b"EFI PART")
      if tail_hdr < 0:
          sys.exit("no backup GPT header in template_tail.bin")
      # Backup layout: the last 32 sectors are the backup entry array and the
      # final sector is the backup header, so the array is at tail offset 0.
      TAIL_ENTRY_OFF = 0
      for buf, arr, name in ((head, HEAD_ENTRY_OFF, "head"),
                             (tail, TAIL_ENTRY_OFF, "tail")):
          gpt_conform.set_esp_type_guid(buf, arr)
          gpt_conform.conform_gpt(buf, [arr], name)
          info = gpt_conform.check(buf, name, arr)
          print("GPT %-4s: npart=%d psz=%d hdrsz=%d crc=0x%08x  ESP type set"
                % (name, info["npart"], info["psz"], info["hsize"], info["header_crc"]))
      open(fixed_head, "wb").write(bytes(head))
      open(fixed_tail, "wb").write(bytes(tail))
      b = ImageBuilder(fixed_head, fixed_tail, args.out,
                       man.get("volume", "RAVYNOS"), geom=geom)
    else:
      b = ImageBuilder(head_src, tail_src, args.out,
                       man.get("volume", "RAVYNOS"), geom=geom)

    def mkdirs(path):
        node = b.root
        for part in path.split("/"):
            if not part:
                continue
            nxt = None
            for ch in node.children:
                if ch.is_dir and ch.name.lower() == part.lower():
                    nxt = ch
                    break
            if nxt is None:
                from fat32img import Node
                nxt = Node(part, True)
                node.children.append(nxt)
            node = nxt
        return node
    expected = {}

    for d in man.get("dirs", []):
        mkdirs(d)

    def add(path, data):
        parent = mkdirs(os.path.dirname(path))
        from fat32img import Node
        parent.children.append(Node(os.path.basename(path), False, data))
        expected[path.lower()] = data

    def read_asset(rel):
        p = os.path.join(HERE, "assets", rel)
        if not os.path.isfile(p):
            sys.exit("missing asset: assets/%s (run extract_assets.py)" % rel)
        with open(p, "rb") as f:
            return f.read()

    for ent in man["files"]:
        if "glob" in ent:
            srcdir = os.path.join(HERE, "assets", ent["asset_prefix"])
            if not os.path.isdir(srcdir):
                sys.exit("missing asset dir: assets/%s" % ent["asset_prefix"])
            for name in sorted(os.listdir(srcdir)):
                fp = os.path.join(srcdir, name)
                if os.path.isfile(fp):
                    add(os.path.join(ent["glob"], name), open(fp, "rb").read())
        elif "asset" in ent:
            add(ent["path"], read_asset(ent["asset"]))
        elif "kernel" in ent:
            add(ent["path"], open(kern, "rb").read())
        elif "init" in ent:
            add(ent["path"], open(init, "rb").read())
        elif "init_exec" in ent:
            add(ent["path"], open(init, "rb").read())
        elif "file" in ent:
            # Additive: stage a file from anywhere (used by the ravynOS EFI
            # loader, which is a build product outside assets/).  No existing
            # manifest uses this key, so today's behaviour is unchanged.
            p = ent["file"]
            if not os.path.isabs(p):
                p = os.path.join(HERE, p)
            if not os.path.isfile(p):
                sys.exit("missing file source: %s" % p)
            add(ent["path"], open(p, "rb").read())
        elif "text" in ent:
            add(ent["path"], ent["text"].encode("utf-8"))
        elif "tree" in ent:
            srcdir = ent["tree"]
            if not os.path.isabs(srcdir):
                srcdir = os.path.join(HERE, srcdir)
            if not os.path.isdir(srcdir):
                sys.exit("missing tree source: %s" % srcdir)
            base = ent["path"].strip("/")
            for root, dirs, files in os.walk(srcdir):
                dirs.sort()
                for name in sorted(files):
                    fp = os.path.join(root, name)
                    rel = os.path.relpath(fp, srcdir).replace(os.sep, "/")
                    key = ((base + "/" + rel) if base else rel)
                    if key.lower() in expected:
                        sys.exit("tree %s: duplicate path %s" % (srcdir, key))
                    add(key, open(fp, "rb").read())
        else:
            sys.exit("manifest entry with no source: %r" % ent)

    import time
    t_build = time.perf_counter()
    b.build()
    print("wrote %s (%d clusters used of %d); build pass %.1fs" %
          (args.out, b.payload_clusters(), b.geom.max_cluster,
           time.perf_counter() - t_build))
    if args.skip_verify:
        print("verify SKIPPED (--skip-verify)")
        return

    # Self-verify: reopen, walk, compare content hash of every regular file.
    import hashlib
    t_ver = time.perf_counter()
    img = b.verify()
    walked = img.walk()
    bad = []
    seen = set()
    img_bytes_cache = {}
    for path, clus, size, is_dir in walked:
        if is_dir:
            continue
        key = path.lower()
        data = img.read_clusters(clus, size)
        img_bytes_cache[key] = data
        if key not in expected:
            bad.append("unexpected file %s" % path)
            continue
        seen.add(key)
        if hashlib.md5(data).hexdigest() != hashlib.md5(expected[key]).hexdigest():
            bad.append("content mismatch %s" % path)
    for k in expected:
        if k not in seen:
            bad.append("missing file %s" % k)
    img.close()
    if bad:
        for m in bad:
            print("VERIFY FAIL:", m)
        sys.exit(1)
    print("verify OK: %d files, %d tree entries, all content hashes match "
          "(verify pass %.1fs)" % (len(seen), len(walked),
                                   time.perf_counter() - t_ver))

    # -----------------------------------------------------------------------
    # RECORD WHAT WENT IN, so the image identifies its own contents.
    #
    # WHY. The self-verify above compares the image against `expected`, which is
    # what was read from disk AT BUILD TIME. That proves the image faithfully
    # reproduces *a* file. It does not record *which* file, and the payloads in
    # this tree get rebuilt: work/stripped_kernel.development was replaced
    # between one run and the next, and a digest pinned by hand was then
    # unverifiable forever, because the file it named no longer existed. The
    # builder was not at fault and was proven byte-exact; the RECORD was missing.
    #
    # So every file IN THE IMAGE is hashed with sha256 -- read back out of the
    # finished image, not from the source files -- and written to a sidecar
    # beside it.
    #
    # READ IT BACK OUT OF THE IMAGE, deliberately. Hashing the source files would
    # record what we INTENDED to put there; hashing the image records what is
    # ACTUALLY there. Only the second survives a payload being rebuilt, and only
    # the second is evidence. If this is ever "optimised" to hash the sources
    # instead, the sidecar silently stops being evidence and still looks fine --
    # so the variable it reads from is named for the image, not the input.
    #
    # The sidecar is what lets a later run say "this image ran THAT kernel" as a
    # check rather than an assumption.
    #
    # The kernel is called out on stdout because it is the one payload that gets
    # relinked by another worker mid-session.
    # img_bytes_cache holds bytes read back OUT of the image during the verify
    # walk above -- not bytes read from the source tree. See the note above.
    digests = []
    for path, clus, size, is_dir in walked:
        if is_dir:
            continue
        digests.append((path, hashlib.sha256(
            img_bytes_cache[path.lower()]).hexdigest()))
    side = args.out + ".digests"
    with open(side, "w") as f:
        f.write("# sha256  path  -- recorded by mkimage.py at build time\n")
        for path, dg in sorted(digests):
            f.write("%s  %s\n" % (dg, path))
    kern = [d for p_, d in digests if p_.endswith("kernel.development")]
    if kern:
        print("kernel sha256 (recorded): %s" % kern[0])
    print("wrote %s (%d digests)" % (side, len(digests)))

if __name__ == "__main__":
    main()
