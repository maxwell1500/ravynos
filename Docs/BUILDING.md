# Building ravynOS From Source

This guide is for the current Darwin-based ravynOS. A new CMake-based build system is being created for portability and maintainability. Structurally, the build starts by creating a toolchain for the host OS and then using it to build the OS for the same CPU architecture.

The host toolchain (Default.xctoolchain) includes clang, LLVM, Apple cctools, xcbuild, and other utilities needed to build the OS. Building LLVM initially takes a __long__ time, so be patient. It lives in `<build_dir>/Developer/Toolchains/Default.xctoolchain` once built.

After the toolchain is available, critical system libraries and headers will be built into the ravynOS.sdk - an equivalent of MacOSX.sdk for ravynOS native targets. The new SDK is then used to progressively build the rest of the system.

Building it this way takes longer, but there are advantages. It helps make the entire build portable and it guarantees build consistency, which helps reduce those nasty "well it works for me" problems. Once it has built fully, subsequent incremental builds are faster.

## What you need:
* A host machine with:
  * clang 16.x+
  * cmake 3.15+ and ninja
  * GNU make (gmake)
  * BSD make (bmake)
  * Python 3
  * OpenSSL
  * libpng (for xcbuild), libxml2, zlib (libz)
* A lot of patience

__NOTE:__ ravynOS currently only builds on macOS! We're working hard to fix this.

__On macOS:__
* Have a recent Xcode installed
* Run: `cmake -S /path/to/ravynos -B /path/to/build -GNinja`
* Run: `cmake --build /path/to/build`

