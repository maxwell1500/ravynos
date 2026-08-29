#include <IOKit/IORPC.h>
#include <IOKit/IOService.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOUserServer.h>
#include <DriverKit/OSAction.h>

// 2. IOService::Stop_async
void
IOService::Stop_async(IOService * provider)
{
    Stop_async_Impl(provider);
}

// 3. IOService::_NewUserClient
kern_return_t
IOService::_NewUserClient(uint32_t type, OSDictionary * entitlements, IOUserClient ** userClient)
{
    return _NewUserClient_Impl(type, entitlements, userClient);
}

// 4. IOUserClient::CreateActionKernelCompletion
kern_return_t
IOUserClient::CreateActionKernelCompletion(size_t referenceSize, OSAction ** action)
{
    (void)referenceSize;
    (void)action;
    return kIOReturnUnsupported;
}

// 5. IOUserClient::CreateMemoryDescriptorFromClient
kern_return_t
IOUserClient::CreateMemoryDescriptorFromClient(
    uint64_t memoryDescriptorCreateOptions,
    uint32_t segmentsCount,
    const IOAddressSegment segments[32],
    IOMemoryDescriptor ** memory,
    OSDispatchMethod supermethod)
{
    (void)supermethod;
    return CreateMemoryDescriptorFromClient_Impl(memoryDescriptorCreateOptions, segmentsCount, segments, memory);
}

// 12. IOUserServer::RegisterService
kern_return_t
IOUserServer::RegisterService(OSDispatchMethod supermethod)
{
    (void)supermethod;
    return RegisterService_Impl();
}
