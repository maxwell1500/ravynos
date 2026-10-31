#ifndef _NS_PRIVATE_DECLS_H
#define _NS_PRIVATE_DECLS_H

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#ifndef CF_CLASSIMPLEMENTATION
#define CF_CLASSIMPLEMENTATION(className) \
- (id)retain { return (id)CFRetain((CFTypeRef)self); } \
- (oneway void)release { CFRelease((CFTypeRef)self); } \
- (NSUInteger)retainCount { return (NSUInteger)CFGetRetainCount((CFTypeRef)self); }
#endif

#ifndef NSMakeCollectable
#define NSMakeCollectable(cf) ((id)CFMakeCollectable((CFTypeRef)(cf)))
#endif

#ifndef NSRequestConcreteImplementation
#define NSRequestConcreteImplementation(self, _cmd, cls) do {} while(0)
#endif

#ifndef NS_DEPRECATED_MAC
#define NS_DEPRECATED_MAC(...)
#endif

#ifndef NS_AVAILABLE_MAC
#define NS_AVAILABLE_MAC(...)
#endif

#endif /* _NS_PRIVATE_DECLS_H */
