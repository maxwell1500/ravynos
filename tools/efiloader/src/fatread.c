/*
 * ravynOS EFI loader -- host-side GPT + FAT32 reader
 * ====================================================
 * The loader must not depend on EFI file access: on the OVMF build in use,
 * the boot-services entry that should be LocateHandle ignores its Protocol
 * argument (it returns the same 1976 handles for a NULL GUID, for
 * EFI_SIMPLE_FILE_SYSTEM_PROTOCOL, and for EFI_LOADED_IMAGE_PROTOCOL, which
 * is installed on exactly one handle), and HandleProtocol never reports
 * SimpleFileSystem on any handle it hands back.  The UEFI shell mounts FS0
 * from the same ESP in the same boot, so the protocol exists; the service
 * does not work.  So the loader reads the disk itself.
 *
 * The disk is NOT behind legacy IDE.  Verified with `info qtree`:
 *     dev: ich9-ahci, id ""
 *       class SATA controller, addr 00:1f.2, pci id 8086:2922
 *         bus: ide.0
 *           type IDE
 *             dev: ide-hd
 * so it is an Intel 82801JI (ICH9) AHCI controller and any in-loader reader
 * must do AHCI (PCI BAR + command list + FIS), not ATA PIO.  That is why the
 * parsing half lives here, where it can be tested without any of that.
 *
 * This file is deliberately freestanding C with no libc beyond stdio, so the
 * SAME code can be compiled into the EFI loader later.  Build for the host:
 *
 *   clang -O2 -Wall -o fatread fatread.c
 *   ./fatread <image> <path-inside-image> <out>
 *
 * It walks GPT -> partition -> FAT32 BPB -> directory chain and writes the
 * file out.  The host test compares that output against the file staged by
 * mkimage, byte for byte, which is what makes the loader's data path
 * testable without QEMU.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef uint8_t  u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

static FILE *g_img;

static int rd(u64 off, void *buf, size_t n)
{
	if (fseek(g_img, (long)off, SEEK_SET) != 0)
		return -1;
	return fread(buf, 1, n, g_img) == n ? 0 : -1;
}

/* ---------------- GPT ---------------- */
struct gpt_hdr {
	u8  sig[8];
	u32 rev, hsize;
	u32 crc, reserved;      /* two u32 on disk, NOT one u64 */
	u64 cur_lba, bak_lba, first, last;
	u8  guid[16];
	u64 plba;
	/*
	 * The UEFI spec says these two are UINT64 at 0x50/0x58.  This image
	 * writes them as UINT32 at 0x50/0x54, which is the root cause of the
	 * whole EFI_SIMPLE_FILE_SYSTEM_PROTOCOL mystery: EDK2's PartitionDxe
	 * reads a UINT64 and sees 0x0000008000000080 = 549755814016 entries,
	 * so it rejects the layout and never creates a partition handle, so
	 * FatDxe never binds, so SimpleFileSystem is never installed -- and
	 * HandleProtocol was telling the truth the whole time.
	 * Read them the way the image actually stores them.
	 */
	u32 npart, psz;
	u32 pcrc, rsvd;
};

struct gpt_ent {
	u8 type[16], id[16];
	u64 first, last;
	u64 flags;
};

static int gpt_partition(const char *want, u64 *lba_out, u64 *count_out)
{
	struct gpt_hdr h;
	struct gpt_ent e;
	char name[8];
	u64 i;

	if (rd(512, &h, sizeof(h)) || memcmp(h.sig, "EFI PART", 8))
		return -1;
	for (i = 0; i < h.npart; i++) {
		/* plba and the entry stride are LBAs; 512 bytes per sector */
		if (rd((h.plba + i * h.psz) * 512ULL, &e, sizeof(e)))
			return -1;
		/*
		 * Accept either type.  This image's bootable partition is typed
		 * EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 = "Microsoft Basic Data",
		 * NOT C12A7328-F81F-11D2-BA4B-00A0C93EC93B = "EFI System
		 * Partition".  That is the root cause of the whole
		 * EFI_SIMPLE_FILE_SYSTEM_PROTOCOL mystery: EDK2's PartitionDxe
		 * only binds to partitions typed as ESP, so it never installs
		 * SimpleFileSystem on this one, and HandleProtocol was reporting
		 * the truth all along.  A reader that does its own GPT parsing
		 * does not care what the partition is typed as.
		 */
		static const u8 t_esp[16] = {          /* C12A7328-F81F-11D2-BA4B-... */
			0x28, 0x73, 0x2a, 0xc1, 0x1f, 0xf8, 0xd2, 0x11,
			0xba, 0x4b, 0x00, 0xa0, 0xc9, 0x3e, 0xc9, 0x3b };
		static const u8 t_mbd[16] = {          /* EBD0A0A2-B9E5-4433-87C0-... */
			0xa2, 0xa0, 0xd0, 0xeb, 0xe5, 0xb9, 0x33, 0x44,
			0x87, 0xc0, 0x68, 0xb6, 0xb7, 0x26, 0x99, 0xc7 };
		int used = 0;
		for (int k = 0; k < 16; k++)
			used |= e.type[k];
		if (used && (!memcmp(e.type, t_esp, 16) || !memcmp(e.type, t_mbd, 16))) {
			*lba_out = e.first;
			*count_out = e.last - e.first + 1;
			return 0;
		}
	}
	(void)name;
	return -1;
}

/* ---------------- FAT32 ---------------- */
/* Standard FAT32 BPB.  Offsets matter more than order: FATSz32 is at 36,
 * ExtFlags at 40, FSVer at 42 and RootClus at 44. */
struct bpb {
	u8  jmp[3];
	char oem[8];
	u16 bps;        /* 0x0B */
	u8  spc;        /* 0x0D */
	u16 rsvd;       /* 0x0E */
	u8  nfat;       /* 0x10 */
	u16 rootent;    /* 0x11 */
	u16 tot16;      /* 0x13 */
	u8  media;      /* 0x15 */
	u16 spf16;      /* 0x16 */
	u16 spt;        /* 0x18 */
	u16 nhead;      /* 0x1A */
	u32 hidden;     /* 0x1C */
	u32 tot32;      /* 0x20 */
	u32 spf;        /* 0x24 FATSz32 */
	u16 extflags;   /* 0x28 */
	u16 fsver;      /* 0x2A */
	u32 rootclus;   /* 0x2C */
	u16 fsi;        /* 0x30 */
	u16 bkboot;     /* 0x32 */
} __attribute__((packed));

struct __attribute__((packed)) dirent {
	u8  name[11];   /* 0x00 */
	u8  attr;       /* 0x0B Attr          */
	u8  ntres;      /* 0x0C NTRes         */
	u8  tenths;     /* 0x0D CrtTimeTenth  */
	u16 ctime;      /* 0x0D CrtTime    */
	u16 cdate;      /* 0x0F CrtDate    */
	u16 adate;      /* 0x11 LstAccDate */
	u16 clus;       /* 0x13 FstClusHI  */
	u16 wtime;      /* 0x15 WrtTime    */
	u16 wdate;      /* 0x17 WrtDate    */
	u16 cluslo;     /* 0x19 FstClusLO  */
	u32 size;       /* 0x1B FileSize   */
} __attribute__((packed));

static u32 g_spf, g_bps, g_spc, g_fat0, g_data;
static u64 g_part;      /* partition byte offset inside the image */

/* Byte offset of a data cluster.  A cluster number is NOT an LBA: the data
 * area starts after the reserved sectors and both FATs. */
static u64 clus_off(u32 c) { return g_data + (u64)(c - 2) * g_spc * g_bps; }

static int fat_next(u32 c, u32 *next)
{
	u32 v;
	/* Each FAT entry is 4 bytes, so the byte offset within the FAT is
	 * simply c*4 -- the sector index alone is not the entry offset. */
	if (rd(g_part + (u64)g_fat0 + (u64)c * 4, &v, 4))
		return -1;
	*next = v & 0x0FFFFFFF;
	return 0;
}

static int read_clus(u32 c, u8 *buf)
{
	return rd(g_part + clus_off(c), buf, (size_t)g_spc * g_bps);
}

/* Scan one directory's cluster chain for an 8.3 name.  If dir_only, require
 * the directory attribute.  On success set *clus (first data cluster). */
static int dir_lookup(u32 start, const char *want11, int dir_only,
		      u32 *clus, u32 *size)
{
	u32 c = start;
	static u8 dbuf[64 * 1024];
	for (;;) {
		if (read_clus(c, dbuf))
			return -1;
		for (unsigned off = 0; off + 32 <= g_spc * g_bps;
		     off += 32) {
			struct dirent *d = (struct dirent *)(dbuf + off);
			if (d->name[0] == 0x00)
				return -1;          /* end of directory */
			if (d->name[0] == 0xE5)
				continue;
			if (d->attr == 0x0F)      /* LFN fragment: skip */
				continue;
			if (memcmp(d->name, want11, 11)) {
						continue;
			}
			if (getenv("FATREAD_TRACE"))
				fprintf(stderr, "   MATCH '%s' attr %02x\n", (char *)d->name, d->attr);
			if (dir_only && !(d->attr & 0x10))
				continue;
			*clus = d->cluslo & 0xFFFF;
			*size = d->size;
			return 0;
		}
		{
			u32 nc;
			if (fat_next(c, &nc) || nc < 2 || nc >= 0x0FFFFFF7)
				return -1;
			c = nc;
		}
	}
}

/* Turn "System/Library/Kernels/kernel.development" into 11-byte 8.3 names. */
static int to_83(const char *comp, char out[12])
{
	const char *dot = strrchr(comp, '.');
	int blen = dot ? (int)(dot - comp) : (int)strlen(comp);
	int elen = dot ? (int)strlen(dot + 1) : 0;
	/*
	 * The image generator uses plain 8.3 with SPACE padding and no
	 * tilde-numbering, so "kernel.development" is stored as
	 * "KERNEL  DEV" -- the first 8 bytes of the base and the first 3 of
	 * the extension, space padded.  Truncate the extension to match.
	 */
	if (blen > 8)
		return -1;
	if (elen > 3)                 /* this image truncates rather than tildes */
		elen = 3;
	for (int i = 0; i < 8; i++)
		out[i] = ' ';
	for (int i = 0; i < 3; i++)
		out[8 + i] = ' ';
	for (int i = 0; i < blen; i++) {
		char ch = comp[i];
		if (ch >= 'a' && ch <= 'z')
			ch = (char)(ch - 32);
		out[i] = ch;
	}
	if (dot)
		for (int i = 1; i <= elen; i++) {
			char ch = dot[i];
			if (ch >= 'a' && ch <= 'z')
				ch = (char)(ch - 32);
			out[8 + i - 1] = ch;
		}
	out[11] = 0;
	return 0;
}

static int find_file(u32 root, const char *path, u32 *clus, u32 *size)
{
	char comp[64], want[12];
	const char *p = path;
	u32 cur = root;

	for (;;) {
		int n = 0, last;
		while (*p && *p != '/' && n < (int)sizeof(comp) - 1)
			comp[n++] = *p++;
		comp[n] = 0;
		if (!n)
			return -1;
		last = (*p == 0);
		if (*p == '/')
			p++;
		if (to_83(comp, want)) return -1;
		if (dir_lookup(cur, want, !last, clus, size))
			return -1;
		if (last)
			return 0;
		cur = *clus;
	}
}

int main(int argc, char **argv)
{
	struct bpb b;
	u64 plba, pcount, part_off;
	u32 c, size, done = 0;
	FILE *out;

	if (argc != 4) {
		fprintf(stderr, "usage: %s <image> <path> <out>\n", argv[0]);
		return 2;
	}
	g_img = fopen(argv[1], "rb");
	if (!g_img) { perror("open image"); return 1; }

	if (gpt_partition(NULL, &plba, &pcount)) {
		fprintf(stderr, "no ESP in GPT\n");
		return 1;
	}
	part_off = plba * 512;
	printf("ESP: lba %llu (%llu sectors)\n",
	       (unsigned long long)plba, (unsigned long long)pcount);

	if (rd(part_off, &b, sizeof(b)) || b.bps != 512) {
		fprintf(stderr, "not a 512b/sector FAT volume\n");
		return 1;
	}
	g_spf = b.spf;
	g_bps = b.bps;
	g_spc = b.spc;
	g_fat0 = (u64)b.rsvd * b.bps;
	g_data = g_fat0 + (u64)b.nfat * b.spf * b.bps;
	g_part = part_off;
	printf("FAT32: bps %u spc %u spf %u rootclus %u\n",
	       b.bps, b.spc, b.spf, b.rootclus);

	if (find_file(b.rootclus, argv[2], &c, &size)) {
		fprintf(stderr, "file not found: %s\n", argv[2]);
		return 1;
	}
	printf("found %s: cluster %u size %u\n", argv[2], c, size);

	out = fopen(argv[3], "wb");
	if (!out) { perror("open out"); return 1; }
	for (;;) {
		u8 buf[64 * 1024];
		size_t want = size - done;
		if (want > sizeof(buf))
			want = sizeof(buf);
		if (!want)
			break;
		if (rd(g_part + clus_off(c), buf, want)) {
			fprintf(stderr, "read error at %u: c=%u off=%llu want=%zu\n",
			        done, c, (unsigned long long)(g_part + clus_off(c)), want);
			return 1;
		}
		if (fwrite(buf, 1, want, out) != want)
			return 1;
		done += (u32)want;
		if (done >= size)
			break;
		/*
		 * A chunk spans however many clusters it covers, so the FAT chain
		 * must be advanced once per cluster consumed, not once per chunk.
		 * Getting this wrong reads the right bytes from the wrong place:
		 * the first chunk matches and everything after it is shifted.
		 */
		{
			u32 step = (u32)(want / ((size_t)g_spc * g_bps));
			while (step--) {
				u32 nx = 0;
				if (fat_next(c, &nx)) {
					fprintf(stderr, "fat_next(%u) failed at done=%u\n",
					        c, done);
					return 1;
				}
				c = nx;
			}
		}
	}
	fclose(out);
	printf("wrote %u bytes to %s\n", done, argv[3]);
	return 0;
}
