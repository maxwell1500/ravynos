# libsystem_info — unmet link dependencies

`libsystem_info` is **source-complete and compile-complete**. All 107 translation
units compile and archive into `libsystem_info.a`. The only thing standing
between it and a working dylib is that three libraries its `LDFLAGS` names are
not present in the SDK.

This file exists so the gap is explicit rather than "worked around". **Do not
drop the three `-l` flags to make the link pass** — that produces a dylib with
unresolved symbols, which is a stub by another name. The link must fail until
the three libraries are really built.

## Status

| Library | Required at | In SDK? | Build status |
|---|---|---|---|
| `libxpc` | `Makefile:150` (`-lxpc`) | absent | **Blocked** on the mach-header unification. Compiles to `unknown type name 'io_main_t'` and `unknown type name 'ipc_space_read_t'` in `Kernel.framework/Versions/A/PrivateHeaders/mach/{mach_host,mach_port}.h` — the same shadowing that was removed from `libsystem_dnssd`. Source is vendored at `Libraries/Libsystem/libxpc/`. |
| `libsystem_trace` | `Makefile:152` (`-lsystem_trace`) | absent | **Blocked**, but *not* on the mach headers. Fails on libkern/osfmk types: `unknown type name 'lck_spin_t'`, `invalid application of 'sizeof' to an incomplete type 'struct os_log_buffer_s'`, `unknown type name 'os_log_buffer_context_t'`. Adding `-I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk -I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk/i386` does **not** fix it (still 20 errors), so this is a deeper libkern header-generation gap, not a missing include path. Source is vendored at `Libraries/Libsystem/libsystem_trace/`. |
| `libsystem_notify` | `Makefile:152` (`-lsystem_notify`) | absent | Source is vendored at `Libraries/Libsystem/libsystem_notify/`. Its `notify_ipc.defs` is also consumed by this Makefile at line 158. |

`libsystem_info` is *not* in a position to fix either of the first two itself;
neither `libxpc` nor `libsystem_trace` is one of its own Makefiles.

## Unblock prediction

Two of the three (`libxpc`, and any future mach-header consumer) unblock
directly when the mach-header unification policy lands. `libsystem_trace` will
**not** unblock from that — it needs separate libkern/osfmk header work.

## Everything else already resolves

The other nine `LDFLAGS` libraries are present: `libsystem_c`, `libsystem_blocks`,
`libsystem_malloc`, `libsystem_platform`, `libsystem_kernel`, `libsystem_pthread`
(SDK) and `libsystem_dnssd` (now a real 62,064-byte build, not the old
8,064-byte stub), plus `libdispatch` and `libdyld`.

## Evidence

Compile stage is complete:

    libsystem_info.a   1,407,784 bytes, 107 objects

Linking the same archive with only the three unavailable libraries removed
(produced by hand, **not** committed to the Makefile) yields a working
`libsystem_info.dylib`: 408,368 bytes, 523 defined exports, including
`_res_query`, `_getaddrinfo`, `_getnameinfo` and `_hstrerror`. That run is
diagnostic only; it is not the shipped configuration.

## Environment requirements

Two variables must be exported or the link fails for unrelated-looking reasons:

- `PROD_VERSION` — unset, `-Wl,-current_version,` is malformed and ld64 reports
  `malformed version number '-compatibility_version' cannot fit in 32-bit
  xxxx.yy.zz`.
- `DEVEL` — `${ROOT_SOURCE_DIR}/Developer`; several Makefiles spell include
  paths relative to it.

`${MIG}` must also resolve (`${TOOLCHAIN}/usr/bin/mig`) for the
`notify_ipc.defs` rule at line 158 to generate `notify_ipcUser.c`.
