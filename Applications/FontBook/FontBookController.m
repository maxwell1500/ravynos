#import "FontBookController.h"
#import <Onyx2D/O2Font_ttf.h>

@implementation FontBookController

- (id)init {
    self = [super init];
    if(self) {
        _sidebarItems = [[NSArray alloc] initWithObjects:@"All Fonts", @"System", @"Computer", @"User", nil];
        _currentSidebar = @"All Fonts";
    }
    return self;
}
 // ARC

- (NSArray *)fontsForSidebar:(NSString *)side {
    NSMutableArray *result = [NSMutableArray array];
    for(NSDictionary *f in _allFonts) {
        NSString *path = [f objectForKey:@"FilePath"];
        BOOL include = NO;
        if([side isEqualToString:@"All Fonts"]) include = YES;
        else if([side isEqualToString:@"System"]) include = [path hasPrefix:@"/System/Library/Fonts"];
        else if([side isEqualToString:@"Computer"]) include = [path hasPrefix:@"/Library/Fonts"];
        else if([side isEqualToString:@"User"]) include = [path hasPrefix:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Fonts"]];
        if(include) [result addObject:f];
    }
    return result;
}

- (NSArray *)familiesForCurrentFilter {
    NSString *query = [_searchField stringValue];
    NSMutableArray *families = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for(NSDictionary *f in [self fontsForSidebar:_currentSidebar]) {
        NSString *fam = [f objectForKey:@"Family"];
        if(query != nil && [query length] > 0) {
            if([fam rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound &&
               [[f objectForKey:@"PostScriptName"] rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound)
                continue;
        }
        if(![seen containsObject:fam]) {
            [seen addObject:fam];
            [families addObject:fam];
        }
    }
    [families sortUsingSelector:@selector(compare:)];
    return families;
}

- (NSArray *)facesForFamily:(NSString *)family {
    NSMutableArray *result = [NSMutableArray array];
    for(NSDictionary *f in [self fontsForSidebar:_currentSidebar]) {
        if([[f objectForKey:@"Family"] isEqualToString:family])
            [result addObject:f];
    }
    return result;
}

- (void)reloadFonts {
    [O2Font_ttf loadAllFontsInDirectories];
    _allFonts = [O2Font_ttf discoveredFonts];
    [_familyOutline reloadData];
    [_sidebarTable reloadData];
}

- (void)showWindow {
    if(_window != nil) { [_window makeKeyAndOrderFront:nil]; return; }

    NSRect frame = NSMakeRect(100, 100, 900, 600);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Font Book"];

    NSView *content = [_window contentView];

    // Sidebar table (left)
    NSScrollView *sideScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 40, 180, 560)];
    _sidebarTable = [[NSTableView alloc] initWithFrame:[sideScroll bounds]];
    NSTableColumn *sideCol = [[NSTableColumn alloc] initWithIdentifier:@"side"];
    [sideCol setWidth:180];
    [_sidebarTable addTableColumn:sideCol];
    [_sidebarTable setDataSource:self];
    [_sidebarTable setDelegate:self];
    [sideScroll setDocumentView:_sidebarTable];
    [content addSubview:sideScroll];

    // Family outline (middle)
    NSScrollView *midScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(180, 40, 240, 560)];
    _familyOutline = [[NSOutlineView alloc] initWithFrame:[midScroll bounds]];
    NSTableColumn *midCol = [[NSTableColumn alloc] initWithIdentifier:@"family"];
    [midCol setWidth:240];
    [_familyOutline addTableColumn:midCol];
    [_familyOutline setOutlineTableColumn:midCol];
    [_familyOutline setDataSource:self];
    [_familyOutline setDelegate:self];
    [midScroll setDocumentView:_familyOutline];
    [content addSubview:midScroll];

    // Preview (right)
    _previewView = [[FontPreviewView alloc] initWithFrame:NSMakeRect(420, 40, 480, 560)];
    [content addSubview:_previewView];

    // Toolbar area top
    _searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(180, 5, 240, 24)];
    [[_searchField cell] setPlaceholderString:@"Search fonts"];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(searchChanged:)];
    [content addSubview:_searchField];

    NSButton *addBtn = [[NSButton alloc] initWithFrame:NSMakeRect(5, 5, 120, 24)];
    [addBtn setTitle:@"Add Fonts…"];
    [addBtn setTarget:self];
    [addBtn setAction:@selector(addFonts:)];
    [addBtn setKeyEquivalent:@"o"];
    [addBtn setKeyEquivalentModifierMask:NSCommandKeyMask];
    [content addSubview:addBtn];

    _modeSegment = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(430, 5, 240, 24)];
    [_modeSegment setSegmentCount:3];
    [_modeSegment setLabel:@"Sample" forSegment:0];
    [_modeSegment setLabel:@"Repertoire" forSegment:1];
    [_modeSegment setLabel:@"Font Info" forSegment:2];
    [_modeSegment setTarget:self];
    [_modeSegment setAction:@selector(modeChanged:)];
    [content addSubview:_modeSegment];

    NSButton *validateBtn = [[NSButton alloc] initWithFrame:NSMakeRect(680, 5, 120, 24)];
    [validateBtn setTitle:@"Validate Font"];
    [validateBtn setTarget:self];
    [validateBtn setAction:@selector(validateFont:)];
    [content addSubview:validateBtn];

    [_window makeKeyAndOrderFront:nil];
    [self reloadFonts];
}

- (void)searchChanged:(id)sender {
    [_familyOutline reloadData];
}

- (void)modeChanged:(id)sender {
    [_previewView setMode:[_modeSegment selectedSegment]];
}

- (void)validateFont:(id)sender {
    [_previewView validate];
}

- (void)addFonts:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:YES];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"ttf", @"otf", @"ttc", nil]];
    if([panel runModal] == NSFileHandlingPanelOKButton) {
        NSArray *urls = [panel URLs];
        if(urls == nil || [urls count] == 0) {
            NSString *fn = [panel filename];
            if(fn) urls = [NSArray arrayWithObject:[NSURL fileURLWithPath:fn]];
        }
        for(NSURL *url in urls) {
            NSString *path = [url path];
            // validate
            NSArray *missing = nil;
            if(![O2Font_ttf validateFontFileAtPath:path missingTables:&missing]) continue;
            // copy to ~/Library/Fonts
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *fontsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Fonts"];
            [fm createDirectoryAtPath:fontsDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *dest = [fontsDir stringByAppendingPathComponent:[path lastPathComponent]];
            if([fm fileExistsAtPath:dest]) {
                // append number
                NSString *base = [path lastPathComponent];
                NSString *name = [base stringByDeletingPathExtension];
                NSString *ext = [base pathExtension];
                int i = 2;
                do {
                    dest = [fontsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d.%@", name, i, ext]];
                    i++;
                } while([fm fileExistsAtPath:dest]);
            }
            [fm copyItemAtPath:path toPath:dest error:nil];
            [O2Font_ttf registerFontFileAtPath:dest];
        }
        [self reloadFonts];
    }
}

// Sidebar table data source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if(tableView == _sidebarTable) return [_sidebarItems count];
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if(tableView == _sidebarTable) return [_sidebarItems objectAtIndex:row];
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if([notification object] == _sidebarTable) {
        NSInteger row = [_sidebarTable selectedRow];
        if(row >= 0 && row < [_sidebarItems count]) {
            _currentSidebar = [_sidebarItems objectAtIndex:row];
            [_familyOutline reloadData];
        }
    }
}

// Outline data source
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if(item == nil) {
        return [[self familiesForCurrentFilter] count];
    }
    if([item isKindOfClass:[NSString class]]) {
        return [[self facesForFamily:item] count];
    }
    return 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if(item == nil) return NO;
    if([item isKindOfClass:[NSString class]]) return YES;
    return NO;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if(item == nil) {
        NSArray *fams = [self familiesForCurrentFilter];
        if(index < [fams count]) return [fams objectAtIndex:index];
        return nil;
    }
    if([item isKindOfClass:[NSString class]]) {
        NSArray *faces = [self facesForFamily:item];
        if(index < [faces count]) return [faces objectAtIndex:index];
    }
    return nil;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    if([item isKindOfClass:[NSString class]]) return item;
    if([item isKindOfClass:[NSDictionary class]]) return [item objectForKey:@"Style"];
    return nil;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    id item = [_familyOutline itemAtRow:[_familyOutline selectedRow]];
    if([item isKindOfClass:[NSDictionary class]]) {
        _selectedFont = item;
        [_previewView setFont:item];
    }
}

@end