/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSDistributedNotificationCenter.h>
#import <Foundation/NSRaise.h>

NSString * const NSLocalNotificationCenterType=@"NSLocalNotificationCenterType";

@implementation NSDistributedNotificationCenter

+(NSDistributedNotificationCenter *)defaultCenter {
   return [self notificationCenterForType:NSLocalNotificationCenterType];
}

/* One center per notification-domain name, remembered for the life of the
 * process: an observer registered through a center has to stay reachable
 * until something posts that notification, so the same object is handed
 * back to every asker. */
+(NSDistributedNotificationCenter *)notificationCenterForType:(NSString *)type {
   static NSMutableDictionary *centers=nil;
   NSDistributedNotificationCenter *center;

   if(type==nil)
      type=NSLocalNotificationCenterType;

   @synchronized(self)
   {
      if(centers==nil)
	 centers=[[NSMutableDictionary allocWithZone:[self zone]] init];

      center=[centers objectForKey:type];
      if(center==nil)
      {
	 center=[[self alloc] init];
	 [centers setObject:center forKey:type];
      }
   }
   return center;
}

-(BOOL)suspended {
   return _suspended;
}

-(void)setSuspended:(BOOL)value {
   _suspended=value;
}

-(void)addObserver:observer selector:(SEL)selector name:(NSString *)name
   object:(NSString *)object suspensionBehavior:(NSNotificationSuspensionBehavior)behavior {
   /* Our notification machinery reaches observers when a notification is
    * posted, and has no per-observer policy about being held back while the
    * center is suspended, so this is the one registration. */
   [super addObserver:observer selector:selector name:name object:object];
}

/* -addObserver:observer selector:name:object:, -removeObserver:... and
 * -postNotificationName:... come from NSNotificationCenter, which keeps a
 * name -> observer registry and hands a posted notification to whatever
 * observers registered for that name. That is the delivery these centers
 * need, so they are inherited rather than restated here. */

@end
