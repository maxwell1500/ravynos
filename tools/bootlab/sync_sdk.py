#!/usr/bin/env python3
"""Synchronize Developer/ravynOS.sdk (and the build-tree SDK) into a self-contained sysroot.

Copies the built userland libraries (/usr/lib/system/*, libobjc, libz, libc++,
libedit, Onyx2D static archives for freetype/png/jpeg/tiff), installs third-party
public headers (zlib, expat, sqlite3, fontconfig, freetype2, libpng, libjpeg,
libtiff, Linux userland compatibility shims), and generates pkg-config (.pc)
files so standard open-source C/C++/Objective-C projects cross-compile against
Developer/ravynOS.sdk out of the box.
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
BUILD = os.environ.get("RAVYN_BUILD_DIR", "/Users/max/Projects/build")
BUILD_SDK = os.path.join(
    BUILD, "Developer", "Platforms", "ravynOS.platform", "Developer", "SDKs", "ravynOS.sdk"
)
REPO_SDK = os.environ.get("RAVYN_REPO_SDKROOT", os.path.join(REPO, "Developer", "ravynOS.sdk"))
BUILD_ONYX2D = os.path.join(BUILD, REPO.lstrip("/"), "Frameworks", "Onyx2D")


def copy_if_changed(src: str, dst: str) -> bool:
    if not os.path.exists(src):
        return False
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.islink(src):
        target = os.readlink(src)
        if os.path.islink(dst) and os.readlink(dst) == target:
            return False
        if os.path.exists(dst) or os.path.islink(dst):
            os.unlink(dst)
        os.symlink(target, dst)
        return True
    if os.path.isfile(dst) and not os.path.islink(dst):
        if os.path.getsize(src) == os.path.getsize(dst):
            with open(src, "rb") as f1, open(dst, "rb") as f2:
                if f1.read() == f2.read():
                    return False
    if os.path.islink(dst):
        os.unlink(dst)
    shutil.copy2(src, dst)
    return True


def ensure_symlink(target: str, link_path: str) -> None:
    os.makedirs(os.path.dirname(link_path), exist_ok=True)
    if os.path.islink(link_path) and os.readlink(link_path) == target:
        return
    if os.path.exists(link_path) or os.path.islink(link_path):
        os.unlink(link_path)
    os.symlink(target, link_path)


def sync_tree_files(src_dir: str, dst_dir: str, exts=None) -> int:
    count = 0
    if not os.path.isdir(src_dir):
        return 0
    for root, _, files in os.walk(src_dir):
        rel = os.path.relpath(root, src_dir)
        target_root = dst_dir if rel == "." else os.path.join(dst_dir, rel)
        for name in files:
            if exts and not any(name.endswith(e) for e in exts):
                continue
            s = os.path.join(root, name)
            d = os.path.join(target_root, name)
            if os.path.isfile(s) and os.path.getsize(s) > 0:
                if copy_if_changed(s, d):
                    count += 1
    return count


def sync_libraries() -> None:
    src_sys = os.path.join(BUILD_SDK, "usr", "lib", "system")
    dst_sys = os.path.join(REPO_SDK, "usr", "lib", "system")
    os.makedirs(dst_sys, exist_ok=True)
    if os.path.isdir(src_sys):
        for name in sorted(os.listdir(src_sys)):
            s = os.path.join(src_sys, name)
            d = os.path.join(dst_sys, name)
            if os.path.isfile(s) and os.path.getsize(s) > 0:
                copy_if_changed(s, d)

    src_lib = os.path.join(BUILD_SDK, "usr", "lib")
    dst_lib = os.path.join(REPO_SDK, "usr", "lib")
    os.makedirs(dst_lib, exist_ok=True)

    top_libs = [
        "libobjc.A.dylib",
        "libedit.dylib",
        "libc++.a",
        "libc++abi.a",
        "libz.a",
        "libsbuf.a",
        "libnv.a",
        "libunwind.a",
        "libclang_rt.osx.a",
    ]
    for name in top_libs:
        s = os.path.join(src_lib, name)
        if os.path.isfile(s) and os.path.getsize(s) > 0:
            copy_if_changed(s, os.path.join(dst_lib, name))

    # Also check in-repo Libraries/zlib/libz.a if build SDK lacked it
    repo_libz = os.path.join(REPO, "Libraries", "zlib", "libz.a")
    if os.path.isfile(repo_libz) and os.path.getsize(repo_libz) > 0:
        copy_if_changed(repo_libz, os.path.join(dst_lib, "libz.a"))
        if os.path.isdir(src_lib):
            copy_if_changed(repo_libz, os.path.join(src_lib, "libz.a"))

    # Copy Onyx2D static archives (freetype, libpng16, libjpeg, libtiff)
    onyx_archives = [
        (os.path.join(BUILD_ONYX2D, "freetype", "libfreetype.a"), "libfreetype.a"),
        (os.path.join(BUILD_ONYX2D, "png", "libpng16.a"), "libpng16.a"),
        (os.path.join(BUILD_ONYX2D, "jpeg", "libjpeg.a"), "libjpeg.a"),
        (os.path.join(BUILD_ONYX2D, "jpeg", "libturbojpeg.a"), "libturbojpeg.a"),
        (os.path.join(BUILD_ONYX2D, "tiff", "libtiff", "libtiff.a"), "libtiff.a"),
    ]
    for src_arch, dst_name in onyx_archives:
        if os.path.isfile(src_arch) and os.path.getsize(src_arch) > 0:
            for target_sdk in (REPO_SDK, BUILD_SDK):
                if os.path.isdir(target_sdk):
                    copy_if_changed(src_arch, os.path.join(target_sdk, "usr", "lib", dst_name))

    # libobjc is installed at usr/lib/libobjc.A.dylib, but isysroot-cc links
    # every dylib against the system directory, so built binaries record
    # /usr/lib/system/libobjc.dylib.  A copy (not a symlink) keeps that path a
    # real file, which is what the image manifest stages.
    for target_sdk in (REPO_SDK, BUILD_SDK):
        sys_lib_dir = os.path.join(target_sdk, "usr", "lib", "system")
        objc_src = os.path.join(target_sdk, "usr", "lib", "libobjc.A.dylib")
        if os.path.isdir(sys_lib_dir) and os.path.isfile(objc_src):
            copy_if_changed(objc_src, os.path.join(sys_lib_dir, "libobjc.dylib"))
            copy_if_changed(objc_src, os.path.join(sys_lib_dir, "libobjc.A.dylib"))

    # Standard symlinks in both SDKs
    symlinks = [
        ("libSystem.B.dylib", "libSystem.dylib"),
        ("libSystem.B.dylib", "libc.dylib"),
        ("libSystem.B.dylib", "libm.dylib"),
        ("libSystem.B.dylib", "libpthread.dylib"),
        ("libSystem.B.dylib", "libdl.dylib"),
        ("libSystem.B.dylib", "libinfo.dylib"),
        ("libobjc.A.dylib", "libobjc.dylib"),
        ("libicucore.A.dylib", "libicucore.dylib"),
        ("libpng16.a", "libpng.a"),
    ]
    for target_sdk in (REPO_SDK, BUILD_SDK):
        lib_dir = os.path.join(target_sdk, "usr", "lib")
        if not os.path.isdir(lib_dir):
            continue
        for target, link_name in symlinks:
            if os.path.exists(os.path.join(lib_dir, target)):
                ensure_symlink(target, os.path.join(lib_dir, link_name))


def ensure_versioned_aliases() -> None:
    """Give staged libraries the names and identities macOS clients record.

    A client records the install name of the library it linked, so the file
    has to exist at that exact path inside the image.  Two of the libraries
    the SDK carries were built with the wrong identity:

      libobjc.A.dylib   id /usr/lib/libobjc.dylib, while every prebuilt macOS
                        binary records /usr/lib/libobjc.A.dylib;
      libfontconfig     unversioned id, while clients record
                        /usr/lib/libfontconfig.1.dylib.

    The objc binary is retagged in place (the code is unchanged and both
    paths keep existing), and fontconfig gets a retagged copy.  Neither is a
    symlink: dyld loads the file named by the client, and a copy keeps that
    name's LC_ID_DYLIB honest.
    """
    for target_sdk in (REPO_SDK, BUILD_SDK):
        lib_dir = os.path.join(target_sdk, "usr", "lib")
        if not os.path.isdir(lib_dir):
            continue

        # libobjc is deliberately NOT retagged.  Its LC_ID_DYLIB stays
        # /usr/lib/libobjc.dylib on both the usr/lib and usr/lib/system copies:
        # dyld2 identifies an image by the install name it records, and giving
        # the two copies the same *new* name made every process load both
        # (/usr/lib/system/libobjc.dylib for the executable,
        # /usr/lib/libobjc.A.dylib for the frameworks) and abort with
        # "Class NSObject is implemented in both".  A file simply existing at
        # /usr/lib/libobjc.A.dylib is what imported binaries need.

        fontconfig_src = None
        for candidate in ("libfontconfig.A.dylib", "libfontconfig.dylib"):
            path = os.path.join(lib_dir, candidate)
            if os.path.isfile(path) and not os.path.islink(path):
                fontconfig_src = path
                break
        if fontconfig_src:
            alias = os.path.join(lib_dir, "libfontconfig.1.dylib")
            if not os.path.isfile(alias) or os.path.getsize(alias) == 0:
                shutil.copyfile(fontconfig_src, alias)
                subprocess.run(["install_name_tool", "-id", "/usr/lib/libfontconfig.1.dylib", alias],
                               capture_output=True)


def sync_missing_frameworks() -> None:
    """Copy frameworks that exist only in the build-tree SDK into the repo SDK.

    The image manifest resolves frameworks repo-first and falls back to the
    build tree, so a framework that only lives in the build tree stages from an
    absolute host path and the manifest stops being portable.  CoreServices is
    the one that matters today (every Cocoa application links it via
    Foundation).
    """
    src_frameworks = os.path.join(BUILD_SDK, "System", "Library", "Frameworks")
    dst_frameworks = os.path.join(REPO_SDK, "System", "Library", "Frameworks")
    if not os.path.isdir(src_frameworks):
        return
    needed = ["CoreServices", "LaunchServices"]
    for name in needed:
        src = os.path.join(src_frameworks, name + ".framework")
        dst = os.path.join(dst_frameworks, name + ".framework")
        if not os.path.isdir(src):
            continue
        binary = None
        for version in ("A", "C"):
            candidate = os.path.join(src, "Versions", version, name)
            if os.path.isfile(candidate):
                binary = candidate
                break
        if binary is None:
            continue
        if not os.path.isdir(dst):
            shutil.copytree(src, dst, symlinks=True)
        else:
            copy_if_changed(binary, os.path.join(dst, os.path.relpath(binary, src)))


def sync_headers() -> None:
    single_headers = [
        (os.path.join(REPO, "Libraries", "zlib", "zlib.h"), "zlib.h"),
        (os.path.join(REPO, "Libraries", "zlib", "zconf.h"), "zconf.h"),
        (os.path.join(REPO, "contrib", "expat", "expat.h"), "expat.h"),
        (os.path.join(REPO, "contrib", "expat", "expat_external.h"), "expat_external.h"),
        (os.path.join(REPO, "contrib", "expat", "expat_config.h"), "expat_config.h"),
        (os.path.join(REPO, "contrib", "sqlite3", "sqlite3.h"), "sqlite3.h"),
        (os.path.join(REPO, "contrib", "sqlite3", "sqlite3ext.h"), "sqlite3ext.h"),
        (os.path.join(REPO, "BSD", "lib", "libpng", "png.h"), "png.h"),
        (os.path.join(REPO, "BSD", "lib", "libpng", "pngconf.h"), "pngconf.h"),
        (os.path.join(BUILD_ONYX2D, "png", "pnglibconf.h"), "pnglibconf.h"),
        (os.path.join(REPO, "BSD", "lib", "libjpeg", "jpeglib.h"), "jpeglib.h"),
        (os.path.join(REPO, "BSD", "lib", "libjpeg", "jmorecfg.h"), "jmorecfg.h"),
        (os.path.join(REPO, "BSD", "lib", "libjpeg", "jerror.h"), "jerror.h"),
        (os.path.join(REPO, "BSD", "lib", "libjpeg", "turbojpeg.h"), "turbojpeg.h"),
        (os.path.join(BUILD_ONYX2D, "jpeg", "jconfig.h"), "jconfig.h"),
        (os.path.join(REPO, "BSD", "lib", "libtiff", "libtiff", "tiff.h"), "tiff.h"),
        (os.path.join(REPO, "BSD", "lib", "libtiff", "libtiff", "tiffio.h"), "tiffio.h"),
        (os.path.join(BUILD_ONYX2D, "tiff", "libtiff", "tiffvers.h"), "tiffvers.h"),
        (os.path.join(BUILD_ONYX2D, "tiff", "libtiff", "tiffconf.h"), "tiffconf.h"),
        (
            os.path.join(
                REPO,
                "CoreServices",
                "WindowServer",
                "libevdev",
                "include",
                "linux",
                "linux",
                "input.h",
            ),
            os.path.join("linux", "input.h"),
        ),
        (
            os.path.join(
                REPO,
                "CoreServices",
                "WindowServer",
                "libevdev",
                "include",
                "linux",
                "linux",
                "input-event-codes.h",
            ),
            os.path.join("linux", "input-event-codes.h"),
        ),
        (
            os.path.join(
                REPO,
                "CoreServices",
                "WindowServer",
                "libevdev",
                "include",
                "linux",
                "linux",
                "uinput.h",
            ),
            os.path.join("linux", "uinput.h"),
        ),
    ]

    for target_sdk in (REPO_SDK, BUILD_SDK):
        if not os.path.isdir(target_sdk):
            continue
        inc = os.path.join(target_sdk, "usr", "include")
        for src, rel_dst in single_headers:
            if os.path.isfile(src):
                copy_if_changed(src, os.path.join(inc, rel_dst))

        # libpng16 subdir headers
        for png_hdr in ("png.h", "pngconf.h", "pnglibconf.h"):
            p = os.path.join(inc, png_hdr)
            if os.path.isfile(p):
                copy_if_changed(p, os.path.join(inc, "libpng16", png_hdr))

        # fontconfig headers
        fc_src = os.path.join(REPO, "Frameworks", "CoreText", "fontconfig", "fontconfig")
        sync_tree_files(fc_src, os.path.join(inc, "fontconfig"), exts=(".h",))

        # freetype2 headers
        ft_src = os.path.join(REPO, "Frameworks", "Onyx2D", "freetype", "include")
        sync_tree_files(ft_src, os.path.join(inc, "freetype2"), exts=(".h",))
        sync_tree_files(ft_src, inc, exts=(".h",))

        # Sync usr/local/include/kernel from BUILD_SDK to REPO_SDK so isysroot-cc finds it
        if target_sdk == REPO_SDK:
            kern_inc = os.path.join(BUILD_SDK, "usr", "local", "include", "kernel")
            if os.path.isdir(kern_inc):
                sync_tree_files(kern_inc, os.path.join(REPO_SDK, "usr", "local", "include", "kernel"))


def write_text_if_changed(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = content.encode("utf-8")
    if os.path.isfile(path):
        with open(path, "rb") as f:
            if f.read() == raw:
                return
    with open(path, "wb") as f:
        f.write(raw)


def install_linux_compat_headers() -> None:
    endian_h = """#ifndef _RAVYNOS_COMPAT_ENDIAN_H_
#define _RAVYNOS_COMPAT_ENDIAN_H_

#include <machine/endian.h>
#include <libkern/OSByteOrder.h>

#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN 1234
#endif
#ifndef __BIG_ENDIAN
#define __BIG_ENDIAN    4321
#endif
#ifndef __BYTE_ORDER
#define __BYTE_ORDER    __LITTLE_ENDIAN
#endif

#ifndef htobe16
#define htobe16(x) OSSwapHostToBigInt16(x)
#define htole16(x) OSSwapHostToLittleInt16(x)
#define be16toh(x) OSSwapBigToHostInt16(x)
#define le16toh(x) OSSwapLittleToHostInt16(x)

#define htobe32(x) OSSwapHostToBigInt32(x)
#define htole32(x) OSSwapHostToLittleInt32(x)
#define be32toh(x) OSSwapBigToHostInt32(x)
#define le32toh(x) OSSwapLittleToHostInt32(x)

#define htobe64(x) OSSwapHostToBigInt64(x)
#define htole64(x) OSSwapHostToLittleInt64(x)
#define be64toh(x) OSSwapBigToHostInt64(x)
#define le64toh(x) OSSwapLittleToHostInt64(x)
#endif

#endif /* _RAVYNOS_COMPAT_ENDIAN_H_ */
"""

    byteswap_h = """#ifndef _RAVYNOS_COMPAT_BYTESWAP_H_
#define _RAVYNOS_COMPAT_BYTESWAP_H_

#include <libkern/OSByteOrder.h>

#define bswap_16(x) OSSwapInt16(x)
#define bswap_32(x) OSSwapInt32(x)
#define bswap_64(x) OSSwapInt64(x)

#endif /* _RAVYNOS_COMPAT_BYTESWAP_H_ */
"""

    eventfd_h = """#ifndef _RAVYNOS_SYS_EVENTFD_H_
#define _RAVYNOS_SYS_EVENTFD_H_

#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t eventfd_t;

#define EFD_SEMAPHORE 0x00000001
#define EFD_CLOEXEC   0x00080000
#define EFD_NONBLOCK  0x00000800

static inline int eventfd(unsigned int initval, int flags) {
    int fds[2];
    if (pipe(fds) < 0)
        return -1;
    if (flags & EFD_CLOEXEC) {
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    }
    if (flags & EFD_NONBLOCK) {
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);
    }
    if (initval > 0) {
        uint64_t v = initval;
        (void)write(fds[1], &v, sizeof(v));
    }
    close(fds[1]);
    return fds[0];
}

static inline int eventfd_read(int fd, eventfd_t *value) {
    ssize_t n = read(fd, value, sizeof(*value));
    return (n == (ssize_t)sizeof(*value)) ? 0 : -1;
}

static inline int eventfd_write(int fd, eventfd_t value) {
    ssize_t n = write(fd, &value, sizeof(value));
    return (n == (ssize_t)sizeof(value)) ? 0 : -1;
}

#ifdef __cplusplus
}
#endif

#endif /* _RAVYNOS_SYS_EVENTFD_H_ */
"""

    epoll_h = """#ifndef _RAVYNOS_SYS_EPOLL_H_
#define _RAVYNOS_SYS_EPOLL_H_

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#ifdef __cplusplus
extern "C" {
#endif

#define EPOLL_CLOEXEC  0x00080000

#define EPOLLIN        0x001
#define EPOLLPRI       0x002
#define EPOLLOUT       0x004
#define EPOLLERR       0x008
#define EPOLLHUP       0x010
#define EPOLLRDHUP     0x2000
#define EPOLLET        (1U << 31)
#define EPOLLONESHOT   (1U << 30)

#define EPOLL_CTL_ADD  1
#define EPOLL_CTL_DEL  2
#define EPOLL_CTL_MOD  3

typedef union epoll_data {
    void    *ptr;
    int      fd;
    uint32_t u32;
    uint64_t u64;
} epoll_data_t;

struct epoll_event {
    uint32_t     events;
    epoll_data_t data;
};

static inline int epoll_create1(int flags) {
    int kq = kqueue();
    if (kq >= 0 && (flags & EPOLL_CLOEXEC)) {
        fcntl(kq, F_SETFD, FD_CLOEXEC);
    }
    return kq;
}

static inline int epoll_create(int size) {
    (void)size;
    return epoll_create1(0);
}

static inline int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event) {
    struct kevent kev[2];
    int n = 0;
    uint16_t kflags = 0;
    if (op == EPOLL_CTL_ADD || op == EPOLL_CTL_MOD) {
        if (!event) { errno = EINVAL; return -1; }
        kflags = EV_ADD | EV_ENABLE;
        if (event->events & EPOLLET) kflags |= EV_CLEAR;
        if (event->events & EPOLLONESHOT) kflags |= EV_ONESHOT;
        if (event->events & EPOLLIN) {
            EV_SET(&kev[n++], fd, EVFILT_READ, kflags, 0, 0, event->data.ptr);
        }
        if (event->events & EPOLLOUT) {
            EV_SET(&kev[n++], fd, EVFILT_WRITE, kflags, 0, 0, event->data.ptr);
        }
    } else if (op == EPOLL_CTL_DEL) {
        EV_SET(&kev[0], fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
        EV_SET(&kev[1], fd, EVFILT_WRITE, EV_DELETE, 0, 0, NULL);
        (void)kevent(epfd, &kev[0], 1, NULL, 0, NULL);
        (void)kevent(epfd, &kev[1], 1, NULL, 0, NULL);
        return 0;
    } else {
        errno = EINVAL;
        return -1;
    }
    return kevent(epfd, kev, n, NULL, 0, NULL);
}

static inline int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout) {
    if (maxevents <= 0 || maxevents > 64) maxevents = 64;
    struct kevent kev[64];
    struct timespec ts, *tsp = NULL;
    if (timeout >= 0) {
        ts.tv_sec = timeout / 1000;
        ts.tv_nsec = (timeout % 1000) * 1000000L;
        tsp = &ts;
    }
    int n = kevent(epfd, NULL, 0, kev, maxevents, tsp);
    for (int i = 0; i < n; i++) {
        uint32_t ev = 0;
        if (kev[i].filter == EVFILT_READ) ev |= EPOLLIN;
        if (kev[i].filter == EVFILT_WRITE) ev |= EPOLLOUT;
        if (kev[i].flags & EV_EOF) ev |= EPOLLHUP;
        if (kev[i].flags & EV_ERROR) ev |= EPOLLERR;
        events[i].events = ev;
        events[i].data.ptr = kev[i].udata;
    }
    return n;
}

#ifdef __cplusplus
}
#endif

#endif /* _RAVYNOS_SYS_EPOLL_H_ */
"""

    for target_sdk in (REPO_SDK, BUILD_SDK):
        if not os.path.isdir(target_sdk):
            continue
        inc = os.path.join(target_sdk, "usr", "include")
        write_text_if_changed(os.path.join(inc, "sys", "endian.h"), endian_h)
        write_text_if_changed(os.path.join(inc, "byteswap.h"), byteswap_h)
        write_text_if_changed(os.path.join(inc, "sys", "eventfd.h"), eventfd_h)
        write_text_if_changed(os.path.join(inc, "sys", "epoll.h"), epoll_h)


def build_libcxx_dylib() -> None:
    """Produce usr/lib/libc++.1.dylib next to the C++ archives.

    Imported macOS binaries link /usr/lib/libc++.1.dylib by name, and the
    in-tree C++ toolchain cannot link against libc++.a and libc++abi.a
    together (both define std::terminate).  The script is the only place that
    knows how the two archives are recombined; running it here means a synced
    SDK is always complete for C++.
    """
    script = os.path.join(HERE, "make_libcxx_dylib.py")
    if not os.path.exists(script):
        return
    result = subprocess.run(
        [sys.executable, script, "--sdk", REPO_SDK, "--also-build-sdk"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        # Loud, but not fatal for the rest of the sync: the SDK is still usable
        # for C, and a silent skip is how a broken C++ runtime ships.
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        print("[sync_sdk] WARNING: libc++.1.dylib could not be built")


def write_pkgconfig_files() -> None:
    pcs = {
        "zlib.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
sharedlibdir=${libdir}
includedir=${prefix}/include

Name: zlib
Description: zlib compression library
Version: 1.3.1
Requires:
Libs: -L${libdir} -lz
Cflags: -I${includedir}
""",
        "expat.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: expat
Version: 2.6.2
Description: expat XML parser
Libs: -L${libdir} -lexpat
Cflags: -I${includedir}
""",
        "sqlite3.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: SQLite
Description: SQL database engine
Version: 3.46.0
Libs: -L${libdir} -lsqlite3
Libs.private: -lpthread
Cflags: -I${includedir}
""",
        "fontconfig.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: Fontconfig
Description: Font configuration and customization library
Version: 2.15.0
Requires: freetype2 expat
Libs: -L${libdir} -lfontconfig
Cflags: -I${includedir}
""",
        "freetype2.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: FreeType 2
Description: A free, high-quality, and portable font engine.
Version: 26.1.20
Requires.private: zlib
Libs: -L${libdir} -lfreetype -lz
Cflags: -I${includedir}/freetype2
""",
        "libpng16.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/libpng16

Name: libpng
Description: Loads and saves PNG files
Version: 1.6.43
Requires.private: zlib
Libs: -L${libdir} -lpng16 -lz
Cflags: -I${includedir}
""",
        "libpng.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/libpng16

Name: libpng
Description: Loads and saves PNG files
Version: 1.6.43
Requires.private: zlib
Libs: -L${libdir} -lpng16 -lz
Cflags: -I${includedir}
""",
        "libjpeg.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libjpeg
Description: A SIMD-accelerated JPEG codec that provides the libjpeg API
Version: 3.0.3
Libs: -L${libdir} -ljpeg
Cflags: -I${includedir}
""",
        "libtiff-4.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libtiff
Description: Tag Image File Format (TIFF) library.
Version: 4.6.0
Libs: -L${libdir} -ltiff -ljpeg -lz
Cflags: -I${includedir}
""",
        "jansson.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: Jansson
Description: Library for encoding, decoding and manipulating JSON data
Version: 2.14
Libs: -L${libdir} -ljansson
Cflags: -I${includedir}
""",
        "icu-uc.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: icu-uc
Description: International Components for Unicode: Common and Data libraries
Version: 78.3
Libs: -L${libdir} -licucore
Cflags: -I${includedir}
""",
        "icu-i18n.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: icu-i18n
Description: International Components for Unicode: Internationalization library
Version: 78.3
Libs: -L${libdir} -licucore
Cflags: -I${includedir}
""",
        "sdl2.pc": """prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: sdl2
Description: Simple DirectMedia Layer is a cross-platform multimedia library designed to provide low level access to audio, keyboard, mouse, joystick, 3D hardware via OpenGL, and 2D video framebuffer.
Version: 2.32.10
Requires:
Conflicts:
Libs: -L${libdir} -lSDL2 -Wl,-framework,AppKit -Wl,-framework,Foundation -Wl,-framework,CoreGraphics -Wl,-framework,Onyx2D -Wl,-framework,CoreFoundation -lobjc -lpthread -lm
Cflags: -I${includedir}/SDL2 -I${includedir} -D_REENTRANT -D__RAVYNOS__=1
""",
    }
    for target_sdk in (REPO_SDK, BUILD_SDK):
        if not os.path.isdir(target_sdk):
            continue
        pc_dir = os.path.join(target_sdk, "usr", "lib", "pkgconfig")
        os.makedirs(pc_dir, exist_ok=True)
        for name, body in pcs.items():
            write_text_if_changed(os.path.join(pc_dir, name), body)


def main() -> int:
    sync_libraries()
    ensure_versioned_aliases()
    sync_missing_frameworks()
    sync_headers()
    install_linux_compat_headers()
    build_libcxx_dylib()
    write_pkgconfig_files()
    print(f"[sync_sdk] Synchronized SDK at {REPO_SDK}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
