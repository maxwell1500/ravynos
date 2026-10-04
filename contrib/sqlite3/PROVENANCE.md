# sqlite3 — provenance of the vendored amalgamation

Vendored so that `BSD/lib/libsqlite3` has the sources its Makefile names.
Without these three files the library cannot be built at all (`sqlite3.c`,
`sqlite3.h`, `sqlite3ext.h` under `contrib/sqlite3/`), and `LaunchServices`
— which `#include <sqlite3.h>` and links `-lsqlite3` — cannot link.

## What was obtained

The **official amalgamation** published by SQLite, not a hand-written or
truncated copy. `shell.c` from the archive is deliberately **not** vendored:
the Makefile builds only `sqlite3.c` and installs only the two headers.

| field | value |
|---|---|
| source URL | `https://sqlite.org/2026/sqlite-amalgamation-3530400.zip` |
| publisher | SQLite (sqlite.org), official download page `https://sqlite.org/download.html` |
| version | **3.53.4** (amalgamation, source id `3530400`) |
| archive size | 2,946,650 bytes |
| archive sha256 | `1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d` |
| archive SHA3-256 | `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e` |
| retrieval date | **2026-10-04** |

The SHA3-256 is the value SQLite publishes for this artifact on its download
page (`PRODUCT,3.53.4,2026/sqlite-amalgamation-3530400.zip,2946650,628a44cf…`),
and the downloaded archive hashes to exactly that, so the bytes are the
publisher's. SHA3-256 is recorded because it is the publisher's own checksum;
sha256 is recorded because it is what this tree's other tooling uses.

A local copy was checked first and rejected: the Homebrew cache on this host
holds only the **bottle** (`sqlite--3.53.4.tahoe.bottle.1.tar.gz`) and
`/usr/local/Cellar/sqlite/3.53.4/` holds only built artifacts — no `sqlite3.c`
anywhere (`find /usr/local/Cellar/sqlite -name sqlite3.c` → empty). A real
amalgamation therefore had to be fetched.

## Vendored files

| file | bytes | sha256 |
|---|---|---|
| `sqlite3.c` | 9,515,341 | `b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189` |
| `sqlite3.h` | 690,838 | `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d` |
| `sqlite3ext.h` | 39,175 | `ac9645e5c9ff0cf176efdd6e75cb5e98f46295d38e02db5c4d208826a39ab4be` |

These are byte-for-byte the files inside the archive; they are **not** edited
by this tree.

## Licence

SQLite is in the **public domain**. The SPDX identifier used by the project
(and by Homebrew's `sqlite` formula) is `blessing`
(<https://sqlite.org/copyright.html>). No licence text is required to
redistribute it.

## Convention

`tools/bootlab/PROVENANCE-PLAN.md` is the project's standing provenance record.
It is prose plus an enforced gate for **binary** borrowing
(`provenance_scan.py` flags host-dyld-cache images); it does not carry a
machine-checked manifest of *source* hashes, so there is no manifest to add an
entry to. The component-root convention is the plain `_PROVENANCE` file
(`Libraries/_PROVENANCE`, `Developer/ravynOS.sdk/_PROVENANCE`), so this import
is also recorded there as `contrib/_PROVENANCE`, with the hashes above carried
here.
