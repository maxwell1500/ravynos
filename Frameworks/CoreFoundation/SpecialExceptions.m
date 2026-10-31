/*
 * NSException's exception-handling type, exported from CoreFoundation.
 *
 * XUL's two-level binding names CoreFoundation for
 * _OBJC_EHTYPE_$_NSException even though the NSException class lives in
 * Foundation, and dyld refuses to load the application when the named
 * library does not export it:
 *
 *   Symbol not found: _OBJC_EHTYPE_$_NSException
 *   Expected in: /System/Library/Frameworks/CoreFoundation.framework/...
 *
 * The compiler emits an EH type into the image that contains a @catch for the
 * class, so this translation unit exists to produce one in CoreFoundation.
 * It must be a real EH type: a bare data symbol would let dyld load the
 * application but break @catch matching.  The class reference is weak so
 * CoreFoundation can still load before Foundation is present.
 */
#import <objc/objc.h>

/*
 * Forward declaration only: the class object is Foundation's.  Marked as a
 * root class because this translation unit has no NSObject declaration, and
 * weak because CoreFoundation loads before Foundation.
 */
__attribute__((objc_root_class))
__attribute__((weak_import))
@interface NSException
@end

void
__CFNSExceptionEHTypeAnchor(void)
{
    @try {
        /* Nothing is thrown here; the clause exists for the EH type. */
    } @catch (NSException *e) {
        (void)e;
    }
}
