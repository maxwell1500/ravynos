# Darwin 24 Integration Plan — ravynOS

Multiphase plan with microsteps for completing the "put Darwin 24 into ravynOS" program:
replacing the project's ~macOS-12-era Darwin generation with Darwin 24 (xnu-11215) —
kernel first (done), then the userland stack built from vendored Apple source, then
real launchd, then system services.

Framing rule for every phase: **if Apple source exists (this repo or
apple-oss-distributions), build it — do not reimplement, do not stub.** Stubs are
bring-up scaffolding and must be tracked for replacement.

---

## Current State (verified 2026-09-06)

| Layer | Status | Evidence |
|---|---|---|
| Kernel | **Darwin 24 xnu-11215 (Darwin Kernel 24.3.0) boots end-to-end** | `/tmp/full_boot.out` — no `-s`, no `-no_shared_cr3`, zero traps |
| Boot chain | EDK2 OVMF → `boot.efi` typed over serial socket → `bsd_init` → PID 1 | `/tmp/test_split_boot.py` modes `split`/`full`/`fallback` |
| Storage | FAT32 root via in-kernel AHCI `bdevsw` (major 1) + msdosfs mount | `/Users/max/Projects/ravynos` uncommitted: `ahci_block.c`, `msdosfs_vfsops.c` |
| PID 1 | **Static freestanding stub** (4.3 KB, raw syscalls, tick loop) | `/tmp/init_static.c` → staged as `/sbin/launchd` |
| Dynamic exec | Kernel-side exec path proven (`load_init_program`, dyld3 ran) | `/tmp/interactive4.out` (cat + staged libSystem, PID-1 file I/O) |
| Userland libs | **Hand-staged dyld-1066-era dylib pile + libSystem stub** — placeholder, not built artifacts | `/usr/lib` on `/tmp/fresh_test.img` |
| Blocking issue | dyld abort: `Library not loaded: /usr/lib/libobjc.A.dylib` — no dynamic PID-1/exec | namespace 6 subcode 0x1 |
| Security | `cs_validate` permissive; no trust cache from SSV; `amfi==NULL` | `kern_cs.c` uncommitted diff |
| Multi-CPU | Unproven (`cpus=1` boot arg) | boot cmd |
| Kexts | None loaded (`can't perform kext scan: no kext summary`); IOKit built-in lazy | boot logs |

Key tooling (all under `/tmp` — must be moved into `tools/`, see Phase 0):
- `/tmp/build_new_kernel.sh` → `/tmp/new_kernel.development` → strip → image
- `/tmp/update_kernel_on_disk.py` (`FAT32Writer`), `/tmp/install_init.py`
- `/tmp/test_split_boot.py` (QEMU harness, socket-typed boot command)
- `/tmp/mon_boot3.py` (headless boot; writes `/tmp/interactive5.out` only)
- Canonical boot args: `-v serial=1 debug=0x14e keepsyms=1 slide=0 kcsuffix=development rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 -no_compat_check cpus=1 quiet_boot=1`

Gotchas (enforced by plan below):
1. NEVER call `FAT32Writer.update_dir_entries()` blindly — it false-matches Mach-O file
   data as directory entries. Patch the known 32-byte dir entry manually.
2. Stale pflash vars → UEFI `#UD RIP 0xB0000` at handoff. Restore
   `cp /tmp/test_vars2.fd <vars>` before any run that previously panicked.
3. `random_init: failed to allocate a major number` panic is intermittent — re-run
   once before investigating.
4. Kernel symbolication requires fresh `nm` kallsyms per build (slide changes per run).

---

## Phase 0 — Freeze the Bring-up Harness (make reproducibility real)

Goal: the boot pipeline stops being `/tmp` archaeology. Everything below depends on
being able to rebuild a bootable image from a clean checkout in one command.

- [ ] 0.1 Create `tools/bootlab/` in-repo; move `build_new_kernel.sh`,
      `strip_kernel.py`, `update_kernel_on_disk.py` (as `fat32img.py` + CLI),
      `test_split_boot.py`, `mon_boot3.py` into it.
- [ ] 0.2 Replace `FAT32Writer.update_dir_entries()` with explicit
      `set_file(cluster_chain, dir_cluster, name83, size)`; delete the old method.
- [ ] 0.3 Add `tools/bootlab/mkimage.py`: builds a fresh FAT32 image from a manifest
      (kernel, boot.efi, /bin, /sbin, /usr/lib tree, /hello.txt) — no more surgical
      cluster patching of a frozen image.
- [ ] 0.4 Add `tools/bootlab/run.sh <mode>` wrapper: fresh vars copy from a pristine
      `vars.fd` template + boot + serial capture + pass/fail grep (`alive tick|panic`).
- [ ] 0.5 Commit current uncommitted kernel work as a labeled checkpoint
      (`darwin24-bootlab-2026-09`): ahci_block.c, msdosfs_vfsops.c, bsd_init.c,
      pmap/pmap.h, bsd_i386.c, idt64.s, i386_init.c, i386_vm_init.c, kern_cs.c,
      ubc_subr.c, kern_trustcache.c, pthread_builtin.c, systemcalls.c.
- [ ] 0.6 Write `tools/bootlab/README.md`: boot args table, image layout (FAT32 BPB
      offsets, cluster map), the 4 gotchas above.
- [ ] **Exit:** `tools/bootlab/run.sh full` from a clean clone boots to
      `alive tick 3` on first try.

## Phase 1 — Real Darwin 24 Core Runtime Libraries (end the stub era)

Goal: `/usr/lib` contains **built-from-source** libobjc + libSystem + libc + dyld.
Fixes the dynamic-exec blocker by building `Libraries/objc4`, not by faking.

- [ ] 1.1 Inventory versions in tree vs Darwin 24 targets: `Libraries/objc4` (which
      objc release?), `Libraries/dyld` (1066.8 = macOS 12; Darwin 24 is dyld-11215+ —
      fetch `apple-oss-distributions/dyld` matching xnu-11215), Libsystem generation.
      Record deltas in `Docs/Darwin24SourceMap.md`.
- [ ] 1.2 Build `Libraries/objc4` against the ravynOS SDK → `libobjc.A.dylib`.
      Microsteps: CMake target; resolve ABI-set (choose `ABI_86` path for x86-64);
      no libdispatch dependency in low-level gc/exceptions paths; `install_name
      /usr/lib/libobjc.A.dylib`; verify `nm -gU` exports match what staged dylibs
      import (`nm -u` diff over all 40 staged libs).
- [ ] 1.3 Fetch + build Darwin 24 `launchd` source (apple-oss-distributions/launchd
      @ matching tag) — **compile only** for now; run is Phase 3.
- [ ] 1.4 Build `Libraries/dyld` (target generation per 1.1) and `Libraries/Libsystem`
      (+ Libc, libpthread, libmalloc, libplatform, Libinfo, Libnotify, CommonCrypto,
      libdispatch) with the in-repo xcbuild toolchain. Track per-library build status
      in a checklist inside this file.
- [ ] 1.5 Build `BSD/` tools (`cat`, `ls`, `sh`, `echo`) from tree against the new
      libSystem — replaces hand-staged pile.
- [ ] 1.6 Extend `mkimage.py` manifest format: name83 + host path + install path;
      builds `/usr/lib` + `/usr/lib/system` correctly (8.3 truncation collision table,
      e.g. `LIBSYS~15.DYL` — document each collision).
- [ ] 1.7 Stage built dylibs into test image; boot; run dynamic `/bin/cat` PID 1
      (the pre-existing dynamic cat: `/tmp/launchd_cat_backup.bin` or 1.5-built cat).
- [ ] 1.8 Delete the hand-staged dylib pile from all future images (clean cutover —
      images contain only built artifacts).
- [ ] **Exit:** dynamic `/bin/ls /` runs as PID 1, prints root listing on console,
      with zero hand-staged binaries in the image.

## Phase 2 — Process Model: fork/execve + Interactive Console

Goal: PID 1 spawns children; typed serial input reaches a process. Gate for
single-user. (Static-init prototype is the vehicle until real launchd.)

- [ ] 2.1 Microstep: static init calls `getpid()/getppid()` round-trip — sanity of
      proc struct from userland.
- [ ] 2.2 `fork()` (or `vfork()`+`execve()`): extend `/tmp/init_static.c` (move into
      `tools/bootlab/init/`) to `fork()` + child `execve("/bin/cat", ...)` + parent
      `wait4()`. Kernel-side watch: `exec_activate_image` path with permissive
      `cs_validate`; expect first real cross-process pmap work.
- [ ] 2.3 Fix whatever breaks (predictions: `mac_syscall`/mach port setup for
      spawned task, `proc_justspawn` task signal, `psend`/`ast` path on TCG).
- [ ] 2.4 Console read path: verify `read(0)` blocks + returns bytes typed on the
      serial socket (`-serial unix:` already delivers RX). Kernel side: console
      device + (likely) kdb/cons code — the current console is write-only.
- [ ] 2.5 Mini-shell v1 (static, raw syscalls): readline on fd0, `fork`+`execve` on
      absolute paths, builtin `exit`. Install as `/sbin/launchd` replacement in lab
      images only.
- [ ] 2.6 Real `/bin/sh` (1.5-built, dynamic) launched by mini-shell; fix dylib
      closure gaps as they surface (no more libobjc-class surprises — Phase 1 built).
- [ ] 2.7 Terminal semantics pass: ioctl (`TIOCGETA`, window size), signals
      (`SIGINT` on Ctrl-C byte → foreground pgrp), `tcsetpgrp`.
- [ ] **Exit:** human types `ls /bin` on the serial socket, output appears; Ctrl-C
      interrupts a `cat` with no console input.

## Phase 3 — Real launchd + Single-User Mode

Goal: Apple launchd (Darwin 24 source) is PID 1; `boot-args -x`/`-s` semantics land.

- [ ] 3.1 Run 1.3-built launchd as PID 1. Expected failures to sequence:
      (a) `/etc/launchd.conf` absent → fine; (b) `xpc` bootstrap requires
      `kernel_task` rendezvous ports — verify `bootstrap` ports come up (xnu side is
      stock, likely OK); (c) `utimes`/`sethostname`/`setgid` denied syscalls → fix
      `bsd_init` env; (d) job parsing of missing plists → run with empty
      `/System/Library/LaunchDaemons`.
- [ ] 3.2 Bring up launchd **maintenance mode** (`launchd -m`, what RB_SINGLE gives
      us): needs `RB_SINGLE` plumbed from boot.efi args (`-x` or `-s`) through
      `bsd_init`'s `rb_safe_level`/`init_path` selection — audit `load_init_program`
      boot-args handling for `single-user` semantics (upstream xnu keys off
      `PE_ioplg`/`IOPlatformExpert` `apple-boot-args`; provide built-in PE shim value).
- [ ] 3.3 launchd -m spawns root `/bin/sh` on `/dev/console` (its maintenance job
      definition) — this is the deliverable "single user mode".
- [ ] 3.4 Add `/etc/rc` real script (mount -a with fstab on FAT32 root, hostname,
      swap-none) executed by launchd rc job.
- [ ] 3.5 `multiuser` path: minimal LaunchDaemons set that doesn't depend on closed
      services (cron-class, log-stream placeholder), documented as a curated set.
- [ ] **Exit:** boot with `-x` → passwordless root shell on serial console,
      `launchd` visible as pid 1 (`ps` via Phase 2 shell). Boot without `-x` →
      curated multi-user to the same shell prompt.

## Phase 4 — Storage, Filesystems, and the Mach Services Surface

Goal: ravynOS holds the macOS folder-layout contract and real FS support (README
design goals: HFS+, APFS, FAT, NTFS, ZFS) without Apple platform services.

- [ ] 4.1 Move AHCI block driver from `bsd_init` hack to a real kext
      (`Kernel/Extensions/` — reference-era `AppleIntelPIIXATA`/IOATAFamily exist as
      APSL source in `_PROVENANCE`; port to current IOKit or write minimal
      AHCI kext). Retire `ahci_block.c` bdevsw as the only path.
- [ ] 4.2 Kext loading path: build a BOOTKC (kernel collection) from tree kexts
      (IOPCIFamily, IOKit family, AHCI, msdosfs/HFS+ kext), fix `no kext summary`
      → kmalloc'd kext map (`can't perform kext scan`) via stock
      `kextd`-less load path: `kextmap` from BOOTKC handled by xnu directly.
- [ ] 4.3 HFS+ read-write (xnu's msdosfs sibling: AppleHFSPlus is not APSL —
      options: port `libhfs` from hfsplus-tools (open source) mounted via a FUSE-less
      in-kernel kext from the FreeBSD `msdosfs`/`hfs+` lineage — ravynOS ships
      FreeBSD foundations per README: prefer FreeBSD's `hfs+` kernel module port).
- [ ] 4.4 APFS: defer to FreeBSD `apfs` module port (same lineage note);
      read-only first.
- [ ] 4.5 `/etc/fstab` + `mount(8)` from `BSD/sbin/mount*` built (Phase 1 recipe).
- [ ] 4.6 Mach bootstrap surface audit: `bootstrap_look up`, `task_for_pid` policy,
      `host_info` — regression-test with a small Mach probe binary suite in
      `tools/bootlab/probes/`.
- [ ] **Exit:** root on HFS+ (or APFS RO) with `/System /Library /Users /Volumes`
      layout; kexts loading from BOOTKC; serial shell shows `mount` output.

## Phase 5 — Security Model De-Permissiving

Goal: replace the bring-up "accept everything" knobs with policy that actually
loads, per subsystem. Keep lab escape hatches as explicit boot args.

- [ ] 5.1 Inventory current permissive knobs as a table in `Docs/SecurityDebt.md`:
      `cs_validate` bypass, trust cache guards, `amfi==NULL`, `kcsuffix` fudge,
      `no_compat_check`. Each gets an owner step.
- [ ] 5.2 Build trust caches **ourselves** with `bctl` (Apple OSS, matches
      Darwin 24) over the Phase-1-built dylib set; sign the kernel ad-hoc; teach
      kernel to load the FAT-resident trust cache through the existing
      `trustcache` bootstrap path (xnu source supports `cp=aslr,slide=...`-style
      loading; the file form lives at `/System/Library/Caches/com.apple.kernelcaches`).
- [ ] 5.3 AMFI as a kext with a ravynOS policy: ad-hoc signatures accepted for
      system-partition files only (document the deliberate difference from Apple
      SSV — SSV/tickets stay out of scope permanently, per closed-residue rule).
- [ ] 5.4 Code-sign `mount`/launchd/sh with real `codesign`-equivalent: use
      `cctools`/`ld64` in `Developer/cctools` + `xcodebuild`-less sign helper
      (`ldid`, open source, is the accepted tool for ad-hoc Mach-O signing).
- [ ] 5.5 Flip defaults: remove permissive `cs_validate` patch → policy from 5.2/5.3;
      lab images boot with existing args, security-lab images boot without.
- [ ] **Exit:** unsigned binary fails to exec with `EXEC_BADASSOC`/codesign kill;
      signed staged set boots clean.

## Phase 6 — Multi-CPU, Timers, Platform Parity

Goal: the `-smp 2` (and beyond) path works; timing is honest; no `-s`-class flags
needed anywhere.

- [ ] 6.1 Audit `i386_init`/`cpu_mp_start` for the AppleAPIC/ACPI enablement state
      (APSLE kexts present in tree; boot currently single-CPU by arg).
- [ ] 6.2 Drop `cpus=1`; TCG 2-vCPU boot; fix IPI/APIC bring-up (expect: TVMClock,
      TSC deadline missing on TCG → LAPIC timer fallback path).
- [ ] 6.3 Timekeeping: rtc via CMOS driver, `mach_absolute_time` sanity vs wall clock.
- [ ] 6.4 Re-run the full split-CR3 matrix (`split`/`full`/`fallback`) × `smp 2`;
      commit results table into this file.
- [ ] **Exit:** `smp 2`, both CPUs online in `sysctl hw.ncpu` + tick loop stable,
      scheduler paths exercised by Phase 3 multi-user.

## Phase 7 — GUI Foundation (bridge to existing ravynOS tracks)

Goal: the WindowServer/CoreGraphics/Onyx2D trees get a working Darwin 24 substrate.
Keep this phase deliberately coarse — it's several own-planned programs.

- [ ] 7.1 Framebuffer kext over QEMU `ramfb`/Bochs dispi (GOP hands off; current
      stack is BSDFramebuffer-class) → expose IOFB-style device for WindowServer.
- [ ] 7.2 WindowServer against Darwin 24 libSystem + built IOKit user frames
      (Phase 1 libs): first window with CPU compositing (Onyx2D path — exists today).
- [ ] 7.3 OpenGL story decision (record in ADR): vendor Mesa (llvmpipe/GL on
      CPU) vs. port IOGL — unblocks apps needing GL; **Metal stays its own program**
      (per owner direction, post-Tahoe): the Metal gap remains the largest compat
      hole; log it as such, do not half-solve here.
- [ ] 7.4 Event input: PS/2 kexts (APSLE source in tree) or virtio-input under QEMU.
- [ ] **Exit:** boot to a rasterized login-less desktop-ish UI with keyboard, driven
      by real launchd session bootstrap.

## Phase 8 — Generate Handoff / Tech Debt Closeout

- [ ] 8.1 Version-sync report: every vendored component vs Darwin 24 tag parity
      (kernel: done; userland: from Phases 1-3; frameworks: Phase 7).
- [ ] 8.2 Retire this file → fold remaining into `kernel_upgrade_techdebt.md`'s
      architecture doc; archive plan in `Docs/`.
- [ ] 8.3 Roadmap items to keep visible: real T2 support (post-Tahoe, owner
      directive), arm64, Metal program.

---

## Cross-cutting rules

1. Every phase exit is a **booted-image observation**, not a compile success.
2. New binaries reach images only via `mkimage.py` manifest (no cluster surgery).
3. Each closed-residue decision (skip/degrade/substitute) gets an ADR in
   `Docs/adr/` — never a silent stub.
4. Kernel edits keep the audit-comment style used in `i386_init.c` split-CR3 steps
   so a future rebase onto newer xnu can diff our glue out.
5. Intermittent-boot rule: one clean re-run before any panic investigation.

## Verification harness reference

| Command | Meaning |
|---|---|
| `tools/bootlab/run.sh full` | no `-s`, no `-no_shared_cr3` — the gold path |
| `tools/bootlab/run.sh split` | `-s` only |
| `tools/bootlab/run.sh fallback` | `-s -no_shared_cr3` legacy |
| pass grep | `=== RAVYNOS PERSISTENT INIT RUNNING AS PID 1 ===` + ≥2 `alive tick` |
| fail grep | `panic:`, `Kernel trap`, `#UD`, `STOP]` |
