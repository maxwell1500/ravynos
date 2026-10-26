/*
 * SDL2 Video & Window subsystem for ravynOS.
 * Bridges SDL_Window directly to AppKit NSWindow + Onyx2D/WindowServer shared memory.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2Surface.h>
#include "SDL_ravynos_internal.h"
#include <stdlib.h>
#include <string.h>

@interface SDLRavynContentView : NSView {
@public
    SDL_Window *_sdlWindow;
}
- (instancetype)initWithFrame:(NSRect)frame sdlWindow:(SDL_Window *)sdlWin;
@end

@interface SDLRavynWindowDelegate : NSObject {
@public
    SDL_Window *_sdlWindow;
}
- (instancetype)initWithSDLWindow:(SDL_Window *)sdlWin;
@end

static SDL_Window *g_window_list = NULL;
static Uint32 g_next_window_id = 1;
static SDL_bool g_screensaver_enabled = SDL_TRUE;

@implementation SDLRavynContentView

- (instancetype)initWithFrame:(NSRect)frame sdlWindow:(SDL_Window *)sdlWin {
    self = [super initWithFrame:frame];
    if (self) {
        _sdlWindow = sdlWin;
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)canBecomeKeyView {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    /* Rendering is driven directly into the window's shared-memory surface
     * by SDL_UpdateWindowSurface / SDL_RenderPresent; avoid overwriting it
     * with a blank NSView background clear. */
}

@end

@implementation SDLRavynWindowDelegate

- (instancetype)initWithSDLWindow:(SDL_Window *)sdlWin {
    self = [super init];
    if (self) {
        _sdlWindow = sdlWin;
    }
    return self;
}

- (BOOL)windowShouldClose:(id)sender {
    (void)sender;
    if (_sdlWindow) {
        SDL_Event w_ev;
        memset(&w_ev, 0, sizeof(w_ev));
        w_ev.type = SDL_WINDOWEVENT;
        w_ev.window.timestamp = SDL_GetTicks();
        w_ev.window.windowID = _sdlWindow->id;
        w_ev.window.event = SDL_WINDOWEVENT_CLOSE;
        SDL_RavynPushEventInternal(&w_ev);

        SDL_Event q_ev;
        memset(&q_ev, 0, sizeof(q_ev));
        q_ev.type = SDL_QUIT;
        q_ev.quit.timestamp = SDL_GetTicks();
        SDL_RavynPushEventInternal(&q_ev);
    }
    return NO;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    (void)notification;
    if (_sdlWindow) {
        _sdlWindow->flags |= SDL_WINDOW_INPUT_FOCUS;
        SDL_Event ev;
        memset(&ev, 0, sizeof(ev));
        ev.type = SDL_WINDOWEVENT;
        ev.window.timestamp = SDL_GetTicks();
        ev.window.windowID = _sdlWindow->id;
        ev.window.event = SDL_WINDOWEVENT_FOCUS_GAINED;
        SDL_RavynPushEventInternal(&ev);
    }
}

- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    if (_sdlWindow) {
        _sdlWindow->flags &= ~SDL_WINDOW_INPUT_FOCUS;
        SDL_Event ev;
        memset(&ev, 0, sizeof(ev));
        ev.type = SDL_WINDOWEVENT;
        ev.window.timestamp = SDL_GetTicks();
        ev.window.windowID = _sdlWindow->id;
        ev.window.event = SDL_WINDOWEVENT_FOCUS_LOST;
        SDL_RavynPushEventInternal(&ev);
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    if (_sdlWindow && _sdlWindow->nswindow) {
        NSWindow *nswin = (NSWindow *)_sdlWindow->nswindow;
        NSRect contentRect = [[nswin contentView] frame];
        int nw = (int)contentRect.size.width;
        int nh = (int)contentRect.size.height;
        if (nw > 0 && nh > 0 && (nw != _sdlWindow->w || nh != _sdlWindow->h)) {
            _sdlWindow->w = nw;
            _sdlWindow->h = nh;
            _sdlWindow->surface_valid = SDL_FALSE;
            SDL_Event ev;
            memset(&ev, 0, sizeof(ev));
            ev.type = SDL_WINDOWEVENT;
            ev.window.timestamp = SDL_GetTicks();
            ev.window.windowID = _sdlWindow->id;
            ev.window.event = SDL_WINDOWEVENT_RESIZED;
            ev.window.data1 = nw;
            ev.window.data2 = nh;
            SDL_RavynPushEventInternal(&ev);
        }
    }
}

@end

SDL_Window *SDL_RavynGetWindowList(void) {
    return g_window_list;
}

int SDL_RavynVideoInit(void) {
    if (NSApp == nil) {
        [NSApplication sharedApplication];
    }
    /* SDL drives its own event loop, so NSApplication.run never runs and the
     * launch sequence has to be completed explicitly.  Without this a window
     * can be created and ordered front, and then the activation path that
     * orderFront triggers dereferences state that only finishLaunching sets
     * up -- the window appears and the process dies, which is what this port
     * did until the trace showed the crash inside makeKeyAndOrderFront. */
    static SDL_bool launchFinished = SDL_FALSE;
    if (!launchFinished) {
        [NSApp finishLaunching];
        launchFinished = SDL_TRUE;
        SDL_RavynTrace("finishLaunching done");
    }
    return 0;
}

void SDL_RavynVideoQuit(void) {
    while (g_window_list) {
        SDL_DestroyWindow(g_window_list);
    }
}

int SDL_GetNumVideoDrivers(void) {
    return 1;
}

const char *SDL_GetVideoDriver(int index) {
    return (index == 0) ? "ravynOS" : NULL;
}

int SDL_VideoInit(const char *driver_name) {
    (void)driver_name;
    return SDL_RavynVideoInit();
}

void SDL_VideoQuit(void) {
    SDL_RavynVideoQuit();
}

const char *SDL_GetCurrentVideoDriver(void) {
    return "ravynOS";
}

int SDL_GetNumVideoDisplays(void) {
    return 1;
}

const char *SDL_GetDisplayName(int displayIndex) {
    if (displayIndex != 0) {
        SDL_SetError("Invalid display index");
        return NULL;
    }
    return "ravynOS Display";
}

int SDL_GetDisplayBounds(int displayIndex, SDL_Rect *rect) {
    if (displayIndex != 0) return SDL_SetError("Invalid display index");
    CGRect bounds = CGDisplayBounds(CGMainDisplayID());
    int w = (int)bounds.size.width;
    int h = (int)bounds.size.height;
    if (w <= 0 || h <= 0) {
        w = 1920;
        h = 1080;
    }
    if (rect) {
        rect->x = (int)bounds.origin.x;
        rect->y = (int)bounds.origin.y;
        rect->w = w;
        rect->h = h;
    }
    return 0;
}

int SDL_GetDisplayUsableBounds(int displayIndex, SDL_Rect *rect) {
    if (SDL_GetDisplayBounds(displayIndex, rect) < 0) return -1;
    if (rect && rect->h > 28) {
        rect->y += 24;
        rect->h -= 24;
    }
    return 0;
}

int SDL_GetDisplayDPI(int displayIndex, float *ddpi, float *hdpi, float *vdpi) {
    if (displayIndex != 0) return SDL_SetError("Invalid display index");
    if (ddpi) *ddpi = 96.0f;
    if (hdpi) *hdpi = 96.0f;
    if (vdpi) *vdpi = 96.0f;
    return 0;
}

SDL_DisplayOrientation SDL_GetDisplayOrientation(int displayIndex) {
    (void)displayIndex;
    return SDL_ORIENTATION_LANDSCAPE;
}

int SDL_GetNumDisplayModes(int displayIndex) {
    return (displayIndex == 0) ? 1 : SDL_SetError("Invalid display index");
}

int SDL_GetDisplayMode(int displayIndex, int modeIndex, SDL_DisplayMode *mode) {
    if (displayIndex != 0 || modeIndex != 0) return SDL_SetError("Invalid display/mode index");
    SDL_Rect r;
    SDL_GetDisplayBounds(0, &r);
    if (mode) {
        mode->format = SDL_PIXELFORMAT_ARGB8888;
        mode->w = r.w;
        mode->h = r.h;
        mode->refresh_rate = 60;
        mode->driverdata = NULL;
    }
    return 0;
}

int SDL_GetDesktopDisplayMode(int displayIndex, SDL_DisplayMode *mode) {
    return SDL_GetDisplayMode(displayIndex, 0, mode);
}

int SDL_GetCurrentDisplayMode(int displayIndex, SDL_DisplayMode *mode) {
    return SDL_GetDisplayMode(displayIndex, 0, mode);
}

SDL_DisplayMode *SDL_GetClosestDisplayMode(int displayIndex, const SDL_DisplayMode *mode, SDL_DisplayMode *closest) {
    (void)mode;
    if (!closest) return NULL;
    if (SDL_GetDisplayMode(displayIndex, 0, closest) < 0) return NULL;
    return closest;
}

int SDL_GetPointDisplayIndex(const SDL_Point *point) {
    (void)point;
    return 0;
}

int SDL_GetRectDisplayIndex(const SDL_Rect *rect) {
    (void)rect;
    return 0;
}

int SDL_GetWindowDisplayIndex(SDL_Window *window) {
    (void)window;
    return 0;
}

int SDL_SetWindowDisplayMode(SDL_Window *window, const SDL_DisplayMode *mode) {
    (void)window;
    (void)mode;
    return 0;
}

int SDL_GetWindowDisplayMode(SDL_Window *window, SDL_DisplayMode *mode) {
    if (!window || !mode) return SDL_SetError("Invalid window/mode");
    mode->format = SDL_PIXELFORMAT_ARGB8888;
    mode->w = window->w;
    mode->h = window->h;
    mode->refresh_rate = 60;
    mode->driverdata = NULL;
    return 0;
}

Uint32 SDL_GetWindowPixelFormat(SDL_Window *window) {
    (void)window;
    return SDL_PIXELFORMAT_ARGB8888;
}

SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, Uint32 flags) {
    if (SDL_RavynVideoInit() < 0) return NULL;

    if (w <= 0) w = 640;
    if (h <= 0) h = 480;

    SDL_Rect disp;
    SDL_GetDisplayBounds(0, &disp);
    if (SDL_WINDOWPOS_ISCENTERED(x) || SDL_WINDOWPOS_ISUNDEFINED(x)) {
        x = (disp.w > w) ? (disp.w - w) / 2 : 64;
    }
    if (SDL_WINDOWPOS_ISCENTERED(y) || SDL_WINDOWPOS_ISUNDEFINED(y)) {
        y = (disp.h > h) ? (disp.h - h) / 2 : 64;
    }

    SDL_Window *win = (SDL_Window *)calloc(1, sizeof(SDL_Window));
    if (!win) {
        SDL_OutOfMemory();
        return NULL;
    }
    win->id = g_next_window_id++;
    win->title = strdup(title ? title : "SDL2 Application");
    win->x = x;
    win->y = y;
    win->w = w;
    win->h = h;
    win->opacity = 1.0f;
    win->flags = flags | SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_MOUSE_FOCUS;
    if (!(flags & SDL_WINDOW_HIDDEN)) {
        win->flags |= SDL_WINDOW_SHOWN;
    }

    /* No autorelease pool in here.  Draining one immediately after the window
     * is ordered front frees objects AppKit is still using (the frame view's
     * deferred display state among them), and the crash lands after the window
     * is already visible, which reads as "the window came up and the process
     * died".  The window and its views are owned by this function's +1
     * references, so nothing here depends on a pool. */
    /* Always use borderless or titled window cleanly so content matches w x h */
    NSUInteger styleMask = NSBorderlessWindowMask;
    if (!(flags & (SDL_WINDOW_BORDERLESS | SDL_WINDOW_FULLSCREEN))) {
        styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
        if (flags & SDL_WINDOW_RESIZABLE) {
            styleMask |= NSResizableWindowMask;
        }
    }
    SDL_RavynTrace("styleMask=0x%lx flags=0x%x", (unsigned long)styleMask, (unsigned)flags);

    /* Convert top-left (x, y) to AppKit bottom-left screen origin */
    CGFloat cocoaY = (CGFloat)(disp.h - y - h);
    if (cocoaY < 0) cocoaY = 40;
    NSRect contentRect = NSMakeRect((CGFloat)x, cocoaY, (CGFloat)w, (CGFloat)h);

    NSWindow *nswin = [[NSWindow alloc] initWithContentRect:contentRect
                                                  styleMask:styleMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    SDL_RavynTrace("window %p created", (void *)nswin);
    if (nswin) {
        [nswin setTitle:[NSString stringWithUTF8String:win->title]];
        [nswin setAcceptsMouseMovedEvents:YES];

        SDLRavynContentView *view = [[SDLRavynContentView alloc] initWithFrame:NSMakeRect(0, 0, w, h)
                                                                     sdlWindow:win];
        [nswin setContentView:view];
        SDL_RavynTrace("content view installed");
        [nswin makeFirstResponder:view];
        SDL_RavynTrace("first responder set");

        SDLRavynWindowDelegate *del = [[SDLRavynWindowDelegate alloc] initWithSDLWindow:win];
        [nswin setDelegate:(id)del];
        SDL_RavynTrace("delegate installed");
        SDL_RavynTrace("delegate installed");

        win->nswindow = nswin;
        win->nsview = view;

        if (win->flags & SDL_WINDOW_SHOWN) {
            /* The same steps as -makeKeyAndOrderFront:, one at a time, each
             * followed by a trace line: AppKit's version is a composite and a
             * fault inside it says nothing about which part failed.  Keeping
             * the steps explicit also lets the window become visible without
             * becoming key, which is what a window that never gets focus
             * (a splash or a borderless game window) wants. */
            SDL_RavynTrace("orderFront start");
            [nswin orderFront:nil];
            SDL_RavynTrace("orderFront done");
            /* Reaching here means AppKit finished the whole ordering cycle,
             * including the frame view's display pass.  Trace it because the
             * absence of this line is what a hang in that pass looks like. */
            if (!(flags & SDL_WINDOW_BORDERLESS)) {
                [nswin makeKeyWindow];
                SDL_RavynTrace("makeKeyWindow done");
            }
            [nswin display];
            SDL_RavynTrace("display done");
            [nswin flushWindow];
            SDL_RavynTrace("flush done");
        }
    }

    win->next = g_window_list;
    g_window_list = win;

    if (win->flags & SDL_WINDOW_SHOWN) {
        SDL_Event ev;
        memset(&ev, 0, sizeof(ev));
        ev.type = SDL_WINDOWEVENT;
        ev.window.timestamp = SDL_GetTicks();
        ev.window.windowID = win->id;
        ev.window.event = SDL_WINDOWEVENT_SHOWN;
        SDL_RavynPushEventInternal(&ev);

        ev.window.event = SDL_WINDOWEVENT_EXPOSED;
        SDL_RavynPushEventInternal(&ev);
    }
    SDL_RavynTrace("SDL_CreateWindow returning %p", (void *)win);

    return win;
}

SDL_Window *SDL_CreateWindowFrom(const void *data) {
    (void)data;
    return SDL_CreateWindow("SDL2 Native Window", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 640, 480, SDL_WINDOW_SHOWN);
}

Uint32 SDL_GetWindowID(SDL_Window *window) {
    return window ? window->id : 0;
}

SDL_Window *SDL_GetWindowFromID(Uint32 id) {
    SDL_Window *curr = g_window_list;
    while (curr) {
        if (curr->id == id) return curr;
        curr = curr->next;
    }
    return NULL;
}

Uint32 SDL_GetWindowFlags(SDL_Window *window) {
    return window ? window->flags : 0;
}

void SDL_SetWindowTitle(SDL_Window *window, const char *title) {
    if (!window) return;
    free(window->title);
    window->title = strdup(title ? title : "");
    if (window->nswindow) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [(NSWindow *)window->nswindow setTitle:[NSString stringWithUTF8String:window->title]];
        [pool release];
    }
}

const char *SDL_GetWindowTitle(SDL_Window *window) {
    return (window && window->title) ? window->title : "";
}

void SDL_SetWindowIcon(SDL_Window *window, SDL_Surface *icon) {
    (void)window;
    (void)icon;
}

void *SDL_SetWindowData(SDL_Window *window, const char *name, void *userdata) {
    if (!window || !name) return NULL;
    SDLRavynDataEntry *curr = (SDLRavynDataEntry *)window->userdata;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            void *prev = curr->value;
            curr->value = userdata;
            return prev;
        }
        curr = curr->next;
    }
    SDLRavynDataEntry *entry = (SDLRavynDataEntry *)calloc(1, sizeof(SDLRavynDataEntry));
    if (!entry) return NULL;
    entry->name = strdup(name);
    entry->value = userdata;
    entry->next = (SDLRavynDataEntry *)window->userdata;
    window->userdata = entry;
    return NULL;
}

void *SDL_GetWindowData(SDL_Window *window, const char *name) {
    if (!window || !name) return NULL;
    SDLRavynDataEntry *curr = (SDLRavynDataEntry *)window->userdata;
    while (curr) {
        if (strcmp(curr->name, name) == 0) return curr->value;
        curr = curr->next;
    }
    return NULL;
}

void SDL_SetWindowPosition(SDL_Window *window, int x, int y) {
    if (!window) return;
    SDL_Rect disp;
    SDL_GetDisplayBounds(0, &disp);
    if (SDL_WINDOWPOS_ISCENTERED(x) || SDL_WINDOWPOS_ISUNDEFINED(x)) {
        x = (disp.w > window->w) ? (disp.w - window->w) / 2 : 64;
    }
    if (SDL_WINDOWPOS_ISCENTERED(y) || SDL_WINDOWPOS_ISUNDEFINED(y)) {
        y = (disp.h > window->h) ? (disp.h - window->h) / 2 : 64;
    }
    window->x = x;
    window->y = y;
    if (window->nswindow) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        CGFloat cocoaY = (CGFloat)(disp.h - y - window->h);
        [(NSWindow *)window->nswindow setFrameOrigin:NSMakePoint((CGFloat)x, cocoaY)];
        [pool release];
    }
}

void SDL_GetWindowPosition(SDL_Window *window, int *x, int *y) {
    if (!window) return;
    if (x) *x = window->x;
    if (y) *y = window->y;
}

void SDL_SetWindowSize(SDL_Window *window, int w, int h) {
    if (!window || w <= 0 || h <= 0) return;
    window->w = w;
    window->h = h;
    window->surface_valid = SDL_FALSE;
    if (window->nswindow) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [(NSWindow *)window->nswindow setContentSize:NSMakeSize((CGFloat)w, (CGFloat)h)];
        [pool release];
    }
}

void SDL_GetWindowSize(SDL_Window *window, int *w, int *h) {
    if (!window) return;
    if (w) *w = window->w;
    if (h) *h = window->h;
}

void SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h) {
    SDL_GetWindowSize(window, w, h);
}

int SDL_GetWindowBordersSize(SDL_Window *window, int *top, int *left, int *bottom, int *right) {
    (void)window;
    if (top) *top = 22;
    if (left) *left = 0;
    if (bottom) *bottom = 0;
    if (right) *right = 0;
    return 0;
}

void SDL_SetWindowMinimumSize(SDL_Window *window, int min_w, int min_h) {
    if (!window) return;
    window->min_w = min_w;
    window->min_h = min_h;
}

void SDL_GetWindowMinimumSize(SDL_Window *window, int *w, int *h) {
    if (!window) return;
    if (w) *w = window->min_w;
    if (h) *h = window->min_h;
}

void SDL_SetWindowMaximumSize(SDL_Window *window, int max_w, int max_h) {
    if (!window) return;
    window->max_w = max_w;
    window->max_h = max_h;
}

void SDL_GetWindowMaximumSize(SDL_Window *window, int *w, int *h) {
    if (!window) return;
    if (w) *w = window->max_w;
    if (h) *h = window->max_h;
}

void SDL_SetWindowBordered(SDL_Window *window, SDL_bool bordered) {
    if (!window) return;
    if (bordered) window->flags &= ~SDL_WINDOW_BORDERLESS;
    else window->flags |= SDL_WINDOW_BORDERLESS;
}

void SDL_SetWindowResizable(SDL_Window *window, SDL_bool resizable) {
    if (!window) return;
    if (resizable) window->flags |= SDL_WINDOW_RESIZABLE;
    else window->flags &= ~SDL_WINDOW_RESIZABLE;
}

void SDL_SetWindowAlwaysOnTop(SDL_Window *window, SDL_bool on_top) {
    if (!window) return;
    if (on_top) window->flags |= SDL_WINDOW_ALWAYS_ON_TOP;
    else window->flags &= ~SDL_WINDOW_ALWAYS_ON_TOP;
}

void SDL_ShowWindow(SDL_Window *window) {
    if (!window) return;
    window->flags = (window->flags & ~SDL_WINDOW_HIDDEN) | SDL_WINDOW_SHOWN;
    if (window->nswindow) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [(NSWindow *)window->nswindow makeKeyAndOrderFront:nil];
        [pool release];
    }
}

void SDL_HideWindow(SDL_Window *window) {
    if (!window) return;
    window->flags = (window->flags & ~SDL_WINDOW_SHOWN) | SDL_WINDOW_HIDDEN;
    if (window->nswindow) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [(NSWindow *)window->nswindow orderOut:nil];
        [pool release];
    }
}

void SDL_RaiseWindow(SDL_Window *window) {
    SDL_ShowWindow(window);
}

void SDL_MaximizeWindow(SDL_Window *window) {
    if (window) window->flags |= SDL_WINDOW_MAXIMIZED;
}

void SDL_MinimizeWindow(SDL_Window *window) {
    if (!window) return;
    window->flags |= SDL_WINDOW_MINIMIZED;
    if (window->nswindow) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [(NSWindow *)window->nswindow miniaturize:nil];
        [pool release];
    }
}

void SDL_RestoreWindow(SDL_Window *window) {
    if (!window) return;
    window->flags &= ~(SDL_WINDOW_MAXIMIZED | SDL_WINDOW_MINIMIZED);
}

int SDL_SetWindowFullscreen(SDL_Window *window, Uint32 flags) {
    if (!window) return -1;
    window->flags = (window->flags & ~(SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP)) |
                    (flags & (SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP));
    return 0;
}

SDL_Surface *SDL_GetWindowSurface(SDL_Window *window) {
    if (!window) {
        SDL_SetError("Invalid window");
        return NULL;
    }
    if (!window->surface || !window->surface_valid ||
        window->surface->w != window->w || window->surface->h != window->h) {
        if (window->surface) {
            SDL_FreeSurface(window->surface);
            window->surface = NULL;
        }
        window->surface = SDL_CreateRGBSurfaceWithFormat(0, window->w, window->h, 32, SDL_PIXELFORMAT_ARGB8888);
        window->surface_valid = (window->surface != NULL) ? SDL_TRUE : SDL_FALSE;
    }
    return window->surface;
}

int SDL_UpdateWindowSurface(SDL_Window *window) {
    if (!window || !window->surface) {
        return SDL_SetError("Window surface is invalid");
    }
    if (!window->nswindow) {
        return 0;
    }

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSWindow *nswin = (NSWindow *)window->nswindow;
    O2Context *ctx = (O2Context *)[nswin cgContext];
    SDL_RavynTrace("present ctx=%p", (void *)ctx);
    if (ctx != nil) {
        O2Surface *o2surf = [ctx surface];
        /* A nil surface means the window has no backing store yet (its shared
         * memory mapping failed); dereferencing it here would fault inside the
         * rasteriser for a condition that is recoverable -- the next present
         * retries. */
        if (o2surf == nil) {
            [pool release];
            return 0;
        }
        uint8_t *dst_base = (uint8_t *)O2SurfaceGetPixelBytes(o2surf);
        size_t dst_bpr = O2SurfaceGetBytesPerRow(o2surf);
        int dst_w = (int)O2SurfaceGetWidth(o2surf);
        int dst_h = (int)O2SurfaceGetHeight(o2surf);

        /* In NSWindow on ravynOS, the O2Surface covers the full window frame
         * (including the 22px titlebar at the top when titled). Content area
         * occupies the bottom window->h rows (or starts at y_off from top). */
        int y_off = (dst_h > window->h) ? (dst_h - window->h) : 0;
        int copy_w = (window->surface->w < dst_w) ? window->surface->w : dst_w;
        int copy_h = (window->surface->h < (dst_h - y_off)) ? window->surface->h : (dst_h - y_off);

        /* The client surface must fit inside the backing row, or the copy
         * below writes past the end of the mapping. */
        if (dst_bpr < (size_t)copy_w * 4) {
            copy_w = (int)(dst_bpr / 4);
        }
        if (dst_base != NULL && copy_w > 0 && copy_h > 0) {
            const uint8_t *src_base = (const uint8_t *)window->surface->pixels;
            int src_pitch = window->surface->pitch;
            for (int row = 0; row < copy_h; row++) {
                const uint32_t *srow = (const uint32_t *)(src_base + row * src_pitch);
                uint32_t *drow = (uint32_t *)(dst_base + (y_off + row) * dst_bpr);
                for (int col = 0; col < copy_w; col++) {
                    /* Ensure opaque alpha so WindowServer composites solid window content */
                    drow[col] = srow[col] | 0xFF000000U;
                }
            }
        }
        [nswin flushWindow];
    }
    [pool release];
    return 0;
}

int SDL_UpdateWindowSurfaceRects(SDL_Window *window, const SDL_Rect *rects, int numrects) {
    (void)rects;
    (void)numrects;
    return SDL_UpdateWindowSurface(window);
}

int SDL_DestroyWindowSurface(SDL_Window *window) {
    if (!window) return -1;
    if (window->surface) {
        SDL_FreeSurface(window->surface);
        window->surface = NULL;
    }
    window->surface_valid = SDL_FALSE;
    return 0;
}

SDL_bool SDL_HasWindowSurface(SDL_Window *window) {
    return (window && window->surface && window->surface_valid) ? SDL_TRUE : SDL_FALSE;
}

void SDL_SetWindowGrab(SDL_Window *window, SDL_bool grabbed) {
    if (!window) return;
    if (grabbed) window->flags |= SDL_WINDOW_INPUT_GRABBED;
    else window->flags &= ~SDL_WINDOW_INPUT_GRABBED;
}

void SDL_SetWindowKeyboardGrab(SDL_Window *window, SDL_bool grabbed) {
    SDL_SetWindowGrab(window, grabbed);
}

void SDL_SetWindowMouseGrab(SDL_Window *window, SDL_bool grabbed) {
    SDL_SetWindowGrab(window, grabbed);
}

SDL_bool SDL_GetWindowGrab(SDL_Window *window) {
    return (window && (window->flags & SDL_WINDOW_INPUT_GRABBED)) ? SDL_TRUE : SDL_FALSE;
}

SDL_bool SDL_GetWindowKeyboardGrab(SDL_Window *window) {
    return SDL_GetWindowGrab(window);
}

SDL_bool SDL_GetWindowMouseGrab(SDL_Window *window) {
    return SDL_GetWindowGrab(window);
}

SDL_Window *SDL_GetGrabbedWindow(void) {
    SDL_Window *curr = g_window_list;
    while (curr) {
        if (curr->flags & SDL_WINDOW_INPUT_GRABBED) return curr;
        curr = curr->next;
    }
    return NULL;
}

int SDL_SetWindowMouseRect(SDL_Window *window, const SDL_Rect *rect) {
    (void)window; (void)rect;
    return 0;
}

const SDL_Rect *SDL_GetWindowMouseRect(SDL_Window *window) {
    (void)window;
    return NULL;
}

int SDL_SetWindowBrightness(SDL_Window *window, float brightness) {
    (void)window; (void)brightness;
    return 0;
}

float SDL_GetWindowBrightness(SDL_Window *window) {
    (void)window;
    return 1.0f;
}

int SDL_SetWindowOpacity(SDL_Window *window, float opacity) {
    if (!window) return -1;
    window->opacity = opacity;
    return 0;
}

int SDL_GetWindowOpacity(SDL_Window *window, float *out_opacity) {
    if (!window) return -1;
    if (out_opacity) *out_opacity = window->opacity;
    return 0;
}

int SDL_SetWindowModalFor(SDL_Window *modal_window, SDL_Window *parent_window) {
    (void)modal_window; (void)parent_window;
    return 0;
}

int SDL_SetWindowInputFocus(SDL_Window *window) {
    SDL_RaiseWindow(window);
    return 0;
}

int SDL_SetWindowGammaRamp(SDL_Window *window, const Uint16 *red, const Uint16 *green, const Uint16 *blue) {
    (void)window; (void)red; (void)green; (void)blue;
    return 0;
}

int SDL_GetWindowGammaRamp(SDL_Window *window, Uint16 *red, Uint16 *green, Uint16 *blue) {
    (void)window; (void)red; (void)green; (void)blue;
    return 0;
}

int SDL_SetWindowHitTest(SDL_Window *window, SDL_HitTest callback, void *callback_data) {
    (void)window; (void)callback; (void)callback_data;
    return 0;
}

int SDL_FlashWindow(SDL_Window *window, SDL_FlashOperation operation) {
    (void)window; (void)operation;
    return 0;
}

void SDL_DestroyWindow(SDL_Window *window) {
    if (!window) return;

    SDL_Window **pp = &g_window_list;
    while (*pp) {
        if (*pp == window) {
            *pp = window->next;
            break;
        }
        pp = &((*pp)->next);
    }

    if (window->renderer) {
        SDL_Renderer *r = window->renderer;
        window->renderer = NULL;
        SDL_DestroyRenderer(r);
    }

    if (window->surface) {
        SDL_FreeSurface(window->surface);
        window->surface = NULL;
    }

    if (window->nswindow) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSWindow *nswin = (NSWindow *)window->nswindow;
        [nswin setDelegate:nil];
        [nswin orderOut:nil];
        [nswin close];
        window->nswindow = NULL;
        [pool release];
    }

    SDLRavynDataEntry *curr = (SDLRavynDataEntry *)window->userdata;
    while (curr) {
        SDLRavynDataEntry *next = curr->next;
        free(curr->name);
        free(curr);
        curr = next;
    }

    free(window->title);
    free(window);
}

SDL_bool SDL_IsScreenSaverEnabled(void) {
    return g_screensaver_enabled;
}

void SDL_EnableScreenSaver(void) {
    g_screensaver_enabled = SDL_TRUE;
}

void SDL_DisableScreenSaver(void) {
    g_screensaver_enabled = SDL_FALSE;
}

SDL_bool SDL_GetWindowWMInfo(SDL_Window *window, SDL_SysWMinfo *info) {
    if (!window || !info) return SDL_FALSE;
    info->subsystem = SDL_SYSWM_COCOA;
#if defined(SDL_VIDEO_DRIVER_COCOA)
    info->info.cocoa.window = (NSWindow *)window->nswindow;
#endif
    return SDL_TRUE;
}

/* OpenGL / Vulkan / Metal stub hooks so SDL2 callers probing GL/Metal don't fail link */
int SDL_GL_LoadLibrary(const char *path) { (void)path; return SDL_SetError("OpenGL not supported on ravynOS"); }
void *SDL_GL_GetProcAddress(const char *proc) { (void)proc; return NULL; }
void SDL_GL_UnloadLibrary(void) {}
SDL_bool SDL_GL_ExtensionSupported(const char *extension) { (void)extension; return SDL_FALSE; }
void SDL_GL_ResetAttributes(void) {}
int SDL_GL_SetAttribute(SDL_GLattr attr, int value) { (void)attr; (void)value; return 0; }
int SDL_GL_GetAttribute(SDL_GLattr attr, int *value) { (void)attr; if (value) *value = 0; return 0; }
SDL_GLContext SDL_GL_CreateContext(SDL_Window *window) { (void)window; SDL_SetError("OpenGL context not available"); return NULL; }
int SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context) { (void)window; (void)context; return -1; }
SDL_Window *SDL_GL_GetCurrentWindow(void) { return NULL; }
SDL_GLContext SDL_GL_GetCurrentContext(void) { return NULL; }
void SDL_GL_GetDrawableSize(SDL_Window *window, int *w, int *h) { SDL_GetWindowSize(window, w, h); }
int SDL_GL_SetSwapInterval(int interval) { (void)interval; return 0; }
int SDL_GL_GetSwapInterval(void) { return 1; }
void SDL_GL_SwapWindow(SDL_Window *window) { SDL_UpdateWindowSurface(window); }
void SDL_GL_DeleteContext(SDL_GLContext context) { (void)context; }
