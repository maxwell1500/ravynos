/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE. */

#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <WindowServer/message.h>
#import <WindowServer/rpc.h>

#include <mach/mach.h>
#include <servers/bootstrap.h>

extern mach_port_t bootstrap_port;
extern void bootstrap_init(void);
extern kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);

/* The view that draws the dragged image inside the drag proxy window. */
@interface WSDragImageView : NSView {
    NSImage *_image;
}
- (void)setDragImage:(NSImage *)image;
@end

@implementation WSDragImageView
- (void)setDragImage:(NSImage *)image {
    [_image release];
    _image = [image retain];
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)rect {
    if(_image == nil)
        return;
    [_image drawInRect:[self bounds] fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver fraction:1.0];
}
@end

/* The information object handed to the drag destination. */
@interface WSDraggingInfo : NSObject <NSDraggingInfo> {
    NSWindow *_draggingDestinationWindow;
    NSDragOperation _draggingSourceOperationMask;
    NSPoint _draggingLocation;
    NSImage *_draggedImage;
    NSPoint _draggedImageLocation;
    NSPasteboard *_draggingPasteboard;
    id _draggingSource;
    int _sequenceNumber;
    NSWindow *_proxyWindow;
}

- (void)setDraggingDestinationWindow:(NSWindow *)window;
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask;
- (void)setDraggingLocation:(NSPoint)location;
- (void)setDraggedImage:(NSImage *)image;
- (void)setDraggedImageLocation:(NSPoint)location;
- (void)setDraggingPasteboard:(NSPasteboard *)pasteboard;
- (void)setDraggingSource:(id)source;
- (void)setProxyWindow:(NSWindow *)window;

@end

@implementation WSDraggingInfo

- (id)init {
    self = [super init];
    if(self != nil) {
        _draggingSourceOperationMask = NSDragOperationEvery;
        _draggingPasteboard = [[NSPasteboard pasteboardWithName:NSDragPboard] retain];
        _sequenceNumber = 1;
    }
    return self;
}

- (void)dealloc {
    [_draggingDestinationWindow release];
    [_draggedImage release];
    [_draggingPasteboard release];
    [_draggingSource release];
    [_proxyWindow release];
    [super dealloc];
}

- (void)setDraggingDestinationWindow:(NSWindow *)window {
    [_draggingDestinationWindow release];
    _draggingDestinationWindow = [window retain];
}
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask {
    _draggingSourceOperationMask = mask;
}
- (void)setDraggingLocation:(NSPoint)location {
    _draggingLocation = location;
}
- (void)setDraggedImage:(NSImage *)image {
    [_draggedImage release];
    _draggedImage = [image retain];
}
- (void)setDraggedImageLocation:(NSPoint)location {
    _draggedImageLocation = location;
}
- (void)setDraggingPasteboard:(NSPasteboard *)pasteboard {
    if(pasteboard == nil)
        return;
    [_draggingPasteboard release];
    _draggingPasteboard = [pasteboard retain];
}
- (void)setDraggingSource:(id)source {
    [_draggingSource release];
    _draggingSource = [source retain];
}
- (void)setProxyWindow:(NSWindow *)window {
    [_proxyWindow release];
    _proxyWindow = [window retain];
}

- (NSPasteboard *)draggingPasteboard {
    return _draggingPasteboard;
}
- (NSDragOperation)draggingSourceOperationMask {
    return _draggingSourceOperationMask;
}
- (NSPoint)draggingLocation {
    return _draggingLocation;
}
- (NSImage *)draggedImage {
    return _draggedImage;
}
- (NSPoint)draggedImageLocation {
    return _draggedImageLocation;
}
- (NSWindow *)draggingDestinationWindow {
    return _draggingDestinationWindow;
}
- (id)draggingSource {
    return _draggingSource;
}
- (int)draggingSequenceNumber {
    return _sequenceNumber;
}
- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)destination {
    return nil;
}
- (void)slideDraggedImageTo:(NSPoint)point {
    /* The proxy window is the dragged image: move it and let the compositor
     * redraw. */
    if(_proxyWindow == nil)
        return;
    [_proxyWindow setFrameOrigin:NSMakePoint(point.x - _draggedImageLocation.x,
                                            point.y - _draggedImageLocation.y)];
}

@end

@interface WSDraggingManager : NSDraggingManager {
    NSMutableArray *_registeredWindows;
    id _localDraggingSource;
}
-(void)handleRemoteDragEvent:(const struct mach_drag_event *)event;
@end

@implementation WSDraggingManager

+(NSDraggingManager *)sharedManager {
    static WSDraggingManager *manager = nil;

    if(manager == nil)
        manager = [[WSDraggingManager alloc] init];
    return manager;
}

-(id)init {
    self = [super init];
    if(self != nil)
        _registeredWindows = [[NSMutableArray alloc] init];
    return self;
}

-(void)dealloc {
    [_registeredWindows release];
    [super dealloc];
}

-(void)registerWindow:(NSWindow *)window dragTypes:(NSArray *)types {
    if(window == nil)
        return;
    [_registeredWindows addObject:@{@"window": window, @"types": types != nil ? types : [NSArray array]}];
}

-(void)unregisterWindow:(NSWindow *)window {
    unsigned i;
    for(i = [_registeredWindows count]; i > 0; i--) {
        NSDictionary *entry = [_registeredWindows objectAtIndex:i - 1];
        if([entry objectForKey:@"window"] == window)
            [_registeredWindows removeObjectAtIndex:i - 1];
    }
}

-(id)localDraggingSource {
    return _localDraggingSource;
}

#pragma mark - Drag session

/* The topmost visible window under a screen point, as the WindowServer sees
 * it.  Returns NO when the WindowServer cannot be reached. */
-(BOOL)_hitTestAtScreenPoint:(NSPoint)point windowID:(int *)windowID pid:(pid_t *)pid {
    struct wsRPCDragHitTest args;
    struct wsRPCDragHitTest reply;
    int len = sizeof(reply);

    memset(&args, 0, sizeof(args));
    memset(&reply, 0, sizeof(reply));
    args.base.code = kWSDragHitTest;
    args.base.len = 0;
    args.x = point.x;
    args.y = point.y;

    if(_windowServerRPC(&args, sizeof(args), &reply, &len) != KERN_SUCCESS)
        return NO;
    if(reply.found == 0)
        return NO;

    if(windowID != NULL)
        *windowID = (int)reply.windowID;
    if(pid != NULL)
        *pid = (pid_t)reply.pid;
    return YES;
}

/* Send a drag event to another app through the WindowServer. */
-(void)_sendDragEvent:(int)subcode toWindow:(int)windowID atPoint:(NSPoint)point {
    struct mach_drag_event ev;
    Message msg;
    mach_port_t port;

    if(bootstrap_port == MACH_PORT_NULL)
        bootstrap_init();
    if(bootstrap_look_up(bootstrap_port, WINDOWSERVER_SVC_NAME, &port) != KERN_SUCCESS)
        return;

    memset(&ev, 0, sizeof(ev));
    ev.subcode = (uint32_t)subcode;
    ev.windowID = (uint32_t)windowID;
    ev.x = point.x;
    ev.y = point.y;

    memset(&msg, 0, sizeof(msg));
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = CODE_DRAG_EVENT;
    msg.pid = getpid();
    const char *env = getenv("RAVYN_BUNDLE_ID");
    if(env != NULL)
        strncpy(msg.bundleID, env, sizeof(msg.bundleID) - 1);
    else
        snprintf(msg.bundleID, sizeof(msg.bundleID), "unix.%u", getpid());
    memcpy(msg.data, &ev, sizeof(ev));
    msg.len = sizeof(ev);

    mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
             sizeof(msg) - sizeof(mach_msg_trailer_t), 0, MACH_PORT_NULL,
             200 /* ms timeout */, MACH_PORT_NULL);
}

/* The screen position of an event.  The event location is relative to the
 * window's frame origin, which is where the WindowServer's coordinates
 * start. */
/* A drag event forwarded by the WindowServer from another process.  The
 * source app owns the pasteboard; this app reconstructs the session and runs
 * the destination protocol on its own views. */
-(void)handleRemoteDragEvent:(const struct mach_drag_event *)event {
    NSWindow *window;
    NSPoint location;
    WSDraggingInfo *info;
    id receiver;

    if(event == NULL)
        return;

    window = [NSApp windowWithWindowNumber:(NSInteger)event->windowID];
    if(window == nil)
        return;

    /* Screen point -> window coordinates (bottom-left origin). */
    location = NSMakePoint(event->x - [window frame].origin.x,
                           event->y - [window frame].origin.y);

    info = [[WSDraggingInfo alloc] init];
    [info setDraggingDestinationWindow:window];
    [info setDraggingLocation:location];
    [info setDraggingSourceOperationMask:(NSDragOperation)event->operationMask];
    [info setDraggingPasteboard:[NSPasteboard pasteboardWithName:NSDragPboard]];

    receiver = [window _receiverForDragSession:info];
    if(receiver == nil) {
        [info release];
        return;
    }

    switch(event->subcode) {
        case DRAG_ENTER:
            if([receiver respondsToSelector:@selector(draggingEntered:)])
                [receiver draggingEntered:info];
            break;
        case DRAG_MOVE:
            if([receiver respondsToSelector:@selector(draggingUpdated:)])
                [receiver draggingUpdated:info];
            break;
        case DRAG_EXIT:
            if([receiver respondsToSelector:@selector(draggingExited:)])
                [receiver draggingExited:info];
            break;
        case DRAG_DROP: {
            BOOL performed = NO;

            if([receiver respondsToSelector:@selector(prepareForDragOperation:)])
                performed = [receiver prepareForDragOperation:info];
            if(performed && [receiver respondsToSelector:@selector(performDragOperation:)])
                performed = [receiver performDragOperation:info];
            if(performed && [receiver respondsToSelector:@selector(concludeDragOperation:)])
                [receiver concludeDragOperation:info];
            break;
        }
        default:
            break;
    }

    [info release];
}

-(NSPoint)_screenPointForEvent:(NSEvent *)event {
    NSWindow *window = [event window];
    NSPoint local = [event locationInWindow];
    NSRect frame;

    if(window == nil)
        return local;
    frame = [window frame];
    return NSMakePoint(frame.origin.x + local.x, frame.origin.y + local.y);
}

/* The view of the destination window that is under the cursor. */
-(NSView *)_viewUnderPoint:(NSPoint)screenPoint inWindow:(NSWindow *)window {
    NSView *content = [window contentView];
    NSRect frame;
    NSRect contentFrame;
    NSPoint local;
    NSView *view;

    if(content == nil)
        return nil;
    frame = [window frame];
    contentFrame = [content frame];
    local = NSMakePoint(screenPoint.x - frame.origin.x - contentFrame.origin.x,
                        screenPoint.y - frame.origin.y - contentFrame.origin.y);
    view = [content hitTest:local];
    return view;
}

-(NSWindow *)_createProxyWindowWithImage:(NSImage *)image offset:(NSSize)offset {
    NSWindow *proxy;
    WSDragImageView *view;
    NSSize size = image != nil ? [image size] : NSMakeSize(16, 16);

    proxy = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                                        styleMask:NSBorderlessWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:YES];
    [proxy setLevel:NSPopUpMenuWindowLevel];
    [proxy setOpaque:NO];
    [proxy setHasShadow:NO];
    [proxy setIgnoresMouseEvents:YES];
    view = [[WSDragImageView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    [view setDragImage:image];
    [[proxy contentView] addSubview:view];
    [view release];
    [proxy orderFront:nil];

    return proxy;
}

// Location is expected to be in the same window coordinate system as the event
-(void)dragImage:(NSImage *)image at:(NSPoint)location offset:(NSSize)offset event:(NSEvent *)event pasteboard:(NSPasteboard *)pasteboard source:(id)source slideBack:(BOOL)slideBack {
    WSDraggingInfo *info = [[WSDraggingInfo alloc] init];
    NSWindow *proxy;
    NSView *currentTarget = nil;
    int currentTargetWindow = 0;
    pid_t currentTargetPid = 0;
    NSDragOperation operation = NSDragOperationNone;
    NSPoint startPoint;
    BOOL finished = NO;

    if(source != nil)
        _localDraggingSource = source;

    [info setDraggingSource:source];
    [info setDraggingPasteboard:pasteboard];
    [info setDraggedImage:image];
    [info setDraggedImageLocation:NSMakePoint(offset.width, offset.height)];
    if(source != nil && [source respondsToSelector:@selector(draggingSourceOperationMaskForLocal:)])
        [info setDraggingSourceOperationMask:[source draggingSourceOperationMaskForLocal:YES]];
    else
        [info setDraggingSourceOperationMask:NSDragOperationEvery];

    proxy = [self _createProxyWindowWithImage:image offset:offset];
    [info setProxyWindow:proxy];

    startPoint = event != nil ? [self _screenPointForEvent:event] : location;
    [proxy setFrameOrigin:NSMakePoint(startPoint.x - offset.width, startPoint.y - offset.height)];

    if(source != nil && [source respondsToSelector:@selector(draggedImage:beganAt:)])
        [source draggedImage:image beganAt:startPoint];

    while(!finished) {
        NSEvent *e = [NSApp nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
                                         untilDate:[NSDate distantFuture]
                                            inMode:NSDefaultRunLoopMode
                                           dequeue:YES];
        NSPoint screenPoint;
        int windowID = 0;
        pid_t pid = 0;

        if(e == nil)
            break;

        screenPoint = [self _screenPointForEvent:e];
        if([e type] == NSLeftMouseUp)
            finished = YES;

        [proxy setFrameOrigin:NSMakePoint(screenPoint.x - offset.width, screenPoint.y - offset.height)];
        [info setDraggingLocation:screenPoint];

        if(source != nil && [source respondsToSelector:@selector(draggedImage:movedTo:)])
            [source draggedImage:image movedTo:screenPoint];

        if(![self _hitTestAtScreenPoint:screenPoint windowID:&windowID pid:&pid]) {
            /* Left the screen: tell the old target we are gone. */
            if(currentTarget != nil) {
                [currentTarget draggingExited:info];
                currentTarget = nil;
            } else if(currentTargetWindow != 0) {
                [self _sendDragEvent:DRAG_EXIT toWindow:currentTargetWindow atPoint:screenPoint];
            }
            currentTargetWindow = 0;
            currentTargetPid = 0;
            operation = NSDragOperationNone;
            if(finished)
                break;
            continue;
        }

        if(windowID != currentTargetWindow) {
            /* A different window: exit the old one, enter the new one. */
            if(currentTarget != nil)
                [currentTarget draggingExited:info];
            else if(currentTargetWindow != 0)
                [self _sendDragEvent:DRAG_EXIT toWindow:currentTargetWindow atPoint:screenPoint];

            currentTarget = nil;
            currentTargetWindow = windowID;
            currentTargetPid = pid;

            if(pid == getpid()) {
                NSWindow *window = [NSApp windowWithWindowNumber:windowID];
                if(window != nil) {
                    [info setDraggingDestinationWindow:window];
                    currentTarget = [self _viewUnderPoint:screenPoint inWindow:window];
                    if(currentTarget != nil)
                        operation = [currentTarget draggingEntered:info];
                }
            } else {
                [self _sendDragEvent:DRAG_ENTER toWindow:windowID atPoint:screenPoint];
            }
        } else if(currentTarget != nil) {
            operation = [currentTarget draggingUpdated:info];
        } else if(currentTargetPid != getpid()) {
            [self _sendDragEvent:DRAG_MOVE toWindow:windowID atPoint:screenPoint];
        }

        if(finished) {
            if(currentTarget != nil && operation != NSDragOperationNone) {
                if([currentTarget prepareForDragOperation:info] &&
                   [currentTarget performDragOperation:info]) {
                    [currentTarget concludeDragOperation:info];
                } else {
                    operation = NSDragOperationNone;
                }
            } else if(currentTargetWindow != 0 && currentTargetPid != getpid()) {
                [self _sendDragEvent:DRAG_DROP toWindow:currentTargetWindow atPoint:screenPoint];
            }
        }
    }

    if(operation == NSDragOperationNone && slideBack && source != nil) {
        [info slideDraggedImageTo:startPoint];
    }
    if(source != nil && [source respondsToSelector:@selector(draggedImage:endedAt:operation:)])
        [source draggedImage:image endedAt:startPoint operation:operation];

    [proxy orderOut:nil];
    [proxy release];
    [info release];
    _localDraggingSource = nil;
}

@end

@implementation NSDraggingManager

+(NSDraggingManager *)draggingManager {
   return [WSDraggingManager sharedManager];
}

-(void)registerWindow:(NSWindow *)window dragTypes:(NSArray *)types {
   [[WSDraggingManager sharedManager] registerWindow:window dragTypes:types];
}

-(void)unregisterWindow:(NSWindow *)window {
   [[WSDraggingManager sharedManager] unregisterWindow:window];
}

-(id)localDraggingSource {
   return [[WSDraggingManager sharedManager] localDraggingSource];
}

// Location is expected to be in the same window coordinate system as the event
-(void)dragImage:(NSImage *)image at:(NSPoint)location offset:(NSSize)offset event:(NSEvent *)event pasteboard:(NSPasteboard *)pasteboard source:(id)source slideBack:(BOOL)slideBack {
   [[WSDraggingManager sharedManager] dragImage:image at:location offset:offset event:event
                                     pasteboard:pasteboard source:source slideBack:slideBack];
}

@end
