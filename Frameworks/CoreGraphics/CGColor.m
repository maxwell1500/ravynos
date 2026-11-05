/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreGraphics/CGColor.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2ColorSpace.h>

CGColorRef CGColorRetain(CGColorRef self) {
   return O2ColorRetain(self);
}

void CGColorRelease(CGColorRef self) {
   O2ColorRelease(self);
}

CGColorRef CGColorCreate(CGColorSpaceRef colorSpace,const CGFloat *components) {
   if(colorSpace == NULL || components == NULL)
      return NULL;
   size_t count = O2ColorSpaceGetNumberOfComponents(colorSpace) + 1;
   O2Float fltComps[count];
   for(size_t i = 0; i < count; i++)
      fltComps[i] = (O2Float)components[i];
   return O2ColorCreate(colorSpace, fltComps);
}

CGColorRef CGColorCreateGenericGray(CGFloat gray,CGFloat a) {
   return O2ColorCreateGenericGray((O2Float)gray, (O2Float)a);
}

CGColorRef CGColorCreateGenericRGB(CGFloat r,CGFloat g,CGFloat b,CGFloat a) {
   return O2ColorCreateGenericRGB((O2Float)r, (O2Float)g, (O2Float)b, (O2Float)a);
}

CGColorRef CGColorCreateGenericCMYK(CGFloat c,CGFloat m,CGFloat y,CGFloat k,CGFloat a) {
   return O2ColorCreateGenericCMYK((O2Float)c, (O2Float)m, (O2Float)y, (O2Float)k, (O2Float)a);
}

CGColorRef CGColorCreateWithPattern(CGColorSpaceRef colorSpace,CGPatternRef pattern,const CGFloat *components) {
   if(colorSpace == NULL)
      return NULL;
   size_t count = O2ColorSpaceGetNumberOfComponents(colorSpace) + 1;
   O2Float fltComps[count];
   if(components != NULL) {
      for(size_t i = 0; i < count; i++)
         fltComps[i] = (O2Float)components[i];
   }
   return O2ColorCreateWithPattern(colorSpace, pattern, components ? fltComps : NULL);
}

CGColorRef CGColorCreateCopy(CGColorRef self) {
   return O2ColorCreateCopy(self);
}

CGColorRef CGColorCreateCopyWithAlpha(CGColorRef self,CGFloat a) {
   return O2ColorCreateCopyWithAlpha(self, (O2Float)a);
}

bool CGColorEqualToColor(CGColorRef self,CGColorRef other) {
   return O2ColorEqualToColor(self,other);
}

CGColorSpaceRef CGColorGetColorSpace(CGColorRef self) {
   return O2ColorGetColorSpace(self);
}

size_t CGColorGetNumberOfComponents(CGColorRef self) {
   return O2ColorGetNumberOfComponents(self);
}

const CGFloat *CGColorGetComponents(CGColorRef self) {
   return O2ColorGetCGComponents(self);
}

CGFloat CGColorGetAlpha(CGColorRef self) {
   return O2ColorGetAlpha(self);
}

CGPatternRef CGColorGetPattern(CGColorRef self) {
   return O2ColorGetPattern(self);
}
