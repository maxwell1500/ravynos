/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSArray_concrete.h"
#import <Foundation/NSRaise.h>
#import <Foundation/NSRaiseException.h>
#include <stdio.h>

@implementation NSArray_concrete

static inline NSArray_concrete *newWithCount(NSZone *zone,NSUInteger count){
   return NSAllocateObject([NSArray_concrete class],sizeof(id)*count,zone);
}

NSArray *NSArray_concreteNewWithCount(NSZone *zone,id **objects,NSUInteger count){
   NSArray_concrete *self=newWithCount(zone,count);

   self->_count=count;
   *objects=self->_objects;

   return self;
}

#import <mach-o/loader.h>
#import <mach-o/dyld.h>

/* True when ptr lies inside a loaded image's data (non-executable)
 * segment -- i.e. where legitimate class objects live.  The exec-range
 * cache rebuilds when dyld's image count changes; until then an empty
 * cache reports "not image data", which errs toward printing. */
static int _isaIsImageData(uintptr_t ptr)
{
    static struct { uintptr_t start,end; } ranges[512]; /* all data segs; Firefox alone loads >96 */
    static uint32_t nranges, lastImageCount=(uint32_t)-1;
    uint32_t n=_dyld_image_count();

    if(n!=lastImageCount) {
        uint32_t i,r=0;
        for(i=0;i<n && r<512;i++) {
            const struct mach_header *h=_dyld_get_image_header(i);
            const struct load_command *lc=(const void *)((char *)h+sizeof(struct mach_header_64));
            const struct segment_command_64 *seg;
            uint32_t c;
            for(c=0;c<h->ncmds;c++) {
                if(lc->cmd==LC_SEGMENT_64) {
                    seg=(const void *)lc;
                    if(!(seg->initprot & VM_PROT_EXECUTE) &&
                       seg->filesize>0 && (seg->initprot & VM_PROT_READ)) {
                        ranges[r].start=(uintptr_t)seg->vmaddr+
                                        _dyld_get_image_vmaddr_slide(i);
                        ranges[r].end=ranges[r].start+seg->vmsize;
                        if(++r>=512) break;
                    }
                    lc=(const void *)((char *)lc+lc->cmdsize);
                } else lc=(const void *)((char *)lc+lc->cmdsize);
            }
        }
        nranges=r; lastImageCount=n;
    }
    {   uint32_t i;
        for(i=0;i<nranges;i++)
            if(ptr>=ranges[i].start && ptr<ranges[i].end) return true;
    }
    return false;
}
NSArray *NSArray_concreteNew(NSZone *zone,id *objects,NSUInteger count) {
   NSArray_concrete *self=newWithCount(zone,count);
   NSUInteger         i;
   extern int _objc_isKnownClassPtr(const void *ptr); /* objc4 */

   self->_count=count;
   for(i=0;i<count;i++) {
    id o=objects[i];
    /* [NSARR] The retain CAS died writing code bytes as an isa word
     * (measured: &___CFStringDeallocate).  Print the culprit before the
     * same CAS runs, so serial carries the pointer the CORPSE cannot.
     * Non-pointer isas (magic 0x001d8..., Firefox uses them) and any
     * class the runtime registered are normal and stay silent; a real
     * class object lives in an image's data segment, so print only when
     * the isa is NOT image-backed data -- an executable-range pointer
     * (code bytes) or plain garbage.  A dedupe ring was tried instead and
     * flooded (154k lines/one session: >8 unknown isas interleave and
     * every eviction reprints). */
    if(o!=NULL && (uintptr_t)o > 0xffff) {
     uintptr_t isa=*(uintptr_t *)o & 0x00007ffffffffff8ULL;
    if(!_objc_isKnownClassPtr((void *)isa) && !_isaIsImageData(isa)) {
     static int named;
     if(named<3){
      /* dladdr is unimplemented in the guest libdyld (returns 0,
       * measured), so name the caller by walking dyld's image list. */
      uintptr_t ra=(uintptr_t)__builtin_return_address(0);
      uint32_t ni=_dyld_image_count(),ki;
      for(ki=0;ki<ni;ki++){
       const struct mach_header *h=_dyld_get_image_header(ki);
       const struct load_command *lc=(const void *)((char *)h+sizeof(struct mach_header_64));
       const struct segment_command_64 *seg;
       uint32_t c;
       for(c=0;c<h->ncmds;c++,lc=(const void *)((char *)lc+lc->cmdsize))
        if(lc->cmd==LC_SEGMENT_64){
         seg=(const void *)lc;
         uintptr_t s=(uintptr_t)seg->vmaddr+_dyld_get_image_vmaddr_slide(ki);
         if(ra>=s && ra<s+seg->vmsize){
          fprintf(stdout,"[NSARR] caller=%p off=+0x%llx img=%s\n",
                  (void *)ra,(unsigned long long)(ra-s),
                  _dyld_get_image_name(ki));
          goto named_done;
         }
        }
      }
      fprintf(stdout,"[NSARR] caller=%p img=?\n",(void *)ra);
named_done:
      named++;
     }
     fprintf(stdout,"[NSARR] retain of non-object %p first=%p\n",
             (void *)o,(void *)isa);
    }
    }
    self->_objects[i]=[o retain];
   }

   return self;
}

NSArray *NSArray_concreteWithArrayAndObject(NSArray *array,id object) {
   NSUInteger         i,count=[array count];
   NSArray_concrete *self=newWithCount(NULL,count+1);

   self->_count=count+1;

   [array getObjects:self->_objects];
   for(i=0;i<count;i++)
    [self->_objects[i] retain];

   self->_objects[count]=[object retain];

   return self;
}

NSArray *NSArray_concreteWithArrayAndArray(NSArray *array1,NSArray *array2) {
   NSUInteger         i,count1=[array1 count],total=count1+[array2 count];
   NSArray_concrete *self=newWithCount(NULL,total);

   self->_count=total;

   [array1 getObjects:self->_objects];
   [array2 getObjects:self->_objects+count1];
   for(i=0;i<total;i++)
    [self->_objects[i] retain];

   return self;
}

NSArray *NSArray_concreteWithArrayRange(NSArray *array,NSRange range) {
   NSArray_concrete *self=newWithCount(NULL,range.length);
   NSUInteger         i;

   self->_count=range.length;

   [array getObjects:self->_objects range:range];

   for(i=0;i<range.length;i++)
    [self->_objects[i] retain];

   return self;
}

-(void)dealloc {
   NSInteger count=_count;

   while(--count>=0)
    [_objects[count] release];

   NSDeallocateObject(self);
   return;
   [super dealloc];
}

-(NSUInteger)count { return _count; }

-objectAtIndex:(NSUInteger)index {
   if(index>=_count){
    NSRaiseException(NSRangeException,self,_cmd,@"index %d beyond count %d",index,_count);
    return nil;
   }
   
   return _objects[index];
}

-lastObject {
   if(_count==0)
    return nil;

   return _objects[_count-1];
}

-(NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)length;
{
   if(state->state>=_count)
    return 0;
   
   state->itemsPtr=_objects;
   state->state=_count;
   
   state->mutationsPtr=(unsigned long*)self;
	
   return _count;
}

@end
