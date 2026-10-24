#import <AppKit/AppKit.h>
#import "FontPreviewView.h"

@interface FontBookController : NSObject
@property (retain) NSWindow *window;
@property (retain) NSOutlineView *familyOutline;
@property (retain) NSTableView *sidebarTable;
@property (retain) FontPreviewView *previewView;
@property (retain) NSSegmentedControl *modeSegment;
@property (retain) NSTextField *searchField;
@property (retain) NSArray *allFonts;
@property (retain) NSArray *sidebarItems;
@property (retain) NSString *currentSidebar;
@property (retain) NSDictionary *selectedFont;

- (void)showWindow;
- (void)reloadFonts;
@end