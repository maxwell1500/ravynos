/*
 * ravynOS Application Launcher & Status Bar
 *
 * Copyright (C) 2021-2024 Zoe Knox <zoe@pixin.net>
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

#include <mach/message.h>
#import "Dock.h"
#import "DockItem.h"
#import "DockTileData.h"
#import "WindowServer/message.h"
#import "WindowServer/rpc.h"
#import <LaunchServices/LaunchServices.h>

/* WindowServer RPC entry point, provided by libWindowServer on ravynOS. Same
 * forward declaration as WindowServer.m:59, AppKit/NSWindow.m:69 and
 * CoreGraphics/CGDirectDisplay.m:66; WindowServer/rpc.h defines only the
 * WSRPC codes, not the entry point. */
kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);

#define RUNMK_DIAMETER 8
#define RUNMK_SPACER 2

@implementation DockItem

+dockItemWithPath:(NSString *)path {
    return [[DockItem alloc] initWithPath:path];
}

+dockItemWithMinimizedWindow:(unsigned int)window forApp:(DockItem *)appItem {
    return [[DockItem alloc] initWithMinimizedWindow:window forApp:appItem];
}

+(int)iconSize {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    int size = [prefs integerForKey:INFOKEY_TILESIZE];
    return size ? size : 64;
}

/* Application Dock Tiles

   An application Dock tile defaults to display the application’s
   applicationIconImage.

   The application Dock tile never shows a smaller application icon badge.

   Whether using the default or custom view, the application Dock tile may be
   badged with a short custom string.
*/

-initWithPath:(NSString *)path {
    _path = path;
    _label = nil;
    _type = DIT_INVALID;
    _icon = nil;
    _iconImage = NULL;
    _bundleID = nil;
    _app = nil;
    _isRunning = NO;
    _special = NO;
    int size = [DockItem iconSize];

    self = [super initWithFrame:NSMakeRect(0,0,size,size + 16)];
    // first, walk the path for .app or .AppDir in case this is the
    // path to the actual executable inside
    NSArray *comps = [path pathComponents];
    for(int i = [comps count] - 1; i >= 0; --i) {
        if([[comps objectAtIndex:i] hasSuffix:@"app"] == YES) {
            path = [NSString stringWithFormat:@"/%@",
                [NSString pathWithComponents:
                [comps subarrayWithRange:NSMakeRange(0,i+1)]]];
            break;
        }
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    if(LSIsNSBundle((__bridge CFURLRef)url)) {
        _type = DIT_APP_BUNDLE;
        NSBundle *b = [NSBundle bundleWithPath:path];
        _label = [b objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if(!_label)
            _label = [b objectForInfoDictionaryKey:@"CFBundleName"];
        _execPath = [b executablePath];

        NSString *rsc = [[NSBundle mainBundle] resourcePath];
        if([[b bundlePath] hasPrefix:rsc])
            _special = YES;

        NSString *iconFile = [b objectForInfoDictionaryKey:
            @"CFBundleIconFile"];
        if(!iconFile)
            iconFile = [b objectForInfoDictionaryKey:@"NSIcon"];
        NSString *iconPath = [NSString stringWithFormat:@"%@/Contents/Resources/%@",path,iconFile];

        _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(
            0,RUNMK_DIAMETER+2*RUNMK_SPACER,size,size)];
        [_icon setImage:[[NSImage alloc] initWithContentsOfFile:iconPath]];
        [[_icon image] setScalesWhenResized:YES];
        [_icon setImageScaling:NSImageScaleProportionallyUpOrDown];

        _bundleID = [b objectForInfoDictionaryKey:@"CFBundleIdentifier"];
        if(_bundleID == nil)
            _bundleID = [NSString stringWithFormat:@"unknown.bundle.%x", self];
    } else if(LSIsAppDir((__bridge CFURLRef)url)) {
        _type = DIT_APP_APPDIR;
        _execPath = [_path stringByAppendingPathComponent:@"AppRun"];
        _label = [[path lastPathComponent] stringByDeletingPathExtension];
        NSString *iconFile = [NSString stringWithFormat:@"%@/.DirIcon", path];
        if([[NSFileManager defaultManager] fileExistsAtPath:iconFile]) {
            _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(
                0,RUNMK_DIAMETER+2*RUNMK_SPACER,size,size)];
            [_icon setImage:[[NSImage alloc] initWithContentsOfFile:iconFile]];
            [[_icon image] setScalesWhenResized:YES];
            [_icon setImageScaling:NSImageScaleProportionallyUpOrDown];
        }
    }

    // A tile whose bundle has no usable CFBundleIconFile (or whose app is not
    // installed at all) still got an NSImageView from the branches above -- one
    // with no image -- so testing _icon alone left such tiles blank and this
    // fallback was dead code.  Test the image as well.
    if(_icon == nil || [_icon image] == nil) {
        NSString *windowPNG = [[NSBundle mainBundle] pathForResource:@"window" ofType:@"png"];
        _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(
            0,RUNMK_DIAMETER+2*RUNMK_SPACER,size,size)];
        [_icon setImage:[[NSImage alloc] initWithContentsOfFile:windowPNG]];
        [[_icon image] setScalesWhenResized:YES];
        [_icon setImageScaling:NSImageScaleProportionallyUpOrDown];
    }

    // Whatever the branches above loaded, pull a CGImage out of it so
    // drawRect: can composite the icon directly.  The control layer in this
    // tree never paints -- an NSImageView has no working draw path -- so a
    // tile that relies on one stays blank.  DockView paints the tray behind
    // the tiles with raw CoreGraphics, and this does the same for the icon.
    {
        NSArray *reps = [[_icon image] representations];
        NSUInteger i, count = [reps count];
        for(i = 0; i < count; ++i) {
            NSImageRep *rep = [reps objectAtIndex:i];
            if([rep isKindOfClass:[NSBitmapImageRep class]]) {
                _iconImage = CGImageRetain([(NSBitmapImageRep *)rep CGImage]);
                break;
            }
        }
    }

    _origIcon = _icon;
    [self addSubview:_icon];

    _flags = DIF_NORMAL;
    if([_bundleID isEqualToString:@"com.ravynos.Filer"] || [_bundleID hasPrefix:@"com.ravynos.Dock"])
        [self setLocked:YES];

    _windows = [NSMutableArray new];

    NSString *marker = [[NSBundle mainBundle] pathForResource:@"running" ofType:@"png"];
    _runMarker = [[NSImageView alloc] initWithFrame:NSMakeRect(
        size/2 - RUNMK_DIAMETER/2, RUNMK_SPACER, RUNMK_DIAMETER, RUNMK_DIAMETER)];
    [_runMarker setImage:[[NSImage alloc] initWithContentsOfFile:marker]];
    [[_runMarker image] setScalesWhenResized:YES];

    [_icon setTarget:self];
    [_icon setAction:@selector(openApp:)];
    return self;
}

/*
  Window Dock Tiles
  
  A window Dock tile defaults to display a miniaturized version of the windows
  contents with a badge derived from the application Dock icon, including any
  customized application Dock icon. The default window Dock tile image may not
  be badged with a custom string.

  A window Dock tile can use a custom view to draw the Dock icon. If a custom
  view is used, no application badge will be added, but the text label will be
  overlaid on top of the icon.
*/

-initWithMinimizedWindow:(unsigned int)window forApp:(DockItem *)appItem {
    _path = nil;
    _execPath = nil;
    _label = nil;
    _app = appItem;
    _type = DIT_WINDOW;
    _isRunning = NO;
    _special = NO;
    int size = [DockItem iconSize];
    self = [super initWithFrame:NSMakeRect(0,0,size,size+16)];

    NSString *windowPNG = [[NSBundle mainBundle] pathForResource:@"window" ofType:@"png"];
    _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(
        size*0.2, RUNMK_DIAMETER+2*RUNMK_SPACER, size-(size*0.2), size-RUNMK_DIAMETER-RUNMK_SPACER)];
    [_icon setImageScaling:NSImageScaleProportionallyUpOrDown];
    [_icon setImage:[[NSImage alloc] initWithContentsOfFile:windowPNG]];
    [[_icon image] setScalesWhenResized:YES];

    _origIcon = _icon;
    [self addSubview:_icon];

    if(appItem != nil) {
        _badge = [[NSImageView alloc] initWithFrame:
            NSMakeRect(0,RUNMK_DIAMETER+2*RUNMK_SPACER,size*0.55,size*0.55)];
        [_badge setImageScaling:NSImageScaleProportionallyUpOrDown];
        [_badge setImage:[appItem icon]];
        [[_badge image] setScalesWhenResized:YES];
        [self addSubview:_badge];
    }

    _bundleID = nil;
    _flags = DIF_NORMAL;
    _windows = [NSMutableArray new];
    [_windows addObject:[NSNumber numberWithInteger:window]];

    [_icon setTarget:self];
    [_icon setAction:@selector(activateWindow:)];
    return self;
}

-(void)drawRect:(NSRect)rect {
    [super drawRect:rect];

    // Composite the tile's icon with CoreGraphics.  This tree's control layer
    // has no working draw path, so an NSImageView added as a subview never
    // reliably puts pixels on screen; DockView paints the tray behind the
    // tiles the same way this paints the artwork on top of it.
    if(_iconImage == NULL || _icon == nil)
        return;

    // NB: DockItem declares its own -window returning the window *ID*, which
    // shadows NSView's.  Reach past it for the NSWindow.
    CGContextRef context = [[[super window] graphicsContext] graphicsPort];
    if(context == NULL)
        return;

    NSRect box = [_icon frame];
    CGContextDrawImage(context,
        CGRectMake(box.origin.x, box.origin.y, box.size.width, box.size.height),
        _iconImage);
}

-(void)drawIconInContext:(CGContextRef)context {
    if(_iconImage == NULL || _icon == nil || context == NULL)
        return;

    NSRect tile = [self frame];
    NSRect box = [_icon frame];
    CGContextDrawImage(context,
        CGRectMake(tile.origin.x + box.origin.x, tile.origin.y + box.origin.y,
                   box.size.width, box.size.height),
        _iconImage);
}

-(void)setTileSize:(NSSize)size {
    NSSize framesize = size;
    /* The run marker sits under the icon (RUNMK_DIAMETER + 2*RUNMK_SPACER,
     * 12px) so the window is taller than the artwork.  Keep the icon centred in
     * the strip between the marker and the top: `size` alone would push a 64px
     * icon to y=12..76 of an 80px tile and clip its bottom edge against the
     * rounded tray. */
    framesize.height += RUNMK_DIAMETER+2*RUNMK_SPACER;
    [self setFrameSize:framesize];
    [_icon setFrameSize:size];
    [_icon setFrameOrigin:NSMakePoint(0,RUNMK_DIAMETER+2*RUNMK_SPACER)];
    [self setNeedsDisplay:YES];
}

-(NSString *)path {
    return _path;
}

-(NSString *)execPath {
    return _execPath;
}

-(NSString *)bundleIdentifier {
    return _bundleID;
}

-(NSString *)label {
    return _label;
}

-(DockItemType)type {
    return _type;
}

-(DockItemFlags)flags {
    return (DockItemFlags)_flags;
}

-(BOOL)isNormal {
    return (_flags == DIF_NORMAL) ? YES : NO;
}

-(BOOL)isLocked {
    return (_flags & DIF_LOCKED) ? YES : NO;
}

-(BOOL)isRunning {
    return _isRunning;
}

-(BOOL)isPersistent {
    return (_flags & DIF_PERSISTENT) ? YES : NO;
}

-(BOOL)needsAttention {
    return (_flags & DIF_ATTENTION) ? YES : NO;
}

-(BOOL)isSpecial {
    return _special;
}

-(unsigned int)window {
    if(_windows && [_windows count])
        return [[_windows firstObject] intValue];
    return 0;
}

-(NSArray *)windows {
    return [NSArray arrayWithArray:_windows];
}

-(NSImage *)icon {
    return [_icon image];
}

-(DockItem *)app {
    return _app;
}

// YES if equal to either item path
// YES if bundle and path is within bundle
// NO otherwise
-(BOOL)hasPath:(NSString *)path {
    if([path isEqualToString:_execPath] || [path isEqualToString:_path])
        return YES;

    if(_type != DIT_APP_BUNDLE)
        return NO;

    NSArray *comps = [path pathComponents];
    // FIXME: should this be reverse order to find sub bundles?
    for(int i = [comps count] - 1; i >= 0; --i) {
        if([[comps objectAtIndex:i] hasSuffix:@"app"] == YES) {
            NSString *newpath = [NSString stringWithFormat:@"/%@",
            [NSString pathWithComponents:
                [comps subarrayWithRange:NSMakeRange(0,i+1)]]];
            NSBundle *b = [NSBundle bundleWithModulePath:newpath];
            if([[b bundlePath] isEqualToString:_path])
                return YES;
        }
    }
    return NO;
}

-(void)setFlags:(DockItemFlags)flags {
    _flags = flags;
}

-(void)setNormal {
    _flags = DIF_NORMAL;
}

-(void)setLocked:(BOOL)value {
    if(value == YES)
        _flags |= DIF_LOCKED;
    else
        _flags &= ~DIF_LOCKED;
}

-(void)setRunning:(BOOL)value {
    BOOL _currentlyRunning = _isRunning;
    _isRunning = value;

    if(_currentlyRunning && !_isRunning) {
        [_runMarker removeFromSuperview];
    } else if(!_currentlyRunning && _isRunning) {
        [self addSubview:_runMarker];
    }
    [self setNeedsDisplay:YES];
}

-(void)addWindow:(unsigned int)window {
    for(int i = 0; i < [_windows count]; ++i) {
        if([[_windows objectAtIndex:i] intValue] == window)
            return;
    }
    [_windows addObject:[NSNumber numberWithInteger:window]];
}

-(void)removeWindow:(unsigned int)window {
    for(int i = 0; i < [_windows count]; ++i) {
        if([[_windows objectAtIndex:i] intValue] == window) {
            [_windows removeObjectAtIndex:i];
            return;
        }
    }
}

-(void)setPersistent:(BOOL)value {
    if(value == YES)
        _flags |= DIF_PERSISTENT;
    else
        _flags &= ~DIF_PERSISTENT;
}

-(void)setNeedsAttention:(BOOL)value {
    if(value == YES)
        _flags |= DIF_ATTENTION;
    else
        _flags &= ~DIF_ATTENTION;
}

-(void)setApplicationIconImage:(NSImage *)image {
    if(image == nil) { // user wants to remove customization
        [_icon removeFromSuperview];
        _icon = _origIcon;
        [self addSubview:_icon];
        return;
    }

    [image setScalesWhenResized:YES];
    [_icon setImage:image];
}

/*
The view you specify should be height and width resizable.

Cocoa does not automatically redraw the contents of your dock tile. Instead,
your application must explicitly send display messages to the dock tile object
whenever the contents of your view change and need to be redrawn. Your dock
tile view is responsible for drawing the entire contents of the dock tile. Your
view does not need to draw the application or custom string badges.
*/

-(void)setContentView:(NSView *)contentView {
    [_icon removeFromSuperview];
    _icon = contentView;
    [self addSubview:_icon];
}

// This is called when a miniaturized window icon is clicked. Restore it and
// activate the owning app.
-(void)activateWindow:(id)sender {
    int windowNumber = [[_windows firstObject] intValue];
    struct {
        struct wsRPCWindow win;
        char buf[128];
    } data = {
        .win = {
            .base = {
                .code = kWSApplicationActivate,
                .len = sizeof(struct wsRPCWindow) - sizeof(struct wsRPCBase),
            },
            .windowID = windowNumber,
            .state = NORMAL,
        },
        '\0',
    };

    strncpy(data.buf, [[[self app] bundleIdentifier] UTF8String], sizeof(data.buf));
    data.win.base.len += strlen(data.buf);
    _windowServerRPC(&data, sizeof(data), NULL, NULL);
}

/* Launch a tile's bundle.  LaunchServices is deliberately not used: an
   in-process LSOpenCFURLRef dlopens LaunchServices and crashes the client
   (measured: EX_CORPSE_NOTIFY, followed by "[WS] DESTROY win=..." for the
   Dock's own window).  WindowServer forks the bundle from its main loop
   instead, which is the only context in which the child can resolve
   com.ravynos.WindowServer for its startup handshake. */
- (void)_launchBundle {
    if(!_path)
        return;

    if([[NSApplication sharedApplication] openBundlePath:_path])
        return;

    /* Fallback for a bundle WindowServer cannot take: resolve the executable
       from the bundle layout and run it locally.  NSBundle is not consulted --
       on this tree bundleWithPath: returns nil for paths that are known-good,
       which silently dropped every launch. */
    NSString *name = [[_path lastPathComponent] stringByDeletingPathExtension];
    NSArray *candidates = @[
        [NSString stringWithFormat:@"%@/Contents/ravynOS/%@", _path, name],
        [NSString stringWithFormat:@"%@/Contents/MacOS/%@", _path, name],
        [NSString stringWithFormat:@"%@/%@", _path, name],
    ];

    const char *exe = NULL;
    for(NSString *candidate in candidates) {
        const char *c = [candidate UTF8String];
        if(c != NULL && access(c, X_OK) == 0) {
            exe = c;
            break;
        }
    }
    if(exe == NULL)
        return;

    pid_t pid = fork();
    if(pid == 0) {
        char argvbuf[512];
        snprintf(argvbuf, sizeof argvbuf, "%s", [name UTF8String]);
        char *argv[2];
        argv[0] = argvbuf;
        argv[1] = NULL;
        execve(exe, argv, NULL);
        _exit(1);
    }
}

-(void)openApp:(id)sender {
    if(![self isRunning]) {
        [self _launchBundle];
    } else {
        struct {
            struct wsRPCWindow win;
            char buf[128];
        } data = {
            .win = {
                .base = {
                    .code = kWSApplicationActivate,
                    .len = sizeof(struct wsRPCWindow) - sizeof(struct wsRPCBase),
                },
                .windowID = 0,
                .state = NORMAL,
            },
            '\0',
        };

        strncpy(data.buf, [[self bundleIdentifier] UTF8String], sizeof(data.buf));
        data.win.base.len += strlen(data.buf);
        _windowServerRPC(&data, sizeof(data), NULL, NULL);
    }
}

-(void)_installTileClickProxy {
    NSMutableArray *ordered = [NSMutableArray new];
    NSArray *subs = [[self subviews] copy];
    for(NSView *v in subs) {
        if([v isKindOfClass:[NSTileClickProxy class]])
            continue;
        [ordered addObject:v];
    }
    NSTileClickProxy *proxy = [[NSTileClickProxy alloc] initWithFrame:[self bounds]];
    [proxy setTileOwner:self];
    [ordered addObject:proxy];
    [self setSubviews:ordered];
}

-(NSDictionary *)tileData {
    return dockTileData(_path);
}

-(NSString *)description {
    return [NSString stringWithFormat:
    @"<%@ 0x%p> path:%@ exec:%@ label:%@ windows:%@ flags:0x%02x id:%@",
    [self class], self, _path, _execPath, _label, _windows, _flags,
    _bundleID];
}
/**/
@end

@implementation NSTileClickProxy
-(void)setTileOwner:(id)owner {
    _tileOwner = owner;
}

-(void)mouseDown:(NSEvent *)event {
    if(_tileOwner != nil)
        [_tileOwner openApp:self];
}
@end
