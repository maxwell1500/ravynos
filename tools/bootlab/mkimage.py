#!/usr/bin/env python3
"""Build a fresh bootable ravynOS FAT32 disk image from committed sources.

  python3 tools/bootlab/mkimage.py [out.img] [--manifest FILE]

Layout comes from the committed head/tail templates (verbatim golden bytes:
MBR + GPT + BPB + FSInfo + reserved sectors, plus backup-GPT tail), so the
firmware-visible geometry is bit-identical to the proven golden image.
The tree itself is defined by a manifest: manifest.json for the standard
image, manifest_dynamic.json for the dynamic-userland gate.

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
    ap.add_argument("--manifest",
                    help="manifest file, relative to tools/bootlab or absolute "
                         "(default manifest.json)")
    args = ap.parse_args()

    mpath = args.manifest or "manifest.json"
    if not os.path.isabs(mpath):
        mpath = os.path.join(HERE, mpath)
    with open(mpath) as f:
        man = json.load(f)

    kern = newest_kernel(args.kernel)
    init = ensure_init_exec() if needs_init_exec(man) else ensure_init()
    print("manifest:       %s" % mpath)
    print("kernel payload: %s (%d bytes)" % (kern, os.path.getsize(kern)))
    print("init  payload:  %s (%d bytes)" % (init, os.path.getsize(init)))

    b = ImageBuilder(os.path.join(HERE, "assets", "template_head.bin"),
                     os.path.join(HERE, "assets", "template_tail.bin"),
                     args.out, man.get("volume", "RAVYNOS"))

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
        elif "text" in ent:
            add(ent["path"], ent["text"].encode("utf-8"))
        else:
            sys.exit("manifest entry with no source: %r" % ent)

    b.build()
    print("wrote %s (%d clusters used of 130301)" % (args.out, b.payload_clusters()))

    # Self-verify: reopen, walk, compare content hash of every regular file.
    import hashlib
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
    print("verify OK: %d files, %d tree entries, all content hashes match" %
          (len(seen), len(walked)))

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
