/* iig(DriverKit-254) generated from IOEventLink.iig */

#ifndef _IOKIT_UIOEVENTLINK_H
#define _IOKIT_UIOEVENTLINK_H

#include <DriverKit/OSObject.h>
#include <DriverKit/IOUserClient.h>

#if __DOCUMENTATION__
#define KERNEL IIG_KERNEL
enum { kIOEventLinkMaxNameLength = 64, kIOEventLinkAssociateCurrentThread = 0, kIOEventLinkAssociateOnWait = 1, kIOEventLinkClockMachAbsoluteTime = 0 };
class NATIVE KERNEL IOEventLink : public OSObject
{
public:
    virtual bool init() override;
    virtual void free() override;
    static kern_return_t Create(OSString * name, IOUserClient * userClient, IOEventLink ** eventLink) LOCAL;
    virtual kern_return_t SetEventlinkPort(mach_port_t port PORTCOPYSEND) LOCAL;
    kern_return_t Signal() LOCALONLY;
    kern_return_t Wait(uint64_t * signalsConsumed) LOCALONLY;
    kern_return_t SignalAndWait(uint64_t * signalsConsumed) LOCALONLY;
    kern_return_t SignalAndWaitUntil(uint64_t clockOptions, uint64_t timeout, uint64_t * signalsConsumed) LOCALONLY;
    kern_return_t WaitUntil(uint64_t clockOptions, uint64_t timeout, uint64_t * signalsConsumed) LOCALONLY;
    kern_return_t Cancel() LOCALONLY;
    kern_return_t Activate() LOCALONLY;
    kern_return_t Associate(uint64_t options) LOCALONLY;
    kern_return_t Disassociate() LOCALONLY;
    kern_return_t Invalidate() LOCALONLY;
    virtual kern_return_t InvalidateKernel(IOUserClient * client);
};
#undef KERNEL
#else /* __DOCUMENTATION__ */

#define IOEventLink_InvalidateKernel_ID           0x7936639ac7bdf7cbULL
#define IOEventLink_InvalidateKernel_Args         IOUserClient * client

#define IOEventLink_Methods \
\
public:\
\
    virtual kern_return_t\
    Dispatch(const IORPC rpc) APPLE_KEXT_OVERRIDE;\
\
    static kern_return_t\
    _Dispatch(IOEventLink * self, const IORPC rpc);\
\
    kern_return_t\
    InvalidateKernel(\
        IOUserClient * client,\
        OSDispatchMethod supermethod = NULL);\
\
    /* _Invoke methods */\
\
    typedef kern_return_t (*InvalidateKernel_Handler)(OSMetaClassBase * target, IOEventLink_InvalidateKernel_Args);\
    static kern_return_t\
    InvalidateKernel_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        InvalidateKernel_Handler func);\
\


#define IOEventLink_KernelMethods \
\
protected:\
    kern_return_t\
    InvalidateKernel_Impl(IOEventLink_InvalidateKernel_Args);\
\


#define IOEventLink_VirtualMethods \
\
public:\
\
    virtual bool init() APPLE_KEXT_OVERRIDE;\
    virtual void free() APPLE_KEXT_OVERRIDE;\
\


#if !KERNEL
extern OSMetaClass * gIOEventLinkMetaClass;
extern const OSClassLoadInformation IOEventLink_Class;
class IOEventLinkMetaClass : public OSMetaClass
{
public:
    virtual kern_return_t New(OSObject * instance) override;
    virtual kern_return_t Dispatch(const IORPC rpc) override;
};
#endif /* !KERNEL */

class IOEventLinkInterface : public OSInterface { public: };
struct IOEventLink_IVars;
struct IOEventLink_LocalIVars;

class IOEventLink : public OSObject, public IOEventLinkInterface
{
#if KERNEL
    OSDeclareDefaultStructorsWithDispatch(IOEventLink);
#endif /* KERNEL */
#if !KERNEL
    IOEventLink_Methods
#endif /* !KERNEL */
    IOEventLink_VirtualMethods
};

#endif /* __DOCUMENTATION__ */
#endif /* _IOKIT_UIOEVENTLINK_H */
