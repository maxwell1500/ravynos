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
# Every step is idempotent. work/ is scratch; assets/ (config only) plus the
# manifests are the source of truth for the disk tree.
#
# THE DEFAULT MANIFEST IS manifest_cpmv.json, changed 2026-10-02.  It was
# manifest.json.  Two independent reasons, and both are now closed:
#
#   (a) manifest.json used to carry a `glob` over assets/usr/lib/system/,
#       which staged 31 host-extracted Apple dylibs.  closure_gate.py refused
#       it, so `./run.sh mkimage` and `./run.sh full` STOPPED rather than
#       building.  P1 has since quarantined those binaries out of assets/ (see
#       assets-quarantine/QUARANTINE_INVENTORY.txt) and manifest.json no
#       longer globs -- all three manifests now pass the gate with
#       HOST-EXTRACTED 0.  manifest_cpmv.json is nevertheless the default
#       because it is the closure with a proven boot history behind it.
#   (b) Reproducibility.  manifest_cpmv.json's 12 work/ entries all have a
#       producer; the recipe is at the bottom of this file.  A manifest whose
#       sources cannot be rebuilt from a clean checkout is not a default.
#
# Override either way: `--manifest M` for mkimage, RAVYN_MANIFEST=M for full.
#
# THE BUILD GATE.  Every subcommand that constructs a disk first runs
# closure_gate.py on the manifest it is about to build (PROVENANCE-PLAN P2)
# and refuses to continue on a nonzero verdict.  It gates the SOURCES, before
# any image exists; run_dynamic_gate.sh --no-build is the one mode that gates
# a finished image.  See README.md "The build gate".
#
# WHY manifest_cpmv.json AND NOT manifest_dynamic.json FOR `full`, measured
# 2026-10-02.  manifest_cpmv.json is clean and is NOT refused -- it passes the
# gate with 0 host-extracted binaries and its image boots.  It still cannot
# be the default for `full`, for one reason that is a property of the harness
# rather than of the manifest, so the choice below is a decision about that one
# thing and not a one-line edit:
#
#   1. boot.py -- PROTECTED -- judges a boot by counting "alive tick" lines and
#      returns nonzero when there are none.  init/init_shell.c prints that
#      string ONLY in its failure branch ("SHELL FAILED TO START"), so the
#      better the dynamic boot is, the more certainly the verdict is FAIL.
#      Measured on a manifest_cpmv.json image: kernel up, PID 1 execve'd
#      /bin/sh, dyld loaded the shell, interactive "# " prompt reached at
#      serial line 824, 0 strict panics -- and boot.py still exited 1.
#      `full` is an exit test, so defaulting it to cpmv would report every
#      healthy dynamic boot as a failure.  run.sh dynamic is the exit test
#      whose criterion matches its PID 1.
#
#   2. (RESOLVED 2026-10-02) manifest_cpmv.json was not reproducible from a
#      clean checkout: 12 of its entries resolve into gitignored work/, and 10
#      of those had no producer.  All ten now have one --
#      work/efi/BOOTX64.EFI <- build_applefree.sh, work/init_shell <-
#      build_init_shell.sh (BOTH existed all along; not having checked them
#      first was the error), and the nine dynamic utilities <- the new
#      build_dynutils.sh.
#
# The exact commands, unchanged by this switch:
#   ./run.sh mkimage work/boot.img                       # now the default
#   ./run.sh mkimage work/boot.img --manifest manifest_dynamic.json
#   RAVYN_MANIFEST=manifest_dynamic.json ./run.sh full
#   python3 boot.py --img work/boot.img --mode full      # exit 1 on a cpmv image: see 1
# For an exit test that actually judges the dynamic userland, use
# ./run.sh dynamic (manifest_dynamic.json, init_exec PID 1), or drive the
# serial-input harness over a cpmv image -- see README.md "The build gate".
#
# BUILDING THE cpmv TREE FROM SCRATCH (all 12 work/ products, in order):
#   tools/bootlab/build_all_libsystem.sh   # Libsystem + SDK (prerequisite)
#   BSD/lib/libedit                          # libedit.dylib, for sh
#   tools/bootlab/build_init_shell.sh        # work/init_shell  (PID 1)
#   tools/bootlab/build_applefree.sh         # work/efi/BOOTX64.EFI
#   tools/bootlab/build_dynutils.sh          # the nine work/*_dyn utilities
#   ./run.sh mkimage work/boot.img --manifest manifest_cpmv.json
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# THE BUILD GATE (PROVENANCE-PLAN P2).  Every path below that constructs a
# disk first runs closure_gate.py on the SAME manifest it hands to mkimage.py.
# It fails closed: a host cache that cannot be read is a FAIL, not a pass.
#
# P1 is EXECUTED, so this gate is no longer the only defence against host
# binaries -- there are none left under assets/ to defend against.  It stays
# because it is the thing that makes that true on every future run, including
# the next `git clone`, and because a manifest can still name a path outside
# the repository, which the relocatability preflight refuses by name.
#
# The manifest is taken from the caller's own arguments rather than hardcoded,
# so gating a tree can never diverge from building it.  DEFAULT_MANIFEST is
# the default for both mkimage and full; mkimage.py's own default is still
# manifest.json, which is why this is overridden explicitly rather than relied
# upon, and why `full` must pass --manifest too.
DEFAULT_MANIFEST="manifest_cpmv.json"
manifest_from_args() {
  local m="$DEFAULT_MANIFEST" prev=""
  for a in "$@"; do
    if [ "$prev" = "--manifest" ]; then m="$a"; prev=""; continue; fi
    case "$a" in
      --manifest)   prev="--manifest" ;;
      --manifest=*) m="${a#--manifest=}" ;;
    esac
  done
  printf '%s\n' "$m"
}

cmd="${1:-full}"; shift || true
case "$cmd" in
  build)   python3 kernel_build.py ;;
  init)    ./build_init.sh ;;
  mkimage)
    # mkimage.py is PROTECTED and its own --manifest default is manifest.json.
    # Passing the caller's args through unchanged would therefore let the gate
    # judge manifest_cpmv.json while mkimage built manifest.json -- the exact
    # divergence this file exists to prevent.  So when the caller names no
    # manifest, the default is injected explicitly.
    MAN="$(manifest_from_args "$@")"
    if [ "$MAN" = "$DEFAULT_MANIFEST" ] && ! printf '%s\n' "$@" \
         | grep -q -- '--manifest'; then
      set -- "$@" --manifest "$DEFAULT_MANIFEST"
    fi
    python3 closure_gate.py "$MAN"
    python3 mkimage.py "$@"
    ;;
  boot)    python3 boot.py --img "${BOOT_IMG:-work/boot.img}" --mode "${1:-full}" ;;
  dynamic) exec ./run_dynamic_gate.sh "$@" ;;
  full)
    python3 kernel_build.py
    ./build_init.sh
    MAN="${RAVYN_MANIFEST:-$DEFAULT_MANIFEST}"
    # `full` takes no mkimage arguments -- boot.py below boots work/boot.img,
    # so letting the caller redirect the image would boot a stale one -- so
    # the manifest comes from the environment instead.  The gate and mkimage
    # are handed the SAME value, so gating a tree can never diverge from
    # building it.
    python3 closure_gate.py "$MAN"
    python3 mkimage.py --manifest "$MAN"
    exec python3 boot.py --img work/boot.img --mode full --window 210
    ;;
  *) echo "usage: run.sh {build|init|mkimage [img]|boot [mode]|full|dynamic}" >&2; exit 2 ;;
esac
