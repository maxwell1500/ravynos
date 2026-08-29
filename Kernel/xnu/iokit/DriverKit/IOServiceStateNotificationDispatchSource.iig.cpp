/* iig(DriverKit-254 Oct 18 2022 12:24:09) generated from IOServiceStateNotificationDispatchSource.iig */

#undef	IIG_IMPLEMENTATION
#define	IIG_IMPLEMENTATION 	IOServiceStateNotificationDispatchSource.iig

#if KERNEL
#include <libkern/c++/OSString.h>
#else
#include <DriverKit/DriverKit.h>
#endif /* KERNEL */
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOServiceStateNotificationDispatchSource.h>

#if __has_builtin(__builtin_load_member_function_pointer)
#define SimpleMemberFunctionCast(cfnty, self, func) (cfnty)__builtin_load_member_function_pointer(self, func)
#else
#define SimpleMemberFunctionCast(cfnty, self, func) ({ union { typeof(func) memfun; cfnty cfun; } pair; pair.memfun = func; pair.cfun; })
#endif


struct IOServiceStateNotificationDispatchSource_SetHandler_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
    OSObjectRef  action;
};
#pragma pack(4)
struct IOServiceStateNotificationDispatchSource_SetHandler_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    mach_msg_port_descriptor_t action__descriptor;
    IOServiceStateNotificationDispatchSource_SetHandler_Msg_Content content;
};
#pragma pack()
#define IOServiceStateNotificationDispatchSource_SetHandler_Msg_ObjRefs (2)

struct IOServiceStateNotificationDispatchSource_SetHandler_Rpl_Content
{
    IORPCMessage __hdr;
};
#pragma pack(4)
struct IOServiceStateNotificationDispatchSource_SetHandler_Rpl
{
    IORPCMessageMach           mach;
    IOServiceStateNotificationDispatchSource_SetHandler_Rpl_Content content;
};
#pragma pack()
#define IOServiceStateNotificationDispatchSource_SetHandler_Rpl_ObjRefs (0)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOServiceStateNotificationDispatchSource_SetHandler_Msg * message;
        struct IOServiceStateNotificationDispatchSource_SetHandler_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOServiceStateNotificationDispatchSource_SetHandler_Invocation;

struct IOServiceStateNotificationDispatchSource_StateNotificationBegin_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
};
#pragma pack(4)
struct IOServiceStateNotificationDispatchSource_StateNotificationBegin_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    IOServiceStateNotificationDispatchSource_StateNotificationBegin_Msg_Content content;
};
#pragma pack()
#define IOServiceStateNotificationDispatchSource_StateNotificationBegin_Msg_ObjRefs (1)

struct IOServiceStateNotificationDispatchSource_StateNotificationBegin_Rpl_Content
{
    IORPCMessage __hdr;
};
#pragma pack(4)
struct IOServiceStateNotificationDispatchSource_StateNotificationBegin_Rpl
{
    IORPCMessageMach           mach;
    IOServiceStateNotificationDispatchSource_StateNotificationBegin_Rpl_Content content;
};
#pragma pack()
#define IOServiceStateNotificationDispatchSource_StateNotificationBegin_Rpl_ObjRefs (0)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOServiceStateNotificationDispatchSource_StateNotificationBegin_Msg * message;
        struct IOServiceStateNotificationDispatchSource_StateNotificationBegin_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOServiceStateNotificationDispatchSource_StateNotificationBegin_Invocation;

#if !KERNEL
extern OSMetaClass * gOSContainerMetaClass;
extern OSMetaClass * gOSDataMetaClass;
extern OSMetaClass * gOSNumberMetaClass;
extern OSMetaClass * gOSStringMetaClass;
extern OSMetaClass * gOSBooleanMetaClass;
extern OSMetaClass * gOSDictionaryMetaClass;
extern OSMetaClass * gOSArrayMetaClass;
extern OSMetaClass * gIODispatchSourceMetaClass;
extern OSMetaClass * gIOServiceMetaClass;
extern OSMetaClass * gIODispatchQueueMetaClass;
#endif /* !KERNEL */

#if KERNEL
OSDefineMetaClassAndStructors(IOServiceStateNotificationDispatchSource, IODispatchSource);
#endif /* KERNEL */

#if !KERNEL

#define IOServiceStateNotificationDispatchSource_QueueNames  ""
#define IOServiceStateNotificationDispatchSource_MethodNames  ""
#define IOServiceStateNotificationDispatchSourceMetaClass_MethodNames  ""

struct OSClassDescription_IOServiceStateNotificationDispatchSource_t
{
    OSClassDescription base;
    uint64_t           methodOptions[2 * 0];
    uint64_t           metaMethodOptions[2 * 0];
    char               queueNames[sizeof(IOServiceStateNotificationDispatchSource_QueueNames)];
    char               methodNames[sizeof(IOServiceStateNotificationDispatchSource_MethodNames)];
    char               metaMethodNames[sizeof(IOServiceStateNotificationDispatchSourceMetaClass_MethodNames)];
};

const struct OSClassDescription_IOServiceStateNotificationDispatchSource_t
OSClassDescription_IOServiceStateNotificationDispatchSource =
{
    .base =
    {
        .descriptionSize         = sizeof(OSClassDescription_IOServiceStateNotificationDispatchSource_t),
        .name                    = "IOServiceStateNotificationDispatchSource",
        .superName               = "IODispatchSource",
        .methodOptionsSize       = 2 * sizeof(uint64_t) * 0,
        .methodOptionsOffset     = __builtin_offsetof(struct OSClassDescription_IOServiceStateNotificationDispatchSource_t, methodOptions),
        .metaMethodOptionsSize   = 2 * sizeof(uint64_t) * 0,
        .metaMethodOptionsOffset = __builtin_offsetof(struct OSClassDescription_IOServiceStateNotificationDispatchSource_t, metaMethodOptions),
        .queueNamesSize       = sizeof(IOServiceStateNotificationDispatchSource_QueueNames),
        .queueNamesOffset     = __builtin_offsetof(struct OSClassDescription_IOServiceStateNotificationDispatchSource_t, queueNames),
        .methodNamesSize         = sizeof(IOServiceStateNotificationDispatchSource_MethodNames),
        .methodNamesOffset       = __builtin_offsetof(struct OSClassDescription_IOServiceStateNotificationDispatchSource_t, methodNames),
        .metaMethodNamesSize     = sizeof(IOServiceStateNotificationDispatchSourceMetaClass_MethodNames),
        .metaMethodNamesOffset   = __builtin_offsetof(struct OSClassDescription_IOServiceStateNotificationDispatchSource_t, metaMethodNames),
        .flags                   = 1*kOSClassCanRemote,
    },
    .methodOptions = {},
    .metaMethodOptions = {},
    .queueNames      = IOServiceStateNotificationDispatchSource_QueueNames,
    .methodNames     = IOServiceStateNotificationDispatchSource_MethodNames,
    .metaMethodNames = IOServiceStateNotificationDispatchSourceMetaClass_MethodNames,
};

OSMetaClass * gIOServiceStateNotificationDispatchSourceMetaClass;

static kern_return_t
IOServiceStateNotificationDispatchSource_New(OSMetaClass * instance);

const OSClassLoadInformation
IOServiceStateNotificationDispatchSource_Class =
{
    .description       = &OSClassDescription_IOServiceStateNotificationDispatchSource.base,
    .metaPointer       = &gIOServiceStateNotificationDispatchSourceMetaClass,
    .version           = 1,
    .instanceSize      = sizeof(IOServiceStateNotificationDispatchSource),
    .New               = &IOServiceStateNotificationDispatchSource_New,
};

extern const void * const
gIOServiceStateNotificationDispatchSource_Declaration;
const void * const
gIOServiceStateNotificationDispatchSource_Declaration
__attribute__((visibility("hidden"),section("__DATA_CONST,__osclassinfo,regular,no_dead_strip"),no_sanitize("address")))
    = &IOServiceStateNotificationDispatchSource_Class;

static kern_return_t
IOServiceStateNotificationDispatchSource_New(OSMetaClass * instance)
{
    if (!new(instance) IOServiceStateNotificationDispatchSourceMetaClass) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

kern_return_t
IOServiceStateNotificationDispatchSourceMetaClass::New(OSObject * instance)
{
    if (!new(instance) IOServiceStateNotificationDispatchSource) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

#endif /* !KERNEL */

kern_return_t
IOServiceStateNotificationDispatchSource::Dispatch(const IORPC rpc)
{
    return _Dispatch(this, rpc);
}

kern_return_t
IOServiceStateNotificationDispatchSource::_Dispatch(IOServiceStateNotificationDispatchSource * self, const IORPC rpc)
{
    kern_return_t ret = kIOReturnUnsupported;
    IORPCMessage * msg = IORPCMessageFromMach(rpc.message, false);

    switch (msg->msgid)
    {
#if KERNEL
        case IOServiceStateNotificationDispatchSource_SetHandler_ID:
        {
            ret = IOServiceStateNotificationDispatchSource::SetHandler_Invoke(rpc, self, SimpleMemberFunctionCast(IOServiceStateNotificationDispatchSource::SetHandler_Handler, *self, &IOServiceStateNotificationDispatchSource::SetHandler_Impl));
            break;
        }
        case IOServiceStateNotificationDispatchSource_StateNotificationBegin_ID:
        {
            ret = IOServiceStateNotificationDispatchSource::StateNotificationBegin_Invoke(rpc, self, SimpleMemberFunctionCast(IOServiceStateNotificationDispatchSource::StateNotificationBegin_Handler, *self, &IOServiceStateNotificationDispatchSource::StateNotificationBegin_Impl));
            break;
        }
#endif /* !KERNEL */

        default:
            ret = IODispatchSource::_Dispatch(self, rpc);
            break;
    }

    return (ret);
}

#if KERNEL
kern_return_t
IOServiceStateNotificationDispatchSource::MetaClass::Dispatch(const IORPC rpc)
{
#else /* KERNEL */
kern_return_t
IOServiceStateNotificationDispatchSourceMetaClass::Dispatch(const IORPC rpc)
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
