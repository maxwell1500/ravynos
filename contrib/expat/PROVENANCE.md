# expat provenance

Vendored so that `Frameworks/CoreText/fontconfig` has the XML parser its
configure requires. fontconfig links `-lexpat`; without these sources the
library cannot be built, and `CoreText` cannot link.

## What was obtained

The **official release tarball** published by the Expat project.

| field | value |
|---|---|
| source URL | `https://github.com/libexpat/libexpat/releases/download/R_2_6_4/expat-2.6.4.tar.gz` |
| publisher | the Expat project (libexpat/libexpat), official GitHub release `R_2_6_4`, published 2024-11-07 |
| version | **2.6.4** |
| archive size | 766,380 bytes |
| archive sha256 | `fd03b7172b3bd7427a3e7a812063f74754f24542429b634e0db6511b53fb2278` |

## Signature status — NOT VERIFIED

**The archive's OpenPGP signature was not fetched and not verified. No
upstream signature is claimed for these bytes.**

The upstream release does publish a detached signature for this archive
(`expat-2.6.4.tar.gz.asc`, alongside `.bz2.asc`, `.lz.asc` and `.xz.asc` in
the `R_2_6_4` asset list). That signature was **not** obtained, and no
signer, key or uid is asserted here.

There is deliberately no key fingerprint in this file. A previous revision
of this file carried `key 3C2A6B6E6B6E6B6E6B6E6B6E6B6E6B6E6B6E6B6E`, which
was **not a real fingerprint** — it was a placeholder that had never been
verified against anything. It has been removed rather than replaced with a
different unverified claim.

Verification tooling is not available on this host: `gpg`/`gpg2` are not
installed and the `pgpy` Python module is absent, so a signature check could
not be performed here even in principle. Integrity below rests on the
sha256 match against the upstream-published archive, nothing more.

## What WAS verified

1. **Archive identity.** The tarball was re-fetched from the URL above and
   its sha256 computed on this host: `fd03b717…fb2278`, matching the value
   recorded here. The archive is the publisher's.
2. **Vendored sources are byte-for-byte from that archive.** Every `lib/*.c`
   and `lib/*.h` file below was compared with `cmp` against the extracted
   tarball and is **identical** — not edited, not regenerated, not truncated.
   The same holds for `COPYING`, `configure`, `CMakeLists.txt` and
   `lib/libexpat.def.cmake` (`libexpat.def.cmake` is vendored as
   `libexpat.def.cmake`).
3. **`expat_config.h`** is **identical to the copy shipped in the 2.6.4
   tarball**, not a locally generated substitute. (The 2.6.4 release does
   ship a ready-made `expat_config.h` at the archive root.)

### Sources — identical to the upstream archive

| file | bytes | sha256 |
|---|---|---|
| `xmlparse.c` | 287,287 | `c1518244dd5ea397e345d00e12cc45d42f43453ed208218559c981c97a0583e2` |
| `xmltok.c` | 54,346 | `5b16c671ccc42496374762768e4bf48f614aecfd2025a07925b8d94244aec645` |
| `xmlrole.c` | 35,475 | `71fb52aa302cf6f56e41943009965804f49ff2210d9bd15b258f70aaf70db772` |
| `xmltok_impl.c` | 53,720 | `a3fe18ff32b21fbcb7c190895c68158404e1b9fb449db6431bc08b261dc03938` |
| `xmltok_ns.c` | 4,640 | `6ce6d03193279078d55280150fe91e7370370b504a6c123a79182f28341f3e90` |
| `expat.h` | 44,120 | `0f750bc336e510d14ac9a3e63fc2399f60f3f04f0061c426e86751ed5fba90e4` |
| `expat_external.h` | 6,029 | `7ca9ed28dd5e08eac425931894fabd4c876db8f4be26f9b9a33c2e4f70a0d6c3` |
| `internal.h` | 6,343 | `f7523357d8009749e7dba94b0bd7d0fa60e011cc254e55c4ebccd6313f031122` |
| `ascii.h` | 3,682 | `42f8b392c70366743eacbc60ce021389ccaa333598dd49eef6ee5c93698ca205` |
| `asciitab.h` | 3,520 | `1cc0ae749019fc0e488cd1cf245f6beaa6d4f7c55a1fc797e5aa40a408bc266b` |
| `iasciitab.h` | 3,590 | `ad8b01e9f323cc4208bcd22241df383d7e8641fe3c8b3415aa513de82531f89f` |
| `latin1tab.h` | 3,573 | `eab66226da100372e01e42e1cbcd8ac2bbbb5c1b5f95d735289cc85c7a8fc2ba` |
| `nametab.h` | 9,044 | `67dcf415d37a4b692a6a8bb46f990c02d83f2ef3d01a65cd61c8594a084246f2` |
| `siphash.h` | 13,014 | `f537add526ecda8389503b7ef45fb52b6217e4dc171dcc3a8dc6903ff6134726` |
| `utf8tab.h` | 3,522 | `8cd26bd461d334d5e1caedb3af4518d401749f2fc66d56208542b29085159c18` |
| `winconfig.h` | 2,038 | `e70948500d34dfcba4e9f0b305319dfe2a937c7cbfb687905128b56e1a6f8b33` |
| `xmlrole.h` | 4,679 | `228470eb9181a9a7575b63137edcb61b817ee4e0923faffdbeba29e07c939713` |
| `xmltok.h` | 12,894 | `6b8919dc951606dc6f2b0175f8955a9ced901ce8bd08db47f291b6c04227ae7f` |
| `xmltok_impl.h` | 3,430 | `f05ad4fe5e98429a7349ff04f57192cac58c324601f2a2e5e697ab0bc05d36d5` |

Also byte-identical to the upstream archive: `COPYING`, `configure`,
`CMakeLists.txt` and `libexpat.def.cmake`
(`f6c882bff8ab40f194c94a69bd237ffd7b58a73cb39dd755910377543e8ed166`), the
last vendored as `libexpat.def.cmake` from the archive's `lib/`.

### Build files — NOT identical to the upstream archive

| file | sha256 |
|---|---|
| `Makefile.am` | `31695f595a9b4ee971f63f1cc5991a6addd6fcec792006793b647d0cc6204139` |
| `Makefile.in` | `bdd754a838eed95f0880767ee89386b1047630dd2fcf37159f2c0e30ee632898` |

No build in this tree consumes them — fontconfig builds expat through its own
`configure`, and nothing under `tools/`, `Frameworks/CoreText/`, `BSD/` or any
`.mk`/`.sh`/`.py`/`.cmake` refers to `contrib/expat/Makefile.*`. They are
recorded here so the discrepancy is visible rather than silent, and should be
either replaced with the 2.6.4 originals or deleted.

## Licence

Expat is **MIT** (`SPDX:MIT`). `COPYING` is vendored verbatim
(sha256 `122f2c27000472a201d337b9b31f7eb2b52d091b02857061a8880371612d9534`).

## Convention

`tools/bootlab/PROVENANCE-PLAN.md` is the project's standing provenance
record. The component-root convention is the plain `_PROVENANCE` file, so this
import is also recorded in `contrib/_PROVENANCE`.