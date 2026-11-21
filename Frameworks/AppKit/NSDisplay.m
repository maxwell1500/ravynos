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
#import <CoreGraphics/CGEvent.h>
#import "WindowServer/rpc.h"

extern kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSDraggingManager.h>
#include <unistd.h>
#include <pthread.h>
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
   /* There is one display for the process, not one per thread.  This used to
    * return NSThreadSharedInstance, which is keyed by the *current* thread, so
    * the mach service thread that calls -postEvent: and the main thread that
    * drains the queue could hold two different NSDisplay objects, each with its
    * own _eventQueue.  Events then accumulated in a queue nothing drained:
    * measured as [NSPOST] q=1..9 with no matching [APPDISP], and as a menu bar
    * that posted every click and dispatched none. */
   static NSDisplay *shared = nil;
   if(shared == nil) {
      @synchronized([NSDisplay class]) {
         if(shared == nil)
            shared = [[NSDisplay alloc] init];
      }
   }
   return shared;
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

-(NSEvent *)_dequeueEventMatchingMask:(unsigned)mask dequeue:(BOOL)dequeue {
   NSEvent *result=nil;

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
         /* Menu tracking calls with a narrow mask; parking (not dropping)
          * non-matching events preserves button-up/flags/key-up/wheel. */
         [_eventQueue removeObjectAtIndex:0];
         [_eventQueue addObject:check];
         if([_eventQueue count] > 1024) [_eventQueue removeObjectAtIndex:0];
         continue;
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

   return result;
}

-(NSEvent *)nextEventMatchingMask:(unsigned)mask untilDate:(NSDate *)untilDate inMode:(NSString *)mode dequeue:(BOOL)dequeue {
    NSEvent *result;

    /* Look in the queue first.  This used to happen after the wait below, and
     * in between sat -[NSRunLoop removeInputSource:forMode:] and
     * -limitDateForMode:, both of which mutate the run loop.  Measured on a
     * boot where the menu bar posted every click and dispatched none: the loop
     * reported "enter q=9" with the events already queued, then never took a
     * single event for the rest of the run -- it was stuck in the run-loop
     * calls with work waiting.  Nothing needs the run loop to hand back an
     * event that is already in the queue. */
    result=[self _dequeueEventMatchingMask:mask dequeue:dequeue];
    if(result!=nil)
        return result;

    if(untilDate==nil || [untilDate timeIntervalSinceNow] > 0) {
        /* The pipe wake-up (NSSelectInputSource -> NSRunLoop) does not reliably
         * return on ravynOS, and blocking forever here starves every client of
         * key, mouse and redraw events.  Bound the wait instead: the mach service
         * thread posts events and pokes us through _machEventPipe, so a short
         * poll keeps the queue live without depending on that select path. */
        NSTimeInterval waitFor = 0.05;
        if(untilDate!=nil)
            waitFor = [untilDate timeIntervalSinceNow];
        if(waitFor > 0.25)
            waitFor = 0.25;
        if(waitFor > 0) {
            int pipeFd = [NSApp machEventPipeReadFd];
            if(pipeFd >= 0) {
                struct pollfd pfd;
                pfd.fd = pipeFd;
                pfd.events = POLLIN;
                poll(&pfd, 1, (int)(waitFor * 1000));
            }
        }
        [NSApp _drainPipe]; // if there are events, read one at a time
        result=[self _dequeueEventMatchingMask:mask dequeue:dequeue];
        if(result!=nil)
            return result;
    }

    /* Nothing waiting: give the loop a turn so timers and observers still run,
     * then return the system event as before. */
    [[NSRunLoop currentRunLoop] limitDateForMode:mode];

    result=[[[NSEvent alloc] initWithType:NSAppKitSystem location:NSMakePoint(0,0) modifierFlags:0 window:nil] autorelease];
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

-(NSUInteger)queueLength {
   NSUInteger n;
   @synchronized(_eventQueue) { n = [_eventQueue count]; }
   return n;
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
    { static int n = 0;
      if(n < 40) { ++n;
        fprintf(stderr, "[NSPOST] pid=%d display=%p type=%d win=%d q=%d\n",
                (int)getpid(), (void *)self, (int)[event type],
                (int)[event windowNumber], (int)[_eventQueue count]); } }
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
   NSEnumerator   *next=[O2FontKnownFontNames() objectEnumerator];
   NSString       *name;
   NSString       *normalizedFamily=[[familyName stringByReplacingOccurrencesOfString:@" " withString:@""] lowercaseString];

   /* Same reasoning as -allFontFamilyNames: no fontconfig. */
   while((name=[next nextObject])!=nil){
    NSString        *traitName;
    NSFontTraitMask  traits=0;
    NSRange          dash=[name rangeOfString:@"-"];
    NSString        *familyPart=(dash.location==NSNotFound)?name:[name substringToIndex:dash.location];
    NSString        *normalizedPart=[[familyPart stringByReplacingOccurrencesOfString:@" " withString:@""] lowercaseString];

    /* Match the family part case- and space-insensitively: Gecko asks for
     * "Hiragino Kaku Gothic Pro" while the face is registered as
     * "HiraginoKakuGothicPro-W3".  A face with no dash is the regular
     * face of its family ("Arial", "Helvetica", "Monaco", "System"). */
    if(![normalizedPart isEqualToString:normalizedFamily])
     continue;

    traitName=(dash.location==NSNotFound)?@"Regular":[name substringFromIndex:dash.location+1];

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

/* Live modifier state of the last event delivered to this app.  NSEvent's
 * +modifierFlags and drag-time code read this without an event in hand, so a
 * stub returning 0 made every modifier look released outside -keyDown:. */
static NSUInteger sCurrentModifierFlags = 0;

-(NSUInteger)currentModifierFlags {
   return sCurrentModifierFlags;
}

-(void)setCurrentModifierFlags:(NSUInteger)flags {
   sCurrentModifierFlags = flags;
   RavynCGEventSourceSetCurrentFlags((CGEventFlags)flags);
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
