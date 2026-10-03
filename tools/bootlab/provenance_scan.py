#!/usr/bin/env python3
"""Provenance gate: flag Mach-O binaries lifted out of the host's dyld cache.

Why this exists
---------------
ravynOS's build path is genuine Apple open-source Darwin source (see
PROVENANCE-PLAN.md sec. 3.1).  But 31 dylibs staged under
``assets/usr/lib/system/`` were extracted from the *host Mac's* dyld shared
cache.  Nothing in the tree prevented that from happening again: the live
manifest stopped using an ``assets/`` glob, so the contamination became inert
by accident rather than by enforcement.  The next person who adds a glob would
reintroduce all 31 silently, and the only symptom would be a boot failure
inside QEMU.  This tool makes that impossible to miss.

The test
--------
Apple mints a fresh ``LC_UUID`` per build, and the host cache records every
image's ``LC_UUID``.  Therefore *a binary whose ``LC_UUID`` appears in the host
cache came out of that exact Apple build*.  The test is content-based and
machine-local, and -- unlike a byte comparison -- it survives an in-place
rewrite: eight of the 31 were re-based/fixed-up after extraction, which is why
byte comparison misses them but the UUID still hits.

Design notes that are load-bearing (see PROVENANCE-PLAN.md sec. 2)
-----------------------------------------------------------------
* The host cache is a SPLIT cache.  All seven files are scanned.  On this host
  the base file alone carries every one of the 31 (they live in the base
  cache's ``RW`` mapping), so the subcaches are not load-bearing *here* -- but
  a future OS could move an image into a subcache, and under-approximation is
  exactly the failure this gate exists to prevent.
* Indexing must be RECORD-aligned, not page-aligned.  Shared-cache images are
  not all 2048-aligned, and an earlier 2048-aligned pass under-counted and
  reported 24 instead of the true 31.
* The scan is a deliberate SUPERSET: every non-zero 16-byte value at an
  8-byte-aligned offset whose following ``u64`` falls inside one of the mapped
  ranges from the ``.map`` file.  Over-approximation is safe (a 128-bit UUID
  does not collide by accident); under-approximation would hide a borrow.
  Measured on this host the superset is ~12.7M values against ~3.6k real
  image records, and the false-positive rate against real clean binaries and
  against 20k synthetic random UUIDs was 0.

Exit status
-----------
0   no host-extracted binary found -- ONLY when the check actually ran, or
    when it could not run and ``--allow-missing-host-cache`` recorded an
    explicit waiver (such a run prints NOT SATISFIED and never says PASS)
1   at least one host-extracted binary found
2   the check could NOT run: host cache missing or unreadable and no waiver --
    a loud failure.  The default is FAIL CLOSED: a check that cannot run must
    not pass, because a silently-passing check is worse than no check.
    ``closure_check.py`` fails closed the same way when its cache load fails.
"""

import argparse
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# Where macOS keeps the split cache.  Overridable for a non-standard layout.
DEFAULT_CACHE_DIR = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld"
CACHE_BASENAME = "dyld_shared_cache_x86_64h"

# Mach-O constants (same set closure_check.py uses; verified against
# Libraries/dyld's own headers).
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
LC_UUID = 0x1B
LC_SEGMENT_64 = 0x19
CPU_TYPE_X86_64 = 0x01000007
CPU_TYPE_ARM64 = 0x0100000C

EXIT_CLEAN = 0
EXIT_DIRTY = 1
EXIT_CANNOT_RUN = 2


# --------------------------------------------------------------------------
# Host cache: mapped ranges + UUID superset
# --------------------------------------------------------------------------

def cache_files(cache_dir):
    """The seven split-cache files, base first then subcaches in order."""
    out = []
    base = os.path.join(cache_dir, CACHE_BASENAME)
    if os.path.isfile(base):
        out.append(base)
    i = 1
    while True:
        p = os.path.join(cache_dir, "%s.%02d" % (CACHE_BASENAME, i))
        if not os.path.isfile(p):
            break
        out.append(p)
        i += 1
    return out


def mapped_ranges(cache_dir):
    """(start, end) VM ranges from the .map file, sorted.

    The .map has no size column -- each line is ``address -> address`` -- so
    the end of one range and the start of the next are used as given.
    """
    import re
    mp = os.path.join(cache_dir, CACHE_BASENAME + ".map")
    if not os.path.isfile(mp):
        return []
    rx = re.compile(rb"^mapping\s+\S+\s+\S+\s+0x([0-9A-Fa-f]+)\s*->\s*0x([0-9A-Fa-f]+)")
    out = []
    with open(mp, "rb") as fh:
        for line in fh:
            m = rx.match(line)
            if m:
                out.append((int(m.group(1), 16), int(m.group(2), 16)))
    out.sort()
    return out


def _make_in_range(ranges):
    """Binary-search membership test, closed over a sorted range list."""
    n = len(ranges)

    def in_range(addr):
        lo, hi = 0, n
        while lo < hi:
            mid = (lo + hi) // 2
            if addr < ranges[mid][0]:
                hi = mid
            elif addr >= ranges[mid][1]:
                lo = mid + 1
            else:
                return True
        return False
    return in_range


def scan_cache_file(path, uuids, in_range, verbose=False):
    """Add every superset UUID candidate found in one cache file.

    Record layout: the candidate is a 16-byte UUID at an 8-byte-aligned
    offset whose following ``u64`` (offset +16) is a mapped VM address.  Every
    address in this cache has the two top bytes ``0x7f 0x00`` on little
    endian, so scanning for the needle ``\\x7f\\x00`` finds candidate positions
    at memory speed and the alignment/range test does the rest.
    """
    CHUNK = 64 << 20
    overlap = 64
    scanned = cands = hits = 0
    with open(path, "rb") as fh:
        carry = b""
        while True:
            chunk = fh.read(CHUNK)
            if not chunk:
                break
            scanned += len(chunk)
            buf = carry + chunk if carry else chunk
            pos = 0
            find = buf.find
            while True:
                i = find(b"\x7f\x00", pos)
                if i < 0:
                    break
                pos = i + 1
                # needle sits at address-bytes 5..6, so the u64 starts at i-5
                ustart = i - 5
                iu = ustart - 16
                if iu >= 0 and (iu & 7) == 0:
                    cands += 1
                    if in_range(struct.unpack_from("<Q", buf, ustart)[0]):
                        hits += 1
                        u = bytes(buf[iu:iu + 16])
                        if u.strip(b"\x00"):
                            uuids.add(u)
            carry = buf[-overlap:] if len(buf) >= overlap else buf
    if verbose:
        sys.stderr.write("  %-34s %11d bytes  cands=%-9d in-range=%-9d set=%d\n"
                         % (os.path.basename(path), scanned, cands, hits,
                            len(uuids)))
    return scanned


def build_host_uuid_set(cache_dir, verbose=False):
    """Build the superset UUID set from all seven split-cache files.

    Returns (uuid_set, bytes_scanned, n_files).  This is ~8 GB of I/O, so the
    caller must build it ONCE and then scan as many trees as it likes.
    """
    files = cache_files(cache_dir)
    ranges = mapped_ranges(cache_dir)
    if not files:
        raise FileNotFoundError("no %s* under %s" % (CACHE_BASENAME, cache_dir))
    if not ranges:
        raise FileNotFoundError("no %s.map under %s" % (CACHE_BASENAME, cache_dir))
    in_range = _make_in_range(ranges)
    uuids = set()
    total = 0
    if verbose:
        sys.stderr.write("scanning %d split-cache file(s), %d mapped ranges\n"
                         % (len(files), len(ranges)))
    for p in files:
        total += scan_cache_file(p, uuids, in_range, verbose)
    return uuids, total, len(files)




def _cache_key(cache_dir, files):
    """Identity of a cache build: file names, sizes and mtimes."""
    parts = []
    for p in files:
        st = os.stat(p)
        parts.append("%s:%d:%d" % (os.path.basename(p), st.st_size,
                                   int(st.st_mtime)))
    return "|".join(parts)


def cached_host_uuid_set(cache_dir, cache_file=None, verbose=False):
    """build_host_uuid_set(), memoised on disk across processes.

    The scan is ~5.8 GB of I/O and ~25 s, which is fine once but wasteful when
    the gate is invoked repeatedly (every stage, every CI run).  The key binds
    the memo to the exact cache build -- any change to any of the seven files'
    size or mtime invalidates it, so a stale set can never be reused.  A
    missing or unreadable memo is not an error: it just means we rebuild.
    """
    files = cache_files(cache_dir)
    if cache_file is None:
        import tempfile
        cache_file = os.path.join(tempfile.gettempdir(),
                                  "ravynos-host-cache-uuids.v1")
    key = _cache_key(cache_dir, files)
    import pickle
    try:
        with open(cache_file, "rb") as fh:
            blob = pickle.load(fh)
        if blob.get("key") == key:
            if verbose:
                sys.stderr.write("reusing host UUID set from %s\n" % cache_file)
            return set(blob["uuids"]), blob["bytes"], blob["files"]
    except Exception:
        pass
    uuids, nbytes, nfiles = build_host_uuid_set(cache_dir, verbose)
    try:
        tmp = cache_file + ".tmp%d" % os.getpid()
        with open(tmp, "wb") as fh:
            pickle.dump({"key": key, "uuids": uuids, "bytes": nbytes,
                         "files": nfiles}, fh, protocol=4)
        os.replace(tmp, cache_file)
    except Exception:
        pass
    return uuids, nbytes, nfiles



# --------------------------------------------------------------------------
# Mach-O reading
# --------------------------------------------------------------------------

def macho_uuids_and_text_bytes(data):
    """(list_of_uuid_bytes, __TEXT_vmaddr_or_None, file_type_or_None).

    Takes BYTES, not a path, because the verdict that matters is about the
    bytes a machine will actually load.  Reading them from a path re-derives
    the answer from the build tree; reading them back out of the finished
    image derives it from the disk.  The two can differ -- a manifest can be
    edited between build and check, and a stage step can substitute a file
    after the check -- and only the second is evidence about the artifact.

    Fat files yield the UUID of every slice, so a universal binary is judged
    if ANY slice came from the host cache.
    """
    if len(data) < 8:
        return [], None, None
    # The fat header is ALWAYS big-endian, even when the Mach-O slices inside
    # it are little-endian.  Reading its magic with a little-endian "<I" yields
    # FAT_CIGAM (0xBEBAFECA) for a normal 0xCAFEBABE file, which matches
    # neither constant and silently rejects every universal binary -- including
    # dyld.orig, the one arm64e-containing file in the contaminated region.
    magic_be = struct.unpack_from(">I", data, 0)[0]
    magic_le = struct.unpack_from("<I", data, 0)[0]
    offsets = []
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        n = struct.unpack_from(">I", data, 4)[0]
        if n > 64:
            return [], None, None
        for i in range(n):
            cputype = struct.unpack_from(">I", data, 8 + i * 20)[0]
            off = struct.unpack_from(">I", data, 8 + i * 20 + 8)[0]
            # Accept every 64-bit-capable slice we understand.  arm64e carries
            # cputype 0x0100000C with the high subtype bit set, so filtering on
            # cputype alone (not cputype+subtype) keeps arm64e, which matters:
            # an arm64e slice is itself evidence the repo never built the file.
            if cputype in (CPU_TYPE_X86_64, CPU_TYPE_ARM64):
                offsets.append(off)
    elif magic_le == MH_MAGIC_64:
        offsets = [0]
    else:
        return [], None, None

    uuids = []
    text_vmaddr = None
    filetype = None
    for off in offsets:
        if off + 32 > len(data):
            continue
        filetype = struct.unpack_from("<I", data, off + 12)[0]
        ncmds = struct.unpack_from("<I", data, off + 16)[0]
        p = off + 32
        for _ in range(ncmds):
            if p + 8 > len(data):
                break
            cmd, cmdsize = struct.unpack_from("<II", data, p)
            if cmdsize < 8:
                break
            if cmd == LC_UUID and cmdsize >= 24 and p + 24 <= len(data):
                uuids.append(bytes(data[p + 8:p + 24]))
            elif cmd == LC_SEGMENT_64 and cmdsize >= 72 and p + 72 <= len(data):
                if data[p + 8:p + 24].rstrip(b"\x00") == b"__TEXT":
                    text_vmaddr = struct.unpack_from("<Q", data, p + 24)[0]
            p += cmdsize
    return uuids, text_vmaddr, filetype


def macho_uuids_and_text(path):
    """Path wrapper around macho_uuids_and_text_bytes()."""
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except (IOError, OSError):
        return [], None, None
    return macho_uuids_and_text_bytes(data)


def iter_tree(root):
    """Every regular file under `root` (or `root` itself if it is a file)."""
    if os.path.isfile(root):
        yield root
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            yield os.path.join(dirpath, name)


# --------------------------------------------------------------------------
# Manifest closure
# --------------------------------------------------------------------------

class ManifestSourceError(Exception):
    """A manifest entry names a source that is not there.

    Raising rather than skipping is the whole point: a source that cannot be
    read is a staged binary this scan has no verdict on, and a check that
    silently drops what it cannot see prints the same "HOST-EXTRACTED: 0" as
    a check that saw everything.  Those are different claims and only one of
    them is true.
    """


def kernel_payload(base_dir=HERE):
    """Mirror mkimage.newest_kernel(): the newest of the two candidates.

    The kernel is a staged Mach-O like any other, so it belongs in the
    provenance judgement.  It is deliberately NOT a dyld-closure participant
    (closure_check maps it to no source for that reason), which is why the two
    tools resolve it differently -- but "not in the closure" must not silently
    become "not scanned at all".
    """
    cands = [os.path.join(base_dir, "work", "stripped_kernel.development"),
             os.path.join(base_dir, "assets", "kernel.development")]
    cands = [c for c in cands if os.path.isfile(c)]
    if not cands:
        raise ManifestSourceError("no kernel payload: neither "
                                  "work/stripped_kernel.development nor "
                                  "assets/kernel.development exists")
    return max(cands, key=os.path.getmtime)


def manifest_sources(manifest_path):
    """[(staged_path, host_source)] for every staged Mach-O in a manifest.

    Resolution rules are mirrored from closure_check.manifest_staged_files /
    mkimage.py: every relative path resolves against tools/bootlab, NOT
    against the manifest's own directory.  Diverging here would make this tool
    describe a different tree than the one the image is built from.

    Every entry kind that produces BYTES is resolved: "glob", "asset",
    "file", "init", "init_exec" and "kernel".  Only "text" is skipped, because
    an inline string has no provenance.  A missing source raises
    ManifestSourceError rather than being dropped -- see that class.
    """
    base_dir = HERE
    with open(manifest_path) as fh:
        man = json.load(fh)
    out = []
    for ent in man.get("files", []):
        if "glob" in ent:
            srcdir = os.path.join(base_dir, "assets", ent["asset_prefix"])
            if not os.path.isdir(srcdir):
                raise ManifestSourceError("missing asset dir: %s" % srcdir)
            for name in sorted(os.listdir(srcdir)):
                fp = os.path.join(srcdir, name)
                if os.path.isfile(fp):
                    out.append((os.path.join(ent["glob"], name).lstrip("/"), fp))
        elif "asset" in ent:
            p = os.path.join(base_dir, "assets", ent["asset"])
            if not os.path.isfile(p):
                raise ManifestSourceError("missing asset: assets/%s"
                                          % ent["asset"])
            out.append((ent["path"].lstrip("/"), p))
        elif "file" in ent:
            p = ent["file"]
            if not os.path.isabs(p):
                p = os.path.join(base_dir, p)
            if not os.path.isfile(p):
                raise ManifestSourceError("missing file source: %s" % p)
            out.append((ent["path"].lstrip("/"), p))
        elif "init" in ent or "init_exec" in ent:
            # PID 1 is a staged Mach-O and is execve()d by the kernel, so it
            # is exactly the kind of binary this gate exists to judge.  It was
            # skipped here while closure_check resolved it, which meant
            # "no staged binary came from the host cache" was a statement
            # about the tree MINUS the process the kernel starts first.
            which = "init_exec" if ent.get("init_exec") else "init"
            p = os.path.join(base_dir, "work", which)
            if not os.path.isfile(p):
                raise ManifestSourceError("missing %s payload: %s (build it "
                                          "first)" % (which, p))
            out.append((ent["path"].lstrip("/"), p))
        elif "kernel" in ent:
            out.append((ent["path"].lstrip("/"), kernel_payload(base_dir)))
        else:
            # "text": an inline string.  No bytes, no provenance, nothing to
            # judge -- and nothing to fail to read either.
            pass
    return out


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def rule(title):
    print("")
    print(title)
    print("-" * len(title))


def main():
    ap = argparse.ArgumentParser(
        description="Detect Mach-O binaries extracted from the host's dyld "
                    "shared cache.  Exits 1 if any are found; exits 2 if the "
                    "check could not run, unless --allow-missing-host-cache "
                    "records an explicit waiver.")
    ap.add_argument("--target", action="append", metavar="PATH",
                    help="directory tree (or single file) to scan; repeatable")
    ap.add_argument("--manifest", metavar="JSON",
                    help="scan the resolved closure of this bootlab manifest")
    ap.add_argument("--cache-dir", default=DEFAULT_CACHE_DIR, metavar="DIR",
                    help="host dyld cache directory (default: %s)"
                         % DEFAULT_CACHE_DIR)
    ap.add_argument("--allow-missing-host-cache", action="store_true",
                    help="WAIVER, off by default: if the host cache is missing "
                         "or unreadable, print NOT SATISFIED and exit 0 "
                         "instead of failing closed.  The run is "
                         "NON-AUTHORITATIVE and never prints PASS; it exists "
                         "only to record that a human accepted an unverified "
                         "result")
    ap.add_argument("--verbose", action="store_true",
                    help="per-cache-file progress on stderr")
    ap.add_argument("--no-uuid-cache", action="store_true",
                    help="ignore/rebuild the on-disk memo of the host UUID "
                         "set instead of reusing it")
    args = ap.parse_args()

    if not args.target and not args.manifest:
        ap.error("need --target and/or --manifest")

    print("provenance_scan: host cache = %s" % args.cache_dir)

    # ---- obtain the host UUID set (built ONCE, then reused) ---------------
    # A missing or unreadable host cache means the check CANNOT RUN, and a
    # check that cannot run must not pass: this fails CLOSED by default.
    # --allow-missing-host-cache is the only way to exit 0 in that state, and
    # even then the run is labelled NOT SATISFIED and never PASS.
    uuids = None
    waived = False
    files = cache_files(args.cache_dir)
    rule("HOST CACHE")
    if not files:
        print("  !! NOT SATISFIED: no %s* under %s"
              % (CACHE_BASENAME, args.cache_dir))
        print("  !! The provenance check COULD NOT RUN: without the host")
        print("  !! cache there is no evidence either way, and a check that")
        print("  !! cannot run must not pass.")
        if args.allow_missing_host_cache:
            waived = True
            print("  WAIVER: --allow-missing-host-cache given.  The report")
            print("          below is NON-AUTHORITATIVE and unverified; it")
            print("          does NOT establish that any tree is clean.")
        else:
            print("  FAIL  failing closed.  Run on a machine that has the host")
            print("        cache, point --cache-dir at it, or pass")
            print("        --allow-missing-host-cache to record a waiver.")
    else:
        if args.verbose:
            sys.stderr.write("building host UUID set...\n")
        try:
            if args.no_uuid_cache:
                uuids, nbytes, nfiles = build_host_uuid_set(
                    args.cache_dir, args.verbose)
            else:
                uuids, nbytes, nfiles = cached_host_uuid_set(
                    args.cache_dir, verbose=args.verbose)
        except (IOError, OSError) as exc:
            print("  !! NOT SATISFIED: cache scan failed: %s" % exc)
            print("  !! The provenance check COULD NOT RUN.")
            if args.allow_missing_host_cache:
                waived = True
                print("  WAIVER: --allow-missing-host-cache given.  The report")
                print("          below is NON-AUTHORITATIVE and unverified;")
                print("          it does NOT establish that any tree is clean.")
            else:
                print("  FAIL  failing closed.")
            uuids = None
        else:
            print("  split-cache files scanned: %d" % nfiles)
            print("  bytes read:                %d" % nbytes)
            print("  UUID candidate set:        %d" % len(uuids))

    if uuids is None:
        # The check could not run.  Do NOT scan and print a report: without
        # the host UUID set every file would trivially count as "not in the
        # host cache", which reads like a clean result but is no evidence at
        # all.  Fail closed, or, under an explicit waiver, exit 0 having said
        # plainly that nothing was verified.
        print("")
        print("provenance_scan: CHECK COULD NOT RUN -- NOT SATISFIED")
        if waived:
            print("provenance_scan: waived via --allow-missing-host-cache; "
                  "this exit 0 is NOT a pass")
            return EXIT_CLEAN
        return EXIT_CANNOT_RUN

    # ---- collect the files to judge ----------------------------------------
    to_scan = []           # (label, host_path)
    if args.target:
        for t in args.target:
            for p in iter_tree(os.path.abspath(t)):
                # Repo-relative when the file is inside the repo; absolute
                # otherwise, so a planted file outside the tree is still
                # reported unambiguously instead of as a pile of ../.
                rel = os.path.relpath(p, REPO)
                label = p if rel.startswith("..") else rel
                to_scan.append((label, p))
    if args.manifest:
        # A relative manifest path is resolved against the CWD, not against
        # tools/bootlab -- the latter is how *entries inside* a manifest
        # resolve, and conflating the two produced a doubled path.
        mp = os.path.abspath(args.manifest)
        if not os.path.isfile(mp):
            sys.stderr.write("provenance_scan: no such manifest: %s\n" % mp)
            return EXIT_CANNOT_RUN
        try:
            sources = manifest_sources(mp)
        except ManifestSourceError as exc:
            # Not a warning.  A staged binary this run could not read is a
            # binary it has no verdict on, and printing a summary anyway
            # would report it as "not in the host cache" -- vacuously true,
            # and indistinguishable from a real pass.
            print("")
            print("!! NOT SATISFIED: %s" % exc)
            print("!! A manifest source could not be read, so the tree it")
            print("!! describes was NOT fully scanned.  Fix or build the")
            print("!! missing piece; the provenance verdict cannot be made.")
            print("")
            print("provenance_scan: CHECK COULD NOT RUN -- NOT SATISFIED")
            return EXIT_CANNOT_RUN
        for staged, src in sources:
            if src is not None:
                to_scan.append((staged, src))

    # de-dup by host path, preserving first-seen order
    seen = set()
    ordered = []
    for label, p in to_scan:
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        ordered.append((label, p))

    # ---- judge -------------------------------------------------------------
    scanned = hits = 0
    dirty = []
    for label, p in ordered:
        uuids_found, text_vmaddr, filetype = macho_uuids_and_text(p)
        if not uuids_found and text_vmaddr is None:
            continue                       # not a Mach-O we can read
        scanned += 1
        if uuids is not None and any(u in uuids for u in uuids_found):
            hits += 1
            dirty.append((label, uuids_found, text_vmaddr, filetype))

    rule("SCANNED")
    print("  Mach-O files examined: %d" % scanned)
    origins = ["target %s" % t for t in (args.target or [])]
    if args.manifest:
        origins.append("manifest %s" % os.path.basename(args.manifest))
    print("  source: %s" % (", ".join(origins) or "(none)"))

    if dirty:
        rule("HOST-EXTRACTED BINARIES (LC_UUID found in the host cache)")
        print("  %-64s %-34s %s" % ("path", "uuid", "__TEXT vmaddr"))
        for label, uu, tvm, ft in dirty:
            print("  %-64s %-34s %s"
                  % (label, uu[0].hex(), hex(tvm) if tvm is not None else "-"))
        print("")
        print("  These %d file(s) came out of the host Mac's dyld shared cache." % hits)
        print("  They are Apple binaries: not built by this repository, not")
        print("  ours to ship, and not fixable by rebuilding.")

    print("")
    print("HOST-EXTRACTED: %d" % hits)
    print("NOT-IN-HOST-CACHE: %d" % (scanned - hits))

    print("provenance_scan: %s" % ("FAIL" if dirty else "PASS"))
    return EXIT_DIRTY if dirty else EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main())