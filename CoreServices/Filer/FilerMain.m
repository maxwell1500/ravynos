/*
 * FilerMain.m - ravynOS Desktop File Manager (Filer.app)
 *
 * Provides desktop file browsing and bundle execution via fork/exec of the
 * bundle's executable (LaunchServices in this tree is not usable in process),
 * and drag-and-drop .app bundle installation into /Applications.
 *
 * Copyright (C) 2026 Jack Davenport. All rights reserved.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/ioctl.h>
#import <poll.h>
#include <dirent.h>
#import <stdlib.h>
#import <string.h>
#import "term_font.h"


#define LOGF(...) do{ char _b[256]; int _n=snprintf(_b,sizeof _b,__VA_ARGS__); if(_n>0) write(2,_b,_n); }while(0)
#define TERM_COLS 96
#define TERM_ROWS 26
#define TERM_HEADER_H 24

/* ravynOS: opening a bundle spawns its own executable directly.
 *
 * LSOpenCFURLRef was tried first (resolved with dlopen so the framework's
 * classes are not registered at image load), but in-process Resolution of the
 * bundle through LaunchServices faults: right after the call Filer dies with
 * EXC_CORPSE_NOTIFY and WindowServer destroys its window, so the click that was
 * supposed to open the app took the desktop down with it.  The WindowServer
 * already spawns the shell apps with fork/execve (see the DESKTOP stage of
 * CoreServices/WindowServer/WindowServer.m), so do the same here: resolve the
 * bundle's executable, export the same RAVYN_BUNDLE_ID the other apps get, and
 * exec it. */
static void filerOpenBundle(NSString *path){
    if(!path)
        return;

    /* Preferred route: WindowServer spawns the bundle for us.  A child forked
     * from Filer cannot resolve com.ravynos.WindowServer (the bootstrap lookup
     * that every GUI app performs at startup fails: "[AppKit] Failed to locate
     * WindowServer service"), so the server does the exec.  It resolves the
     * bundle's executable itself, so nothing here has to read the Info.plist. */
    if([[NSApplication sharedApplication] openBundlePath:path])
        return;

    /* Fallback: run it locally.  NSBundle is not consulted -- on this tree
     * bundleWithPath: returns nil for paths that are known-good (measured:
     * /System/Library/CoreServices/Filer.app), which silently dropped every
     * bundle launch -- so resolve the executable from the bundle layout. */
    NSString *name=[[path lastPathComponent] stringByDeletingPathExtension];
    NSString *cands[3];
    cands[0]=[NSString stringWithFormat:@"%@/Contents/ravynOS/%@",path,name];
    cands[1]=[NSString stringWithFormat:@"%@/Contents/MacOS/%@",path,name];
    cands[2]=[NSString stringWithFormat:@"%@/%@",path,name];

    const char *exe=NULL;
    for(int i=0;i<3;i++){
        const char *c=[cands[i] UTF8String];
        if(c!=NULL && access(c,X_OK)==0){ exe=c; break; }
    }
    if(exe==NULL)
        return;

    pid_t pid=fork();
    if(pid==0){
        char argvbuf[512];
        snprintf(argvbuf,sizeof argvbuf,"%s",name?[name UTF8String]:"app");
        char *argv[2];
        argv[0]=argvbuf;
        argv[1]=NULL;
        char *envp[1];
        envp[0]=NULL;
        execve(exe,argv,envp);
        _exit(1);
    }
}
/* Desktop places: boot volume, Trash and Home as labelled tiles.  Items whose
   bundle ships artwork draw their icon; the rest are label-only, which is why
   the boot volume and Home have no image to load. */
@interface DesktopPlaceView : NSView {
    NSString *_label;
    NSString *_iconPath;
    NSImageView *_iv;
}
-(void)setLabel:(NSString *)l;
-(void)setIconPath:(NSString *)p;
@end

@implementation DesktopPlaceView

-(void)setLabel:(NSString *)l { _label = [l copy]; }

-(void)setIconPath:(NSString *)p {
    _iconPath = [p copy];
}

-(void)drawRect:(NSRect)dirty {
    /* Same as FileBrowserView: without the super call the view's backing was
     * never established and the whole pane came out blank. */
    [super drawRect:dirty];
    NSSize sz=[self bounds].size;
    CGContextRef ctx=[[[self window] graphicsContext] graphicsPort];
    if(ctx==NULL)
        return;
    float x=8.0f;
    if(_iconPath)
        x=8.0f;   /* artwork lives on the window's content view, not inside this view */
    if(_label==nil)
        return;
    NSFont *font=[NSFont fontWithName:@"Inter-Regular" size:12];
    NSDictionary *attrs = (font!=nil)
        ? [NSDictionary dictionaryWithObjects:@[font,[NSColor blackColor]]
            forKeys:@[NSFontAttributeName,NSForegroundColorAttributeName]]
        : [NSDictionary dictionaryWithObjects:@[[NSColor blackColor]]
            forKeys:@[NSForegroundColorAttributeName]];
    NSAttributedString *str=[[NSAttributedString alloc] initWithString:_label
        attributes:attrs];
    [str drawInRect:NSMakeRect(x,6,sz.width-x-8,sz.height-10)];
}

@end

@interface TerminalView : NSView {
    int ptyMaster;
    pid_t shellPid;
    int logFd;

    uint32_t cells[TERM_ROWS][TERM_COLS]; // packed 0x00RRGGBB, 0 = unused
    char grid[TERM_ROWS][TERM_COLS];
    int curRow, curCol;
    BOOL pendingClear;

    unsigned char *_termBuf;   /* rasterised grid, blitted on redraw */
    int _termW;
    int _termH;
    NSBitmapImageRep *_termRep;
    BOOL _termDirty;}
@end

@implementation TerminalView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        ptyMaster = -1;
        shellPid = -1;
        logFd = open("/dev/console", O_WRONLY);
        pendingClear = NO;
        _termBuf = NULL;
        _termRep = nil;
        _termW = _termH = 0;
        _termDirty = YES;
        [self resetScreen];

        ptyMaster = open("/dev/ptmx", O_RDWR | O_NOCTTY | O_NONBLOCK);
        if(ptyMaster >= 0) {
            grantpt(ptyMaster);
            unlockpt(ptyMaster);
            char *sname = ptsname(ptyMaster);
            if(sname) {
                shellPid = fork();
                { char b[64]; int n = snprintf(b, sizeof(b), "[Filer] spawned shell pid=%d\n", shellPid); if(n>0) write(2, b, n); }
                if(shellPid == 0) {
                    setsid();
                    int slave = open(sname, O_RDWR);
                    if(slave >= 0) {
                        ioctl(slave, TIOCSCTTY, 0);
                        pid_t pgrp = getpid();
                        tcsetpgrp(slave, pgrp);
                        struct winsize ws = { 26, 96, 0, 0 };
                        ioctl(slave, TIOCSWINSZ, &ws);
                        dup2(slave, 0);
                        dup2(slave, 1);
                        dup2(slave, 2);
                        if(slave > 2)
                            close(slave);
                    }
                    close(ptyMaster);
                    setenv("TERM", "xterm", 1);
                    execl("/bin/sh", "-sh", "-i", NULL);
                    execl("/bin/sh", "sh", "-i", NULL);
                    execl("/bin/sh", "sh", NULL);
                    _exit(1);
                }
                /* Start a 20Hz timer to drain the PTY asynchronously as the shell outputs */
                [NSTimer scheduledTimerWithTimeInterval:0.05
                                                 target:self
                                               selector:@selector(timerDrain:)
                                               userInfo:nil
                                                repeats:YES];
                [self drainPty];
            } else {
                [self printLine:"ptsname() failed" color:0xFC6159];
            }
        } else {
            [self printLine:"open(/dev/ptmx) failed" color:0xFC6159];
        }
    }
    return self;
}

static void drawChar8x16(CGContextRef ctx, int x, int y, char c, CGFloat r, CGFloat g, CGFloat b) {
    if(c < 32 || c > 126) c = ' ';
    const unsigned char *glyph = term_font_8x16[c - 32];
    CGContextSetRGBFillColor(ctx, r, g, b, 1.0);
    for(int row = 0; row < 16; row++) {
        unsigned char mask = glyph[row];
        for(int col = 0; col < 8; col++) {
            if((mask >> (7 - col)) & 1) {
                CGContextFillRect(ctx, NSMakeRect(x + col, y + (15 - row), 1, 1));
            }
        }
    }
}

static void drawString8x16(CGContextRef ctx, int x, int y, const char *str, CGFloat r, CGFloat g, CGFloat b) {
    while(*str) {
        drawChar8x16(ctx, x, y, *str, r, g, b);
        x += 8;
        str++;
    }
}

/* ravynOS: the terminal grid used to be drawn with one CGContextFillRect per
 * glyph pixel -- 12k-21k calls, measured at 5-8.5 s per redraw on this tree.
 * While a redraw runs the run loop cannot drain the event queue, so a
 * double-click's second click never got processed.  The glyphs now go into a
 * plain RGBA buffer (a few thousand memory writes) and the redraw is a single
 * image blit. */
static void blitChar8x16(unsigned char *buf, int stride, int w, int h,
                         int x, int y, char c,
                         unsigned char r, unsigned char g, unsigned char b) {
    if(c < 32 || c > 126) c = ' ';
    const unsigned char *glyph = term_font_8x16[c - 32];
    for(int row = 0; row < 16; row++) {
        int py = y + (15 - row);
        if(py < 0 || py >= h)
            continue;
        unsigned char mask = glyph[row];
        unsigned char *dst = buf + py * stride;
        for(int col = 0; col < 8; col++) {
            if(!((mask >> (7 - col)) & 1))
                continue;
            int px = x + col;
            if(px < 0 || px >= w)
                continue;
            unsigned char *p = dst + px * 4;
            /* CGImage on this tree reads the planes as A,B,G,R in memory. */
            p[0] = 255; p[1] = b; p[2] = g; p[3] = r;
        }
    }
}

static void blitString8x16(unsigned char *buf, int stride, int w, int h,
                           int x, int y, const char *str,
                           unsigned char r, unsigned char g, unsigned char b) {
    while(*str) {
        blitChar8x16(buf, stride, w, h, x, y, *str, r, g, b);
        x += 8;
        str++;
    }
}

static void blitFill(unsigned char *buf, int stride, int w, int h,
                     int x, int y, int rw, int rh,
                     unsigned char r, unsigned char g, unsigned char b) {
    if(x < 0) { rw += x; x = 0; }
    if(y < 0) { rh += y; y = 0; }
    if(x + rw > w) rw = w - x;
    if(y + rh > h) rh = h - y;
    for(int py = y; py < y + rh; py++) {
        unsigned char *dst = buf + py * stride + x * 4;
        for(int px = 0; px < rw; px++) {
            dst[0] = 255; dst[1] = b; dst[2] = g; dst[3] = r;
            dst += 4;
        }
    }
}

#define TERM_DEFAULT_FG 0xE8E8E8
#define TERM_HEADER_BG  0x1C2233
#define TERM_BODY_BG    0x0F1320
#define TERM_ANSI_BASE  0x8A94A6

/* ANSI SGR foreground palette (xterm-ish) */
static uint32_t termAnsiColor(int n) {
    switch(n) {
        case 30: return 0x2B2B2B;
        case 31: return 0xE06C75;
        case 32: return 0x98C379;
        case 33: return 0xE5C07B;
        case 34: return 0x61AFEF;
        case 35: return 0xC678DD;
        case 36: return 0x56B6C2;
        case 37: return 0xB8BCC4;
        default: return TERM_DEFAULT_FG;
    }
}

- (void)resetScreen {
    memset(grid, 0, sizeof(grid));
    for(int r = 0; r < TERM_ROWS; r++)
        for(int c = 0; c < TERM_COLS; c++)
            cells[r][c] = TERM_DEFAULT_FG;
    curRow = 0;
    curCol = 0;
    pendingClear = NO;
}

- (void)scrollUp {
    memmove(grid[0], grid[1], sizeof(grid[0]) * (TERM_ROWS - 1));
    memmove(cells[0], cells[1], sizeof(cells[0]) * (TERM_ROWS - 1));
    int last = TERM_ROWS - 1;
    memset(grid[last], 0, sizeof(grid[last]));
    for(int c = 0; c < TERM_COLS; c++)
        cells[last][c] = TERM_DEFAULT_FG;
}

- (void)putChar:(char)c color:(uint32_t)color {
    if(c == '\r') {
        curCol = 0;
        return;
    }
    if(c == '\n') {
        curCol = 0;
        if(++curRow >= TERM_ROWS) {
            curRow = TERM_ROWS - 1;
            [self scrollUp];
        }
        return;
    }
    if(c == '\b') {
        if(curCol > 0)
            curCol--;
        return;
    }
    if(c == '\t') {
        int next = (curCol + 8) & ~7;
        while(curCol < next && curCol < TERM_COLS - 1)
            curCol++;
        return;
    }
    if((unsigned char)c < 32)
        return;

    grid[curRow][curCol] = c;
    cells[curRow][curCol] = color;
    if(++curCol >= TERM_COLS) {
        curCol = 0;
        if(++curRow >= TERM_ROWS) {
            curRow = TERM_ROWS - 1;
            [self scrollUp];
        }
    }
}

- (void)printLine:(const char *)text color:(uint32_t)color {
    while(*text)
        [self putChar:*text++ color:color];
    [self putChar:'\n' color:color];
}

/* VT100 subset: \e[2J, \e[H, \e[K, cursor moves, SGR 3x font color */
- (void)feedBytes:(const uint8_t *)buf length:(size_t)len {
    static uint32_t fg = TERM_DEFAULT_FG;

    for(size_t i = 0; i < len; i++) {
        uint8_t c = buf[i];

        if(pendingClear) {
            if(c == '[') {
                int params[4] = {0, 0, 0, 0};
                int nparam = 0;
                size_t j = i + 1;
                while(j < len && nparam < 4) {
                    if(buf[j] == ';') {
                        nparam++;
                    } else if(buf[j] >= '0' && buf[j] <= '9') {
                        params[nparam] = params[nparam] * 10 + (buf[j] - '0');
                    } else {
                        break;
                    }
                    j++;
                }
                if(j >= len)
                    return;

                char cmd = buf[j];
                i = j;
                switch(cmd) {
                    case 'J':
                        [self resetScreen];
                        break;
                    case 'H': {
                        int row = params[0] ? params[0] - 1 : 0;
                        int col = params[1] ? params[1] - 1 : 0;
                        if(row < 0) row = 0;
                        if(col < 0) col = 0;
                        if(row >= TERM_ROWS) row = TERM_ROWS - 1;
                        if(col >= TERM_COLS) col = TERM_COLS - 1;
                        curRow = row;
                        curCol = col;
                        break;
                    }
                    case 'K':
                        for(int k = curCol; k < TERM_COLS; k++) {
                            grid[curRow][k] = 0;
                            cells[curRow][k] = TERM_DEFAULT_FG;
                        }
                        break;
                    case 'A': if(curRow > params[0]) curRow -= params[0] > 0 ? params[0] : 1; break;
                    case 'B': curRow += params[0] > 0 ? params[0] : 1;
                              if(curRow >= TERM_ROWS) curRow = TERM_ROWS - 1;
                              break;
                    case 'C': curCol += params[0] > 0 ? params[0] : 1;
                              if(curCol >= TERM_COLS) curCol = TERM_COLS - 1;
                              break;
                    case 'D': if(curCol >= (params[0] > 0 ? params[0] : 1)) curCol -= params[0];
                              else curCol = 0;
                              break;
                    case 'm':
                        fg = termAnsiColor(params[0]);
                        if(params[0] == 0 || params[0] == 39)
                            fg = TERM_DEFAULT_FG;
                        break;
                    default:
                        break;
                }
                pendingClear = NO;
                continue;
            }
            pendingClear = NO;
        }

        if(c == 0x1B) {
            pendingClear = YES;
            continue;
        }
        [self putChar:c color:fg];
    }
}

/* Pull whatever the shell has produced into the screen buffer */
- (void)timerDrain:(NSTimer *)timer {
    [self drainPty];
}

- (void)drainPty {
    if(ptyMaster < 0)
        return;

    uint8_t buf[1024];
    ssize_t n;
    int budget = 8;
    while(budget-- > 0 && (n = read(ptyMaster, buf, sizeof(buf))) > 0) {
        [self feedBytes:buf length:(size_t)n];
    }

    [self setNeedsDisplay:YES];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    return YES;
}

- (void)dealloc {
    if(logFd >= 0) {
        close(logFd);
        logFd = -1;
    }
    free(_termBuf);
    _termBuf = NULL;
    _termRep = nil;   /* ARC: assignment drops the retained reference */
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event characters];
    NSUInteger len = [chars length];
    if(ptyMaster < 0)
        return;


    for(NSUInteger i = 0; i < len; i++) {
        unichar ch = [chars characterAtIndex:i];
        uint8_t outbuf[8];
        size_t outlen = 0;

        switch(ch) {
            case NSLeftArrowFunctionKey:
                outbuf[0] = 0x1B; outbuf[1] = '['; outbuf[2] = 'D'; outlen = 3;
                break;
            case NSRightArrowFunctionKey:
                outbuf[0] = 0x1B; outbuf[1] = '['; outbuf[2] = 'C'; outlen = 3;
                break;
            case NSUpArrowFunctionKey:
                outbuf[0] = 0x1B; outbuf[1] = '['; outbuf[2] = 'A'; outlen = 3;
                break;
            case NSDownArrowFunctionKey:
                outbuf[0] = 0x1B; outbuf[1] = '['; outbuf[2] = 'B'; outlen = 3;
                break;
            case NSHomeFunctionKey:
                outbuf[0] = 0x1B; outbuf[1] = '['; outbuf[2] = 'H'; outlen = 3;
                break;
            default:
                if([event modifierFlags] & NSControlKeyMask) {
                    if(ch >= 'a' && ch <= 'z')
                        ch -= 32;
                    if(ch >= '@' && ch <= '_')
                        outbuf[0] = (uint8_t)(ch - '@');
                    else if(ch >= '`' && ch <= '~')
                        outbuf[0] = (uint8_t)(ch - '`' + 1);
                    else
                        continue;
                    outlen = 1;
                } else {
                    if(ch == '\r') {
                        outbuf[0] = '\r';
                        outlen = 1;
                    } else if(ch < 128) {
                        outbuf[0] = (uint8_t)ch;
                        outlen = 1;
                    } else {
                        continue;
                    }
                }
                break;
        }

        if(outlen > 0) {
            ssize_t wr = write(ptyMaster, outbuf, outlen);
        }
    }

    /* give the pty a moment to answer (line discipline + shell) */
    for(int wait = 0; wait < 8; wait++) {
        struct pollfd pfd;
        pfd.fd = ptyMaster;
        pfd.events = POLLIN;
        if(poll(&pfd, 1, 30) <= 0)
            continue;
        [self drainPty];
    }
}

/* Any caller that marks the terminal dirty must also invalidate the cached
 * rasterisation, otherwise the blit would keep showing a stale grid. */
-(void)setNeedsDisplay:(BOOL)flag {
    if(flag)
        _termDirty = YES;
    [super setNeedsDisplay:flag];
}

- (void)drawRect:(NSRect)rect {
    /* One image blit instead of tens of thousands of fill rects: the grid is
     * rasterised into a buffer only when the terminal state changed (drainPty
     * marks it dirty), so a redraw costs a single drawImage. */
    int w = (int)rect.size.width;
    int h = (int)rect.size.height;
    if(w <= 0 || h <= 0)
        return;

    if(_termBuf == NULL || _termW != w || _termH != h) {
        free(_termBuf);
        _termW = w;
        _termH = h;
        _termBuf = malloc((size_t)w * h * 4);
        _termRep = nil;
        _termDirty = YES;
    }

    /* AppKit's own dirty flag does not route through our -setNeedsDisplay:
     * override, so "nothing rasterised yet" has to count as dirty too. */
    if((_termDirty || _termRep == nil) && _termBuf != NULL) {
        int stride = w * 4;
        unsigned char *buf = _termBuf;

        blitFill(buf, stride, w, h, 0, 0, w, h, 15, 18, 33);

        blitFill(buf, stride, w, h, 0, h - TERM_HEADER_H, w, TERM_HEADER_H,
            (TERM_HEADER_BG >> 16) & 0xFF,
            (TERM_HEADER_BG >> 8) & 0xFF,
            TERM_HEADER_BG & 0xFF);

        int hy = h - TERM_HEADER_H - 6;
        blitString8x16(buf, stride, w, h, 10, hy,
            "ravynOS Terminal  -  /bin/sh on /dev/ptmx", 110, 153, 219);
        blitString8x16(buf, stride, w, h, w - 14 * 8, hy, "tty: ttys000", 110, 153, 219);

        for(int r = 0; r < TERM_ROWS; r++) {
            int ry = h - TERM_HEADER_H - 22 - r * 16;
            if(ry < -16)
                break;
            for(int c = 0; c < TERM_COLS; c++) {
                char ch = grid[r][c];
                if(ch == 0)
                    continue;
                uint32_t fg = cells[r][c];
                blitChar8x16(buf, stride, w, h, 10 + c * 8, ry, ch,
                    (fg >> 16) & 0xFF,
                    (fg >> 8) & 0xFF,
                    fg & 0xFF);
            }
        }

        if(curRow < TERM_ROWS) {
            int cy = h - TERM_HEADER_H - 22 - curRow * 16;
            int cx = 10 + curCol * 8;
            if(cy >= -16 && cy < h)
                blitFill(buf, stride, w, h, cx, cy, 8, 16, 77, 219, 133);
        }

        unsigned char *planes[1];
        planes[0] = _termBuf;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:planes
            pixelsWide:w
            pixelsHigh:h
            bitsPerSample:8
            samplesPerPixel:4
            hasAlpha:YES
            isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace
            bytesPerRow:stride
            bitsPerPixel:32];
        _termRep = rep;
        _termDirty = NO;
    }

    if(_termRep != nil)
        [_termRep drawInRect:rect];
}

@end
@interface FileBrowserView : NSView {
    NSString *_bp;
    NSArray *_listing;
    NSInteger _selIndex;
    NSInteger _clickRun;   /* consecutive same-row clicks; second one navigates */
    NSInteger _lastSel;
}
-(void)navigateToIndex:(NSInteger)idx;
-(NSUInteger)listingCount;
-(void)selectIndex:(NSInteger)i;
-(void)setPath:(NSString *)p;
-(NSString *)pathValue;
-(NSInteger)indexOfYInWindow:(float)y;
-(void)mouseDown:(NSEvent *)event;
-(BOOL)doubleClicked:(NSEvent *)event;
@end

@implementation FileBrowserView

-(void)setPath:(NSString *)p {
    _bp = [p copy];
    _selIndex = -1;
    [self refreshListing];
    [self setNeedsDisplay:YES];
}

-(NSString *)pathValue { return _bp ? _bp : @"/"; }

-(void)refreshListing {
    NSMutableArray *acc=[NSMutableArray array];
    NSString *p=[self pathValue];
    char pathbuf[1024];
    strncpy(pathbuf,[p UTF8String],sizeof(pathbuf)-1);
    pathbuf[sizeof(pathbuf)-1]=0;
    DIR *dp=opendir(pathbuf);
    if(dp){
        struct dirent *de;
        while((de=readdir(dp))){
            if(!strcmp(de->d_name,".") && !strcmp(de->d_name,".."))
                continue;
            [acc addObject:[NSString stringWithFormat:@"%s",de->d_name]];
        }
        closedir(dp);
    }
    NSArray *sorted=[acc sortedArrayUsingSelector:@selector(compare:)];
    _listing = sorted ? sorted : [acc copy];
}

-(NSInteger)indexOfYInWindow:(float)y {
    NSRect b=[self bounds];
    float rowh=15.0f;
    /* The event reports a *window* coordinate, so a pane that does not sit at
     * the window origin has to convert it first -- without this the row index
     * is measured from the window's bottom edge and every click lands on the
     * wrong entry (measured: a click on row 0 selected the last row). */
    NSPoint local=[self convertPoint:NSMakePoint(0.0f,y) fromView:nil];
    int idx=(int)(((local.y - b.origin.y) - 4.0f)/rowh);
    if(idx<0) idx=0;
    if(_listing && idx>=(int)[_listing count]) idx=(int)[_listing count]-1;
    if(!_listing || idx<0 || ![_listing count]) return -1;
    return idx;
}

-(void)mouseDown:(NSEvent *)event {
    NSInteger pidx=[self indexOfYInWindow:[event locationInWindow].y];
    NSInteger idx=pidx;

    /* AppKit here never synthesizes doubleClicked: -- WindowServer sends two plain
     * button-down events (CLICK50 logged code=1 at the same position twice), so pair
     * them ourselves.  A monotonic clock would be nicer, but <time.h> is not in this
     * SDK's include path; a second consecutive click on the very same row is the
     * signal we can see, which is exactly what a double-click looks like here. */
    if(_lastSel==idx){ _clickRun+=1; } else { _clickRun=0; _lastSel=idx; }
    if(_clickRun>=1){
        _clickRun = 0;                    /* consume, so a triple click navigates once */
        _lastSel = -999;                  /* next click starts a fresh pairing run */
        [self navigateToIndex:idx];
        return;
    }
    _selIndex = idx;
    [self setNeedsDisplay:YES];
}


-(NSUInteger)listingCount {
    return _listing ? [_listing count] : 0;
}

-(void)selectIndex:(NSInteger)i {
    _selIndex = i;
    [self setNeedsDisplay:YES];
}

-(void)navigateToIndex:(NSInteger)idx {
    if(idx<0 || _listing==nil || idx>=(NSInteger)[_listing count])
        return;
    NSString *name=[_listing objectAtIndex:idx];
    NSString *base=[self pathValue];
    NSString *joined;
    joined=[base isEqualToString:@"/"] ?
        [NSString stringWithFormat:@"/%@",name] :
        [[base stringByAppendingString:@"/"] stringByAppendingString:name];
    if([name hasSuffix:@".app"]){
        filerOpenBundle(joined);
        return;
    }
    [self setPath:joined];
}

-(BOOL)doubleClicked:(NSEvent *)event {
    NSInteger idx=[self indexOfYInWindow:[event locationInWindow].y];
    if(idx>=0 && _listing){
        NSString *name=[_listing objectAtIndex:idx];
        NSString *base=[self pathValue];
        NSString *joined;
        joined=[base isEqualToString:@"/"] ?
            [NSString stringWithFormat:@"/%@",name] :
            [[base stringByAppendingString:@"/"] stringByAppendingString:name];
        /* This is the double-click a user makes: a folder re-targets the pane,
         * a .app bundle runs it.  AppKit sends clickCount 2 here rather than a
         * second -mouseDown:, so the launch branch has to live in this method
         * (measured: the paired -mouseDown: never saw the second click). */
        if([name hasSuffix:@".app"] || [name hasSuffix:@".APP"]){
            filerOpenBundle(joined);
            return YES;
        }
        [self setPath:joined];
    }
    return YES;
}

-(void)drawRect:(NSRect)dirty {
    /* ClockView's text path works only because it lets the superclass set the
     * view up first; this pane and TerminalView both omitted it and painted
     * nothing. */
    [super drawRect:dirty];
    NSRect b=[self bounds];
    NSSize sz=b.size;
    NSString *p=[self pathValue];
    NSFont *font=[NSFont fontWithName:@"Inter-Regular" size:10];
    NSDictionary *attrs = (font!=nil)
        ? [NSDictionary dictionaryWithObjects:@[font,[NSColor blackColor]]
            forKeys:@[NSFontAttributeName,NSForegroundColorAttributeName]]
        : [NSDictionary dictionaryWithObjects:@[[NSColor blackColor]]
            forKeys:@[NSForegroundColorAttributeName]];
    NSAttributedString *hdr=[[NSAttributedString alloc] initWithString:p attributes:attrs];
    /* Header sits at the top-left, under the window's title bar, and every
     * listing row flows downward from just below it.  The old code anchored
     * rows at y+4 and never cleared the view, so the accumulated glyph coverage
     * of earlier draws sat behind the first visible row. */
    [hdr drawInRect:NSMakeRect(b.origin.x+4,sz.height+b.origin.y-16,sz.width-8,13)];
    if(_listing==nil) return;
    int n=(int)_listing.count;
    float rowh=15.0f;
    int rows=(int)((sz.height-20)/rowh);
    int i;
    for(i=0;i<n && i<rows;i++){
        NSString *name=[_listing objectAtIndex:i];
        NSColor *col = (_selIndex==i) ? [NSColor blueColor] : [NSColor blackColor];
        NSDictionary *ra = (font!=nil)
            ? [NSDictionary dictionaryWithObjects:@[font,col]
                forKeys:@[NSFontAttributeName,NSForegroundColorAttributeName]]
            : [NSDictionary dictionaryWithObjects:@[col]
                forKeys:@[NSForegroundColorAttributeName]];
        NSAttributedString *line=[[NSAttributedString alloc] initWithString:name attributes:ra];
        /* Use exactly the idiom the header above uses (rect height 13, origin
         * derived from sz.height - not b.origin.y plus a height computed from
         * the view's own size).  With rowh-3 and a y scaled from the view's
         * own height the same string drew as a solid bar: the rect was tall
         * enough that every glyph's coverage saturated and the rows merged. */
        [line drawInRect:NSMakeRect(b.origin.x+6,sz.height+b.origin.y-31-i*rowh,sz.width-12,13)];
    }
}

@end

@interface FilerAppDelegate : NSObject <NSApplicationDelegate> {
}
@property (strong) NSWindow *window;
@property (strong) NSString *currentPath;
@property (strong) FileBrowserView *browser;
@end

@implementation FilerAppDelegate


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    write(2, "[Filer] applicationDidFinishLaunching entered\n", 46);
    if(self.currentPath == nil)
        self.currentPath = @"/Applications";

    NSRect frame = NSMakeRect(200, 200, 800, 500);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    write(2, "[Filer] creating NSWindow\n", 26);
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    write(2, "[Filer] window created\n", 23);
    [self.window setTitle:@"Terminal - /bin/sh (ttys000)"];
    [self.window setDelegate:self];
        /* Grid is fixed (TERM_ROWS x TERM_COLS) and drawRect maps cells through
     * [self bounds].size, so shrinking the frame rescales cell metrics rather
     * than clipping text: keep the pane above the places strip so the two never
     * fight for the same surface. */
    FileBrowserView *browser=[[FileBrowserView alloc] initWithFrame:NSMakeRect(568,56,234,412)];
    [browser setPath:@"/"];
    [[self.window contentView] addSubview:browser];
    [browser setNeedsDisplay:YES];
    self.browser=browser;   /* delegate owns the pane: sibling views get no clicks */
    /* Dual-mode layout: the terminal keeps the left 560 px, the browser pane the
     * right 234 px; TerminalView's fixed grid maps through [self bounds].size so
     * the narrower frame rescales cell metrics instead of clipping text. */
    TerminalView *termView = [[TerminalView alloc] initWithFrame:NSMakeRect(0, 56, 560, 412)];
    [[self.window contentView] addSubview:termView];
    [termView setNeedsDisplay:YES];
    [self.window setInitialFirstResponder:termView];
    if([self.window makeFirstResponder:termView])
        write(2, "[Filer] TerminalView is first responder\n", 41);
    else
        write(2, "[Filer] makeFirstResponder refused\n", 35);
    /* Places live in the content view below the terminal pane: TerminalView
     * keeps its own frame so grid/scroll geometry stays as verified. */
    /* The image stages Dock under a volume-relative path (manifest entries read
     * "System/Library/CoreServices/Dock.app/..."), so don't assume one mount root:
     * probe the candidate locations and use whichever bundle actually resolves. */
    NSString *res=nil;
    for(NSString *cand in @[@"/System/Library/CoreServices",@"/Applications",@"/usr/local/share"]) {
        NSString *c=[NSString stringWithFormat:@"%@/Dock.app",cand];
        if([[NSFileManager defaultManager] fileExistsAtPath:[c stringByAppendingPathComponent:@"Contents/Info.plist"]]) {
            res=[[NSBundle bundleWithPath:c] resourcePath];
            if(res) break;
        }
    }
    DesktopPlaceView *boot=[ [DesktopPlaceView alloc] initWithFrame:NSMakeRect(8,4,150,52)];
    [boot setLabel:@"/ (boot volume)"];
    DesktopPlaceView *trash=[ [DesktopPlaceView alloc] initWithFrame:NSMakeRect(170,4,150,52)];
    [trash setLabel:@"Trash"];
    NSString *trashIcon = res ? [NSString stringWithFormat:@"%@/Trash.app/Contents/Resources/Trash.png",res] : nil;
    if(trashIcon)
        [trash setIconPath:trashIcon];
    DesktopPlaceView *home=[ [DesktopPlaceView alloc] initWithFrame:NSMakeRect(332,4,150,52)];
    [home setLabel:[NSString stringWithFormat:@"Home (%@)",NSHomeDirectory()]];
    [[self.window contentView] addSubview:boot];
    [[self.window contentView] addSubview:trash];
    [[self.window contentView] addSubview:home];
    /* Artwork sits on the window's content view: nested subviews of a view that
     * overrides drawRect: never composite in this tree, which is exactly what the
     * CLICK47 direct-attachment test proved (Filer painted 1464 dark px there). */
    if(trashIcon){
        NSImage *im=[[NSImage alloc] initWithContentsOfFile:trashIcon];
        if(im){
            NSImageView *tiv=[[NSImageView alloc] initWithFrame:NSMakeRect(178,30,36,36)];
            [tiv setImage:im];
            [tiv setNeedsDisplay:YES];
            [[self.window contentView] addSubview:tiv];
        }
    }
    /* Dock.m forces the content view to composite its subviews with an explicit
     * drawRect call ("Cocoa does not automatically redraw"), which is why Dock's
     * NSImageViews paint while ours did not -- mirror that idiom here. */
    [[self.window contentView] drawRect:[[self.window contentView] bounds]];
    [boot setNeedsDisplay:YES];
    [trash setNeedsDisplay:YES];
    [home setNeedsDisplay:YES];

    [self.window makeKeyAndOrderFront:nil];
    write(2, "[Filer] window makeKeyAndOrderFront done\n", 41);

    // Register drag and drop for application bundles and files
    [self.window registerForDraggedTypes:@[NSFilenamesPboardType, NSPasteboardTypeString]];
    write(2, "[Filer] window registered drag types\n", 37);

    const char *openAtLaunch = getenv("RAVYN_FILER_OPEN");
    if(openAtLaunch != NULL) {
        NSString *target = [NSString stringWithUTF8String:openAtLaunch];
        if([target hasSuffix:@".app"] || [target hasSuffix:@".APP"]) {
            write(2, "[Filer] RAVYN_FILER_OPEN bundle\n", 32);
            filerOpenBundle(target);
        } else {
            write(2, "[Filer] RAVYN_FILER_OPEN folder\n", 32);
            [self.browser setPath:target];
        }
    }
}

- (BOOL)installBundleFromPath:(NSString *)sourcePath toDirectory:(NSString *)destDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *fileName = [sourcePath lastPathComponent];
    NSString *targetPath = [destDir stringByAppendingPathComponent:fileName];

    NSError *error = nil;
    if ([fm fileExistsAtPath:targetPath]) {
        [fm removeItemAtPath:targetPath error:nil];
    }

    BOOL success = [fm copyItemAtPath:sourcePath toPath:targetPath error:&error];
    if (success) {
        NSLog(@"Filer: Installed bundle %@ to %@", fileName, targetPath);
    } else {
        NSLog(@"Filer: Error installing bundle %@: %@", fileName, [error localizedDescription]);
    }
    return success;
}

- (void)openItemAtPath:(NSString *)itemPath {
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:itemPath isDirectory:&isDir]) {
        if ([itemPath hasSuffix:@".app"] || [itemPath hasSuffix:@".APP"]) {
            filerOpenBundle(itemPath);
        }
    }
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    // NSPasteboard has no readObjectsForClasses:options:; the filenames type
    // carries an NSArray of path strings through propertyListForType:.
    NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
    if (files) {
        for (NSString *path in files) {
            [self installBundleFromPath:path toDirectory:self.currentPath];
        }
        return YES;
    }
    return NO;
}

@end

int main(int argc, const char *argv[]) {
    extern void bootstrap_init(void);
    write(2, "[Filer] main entered\n", 21);
    bootstrap_init();
    write(2, "[Filer] bootstrap_init done\n", 28);
    @autoreleasepool {
        write(2, "[Filer] initializing NSApplication\n", 35);
        NSApplication *app = [NSApplication sharedApplication];
        write(2, "[Filer] creating FilerAppDelegate\n", 34);
        FilerAppDelegate *delegate = [FilerAppDelegate new];
        [app setDelegate:delegate];
        /* RAVYN_FILER_OPEN lets a boot, a shell or a test harness exercise the
         * bundle-opening path without driving pointer events: Filer opens that
         * path once the window is up, exactly as a double-click would. */
        const char *openAtLaunch = getenv("RAVYN_FILER_OPEN");
        if(openAtLaunch != NULL) {
            delegate.currentPath = [NSString stringWithUTF8String:openAtLaunch];
        }
        write(2, "[Filer] calling app run\n", 24);
        [app run];
    }
    return 0;
}
