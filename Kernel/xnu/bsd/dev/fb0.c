/*
 * Copyright (c) 2024 Zoe Knox <zoe@ravynsoft.com>
 * Copyright (c) 1994 The Regents of the University of California.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this file
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its affiliates.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
 */

/*
 * /dev/fb0 -- the BSD frame buffer device.
 *
 * Geometry comes from the boot-args Video struct, which the EFI loader fills
 * from the GOP linear framebuffer, via PE_state.video.  That is the same
 * information osfmk/console/video_console.c draws the boot logo with, so this
 * driver describes the memory that is physically being scanned out.
 *
 * mmap() support
 * --------------
 * XNU rejects mmap() of every character device (bsd/kern/kern_mman.c returns
 * ENODEV before ever consulting the cdevsw's d_mmap).  A frame buffer cannot be
 * avoided here, because WindowServer composites straight into scanout memory,
 * so this driver supplies the mapping the way the rest of XNU maps device
 * memory: with the osfmk device pager.
 *
 * device_pager_setup() builds a vm_object whose pages are physically the
 * framebuffer's own pages (device_pager_populate_object() installs each ppn
 * with vm_object_populate_with_private() -- no copy is ever made), then
 * mach_memory_object_memory_entry_64() makes a named entry for it and
 * mach_vm_map_kernel() enters that entry into the caller's address space.  The
 * result is a genuine MAP_SHARED alias of scanout memory: a user store lands in
 * the framebuffer, not in a copy of it.  This is the same sequence
 * osfmk/kern/exclaves_memory.c uses, and the same one IOKit uses for physical
 * IOMemoryDescriptors, so it needs no new VM code.
 *
 * The frames are wired up-front (device_pager_populate_object() faults them
 * into the object and marks them clean/device), so the first user store cannot
 * be preceded by a page-out that would discard the write.
 */

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/conf.h>
#include <sys/errno.h>
#include <sys/ioccom.h>
#include <sys/ioctl.h>
#include <sys/tty.h>
#include <sys/types.h>

#include <sys/fbio.h>               /* struct fbtype, FBIOGTYPE, ... */
#include <sys/consio.h>             /* VT_*, CONS_MOUSECTL, vtmode_t */

#include <sys/proc_internal.h>      /* struct proc's task field */
#include <sys/mman.h>               /* PROT_READ / PROT_WRITE */
#include <kern/locks.h>
#include <kern/task.h>
#include <miscfs/devfs/devfs.h>

#include <pexpert/pexpert.h>

#include <device/device_port.h>    /* DEVICE_PAGER_COHERENT */

#include <vm/vm_kern_xnu.h>
#include <vm/vm_iokit.h>
#include <vm/vm_memory_entry_xnu.h>
#include <vm/vm_protos.h>          /* device_pager_deallocate */
#include <vm/memory_types.h>       /* pulls in machine/memory_types.h */

#include <mach/mach_host.h>        /* mach_memory_object_memory_entry_64 */

#define FB0_MINOR       0
#define FB0_NODE        "fb0"

/*
 * The GOP framebuffer is MMIO, not RAM: it must not be cached, so writes made
 * through the mapping reach the scanner rather than sitting in a dirty line.
 */
#define FB0_CACHE_MODE  VM_WIMG_IO

/* Registers the cdevsw and the /dev/fb0 devfs node; called from bsd_init. */
extern void fb0_init(void);

/* Geometry is read once from PE_state.video and then immutable. */
static PE_Video        fb_video;
static int             fb_major = -1;
static boolean_t       fb_initialized = FALSE;
static lck_mtx_t       fb_lock;
static LCK_GRP_DECLARE(fb_lck_grp, "fb0");

/*
 * VT state.  ravynOS has a single console, so this is bookkeeping: the numbers
 * only have to be stable and monotonic, since WindowServer round-trips
 * VT_GETACTIVE / VT_OPENQRY / VT_ACTIVATE / VT_SETMODE and the restore path
 * depends on the values being echoed back faithfully.
 */
static int             fb_active_vt = 0;
static int             fb_next_vt = 0;
static struct vtmode   fb_vt_mode;

static int fb0_open(dev_t dev, int flags, int devtype, struct proc *p);
static int fb0_close(dev_t dev, int flags, int devtype, struct proc *p);
static int fb0_ioctl(dev_t dev, u_long cmd, caddr_t data, int flag,
    struct proc *p);
static int fb0_mmap(dev_t dev, uint64_t addr, uint64_t size, int prot,
    struct proc *p, uint64_t *ret_addr);

static const struct cdevsw fb0_cdevsw = {
	.d_open       = fb0_open,
	.d_close      = fb0_close,
	.d_read       = eno_rdwrt,
	.d_write      = eno_rdwrt,
	.d_ioctl      = fb0_ioctl,
	.d_stop       = eno_stop,
	.d_reset      = eno_reset,
	.d_ttys       = NULL,
	.d_select     = eno_select,
	.d_mmap       = fb0_mmap,
	.d_strategy   = eno_strat,
	.d_reserved_1 = eno_getc,
	.d_reserved_2 = eno_putc,
};

/* The size of the mapping, page rounded: that is all mmap() ever hands out. */
static vm_size_t
fb0_size(void)
{
	vm_size_t size;

	if (fb_video.v_length != 0) {
		size = (vm_size_t)fb_video.v_length;
	} else {
		size = (vm_size_t)fb_video.v_rowBytes * fb_video.v_height;
	}
	return round_page(size);
}

static int
fb0_open(__unused dev_t dev, int flags, __unused int devtype,
    __unused struct proc *p)
{
	/*
	 * mmap() must be able to install writable PTEs, so an O_RDONLY open
	 * cannot be mapped PROT_WRITE.  Reject that combination here rather
	 * than failing the fault later.
	 */
	if ((flags & FWRITE) == 0) {
		return EACCES;
	}
	return 0;
}

static int
fb0_close(__unused dev_t dev, __unused int flags, __unused int devtype,
    __unused struct proc *p)
{
	return 0;
}

/*
 * No read()/write().  The framebuffer is reached by mapping it, not by
 * reading it: physio() is a block-device path -- it needs a strategy
 * function and a buf -- and cannot serve raw memory.  WindowServer only ever
 * uses open()/ioctl()/mmap() on /dev/fb0.
 */

/*
 * Fill in an fbtype describing the boot framebuffer.
 */
static void
fb0_get_fbtype(struct fbtype *fb)
{
	bzero(fb, sizeof(*fb));

	/* The framebuffer is 32bpp BGRX, as set up by the GOP loader. */
	fb->fb_type      = FB_TYPE_ARGB_PIXELS;
	fb->fb_height    = (unsigned short)fb_video.v_height;
	fb->fb_width     = (unsigned short)fb_video.v_width;
	fb->fb_depth     = (unsigned short)fb_video.v_depth;
	fb->fb_memsize   = (unsigned int)fb0_size();
	fb->fb_linebytes = (unsigned int)fb_video.v_rowBytes;
	fb->fb_base      = (unsigned int)fb_video.v_baseAddr;
	fb->fb_sizex     = (unsigned int)fb_video.v_width;
	fb->fb_sizey     = (unsigned int)fb_video.v_height;
	fb->fb_vertinc   = 1;

	strlcpy(fb->fb_name, FB0_NODE, sizeof(fb->fb_name));
}

static int
fb0_ioctl(dev_t dev, u_long cmd, caddr_t data, __unused int flag,
    __unused struct proc *p)
{
	int error = 0;

	if (minor(dev) != FB0_MINOR) {
		return ENXIO;
	}

	lck_mtx_lock(&fb_lock);

	switch (cmd) {
	case FBIOGTYPE:
	case FBIOGDTYPE:
		fb0_get_fbtype((struct fbtype *)data);
		break;

	case FBIO_GETLINEWIDTH: {
		unsigned int *widthp = (unsigned int *)data;

		if (fb_video.v_rowBytes == 0) {
			error = ENXIO;
			break;
		}
		*widthp = (unsigned int)fb_video.v_rowBytes;
		break;
	}

	case FBIO_SETLINEWIDTH:
		/* Stride is a property of the mode, and there is one mode. */
		error = ENOTTY;
		break;

	/*
	 * Virtual terminal control.  There is a single console on ravynOS, so
	 * these do nothing beyond returning coherent numbers.
	 */
	case VT_OPENQRY: {
		int *vtnp = (int *)data;

		/* Hand out vt 1 and above; vt 0 is the boot console. */
		if (fb_next_vt < 1) {
			fb_next_vt = 1;
		}
		*vtnp = fb_next_vt;
		break;
	}

	case VT_ACTIVATE: {
		int vt = *(int *)data;

		if (vt < 0) {
			error = EINVAL;
			break;
		}
		if (vt > fb_next_vt) {
			fb_next_vt = vt;
		}
		fb_active_vt = vt;
		break;
	}

	case VT_GETACTIVE:
		*(int *)data = fb_active_vt;
		break;

	case VT_SETMODE:
		fb_vt_mode = *(struct vtmode *)data;
		break;

	case VT_GETSTATE: {
		struct vtinfo *vi = (struct vtinfo *)data;

		bzero(vi, sizeof(*vi));
		vi->vt_number = (unsigned short)fb_active_vt;
		vi->vt_mode   = (unsigned short)fb_vt_mode.mode;
		vi->vt_visible = 1;
		vi->vt_memseg = (unsigned int)fb_video.v_baseAddr;
		vi->vt_memsize = (unsigned int)fb0_size();
		vi->vt_row = (unsigned short)fb_video.v_height;
		vi->vt_col = (unsigned short)fb_video.v_width;
		break;
	}

	case CONS_MOUSECTL:
		/* No hardware cursor to hide; accept and ignore. */
		break;

	case FBIO_WAITFORVSYNC:
		break;

	case FIONBIO:
	case FIOASYNC:
		break;

	default:
		error = ENOTTY;
		break;
	}

	lck_mtx_unlock(&fb_lock);

	return error;
}

/*
 * fb0_mmap -- map the framebuffer into the calling process.
 *
 * Called from mmap_common() in bsd/kern/kern_mman.c once the vnode has been
 * resolved to this cdevsw; `addr' is the requested address (0 unless
 * MAP_FIXED), `size' is page-rounded, and on success the address the process
 * actually received is stored in *ret_addr.
 */
static int
fb0_mmap(dev_t dev, uint64_t addr, uint64_t size, int prot,
    struct proc *p, uint64_t *ret_addr)
{
	vm_map_t map;
	memory_object_t pager;
	ipc_port_t entry;
	vm_map_offset_ut map_addr;
	vm_offset_ut fb_size;
	vm_offset_t fb_base;
	vm_prot_t vm_prot;
	vm_offset_t off;
	kern_return_t kr;
	int error = 0;

	if (minor(dev) != FB0_MINOR) {
		return ENXIO;
	}

	if (p == NULL) {
		return EINVAL;
	}

	lck_mtx_lock(&fb_lock);
	fb_base = (vm_offset_t)fb_video.v_baseAddr;
	fb_size = (vm_offset_ut)fb0_size();
	lck_mtx_unlock(&fb_lock);

	/*
	 * PE_state.video is only meaningful when the loader found a GOP
	 * framebuffer.  Without one there is nothing to map, and saying so is
	 * far more useful than handing back a mapping of unrelated memory.
	 */
	if (fb_base == 0 || fb_size == 0) {
		return ENXIO;
	}

	/* Only memory that is really the framebuffer can be mapped. */
	if (size > (uint64_t)fb_size) {
		return EINVAL;
	}

	/*
	 * mmap_common() runs on the calling thread, so current_task() is the
	 * process being mapped -- the same map `p' would give.
	 */
	map = get_task_map(current_task());

	/*
	 * The mapping is scanout memory: uncached and write-through, so a
	 * user store reaches the scanner instead of lingering in a dirty line
	 * in this CPU's cache.  PROT_WRITE is mandatory -- there is nothing
	 * useful to map read-only -- but honour an explicit PROT_NONE.
	 */
	if ((prot & PROT_READ) && !(prot & PROT_WRITE)) {
		return EACCES;
	}
	vm_prot = VM_PROT_READ | VM_PROT_WRITE | FB0_CACHE_MODE;

	pager = device_pager_setup(MEMORY_OBJECT_NULL, (uintptr_t)0,
	    fb_size, DEVICE_PAGER_COHERENT);
	if (pager == MEMORY_OBJECT_NULL) {
		return ENOMEM;
	}

	/*
	 * Install the framebuffer's own physical pages, one frame at a time.
	 * vm_object_populate_with_private() makes these the object's pages
	 * directly -- no copy is ever made -- so the mapping aliases scanout
	 * memory and a user store lands in the framebuffer.
	 */
	for (off = 0; off < fb_size; off += (vm_offset_t)PAGE_SIZE) {
		kr = device_pager_populate_object(pager, off,
		    (ppnum_t)atop(fb_base + off), (vm_size_t)PAGE_SIZE);
		if (kr != KERN_SUCCESS) {
			device_pager_deallocate(pager);
			return ENOMEM;
		}
	}

	entry = IPC_PORT_NULL;
	kr = mach_memory_object_memory_entry_64((host_t)1, /* internal */ FALSE,
	    (memory_object_size_ut)fb_size, (vm_prot_ut)vm_prot, pager, &entry);
	if (kr != KERN_SUCCESS) {
		device_pager_deallocate(pager);
		return ENOMEM;
	}

	map_addr = (vm_map_offset_ut)addr;

	kr = mach_vm_map_kernel(map, &map_addr, (vm_map_size_ut)size,
	    (vm_map_offset_ut)0, VM_MAP_KERNEL_FLAGS_ANYWHERE(), entry,
	    (vm_object_offset_ut)0, /* copy */ FALSE,
	    (vm_prot_ut)vm_prot, (vm_prot_ut)vm_prot, VM_INHERIT_SHARE);

	mach_memory_entry_port_release(entry);

	/*
	 * Drop our reference.  The mapping holds the object alive for as long
	 * as it exists; these are the device's own pages, which VM never
	 * returns to the free list.
	 */
	device_pager_deallocate(pager);

	switch (kr) {
	case KERN_SUCCESS:
		*ret_addr = (uint64_t)map_addr;
		break;
	case KERN_PROTECTION_FAILURE:
		error = EACCES;
		break;
	case KERN_NO_SPACE:
	case KERN_INVALID_ADDRESS:
	case KERN_RESOURCE_SHORTAGE:
	error = ENOMEM;
		break;
	default:
		error = EINVAL;
		break;
	}

	return error;
}

void
fb0_init(void)
{
	int ret;

	if (fb_initialized) {
		return;
	}

	lck_mtx_init(&fb_lock, &fb_lck_grp, LCK_ATTR_NULL);

	/*
	 * PE_state.video is filled in from the boot args by pe_init.c before
	 * bsd_init() runs, and describes the framebuffer the scanner is
	 * actually using.
	 */
	fb_video = PE_state.video;

	if (fb_video.v_baseAddr == 0 || fb_video.v_width == 0 ||
	    fb_video.v_height == 0) {
		/*
		 * No GOP framebuffer.  Still register the driver so that
		 * opening /dev/fb0 fails with ENXIO -- a specific error --
		 * rather than ENOENT from open().
		 */
		printf("fb0: no framebuffer in boot args\n");
	}

	ret = cdevsw_add(-1 /* allocate a major number */, &fb0_cdevsw);
	if (ret < 0) {
		panic("fb0: cdevsw_add failed: %d", ret);
	}
	fb_major = ret;

	if (devfs_make_node(makedev(fb_major, FB0_MINOR), DEVFS_CHAR,
	    UID_ROOT, GID_WINDOWSERVER, 0660, FB0_NODE) == NULL) {
		panic("fb0: devfs_make_node failed for '%s'", FB0_NODE);
	}

	fb_initialized = TRUE;

	printf("fb0: %lux%lu depth %lu stride %lu at 0x%lx\n",
	    fb_video.v_width, fb_video.v_height, fb_video.v_depth,
	    fb_video.v_rowBytes, fb_video.v_baseAddr);
}
