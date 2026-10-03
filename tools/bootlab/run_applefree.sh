#!/bin/bash
# Boot the disk image built from manifest_applefree.json -- i.e. an image whose
# EFI application at System/Library/CoreServices/BOOT.EFI is the loader built
# from tools/efiloader/, not Apple's boot.efi.
#
#   ./run_applefree.sh <trampoline|full> [window_seconds]
#
# It reuses tools/bootlab/boot.py unmodified: boot.py types
# fs0:\System\Library\CoreServices\boot.efi at the UEFI shell, and the
# apple-free manifest deliberately keeps that file name, so the same harness
# runs whichever loader is staged.  assets/ is never written.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

TAG="${1:?usage: run_applefree.sh <trampoline|full> [window]}"
WINDOW="${2:-240}"
VARIANT="BOOTX64.EFI"
[ "$TAG" = "trampoline" ] && VARIANT="BOOTX64.TRAMPOLINE.EFI"
[ -f "work/efi/$VARIANT" ] || { echo "FATAL: work/efi/$VARIANT not built" >&2; exit 1; }

if pgrep -f qemu-system-x86_64 >/dev/null 2>&1; then
    echo "FATAL: a QEMU is already running" >&2; exit 1
fi

# Stage the selected variant under the name the manifest reads.
cp -f "work/efi/$VARIANT" work/efi/BOOTX64.EFI
LSHA="$(shasum -a 256 work/efi/BOOTX64.EFI | cut -d' ' -f1)"

# Pin the kernel so a rebuild by another worker cannot silently change what
# this run is a test OF.
KERNEL="${RAVYN_KERNEL:-assets/kernel.development}"
[ -f "$KERNEL" ] || KERNEL="work/stripped_kernel.development"
KSHA="$(shasum -a 256 "$KERNEL" | cut -d' ' -f1)"

IMG="work/applefree.${TAG}.img"
OUT="work/serial_applefree.${TAG}.log"
QLOG="work/qemu_applefree.${TAG}.log"

echo "[1/4] loader  : work/efi/BOOTX64.EFI (from $VARIANT)"
echo "      sha256  : $LSHA"
echo "[2/4] kernel  : $KERNEL"
echo "      sha256  : $KSHA"

# The pin above is deliberate, but its failure mode is silent and expensive:
# edit a .c file, rebuild, run, and boot the OLD asset instead.  Three
# separate kernel fixes in this repo were "tested" that way before this check
# existed.  If the committed asset is older than a local build, say so loudly.
if [ -z "${RAVYN_KERNEL:-}" ] && [ -f work/stripped_kernel.development ] \
   && [ work/stripped_kernel.development -nt assets/kernel.development ]; then
    echo "WARNING: assets/kernel.development is OLDER than work/stripped_kernel.development" >&2
    echo "WARNING: this run boots the OLD asset, not the kernel you built." >&2
    echo "WARNING: re-run with RAVYN_KERNEL=work/stripped_kernel.development" >&2
fi
echo "[3/4] mkimage -> $IMG"
# THE BUILD GATE (PROVENANCE-PLAN P2), on the manifest mkimage.py is about to
# be given.  This script's whole subject is "the bytes in this image are the
# bytes I just built"; letting an unvetted closure into that image would
# falsify its premise.  Fails closed.
python3 closure_gate.py manifest_applefree.json || exit 1
python3 mkimage.py "$IMG" --manifest manifest_applefree.json --kernel "$KERNEL" || exit 1

# A harness that reports a stale fact is the same shape as a gate that cannot
# fail: it looks like evidence and is not.  I once booted an image built from a
# loader two revisions old, because I read a .digests sidecar left over from a
# previous run instead of the one just written.  The fault PC did not match the
# disassembly I had just produced, which is how it was caught -- far too late.
# Assert it here instead, and refuse to boot on a mismatch.
STAGED="$(grep -i 'CoreServices/BOOT.EFI' "$IMG.digests" | awk '{print $1}')"
# Confirm against the image bytes themselves: a sidecar can be stale, the
# image cannot.  Whichever is wrong, refuse to boot.
ACTUAL="$(python3 - "$IMG" "work/efi/$VARIANT" <<'PY2'
import hashlib, sys
img = open(sys.argv[1], 'rb').read(4 * 1024 * 1024)
ld  = open(sys.argv[2], 'rb').read()
i = img.find(ld)
print(hashlib.sha256(img[i:i + len(ld)]).hexdigest() if i >= 0 else "absent")
PY2
)"
if [ "$ACTUAL" != "$LSHA" ]; then
    echo "FATAL: the image really contains $ACTUAL but we built $LSHA" >&2
    exit 1
fi
if [ "$STAGED" != "$LSHA" ]; then
    echo "FATAL: image carries $STAGED but the freshly built loader is $LSHA" >&2
    echo "       refusing to boot: a stale image is not a result." >&2
    exit 1
fi
echo "      staged : $STAGED (matches the build) "

# Positive control: our loader must be findable IN THE IMAGE by byte search.
python3 - work/efi/BOOTX64.EFI "$IMG" <<'PY' || exit 1
import sys
loader = open(sys.argv[1], 'rb').read()
img = open(sys.argv[2], 'rb').read()
i = img.find(loader)
if i < 0:
    sys.exit("VERIFY FAIL: loader bytes not found in image")
print("      control : loader found in image at offset %d (%d bytes, whole file)"
      % (i, len(loader)))
PY

# A stale NVRAM produces a UEFI #UD at handoff that looks like a loader bug.
# boot.py copies assets/vars.fd itself; do it here too so the file on disk is
# provably pristine before the run.
cp -f assets/vars.fd work/vars_applefree.fd

echo "[4/4] boot --mode full --window $WINDOW (blocking)"
python3 boot.py --img "$IMG" --mode full --window "$WINDOW" --out "$OUT"
RC=$?
cp -f work/qemu_full.log "$QLOG" 2>/dev/null
cp -f work/vars_applefree.fd "work/vars_applefree.${TAG}.used.fd" 2>/dev/null

echo
echo "serial -> $OUT  ($(wc -l < "$OUT" | tr -d ' ') lines, rc=$RC)"
echo "qemu   -> $QLOG ($(stat -f%z "$QLOG" 2>/dev/null || echo 0) bytes)"
echo
echo "SIGNATURE:"
grep -nE 'RL:|EAXX=|EARLY:|vstart|MARK:|panic|alive tick|RAX:|RIP:' "$OUT" | head -40
exit $RC
