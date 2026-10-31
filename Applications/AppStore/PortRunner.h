/*
 * PortRunner.h - MacPorts background task execution engine with streaming output
 */
#import <Foundation/Foundation.h>

@protocol PortRunnerDelegate <NSObject>
@optional
- (void)portRunnerDidOutputLine:(NSString *)line;
- (void)portRunnerDidUpdateStatus:(NSString *)status progress:(double)progress;
- (void)portRunnerDidFinishWithSuccess:(BOOL)success exitCode:(int)code;
@end

@interface PortRunner : NSObject
@property (nonatomic, assign) id<PortRunnerDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSString *currentPort;

+ (instancetype)sharedRunner;

- (BOOL)installPort:(NSString *)portName;
- (BOOL)uninstallPort:(NSString *)portName;
- (BOOL)syncPorts;
- (void)cancelCurrentOperation;

@end
