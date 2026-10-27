#!/bin/sh
# Builds cxxprobe against the ravynOS SDK's C++ dylib.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
OUT="${1:-$REPO/tools/bootlab/work/cxxprobe}"
mkdir -p "$OUT"
"$REPO/tools/sdk/bin/ravynos-c++" -O2 -pthread "$HERE/main.cpp" -o "$OUT/cxxprobe"
echo "built $OUT/cxxprobe"
