# ravynOS Complete System Boot & Technical Debt Remediation Architecture

## 1. Executive Summary & Problem Diagnosis

### 1.1 The Core Problem
Previous development iterations resolved isolated compile/link failures, toolchain anomalies, and early hypervisor faults in a piecemeal manner. However, **a complete operating system boot requires the coordinated execution of seven interdependent system tiers**:

```
[ Tier 0: Firmware & Bootloader (EDK2 / Clover / OpenCore) ]
                          │
                          ▼
[ Tier 1: Kernel Mach Bootstrap (Low-level VM, CPU, SMR, Startup Subsystems) ]
                          │
                          ▼
[ Tier 2: I/O Kit Platform & Storage Infrastructure (ACPI, PCI, AHCI/NVMe, GOP) ]
                          │
                          ▼
[ Tier 3: BSD Subsystem Bootstrap (Process 0, Sysctls, Creds, Mbufs, Knots) ]
                          │
                          ▼
[ Tier 4: VFS Root Mounting (HFS+ / DevFS / Prelinked Ramdisk) ]
                          │
                          ▼
[ Tier 5: Process 1 Construction & Userland Execve (/sbin/launchd or /bin/sh) ]
                          │
                          ▼
[ Tier 6: Userland Runtime Environment (Libsystem, Dev Nodes, TTY / Console) ]
```

When any single link in this chain is missing—such as an unregistered root filesystem driver, an unresolved device node, or a missing binary dependency in the sysroot—boot stalls.

This plan details every component, dependency, technical debt item, and implementation step required to progress from the current execution point directly to a fully booted, interactive ravynOS system.

---

## 2. Technical Debt Catalog & Permanent Semantic Solutions

### 2.1 Mach Startup & KASLR Subsystem
- **Current State:** Hardcoded fallback `startup_entries + 4334` in `Kernel/xnu/osfmk/kern/startup.c` to handle slid section headers.
- **Root Cause:** Linker symbol slide discrepancy between Mach-O `__DATA,__startup` section boundaries and the `startup_entries_end` symbol generated during LTO.
- **Permanent Solution:**
  1. Inspect the loaded kernel Mach-O header (`kernel_mach_header_t _mh_execute_header`) dynamically using `getsectbynamefromheader_64()`.
  2. Derive the exact startup table size as `sect->size / sizeof(struct startup_entry)`.
  3. Validate all function pointers against kernel text segment boundaries (`__TEXT,__text`) before invocation.

### 2.2 Zone Allocator (`zalloc.c`) & Memory Subsystems
- **Current State:** Early return / no-op guards in `kfree_type_impl_internal()` to bypass invalid pointer free panics.
- **Root Cause:** Zones instantiated during early bootstrap were freed before their corresponding zone metadata was fully registered, or pointers allocated from bootstrap arenas (`pmap_steal_memory`) were passed to standard `kfree()`.
- **Permanent Solution:**
  1. Re-enable strict pointer bounds checking in `kfree_type_impl_internal()`.
  2. Implement an early boot memory flag (`pmap_steal_active`) to prevent `kfree()` from operating on stolen boot pages.
  3. Audit all deallocation paths in `bsd_init()`, `kalloc.c`, and `zalloc.c`.

### 2.3 Decompression Pipeline (`lz4.c`)
- **Current State:** Hardcoded zero returns in `lz4_decode()` and stubbed staging hooks.
- **Root Cause:** Missing export symbols for kernel decompression staging (`lz4_stage_initialize`, `lz4_stage_monitor_availability`).
- **Permanent Solution:**
  1. Implement complete streaming LZ4 decompression routines complying with standard XNU memory-buffer APIs.
  2. Restore all exported decompression symbols in `lz4.o` to prevent kernel panics when decompressing kernel caches or ramdisks.

### 2.4 Network Filtering & Socket Inspection
- **Current State:** Bypasses in `cfil_sock_data_out()`, `cfil_sock_data_in()`, and `ip_dooptions()`.
- **Root Cause:** Content Filter engine was invoked during early BSD socket initialization before filter manager control blocks were instantiated.
- **Permanent Solution:**
  1. Add defensive NULL validation to socket filter manager handles.
  2. Ensure socket filter registration is deferred until after `bsd_init()` completes network stack initialization.

### 2.5 Out-of-Tree UBSan & Compiler-RT Runtime
- **Current State:** Ad-hoc standalone `ubsan_stubs.o` object linked to provide missing runtime symbols.
- **Permanent Solution:**
  1. Formalize minimal compiler runtime handlers (`__ubsan_handle_load_invalid_value`, `__ubsan_handle_pointer_overflow`, `__ubsan_handle_shift_out_of_bounds`) directly into `Kernel/xnu/osfmk/kern/ubsan.c` or `Kernel/xnu/libsa/`.
  2. Add build rules into `Kernel/xnu/makedefs/MakeInc.def` and `Kernel/xnu/osfmk/conf/files`.

---

## 3. Seven-Tier Architecture for Full System Boot

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 0: FIRMWARE & BOOTLOADER                                               │
│ • EDK2 OVMF Firmware -> Clover / OpenCore Bootloader                        │
│ • Drivers: OpenRuntime.efi, VBoxHfs.efi, Fat.efi, PartitionDxe.efi         │
│ • Kernel Loading: \System\Library\CoreServices\boot.efi -> kernel.development│
│ • Kernel Cache / Injected KEXTs (IOACPIFamily, AppleAHCIPort, hfs.kext)    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 1: KERNEL MACH INITIALIZATION                                          │
│ • i386_init() -> pmap_bootstrap() -> pmap_steal_memory()                   │
│ • kernel_startup_bootstrap() -> Execute STARTUP() entries dynamically       │
│ • Subsystems: STARTUP_SUB_LOCKS, VM, IPC, THREAD_CALL, SYSCTL, LOCKDOWN     │
│ • Mach Scheduler: sched_init(), thread_daemon_init(), clock_init()          │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 2: I/O KIT PLATFORM & DEVICE DRIVERS                                   │
│ • IORegistryRoot & IOPlatformExpert bootstrap                               │
│ • ACPI Matching (IOACPIFamily) -> PCI Matching (IOPCIFamily)                │
│ • Disk Controllers: RavynAHCIPort / AppleIntelPIIXATA / IONVMeFamily        │
│ • Storage Media: IOStorageFamily -> Partition Schemes (GPT / MBR)          │
│ • Display & Console: IOGOPFramebuffer -> AppleVGA / 16550 Serial UART       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 3: BSD SUBSYSTEM BOOTSTRAP                                             │
│ • bsd_init() entry from Mach bootstrap thread                              │
│ • Data structures: proc0, kauth_cred, file descriptors, mbufs, sysctls     │
│ • Virtual Memory bridge: vm_init_before_launchd()                           │
│ • Device Nodes: devfs initialization (/dev/console, /dev/null, /dev/zero)   │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 4: VFS ROOT MOUNTING                                                   │
│ • vfs_mountroot() invocation                                                │
│ • Root Filesystem Driver: hfs.kext (VFC_VFSCANMOUNTROOT) or Ramdisk / UFS   │
│ • Root Device Discovery: bdevvp(rootdev) -> mount root on "/"               │
│ • Devfs Mount: mount devfs on "/dev"                                        │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 5: PROCESS 1 (INIT / LAUNCHD) SPAWN                                    │
│ • load_init_program() in kern_exec.c                                        │
│ • Search Order:                                                             │
│     1. /usr/appleinternal/sbin/launchd.development                          │
│     2. /sbin/launchd                                                        │
│     3. /bin/sh (single-user / emergency shell fallback)                     │
│ • Mach-O binary loader: parse headers, map __TEXT and __DATA, alloc stack   │
│ • Setup initial user registers (RIP, RSP, RDI, RSI) -> Return from trap     │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TIER 6: USERLAND ENVIRONMENT & INTERACTIVE CONSOLE                          │
│ • Libsystem initialization (libsystem_c, libsystem_kernel, libdispatch)     │
│ • Standard streams (stdin, stdout, stderr) attached to /dev/console         │
│ • Execution of rc scripts or interactive prompt (/bin/sh -s)                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Deep-Dive Subsystem Requirements

### 4.1 Tier 0: Bootloader & Kernel Cache Pipeline
1. **Bootloader Config (`config.plist`):**
   - Boot arguments: `-v serial=1 debug=0x14e keepsyms=1 kcsuffix=development cpus=1 -s`.
   - Quirks: Ensure `ProvideConsoleGop=false` and `AvoidRuntimeDefrag=false` to prevent EDK2 UEFI lock assertions.
2. **Prelinked Kernel (`kernelcache`):**
   - Build `plktool` (`Developer/Default.xctoolchain/plktool/`).
   - Bundle essential KEXTs into the kernel cache:
     * `System.kext` (and plugins: `Mach`, `BSDKernel`, `IOKit`, `Libkern`)
     * `IOACPIFamily.kext`, `IOPCIFamily.kext`, `AppleI386PCI.kext`
     * `RavynAHCIPort.kext`, `IOStorageFamily.kext`, `AppleFileSystemDriver.kext`
     * `hfs.kext` (with `hfs_encodings.kext`)
     * `IOGOPFramebuffer.kext`, `ApplePS2Controller.kext`

### 4.2 Tier 2: Storage Controller & Partition Matching
1. **AHCI Controller Matching:**
   - In QEMU, the SATA controller is `8086:2922` (Intel ICH9 AHCI).
   - `RavynAHCIPort` or `AppleIntelPIIXATA` must match this device ID and publish `IOBlockStorageDevice` nubs.
2. **Partition Probing:**
   - `IOStorageFamily` inspects block devices, parses GPT/MBR partition tables, and instantiates media objects (`IOMedia`) for partition 1 (`disk0s1`).

### 4.3 Tier 4: VFS Root Filesystem & HFS+ Registration
1. **Filesystem Driver Hook:**
   - `hfs.kext` registers with VFS via `vfs_fsadd()` with flag `VFS_TBLCANMOUNTROOT`.
2. **Root Mounting (`vfs_mountroot`):**
   - Kernel evaluates `rootdev` (derived from `boot-args` or default `disk0s1`).
   - Resolves block device vnode via `bdevvp(rootdev, &rootvp)`.
   - Calls `hfs_vfsops.vfs_mountroot(mp, rootvp, ctx)` to mount the root partition on `/`.
   - Mounts `devfs` on `/dev` to provide character devices (`console`, `tty`, `null`, `zero`).

### 4.4 Tier 5: Process 1 (Userland Execution Engine)
1. **Single-User / Fallback Support:**
   - Modify `load_init_program()` in `Kernel/xnu/bsd/kern/kern_exec.c` to gracefully fall back to `/bin/sh` or `/bin/cat` if `/sbin/launchd` is not found or fails to execute.
2. **Mach-O Binary Loader:**
   - Validates that target userland binaries (`/bin/sh`, `/bin/ls`) are valid 64-bit Mach-O executables.
   - Allocates user stack, maps `__TEXT` (RX) and `__DATA` (RW), and initializes thread register state.

---

## 5. Comprehensive Step-by-Step Implementation Roadmap

```
================================================================================
STEP 1: KERNEL CODE CLEANUP & REFACTORING
================================================================================
  1.1 Revert diagnostic stubs in:
      - Kernel/xnu/osfmk/kern/zalloc.c
      - Kernel/xnu/osfmk/vm/lz4.c
      - Kernel/xnu/bsd/net/content_filter.c
      - Kernel/xnu/bsd/netinet/ip_input.c
      - Kernel/xnu/osfmk/kern/smr.c
      - Kernel/xnu/osfmk/vm/vm_kern.c
  1.2 Implement dynamic Mach-O header section sizing for STARTUP entries in:
      - Kernel/xnu/osfmk/kern/startup.c
  1.3 Move UBSan stubs into Kernel/xnu/osfmk/kern/ubsan.c and update Makefiles.

================================================================================
STEP 2: KEXT COMPILATION & KERNELCACHE GENERATION
================================================================================
  2.1 Compile essential storage and filesystem drivers under Kernel/Extensions:
      - IOStorageFamily, RavynAHCIPort, hfs.kext
  2.2 Build plktool and generate prelinked kernelcache containing the kernel
      and all critical boot KEXTs.
  2.3 Deploy kernelcache to /tmp/ravyn-boot.img.

================================================================================
STEP 3: ROOT FILESYSTEM & USERLAND IMAGE PREPARATION
================================================================================
  3.1 Create complete directory hierarchy on the boot volume:
      /bin, /sbin, /usr/bin, /usr/lib, /dev, /etc, /System/Library/Extensions
  3.2 Deploy statically-linked or self-contained Mach-O 64-bit userland utilities:
      - /bin/sh, /bin/ls, /bin/cat, /bin/echo, /sbin/launchd
  3.3 Configure /etc/fstab and /etc/rc boot scripts.

================================================================================
STEP 4: BOOTLOADER & QEMU EXECUTION HARNESS
================================================================================
  4.1 Mount and update /tmp/ravyn-boot.img with Clover/OpenCore EFI bootloader,
      driver configurations, and boot-args (-v serial=1 keepsyms=1 -s).
  4.2 Launch QEMU with serial console piping to stdio.
  4.3 Monitor execution log through Mach init, I/O Kit matching, bsd_init(),
      vfs_mountroot(), and userland spawn.

================================================================================
STEP 5: INTERACTIVE CONSOLE VALIDATION
================================================================================
  5.1 Confirm /dev/console output and keyboard/serial input processing.
  5.2 Execute test commands in /bin/sh (ls, echo "Boot Success!").
================================================================================
```

---

## 6. Verification Milestones & Diagnostics Matrix

| Milestone | Expected Observable Output | Diagnostics / Action on Failure |
| :--- | :--- | :--- |
| **M1: Mach Startup Completion** | `kernel_startup_initialize_upto: completed successfully` | Inspect serial log for faulting entry function pointer; check Mach-O slide. |
| **M2: I/O Kit Storage Matching** | `RavynAHCIPort: attached`, `disk0s1: IOMedia registered` | Verify PCI device IDs match QEMU ICH9 AHCI (`8086:2922`); check `Info.plist`. |
| **M3: BSD Subsystem Bootstrap** | `bsd_init: bsd_bufferinit`, `sysctl registered` | Check for invalid pointer frees in `bsd_init.c`; verify `proc0` credentials. |
| **M4: VFS Root Mount** | `hfs: mounted root volume 'RAVYNOS'`, `devfs: mounted on /dev` | Check `vfs_fsadd` registration in `hfs_iokit.cpp`; verify `rootdev` device node. |
| **M5: Process 1 Load** | `load_init_program: loading /sbin/launchd (or /bin/sh)` | Verify Mach-O format of target binary; check page-table permissions. |
| **M6: User Shell Prompt** | `root# ` or interactive `sh-5.1#` on serial console | Verify `/dev/console` and `/dev/tty` character major/minor nodes in `devfs`. |

---

*This document represents the complete, end-to-end architectural plan for achieving a fully booted ravynOS system.*
