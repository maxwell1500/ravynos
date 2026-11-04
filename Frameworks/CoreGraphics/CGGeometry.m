/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#ifndef MIN
#define MIN(a,b) ({__typeof__(a) _a = (a); __typeof__(b) _b = (b); (_a < _b) ? _a : _b; })
#else
#warning MIN is already defined, MIN(a, b) may not behave as expected.
#endif

#ifndef MAX
#define MAX(a,b) ({__typeof__(a) _a = (a); __typeof__(b) _b = (b); (_a > _b) ? _a : _b; })
#else
#warning MAX is already defined, MAX(a, b) may not not behave as expected.
#endif

#define CGGEOMETRY_BUILDING_EXPORTS 1
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGAffineTransform.h>
#import <CoreFoundation/CoreFoundation.h>

const CGRect CGRectZero={{0,0},{0,0}};
const CGRect CGRectNull={{INFINITY,INFINITY},{0,0}};
const CGPoint CGPointZero={0,0};
const CGSize CGSizeZero={0,0};

CGRect CGRectIntersection(CGRect rect0, CGRect rect1) {
	CGRect result;
	
	if(CGRectGetMaxX(rect0)<=CGRectGetMinX(rect1) || CGRectGetMinX(rect0)>=CGRectGetMaxX(rect1) ||
	   CGRectGetMaxY(rect0)<=CGRectGetMinY(rect1) || CGRectGetMinY(rect0)>=CGRectGetMaxY(rect1))
		return CGRectZero;
	
	result.origin.x=MAX(CGRectGetMinX(rect0), CGRectGetMinX(rect1));
	result.origin.y=MAX(CGRectGetMinY(rect0), CGRectGetMinY(rect1));
	result.size.width=MIN(CGRectGetMaxX(rect0), CGRectGetMaxX(rect1))-result.origin.x;
	result.size.height=MIN(CGRectGetMaxY(rect0), CGRectGetMaxY(rect1))-result.origin.y;
	
	return result;
}

CGRect CGRectIntegral(CGRect rect) {
	if (!CGRectIsEmpty(rect)) {
		float maxX = ceil(CGRectGetMaxX(rect));
		float maxY = ceil(CGRectGetMaxY(rect));
		rect.origin.x = floor(rect.origin.x); 
		rect.origin.y = floor(rect.origin.y);
		rect.size.width =  maxX - CGRectGetMinX(rect); 
		rect.size.height = maxY - CGRectGetMinY(rect); 
	}
	return rect; 
	
}

CGRect CGRectUnion(CGRect a, CGRect b) {
	// make sure we handle null!
	if (CGRectIsNull(a)) {
		return b;
	}
	
	if (CGRectIsNull(b)) {
		return a;
	}
	
	float minX = MIN(CGRectGetMinX(a), CGRectGetMinX(b));
	float minY = MIN(CGRectGetMinY(a), CGRectGetMinY(b));
	float maxX = MAX(CGRectGetMaxX(a), CGRectGetMaxX(b));
	float maxY = MAX(CGRectGetMaxY(a), CGRectGetMaxY(b));
	return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

CGRect CGRectStandardize(CGRect rect) {
	if (rect.size.width < 0) {
		rect.origin.x += rect.size.width;
		rect.size.width = -rect.size.width;
	}
	if (rect.size.height < 0) {
		rect.origin.y += rect.size.height;
		rect.size.height = -rect.size.height;
	}
	return rect;
}

CGFloat CGRectGetMinX(CGRect rect) {
	rect = CGRectStandardize(rect);
	return rect.origin.x;
}

CGFloat CGRectGetMaxX(CGRect rect) {
	rect = CGRectStandardize(rect);
	return rect.origin.x + rect.size.width;
}

CGFloat CGRectGetMidX(CGRect rect) {
	rect = CGRectStandardize(rect);
	return rect.origin.x + (rect.size.width * 0.5);
}

CGFloat CGRectGetMinY(CGRect rect) {
	rect = CGRectStandardize(rect);
	return rect.origin.y;
}

CGFloat CGRectGetMaxY(CGRect rect) {
	rect = CGRectStandardize(rect);
	return rect.origin.y + rect.size.height;
}

CGFloat CGRectGetMidY(CGRect rect) {
	rect = CGRectStandardize(rect);
	return rect.origin.y + (rect.size.height * 0.5);
}

CGFloat CGRectGetWidth(CGRect rect) {
	return rect.size.width < 0 ? -rect.size.width : rect.size.width;
}

CGFloat CGRectGetHeight(CGRect rect) {
	return rect.size.height < 0 ? -rect.size.height : rect.size.height;
}

bool CGRectIsEmpty(CGRect rect) {
	if (CGRectIsNull(rect))
		return true;
	rect = CGRectStandardize(rect);
	return (rect.size.width <= 0 || rect.size.height <= 0);
}

bool CGRectContainsRect(CGRect a, CGRect b) {
	if (CGRectIsEmpty(b))
		return true;
	if (CGRectIsEmpty(a))
		return false;
	return (CGRectGetMinX(b) >= CGRectGetMinX(a) &&
	    CGRectGetMaxX(b) <= CGRectGetMaxX(a) &&
	    CGRectGetMinY(b) >= CGRectGetMinY(a) &&
	    CGRectGetMaxY(b) <= CGRectGetMaxY(a));
}

CGRect CGRectApplyAffineTransform(CGRect rect, CGAffineTransform t) {
	rect = CGRectStandardize(rect);
	CGPoint p1 = CGPointApplyAffineTransform(CGPointMake(rect.origin.x, rect.origin.y), t);
	CGPoint p2 = CGPointApplyAffineTransform(CGPointMake(rect.origin.x + rect.size.width, rect.origin.y), t);
	CGPoint p3 = CGPointApplyAffineTransform(CGPointMake(rect.origin.x, rect.origin.y + rect.size.height), t);
	CGPoint p4 = CGPointApplyAffineTransform(CGPointMake(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height), t);
	CGFloat minX = MIN(MIN(p1.x, p2.x), MIN(p3.x, p4.x));
	CGFloat maxX = MAX(MAX(p1.x, p2.x), MAX(p3.x, p4.x));
	CGFloat minY = MIN(MIN(p1.y, p2.y), MIN(p3.y, p4.y));
	CGFloat maxY = MAX(MAX(p1.y, p2.y), MAX(p3.y, p4.y));
	return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

bool CGRectMakeWithDictionaryRepresentation(CFDictionaryRef dict, CGRect *rect) {
	if (dict == NULL || rect == NULL)
		return false;
	CFNumberRef nx = CFDictionaryGetValue(dict, CFSTR("X"));
	CFNumberRef ny = CFDictionaryGetValue(dict, CFSTR("Y"));
	CFNumberRef nw = CFDictionaryGetValue(dict, CFSTR("Width"));
	CFNumberRef nh = CFDictionaryGetValue(dict, CFSTR("Height"));
	double x = 0, y = 0, w = 0, h = 0;
	if (nx) CFNumberGetValue(nx, kCFNumberDoubleType, &x);
	if (ny) CFNumberGetValue(ny, kCFNumberDoubleType, &y);
	if (nw) CFNumberGetValue(nw, kCFNumberDoubleType, &w);
	if (nh) CFNumberGetValue(nh, kCFNumberDoubleType, &h);
	*rect = CGRectMake(x, y, w, h);
	return (nx != NULL && ny != NULL && nw != NULL && nh != NULL);
}
