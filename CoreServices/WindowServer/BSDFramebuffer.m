/*
 * Copyright (C) 2024 Zoe Knox <zoe@ravynsoft.com>
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
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "BSDFramebuffer.h"
#import <sys/types.h>
#import <sys/ipc.h>
#import <sys/shm.h>
#import "rpc.h" // for mode definitions
/* FreeBSD mmap hint flags the ravynOS sys/mman.h does not define. Both are
 * hints only, so 0 is the correct no-op value. */
#ifndef MAP_NOCORE
#define MAP_NOCORE 0
#endif
#ifndef MAP_NOSYNC
#define MAP_NOSYNC 0
#endif


#include <math.h>
#include <string.h>

static int minInt(int a, int b) { return a < b ? a : b; }
static int maxInt(int a, int b) { return a > b ? a : b; }
static void blitRows(uint8_t *dst, const uint8_t *src, size_t stride, int bpp, int width, int height, int x0, int x1, int y0, int y1)
{
    if(!dst || !src || stride <= 0 || bpp <= 0 || width <= 0 || height <= 0)
        return;
    if(x0 < 0) x0 = 0;
    if(y0 < 0) y0 = 0;
    if(x1 > width) x1 = width;
    if(y1 > height) y1 = height;
    if(x1 <= x0 || y1 <= y0)
        return;
    size_t rowBytes = (size_t)(x1 - x0) * bpp;
    for(int y = y0; y < y1; ++y) {
        uint8_t *d = dst + (size_t)y * stride + (size_t)x0 * bpp;
        const uint8_t *s = src + (size_t)y * stride + (size_t)x0 * bpp;
        memcpy(d, s, rowBytes);
    }
}

@implementation BSDFramebuffer

- (id)init
{
    self = [super init];
    _flags = kWSDisplayActive | kWSDisplayOnline | kWSDisplayPrimary | kWSDisplayMain;
    _openGLMask = 0;
    fbfd = -1;
    stride = -1;
    data = NULL;
    size = 0;
    ctx = NULL;
    ctx2 = NULL;
    return self;
}

- (int)openFramebuffer: (const char *)device
{
    struct fbtype fb;
    write(2, "[WS] openFramebuffer\n", 21);

    fbfd = open(device, O_RDWR);
    if(fbfd < 0) {
        perror(device);
        return -1;
    }

    if(ioctl(fbfd, FBIOGTYPE, &fb) < 0) {
        perror("FBIOGTYPE");
        close(fbfd);
        return -1;
    }

    if(ioctl(fbfd, FBIO_GETLINEWIDTH, &stride) < 0) {
        perror("FBIO_GETLINEWIDTH");
        close(fbfd);
        return -1;
    }

    depth = fb.fb_depth;
    width = fb.fb_width;
    height = fb.fb_height;

    _currentMode->width = width;
    _currentMode->height = height;
    _currentMode->depth = depth;
    _currentMode->refresh = 60.0; // the emulated scanout runs at 60 Hz
    _currentMode->flags = 0;

    CFArrayAppendValue(_allModes, CGDisplayModeRetain(_currentMode));

    /* Virtual modes the compositor can present at the scanout's size.  The
     * mode is applied in software by scaling/scissoring the scene, so the
     * Displays pane has real choices instead of a one-entry list. */
    {
        static const struct { uint32_t w, h; } virtualModes[] = {
            { 1600, 900 }, { 1440, 900 }, { 1280, 800 },
            { 1280, 720 }, { 1024, 768 },  { 800, 600 },
        };
        unsigned i;

        for(i = 0; i < sizeof(virtualModes) / sizeof(virtualModes[0]); i++) {
            if(virtualModes[i].w == width && virtualModes[i].h == height)
                continue;
            if(virtualModes[i].w > width || virtualModes[i].h > height)
                continue;
            {
                struct CGDisplayMode *m = calloc(sizeof(struct CGDisplayMode), 1);
                m->width = virtualModes[i].w;
                m->height = virtualModes[i].h;
                m->depth = depth;
                m->refresh = 60.0;
                m->flags = 0;
                CFArrayAppendValue(_allModes, m);
            }
        }
    }

    size_t pagemask = getpagesize() - 1;
    size = (stride * height + pagemask) & ~pagemask;
    data = mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_NOCORE|MAP_NOSYNC, fbfd, 0);
    if(data == MAP_FAILED) {
        write(2, "[WS] fb0 mmap FAILED\n", 21);
        perror("mmap");
        return -1;
    }
    write(2, "[WS] fb0 mmap OK\n", 17);
    char geombuf[128];
    int glen = snprintf(geombuf, sizeof(geombuf), "[WS] fb geom: %dx%d depth %d stride %d size %d\n", width, height, depth, stride, size);
    write(2, geombuf, glen);

    // Paint immediate 4-colour test pattern into mmap'd scanout to prove
    // scanout visibility end-to-end, matching tools/bootlab/init/fb_probe.c.
    if(data != NULL && data != MAP_FAILED && stride > 0 && width > 0 && height > 0) {
        volatile uint32_t *fb_pixels = (volatile uint32_t *)data;
        uint32_t stride_px = (uint32_t)(stride / 4);
        for(uint32_t y = 0; y < (uint32_t)height; y++) {
            volatile uint32_t *row = fb_pixels + (size_t)y * stride_px;
            for(uint32_t x = 0; x < (uint32_t)width; x++) {
                uint32_t bar = (x * 4) / (uint32_t)width;
                uint32_t c;
                if(bar == 0)
                    c = 0xFFFFFFFFu; // White
                else if(bar == 1)
                    c = 0x00FF0000u; // Red
                else if(bar == 2)
                    c = 0x0000FF00u; // Green
                else
                    c = 0x000000FFu; // Blue
                row[x] = c;
            }
        }
        write(2, "[WS] fb test pattern painted OK\n", 32);
    }
    cs = CGColorSpaceCreateDeviceRGB();
    write(2, "[WS] creating ctx\n", 18);
    ctx = [O2Context createWithBytes:NULL width:width height:height 
                bitsPerComponent:8 bytesPerRow:stride colorSpace:(__bridge O2ColorSpaceRef)cs
                bitmapInfo:[self format] releaseCallback:NULL releaseInfo:NULL];
    write(2, "[WS] ctx created\n", 17);
    ctxPixels = [[ctx surface] pixelBytes];
    write(2, "[WS] creating ctx2\n", 19);
    ctx2 = [O2Context createWithBytes:NULL width:width height:height 
            bitsPerComponent:8 bytesPerRow:stride colorSpace:(__bridge O2ColorSpaceRef)cs
            bitmapInfo:[self format] releaseCallback:NULL releaseInfo:NULL];
    write(2, "[WS] ctx2 created\n", 18);
    ctx2Pixels = [[ctx2 surface] pixelBytes];
    activeCtx = ctx;
    write(2, "[WS] openFramebuffer finished OK\n", 33);
    return 0;
}

- (void)dealloc
{
    [self releaseCapture];
    if(fbfd >= 0) {
        munmap(data, size);
        close(fbfd);
    }
    if(cs)
        CGColorSpaceRelease(cs);
    ctx = nil;
    activeCtx = nil;
    ctx2 = nil;
}

// clear screen. does not swap active buffer
-(void)clear {
    void *pixels = NULL;
    if(_captured)
        pixels = [[captureCtx surface] pixelBytes];
    else 
        pixels = ctxPixels;
    write(2, "[WS] fb clear starting\n", 23);
    O2ContextSetRGBFillColor(activeCtx, 0.15, 0.25, 0.35, 1);
    O2ContextFillRect(activeCtx, (O2Rect)NSMakeRect(0, 0, width, height));
    memcpy(data, pixels, size);
    write(2, "[WS] fb clear finished\n", 23);
}

- (void)draw
{
    [self drawRect:NSMakeRect(0, 0, width, height)];
}

- (void)drawRect:(NSRect)rect
{
    void *pixels = NULL;
    if(_captured)
        pixels = [[captureCtx surface] pixelBytes];
    else
        pixels = ctxPixels;
    if(data == NULL || pixels == NULL || width <= 0 || height <= 0 || stride <= 0)
        return;
    int bpp = (depth > 0) ? (depth / 8) : 4;
    if(bpp <= 0)
        bpp = 4;
    int x0 = (int)rect.origin.x;
    int x1 = (int)(rect.origin.x + rect.size.width) + 1;
    if(x0 < 0) x0 = 0;
    if(x1 > width) x1 = width;
    if(x1 <= x0)
        return;
    int y0 = (int)rect.origin.y;
    int y1 = (int)(rect.origin.y + rect.size.height) + 1;
    /* WS geometry is y-up with scanout row 0 at the top of the screen, so a
     * WS-space rect maps to scanout rows [height - y1, height - y0).  Blitting
     * the unflipped range too only duplicated rows for a sub-rect (it was a
     * no-op for the full-screen draw, where both ranges coincide). */
    blitRows((uint8_t *)data, (const uint8_t *)pixels, stride, bpp, width, height, x0, x1, height - y1, height - y0);
}

- (void)drawWithCursor:(O2Image *)cursor inRect:(O2Rect)rect {
    O2ContextDrawImage(ctx2, NSMakeRect(0,0,width,height), [captureCtx surface]);
    O2ContextSetBlendMode(ctx2, kCGBlendModeNormal);
    O2ContextDrawImage(ctx2, rect, cursor);
    memcpy(data, ctx2Pixels, size); // FIXME: this is slooowwww
}

// return the context for drawing, i.e. the back buffer
- (O2Context *)context
{
    if(_captured)
        return captureCtx;
    else
        return ctx;
}

-(BOOL)capture:(pid_t)pid withOptions:(uint32_t)options {
    if(_captured != 0)
        return NO;

    pthread_mutex_lock(&renderLock);
    _captured = pid;

    int reserved = 6*sizeof(int); // save space for dimensions info 
    shmSize = size + reserved;
    shmid = shmget([self getDisplayID] ^ random(), shmSize, IPC_CREAT|0666);
    if(shmid == 0)
        return NO;

    uint8_t *p = shmat(shmid, NULL, 0);
    if(!p) {
        shmctl(shmid, IPC_RMID, NULL);
        shmid = 0;
        return NO;
    }

    uint8_t *bufaddr = (p + reserved);
    captureCtx = [[O2Context_builtin alloc] initWithBytes:(void *)bufaddr
                width:width height:height bitsPerComponent:8 bytesPerRow:width*4
                colorSpace:(__bridge O2ColorSpaceRef)cs
                bitmapInfo:[self format] releaseCallback:NULL releaseInfo:NULL];
    activeCtx = captureCtx;
    pthread_mutex_unlock(&renderLock);
    intptr_t *q = (intptr_t *)p;
    q[0] = width;
    q[1] = height;
    q[2] = [self format];
    
    // we ignore the deprecated options and always fill with black
    [self clear];
    return YES;
}

-(void)releaseCapture {
    pthread_mutex_lock(&renderLock);
    _captured = 0;
    activeCtx = ctx;
    if(captureCtx != nil) {
        shmctl(shmid, IPC_RMID, NULL);
        void *buffer = [[captureCtx surface] pixelBytes];
        buffer -= 6*sizeof(int);
        shmdt(buffer);
        shmid = 0;
        shmSize = 0;
    }
    captureCtx = nil;
    pthread_mutex_unlock(&renderLock);
}

/* FIXME: this should hash the vendor, model, serial, and other data */
- (uint32_t)getDisplayID {
    return 0xf07f0a10; // arbitrary ID
}

/* Changing the hardware mode needs a DRM driver; this framebuffer has none.
 * A virtual mode is accepted so the compositor can letterbox the scene at the
 * requested logical size.  The base class stores it as _currentMode. */
-(BOOL)setMode:(struct CGDisplayMode *)mode {
    if(mode == NULL)
        return NO;
    if(mode->width == 0 || mode->height == 0)
        return NO;
    return [super setMode:mode];
}

@end
