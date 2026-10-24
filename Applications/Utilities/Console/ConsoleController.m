#import "ConsoleController.h"
#import "LogCollector.h"

static NSArray *kSources(void) {
    return @[@"All Messages", @"Kernel (dmesg)", @"system.log", @"Crash Reports"];
}

static NSString *sourceKeyForIndex(NSInteger idx) {
    switch (idx) {
        case 0: return nil; // all
        case 1: return @"Kernel";
        case 2: return @"system.log";
        case 3: return @"Crash Reports";
    }
    return nil;
}

@implementation ConsoleController

@synthesize window, sidebarScroll, sidebarTable, tableScroll, logTable, detailScroll, detailView, searchField, severityPopup, collector, entries, sources, selectedSource, selectedSeverity, nowMode;

- (id)init {
    self = [super init];
    if (self) {
        entries = [NSMutableArray array];
        sources = kSources();
        selectedSource = 0;
        selectedSeverity = @"All";
        nowMode = YES;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    collector = [[LogCollector alloc] initWithController:self];
    [self buildWindow];
    [collector start];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(100, 80, 960, 620);
    window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [window setTitle:@"Console"];
    [window setDelegate:self];
    [window center];

    NSView *content = [window contentView];
    NSRect cb = [content bounds];

    // Sidebar
    NSRect sideFrame = NSMakeRect(0, 0, 180, cb.size.height);
    sidebarScroll = [[NSScrollView alloc] initWithFrame:sideFrame];
    [sidebarScroll setHasVerticalScroller:YES];
    sidebarTable = [[NSTableView alloc] initWithFrame:sideFrame];
    NSTableColumn *sc = [[NSTableColumn alloc] initWithIdentifier:@"src"];
    [sc setWidth:170];
    [[sc headerCell] setStringValue:@"Sources"];
    [sidebarTable addTableColumn:sc];
    [sidebarTable setDataSource:self];
    [sidebarTable setDelegate:self];
    [sidebarTable setHeaderView:nil];
    [sidebarScroll setDocumentView:sidebarTable];
    [sidebarScroll setAutoresizingMask:NSViewHeightSizable];
    [content addSubview:sidebarScroll];

    // Top filter bar
    NSRect barFrame = NSMakeRect(180, cb.size.height - 36, cb.size.width - 180, 36);
    NSView *bar = [[NSView alloc] initWithFrame:barFrame];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    // Severity popup
    severityPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(8, 6, 120, 24) pullsDown:NO];
    [severityPopup addItemsWithTitles:@[@"All", @"Default", @"Info", @"Debug", @"Error", @"Fault"]];
    [severityPopup setTarget:self];
    [severityPopup setAction:@selector(severityChanged:)];
    [bar addSubview:severityPopup];

    // Search field
    searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 6, 260, 24)];
    [[searchField cell] setPlaceholderString:@"Search (Cmd+F)"];
    [searchField setTarget:self];
    [searchField setAction:@selector(searchChanged:)];
    [bar addSubview:searchField];

    // Clear button
    NSButton *clearBtn = [[NSButton alloc] initWithFrame:NSMakeRect(410, 6, 100, 24)];
    [clearBtn setTitle:@"Clear Display"];
    [clearBtn setBezelStyle:NSRoundedBezelStyle];
    [clearBtn setTarget:self];
    [clearBtn setAction:@selector(clearDisplay:)];
    [bar addSubview:clearBtn];

    // Now toggle
    NSButton *nowBtn = [[NSButton alloc] initWithFrame:NSMakeRect(520, 6, 80, 24)];
    [nowBtn setTitle:@"Now"];
    [nowBtn setButtonType:NSSwitchButton];
    [nowBtn setState:NSOnState];
    [nowBtn setTarget:self];
    [nowBtn setAction:@selector(nowToggled:)];
    [bar addSubview:nowBtn];

    [content addSubview:bar];

    // Log table
    NSRect tableFrame = NSMakeRect(180, 180, cb.size.width - 180, cb.size.height - 36 - 180);
    tableScroll = [[NSScrollView alloc] initWithFrame:tableFrame];
    [tableScroll setHasVerticalScroller:YES];
    [tableScroll setHasHorizontalScroller:YES];
    logTable = [[NSTableView alloc] initWithFrame:tableFrame];
    NSArray *cols = @[
        @[@"Time", @"time", @150.0],
        @[@"Process", @"process", @120.0],
        @[@"PID", @"pid", @60.0],
        @[@"Level", @"level", @80.0],
        @[@"Message", @"message", @400.0],
    ];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[1]];
        [col setWidth:[c[2] doubleValue]];
        [[col headerCell] setStringValue:c[0]];
        [logTable addTableColumn:col];
    }
    [logTable setDataSource:self];
    [logTable setDelegate:self];
    [tableScroll setDocumentView:logTable];
    [tableScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:tableScroll];

    // Detail view
    NSRect detailFrame = NSMakeRect(180, 0, cb.size.width - 180, 180);
    detailScroll = [[NSScrollView alloc] initWithFrame:detailFrame];
    [detailScroll setHasVerticalScroller:YES];
    detailView = [[NSTextView alloc] initWithFrame:detailFrame];
    [detailView setEditable:NO];
    [detailView setFont:[NSFont userFixedPitchFontOfSize:11]];
    [detailScroll setDocumentView:detailView];
    [detailScroll setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:detailScroll];

    [window makeKeyAndOrderFront:nil];
}

- (NSArray *)filteredEntries {
    NSMutableArray *out = [NSMutableArray array];
    NSString *srcKey = sourceKeyForIndex(selectedSource);
    NSString *search = [searchField stringValue];
    for (LogEntry *e in entries) {
        if (srcKey) {
            if (![e.source isEqualToString:srcKey]) continue;
        }
        if (![selectedSeverity isEqualToString:@"All"]) {
            if (![e.level isEqualToString:selectedSeverity]) continue;
        }
        if (search.length > 0) {
            if ([e.message rangeOfString:search options:NSCaseInsensitiveSearch].location == NSNotFound &&
                [e.raw rangeOfString:search options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        }
        [out addObject:e];
    }
    return out;
}

- (void)appendEntries:(NSArray *)newEntries {
    [entries addObjectsFromArray:newEntries];
    [self reloadLogTable];
    if (nowMode && newEntries.count > 0) {
        NSArray *fe = [self filteredEntries];
        if (fe.count > 0) {
            [logTable scrollRowToVisible:(int)(fe.count - 1)];
        }
    }
}

- (void)reloadLogTable {
    [logTable reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == sidebarTable) return sources.count;
    return [self filteredEntries].count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == sidebarTable) {
        return [sources objectAtIndex:row];
    }
    NSArray *fe = [self filteredEntries];
    if (row < 0 || row >= (NSInteger)fe.count) return nil;
    LogEntry *e = [fe objectAtIndex:row];
    NSString *ident = [tableColumn identifier];
    if ([ident isEqualToString:@"time"]) return e.timestamp;
    if ([ident isEqualToString:@"process"]) return e.process;
    if ([ident isEqualToString:@"pid"]) return [NSNumber numberWithInt:e.pid];
    if ([ident isEqualToString:@"level"]) return e.level;
    if ([ident isEqualToString:@"message"]) return e.message;
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if ([notification object] == logTable) {
        NSInteger row = [logTable selectedRow];
        NSArray *fe = [self filteredEntries];
        if (row >= 0 && row < (NSInteger)fe.count) {
            LogEntry *e = [fe objectAtIndex:row];
            NSString *text = e.raw.length > 0 ? e.raw : e.message;
            if ([e.source isEqualToString:@"Crash Reports"]) text = e.message;
            [[detailView textStorage] setAttributedString:[[NSAttributedString alloc] initWithString:text]];
        } else {
            [[detailView textStorage] setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
        }
    } else if ([notification object] == sidebarTable) {
        NSInteger row = [sidebarTable selectedRow];
        if (row >= 0) selectedSource = row;
        [self reloadLogTable];
    }
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == logTable && [[tableColumn identifier] isEqualToString:@"level"]) {
        NSArray *fe = [self filteredEntries];
        if (row >= 0 && row < (NSInteger)fe.count) {
            LogEntry *e = [fe objectAtIndex:row];
            NSColor *c = [NSColor textColor];
            if ([e.level isEqualToString:@"Error"]) c = [NSColor yellowColor];
            else if ([e.level isEqualToString:@"Fault"]) c = [NSColor redColor];
            [cell setTextColor:c];
        }
    }
}

- (void)severityChanged:(id)sender {
    selectedSeverity = [[severityPopup selectedItem] title];
    [self reloadLogTable];
}

- (void)searchChanged:(id)sender {
    [self reloadLogTable];
}

- (void)clearDisplay:(id)sender {
    [entries removeAllObjects];
    [self reloadLogTable];
    [[detailView textStorage] setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
}

- (void)nowToggled:(id)sender {
    nowMode = ([(NSButton *)sender state] == NSOnState);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem { return YES; }

- (void)keyDown:(NSEvent *)event {
    // Cmd+F focus search, Cmd+K clear
    if ([event modifierFlags] & NSCommandKeyMask) {
        NSString *ch = [event charactersIgnoringModifiers];
        if ([ch isEqualToString:@"f"]) { [window makeFirstResponder:searchField]; return; }
        if ([ch isEqualToString:@"k"]) { [self clearDisplay:nil]; return; }
    }
}

// NSApplicationDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

- (void)windowWillClose:(NSNotification *)note {
    [collector stop];
    [NSApp terminate:nil];
}

@end