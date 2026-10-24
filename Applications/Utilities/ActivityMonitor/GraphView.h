#import <AppKit/AppKit.h>

@interface GraphView : NSView
@property (strong) NSMutableArray *userHistory;
@property (strong) NSMutableArray *systemHistory;
@property (strong) NSMutableArray *memHistory;
@property (strong) NSMutableArray *netHistory;
/* 0 CPU, 1 Memory, 2 Disk, 3 Network. */
@property (assign) int mode;
@property (strong) NSString *summary;
- (void)addSampleUser:(double)u system:(double)s memoryPressure:(double)m;
- (void)addSampleUser:(double)u system:(double)s memoryPressure:(double)m netKBps:(double)net;
@end