/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>
   Copyright (C) 2022-2024 Zoe Knox <zoe@ravynsoft.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. */

#import <AppKit/NSDisplay.h>
#import "WindowServer/rpc.h"

extern kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSDraggingManager.h>
#include <unistd.h>
#include <stdio.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSColorList.h>
#import <AppKit/NSFontTypeface.h>
#import <Onyx2D/O2Font.h>
#import <AppKit/O2Font_FT.h>
#import <fontconfig.h>
#import <poll.h>

#define MENU_BAR_HEIGHT 24  // exclude from visibleFrame height
#define DOCK_HEIGHT 60      // reserve the Dock strip at the bottom of visibleFrame

@implementation NSDisplay

+(void)initialize {
   /* ravynOS: skip NSUserDefaults registration -- the modifier mapping is
    * not required for WindowServer to paint the LoadingWindow, and the
    * NSUserDefaults init chain (NSProcessInfo, NSPlatform, NSLocale,
    * NSPersistantDomain, NSPropertyListReader) is too slow on TCG and
    * currently blocks the client thread.  Re-enable once the
    * Foundation file-IO path is fast enough. */
}

+(NSDisplay *)currentDisplay {
   return NSThreadSharedInstance(@"NSDisplay");
}

-init {
   /* ravynOS: skip CG RPC calls in -init.  CGMainDisplayID(),
    * CGGetActiveDisplayList(), CGDisplayCopyDisplayMode(), and
    * CGDisplayCopyColorSpace() are all blocking Mach IPC calls to the
    * WindowServer, and the WindowServer is busy in its render loop and
    * does not respond in time.  Use hardcoded values matching the
    * QEMU fb0 framebuffer (1920x1080x32).  The display list is
    * populated from the WindowServer's side anyway. */
   _eventQueue=[NSMutableArray new];
   _screens = [NSMutableArray new];

   NSRect frame = NSMakeRect(0, 0, 1920, 1080);
   NSRect visFrame = frame;
   visFrame.size.height -= MENU_BAR_HEIGHT;
   visFrame.origin.y += DOCK_HEIGHT;
   visFrame.size.height -= DOCK_HEIGHT;
   NSScreen *screen = [[[NSScreen alloc] initWithFrame:frame visibleFrame:visFrame] retain];
   [_screens addObject:screen];

   _depth = 32;
   return self;
}

-(NSArray *)screens {
    return [NSArray arrayWithArray:_screens];
}

-(BOOL)isReady {
    if([_screens count] == 0) {
        write(2, "[AppKit] NSDisplay isReady: querying CGMainDisplayID...\n", 56);
        CGDirectDisplayID mainDisplay = CGMainDisplayID();
        char buf[64];
        int n = snprintf(buf, sizeof(buf), "[AppKit] NSDisplay isReady: mainDisplay=0x%x\n", mainDisplay);
        write(2, buf, n);
        if(mainDisplay != kCGNullDirectDisplay) {
            CGDisplayModeRef mode = CGDisplayCopyDisplayMode(mainDisplay);
            if(mode) {
                CGColorSpaceRef cs = CGDisplayCopyColorSpace(mainDisplay);
                NSRect frame = NSMakeRect(0, 0, CGDisplayModeGetWidth(mode), CGDisplayModeGetHeight(mode));
                NSRect visFrame = frame;
                visFrame.size.height -= MENU_BAR_HEIGHT;
                visFrame.origin.y += DOCK_HEIGHT;
                visFrame.size.height -= DOCK_HEIGHT;
                NSScreen *screen = [[[NSScreen alloc] initWithFrame:frame visibleFrame:visFrame] retain];
                [screen _propertiesFromMode:mode colorSpace:cs displayID:mainDisplay];
                CGDisplayModeRelease(mode);
                [_screens addObject:screen];
                write(2, "[AppKit] NSDisplay isReady: added screen to _screens\n", 53);
            }
        }
    }
    return [_screens count] > 0;
}

-(uint32_t)depth { return _depth; }

-(NSPasteboard *)pasteboardWithName:(NSString *)name {
   return [[[NSPasteboard alloc] _initWithName:name] autorelease];
}

-(NSDraggingManager *)draggingManager {
   /* One dragging manager per process: it owns the drag proxy window and the
    * registry of windows that accept drops. */
   return [NSDraggingManager draggingManager];
}

-(NSColor *)colorWithName:(NSString *)colorName {
   if([colorName isEqual:@"controlColor"])
      return [NSColor lightGrayColor];
   if([colorName isEqual:@"disabledControlTextColor"])
      return [NSColor grayColor];
   if([colorName isEqual:@"controlTextColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"menuBackgroundColor"])
      return [NSColor lightGrayColor];
   if([colorName isEqual:@"controlShadowColor"])
      return [NSColor darkGrayColor];
   if([colorName isEqual:@"selectedControlColor"])
      return [NSColor cyanColor];
   if([colorName isEqual:@"controlBackgroundColor"])
      return [NSColor whiteColor];
   if([colorName isEqual:@"controlLightHighlightColor"])
      return [NSColor lightGrayColor];

   if([colorName isEqual:@"textBackgroundColor"])
      return [NSColor whiteColor];
   if([colorName isEqual:@"textColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"menuItemTextColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"selectedMenuItemTextColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"selectedMenuItemColor"])
      return [NSColor cyanColor];
   if([colorName isEqual:@"selectedControlTextColor"])
      return [NSColor blackColor];
   
   return nil;
}

-(void)_addSystemColor:(NSColor *) result forName:(NSString *)colorName {
   NSUnimplementedMethod();
 }


-(NSTimeInterval)textCaretBlinkInterval {
   return 0.5;
}

-(void)hideCursor {
   /* The WindowServer owns cursor visibility. */
}

-(void)unhideCursor {
   /* The WindowServer owns cursor visibility. */
}

// Arrow, IBeam, HorizontalResize, VerticalResize
-(id)cursorWithName:(NSString *)name {
   /* The cursor is drawn by the WindowServer; a client-side cursor is only an
    * opaque token here.  Raising NSUnimplementedMethod aborted every app that
    * touched NSCursor (TextEdit sets the I-beam on its text view). */
   return name != nil ? [[name copy] autorelease] : @"arrowCursor";
}

-(void)setCursor:(id)cursor {
   /* Drawn by the WindowServer from its pointer position. */
}

-(NSEvent *)nextEventMatchingMask:(unsigned)mask untilDate:(NSDate *)untilDate inMode:(NSString *)mode dequeue:(BOOL)dequeue {
    NSEvent *result=nil;
    if([_eventQueue count])
        untilDate=[NSDate date];
    else {
        /* The pipe wake-up (NSSelectInputSource -> NSRunLoop) does not reliably
         * return on ravynOS, and blocking forever here starves every client of
         * key, mouse and redraw events.  Bound the wait instead: the mach service
         * thread posts events and pokes us through _machEventPipe, so a short
         * poll keeps the queue live without depending on that select path. */
        NSDate *bounded=[NSDate dateWithTimeIntervalSinceNow:0.05];
        untilDate=[untilDate earlierDate:bounded];
    }
    [[NSRunLoop currentRunLoop] limitDateForMode:mode];
    int pipeFd = [NSApp machEventPipeReadFd];
    if(pipeFd >= 0) {
        struct pollfd pfd;
        pfd.fd = pipeFd;
        pfd.events = POLLIN;
        NSTimeInterval waitFor = [untilDate timeIntervalSinceNow];
        if(waitFor < 0)
            waitFor = 0;
        if(waitFor > 0.25)
            waitFor = 0.25;
        poll(&pfd, 1, (int)(waitFor * 1000));
    }
    [NSApp _drainPipe]; // if there are events, read one at a time
    [[NSRunLoop currentRunLoop] removeInputSource:[NSApp inputSource] forMode:mode];

    @synchronized(_eventQueue) {
    while(result==nil && [_eventQueue count]>0) {
        NSEvent *check=[_eventQueue objectAtIndex:0];    
        NSEventType headType=[check type];
        if((headType==NSMouseMoved || headType==NSLeftMouseDragged || headType==NSRightMouseDragged) && [_eventQueue count]>1){
            pointerPos=[check locationInWindow];
            [_eventQueue removeObjectAtIndex:0];
            continue;
        }
    if(!(NSEventMaskFromType([check type])&mask)) {
         [_eventQueue removeObjectAtIndex:0];
    }
    else {
         result=[[check retain] autorelease];

         NSEventType _type = [result type];
         if(_type == NSMouseMoved || _type == NSLeftMouseDragged || _type == NSRightMouseDragged)
             pointerPos = [result locationInWindow];

        if(dequeue) {
            [_eventQueue removeObjectAtIndex:0];
        }
       }
   }
    }
    if(result==nil){
     result=[[[NSEvent alloc] initWithType:NSAppKitSystem location:NSMakePoint(0,0) modifierFlags:0 window:nil] autorelease];
    }
   
    return result;
}

-(void)discardEventsMatchingMask:(unsigned)mask beforeEvent:(NSEvent *)event {
   @synchronized(_eventQueue) {
   int count=[_eventQueue count];

   while(--count>=0){
    NSEvent *check=[_eventQueue objectAtIndex:count];

    if(check==event)
     break;
   }

   while(--count>=0){
    if(NSEventMaskFromType([event type])&mask)
     [_eventQueue removeObjectAtIndex:count];
   }
   }
}

-(void)postEvent:(NSEvent *)event atStart:(BOOL)atStart {
   /* Called from the NSApplication mach service thread while the main thread
    * drains the same queue in -nextEventMatchingMask:.  NSMutableArray is not
    * thread-safe, so the two threads racing addObject/removeObjectAtIndex
    * realloc/free the backing store concurrently and corrupt the allocator. */
   @synchronized(_eventQueue) {
    if(atStart)
     [_eventQueue insertObject:event atIndex:0];
    else
     [_eventQueue addObject:event];
   }
}

-(BOOL)containsAndRemovePeriodicEvents {
   @synchronized(_eventQueue) {
   BOOL result=NO;
   int  count=[_eventQueue count];

   while(--count>=0){
    if([(NSEvent *)[_eventQueue objectAtIndex:count] type]==NSPeriodic){
     result=YES;
     [_eventQueue removeObjectAtIndex:count];
    }
   }

   return result;
   }
}

-(unsigned)modifierForDefault:(NSString *)key:(unsigned)standard {
   NSDictionary *modmap=[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NSModifierFlagMapping"];
   NSString     *remap=[modmap objectForKey:key];

   if([remap isEqualToString:@"Command"])
    return NSCommandKeyMask;
   if([remap isEqualToString:@"Alt"])
    return NSAlternateKeyMask;
   if([remap isEqualToString:@"Control"])
    return NSControlKeyMask;

   return standard;
}

-(void)beep {
   NSUnimplementedMethod();
}

-(NSSet *)allFontFamilyNames {
   NSMutableSet *ret=[NSMutableSet set];
   NSArray      *names=O2FontKnownFontNames();
   NSEnumerator *next=[names objectEnumerator];
   NSString     *name;

   /* Enumerate the fonts this platform can resolve rather than asking
    * fontconfig: fontconfig is not the face lookup path here (see
    * O2Font_ttf.m), and initialising it from this method crashed the menu
    * bar inside FcConfigMessage (it reports "out of memory" and then
    * prints through a NULL stream). */
   while((name=[next nextObject])!=nil){
    NSRange dash=[name rangeOfString:@"-"];

    [ret addObject:(dash.location==NSNotFound)?name:[name substringToIndex:dash.location]];
   }

   return ret;
}

-(NSArray *)fontTypefacesForFamilyName:(NSString *)familyName {
   NSMutableArray *ret=[NSMutableArray array];
   NSString       *prefix=[familyName stringByAppendingString:@"-"];
   NSEnumerator   *next=[O2FontKnownFontNames() objectEnumerator];
   NSString       *name;

   /* Same reasoning as -allFontFamilyNames: no fontconfig. */
   while((name=[next nextObject])!=nil){
    NSString        *traitName;
    NSFontTraitMask  traits=0;

    if(![name hasPrefix:prefix])
     continue;

    traitName=[name substringFromIndex:[prefix length]];

    if([traitName rangeOfString:@"Bold"].location!=NSNotFound)
     traits|=NSBoldFontMask;
    if([traitName rangeOfString:@"Italic"].location!=NSNotFound ||
       [traitName rangeOfString:@"Oblique"].location!=NSNotFound)
     traits|=NSItalicFontMask;

    [ret addObject:[[[NSFontTypeface alloc] initWithName:name traitName:traitName traits:traits] autorelease]];
   }

   return ret;
}

-(float)scrollerWidth {
   return 15.0;
}

-(float)doubleClickInterval {
   return 1.0;
}


-(int)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)printInfo {
   NSUnimplementedMethod();
	return 0;
}

-(int)runModalPrintPanelWithPrintInfoDictionary:(NSMutableDictionary *)attributes {
   NSUnimplementedMethod();
   return 0;
}

-(O2Context *)graphicsPortForPrintOperationWithView:(NSView *)view printInfo:(NSPrintInfo *)printInfo pageRange:(NSRange)pageRange {
   NSUnimplementedMethod();
   return nil;
}

-(int)savePanel:(NSSavePanel *)savePanel runModalForDirectory:(NSString *)directory file:(NSString *)file {
   /* The panel owns its browser; the display only forwards to it. */
   return [savePanel _runRavynModalForDirectory:directory file:file types:nil];
}

-(int)openPanel:(NSOpenPanel *)openPanel runModalForDirectory:(NSString *)directory file:(NSString *)file types:(NSArray *)types {
   return [openPanel _runRavynModalForDirectory:directory file:file types:types];
}

/* Screen coordinates, as Cocoa defines it.  pointerPos only ever holds the
 * last event's window-relative point, so ask the WindowServer for the real
 * cursor position and fall back to the cached value when it cannot answer. */
-(NSPoint)mouseLocation {
    struct wsRPCSimple args;
    struct wsRPCSimple reply;
    int len = sizeof(reply);

    memset(&args, 0, sizeof(args));
    memset(&reply, 0, sizeof(reply));
    args.base.code = kWSGetPointerPosition;
    args.base.len = 0;

    if(_windowServerRPC != NULL &&
       _windowServerRPC(&args, sizeof(args), &reply, &len) == KERN_SUCCESS &&
       reply.base.len >= 8) {
        pointerPos = NSMakePoint((CGFloat)(int32_t)reply.val1,
                                 (CGFloat)(int32_t)reply.val2);
    }
    return pointerPos;
}

-(NSUInteger)currentModifierFlags {
   NSUnimplementedMethod();
   return 0;
}

@end

void NSColorSetCatalogColor(NSString *catalogName,NSString *colorName,NSColor *color){
    NSColorList *list = [NSColorList colorListNamed:catalogName];
    if(list)
        [list setColor:color forKey:colorName];
}

NSColor *NSColorGetCatalogColor(NSString *catalogName,NSString *colorName){
    return [NSColor colorWithCatalogName:catalogName colorName:colorName];
}

#import <AppKit/NSGraphicsStyle.h>

@implementation NSGraphicsStyle (Overrides) 
-(void)drawMenuBranchArrowInRect:(NSRect)rect selected:(BOOL)selected {
    NSImage* arrow=[NSImage imageNamed:@"NSMenuArrow"];
    // ??? magic numbers
    rect.origin.y+=5;
    rect.origin.x-=2;
    [arrow drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
}
@end
