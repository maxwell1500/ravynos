/*
 * ravynOS EFI loader
 * ==================
 * A purpose-built PE/COFF EFI application that loads the ravynOS XNU kernel
 * off the ESP and enters it.  This replaces Apple's efiboot (boot.efi), the
 * last Apple binary in the boot chain.
 *
 * THE KERNEL-ENTRY CONTRACT (read out of Kernel/xnu, see the design doc for
 * the citations):
 *
 *   entry     LC_UNIXTHREAD.rip of kernel.development, i.e. _pstart
 *   CPU state 32-bit protected mode, paging OFF, flat 4 GiB segments
 *   %eax      physical address of a 4096-byte `boot_args`
 *   load at   segment_phys = seg.vmaddr & 0xFFFFFFFF  (0x100000 for our kernel)
 *
 * The kernel brings its own GDT, IDT and identity page tables, so the loader
 * builds no page tables at all.
 *
 * Build (no EDK2, no gnu-efi and no PE linker are needed on this host):
 *
 *   clang -target x86_64-unknown-windows -ffreestanding -fno-stack-protector \
 *         -mno-red-zone -mcmodel=medium -fno-builtin -Os -g0 \
 *         -c loader.c -o loader.obj
 *   python3 ../pack.py loader.obj BOOTX64.EFI efi_main
 *
 * MEASURED FIRMWARE ANOMALY (blocks volume discovery as of 2026-09-28)
 * -------------------------------------------------------------------
 * On the OVMF build in /usr/local/share/qemu/edk2-x86_64-code.fd, this
 * loader cannot obtain EFI_SIMPLE_FILE_SYSTEM_PROTOCOL by any route:
 *
 *   - HandleProtocol (index 16, 0x98) is CORRECT: it returns a coherent
 *     EFI_LOADED_IMAGE_PROTOCOL whose SystemTable == ST, ImageBase
 *     0x7ddf5000, ImageSize 0x2c000, ImageCodeType 1, ImageDataType 2.
 *   - HandleProtocol(DeviceHandle | FileHandle | ParentHandle,
 *     SimpleFS) returns EFI_UNSUPPORTED, EFI_INVALID_PARAMETER and
 *     EFI_UNSUPPORTED respectively.
 *   - A sweep of all 1976 handles returned by the index-19 entry returns
 *     EFI_UNSUPPORTED for every one of them.
 *   - The entry at 0xB0 ignores its Protocol argument: it returns the same
 *     1976 handles for a NULL GUID, for SimpleFS, and for LoadedImage
 *     (which is installed on exactly ONE handle, ours).  It is therefore not
 *     behaving as LocateHandle.
 *   - 0xA0 (Reserved) is NULL, so the table layout is standard up to there.
 *   - Both GUIDs are byte-verified present and correct in the packed image.
 *   - The UEFI shell mounts FS0 from the same ESP, so SimpleFS exists.
 *
 * That combination is self-contradictory, so the next step is to stop
 * depending on it: read the kernel straight off the IDE disk with PCI/ATA
 * port I/O and parse GPT+FAT32 in this loader.  That needs no boot service
 * beyond nothing at all, and so cannot be blocked by this quirk.
 *
 * -DRAVYN_TRAMPOLINE_TEST builds the phase-1 gate: the handoff lands in a
 * 32-bit routine of our own that echoes the boot_args pointer to the serial
 * port and halts, so the long->compat-mode transition is proven without the
 * kernel being involved at all.
 */

typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef int i32;

typedef u64 EFI_STATUS;
typedef u64 EFI_HANDLE;
typedef void *EFI_VOID;

#define ERR(a)              (0x8000000000000000ULL | (a))
#define EFI_BUFFER_TOO_SMALL ERR(5)
#define EFI_FILE_MODE_READ   0x0000000000000001ULL
#define EFI_MEMORY_RUNTIME   0x8000000000000000ULL

typedef struct { u32 Data1; u16 Data2; u16 Data3; u8 Data4[8]; } EFI_GUID;
#define GUID(a, b, c, d, e, f, g, h, i, j, k) \
	{ a, b, c, { d, e, f, g, h, i, j, k } }

#define GUID_LOADED_IMAGE  GUID(0x5B1B31A1, 0x9562, 0x11D2, \
	0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B)
#define GUID_SIMPLE_FS     GUID(0x964E5B22, 0x6459, 0x11D2, \
	0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B)

typedef struct { u64 Signature; u32 Revision; u32 HeaderSize; u32 CRC32;
	u32 Reserved; } EFI_TABLE_HEADER;

typedef struct { u64 Reserved; void *Write; } SIMPLE_TEXT_OUT;

typedef struct {
	EFI_TABLE_HEADER Hdr;
	u64 FirmwareVendor;
	u32 FirmwareRevision;
	u32 __pad;
	u64 ConsoleInHandle;   void *ConIn;
	u64 ConsoleOutHandle;  SIMPLE_TEXT_OUT *ConOut;
	u64 StandardErrorHandle; SIMPLE_TEXT_OUT *StdErr;
	void *RT;
	void *BS;
	u64 NumberOfTableEntries;
	void *ConfigurationTable;
} EFI_SYSTEM_TABLE;

typedef struct EFI_FILE_PROTOCOL EFI_FILE_PROTOCOL;
struct EFI_FILE_PROTOCOL {
	u64 Revision;
	u64 (*Open)(EFI_FILE_PROTOCOL *, EFI_FILE_PROTOCOL **, u16 *, u64, void *);
	u64 (*Close)(EFI_FILE_PROTOCOL *);
	u64 (*Delete)(EFI_FILE_PROTOCOL *);
	u64 (*Read)(EFI_FILE_PROTOCOL *, u64 *, void *);
	u64 (*Write)(EFI_FILE_PROTOCOL *, u64 *, void *);
	u64 (*GetPosition)(EFI_FILE_PROTOCOL *, u64 *);
	u64 (*SetPosition)(EFI_FILE_PROTOCOL *, u64);
	u64 (*GetInfo)(EFI_FILE_PROTOCOL *, void *, u64 *, u64 *);
	u64 (*SetInfo)(EFI_FILE_PROTOCOL *, void *, u64, u64);
	u64 (*Flush)(EFI_FILE_PROTOCOL *);
};

typedef struct { u64 Revision;
	u64 (*OpenVolume)(EFI_FILE_PROTOCOL *, EFI_FILE_PROTOCOL **);
} EFI_SIMPLE_FILE_SYSTEM_PROTOCOL;

/*
 * EFI_LOADED_IMAGE_PROTOCOL, UEFI 2.10 section 4. The two members that are
 * easy to get wrong are ParentHandle and SystemTable, which sit BETWEEN
 * Revision and DeviceHandle: get them wrong and every later field is read
 * 8 bytes early.  Measured on this firmware: FileHandle came out inside the
 * loader's own image and DeviceHandle produced EFI_INVALID_PARAMETER (a
 * malformed handle) rather than EFI_UNSUPPORTED, which is what gave it away.
 *
 *   0x00 Revision        0x08 ParentHandle   0x10 SystemTable
 *   0x18 DeviceHandle    0x20 FileHandle     0x28 Reserved
 *   0x30 LoadOptionsSize 0x38 LoadOptions    0x40 ImageBase
 *   0x48 ImageSize       0x4C ImageCodeType  0x50 ImageDataType
 *   0x58 Unload
 */
typedef struct {
	u32  Revision;
	u32  _pad;
	void *ParentHandle;
	EFI_SYSTEM_TABLE *SystemTable;
	void *DeviceHandle;
	void *FileHandle;
	void *Reserved;
	u32  LoadOptionsSize;
	void *LoadOptions;
	void *ImageBase;
	u64  ImageSize;
	u32  ImageCodeType;
	u32  ImageDataType;
	u64  Unload;
} EFI_LOADED_IMAGE_PROTOCOL;

typedef struct { u64 Signature; u32 Revision; u32 HeaderSize; u32 CRC32;
	u32 Reserved; } EFI_BOOT_SERVICES_HDR;

typedef EFI_STATUS (*EFI_GET_MEMORY_MAP)(u64 *, u64 *, u64 *, u64 *, u64 *);
typedef EFI_STATUS (*EFI_HANDLE_PROTOCOL)(EFI_HANDLE, EFI_GUID *, void **);
typedef EFI_STATUS (*EFI_LOCATE_HANDLE)(u32, EFI_GUID *, void *, u64 *, EFI_HANDLE *);
typedef EFI_STATUS (*EFI_LOCATE_HANDLE_BUFFER)(u32, EFI_GUID *, void *, u64 *, void **);

typedef EFI_STATUS (*EFI_EXIT_BOOT_SERVICES)(EFI_HANDLE, u64);

typedef struct {
	EFI_BOOT_SERVICES_HDR Hdr;
	void *RaiseTPL;
	void *RestoreTPL;
	void *AllocatePages;
	void *FreePages;
	EFI_GET_MEMORY_MAP GetMemoryMap;
	void *AllocatePool; void *FreePool;
	void *CreateEvent; void *SetTimer; void *WaitForEvent;
	void *SignalEvent; void *CloseEvent; void *CheckEvent;
	void *InstallProtocolInterface;
	void *ReinstallProtocolInterface;
	void *UninstallProtocolInterface;
	EFI_HANDLE_PROTOCOL HandleProtocol;
	u64 Reserved;
	void *RegisterProtocolNotify;
	EFI_LOCATE_HANDLE LocateHandle;
	void *LocateDevicePath;
	void *InstallConfigurationTable;
	void *LoadImage;
	void *StartImage;
	void *Exit;
	void *UnloadImage;
	EFI_EXIT_BOOT_SERVICES ExitBootServices;
} EFI_BOOT_SERVICES;

/* ------------------------------------------------------------------ */
/* boot_args: byte-for-byte from pexpert/pexpert/i386/boot.h:150-223   */
/* ------------------------------------------------------------------ */
#define BOOT_LINE_LENGTH 1024

typedef struct {
	u32 v_baseAddr, v_display, v_rowBytes, v_width, v_height, v_depth;
} Boot_VideoV1;

typedef struct {
	u32 v_display, v_rowBytes, v_width, v_height, v_depth;
	u8  v_rotate;
	u8  v_resv_byte[3];
	u32 v_resv[6];
	u64 v_baseAddr;
} Boot_Video;

typedef struct {
	u16 Revision;
	u16 Version;
	u8  efiMode;
	u8  debugMode;
	u16 flags;
	char CommandLine[BOOT_LINE_LENGTH];
	u32 MemoryMap;
	u32 MemoryMapSize;
	u32 MemoryMapDescriptorSize;
	u32 MemoryMapDescriptorVersion;
	Boot_VideoV1 VideoV1;
	u32 deviceTreeP;
	u32 deviceTreeLength;
	u32 kaddr;
	u32 ksize;
	u32 efiRuntimeServicesPageStart;
	u32 efiRuntimeServicesPageCount;
	u64 efiRuntimeServicesVirtualPageStart;
	u32 efiSystemTable;
	u32 kslide;
	u32 performanceDataStart;
	u32 performanceDataSize;
	u32 keyStoreDataStart;
	u32 keyStoreDataSize;
	u64 bootMemStart;
	u64 bootMemSize;
	u64 PhysicalMemorySize;
	u64 FSBFrequency;
	u64 pciConfigSpaceBaseAddress;
	u32 pciConfigSpaceStartBusNumber;
	u32 pciConfigSpaceEndBusNumber;
	u32 csrActiveConfig;
	u32 csrCapabilities;
	u32 boot_SMC_plimit;
	u16 bootProgressMeterStart;
	u16 bootProgressMeterEnd;
	Boot_Video Video;
	u32 apfsDataStart;
	u32 apfsDataSize;
	u64 KC_hdrs_vaddr;
	u64 arvRootHashStart;
	u64 arvRootHashSize;
	u64 arvManifestStart;
	u64 arvManifestSize;
	u64 bsARVRootHashStart;
	u64 bsARVRootHashSize;
	u64 bsARVManifestStart;
	u64 bsARVManifestSize;
	u64 topOfKernelData;
	u32 __reserved4[690];
} boot_args;

typedef char assert_boot_args_is_4096[(sizeof(boot_args) == 4096) ? 1 : -1];

typedef struct {
	u32 Type;
	u32 Pad;
	u64 PhysicalStart;
	u64 VirtualStart;
	u64 NumberOfPages;
	u64 Attribute;
} EFI_MEMORY_DESCRIPTOR;

#define EfiLoaderData 2
#define EfiConventionalMemory 7

/* ------------------------------------------------------------------ */
/* build-time configuration                                            */
/* ------------------------------------------------------------------ */
#ifdef RAVYN_TRAMPOLINE_TEST
#define TRAMPOLINE_TEST 1
#else
#define TRAMPOLINE_TEST 0
#endif

#if TRAMPOLINE_TEST
__attribute__((used)) static const char RL_BUILD_TAG[] =
	"RAVYN-EFI-LOADER BUILD=TRAMPOLINE-TEST";
#else
__attribute__((used)) static const char RL_BUILD_TAG[] =
	"RAVYN-EFI-LOADER BUILD=FULL";
#endif

#ifndef RAVYN_KERNEL_PATH
#define RAVYN_KERNEL_PATH L"\\System\\Library\\Kernels\\kernel.development"
#endif

/*
 * The block we own: handoff block + boot_args page.
 *
 * We deliberately do NOT call AllocatePages.  Measured on this firmware:
 * every request is refused (EFI_INVALID_PARAMETER for memory types 1..7 at
 * six fixed addresses, and for PageAddress = MAX_UINTN), and the UEFI spec
 * forbids allocating below 1 MiB anyway.  Instead we pick a run of
 * EfiConventionalMemory pages that is already free, outside the kernel
 * image and below 4 GiB (the handoff is a 32-bit far jump), and then extend
 * boot_args.ksize so physfree covers it.  The kernel marks every page below
 * physfree as already allocated (i386_init.c:746, i386_vm_init.c:628-657),
 * so our pages are unreachable by the allocator with no map editing at all.
 *
 * The padding between the kernel's __HIB and __TEXT (0x1B1000..0x200000) is
 * a natural candidate and is what the search finds on OVMF.
 */
#define BLK_PAGES        32
#define BLK_OFF_BOOTARGS 0x1000
#define BLK_OFF_DEVTREE  0x200   /* minimal Apple DeviceTreeNode blob */
#define BLK_OFF_MEMMAP   0x2000  /* the EFI map the KERNEL reads */
#define BLK_DEVTREE_SIZE 0x1A0   /* root + /chosen + 3 properties */

static u64 rdtsc(void)
{
	u32 lo, hi;
	__asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
	return ((u64)hi << 32) | lo;
}

/*
 * Device tree encoding (pexpert/device_tree.h):
 *   DeviceTreeNode         { u32 nProperties; u32 nChildren; }
 *   DeviceTreeNodeProperty { char name[32]; u32 length; u8 value[]; }
 * A node's NAME is itself a property called "name"; a property value is
 * padded to 4 bytes.  Note skipProperties() returns NULL for a node with NO
 * properties, so any node that has children must carry at least one property
 * of its own -- the root below has "name" for exactly that reason.
 */
static u8 *dt_node(u8 *p, u32 nprops, u32 nchildren)
{
	*(u32 *)p = nprops; p += 4;
	*(u32 *)p = nchildren; p += 4;
	return p;
}

static u8 *dt_prop(u8 *p, const char *name, const void *val, u32 len)
{
	for (int i = 0; i < 32; i++) p[i] = 0;
	for (int i = 0; name[i] && i < 31; i++) p[i] = (u8)name[i];
	*(u32 *)(p + 32) = len;
	for (u32 i = 0; i < len; i++) p[36 + i] = ((const u8 *)val)[i];
	return p + 36 + ((len + 3) & ~3u);
}

static u8 *dt_str(u8 *p, const char *name, const char *val)
{
	u32 n = 0;
	while (val[n]) n++;
	return dt_prop(p, name, val, n + 1);    /* length includes the NUL */
}

static const char DEFAULT_CMDLINE[] =
	"-v serial=1 debug=0x14e keepsyms=1 slide=0 kcsuffix=development "
	"rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 -no_compat_check "
	"cpus=1 quiet_boot=1";

/* g_memmap is the loader's own scratch copy, used only here (find_block()
 * walks it).  The copy the KERNEL reads is written into the low handoff
 * block -- see the BLK_OFF_MEMMAP copy below, and why it must be low. */
#define MEMMAP_MAX_BYTES 32768
static u8 g_memmap[MEMMAP_MAX_BYTES];

/* globals consumed by the naked handoff stub */
static u32 g_hoff_page;       /* physical address of the handoff block */
static u32 g_bootargs_phys;   /* %eax at kernel entry                  */
static u32 g_entry_phys;      /* _pstart physical address              */

/* ------------------------------------------------------------------ */
/* serial output.  The firmware's ConOut goes to the framebuffer, not the */
/* UART, so anything that must appear in the QEMU serial log is written   */
/* straight to 0x3f8 -- which is also how the kernel talks.              */
/* ------------------------------------------------------------------ */
#define COM1 0x3f8
#define LSR  0x3f5

/* The COFF assembler in this clang rejects `in`/`out` with an immediate
 * port operand, so both directions go through DX. */
static inline u16 com_in(u16 port)
{
	u16 v;
	__asm__ volatile("inw %1, %0" : "=a"(v) : "d"(port) : "memory");
	return v;
}

static inline void com_out(u8 v, u16 port)
{
	__asm__ volatile("outb %0, %1" :: "a"(v), "d"(port) : "memory");
}

static void s_putc(char c)
{
	for (int i = 0; i < 200000; i++) {
		if (com_in(LSR) & 0x20)
			break;
	}
	com_out((u8)c, COM1);
}

static void s_puts(const char *s) { while (*s) s_putc(*s++); }

static void s_hex32(u32 v)
{
	static const char h[] = "0123456789abcdef";
	for (int i = 28; i >= 0; i -= 4)
		s_putc(h[(v >> i) & 0xf]);
}

static void s_hex64(u64 v)
{
	static const char h[] = "0123456789abcdef";
	for (int i = 60; i >= 0; i -= 4)
		s_putc(h[(v >> i) & 0xf]);
}

static void s_dec(u64 v)
{
	char b[24];
	int i = 0;
	if (!v) { s_putc('0'); return; }
	while (v) { b[i++] = (char)('0' + (v % 10)); v /= 10; }
	while (i--) s_putc(b[i]);
}

/* ------------------------------------------------------------------ */
/* the handoff: 64-bit -> 32-bit protected mode -> far jump            */
/*                                                                     */
/* Everything is register- and RIP-relative, so the packed image needs   */
/* no base relocations and the DXE core may place it anywhere --         */
/* including above 4 GiB, which is where EDK2 put ours (0x7fe5a000).     */
/* The 32-bit stub and the GDT therefore live in a low page whose          */
/* physical address we chose ourselves.                                    */
/* ------------------------------------------------------------------ */
/*
 * The handoff: 64-bit -> 32-bit protected mode, following Apple boot.efi's
 * sequence byte for byte (tools/efiloader/ref/apple-boot32-modeswitch.S,
 * extracted from the loader that actually boots this kernel):
 *
 *   lgdt [page]              ; GDT: null | 0x08 code | 0x10 data
 *   mov ax,0x10 ; ds/es/fs/gs
 *   mov cr0.PG = 0           ; leaves paging, so LMA = 0
 *   EFER.LME = 0             ; leaves long mode
 *   jmp rdi                  ; NEAR jump; eax = boot_args, edi = entry
 *
 * There is deliberately NO far return and NO CS reload.  A far jump cannot
 * load a non-long CS (it raises #GP in 64-bit mode), and Apple never reloads
 * CS here: clearing LMA is what makes the cached CS execute as 32-bit.  The
 * far-return-through-a-32-bit-stub design this file used to have never once
 * produced the gate probe's output, i.e. it never worked at all.
 *
 * The kernel entry IS 32-bit code: __HIB at physical 0x1a8000 begins with
 * `pushal; jmp` into a COM1 routine that prints "EAX=<boot_args>".  That
 * string is the first proof the handoff landed, and it is why the gate's
 * probe mirrors it.
 */
#define HANDOFF_PAGE 0x00020000ULL

/*
 * page and val arrive in the Windows x64 argument registers RCX and RDX.
 *
 * They are passed in rather than read from C globals because a static
 * referenced ONLY from a naked function's inline asm gets no definition
 * emitted by clang: the object carries an undefined external, and a linker
 * that resolves that quietly invents an address.  That is not hypothetical
 * -- it is exactly what produced a garbage `lgdt` and a far jump with a
 * selector of 0x38 in an earlier run.  pack.py now REFUSES such a
 * relocation; this change removes the cause.
 */
/* Dumped from inside the handoff stub, with the address the CPU will actually
 * dereference, immediately before the transfer. */
__attribute__((noinline)) void rl_dump_far(void *p)
{
	const u8 *b = (const u8 *)p;
	s_puts("RL: RBX="); s_hex64((u64)p);
	s_puts(" [rbx+0x30]:");
	for (int i = 0; i < 16; i++)
		s_hex32((u32)b[0x30 + i]);
	s_puts("\r\n");
}

/* Prints the GDTR the CPU itself reports, so a failed lgdt cannot hide. */
__attribute__((noinline)) void rl_dump_gdtr(u64 base, u64 limit)
{
	s_puts("RL: GDTR-from-CPU limit=0x");
	s_hex32((u32)limit);
	s_puts(" base=0x");
	s_hex64(base);
	s_puts("\r\n");
}

__attribute__((naked)) static void handoff(u32 page, u32 val)
{
	__asm__ volatile(
		"cli                                     \n\t"
		"movl   %ecx, %ebx                       \n\t"   /* ebx  = page      */
		"movl   %edx, 0x38(%rbx)                 \n\t"   /* page[0x38] = boot_args */
		"movq   %rbx, %rcx                       \n\t"
		"callq  rl_dump_far                      \n\t"
		"lgdt   (%rbx)                           \n\t"   /* GDT at page+0x00 */
		"movw   $0x0010, %ax                     \n\t"   /* flat data (0x10) */
		"movw   %ax, %ds                         \n\t"
		"movw   %ax, %es                         \n\t"
		"movw   %ax, %fs                         \n\t"
		"movw   %ax, %gs                         \n\t"
		"movq   %cr0, %rax                       \n\t"
		"btr    $31, %eax                        \n\t"   /* CR0.PG=0 -> LMA=0 */
		"movq   %rax, %cr0                       \n\t"
		"movl   $0xC0000080, %ecx                \n\t"   /* IA32_EFER        */
		"rdmsr                                   \n\t"
		"btr    $8, %eax                         \n\t"   /* EFER.LME=0       */
		"wrmsr                                   \n\t"
		"movl   0x30(%rbx), %edi                 \n\t"   /* edi = entry      */
		"movl   0x38(%rbx), %eax                 \n\t"   /* eax = boot_args  */
		"jmp    *%rdi                            \n\t"   /* NEAR: CS untouched */
		"hlt                                     \n\t");
}

/* 32-bit probe: EBX = page, EAX = the value to echo.  cli;
 * mov %ebx,%esi; add $0xA0,%esi; mov %eax,%edi; mov $8,%cl;
 * 1: mov (%esi),%dl; mov %dl,%al; out $0x3f8,%al; inc %esi; dec %ecx; jnz 1b; hlt */
/*
 * The 32-bit entry.  Its FIRST action is a single immediate port write, before
 * any segment or stack setup, so that seeing that one byte in the log proves
 * the CPU arrived in 32-bit mode with nothing else having to work.
 *
 * `out $0x3f8, $0x2a` is E6 2A: port 0x3F8 truncated to 8 bits is 0xF8, so
 * the encoding is E6 <F8> <03> and the immediate payload is 0x2A.  We emit the
 * two bytes explicitly so the port is 0x3F8 and the character is '*'.
 *
 * After that, the routine writes a known byte to our own low page.  That is the
 * flag the 64-bit loader reads back and prints, which proves the 32-bit code
 * executed independently of whether the serial path works at all.
 */
static const u8 CODE32_PROBE[] = {
	0xFA,                                  /* cli                        */
	0xB0, 0x2A,                            /* mov $'*', %al              */
	0xE6, 0xF8, 0x03,                      /* out $0x3f8, %al            */
	/* Proof-of-execution flag: flip the marker byte in our own page. */
	0xB0, 0x77,                            /* mov $0x77, %al              */
	0x88, 0x83, (u8)0x00, (u8)0x02,        /* mov %al, 0x20083(%ebx) */
	0xB0, 0x77,                            /* mov $'w', %al              */
	0xE6, 0xF8, 0x03,                      /* out $0x3f8, %al            */
	0xFA,                                  /* cli                        */
	0xF4,                                  /* hlt                        */
};

#define PROBE_OFF    0x80
#define PROBE_STR_OFF 0xA0

/*
 * Handoff block layout (all offsets from g_hoff_page):
 *   0x00  GDT pointer   (limit u16, then 8-byte base = g_hoff_page + 0x10)
 *   0x10  GDT[3]        null | 0x08 32-bit code | 0x10 32-bit data
 *   0x30  near-jump target (u32): the kernel entry, or the gate's probe
 *   0x80  32-bit probe (gate build only)
 *   0xA0  "EAXX=xxxxxxxx" (gate build only)
 */
static void build_handoff_block(u8 *p)
{
	/* +0x00 GDT pointer: limit u16 then 8-byte base.  The base is
	 * g_hoff_page + 0x10, so the table written at p[0x10] puts data at
	 * selector 0x10 and code at 0x08 -- the numbering Apple uses. */
	u32 gbase = g_hoff_page + 0x10;
	p[0x00] = 23; p[0x01] = 0;
	for (int i = 0; i < 8; i++) p[0x02 + i] = 0;
	p[0x02] = (u8)(gbase & 0xff);
	p[0x03] = (u8)((gbase >> 8) & 0xff);
	p[0x04] = (u8)((gbase >> 16) & 0xff);
	p[0x05] = (u8)((gbase >> 24) & 0xff);

	/*
	 * Flags byte = G<<7 | AVL<<6 | L<<5 | D/B<<4 | limit_hi.
	 * For a flat 32-bit segment that is 0x80|0x00|0x00|0x10|0x0F = 0x9F.
	 *
	 * It was 0xCF, which is 0x80|0x40|0x00|0x00|0x0F: AVL=1 and D/B=0.
	 * D/B=0 makes the segment 16-bit, so CS:IP was limited to 64 KiB and
	 * the target 0x20060 was out of range -> #GP on the transfer, every
	 * time, with the GDT pointer and far pointer both reading back
	 * perfectly correct.  A wrong flag bit, not a wrong address.
	 */
	static const u8 gdt[24] = {
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, /* null           */
		0xFF, 0xFF, 0x00, 0x00, 0x00, 0x9B, 0x9F, 0x00, /* 0x08 32b code  */
		0xFF, 0xFF, 0x00, 0x00, 0x00, 0x93, 0x9F, 0x00, /* 0x10 32b data  */
	};
	for (int i = 0; i < 24; i++) p[0x10 + i] = gdt[i];

	{
		/*
		 * +0x30 the near-jump target, read back by handoff() as a 32-bit
		 * immediate: the kernel entry, or the gate's 32-bit probe.
		 */
		u32 t0 = TRAMPOLINE_TEST ? (u32)(g_hoff_page + PROBE_OFF)
					 : g_entry_phys;
		for (int k = 0; k < 4; k++)
			p[0x30 + k] = (u8)((t0 >> (8 * k)) & 0xff);
	}

	/*
	 * +0x200 the device tree the kernel needs.
	 *
	 * The kernel does `PE_state.deviceTreeHead = ml_static_ptovirt(
	 * args->deviceTreeP)` and ml_static_ptovirt(0) is the PHYSMAP BASE, not
	 * NULL -- so a zero deviceTreeP makes it SecureDTInit() a bogus tree at
	 * 0xffffff8000000000 and the first SecureDTLookupEntry walks garbage
	 * (#PF, #DF, triple fault; exactly what the boot log showed).  Apple's
	 * loader handed over a real tree, so this never fired.
	 *
	 * Layout (pexpert/device_tree.h): DeviceTreeNode { u32 nProperties;
	 * u32 nChildren; } then this node's properties, then its children.  A
	 * node's NAME is itself a property called "name"; a property is
	 * DeviceTreeNodeProperty { char name[32]; u32 length; u8 value[]; }
	 * with the value padded to 4 bytes.
	 *
	 * /chosen/random-seed is not optional: bootseed_init() panics with
	 * "no random seed @pe_gen.c:188" without it.  The seed is derived from
	 * the TSC and our own addresses -- it varies per boot, but it is a
	 * bring-up seed, not a CSPRNG, and should become EFI_RNG_PROTOCOL.
	 * The kernel demands SEED_SIZE (192) bytes and panics on short supply,
	 * so hand over 256.
	 */
	{
		u8 *d = p + BLK_OFF_DEVTREE;
		u8 *q;
		u64 seed[32];

		for (int i = 0; i < BLK_DEVTREE_SIZE; i++) d[i] = 0;

		q = dt_node(d, 1, 1);                /* root: 1 property, 1 child */
		q = dt_str(q, "name", "device-tree");
		q = dt_node(q, 2, 0);                /* /chosen: 2 properties     */
		q = dt_str(q, "name", "chosen");
		{
			u64 x = rdtsc() ^ ((u64)g_bootargs_phys << 17)
			    ^ ((u64)g_entry_phys << 3);
			for (int i = 0; i < 32; i++) {
				x ^= x << 13; x ^= x >> 7; x ^= x << 17;
				seed[i] = x;
			}
		}
		q = dt_prop(q, "random-seed", seed, sizeof(seed));
	}

	if (TRAMPOLINE_TEST) {
		for (unsigned i = 0; i < sizeof(CODE32_PROBE); i++)
			p[PROBE_OFF + i] = CODE32_PROBE[i];
		const char *tag = "EAXX=";
		for (int i = 0; i < 5; i++) p[PROBE_STR_OFF + i] = (u8)tag[i];
		for (int i = 0; i < 8; i++)
			p[PROBE_STR_OFF + 5 + i] =
			    (u8)"0123456789abcdef"[(g_bootargs_phys >> (28 - 4 * i)) & 0xf];
		p[PROBE_STR_OFF + 13] = '\r';
		p[PROBE_STR_OFF + 14] = '\n';
	}
}

/* ------------------------------------------------------------------ */
/* Mach-O                                                              */
/* ------------------------------------------------------------------ */
struct mach_header_64 {
	u32 magic; i32 cputype, cpusubtype;
	u32 filetype, ncmds, sizeofcmds, flags, reserved;
};
#define MH_MAGIC_64  0xfeedfacfu
#define MH_EXECUTE   2
#define LC_SEGMENT_64 0x19
#define LC_UNIXTHREAD  0x5

struct segment_command_64 {
	u32 cmd, cmdsize;
	char segname[16];
	u64 vmaddr, vmsize, fileoff, filesize;
	u32 maxprot, initprot, nsects, flags;
};
struct load_cmd { u32 cmd, cmdsize; };

#define MAXSEGS 32
static struct segment_command_64 g_segs[MAXSEGS];
static int g_nsegs;
static u64 g_entry_vaddr;

static int macho_parse(const u8 *hdr, u64 len)
{
	const struct mach_header_64 *mh = (const struct mach_header_64 *)hdr;
	if (len < sizeof(*mh) || mh->magic != MH_MAGIC_64) {
		s_puts("RL: bad mach magic\r\n");
		return -1;
	}
	if (mh->filetype != MH_EXECUTE) {
		s_puts("RL: kernel is not MH_EXECUTE\r\n");
		return -1;
	}
	u64 off = sizeof(*mh);
	for (u32 i = 0; i < mh->ncmds; i++) {
		if (off + sizeof(struct load_cmd) > len)
			return -1;
		const struct load_cmd *lc = (const struct load_cmd *)(hdr + off);
		if (lc->cmd == LC_SEGMENT_64) {
			if (g_nsegs >= MAXSEGS || off + sizeof(struct segment_command_64) > len)
				return -1;
			g_segs[g_nsegs++] = *(const struct segment_command_64 *)(hdr + off);
		} else if (lc->cmd == LC_UNIXTHREAD) {
			/* x86_thread_state64: r[16] then ... ; rip is the 17th qword */
			if (off + 16 + 17 * 8 > len)
				return -1;
			g_entry_vaddr = *(const u64 *)(hdr + off + 16 + 16 * 8);
		}
		off += lc->cmdsize;
	}
	return g_nsegs ? 0 : -1;
}

/* ------------------------------------------------------------------ */

static void *memset(void *d, int c, u64 n)
{
	u8 *p = d;
	while (n--) *p++ = (u8)c;
	return d;
}

/*
 * Find BLK_PAGES consecutive EfiConventionalMemory pages inside
 * [lo, hi) that do not overlap the kernel image [klo, khi).
 *
 * The map is strided by the firmware-reported descriptor size, which is
 * NOT required to equal sizeof(EFI_MEMORY_DESCRIPTOR) -- OVMF reports 48
 * against our 40 -- so the stride must be passed in, never assumed.
 */
static u64 find_block(const u8 *map, u64 n, u64 dsz,
    u64 lo, u64 hi, u64 klo, u64 khi)
{
	for (u64 i = 0; i < n; i++) {
		const EFI_MEMORY_DESCRIPTOR *d =
		    (const EFI_MEMORY_DESCRIPTOR *)(map + i * dsz);
		if (d->Type != EfiConventionalMemory)
			continue;
		u64 s = d->PhysicalStart;
		u64 e = s + (d->NumberOfPages << 12);
		if (s < lo) s = lo;
		if (e > hi) e = hi;
		for (u64 a = (s + 0xFFF) & ~0xFFFULL; a + (BLK_PAGES << 12) <= e;
		     a += 0x1000) {
			u64 bend = a + (BLK_PAGES << 12);
			if (a < khi && bend > klo)
				continue;               /* would collide with the kernel */
			return a;
		}
	}
	return 0;
}

/* ------------------------------------------------------------------ */
EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *ST);

EFI_STATUS
efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *ST)
{
	EFI_BOOT_SERVICES *BS = (EFI_BOOT_SERVICES *)ST->BS;
	EFI_LOADED_IMAGE_PROTOCOL *li = 0;
	EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs = 0;
	EFI_FILE_PROTOCOL *root = 0, *kf = 0;
	EFI_GUID g_li = GUID_LOADED_IMAGE;
	EFI_GUID g_fs = GUID_SIMPLE_FS;
	EFI_MEMORY_DESCRIPTOR *map;
	u64 key = 0, dsz = 0, dver = 0, size, n, used = 0, ram_top = 0;
	boot_args *A;
	u64 base, top;
	u64 rt_end = 0;            /* one past the highest runtime VA assigned */
	u32 i;
	u64 st2;

	s_puts("\r\nRL: ravynOS EFI loader\r\n");
	s_puts("RL: "); s_puts(RL_BUILD_TAG); s_puts("\r\n");

	/* --- 1. our own image (also validates EFI_SYSTEM_TABLE) ---------- */
	st2 = BS->HandleProtocol(ImageHandle, &g_li, (void **)&li);
	if (st2) { s_puts("RL: no LoadedImage\r\n"); return (u64)st2; }
	/* Dump the whole struct first: the layout above is the single most
	 * load-bearing assumption in the loader, so confirm it by observation
	 * before depending on it. */
	s_puts("RL: li rev="); s_hex32(li->Revision);
	s_puts(" parent=0x"); s_hex64((u64)li->ParentHandle);
	s_puts(" systab="); s_hex64((u64)li->SystemTable);
	s_puts(" dev=0x"); s_hex64((u64)li->DeviceHandle);
	s_puts(" file=0x"); s_hex64((u64)li->FileHandle);
	s_puts("\r\n");
	s_puts("RL: base=0x"); s_hex64((u64)li->ImageBase);
	s_puts(" size=0x"); s_hex64(li->ImageSize);
	s_puts(" codeT="); s_hex32(li->ImageCodeType);
	s_puts(" dataT="); s_hex32(li->ImageDataType);
	s_puts(" BS=0x"); s_hex64((u64)BS);
	s_puts(" ST="); s_hex64((u64)ST);
	s_puts("\r\n");
	if (li->SystemTable != ST) {
		s_puts("RL: FATAL loaded-image SystemTable != ST\r\n");
		return ERR(22);
	}

	/*
	 * --- 2. the boot volume, and the kernel -------------------------
	 *
	 * SKIPPED IN TRAMPOLINE TEST BUILD.  A gate that depends on volume
	 * discovery is not a gate: the mode switch is the risky step and it
	 * must be provable independently of everything else.
	 */
	if (TRAMPOLINE_TEST) {
		s_puts("RL: "); s_puts(RL_BUILD_TAG);
		s_puts(" -- skipping volume/kernel, going straight to handoff\r\n");
		g_hoff_page = (u32)HANDOFF_PAGE;
		{
			u8 *ba = (u8 *)(u64)(g_hoff_page + BLK_OFF_BOOTARGS);
			memset(ba, 0, 4096);
			A = (boot_args *)ba;
			g_bootargs_phys = g_hoff_page + BLK_OFF_BOOTARGS;
			A->Revision = 0;
			A->Version = 2;
			A->efiMode = 64;
			A->kaddr = 0x100000;
			A->ksize = 0x400000;
			A->efiSystemTable = (u32)(u64)ST;
			A->PhysicalMemorySize = 0x40000000ULL;
			A->deviceTreeP = g_hoff_page + BLK_OFF_DEVTREE;
			A->deviceTreeLength = BLK_DEVTREE_SIZE;
			A->MemoryMap = (u32)(u64)g_memmap;
			{ u32 cn = 0; const char *q = DEFAULT_CMDLINE;
			  while (*q && cn < BOOT_LINE_LENGTH - 1) A->CommandLine[cn++] = *q++;
			  A->CommandLine[cn] = 0; }
		}
		/* A real memory-map key: ExitBootServices rejects a stale or zero
		 * one with EFI_INVALID_PARAMETER and leaves boot services LIVE
		 * through the handoff, which is not the state we want to test. */
		{
			u64 need = 0, k = 0, dsz = 0, dver = 0;
			st2 = BS->GetMemoryMap(&need, (void *)0, &k, &dsz, &dver);
			if (need == 0 || need > MEMMAP_MAX_BYTES) {
				s_puts("RL: gate GetMemoryMap need="); s_dec(need);
				s_puts("\r\n");
				return ERR(22);
			}
			st2 = BS->GetMemoryMap(&need, (void *)g_memmap, &k,
			    &dsz, &dver);
			A->MemoryMapDescriptorSize = (u32)dsz;
			s_puts("RL: mapkey=0x"); s_hex64(k);
			s_puts(" n="); s_dec(dsz ? need / dsz : 0);
			s_puts(" EBS-pre="); s_hex32((u32)st2); s_puts("\r\n");
			build_handoff_block((u8 *)(u64)g_hoff_page);
			st2 = BS->ExitBootServices(ImageHandle, k);
			s_puts("RL: EBS="); s_hex32((u32)st2); s_puts("\r\n");
		}
		/* Read the GDT pointer back OUT OF MEMORY, not out of the copy we
		 * just wrote, so the bytes the CPU will actually use are on the
		 * record before the jump. */
		{
			const u8 *gp = (const u8 *)(u64)g_hoff_page;
			s_puts("RL: GDTptr[0..11]:");
			for (int i = 0; i < 12; i++)
				s_hex32((u32)gp[i]);
			s_puts("\r\n");
			/* Every byte the GDT limit (0x17 = 23) actually covers,
			 * as three named raw descriptors.  A decoded summary
			 * hides the access byte, which is the byte that decides
			 * whether a CS may be loaded at all. */
			s_puts("RL: GDT[0..7]  null:");
			for (int i = 0; i < 8; i++)
				s_hex32((u32)gp[0x10 + i]);
			s_puts("\r\n");
			s_puts("RL: GDT[8..15] code:");
			for (int i = 0; i < 8; i++)
				s_hex32((u32)gp[0x18 + i]);
			s_puts("\r\n");
			s_puts("RL: GDT[16..23] data:");
			for (int i = 0; i < 8; i++)
				s_hex32((u32)gp[0x20 + i]);
			s_puts("\r\n");
			/* 16 bytes so both the m16:32 and m16:64 readings are on
			 * the wire, not just the six the instruction consumes. */
			s_puts("RL: far[0x30..0x3f]:");
			for (int i = 0; i < 16; i++)
				s_hex32((u32)gp[0x30 + i]);
			s_puts("\r\n");
		}
		s_puts("RL: HANDOFF eax=0x"); s_hex32(g_bootargs_phys);
		s_puts(" page=0x"); s_hex32(g_hoff_page);
		s_puts(" (trampoline)\r\n");
		handoff(g_hoff_page, g_bootargs_phys);
		return 0;
	}

	/*
	 * li->DeviceHandle is the handle of the volume this image was loaded
	 * from, and on EDK2 that is the handle carrying
	 * EFI_SIMPLE_FILE_SYSTEM_PROTOCOL.
	 */
	st2 = BS->HandleProtocol((EFI_HANDLE)(u64)li->DeviceHandle,
	    &g_fs, (void **)&fs);
	s_puts("RL: DeviceHandle=0x"); s_hex64((u64)li->DeviceHandle);
	s_puts(" HP(SimpleFS)="); s_hex32((u32)st2);
	s_puts(" fs=0x"); s_hex64((u64)fs); s_puts("\r\n");
	if (st2 || !fs) { s_puts("RL: no SimpleFS\r\n"); return ERR(14); }
	st2 = fs->OpenVolume((EFI_FILE_PROTOCOL *)fs, &root);
	if (st2) { s_puts("RL: OpenVolume failed\r\n"); return (u64)st2; }
	/* Only the kernel proper.  manifest.json also stages the same binary as
	 * BootKernelExtensions.kc, and feeding that in would trip
	 * assert(filetype == MH_FILESET) at i386_init.c:666. */
	st2 = root->Open(root, &kf, (u16 *)RAVYN_KERNEL_PATH,
	    EFI_FILE_MODE_READ, 0);
	if (st2) {
		s_puts("RL: cannot open kernel, status="); s_hex32((u32)st2);
		s_puts("\r\n");
		return (u64)st2;
	}
	s_puts("RL: opened kernel\r\n");

	/* --- 3. Mach-O layout ------------------------------------------- */
	{
		static u8 hdr[0x20000];
		u64 got = sizeof(hdr);
		st2 = kf->Read(kf, &got, hdr);
		if (st2) { s_puts("RL: header read failed\r\n"); return (u64)st2; }
		if (macho_parse(hdr, sizeof(hdr))) {
			s_puts("RL: macho parse failed\r\n");
			return ERR(22);
		}
	}
	base = ~0ULL; top = 0;
	for (i = 0; i < (u32)g_nsegs; i++) {
		u64 p = g_segs[i].vmaddr & 0xFFFFFFFFULL;
		u64 e = p + g_segs[i].vmsize;
		if (p < base) base = p;
		if (e > top) top = e;
	}
	g_entry_phys = (u32)(g_entry_vaddr & 0xFFFFFFFFULL);
	s_puts("RL: segs="); s_dec((u64)g_nsegs);
	s_puts(" base=0x"); s_hex32((u32)base);
	s_puts(" top=0x"); s_hex32((u32)top);
	s_puts(" entry=0x"); s_hex32(g_entry_phys); s_puts("\r\n");

	if (base != 0x100000ULL) {
		/* start.s:277-285 rebases the kernel's own boot page tables by the
		 * LINK address, so any other load address mis-maps memory. */
		s_puts("RL: FATAL kernel base is not 0x100000\r\n");
		return ERR(22);
	}

	/* --- 4. load every segment, __LINKEDIT included ------------------ */
	/*
	 * keepsyms=1 is in the live boot line and model_dep.c:1129 finds the
	 * symbol table by virtual-address arithmetic from this header, so the
	 * whole image, __LINKEDIT included, must be resident.
	 *
	 * No AllocatePages: the range is reported as EfiConventionalMemory and
	 * is below physfree, so the kernel's allocator can never reach it.  We
	 * write it immediately before ExitBootServices, and the kernel takes it
	 * over the instant it is entered -- which is exactly what Apple's
	 * efiboot does.
	 */
	memset((void *)(u64)base, 0, top - base);
	for (i = 0; i < (u32)g_nsegs; i++) {
		const struct segment_command_64 *sg = &g_segs[i];
		u64 dst = sg->vmaddr & 0xFFFFFFFFULL;
		u64 left = sg->filesize;
		if (!left) continue;
		st2 = kf->SetPosition(kf, sg->fileoff);
		if (st2) { s_puts("RL: SetPosition failed\r\n"); return (u64)st2; }
		while (left) {
			u64 want = left > (1u << 20) ? (1u << 20) : left;
			u64 got = want;
			st2 = kf->Read(kf, &got, (void *)(u64)dst);
			if (st2) {
				s_puts("RL: read failed "); s_hex32((u32)st2);
				s_puts(" on "); s_puts(sg->segname); s_puts("\r\n");
				return (u64)st2;
			}
			if (!got) { s_puts("RL: short read\r\n"); return ERR(5); }
			dst += got; left -= got;
		}
		s_puts("RL:   "); s_puts(sg->segname);
		s_puts(" -> 0x"); s_hex32((u32)(sg->vmaddr & 0xFFFFFFFFULL));
		s_puts(" +0x"); s_hex32((u32)sg->filesize); s_puts("\r\n");
	}
	kf->Close(kf);

	/* --- 5. the EFI memory map --------------------------------------- */
	size = 0;
	st2 = BS->GetMemoryMap(&size, 0, &key, &dsz, &dver);
	/* dsz is the firmware's descriptor stride, not sizeof(struct); OVMF
	 * reports 48 where our EFI_MEMORY_DESCRIPTOR is 40.  Only sanity-check
	 * that it is at least big enough to hold the fields we read. */
	if (st2 != EFI_BUFFER_TOO_SMALL ||
	    dsz < (u64)sizeof(EFI_MEMORY_DESCRIPTOR)) {
		s_puts("RL: GetMemoryMap(size) -> "); s_hex32((u32)st2);
		s_puts(" dsz="); s_dec(dsz); s_puts("\r\n");
		return st2 ? (u64)st2 : ERR(22);
	}
	if (size > MEMMAP_MAX_BYTES) {
		s_puts("RL: map too big "); s_dec(size); s_puts("\r\n");
		return ERR(22);
	}
	st2 = BS->GetMemoryMap(&size, (void *)g_memmap, &key, &dsz, &dver);
	if (st2) { s_puts("RL: GetMemoryMap failed\r\n"); return (u64)st2; }
	used = size;
	map = (EFI_MEMORY_DESCRIPTOR *)g_memmap;
	n = size / dsz;
	for (u64 k = 0; k < n; k++) {
		const EFI_MEMORY_DESCRIPTOR *d =
		    (const EFI_MEMORY_DESCRIPTOR *)((const u8 *)map + k * dsz);
		u64 end = d->PhysicalStart + (d->NumberOfPages << 12);
		/* Every RAM-bearing type, so the physmap (PhysicalMemorySize + 4GB)
		 * certainly spans the ACPI tables the kernel reaches through the
		 * EFI system table. */
		if (d->Type >= 1 && d->Type <= 7 && end > ram_top)
			ram_top = end;
	}
	s_puts("RL: memmap n="); s_dec(n);
	s_puts(" bytes="); s_dec(used);
	s_puts(" key=0x"); s_hex64(key);
	s_puts(" physmem=0x"); s_hex64(ram_top); s_puts("\r\n");

	/* --- 6. pick the block we own, and fill boot_args ---------------- */
	g_hoff_page = (u32)find_block((const u8 *)map, n, dsz, 0x200000ULL,
	    0x40000000ULL, base, top);
	if (!g_hoff_page) { s_puts("RL: no block for boot_args\r\n"); return ERR(9); }
	s_puts("RL: block at 0x"); s_hex32(g_hoff_page); s_puts("\r\n");


	/*
	 * Copy the memory map into our LOW handoff block.
	 *
	 * The loader's .bss lives wherever the firmware placed the image (~2 GiB
	 * on OVMF), but i386_vm_init reads args->MemoryMap through the kernel's
	 * early STATIC physmap window (ml_static_ptovirt), which does not cover
	 * that high.  The boot log shows exactly this: #PF in i386_vm_init at
	 * 0xffffff807de14d28 = static_base + the loader's own g_memmap address.
	 * Everything the kernel touches before it has built its real physmap
	 * must be in low memory, which is what this block is for.
	 */
	{
		u8 *dst = (u8 *)(u64)(g_hoff_page + BLK_OFF_MEMMAP);
		const u8 *src = g_memmap;
		for (u64 i = 0; i < used; i++) {
			dst[i] = src[i];
		}
		/*
		 * Give the EFI runtime ranges a VirtualStart the kernel can map.
		 *
		 * Nothing calls SetVirtualAddressMap, so the firmware leaves
		 * VirtualStart = 0, and efi_init() maps each range at
		 * `VirtualStart | VM_MIN_KERNEL_ADDRESS`: all five land on
		 * 0xffffff8000000000 and clobber the kernel's own low mappings.
		 *
		 * pmap_map_bd() panics unless the VA's page table entry already
		 * exists, and the kernel preallocates nothing for these ranges --
		 * the window is exactly [0, kaddr + ksize), which this loader
		 * controls.  Measured: physfree 0x17a0000 -> VAs 0x10000000 and
		 * 0x7ee3b000 both panic; physfree 0x8100000 (ksize 128 MiB) ->
		 * VAs 0x2000000..0x6000000 all map.
		 *
		 * Give the ranges distinct low VAs, packed just above the
		 * kernel image.  Identity VAs (the obvious choice) would drag
		 * physfree out to the runtime ranges' own physical addresses
		 * near 2 GiB, and physfree is also first_avail, so 2 GiB of it
		 * costs 2 GiB of real RAM and dies in pmap_steal_memory() --
		 * see BOOT-PLAN.md section 13.  It also cannot work: the static
		 * window is capped at NKPT * PTE_PER_PAGE = 1000 MiB.
		 *
		 * Packing them tight keeps physfree proportional to the
		 * runtime ranges' own sizes (~9 MiB here) instead of to
		 * installed RAM, which is what makes this scale past 4 GB.
		 */
	{
		const u64 A2M = 0x200000ULL;
		u64 lo = g_hoff_page + (BLK_PAGES << 12);   /* past our block */
		u64 slot = (lo > top ? lo : top);
		slot = (slot + A2M - 1) & ~(A2M - 1);

		for (u64 k = 0; k < used / dsz; k++) {
			u8 *e = dst + k * dsz;
			if (*(u64 *)(e + 32) & EFI_MEMORY_RUNTIME) {
				u64 pages = *(u64 *)(e + 24);
				u64 sz = (pages + 1) << 12;      /* 4K, 64-bit len */
				*(u64 *)(e + 16) = slot;
				slot += (sz + A2M - 1) & ~(A2M - 1);
				rt_end = slot;
			}
		}
		s_puts("RL: runtime VA top=0x"); s_hex32((u32)rt_end); s_puts("\r\n");
	}
	}
	{
		u8 *ba = (u8 *)(u64)(g_hoff_page + BLK_OFF_BOOTARGS);
		memset(ba, 0, 4096);
		A = (boot_args *)ba;
		g_bootargs_phys = g_hoff_page + BLK_OFF_BOOTARGS;

		A->Revision = 0;                 /* not a kernel collection */
		A->Version  = 2;
		A->efiMode  = 64;                 /* kBootArgsEfiMode64 */
		A->debugMode = 0;
		A->flags = 0;
		A->kaddr = (u32)base;
		/* physfree = PAGE_ROUND(kaddr + ksize).  It must cover our handoff
		 * block, the kernel image, and every runtime VA we just assigned,
		 * because pmap_map_bd() panics on a VA whose page table entry does
		 * not already exist and the window is exactly [0, physfree).
		 *
		 * physfree is also first_avail, so every byte here is RAM the VM
		 * subsystem will never hand out.  The previous 128 MiB floor was
		 * paid on every boot and on every machine; deriving the bound
		 * from the actual runtime VAs costs ~9 MiB and is independent of
		 * installed memory.  Do not raise it to a fixed number. */
		{
			u64 end = g_hoff_page + (BLK_PAGES << 12) > top
			    ? g_hoff_page + (BLK_PAGES << 12) : top;
			if (end < rt_end) {
				end = rt_end;
			}
			A->ksize = (u32)(end - base);
		}
		A->efiSystemTable = (u32)(u64)ST;
		/* The device tree built in build_handoff_block. */
		A->deviceTreeP = g_hoff_page + BLK_OFF_DEVTREE;
		A->deviceTreeLength = BLK_DEVTREE_SIZE;
		A->KC_hdrs_vaddr = 0;             /* MH_EXECUTE, not MH_FILESET */
		A->kslide = 0;
		A->topOfKernelData = 0;
		A->PhysicalMemorySize = ram_top;
		A->MemoryMap = g_hoff_page + BLK_OFF_MEMMAP;
		A->MemoryMapSize = (u32)used;
		A->MemoryMapDescriptorSize = (u32)dsz;
		A->MemoryMapDescriptorVersion = (u32)dver;
		A->Video.v_display = 0;           /* headless: serial=1 */
		{
			u32 cn = 0;
			const char *src = DEFAULT_CMDLINE;
			while (*src && cn < BOOT_LINE_LENGTH - 1)
				A->CommandLine[cn++] = *src++;
			A->CommandLine[cn] = 0;
		}
		s_puts("RL: kaddr=0x"); s_hex32(A->kaddr);
		s_puts(" ksize=0x"); s_hex32(A->ksize);
		s_puts(" physfree=0x");
		s_hex32((u32)((base + A->ksize + 0xFFF) & ~0xFFFULL));
		s_puts(" map=0x"); s_hex32(A->MemoryMap);
		s_puts(" +0x"); s_hex32(A->MemoryMapSize); s_puts("\r\n");
		s_puts("RL: cmdline='"); s_puts(A->CommandLine); s_puts("'\r\n");
	}

	/* --- 7. handoff -------------------------------------------------- */
	build_handoff_block((u8 *)(u64)g_hoff_page);

	s_puts("RL: EXIT-BOOT-SERVICES\r\n");
	st2 = BS->ExitBootServices(ImageHandle, key);
	if (st2) {
		s_puts("RL: ExitBootServices failed ");
		s_hex32((u32)st2); s_puts("\r\n");
		return (u64)st2;
	}
	s_puts("RL: HANDOFF eax=0x"); s_hex32(g_bootargs_phys);
	s_puts(" target=0x"); s_hex32(g_entry_phys); s_puts("\r\n");

	handoff(g_hoff_page, g_bootargs_phys);
	return 0;   /* not reached */
}
