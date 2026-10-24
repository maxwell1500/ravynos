#!/usr/bin/env python3
"""verify_class_provider.py -- static gates for the Objective-C class provider.

  python3 tools/bootlab/verify_class_provider.py

Reads work/chrome_plan.json (written by chrome_stage.py) and checks the
provider image and every dependency shim that traps Objective-C class symbols.

GATES
  G1  the provider exports exactly one class symbol and one metaclass symbol
      per synthesized class, and every one of them is S-type: the symbol's
      ADDRESS is the objc_class structure, which is what Chrome's
      __objc_classrefs binds expect.  A D-type slot cannot satisfy that.
  G2  the provider carries __objc_classlist, __objc_imageinfo and __objc_data,
      and otool -ov prints the canonical modern layout (isa -> its own
      metaclass, superclass -> libobjc's NSObject, cache -> __objc_empty_cache).
  G3  no dependency shim traps an Objective-C class or metaclass symbol any
      more: every one of them is satisfied by a staged image (a re-export
      edge) or by the provider (a re-export edge).
  G4  every dependency that traps an Objective-C class symbol re-exports the
      provider, because Chrome's binds are library-scoped: dyld resolves
      Metal/_OBJC_CLASS_$_MTLTextureDescriptor against the NAMED library's
      export list and walks that library's libReExported chain.
  G5  no synthesized class name collides with a class any staged image or any
      Chrome payload image defines -- two class objects with one name make the
      runtime's addNamedClass warn and keep the OLD mapping.

dyld_info -fixups is deliberately not a gate: it does not faithfully decode
staged images' bind streams (BOOT-PLAN.md 22, class-provider plan section 8).
"""
import collections
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
PLAN_JSON = os.path.join(WORK, "chrome_plan.json")
PAYLOAD = os.path.join(WORK, "chrome-payload")
SHIMS = os.path.join(WORK, "chrome-shims")
BASE_MANIFEST = os.path.join(HERE, "manifest_gui.json")

OBJC_CLASS_PREFIX = "_OBJC_CLASS_$_"
OBJC_META_PREFIX = "_OBJC_METACLASS_$_"

MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe",
                b"\xbe\xba\xfe\xca", b"\xce\xfa\xed\xfe", b"\xed\xfe\xfa\xce")

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))
    print("%-4s %-58s %s" % ("PASS" if ok else "FAIL", name, detail))
    return bool(ok)


def sh(cmd, check_rc=True):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check_rc and r.returncode != 0:
        sys.exit("FATAL: %s -> rc=%d\n%s%s"
                 % (" ".join(cmd), r.returncode, r.stdout, r.stderr))
    return r.stdout


def is_macho(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) in MACHO_MAGICS
    except OSError:
        return False


def nm_types(path):
    """{symbol: nm type letter} for the image's global symbols."""
    out = {}
    for line in sh(["nm", "-g", path], check_rc=False).splitlines():
        p = line.split(maxsplit=2)
        if len(p) == 3:
            out[p[2]] = p[1]
    return out


def reexport_targets(path):
    """The install names this image re-exports (LC_REEXPORT_DYLIB).

    otool prints the load command as "cmd LC_REEXPORT_DYLIB", then
    "cmdsize N", then "name <path> (offset N)" -- so the name line is not
    adjacent to the cmd line."""
    out = []
    want = False
    for line in sh(["otool", "-l", path], check_rc=False).splitlines():
        s = line.strip()
        if s.startswith("cmd "):
            want = (s == "cmd LC_REEXPORT_DYLIB")
            continue
        if want and s.startswith("name "):
            out.append(s[len("name "):].split(" (")[0].strip())
            want = False
    return out


def defined_class_names(path):
    """The class names an image DEFINES.

    Taken from the image's own __objc_classlist section only: the classlist
    holds the classes the image defines, and the entry's symbol name IS the
    class name.  __objc_classrefs uses the same "<addr> <ptr> <symbol>" line
    format but holds REFERENCES to classes defined elsewhere, so the section
    has to be selected rather than the whole dump.  (Scraping every
    "name 0x... X" line would also pick up categories and protocols.)"""
    out = set()
    in_list = False
    for ln in sh(["otool", "-ov", path], check_rc=False).splitlines():
        if ln.startswith("Contents of"):
            in_list = "__objc_classlist" in ln
            continue
        if not in_list:
            continue
        m = re.match(r"^[0-9a-f]{8,16} 0x[0-9a-f]+ _OBJC_CLASS_\$_(\S+)$", ln)
        if m:
            out.add(m.group(1))
    return out


def main():
    if not os.path.isfile(PLAN_JSON):
        sys.exit("missing %s -- run tools/bootlab/chrome_stage.py first"
                 % PLAN_JSON)
    with open(PLAN_JSON) as f:
        plan = json.load(f)

    prov = plan.get("class_provider")
    if not prov:
        sys.exit("plan has no class_provider record -- chrome_stage.py did not "
                 "build the provider")
    classes = prov["classes"]
    install = prov["install_name"]
    host = prov["host_path"]
    staged = os.path.join(SHIMS, install.lstrip("/"))

    # ---------------------------------------------------------------- G1
    syms = nm_types(staged)
    bad = []
    for n in classes:
        for s in (OBJC_CLASS_PREFIX + n, OBJC_META_PREFIX + n):
            if syms.get(s) != "S":
                bad.append("%s=%s" % (s, syms.get(s)))
    check("G1 provider exports %d classes + %d metaclasses, all S-type"
          % (len(classes), len(classes)),
          not bad and len(classes) > 0,
          "" if not bad else "%d wrong: %s" % (len(bad), ", ".join(bad[:4])))

    # ---------------------------------------------------------------- G2
    secs = sh(["otool", "-l", staged], check_rc=False)
    want = [s for s in ("__objc_classlist", "__objc_imageinfo", "__objc_data")
            if s not in secs]
    check("G2 provider carries the ObjC sections", not want,
          "" if not want else "missing %s" % ", ".join(want))
    lines = sh(["otool", "-ov", staged], check_rc=False).splitlines()
    layout_ok = True
    detail = ""
    for sample in (classes[0], classes[-1]):
        idx = None
        for i, ln in enumerate(lines):
            if ln.endswith("_OBJC_CLASS_$_" + sample):
                idx = i
                break
        blk = "\n".join(lines[idx:idx + 6]) if idx is not None else ""
        if idx is None or (OBJC_META_PREFIX + sample) not in blk \
                or "_OBJC_CLASS_$_NSObject" not in blk \
                or "__objc_empty_cache" not in blk:
            layout_ok = False
            detail = "sample %s:\n%s" % (sample, blk)
            break
    check("G2 otool -ov shows the canonical modern class layout", layout_ok,
          detail)

    # ---------------------------------------------------------------- G3
    leftover = {}
    for path, rec in plan["deps"].items():
        bad_syms = [s for s in (rec.get("traps_effective") or [])
                    if s.startswith(OBJC_CLASS_PREFIX)
                    or s.startswith(OBJC_META_PREFIX)]
        if bad_syms:
            leftover[path] = bad_syms
    check("G3 no shim traps an ObjC class/metaclass symbol", not leftover,
          "" if not leftover else
          "; ".join("%s: %d" % (p, len(v)) for p, v in sorted(leftover.items())))

    # ---------------------------------------------------------------- G4
    need = [p for p, rec in plan["deps"].items()
            if rec.get("provider_covered")]
    missing_edge = []
    for path in need:
        shim = os.path.join(SHIMS, rec_shim(plan, path).lstrip("/"))
        if install not in reexport_targets(shim):
            missing_edge.append(path)
    check("G4 all %d ObjC deps re-export the provider" % len(need),
          not missing_edge and len(need) > 0,
          "" if not missing_edge else
          "%d without the edge: %s" % (len(missing_edge), missing_edge[:3]))

    # ---------------------------------------------------------------- G5
    coll = {}
    staged_names = set()
    with open(BASE_MANIFEST) as f:
        man = json.load(f)
    for e in man["files"]:
        src = e.get("file")
        if not src:
            continue
        if not os.path.isabs(src):
            src = os.path.join(HERE, src)
        if os.path.isfile(src) and is_macho(src):
            staged_names |= defined_class_names(src)
    payload_names = set()
    for dp, dn, fn in os.walk(PAYLOAD):
        for n in fn:
            p = os.path.join(dp, n)
            if is_macho(p):
                payload_names |= defined_class_names(p)
    for other in (staged_names, payload_names):
        hit = other & set(classes)
        if hit:
            coll["staged" if other is staged_names else "payload"] = sorted(hit)
    check("G5 no synthesized name collides with a staged/payload class",
          not coll,
          "" if not coll else json.dumps(coll)[:200])

    print("")
    bad = [n for n, ok, _ in RESULTS if not ok]
    print("%d/%d gates passed" % (len(RESULTS) - len(bad), len(RESULTS)))
    if bad:
        print("FAILED: %s" % ", ".join(bad))
    return 1 if bad else 0


def rec_shim(plan, path):
    return plan["deps"][path].get("shim_at") or path


if __name__ == "__main__":
    sys.exit(main())
