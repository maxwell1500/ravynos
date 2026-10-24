#import <AppKit/AppKit.h>
#import "KeychainVault.h"

@interface KeychainController : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) KeychainVault *selectedVault;
@property (strong) NSMutableArray *vaults;
@property (strong) NSTableView *keychainTable;
@property (strong) NSTableView *categoryTable;
@property (strong) NSTableView *itemTable;
@property (strong) NSTextField *searchField;
@property (strong) NSButton *lockButton;
@property (strong) NSButton *showPasswordButton;
@property (strong) NSTextField *detailField;
@property (strong) NSMutableArray *filteredItems;
@property (strong) KeychainItem *selectedItem;
@property (assign) NSInteger selectedCategory; // 0 all,1 password,2 note,3 cert
- (void)refreshItems;
- (void)unlockSelectedVault:(id)sender;
- (void)newItem:(id)sender;
- (void)deleteItem:(id)sender;
- (void)showPassword:(id)sender;
- (void)openGenerator:(id)sender;
@end