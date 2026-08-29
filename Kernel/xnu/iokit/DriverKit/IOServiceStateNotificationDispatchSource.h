/* iig(DriverKit-254) generated from IOServiceStateNotificationDispatchSource.iig */

#ifndef _IOKIT_UIOSERVICESTATEDISPATCHSOURCE_H
#define _IOKIT_UIOSERVICESTATEDISPATCHSOURCE_H

#include <DriverKit/IODispatchSource.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/IOService.h>
#include <DriverKit/IODispatchQueue.h>

#if __DOCUMENTATION__
#define KERNEL IIG_KERNEL
class NATIVE KERNEL IOServiceStateNotificationDispatchSource : public IODispatchSource
{
public:
    virtual bool init() override;
    virtual void free() override;
    static kern_return_t Create(IOService * service, OSArray * items, IODispatchQueue * queue, IOServiceStateNotificationDispatchSource ** source) LOCAL;
    virtual kern_return_t SetEnableWithCompletion(bool enable, IODispatchSourceCancelHandler handler) override LOCAL;
    virtual kern_return_t Cancel(IODispatchSourceCancelHandler handler) override LOCAL;
    virtual kern_return_t SetHandler(OSAction * action TYPE(StateNotificationReady));
    virtual kern_return_t StateNotificationBegin(void);
private:
    virtual void StateNotificationReady(OSAction * action TARGET) LOCAL = 0;
};
#undef KERNEL
#else /* __DOCUMENTATION__ */

#define IOServiceStateNotificationDispatchSource_SetHandler_ID            0xca55c48f95fc6f8eULL
#define IOServiceStateNotificationDispatchSource_StateNotificationBegin_ID 0xb1234567890abcdeULL
#define IOServiceStateNotificationDispatchSource_StateNotificationReady_ID 0xfbaa85f2cdb990b4ULL

#define IOServiceStateNotificationDispatchSource_SetHandler_Args \
        OSAction * action

#define IOServiceStateNotificationDispatchSource_StateNotificationBegin_Args /* no arguments */

#define IOServiceStateNotificationDispatchSource_Methods \
\
public:\
\
    virtual kern_return_t\
    Dispatch(const IORPC rpc) APPLE_KEXT_OVERRIDE;\
\
    static kern_return_t\
    _Dispatch(IOServiceStateNotificationDispatchSource * self, const IORPC rpc);\
\
    kern_return_t\
    SetHandler(\
        OSAction * action,\
        OSDispatchMethod supermethod = NULL);\
\
    kern_return_t\
    StateNotificationBegin(\
        OSDispatchMethod supermethod = NULL);\
\
    /* _Invoke methods */\
\
    typedef kern_return_t (*SetHandler_Handler)(OSMetaClassBase * target, IOServiceStateNotificationDispatchSource_SetHandler_Args);\
    static kern_return_t\
    SetHandler_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        SetHandler_Handler func);\
\
    typedef kern_return_t (*StateNotificationBegin_Handler)(OSMetaClassBase * target);\
    static kern_return_t\
    StateNotificationBegin_Invoke(const IORPC rpc,\
        OSMetaClassBase * target,\
        StateNotificationBegin_Handler func);\
\


#define IOServiceStateNotificationDispatchSource_KernelMethods \
\
protected:\
    kern_return_t\
    SetHandler_Impl(IOServiceStateNotificationDispatchSource_SetHandler_Args);\
\
    kern_return_t\
    StateNotificationBegin_Impl(/* no arguments */);\
\


#define IOServiceStateNotificationDispatchSource_VirtualMethods \
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
extern OSMetaClass * gIOServiceStateNotificationDispatchSourceMetaClass;
extern const OSClassLoadInformation IOServiceStateNotificationDispatchSource_Class;
class IOServiceStateNotificationDispatchSourceMetaClass : public OSMetaClass
{
public:
    virtual kern_return_t New(OSObject * instance) override;
    virtual kern_return_t Dispatch(const IORPC rpc) override;
};
#endif /* !KERNEL */

class IOServiceStateNotificationDispatchSourceInterface : public OSInterface { public: };
struct IOServiceStateNotificationDispatchSource_IVars;
struct IOServiceStateNotificationDispatchSource_LocalIVars;

class IOServiceStateNotificationDispatchSource : public IODispatchSource, public IOServiceStateNotificationDispatchSourceInterface
{
#if KERNEL
    OSDeclareDefaultStructorsWithDispatch(IOServiceStateNotificationDispatchSource);
#endif /* KERNEL */
#if !KERNEL
    IOServiceStateNotificationDispatchSource_Methods
#endif /* !KERNEL */
    IOServiceStateNotificationDispatchSource_VirtualMethods
};

#endif /* __DOCUMENTATION__ */
#endif /* _IOKIT_UIOSERVICESTATEDISPATCHSOURCE_H */
