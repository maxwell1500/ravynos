#!/bin/bash
# Build version-matched placeholder dylibs for libraries that the staged
# Darwin 24 world references only via LC_LOAD_(UPWARD_|WEAK_)DYLIB with
# zero imported symbols (verified with dyld_info -imports). dyld only needs
# a mach-o whose LC_ID_DYLIB install-name/version matches the client's
# LC_LOAD_DYLIB expectation; no code is ever called through these.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
stub_c="$(mktemp /tmp/ravyn_stubXXXX.c)"
printf 'int __ravyn_placeholder(void) { return 0; }\nvoid _objc_atfork_prepare(void) {}\nvoid _objc_atfork_parent(void) {}\nvoid _objc_atfork_child(void) {}\n' > "$stub_c"

mk() { # out install_name current [extra_srcs...]
  mkdir -p "$(dirname "$here/assets/$1")"
  xcrun clang -arch x86_64 -mmacos-version-min=11.0 -dynamiclib \
      -Wl,-fixup_chains \
      -Wl,-compatibility_version,1.0.0 -Wl,-current_version,"$3" \
      -O1 -o "$here/assets/$1" "$stub_c" ${4:+"${@:4}"}
  echo "stub: assets/$1 ($(stat -f%z "$here/assets/$1") bytes) id=$2"
}

mk usr/lib/libobjc.A.dylib /usr/lib/libobjc.A.dylib 228.0.0 "$here/objc_stubs.c"
mk System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation \
   /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation 5026.6.7
rm -f "$stub_c"
