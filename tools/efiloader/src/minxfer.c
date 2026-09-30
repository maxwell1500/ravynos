/*
 * Minimal A/B for the long->32-bit transfer.
 *
 * WHY THIS EXISTS
 * ---------------
 * The full loader's far return raises #GP(8) even though every field is
 * confirmed correct on the wire: GDT limit 0x17 base 0x20000, code descriptor
 * access byte 0x9B (P=1 S=1 type=0xB), D/B=1, L=0, a packed 4+2 frame in our
 * own low page, CR0.PG and CR4.PAE cleared before the transfer, and `cb lretl`
 * present unprefixed in the packed PE.
 *
 * This file does NONE of that work's neighbours. No Mach-O, no boot_args, no
 * memory map, no ExitBootServices, no serial helpers beyond one byte. It is
 * the smallest thing that can either transfer or not, so:
 *   - if it works, the difference is in what the full loader does beforehand
 *   - if it fails identically, the transfer IDIOM is wrong and the answer is
 *     in the SDM or a reference implementation, not in our code
 *
 * It runs with paging ON (the firmware's identity map is still valid) and
 * clears CR0.PG only after the transfer, so it does not even share that
 * precondition with the full loader.
 *
 * Build:  clang -target x86_64-unknown-windows -ffreestanding -fno-stack-protector
 *           -mno-red-zone -mcmodel=medium -fno-builtin -Os -g0 -c minxfer.c -o m.obj
 *         python3 ../pack.py m.obj MINXFER.EFI efi_main
 */
typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef u64 EFI_STATUS;
typedef u64 EFI_HANDLE;
typedef void *EFI_VOID;

typedef struct { u64 Signature; u32 Revision; u32 HeaderSize; u32 CRC32; u32 Reserved; } EFI_TABLE_HEADER;
typedef struct { u64 Reserved; void *Write; } SIMPLE_TEXT_OUT;
typedef struct {
	EFI_TABLE_HEADER Hdr;
	u64 FirmwareVendor; u32 FirmwareRevision; u32 pad;
	u64 ConsoleInHandle; void *ConIn;
	u64 ConsoleOutHandle; SIMPLE_TEXT_OUT *ConOut;
	u64 StandardErrorHandle; SIMPLE_TEXT_OUT *StdErr;
	void *RT; void *BS; u64 NumberOfTableEntries; void *ConfigurationTable;
} EFI_SYSTEM_TABLE;
typedef struct { u64 Signature; u32 Revision; u32 HeaderSize; u32 CRC32; u32 Reserved; } EFI_BS_HDR;
typedef struct {
	EFI_BS_HDR Hdr;
	void *RaiseTPL; void *RestoreTPL;
	void *AllocatePages; void *FreePages; void *GetMemoryMap;
	void *AllocatePool; void *FreePool;
	void *CreateEvent; void *SetTimer; void *WaitForEvent;
	void *SignalEvent; void *CloseEvent; void *CheckEvent;
	void *InstallProtocolInterface; void *ReinstallProtocolInterface;
	void *UninstallProtocolInterface;
	void *HandleProtocol; u64 Reserved;
	void *RegisterProtocolNotify; void *LocateHandle;
} EFI_BOOT_SERVICES;
typedef EFI_STATUS (*EFI_ALLOCATE_PAGES)(u32, u64, u64 *);

#define PAGE 0x1000
#define LOW  0x00020000ULL

static inline void outb(u8 v, u16 p)
{
	__asm__ volatile("outb %0, %1" :: "a"(v), "d"(p) : "memory");
}

static void s(const char *x) { while (*x) outb((u8)*x++, 0x3F8); }
static void hex(u64 v)
{
	static const char h[] = "0123456789abcdef";
	for (int i = 60; i >= 0; i -= 4)
		outb((u8)h[(v >> i) & 0xf], 0x3F8);
}

/* The 64-bit half: clear CR0.PG/CR4.PAE, lgdt, packed 4+2 frame, lretl.
 * Sequence per the standard long->protected transition: the paging-mode
 * change happens from the 64-bit side, while the firmware's identity map is
 * still in effect. */
__attribute__((naked)) static void go(void)
{
	/* MEMORY-OPERAND form, and this comment used to claim otherwise --
	 * it described an "immediate form" that this code never emitted.
	 * CB is RETF with no immediate (that opcode is CA imm16).  What the
	 * bytes below actually do: point RSP at the packed 4+2 frame the C
	 * half wrote at low+0x60, then RETF pops RIP from [RSP] and CS from
	 * [RSP+4].  Trust the bytes, not this comment.
	 *
	 * EFER.LMA is now cleared too.  Apple's boot.efi -- which is proven to
	 * hand off on this exact machine -- does exactly this, in this order:
	 *     lgdt; mov ds/es/gs/fs,0x10; clear CR0.PG; rdmsr EFER;
	 *     btr eax,8; wrmsr; ... jump
	 * Leaving LMA=1 while a far RETURN loads a non-long CS is the second,
	 * separate defect; the first (CS naming a null descriptor) is fixed
	 * above and is why the #GP(8) error code named the selector. */
	__asm__ volatile(
		"cli                              \n\t"
		"movabsq $0x20000, %rbx           \n\t"
		"movq   %cr0, %rax                \n\t"
		"btr    $31, %eax                 \n\t"
		"btr    $16, %eax                 \n\t"
		"movq   %rax, %cr0                \n\t"
		"movq   %cr4, %rax                \n\t"
		"btr    $5, %eax                  \n\t"
		"movq   %rax, %cr4                \n\t"
		"movl   $0xc0000080, %ecx         \n\t"	/* IA32_EFER          */
		"rdmsr                            \n\t"
		"btr    $8, %eax                  \n\t"	/* EFER.LMA = 0       */
		"wrmsr                            \n\t"
		"lgdt   0x00(%rbx)                \n\t"
		"sgdt   0xA0(%rbx)                \n\t"
		"leaq   0x60(%rbx), %rsp          \n\t"
		".byte  0xCB                      \n\t"  /* RETF, 32-bit operand */
		"hlt                              \n\t");
}

EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *ST);

EFI_STATUS
efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *ST)
{
	u8 *low = (u8 *)(u64)LOW;

	/* No allocation and no ExitBootServices. Paging stays on, the firmware's
	 * identity map is in effect, and the low page is ordinary RAM. */

	/* 0x00: GDT pointer (limit u16, base u64 at +2) */
	low[0x00] = 23; low[0x01] = 0;
	for (int i = 0; i < 8; i++) low[0x02 + i] = 0;
	low[0x02] = (u8)(LOW & 0xff);
	low[0x03] = (u8)((LOW >> 8) & 0xff);
	low[0x04] = (u8)((LOW >> 16) & 0xff);
	low[0x05] = (u8)((LOW >> 24) & 0xff);
	/* Descriptor table, at low[0x10].
	 *
	 * THE GDT BASE IS *low* (0x20000), so selector N addresses
	 * low[N & ~7].  The table therefore cannot start before low[0x10]:
	 * the pseudo-descriptor above occupies low[0x00..0x09], and its last
	 * two bytes ARE the high bytes of the base.  Writing a descriptor at
	 * low[0x08] overwrites them -- the CPU then confirms a base of
	 * 0xffff000000020000, which is exactly what the sgdt read-back showed.
	 *
	 * With the table at low[0x10], this array leads with the CODE
	 * descriptor, so the code segment is selector 0x10 and the far-return
	 * frame below loads CS=0x0010.  The original code had the table in
	 * the same place but led with a null descriptor, which put a NULL at
	 * selector 0x10 and the code at 0x18 -- while the frame loaded
	 * CS=0x0010, the eight zero bytes at low[0x08].
	 *
	 * The error code was naming the selector being loaded the whole time:
	 * a null descriptor is not present, so loading it raises #GP carrying
	 * that selector, which is why the code read #GP(8).
	 */
	static const u8 gdt[24] = {
		0xFF, 0xFF, 0x00, 0x00, 0x00, 0x9B, 0x9F, 0x00,	/* sel 0x10: code */
		0xFF, 0xFF, 0x00, 0x00, 0x00, 0x93, 0x9F, 0x00,	/* sel 0x18: data */
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	};
	for (int i = 0; i < 24; i++) low[0x10 + i] = gdt[i];
	/* 0x60: the packed far-return frame, written here by C so the 64-bit
	 * half does not have to compute it */
	/* 0x80: the 32-bit target, emitted here so the frame can point at it */
	static const u8 code32[] = {
		0xFA,                       /* cli              */
		0xB0, 0x2A,                 /* mov $'*',%al     */
		0x66, 0xBA, 0xF8, 0x03,     /* mov $0x3f8,%dx   */
		0xEE,                       /* out %al,%dx      */
		0xB0, 0x2B,                 /* mov $'+',%al     */
		0xEE,                       /* out %al,%dx      */
		0xF4,                       /* hlt              */
	};
	for (unsigned i = 0; i < sizeof(code32); i++)
		low[0x80 + i] = code32[i];

	low[0x60] = (u8)(((u32)LOW + 0x80) & 0xff);
	low[0x61] = (u8)(((u32)LOW + 0x80) >> 8 & 0xff);
	low[0x62] = (u8)(((u32)LOW + 0x80) >> 16 & 0xff);
	low[0x63] = (u8)(((u32)LOW + 0x80) >> 24 & 0xff);
	low[0x64] = 0x10;	/* CS = selector 0x10 == the CODE descriptor */
	low[0x65] = 0x00;

	/* --- read GDTR back FROM the CPU ---------------------------------
	 * Every other field has been confirmed from OUR memory.  This one is
	 * only true if the CPU actually took it, and a wrong base is
	 * consistent with every symptom seen so far.  Plain C, into our own
	 * low page, before any transfer.
	 *
	 * NOTE the offset: the pseudo-descriptor is at low+0x00.  Both this
	 * and the stub below originally read low+0x10, which is the first
	 * DESCRIPTOR -- so the CPU was handed limit=0xffff and a base built out
	 * of descriptor bytes, and the sgdt read-back is what finally showed
	 * it. */
	__asm__ volatile("lgdt 0x00(%0)   \n\t"
	                 "sgdt 0xA0(%0)       "
	                 : : "r"(low) : "memory");
	{
		u64 gb = 0;
		for (int i = 0; i < 8; i++)
			gb |= (u64)low[0xA2 + i] << (8 * i);
		s("\r\nMINXFER: GDTR-from-CPU limit=0x");
		hex(low[0xA0] | (low[0xA1] << 8));
		s(" base=0x");
		hex(gb);
		s("   [we loaded limit=0x17 base=0x20000]\r\n");
		/* Print the descriptor the far return will ACTUALLY load, i.e.
		 * the one at (GDT base + CS), with an explicit marker so an
		 * all-zero read cannot look like a formatting glitch.  An earlier
		 * run printed eight raw 0x00 bytes here as an apparently empty
		 * line; that empty line WAS the bug -- selector 8 resolved to a
		 * null descriptor, which is exactly what #GP(8) reports. */
		{
			volatile u8 *d = (volatile u8 *)(gb + 0x10);
			s("MINXFER: desc for CS=0x10 at GDT+0x10 = [");
			for (int i = 0; i < 8; i++) {
				outb('0', 0x3F8); outb('0', 0x3F8);
				u8 b = d[i];
				outb("0123456789abcdef"[b >> 4], 0x3F8);
				outb("0123456789abcdef"[b & 15], 0x3F8);
			}
			s("] access=0x");
			outb("0123456789abcdef"[d[5] >> 4], 0x3F8);
			outb("0123456789abcdef"[d[5] & 15], 0x3F8);
			s(" present=");
			s((d[5] & 0x80) ? "YES" : "NO");
			s((d[5] == 0x9b) ? " (32-bit code, correct)" : "  *** WRONG ***");
			s("\r\n");
		}
	}

	s("\r\nMINXFER: low page at 0x");
	hex(LOW);
	s(", GDT limit 0x17 base 0x");
	hex(LOW);
	s(", code access 0x9B, frame RIP=0x");
	hex(LOW + 0x60);
	s(" CS=0x0010\r\nMINXFER: transferring\r\n");

	go();
	s("MINXFER: RETURNED (transfer did not happen)\r\n");
	return 0;
}
