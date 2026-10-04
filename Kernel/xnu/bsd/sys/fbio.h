/*
 * Copyright (c) 2024 Zoe Knox <zoe@ravynsoft.com>
 * Copyright (c) 1994 The Regents of the University of California.  All rights reserved.
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
 * Frame buffer device ioctls.
 *
 * These numbers are the long-standing NetBSD/Darwin 'f' group values.  They
 * are fixed ABI: CoreServices/WindowServer/BSDFramebuffer.m issues
 * FBIOGTYPE and FBIO_GETLINEWIDTH against them, so they must not change.
 */

#ifndef _SYS_FBIO_H_
#define _SYS_FBIO_H_

#include <sys/param.h>
#include <sys/ioccom.h>

__BEGIN_DECLS

/*
 * Frame buffer types, as returned in fb_type by FBIOGTYPE.
 */
#define FB_TYPE_PACKED_PIXELS     0   /* compacted, palette-mapped     */
#define FB_TYPE_ARGB_PIXELS       1   /* 32bpp true colour (A:R:G:B)   */
#define FB_TYPE_A8B8G8R8_PIXELS   1
#define FB_TYPE_RGB_DIRECT        2   /* direct colour, no palette      */

/* Canonical spelling used by the driver below. */
#define FBIO_TYPE_PACKED_PIXELS   FB_TYPE_PACKED_PIXELS
#define FBIO_TYPE_ARGB_PIXELS     FB_TYPE_ARGB_PIXELS
#define FBIO_TYPE_RGB_DIRECT      FB_TYPE_RGB_DIRECT

/*
 * struct fbtype -- the device description returned by FBIOGTYPE.
 *
 * This is the flat 4.3BSD layout, which is what BSDFramebuffer.m expects: it
 * reads fb_depth, fb_width and fb_height as direct members.  Newer NetBSD
 * wraps these in a `struct fbtype_s fb' sub-struct behind fb_* macros; those
 * macros are deliberately NOT defined here, because fb_base/fb_size are
 * ordinary identifiers in kernel code and turning them into macros silently
 * corrupts unrelated declarations.
 */
struct fbtype {
	char           fb_name[16];    /* short canonical name         */
	unsigned short fb_type;        /* FB_TYPE_*                    */
	unsigned short fb_height;      /* pixels                       */
	unsigned short fb_width;       /* pixels                       */
	unsigned short fb_pad1;
	unsigned int   fb_pad2;
	unsigned int   fb_memsize;     /* bytes of frame buffer        */
	unsigned int   fb_linebytes;   /* stride, bytes per row        */
	unsigned int   fb_base;        /* physical address             */
	unsigned int   fb_sizex;       /* virtual display width        */
	unsigned int   fb_sizey;       /* virtual display height       */
	unsigned short fb_vertinc;     /* rows of memory per screen    */
	unsigned short fb_depth;       /* bits per pixel               */
};

/* Pixel formats reported in fb_visual (the real struct is `unsigned int'). */
#define FB_VISUAL_INDEX            0
#define FB_VISUAL_DIRECT           1
#define FB_VISUAL_TRUECOLOR        2

#define FBIOGTYPE              _IOR('f', 0, struct fbtype)
#define FBIOGDTYPE             _IOR('f', 1, struct fbtype)

/*
 * FBIO_GETLINEWIDTH returns the stride in bytes in an unsigned int.
 * WindowServer passes an int and uses the value directly as a byte stride.
 */
#define FBIO_GETLINEWIDTH      _IOWR('f', 2, unsigned int)
#define FBIO_SETLINEWIDTH      _IOWR('f', 3, unsigned int)

#define FBIOGET_FSCREENINFO    _IOR('f', 4, unsigned int)
#define FBIO_SETPOS            _IOW('f', 5, unsigned long)
#define FBIO_GETPOS            _IOWR('f', 6, unsigned long)
#define FBIOGET_VSCREENINFO    _IOR('f', 7, unsigned int)
#define FBIO_GETCMAP           _IOWR('f', 8, unsigned int)
#define FBIO_SETCMAP           _IOWR('f', 9, unsigned int)
#define FBIO_COPYCOPY          _IOWR('f', 10, unsigned int)
#define FBIO_WAITFORVSYNC      _IO('f', 11)
#define FBIOGET_CURRENTFBINFO  _IOR('f', 12, unsigned int)

__END_DECLS

#endif /* _SYS_FBIO_H_ */