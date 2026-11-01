/*
 * autorelease.m -- nested autorelease pools must release each object once.
 *
 * Firefox died in AutoreleasePoolPage::releaseUntil releasing an NSData
 * whose isa had already been filled with 0xe5: the object had been
 * autoreleased once and released twice.  This fixture isolates the pool
 * bookkeeping from any framework retain/release behaviour: it creates
 * objects whose dealloc is counted, puts them in nested pools (including
 * enough objects to allocate child pages), and asserts the count after
 * each drain.
 *
 * Built with Apple's clang and SDK, like the other fixtures, so a pass is
 * a statement about the runtime in the guest, not about our headers.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>

static long g_deallocs;

@interface PoolProbe : NSObject
@end

@implementation PoolProbe
- (void)dealloc
{
    g_deallocs++;
    [super dealloc];
}
@end

static int g_failures;

static void
fail(const char *what, long expected, long actual)
{
    fprintf(stderr, "autorelease: FAIL %s: expected %ld deallocs, got %ld\n",
            what, expected, actual);
    g_failures++;
}

static void
expect(const char *what, long expected)
{
    if (g_deallocs != expected)
        fail(what, expected, g_deallocs);
}

static PoolProbe *
autoreleased_probe(void)
{
    return [[[PoolProbe alloc] init] autorelease];
}

int
main(void)
{
    /* 1. One pool, one object. */
    NSAutoreleasePool *p1 = [[NSAutoreleasePool alloc] init];
    autoreleased_probe();
    [p1 drain];
    expect("single pool", 1);

    /* 2. Nested pools: the inner drain must not touch the outer object,
     *    and the outer drain must not release the inner object again. */
    NSAutoreleasePool *outer = [[NSAutoreleasePool alloc] init];
    autoreleased_probe();
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    autoreleased_probe();
    [inner drain];
    expect("inner drain", 2);
    [outer drain];
    expect("outer drain", 3);

    /* 3. One object, two pool entries, retained once for each entry: it
     *    must be deallocated exactly once.  This is the shape that crashes
     *    when the pool releases an entry it no longer owns. */
    NSAutoreleasePool *dup = [[NSAutoreleasePool alloc] init];
    PoolProbe *twice = [[[PoolProbe alloc] init] retain];
    [twice autorelease];
    [twice autorelease];
    [dup drain];
    expect("double autorelease", 4);

    /* 4. Child pages: enough entries to cross the page boundary, with a
     *    nested pool opened after the pages exist.  Popping the inner pool
     *    must leave every outer entry alive. */
    long before = g_deallocs;
    NSAutoreleasePool *pages = [[NSAutoreleasePool alloc] init];
    enum { N = 40000 };
    for (int i = 0; i < N; i++)
        autoreleased_probe();

    NSAutoreleasePool *late = [[NSAutoreleasePool alloc] init];
    autoreleased_probe();
    [late drain];
    if (g_deallocs != before + 1)
        fail("late pool drained outer entries", before + 1, g_deallocs);

    [pages drain];
    if (g_deallocs != before + N + 1)
        fail("page drain", before + N + 1, g_deallocs);

    /* 5. @autoreleasepool syntax goes through the same push/pop entry
     *    points; nested blocks with many objects must behave the same. */
    long before2 = g_deallocs;
    @autoreleasepool {
        for (int i = 0; i < 1000; i++)
            autoreleased_probe();
        @autoreleasepool {
            for (int i = 0; i < 1000; i++)
                autoreleased_probe();
        }
    }
    if (g_deallocs != before2 + 2000)
        fail("@autoreleasepool nesting", before2 + 2000, g_deallocs);

    if (g_failures) {
        fprintf(stderr, "FIXTURE autorelease rc=1\n");
        return 1;
    }

    printf("FIXTURE autorelease rc=0\n");
    return 0;
}
