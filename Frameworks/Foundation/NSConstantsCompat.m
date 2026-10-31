/*
 * NSConstantsCompat -- constants a stock application links at load time.
 *
 * These are non-lazy data references: dyld refuses to load the application
 * when any of them is absent ("Symbol not found: <name>"), so they must
 * exist as real NSString objects even where the feature behind them is not
 * implemented. Each value is the documented string for the constant; the
 * name is what applications compare against, and a dictionary key only has
 * to be a stable non-NULL string.
 */
#import <Foundation/Foundation.h>

NSString * const NSFileGroupOwnerAccountID = @"NSFileGroupOwnerAccountID";
NSString * const NSUserActivityTypeBrowsingWeb = @"NSUserActivityTypeBrowsingWeb";
NSString * const NSUserNotificationDefaultSoundName = @"NSUserNotificationDefaultSoundName";
