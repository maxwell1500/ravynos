/*
 * Copyright (c) 2026 ravynOS Project. All rights reserved.
 *
 * /dev/mouse (and /dev/psm0) -- PS/2 mouse character device driver.
 *
 * Communicates with the standard x86 i8042 keyboard/aux controller on
 * ports 0x60 (data) and 0x64 (command/status). Provides PS/2 mouse motion and
 * button packets to userspace (e.g. WindowServer) as fixed 4-byte records:
 *
 *     flags, dx, dy, dz
 *
 * The device is asked for IntelliMouse mode on open (the documented
 * sample-rate magic sequence); when the mouse answers with device id 3 or 4
 * the fourth byte carries the wheel, otherwise dz is always 0 and the wire
 * format is still 4 bytes so readers never have to care which mouse is
 * attached.
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
#define MOUSE_CMD_SET_SAMPLE_RATE 0xf3
#define MOUSE_CMD_GET_ID         0xf2

/* flags, dx, dy, dz -- see the file comment. */
#define MOUSE_RECORD_SIZE 4
#define MOUSE_RING_SIZE (1024 * MOUSE_RECORD_SIZE)

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

/* Set by ps2mouse_open when the device answered the IntelliMouse magic. */
static boolean_t mouse_wheel = FALSE;
/* Packet being assembled from the controller's byte stream. */
static uint8_t   mouse_pkt[MOUSE_RECORD_SIZE];
static int       mouse_pktlen;

/* Send one byte to the aux device and report whether it was ACKed (0xfa). */
static int
ps2_write_aux_acked(uint8_t cmd)
{
	ps2_write_aux(cmd);
	return ps2_read_data() == 0xfa;
}

/* Append one normalized 4-byte record to the ring.  */

static void
ps2mouse_push_record(const uint8_t *pkt)
{
	uint8_t rec[MOUSE_RECORD_SIZE];
	uint32_t i;

	rec[0] = pkt[0];
	rec[1] = pkt[1];
	rec[2] = pkt[2];
	if (mouse_wheel) {
		/* The wheel is a 4-bit two's complement field in bits 0-3 with its
		 * sign duplicated in bit 3; extend it to a signed byte. */
		rec[3] = (uint8_t)((pkt[3] & 0x08) ? (pkt[3] | 0x80) : pkt[3]);
	} else {
		rec[3] = 0;
	}

	for (i = 0; i < MOUSE_RECORD_SIZE; i++) {
		uint32_t next_head = (mouse_head + 1) % MOUSE_RING_SIZE;
		if (next_head == mouse_tail)
			return;                 /* ring full: drop the record */
		mouse_ring[mouse_head] = rec[i];
		mouse_head = next_head;
	}
}

static void
ps2mouse_drain_hardware(void)
{
	/* Drain any pending mouse bytes from the i8042 controller and assemble
	 * them into records.  A packet always starts with bit 3 set in its first
	 * byte, which is how a half packet left over from a previous read is
	 * discarded. */
	int count = 64;
	while (count-- > 0) {
		uint8_t status = inb_port(I8042_CMD_PORT);
		if ((status & (I8042_STATUS_OUTBUF_FULL | I8042_STATUS_AUX_DATA)) ==
		    (I8042_STATUS_OUTBUF_FULL | I8042_STATUS_AUX_DATA)) {
			uint8_t byte = inb_port(I8042_DATA_PORT);
			int pkt_size = mouse_wheel ? 4 : 3;

			if (mouse_pktlen == 0 && !(byte & 0x08))
				continue;       /* not a packet start: resync */
			mouse_pkt[mouse_pktlen++] = byte;
			if (mouse_pktlen == pkt_size) {
				ps2mouse_push_record(mouse_pkt);
				mouse_pktlen = 0;
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

	/* 5. Ask for IntelliMouse mode: the 200/100/80 sample-rate sequence is
	 * the documented handshake, and the id read back says whether it took.
	 * Device id 3 is a wheel, 4 adds the 5th button. */
	ps2_write_aux_acked(MOUSE_CMD_SET_SAMPLE_RATE);
	ps2_write_aux_acked(200);
	ps2_write_aux_acked(MOUSE_CMD_SET_SAMPLE_RATE);
	ps2_write_aux_acked(100);
	ps2_write_aux_acked(MOUSE_CMD_SET_SAMPLE_RATE);
	ps2_write_aux_acked(80);
	/* GET_ID is answered with an ACK *then* the id byte, so the first read
	 * is the ACK (measured: reading once returned 0xfa and reported
	 * "device id 250").  Skip ACKs and take the first other byte. */
	ps2_write_aux(MOUSE_CMD_GET_ID);
	int devid = 0;
	for (int i = 0; i < 4; i++) {
		int b = ps2_read_data();
		if (b != 0xfa) {
			devid = b;
			break;
		}
	}
	mouse_wheel = (devid == 0x03 || devid == 0x04);
	mouse_pktlen = 0;
	printf("ps2mouse: device id %d (%s)\n", devid,
	       mouse_wheel ? "IntelliMouse, 4-byte records with wheel"
	                   : "3-byte, wheel absent");

	/* 6. Enable data reporting (streaming mode) */
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
	size_t chunk;

	/* Never split a record: a reader that got half of one would misread the
	 * next packet's flags as its own. */
	to_read -= to_read % MOUSE_RECORD_SIZE;
	if (to_read == 0) {
		lck_mtx_unlock(&mouse_lock);
		return 0;
	}
	chunk = MIN(to_read, sizeof(temp_buf));
	chunk -= chunk % MOUSE_RECORD_SIZE;
	if (chunk == 0) {
		lck_mtx_unlock(&mouse_lock);
		return 0;
	}

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
