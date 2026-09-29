#!/bin/bash
# Build the ravynOS EFI loader(s) from tools/efiloader/src/loader.c.
#
#   ./build_applefree.sh            -> work/efi/BOOTX64.EFI          (full loader)
#   ./build_applefree.sh trampoline -> work/efi/BOOTX64.TRAMPOLINE.EFI (gate)
#
# Two commands, no EDK2 and no PE linker (see tools/efiloader/pack.py).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EFIDIR="$HERE/../efiloader"
OUT="$HERE/work/efi"
CLANG="${CLANG:-/Library/Developer/CommandLineTools/usr/bin/clang}"
MODE="${1:-full}"
EXTRA=""
OUTNAME="BOOTX64.EFI"
if [ "$MODE" = "trampoline" ]; then
    EXTRA="-DRAVYN_TRAMPOLINE_TEST"
    OUTNAME="BOOTX64.TRAMPOLINE.EFI"
fi

mkdir -p "$OUT"
OBJ="$OUT/loader${MODE:+.$(echo "$MODE" | tr a-z A-Z)}.obj"

rm -f "$OBJ" "$OUT/$OUTNAME"
set -x
"$CLANG" -target x86_64-unknown-windows \
    -ffreestanding -fno-stack-protector -mno-red-zone -mcmodel=medium \
    -fno-builtin -Os -g0 -Wall $EXTRA \
    -c "$EFIDIR/src/loader.c" -o "$OBJ"
python3 "$EFIDIR/pack.py" "$OBJ" "$OUT/$OUTNAME" efi_main
set +x

echo "built $OUT/$OUTNAME  sha256 $(shasum -a 256 "$OUT/$OUTNAME" | cut -d' ' -f1)"
echo "         $(stat -f%z "$OUT/$OUTNAME") bytes"

# A GATE THAT CANNOT FAIL IS WORSE THAN NO GATE: it manufactures false confidence.
# The phase-1 trampoline build and the full build MUST differ, and the only way to
# know they differ is to compare them.  (They were byte-identical once, because the
# -DRAVYN_TRAMPOLINE_TEST branch had no effect on codegen.)
# Rebuild the other variant too, so the comparison below is always
# fresh-vs-fresh.  A stale artifact must never be able to satisfy it.
OTHER="BOOTX64.EFI"; OMODE="full"
[ "$MODE" = "full" ] && { OTHER="BOOTX64.TRAMPOLINE.EFI"; OMODE="trampoline"; }
OEXTRA=""; [ "$OMODE" = "trampoline" ] && OEXTRA="-DRAVYN_TRAMPOLINE_TEST"
OOBJ="$OUT/loader.$OMODE.obj"
rm -f "$OOBJ" "$OUT/$OTHER"
"$CLANG" -target x86_64-unknown-windows \
    -ffreestanding -fno-stack-protector -mno-red-zone -mcmodel=medium \
    -fno-builtin -Os -g0 -Wall $OEXTRA \
    -c "$EFIDIR/src/loader.c" -o "$OOBJ"
python3 "$EFIDIR/pack.py" "$OOBJ" "$OUT/$OTHER" efi_main

if [ -f "$OUT/BOOTX64.EFI" ] && [ -f "$OUT/BOOTX64.TRAMPOLINE.EFI" ]; then
    A=$(shasum -a 256 "$OUT/BOOTX64.EFI" | cut -d' ' -f1)
    B=$(shasum -a 256 "$OUT/BOOTX64.TRAMPOLINE.EFI" | cut -d' ' -f1)
    echo "         full        sha256 $A"
    echo "         trampoline  sha256 $B"
    if [ "$A" = "$B" ]; then
        echo "FATAL: the trampoline and full builds are byte-identical." >&2
        echo "       The phase-1 gate cannot fail, so it cannot report either." >&2
        echo "       -DRAVYN_TRAMPOLINE_TEST is not reaching codegen." >&2
        exit 1
    fi
    echo "         gate check: builds differ (good)"
fi
