#!/bin/bash
# Build and boot tools/efiloader/src/minxfer.c -- the minimal long->32-bit
# transfer reproducer -- and report whether M32 appeared in the serial log.
#
#   ./run_minxfer.sh [window_seconds]
#
# Does NOT touch boot.py, mkimage.py, manifest.json or assets/.  Reuses boot.py
# unmodified: boot.py types fs0:\System\Library\CoreServices\boot.efi, and
# manifest_minxfer.json stages MINXFER.EFI at exactly that path.
#
# Positive signals, in order of strength:
#   M32      -- the 32-bit routine ran and wrote '*' to 0x3f8.  This is the
#               only signal that means the mode switch LANDED.
#   'RETURNED' -- control came back to the 64-bit half, i.e. the far return
#               did NOT switch CS.  A distinct, also-useful outcome.
#   neither   -- the far return faulted (previous behaviour: #GP).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
WINDOW="${1:-240}"
EFIDIR="$HERE/../efiloader"
CLANG="${CLANG:-/Library/Developer/CommandLineTools/usr/bin/clang}"

# Another worker uses QEMU intermittently.  Defer rather than preempt.
if pgrep -fl qemu-system >/dev/null 2>&1; then
    echo "DEFER: another QEMU is running:" >&2
    pgrep -fl qemu-system >&2
    exit 75
fi

mkdir -p work/efi work
OBJ=work/efi/minxfer.obj
EFI=work/efi/MINXFER.EFI

# Rebuild unconditionally.  A cached object would silently test an old bug.
rm -f "$OBJ" "$EFI"
echo "[1/5] compile minxfer.c"
"$CLANG" -target x86_64-unknown-windows \
    -ffreestanding -fno-stack-protector -mno-red-zone -mcmodel=medium \
    -fno-builtin -Os -g0 -Wall \
    -c "$EFIDIR/src/minxfer.c" -o "$OBJ" || exit 1

echo "[2/5] pack"
python3 "$EFIDIR/pack.py" "$OBJ" "$EFI" efi_main || exit 1

# Assert the transfer instruction really is in the artifact we are about to
# boot: one standalone CB, and no 66 CB (the ruled-out prefixed form).
python3 - "$EFI" <<'PY' || exit 1
import sys
d = open(sys.argv[1], 'rb').read()
cb = d.count(b'\xcb')
pref = d.count(b'\x66\xcb')
print("      transfer bytes: cb=%d  66cb=%d  lgdtq=%d" %
      (cb, pref, d.count(b'\x0f\x01\x13')))
if cb != 1:
    print("FATAL: expected exactly one standalone RETF (CB), found %d" % cb)
    sys.exit(1)
if pref:
    print("FATAL: prefixed 66 CB present; that form was already ruled out")
    sys.exit(1)
PY
ESHA=$(shasum -a 256 "$EFI" | cut -d' ' -f1)
echo "      sha256 $ESHA"

KERNEL="${RAVYN_KERNEL:-assets/kernel.development}"
[ -f "$KERNEL" ] || KERNEL="work/stripped_kernel.development"
IMG=work/minxfer.img
echo "[3/5] mkimage -> $IMG"
python3 mkimage.py "$IMG" --manifest manifest_minxfer.json --kernel "$KERNEL" || exit 1

# Positive control: the loader must be findable IN THE IMAGE by byte search.
# A sidecar can be stale; the image bytes cannot.
ACTUAL=$(python3 - "$IMG" "$EFI" <<'PY'
import hashlib, sys
img = open(sys.argv[1], 'rb').read()
efi = open(sys.argv[2], 'rb').read()
i = img.find(efi)
print("MISSING" if i < 0 else hashlib.sha256(efi).hexdigest())
PY
)
if [ "$ACTUAL" != "$ESHA" ]; then
    echo "FATAL: staged image bytes do not match the build ($ACTUAL vs $ESHA)" >&2
    exit 1
fi
echo "      staged in image, hash verified"

# A stale NVRAM produces a UEFI #UD at handoff that mimics a loader bug.
cp -f assets/vars.fd work/vars_minxfer.fd

OUT=work/serial_MINXFER.log
QLOG=work/qemu_MINXFER.log
echo "[4/5] boot --mode full --window $WINDOW (blocking)"
python3 boot.py --img "$IMG" --mode full --window "$WINDOW" --out "$OUT"
RC=$?
cp -f work/qemu_full.log "$QLOG" 2>/dev/null

echo
echo "[5/5] result"
echo "serial -> $OUT"
echo "qemu   -> $QLOG"
echo
grep -nE 'MINXFER|RETURNED' "$OUT" || echo "(no MINXFER lines)"
echo "--- '*' marker count: $(grep -c '\*' "$OUT") ---"
echo
# The 32-bit routine emits '*' then '+' to port 0x3f8.  There is no literal
# "M32" string in the output -- grepping for one reports a false negative.
if grep -q '\*' "$OUT"; then
    echo "VERDICT: MODE SWITCH LANDED ('*' from the 32-bit routine is present)"
elif grep -q 'RETURNED' "$OUT"; then
    echo "VERDICT: far return did NOT switch CS (control returned to 64-bit)"
else
    echo "VERDICT: far return faulted before reaching the 32-bit routine"
fi
exit $RC
