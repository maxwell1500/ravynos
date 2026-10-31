/*
 * AppStoreWindowController.h - Main window controller for ravynOS App Store
 */
#import <AppKit/AppKit.h>
#import "AppCatalog.h"
#import "PortRunner.h"

@interface AppStoreWindowController : NSWindowController <PortRunnerDelegate> {
@public
    NSSplitView *_mainSplitView;
    NSTableView *_sidebarTable;
    NSTableView *_appsTable;
    NSSearchField *_searchField;
    NSTextField *_categoryTitleLabel;

    /* Terminal Drawer */
    NSView *_bottomContainer;
    NSProgressIndicator *_progressBar;
    NSTextField *_statusLabel;
    NSButton *_disclosureButton;
    NSScrollView *_terminalScrollView;
    NSTextView *_terminalTextView;
    BOOL _sawIndexError;
    BOOL _isTerminalExpanded;
    id _terminalHeightConstraint;

    /* Data */
    NSArray *_categories;
    NSString *_selectedCategory;
    NSArray *_displayedApps;
    NSString *_searchQuery;
}

- (instancetype)init;

@end
