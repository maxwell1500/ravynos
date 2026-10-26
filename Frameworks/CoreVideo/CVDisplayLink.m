/* Only the pieces this file uses.  Importing <Foundation/Foundation.h> pulls
 * in CoreServices, which pulls in CFNetwork, whose headers need
 * ConditionalMacros.h in scope -- a much wider dependency than a display-link
 * timer justifies. */
#import <Foundation/NSObject.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSAutoreleasePool.h>
#import "Headers/CoreVideo.h"
#import <mach/mach_time.h>
#import <string.h>

// FIXME: use only one timer for all the display links, this will reduce run loop overhead

@interface CVDisplayLink : NSObject {
    NSTimer *_timer;
    CVDisplayLinkOutputCallback _callback;
    void  *_userInfo;
}

@end

@implementation CVDisplayLink

-init {
    return self;
}

-(void)dealloc {
    [_timer invalidate];
    [_timer release];
    [super dealloc];
}

-(void)displayLinkTimer:(NSTimer *)timer {
    if(_callback!=NULL)
        _callback(self,NULL,NULL,0,NULL,_userInfo);
}

-(void)start {
    _timer=[[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(displayLinkTimer:) userInfo:nil repeats:YES] retain];
}

-(void)stop {
    [_timer invalidate];
    [_timer release];
    _timer = nil;
}

CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *result) {
    if (result == NULL) return kCVReturnInvalidArgument;
    *result=(CVDisplayLinkRef)[[CVDisplayLink alloc] init];
    return (*result != NULL) ? kCVReturnSuccess : kCVReturnAllocationFailed;
}

CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID displayID, CVDisplayLinkRef *result) {
    (void)displayID;
    return CVDisplayLinkCreateWithActiveCGDisplays(result);
}

CVReturn CVDisplayLinkCreateWithCGDisplays(CGDirectDisplayID *displayArray, CFIndex count,
                                          CVDisplayLinkRef *result) {
    (void)displayArray;
    (void)count;
    return CVDisplayLinkCreateWithActiveCGDisplays(result);
}

CVReturn CVDisplayLinkCreateWithOpenGLDisplayMask(uint32_t displayMask, CVDisplayLinkRef *result) {
    (void)displayMask;
    return CVDisplayLinkCreateWithActiveCGDisplays(result);
}

CVReturn CVDisplayLinkSetCurrentCGDisplay(CVDisplayLinkRef self, CGDirectDisplayID displayID) {
    (void)self;
    (void)displayID;
    return kCVReturnSuccess;
}

CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay(CVDisplayLinkRef self) {
    (void)self;
    return CGMainDisplayID();
}

CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef self) {
    (void)self;
    CVTime result = { 1, 60, 0 };
    return result;
}

CVTime CVDisplayLinkGetOutputVideoLatency(CVDisplayLinkRef self) {
    (void)self;
    CVTime result = { 0, 1, 0 };
    return result;
}

double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef self) {
    (void)self;
    return 1.0 / 60.0;
}

CVReturn CVDisplayLinkGetCurrentTime(CVDisplayLinkRef self, CVTimeStamp *outTime) {
    (void)self;
    if (outTime == NULL) return kCVReturnInvalidArgument;
    memset(outTime, 0, sizeof(*outTime));
    outTime->version = 0;
    outTime->videoTimeScale = 600;
    outTime->videoTime = (int64_t)([NSDate timeIntervalSinceReferenceDate] * 600.0);
    outTime->hostTime = mach_absolute_time();
    outTime->rateScalar = 1.0;
    outTime->videoRefreshPeriod = 10;   /* 600 / 60 */
    return kCVReturnSuccess;
}

CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef self,CVDisplayLinkOutputCallback callback,void *userInfo) {
    self->_callback=callback;
    self->_userInfo=userInfo;
    return kCVReturnSuccess;
}

CVReturn CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(CVDisplayLinkRef self,void *cglContext,void *cglPixelFormat) {
    return kCVReturnSuccess;
}

CVReturn CVDisplayLinkStart(CVDisplayLinkRef self) {
    if (CVDisplayLinkIsRunning(self))
        return kCVReturnDisplayLinkAlreadyRunning;
    [self start];
    return kCVReturnSuccess;
}

CVReturn CVDisplayLinkStop(CVDisplayLinkRef self) {
    if (!CVDisplayLinkIsRunning(self))
        return kCVReturnDisplayLinkNotRunning;
    [self stop];
    return kCVReturnSuccess;
}

Boolean CVDisplayLinkIsRunning (CVDisplayLinkRef self) {
    return (self->_timer != nil);
}

CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef self) {
    return (CVDisplayLinkRef)[self retain];
}

void CVDisplayLinkRelease(CVDisplayLinkRef self) {
    [self release];
}

@end
