#!/bin/bash
# ravynOS bootlab one-stop driver.
#
#   run.sh build                 recompile boot-critical objects + relink kernel
#                                -> work/new_kernel.development,
#                                   work/stripped_kernel.development
#   run.sh init                  build static PID1 -> work/init
#   run.sh mkimage [out.img]     build FAT32 disk -> default work/boot.img
#   run.sh boot [mode]           QEMU boot (split|full|fallback, default full)
#   run.sh full                  build + init + mkimage + boot full  (exit test)
#   run.sh dynamic              dynamic-USERLAND GATE (exit test): stages a
#                                static exec-runner as PID 1 that execve()s the
#                                dylib-linked /bin/echo, so dyld, the
#                                libSystem closure and a dylib main() are
#                                actually exercised. `full` cannot reach that
#                                path -- its PID 1 execs nothing.
#
# Every step is idempotent. work/ is scratch; assets/ + manifest.json are
# the committed source of truth for the disk tree.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

cmd="${1:-full}"; shift || true
case "$cmd" in
  build)   python3 kernel_build.py ;;
  init)    ./build_init.sh ;;
  mkimage) python3 mkimage.py "$@" ;;
  boot)    python3 boot.py --img "${BOOT_IMG:-work/boot.img}" --mode "${1:-full}" ;;
  dynamic) exec ./run_dynamic_gate.sh "$@" ;;
  full)
    python3 kernel_build.py
    ./build_init.sh
    python3 mkimage.py
    exec python3 boot.py --img work/boot.img --mode full --window 210
    ;;
  *) echo "usage: run.sh {build|init|mkimage [img]|boot [mode]|full|dynamic}" >&2; exit 2 ;;
esac
