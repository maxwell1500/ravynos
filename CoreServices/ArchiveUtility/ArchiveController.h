#import <AppKit/AppKit.h>
#import "ArchiveEngine.h"

@interface ArchiveController : NSObject <NSApplicationDelegate>
@property (nonatomic, assign) BOOL compressMode;
@property (nonatomic, strong) NSArray *paths;
@property (nonatomic, strong) NSString *archivePath;
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextField *entryField;
@property (nonatomic, strong) NSProgressIndicator *progress;
@end