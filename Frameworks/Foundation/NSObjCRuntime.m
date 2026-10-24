/* Copyright (c) 2006-2008 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSStringFormatter.h>
#import <Foundation/NSStringUTF8.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSPlatform.h>
#import <Foundation/NSAutoreleasePool-private.h>
#import <Foundation/NSString.h>

#import "NSString/NSString_cString.h"

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

typedef void (*NSLogCStringFunc)(const char *string, unsigned length, BOOL withSyslogBanner);

// These are private-yet-sort-of-documented in Cocoa.
FOUNDATION_EXPORT NSLogCStringFunc _NSLogCStringFunction(void);
FOUNDATION_EXPORT void _NSSetLogCStringFunction(NSLogCStringFunc proc);

static void NSLogDefaultCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner);

static NSLogCStringFunc sNSLogCString = NSLogDefaultCStringFunction;


static void NSLogFormat(NSString *format,...) {
   NSString *string;
   va_list   arguments;

   va_start(arguments,format);
   string=NSStringNewWithFormat(format,nil,arguments,NULL);
   va_end(arguments);

   NSPlatformLogString(string);

   [string release];
}

/* Append one line to /var/log/system.log with raw POSIX calls.
 *
 * Deliberately no Foundation objects in here: NSLog is called from message-
 * formatting and allocation paths, and an NSLog that allocates can re-enter
 * itself (a formatter or file manager that logs).  The thread-local guard
 * makes that a no-op instead of unbounded recursion, and gettimeofday +
 * localtime_r + snprintf keep the whole path allocation-free. */
static void NSLogAppendToSystemLog(const char *string, unsigned length) {
   static __thread int inLog = 0;
   struct timeval tv;
   struct tm tm;
   time_t secs;
   char prefix[128];
   char line[1200];
   int plen, total;
   int fd;

   if(inLog)
      return;
   inLog = 1;

   gettimeofday(&tv, NULL);
   secs = tv.tv_sec;
   localtime_r(&secs, &tm);
   plen = snprintf(prefix, sizeof(prefix),
       "%04d-%02d-%02d %02d:%02d:%02d.%03d %s[%d] <Default>: ",
       tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
       tm.tm_hour, tm.tm_min, tm.tm_sec, (int)(tv.tv_usec / 1000),
       [[[NSProcessInfo processInfo] processName] UTF8String],
       (int)getpid());

   if(plen > 0 && (unsigned)plen < sizeof(prefix)) {
      if(length > sizeof(line) - (unsigned)plen - 2)
         length = (unsigned)(sizeof(line) - (unsigned)plen - 2);
      memcpy(line, prefix, (size_t)plen);
      memcpy(line + plen, string, length);
      total = plen + (int)length;
      line[total++] = '\n';

      mkdir("/var/log", 0755);
      fd = open("/var/log/system.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
      if(fd >= 0) {
         ssize_t written = 0;
         while(written < total) {
            ssize_t n = write(fd, line + written, (size_t)(total - written));
            if(n <= 0)
               break;
            written += n;
         }
         close(fd);
      }
   }

   inLog = 0;
}

static void NSLogDefaultCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner) {
   NSString *message = [[NSString alloc] initWithBytes:string length:length encoding:[NSString defaultCStringEncoding]];
   if (withSyslogBanner)
   {
      NSLogFormat(@"%s", string);
      NSLogAppendToSystemLog(string, length);
   }
   else
   {
      NSPlatformLogString(message);
   }
   [message release];
}

void NSLogv(NSString *format,va_list arguments) {
   NSString *string=NSStringNewWithFormat(format,nil,arguments,NULL);

   NSUInteger length=[string length],byteLength;
   unichar  unicode[length];
   char    *bytes;

   [string getCharacters:unicode];
   bytes=NSString_cStringFromCharacters(unicode,length,YES,&byteLength,NULL,NO);
   [string release];
   if (bytes == NULL) return;

   sNSLogCString(bytes,byteLength,YES);
   NSZoneFree(NULL,bytes);
}

void NSLog(NSString *format,...) {
   va_list arguments;

   va_start(arguments,format);
   NSLogv(format,arguments);
   va_end(arguments);
}

NSLogCStringFunc _NSLogCStringFunction(void)
{
   return sNSLogCString;
}

void _NSSetLogCStringFunction(NSLogCStringFunc proc)
{
   sNSLogCString=proc?proc:NSLogDefaultCStringFunction;
}


const char *NSGetSizeAndAlignment(const char *type, NSUInteger *size, NSUInteger *alignment)
{
    NSUInteger ignore = 0;
    if (!size) {
        size = &ignore;
    }
    if (!alignment) {
        alignment = &ignore;
    }

    *size = 0;
    *alignment = 0;

    *size = objc_ext_sizeof_type(type);
    *alignment = objc_ext_alignof_type(type);
    return objc_ext_skip_type_specifier(type, NO);
}


SEL NSSelectorFromString(NSString *selectorName) {
   NSUInteger length=[selectorName length];
   char     cString[length+1];

   [selectorName getCString:cString maxLength:length+1 encoding:NSASCIIStringEncoding];

   return sel_getUid(cString);
}

NSString *NSStringFromSelector(SEL selector) {
   if(selector==NULL)
    return @"";

    const char *name = sel_getName(selector);
    return NSAutorelease(NSString_anyCStringNewWithBytes(NSASCIIStringEncoding, NULL,name, strlen(name)));
}

Class NSClassFromString(NSString *className) {
   if (className != nil) {
    NSUInteger length=[className length];
    char     cString[length+1];

    [className getCString:cString maxLength:length+1 encoding:NSASCIIStringEncoding];

    return objc_lookUpClass(cString);
   }
   else
    return nil;
}

NSString *NSStringFromClass(Class class) {
   if(class==Nil)
    return nil;

    const char *name = class_getName(class);
    return NSAutorelease(NSString_anyCStringNewWithBytes(NSASCIIStringEncoding, NULL,name, strlen(name)));
}
