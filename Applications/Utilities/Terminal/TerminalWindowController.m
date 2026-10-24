#import "TerminalWindowController.h"

@implementation TerminalWindowController

@synthesize tabView = _tabView;

- (id)init {
    NSRect frame = NSMakeRect(100, 100, 800, 500);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask|NSResizableWindowMask)
                                              backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:w];
    if (self) {
        _tabView = [[NSTabView alloc] initWithFrame:[w.contentView bounds]];
        _tabView.tabViewType = NSTopTabsBezelBorder;
        _tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [w setContentView:_tabView];
        [w setTitle:@"Terminal"];
        [self createTab];
    }
    return self;
}

- (TerminalView *)firstTerminalViewIn:(NSView *)view {
    if ([view isKindOfClass:[TerminalView class]]) return (TerminalView *)view;
    for (NSView *sub in [view subviews]) {
        TerminalView *t = [self firstTerminalViewIn:sub];
        if (t) return t;
    }
    return nil;
}

- (TerminalView *)currentPane {
    NSResponder *r = [[self window] firstResponder];
    if ([r isKindOfClass:[TerminalView class]]) return (TerminalView *)r;
    NSTabViewItem *item = [self.tabView selectedTabViewItem];
    if (item) return [self firstTerminalViewIn:[item view]];
    return nil;
}

- (void)applyThemeToAllPanes:(int)tag {
    for (NSTabViewItem *item in [self.tabView tabViewItems]) {
        // collect all terminal views
        NSMutableArray *stack = [NSMutableArray arrayWithObject:[item view]];
        while ([stack count] > 0) {
            NSView *v = [stack lastObject]; [stack removeLastObject];
            if ([v isKindOfClass:[TerminalView class]]) [(TerminalView *)v setTheme:tag];
            [stack addObjectsFromArray:[v subviews]];
        }
    }
}

- (void)createTab {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0,0,800,500)];
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    TerminalView *tv = [[TerminalView alloc] initWithFrame:container.bounds];
    tv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:tv];
    [tv startShell];

    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:[NSString stringWithFormat:@"tab-%lu", (unsigned long)[[self.tabView tabViewItems] count]]];
    [item setLabel:@"Terminal"];
    [item setView:container];
    [self.tabView addTabViewItem:item];
    [self.tabView selectTabViewItem:item];
    [[self window] makeFirstResponder:tv];
}

- (void)newTab:(id)sender { [self createTab]; }

- (void)closeTab:(id)sender {
    NSTabViewItem *item = [self.tabView selectedTabViewItem];
    if (!item) return;
    // terminate shells
    NSMutableArray *stack = [NSMutableArray arrayWithObject:[item view]];
    while ([stack count] > 0) {
        NSView *v = [stack lastObject]; [stack removeLastObject];
        if ([v isKindOfClass:[TerminalView class]]) [(TerminalView *)v terminateShell];
        [stack addObjectsFromArray:[v subviews]];
    }
    [self.tabView removeTabViewItem:item];
    if ([[self.tabView tabViewItems] count] == 0) {
        [self createTab];
    }
}

- (void)nextTab:(id)sender {
    NSArray *items = [self.tabView tabViewItems];
    if ([items count] == 0) return;
    NSInteger idx = [self.tabView indexOfTabViewItem:[self.tabView selectedTabViewItem]];
    idx = (idx + 1) % [items count];
    [self.tabView selectTabViewItem:[items objectAtIndex:idx]];
}

- (void)previousTab:(id)sender {
    NSArray *items = [self.tabView tabViewItems];
    if ([items count] == 0) return;
    NSInteger idx = [self.tabView indexOfTabViewItem:[self.tabView selectedTabViewItem]];
    idx = (idx - 1 + [items count]) % [items count];
    [self.tabView selectTabViewItem:[items objectAtIndex:idx]];
}

- (void)splitVertical:(id)sender {
    TerminalView *src = [self currentPane];
    if (!src) return;
    NSView *container = [src superview];
    NSSplitView *split = nil;
    if ([container isKindOfClass:[NSSplitView class]]) split = (NSSplitView *)container;
    else {
        split = [[NSSplitView alloc] initWithFrame:container.bounds];
        split.vertical = YES;
        split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [src removeFromSuperview];
        [split addSubview:src];
        [container addSubview:split];
        src.frame = split.bounds;
    }
    TerminalView *nw = [[TerminalView alloc] initWithFrame:src.frame];
    nw.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [nw startShell];
    [split addSubview:nw];
    [split adjustSubviews];
}

- (void)splitHorizontal:(id)sender {
    TerminalView *src = [self currentPane];
    if (!src) return;
    NSView *container = [src superview];
    NSSplitView *split = nil;
    if ([container isKindOfClass:[NSSplitView class]]) split = (NSSplitView *)container;
    else {
        split = [[NSSplitView alloc] initWithFrame:container.bounds];
        split.vertical = NO;
        split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [src removeFromSuperview];
        [split addSubview:src];
        [container addSubview:split];
        src.frame = split.bounds;
    }
    TerminalView *nw = [[TerminalView alloc] initWithFrame:src.frame];
    nw.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [nw startShell];
    [split addSubview:nw];
    [split adjustSubviews];
}

- (void)zoomIn:(id)sender {
    TerminalView *tv = [self currentPane];
    if (tv) [tv setFontSize:tv.fontSize + 1]; // need fontSize property
}

- (void)zoomOut:(id)sender {
    TerminalView *tv = [self currentPane];
    if (tv) [tv setFontSize:tv.fontSize - 1];
}

- (void)zoomReset:(id)sender {
    TerminalView *tv = [self currentPane];
    if (tv) [tv setFontSize:13.0];
}

- (void)setThemeAction:(id)sender {
    int tag = (int)[(NSMenuItem *)sender tag];
    [self applyThemeToAllPanes:tag];
}

- (void)clearAll:(id)sender {
    TerminalView *tv = [self currentPane];
    if (tv) [tv clearScreen];
}

@end
