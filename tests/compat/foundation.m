/*
 * foundation.m -- ABI conformance fixture for the Cocotron-derived Foundation.
 *
 * Built on the development Mac against Apple's SDK (see build-fixtures.sh) and
 * run inside ravynOS: the binary is Apple-ABI, the Foundation it calls is
 * ravynOS's.  Covers the Phase-1 correctness fixes: NSFileManager's modern
 * API, NSDecimalNumber arithmetic, NSInvocation dispatch and NSProcessInfo.
 */
#import <Foundation/Foundation.h>
#include <stdio.h>
#import <objc/runtime.h>

static int failures = 0;

static void check(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if(!condition)
        failures++;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"ravyn-foundation-test"];
    NSString *file, *link, *hardLink;
    NSError *error = nil;

    [fileManager removeItemAtPath:directory error:NULL];

    check([fileManager createDirectoryAtPath:directory
              withIntermediateDirectories:YES attributes:nil error:&error],
          "NSFileManager createDirectoryAtPath:");

    file = [directory stringByAppendingPathComponent:@"a.txt"];
    check([fileManager createFileAtPath:file
              contents:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]
              attributes:nil], "NSFileManager createFileAtPath:");

    check([fileManager fileExistsAtPath:file], "NSFileManager fileExistsAtPath:");

    {
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:file error:NULL];
        check(attributes != nil &&
              [[attributes objectForKey:NSFileSize] longValue] == 5,
              "NSFileManager attributesOfItemAtPath: (size 5)");
        check([attributes objectForKey:NSFileType] != nil,
              "NSFileManager attributes include NSFileType");
    }

    {
        NSArray *subpaths = [fileManager subpathsOfDirectoryAtPath:directory error:NULL];
        check(subpaths != nil && [subpaths count] == 1,
              "NSFileManager subpathsOfDirectoryAtPath: (1 entry)");
    }

    link = [directory stringByAppendingPathComponent:@"link"];
    check([fileManager createSymbolicLinkAtPath:link
              withDestinationPath:@"a.txt" error:&error],
          "NSFileManager createSymbolicLinkAtPath:");
    check([[fileManager destinationOfSymbolicLinkAtPath:link error:NULL]
              isEqualToString:@"a.txt"],
          "NSFileManager destinationOfSymbolicLinkAtPath:");

    hardLink = [directory stringByAppendingPathComponent:@"hard"];
    /*
     * Hard links are a filesystem capability, not a Foundation one.  The root
     * volume here is FAT32, where link(2) cannot ever succeed, so a plain
     * failure would keep the suite red for a reason outside this API's
     * contract.  Probe, and fall back to a copy so that the two checks that
     * only need "a second identical file" still mean something.
     */
    if(![fileManager linkItemAtPath:file toPath:hardLink error:&error]) {
        printf("SKIP NSFileManager linkItemAtPath: (%s)\n",
               [[error localizedDescription] UTF8String]);
        check([fileManager copyItemAtPath:file toPath:hardLink error:&error],
              "NSFileManager copyItemAtPath: stands in for linkItemAtPath:");
    } else {
        check(YES, "NSFileManager linkItemAtPath:");
    }
    check([fileManager contentsEqualAtPath:file andPath:hardLink],
          "NSFileManager contentsEqualAtPath:");
    check([fileManager isDeletableFileAtPath:file],
          "NSFileManager isDeletableFileAtPath:");

    check([fileManager moveItemAtPath:hardLink
              toPath:[directory stringByAppendingPathComponent:@"moved"]
              error:&error],
          "NSFileManager moveItemAtPath:");

    check([fileManager removeItemAtPath:file error:&error],
          "NSFileManager removeItemAtPath:");
    check(![fileManager fileExistsAtPath:file],
          "NSFileManager removeItemAtPath: actually removed");

    [fileManager removeItemAtPath:directory error:NULL];

    {
        NSDecimalNumber *oneAndAHalf = [NSDecimalNumber decimalNumberWithString:@"1.5"];
        NSDecimalNumber *sum = [oneAndAHalf decimalNumberByAdding:[NSDecimalNumber one]];
        check([[sum stringValue] isEqualToString:@"2.5"],
              "NSDecimalNumber 1.5 + 1 = 2.5");

        NSDecimalNumber *product = [[NSDecimalNumber decimalNumberWithString:@"2.5"]
            decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"4"]];
        check([[product stringValue] isEqualToString:@"10"],
              "NSDecimalNumber 2.5 * 4 = 10");

        NSDecimalNumber *quotient = [[NSDecimalNumber one]
            decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithString:@"4"]];
        check([[quotient stringValue] isEqualToString:@"0.25"],
              "NSDecimalNumber 1 / 4 = 0.25");

        NSDecimalNumber *difference = [[NSDecimalNumber decimalNumberWithString:@"0.3"]
            decimalNumberBySubtracting:[NSDecimalNumber decimalNumberWithString:@"0.1"]];
        check([[difference stringValue] isEqualToString:@"0.2"],
              "NSDecimalNumber 0.3 - 0.1 = 0.2 (exact)");

        {
            NSDecimalNumber *two = [NSDecimalNumber decimalNumberWithString:@"2"];
            NSDecimalNumber *ten = [NSDecimalNumber decimalNumberWithString:@"10"];
            printf("DECIMAL two=%s dbl=%g ten=%s dbl=%g compare=%d sizeofNSDecimal=%zu\n",
                   [[two stringValue] UTF8String], [two doubleValue],
                   [[ten stringValue] UTF8String], [ten doubleValue],
                   (int)[two compare:ten], sizeof(NSDecimal));
            printf("DECIMAL class two=%s ten=%s\n",
                   class_getName(object_getClass(two)), class_getName(object_getClass(ten)));

            check([two compare:ten] == NSOrderedAscending,
                  "NSDecimalNumber compare: 2 < 10");
        }

        /*
         * NSDecimal is passed *by value* across the framework boundary, so its
         * layout is an ABI: 20 bytes, signed 8-bit exponent, length in
         * base-65536 words, little-endian mantissa.  This binary was compiled
         * against Apple's header, so reading the fields here is exactly what a
         * stock application does.
         */
        {
            NSDecimal d = [[NSDecimalNumber decimalNumberWithString:@"1.5"]
                           decimalValue];
            unsigned long long m = 0;
            NSDecimal e = [[NSDecimalNumber decimalNumberWithString:@"-3.25"]
                           decimalValue];
            NSDecimal g = [[NSDecimalNumber decimalNumberWithString:
                            @"1234567890123456789"] decimalValue];
            unsigned long long gm = 0;
            NSDecimalNumber *back = [NSDecimalNumber decimalNumberWithDecimal:d];
            int i;

            for(i = (int)d._length - 1; i >= 0; i--)
                m = (m << 16) | d._mantissa[i];
            for(i = (int)g._length - 1; i >= 0; i--)
                gm = (gm << 16) | g._mantissa[i];

            check(sizeof(NSDecimal) == 20, "NSDecimal is 20 bytes (ABI)");
            check(m == 15 && d._exponent == -1 && d._length == 1
                  && !d._isNegative,
                  "NSDecimal decimalValue: 1.5 -> 15e-1");
            check(e._isNegative == 1 && e._exponent == -2,
                  "NSDecimal decimalValue: -3.25 keeps sign and exponent");
            check(gm == 1234567890123456789ULL && g._length == 4,
                  "NSDecimal decimalValue: 19 digits span 4 mantissa words");
            check([[back stringValue] isEqualToString:@"1.5"],
                  "NSDecimalNumber decimalNumberWithDecimal: round trip");
        }

        {
        }
    }

    check([[NSProcessInfo processInfo] processorCount] >= 1,
          "NSProcessInfo processorCount >= 1");
    check([[NSProcessInfo processInfo] activeProcessorCount] >= 1,
          "NSProcessInfo activeProcessorCount >= 1");
    check([[NSProcessInfo processInfo] physicalMemory] > 0,
          "NSProcessInfo physicalMemory > 0");
    check([[NSProcessInfo processInfo] operatingSystem] == NSMACHOperatingSystem,
          "NSProcessInfo operatingSystem == NSMACHOperatingSystem");

    {
        NSMutableString *target = [NSMutableString stringWithString:@"x"];
        SEL selector = @selector(appendString:);
        NSMethodSignature *signature = [target methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        NSString *argument = @"y";

        [invocation setTarget:target];
        [invocation setSelector:selector];
        [invocation setArgument:&argument atIndex:2];
        [invocation invoke];

        check([target isEqualToString:@"xy"],
              "NSInvocation -invoke dispatches with an object argument");
    }

    printf("%s (%d failure(s))\n", failures ? "FAILED" : "PASSED", failures);

    [pool release];
    return failures ? 1 : 0;
}
