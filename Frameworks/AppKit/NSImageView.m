/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009 Markus Hitter <mah@jump-ing.de>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSImageView.h>
#import <AppKit/NSImageCell.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>

@implementation NSImageView

+(Class)cellClass {
   return [NSImageCell class];
}

-target {
   return _target;
}

-(SEL)action {
   return _action;
}

-(void)setTarget:target {
   _target=target;
}

-(void)setAction:(SEL)action {
   _action=action;
}

-(BOOL)allowsCutCopyPaste {
   // Because cut, copy, paste isn't implemented yet ...
   return NO;
}

-(BOOL)animates {
   // Because animation isn't implemented yet ...
   return NO;
}

-(NSImage *)image {
   return [_cell image];
}

-(NSImageAlignment)imageAlignment {
   return [_cell imageAlignment];
}

-(NSImageFrameStyle)imageFrameStyle {
   return [_cell imageFrameStyle];
}

-(NSImageScaling)imageScaling {
   return [_cell imageScaling];
}

-(BOOL)refusesFirstResponder {
    // we don't have an NSCell
    return YES;
}

-(BOOL)isEditable {
   return [_cell isEditable];
}

-(void)setAllowsCutCopyPaste:(BOOL)allow {
   if(allow!=NO)
    NSUnimplementedMethod();
}

-(void)setAnimates:(BOOL)flag {
   if(flag!=NO)
    ;// NSUnimplementedMethod(); ignore until implemented
}

-(void)setEditable:(BOOL)flag {
   [_cell setEditable:flag];
}

-(void)setImage:(NSImage *)image {
	[_cell setImage:image];
	[self setNeedsDisplay:YES];
}

-(void)setValuePath:(NSString *)path {
	NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
	[_cell setImage:image];
	[self setNeedsDisplay:YES];
}

-(void)setValueURL:(NSURL *)url {
	NSImage *image = [[[NSImage alloc] initWithContentsOfURL:url] autorelease];
	[_cell setImage:image];
	[self setNeedsDisplay:YES];
}

-(void)setImageAlignment:(NSImageAlignment)alignment {
   [_cell setImageAlignment:alignment];
   [self setNeedsDisplay:YES];
}

-(void)setImageFrameStyle:(NSImageFrameStyle)frameStyle {
   [_cell setImageFrameStyle:frameStyle];
   [self setNeedsDisplay:YES];
}

-(void)setImageScaling:(NSImageScaling)scaling {
   [_cell setImageScaling:scaling];
   [self setNeedsDisplay:YES];
}
/* This tree never draws cell-based views (-[NSView displayRectIgnoringOpacity:inContext:]
 * is NSUnimplementedMethod and base -drawRect: does nothing), so image views painted
 * nothing anywhere; composite the image ourselves using the scaling already stored on
 * the cell and the graphicsPort idiom proven to work elsewhere in this tree. */
-(void)drawRect:(NSRect)rect {
    NSImage *img=[_cell _imageValue];
    if(img==nil)
        return;
    NSRect bnds=[self bounds];
    NSSize fsz=bnds.size;
    NSSize isz=[img size];
    /* Several PNGs here report no intrinsic size, so fall back to the view box. */
    if(isz.width<=0 || isz.height<=0){
        isz.width=fsz.width;
        isz.height=fsz.height;
    }
    float sx=fsz.width/isz.width, sy=fsz.height/isz.height;
    float s=(sx<sy)?sx:sy;
    if([_cell imageScaling]==NSImageScaleNone)
        s=1.0f;
    NSSize dsz;
    dsz.width=isz.width*s;
    dsz.height=isz.height*s;
    NSPoint org;
    org.x=bnds.origin.x+(fsz.width-dsz.width)/2;
    org.y=bnds.origin.y+(fsz.height-dsz.height)/2;
    NSGraphicsContext *winCtx = [[self window] graphicsContext];
    if(winCtx == nil)
        return;
    NSGraphicsContext *prev = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:winCtx];
    [img drawInRect:NSMakeRect(org.x,org.y,dsz.width,dsz.height)
        fromRect:NSZeroRect
        operation:NSCompositingOperationSourceOver
        fraction:1.0];
    [NSGraphicsContext setCurrentContext:prev];
}

@end
