#import <Foundation/Foundation.h>

@class ConsoleController;

@interface LogEntry : NSObject
@property (copy) NSString *timestamp;
@property (copy) NSString *process;
@property (assign) int pid;
@property (copy) NSString *level;
@property (copy) NSString *message;
@property (copy) NSString *raw;
@property (copy) NSString *source;
@end
@interface LogCollector : NSObject
@property (assign) ConsoleController *controller;
- (id)initWithController:(ConsoleController *)controller;
- (void)start;
- (void)stop;
@end