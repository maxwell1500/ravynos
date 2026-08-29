/* iig(DriverKit-254) generated from IOExtensiblePaniclog.iig */

#ifndef _IOKIT_UIOEXTENSIBLEPANICLOG_H
#define _IOKIT_UIOEXTENSIBLEPANICLOG_H

#include <DriverKit/OSObject.h>  /* .iig include */
#include <DriverKit/IOBufferMemoryDescriptor.h>  /* .iig include */

#if __DOCUMENTATION__
#define KERNEL IIG_KERNEL

enum {
    kIOExtensiblePaniclogOptionsNone = 0x0,
    kIOExtensiblePaniclogOptionsWithBuffer = 0x1,
};

class KERNEL IOExtensiblePaniclog : public OSObject
{
public:
    virtual bool init() override;
    virtual void free() override;
    static kern_return_t Create(OSData *uuid, OSString *data_id, uint32_t max_len, uint32_t options, IOExtensiblePaniclog **out);
    virtual kern_return_t SetActive();
    virtual kern_return_t SetInactive();
    virtual kern_return_t InsertData(OSData *data);
    virtual kern_return_t AppendData(OSData *data);
    virtual kern_return_t CopyMemoryDescriptor(IOBufferMemoryDescriptor **mem);
    virtual kern_return_t ClaimBuffer(uint64_t *addr, uint64_t *len) LOCALONLY;
    virtual kern_return_t YieldBuffer(uint32_t used_len) LOCALONLY;
    virtual kern_return_t SetUsedLen(uint32_t used_len);
};

#undef KERNEL
#else /* __DOCUMENTATION__ */

#define IOExtensiblePaniclog_Create_ID            0x19a1e73b42105e43ULL
#define IOExtensiblePaniclog_SetActive_ID         0x83bc5292d5169263ULL
#define IOExtensiblePaniclog_SetInactive_ID       0xaede718b8d9dd7d4ULL
#define IOExtensiblePaniclog_InsertData_ID        0x407a62e0915f6852ULL
#define IOExtensiblePaniclog_AppendData_ID        0x8c65f692cb35464bULL
#define IOExtensiblePaniclog_CopyMemoryDescriptor_ID 0x786480379dcef440ULL
#define IOExtensiblePaniclog_SetUsedLen_ID        0xa65427629cb2e17bULL

#define IOExtensiblePaniclog_Create_Args \
        OSData * uuid, \
        OSString * data_id, \
        uint32_t max_len, \
        uint32_t options, \
        IOExtensiblePaniclog ** out

#define IOExtensiblePaniclog_SetActive_Args       /* no arguments */
#define IOExtensiblePaniclog_SetInactive_Args     /* no arguments */
#define IOExtensiblePaniclog_InsertData_Args      OSData * data
#define IOExtensiblePaniclog_AppendData_Args      OSData * data
#define IOExtensiblePaniclog_CopyMemoryDescriptor_Args IOBufferMemoryDescriptor ** mem
#define IOExtensiblePaniclog_SetUsedLen_Args      uint32_t used_len

#define IOExtensiblePaniclog_Methods \
\
public:\
\
    virtual kern_return_t\
    Dispatch(const IORPC rpc) APPLE_KEXT_OVERRIDE;\
\
    static kern_return_t\
    _Dispatch(IOExtensiblePaniclog * self, const IORPC rpc);\
\
    static kern_return_t\
    Create(\
        OSData * uuid,\
        OSString * data_id,\
        uint32_t max_len,\
        uint32_t options,\
        IOExtensiblePaniclog ** out);\
\
    kern_return_t\
    SetActive(\
        OSDispatchMethod supermethod = NULL);\
\
    kern_return_t\
    SetInactive(\
        OSDispatchMethod supermethod = NULL);\
\
    kern_return_t\
    InsertData(\
        OSData * data,\
        OSDispatchMethod supermethod = NULL);\
\
    kern_return_t\
    AppendData(\
        OSData * data,\
        OSDispatchMethod supermethod = NULL);\
\
    kern_return_t\
    CopyMemoryDescriptor(\
        IOBufferMemoryDescriptor ** mem,\
        OSDispatchMethod supermethod = NULL);\
\
    kern_return_t\
    SetUsedLen(\
        uint32_t used_len,\
        OSDispatchMethod supermethod = NULL);\
\
\
    /* _Invoke methods */\
\
    typedef kern_return_t (*Create_Handler)(IOExtensiblePaniclog_Create_Args);\
    static kern_return_t\
    Create_Invoke(const IORPC rpc,\
        Create_Handler func);\
\
    typedef kern_return_t (*SetActive_Handler)(OSMetaClassBase * target);\
    static kern_return_t\
    SetActive_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        SetActive_Handler func);\
\
    typedef kern_return_t (*SetInactive_Handler)(OSMetaClassBase * target);\
    static kern_return_t\
    SetInactive_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        SetInactive_Handler func);\
\
    typedef kern_return_t (*InsertData_Handler)(OSMetaClassBase * target, IOExtensiblePaniclog_InsertData_Args);\
    static kern_return_t\
    InsertData_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        InsertData_Handler func);\
\
    typedef kern_return_t (*AppendData_Handler)(OSMetaClassBase * target, IOExtensiblePaniclog_AppendData_Args);\
    static kern_return_t\
    AppendData_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        AppendData_Handler func);\
\
    typedef kern_return_t (*CopyMemoryDescriptor_Handler)(OSMetaClassBase * target, IOExtensiblePaniclog_CopyMemoryDescriptor_Args);\
    static kern_return_t\
    CopyMemoryDescriptor_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        CopyMemoryDescriptor_Handler func);\
\
    typedef kern_return_t (*SetUsedLen_Handler)(OSMetaClassBase * target, IOExtensiblePaniclog_SetUsedLen_Args);\
    static kern_return_t\
    SetUsedLen_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        SetUsedLen_Handler func);\
\


#define IOExtensiblePaniclog_KernelMethods \
\
protected:\
    /* _Impl methods */\
\
    static kern_return_t\
    Create_Impl(IOExtensiblePaniclog_Create_Args);\
\
    kern_return_t\
    SetActive_Impl(/* no arguments */);\
\
    kern_return_t\
    SetInactive_Impl(/* no arguments */);\
\
    kern_return_t\
    InsertData_Impl(IOExtensiblePaniclog_InsertData_Args);\
\
    kern_return_t\
    AppendData_Impl(IOExtensiblePaniclog_AppendData_Args);\
\
    kern_return_t\
    CopyMemoryDescriptor_Impl(IOExtensiblePaniclog_CopyMemoryDescriptor_Args);\
\
    kern_return_t\
    SetUsedLen_Impl(IOExtensiblePaniclog_SetUsedLen_Args);\
\


#define IOExtensiblePaniclog_VirtualMethods \
\
public:\
\
    virtual bool\
    init(\
) APPLE_KEXT_OVERRIDE;\
\
    virtual void\
    free(\
) APPLE_KEXT_OVERRIDE;\
\


#if !KERNEL

extern OSMetaClass          * gIOExtensiblePaniclogMetaClass;
extern const OSClassLoadInformation IOExtensiblePaniclog_Class;

class IOExtensiblePaniclogMetaClass : public OSMetaClass
{
public:
    virtual kern_return_t
    New(OSObject * instance) override;
    virtual kern_return_t
    Dispatch(const IORPC rpc) override;
};

#endif /* !KERNEL */

class IOExtensiblePaniclogInterface : public OSInterface
{
public:
};

struct IOExtensiblePaniclog_IVars;
struct IOExtensiblePaniclog_LocalIVars;

class IOExtensiblePaniclog : public OSObject, public IOExtensiblePaniclogInterface
{
#if KERNEL
    OSDeclareDefaultStructorsWithDispatch(IOExtensiblePaniclog);
#endif /* KERNEL */

#if !KERNEL
    IOExtensiblePaniclog_Methods
#endif /* !KERNEL */

    IOExtensiblePaniclog_VirtualMethods
};

#endif /* __DOCUMENTATION__ */

#endif /* _IOKIT_UIOEXTENSIBLEPANICLOG_H */
