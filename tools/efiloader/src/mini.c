/* Minimal freestanding EFI application - toolchain/ABI proof for the
 * ravynOS EFI loader.  Single translation unit, no libc, no EDK2.
 *
 * Proves: (1) clang -target x86_64-unknown-windows produces COFF that
 * pack.py turns into a PE32+ EFI application, (2) the EFI boot-services
 * table walk works, (3) EFI_FILE_PROTOCOL reads the real kernel image
 * off the ESP, (4) a 32-bit protected-mode entry trampoline assembles.
 */

typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef int i32;

typedef u64 EFI_STATUS;
typedef u64 EFI_HANDLE;
typedef void *EFI_VOID;

#define ERR(a) (0x8000000000000000ULL | (a))

typedef struct { u32 Data1; u16 Data2; u16 Data3; u8 Data4[8]; } EFI_GUID;
#define GUID(a, b, c, d, e, f, g, h, i, j, k) { a, b, c, { d, e, f, g, h, i, j, k } }

typedef struct { u64 Signature; u32 Revision; u32 HeaderSize; u32 CRC32; u32 Reserved; } EFI_TABLE_HEADER;

typedef struct { u64 _rsvd; u8 *Data; } SIMPLE_TEXT_OUT;

typedef EFI_STATUS (*EFI_TEXT_OUT)(void *, u64 *, u16 *);

typedef struct { u64 _rsvd; EFI_TEXT_OUT Write; } EFI_SIMPLE_TEXT_OUT;

typedef struct {
	EFI_TABLE_HEADER Hdr;
	u64 FirmwareVendor;
	u32 FirmwareRevision;
	u32 __pad;
	u64 ConsoleInHandle;   EFI_VOID *ConIn;
	u64 ConsoleOutHandle;  EFI_SIMPLE_TEXT_OUT *ConOut;
	u64 StandardErrorHandle; EFI_SIMPLE_TEXT_OUT *StdErr;
	EFI_VOID *RT;
	EFI_VOID *BS;
	u64 NumberOfTableEntries;
	EFI_GUID *ConfigurationTable;
} EFI_SYSTEM_TABLE;

/* EFI_BOOT_SERVICES, only the entries we use, in spec order. */
typedef struct {
	EFI_TABLE_HEADER Hdr;
	u64 (*RaiseTPL)(u64);
	u64 (*RestoreTPL)(u64);
	u64 (*AllocatePages)(u32, u64, u64 *);
	u64 (*FreePages)(u64, u64);
	u64 (*GetMemoryMap)(u64 *, u64 *, u64 *, u64 *, u64);
	u64 (*AllocatePool)(u32, u64, EFI_VOID **);
	u64 (*FreePool)(EFI_VOID *);
	u64 (*CreateEvent)(u32, u64, u64, EFI_VOID *, EFI_VOID **);
	u64 (*SetTimer)(EFI_VOID *, u64, u64);
	u64 (*WaitForEvent)(u64, u64 *);
	u64 (*SignalEvent)(EFI_VOID *);
	u64 (*CloseEvent)(EFI_VOID *);
	u64 (*CheckEvent)(EFI_VOID *);
	u64 (*InstallProtocolInterface)(u64 *, EFI_GUID *, u32, u64);
	u64 (*ReinstallProtocolInterface)(u64, EFI_GUID *, u64);
	u64 (*UninstallProtocolInterface)(u64, EFI_GUID *, u64);
	u64 (*HandleProtocol)(EFI_HANDLE, EFI_GUID *, EFI_VOID **);
	u64 Reserved;
	u64 (*RegisterProtocolNotify)(EFI_HANDLE, EFI_GUID *, EFI_VOID *, EFI_VOID **);
	u64 (*LocateHandle)(u32, EFI_GUID *, EFI_VOID *, u64 *, EFI_HANDLE *);
	u64 (*LocateDevicePath)(EFI_GUID *, EFI_VOID **, EFI_HANDLE *);
	u64 (*InstallConfigurationTable)(EFI_GUID *, EFI_VOID *);
} EFI_BOOT_SERVICES;

typedef struct EFI_LOADED_IMAGE_PROTOCOL EFI_LOADED_IMAGE_PROTOCOL;
struct EFI_LOADED_IMAGE_PROTOCOL {
	u32 Revision;
	EFI_VOID *FileHandle;
	EFI_VOID *DeviceHandle;
	EFI_VOID *ImageBase;
	u64 ImageSize;
	EFI_VOID *ImageCode;
	EFI_VOID *ImageData;
	u64 Unload;
};

typedef struct EFI_FILE_PROTOCOL EFI_FILE_PROTOCOL;
struct EFI_FILE_PROTOCOL {
	u64 Revision;
	u64 (*Open)(EFI_FILE_PROTOCOL *, EFI_FILE_PROTOCOL **, u16 *, u64, EFI_VOID *);
	u64 (*Close)(EFI_FILE_PROTOCOL *);
	u64 (*Delete)(EFI_FILE_PROTOCOL *);
	u64 (*Read)(EFI_FILE_PROTOCOL *, u64 *, void *);
	u64 (*Write)(EFI_FILE_PROTOCOL *, u64 *, EFI_VOID *);
	u64 (*GetPosition)(EFI_FILE_PROTOCOL *, u64 *);
	u64 (*SetPosition)(EFI_FILE_PROTOCOL *, u64);
	u64 (*GetInfo)(EFI_FILE_PROTOCOL *, EFI_VOID *, u64 *, u64 *);
	u64 (*SetInfo)(EFI_FILE_PROTOCOL *, EFI_VOID *, u64, u64);
	u64 (*Flush)(EFI_FILE_PROTOCOL *);
};

typedef struct { u64 Revision; u64 (*OpenVolume)(EFI_FILE_PROTOCOL *, EFI_FILE_PROTOCOL **); }
	EFI_SIMPLE_FILE_SYSTEM_PROTOCOL;

static EFI_SIMPLE_TEXT_OUT *g_ConOut;

static void cputc(u8 c)
{
	u16 b[2]; u64 n = 2; b[0] = c; b[1] = 0;
	g_ConOut->Write(g_ConOut, &n, b);
}

static void puts_(const char *s) { while (*s) cputc((u8)*s++); }

static void puthex(u64 v, int digits)
{
	static const char h[] = "0123456789abcdef";
	for (int i = digits * 4 - 4; i >= 0; i -= 4) cputc((u8)h[(v >> i) & 0xf]);
}

static void putdec(u64 v)
{
	char b[24]; int i = 0;
	if (!v) { cputc('0'); return; }
	while (v) { b[i++] = (char)('0' + (v % 10)); v /= 10; }
	while (i--) cputc((u8)b[i]);
}

#define NL cputc('\r'); cputc('\n')

/* 32-bit protected-mode landing pad.  The ravynOS kernel's _pstart is
 * .code32 and expects protected mode, paging off, flat 4G segments. */
__asm__(
	".section .text.boot32,\"xr\"\n"
	".code32\n"
	".globl boot32_entry\n"
	".def boot32_entry; .scl 2; .type 32; .endef\n"
	"boot32_entry:\n"
	"	cli\n"
	"	movl	%eax, %edi\n"		/* EDI = boot_args phys */
	"	movl	$0x9000, %esp\n"
	"	movw	$0x10, %ax\n"
	"	movw	%ax, %ds\n"
	"	movw	%ax, %es\n"
	"	movw	%ax, %ss\n"
	"	movw	%ax, %fs\n"
	"	movw	%ax, %gs\n"
	"	hlt\n"
	".code64\n");

extern void boot32_entry(void);

EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *ST);

EFI_STATUS
efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *ST)
{
	EFI_GUID g_loaded_image = GUID(0x5B1B31A1, 0x9562, 0x11D2,
	    0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B);
	EFI_GUID g_simple_fs = GUID(0x964E5B22, 0x6459, 0x11D2,
	    0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B);
	EFI_BOOT_SERVICES *BS = (EFI_BOOT_SERVICES *)ST->BS;
	EFI_LOADED_IMAGE_PROTOCOL *li = 0;
	EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs = 0;
	EFI_FILE_PROTOCOL *root = 0, *k = 0;
	u16 path[] = { '\\', 'S', 'y', 's', 't', 'e', 'm', '\\', 'L', 'i',
	    'b', 'r', 'a', 'r', 'y', '\\', 'K', 'e', 'r', 'n', 'e', 'l',
	    's', '\\', 'k', 'e', 'r', 'n', 'e', 'l', '.', 'd', 'e', 'v',
	    'e', 'l', 'o', 'p', 'm', 'e', 'n', 't', 0 };
	u32 hdr[2];
	u64 n = sizeof(hdr);
	u64 st;

	g_ConOut = ST->ConOut;
	puts_("ravynos-efi-loader probe"); NL;
	puts_("  ImageHandle="); puthex((u64)ImageHandle, 16); NL;
	puts_("  SystemTable="); puthex((u64)ST, 16); NL;

	st = BS->HandleProtocol(ImageHandle, &g_loaded_image, (EFI_VOID **)&li);
	puts_("  HandleProtocol(LoadedImage)="); puthex(st, 16);
	puts_(" ImageBase="); puthex((u64)li->ImageBase, 16);
	puts_(" ImageSize="); puthex(li->ImageSize, 16); NL;
	if (st) return st;

	{
		EFI_HANDLE *handles = 0;
		u64 nhandles = 0;
		st = BS->LocateHandle(2 /*ByProtocol*/, &g_simple_fs, 0,
		    &nhandles, (EFI_HANDLE *)&handles);
		puts_("  LocateHandle(SimpleFS)="); puthex(st, 16);
		puts_(" n="); putdec(nhandles); NL;
		if (st || !nhandles) { puts_("  no volume"); NL; return ERR(2); }
		st = BS->HandleProtocol(handles[0], &g_simple_fs, (EFI_VOID **)&fs);
		if (st) return st;
	}
	st = fs->OpenVolume(fs, &root);
	puts_("  OpenVolume="); puthex(st, 16); NL;

	st = root->Open(root, &k, path, 0, 0);
	puts_("  Open(kernel.development)="); puthex(st, 16); NL;
	if (st) { puts_("  FAIL"); NL; return st; }

	st = k->Read(k, &n, hdr);
	puts_("  Read="); puthex(st, 16);
	puts_(" n="); putdec(n);
	puts_(" magic=0x"); puthex(hdr[1], 8); NL;
	if (hdr[1] == 0xfeedfacfu) puts_("  MH_MAGIC_64 confirmed"); NL;

	puts_("  boot32_entry="); puthex((u64)boot32_entry, 16); NL;
	puts_("probe OK"); NL;
	return 0;
}
