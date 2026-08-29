/* iig(DriverKit-254 Oct 18 2022 12:24:09) generated from IOExtensiblePaniclog.iig */

#undef	IIG_IMPLEMENTATION
#define	IIG_IMPLEMENTATION 	IOExtensiblePaniclog.iig

#if KERNEL
#include <libkern/c++/OSString.h>
#else
#include <DriverKit/DriverKit.h>
#endif /* KERNEL */
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOExtensiblePaniclog.h>
/* @iig implementation */
#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOUserClient.h>
/* @iig end */

#if __has_builtin(__builtin_load_member_function_pointer)
#define SimpleMemberFunctionCast(cfnty, self, func) (cfnty)__builtin_load_member_function_pointer(self, func)
#else
#define SimpleMemberFunctionCast(cfnty, self, func) ({ union { typeof(func) memfun; cfnty cfun; } pair; pair.memfun = func; pair.cfun; })
#endif

struct IOExtensiblePaniclog_SetActive_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
};
#pragma pack(4)
struct IOExtensiblePaniclog_SetActive_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    IOExtensiblePaniclog_SetActive_Msg_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_SetActive_Msg_ObjRefs (1)

struct IOExtensiblePaniclog_SetActive_Rpl_Content
{
    IORPCMessage __hdr;
};
#pragma pack(4)
struct IOExtensiblePaniclog_SetActive_Rpl
{
    IORPCMessageMach           mach;
    IOExtensiblePaniclog_SetActive_Rpl_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_SetActive_Rpl_ObjRefs (0)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOExtensiblePaniclog_SetActive_Msg * message;
        struct IOExtensiblePaniclog_SetActive_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOExtensiblePaniclog_SetActive_Invocation;
struct IOExtensiblePaniclog_SetInactive_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
};
#pragma pack(4)
struct IOExtensiblePaniclog_SetInactive_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    IOExtensiblePaniclog_SetInactive_Msg_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_SetInactive_Msg_ObjRefs (1)

struct IOExtensiblePaniclog_SetInactive_Rpl_Content
{
    IORPCMessage __hdr;
};
#pragma pack(4)
struct IOExtensiblePaniclog_SetInactive_Rpl
{
    IORPCMessageMach           mach;
    IOExtensiblePaniclog_SetInactive_Rpl_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_SetInactive_Rpl_ObjRefs (0)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOExtensiblePaniclog_SetInactive_Msg * message;
        struct IOExtensiblePaniclog_SetInactive_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOExtensiblePaniclog_SetInactive_Invocation;
struct IOExtensiblePaniclog_InsertData_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
    OSObjectRef  data;
};
#pragma pack(4)
struct IOExtensiblePaniclog_InsertData_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    mach_msg_port_descriptor_t data__descriptor;
    IOExtensiblePaniclog_InsertData_Msg_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_InsertData_Msg_ObjRefs (2)

struct IOExtensiblePaniclog_InsertData_Rpl_Content
{
    IORPCMessage __hdr;
};
#pragma pack(4)
struct IOExtensiblePaniclog_InsertData_Rpl
{
    IORPCMessageMach           mach;
    IOExtensiblePaniclog_InsertData_Rpl_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_InsertData_Rpl_ObjRefs (0)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOExtensiblePaniclog_InsertData_Msg * message;
        struct IOExtensiblePaniclog_InsertData_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOExtensiblePaniclog_InsertData_Invocation;
struct IOExtensiblePaniclog_AppendData_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
    OSObjectRef  data;
};
#pragma pack(4)
struct IOExtensiblePaniclog_AppendData_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    mach_msg_port_descriptor_t data__descriptor;
    IOExtensiblePaniclog_AppendData_Msg_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_AppendData_Msg_ObjRefs (2)

struct IOExtensiblePaniclog_AppendData_Rpl_Content
{
    IORPCMessage __hdr;
};
#pragma pack(4)
struct IOExtensiblePaniclog_AppendData_Rpl
{
    IORPCMessageMach           mach;
    IOExtensiblePaniclog_AppendData_Rpl_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_AppendData_Rpl_ObjRefs (0)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOExtensiblePaniclog_AppendData_Msg * message;
        struct IOExtensiblePaniclog_AppendData_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOExtensiblePaniclog_AppendData_Invocation;
struct IOExtensiblePaniclog_CopyMemoryDescriptor_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
};
#pragma pack(4)
struct IOExtensiblePaniclog_CopyMemoryDescriptor_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    IOExtensiblePaniclog_CopyMemoryDescriptor_Msg_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_CopyMemoryDescriptor_Msg_ObjRefs (1)

struct IOExtensiblePaniclog_CopyMemoryDescriptor_Rpl_Content
{
    IORPCMessage __hdr;
    OSObjectRef  mem;
};
#pragma pack(4)
struct IOExtensiblePaniclog_CopyMemoryDescriptor_Rpl
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t mem__descriptor;
    IOExtensiblePaniclog_CopyMemoryDescriptor_Rpl_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_CopyMemoryDescriptor_Rpl_ObjRefs (1)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOExtensiblePaniclog_CopyMemoryDescriptor_Msg * message;
        struct IOExtensiblePaniclog_CopyMemoryDescriptor_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOExtensiblePaniclog_CopyMemoryDescriptor_Invocation;
struct IOExtensiblePaniclog_SetUsedLen_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
    uint32_t  used_len;
};
#pragma pack(4)
struct IOExtensiblePaniclog_SetUsedLen_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    IOExtensiblePaniclog_SetUsedLen_Msg_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_SetUsedLen_Msg_ObjRefs (1)

struct IOExtensiblePaniclog_SetUsedLen_Rpl_Content
{
    IORPCMessage __hdr;
};
#pragma pack(4)
struct IOExtensiblePaniclog_SetUsedLen_Rpl
{
    IORPCMessageMach           mach;
    IOExtensiblePaniclog_SetUsedLen_Rpl_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_SetUsedLen_Rpl_ObjRefs (0)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOExtensiblePaniclog_SetUsedLen_Msg * message;
        struct IOExtensiblePaniclog_SetUsedLen_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOExtensiblePaniclog_SetUsedLen_Invocation;
struct IOExtensiblePaniclog_Create_Msg_Content
{
    IORPCMessage __hdr;
    OSObjectRef  __object;
    OSObjectRef  uuid;
    OSObjectRef  data_id;
    uint32_t  max_len;
    uint32_t  options;
};
#pragma pack(4)
struct IOExtensiblePaniclog_Create_Msg
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t __object__descriptor;
    mach_msg_port_descriptor_t uuid__descriptor;
    mach_msg_port_descriptor_t data_id__descriptor;
    IOExtensiblePaniclog_Create_Msg_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_Create_Msg_ObjRefs (3)

struct IOExtensiblePaniclog_Create_Rpl_Content
{
    IORPCMessage __hdr;
    OSObjectRef  out;
};
#pragma pack(4)
struct IOExtensiblePaniclog_Create_Rpl
{
    IORPCMessageMach           mach;
    mach_msg_port_descriptor_t out__descriptor;
    IOExtensiblePaniclog_Create_Rpl_Content content;
};
#pragma pack()
#define IOExtensiblePaniclog_Create_Rpl_ObjRefs (1)

typedef union
{
    const IORPC rpc;
    struct
    {
        const struct IOExtensiblePaniclog_Create_Msg * message;
        struct IOExtensiblePaniclog_Create_Rpl       * reply;
        uint32_t sendSize;
        uint32_t replySize;
    };
}
IOExtensiblePaniclog_Create_Invocation;
#if !KERNEL
extern OSMetaClass * gOSContainerMetaClass;
extern OSMetaClass * gOSDataMetaClass;
extern OSMetaClass * gOSNumberMetaClass;
extern OSMetaClass * gOSStringMetaClass;
extern OSMetaClass * gOSBooleanMetaClass;
extern OSMetaClass * gOSDictionaryMetaClass;
extern OSMetaClass * gOSArrayMetaClass;
extern OSMetaClass * gIOBufferMemoryDescriptorMetaClass;
#endif /* !KERNEL */

#if KERNEL
OSDefineMetaClassAndStructors(IOExtensiblePaniclog, OSObject);
#endif /* KERNEL */

#if !KERNEL

#define IOExtensiblePaniclog_QueueNames  ""

#define IOExtensiblePaniclog_MethodNames  ""

#define IOExtensiblePaniclogMetaClass_MethodNames  ""

struct OSClassDescription_IOExtensiblePaniclog_t
{
    OSClassDescription base;
    uint64_t           methodOptions[2 * 0];
    uint64_t           metaMethodOptions[2 * 0];
    char               queueNames[sizeof(IOExtensiblePaniclog_QueueNames)];
    char               methodNames[sizeof(IOExtensiblePaniclog_MethodNames)];
    char               metaMethodNames[sizeof(IOExtensiblePaniclogMetaClass_MethodNames)];
};

const struct OSClassDescription_IOExtensiblePaniclog_t
OSClassDescription_IOExtensiblePaniclog =
{
    .base =
    {
        .descriptionSize         = sizeof(OSClassDescription_IOExtensiblePaniclog_t),
        .name                    = "IOExtensiblePaniclog",
        .superName               = "OSObject",
        .methodOptionsSize       = 2 * sizeof(uint64_t) * 0,
        .methodOptionsOffset     = __builtin_offsetof(struct OSClassDescription_IOExtensiblePaniclog_t, methodOptions),
        .metaMethodOptionsSize   = 2 * sizeof(uint64_t) * 0,
        .metaMethodOptionsOffset = __builtin_offsetof(struct OSClassDescription_IOExtensiblePaniclog_t, metaMethodOptions),
        .queueNamesSize       = sizeof(IOExtensiblePaniclog_QueueNames),
        .queueNamesOffset     = __builtin_offsetof(struct OSClassDescription_IOExtensiblePaniclog_t, queueNames),
        .methodNamesSize         = sizeof(IOExtensiblePaniclog_MethodNames),
        .methodNamesOffset       = __builtin_offsetof(struct OSClassDescription_IOExtensiblePaniclog_t, methodNames),
        .metaMethodNamesSize     = sizeof(IOExtensiblePaniclogMetaClass_MethodNames),
        .metaMethodNamesOffset   = __builtin_offsetof(struct OSClassDescription_IOExtensiblePaniclog_t, metaMethodNames),
        .flags                   = 1*kOSClassCanRemote,
    },
    .methodOptions = {},
    .metaMethodOptions = {},
    .queueNames      = IOExtensiblePaniclog_QueueNames,
    .methodNames     = IOExtensiblePaniclog_MethodNames,
    .metaMethodNames = IOExtensiblePaniclogMetaClass_MethodNames,
};

OSMetaClass * gIOExtensiblePaniclogMetaClass;

static kern_return_t
IOExtensiblePaniclog_New(OSMetaClass * instance);

const OSClassLoadInformation
IOExtensiblePaniclog_Class =
{
    .description       = &OSClassDescription_IOExtensiblePaniclog.base,
    .metaPointer       = &gIOExtensiblePaniclogMetaClass,
    .version           = 1,
    .instanceSize      = sizeof(IOExtensiblePaniclog),
    .New               = &IOExtensiblePaniclog_New,
};

extern const void * const
gIOExtensiblePaniclog_Declaration;
const void * const
gIOExtensiblePaniclog_Declaration
__attribute__((visibility("hidden"),section("__DATA_CONST,__osclassinfo,regular,no_dead_strip"),no_sanitize("address")))
    = &IOExtensiblePaniclog_Class;

static kern_return_t
IOExtensiblePaniclog_New(OSMetaClass * instance)
{
    if (!new(instance) IOExtensiblePaniclogMetaClass) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

kern_return_t
IOExtensiblePaniclogMetaClass::New(OSObject * instance)
{
    if (!new(instance) IOExtensiblePaniclog) return (kIOReturnNoMemory);
    return (kIOReturnSuccess);
}

#endif /* !KERNEL */

kern_return_t
IOExtensiblePaniclog::Dispatch(const IORPC rpc)
{
    return _Dispatch(this, rpc);
}

kern_return_t
IOExtensiblePaniclog::_Dispatch(IOExtensiblePaniclog * self, const IORPC rpc)
{
    kern_return_t ret = kIOReturnUnsupported;
    IORPCMessage * msg = IORPCMessageFromMach(rpc.message, false);

    switch (msg->msgid)
    {
#if KERNEL
        case IOExtensiblePaniclog_SetActive_ID:
        {
            ret = IOExtensiblePaniclog::SetActive_Invoke(rpc, self, SimpleMemberFunctionCast(IOExtensiblePaniclog::SetActive_Handler, *self, &IOExtensiblePaniclog::SetActive_Impl));
            break;
        }
        case IOExtensiblePaniclog_SetInactive_ID:
        {
            ret = IOExtensiblePaniclog::SetInactive_Invoke(rpc, self, SimpleMemberFunctionCast(IOExtensiblePaniclog::SetInactive_Handler, *self, &IOExtensiblePaniclog::SetInactive_Impl));
            break;
        }
        case IOExtensiblePaniclog_InsertData_ID:
        {
            ret = IOExtensiblePaniclog::InsertData_Invoke(rpc, self, SimpleMemberFunctionCast(IOExtensiblePaniclog::InsertData_Handler, *self, &IOExtensiblePaniclog::InsertData_Impl));
            break;
        }
        case IOExtensiblePaniclog_AppendData_ID:
        {
            ret = IOExtensiblePaniclog::AppendData_Invoke(rpc, self, SimpleMemberFunctionCast(IOExtensiblePaniclog::AppendData_Handler, *self, &IOExtensiblePaniclog::AppendData_Impl));
            break;
        }
        case IOExtensiblePaniclog_CopyMemoryDescriptor_ID:
        {
            ret = IOExtensiblePaniclog::CopyMemoryDescriptor_Invoke(rpc, self, SimpleMemberFunctionCast(IOExtensiblePaniclog::CopyMemoryDescriptor_Handler, *self, &IOExtensiblePaniclog::CopyMemoryDescriptor_Impl));
            break;
        }
        case IOExtensiblePaniclog_SetUsedLen_ID:
        {
            ret = IOExtensiblePaniclog::SetUsedLen_Invoke(rpc, self, SimpleMemberFunctionCast(IOExtensiblePaniclog::SetUsedLen_Handler, *self, &IOExtensiblePaniclog::SetUsedLen_Impl));
            break;
        }
#endif /* !KERNEL */

        default:
            ret = self->OSObject::_Dispatch(self, rpc);
            break;
    }

    return (ret);
}

#if KERNEL
kern_return_t
IOExtensiblePaniclog::MetaClass::Dispatch(const IORPC rpc)
{
#else /* KERNEL */
kern_return_t
IOExtensiblePaniclogMetaClass::Dispatch(const IORPC rpc)
{
#endif /* !KERNEL */

    kern_return_t ret = kIOReturnUnsupported;
    IORPCMessage * msg = IORPCMessageFromMach(rpc.message, false);

    switch (msg->msgid)
    {
#if KERNEL
        case IOExtensiblePaniclog_Create_ID:
            ret = IOExtensiblePaniclog::Create_Invoke(rpc, &IOExtensiblePaniclog::Create_Impl);
            break;
#endif /* !KERNEL */

        default:
            ret = OSMetaClassBase::Dispatch(rpc);
            break;
    }

    return (ret);
}
