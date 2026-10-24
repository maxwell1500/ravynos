#import <AppKit/AppKit.h>
@class LogCollector;
@class LogEntry;

@interface ConsoleController : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSScrollView *sidebarScroll;
@property (strong) NSTableView *sidebarTable;
@property (strong) NSScrollView *tableScroll;
@property (strong) NSTableView *logTable;
@property (strong) NSScrollView *detailScroll;
@property (strong) NSTextView *detailView;
@property (strong) NSTextField *searchField;
@property (strong) NSPopUpButton *severityPopup;
@property (strong) LogCollector *collector;
@property (strong) NSMutableArray *entries;
@property (strong) NSArray *sources;
@property (assign) NSInteger selectedSource;
@property (copy) NSString *selectedSeverity;
@property (assign) BOOL nowMode;
- (void)appendEntries:(NSArray *)newEntries;
- (void)reloadLogTable;
@end