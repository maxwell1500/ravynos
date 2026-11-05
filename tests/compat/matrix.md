# Compatibility matrix

Status is evidence, not intent.  `PASS` means the boot gate in
`tools/bootlab/verify_compat.py` ran on that platform and every fixture
reported `rc=0`; `—` means untested and must not be read as supported.

| Platform | Boot/desktop | Fixtures | Firefox ESR | Notes |
|---|---|---|---|---|
| QEMU x86_64 (HVF, 8 vCPU) | PASS | PASS (16) | PROGRESS | CGL/NSOpenGL implemented; window composites; SW-WR active; see `firefox-blockers.md` |
| Penryn 2008 (MacBook5,1 / MacBookPro5,x) | — | — | — | no hardware run yet |
| Nehalem 2009 (MacBookPro6,x) | — | — | — | no hardware run yet |
| Sandy Bridge 2011 (MacBookPro8,x) | — | — | — | no hardware run yet |
| Ivy Bridge 2012 (MacBookPro9,x) | — | — | — | no hardware run yet |
| Haswell 2013 (MacBookPro11,x) | — | — | — | no hardware run yet |
| Broadwell 2015 (MacBookPro12,1) | — | — | — | no hardware run yet |
| Skylake 2016 (MacBookPro13,x) | — | — | — | no hardware run yet |
| Kaby Lake 2017 (MacBookPro14,x) | — | — | — | no hardware run yet |

## Gate definitions

- **Boot/desktop** — `RAVYNOS_DESKTOP_READY`, zero `CORPSE`, Filer present,
  every prelinked kext started.
- **Fixtures** — `posix`, `malloczone`, `autorelease`, `backup`, `passwd`,
  `accounts`, `cocoa`, `launch`, `pasteboard`, `net`, `icmp`, `tcp`,
  `dmesg`, `sandbox`, `perms`, `spinkill`.
- **Firefox ESR** — unmodified 115.15.0esr opens `https://example.com`,
  renders text/images, two tabs, 30-minute soak.

T2 Macs are out of scope.  Wi-Fi support is BCM4331/BCM4360 only; other
chipsets are listed unsupported rather than silently ignored.
