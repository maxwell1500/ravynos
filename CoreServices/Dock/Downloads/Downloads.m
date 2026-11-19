/*
 * ravynOS Application Launcher & Status Bar - Downloads.app
 *
 * Copyright (C) 2021-2022 Zoe Knox <zoe@pixin.net>
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

#import "Downloads.h"
#import <Foundation/NSPlatform.h>
#import <CoreFoundation/CoreFoundation.h>
#import <LaunchServices/LaunchServices.h>

@implementation Downloads

-(int)run {
    NSURL *url = [NSURL fileURLWithPath:
        [[[NSPlatform currentPlatform] homeDirectory]
        stringByAppendingPathComponent:@"Downloads"]];
    /* [DLURL] This one-shot app crashed twice via LSOpenFromURLSpec
     * ([LSNIL] itemURLs[0] of 1 is NULL) while the identical chain in the
     * homechain fixture measured healthy in the same boot.  Print each
     * link from inside the failing process until the nil is named. */
    NSArray *urls = [NSArray arrayWithObject:url];
    /* [DLURL] This one-shot app crashed via LSOpenFromURLSpec
     * (nil/'Object' items measured by [LSNIL] and the abort log) while the
     * identical chain in the homechain fixture measured healthy.  Print the
     * addresses so the over-release or storage bug is named exactly. */
    NSLog(@"[DLURL] home=%@ url=%@ at=%p urls=%p",
          [[NSPlatform currentPlatform] homeDirectory], url, url, urls);
    if ([urls count] == 1)
        NSLog(@"[DLURL] urls[0]=%p", [urls objectAtIndex:0]);
    NSURL *app = [NSURL fileURLWithPath:
        @"/System/Library/CoreServices/Filer.app"];

    LSLaunchURLSpec spec = { 0 };
    spec.appURL = (__bridge_retained CFURLRef)app;
    spec.itemURLs = (__bridge_retained CFArrayRef)urls;
    LSOpenFromURLSpec(&spec, NULL);
    return 0;
}

@end
