/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>, 2008 Johannes Fortmann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE. */
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSView.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSFileManager.h>

#include <sys/param.h>
#include <sys/mount.h>

/* The file browser used by both NSSavePanel and NSOpenPanel.
 *
 * The panel is a modal NSWindow with the standard macOS layout: a sidebar
 * with volumes and places, a clickable breadcrumb bar, a file table
 * (Name / Size / Date Modified) and a bottom row with the name field, the
 * accessory view slot and the OK / Cancel buttons.
 */

@class RavynFilePanelController;

@interface RavynPanelTableView : NSTableView {
    RavynFilePanelController *_panelController;
}
- (void)setPanelController:(RavynFilePanelController *)controller;
@end

@implementation RavynPanelTableView
- (void)setPanelController:(RavynFilePanelController *)controller {
    _panelController = controller;
}
- (void)keyDown:(NSEvent *)event {
    if(_panelController != nil &&
       ([event modifierFlags] & (NSCommandKeyMask | NSShiftKeyMask)) == (NSCommandKeyMask | NSShiftKeyMask) &&
       [[event charactersIgnoringModifiers] isEqualToString:@"."]) {
        [_panelController toggleHiddenFiles:nil];
        return;
    }
    [super keyDown:event];
}
@end

@interface RavynPanelTextField : NSTextField {
    RavynFilePanelController *_panelController;
}
- (void)setPanelController:(RavynFilePanelController *)controller;
@end

@implementation RavynPanelTextField
- (void)setPanelController:(RavynFilePanelController *)controller {
    _panelController = controller;
}
- (void)keyDown:(NSEvent *)event {
    if(_panelController != nil &&
       ([event modifierFlags] & (NSCommandKeyMask | NSShiftKeyMask)) == (NSCommandKeyMask | NSShiftKeyMask) &&
       [[event charactersIgnoringModifiers] isEqualToString:@"."]) {
        [_panelController toggleHiddenFiles:nil];
        return;
    }
    [super keyDown:event];
}
@end

@interface RavynFilePanelController : NSObject {
    NSSavePanel *_panel;
    BOOL _isOpenPanel;

    NSWindow *_window;
    RavynPanelTableView *_table;
    RavynPanelTableView *_sidebar;
    RavynPanelTextField *_nameField;
    NSView *_breadcrumb;
    NSMutableArray *_entries;
    NSMutableArray *_places;
    NSString *_directory;
    NSString *_resultPath;
    NSMutableArray *_resultPaths;
    NSArray *_allowedTypes;
    BOOL _allowsOtherFileTypes;
    BOOL _showsHiddenFiles;
    BOOL _allowsMultipleSelection;
    BOOL _canChooseFiles;
    BOOL _canChooseDirectories;
    BOOL _treatsFilePackagesAsDirectories;
    BOOL _canCreateDirectories;
}

- (id)initWithPanel:(NSSavePanel *)panel open:(BOOL)isOpen;
- (int)runDirectory:(NSString *)directory file:(NSString *)file types:(NSArray *)types;
- (void)toggleHiddenFiles:(id)sender;
- (NSString *)resultPath;
- (NSArray *)resultPaths;
- (void)setCanChooseFiles:(BOOL)value;
- (void)setCanChooseDirectories:(BOOL)value;
- (void)setAllowsMultipleSelection:(BOOL)value;

@end

@implementation RavynFilePanelController

- (id)initWithPanel:(NSSavePanel *)panel open:(BOOL)isOpen {
    self = [super init];
    if(self != nil) {
        _panel = panel;
        _isOpenPanel = isOpen;
        _entries = [[NSMutableArray alloc] init];
        _places = [[NSMutableArray alloc] init];
        _resultPaths = [[NSMutableArray alloc] init];
        _showsHiddenFiles = NO;
        _allowsOtherFileTypes = YES;
    }
    return self;
}

- (void)dealloc {
    [_entries release];
    [_places release];
    [_resultPaths release];
    [_directory release];
    [_resultPath release];
    [super dealloc];
}

- (NSString *)resultPath {
    return _resultPath;
}

- (NSArray *)resultPaths {
    return _resultPaths;
}

- (void)setCanChooseFiles:(BOOL)value {
    _canChooseFiles = value;
}

- (void)setCanChooseDirectories:(BOOL)value {
    _canChooseDirectories = value;
}

- (void)setAllowsMultipleSelection:(BOOL)value {
    _allowsMultipleSelection = value;
}

#pragma mark - Layout

- (NSString *)_homeDirectory {
    NSString *home = NSHomeDirectory();
    return home != nil ? home : @"/";
}

- (void)_buildWindow {
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask;
    NSRect frame = NSMakeRect(0, 0, 680, 440);
    NSView *content;

    _window = [[NSWindow alloc] initWithContentRect:frame
                                           styleMask:style
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
    [_window setTitle:_isOpenPanel ? @"Open" : @"Save"];
    content = [_window contentView];

    /* Sidebar */
    _sidebar = [[RavynPanelTableView alloc] initWithFrame:NSMakeRect(8, 44, 160, 380)];
    [_sidebar setPanelController:self];
    [_sidebar setDataSource:self];
    [_sidebar setDelegate:self];
    {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"place"];
        [[col headerCell] setStringValue:@"Places"];
        [_sidebar addTableColumn:col];
        [col release];
    }
    [content addSubview:_sidebar];

    /* Breadcrumb bar */
    _breadcrumb = [[NSView alloc] initWithFrame:NSMakeRect(176, 380, 496, 26)];
    [content addSubview:_breadcrumb];

    /* File table */
    {
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(176, 60, 496, 316)];
        NSTableColumn *col;

        _table = [[RavynPanelTableView alloc] initWithFrame:[[scroll contentView] bounds]];
        [_table setPanelController:self];
        [_table setDataSource:self];
        [_table setDelegate:self];
        [_table setAllowsMultipleSelection:NO];
        [_table setDoubleAction:@selector(tableDoubleClick:)];

        col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [[col headerCell] setStringValue:@"Name"];
        [col setWidth:280];
        [_table addTableColumn:col];
        [col release];

        col = [[NSTableColumn alloc] initWithIdentifier:@"size"];
        [[col headerCell] setStringValue:@"Size"];
        [col setWidth:80];
        [_table addTableColumn:col];
        [col release];

        col = [[NSTableColumn alloc] initWithIdentifier:@"date"];
        [[col headerCell] setStringValue:@"Date Modified"];
        [col setWidth:130];
        [_table addTableColumn:col];
        [col release];

        [scroll setDocumentView:_table];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];
        [content addSubview:scroll];
        [scroll release];
    }

    /* Bottom row */
    {
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(176, 14, 70, 22)];
        [label setStringValue:_isOpenPanel ? @"File Name:" : @"Save As:"];
        [label setEditable:NO];
        [label setSelectable:NO];
        [label setBezeled:NO];
        [label setDrawsBackground:NO];
        [label setAlignment:NSRightTextAlignment];
        [content addSubview:label];
        [label release];

        _nameField = [[RavynPanelTextField alloc] initWithFrame:NSMakeRect(250, 14, 280, 22)];
        [_nameField setPanelController:self];
        [_nameField setTarget:self];
        [_nameField setAction:@selector(ok:)];
        [_nameField setEditable:YES];
        [content addSubview:_nameField];

        {
            NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(538, 12, 66, 26)];
            [ok setTitle:_isOpenPanel ? @"Open" : @"Save"];
            [ok setTarget:self];
            [ok setAction:@selector(ok:)];
            [ok setBezelStyle:NSRoundedBezelStyle];
            [ok setKeyEquivalent:@"\r"];
            [content addSubview:ok];
            [ok release];

            {
                NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(608, 12, 64, 26)];
                [cancel setTitle:@"Cancel"];
                [cancel setTarget:self];
                [cancel setAction:@selector(cancel:)];
                [cancel setBezelStyle:NSRoundedBezelStyle];
                [cancel setKeyEquivalent:@"\033"];
                [content addSubview:cancel];
                [cancel release];
            }
        }
    }

    /* Accessory view slot (save panel) */
    if(!_isOpenPanel) {
        NSView *accessory = [_panel accessoryView];
        if(accessory != nil) {
            NSRect r = [accessory frame];
            if(r.size.height <= 0)
                r = NSMakeRect(0, 0, 496, 60);
            [accessory setFrameOrigin:NSMakePoint(176, 60 + 316 - r.size.height + 6)];
            [content addSubview:accessory];
        }
    }

    /* Toolbar buttons above the table */
    {
        NSButton *back = [[NSButton alloc] initWithFrame:NSMakeRect(176, 356, 34, 22)];
        [back setTitle:@"<"];
        [back setTarget:self];
        [back setAction:@selector(goUp:)];
        [back setBezelStyle:NSRoundedBezelStyle];
        [content addSubview:back];
        [back release];

        {
            NSButton *hidden = [[NSButton alloc] initWithFrame:NSMakeRect(500, 356, 172, 22)];
            [hidden setTitle:@"Show Hidden Files"];
            [hidden setTarget:self];
            [hidden setAction:@selector(toggleHiddenFiles:)];
            [hidden setBezelStyle:NSRoundedBezelStyle];
            [content addSubview:hidden];
            [hidden release];
        }

        if(_canCreateDirectories) {
            NSButton *newFolder = [[NSButton alloc] initWithFrame:NSMakeRect(374, 356, 120, 22)];
            [newFolder setTitle:@"New Folder"];
            [newFolder setTarget:self];
            [newFolder setAction:@selector(newFolder:)];
            [newFolder setBezelStyle:NSRoundedBezelStyle];
            [content addSubview:newFolder];
            [newFolder release];
        }
    }
}

#pragma mark - Places and volumes

- (void)_populatePlaces {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *places = [NSMutableArray array];
    struct statfs *fs = NULL;
    int count = 0;
    int i;

    [_places removeAllObjects];

    /* Volumes: every mounted filesystem, once each. */
    count = getfsstat(NULL, 0, MNT_NOWAIT);
    if(count > 0) {
        fs = malloc(sizeof(struct statfs) * count);
        if(fs != NULL) {
            count = getfsstat(fs, sizeof(struct statfs) * count, MNT_NOWAIT);
            for(i = 0; i < count; i++) {
                NSString *mount = [NSString stringWithUTF8String:fs[i].f_mntonname];
                BOOL seen = NO;
                unsigned j;
                if(mount == nil)
                    continue;
                for(j = 0; j < [_places count]; j++)
                    if([[[_places objectAtIndex:j] objectForKey:@"path"] isEqualToString:mount])
                        seen = YES;
                if(!seen)
                    [_places addObject:@{@"title": mount, @"path": mount}];
            }
            free(fs);
        }
    }

    /* Places */
    [places addObject:@{@"title": @"Macintosh HD", @"path": @"/"}];
    [places addObject:@{@"title": @"Applications", @"path": @"/Applications"}];
    [places addObject:@{@"title": @"CoreServices", @"path": @"/System/Library/CoreServices"}];
    [places addObject:@{@"title": @"Home", @"path": [self _homeDirectory]}];
    [places addObject:@{@"title": @"Desktop", @"path": [[self _homeDirectory] stringByAppendingPathComponent:@"Desktop"]}];
    [places addObject:@{@"title": @"Documents", @"path": [[self _homeDirectory] stringByAppendingPathComponent:@"Documents"]}];
    [places addObject:@{@"title": @"Downloads", @"path": [[self _homeDirectory] stringByAppendingPathComponent:@"Downloads"]}];

    for(i = 0; i < (int)[places count]; i++) {
        NSDictionary *place = [places objectAtIndex:i];
        NSString *path = [place objectForKey:@"path"];
        if([fm fileExistsAtPath:path])
            [_places addObject:place];
    }

    [_sidebar reloadData];
}

#pragma mark - Directory listing

- (NSString *)_utiForExtension:(NSString *)ext {
    if([ext isEqualToString:@"txt"] || [ext isEqualToString:@"text"])
        return @"public.plain-text";
    if([ext isEqualToString:@"rtf"])
        return @"public.rtf";
    if([ext isEqualToString:@"rtfd"])
        return @"public.rtf-rtfd";
    if([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"])
        return @"net.daringfireball.markdown";
    if([ext isEqualToString:@"png"])
        return @"public.png";
    if([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
        return @"public.jpeg";
    if([ext isEqualToString:@"tif"] || [ext isEqualToString:@"tiff"])
        return @"public.tiff";
    if([ext isEqualToString:@"gif"])
        return @"com.compuserve.gif";
    if([ext isEqualToString:@"bmp"])
        return @"com.microsoft.bmp";
    if([ext isEqualToString:@"pdf"])
        return @"com.adobe.pdf";
    if([ext isEqualToString:@"zip"])
        return @"public.zip-archive";
    if([ext isEqualToString:@"ttf"])
        return @"public.truetype-ttf-font";
    if([ext isEqualToString:@"otf"])
        return @"public.opentype-font";
    if([ext isEqualToString:@"ttc"])
        return @"public.truetype-collection-font";
    if([ext isEqualToString:@"c"] || [ext isEqualToString:@"h"] || [ext isEqualToString:@"m"] ||
       [ext isEqualToString:@"py"] || [ext isEqualToString:@"sh"] || [ext isEqualToString:@"json"] ||
       [ext isEqualToString:@"plist"])
        return @"public.source-code";
    return nil;
}

- (BOOL)_entryMatchesTypes:(NSString *)name {
    NSString *ext;
    NSString *uti;
    unsigned i;

    if(_allowedTypes == nil || [_allowedTypes count] == 0)
        return YES;

    ext = [[name pathExtension] lowercaseString];
    uti = [self _utiForExtension:ext];

    for(i = 0; i < [_allowedTypes count]; i++) {
        NSString *allowed = [[_allowedTypes objectAtIndex:i] lowercaseString];
        if([allowed isEqualToString:ext])
            return YES;
        if(uti != nil && [allowed isEqualToString:uti])
            return YES;
        if([allowed isEqualToString:@"*"] || [allowed isEqualToString:@"public.data"])
            return YES;
    }

    return NO;
}

- (void)_reloadDirectory:(NSString *)directory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names;
    NSMutableArray *dirs = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    NSDateFormatter *formatter = [[[NSDateFormatter alloc]
                                     initWithDateFormat:@"yyyy-MM-dd HH:mm"
                                         allowNaturalLanguage:NO] autorelease];
    unsigned i;

    [_entries removeAllObjects];

    names = [fm contentsOfDirectoryAtPath:directory error:NULL];
    if(names == nil)
        names = [NSArray array];


    for(i = 0; i < [names count]; i++) {
        NSString *name = [names objectAtIndex:i];
        NSString *path = [directory stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        NSDictionary *attrs;
        unsigned long long size = 0;
        NSDate *date = nil;

        if(!_showsHiddenFiles && [name hasPrefix:@"."])
            continue;

        if(![fm fileExistsAtPath:path isDirectory:&isDir])
            continue;

        /* An application bundle is a file unless the panel is asked to treat
         * packages as directories. */
        if(isDir && !_treatsFilePackagesAsDirectories &&
           [[name pathExtension] isEqualToString:@"app"])
            isDir = NO;

        attrs = [fm fileAttributesAtPath:path traverseLink:NO];
        if(attrs != nil) {
            NSNumber *s = [attrs objectForKey:NSFileSize];
            if(s != nil)
                size = (unsigned long long)[s unsignedLongLongValue];
            date = [attrs objectForKey:NSFileModificationDate];
        }

        NSDictionary *entry = @{
            @"name": name,
            @"path": path,
            @"dir": [NSNumber numberWithBool:isDir],
            @"size": [NSNumber numberWithUnsignedLongLong:size],
            @"date": date != nil ? date : [NSDate date],
            @"allowed": [NSNumber numberWithBool:[self _entryMatchesTypes:name] || isDir]
        };

        if(isDir)
            [dirs addObject:entry];
        else
            [files addObject:entry];
    }

    /* Directories first, then case insensitive name order. */
    {
        NSMutableArray *d = [NSMutableArray arrayWithArray:dirs];
        NSMutableArray *f = [NSMutableArray arrayWithArray:files];
        unsigned x, y;

        for(x = 1; x < [d count]; x++) {
            NSDictionary *item = [d objectAtIndex:x];
            NSString *itemName = [item objectForKey:@"name"];
            y = x;
            while(y > 0) {
                NSDictionary *prev = [d objectAtIndex:y - 1];
                NSString *prevName = [prev objectForKey:@"name"];
                if([itemName caseInsensitiveCompare:prevName] == NSOrderedAscending) {
                    [d replaceObjectAtIndex:y withObject:prev];
                    y--;
                } else {
                    break;
                }
            }
            [d replaceObjectAtIndex:y withObject:item];
        }
        for(x = 1; x < [f count]; x++) {
            NSDictionary *item = [f objectAtIndex:x];
            NSString *itemName = [item objectForKey:@"name"];
            y = x;
            while(y > 0) {
                NSDictionary *prev = [f objectAtIndex:y - 1];
                NSString *prevName = [prev objectForKey:@"name"];
                if([itemName caseInsensitiveCompare:prevName] == NSOrderedAscending) {
                    [f replaceObjectAtIndex:y withObject:prev];
                    y--;
                } else {
                    break;
                }
            }
            [f replaceObjectAtIndex:y withObject:item];
        }

        [_entries addObjectsFromArray:d];
        [_entries addObjectsFromArray:f];
    }

    [_table reloadData];
}

- (void)_updateBreadcrumb {
    NSArray *subviews = [_breadcrumb subviews];
    unsigned i;
    NSMutableArray *components = [NSMutableArray array];
    NSString *path = _directory != nil ? _directory : @"/";
    float x = 4;

    for(i = 0; i < [subviews count]; i++)
        [[subviews objectAtIndex:i] removeFromSuperview];

    if(![path hasPrefix:@"/"]) {
        [components addObject:path];
    } else {
        NSArray *parts = [path componentsSeparatedByString:@"/"];
        NSMutableString *accumulated = [NSMutableString string];
        [components addObject:@"/"];
        for(i = 1; i < [parts count]; i++) {
            NSString *part = [parts objectAtIndex:i];
            if([part length] == 0)
                continue;
            [accumulated appendFormat:@"/%@", part];
            [components addObject:[accumulated copy]];
        }
    }

    for(i = 0; i < [components count]; i++) {
        NSString *component = [components objectAtIndex:i];
        NSString *title = component;
        NSButton *button;
        float width;

        if(i == 0)
            title = @"/";
        else
            title = [[component componentsSeparatedByString:@"/"] lastObject];

        width = 30 + [title length] * 7;
        button = [[NSButton alloc] initWithFrame:NSMakeRect(x, 2, width, 20)];
        [button setTitle:title];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setFont:[NSFont systemFontOfSize:11]];
        [button setTarget:self];
        [button setAction:@selector(breadcrumbClicked:)];
        [button setTag:(int)i];
        [_breadcrumb addSubview:button];
        [button release];
        x += width + 2;
    }
}

- (void)_navigateTo:(NSString *)directory {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;

    if(directory == nil || ![fm fileExistsAtPath:directory isDirectory:&isDir] || !isDir)
        directory = @"/";

    [_directory release];
    _directory = [directory copy];

    [self _reloadDirectory:_directory];
    [self _updateBreadcrumb];
}

#pragma mark - Actions

- (void)goUp:(id)sender {
    NSString *parent = [_directory stringByDeletingLastPathComponent];
    if(parent == nil || [parent length] == 0)
        parent = @"/";
    [self _navigateTo:parent];
}

- (void)breadcrumbClicked:(id)sender {
    NSArray *components = nil;
    NSString *path = _directory;
    unsigned i;

    if([sender respondsToSelector:@selector(tag)]) {
        int tag = [sender tag];
        NSMutableArray *parts = [NSMutableArray array];
        NSMutableString *accumulated = [NSMutableString string];

        if(path != nil && [path hasPrefix:@"/"]) {
            NSArray *raw = [path componentsSeparatedByString:@"/"];
            for(i = 1; i < [raw count]; i++) {
                if([[raw objectAtIndex:i] length] == 0)
                    continue;
                [accumulated appendFormat:@"/%@", [raw objectAtIndex:i]];
                [parts addObject:[accumulated copy]];
            }
        }
        if(tag == 0)
            [self _navigateTo:@"/"];
        else if(tag - 1 < (int)[parts count])
            [self _navigateTo:[parts objectAtIndex:tag - 1]];
        return;
    }
    (void)components;
}

- (void)toggleHiddenFiles:(id)sender {
    _showsHiddenFiles = !_showsHiddenFiles;
    if(sender != nil && [sender respondsToSelector:@selector(setTitle)])
        [sender setTitle:_showsHiddenFiles ? @"Hide Hidden Files" : @"Show Hidden Files"];
    [self _reloadDirectory:_directory];
}

- (void)newFolder:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [_directory stringByAppendingPathComponent:@"untitled folder"];
    NSString *path = base;
    int n = 2;

    while([fm fileExistsAtPath:path]) {
        path = [NSString stringWithFormat:@"%@ %d", base, n++];
    }

    if([fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL]) {
        [self _reloadDirectory:_directory];
        [_nameField setStringValue:[path lastPathComponent]];
    }
}

- (void)tableDoubleClick:(id)sender {
    int row = [_table clickedRow];
    if(row < 0 || row >= (int)[_entries count])
        return;

    NSDictionary *entry = [_entries objectAtIndex:row];
    if([[entry objectForKey:@"dir"] boolValue]) {
        [self _navigateTo:[entry objectForKey:@"path"]];
        return;
    }
    [self ok:nil];
}

- (void)ok:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *name = [_nameField stringValue];
    int row = [_table selectedRow];

    /* Multiple selection: every selected row is a result. */
    if(_allowsMultipleSelection) {
        int r;
        [_resultPaths removeAllObjects];
        for(r = 0; r < (int)[_entries count]; r++) {
            NSDictionary *entry;
            if(![_table isRowSelected:r])
                continue;
            entry = [_entries objectAtIndex:r];
            if([[entry objectForKey:@"dir"] boolValue] && !_canChooseDirectories)
                continue;
            [_resultPaths addObject:[entry objectForKey:@"path"]];
        }
        if([_resultPaths count] > 0) {
            [_resultPath release];
            _resultPath = [[_resultPaths objectAtIndex:0] copy];
            [NSApp stopModalWithCode:NSFileHandlingPanelOKButton];
            return;
        }
    }

    if(row >= 0 && row < (int)[_entries count]) {
        NSDictionary *entry = [_entries objectAtIndex:row];
        if([[entry objectForKey:@"dir"] boolValue] && !_canChooseDirectories) {
            [self _navigateTo:[entry objectForKey:@"path"]];
            return;
        }
        name = [entry objectForKey:@"name"];
    }

    if(name == nil || [name length] == 0) {
        [self cancel:nil];
        return;
    }

    if([name hasPrefix:@"/"]) {
        [_resultPath release];
        _resultPath = [name copy];
    } else {
        NSString *path = [_directory stringByAppendingPathComponent:name];
        if(_isOpenPanel) {
            BOOL isDir = NO;
            if(![fm fileExistsAtPath:path isDirectory:&isDir]) {
                [self cancel:nil];
                return;
            }
            if(isDir && !_canChooseDirectories) {
                [self _navigateTo:path];
                return;
            }
            if(!isDir && !_canChooseFiles) {
                [self cancel:nil];
                return;
            }
        }
        [_resultPath release];
        _resultPath = [path copy];
    }

    [_resultPaths removeAllObjects];
    [_resultPaths addObject:_resultPath];

    [NSApp stopModalWithCode:NSFileHandlingPanelOKButton];
}

- (void)cancel:(id)sender {
    [NSApp stopModalWithCode:NSFileHandlingPanelCancelButton];
}

#pragma mark - Table data source

- (int)numberOfRowsInTableView:(NSTableView *)tableView {
    if(tableView == _sidebar)
        return (int)[_places count];
    return (int)[_entries count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)col row:(int)row {
    if(tableView == _sidebar) {
        if(row < 0 || row >= (int)[_places count])
            return nil;
        return [[_places objectAtIndex:row] objectForKey:@"title"];
    }

    if(row < 0 || row >= (int)[_entries count])
        return nil;

    NSDictionary *entry = [_entries objectAtIndex:row];
    NSString *identifier = [col identifier];

    if([identifier isEqualToString:@"name"])
        return [entry objectForKey:@"name"];
    if([identifier isEqualToString:@"size"]) {
        if([[entry objectForKey:@"dir"] boolValue])
            return @"--";
        unsigned long long size = [[entry objectForKey:@"size"] unsignedLongLongValue];
        if(size < 1024)
            return [NSString stringWithFormat:@"%llu bytes", size];
        if(size < 1024 * 1024)
            return [NSString stringWithFormat:@"%.1f KB", (double)size / 1024.0];
        return [NSString stringWithFormat:@"%.1f MB", (double)size / (1024.0 * 1024.0)];
    }
    if([identifier isEqualToString:@"date"]) {
        NSDate *date = [entry objectForKey:@"date"];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc]
                                     initWithDateFormat:@"yyyy-MM-dd HH:mm"
                                         allowNaturalLanguage:NO] autorelease];
        return [formatter stringFromDate:date];
    }

    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    if([note object] != _sidebar)
        return;
    int row = [_sidebar selectedRow];
    if(row < 0 || row >= (int)[_places count])
        return;
    [self _navigateTo:[[_places objectAtIndex:row] objectForKey:@"path"]];
}

#pragma mark - Running

- (int)runDirectory:(NSString *)directory file:(NSString *)file types:(NSArray *)types {
    int result;

    /* The types given to the run call win; otherwise the panel's own
     * allowed file types are used. */
    _allowedTypes = types != nil && [types count] > 0 ? types : [_panel allowedFileTypes];
    _allowsOtherFileTypes = [_panel allowsOtherFileTypes];
    _treatsFilePackagesAsDirectories = [_panel treatsFilePackagesAsDirectories];
    _canCreateDirectories = [_panel canCreateDirectories];
    _showsHiddenFiles = [_panel showsHiddenFiles];
    _canChooseFiles = [_panel _panelCanChooseFiles];
    _canChooseDirectories = [_panel _panelCanChooseDirectories];
    _allowsMultipleSelection = [_panel _panelAllowsMultipleSelection];

    [self _buildWindow];
    [_table setAllowsMultipleSelection:_allowsMultipleSelection];
    [self _populatePlaces];

    if(directory == nil)
        directory = [_panel directory];
    if(directory == nil || [directory length] == 0)
        directory = [self _homeDirectory];

    [self _navigateTo:directory];

    if(file != nil && [file length] > 0)
        [_nameField setStringValue:file];
    else if([_panel nameFieldStringValue] != nil)
        [_nameField setStringValue:[_panel nameFieldStringValue]];

    [_window makeKeyAndOrderFront:nil];
    result = [NSApp runModalForWindow:_window];
    [_window orderOut:nil];

    if(result != NSFileHandlingPanelOKButton || _resultPath == nil)
        return NSFileHandlingPanelCancelButton;

    return NSFileHandlingPanelOKButton;
}

@end

@implementation NSSavePanel

+(NSSavePanel *)savePanel {
   return [[self new] autorelease];
}

-init {
   [super initWithContentRect:NSMakeRect(0,0,1,1) styleMask:NSTitledWindowMask|NSResizableWindowMask backing:NSBackingStoreBuffered defer:YES];

   _dialogTitle=@"Save";
   _filename=@"";
   _directory=[NSHomeDirectory() copy];
   _requiredFileType=@"";
   _treatsFilePackagesAsDirectories=NO;
   _accessoryView=nil;
   _canCreateDirectories=YES;
   _allowsOtherFileTypes=NO;
   _showsHiddenFiles=NO;
   _allowedFileTypes=[[NSArray alloc] init];
   _nameFieldStringValue=nil;
   return self;
}

-(void)dealloc {
   [_dialogTitle release];
   [_filename release];
   [_directory release];
   [_requiredFileType release];
   [_accessoryView release];
   [_allowedFileTypes release];
   [_nameFieldStringValue release];
   [super dealloc];
}

-(void)_setFilename:(NSString*)filename {
   @synchronized(self) {
      if(filename!=_filename) {
         [_filename release];
         _filename=[filename copy];
         if(_filename==nil) {
            _filename=@"";
         }
      }
   }
}

-(NSURL *)URL {
   return [NSURL fileURLWithPath:[self filename]];
}

-(NSString *)filename {
   id ret=nil;
	@synchronized(self)
	{
		ret=[[_filename copy] autorelease];
	}
	return ret;
}

-(NSString *)directory {
   id ret=nil;
	@synchronized(self)
	{
		ret=[[_directory copy] autorelease];
	}
	return ret;
}

-(BOOL)treatsFilePackagesAsDirectories {
   return _treatsFilePackagesAsDirectories;
}

-(NSView *)accessoryView {
   return _accessoryView;
}

-(void)setTitle:(NSString *)title {
   [_dialogTitle release];
   _dialogTitle=[title copy];
}

-(void)setDirectory:(NSString *)directory {
	@synchronized(self)
	{
		[_directory release];
		_directory=[directory copy];
	}
}

-(void)setRequiredFileType:(NSString *)type {
   [_requiredFileType release];
   _requiredFileType=[type copy];
}

-(void)setTreatsFilePackagesAsDirectories:(BOOL)flag {
   _treatsFilePackagesAsDirectories=flag;
}

-(void)setAccessoryView:(NSView *)view {
   [_accessoryView release];
   _accessoryView=[view retain];
}

-(void)setCanCreateDirectories:(BOOL)value {
   _canCreateDirectories=value;
}

-(BOOL)canCreateDirectories {
   return _canCreateDirectories;
}

-(void)setAllowedFileTypes:(NSArray *)value {
   [_allowedFileTypes release];
   _allowedFileTypes=[value copy];
}

-(NSArray *)allowedFileTypes {
   return _allowedFileTypes;
}

-(void)setAllowsOtherFileTypes:(BOOL)value {
   _allowsOtherFileTypes=value;
}

-(BOOL)allowsOtherFileTypes {
   return _allowsOtherFileTypes;
}

-(void)setShowsHiddenFiles:(BOOL)value {
   _showsHiddenFiles=value;
}

-(BOOL)showsHiddenFiles {
   return _showsHiddenFiles;
}

-(void)setNameFieldStringValue:(NSString *)value {
   [_nameFieldStringValue release];
   _nameFieldStringValue=[value copy];
}

-(NSString *)nameFieldStringValue {
   return _nameFieldStringValue;
}

-(void)setMessage:(NSString *)message {
   [_message release];
   _message=[message copy];
}

-(NSString *)message {
   return _message;
}

-(void)setPrompt:(NSString *)message {
   [_prompt release];
   _prompt=[message copy];
}

-(NSString *)prompt {
   return _prompt;
}

/* The panel's own modal run: NSDisplay forwards to this so that the panel
 * does not have to know about the display. */
-(int)_runRavynModalForDirectory:(NSString *)directory file:(NSString *)file types:(NSArray *)types {
   RavynFilePanelController *controller = [[RavynFilePanelController alloc] initWithPanel:self
                                                                                    open:[self _panelIsOpenPanel]];
   int result = [controller runDirectory:directory file:file types:types];

   if(result == NSFileHandlingPanelOKButton) {
      NSArray *paths = [controller resultPaths];
      if([paths count] > 0)
         [self _panelDidChoosePaths:paths];
   }
   [controller release];

   return result;
}

-(BOOL)_panelIsOpenPanel {
   return NO;
}

-(BOOL)_panelCanChooseFiles {
   return YES;
}

-(BOOL)_panelCanChooseDirectories {
   return NO;
}

-(BOOL)_panelAllowsMultipleSelection {
   return NO;
}

-(void)_panelDidChoosePaths:(NSArray *)paths {
   NSString *path = [paths objectAtIndex:0];
   [self _setFilename:[path lastPathComponent]];
   [self setDirectory:[path stringByDeletingLastPathComponent]];
}

-(int)runModalForDirectory:(NSString *)directory file:(NSString *)file {
   return [self _runRavynModalForDirectory:directory file:file types:nil];
}

-(int)runModal {
   return [self runModalForDirectory:nil file:nil];
}

-(void)beginSheetForDirectory:(NSString *)path
                          file:(NSString *)name
                modalForWindow:(NSWindow *)docWindow
                 modalDelegate:(id)modalDelegate
                didEndSelector:(SEL)didEndSelector
                   contextInfo:(void *)contextInfo
{
   /* Sheets run on the main thread: the panel is a modal window and the
    * delegate callback has to arrive on the main run loop. */
   int ret = [self _runRavynModalForDirectory:path file:name types:nil];

   if(modalDelegate != nil && didEndSelector != NULL) {
      NSMethodSignature *signature = [modalDelegate methodSignatureForSelector:didEndSelector];
      if(signature != nil) {
         NSInvocation *inv = [NSInvocation invocationWithMethodSignature:signature];
         [inv setTarget:modalDelegate];
         [inv setSelector:didEndSelector];
         [inv setArgument:&self atIndex:2];
         [inv setArgument:&ret atIndex:3];
         [inv setArgument:&contextInfo atIndex:4];
         [inv retainArguments];
         [inv invoke];
      }
   }
}

@end
