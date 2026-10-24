/*
 * Copyright (c) 2026 ravynOS Project. All rights reserved.
 *
 * /dev/keyboard (and /dev/kbd) -- PS/2 keyboard character device driver.
 *
 * Exports the raw AT scan-code stream (set 1, i8042 IRQ 1) to userspace so
 * the WindowServer can build NSEvents without libinput/xkbcommon.
 *
 * The bytes are delivered by the ApplePS2Controller kext, which already owns
 * the i8042 status/data ports: every keyboard byte it dispatches to the IOKit
 * keyboard driver is mirrored here through ps2keyboard_tap(). This driver
 * never touches the ports itself, so it cannot steal scan codes from the
 * in-kernel driver. Only if that kext is absent (no tap hook installed) does
 * it fall back to polling the controller directly.
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
extern void ps2keyboard_init(void);

#define I8042_DATA_PORT    0x60
#define I8042_CMD_PORT     0x64

#define I8042_STATUS_OUTBUF_FULL 0x01
#define I8042_STATUS_INBUF_FULL  0x02
#define I8042_STATUS_AUX_DATA    0x20

#define KBD_RING_SIZE 1024

static inline uint8_t
inb_port(uint16_t port)
{
	uint8_t data;
	__asm__ volatile ("inb %1, %0" : "=a" (data) : "Nd" (port));
	return data;
}

static inline void
ps2_delay(void)
{
	IODelay(20);
}

/* Keyboard ring buffer state */
static uint8_t   kbd_ring[KBD_RING_SIZE];
static uint32_t  kbd_head = 0;
static uint32_t  kbd_tail = 0;
static lck_mtx_t kbd_lock;
static LCK_GRP_DECLARE(kbd_lck_grp, "ps2keyboard");
static int       ps2keyboard_major = -1;
static boolean_t ps2keyboard_initialized = FALSE;
static boolean_t kbd_tap_active = FALSE; /* kext is feeding us */

/*
 * Called from the ApplePS2Controller kext for every raw keyboard scan code
 * it reads off the i8042. Runs on the IOKit work loop, so take the lock.
 */
void
ps2keyboard_tap(uint8_t code)
{
	lck_mtx_lock(&kbd_lock);
	kbd_tap_active = TRUE; /* the kext owns the ports from now on */
	uint32_t next_head = (kbd_head + 1) % KBD_RING_SIZE;
	if (next_head != kbd_tail) {
		kbd_ring[kbd_head] = code;
		kbd_head = next_head;
	}
	lck_mtx_unlock(&kbd_lock);
}

/*
 * Fallback only: used when no kext installed the tap, in which case nothing
 * else is draining the keyboard stream and polling is safe.
 */
static void
ps2keyboard_drain_hardware(void)
{
	if (kbd_tap_active)
		return;

	int count = 128;
	while (count-- > 0) {
		uint8_t status = inb_port(I8042_CMD_PORT);
		if ((status & I8042_STATUS_OUTBUF_FULL) &&
		    !(status & I8042_STATUS_AUX_DATA)) {
			uint32_t next_head = (kbd_head + 1) % KBD_RING_SIZE;
			if (next_head != kbd_tail) {
				kbd_ring[kbd_head] = inb_port(I8042_DATA_PORT);
				kbd_head = next_head;
			} else {
				(void)inb_port(I8042_DATA_PORT);
			}
		} else {
			break;
		}
	}
}

void
ps2keyboard_set_tap_active(void)
{
	kbd_tap_active = TRUE;
}

static int
ps2keyboard_open(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	int dummy;
	lck_mtx_lock(&kbd_lock);
	dummy = (int)kbd_tap_active;
	lck_mtx_unlock(&kbd_lock);

	kbd_head = 0;
	kbd_tail = 0;
	printf("ps2keyboard: opened (tap=%d)\n", dummy);
	return 0;
}

static int
ps2keyboard_close(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	return 0;
}

static int
ps2keyboard_read(__unused dev_t dev, struct uio *uio, __unused int ioflag)
{
	ps2keyboard_drain_hardware();

	size_t requested = (size_t)uio_resid(uio);
	if (requested == 0) {
		return 0;
	}

	lck_mtx_lock(&kbd_lock);
	size_t available;
	if (kbd_head >= kbd_tail) {
		available = kbd_head - kbd_tail;
	} else {
		available = KBD_RING_SIZE - kbd_tail + kbd_head;
	}

	if (available == 0) {
		lck_mtx_unlock(&kbd_lock);
		return 0; /* Non-blocking EOF / no data right now */
	}

	size_t to_read = MIN(requested, available);
	uint8_t temp_buf[256];
	size_t chunk = MIN(to_read, sizeof(temp_buf));

    for (size_t i = 0; i < chunk; i++) {
        temp_buf[i] = kbd_ring[kbd_tail];
        kbd_tail = (kbd_tail + 1) % KBD_RING_SIZE;
    }
    lck_mtx_unlock(&kbd_lock);

    return uiomove((caddr_t)temp_buf, (int)chunk, uio);
}

static int
ps2keyboard_select(__unused dev_t dev, int which, __unused void *wql, __unused struct proc *p)
{
	if (which != FREAD) {
		return 0;
	}

	ps2keyboard_drain_hardware();

	lck_mtx_lock(&kbd_lock);
	int ready = (kbd_head != kbd_tail) ? 1 : 0;
	lck_mtx_unlock(&kbd_lock);

	return ready;
}

static int
ps2keyboard_ioctl(__unused dev_t dev, __unused u_long cmd, __unused caddr_t data, __unused int flag, __unused struct proc *p)
{
	return ENOTTY;
}

static const struct cdevsw ps2keyboard_cdevsw = {
	.d_open       = ps2keyboard_open,
	.d_close      = ps2keyboard_close,
	.d_read       = ps2keyboard_read,
	.d_write      = eno_rdwrt,
	.d_ioctl      = ps2keyboard_ioctl,
	.d_stop       = eno_stop,
	.d_reset      = eno_reset,
	.d_ttys       = NULL,
	.d_select     = ps2keyboard_select,
	.d_mmap       = eno_mmap,
	.d_strategy   = eno_strat,
	.d_reserved_1 = eno_getc,
	.d_reserved_2 = eno_putc,
};

void
ps2keyboard_init(void)
{
	int ret;

	if (ps2keyboard_initialized) {
		return;
	}

	lck_mtx_init(&kbd_lock, &kbd_lck_grp, LCK_ATTR_NULL);

	ret = cdevsw_add(-1, &ps2keyboard_cdevsw);
	if (ret < 0) {
		printf("ps2keyboard: cdevsw_add failed: %d\n", ret);
		return;
	}
	ps2keyboard_major = ret;

	if (devfs_make_node(makedev(ps2keyboard_major, 0), DEVFS_CHAR,
	    UID_ROOT, GID_WHEEL, 0666, "keyboard") == NULL) {
		printf("ps2keyboard: devfs_make_node failed for 'keyboard'\n");
		return;
	}

	(void)devfs_make_node(makedev(ps2keyboard_major, 0), DEVFS_CHAR,
	    UID_ROOT, GID_WHEEL, 0666, "kbd");

	ps2keyboard_initialized = TRUE;
	printf("ps2keyboard: registered character device major %d (/dev/keyboard, /dev/kbd)\n",
	    ps2keyboard_major);
}
