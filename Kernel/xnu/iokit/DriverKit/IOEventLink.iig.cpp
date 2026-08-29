/* iig(DriverKit-254 Oct 18 2022 12:24:09) generated from IOEventLink.iig */

#undef	IIG_IMPLEMENTATION
#define	IIG_IMPLEMENTATION 	IOEventLink.iig

#if KERNEL
#include <libkern/c++/OSString.h>
#else
#include <DriverKit/DriverKit.h>
#endif /* KERNEL */
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOEventLink.h>

#if __has_builtin(__builtin_load_member_function_pointer)
#define SimpleMemberFunctionCast(cfnty, self, func) (cfnty)__builtin_load_member_function_pointer(self, func)
#else
#define SimpleMemberFunctionCast(cfnty, self, func) ({ union { typeof(func) memfun; cfnty cfun; } pair; pair.memfun = func; pair.cfun; })
#endif


#if !KERNEL
extern OSMetaClass * gOSContainerMetaClass;
extern OSMetaClass * gOSDataMetaClass;
extern OSMetaClass * gOSNumberMetaClass;
extern OSMetaClass * gOSStringMetaClass;
extern OSMetaClass * gOSBooleanMetaClass;
extern OSMetaClass * gOSDictionaryMetaClass;
extern OSMetaClass * gOSArrayMetaClass;
extern OSMetaClass * gIOUserClientMetaClass;
#endif /* !KERNEL */

#if KERNEL
OSDefineMetaClassAndStructors(IOEventLink, OSObject);
#endif /* KERNEL */

#if !KERNEL

#define IOEventLink_QueueNames  ""
#define IOEventLink_MethodNames  ""
#define IOEventLinkMetaClass_MethodNames  ""

struct OSClassDescription_IOEventLink_t
{
    OSClassDescription base;
    uint64_t           methodOptions[2 * 0];
    uint64_t           metaMethodOptions[2 * 0];
    char               queueNames[sizeof(IOEventLink_QueueNames)];
    char               methodNames[sizeof(IOEventLink_MethodNames)];
    char               metaMethodNames[sizeof(IOEventLinkMetaClass_MethodNames)];
};

const struct OSClassDescription_IOEventLink_t
OSClassDescription_IOEventLink =
{
    .base =
    {
        .descriptionSize         = sizeof(OSClassDescription_IOEventLink_t),
        .name                    = "IOEventLink",
        .superName               = "OSObject",
        .methodOptionsSize       = 2 * sizeof(uint64_t) * 0,
        .methodOptionsOffset     = __builtin_offsetof(struct OSClassDescription_IOEventLink_t, methodOptions),
        .metaMethodOptionsSize   = 2 * sizeof(uint64_t) * 0,
        .metaMethodOptionsOffset = __builtin_offsetof(struct OSClassDescription_IOEventLink_t, metaMethodOptions),
        .queueNamesSize       = sizeof(IOEventLink_QueueNames),
        .queueNamesOffset     = __builtin_offsetof(struct OSClassDescription_IOEventLink_t, queueNames),
        .methodNamesSize         = sizeof(IOEventLink_MethodNames),
        .methodNamesOffset       = __builtin_offsetof(struct OSClassDescription_IOEventLink_t, methodNames),
        .metaMethodNamesSize     = sizeof(IOEventLinkMetaClass_MethodNames),
        .metaMethodNamesOffset   = __builtin_offsetof(struct OSClassDescription_IOEventLink_t, metaMethodNames),
        .flags                   = 1*kOSClassCanRemote,
    },
    .methodOptions = {},
    .metaMethodOptions = {},
    .queueNames      = IOEventLink_QueueNames,
    .methodNames     = IOEventLink_MethodNames,
    .metaMethodNames = IOEventLinkMetaClass_MethodNames,
};

OSMetaClass * gIOEventLinkMetaClass;

static kern_return_t
IOEventLink_New(OSMetaClass * instance);

const OSClassLoadInformation
IOEventLink_Class =
{
    .description       = &OSClassDescription_IOEventLink.base,
    .metaPointer       = &gIOEventLinkMetaClass,
    .version           = 1,
    .instanceSize      = sizeof(IOEventLink),
    .New               = &IOEventLink_New,
};

extern const void * const
gIOEventLink_Declaration;
const void * const
gIOEventLink_Declaration
__attribute__((visibility("hidden"),section("__DATA_CONST,__osclassinfo,regular,no_dead_strip"),no_sanitize("address")))
    = &IOEventLink_Class;

static kern_return_t
IOEventLink_New(OSMetaClass * instance)
{
    if (!new(instance) IOEventLinkMetaClass) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

kern_return_t
IOEventLinkMetaClass::New(OSObject * instance)
{
    if (!new(instance) IOEventLink) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

#endif /* !KERNEL */

kern_return_t
IOEventLink::Dispatch(const IORPC rpc)
{
    return _Dispatch(this, rpc);
}

kern_return_t
IOEventLink::_Dispatch(IOEventLink * self, const IORPC rpc)
{
    kern_return_t ret = kIOReturnUnsupported;
    IORPCMessage * msg = IORPCMessageFromMach(rpc.message, false);

    switch (msg->msgid)
    {
#if KERNEL
        case IOEventLink_InvalidateKernel_ID:
        {
            ret = IOEventLink::InvalidateKernel_Invoke(rpc, self, SimpleMemberFunctionCast(IOEventLink::InvalidateKernel_Handler, *self, &IOEventLink::InvalidateKernel_Impl));
            break;
        }
#endif /* !KERNEL */

        default:
            ret = OSObject::_Dispatch(self, rpc);
            break;
    }

    return (ret);
}

#if KERNEL
kern_return_t
IOEventLink::MetaClass::Dispatch(const IORPC rpc)
{
#else /* KERNEL */
kern_return_t
IOEventLinkMetaClass::Dispatch(const IORPC rpc)
{
#endif /* !KERNEL */

    kern_return_t ret = kIOReturnUnsupported;
    IORPCMessage * msg = IORPCMessageFromMach(rpc.message, false);

    switch (msg->msgid)
    {
        default:
            ret = OSMetaClassBase::Dispatch(rpc);
            break;
    }

    return (ret);
}
