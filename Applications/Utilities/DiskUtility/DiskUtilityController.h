#import <AppKit/AppKit.h>
#import "DiskBackend.h"
#import "CapacityBarView.h"

 @interface DiskUtilityController : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTableView *sidebarTable;
@property (strong) NSScrollView *sidebarScroll;
@property (strong) NSView *inspectorView;
@property (strong) NSTextField *deviceNameField;
@property (strong) NSButton *mountPointButton;
@property (strong) NSTextField *fsTypeField;
@property (strong) NSTextField *totalField;
@property (strong) NSTextField *usedField;
@property (strong) NSTextField *availField;
@property (strong) NSTextField *statusField;
@property (strong) CapacityBarView *capacityBar;
@property (strong) DiskItem *selectedItem;
@property (strong) NSMutableArray *sidebarRows; // array of DiskItem or NSString section headers
@property (strong) NSMutableArray *sectionMarkers; // indices
@property (assign) NSTimer *pollTimer;
- (void)refresh;
- (void)openMountPoint:(id)sender;
- (void)firstAid:(id)sender;
- (void)mountVolume:(id)sender;
- (void)unmountVolume:(id)sender;
- (void)ejectVolume:(id)sender;
- (void)eraseVolume:(id)sender;
- (void)newDiskImage:(id)sender;
@end