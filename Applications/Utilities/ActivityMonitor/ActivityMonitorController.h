#import <AppKit/AppKit.h>
#import "SystemMetricsCollector.h"
#import "GraphView.h"

@interface ActivityMonitorController : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSScrollView *tableScroll;
@property (strong) NSTableView *table;
@property (strong) NSTextField *searchField;
@property (strong) NSButton *inspectButton;
@property (strong) NSButton *quitButton;
@property (strong) NSSegmentedControl *tabSegment;
@property (strong) GraphView *graphView;
@property (strong) SystemMetricsCollector *collector;
@property (strong) NSTimer *timer;
@property (copy) NSString *sortKey;
@property (assign) BOOL sortAscending;
@property (strong) NSMutableArray *filtered;
@property (assign) int activeTab;
- (void)refresh:(id)sender;
- (void)inspectProcess:(id)sender;
- (void)quitProcess:(id)sender;
@end