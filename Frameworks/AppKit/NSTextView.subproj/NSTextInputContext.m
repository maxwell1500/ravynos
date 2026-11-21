/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSTextInputClient.h"
#import <AppKit/NSEvent.h>
#import <AppKit/NSResponder.h>
#import <Foundation/NSArray.h>

@implementation NSTextInputContext

-initWithClient:(id)client {
   _client=[client retain];
   return self;
}

-(void)dealloc {
   [_client release];
   [super dealloc];
}

-(id)client {
   return _client;
}

-(BOOL)handleEvent:(NSEvent *)event {
   if(event==nil)
    return NO;

   if([event type]!=NSKeyDown)
    return NO;

   /* Route the key event through the binding manager, which delivers the
    * mapped selector or -insertText: to the client. */
   [_client interpretKeyEvents:[NSArray arrayWithObject:event]];

   return YES;
}

@end
