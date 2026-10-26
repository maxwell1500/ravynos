/*
 * Copyright (c) 2011 Tobias Platen
 * Copyright (c) 2026 ravynOS Project
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

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct Block_layout {
    void *isa;
    volatile int32_t flags;
    int32_t reserved;
    void (*invoke)(void *, ...);
    void *descriptor;
};
#define BLOCK_REFCOUNT_MASK (0xffff0000)

OBJC_EXPORT void *_Block_copy(const void *aBlock);
OBJC_EXPORT void _Block_release(const void *aBlock);

extern void * _NSConcreteStackBlock[32];
extern void * _NSConcreteMallocBlock[32];
extern void * _NSConcreteAutoBlock[32];
extern void * _NSConcreteFinalizingBlock[32];
extern void * _NSConcreteGlobalBlock[32];

static void * _NSConcreteStackBlockMeta[32];
static void * _NSConcreteMallocBlockMeta[32];
static void * _NSConcreteAutoBlockMeta[32];
static void * _NSConcreteFinalizingBlockMeta[32];
static void * _NSConcreteGlobalBlockMeta[32];

OBJC_EXPORT Class _Nullable
objc_initializeClassPair(Class _Nullable superclass, const char * _Nonnull name,
                         Class _Nonnull cls, Class _Nonnull metacls);
OBJC_EXPORT void objc_registerClassPair(Class _Nonnull cls);
OBJC_EXPORT id _Nullable objc_autorelease(id _Nullable value);

@interface NSBlock : NSObject
- (void)invoke;
@end

@implementation NSBlock
- (void)invoke {
    void (^blk)(void) = (void (^)(void))self;
    blk();
}

- (id)copy {
    return (id)_Block_copy((const void *)self);
}

- (id)copyWithZone:(NSZone *)zone {
    return (id)_Block_copy((const void *)self);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p>", [self class], self];
}
@end

// __NSStackBlock__ method implementations
static id stack_copy(id self, SEL _cmd) {
    return (id)_Block_copy((const void *)self);
}

static id stack_copyWithZone(id self, SEL _cmd, struct _NSZone *zone) {
    return (id)_Block_copy((const void *)self);
}

static id stack_retain(id self, SEL _cmd) {
    return self;
}

static void stack_release(id self, SEL _cmd) {
    // stack blocks cannot be freed
}

static id stack_autorelease(id self, SEL _cmd) {
    return self;
}

static NSUInteger stack_retainCount(id self, SEL _cmd) {
    return 1;
}

// __NSMallocBlock__ method implementations
static id malloc_retain(id self, SEL _cmd) {
    return (id)_Block_copy((const void *)self);
}

static void malloc_release(id self, SEL _cmd) {
    _Block_release((const void *)self);
}

static id malloc_autorelease(id self, SEL _cmd) {
    return objc_autorelease(self);
}

static id malloc_copy(id self, SEL _cmd) {
    return (id)_Block_copy((const void *)self);
}

static id malloc_copyWithZone(id self, SEL _cmd, struct _NSZone *zone) {
    return (id)_Block_copy((const void *)self);
}

static void malloc_dealloc(id self, SEL _cmd) {
    _Block_release((const void *)self);
}

static NSUInteger malloc_retainCount(id self, SEL _cmd) {
    struct Block_layout *aBlock = (struct Block_layout *)self;
    return (NSUInteger)((aBlock->flags & BLOCK_REFCOUNT_MASK) >> 1);
}

// __NSGlobalBlock__ method implementations
static id global_retain(id self, SEL _cmd) {
    return self;
}

static void global_release(id self, SEL _cmd) {
    // global blocks are immortal
}

static id global_autorelease(id self, SEL _cmd) {
    return self;
}

static id global_copy(id self, SEL _cmd) {
    return self;
}

static id global_copyWithZone(id self, SEL _cmd, struct _NSZone *zone) {
    return self;
}

static NSUInteger global_retainCount(id self, SEL _cmd) {
    return (NSUInteger)-1;
}

static void initBlockClass(Class *outCls, Class superclass, const char *name,
                           void *clsStorage, void *metaStorage, int kind) {
    Class cls = objc_initializeClassPair(superclass, name, (Class)clsStorage, (Class)metaStorage);
    if (!cls) {
        fprintf(stderr, "[NSBlock] failed to initialize %s\n", name);
        return;
    }
    if (kind == 0) { // stack
        class_addMethod(cls, @selector(copy), (IMP)stack_copy, "@:@");
        class_addMethod(cls, @selector(copyWithZone:), (IMP)stack_copyWithZone, "@:@^v");
        class_addMethod(cls, @selector(retain), (IMP)stack_retain, "@:@");
        class_addMethod(cls, @selector(release), (IMP)stack_release, "v:@");
        class_addMethod(cls, @selector(autorelease), (IMP)stack_autorelease, "@:@");
        class_addMethod(cls, @selector(retainCount), (IMP)stack_retainCount, "Q:@");
    } else if (kind == 1) { // malloc
        class_addMethod(cls, @selector(copy), (IMP)malloc_copy, "@:@");
        class_addMethod(cls, @selector(copyWithZone:), (IMP)malloc_copyWithZone, "@:@^v");
        class_addMethod(cls, @selector(retain), (IMP)malloc_retain, "@:@");
        class_addMethod(cls, @selector(release), (IMP)malloc_release, "v:@");
        class_addMethod(cls, @selector(autorelease), (IMP)malloc_autorelease, "@:@");
        class_addMethod(cls, @selector(retainCount), (IMP)malloc_retainCount, "Q:@");
        class_addMethod(cls, @selector(dealloc), (IMP)malloc_dealloc, "v:@");
    } else { // global
        class_addMethod(cls, @selector(copy), (IMP)global_copy, "@:@");
        class_addMethod(cls, @selector(copyWithZone:), (IMP)global_copyWithZone, "@:@^v");
        class_addMethod(cls, @selector(retain), (IMP)global_retain, "@:@");
        class_addMethod(cls, @selector(release), (IMP)global_release, "v:@");
        class_addMethod(cls, @selector(autorelease), (IMP)global_autorelease, "@:@");
        class_addMethod(cls, @selector(retainCount), (IMP)global_retainCount, "Q:@");
    }
    objc_registerClassPair(cls);
    if (outCls) *outCls = cls;
}

__attribute__((constructor))
static void _rvn_init_blocks(void) {
    static int initialized = 0;
    if (initialized) return;
    initialized = 1;

    Class blockSuper = [NSBlock class];
    Class stackCls = Nil, mallocCls = Nil, globalCls = Nil;

    initBlockClass(&stackCls, blockSuper, "__NSStackBlock__",
                   _NSConcreteStackBlock, _NSConcreteStackBlockMeta, 0);
    initBlockClass(&mallocCls, blockSuper, "__NSMallocBlock__",
                   _NSConcreteMallocBlock, _NSConcreteMallocBlockMeta, 1);
    initBlockClass(&globalCls, blockSuper, "__NSGlobalBlock__",
                   _NSConcreteGlobalBlock, _NSConcreteGlobalBlockMeta, 2);
    initBlockClass(NULL, blockSuper, "__NSAutoBlock__",
                   _NSConcreteAutoBlock, _NSConcreteAutoBlockMeta, 1);
    initBlockClass(NULL, blockSuper, "__NSFinalizingBlock__",
                   _NSConcreteFinalizingBlock, _NSConcreteFinalizingBlockMeta, 1);

    fprintf(stderr, "[NSBlock] installed classes: stack=%p malloc=%p global=%p\n",
            stackCls, mallocCls, globalCls);
}
