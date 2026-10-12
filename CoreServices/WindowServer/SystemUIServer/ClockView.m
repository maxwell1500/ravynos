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

#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
#include <locale.h>
#import <AppKit/AppKit.h>
#import "desktop.h"

const NSString *PrefsDateFormatStringKey = @"DateFormatString";
const NSString *defaultFormatEN = @"%a %b %d  %I:%M %p";
pthread_mutex_t mtx;

@interface NSApplication(SystemUIServer)
-(int)_wakeUp;
@end

@implementation ClockView

- initWithFrame:(NSRect)frame {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    dateFormat = [prefs stringForKey:PrefsDateFormatStringKey];
    if(dateFormat == nil || [dateFormat length] == 0) {
        NSString *locale = [[NSLocale currentLocale] localeIdentifier];
        if([locale hasPrefix:@"en"])
            dateFormat = defaultFormatEN;
        else if([locale hasPrefix:@"C"])
            dateFormat = @"%Y-%m-%d %R";
        else
            dateFormat = [prefs objectForKey:NSTimeDateFormatString];
    }
    if(dateFormat == nil)
        dateFormat = defaultFormatEN;

    dateFormatter = [[NSDateFormatter alloc] initWithDateFormat:dateFormat
                                        allowNaturalLanguage:YES
                                        locale:[NSLocale currentLocale]];

    /* -[NSFont systemFontOfSize:] resolves through CoreText's
     * CTFontCreateUIFontForLanguage, which KTFont cannot implement in this
     * tree (no concrete subclass), so it returns NULL and AppKit falls back
     * to resolving a real face through O2Font.  Layout only needs the size,
     * so keep the font request and measure the attributed string; if no face
     * comes back, the fixed-width fallback below keeps the clock laid out. */
    NSFont *font = [NSFont systemFontOfSize:15];
    if(font != nil)
        attributes = [NSDictionary dictionaryWithObjects:@[font, [NSColor blackColor]]
                                            forKeys:@[NSFontAttributeName,
                                                      NSForegroundColorAttributeName]];
    else
        attributes = [NSDictionary dictionaryWithObjects:@[[NSColor blackColor]]
                                            forKeys:@[NSForegroundColorAttributeName]];

    dateString = [[NSAttributedString alloc] initWithString:[self currentDateValue]
                                               attributes:attributes];

    NSSize sz = [dateString size];
    if(sz.width <= 0)
        sz.width = 96;
    sz.width += menuBarHPad;

    self = [super initWithFrame:NSMakeRect(frame.size.width - sz.width,
            menuBarVPad, sz.width + menuBarHPad, sz.height)];

    pthread_mutex_init(&mtx, NULL);
    [NSThread detachNewThreadSelector:@selector(notifyTick:)
                             toTarget:self
                           withObject:nil];
    return self;
}

- (NSString *)currentDateValue {
    return [dateFormatter stringForObjectValue:[NSDate date]];
}

- (void)notifyTick:(id)arg {
    static NSString *_dateValue = NULL;
    while(YES) {        if([_dateValue isEqualToString:[self currentDateValue]] == NO) {
            _dateValue = [self currentDateValue];
            [self setNeedsDisplay:YES];
            [NSApp _wakeUp];
        }
        sleep(1);
    }
}

-(void)drawRect:(NSRect)rect {
    [super drawRect:rect];
    dateString = [[NSAttributedString alloc] initWithString:[self currentDateValue] attributes:attributes];
    [dateString drawInRect:rect];
}

- (NSSize)size {
    return _frame.size;
}

- (BOOL)refusesFirstResponder {
	return YES;
}

@end

