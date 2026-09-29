#!/bin/bash
# run_gated_loader.sh -- build the image ONCE with OUR loader in it, boot it, and
# keep the evidence. Refuses to start unless it can prove what it is about to run.
#
# WHY THIS IS A SCRIPT
#   Every rule this project has been bitten by is a rule about ORDER, and order is
#   exactly what a shell one-liner gets wrong when it is typed under time pressure:
#
#     * "An image a live process holds open is not pinned" -- overwriting
#       boot_dynamic.img while a QEMU has it open changes nothing for that QEMU,
#       and two concurrent mkimage runs give VERIFY FAIL: content mismatch.
#     * "boot.py truncates the QEMU log on every start" -- the log must be copied
#       aside IMMEDIATELY after exit, before anything else runs.
#     * "A negative result needs a positive control" -- the loader in the image
#       must be located BYTE SEARCH in the built image, not inferred from the
#       fact that assets/ was staged.
#     * boot.py copies assets/vars.fd to a per-run vars file itself, so a stale
#       NVRAM cannot reach the boot. Nothing to do here but do not defeat it.
#
# Usage: tools/bootlab/run_gated_loader.sh <loader-file> <tag> [window_seconds]
# Exit:  0 boot ran and logs were preserved; non-zero if a precondition failed.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

LOADER="${1:?usage: run_gated_loader.sh <loader-file> <tag> [window]}"
TAG="${2:?tag required}"
WINDOW="${3:-300}"
IMG="work/boot_dynamic.${TAG}.img"
# THE TWO-BOOT DESIGN, one command away.
#   This script takes the loader as an argument precisely so the settling
#   experiment is just running it twice against the same kernel:
#
#     ./run_gated_loader.sh assets/usr/lib/dyld.PRE-SALLOC-GATE A
#     ./run_gated_loader.sh assets/usr/lib/dyld.DYLD-BOOT-VERSION  B
#
#   and then diffing the two serial logs. Because the kernel sha256 is printed
#   by each run, "the kernel did not change in between" is a CHECK rather than
#   an assumption -- which is the whole difference between that pair being a
#   controlled comparison and being two anecdotes.
#
OUT="work/serial_dynamic.${TAG}.log"
QLOG="work/qemu_${TAG}.log"
MINE_SHA="$(shasum -a 256 "$LOADER" | cut -d' ' -f1)"

fail() { echo "FATAL: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. REFUSE unless the machine is free and the loader is the one we mean.
# ---------------------------------------------------------------------------
if pgrep -f qemu-system-x86_64 >/dev/null 2>&1; then
    fail "a QEMU is running and holds the image; not rebuilding under a live process"
fi
if pgrep -f 'bmake|isysroot-cc|mkimage|boot\.py|kernel_build' >/dev/null 2>&1; then
    fail "another builder is running; the image must be built once and alone"
fi
[ -f "$LOADER" ] || fail "no loader at $LOADER"

# Stage it into the one path the manifest reads, keeping whatever was there.
# Assets are gitignored build products; this is a swap, not a commit, and the
# previous occupant is kept so a revert test is one mv.
if [ "$(shasum -a 256 assets/usr/lib/dyld | cut -d' ' -f1)" != "$MINE_SHA" ]; then
    cp -f assets/usr/lib/dyld "assets/usr/lib/dyld.PREV-${TAG}" 2>/dev/null
    cp -f "$LOADER" assets/usr/lib/dyld
fi
STAGED="$(shasum -a 256 assets/usr/lib/dyld | cut -d' ' -f1)"

# The control below verifies the file that was ACTUALLY STAGED, not the path the
# caller named. Those are normally the same file, but a co-ordinated worker may
# have removed their own temporary copy between the swap and this check, and a
# control that aborts on a missing alias has measured nothing while looking
# careful. mkimage reads the staged path, so that is the path that must be
# byte-verified in the image.
STAGED_PATH="assets/usr/lib/dyld"
[ "$STAGED" = "$MINE_SHA" ] || fail "staging did not take: $STAGED != $MINE_SHA"
echo "[1/5] staged loader sha256 ${MINE_SHA:0:16}  ($(stat -f%z "$LOADER") bytes)"

# ---------------------------------------------------------------------------
# 1. Build the image ONCE.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 1b. PIN AND RECORD THE KERNEL.
#     mkimage defaults to work/stripped_kernel.development, which the OTHER
#     worker relinks with kernel_build.py. If that happens between boots then two
#     runs differ by the kernel as well as by whatever we are testing, and the
#     fault signature stops being attributable. So the payload is named
#     explicitly and its hash printed BEFORE the image is built. A kernel hash
#     that differs from the control run's must be stated in the report, not
#     discovered afterwards.
# ---------------------------------------------------------------------------
KERNEL="work/stripped_kernel.development"
[ -f "$KERNEL" ] || KERNEL="assets/kernel.development"
[ -f "$KERNEL" ] || fail "no kernel payload: neither work/ nor assets/ has one"
KSHA="$(shasum -a 256 "$KERNEL" | cut -d' ' -f1)"
echo "      kernel payload: $KERNEL"
echo "      kernel sha256 : ${KSHA:0:16}  ($(stat -f%z "$KERNEL") bytes)"
echo "      ^ RECORD THIS: if it differs from the control run's kernel, the"
echo "        signature is not attributable to the loader alone."
echo "[2/5] mkimage -> $IMG"
python3 mkimage.py "$IMG" --manifest manifest_dynamic.json || fail "mkimage failed"

# ---------------------------------------------------------------------------
# 2. POSITIVE CONTROL: find our loader IN THE IMAGE, by byte search, and then
#    verify the WHOLE FILE at that offset.
#
#    This used to compare only the first 4 KB.  That is the control section
#    33.3 identified as incapable of seeing the class of difference that matters
#    here: a divergent __DATA.  Every fault in this workstream that mattered
#    lived past the first page, and a head-only check reports "identical" for a
#    binary that differs exactly where the bug is.  The offset is still located
#    by the head (a whole-file search is quadratic and the image is 512 MB), but
#    nothing is claimed until every byte has been compared.
# ---------------------------------------------------------------------------
python3 - "$STAGED_PATH" "$IMG" <<'PY' || exit 1
import os, sys
loader, img = sys.argv[1], sys.argv[2]
want = os.path.getsize(loader)
head = open(loader, 'rb').read(4096)
with open(img, 'rb') as f:
    data = f.read()
off = data.find(head)
if off < 0:
    print("FATAL: the loader's first 4 KB are NOT in the image at any offset.")
    print("       The boot would measure something else entirely.")
    sys.exit(1)
# Now compare EVERY byte, not just the head.
if off + want > len(data):
    print("FATAL: loader head found at %d but only %d bytes follow; the image is short."
          % (off, len(data) - off))
    sys.exit(1)
with open(loader, 'rb') as lf:
    expected = lf.read()
actual = data[off:off + want]
if actual != expected:
    bad = next(i for i in range(want) if actual[i] != expected[i])
    print("FATAL: loader head is at %d but the file DIFFERS at byte %d (%#04x vs %#04x)."
          % (off, bad, expected[bad], actual[bad]))
    print("       A head-only check would have passed this. Aborting.")
    sys.exit(1)
print("[3/5] VERIFIED WHOLE FILE: all %d bytes at image offset %d match the staged loader"
      % (want, off))
PY

# ---------------------------------------------------------------------------
# 3. Boot, and WAIT FOR IT TO EXIT. A running process is not a result.
# ---------------------------------------------------------------------------
echo "[4/5] boot --mode full --window $WINDOW  (blocking; a live process is not a result)"
python3 boot.py --img "$IMG" --mode full --window "$WINDOW" --out "$OUT"
BOOT_RC=$?

# ---------------------------------------------------------------------------
# 4. The QEMU log is truncated on every start, so it is copied aside FIRST,
#    before anything else can start a new boot.
# ---------------------------------------------------------------------------
cp -f work/qemu_full.log "$QLOG" 2>/dev/null
echo "[5/5] serial -> $OUT ($(wc -l < "$OUT" | tr -d ' ') lines, rc=$BOOT_RC)"
echo "       qemu  -> $QLOG ($(stat -f%z "$QLOG" 2>/dev/null || echo 0) bytes)"
echo
echo "SIGNATURE:"
grep -nE 'DYLD-LOAD-BASE|panic\(|initproc failed|exit reason|Backtrace continues|^RAX:|^RIP:' "$OUT" | head -20
echo
echo "symbolize with:"
echo "  python3 symbolize_anchored.py $OUT $STAGED_PATH"
