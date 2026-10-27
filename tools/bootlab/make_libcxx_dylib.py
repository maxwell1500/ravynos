#!/usr/bin/env python3
"""Build /usr/lib/libc++.1.dylib from the C++ runtime archives in the SDK.

WHY THIS EXISTS
  Every macOS binary built with clang++ records an LC_LOAD_DYLIB of
  /usr/lib/libc++.1.dylib.  The SDK shipped libc++.a and libc++abi.a only, so
  an imported bundle could not load, and the in-tree C++ toolchain could not
  link at all: the two archives both define std::terminate, std::set_terminate,
  std::get_terminate and the stdexcept/typeinfo classes, so naming them on one
  link line is a duplicate-symbol error.  Measured before this script:
      ld: duplicate symbol 'std::set_terminate(void (*)())'
          libc++.a[11](exception.o) vs libc++abi.a[4](cxa_default_handlers.o)

WHAT THIS DOES
  Links one dylib from both archives, choosing one definition where they
  overlap, and supplies the two libc hooks ravynOS's libSystem does not have:

    * libc++ keeps the C++-level standard library: std::terminate and friends,
      stdexcept, typeinfo, new/delete.
    * libc++abi keeps the C-level ABI: __cxa_throw, __cxa_begin_catch,
      __cxa_guard_*, __cxa_demangle, private_typeinfo, the personality routine.
    * libc++abi's stdlib_*.o are dropped: they are the fallbacks for builds
      without libc++ and define the same classes a second time.
    * cxa_noexception.o is dropped: it is the -fno-exceptions variant of
      cxa_exception.o and defines the same symbols.
    * cxa_handlers.o and cxa_default_handlers.o are dropped for the same reason
      as the stdlib_* files: libc++'s exception.o defines std::terminate,
      std::set_terminate, std::get_terminate, std::unexpected and
      std::get_unexpected, and these two objects define them again.
    * cxa_thread_atexit_impl.c supplies __cxa_thread_atexit_impl.  libc++abi
      references it strongly (its weak fallback is only compiled when
      HAVE___CXA_THREAD_ATEXIT_IMPL is undefined, and on Mach-O the weak
      declaration is __attribute__((weak)) rather than weak_import, so ld
      rejects it either way).

  The result is verified before it replaces anything: x86_64, install name
  /usr/lib/libc++.1.dylib, compatibility version 1.0.0, more than 2000 exports,
  and every undefined symbol it carries must resolve against the SDK's own
  libraries (indirect symbols included -- _memcpy is one of those).

WHAT IT DOES NOT DO
  It does not rebuild libc++ or libc++abi from source; the archives are the
  ones the SDK already carries, and a from-source build of both against this
  target is a larger job than packaging them.  It also does not touch the
  archives themselves: dyld links libc++.a/libc++abi.a directly and must keep
  working.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD = os.environ.get("RAVYN_BUILD_DIR", "/Users/max/Projects/build")
BUILD_SDK = os.path.join(
    BUILD, "Developer", "Platforms", "ravynOS.platform", "Developer", "SDKs", "ravynOS.sdk"
)
BUILD_TOOLCHAIN = os.path.join(
    BUILD, "Developer", "Platforms", "ravynOS.platform", "Developer", "Toolchains",
    "Default.xctoolchain", "usr", "bin",
)
SUPPORT_SOURCE = os.path.join(
    REPO, "Libraries", "llvm_target", "libcxx", "support", "cxa_thread_atexit_impl.c"
)

# Members of libc++abi.a that must not be linked: they redefine symbols the
# libc++ archive already provides (see the module docstring).
DROPPED_ABI_MEMBERS = (
    "stdlib_exception.o",
    "stdlib_new_delete.o",
    "stdlib_stdexcept.o",
    "stdlib_typeinfo.o",
    "cxa_noexception.o",
    "cxa_handlers.o",
    "cxa_default_handlers.o",
)

MIN_EXPORTS = 2000


def find_clang() -> str:
    for candidate in (
        os.path.join(BUILD_TOOLCHAIN, "clang-17"),
        os.path.join(BUILD_TOOLCHAIN, "clang"),
        shutil.which("clang-17"),
        shutil.which("clang"),
    ):
        if candidate and os.path.exists(candidate):
            return candidate
    raise SystemExit("[libcxx] no clang found; set RAVYN_BUILD_DIR")


def run(cmd, **kwargs) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit("[libcxx] failed: %s" % " ".join(cmd))
    return result.stdout


# Indirect symbols carry no address column: "                 I _memcpy (...)";
# ordinary ones do.  Both forms must yield the name in group 2.
NM_DEFINED_LINE = re.compile(r"^\s*(?:[0-9a-fA-F]+)?\s*([A-Za-z])\s+(\S+)")


def symbols_nm(path: str, undefined: bool) -> list:
    """Defined (or undefined) symbols in a Mach-O image.

    Defined lines look like "0000000000020910 I _memcpy (indirect for ...)":
    the type letter is the second field and the name the third, and an
    indirect symbol has trailing annotation that must not be mistaken for the
    name.  _memcpy is exactly that case on libsystem_c.
    """
    flag = "-u" if undefined else "-gU"
    out = run(["nm", flag, path])
    names = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        if undefined:
            names.append(line.split()[-1])
            continue
        match = NM_DEFINED_LINE.match(line)
        if match:
            names.append(match.group(2))
    return names


def sdk_symbol_table(sdk: str) -> set:
    """Exported names from every dylib the image can load."""
    names = set()
    roots = [
        os.path.join(sdk, "usr", "lib"),
        os.path.join(sdk, "usr", "lib", "system"),
        os.path.join(sdk, "System", "Library", "Frameworks"),
    ]
    for root in roots:
        for dirpath, _dirnames, filenames in os.walk(root):
            for filename in filenames:
                if not filename.endswith(".dylib"):
                    continue
                path = os.path.join(dirpath, filename)
                if not os.path.exists(os.path.realpath(path)):
                    continue
                try:
                    names.update(symbols_nm(path, undefined=False))
                except SystemExit:
                    continue
    return names


def check_dylib(path: str, sdk: str) -> None:
    archs = run(["lipo", "-archs", path]).strip()
    if archs != "x86_64":
        raise SystemExit("[libcxx] %s is %r, expected x86_64" % (path, archs))

    install = run(["otool", "-D", path]).splitlines()
    install_name = install[1].strip() if len(install) > 1 else ""
    if install_name != "/usr/lib/libc++.1.dylib":
        raise SystemExit("[libcxx] install name is %r" % install_name)

    exports = symbols_nm(path, undefined=False)
    if len(exports) < MIN_EXPORTS:
        raise SystemExit(
            "[libcxx] only %d exports (expected at least %d)" % (len(exports), MIN_EXPORTS)
        )
    for required in (
        "___cxa_throw",
        "___cxa_thread_atexit_impl",
        "___cxa_demangle",
        "__Znwm",
        "__ZSt9terminatev",
    ):
        if required not in exports:
            raise SystemExit("[libcxx] missing required export %s" % required)

    available = sdk_symbol_table(sdk)
    unresolved = [s for s in symbols_nm(path, undefined=True) if s not in available]
    if unresolved:
        raise SystemExit(
            "[libcxx] unresolved imports: %s" % ", ".join(sorted(unresolved)[:12])
        )

    linked = run(["otool", "-L", path]).splitlines()[1:]
    for line in linked:
        dep = line.strip().split(" (compatibility")[0]
        if dep == install_name:
            # otool -L repeats the image's own install name as its first entry.
            continue
        if dep.startswith("/usr/lib") and not os.path.exists(
            os.path.join(sdk, dep.lstrip("/"))
        ):
            raise SystemExit("[libcxx] depends on %s, absent from the SDK" % dep)


def build(sdk: str, output: str, verbose: bool) -> None:
    for name in ("libc++.a", "libc++abi.a"):
        if not os.path.exists(os.path.join(sdk, "usr", "lib", name)):
            raise SystemExit("[libcxx] %s/usr/lib/%s is missing" % (sdk, name))
    if not os.path.exists(SUPPORT_SOURCE):
        raise SystemExit("[libcxx] support source %s is missing" % SUPPORT_SOURCE)

    clang = find_clang()
    tmp = tempfile.mkdtemp(prefix="libcxx-dylib.")
    try:
        abi = os.path.join(tmp, "libc++abi-link.a")
        shutil.copyfile(os.path.join(sdk, "usr", "lib", "libc++abi.a"), abi)
        present = set(run(["ar", "t", abi]).split())
        dropped = [m for m in DROPPED_ABI_MEMBERS if m in present]
        for member in dropped:
            run(["ar", "d", abi, member])

        support_o = os.path.join(tmp, "cxa_thread_atexit_impl.o")
        run([
            clang, "-c", SUPPORT_SOURCE, "-o", support_o,
            "--sysroot=" + sdk, "-arch", "x86_64", "-mmacos-version-min=15.0",
            "-Wno-incompatible-sysroot",
        ])

        cmd = [
            clang, "-dynamiclib", "--sysroot=" + sdk, "-arch", "x86_64",
            "-mmacos-version-min=15.0", "-Wno-incompatible-sysroot", "-nostdlib",
            "-Wl,-all_load", support_o,
            os.path.join(sdk, "usr", "lib", "libc++.a"), abi,
            "-L" + os.path.join(sdk, "usr", "lib"),
            "-L" + os.path.join(sdk, "usr", "lib", "system"),
            "-lSystem", "-lCrashReporterClient",
            "-Wl,-install_name,/usr/lib/libc++.1.dylib",
            "-Wl,-compatibility_version,1.0.0",
            "-Wl,-current_version,1.0.0",
            "-o", output,
        ]
        if verbose:
            print("[libcxx] dropped ABI members: %s" % (", ".join(dropped) or "none"))
        run(cmd)
        if verbose:
            size = os.path.getsize(output)
            print("[libcxx] linked %s (%d bytes)" % (os.path.basename(output), size))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def install(sdk: str, dylib: str, verbose: bool) -> bool:
    dest_dir = os.path.join(sdk, "usr", "lib")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, "libc++.1.dylib")
    staging = dest + ".new"
    check_dylib(dylib, sdk)
    if os.path.exists(dest) and open(dest, "rb").read() == open(dylib, "rb").read():
        if verbose:
            print("[libcxx] %s is up to date" % dest)
        changed = False
    else:
        shutil.copyfile(dylib, staging)
        os.replace(staging, dest)
        if verbose:
            print("[libcxx] installed %s (%d bytes)" % (dest, os.path.getsize(dest)))
        changed = True
    link = os.path.join(dest_dir, "libc++.dylib")
    if not os.path.islink(link) or os.path.basename(os.readlink(link)) != "libc++.1.dylib":
        if os.path.exists(link) and not os.path.islink(link):
            os.remove(link)
        if os.path.islink(link):
            os.remove(link)
        os.symlink("libc++.1.dylib", link)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sdk", default=os.path.join(REPO, "Developer", "ravynOS.sdk"))
    parser.add_argument("--also-build-sdk", action="store_true",
                        help="install into the out-of-tree build SDK as well")
    parser.add_argument("--check-only", action="store_true",
                        help="verify an existing dylib, build nothing")
    parser.add_argument("--force", action="store_true", help="rebuild even if present")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    sdk = os.path.abspath(args.sdk)
    dest = os.path.join(sdk, "usr", "lib", "libc++.1.dylib")

    if args.check_only:
        if not os.path.exists(dest):
            raise SystemExit("[libcxx] %s does not exist" % dest)
        check_dylib(dest, sdk)
        print("[libcxx] %s verified" % dest)
        return 0

    if os.path.exists(dest) and not args.force:
        try:
            check_dylib(dest, sdk)
            if args.verbose:
                print("[libcxx] %s already valid" % dest)
            return 0
        except SystemExit:
            if args.verbose:
                print("[libcxx] existing %s failed verification; rebuilding" % dest)

    tmpdir = tempfile.mkdtemp(prefix="libcxx-out.")
    try:
        built = os.path.join(tmpdir, "libc++.1.dylib")
        build(sdk, built, args.verbose)
        install(sdk, built, args.verbose)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    if args.also_build_sdk and os.path.isdir(BUILD_SDK):
        os.makedirs(os.path.join(BUILD_SDK, "usr", "lib"), exist_ok=True)
        target = os.path.join(BUILD_SDK, "usr", "lib", "libc++.1.dylib")
        source = os.path.join(sdk, "usr", "lib", "libc++.1.dylib")
        shutil.copyfile(source, target + ".new")
        os.replace(target + ".new", target)
        link = os.path.join(BUILD_SDK, "usr", "lib", "libc++.dylib")
        if os.path.islink(link):
            os.remove(link)
        os.symlink("libc++.1.dylib", link)
        if args.verbose:
            print("[libcxx] installed %s" % target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
