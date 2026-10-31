/*
 * LocalAuthentication -- the part a stock application actually links.
 *
 * Firefox's XUL records _OBJC_CLASS_$_LAContext at load time, so the class
 * must exist as a real Objective-C class in this framework or dyld refuses to
 * load the application:
 *
 *   Symbol not found: _OBJC_CLASS_$_LAContext
 *
 * ravynOS has no biometric sensor and no Touch ID daemon, so every policy
 * evaluation answers "not available" with LAErrorNotInteractive. That is a
 * truthful answer, not a stub that reports success: an application that asks
 * for Touch ID is told there is none.
 */
#import <Foundation/Foundation.h>

NSString * const LAErrorDomain = @"com.apple.LocalAuthentication.LAErrorDomain";

enum {
    LAErrorAuthenticationFailed = -1,
    LAErrorUserCancel = -2,
    LAErrorUserFallback = -3,
    LAErrorSystemCancel = -4,
    LAErrorPasscodeNotSet = -5,
    LAErrorTouchIDNotAvailable = -6,
    LAErrorTouchIDNotEnrolled = -7,
    LAErrorNotInteractive = -1004
};

@implementation LAContext

- (BOOL)canEvaluatePolicy:(NSInteger)policy error:(NSError **)error
{
    (void)policy;
    if (error != NULL) {
        *error = [NSError errorWithDomain:LAErrorDomain
                                     code:LAErrorTouchIDNotAvailable
                                 userInfo:nil];
    }
    return NO;
}

- (void)evaluatePolicy:(NSInteger)policy
     localizedReason:(NSString *)reason
               reply:(void (^)(BOOL success, NSError *error))reply
{
    (void)policy;
    (void)reason;
    if (reply != NULL) {
        reply(NO, [NSError errorWithDomain:LAErrorDomain
                                      code:LAErrorTouchIDNotAvailable
                                  userInfo:nil]);
    }
}

- (void)invalidate
{
}

@end
