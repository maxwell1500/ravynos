/*
 * FilerMain.m - ravynOS Desktop File Manager (Filer.app)
 *
 * Copyright (C) 2026 Jack Davenport and contributors. All rights reserved.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import <LaunchServices/LaunchServices.h>
#import <CoreGraphics/CoreGraphics.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <dirent.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

typedef enum {
    FilerViewModeIcons   = 0,
    FilerViewModeList    = 1,
    FilerViewModeColumns = 2
} FilerViewMode;

static void filerOpenBundle(NSString *path) {
    if(!path) return;

    /* Ask WindowServer to launch it.  A GUI child has to inherit launchd's
     * bootstrap context, which only WindowServer's own children get; a fork
     * from Filer inherits Filer's, and the application comes up unable to
     * reach the window server.  WindowServer also reads CFBundleExecutable
     * from Info.plist, so a bundle whose executable is not named after the
     * bundle still launches (this used to guess three fixed paths). */
    if([[NSApplication sharedApplication] openBundlePath:path])
        return;

    /* Fallback for a Filer with no window-server connection (for example one
     * started from a terminal by hand): exec the bundle's executable, and
     * pass the environment through instead of an empty one, or the child
     * inherits nothing it needs to find its own frameworks. */
    NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
    NSString *cands[3];
    cands[0] = [NSString stringWithFormat:@"%@/Contents/ravynOS/%@", path, name];
    cands[1] = [NSString stringWithFormat:@"%@/Contents/MacOS/%@", path, name];
    cands[2] = [NSString stringWithFormat:@"%@/%@", path, name];
    const char *exe = NULL;
    for(int i = 0; i < 3; i++) {
        const char *c = [cands[i] UTF8String];
        if(c != NULL && access(c, X_OK) == 0) { exe = c; break; }
    }
    if(exe == NULL) return;
    pid_t pid = fork();
    if(pid == 0) {
        char argvbuf[512];
        snprintf(argvbuf, sizeof(argvbuf), "%s", name ? [name UTF8String] : "app");
        char *argv[2] = { argvbuf, NULL };
        extern char **environ;
        execve(exe, argv, environ);
        _exit(1);
    }
}

static NSString *filerFormatSize(off_t bytes) {
    if(bytes < 1024) return [NSString stringWithFormat:@"%lld B", (long long)bytes];
    else if(bytes < 1048576) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    else if(bytes < 1073741824LL) return [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
    else return [NSString stringWithFormat:@"%.2f GB", bytes / 1073741824.0];
}

static NSDate *filerDateFromStat(struct stat *st, BOOL created) {
    time_t t = created ? st->st_birthtime : st->st_mtime;
    if(t == 0) t = st->st_mtime;
    return [NSDate dateWithTimeIntervalSince1970:t];
}

@interface FileItem : NSObject
@property (copy) NSString *name;
@property (copy) NSString *fullPath;
@property (assign) BOOL isDirectory;
@property (assign) BOOL isApp;
@property (assign) BOOL isExecutable;
@property (assign) off_t size;
@property (assign) mode_t mode;
@property (assign) uid_t uid;
@property (assign) gid_t gid;
@property (strong) NSDate *created;
@property (strong) NSDate *modified;
@property (strong) NSImage *icon;
@property (assign) NSInteger depth;   /* list-view expansion level */
- (NSComparisonResult)compareFileItem:(FileItem *)other;
- (NSComparisonResult)compareByName:(FileItem *)other;
- (NSComparisonResult)compareByDate:(FileItem *)other;
- (NSComparisonResult)compareBySize:(FileItem *)other;
- (NSComparisonResult)compareByKind:(FileItem *)other;
- (NSString *)kindString;
@end

@implementation FileItem
- (NSComparisonResult)compareFileItem:(FileItem *)other {
    if(self.isApp != other.isApp) return self.isApp ? NSOrderedAscending : NSOrderedDescending;
    if(self.isDirectory != other.isDirectory) return self.isDirectory ? NSOrderedAscending : NSOrderedDescending;
    return [self.name caseInsensitiveCompare:other.name];
}
- (NSComparisonResult)compareByName:(FileItem *)o { return [self.name caseInsensitiveCompare:o.name]; }
- (NSComparisonResult)compareByDate:(FileItem *)o { return [self.modified compare:o.modified]; }
- (NSComparisonResult)compareBySize:(FileItem *)o { if(self.size < o.size) return NSOrderedAscending; if(self.size > o.size) return NSOrderedDescending; return NSOrderedSame; }
- (NSComparisonResult)compareByKind:(FileItem *)o { return [[self kindString] caseInsensitiveCompare:[o kindString]]; }
- (NSString *)kindString {
    if(self.isApp) return @"Application";
    if(self.isDirectory) return @"Folder";
    if(self.isExecutable) return @"Unix Executable";
    return @"Document";
}
@end

@class FilerWindowController;

@interface PlaceItem : NSObject
@property (copy) NSString *title;
@property (copy) NSString *path;
+ (instancetype)itemWithTitle:(NSString *)title path:(NSString *)path;
@end

@implementation PlaceItem
+ (instancetype)itemWithTitle:(NSString *)title path:(NSString *)path {
    PlaceItem *pi = [PlaceItem new];
    pi.title = title; pi.path = path; return pi;
}
@end

#define TOOLBAR_H   38.0f
#define STATUS_H    22.0f
#define SIDEBAR_W   145.0f
#define CELL_W      100.0f
#define CELL_H      96.0f
#define ICON_SZ     48.0f
#define LIST_ROW_H  24.0f
#define LIST_HDR_H  22.0f
#define COL_W       180.0f
#define PREVIEW_W   240.0f

@interface FileBrowserView : NSView {
    NSString *_currentPath;
    NSMutableArray *_items;
    NSMutableArray *_places;
    NSMutableArray *_backStack;
    NSMutableArray *_forwardStack;
    NSInteger _selectedIndex;
    NSMutableIndexSet *_selectedIndexes;
    NSTimeInterval _lastClickTime;
    NSInteger _lastClickedIndex;
    FilerViewMode _viewMode;
    CGFloat _scrollOffsetY;
    NSString *_customStatusText;

    NSString *_sortColumn;
    BOOL _sortAscending;
    NSMutableSet *_expandedPaths;

    NSMutableArray *_columnItems; // NSArray<NSMutableArray<FileItem*>>
    NSInteger _columnSelectedCol;
    NSInteger _columnSelectedRow;
    FileItem *_previewItem;

    NSRect _marqueeRect;
    BOOL _marqueeActive;
    NSPoint _marqueeStart;
    NSPoint _dragOrigin;
    BOOL _dragOriginValid;

    // inline rename
    NSTextField *_renameField;
    NSInteger _renameIndex;

    NSRect _btnBackRect, _btnFwdRect, _btnUpRect, _btnIconsRect, _btnListRect, _btnColsRect;
    NSMutableArray *_crumbRects, *_crumbPaths;
}
- (void)loadPath:(NSString *)path addToHistory:(BOOL)add;
- (void)loadPath:(NSString *)path;
- (NSString *)currentPath;
- (void)goBack; - (void)goForward; - (void)goUp;
- (void)setViewMode:(FilerViewMode)mode;
- (FilerViewMode)viewMode;
- (void)refresh;
- (void)createNewFolder;
- (void)beginInlineRenameAtIndex:(NSInteger)idx;
- (void)duplicateSelected;
- (void)moveSelectedToTrash;
- (void)emptyTrash;
- (void)showGetInfoForItem:(FileItem *)item;
- (void)copySelectedToPasteboard;
- (void)pasteFromPasteboardMove:(BOOL)move;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@implementation FileBrowserView

- (NSImage *)iconForPath:(NSString *)path isApp:(BOOL)isApp isDir:(BOOL)isDir {
    if(isApp) {
        NSString *plistPath = [path stringByAppendingPathComponent:@"Contents/Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSString *iconName = [info objectForKey:@"CFBundleIconFile"];
        if(iconName) {
            if(![iconName hasSuffix:@".png"] && ![iconName hasSuffix:@".icns"]) iconName = [iconName stringByAppendingPathExtension:@"png"];
            NSString *iconFile = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"Contents/Resources/%@", iconName]];
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
    return nil;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        _items = [NSMutableArray new];
        _places = [NSMutableArray new];
        _backStack = [NSMutableArray new];
        _forwardStack = [NSMutableArray new];
        _crumbRects = [NSMutableArray new];
        _crumbPaths = [NSMutableArray new];
        _selectedIndex = -1;
        _selectedIndexes = [NSMutableIndexSet new];
        _lastClickedIndex = -1;
        _lastClickTime = 0;
        _viewMode = FilerViewModeIcons;
        _scrollOffsetY = 0;
        _expandedPaths = [NSMutableSet new];
        _columnItems = [NSMutableArray new];
        _columnSelectedCol = 0;
        _columnSelectedRow = -1;
        _sortColumn = @"Name";
        _sortAscending = YES;
        _renameIndex = -1;

        [self registerForDraggedTypes:@[NSFilenamesPboardType, NSPasteboardTypeFileURL]];

        [_places addObject:[PlaceItem itemWithTitle:@"Root (/)" path:@"/"]];
        [_places addObject:[PlaceItem itemWithTitle:@"System" path:@"/System"]];
        [_places addObject:[PlaceItem itemWithTitle:@"CoreServices" path:@"/System/Library/CoreServices"]];
        [_places addObject:[PlaceItem itemWithTitle:@"Frameworks" path:@"/System/Library/Frameworks"]];
        [_places addObject:[PlaceItem itemWithTitle:@"Binaries" path:@"/bin"]];
        [_places addObject:[PlaceItem itemWithTitle:@"Temporary" path:@"/tmp"]];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSString *)currentPath { return _currentPath; }
- (FilerViewMode)viewMode { return _viewMode; }

- (void)setViewMode:(FilerViewMode)mode {
    _viewMode = mode;
    _scrollOffsetY = 0;
    if(mode == FilerViewModeColumns) {
        [_columnItems removeAllObjects];
        NSMutableArray *first = [NSMutableArray arrayWithArray:_items];
        [_columnItems addObject:first];
        _columnSelectedCol = 0;
        _columnSelectedRow = _selectedIndex;
    }
    [self setNeedsDisplay:YES];
}

- (void)loadPath:(NSString *)path addToHistory:(BOOL)add {
    if(!path || [path length] == 0) path = @"/";
    if(add && _currentPath && ![_currentPath isEqualToString:path]) {
        [_backStack addObject:_currentPath];
        [_forwardStack removeAllObjects];
    }
    _currentPath = [path copy];
    /* Expanded folders belong to the directory being left. */
    [_expandedPaths removeAllObjects];
    [_items removeAllObjects];
    _selectedIndex = -1;
    [_selectedIndexes removeAllIndexes];
    _scrollOffsetY = 0;
    _previewItem = nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:_currentPath error:nil];
    if(files) {
        for(NSString *file in files) {
            if([file hasPrefix:@"."]) continue;
            NSString *full = [_currentPath isEqualToString:@"/"] ? [NSString stringWithFormat:@"/%@", file] : [_currentPath stringByAppendingPathComponent:file];
            BOOL isDir = NO;
            if(![fm fileExistsAtPath:full isDirectory:&isDir]) continue;
            struct stat st; memset(&st, 0, sizeof(st)); stat([full UTF8String], &st);
            FileItem *item = [FileItem new];
            item.name = file;
            item.fullPath = full;
            item.isDirectory = isDir;
            item.isApp = [file hasSuffix:@".app"] || [file hasSuffix:@".APP"];
            item.isExecutable = (!isDir && (st.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)));
            item.size = st.st_size;
            item.mode = st.st_mode & 0777;
            item.uid = st.st_uid;
            item.gid = st.st_gid;
            item.created = filerDateFromStat(&st, YES);
            item.modified = filerDateFromStat(&st, NO);
            item.icon = [self iconForPath:full isApp:item.isApp isDir:isDir];
            [_items addObject:item];
        }
        [self sortItems];
    }
    [[self window] setTitle:[NSString stringWithFormat:@"Filer — %@", _currentPath]];
    [self setNeedsDisplay:YES];
}

- (void)sortItems {
    SEL sel = @selector(compareByName:);
    if([_sortColumn isEqualToString:@"Date Modified"]) sel = @selector(compareByDate:);
    else if([_sortColumn isEqualToString:@"Size"]) sel = @selector(compareBySize:);
    else if([_sortColumn isEqualToString:@"Kind"]) sel = @selector(compareByKind:);
    [_items sortUsingSelector:sel];
    if(!_sortAscending) {
        // reverse
        NSMutableArray *rev = [NSMutableArray new];
        for(NSInteger i = [_items count]-1; i >= 0; i--) [rev addObject:[_items objectAtIndex:i]];
        [_items removeAllObjects];
        [_items addObjectsFromArray:rev];
    }
}

- (void)loadPath:(NSString *)path { [self loadPath:path addToHistory:YES]; }
- (void)refresh { [self loadPath:_currentPath addToHistory:NO]; }
- (void)goBack {
    if([_backStack count] > 0) {
        NSString *prev = [_backStack lastObject];
        [_backStack removeLastObject];
        if(_currentPath) [_forwardStack addObject:_currentPath];
        [self loadPath:prev addToHistory:NO];
    }
}
- (void)goForward {
    if([_forwardStack count] > 0) {
        NSString *next = [_forwardStack lastObject];
        [_forwardStack removeLastObject];
        if(_currentPath) [_backStack addObject:_currentPath];
        [self loadPath:next addToHistory:NO];
    }
}
- (void)goUp {
    if(![_currentPath isEqualToString:@"/"]) {
        NSString *parent = [_currentPath stringByDeletingLastPathComponent];
        if([parent length] == 0) parent = @"/";
        [self loadPath:parent addToHistory:YES];
    }
}

/* drawing helpers */
static void drawVectorFolder(CGContextRef ctx, NSRect r) {
    if(!ctx) return;
    CGContextSetRGBFillColor(ctx, 0.22, 0.55, 0.88, 1.0);
    CGContextFillRect(ctx, CGRectMake(r.origin.x + 2, r.origin.y + 2, r.size.width * 0.45, r.size.height * 0.25));
    CGContextSetRGBFillColor(ctx, 0.35, 0.68, 0.95, 1.0);
    CGContextFillRect(ctx, CGRectMake(r.origin.x, r.origin.y + r.size.height * 0.20, r.size.width, r.size.height * 0.80));
    CGContextSetRGBStrokeColor(ctx, 0.15, 0.45, 0.78, 1.0);
    CGContextStrokeRect(ctx, CGRectMake(r.origin.x, r.origin.y + r.size.height * 0.20, r.size.width, r.size.height * 0.80));
    CGContextSetRGBFillColor(ctx, 0.45, 0.75, 0.98, 1.0);
    CGContextFillRect(ctx, CGRectMake(r.origin.x + 2, r.origin.y + r.size.height * 0.35, r.size.width - 4, r.size.height * 0.60));
}
static void drawVectorDocument(CGContextRef ctx, NSRect r, BOOL isExe) {
    if(!ctx) return;
    if(isExe) {
        CGContextSetRGBFillColor(ctx, 0.20, 0.22, 0.25, 1.0);
        CGContextFillRect(ctx, CGRectMake(r.origin.x + 2, r.origin.y, r.size.width - 4, r.size.height));
        CGContextSetRGBStrokeColor(ctx, 0.10, 0.12, 0.15, 1.0);
        CGContextStrokeRect(ctx, CGRectMake(r.origin.x + 2, r.origin.y, r.size.width - 4, r.size.height));
    } else {
        CGContextSetRGBFillColor(ctx, 0.96, 0.96, 0.97, 1.0);
        CGContextFillRect(ctx, CGRectMake(r.origin.x + 4, r.origin.y, r.size.width - 8, r.size.height));
        CGContextSetRGBStrokeColor(ctx, 0.72, 0.74, 0.78, 1.0);
        CGContextStrokeRect(ctx, CGRectMake(r.origin.x + 4, r.origin.y, r.size.width - 8, r.size.height));
    }
}
static void drawVectorApp(CGContextRef ctx, NSRect r) {
    if(!ctx) return;
    CGContextSetRGBFillColor(ctx, 0.28, 0.52, 0.88, 1.0);
    CGContextFillRect(ctx, CGRectMake(r.origin.x + 2, r.origin.y + 2, r.size.width - 4, r.size.height - 4));
    CGContextSetRGBStrokeColor(ctx, 0.18, 0.38, 0.72, 1.0);
    CGContextStrokeRect(ctx, CGRectMake(r.origin.x + 2, r.origin.y + 2, r.size.width - 4, r.size.height - 4));
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = [self bounds];
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSFont *fontRegular = [NSFont fontWithName:@"Inter-Regular" size:11] ?: [NSFont systemFontOfSize:11];
    NSFont *fontBold = [NSFont boldSystemFontOfSize:11] ?: fontRegular;
    NSFont *fontSmall = [NSFont systemFontOfSize:10] ?: fontRegular;
    NSDictionary *textAttrs = [NSDictionary dictionaryWithObjectsAndKeys: fontRegular, NSFontAttributeName, [NSColor colorWithCalibratedWhite:0.15 alpha:1.0], NSForegroundColorAttributeName, nil];
    NSDictionary *selTextAttrs = [NSDictionary dictionaryWithObjectsAndKeys: fontRegular, NSFontAttributeName, [NSColor whiteColor], NSForegroundColorAttributeName, nil];
    NSDictionary *dimAttrs = [NSDictionary dictionaryWithObjectsAndKeys: fontSmall, NSFontAttributeName, [NSColor colorWithCalibratedWhite:0.45 alpha:1.0], NSForegroundColorAttributeName, nil];
    NSDictionary *headerAttrs = [NSDictionary dictionaryWithObjectsAndKeys: fontBold, NSFontAttributeName, [NSColor colorWithCalibratedWhite:0.35 alpha:1.0], NSForegroundColorAttributeName, nil];

    // Toolbar
    NSRect toolbarRect = NSMakeRect(0, 0, bounds.size.width, TOOLBAR_H);
    CGContextSetRGBFillColor(ctx, 0.93, 0.94, 0.96, 1.0);
    CGContextFillRect(ctx, toolbarRect);
    CGContextSetRGBStrokeColor(ctx, 0.80, 0.82, 0.85, 1.0);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextBeginPath(ctx); CGContextMoveToPoint(ctx, 0, TOOLBAR_H); CGContextAddLineToPoint(ctx, bounds.size.width, TOOLBAR_H); CGContextStrokePath(ctx);

    _btnBackRect = NSMakeRect(8, 7, 26, 24);
    _btnFwdRect  = NSMakeRect(36, 7, 26, 24);
    _btnUpRect   = NSMakeRect(66, 7, 26, 24);
    NSRect btns[3] = { _btnBackRect, _btnFwdRect, _btnUpRect };
    NSString *btnLabels[3] = { @"◀", @"▶", @"▲" };
    BOOL btnEnabled[3] = { [_backStack count] > 0, [_forwardStack count] > 0, ![_currentPath isEqualToString:@"/"] };
    for(int b = 0; b < 3; b++) {
        CGContextSetRGBFillColor(ctx, btnEnabled[b] ? 0.98 : 0.92, btnEnabled[b] ? 0.98 : 0.92, btnEnabled[b] ? 0.99 : 0.93, 1.0);
        CGContextFillRect(ctx, btns[b]);
        CGContextSetRGBStrokeColor(ctx, btnEnabled[b] ? 0.75 : 0.85, btnEnabled[b] ? 0.77 : 0.87, btnEnabled[b] ? 0.80 : 0.90, 1.0);
        CGContextStrokeRect(ctx, btns[b]);
        NSDictionary *ba = [NSDictionary dictionaryWithObjectsAndKeys: fontRegular, NSFontAttributeName, btnEnabled[b] ? [NSColor colorWithCalibratedWhite:0.2 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.65 alpha:1.0], NSForegroundColorAttributeName, nil];
        NSSize s = [btnLabels[b] sizeWithAttributes:ba];
        [btnLabels[b] drawAtPoint:NSMakePoint(btns[b].origin.x + (btns[b].size.width - s.width)/2.0, btns[b].origin.y + (btns[b].size.height - s.height)/2.0) withAttributes:ba];
    }

    _btnColsRect = NSMakeRect(bounds.size.width - 168, 7, 52, 24);
    _btnListRect = NSMakeRect(bounds.size.width - 114, 7, 52, 24);
    _btnIconsRect = NSMakeRect(bounds.size.width - 60, 7, 52, 24);

    // Icons
    CGContextSetRGBFillColor(ctx, (_viewMode == FilerViewModeIcons) ? 0.20 : 0.98, (_viewMode == FilerViewModeIcons) ? 0.52 : 0.98, (_viewMode == FilerViewModeIcons) ? 0.92 : 0.99, 1.0);
    CGContextFillRect(ctx, _btnIconsRect); CGContextSetRGBStrokeColor(ctx, 0.75,0.77,0.80,1.0); CGContextStrokeRect(ctx, _btnIconsRect);
    NSDictionary *icAttr = (_viewMode == FilerViewModeIcons) ? selTextAttrs : textAttrs;
    NSSize isz = [@"Icons" sizeWithAttributes:icAttr];
    [@"Icons" drawAtPoint:NSMakePoint(_btnIconsRect.origin.x + (_btnIconsRect.size.width - isz.width)/2.0, _btnIconsRect.origin.y + (_btnIconsRect.size.height - isz.height)/2.0) withAttributes:icAttr];
    // List
    CGContextSetRGBFillColor(ctx, (_viewMode == FilerViewModeList) ? 0.20 : 0.98, (_viewMode == FilerViewModeList) ? 0.52 : 0.98, (_viewMode == FilerViewModeList) ? 0.92 : 0.99, 1.0);
    CGContextFillRect(ctx, _btnListRect); CGContextSetRGBStrokeColor(ctx, 0.75,0.77,0.80,1.0); CGContextStrokeRect(ctx, _btnListRect);
    NSDictionary *lsAttr = (_viewMode == FilerViewModeList) ? selTextAttrs : textAttrs;
    NSSize lsz = [@"List" sizeWithAttributes:lsAttr];
    [@"List" drawAtPoint:NSMakePoint(_btnListRect.origin.x + (_btnListRect.size.width - lsz.width)/2.0, _btnListRect.origin.y + (_btnListRect.size.height - lsz.height)/2.0) withAttributes:lsAttr];
    // Columns
    CGContextSetRGBFillColor(ctx, (_viewMode == FilerViewModeColumns) ? 0.20 : 0.98, (_viewMode == FilerViewModeColumns) ? 0.52 : 0.98, (_viewMode == FilerViewModeColumns) ? 0.92 : 0.99, 1.0);
    CGContextFillRect(ctx, _btnColsRect); CGContextSetRGBStrokeColor(ctx, 0.75,0.77,0.80,1.0); CGContextStrokeRect(ctx, _btnColsRect);
    NSDictionary *csAttr = (_viewMode == FilerViewModeColumns) ? selTextAttrs : textAttrs;
    NSSize csz = [@"Cols" sizeWithAttributes:csAttr];
    [@"Cols" drawAtPoint:NSMakePoint(_btnColsRect.origin.x + (_btnColsRect.size.width - csz.width)/2.0, _btnColsRect.origin.y + (_btnColsRect.size.height - csz.height)/2.0) withAttributes:csAttr];

    // Breadcrumb
    float pathX = 100.0f;
    float pathW = _btnColsRect.origin.x - pathX - 8.0f;
    NSRect pathBarRect = NSMakeRect(pathX, 7, pathW, 24);
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(ctx, pathBarRect);
    CGContextSetRGBStrokeColor(ctx, 0.80, 0.82, 0.85, 1.0);
    CGContextStrokeRect(ctx, pathBarRect);
    [_crumbRects removeAllObjects]; [_crumbPaths removeAllObjects];
    float curCrumbX = pathX + 6.0f;
    NSArray *components = [_currentPath componentsSeparatedByString:@"/"];
    NSMutableArray *cleanComps = [NSMutableArray new]; [cleanComps addObject:@"/"];
    for(NSString *c in components) if([c length] > 0) [cleanComps addObject:c];
    NSMutableString *accumPath = [NSMutableString stringWithString:@"/"];
    for(NSUInteger ci = 0; ci < [cleanComps count]; ci++) {
        NSString *seg = [cleanComps objectAtIndex:ci];
        if(ci > 0) {
            if(![accumPath isEqualToString:@"/"]) [accumPath appendString:@"/"];
            [accumPath appendString:seg];
            [@"▸" drawAtPoint:NSMakePoint(curCrumbX, 11) withAttributes:dimAttrs];
            curCrumbX += 14.0f;
        }
        NSSize segSize = [seg sizeWithAttributes:textAttrs];
        NSRect cRect = NSMakeRect(curCrumbX, 9, segSize.width, 20);
        [seg drawAtPoint:NSMakePoint(curCrumbX, 11) withAttributes:textAttrs];
        [_crumbRects addObject:[NSValue valueWithRect:cRect]];
        [_crumbPaths addObject:[accumPath copy]];
        curCrumbX += segSize.width + 4.0f;
    }

    // Sidebar
    float contentY = TOOLBAR_H;
    float contentH = bounds.size.height - TOOLBAR_H - STATUS_H;
    NSRect sidebarRect = NSMakeRect(0, contentY, SIDEBAR_W, contentH);
    CGContextSetRGBFillColor(ctx, 0.94, 0.95, 0.97, 1.0);
    CGContextFillRect(ctx, sidebarRect);
    CGContextSetRGBStrokeColor(ctx, 0.82, 0.84, 0.88, 1.0);
    CGContextBeginPath(ctx); CGContextMoveToPoint(ctx, SIDEBAR_W, contentY); CGContextAddLineToPoint(ctx, SIDEBAR_W, contentY + contentH); CGContextStrokePath(ctx);
    [@"PLACES" drawAtPoint:NSMakePoint(12, contentY + 10) withAttributes:headerAttrs];
    float placeY = contentY + 30.0f;
    for(PlaceItem *pi in _places) {
        NSRect rowRect = NSMakeRect(4, placeY, SIDEBAR_W - 8, 24);
        BOOL isCur = [_currentPath isEqualToString:pi.path];
        if(isCur) { CGContextSetRGBFillColor(ctx, 0.20, 0.52, 0.92, 1.0); CGContextFillRect(ctx, rowRect); }
        drawVectorFolder(ctx, NSMakeRect(10, placeY + 4, 16, 14));
        NSDictionary *pa = isCur ? selTextAttrs : textAttrs;
        [pi.title drawAtPoint:NSMakePoint(32, placeY + 4) withAttributes:pa];
        placeY += 26.0f;
    }

    // Main content
    float mainX = SIDEBAR_W;
    float mainW = bounds.size.width - SIDEBAR_W;
    NSRect mainRect = NSMakeRect(mainX, contentY, mainW, contentH);
    CGContextSetRGBFillColor(ctx, 0.99, 0.99, 1.0, 1.0);
    CGContextFillRect(ctx, mainRect);

    if(_viewMode == FilerViewModeIcons) {
        int cols = (int)(mainW / CELL_W); if(cols < 1) cols = 1;
        for(NSInteger i = 0; i < (NSInteger)[_items count]; i++) {
            FileItem *item = [_items objectAtIndex:i];
            int col = (int)(i % cols); int row = (int)(i / cols);
            float cellX = mainX + col * CELL_W;
            float cellY = contentY + 8.0f + row * CELL_H - _scrollOffsetY;
            if(cellY + CELL_H < contentY || cellY > contentY + contentH) continue;
            if([_selectedIndexes containsIndex:i] || i == _selectedIndex) {
                CGContextSetRGBFillColor(ctx, 0.20, 0.52, 0.92, 0.90);
                CGContextFillRect(ctx, CGRectMake(cellX + 4, cellY + 2, CELL_W - 8, CELL_H - 4));
            }
            float iconX = cellX + (CELL_W - ICON_SZ) / 2.0f;
            float iconY = cellY + 6.0f;
            NSRect iconRect = NSMakeRect(iconX, iconY, ICON_SZ, ICON_SZ);
            if(item.icon) [item.icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            else if(item.isApp) drawVectorApp(ctx, iconRect);
            else if(item.isDirectory) drawVectorFolder(ctx, iconRect);
            else drawVectorDocument(ctx, iconRect, item.isExecutable);
            NSString *displayName = item.name;
            if(item.isApp && [displayName hasSuffix:@".app"]) displayName = [displayName substringToIndex:[displayName length] - 4];
            NSDictionary *curAttrs = (i == _selectedIndex) ? selTextAttrs : textAttrs;
            NSRect labelRect = NSMakeRect(cellX + 2, cellY + ICON_SZ + 8.0f, CELL_W - 4, 28.0f);
            [displayName drawInRect:labelRect withAttributes:curAttrs];
        }
    } else if(_viewMode == FilerViewModeList) {
        // Header with sortable columns
        NSRect hdrRect = NSMakeRect(mainX, contentY, mainW, LIST_HDR_H);
        CGContextSetRGBFillColor(ctx, 0.95, 0.96, 0.98, 1.0);
        CGContextFillRect(ctx, hdrRect);
        CGContextSetRGBStrokeColor(ctx, 0.85, 0.86, 0.90, 1.0);
        CGContextBeginPath(ctx); CGContextMoveToPoint(ctx, mainX, contentY + LIST_HDR_H); CGContextAddLineToPoint(ctx, bounds.size.width, contentY + LIST_HDR_H); CGContextStrokePath(ctx);
        // disclosure + name
        [@"Name" drawAtPoint:NSMakePoint(mainX + 32, contentY + 4) withAttributes:headerAttrs];
        [@"Date Modified" drawAtPoint:NSMakePoint(mainX + mainW * 0.42, contentY + 4) withAttributes:headerAttrs];
        [@"Kind" drawAtPoint:NSMakePoint(mainX + mainW * 0.62, contentY + 4) withAttributes:headerAttrs];
        [@"Size" drawAtPoint:NSMakePoint(mainX + mainW * 0.82, contentY + 4) withAttributes:headerAttrs];

        float rowY = contentY + LIST_HDR_H;
        for(NSInteger i = 0; i < (NSInteger)[_items count]; i++) {
            FileItem *item = [_items objectAtIndex:i];
            // expanded paths handling: simple flat list; disclosure for dirs
            NSRect rRect = NSMakeRect(mainX, rowY - _scrollOffsetY, mainW, LIST_ROW_H);
            if(rRect.origin.y + LIST_ROW_H < contentY + LIST_HDR_H || rRect.origin.y > contentY + contentH) { rowY += LIST_ROW_H; continue; }
            if(i == _selectedIndex || [_selectedIndexes containsIndex:(NSUInteger)i]) { CGContextSetRGBFillColor(ctx, 0.20, 0.52, 0.92, 1.0); CGContextFillRect(ctx, rRect); }
            else if(i % 2 == 1) { CGContextSetRGBFillColor(ctx, 0.97, 0.98, 0.99, 1.0); CGContextFillRect(ctx, rRect); }
            // disclosure triangle for folders, indented by expansion depth
            float indent = (float)item.depth * 16.0f;
            if(item.isDirectory) {
                NSString *tri = [_expandedPaths containsObject:item.fullPath] ? @"▾" : @"▸";
                [tri drawAtPoint:NSMakePoint(mainX + 8 + indent, rRect.origin.y + 4) withAttributes:dimAttrs];
            }
            NSRect mIcon = NSMakeRect(mainX + 22 + indent, rRect.origin.y + 4, 16, 16);
            if(item.icon) [item.icon drawInRect:mIcon fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            else if(item.isApp) drawVectorApp(ctx, mIcon);
            else if(item.isDirectory) drawVectorFolder(ctx, mIcon);
            else drawVectorDocument(ctx, mIcon, item.isExecutable);

            NSDictionary *ca = (i == _selectedIndex) ? selTextAttrs : textAttrs;
            NSDictionary *da = (i == _selectedIndex) ? selTextAttrs : dimAttrs;
            NSString *displayName = item.name;
            if(item.isApp && [displayName hasSuffix:@".app"]) displayName = [displayName substringToIndex:[displayName length] - 4];
            [displayName drawAtPoint:NSMakePoint(mainX + 42 + indent, rRect.origin.y + 4) withAttributes:ca];
            NSDateFormatter *df = [NSDateFormatter new];
            [df setDateFormat:@"yyyy-MM-dd HH:mm"];
            NSString *dateStr = [df stringFromDate:item.modified] ?: @"--";
            [dateStr drawAtPoint:NSMakePoint(mainX + mainW * 0.42, rRect.origin.y + 4) withAttributes:da];
            [[item kindString] drawAtPoint:NSMakePoint(mainX + mainW * 0.62, rRect.origin.y + 4) withAttributes:da];
            NSString *sz = item.isDirectory ? @"--" : filerFormatSize(item.size);
            [sz drawAtPoint:NSMakePoint(mainX + mainW * 0.82, rRect.origin.y + 4) withAttributes:da];
            rowY += LIST_ROW_H;
        }
    } else {
        // Columns (Miller)
        float x = mainX;
        for(NSUInteger ci = 0; ci < [_columnItems count]; ci++) {
            NSMutableArray *col = [_columnItems objectAtIndex:ci];
            NSRect colRect = NSMakeRect(x, contentY, COL_W, contentH);
            CGContextSetRGBFillColor(ctx, 0.99, 0.99, 1.0, 1.0);
            CGContextFillRect(ctx, colRect);
            CGContextSetRGBStrokeColor(ctx, 0.85, 0.86, 0.90, 1.0);
            CGContextBeginPath(ctx); CGContextMoveToPoint(ctx, x + COL_W, contentY); CGContextAddLineToPoint(ctx, x + COL_W, contentY + contentH); CGContextStrokePath(ctx);
            float ry = contentY;
            for(NSInteger i = 0; i < (NSInteger)[col count]; i++) {
                FileItem *item = [col objectAtIndex:i];
                NSRect rRect = NSMakeRect(x, ry, COL_W, LIST_ROW_H);
                if(ry + LIST_ROW_H < contentY || ry > contentY + contentH) { ry += LIST_ROW_H; continue; }
                BOOL sel = (ci == (NSUInteger)_columnSelectedCol && i == _columnSelectedRow);
                if(sel) { CGContextSetRGBFillColor(ctx, 0.20, 0.52, 0.92, 1.0); CGContextFillRect(ctx, rRect); }
                NSRect mIcon = NSMakeRect(x + 6, ry + 4, 16, 16);
                if(item.icon) [item.icon drawInRect:mIcon fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
                else if(item.isApp) drawVectorApp(ctx, mIcon);
                else if(item.isDirectory) drawVectorFolder(ctx, mIcon);
                else drawVectorDocument(ctx, mIcon, item.isExecutable);
                NSDictionary *ca = sel ? selTextAttrs : textAttrs;
                NSString *dn = item.name;
                if(item.isApp && [dn hasSuffix:@".app"]) dn = [dn substringToIndex:[dn length]-4];
                [dn drawAtPoint:NSMakePoint(x + 26, ry + 4) withAttributes:ca];
                if(item.isDirectory) [@"▸" drawAtPoint:NSMakePoint(x + COL_W - 16, ry + 4) withAttributes:dimAttrs];
                ry += LIST_ROW_H;
            }
            x += COL_W;
        }
        // Preview pane if selected file
        if(_previewItem) {
            NSRect pRect = NSMakeRect(x, contentY, PREVIEW_W, contentH);
            CGContextSetRGBFillColor(ctx, 0.97, 0.97, 0.99, 1.0);
            CGContextFillRect(ctx, pRect);
            float py = contentY + 12;
            // thumbnail
            NSRect tRect = NSMakeRect(x + 20, py, PREVIEW_W - 40, 120);
            if(_previewItem.icon) [_previewItem.icon drawInRect:tRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            else if(_previewItem.isApp) drawVectorApp(ctx, tRect);
            else if(_previewItem.isDirectory) drawVectorFolder(ctx, tRect);
            else drawVectorDocument(ctx, tRect, _previewItem.isExecutable);
            py += 132;
            NSArray *lines = @[
                [NSString stringWithFormat:@"Name: %@", _previewItem.name],
                [NSString stringWithFormat:@"Kind: %@", [_previewItem kindString]],
                [NSString stringWithFormat:@"Size: %@", _previewItem.isDirectory ? @"--" : filerFormatSize(_previewItem.size)],
                [NSString stringWithFormat:@"Permissions: %o", _previewItem.mode],
                [NSString stringWithFormat:@"Created: %@", _previewItem.created ?: @"--"],
                [NSString stringWithFormat:@"Modified: %@", _previewItem.modified ?: @"--"],
                [NSString stringWithFormat:@"Path: %@", _previewItem.fullPath]
            ];
            for(NSString *ln in lines) {
                [ln drawAtPoint:NSMakePoint(x + 12, py) withAttributes:textAttrs];
                py += 16;
            }
        }
    }

    // Marquee
    if(_marqueeActive) {
        CGContextSetRGBFillColor(ctx, 0.20, 0.52, 0.92, 0.15);
        CGContextFillRect(ctx, _marqueeRect);
        CGContextSetRGBStrokeColor(ctx, 0.20, 0.52, 0.92, 0.8);
        CGContextStrokeRect(ctx, _marqueeRect);
    }

    // Inline rename field handled by subview

    // Status bar
    NSRect statusRect = NSMakeRect(0, bounds.size.height - STATUS_H, bounds.size.width, STATUS_H);
    CGContextSetRGBFillColor(ctx, 0.93, 0.94, 0.96, 1.0);
    CGContextFillRect(ctx, statusRect);
    CGContextSetRGBStrokeColor(ctx, 0.82, 0.84, 0.88, 1.0);
    CGContextBeginPath(ctx); CGContextMoveToPoint(ctx, 0, bounds.size.height - STATUS_H); CGContextAddLineToPoint(ctx, bounds.size.width, bounds.size.height - STATUS_H); CGContextStrokePath(ctx);
    NSString *statusText;
    if(_customStatusText != nil) statusText = _customStatusText;
    else if(_selectedIndex >= 0 && _selectedIndex < (NSInteger)[_items count]) {
        FileItem *sel = [_items objectAtIndex:_selectedIndex];
        statusText = [NSString stringWithFormat:@"%lu items — \"%@\" selected (%@)", (unsigned long)[_items count], sel.name, sel.isDirectory ? [sel kindString] : filerFormatSize(sel.size)];
    } else statusText = [NSString stringWithFormat:@"%lu items", (unsigned long)[_items count]];
    NSSize stSize = [statusText sizeWithAttributes:dimAttrs];
    [statusText drawAtPoint:NSMakePoint((bounds.size.width - stSize.width) / 2.0f, bounds.size.height - STATUS_H + 4.0f) withAttributes:dimAttrs];
}

// Inline rename
- (void)beginInlineRenameAtIndex:(NSInteger)idx {
    if(idx < 0 || idx >= (NSInteger)[_items count]) return;
    _renameIndex = idx;
    FileItem *item = [_items objectAtIndex:idx];
    NSRect bounds = [self bounds];
    float x = SIDEBAR_W, y;
    if(_viewMode == FilerViewModeIcons) {
        int cols = (int)((bounds.size.width - SIDEBAR_W) / CELL_W); if(cols < 1) cols = 1;
        int col = (int)(idx % cols); int row = (int)(idx / cols);
        x = SIDEBAR_W + col * CELL_W;
        y = TOOLBAR_H + 8.0f + row * CELL_H - _scrollOffsetY + ICON_SZ + 8.0f;
    } else {
        y = TOOLBAR_H + LIST_HDR_H + idx * LIST_ROW_H - _scrollOffsetY;
        x = SIDEBAR_W + 42;
    }
    _renameField = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 140, 20)];
    [_renameField setStringValue:item.name];
    [_renameField setEditable:YES];
    [_renameField setSelectable:YES];
    [_renameField setDelegate:self];
    [self addSubview:_renameField];
    [[self window] makeFirstResponder:_renameField];
}

- (void)finalizeRename {
    if(!_renameField) return;
    NSString *newName = [_renameField stringValue];
    if(_renameIndex >= 0 && _renameIndex < (NSInteger)[_items count] && [newName length] > 0) {
        FileItem *item = [_items objectAtIndex:_renameIndex];
        if(![newName isEqualToString:item.name]) {
            NSString *newPath = [[item.fullPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
            [[NSFileManager defaultManager] moveItemAtPath:item.fullPath toPath:newPath error:nil];
        }
    }
    [_renameField removeFromSuperview];
    _renameField = nil;
    _renameIndex = -1;
    [self refresh];
}

- (void)controlTextDidEndEditing:(NSNotification *)n {
    [self finalizeRename];
}

// File operations
- (void)createNewFolder {
    NSString *base = [_currentPath stringByAppendingPathComponent:@"Untitled Folder"];
    NSString *target = base;
    NSFileManager *fm = [NSFileManager defaultManager];
    int n = 2;
    while([fm fileExistsAtPath:target]) {
        target = [NSString stringWithFormat:@"%@/Untitled Folder %d", _currentPath, n++];
    }
[fm createDirectoryAtPath:target withIntermediateDirectories:NO attributes:nil error:nil];
[self refresh];
for(NSInteger i = 0; i < (NSInteger)[_items count]; i++) {
    FileItem *it = [_items objectAtIndex:i];
    if([it.fullPath isEqualToString:target]) { _selectedIndex = i; [self beginInlineRenameAtIndex:i]; break; }
}
[self setNeedsDisplay:YES];
}

- (void)duplicateSelected {
    if(_selectedIndex < 0 || _selectedIndex >= (NSInteger)[_items count]) return;
    FileItem *item = [_items objectAtIndex:_selectedIndex];
    NSString *dir = [item.fullPath stringByDeletingLastPathComponent];
    NSString *base = [item.name stringByDeletingPathExtension];
    NSString *ext = [item.name pathExtension];
    NSString *newName = ext.length ? [NSString stringWithFormat:@"%@ copy.%@", base, ext] : [NSString stringWithFormat:@"%@ copy", base];
    NSString *target = [dir stringByAppendingPathComponent:newName];
    [[NSFileManager defaultManager] copyItemAtPath:item.fullPath toPath:target error:nil];
    [self refresh];
}

- (void)moveSelectedToTrash {
    if(_selectedIndex < 0 || _selectedIndex >= (NSInteger)[_items count]) return;
    FileItem *item = [_items objectAtIndex:_selectedIndex];
    NSString *home = NSHomeDirectory();
    NSString *trash = [home stringByAppendingPathComponent:@".Trash"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trash withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *target = [trash stringByAppendingPathComponent:item.name];
    NSFileManager *fm = [NSFileManager defaultManager];
    // avoid collision
    if([fm fileExistsAtPath:target]) {
        target = [trash stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %lu", item.name, (unsigned long)[[NSDate date] timeIntervalSince1970]]];
    }
    // record origin
    NSString *originsPath = [trash stringByAppendingPathComponent:@".trash_origins.plist"];
    NSMutableDictionary *origins = [NSMutableDictionary dictionaryWithContentsOfFile:originsPath] ?: [NSMutableDictionary new];
    origins[target] = item.fullPath;
    [origins writeToFile:originsPath atomically:YES];
    [fm moveItemAtPath:item.fullPath toPath:target error:nil];
    [self refresh];
}

- (void)emptyTrash {
    NSAlert *a = [NSAlert alertWithMessageText:@"Empty Trash?" defaultButton:@"Empty Trash" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"All items in the Trash will be permanently deleted."];
    if([a runModal] == NSAlertDefaultReturn) {
        NSString *trash = [NSHomeDirectory() stringByAppendingPathComponent:@".Trash"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *contents = [fm contentsOfDirectoryAtPath:trash error:nil];
        for(NSString *f in contents) {
            if([f hasPrefix:@"."]) continue;
            [fm removeItemAtPath:[trash stringByAppendingPathComponent:f] error:nil];
        }
    }
}

- (void)copySelectedToPasteboard {
    if(_selectedIndex < 0 || _selectedIndex >= (NSInteger)[_items count]) return;
    FileItem *item = [_items objectAtIndex:_selectedIndex];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb declareTypes:@[NSFilenamesPboardType, NSPasteboardTypeFileURL] owner:self];
    [pb setPropertyList:@[item.fullPath] forType:NSFilenamesPboardType];
    [pb setString:[NSString stringWithFormat:@"file://%@", item.fullPath] forType:NSPasteboardTypeFileURL];
}

- (void)pasteFromPasteboardMove:(BOOL)move {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSArray *files = [pb propertyListForType:NSFilenamesPboardType];
    if(![files isKindOfClass:[NSArray class]]) {
        NSString *urlStr = [pb stringForType:NSPasteboardTypeFileURL];
        if(urlStr) files = @[ [urlStr stringByReplacingOccurrencesOfString:@"file://" withString:@""] ];
    }
    if(![files isKindOfClass:[NSArray class]]) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    for(NSString *src in files) {
        NSString *name = [src lastPathComponent];
        NSString *dest = [_currentPath stringByAppendingPathComponent:name];
        if(move) [fm moveItemAtPath:src toPath:dest error:nil];
        else [fm copyItemAtPath:src toPath:dest error:nil];
    }
    [self refresh];
}

- (void)showGetInfoForItem:(FileItem *)item {
    if(!item) return;
    NSRect frame = NSMakeRect(200, 200, 340, 460);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame styleMask:(NSTitledWindowMask | NSClosableWindowMask) backing:NSBackingStoreBuffered defer:NO];
    [win setTitle:[NSString stringWithFormat:@"Get Info — %@", item.name]];
    NSView *cv = [win contentView];
    // icon
    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(140, 400, 60, 60)];
    if(item.icon) [iv setImage:item.icon];
    [cv addSubview:iv];
    // name field
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 370, 300, 24)];
    [nameField setStringValue:item.name];
    [cv addSubview:nameField];
    // info labels
    /* Folders report their recursive size: "Size: --" told the user nothing
     * about what a folder occupies. */
    NSString *sizeText;
    if(item.isDirectory) {
        unsigned long long total = 0;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDirectoryEnumerator *walk = [fm enumeratorAtPath:item.fullPath];
        NSString *rel;
        int visited = 0;

        while((rel = [walk nextObject]) != nil && visited < 5000) {
            NSDictionary *attrs = [walk fileAttributes];

            if([[attrs objectForKey:NSFileType] isEqualToString:NSFileTypeRegular])
                total += [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
            visited++;
        }
        sizeText = [NSString stringWithFormat:@"%@ (%d items)", filerFormatSize((off_t)total), visited];
    } else {
        sizeText = filerFormatSize(item.size);
    }

    NSArray *info = @[
        [NSString stringWithFormat:@"Kind: %@", [item kindString]],
        [NSString stringWithFormat:@"Size: %@", sizeText],
        [NSString stringWithFormat:@"Where: %@", [item.fullPath stringByDeletingLastPathComponent]],
        [NSString stringWithFormat:@"Created: %@", item.created ?: @"--"],
        [NSString stringWithFormat:@"Modified: %@", item.modified ?: @"--"],
    ];
    float y = 340;
    for(NSString *ln in info) {
        NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 300, 18)];
        [lbl setStringValue:ln];
        [lbl setEditable:NO];
        [lbl setBordered:NO];
        [lbl setDrawsBackground:NO];
        [cv addSubview:lbl];
        y -= 22;
    }
    // Owner and group are editable (chown on Apply).
    {
        NSTextField *ol = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 60, 18)];
        [ol setStringValue:@"Owner:"];
        [ol setEditable:NO]; [ol setBordered:NO]; [ol setDrawsBackground:NO];
        [cv addSubview:ol];
        NSTextField *ownerField = [[NSTextField alloc] initWithFrame:NSMakeRect(90, y - 2, 60, 22)];
        [ownerField setStringValue:[NSString stringWithFormat:@"%u", item.uid]];
        [ownerField setTag:997];
        [cv addSubview:ownerField];
        NSTextField *gl2 = [[NSTextField alloc] initWithFrame:NSMakeRect(160, y, 60, 18)];
        [gl2 setStringValue:@"Group:"];
        [gl2 setEditable:NO]; [gl2 setBordered:NO]; [gl2 setDrawsBackground:NO];
        [cv addSubview:gl2];
        NSTextField *groupField = [[NSTextField alloc] initWithFrame:NSMakeRect(225, y - 2, 60, 22)];
        [groupField setStringValue:[NSString stringWithFormat:@"%u", item.gid]];
        [groupField setTag:998];
        [cv addSubview:groupField];
        y -= 26;
    }

    // Permissions section
    NSTextField *permHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 300, 18)];
    [permHeader setStringValue:@"Sharing & Permissions"];
    [permHeader setEditable:NO]; [permHeader setBordered:NO]; [permHeader setDrawsBackground:NO];
    [cv addSubview:permHeader];
    y -= 24;
    // checkboxes owner/group/others rwx
    NSArray *labels = @[@"Owner", @"Group", @"Others"];
    for(int g = 0; g < 3; g++) {
        int shift = (2 - g) * 3;
        NSTextField *gl = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 60, 18)];
        [gl setStringValue:labels[g]]; [gl setEditable:NO]; [gl setBordered:NO]; [gl setDrawsBackground:NO];
        [cv addSubview:gl];
        NSString *rwx = @"rwx";
        for(int b = 0; b < 3; b++) {
            NSButton *cb = [[NSButton alloc] initWithFrame:NSMakeRect(90 + b*30, y, 24, 18)];
            [cb setButtonType:NSSwitchButton];
            [cb setTitle:[NSString stringWithFormat:@"%c", [rwx characterAtIndex:b]]];
            int bit = 1 << (2 - b);
            BOOL on = (item.mode >> (shift + (2-b))) & 1;
            [cb setState:on ? NSOnState : NSOffState];
            /* Checkboxes use 100..108 so the Apply button (tag 0) is never
             * mistaken for a permission bit. */
            [cb setTag:(100 + g*3 + b)];
            [cv addSubview:cb];
        }
        y -= 22;
    }
    // octal field
    NSTextField *octalLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 80, 18)];
    [octalLabel setStringValue:@"Octal:"];
    [octalLabel setEditable:NO]; [octalLabel setBordered:NO]; [octalLabel setDrawsBackground:NO];
    [cv addSubview:octalLabel];
    NSTextField *octalField = [[NSTextField alloc] initWithFrame:NSMakeRect(100, y, 60, 22)];
    [octalField setStringValue:[NSString stringWithFormat:@"%o", item.mode]];
    [octalField setTag:999];
    /* Remember the starting text in the field's toolTip: an untouched field
     * must not overwrite what the permission checkboxes just set. */
    [octalField setToolTip:[NSString stringWithFormat:@"%o", item.mode]];
    [cv addSubview:octalField];
    y -= 30;
    NSButton *applyBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 100, 28)];
    [applyBtn setTitle:@"Apply"];
    [applyBtn setTarget:self];
    // store item path in button tag? Use representedObject via tooltip hack? Instead use a block-like approach: store in window's representedObject
    // path stored in apply button toolTip
    [applyBtn setAction:@selector(applyInfoPermissions:)];
    [cv addSubview:applyBtn];
    // Apply button needs item path; store in button's toolTip
    [applyBtn setToolTip:item.fullPath];
    [win makeKeyAndOrderFront:nil];
}

- (void)applyInfoPermissions:(id)sender {
    NSButton *btn = (NSButton *)sender;
    NSString *path = [btn toolTip];
    NSWindow *win = [btn window];
    NSView *cv = [win contentView];
    // collect checkboxes
    int mode = 0;
    BOOL octalUsed = NO;
    uid_t owner = (uid_t)-1;
    gid_t group = (gid_t)-1;
    for(NSView *v in [cv subviews]) {
        if([v isKindOfClass:[NSButton class]]) {
            int tag = (int)[(NSButton*)v tag];
            if(tag >= 100 && tag < 109) {
                NSButton *cb = (NSButton*)v;
                if([cb state] == NSOnState) {
                    int idx = tag - 100;
                    int g = idx / 3;
                    int b = idx % 3;
                    int shift = (2 - g) * 3;
                    mode |= (1 << (shift + (2 - b)));
                }
            }
        }
        if([v isKindOfClass:[NSTextField class]]) {
            int tag = (int)[(NSTextField*)v tag];
            NSString *str = [(NSTextField*)v stringValue];
            if(tag == 999) {
                NSString *initial = [(NSTextField*)v toolTip];
                unsigned int m;

                if(initial != nil && [str isEqualToString:initial]) {
                    /* untouched: the checkboxes own the mode */
                } else if(sscanf([str UTF8String], "%o", &m) == 1) {
                    mode = (int)m;
                    octalUsed = YES;
                }
            } else if(tag == 997) {
                owner = (uid_t)[str intValue];
            } else if(tag == 998) {
                group = (gid_t)[str intValue];
            }
        }
    }
    if(chmod([path UTF8String], (mode_t)mode) != 0)
        fprintf(stderr, "[Filer] chmod %s failed: %s\n", [path UTF8String], strerror(errno));
    if(owner != (uid_t)-1 || group != (gid_t)-1) {
        if(chown([path UTF8String], owner, group) != 0)
            fprintf(stderr, "[Filer] chown %s failed: %s\n", [path UTF8String], strerror(errno));
    }
    (void)octalUsed;
}

// Context menu
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [NSMenu new];
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    // determine selected item under cursor
    FileItem *clicked = nil;
    NSInteger idx = -1;
    if(_viewMode == FilerViewModeIcons) {
        float mainW = [self bounds].size.width - SIDEBAR_W;
        int cols = (int)(mainW / CELL_W); if(cols < 1) cols = 1;
        float contentY = TOOLBAR_H;
        int col = (int)((loc.x - SIDEBAR_W) / CELL_W);
        int row = (int)((loc.y - contentY - 8.0f + _scrollOffsetY) / CELL_H);
        if(col >= 0 && col < cols && row >= 0) {
            NSInteger ti = row * cols + col;
            if(ti >= 0 && ti < (NSInteger)[_items count]) { idx = ti; clicked = [_items objectAtIndex:ti]; }
        }
    } else {
        float rowY = loc.y - TOOLBAR_H - LIST_HDR_H + _scrollOffsetY;
        if(rowY >= 0) {
            NSInteger ti = (NSInteger)(rowY / LIST_ROW_H);
            if(ti >= 0 && ti < (NSInteger)[_items count]) { idx = ti; clicked = [_items objectAtIndex:ti]; }
        }
    }
    if(clicked) {
        _selectedIndex = idx;
        [self setNeedsDisplay:YES];
        [menu addItemWithTitle:@"Open" action:@selector(ctxOpen:) keyEquivalent:@""];
        [menu addItemWithTitle:@"Open With" action:@selector(ctxOpenWith:) keyEquivalent:@""];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItemWithTitle:@"Get Info" action:@selector(ctxGetInfo:) keyEquivalent:@""];
        [menu addItemWithTitle:@"Rename" action:@selector(ctxRename:) keyEquivalent:@""];
        [menu addItemWithTitle:@"Duplicate" action:@selector(ctxDuplicate:) keyEquivalent:@""];
        NSString *compressTitle = [NSString stringWithFormat:@"Compress \"%@\"", clicked.name];
        NSMenuItem *ci = [menu addItemWithTitle:compressTitle action:@selector(ctxCompress:) keyEquivalent:@""];
        [ci setRepresentedObject:clicked.fullPath];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItemWithTitle:@"Move to Trash" action:@selector(ctxTrash:) keyEquivalent:@""];
    } else {
        // empty background
        [menu addItemWithTitle:@"New Folder" action:@selector(ctxNewFolder:) keyEquivalent:@""];
        [menu addItemWithTitle:@"Paste" action:@selector(ctxPaste:) keyEquivalent:@""];
    }
    // attach target
    for(NSMenuItem *mi in [menu itemArray]) [mi setTarget:self];
    return menu;
}

- (void)ctxOpen:(id)s {
    if(_selectedIndex < 0 || _selectedIndex >= (NSInteger)[_items count]) return;
    FileItem *item = [_items objectAtIndex:_selectedIndex];
    if(item.isApp) filerOpenBundle(item.fullPath);
    else if(item.isDirectory) [self loadPath:item.fullPath addToHistory:YES];
}
- (void)ctxOpenWith:(id)s {
    NSInteger idx = _selectedIndex;
    NSOpenPanel *panel;
    NSString *chosen;

    if(idx < 0 || idx >= (NSInteger)[_items count])
        return;

    panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    if([panel runModalForDirectory:@"/Applications" file:nil types:@[@"app"]] != NSFileHandlingPanelOKButton)
        return;
    chosen = [[panel filenames] count] > 0 ? [[panel filenames] objectAtIndex:0] : nil;
    if(chosen == nil)
        return;

    {
        FileItem *item = [_items objectAtIndex:idx];
        NSURL *appURL = [NSURL fileURLWithPath:chosen];
        NSURL *docURL = [NSURL fileURLWithPath:item.fullPath];
        LSLaunchURLSpec spec;

        memset(&spec, 0, sizeof(spec));
        spec.appURL = (__bridge CFURLRef)appURL;
        spec.itemURLs = (__bridge CFArrayRef)[NSArray arrayWithObject:docURL];
        spec.launchFlags = kLSLaunchDefaults;
        LSOpenFromURLSpec(&spec, NULL);
    }
}
- (void)ctxGetInfo:(id)s {
    if(_selectedIndex < 0 || _selectedIndex >= (NSInteger)[_items count]) return;
    [self showGetInfoForItem:[_items objectAtIndex:_selectedIndex]];
}
- (void)ctxRename:(id)s {
    if(_selectedIndex >= 0) [self beginInlineRenameAtIndex:_selectedIndex];
}
- (void)ctxDuplicate:(id)s { [self duplicateSelected]; }
- (void)ctxCompress:(id)s {
    NSMenuItem *mi = (NSMenuItem *)s; // not actually menu item when invoked via action? Use selected
    NSString *path = nil;
    if([s isKindOfClass:[NSMenuItem class]]) path = [(NSMenuItem*)s representedObject];
    if(!path && _selectedIndex >= 0 && _selectedIndex < (NSInteger)[_items count]) path = [[_items objectAtIndex:_selectedIndex] fullPath];
    if(!path) return;
    NSString *cmd = [NSString stringWithFormat:@"/System/Library/CoreServices/Archive\\ Utility.app/Contents/ravynOS/Archive\\ Utility --compress \"%@\"", path];
    system([cmd UTF8String]);
}
- (void)ctxTrash:(id)s { [self moveSelectedToTrash]; }
- (void)ctxNewFolder:(id)s { [self createNewFolder]; }
- (void)ctxPaste:(id)s { [self pasteFromPasteboardMove:NO]; }

// Mouse handling
- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect bounds = [self bounds];
    if(loc.y < TOOLBAR_H) {
        if(NSPointInRect(loc, _btnBackRect)) { [self goBack]; return; }
        if(NSPointInRect(loc, _btnFwdRect)) { [self goForward]; return; }
        if(NSPointInRect(loc, _btnUpRect)) { [self goUp]; return; }
        if(NSPointInRect(loc, _btnIconsRect)) { [self setViewMode:FilerViewModeIcons]; return; }
        if(NSPointInRect(loc, _btnListRect)) { [self setViewMode:FilerViewModeList]; return; }
        if(NSPointInRect(loc, _btnColsRect)) { [self setViewMode:FilerViewModeColumns]; return; }
        for(NSUInteger i = 0; i < [_crumbRects count]; i++) {
            NSRect cr = [[_crumbRects objectAtIndex:i] rectValue];
            if(NSPointInRect(loc, cr)) { [self loadPath:[_crumbPaths objectAtIndex:i] addToHistory:YES]; return; }
        }
        return;
    }
    if(loc.x < SIDEBAR_W && loc.y < bounds.size.height - STATUS_H) {
        float placeY = TOOLBAR_H + 30.0f;
        for(PlaceItem *pi in _places) {
            NSRect r = NSMakeRect(4, placeY, SIDEBAR_W - 8, 24);
            if(NSPointInRect(loc, r)) { [self loadPath:pi.path addToHistory:YES]; return; }
            placeY += 26.0f;
        }
        return;
    }
    if(loc.x >= SIDEBAR_W && loc.y < bounds.size.height - STATUS_H) {
        // Column view handling
        if(_viewMode == FilerViewModeColumns) {
            float x = SIDEBAR_W;
            NSInteger colIdx = -1, rowIdx = -1;
            for(NSUInteger ci = 0; ci < [_columnItems count]; ci++) {
                if(loc.x >= x && loc.x < x + COL_W) { colIdx = ci; break; }
                x += COL_W;
            }
            if(_previewItem && colIdx == -1 && loc.x >= x && loc.x < x + PREVIEW_W) { colIdx = -2; }
            if(colIdx >= 0) {
                NSMutableArray *col = [_columnItems objectAtIndex:colIdx];
                float ry = TOOLBAR_H;
                for(NSInteger i = 0; i < (NSInteger)[col count]; i++) {
                    if(loc.y >= ry && loc.y < ry + LIST_ROW_H) { rowIdx = i; break; }
                    ry += LIST_ROW_H;
                }
                if(rowIdx >= 0) {
                    _columnSelectedCol = colIdx;
                    _columnSelectedRow = rowIdx;
                    FileItem *item = [col objectAtIndex:rowIdx];
                    if(item.isDirectory) {
                        // trim columns after
                        while([_columnItems count] > (NSUInteger)(colIdx + 1)) [_columnItems removeLastObject];
                        // load dir into next column
                        NSFileManager *fm = [NSFileManager defaultManager];
                        NSArray *files = [fm contentsOfDirectoryAtPath:item.fullPath error:nil];
                        NSMutableArray *newCol = [NSMutableArray new];
                        if(files) {
                            for(NSString *file in files) {
                                if([file hasPrefix:@"."]) continue;
                                NSString *full = [item.fullPath stringByAppendingPathComponent:file];
                                BOOL isDir = NO; if(![fm fileExistsAtPath:full isDirectory:&isDir]) continue;
                                struct stat st; memset(&st,0,sizeof(st)); stat([full UTF8String],&st);
                                FileItem *it = [FileItem new];
                                it.name = file; it.fullPath = full; it.isDirectory = isDir;
                                it.isApp = [file hasSuffix:@".app"];
                                it.isExecutable = (!isDir && (st.st_mode & (S_IXUSR|S_IXGRP|S_IXOTH)));
                                it.size = st.st_size; it.mode = st.st_mode & 0777; it.uid = st.st_uid; it.gid = st.st_gid;
                                it.created = filerDateFromStat(&st, YES); it.modified = filerDateFromStat(&st, NO);
                                it.icon = [self iconForPath:full isApp:it.isApp isDir:isDir];
                                [newCol addObject:it];
                            }
                        }
                        [_columnItems addObject:newCol];
                        _previewItem = nil;
                    } else {
                        _previewItem = item;
                    }
                    [self setNeedsDisplay:YES];
                }
            }
            return;
        }
        _dragOrigin = loc;
        _dragOriginValid = YES;

        if(_viewMode == FilerViewModeList && loc.y > bounds.size.height - TOOLBAR_H - STATUS_H - LIST_HDR_H) {
            /* Column header: neither a row nor empty background. */
            return;
        }

        // Icons/List hit test
        float mainX = SIDEBAR_W;
        float mainW = bounds.size.width - SIDEBAR_W;
        NSInteger idx = -1;
        if(_viewMode == FilerViewModeIcons) {
            int cols = (int)(mainW / CELL_W); if(cols < 1) cols = 1;
            int col = (int)((loc.x - mainX) / CELL_W);
            int row = (int)((loc.y - TOOLBAR_H - 8.0f + _scrollOffsetY) / CELL_H);
            if(col >= 0 && col < cols && row >= 0) {
                NSInteger testIdx = row * cols + col;
                if(testIdx >= 0 && testIdx < (NSInteger)[_items count]) idx = testIdx;
            }
        } else {
            float rowY = loc.y - TOOLBAR_H - LIST_HDR_H + _scrollOffsetY;
            if(rowY >= 0) {
                NSInteger testIdx = (NSInteger)(rowY / LIST_ROW_H);
                if(testIdx >= 0 && testIdx < (NSInteger)[_items count]) idx = testIdx;
            }
        }
        // marquee start if empty
        if(idx < 0) {
            _marqueeActive = YES;
            _marqueeStart = loc;
            _marqueeRect = NSMakeRect(loc.x, loc.y, 0, 0);
            [_selectedIndexes removeAllIndexes];
            _selectedIndex = -1;
            [self setNeedsDisplay:YES];
            return;
        }
        /* Clicking the disclosure triangle expands or collapses the folder. */
        if(_viewMode == FilerViewModeList && idx >= 0 && idx < (NSInteger)[_items count]) {
            FileItem *hit = [_items objectAtIndex:idx];
            float triangleX = SIDEBAR_W + 8 + (float)hit.depth * 16.0f;

            if(hit.isDirectory && loc.x >= triangleX - 2 && loc.x <= triangleX + 18) {
                [self toggleExpansionOfItem:hit atIndex:idx];
                return;
            }
        }

        NSTimeInterval now = [event timestamp];
        BOOL isDouble = (idx >= 0 && idx == _lastClickedIndex && (now - _lastClickTime) < 0.6);
        _lastClickTime = now;
        _lastClickedIndex = idx;
        // multi-select with shift/cmd
        if([event modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask)) {
            if([_selectedIndexes containsIndex:idx]) [_selectedIndexes removeIndex:idx];
            else [_selectedIndexes addIndex:idx];
        } else {
            [_selectedIndexes removeAllIndexes];
            [_selectedIndexes addIndex:idx];
        }
        _selectedIndex = idx;
        [self setNeedsDisplay:YES];
        if(idx >= 0 && (isDouble || [event clickCount] >= 2)) {
            FileItem *item = [_items objectAtIndex:idx];
            if(item.isApp) filerOpenBundle(item.fullPath);
            else if(item.isDirectory) [self loadPath:item.fullPath addToHistory:YES];
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    /* A press on an item that moves more than a few pixels starts a drag
     * session instead of a marquee. */
    if(_dragOriginValid && !_marqueeActive && [_selectedIndexes count] > 0 && !_renameField) {
        NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
        CGFloat dx = loc.x - _dragOrigin.x;
        CGFloat dy = loc.y - _dragOrigin.y;

        if(dx * dx + dy * dy >= 25.0) {
            [self beginDragOutWithEvent:event];
            return;
        }
    }

    if(_marqueeActive) {
        NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
        float x = (_marqueeStart.x < loc.x) ? _marqueeStart.x : loc.x;
        float y = (_marqueeStart.y < loc.y) ? _marqueeStart.y : loc.y;
        float w = fabs(loc.x - _marqueeStart.x);
        float h = fabs(loc.y - _marqueeStart.y);
        _marqueeRect = NSMakeRect(x, y, w, h);
        // select intersecting items
        [_selectedIndexes removeAllIndexes];
        float mainX = SIDEBAR_W; float mainW = [self bounds].size.width - SIDEBAR_W;
        if(_viewMode == FilerViewModeIcons) {
            int cols = (int)(mainW / CELL_W); if(cols < 1) cols = 1;
            for(NSInteger i = 0; i < (NSInteger)[_items count]; i++) {
                int col = (int)(i % cols); int row = (int)(i / cols);
                float cx = mainX + col * CELL_W;
                float cy = TOOLBAR_H + 8.0f + row * CELL_H - _scrollOffsetY;
                NSRect cellRect = NSMakeRect(cx + 4, cy + 2, CELL_W - 8, CELL_H - 4);
                if(NSIntersectsRect(cellRect, _marqueeRect)) [_selectedIndexes addIndex:i];
            }
        } else if(_viewMode == FilerViewModeList) {
            for(NSInteger i = 0; i < (NSInteger)[_items count]; i++) {
                float ry = TOOLBAR_H + LIST_HDR_H + i * LIST_ROW_H - _scrollOffsetY;
                NSRect rowRect = NSMakeRect(mainX, ry, mainW, LIST_ROW_H);

                if(NSIntersectsRect(rowRect, _marqueeRect))
                    [_selectedIndexes addIndex:i];
            }
        }
        if([_selectedIndexes count] > 0) _selectedIndex = (NSInteger)[_selectedIndexes firstIndex];
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _dragOriginValid = NO;
    if(_marqueeActive) {
        _marqueeActive = NO;
        [self setNeedsDisplay:YES];
    }
}

#pragma mark - Dragging (source and destination)

/* Source-side callbacks of this AppKit build (NSObject categories in
 * NSDragging.h), not the NSDraggingSource protocol. */
- (BOOL)ignoreModifierKeysWhileDragging {
    return NO;
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal {
    return isLocal ? (NSDragOperationCopy | NSDragOperationMove) : NSDragOperationCopy;
}

- (NSArray *)draggedPaths {
    NSMutableArray *paths = [NSMutableArray array];
    NSUInteger idx = [_selectedIndexes firstIndex];

    while(idx != NSNotFound) {
        if(idx < [_items count])
            [paths addObject:[[_items objectAtIndex:idx] fullPath]];
        idx = [_selectedIndexes indexGreaterThanIndex:idx];
    }
    if([paths count] == 0 && _selectedIndex >= 0 &&
       _selectedIndex < (NSInteger)[_items count])
        [paths addObject:[[_items objectAtIndex:_selectedIndex] fullPath]];
    return paths;
}

- (void)beginDragOutWithEvent:(NSEvent *)event {
    NSArray *paths = [self draggedPaths];
    NSPasteboard *pb;
    NSImage *dragImage;
    NSPoint loc;

    if([paths count] == 0)
        return;

    pb = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pb clearContents];
    [pb setPropertyList:paths forType:NSFilenamesPboardType];
    [pb setString:[[NSURL fileURLWithPath:[paths objectAtIndex:0]] absoluteString]
          forType:NSPasteboardTypeFileURL];

    dragImage = [[NSImage alloc] initWithSize:NSMakeSize(48, 48)];
    [dragImage lockFocus];
    [[NSColor colorWithCalibratedWhite:0.95 alpha:0.9] setFill];
    NSRectFill(NSMakeRect(0, 0, 48, 48));
    [[NSColor darkGrayColor] setStroke];
    NSFrameRect(NSMakeRect(0, 0, 48, 48));
    [dragImage unlockFocus];

    loc = [self convertPoint:[event locationInWindow] fromView:nil];
    [self dragImage:dragImage at:loc offset:NSZeroSize event:event
            pasteboard:pb source:self slideBack:YES];
}

/* Insert (or remove) a folder's children directly after it, so the flat list
 * behaves like an outline.  Children inherit depth+1 and are marked so a
 * collapse can remove exactly them. */
- (void)toggleExpansionOfItem:(FileItem *)item atIndex:(NSInteger)idx {
    NSFileManager *fm = [NSFileManager defaultManager];

    if([_expandedPaths containsObject:item.fullPath]) {
        NSInteger removeCount = 0;
        NSInteger i;

        [_expandedPaths removeObject:item.fullPath];
        for(i = idx + 1; i < (NSInteger)[_items count]; i++) {
            FileItem *child = [_items objectAtIndex:i];

            if(child.depth <= item.depth)
                break;
            removeCount++;
        }
        if(removeCount > 0)
            [_items removeObjectsInRange:NSMakeRange((NSUInteger)idx + 1, (NSUInteger)removeCount)];
    } else {
        NSArray *names = [fm contentsOfDirectoryAtPath:item.fullPath error:nil];
        NSMutableArray *children = [NSMutableArray array];
        NSInteger i;

        [_expandedPaths addObject:item.fullPath];
        for(NSString *name in names) {
            NSString *full;
            BOOL isDir = NO;
            struct stat st;
            FileItem *child;

            if([name hasPrefix:@"."])
                continue;
            full = [item.fullPath stringByAppendingPathComponent:name];
            if(![fm fileExistsAtPath:full isDirectory:&isDir])
                continue;
            memset(&st, 0, sizeof(st));
            stat([full UTF8String], &st);
            child = [FileItem new];
            child.name = name;
            child.fullPath = full;
            child.isDirectory = isDir;
            child.isApp = [name hasSuffix:@".app"];
            child.isExecutable = (!isDir && (st.st_mode & (S_IXUSR|S_IXGRP|S_IXOTH)));
            child.size = st.st_size;
            child.mode = st.st_mode & 0777;
            child.uid = st.st_uid;
            child.gid = st.st_gid;
            child.created = filerDateFromStat(&st, YES);
            child.modified = filerDateFromStat(&st, NO);
            child.depth = item.depth + 1;
            [children addObject:child];
        }
        [children sortUsingSelector:@selector(compareFileItem:)];
        for(i = 0; i < (NSInteger)[children count]; i++)
            [_items insertObject:[children objectAtIndex:i] atIndex:(NSUInteger)(idx + 1 + i)];
        /* Row indices after the insertion no longer mean what they did. */
        [_selectedIndexes removeAllIndexes];
        _selectedIndex = idx;
        [_selectedIndexes addIndex:(NSUInteger)idx];
    }
    [self setNeedsDisplay:YES];
}

- (NSInteger)itemIndexAtPoint:(NSPoint)loc {
    float mainW = [self bounds].size.width - SIDEBAR_W;

    if(_viewMode == FilerViewModeIcons) {
        int cols = (int)(mainW / CELL_W);
        int col, row;
        NSInteger testIdx;

        if(cols < 1) cols = 1;
        col = (int)((loc.x - SIDEBAR_W) / CELL_W);
        row = (int)((loc.y - TOOLBAR_H - 8.0f + _scrollOffsetY) / CELL_H);
        if(col < 0 || col >= cols || row < 0)
            return -1;
        testIdx = row * cols + col;
        return (testIdx >= 0 && testIdx < (NSInteger)[_items count]) ? testIdx : -1;
    }

    if(_viewMode == FilerViewModeList) {
        float rowY = loc.y - TOOLBAR_H - LIST_HDR_H + _scrollOffsetY;
        NSInteger testIdx;

        if(rowY < 0)
            return -1;
        testIdx = (NSInteger)(rowY / LIST_ROW_H);
        return (testIdx >= 0 && testIdx < (NSInteger)[_items count]) ? testIdx : -1;
    }
    return -1;
}

- (NSString *)dropTargetDirectory {
    return _currentPath;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if([self dropTargetDirectoryForSender:sender] == nil)
        return NSDragOperationNone;
    [self setNeedsDisplay:YES];
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self draggingEntered:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [self setNeedsDisplay:YES];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return [self dropTargetDirectoryForSender:sender] != nil;
}

/* Folder under the cursor, or the window's current directory. */
- (NSString *)dropTargetDirectoryForSender:(id<NSDraggingInfo>)sender {
    /* draggingLocation is window coordinates; the view hit test needs view
     * coordinates.  The global pointer is not usable here: NSDisplay returns
     * the last event's window-relative point. */
    NSPoint p = [self convertPoint:[sender draggingLocation] fromView:nil];
    NSInteger idx = [self itemIndexAtPoint:p];
    NSString *target = _currentPath;

    if(idx >= 0 && idx < (NSInteger)[_items count]) {
        FileItem *item = [_items objectAtIndex:idx];

        if(item.isDirectory && !item.isApp)
            target = item.fullPath;
    }
    return target;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray *paths = [pb propertyListForType:NSFilenamesPboardType];
    NSString *target = [self dropTargetDirectoryForSender:sender];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL wantsMove = ([sender draggingSourceOperationMask] & NSDragOperationMove) != 0;
    unsigned moved = 0;

    if(paths == nil) {
        NSString *urlString = [pb stringForType:NSPasteboardTypeFileURL];

        if(urlString != nil) {
            NSURL *url = [NSURL URLWithString:urlString];

            if(url != nil)
                paths = [NSArray arrayWithObject:[url path]];
        }
    }
    if(paths == nil || target == nil)
        return NO;

    for(NSString *src in paths) {
        NSString *dest = [target stringByAppendingPathComponent:[src lastPathComponent]];

        if([[src stringByDeletingLastPathComponent] isEqualToString:target])
            continue;
        if([fm fileExistsAtPath:dest])
            dest = [self uniquePathFor:dest];
        if(wantsMove
           ? [fm moveItemAtPath:src toPath:dest error:NULL]
           : [fm copyItemAtPath:src toPath:dest error:NULL])
            moved++;
    }
    [self refresh];
    return moved > 0;
}

- (NSString *)uniquePathFor:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSString *base = [[path lastPathComponent] stringByDeletingPathExtension];
    NSString *ext = [path pathExtension];
    int i;

    for(i = 2; i < 1000; i++) {
        NSString *candidate = [ext length] > 0
            ? [NSString stringWithFormat:@"%@ %d.%@", base, i, ext]
            : [NSString stringWithFormat:@"%@ %d", base, i];
        NSString *full = [dir stringByAppendingPathComponent:candidate];

        if(![fm fileExistsAtPath:full])
            return full;
    }
    return path;
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event characters];
    unichar c = ([chars length] > 0) ? [chars characterAtIndex:0] : 0;
    NSUInteger mods = [event modifierFlags];
    BOOL cmd = (mods & NSCommandKeyMask) != 0;
    BOOL shift = (mods & NSShiftKeyMask) != 0;
    BOOL opt = (mods & NSAlternateKeyMask) != 0;

    if(cmd && c == NSUpArrowFunctionKey) { [self goUp]; return; }
    if(cmd && [chars isEqualToString:@"["]) { [self goBack]; return; }
    if(cmd && [chars isEqualToString:@"]"]) { [self goForward]; return; }
    if(cmd && shift && ([chars isEqualToString:@"N"])) { [self createNewFolder]; return; }
    if(c == '\r' || c == '\n') { if(_selectedIndex >= 0) [self beginInlineRenameAtIndex:_selectedIndex]; return; }
    if(cmd && [chars isEqualToString:@"d"]) { [self duplicateSelected]; return; }
    if(cmd && shift && (c == 0x7F || c == 0x08)) { [self emptyTrash]; return; }
    if(cmd && (c == 0x7F || c == 0x08)) { [self moveSelectedToTrash]; return; }
    if(cmd && [chars isEqualToString:@"c"]) { [self copySelectedToPasteboard]; return; }
    if(cmd && [chars isEqualToString:@"v"]) { [self pasteFromPasteboardMove:opt]; return; }
    if(cmd && [chars isEqualToString:@"i"]) {
        if(_selectedIndex >= 0 && _selectedIndex < (NSInteger)[_items count]) [self showGetInfoForItem:[_items objectAtIndex:_selectedIndex]];
        return;
    }
    // arrows
    if(c == NSUpArrowFunctionKey) {
        if(_selectedIndex > 0) _selectedIndex--;
        [self setNeedsDisplay:YES]; return;
    }
    if(c == NSDownArrowFunctionKey) {
        if(_selectedIndex + 1 < (NSInteger)[_items count]) _selectedIndex++;
        [self setNeedsDisplay:YES]; return;
    }
    [super keyDown:event];
}

- (void)copy:(id)sender { [self copySelectedToPasteboard]; }
- (void)paste:(id)sender { [self pasteFromPasteboardMove:NO]; }
- (void)cut:(id)sender { [self copySelectedToPasteboard]; }
- (void)selectAll:(id)sender {
    [_selectedIndexes removeAllIndexes];
    for(NSInteger i = 0; i < (NSInteger)[_items count]; i++) [_selectedIndexes addIndex:i];
    if([_items count] > 0) _selectedIndex = 0;
    [self setNeedsDisplay:YES];
}

@end

// Desktop view
@interface DesktopView : NSView {
    NSMutableArray *_desktopItems;
    NSPoint _dragStart;
    BOOL _dragging;
    NSInteger _selectedDesktopIndex;
}
- (void)refreshDesktop;
@end

@implementation DesktopView
- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if(self) { _desktopItems = [NSMutableArray new]; [self refreshDesktop]; }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)refreshDesktop {
    [_desktopItems removeAllObjects];
    NSString *desktop = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
    [[NSFileManager defaultManager] createDirectoryAtPath:desktop withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:desktop error:nil];
    for(NSString *f in files) {
        if([f hasPrefix:@"."]) continue;
        NSString *full = [desktop stringByAppendingPathComponent:f];
        BOOL isDir = NO; [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir];
        FileItem *it = [FileItem new];
        it.name = f; it.fullPath = full; it.isDirectory = isDir; it.isApp = [f hasSuffix:@".app"];
        struct stat st; memset(&st,0,sizeof(st)); stat([full UTF8String],&st);
        it.size = st.st_size; it.mode = st.st_mode & 0777;
        [_desktopItems addObject:it];
    }
    // mounted volumes
    NSArray *volEntries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:nil];
    for(NSString *v in volEntries) {
        NSString *full = [@"/Volumes" stringByAppendingPathComponent:v];
        FileItem *it;

        /* /Volumes can list a volume twice (device alias + mount point);
         * show one icon per path. */
        {
            BOOL seen = NO;

            for(FileItem *existing in _desktopItems)
                if([existing.fullPath isEqualToString:full]) { seen = YES; break; }
            if(seen)
                continue;
        }

        it = [FileItem new];
        it.name = v; it.fullPath = full; it.isDirectory = YES;
        struct statvfs vfs; memset(&vfs,0,sizeof(vfs));
        if(statvfs([full UTF8String], &vfs) == 0) {
            it.size = (off_t)vfs.f_blocks * (off_t)vfs.f_frsize;
        }
        [_desktopItems addObject:it];
    }
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSFont *f = [NSFont systemFontOfSize:11] ?: [NSFont systemFontOfSize:11];
    NSDictionary *a = [NSDictionary dictionaryWithObjectsAndKeys: f, NSFontAttributeName, [NSColor whiteColor], NSForegroundColorAttributeName, nil];
    float x = 20, y = 20;
    for(FileItem *it in _desktopItems) {
        NSRect iconRect = NSMakeRect(x, y, 48, 48);

        if([_desktopItems indexOfObjectIdenticalTo:it] == (NSUInteger)_selectedDesktopIndex) {
            CGContextSetRGBFillColor(ctx, 0.20, 0.52, 0.92, 0.35);
            CGContextFillRect(ctx, NSMakeRect(x - 6, y - 6, 60, 76));
            CGContextSetRGBStrokeColor(ctx, 0.20, 0.52, 0.92, 0.9);
            CGContextStrokeRect(ctx, NSMakeRect(x - 6, y - 6, 60, 76));
        }
        if(it.isApp) drawVectorApp(ctx, iconRect); else if(it.isDirectory) drawVectorFolder(ctx, iconRect); else drawVectorDocument(ctx, iconRect, NO);
        [it.name drawAtPoint:NSMakePoint(x, y + 52) withAttributes:a];
        // capacity badge for volumes
        if([it.fullPath hasPrefix:@"/Volumes"] || [it.fullPath isEqualToString:@"/"]) {
            struct statvfs vfs; memset(&vfs,0,sizeof(vfs));
            if(statvfs([it.fullPath UTF8String], &vfs) == 0) {
                off_t total = (off_t)vfs.f_blocks * (off_t)vfs.f_frsize;
                off_t free = (off_t)vfs.f_bavail * (off_t)vfs.f_frsize;
                NSString *badge = [NSString stringWithFormat:@"%@ / %@", filerFormatSize(free), filerFormatSize(total)];
                [badge drawAtPoint:NSMakePoint(x, y + 66) withAttributes:a];
            }
        }
        y += 90;
        if(y > [self bounds].size.height - 100) { y = 20; x += 90; }
    }
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:[event locationInWindow] fromView:nil];
    float x = 20, y = 20;
    NSInteger hit = -1;
    NSInteger i;

    for(i = 0; i < (NSInteger)[_desktopItems count]; i++) {
        if(NSPointInRect(loc, NSMakeRect(x, y, 48, 48)))
            hit = i;
        y += 90;
        if(y > [self bounds].size.height - 100) { y = 20; x += 90; }
    }

    _selectedDesktopIndex = hit;
    [self setNeedsDisplay:YES];

    if(hit >= 0 && [event clickCount] >= 2) {
        FileItem *item = [_desktopItems objectAtIndex:hit];
        NSURL *url = [NSURL fileURLWithPath:item.fullPath];
        LSOpenCFURLRef((__bridge CFURLRef)url, NULL);
    }
}
@end

@interface FilerAppDelegate : NSObject <NSApplicationDelegate> {
    NSMutableArray *_windows;
    int _windowCount;
}
@property (strong) NSString *currentPath;
- (void)newWindow:(id)sender;
- (NSWindow *)createWindowWithPath:(NSString *)path;
- (void)viewAsIcons:(id)sender;
- (void)viewAsList:(id)sender;
- (void)viewAsColumns:(id)sender;
- (void)refreshCurrentWindow:(id)sender;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)goUp:(id)sender;
@end

@implementation FilerAppDelegate
- (NSWindow *)createWindowWithPath:(NSString *)path {
    _windowCount++;
    CGFloat offset = ((_windowCount - 1) % 8) * 25.0f;
    NSRect frame = NSMakeRect(160 + offset, 160 - offset, 760, 500);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [win setDelegate:self];
    [win setTitle:[NSString stringWithFormat:@"Filer — %@", path]];
    NSRect contentBounds = [[win contentView] bounds];
    FileBrowserView *browserView = [[FileBrowserView alloc] initWithFrame:contentBounds];
    [browserView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[win contentView] addSubview:browserView];
    [browserView loadPath:path addToHistory:NO];
    [win registerForDraggedTypes:@[NSFilenamesPboardType, NSStringPboardType]];
    [win makeKeyAndOrderFront:nil];
    [win display];
    [_windows addObject:win];
    return win;
}
- (void)newWindow:(id)sender { [self createWindowWithPath:self.currentPath ?: @"/"]; }
- (FileBrowserView *)activeBrowserView {
    NSWindow *keyWin = [NSApp keyWindow];
    if(!keyWin && [_windows count] > 0) keyWin = [_windows lastObject];
    if(keyWin) for(NSView *v in [[keyWin contentView] subviews]) if([v isKindOfClass:[FileBrowserView class]]) return (FileBrowserView *)v;
    return nil;
}
- (void)viewAsIcons:(id)sender { [[self activeBrowserView] setViewMode:FilerViewModeIcons]; }
- (void)viewAsList:(id)sender { [[self activeBrowserView] setViewMode:FilerViewModeList]; }
- (void)viewAsColumns:(id)sender { [[self activeBrowserView] setViewMode:FilerViewModeColumns]; }
- (void)refreshCurrentWindow:(id)sender { [[self activeBrowserView] refresh]; }
- (void)goBack:(id)sender { [[self activeBrowserView] goBack]; }
- (void)goForward:(id)sender { [[self activeBrowserView] goForward]; }
- (void)goUp:(id)sender { [[self activeBrowserView] goUp]; }

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _windows = [NSMutableArray new];
    self.currentPath = @"/";
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *appMenuItem = [NSMenuItem new];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Filer"];
    [appMenu addItemWithTitle:@"About Filer" action:nil keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide Filer" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Quit Filer" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenuItem setTitle:@"Filer"]; [appMenuItem setSubmenu:appMenu];
    [appMenu setValue:@"NSAppleMenu" forKey:@"name"];
    [mainMenu addItem:appMenuItem];

    NSMenuItem *fileMenuItem = [NSMenuItem new];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Window" action:@selector(newWindow:) keyEquivalent:@"n"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"New Folder" action:@selector(ctxNewFolder:) keyEquivalent:@"N"];
    [[fileMenu itemAtIndex:[fileMenu numberOfItems]-1] setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    [fileMenuItem setTitle:@"File"]; [fileMenuItem setSubmenu:fileMenu];
    [mainMenu addItem:fileMenuItem];

    NSMenuItem *editMenuItem = [NSMenuItem new];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenuItem setTitle:@"Edit"]; [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];

    NSMenuItem *viewMenuItem = [NSMenuItem new];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"as Icons" action:@selector(viewAsIcons:) keyEquivalent:@"1"];
    [viewMenu addItemWithTitle:@"as List" action:@selector(viewAsList:) keyEquivalent:@"2"];
    [viewMenu addItemWithTitle:@"as Columns" action:@selector(viewAsColumns:) keyEquivalent:@"3"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Refresh" action:@selector(refreshCurrentWindow:) keyEquivalent:@"r"];
    [viewMenuItem setTitle:@"View"]; [viewMenuItem setSubmenu:viewMenu];
    [mainMenu addItem:viewMenuItem];

    NSMenuItem *goMenuItem = [NSMenuItem new];
    NSMenu *goMenu = [[NSMenu alloc] initWithTitle:@"Go"];
    [goMenu addItemWithTitle:@"Back" action:@selector(goBack:) keyEquivalent:@"["];
    [[goMenu itemAtIndex:[goMenu numberOfItems]-1] setKeyEquivalentModifierMask:NSCommandKeyMask];
    [goMenu addItemWithTitle:@"Forward" action:@selector(goForward:) keyEquivalent:@"]"];
    [[goMenu itemAtIndex:[goMenu numberOfItems]-1] setKeyEquivalentModifierMask:NSCommandKeyMask];
    [goMenu addItemWithTitle:@"Enclosing Folder" action:@selector(goUp:) keyEquivalent:@"Up"];
    [[goMenu itemAtIndex:[goMenu numberOfItems]-1] setKeyEquivalentModifierMask:NSCommandKeyMask];
    [goMenuItem setTitle:@"Go"]; [goMenuItem setSubmenu:goMenu];
    [mainMenu addItem:goMenuItem];

    [NSApp setMainMenu:mainMenu];
    // target wiring
    for(NSMenuItem *mi in [fileMenu itemArray]) [mi setTarget:self];
    for(NSMenuItem *mi in [editMenu itemArray]) [mi setTarget:[self activeBrowserView]];
    for(NSMenuItem *mi in [viewMenu itemArray]) [mi setTarget:self];
    for(NSMenuItem *mi in [goMenu itemArray]) [mi setTarget:self];

    [self createWindowWithPath:self.currentPath];
}

- (BOOL)windowShouldClose:(id)sender { return YES; }
- (void)windowWillClose:(NSNotification *)notification {
    NSWindow *closingWindow = [notification object];
    [_windows removeObject:closingWindow];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if ([_windows count] == 0) [self newWindow:nil];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        FilerAppDelegate *delegate = [FilerAppDelegate new];
        [app setDelegate:delegate];
        // desktop mode
        for(int i = 1; i < argc; i++) {
            if(strcmp(argv[i], "--desktop") == 0) {
                NSRect frame = [[NSScreen mainScreen] frame];
                NSWindow *dw = [[NSWindow alloc] initWithContentRect:frame styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
                [dw setLevel:0];
                DesktopView *dv = [[DesktopView alloc] initWithFrame:frame];
                [dv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
                [[dw contentView] addSubview:dv];
                [dw makeKeyAndOrderFront:nil];
            }
        }
        [app run];
    }
    return 0;
}
