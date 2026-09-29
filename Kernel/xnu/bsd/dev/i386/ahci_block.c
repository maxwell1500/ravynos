/*
 * Minimal in-kernel AHCI block driver for QEMU q35 (Port 0 only).
 *
 * Exposes the AHCI Port 0 disk through the bdevsw so it can serve as
 * the root device (disk0s1, LBA 2048) for msdosfs root mounting.
 */

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/conf.h>
#include <sys/buf.h>
#include <sys/disk.h>
#include <i386/hw_defs.h>
#include <architecture/i386/pio.h>
#include <i386/machine_routines.h>
#include <i386/pmap.h>
#include <machine/string.h>
/*
 * ml_io_map() / kvtophys() are declared in <i386/machine_routines.h> and
 * <i386/pmap.h> only under MACH_KERNEL_PRIVATE, which BSD files are not
 * built with.  Declare them locally instead; both are exported by the
 * kernel (verified in the linked image).
 */
extern vm_offset_t ml_io_map(vm_offset_t phys_addr, vm_size_t size);
extern addr64_t kvtophys(vm_offset_t addr);

static int ahci_major = -1;
static vm_offset_t ahci_abar_virt = 0;

static uint8_t __attribute__((aligned(4096))) ahci_bounce[65536];
static uint64_t ahci_bounce_phys = 0;
static uint8_t __attribute__((aligned(1024))) ahci_clb[1024];
static uint8_t __attribute__((aligned(256))) ahci_fb[256];
static uint8_t __attribute__((aligned(128))) ahci_ct[512];
static uint64_t ahci_clb_phys = 0, ahci_fb_phys = 0, ahci_ct_phys = 0;

static int ahci_transfer_sectors(uint64_t lba, uint32_t sec_count, void *buf, int is_write);
static void ahci_strategy(struct buf *bp);

static int
ahci_open(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	return 0;
}

static int
ahci_close(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	return 0;
}

static int
ahci_ioctl(dev_t dev, u_long cmd, caddr_t data,
    __unused int fflag, __unused struct proc *p)
{
	int d = minor(dev);
	uint32_t *f = (uint32_t *)data;
	uint64_t *o = (uint64_t *)data;

	switch (cmd) {
	case DKIOCGETBLOCKSIZE:
		*f = 512;
		return 0;

	case DKIOCSETBLOCKSIZE:
		if (*f < 512) {
			return EINVAL;
		}
		return 0;

	case DKIOCISWRITABLE:
		*f = 1;
		return 0;

	case DKIOCGETBLOCKCOUNT:
		/* Partition 1 (disk0s1) has 1044480 sectors (LBA 2048 to 1046527), disk0 has 1048576 sectors */
		if (d == 1) {
			*o = 1044480;
		} else {
			*o = 1048576;
		}
		return 0;

	case DKIOCGETMAXBLOCKCOUNTREAD:
	case DKIOCGETMAXBLOCKCOUNTWRITE:
	case DKIOCGETMAXSEGMENTCOUNTREAD:
	case DKIOCGETMAXSEGMENTCOUNTWRITE:
		*o = 128;
		return 0;

	case DKIOCGETTHROTTLEMASK:
		*f = 0;
		return 0;

	case DKIOCISSOLIDSTATE:
		*f = 0;
		return 0;

	default:
		return ENOTTY;
	}
}

static int
ahci_psize(__unused dev_t dev)
{
	return 512;
}

struct bdevsw ahci_bdevsw = {
	.d_open = ahci_open,
	.d_close = ahci_close,
	.d_strategy = ahci_strategy,
	.d_ioctl = ahci_ioctl,
	.d_dump = eno_dump,
	.d_psize = ahci_psize,
	.d_type = D_DISK
};

int
ahci_init(void)
{
	volatile uint32_t *ghc;
	volatile uint32_t *port;
	uint32_t bar5;
	uint32_t cmd;
	uint32_t ssts;
	uint32_t pxcmd;
	int i;

	/* Read BAR5 at PCI 00:1f.2 */
	outl(cfgAdr, 0x80000000 | (0 << 16) | (31 << 11) | (2 << 8) | 0x24);
	bar5 = inl(cfgDat) & ~0xFU;
	if (bar5 == 0 || bar5 == 0xfffffff0) {
		printf("AHCI: no BAR5 at 00:1f.2\n");
		return -1;
	}

	/* Enable Bus Master & Memory Space */
	outl(cfgAdr, 0x80000000 | (0 << 16) | (31 << 11) | (2 << 8) | 0x04);
	cmd = inl(cfgDat);
	outl(cfgDat, cmd | 0x06);

	/* Map ABAR */
	ahci_abar_virt = ml_io_map((vm_offset_t)bar5, 4096);
	if (!ahci_abar_virt) {
		printf("AHCI: ml_io_map failed for BAR5 0x%x\n", bar5);
		return -1;
	}

	/* Enable AHCI in GHC (offset 0x04) */
	ghc = (volatile uint32_t *)(ahci_abar_virt + 0x04);
	*ghc |= (1U << 31);

	/* Port 0 at ahci_abar_virt + 0x100; check PxSSTS (offset 0x28) */
	ssts = *(volatile uint32_t *)(ahci_abar_virt + 0x128);
	if ((ssts & 0x0f) != 3) {
		printf("AHCI: Port 0 no device (SSTS=0x%x)\n", ssts);
		return -1;
	}

	/* Physical addresses of DMA buffers */
	ahci_bounce_phys = kvtophys((vm_offset_t)ahci_bounce);
	ahci_clb_phys = kvtophys((vm_offset_t)ahci_clb);
	ahci_fb_phys = kvtophys((vm_offset_t)ahci_fb);
	ahci_ct_phys = kvtophys((vm_offset_t)ahci_ct);

	port = (volatile uint32_t *)(ahci_abar_virt + 0x100);

	/* Stop Port 0: clear PxCMD.ST (bit 0) and PxCMD.FRE (bit 4) */
	pxcmd = port[0x18 / 4];
	pxcmd &= ~((1U << 0) | (1U << 4));
	port[0x18 / 4] = pxcmd;

	/* Spin until PxCMD.CR (bit 15) and PxCMD.FR (bit 14) are 0 */
	for (i = 0; i < 1000000; i++) {
		pxcmd = port[0x18 / 4];
		if ((pxcmd & ((1U << 15) | (1U << 14))) == 0) {
			break;
		}
	}

	/* Set PxCLB / PxCLBU */
	port[0x00 / 4] = (uint32_t)ahci_clb_phys;
	port[0x04 / 4] = (uint32_t)(ahci_clb_phys >> 32);

	/* Set PxFB / PxFBU */
	port[0x08 / 4] = (uint32_t)ahci_fb_phys;
	port[0x0C / 4] = (uint32_t)(ahci_fb_phys >> 32);

	/* Clear PxSERR (offset 0x30) and PxIS (offset 0x10) */
	port[0x30 / 4] = 0xFFFFFFFF;
	port[0x10 / 4] = 0xFFFFFFFF;

	/* Start Port 0: set PxCMD.FRE (bit 4), then PxCMD.ST (bit 0) */
	pxcmd = port[0x18 / 4];
	pxcmd |= (1U << 4);
	port[0x18 / 4] = pxcmd;
	pxcmd = port[0x18 / 4];
	pxcmd |= (1U << 0);
	port[0x18 / 4] = pxcmd;

	/* Register bdevsw */
	ahci_major = bdevsw_add(-1, &ahci_bdevsw);
	printf("AHCI: Port 0 ready, bdevsw registered at major %d\n", ahci_major);
	return ahci_major;
}

dev_t
ahci_get_rootdev(void)
{
	if (ahci_major < 0) {
		return NODEV;
	}
	return makedev(ahci_major, 1); /* minor 1 = disk0s1 */
}

static int
ahci_transfer_sectors(uint64_t lba, uint32_t sec_count, void *buf, int is_write)
{
	uint64_t cur_lba = lba;
	uint32_t offset = 0;

	while (sec_count > 0) {
		uint32_t chunk = sec_count > 128 ? 128 : sec_count;
		volatile uint32_t *prdt;
		volatile uint32_t *cmd_hdr;
		volatile uint32_t *tfd;
		uint32_t tfd_val;
		int timeout;

		if (is_write) {
			memcpy(ahci_bounce, (const uint8_t *)buf + offset, chunk * 512);
		}

		/* Set PRDT at ahci_ct + 0x80 */
		prdt = (volatile uint32_t *)(ahci_ct + 0x80);
		prdt[0] = (uint32_t)ahci_bounce_phys;
		prdt[1] = (uint32_t)(ahci_bounce_phys >> 32);
		prdt[2] = 0;
		prdt[3] = (chunk * 512) - 1; /* DBC = count - 1! */

		/* Set Command FIS at ahci_ct */
		memset(ahci_ct, 0, 64);
		ahci_ct[0] = 0x27; /* H2D */
		ahci_ct[1] = 0x80; /* Command bit */
		ahci_ct[2] = is_write ? 0x35 : 0x25; /* WRITE DMA EXT or READ DMA EXT */
		ahci_ct[4] = (uint8_t)cur_lba;
		ahci_ct[5] = (uint8_t)(cur_lba >> 8);
		ahci_ct[6] = (uint8_t)(cur_lba >> 16);
		ahci_ct[7] = 0xe0;
		ahci_ct[8] = (uint8_t)(cur_lba >> 24);
		ahci_ct[9] = (uint8_t)(cur_lba >> 32);
		ahci_ct[10] = (uint8_t)(cur_lba >> 40);
		ahci_ct[12] = (uint8_t)chunk;
		ahci_ct[13] = (uint8_t)(chunk >> 8);

		/* Set Command Header 0 at ahci_clb */
		cmd_hdr = (volatile uint32_t *)ahci_clb;
		cmd_hdr[0] = 5 | (is_write ? (1 << 6) : 0) | (1 << 16); /* CFL=5, W-bit, PRDTL=1! */
		cmd_hdr[1] = 0;                                          /* PRDBC = 0 */
		cmd_hdr[2] = (uint32_t)ahci_ct_phys;
		cmd_hdr[3] = (uint32_t)(ahci_ct_phys >> 32);

		/* Wait for PxTFD (offset 0x20) (BSY | DRQ) to clear */
		tfd = (volatile uint32_t *)(ahci_abar_virt + 0x120);
		for (timeout = 0; timeout < 10000000; timeout++) {
			if ((*tfd & 0x88) == 0) {
				break;
			}
		}

		/* Clear PxIS (offset 0x10) */
		*(volatile uint32_t *)(ahci_abar_virt + 0x110) = 0xFFFFFFFF;

		/* Issue command: PxCI = 1 */
		*(volatile uint32_t *)(ahci_abar_virt + 0x138) = 1;

		/* Poll PxCI & 1 until 0 */
		for (timeout = 0; timeout < 10000000; timeout++) {
			if ((*(volatile uint32_t *)(ahci_abar_virt + 0x138) & 1) == 0) {
				break;
			}
		}
		if (timeout >= 10000000) {
			printf("AHCI: command timeout (lba %llu)\n", cur_lba);
			return EIO;
		}

		/* Check error bit in PxTFD */
		tfd_val = *tfd;
		if (tfd_val & 1) {
			printf("AHCI: command error TFD=0x%x (lba %llu)\n", tfd_val, cur_lba);
			return EIO;
		}

		if (!is_write) {
			memcpy((uint8_t *)buf + offset, ahci_bounce, chunk * 512);
		}

		cur_lba += chunk;
		offset += chunk * 512;
		sec_count -= chunk;
	}

	return 0;
}

static void
ahci_strategy(struct buf *bp)
{
	int d = minor(buf_device(bp));
	uint64_t blkno = buf_blkno(bp);
	uint32_t byte_count = buf_count(bp);
	uint32_t sec_count = (byte_count + 511) / 512;
	uint64_t lba = blkno;
	caddr_t vaddr;
	int is_write;
	int err;

	if (d == 1) {
		lba += 2048; /* Partition 1 is disk0s1 at LBA 2048! */
	}

	if (buf_map(bp, &vaddr)) {
		buf_seterror(bp, EIO);
		buf_biodone(bp);
		return;
	}

	is_write = (buf_flags(bp) & B_READ) ? 0 : 1;
	err = ahci_transfer_sectors(lba, sec_count, (void *)vaddr, is_write);
	buf_unmap(bp);

	if (err) {
		buf_seterror(bp, EIO);
	} else {
		buf_setresid(bp, 0);
	}
	buf_biodone(bp);
}
