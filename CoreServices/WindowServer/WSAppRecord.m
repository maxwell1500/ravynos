/*
 * Copyright (C) 2022-2024 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <Foundation/NSMutableArray.h>
#import <Foundation/NSString.h>
#import <pthread.h>
#import "common.h"
#import "WindowServer.h"


extern pthread_mutex_t renderLock;

@implementation WSAppRecord
-init {
    _windows = [NSMutableArray new];
    _mouseCursorConnected = YES;
    _skipSwitcher = NO;
    return self;
}

/* The RPC thread mutates _windows while the render thread walks it.  Every
 * access that is not already documented as render-thread-only takes the
 * server's renderLock: a torn NSMutableArray read is a use-after-free. */
-(void)addWindow:(WSWindowRecord *)window {
    pthread_mutex_lock(&renderLock);
    [_windows addObject:window];
    pthread_mutex_unlock(&renderLock);
}

-(WSWindowRecord *)removeWindowWithID:(int)number {
    WSWindowRecord *found = nil;

    pthread_mutex_lock(&renderLock);
    for(int i = 0; i < [_windows count]; i++) {
        WSWindowRecord *r = [_windows objectAtIndex:i];
        if(r.number == number) {
            found = r;
            [_windows removeObjectAtIndex:i];
            break;
        }
    }
    pthread_mutex_unlock(&renderLock);
    return found;
}

-(WSWindowRecord *)windowWithID:(int)number {
    WSWindowRecord *found = nil;

    pthread_mutex_lock(&renderLock);
    for(int i = 0; i < [_windows count]; i++) {
        WSWindowRecord *r = [_windows objectAtIndex:i];
        if(r.number == number) {
            found = r;
            break;
        }
    }
    pthread_mutex_unlock(&renderLock);
    return found;
}

/* A copy, taken under renderLock: callers walk the result after unlocking,
 * and the RPC thread may mutate the live array underneath them. */
-(NSArray *)windows {
    pthread_mutex_lock(&renderLock);
    NSArray *copy = [_windows copy];
    pthread_mutex_unlock(&renderLock);
    return copy;
}

-(void)removeAllWindows {
    pthread_mutex_lock(&renderLock);
    [_windows removeAllObjects]; // should release them all
    pthread_mutex_unlock(&renderLock);
}

-(void)mouseCursorConnected:(int)connected {
    _mouseCursorConnected = connected;
}

-(BOOL)mouseCursorConnected {
    return _mouseCursorConnected;
}

-(BOOL)skipSwitcher {
    return _skipSwitcher;
}

-(void)skipSwitcher:(BOOL)value {
    _skipSwitcher = value;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"<%@ 0x%x> %@ pid:%u port:%u windows:%u",
           [self class], (uint32_t)self, self.bundleID, self.pid, self.port,
           [[self windows] count]];
}

@end

