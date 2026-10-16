/*
 * FilerMain.m - ravynOS Desktop File Manager (Filer.app)
 *
 * Provides desktop file browsing, bundle execution via LaunchServices,
 * and drag-and-drop .app bundle installation into /Applications.
 *
 * Copyright (C) 2026 Jack Davenport. All rights reserved.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import <CoreGraphics/CoreGraphics.h>
#include <unistd.h>
#include <sys/stat.h>

static void filerOpenBundle(NSString *path) {
    if(!path) return;
    // Preferred route: WindowServer spawns the bundle for us
    if([[NSApplication sharedApplication] openBundlePath:path])
        return;

    // Fallback: run it locally
    NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
    NSString *cands[3];
    cands[0] = [NSString stringWithFormat:@"%@/Contents/ravynOS/%@", path, name];
    cands[1] = [NSString stringWithFormat:@"%@/Contents/MacOS/%@", path, name];
    cands[2] = [NSString stringWithFormat:@"%@/%@", path, name];

    const char *exe = NULL;
    for(int i = 0; i < 3; i++) {
        const char *c = [cands[i] UTF8String];
        if(c != NULL && access(c, X_OK) == 0) {
            exe = c;
            break;
        }
    }
    if(exe == NULL) return;

    pid_t pid = fork();
    if(pid == 0) {
        char argvbuf[512];
        snprintf(argvbuf, sizeof(argvbuf), "%s", name ? [name UTF8String] : "app");
        char *argv[2] = { argvbuf, NULL };
        char *envp[1] = { NULL };
        execve(exe, argv, envp);
        _exit(1);
    }
}

@interface FileItem : NSObject
@property (copy) NSString *name;
@property (copy) NSString *fullPath;
@property (assign) BOOL isDirectory;
@property (assign) BOOL isApp;
@property (strong) NSImage *icon;
- (NSComparisonResult)compareFileItem:(FileItem *)other;
@end

@implementation FileItem
- (NSComparisonResult)compareFileItem:(FileItem *)other {
    if(self.isApp != other.isApp)
        return self.isApp ? NSOrderedAscending : NSOrderedDescending;
    if(self.isDirectory != other.isDirectory)
        return self.isDirectory ? NSOrderedAscending : NSOrderedDescending;
    return [self.name caseInsensitiveCompare:other.name];
}
@end

@interface FileBrowserView : NSView {
    NSString *_currentPath;
    NSMutableArray *_items;
    NSInteger _selectedIndex;
    NSTimeInterval _lastClickTime;
    NSInteger _lastClickedIndex;
}
- (void)loadPath:(NSString *)path;
- (NSString *)currentPath;
@end

@implementation FileBrowserView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        _items = [NSMutableArray new];
        _selectedIndex = -1;
        _lastClickedIndex = -1;
        _lastClickTime = 0;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSString *)currentPath {
    return _currentPath;
}

- (NSImage *)iconForPath:(NSString *)path isApp:(BOOL)isApp isDir:(BOOL)isDir {
    if(isApp) {
        NSString *plistPath = [path stringByAppendingPathComponent:@"Contents/Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSString *iconName = [info objectForKey:@"CFBundleIconFile"];
        if(iconName) {
            if(![iconName hasSuffix:@".png"] && ![iconName hasSuffix:@".icns"])
                iconName = [iconName stringByAppendingPathExtension:@"png"];
            NSString *iconFile = [path stringByAppendingPathComponent:
                [NSString stringWithFormat:@"Contents/Resources/%@", iconName]];
            NSImage *img = [[NSImage alloc] initWithContentsOfFile:iconFile];
            if(img) return img;
        }
        NSString *resDir = [path stringByAppendingPathComponent:@"Contents/Resources"];
        NSArray *resFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:resDir error:nil];
        for(NSString *rf in resFiles) {
            if([rf hasSuffix:@".png"]) {
                NSImage *img = [[NSImage alloc] initWithContentsOfFile:[resDir stringByAppendingPathComponent:rf]];
                if(img) return img;
            }
        }
    }
    NSString *bundleIcon = [[NSBundle mainBundle] pathForResource:@"filer" ofType:@"png"];
    if(bundleIcon) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:bundleIcon];
        if(img) return img;
    }
    return nil;
}

- (void)loadPath:(NSString *)path {
    _currentPath = [path copy];
    [_items removeAllObjects];
    _selectedIndex = -1;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fm contentsOfDirectoryAtPath:_currentPath error:&error];
    if(!files) {
        [self setNeedsDisplay:YES];
        return;
    }

    for(NSString *file in files) {
        if([file hasPrefix:@"."])
            continue;
        NSString *full = [_currentPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        if(![fm fileExistsAtPath:full isDirectory:&isDir])
            continue;

        FileItem *item = [FileItem new];
        item.name = file;
        item.fullPath = full;
        item.isDirectory = isDir;
        item.isApp = [file hasSuffix:@".app"] || [file hasSuffix:@".APP"];
        item.icon = [self iconForPath:full isApp:item.isApp isDir:isDir];
        [_items addObject:item];
    }

    [_items sortUsingSelector:@selector(compareFileItem:)];
    [self setNeedsDisplay:YES];
}

#define CELL_W 100.0f
#define CELL_H 100.0f
#define ICON_SZ 48.0f

- (NSInteger)itemIndexAtPoint:(NSPoint)pt {
    NSRect bounds = [self bounds];
    int cols = (int)(bounds.size.width / CELL_W);
    if(cols < 1) cols = 1;

    int col = (int)(pt.x / CELL_W);
    int row = (int)(pt.y / CELL_H);
    if(col < 0 || col >= cols || row < 0)
        return -1;

    NSInteger idx = row * cols + col;
    if(idx >= 0 && idx < (NSInteger)[_items count])
        return idx;
    return -1;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger idx = [self itemIndexAtPoint:loc];

    NSTimeInterval now = [event timestamp];
    BOOL isDouble = (idx >= 0 && idx == _lastClickedIndex && (now - _lastClickTime) < 0.6);
    _lastClickTime = now;
    _lastClickedIndex = idx;

    _selectedIndex = idx;
    [self setNeedsDisplay:YES];

    if(idx >= 0) {
        FileItem *item = [_items objectAtIndex:idx];
        if(isDouble || [event clickCount] >= 2) {
            if(item.isApp) {
                filerOpenBundle(item.fullPath);
            } else if(item.isDirectory) {
                [self loadPath:item.fullPath];
                [[self window] setTitle:[NSString stringWithFormat:@"Filer - %@", item.fullPath]];
            }
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = [self bounds];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    if(ctx) {
        CGContextSetRGBFillColor(ctx, 0.98, 0.98, 0.98, 1.0);
        CGContextFillRect(ctx, CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height));
    }

    int cols = (int)(bounds.size.width / CELL_W);
    if(cols < 1) cols = 1;

    NSFont *font = [NSFont fontWithName:@"Inter-Regular" size:11];
    if(!font)
        font = [NSFont systemFontOfSize:11];

    NSDictionary *textAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
        font, NSFontAttributeName,
        [NSColor blackColor], NSForegroundColorAttributeName,
        nil];

    NSDictionary *selTextAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
        font, NSFontAttributeName,
        [NSColor whiteColor], NSForegroundColorAttributeName,
        nil];

    for(NSInteger i = 0; i < (NSInteger)[_items count]; i++) {
        FileItem *item = [_items objectAtIndex:i];
        int col = (int)(i % cols);
        int row = (int)(i / cols);

        float cellX = col * CELL_W;
        float cellY = row * CELL_H;

        if(i == _selectedIndex && ctx) {
            CGContextSetRGBFillColor(ctx, 0.18, 0.50, 0.92, 0.85);
            CGContextFillRect(ctx, CGRectMake(cellX + 4, cellY + 4, CELL_W - 8, CELL_H - 8));
        }

        float iconX = cellX + (CELL_W - ICON_SZ) / 2.0f;
        float iconY = cellY + 8.0f;
        NSRect iconRect = NSMakeRect(iconX, iconY, ICON_SZ, ICON_SZ);

        if(item.icon) {
            [item.icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        } else if(ctx) {
            CGContextSetRGBFillColor(ctx, 0.20, 0.55, 0.90, 1.0);
            CGContextFillRect(ctx, CGRectMake(iconX + 6, iconY + 6, ICON_SZ - 12, ICON_SZ - 12));
        }

        NSString *displayName = item.name;
        if(item.isApp && [displayName hasSuffix:@".app"])
            displayName = [displayName substringToIndex:[displayName length] - 4];

        NSDictionary *curAttrs = (i == _selectedIndex) ? selTextAttrs : textAttrs;
        NSRect labelRect = NSMakeRect(cellX + 2, cellY + ICON_SZ + 12.0f, CELL_W - 4, 30.0f);
        [displayName drawInRect:labelRect withAttributes:curAttrs];
    }
}

@end

@interface FilerAppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSString *currentPath;
@property (strong) FileBrowserView *browserView;
@end

@implementation FilerAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.currentPath = @"/Applications";

    NSRect frame = NSMakeRect(200, 200, 720, 480);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [self.window setTitle:@"Applications"];
    [self.window setDelegate:self];

    NSRect contentBounds = [[self.window contentView] bounds];
    self.browserView = [[FileBrowserView alloc] initWithFrame:contentBounds];
    [self.browserView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[self.window contentView] addSubview:self.browserView];
    [self.browserView loadPath:self.currentPath];

    [self.window makeKeyAndOrderFront:nil];

    [self.window registerForDraggedTypes:@[NSFilenamesPboardType, NSStringPboardType]];
}

- (BOOL)windowShouldClose:(id)sender {
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
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
        [self.browserView loadPath:self.currentPath];
    } else {
        NSLog(@"Filer: Error installing bundle %@: %@", fileName, [error localizedDescription]);
    }
    return success;
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
    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        if([files isKindOfClass:[NSArray class]]) {
            for (NSString *path in files) {
                [self installBundleFromPath:path toDirectory:self.currentPath];
            }
            return YES;
        }
    }
    return NO;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        FilerAppDelegate *delegate = [FilerAppDelegate new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
