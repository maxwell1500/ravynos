/*
 * Copyright (c) 2024 Zoe Knox <zoe@ravynsoft.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/*
 * Console/vt and pseudo-device ioctls.
 *
 * The numbers are the long-standing NetBSD/Darwin values.  They are fixed ABI:
 * CoreServices/WindowServer/main.m issues VT_GETACTIVE, VT_OPENQRY,
 * VT_ACTIVATE, VT_SETMODE and CONS_MOUSECTL against them.
 */

#ifndef _SYS_CONSIO_H_
#define _SYS_CONSIO_H_

#include <sys/param.h>
#include <sys/ioccom.h>

__BEGIN_DECLS

/*
 * Console mouse operations, as passed in mouse_info.operation.
 */
#define MOUSE_HIDE            0x01
#define MOUSE_SHOW            0x00
#define MOUSE_POSITION_RELATIVE 0xfffe
#define MOUSE_POSITION_ABSOLUTE 0xffff

struct mouse_info {
	char   operation;
	char   pad0;
	short  pad1;
	int    dx, dy;     /* MOUSE_POSITION_* only */
};

#define CONS_MOUSECTL         _IOWR('t', 31, struct mouse_info)

/*
 * Virtual terminal switching.
 *
 * VT_OPENQRY allocates the next free vt and stores it in an int.
 * VT_ACTIVATE takes an int vt and makes it the active vt.
 * VT_GETACTIVE returns the active vt in an int.
 * VT_SETMODE takes a vtmode_t and sets the switching mode.
 */
#define VT_OPENQRY            _IOWR('t', 1, int)
#define VT_SETMODE            _IOW('t', 2, struct vtmode)
#define VT_GETACTIVE          _IO('t', 3)
#define VT_ACTIVATE           _IO('t', 4)
#define VT_WAITACTIVE         _IO('t', 5)
#define VT_GETSTATE           _IOR('t', 6, int)

/*
 * struct vtmode -- switching modes for VT_SETMODE.
 *
 * WindowServer passes VT_PROCESS with SIGUSR1/SIGUSR2 relay signals.
 */
#define VT_MODE_MASK          0x0f

#define VT_AUTO        0x00    /* new vt becomes current on any key press  */
#define VT_PROCESS     0x01    /* only process in fg session gets signals */
#define VT_ALWAYS     0x02    /* always signal the fg session              */

#define VT_RELOC       0x10    /* vt owns the screen, relocate on switch  */
#define VT_MAKEACTIVE  0x20    /* force vt to be the active vt            */
#define VT_DONTWAIT    0x80    /* do not wait for the switch              */

struct vtmode {
	short   mode;
	short   waitv;
	short   relsig;
	short   acqsig;
	short   frsig;
};

/*
 * struct vtinfo -- full state of a vt, for VT_GETSTATE.
 */
struct vtinfo {
	unsigned short vt_number;
	unsigned short vt_mode;
	unsigned short vt_lock;
	unsigned short vt_visible;
	unsigned short vt_pad0;
	unsigned int   vt_memseg;
	unsigned int   vt_memsize;
	unsigned short vt_row;
	unsigned short vt_col;
	unsigned short vt_x_org;
	unsigned short vt_y_org;
	unsigned int   vt_size;
	short   vt_uctlayer;
	short   vt_actlayer;
	unsigned char vt_realmode;
	unsigned char vt_curattr;
	unsigned char vt_paletteid;
	unsigned char vt_pad1[1];
	unsigned char vt_pad2[2];
};

/*
 * Reboot / console-selection ioctls.  Kept for source compatibility with
 * callers that include <sys/consio.h>; ravynOS has no real firmware console
 * switching.
 */
#define CONS_GETVERSION       _IOR('t', 0x20, int)
#define CONS_REBOOT           _IOWR('t', 0x21, int)

__END_DECLS

#endif /* _SYS_CONSIO_H_ */