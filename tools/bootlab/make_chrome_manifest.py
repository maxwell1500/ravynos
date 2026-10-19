#!/usr/bin/env python3
"""make_chrome_manifest.py -- manifest_gui.json plus Chrome's staged trees.

  python3 tools/bootlab/make_chrome_manifest.py [--probe] [--size-mib MiB]

Writes manifest_chrome.json: the GUI manifest verbatim, with two `tree`
entries appended -- work/chrome-payload at the app's Contents directory and
work/chrome-shims at the filesystem root -- plus, with --probe, a launchd job
and its shell script that exercise Chrome from the serial console.

Asserts before writing:
  * no payload/shim file path collides case-insensitively with a base-manifest
    path or with the other tree (FAT32 cannot tell the two apart);
  * the staged payload fits the image the manifest is built for.
The trees themselves are produced by chrome_stage.py, which must run first.
"""
import argparse
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fat32img

BASE = os.path.join(HERE, "manifest_gui.json")
PAYLOAD = os.path.join(HERE, "work", "chrome-payload")
SHIMS = os.path.join(HERE, "work", "chrome-shims")
OUT = os.path.join(HERE, "manifest_chrome.json")

PROBE_SH = """#!/bin/sh
sleep 30
echo "[CP] probe start" > /dev/console
export HOME=/tmp TMPDIR=/tmp PATH=/bin:/sbin:/usr/bin:/usr/sbin
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
echo "[CP] version:" > /dev/console
DYLD_PRINT_LIBRARIES=1 "$CHROME" --version > /dev/console 2>&1
echo "[CP] version rc=$?" > /dev/console
# WindowServer (re)creates /var/run/windowserver once it accepts clients.
n=0
while ! /bin/test -e /var/run/windowserver; do
    sleep 5
    n=$((n+1))
    /bin/test "$n" -gt 36 && break
done
echo "[CP] windowserver-wait n=$n" > /dev/console
echo "[CP] gui:" > /dev/console
"$CHROME" --no-sandbox --disable-gpu --no-first-run --user-data-dir=/tmp/chrome-profile > /dev/console 2>&1 &
CPID=$!
sleep 25
# No /bin/kill in this image, so liveness is Chrome's own profile dir.
if /bin/test -d /tmp/chrome-profile; then
    echo "[CP] gui ALIVE pid=$CPID (profile dir created)" > /dev/console
else
    wait $CPID
    echo "[CP] gui EXITED rc=$? pid=$CPID" > /dev/console
fi
echo "[CP] done" > /dev/console
"""

PROBE_JOB = ("{\"Label\":\"com.ravynos.chromeprobe\","
             "\"ProgramArguments\":[\"/bin/chromeprobe.sh\"],"
             "\"RunAtLoad\":true,"
             "\"EnvironmentVariables\":{\"ASL_DISABLE\":\"1\","
             "\"LANG\":\"C.UTF-8\"}}\n")


def tree_paths(root, stage_prefix):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            fp = os.path.join(dirpath, name)
            rel = os.path.relpath(fp, root).replace(os.sep, "/")
            out.append((((stage_prefix + "/" + rel) if stage_prefix else rel),
                        fp))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--probe", action="store_true",
                    help="also stage /bin/chromeprobe.sh and its launchd job")
    ap.add_argument("--size-mib", type=int, default=2048,
                    help="image size the manifest is built for (budget check)")
    args = ap.parse_args()

    for d in (PAYLOAD, SHIMS):
        if not os.path.isdir(d):
            sys.exit("missing %s -- run tools/bootlab/chrome_stage.py first" % d)

    with open(BASE) as f:
        man = json.load(f)
    entries = man["files"]

    payload = [(p, fp) for p, fp in
               tree_paths(PAYLOAD, "Applications/Google Chrome.app/Contents")]
    shims = tree_paths(SHIMS, "")

    # Collision check: FAT32 matches names case-insensitively, so two entries
    # that differ only in case are the same file to the guest.
    owners = collections.defaultdict(list)
    for e in entries:
        owners[e["path"].lower()].append("manifest_gui.json")
    for p, fp in payload:
        owners[p.lower()].append("chrome-payload")
    for p, fp in shims:
        owners[p.lower()].append("chrome-shims")
    if args.probe:
        for p in ("bin/chromeprobe.sh",
                  "System/Library/LaunchDaemons/com.ravynos.chromeprobe.json"):
            owners[p.lower()].append("probe")
    bad = {p: o for p, o in owners.items() if len(o) > 1}
    if bad:
        print("path collisions (case-insensitive):")
        for p in sorted(bad):
            print("  %s: %s" % (p, ", ".join(bad[p])))
        sys.exit(1)

    entries.append({
        "tree": "work/chrome-payload",
        "path": "Applications/Google Chrome.app/Contents",
        "comment": "Chrome's bundle tree, thinned + adhoc-signed by chrome_stage.py",
    })
    entries.append({
        "tree": "work/chrome-shims",
        "path": "",
        "comment": "generated dyld-closure shims/stubs + renamed real copies",
    })
    if args.probe:
        entries.append({"path": "bin/chromeprobe.sh", "text": PROBE_SH,
                        "comment": "serial-console probe: --version then GUI"})
        entries.append({
            "path": "System/Library/LaunchDaemons/com.ravynos.chromeprobe.json",
            "text": PROBE_JOB,
            "comment": "runs /bin/chromeprobe.sh at boot"})

    payload_bytes = sum(os.path.getsize(fp) for _, fp in payload)
    shims_bytes = sum(os.path.getsize(fp) for _, fp in shims)
    geom = fat32img.geometry_for_size(args.size_mib * 1024 * 1024)
    usable = geom.max_cluster * geom.cl
    print("chrome-payload: %d files, %.1f MiB" % (len(payload), payload_bytes / 1048576.0))
    print("chrome-shims:   %d files, %.1f MiB" % (len(shims), shims_bytes / 1048576.0))
    print("tree bytes:     %.1f MiB" % ((payload_bytes + shims_bytes) / 1048576.0))
    print("image:          %d MiB, usable %.1f MiB (%d clusters of %d)"
          % (args.size_mib, usable / 1048576.0, geom.max_cluster, geom.cl))
    if payload_bytes + shims_bytes > usable:
        sys.exit("staged trees do not fit a %d MiB image" % args.size_mib)

    with open(args.out, "w") as f:
        json.dump(man, f, indent=1)
        f.write("\n")
    print("wrote %s (%d entries)" % (args.out, len(entries)))


if __name__ == "__main__":
    main()
