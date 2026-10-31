/*
 * AppStoreWindowController.m - Main window controller for ravynOS App Store
 */
#import "AppStoreWindowController.h"


@implementation AppStoreWindowController

- (instancetype)init {
    self = [super init];
    if (self) {
        _categories = [[AppCatalog sharedCatalog] categories];
        _selectedCategory = [_categories firstObject];
        _displayedApps = @[];
        _isTerminalExpanded = NO;
        [PortRunner sharedRunner].delegate = self;
        [self _createWindow];
        [self _reloadApps];
    }
    return self;
}

- (void)_createWindow {
    NSRect frame = NSMakeRect(120, 100, 960, 680);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask |
                       NSMiniaturizableWindowMask | NSResizableWindowMask;
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"App Store"];
    [_window setMinSize:NSMakeSize(800, 500)];
    [self setWindow:_window];

    NSView *contentView = [_window contentView];
    NSRect bounds = [contentView bounds];

    /* Main horizontal split view */
    _mainSplitView = [[NSSplitView alloc] initWithFrame:bounds];
    [_mainSplitView setVertical:YES];
    [_mainSplitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [contentView addSubview:_mainSplitView];

    /* Left Sidebar */
    NSView *sidebarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, bounds.size.height)];
    NSScrollView *sidebarScroll = [[NSScrollView alloc] initWithFrame:[sidebarView bounds]];
    [sidebarScroll setHasVerticalScroller:YES];
    [sidebarScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _sidebarTable = [[NSTableView alloc] initWithFrame:[sidebarScroll bounds]];
    NSTableColumn *sideCol = [[NSTableColumn alloc] initWithIdentifier:@"CategoryCol"];
    [sideCol setWidth:200];
    [_sidebarTable addTableColumn:sideCol];
    [_sidebarTable setHeaderView:nil];
    [_sidebarTable setDataSource:self];
    [_sidebarTable setDelegate:self];
    [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [sidebarScroll setDocumentView:_sidebarTable];
    [sidebarView addSubview:sidebarScroll];
    [_mainSplitView addSubview:sidebarView];

    /* Right Content Area */
    CGFloat rightW = bounds.size.width - 220;
    NSView *rightContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, rightW, bounds.size.height)];
    [rightContainer setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_mainSplitView addSubview:rightContainer];

    /* Header Bar */
    NSRect headerRect = NSMakeRect(16, bounds.size.height - 54, rightW - 32, 44);
    NSView *headerView = [[NSView alloc] initWithFrame:headerRect];
    [headerView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    _categoryTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 8, 300, 28)];
    [_categoryTitleLabel setStringValue:_selectedCategory];
    [_categoryTitleLabel setFont:[NSFont boldSystemFontOfSize:18]];
    [_categoryTitleLabel setBezeled:NO];
    [_categoryTitleLabel setDrawsBackground:NO];
    [_categoryTitleLabel setEditable:NO];
    [headerView addSubview:_categoryTitleLabel];

    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(rightW - 32 - 240, 8, 240, 24)];
    [_searchField setPlaceholderString:@"Search Software..."];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(_searchChanged:)];
    [_searchField setAutoresizingMask:NSViewMinXMargin];
    [headerView addSubview:_searchField];
    [rightContainer addSubview:headerView];

    /* Apps Table (Center Area) */
    NSRect tableRect = NSMakeRect(16, 80, rightW - 32, bounds.size.height - 144);
    NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:tableRect];
    [tableScroll setHasVerticalScroller:YES];
    [tableScroll setVerticalLineScroll:28];
    [tableScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _appsTable = [[NSTableView alloc] initWithFrame:[tableScroll bounds]];
    NSTableColumn *appCol = [[NSTableColumn alloc] initWithIdentifier:@"AppCol"];
    [appCol setWidth:tableRect.size.width - 20];
    [_appsTable addTableColumn:appCol];
    [_appsTable setHeaderView:nil];
    [_appsTable setRowHeight:28];
    [_appsTable setDataSource:self];
    [_appsTable setDelegate:self];
    [_appsTable setTarget:self];
    [_appsTable setDoubleAction:@selector(_installClicked:)];
    [tableScroll setDocumentView:_appsTable];
    [rightContainer addSubview:tableScroll];

    /* Bottom Status & Terminal Drawer (Synaptic-Style) */
    NSRect bottomRect = NSMakeRect(0, 0, rightW, 76);
    _bottomContainer = [[NSView alloc] initWithFrame:bottomRect];
    [_bottomContainer setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [rightContainer addSubview:_bottomContainer];

    /* Progress bar */
    _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(16, 48, rightW - 200, 16)];
    [_progressBar setIndeterminate:NO];
    [_progressBar setMinValue:0.0];
    [_progressBar setMaxValue:1.0];
    [_progressBar setDoubleValue:0.0];
    [_progressBar setAutoresizingMask:NSViewWidthSizable];
    [_bottomContainer addSubview:_progressBar];

    /* Disclosure Button for Terminal */
    _disclosureButton = [[NSButton alloc] initWithFrame:NSMakeRect(rightW - 170, 42, 154, 26)];
    [_disclosureButton setTitle:@"Show Terminal ▸"];
    [_disclosureButton setButtonType:NSMomentaryPushInButton];
    [_disclosureButton setBezelStyle:NSRoundedBezelStyle];
    [_disclosureButton setTarget:self];
    [_disclosureButton setAction:@selector(_toggleTerminal:)];
    [_disclosureButton setAutoresizingMask:NSViewMinXMargin];
    [_bottomContainer addSubview:_disclosureButton];

    /* Status Label */
    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 18, rightW - 32, 22)];
    [_statusLabel setStringValue:@"Ready. Browse or search applications above."];
    [_statusLabel setFont:[NSFont systemFontOfSize:12]];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setAutoresizingMask:NSViewWidthSizable];
    [_bottomContainer addSubview:_statusLabel];

    /* Collapsible Terminal Scroll & Text View */
    NSRect termRect = NSMakeRect(16, 76, rightW - 32, 0);
    _terminalScrollView = [[NSScrollView alloc] initWithFrame:termRect];
    [_terminalScrollView setHasVerticalScroller:YES];
    [_terminalScrollView setHasHorizontalScroller:NO];
    [_terminalScrollView setAutoresizingMask:NSViewWidthSizable];
    [_terminalScrollView setHidden:YES];

    _terminalTextView = [[NSTextView alloc] initWithFrame:[_terminalScrollView bounds]];
    [_terminalTextView setEditable:NO];
    [_terminalTextView setBackgroundColor:[NSColor colorWithCalibratedRed:0.08 green:0.09 blue:0.10 alpha:1.0]];
    [_terminalTextView setTextColor:[NSColor colorWithCalibratedRed:0.29 green:0.96 blue:0.15 alpha:1.0]];
    [_terminalTextView setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_terminalTextView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_terminalScrollView setDocumentView:_terminalTextView];
    [rightContainer addSubview:_terminalScrollView];

    [_window makeKeyAndOrderFront:nil];
}

- (void)_reloadApps {
    _displayedApps = [[AppCatalog sharedCatalog] appsForCategory:_selectedCategory searchQuery:_searchQuery];
    [_appsTable reloadData];
}

- (void)_searchChanged:(id)sender {
    _searchQuery = [_searchField stringValue];
    [self _reloadApps];
}

- (void)_toggleTerminal:(id)sender {
    _isTerminalExpanded = !_isTerminalExpanded;
    NSRect rFrame = [_window.contentView bounds];
    CGFloat rightW = rFrame.size.width - 220;

    if (_isTerminalExpanded) {
        [_disclosureButton setTitle:@"Hide Terminal ▾"];
        [_terminalScrollView setHidden:NO];
        [_terminalScrollView setFrame:NSMakeRect(16, 76, rightW - 32, 160)];
        /* Shrink apps table */
        NSRect tFrame = [_appsTable.enclosingScrollView frame];
        tFrame.origin.y = 244;
        tFrame.size.height = rFrame.size.height - 244 - 60;
        [_appsTable.enclosingScrollView setFrame:tFrame];
    } else {
        [_disclosureButton setTitle:@"Show Terminal ▸"];
        [_terminalScrollView setHidden:YES];
        [_terminalScrollView setFrame:NSMakeRect(16, 76, rightW - 32, 0)];
        /* Expand apps table */
        NSRect tFrame = [_appsTable.enclosingScrollView frame];
        tFrame.origin.y = 80;
        tFrame.size.height = rFrame.size.height - 80 - 60;
        [_appsTable.enclosingScrollView setFrame:tFrame];
    }
}

/* --- TableView DataSource & Delegate --- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _sidebarTable) {
        return [_categories count];
    } else if (tableView == _appsTable) {
        return [_displayedApps count];
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (tableView == _sidebarTable) {
        return (row >= 0 && row < (NSInteger)[_categories count]) ? _categories[row] : @"";
    } else if (tableView == _appsTable) {
        if (row < 0 || row >= (NSInteger)[_displayedApps count]) return @"";
        AppItem *item = _displayedApps[row];
        NSString *badge = item.isInstalled ? @"[Installed]" : @"[Double-click to Install]";
        return [NSString stringWithFormat:@"%@ (%@)  %@  —  %@",
                item.displayName, item.version, badge, item.summary ? item.summary : @""];
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if ([notification object] == _sidebarTable) {
        NSInteger row = [_sidebarTable selectedRow];
        if (row >= 0 && row < (NSInteger)[_categories count]) {
            _selectedCategory = _categories[row];
            [_categoryTitleLabel setStringValue:_selectedCategory];
            [self _reloadApps];
        }
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == _appsTable) {
        if (row < 0 || row >= (NSInteger)[_displayedApps count]) return nil;
        AppItem *item = _displayedApps[row];

        NSRect cellRect = NSMakeRect(0, 0, [tableColumn width], 64);
        NSView *cell = [[NSView alloc] initWithFrame:cellRect];

        /* Emoji Icon */
        NSTextField *iconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 12, 40, 40)];
        [iconLabel setStringValue:item.iconGlyph ? item.iconGlyph : @"📦"];
        [iconLabel setFont:[NSFont systemFontOfSize:28]];
        [iconLabel setBezeled:NO];
        [iconLabel setDrawsBackground:NO];
        [iconLabel setEditable:NO];
        [cell addSubview:iconLabel];

        /* App Title */
        NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(56, 36, 400, 20)];
        [titleLabel setStringValue:[NSString stringWithFormat:@"%@ (%@)", item.displayName, item.version]];
        [titleLabel setFont:[NSFont boldSystemFontOfSize:14]];
        [titleLabel setBezeled:NO];
        [titleLabel setDrawsBackground:NO];
        [titleLabel setEditable:NO];
        [cell addSubview:titleLabel];

        /* Summary */
        NSTextField *summaryLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(56, 12, cellRect.size.width - 180, 22)];
        [summaryLabel setStringValue:item.summary ? item.summary : @""];
        [summaryLabel setFont:[NSFont systemFontOfSize:11]];
        [summaryLabel setTextColor:[NSColor grayColor]];
        [summaryLabel setBezeled:NO];
        [summaryLabel setDrawsBackground:NO];
        [summaryLabel setEditable:NO];
        [cell addSubview:summaryLabel];

        /* Action Button */
        NSButton *actionBtn = [[NSButton alloc] initWithFrame:NSMakeRect(cellRect.size.width - 110, 18, 96, 28)];
        [actionBtn setBezelStyle:NSRoundedBezelStyle];
        [actionBtn setTag:row];
        [actionBtn setTarget:self];

        if (item.isInstalled) {
            [actionBtn setTitle:@"Installed"];
            [actionBtn setEnabled:NO];
        } else {
            [actionBtn setTitle:@"Install"];
            [actionBtn setEnabled:![PortRunner sharedRunner].isRunning];
            [actionBtn setAction:@selector(_installClicked:)];
        }
        [cell addSubview:actionBtn];

        return cell;
    }
    return nil;
}

- (void)_installClicked:(id)sender {
    NSInteger row = [sender isKindOfClass:[NSButton class]] ? [(NSButton *)sender tag] : [_appsTable selectedRow];
    if (row < 0 || row >= (NSInteger)[_displayedApps count]) return;
    AppItem *item = _displayedApps[row];

    /* Auto-expand terminal so user can monitor progress */
    if (!_isTerminalExpanded) {
        [self _toggleTerminal:nil];
    }

    NSString *msg = [NSString stringWithFormat:@"Installing %@ (@%@)...", item.displayName, item.portName];
    [_statusLabel setStringValue:msg];
    [_progressBar setDoubleValue:0.05];

    [[PortRunner sharedRunner] installPort:item.portName];
    [_appsTable reloadData];
}

/* --- PortRunnerDelegate --- */

- (void)portRunnerDidOutputLine:(NSString *)line {
    /* macports cannot resolve anything without a synced index, and the image has
     * no network yet; say that instead of a bare exit code. */
    if([line rangeOfString:@"No index(es) found"].location != NSNotFound ||
       [line rangeOfString:@"not found"].location != NSNotFound)
        _sawIndexError = YES;
    NSAttributedString *attrLine = [[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                                   attributes:@{
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.29 green:0.96 blue:0.15 alpha:1.0],
        NSFontAttributeName: [NSFont userFixedPitchFontOfSize:11]
    }];
    [[_terminalTextView textStorage] appendAttributedString:attrLine];
    [_terminalTextView scrollRangeToVisible:NSMakeRange([[_terminalTextView string] length], 0)];
}

- (void)portRunnerDidUpdateStatus:(NSString *)status progress:(double)progress {
    [_statusLabel setStringValue:status];
    [_progressBar setDoubleValue:progress];
}

- (void)portRunnerDidFinishWithSuccess:(BOOL)success exitCode:(int)code {
    if (success) {
        [_statusLabel setStringValue:@"Installation finished successfully."];
        [_progressBar setDoubleValue:1.0];
    } else if(_sawIndexError) {
        [_statusLabel setStringValue:
            @"No package index: this image has no network or NIC driver yet, so macports "
            @"cannot fetch or build any port."];
    } else {
        [_statusLabel setStringValue:[NSString stringWithFormat:@"Installation failed with exit code %d.", code]];
    }
    _sawIndexError = NO;
    [[AppCatalog sharedCatalog] refreshInstalledStatus];
    [self _reloadApps];
}

@end
