// layertest.m -- does a layer-backed window's contents reach the screen?
//
// Every window that works in this tree (Filer, Dock, SystemUIServer) draws in
// -drawRect:. The only thing that composites CALayer contents is AppKit's
// _renderLayer:inContext:, and Firefox's browser window is entirely
// layer-backed: Gecko puts its page tiles in CALayer.contents and expects
// AppKit to draw them.  Nothing in the suite has ever exercised that path, so
// a blank Firefox window cannot be attributed until a known image is pushed
// through it.
//
// This window paints a 64x64 magenta tile through a layer and nothing else.
// The check is a readback of the framebuffer: if the tile is there, the layer
// path works and any blank client window is the client's own doing; if the
// window is white where the tile should be, the defect is ours.
//
// The readback uses /dev/fb0, the same device the compositor scans out to.
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#define _XOPEN_SOURCE 700
#include <signal.h>
#include <ucontext.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <unistd.h>

/* The stage markers say which call dies; this says where inside it.  A fault
 * that takes the whole process cannot be inspected after the fact in this
 * image (no corpse record for a client), so the fixture reports its own
 * signal: the faulting address from siginfo and the pc/rsp from the ucontext.
 * If the kernel does not fill the ucontext for SA_SIGINFO handlers, the pc
 * prints as garbage and the address alone still answers pointer-vs-alignment. */
static void reportFault(int sig, siginfo_t *info, void *context) {
    ucontext_t *uc = (ucontext_t *)context;

    void *rip = (void *)uc->uc_mcontext->__ss.__rip;
    Dl_info info2;

    printf("LAYER-SIGNAL sig=%d addr=%p rip=%p rsp=%p\n", sig, info->si_addr,
           rip, (void *)uc->uc_mcontext->__ss.__rsp);
    if (dladdr(rip, &info2) && info2.dli_fname != NULL)
        printf("LAYER-AT %s + %#lx (base %p) near %s\n", info2.dli_fname,
               (unsigned long)((uintptr_t)rip - (uintptr_t)info2.dli_fbase),
               info2.dli_fbase, info2.dli_sname ? info2.dli_sname : "?");
    else
        printf("LAYER-AT dladdr failed for rip\n");

    /* The pc alone names the atomic helper, not the caller.  Walk the
     * frame-pointer chain so the fault is attributed to a call chain; a
     * frame outside the live stack (rsp .. rsp+1MB, 8-aligned) ends the walk,
     * because dereferencing a bogus fp inside this handler would fault again
     * and lose the report. */
    {
        uintptr_t lo = (uintptr_t)uc->uc_mcontext->__ss.__rsp;
        uintptr_t hi = lo + (1u << 20);
        uintptr_t *fp = (uintptr_t *)uc->uc_mcontext->__ss.__rbp;
        int i;

        for (i = 0; i < 12 && fp != NULL; i++) {
            Dl_info fd;
            uintptr_t ret;

            if ((uintptr_t)fp < lo || (uintptr_t)fp > hi || ((uintptr_t)fp & 7) != 0)
                break;
            ret = fp[1];
            if (ret == 0)
                break;
            if (dladdr((void *)ret, &fd) && fd.dli_fname != NULL)
                printf("LAYER-FRAME %d %s + %#lx\n", i, fd.dli_fname,
                       (unsigned long)(ret - (uintptr_t)fd.dli_fbase));
            else
                printf("LAYER-FRAME %d %p\n", i, (void *)ret);
            fp = (uintptr_t *)fp[0];
        }
    }
    fflush(stdout);
    _exit(138);   /* the SIGBUS convention the runner classifies as KNOWN-CRASH */
}
#import <fcntl.h>
#import <stdio.h>
#import <string.h>
#import <sys/ioctl.h>
#import <sys/mman.h>
#import <unistd.h>

#define WIN_X 200
#define WIN_Y 200
#define WIN_W 300
#define WIN_H 200
#define TILE_W 64
#define TILE_H 64
#define CTRL_X 600
#define CTRL_Y 200
#define CTRL_W 300
#define CTRL_H 200

/* Flat 4.3BSD layout, exactly as sys/fbio.h declares it (same struct and same
 * ioctl number as tools/bootlab/init/fb_probe.c, computed from ioccom.h:
 * IOC_OUT|((52&0x1fff)<<16)|('f'<<8)|0).  Guessing _IOR('F',0,...) gives 'F'
 * not 'f' and a different size, which the kernel rejects. */
struct fbtype_local {
    char           fb_name[16];
    unsigned short fb_type;
    unsigned short fb_height;
    unsigned short fb_width;
    unsigned short fb_pad1;
    unsigned int   fb_pad2;
    unsigned int   fb_memsize;
    unsigned int   fb_linebytes;
    unsigned int   fb_base;
    unsigned int   fb_sizex;
    unsigned int   fb_sizey;
    unsigned short fb_vertinc;
    unsigned short fb_depth;
};
#define FBIOGTYPE_LOCAL 0x40346600UL

// A solid magenta CGImage, built the way an application would build one.
static CGImageRef magentaTile(size_t w, size_t h) {
    size_t rowBytes = w * 4;
    uint8_t *px = calloc(rowBytes * h, 1);
    if (!px) return NULL;
    for (size_t i = 0; i < w * h; i++) {
        px[i * 4 + 0] = 0xff;   // R
        px[i * 4 + 1] = 0x00;   // G
        px[i * 4 + 2] = 0xff;   // B
        px[i * 4 + 3] = 0xff;   // A
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, px, rowBytes * h, NULL);
    CGImageRef img = CGImageCreate(w, h, 8, 32, rowBytes, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault,
        prov, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(prov);
    CGColorSpaceRelease(space);
    return img;
}

/* Control window: the SAME tile drawn straight from drawRect:, once 1:1
 * and once scaled, plus a plain fill as the known-good baseline.  If the
 * fill lands and the images do not, image drawing is broken in this
 * context; if nothing lands, the window's compositing is. */
@interface ControlView : NSView {
    CGImageRef _tile;
}
- (instancetype)initWithFrame:(NSRect)f tile:(CGImageRef)t;
- (void)drawRect:(NSRect)rect;
@end

@implementation ControlView
- (instancetype)initWithFrame:(NSRect)f tile:(CGImageRef)t {
    self = [super initWithFrame:f];
    if (self) _tile = CGImageRetain(t);
    return self;
}
- (void)drawRect:(NSRect)rect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    printf("CTRL-CTX %p flipped=%d rect=%g,%g %gx%g\n", ctx,
           (int)[self isFlipped], rect.origin.x, rect.origin.y,
           rect.size.width, rect.size.height);
    if (!ctx || !_tile) return;
    CGContextSetRGBFillColor(ctx, 1.0, 0.0, 1.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(20, 120, 64, 64));
    CGContextDrawImage(ctx, CGRectMake(20, 20, 64, 64), _tile);          /* 1:1 */
    CGContextDrawImage(ctx, CGRectMake(120, 20, 150, 100), _tile);     /* scaled */
}
@end

/* Count magenta pixels inside a window rect, so the control window and the
 * layer window get separate verdicts from one readback. */
static size_t g_controlPixels;   /* set by framebufferHasTile for the CONTROL verdict */

static size_t countMagentaInWindow(const uint8_t *map, uint32_t fbw, uint32_t fbh,
                                   int x, int y, int w, int h) {
    size_t topRow = (size_t)fbh - (y + h), hits = 0;
    for (size_t r = topRow; r < topRow + h && r < (size_t)fbh; r++)
        for (size_t c = (size_t)x; c < (size_t)(x + w) && c < (size_t)fbw; c++) {
            const uint8_t *p = map + (r * (size_t)fbw + c) * 4;
            if (p[0] > 200 && p[1] < 60 && p[2] > 200) hits++;
        }
    return hits;

}

// Count magenta pixels in the framebuffer, and report what is at the tile's
// expected position in case it is something else.
static int framebufferHasTile(void) {
    int fd = open("/dev/fb0", O_RDWR);
    if (fd < 0) {
        printf("LAYER-SKIP cannot open /dev/fb0 errno\n");
        return -1;
    }
    struct fbtype_local fb;
    if (ioctl(fd, FBIOGTYPE_LOCAL, &fb) < 0 || fb.fb_width <= 0 || fb.fb_height <= 0) {
        printf("LAYER-SKIP FBIOGTYPE failed\n");
        close(fd);
        return -1;
    }
    size_t bytes = (size_t)fb.fb_width * (size_t)fb.fb_height * 4;
    uint8_t *map = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        printf("LAYER-SKIP mmap failed\n");
        close(fd);
        return -1;
    }

    // Bottom-left window origin, rows counted from the top of the scanout.
    size_t topRow = (size_t)fb.fb_height - (WIN_Y + WIN_H);
    size_t hits = 0;
    for (size_t y = topRow; y < topRow + WIN_H && y < (size_t)fb.fb_height; y++) {
        for (size_t x = WIN_X; x < (size_t)(WIN_X + WIN_W) && x < (size_t)fb.fb_width; x++) {
            uint8_t *p = map + (y * (size_t)fb.fb_width + x) * 4;
            // scanout is BGRA
            if (p[0] > 200 && p[1] < 60 && p[2] > 200)
                hits++;
        }
    }

    size_t ctrl = countMagentaInWindow(map, fb.fb_width, fb.fb_height,
                                       CTRL_X, CTRL_Y, CTRL_W, CTRL_H);
    size_t sx = WIN_X + TILE_W + 20, sy = topRow + 20;   // inside the window, outside the tile
    uint8_t *s = map + (sy * (size_t)fb.fb_width + sx) * 4;
    printf("LAYER-FB %dx%d tile_pixels=%zu control_pixels=%zu sample_elsewhere=%02x%02x%02x%02x\n",
           fb.fb_width, fb.fb_height, hits, ctrl, s[0], s[1], s[2], s[3]);
    g_controlPixels = ctrl;

    munmap(map, bytes);
    close(fd);
    return hits > 1000 ? 1 : 0;
}

int main(int argc, char **argv) {
    /* Line-buffered: stdout is a file here, and a crash must not swallow the
     * record of how far the fixture got. */
    setvbuf(stdout, NULL, _IOLBF, 0);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = reportFault;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGSEGV, &sa, NULL);

    /* Which image is which, so a raw pc from the handler can be attributed
     * even when dladdr is unavailable in this dyld. */
    {
        uint32_t n = _dyld_image_count(), i;
        printf("LAYER-IMGS %u\n", (unsigned)n);
        for (i = 0; i < n; i++)
            printf("LAYER-IMG %p %s\n", (void *)_dyld_get_image_header(i),
                   _dyld_get_image_name(i));
        fflush(stdout);
    }
    @autoreleasepool {
        [NSApplication sharedApplication];
        printf("LAYER-STAGE app\n");

        // [CATransaction disableActions] dies before touching any layer, and
        // its only work is a dictionary with framework-constant string keys
        // plus the per-thread shared dictionary. Test those two on their own,
        // so the fault is attributed to one of them and not to the layer path.
        {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            [d setObject:@"v" forKey:@"kLiteral"];
            printf("LAYER-DICT literal=%s count=%d\n",
                   [[d objectForKey:@"kLiteral"] UTF8String], (int)[d count]);
            NSString *constKey = [[NSBundle mainBundle] bundleIdentifier] ? @"kConst" : @"kConst";
            [d setObject:[NSNumber numberWithBool:NO] forKey:constKey];
            printf("LAYER-DICT const=%d\n", (int)[[d objectForKey:constKey] boolValue]);
            NSMutableDictionary *shared = [[NSThread currentThread] sharedDictionary];
            printf("LAYER-DICT shared=%p\n", (void *)shared);
            [shared setObject:@"x" forKey:@"probe"];
            printf("LAYER-DICT shared-set=%s\n",
                   [[shared objectForKey:@"probe"] UTF8String]);
        }
        printf("LAYER-STAGE dict-done\n");
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSRect frame = NSMakeRect(WIN_X, WIN_Y, WIN_W, WIN_H);
        NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                    styleMask:NSTitledWindowMask
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        printf("LAYER-STAGE window\n");
        [win setTitle:@"layertest"];

        NSView *content = [win contentView];
        printf("LAYER-STAGE wantsLayer\n");
        [content setWantsLayer:YES];

        CGImageRef tile = magentaTile(TILE_W, TILE_H);
        if (!tile) {
            printf("LAYER-FAIL no image\n");
            return 1;
        }
        CALayer *layer = [content layer];
        printf("LAYER-STAGE contents\n");
        [layer setContents:(id)tile];
        printf("LAYER-STAGE contents-done\n");

        // setFrame: is two setters, and each reaches the animation machinery.
        // Call them directly (and the transaction query they make) so a fault
        // names the exact call rather than the outer one.
        printf("LAYER-STAGE txn\n");
        printf("LAYER-TXN disableActions=%d\n", (int)[CATransaction disableActions]);
        printf("LAYER-STAGE pos\n");
        [layer setPosition:CGPointMake(TILE_W / 2.0, TILE_H / 2.0)];
        printf("LAYER-STAGE pos-done\n");
        printf("LAYER-STAGE bnd\n");
        [layer setBounds:CGRectMake(0, 0, TILE_W, TILE_H)];
        printf("LAYER-STAGE bnd-done\n");

        [layer setFrame:CGRectMake(0, 0, TILE_W, TILE_H)];
        // A layer whose contents we set must not be treated as a bare backing
        // store; both flags exist for exactly this case.
        printf("LAYER-STAGE frame-done\n");
        [layer setNeedsDisplay];
        printf("LAYER-STAGE layerdirty-done\n");
        [content setNeedsDisplay:YES];

        printf("LAYER-STAGE ordered\n");

        // Control window: same tile, plain drawRect: path, no layers.
        NSWindow *cwin = [[NSWindow alloc] initWithContentRect:
                            NSMakeRect(CTRL_X, CTRL_Y, CTRL_W, CTRL_H)
                                                    styleMask:NSTitledWindowMask
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        [cwin setTitle:@"layertest-control"];
        [cwin setContentView:[[ControlView alloc] initWithFrame:
                              NSMakeRect(0, 0, CTRL_W, CTRL_H) tile:tile]];
        [cwin orderFront:nil];
        [cwin display];
        [cwin flushWindow];
        [win orderFront:nil];
        [win makeKeyWindow];
        printf("LAYER-STAGE displayed\n");

        // Let the compositor
        [win display];
        [win flushWindow];

        // Let the compositor produce at least one frame before reading it back.
        // Run the loop briefly rather than sleeping, so window updates happen.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while ([until timeIntervalSinceNow] > 0) {
            NSEvent *e = [NSApp nextEventMatchingMask:NSAnyEventMask
                                            untilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
            if (e) [NSApp sendEvent:e];
        }
        [win display];
        [win flushWindow];
        [cwin display];
        [cwin flushWindow];

        printf("LAYER-WINDOW frame=%d,%d %dx%d layer=%p\n",
               WIN_X, WIN_Y, WIN_W, WIN_H, (void *)layer);

        int verdict = framebufferHasTile();
        if (verdict < 0) {
            printf("LAYER-SKIP framebuffer not readable\n");
            return 0;   // cannot measure: not a failure of the layer path
        }
        /* Control verdict: the drawRect: path must land too -- it is the
         * baseline every other window in the image already relies on. */
        int ctrl_ok = g_controlPixels > 1000;
        printf("LAYER-%s CONTROL-%s\n", verdict ? "OK" : "FAIL",
               ctrl_ok ? "OK" : "FAIL");
        return (verdict && ctrl_ok) ? 0 : 1;
    }
}
