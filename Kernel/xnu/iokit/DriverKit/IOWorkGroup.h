/* iig(DriverKit-254) generated from IOWorkGroup.iig */

#ifndef _IOKIT_UIOWORKGROUP_H
#define _IOKIT_UIOWORKGROUP_H

#include <DriverKit/OSObject.h>
#include <DriverKit/IOUserClient.h>

#if __DOCUMENTATION__
#define KERNEL IIG_KERNEL
enum { kIOWorkGroupMaxNameLength = 64 };
class NATIVE KERNEL IOWorkGroup : public OSObject
{
public:
    virtual bool init() override;
    virtual void free() override;
    static kern_return_t Create(OSString * name, IOUserClient * userClient, IOWorkGroup ** workgroup) LOCAL;
    virtual kern_return_t SetWorkGroupPort(mach_port_t port PORTCOPYSEND) LOCAL;
    size_t GetTokenSize() LOCALONLY;
    kern_return_t Join(void * token) LOCALONLY;
    kern_return_t Leave(void * token) LOCALONLY;
    kern_return_t Invalidate() LOCALONLY;
    virtual kern_return_t InvalidateKernel(IOUserClient * client);
};
#undef KERNEL
#else /* __DOCUMENTATION__ */

#define IOWorkGroup_InvalidateKernel_ID           0x89abcdef01234567ULL
#define IOWorkGroup_InvalidateKernel_Args         IOUserClient * client

#define IOWorkGroup_Methods \
\
public:\
\
    virtual kern_return_t\
    Dispatch(const IORPC rpc) APPLE_KEXT_OVERRIDE;\
\
    static kern_return_t\
    _Dispatch(IOWorkGroup * self, const IORPC rpc);\
\
    kern_return_t\
    InvalidateKernel(\
        IOUserClient * client,\
        OSDispatchMethod supermethod = NULL);\
\
    /* _Invoke methods */\
\
    typedef kern_return_t (*InvalidateKernel_Handler)(OSMetaClassBase * target, IOWorkGroup_InvalidateKernel_Args);\
    static kern_return_t\
    InvalidateKernel_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        InvalidateKernel_Handler func);\
\


#define IOWorkGroup_KernelMethods \
\
protected:\
    kern_return_t\
    InvalidateKernel_Impl(IOWorkGroup_InvalidateKernel_Args);\
\


#define IOWorkGroup_VirtualMethods \
\
public:\
\
    virtual bool init() APPLE_KEXT_OVERRIDE;\
    virtual void free() APPLE_KEXT_OVERRIDE;\
\


#if !KERNEL
extern OSMetaClass * gIOWorkGroupMetaClass;
extern const OSClassLoadInformation IOWorkGroup_Class;
class IOWorkGroupMetaClass : public OSMetaClass
{
public:
    virtual kern_return_t New(OSObject * instance) override;
    virtual kern_return_t Dispatch(const IORPC rpc) override;
};
#endif /* !KERNEL */

class IOWorkGroupInterface : public OSInterface { public: };
struct IOWorkGroup_IVars;
struct IOWorkGroup_LocalIVars;

class IOWorkGroup : public OSObject, public IOWorkGroupInterface
{
#if KERNEL
    OSDeclareDefaultStructorsWithDispatch(IOWorkGroup);
#endif /* KERNEL */
#if !KERNEL
    IOWorkGroup_Methods
#endif /* !KERNEL */
    IOWorkGroup_VirtualMethods
};

#endif /* __DOCUMENTATION__ */
#endif /* _IOKIT_UIOWORKGROUP_H */
