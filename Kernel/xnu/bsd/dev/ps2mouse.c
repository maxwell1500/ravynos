/*
 * Copyright (c) 2026 ravynOS Project. All rights reserved.
 *
 * /dev/mouse (and /dev/psm0) -- PS/2 mouse character device driver.
 *
 * Communicates with the standard x86 i8042 keyboard/aux controller on
 * ports 0x60 (data) and 0x64 (command/status). Provides standard 3-byte
 * PS/2 mouse motion and button packets to userspace (e.g. WindowServer).
 */
#include <sys/param.h>
#include <sys/systm.h>
#include <sys/conf.h>
#include <sys/errno.h>
#include <sys/fcntl.h>
#include <sys/ioctl.h>
#include <sys/tty.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/uio_internal.h>
#include <sys/proc_internal.h>
#include <kern/locks.h>
#include <miscfs/devfs/devfs.h>
#include <pexpert/pexpert.h>

extern void IODelay(unsigned int microseconds);
extern void ps2mouse_init(void);

#define I8042_DATA_PORT    0x60
#define I8042_CMD_PORT     0x64

#define I8042_STATUS_OUTBUF_FULL 0x01
#define I8042_STATUS_INBUF_FULL  0x02
#define I8042_STATUS_AUX_DATA    0x20

#define I8042_CMD_READ_CONFIG    0x20
#define I8042_CMD_WRITE_CONFIG   0x60
#define I8042_CMD_ENABLE_AUX     0xa8
#define I8042_CMD_WRITE_AUX      0xd4

#define MOUSE_CMD_RESET          0xff
#define MOUSE_CMD_SET_DEFAULTS   0xf6
#define MOUSE_CMD_ENABLE_STREAM  0xf4
#define MOUSE_CMD_DISABLE_STREAM 0xf5

#define MOUSE_RING_SIZE 1024

static inline uint8_t
inb_port(uint16_t port)
{
	uint8_t data;
	__asm__ volatile ("inb %1, %0" : "=a" (data) : "Nd" (port));
	return data;
}

static inline void
outb_port(uint16_t port, uint8_t data)
{
	__asm__ volatile ("outb %0, %1" : : "a" (data), "Nd" (port));
}

static inline void
ps2_delay(void)
{
	IODelay(50);
}

static inline void
ps2_wait_write(void)
{
	int timeout = 50000;
	while ((inb_port(I8042_CMD_PORT) & I8042_STATUS_INBUF_FULL) && --timeout) {
		ps2_delay();
	}
}

static inline boolean_t
ps2_wait_read(void)
{
	int timeout = 50000;
	while (!(inb_port(I8042_CMD_PORT) & I8042_STATUS_OUTBUF_FULL) && --timeout) {
		ps2_delay();
	}
	return (timeout > 0);
}

static void
ps2_write_cmd(uint8_t cmd)
{
	ps2_wait_write();
	outb_port(I8042_CMD_PORT, cmd);
}

static void
ps2_write_data(uint8_t data)
{
	ps2_wait_write();
	outb_port(I8042_DATA_PORT, data);
}

static uint8_t
ps2_read_data(void)
{
	if (!ps2_wait_read()) {
		return 0;
	}
	return inb_port(I8042_DATA_PORT);
}

static void
ps2_write_aux(uint8_t data)
{
	ps2_write_cmd(I8042_CMD_WRITE_AUX);
	ps2_write_data(data);
}

/* Mouse ring buffer state */
static uint8_t   mouse_ring[MOUSE_RING_SIZE];
static uint32_t  mouse_head = 0;
static uint32_t  mouse_tail = 0;
static lck_mtx_t mouse_lock;
static LCK_GRP_DECLARE(mouse_lck_grp, "ps2mouse");
static int       ps2mouse_major = -1;
static boolean_t ps2mouse_initialized = FALSE;

static void
ps2mouse_drain_hardware(void)
{
	/* Drain any pending mouse bytes from the i8042 controller into ring */
	int count = 64;
	while (count-- > 0) {
		uint8_t status = inb_port(I8042_CMD_PORT);
		if ((status & (I8042_STATUS_OUTBUF_FULL | I8042_STATUS_AUX_DATA)) ==
		    (I8042_STATUS_OUTBUF_FULL | I8042_STATUS_AUX_DATA)) {
			uint8_t byte = inb_port(I8042_DATA_PORT);
			uint32_t next_head = (mouse_head + 1) % MOUSE_RING_SIZE;
			if (next_head != mouse_tail) {
				mouse_ring[mouse_head] = byte;
				mouse_head = next_head;
			}
		} else {
			break;
		}
	}
}

static int
ps2mouse_open(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	lck_mtx_lock(&mouse_lock);

	/* Clear stale data from ring */
	mouse_head = 0;
	mouse_tail = 0;

	/* Flush any garbage currently in the i8042 buffer */
	while (inb_port(I8042_CMD_PORT) & I8042_STATUS_OUTBUF_FULL) {
		ps2_delay();
		inb_port(I8042_DATA_PORT);
		ps2_delay();
	}

	/* 1. Enable auxiliary device (mouse) */
	ps2_write_cmd(I8042_CMD_ENABLE_AUX);

	/* 2. Read controller configuration byte */
	ps2_write_cmd(I8042_CMD_READ_CONFIG);
	uint8_t cb = ps2_read_data();

	/* Enable aux interrupts (bit 1) and enable aux clock (clear bit 5) */
	cb |= 0x02;
	cb &= ~0x20;

	/* 3. Write back controller configuration byte */
	ps2_write_cmd(I8042_CMD_WRITE_CONFIG);
	ps2_write_data(cb);

	/* 4. Set default sampling rate and resolution */
	ps2_write_aux(MOUSE_CMD_SET_DEFAULTS);
	(void)ps2_read_data(); /* ACK 0xFA */

	/* 5. Enable data reporting (streaming mode) */
	ps2_write_aux(MOUSE_CMD_ENABLE_STREAM);
	(void)ps2_read_data(); /* ACK 0xFA */

	printf("ps2mouse: opened and streaming enabled\n");

	lck_mtx_unlock(&mouse_lock);
	return 0;
}

static int
ps2mouse_close(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	lck_mtx_lock(&mouse_lock);
	/* Disable data reporting */
	ps2_write_aux(MOUSE_CMD_DISABLE_STREAM);
	(void)ps2_read_data();
	lck_mtx_unlock(&mouse_lock);
	return 0;
}

static int
ps2mouse_read(__unused dev_t dev, struct uio *uio, __unused int ioflag)
{
	lck_mtx_lock(&mouse_lock);

	/* Drain hardware port */
	ps2mouse_drain_hardware();

	size_t requested = (size_t)uio_resid(uio);
	if (requested == 0) {
		lck_mtx_unlock(&mouse_lock);
		return 0;
	}

	/* Check available bytes in ring */
	size_t available;
	if (mouse_head >= mouse_tail) {
		available = mouse_head - mouse_tail;
	} else {
		available = MOUSE_RING_SIZE - mouse_tail + mouse_head;
	}

	if (available == 0) {
		lck_mtx_unlock(&mouse_lock);
		return 0; /* Non-blocking EOF / no data right now */
	}

	size_t to_read = MIN(requested, available);
	uint8_t temp_buf[256];
	size_t chunk = MIN(to_read, sizeof(temp_buf));

	for (size_t i = 0; i < chunk; i++) {
		temp_buf[i] = mouse_ring[mouse_tail];
		mouse_tail = (mouse_tail + 1) % MOUSE_RING_SIZE;
	}

	lck_mtx_unlock(&mouse_lock);

	return uiomove((caddr_t)temp_buf, (int)chunk, uio);
}

static int
ps2mouse_select(__unused dev_t dev, int which, __unused void *wql, __unused struct proc *p)
{
	if (which != FREAD) {
		return 0;
	}

	lck_mtx_lock(&mouse_lock);
	ps2mouse_drain_hardware();

	int ready = (mouse_head != mouse_tail) ? 1 : 0;
	lck_mtx_unlock(&mouse_lock);

	return ready;
}

static int
ps2mouse_ioctl(__unused dev_t dev, __unused u_long cmd, __unused caddr_t data, __unused int flag, __unused struct proc *p)
{
	return ENOTTY;
}

static const struct cdevsw ps2mouse_cdevsw = {
	.d_open       = ps2mouse_open,
	.d_close      = ps2mouse_close,
	.d_read       = ps2mouse_read,
	.d_write      = eno_rdwrt,
	.d_ioctl      = ps2mouse_ioctl,
	.d_stop       = eno_stop,
	.d_reset      = eno_reset,
	.d_ttys       = NULL,
	.d_select     = ps2mouse_select,
	.d_mmap       = eno_mmap,
	.d_strategy   = eno_strat,
	.d_reserved_1 = eno_getc,
	.d_reserved_2 = eno_putc,
};

void
ps2mouse_init(void)
{
	int ret;

	if (ps2mouse_initialized) {
		return;
	}

	lck_mtx_init(&mouse_lock, &mouse_lck_grp, LCK_ATTR_NULL);

	ret = cdevsw_add(-1, &ps2mouse_cdevsw);
	if (ret < 0) {
		printf("ps2mouse: cdevsw_add failed: %d\n", ret);
		return;
	}
	ps2mouse_major = ret;

	if (devfs_make_node(makedev(ps2mouse_major, 0), DEVFS_CHAR,
	    UID_ROOT, GID_WHEEL, 0666, "mouse") == NULL) {
		printf("ps2mouse: devfs_make_node failed for 'mouse'\n");
		return;
	}

	(void)devfs_make_node(makedev(ps2mouse_major, 0), DEVFS_CHAR,
	    UID_ROOT, GID_WHEEL, 0666, "psm0");

	ps2mouse_initialized = TRUE;
	printf("ps2mouse: registered character device major %d (/dev/mouse, /dev/psm0)\n", ps2mouse_major);
}
