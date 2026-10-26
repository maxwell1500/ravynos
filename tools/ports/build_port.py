#!/usr/bin/env python3
"""build_port.py -- build a third-party source port against the ravynOS SDK.

A port is a directory under tools/ports/<name>/ with a port.json that says how
to build it; this driver supplies the cross-compiler, the sysroot, pkg-config
and the install staging so the port's own build system needs no changes.

port.json fields
  name          port name (defaults to the directory name)
  version       upstream version, for the log line
  src           source directory, relative to the port (default ".")
  build_system  "cmake" | "autotools" | "make"
  cmake_args    extra -D arguments (cmake)
  configure_args extra ./configure arguments (autotools)
  make_args     extra make arguments
  make_targets  make targets (default ["all"])
  install       "destdir" (autotools/make: make DESTDIR=...) or "cmake"
  prefix        install prefix inside the staging root (default /usr)
  bundle        {name, id, executable, info_extra} to package the binary as
                <name>.app under /Applications
  strip         true to strip the installed binaries

WHAT IT LEAVES BEHIND
  tools/ports/<name>/build-obj/    the build tree (ignored by git)
  tools/bootlab/work/ports/        the install staging root, which becomes the
                                   manifest source for the boot image
"""

import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
SDK = os.path.join(REPO, "Developer", "ravynOS.sdk")
TOOLCHAIN = os.path.join(REPO, "Developer", "cmake", "ravynos.toolchain.cmake")
CC = os.path.join(REPO, "tools", "sdk", "bin", "ravynos-cc")
CXX = os.path.join(REPO, "tools", "sdk", "bin", "ravynos-c++")
PKG_CONFIG = os.path.join(REPO, "tools", "sdk", "bin", "ravynos-pkg-config")
STAGE_ROOT = os.path.join(REPO, "tools", "bootlab", "work", "ports")


def log(msg):
    print("build_port: %s" % msg, flush=True)


def die(msg):
    print("build_port: %s" % msg, file=sys.stderr, flush=True)
    sys.exit(1)


def run(cmd, cwd=None, env=None):
    log("$ " + " ".join(cmd))
    result = subprocess.run(cmd, cwd=cwd, env=env)
    if result.returncode != 0:
        die("command failed with status %d" % result.returncode)


def base_env():
    env = dict(os.environ)
    env["RAVYN_SDKROOT"] = SDK
    env["SYSROOT_DIR"] = SDK
    env["CC"] = CC
    env["CXX"] = CXX
    env["PKG_CONFIG"] = PKG_CONFIG
    env["PKG_CONFIG_LIBDIR"] = os.path.join(SDK, "usr", "lib", "pkgconfig")
    env["PKG_CONFIG_SYSROOT_DIR"] = SDK
    env["CFLAGS"] = (env.get("CFLAGS", "") + " -I%s/usr/include" % SDK).strip()
    env["LDFLAGS"] = (env.get("LDFLAGS", "") + " -L%s/usr/lib -L%s/usr/lib/system"
                      % (SDK, SDK)).strip()
    return env


def load_port(arg):
    path = arg if os.path.isdir(arg) else os.path.join(HERE, arg)
    if not os.path.isdir(path):
        die("no such port: %s" % arg)
    config_path = os.path.join(path, "port.json")
    if not os.path.isfile(config_path):
        die("%s has no port.json" % path)
    with open(config_path) as f:
        config = json.load(f)
    config.setdefault("name", os.path.basename(path))
    config.setdefault("src", ".")
    config.setdefault("build_system", "cmake")
    config.setdefault("prefix", "/usr")
    config.setdefault("make_targets", ["all"])
    return path, config


def package_bundle(config, stage_dir):
    """Wrap an installed executable into <Bundle>.app under /Applications."""
    bundle = config.get("bundle")
    if not bundle:
        return None
    exe_name = bundle.get("executable") or config["name"]
    candidates = [
        os.path.join(stage_dir, "usr", "bin", exe_name),
        os.path.join(stage_dir, "usr", "local", "bin", exe_name),
    ]
    exe = next((c for c in candidates if os.path.isfile(c)), None)
    if exe is None:
        die("bundle executable %r was not installed" % exe_name)

    app_name = bundle["name"]
    app_root = os.path.join(stage_dir, "Applications", "%s.app" % app_name)
    macos_dir = os.path.join(app_root, "Contents", "MacOS")
    resources_dir = os.path.join(app_root, "Contents", "Resources")
    os.makedirs(macos_dir, exist_ok=True)
    os.makedirs(resources_dir, exist_ok=True)
    shutil.copy2(exe, os.path.join(macos_dir, exe_name))
    os.chmod(os.path.join(macos_dir, exe_name), 0o755)

    info = {
        "CFBundleDevelopmentRegion": "English",
        "CFBundleExecutable": exe_name,
        "CFBundleIdentifier": bundle.get("id", "org.ravynos.%s" % config["name"]),
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": app_name,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": config.get("version", "1.0"),
        "CFBundleVersion": config.get("version", "1.0"),
        "LSMinimumSystemVersion": "15.0",
    }
    info.update(bundle.get("info_extra", {}))
    with open(os.path.join(app_root, "Contents", "Info.plist"), "wb") as f:
        plistlib.dump(info, f)
    return app_root


def build(name_or_dir, install_sdk):
    port_dir, config = load_port(name_or_dir)
    source_dir = os.path.abspath(os.path.join(port_dir, config["src"]))
    obj_dir = os.path.join(port_dir, "build-obj")
    stage_dir = os.path.join(STAGE_ROOT, config["name"])
    prefix = config["prefix"]

    if install_sdk:
        run([sys.executable, os.path.join(REPO, "tools", "bootlab", "sync_sdk.py")])

    for path in (SDK, TOOLCHAIN, CC, CXX, PKG_CONFIG):
        if not os.path.exists(path):
            die("missing toolchain component: %s" % path)

    env = base_env()
    os.makedirs(obj_dir, exist_ok=True)
    if os.path.isdir(stage_dir):
        shutil.rmtree(stage_dir)
    os.makedirs(stage_dir, exist_ok=True)

    build_system = config["build_system"]
    if build_system == "cmake":
        cmake_cmd = [
            "cmake", "-S", source_dir, "-B", obj_dir,
            "-DCMAKE_TOOLCHAIN_FILE=%s" % TOOLCHAIN,
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_INSTALL_PREFIX=%s" % prefix,
            "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH",
            "-DBUILD_SHARED_LIBS=OFF",
        ]
        cmake_cmd.extend(config.get("cmake_args", []))
        run(cmake_cmd, env=env)
        run(["cmake", "--build", obj_dir, "--parallel"], env=env)
        # cmake --install writes to CMAKE_INSTALL_PREFIX; DESTDIR is what puts
        # it under the staging root without changing the prefix the binary
        # records, which is the same convention autotools and make use below.
        install_env = dict(env)
        install_env["DESTDIR"] = stage_dir
        run(["cmake", "--install", obj_dir], env=install_env)
    elif build_system == "autotools":
        if not os.path.isfile(os.path.join(source_dir, "configure")):
            run(["./autogen.sh"] if os.path.isfile(os.path.join(source_dir, "autogen.sh"))
                else ["autoreconf", "-i"], cwd=source_dir, env=env)
        configure = [
            "./configure",
            "--host=x86_64-apple-darwin24",
            "--prefix=%s" % prefix,
            "CC=%s" % CC, "CXX=%s" % CXX, "PKG_CONFIG=%s" % PKG_CONFIG,
            "ac_cv_func_malloc_0_nonnull=yes",
            "ac_cv_func_realloc_0_nonnull=yes",
        ]
        configure.extend(config.get("configure_args", []))
        run(configure, cwd=obj_dir if os.path.normpath(obj_dir) != os.path.normpath(source_dir) else source_dir,
            env=env)
        make_cwd = obj_dir
        run(["make", "-j4"], cwd=make_cwd, env=env)
        install_env = dict(env)
        install_env["DESTDIR"] = stage_dir
        run(["make", "install"], cwd=make_cwd, env=install_env)
    elif build_system == "make":
        make_cmd = ["make", "-j4", "CC=%s" % CC, "CXX=%s" % CXX,
                    "PKG_CONFIG=%s" % PKG_CONFIG, "PREFIX=%s" % prefix]
        make_cmd.extend(config.get("make_args", []))
        run(make_cmd, cwd=source_dir, env=env)
        install_env = dict(env)
        install_env["DESTDIR"] = stage_dir
        run(["make", "install", "PREFIX=%s" % prefix] +
            config.get("make_args", []), cwd=source_dir, env=install_env)
    else:
        die("unknown build_system %r" % build_system)

    if config.get("strip", True):
        for root, _dirs, files in os.walk(os.path.join(stage_dir, "usr")):
            for name in files:
                path = os.path.join(root, name)
                if name.endswith(".a") or os.path.islink(path):
                    continue
                with open(path, "rb") as f:
                    if f.read(4) not in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
                        continue
                subprocess.run(["strip", "-x", path], capture_output=True)
                subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", path],
                               capture_output=True)

    # The staging tree is shaped like an image root (usr/, Applications/), and
    # build_port keeps it under work/ports/<name>/.  make_gui_manifest.py
    # treats every immediate child of work/ports as one image root.
    app = package_bundle(config, stage_dir)
    log("%s %s built%s" % (config["name"], config.get("version", ""),
                           (" -> " + os.path.relpath(app, REPO)) if app else ""))
    log("staging root: %s" % os.path.relpath(stage_dir, REPO))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("port", help="port name under tools/ports, or a directory")
    parser.add_argument("--install-sdk", action="store_true",
                        help="run sync_sdk.py first so the sysroot is current")
    args = parser.parse_args()
    return build(args.port, args.install_sdk)


if __name__ == "__main__":
    sys.exit(main())
