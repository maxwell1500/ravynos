/* iig(DriverKit-254 Oct 18 2022 12:24:09) generated from IOWorkGroup.iig */

#undef	IIG_IMPLEMENTATION
#define	IIG_IMPLEMENTATION 	IOWorkGroup.iig

#if KERNEL
#include <libkern/c++/OSString.h>
#else
#include <DriverKit/DriverKit.h>
#endif /* KERNEL */
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOWorkGroup.h>

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
OSDefineMetaClassAndStructors(IOWorkGroup, OSObject);
#endif /* KERNEL */

#if !KERNEL

#define IOWorkGroup_QueueNames  ""
#define IOWorkGroup_MethodNames  ""
#define IOWorkGroupMetaClass_MethodNames  ""

struct OSClassDescription_IOWorkGroup_t
{
    OSClassDescription base;
    uint64_t           methodOptions[2 * 0];
    uint64_t           metaMethodOptions[2 * 0];
    char               queueNames[sizeof(IOWorkGroup_QueueNames)];
    char               methodNames[sizeof(IOWorkGroup_MethodNames)];
    char               metaMethodNames[sizeof(IOWorkGroupMetaClass_MethodNames)];
};

const struct OSClassDescription_IOWorkGroup_t
OSClassDescription_IOWorkGroup =
{
    .base =
    {
        .descriptionSize         = sizeof(OSClassDescription_IOWorkGroup_t),
        .name                    = "IOWorkGroup",
        .superName               = "OSObject",
        .methodOptionsSize       = 2 * sizeof(uint64_t) * 0,
        .methodOptionsOffset     = __builtin_offsetof(struct OSClassDescription_IOWorkGroup_t, methodOptions),
        .metaMethodOptionsSize   = 2 * sizeof(uint64_t) * 0,
        .metaMethodOptionsOffset = __builtin_offsetof(struct OSClassDescription_IOWorkGroup_t, metaMethodOptions),
        .queueNamesSize       = sizeof(IOWorkGroup_QueueNames),
        .queueNamesOffset     = __builtin_offsetof(struct OSClassDescription_IOWorkGroup_t, queueNames),
        .methodNamesSize         = sizeof(IOWorkGroup_MethodNames),
        .methodNamesOffset       = __builtin_offsetof(struct OSClassDescription_IOWorkGroup_t, methodNames),
        .metaMethodNamesSize     = sizeof(IOWorkGroupMetaClass_MethodNames),
        .metaMethodNamesOffset   = __builtin_offsetof(struct OSClassDescription_IOWorkGroup_t, metaMethodNames),
        .flags                   = 1*kOSClassCanRemote,
    },
    .methodOptions = {},
    .metaMethodOptions = {},
    .queueNames      = IOWorkGroup_QueueNames,
    .methodNames     = IOWorkGroup_MethodNames,
    .metaMethodNames = IOWorkGroupMetaClass_MethodNames,
};

OSMetaClass * gIOWorkGroupMetaClass;

static kern_return_t
IOWorkGroup_New(OSMetaClass * instance);

const OSClassLoadInformation
IOWorkGroup_Class =
{
    .description       = &OSClassDescription_IOWorkGroup.base,
    .metaPointer       = &gIOWorkGroupMetaClass,
    .version           = 1,
    .instanceSize      = sizeof(IOWorkGroup),
    .New               = &IOWorkGroup_New,
};

extern const void * const
gIOWorkGroup_Declaration;
const void * const
gIOWorkGroup_Declaration
__attribute__((visibility("hidden"),section("__DATA_CONST,__osclassinfo,regular,no_dead_strip"),no_sanitize("address")))
    = &IOWorkGroup_Class;

static kern_return_t
IOWorkGroup_New(OSMetaClass * instance)
{
    if (!new(instance) IOWorkGroupMetaClass) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

kern_return_t
IOWorkGroupMetaClass::New(OSObject * instance)
{
    if (!new(instance) IOWorkGroup) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

#endif /* !KERNEL */

kern_return_t
IOWorkGroup::Dispatch(const IORPC rpc)
{
    return _Dispatch(this, rpc);
}

kern_return_t
IOWorkGroup::_Dispatch(IOWorkGroup * self, const IORPC rpc)
{
    kern_return_t ret = kIOReturnUnsupported;
    IORPCMessage * msg = IORPCMessageFromMach(rpc.message, false);

    switch (msg->msgid)
    {
#if KERNEL
        case IOWorkGroup_InvalidateKernel_ID:
        {
            ret = IOWorkGroup::InvalidateKernel_Invoke(rpc, self, SimpleMemberFunctionCast(IOWorkGroup::InvalidateKernel_Handler, *self, &IOWorkGroup::InvalidateKernel_Impl));
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
IOWorkGroup::MetaClass::Dispatch(const IORPC rpc)
{
#else /* KERNEL */
kern_return_t
IOWorkGroupMetaClass::Dispatch(const IORPC rpc)
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
