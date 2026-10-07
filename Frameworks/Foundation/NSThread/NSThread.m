/* Copyright (c) 2006-2007 Christopher J. W. Lloyd, 2008 Johannes Fortmann

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#include <sys/param.h>

#import <Foundation/NSThread.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSPlatform.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSThread-Private.h>
#import <Foundation/NSSynchronization.h>
#import <Foundation/NSConditionLock.h>
#if !defined(GCC_RUNTIME_3) && !defined(APPLE_RUNTIME_4)
#import <Foundation/objc_debugHelpers.h>
#endif
//#import <Foundation/debugHelpers.h>
#import <Foundation/NSSelectSet.h>
#include <pthread.h>

#if defined(LINUX) ||  defined(__APPLE__) ||  defined(__FreeBSD__)
#include <execinfo.h>
#include <sys/resource.h>
#endif


NSString * const NSDidBecomeSingleThreadedNotification=@"NSDidBecomeSingleThreadedNotification";
NSString * const NSWillBecomeMultiThreadedNotification=@"NSWillBecomeMultiThreadedNotification";
NSString * const NSThreadWillExitNotification=@"NSThreadWillExitNotification";

@implementation NSThread

static BOOL isMultiThreaded = NO;
static NSThread* mainThread = nil;

+(void)initialize
{
	if(self==[NSThread class])
	{
      if(!mainThread)
      {
         mainThread = [NSThread new];
         NSPlatformSetCurrentThread(mainThread);
      }
	}
}

+ (BOOL) isMultiThreaded {
	return isMultiThreaded;
}

+(BOOL)isMainThread {
	return NSCurrentThread()==mainThread;
}

+(NSThread *)mainThread {
   return mainThread;
}


- (id) initWithTarget: (id) aTarget selector: (SEL) aSelector object: (id) anArgument {
   [self init];
   _target   = [aTarget retain];
   _selector = aSelector;
   _argument = [anArgument retain];
   return self;
}

- (void) main {
	[_target performSelector: _selector withObject: _argument];
}

#ifdef WINDOWS
// Be sure the stack is aligned in case the thread wants to do exotic things like SSE2
static  __attribute__((force_align_arg_pointer)) unsigned __stdcall nsThreadStartThread(void* t)
#else
static void *nsThreadStartThread(void* t)
#endif
{
   NSThread    *thread = t;
	NSPlatformSetCurrentThread(thread);
	[thread setExecuting:YES];
    NSCooperativeThreadWaiting();
	@try {
		[thread main];
	}
	@catch (NSException * e) {
        NSLog(@"Exception occured : %@", [e description]);
	}
	[thread setExecuting:NO];
	[thread setFinished:YES];

    NSSelectSetShutdownForCurrentThread();
	
	// We need a pool here in case release triggers some autoreleased object allocations
	// so they won't stay in limbo
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[thread release];
	NSPlatformSetCurrentThread(nil);
	[pool drain];
	
	return 0;
}

+(void)detachNewThreadSelector:(SEL)selector toTarget:target withObject:argument {
	id newThread = [[self alloc] initWithTarget: target selector: selector object: argument];
	[newThread start];
	[newThread release];
}

+(NSThread *)currentThread {
   return NSPlatformCurrentThread();
}

+(NSArray *)callStackReturnAddresses {
    NSMutableArray *ret=[NSMutableArray array];

    void* callstack[128];
    int i, frameCount = backtrace(callstack, 128);
    //ignore current frame
    for (i = 1; i < frameCount; i++) {
        [ret addObject:[NSValue valueWithPointer:callstack[i]]];
    }
    
    return ret;
}

+(NSArray *)callStackSymbols {
    NSMutableArray *ret=[NSMutableArray array];
    void* callstack[128];
    int i, frameCount = backtrace(callstack, 128);
    char** symbols = backtrace_symbols(callstack, frameCount);
    //ignore current frame
    for (i = 1; i < frameCount; ++i) {
        [ret addObject:[NSString stringWithCString:symbols[i] encoding:NSISOLatin1StringEncoding]];
    }
    free(symbols);
    
    return ret;
}

+(double)threadPriority {
   NSUnimplementedMethod();
   return 0;
}

+(BOOL)setThreadPriority:(double)value {
   struct sched_param scheduling;

   value=MAX(0,MIN(value,1.0));

   int policy;

   pthread_getschedparam(pthread_self(),&policy,&scheduling);
   int min=sched_get_priority_min(policy);
   int max=sched_get_priority_min(policy);

   scheduling.sched_priority=min+(max-min)*value;

   pthread_setschedparam(pthread_self(),policy,&scheduling);

   return YES;
}

+(void)sleepUntilDate:(NSDate *)date {
   NSTimeInterval interval=[date timeIntervalSinceNow];

   NSCooperativeThreadBlocking();
   NSPlatformSleepThreadForTimeInterval(interval);
   NSCooperativeThreadWaiting();
}

+(void)sleepForTimeInterval:(NSTimeInterval)value {
   NSCooperativeThreadBlocking();
   NSPlatformSleepThreadForTimeInterval(value);
   NSCooperativeThreadWaiting();
}

+(void)exit {
   NSUnimplementedMethod();
}

-init {
   _dictionary=[NSMutableDictionary new];
   _sharedObjects=[NSMutableDictionary new];
   // if we were init'ed before didBecomeMultithreaded, we won't have a lock either
   //
   // Assigned unconditionally: _NSThreadSharedInstance() sends -[_sharedObjectLock
   // lock] on every call without a NULL guard (NSThread.m:305), and
   // class_createInstance does not zero the instance, so leaving this ivar
   // unwritten on a single-threaded boot made an unconditionally-executed path
   // read indeterminate memory.  -start carries its own lazy re-check below,
   // but it only runs when a thread is created, so the main thread never got
   // one.
   _sharedObjectLock=[NSLock new];
   return self;
}

- (void) dealloc {
	if([self isExecuting])
		[NSException raise:NSInternalInconsistencyException format:@"trying to dealloc thread %@ while it's running", self];
	[_dictionary release]; _dictionary=nil;

   id oldSharedObjects=_sharedObjects;
   _sharedObjects=nil;
	[oldSharedObjects release];

   [_sharedObjectLock release]; _sharedObjectLock=nil;
   [_name release]; _name=nil;
	[_argument release]; _argument=nil;
	[_target release]; _target=nil;
	[super dealloc];
}

-(void)start {
	[self retain]; // balanced by release in nsThreadStartThread

   if (!isMultiThreaded) {
		[[NSNotificationCenter defaultCenter] postNotificationName: NSWillBecomeMultiThreadedNotification
                                                          object: nil
                                                        userInfo: nil];
		isMultiThreaded = YES;
      // Lazily initialise mainThread's lock.  -init now assigns
      // _sharedObjectLock unconditionally, so on any current build this is
      // already non-NULL; the guard keeps the pre-existing lazy path from
      // overwriting (and leaking) a live lock, which is what the unconditional
      // assignment here used to do.
      if(!mainThread->_sharedObjectLock)
        mainThread->_sharedObjectLock=[NSLock new];
#if !defined(GCC_RUNTIME_3) && !defined(APPLE_RUNTIME_4)
		_NSInitializeSynchronizedDirective();
#endif
	}
   // if we were init'ed before didBecomeMultithreaded, we won't have a lock either
   if(!_sharedObjectLock)
      _sharedObjectLock=[NSLock new];
    NSError *error = nil;
	if (NSPlatformDetachThread( &nsThreadStartThread, self, &error) == 0) {
		// No thread has been created. Don't leak:
		[self release];
		[NSException raise: @"NSThreadCreationFailedException"
					format: @"Creation of Objective-C thread failed [%@].", error];
	}
}

-(BOOL)isMainThread {
   return self==mainThread;
}

-(BOOL)isCancelled {
	return _cancelled;
}

-(BOOL)isExecuting {
	return _executing;
}

-(BOOL)isFinished {
	return _finished;
}

-(void)cancel {
	_cancelled=YES;
}

-(NSString *)name {
	return _name;
}

-(void)setExecuting:(BOOL)executing
{
	_executing=executing;
}

-(void)setFinished:(BOOL)finished
{
	_finished=finished;
}

-(NSUInteger)stackSize {
   NSUnimplementedMethod();
   return 0;
}

-(NSMutableDictionary *)threadDictionary {
   return _dictionary;
}

-(void)setName:(NSString *)value {
	if(value!=_name)
	{
		[_name release];
		_name=[value copy];
	}
}

-(void)setStackSize:(NSUInteger)value {
   NSUnimplementedMethod();
}

/* ravynOS: one-shot capture for the WindowServer corpse.  Static-once, and a
 * single raw write(2) -- never printf.  An inline print on this path has been
 * measured to change how far dyld gets (1 image without, 265 with), so the
 * only thing emitted is the buffer, once, from this non-hot path. */
static char ravyn_capture_buf[512];
static volatile int ravyn_capture_done = 0;

static const char ravyn_hex[] = "0123456789abcdef";

static void
ravyn_put_hex16(char *dst, unsigned long x)
{
	int i;
	for (i = 15; i >= 0; i--) {
		dst[i] = ravyn_hex[x & 0xf];
		x >>= 4;
	}
}

/* ravynOS: unconditional trace helpers for GUI bring-up debugging. */
static void ravyn_trace_s(const char *s)
{
	size_t n = 0;
	while (s[n]) n++;
	(void)write(2, s, n);
}
static void ravyn_trace_hex(const char *tag, unsigned long v)
{
	char buf[96];
	char *p = buf;
	const char *s = tag;
	while (*s) *p++ = *s++;
	*p++ = '=';
	ravyn_put_hex16(p, v); p += 16;
	*p++ = '\n';
	(void)write(2, buf, (size_t)(p - buf));
}
static int ravyn_sh_trace_count = 0;
static int ravyn_sh_ret_count = 0;
void ravyn_capture_shared(const char *path, void *thread, void *shared,
	void *lock, void *result);

void
ravyn_capture_shared(const char *path, void *thread, void *shared,
    void *lock, void *result)
{
	char *p = ravyn_capture_buf;
	const char *s;
	unsigned long v;

	if (ravyn_capture_done) {
		return;
	}
	ravyn_capture_done = 1;

	s = "RNSHARE "; while (*s) { *p++ = *s++; }
	s = "path=";   while (*s) { *p++ = *s++; }
	s = path;      while (*s) { *p++ = *s++; }
	*p++ = ' ';

	s = "thread=";  while (*s) { *p++ = *s++; }
	v = (unsigned long)thread;   ravyn_put_hex16(p, v); p += 16; *p++ = ' ';

	s = "shared=";  while (*s) { *p++ = *s++; }
	v = (unsigned long)shared;   ravyn_put_hex16(p, v); p += 16; *p++ = ' ';

	s = "lock=";    while (*s) { *p++ = *s++; }
	v = (unsigned long)lock;     ravyn_put_hex16(p, v); p += 16; *p++ = ' ';

	s = "result=";  while (*s) { *p++ = *s++; }
	v = (unsigned long)result;   ravyn_put_hex16(p, v); p += 16; *p++ = ' ';

	s = "isa=";     while (*s) { *p++ = *s++; }
	v = result ? (unsigned long)*(void **)result : 0UL;
	ravyn_put_hex16(p, v); p += 16;

	*p++ = '\n';
	(void)write(2, ravyn_capture_buf, (size_t)(p - ravyn_capture_buf));
}

-(NSMutableDictionary *)sharedDictionary {
   return _sharedObjects;
}

/* Guard for the per-thread shared-object dictionary.  Statically initialised so
 * that it is valid before any Objective-C object exists -- see the comment in
 * _NSThreadSharedInstance below. */
static pthread_mutex_t _NSThreadSharedBootstrapLock = PTHREAD_MUTEX_INITIALIZER;

static inline id _NSThreadSharedInstance(NSThread *thread,NSString *className,BOOL create) {
   /* Entry capture: the exit capture at the end of this function is
    * unreachable when the fault happens inside NSPlatformCurrentThread(),
    * which re-enters Foundation during -[NSThread init].  Capture on entry
    * so at least one invocation is always reported. */
   ravyn_capture_shared("entry", (void *)thread, 0, 0, 0);
   if (ravyn_sh_trace_count < 100) {
      ravyn_sh_trace_count++;
      ravyn_trace_hex("SH-thread", (unsigned long)thread);
      ravyn_trace_hex("SH-shared", (unsigned long)thread->_sharedObjects);
   }

   NSMutableDictionary *shared=thread->_sharedObjects;
   if(!shared) {
      ravyn_trace_s("SH-nil-return\n");
      return nil;
   }
	id result=nil;
   /* ravynOS: the shared-object dictionary is guarded by a STATICALLY
    * INITIALISED pthread mutex, not by this thread's `_sharedObjectLock`.
    *
    * `_sharedObjectLock` is itself an [NSLock new], and NSLock's allocation
    * used to reach +[NSPlatform currentPlatform] -> NSThreadSharedInstance
    * -> NSPlatformCurrentThread -> [NSThread alloc] -> -[NSThread init], which
    * assigns `_sharedObjectLock`.  So any lookup arriving during thread
    * construction found the ivar still zero and had nothing usable to lock
    * with.  Measured on this tree: WindowServer faulted at `isa + 0x18` inside
    * objc_msgSend (g42-g48); reordering publication instead produced unbounded
    * recursion (g49); nil-guarding the lock produced a permanent nil lock
    * (g51).
    *
    * Upstream GNUstep solved this by never using a heap lock for thread
    * bootstrap state at all -- it guards its thread registry with
    *     static gs_mutex_t _exitingThreadsLock = GS_MUTEX_INIT_STATIC;
    * (libs-base Source/NSThread.m), a constant-initialised C mutex that needs
    * no allocation and so cannot depend on the object it protects.  This is
    * that same shape: PTHREAD_MUTEX_INITIALIZER needs no constructor call, so
    * the guard is valid from the first instruction of the process, including
    * in the middle of -[NSThread init].
    *
    * `_sharedObjectLock` is left in place for its user-facing -lock/-unlock
    * semantics; it is simply no longer on the bootstrap path. */
   pthread_mutex_lock(&_NSThreadSharedBootstrapLock);
   ravyn_trace_s("SH-locked\n");
   result=[shared objectForKey:className];
   ravyn_trace_hex("SH-lookup", (unsigned long)result);
   if(result==nil && create){
      pthread_mutex_unlock(&_NSThreadSharedBootstrapLock);
      // do not hold lock during object allocation
      result=[NSClassFromString(className) new];
   ravyn_trace_hex("SH-alloced", (unsigned long)result);
      pthread_mutex_lock(&_NSThreadSharedBootstrapLock);
      /* Another thread may have published the same class name while the
       * allocation ran without the lock held; keep whichever landed first so
       * callers see one shared instance per (thread, class). */
      id existing=[shared objectForKey:className];
      if(existing==nil){
         [shared setObject:result forKey:className];
      } else {
         [result release];
         result=existing;
      }
   }
   pthread_mutex_unlock(&_NSThreadSharedBootstrapLock);
   if (ravyn_sh_ret_count < 200) {
      ravyn_sh_ret_count++;
      ravyn_trace_hex("SH-ret", (unsigned long)result);
      const char *cn = [className cStringUsingEncoding:NSASCIIStringEncoding];
      if (cn) {
         char buf[128]; int n=0;
         buf[n++]='c'; buf[n++]='l'; buf[n++]='a'; buf[n++]='s'; buf[n++]='s';
         for (int i=0; cn[i] && n<120; i++) buf[n++]=cn[i];
         buf[n++]='\n';
         write(2, buf, (size_t)n);
      }
   } else {
      ravyn_sh_ret_count++;
   }
   ravyn_capture_shared("A/B/C", (void *)thread, (void *)shared,
       (void *)thread->_sharedObjectLock, (void *)result);

   return result;
}

FOUNDATION_EXPORT id NSThreadSharedInstance(NSString *className) {
   return _NSThreadSharedInstance(NSPlatformCurrentThread(),className,YES);
}

FOUNDATION_EXPORT id NSThreadSharedInstanceDoNotCreate(NSString *className) {
   return _NSThreadSharedInstance(NSPlatformCurrentThread(),className,NO);
}

-sharedObjectForClassName:(NSString *)className {
   return _NSThreadSharedInstance(self,className,YES);
}

-(void)setSharedObject:object forClassName:(NSString *)className {
   [_sharedObjectLock lock];
   if(object==nil)
    [_sharedObjects removeObjectForKey:className];
   else
    [_sharedObjects setObject:object forKey:className];
   [_sharedObjectLock unlock];
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@[0x%lx] threadDictionary: %@ currentPool: %@>", object_getClass(self), self, _dictionary, _currentPool];
}

NSAutoreleasePool *NSThreadCurrentPool(void) {
   return NSPlatformCurrentThread()->_currentPool;
}

void NSThreadSetCurrentPool(NSAutoreleasePool *pool){
   NSPlatformCurrentThread()->_currentPool=pool;
}

@end

@implementation NSObject(NSThread)

-(void)_performSelectorOnThreadHelper:(NSArray*)selectorAndArguments {
   NSConditionLock *waitingLock=[selectorAndArguments objectAtIndex:0];
   SEL              selector=NSSelectorFromString([selectorAndArguments objectAtIndex:1]);
   id               object=[[selectorAndArguments objectAtIndex:2] pointerValue];

   [waitingLock lockWhenCondition:0];

   [self performSelector:selector withObject:object];

   [waitingLock unlockWithCondition:1];
   [selectorAndArguments release];
}

- (void)performSelector:(SEL)selector onThread:(NSThread *)thread withObject:(id)object waitUntilDone:(BOOL)waitUntilDone modes:(NSArray *)modes
{
   if(thread==nil){
    [NSException raise:NSInvalidArgumentException format:@"Thread is nil"];
    return;
   }
	id runloop=_NSThreadSharedInstance(thread, @"NSRunLoop", NO);
	if(waitUntilDone)
	{
		if(thread==[NSThread currentThread])
		{
			[self performSelector:selector withObject:object];
		}
		else
		{
			if(!runloop)
				[NSException raise:NSInvalidArgumentException format:@"thread %@ has no runloop in %@", thread, NSStringFromSelector(_cmd)];
			NSConditionLock *waitingLock=[[NSConditionLock alloc] initWithCondition:0];

         // array retain balanced in _performSelectorOnThreadHelper:
			[runloop performSelector:@selector(_performSelectorOnThreadHelper:)
							  target:self
							argument:[[NSArray arrayWithObjects:waitingLock, NSStringFromSelector(selector), [NSValue valueWithPointer:object], nil] retain]
							   order:0
							   modes:modes];

			[waitingLock lockWhenCondition:1];
			[waitingLock unlock];
			[waitingLock release];
		}
	}
	else
	{
		if(!runloop)
			[NSException raise:NSInvalidArgumentException format:@"thread %@ has no runloop in %@", thread, NSStringFromSelector(_cmd)];

		[runloop performSelector:selector target:self argument:object order:0 modes:modes];
	}
}

- (void)performSelector:(SEL)selector onThread:(NSThread *)thread withObject:(id)object waitUntilDone:(BOOL)waitUntilDone
{
	[self performSelector:selector onThread:thread withObject:object waitUntilDone:waitUntilDone modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
}

-(void)performSelectorOnMainThread:(SEL)selector withObject:(id)object waitUntilDone:(BOOL)waitUntilDone modes:(NSArray *)modes {
	[self performSelector:selector onThread:[NSThread mainThread] withObject:object waitUntilDone:waitUntilDone modes:modes];
}

-(void)performSelectorOnMainThread:(SEL)selector withObject:(id)object waitUntilDone:(BOOL)waitUntilDone {
	[self performSelectorOnMainThread:selector withObject:object waitUntilDone:waitUntilDone modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
}

-(void)performSelectorInBackground:(SEL)selector withObject:object {
	[NSThread detachNewThreadSelector:selector toTarget:self withObject:object];
}

@end

FOUNDATION_EXPORT NSThread *NSCurrentThread(void) {
   return NSPlatformCurrentThread();
}

