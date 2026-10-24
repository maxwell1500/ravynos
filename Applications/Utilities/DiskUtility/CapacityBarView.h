#import <AppKit/AppKit.h>

@interface CapacityBarView : NSView
@property (assign) uint64_t totalBytes;
@property (assign) uint64_t usedBytes;
@end