#import <Foundation/Foundation.h>

void test_CFBridgingRetain(void) {
    NSLog(@"--- test_CFBridgingRetain ---");

    @autoreleasepool {
        id obj = [[NSMutableString alloc] initWithString:@"Hello"];
        NSLog(@"Original ObjC object: %@", obj);

        CFTypeRef cf = CFBridgingRetain(obj);
        NSLog(@"CF object pointer:   %p", cf);
        NSLog(@"ObjC object pointer: %p", obj);

        if ((void *)cf == (void *)obj) {
            NSLog(@"Pointers match — toll‑free bridging OK");
        } else {
            NSLog(@"ERROR: pointers differ!");
        }
        
        CFRelease(cf);
        NSLog(@"Released CF object");
    }

    NSLog(@"--- end test_CFBridgingRetain ---");
}

void test_CFBridgingRelease(void) {
    NSLog(@"--- test_CFBridgingRelease ---");

    @autoreleasepool {
        // Create a CF object with +1 ownership
        CFStringRef cf = CFStringCreateWithCString(
            kCFAllocatorDefault,
            "Hello from CF",
            kCFStringEncodingUTF8
        );

        NSLog(@"Created CFStringRef: %p", cf);

        id obj = CFBridgingRelease(cf);

        NSLog(@"Bridged ObjC object: %@", obj);
        if ([obj isKindOfClass:[NSString class]]) {
            NSLog(@"It is an NSString under ARC");
        } else {
            NSLog(@"ERROR: unexpected type");
        }
    }

    NSLog(@"--- end test_CFBridgingRelease ---");
}

int main(void) {
    test_CFBridgingRetain();
    test_CFBridgingRelease();
    return 0;
}
