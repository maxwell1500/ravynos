#!/usr/bin/env python3
"""Extract committed assets from the golden reference image into tools/bootlab/assets/.

Run once against a known-good image (default /tmp/fresh_test.img). Idempotent:
rewrites whatever it finds. Files it extracts:

  template_head.bin   bytes 0x000000..0x202800 of the golden image
                      (MBR+GPT+BPB+FSInfo+reserved sectors — the firmware-
                      visible layout everything else is built on)
  template_tail.bin   last 34 sectors (backup GPT)
  vars.fd             copied from --vars (proven OVMF NVRAM template)
  <asset paths>       every manifest-listed asset that lives in the golden image

The kernel asset is the BootKernelExtensions.kc payload (the proven live path).
"""
import argparse
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fat32img import Fat32Img, HEAD_BYTES, TAIL_BYTES, IMAGE_BYTES

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", default="/tmp/fresh_test.img")
    ap.add_argument("--vars", default="/tmp/test_vars2.fd")
    args = ap.parse_args()

    assets = os.path.join(HERE, "assets")
    os.makedirs(assets, exist_ok=True)

    gsize = os.path.getsize(args.golden)
    if gsize != IMAGE_BYTES:
        sys.exit("golden image is %d bytes, expected %d" % (gsize, IMAGE_BYTES))

    # Head / tail templates -----------------------------------------------------
    with open(args.golden, "rb") as g:
        head = g.read(HEAD_BYTES)
        g.seek(IMAGE_BYTES - TAIL_BYTES)
        tail = g.read()
    with open(os.path.join(assets, "template_head.bin"), "wb") as f:
        f.write(head)
    with open(os.path.join(assets, "template_tail.bin"), "wb") as f:
        f.write(tail)
    print("head %d bytes, tail %d bytes" % (len(head), len(tail)))

    # OVMF vars template ----------------------------------------------------------
    shutil.copyfile(args.vars, os.path.join(assets, "vars.fd"))
    print("vars.fd %d bytes" % os.path.getsize(os.path.join(assets, "vars.fd")))

    # Manifest-listed assets -------------------------------------------------------
    with open(os.path.join(HERE, "manifest.json")) as f:
        man = json.load(f)

    img = Fat32Img(args.golden)
    n = 0

    def dump(src_path, dst_rel):
        nonlocal n
        info = img.path_lookup(src_path)
        if info is None:
            print("MISSING in golden (skipped): %s" % src_path)
            return
        clus, size = info[2], info[3]
        data = img.read_clusters(clus, size)
        if len(data) != size:
            sys.exit("short read %s: %d/%d" % (src_path, len(data), size))
        dst = os.path.join(assets, dst_rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)
        print("%-55s %8d -> %s" % (src_path, len(data), dst_rel))
        n += 1

    done_kernel = False
    for ent in man["files"]:
        if "glob" in ent:
            srcdir = img.path_lookup(ent["glob"])
            if srcdir is None:
                print("MISSING in golden dir (skipped): %s" % ent["glob"])
                continue
            for long, short, clus, size, is_dir in img.listdir(srcdir[2]):
                if is_dir or size == 0:
                    continue
                name = long if long else short
                dump(ent["glob"] + "/" + name, ent["asset_prefix"] + name)
        elif "asset" in ent:
            dump(ent["path"], ent["asset"])
        elif "kernel" in ent and not done_kernel:
            # committed fallback payload, from the proven BOOTKC location
            dump(ent["path"], "kernel.development")
            done_kernel = True
    img.close()
    print("extracted %d assets" % n)

if __name__ == "__main__":
    main()
