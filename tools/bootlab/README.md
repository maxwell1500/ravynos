# bootlab

Reproducible build → disk-image → QEMU-boot pipeline for the ravynOS bringup
kernel (Darwin 24 / xnu-11215 x86_64). Everything the boot test needs lives
here; `work/` is scratch and gitignored, `assets/` + `manifest.json` are the
committed source of truth for the disk tree.

## Quick start

```sh
tools/bootlab/run.sh full      # build kernel + init + image, boot, watch serial
```

Exit test: serial log shows the PID1 banner and `alive tick N` lines with zero
traps/panics. Log: `work/serial_full.log`.

```sh
tools/bootlab/run.sh dynamic   # dynamic-userland gate: execve a dylib-linked binary
```

`run.sh full` is **not** a userland gate. Its PID 1 (`init/init_static.c`)
execs nothing, so it cannot observe dyld, the libSystem closure, or a single
dylib-linked `main()`. It reports a clean boot while the thing being built is
untested. `run.sh dynamic` is the instrument for that: it stages a static
exec-runner as PID 1 which `execve()`s the dylib-linked `/bin/echo`, and
judges on whether that binary reached `main()`. Wired into
`build_all_libsystem.sh` as a **known-blocked stage** (`dynamic_userland`), so
its fault signature appears in the standard driver run and any change in that
signature is visible. Log: `work/serial_dynamic.log`.

## Steps (each idempotent)

| command | what it does |
|---|---|
| `run.sh build` | `kernel_build.py`: recompiles the boot-critical objects (via committed `templates/*.json` + build-tree `<obj>.o.json` clones), compiles `msdosfs` (`msdosfs_compile.sh`), relinks with the build tree's `.LDFLAGS`, strips → `work/new_kernel.development`, `work/stripped_kernel.development`. Requires one completed full xnu build tree (`RAVYN_BUILD_DIR`, default `/Users/max/Projects/build/DEVELOPMENT_X86_64`). |
| `run.sh init` | `build_init.sh`: static no-libc PID1 (`init/init_static.c`) → `work/init` (banner + busy-spin tick loop). |
| `run.sh mkimage [img]` | `mkimage.py`: builds a 512 MiB FAT32 image from `manifest.json`. Head (MBR+GPT+BPB+FSInfo+reserved) and tail (backup GPT) are verbatim golden bytes (`assets/template_{head,tail}.bin`), so firmware-visible geometry is bit-identical to the proven golden disk. Kernel payload: newest of `--kernel`, `work/stripped_kernel.development`, `assets/kernel.development`. Verifies by reopening the image and re-hashing every file. Default output `work/boot.img`. |
| `run.sh boot [mode]` | `boot.py`: QEMU q35 + OVMF (`-pflash` code from `/usr/local/share/qemu`, vars freshly copied from `assets/vars.fd` every run — stale vars fault at handoff). Waits for `Shell>`, types the canonical boot.efi command. Modes: `full` (shared CR3), `split` (`-s`), `fallback` (`-s -no_shared_cr3`). |
| `run.sh dynamic` | `run_dynamic_gate.sh`: stages `init/init_exec_dynamic.c` as PID 1 via `manifest_dynamic.json`, boots, and returns 0 = `/bin/echo` reached `main()`, 1 = blocked (dyld/kernel fault, signature printed), 2 = harness problem (kernel never booted). |

Kernel is installed at BOTH `System/Library/KernelCollections/BootKernelExtensions.kc`
and `System/Library/Kernels/kernel.development` (boot.efi with
`kcsuffix=development` loads the KC path).

## Files

- `fat32img.py` — FAT32 reader/writer library (cluster chains, LFN + 8.3
  entries, FSInfo, template-head builder, walk/verify).
- `manifest.json` — disk tree: files, globs (directory passthrough), assets.
- `manifest_dynamic.json` — same tree, but `/sbin/launchd` is the static
  exec-runner instead of the static init. Selected by `mkimage.py --manifest`.
- `extract_assets.py` — one-time harvest of userland/boot assets from the
  golden image into `assets/` (already run; rerun only to refresh payloads).
- `kernel_build.py` + `templates/` — incremental kernel recompile/relink.
- `msdosfs_compile.sh` — in-kernel msdosfs objects (`work/msdosfs_objs`).
- `boot.py` — QEMU harness; boot command sent over the serial unix socket.
- `init/init_static.c` + `build_init.sh` — static PID1 proof-of-life binary.
- `init/init_exec_dynamic.c` + `build_init_exec.sh` — static PID1 that
  `execve()`s `/bin/echo`; the dynamic-userland gate's instrument.
- `stage_dynamic_libs.sh` — copies the **real** `libobjc.A.dylib` (our objc4
  build product, 1,608,088 B, ~2,100 exports) out of the generated SDK into
  `assets/usr/lib/`, and refuses to proceed if what is staged is a stub. Run
  by `build_all_libsystem.sh` and by the dynamic gate; idempotent.
- `run_dynamic_gate.sh` — the gate itself; verdict read from the serial log
  only after the boot process exits.

## Known-good boot command

```
fs0:\System\Library\CoreServices\boot.efi -v serial=1 debug=0x14e keepsyms=1 \
  slide=0 kcsuffix=development rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 \
  -no_compat_check cpus=1 quiet_boot=1
```

## Gotchas

- EDK2's FAT driver validates LFN checksums (spec byte 13) — a wrong checksum
  makes `ls`/load fail with "File Not Found" even though the bytes are there.
- 8.3 collision suffixes must fit 8 chars (`stem[:8-len(~n)] + ~n`); a 9-char
  stem silently shifts every following directory entry by one byte.
- `startup.nsh` never auto-runs with these OVMF vars; the harness types the
  boot command after `Shell>` appears.
- Dynamic (dyld) binaries need `usr/lib/libobjc.A.dylib` staged, because
  `libsystem_symptoms.dylib` references it. It is now staged from the SDK by
  `stage_dynamic_libs.sh`.

  > **Never stage the 6,856-byte `build_stubs.sh` placeholder. This is the
  > argument for checking EXPORTS rather than SIZE.** The stub *does* define
  > `_objc_msgSend` and `_objc_msgSendSuper2` — as no-ops at `0x540`/`0x550` —
  > while lacking ~2,100 of the real artifact's 2,145 exports. So it is a valid
  > Mach-O, correctly named, at the right path, and 0.4% of the right size:
  > **every size-based check passes it.** Shipping it converts a **loud dyld
  > abort into a silent wrong answer** — the first Objective-C call returns
  > whatever an empty stub returns, with no error anywhere. That is exactly the
  > class `Libraries/check_sdk_stubs.sh` exists to prevent.
  >
  > Real: 1,608,088 B / 2,145 defined symbols. Stub: 6,856 B / 45.
  > `stage_dynamic_libs.sh` checks size, export count *and* `_objc_msgSend`, and
  > **was negative-tested** (a 4,200-byte fake was planted and the gate was
  > confirmed to reject it) — a gate never seen red is the same defect as the
  > derived artifact gate's 19 false reds.
>
> **With `libobjc` staged, the next fault is CoreFoundation, referenced from
> `libxpc.dylib` — and it is inherited, not ours.** Our own
> `Libraries/Libsystem/libxpc` (8 `.c` files) has **0** `CoreFoundation`
> includes and **0** `CF*` symbols, and its `Makefile` links no framework. The
> edge is a non-weak load command in `assets/usr/lib/system/libxpc.dylib`, an
> **Apple shared-cache extract**. `Frameworks/CoreFoundation` source does exist
> in the tree (5.5 MB, 87,013 lines, 44 public headers) and there is no CF
> binary in the SDK, but **do not build it to satisfy a dependency our own
> `libxpc` does not have** — replace the extract with our `libxpc.dylib` (whose
> default target is already `all: libxpc.dylib`) and the edge disappears.
> Full assessment: `Libraries/Libsystem/REMEDIATION_PLAN.md`, section
> "2026-09-27".
- **The `/etc/rc` path is currently DEAD.** Until 2026-09-26 a "MINI-SHELL"
  PID 1 ran `/etc/rc`, which is what executed `/bin/echo` and `/bin/cat`. That
  program's source is **not in the tree** — only its serial output survives, in
  gitignored `work/`, so it is not recoverable. `run.sh dynamic` replaces the
  capability deliberately, from source; do not assume `/etc/rc` is exercised.
- **UNEXPLAINED: the UEFI `#UD` at handoff is not always a stale pflash.**
  `boot.py` re-copies `assets/vars.fd` on every run, yet on 2026-09-27 a boot
  still died before the kernel with
  `!!!! X64 Exception Type - 06(#UD - Invalid Opcode) !!!!`,
  `RIP - 00000000000B0000`, `!!!! Can't find image information. !!!!`
  (efiboot, `#[EB|MMD]` memory-map dump, no `bsd_init`, no PID 1 banner). A
  re-run with an identical image booted normally. So the "always copy fresh
  vars" workaround is **necessary but not sufficient**, and this occurrence is
  recorded as unexplained rather than filed under the known cause. The dynamic
  gate treats a missing PID 1 banner as a harness fault (exit 2), never as a
  kernel verdict.
- `boot.py`'s exit code is 0 only if the log contains `alive tick`; the dynamic
  gate's PID 1 execs instead of ticking, so that code is meaningless there and
  the gate judges on the log.
- Commits are local-only; never push.


## Cost of the dynamic gate, and the baseline of record

- The gate costs **205 s–358 s across two full runs — 40–55% of the loop**,
  and the spread is build caching, not variance in the gate. It is the only
  stage that boots anything, and the only one that can catch a dyld
  regression. `BOOTLAB_SKIP_DYNAMIC=1` keeps it out of the fast path; a
  driver run without it is **not** a baseline, for the same reason a `--quick`
  run is not (it skips stages, one of which does not build).
  Measured: run 1 = 358 s of 654 s; run 2 (serial, clean tree) = 205 s of 511 s.
  The *signature* is stable across both runs; only the panic **caller address**
  moves (`0xffffff80184cc739` / `0xffffff8018ecc739` / `0xffffff80108cc739`),
  which is kernel slide, not a change in fault. Compare the signature, never
  the address.
- **Baseline of record (full run, nothing else touching the tree):**

      stages passed 23   known-blocked 3   skipped 0   UNEXPECTED failures 2
      unexpected: libdispatch, libsystem_darwin
      check_sdk_stubs.sh  PASS
      RESULT: FAIL

  The two unexpected failures are **pre-existing and recorded**, not regressions
  — see "Neither failure is a regression from this session's work" in
  `Libraries/Libsystem/REMEDIATION_PLAN.md`. The delta from the previous
  baseline (22/2/0/2) is exactly `+1 passed` (`stage_dynamic_libs`) and
  `+1 known-blocked` (`dynamic_userland`).
