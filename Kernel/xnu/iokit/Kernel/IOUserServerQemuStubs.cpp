#include <IOKit/IOUserServer.h>
#include <IOKit/IOService.h>
#include <IOKit/IOKitKeys.h>
#include <IOKit/IOReportTypes.h>
#include <kern/kalloc.h>
#include <kern/task.h>
#include <sys/reason.h>
#include "IOKitKernelInternal.h"
#include <IOKit/IOExtensiblePaniclog.h>

extern "C" void IOUserServerRecordExitReason(task_t task, os_reason_t reason) { (void)task; (void)reason; }

void *OSObject_typed_operator_new(kalloc_type_view_t ktv, vm_size_t size) { (void)size; return kalloc_type_impl_external(ktv, Z_WAITOK); }
void OSObject_typed_operator_delete(kalloc_type_view_t ktv, void *mem, vm_size_t size) { (void)size; kfree_type_impl_external(ktv, mem); }

OSDefineMetaClassAndStructors(IOUserServerCheckInToken, OSObject)
OSDefineMetaClassAndStructors(_IOUserServerCheckInCancellationHandler, OSObject)

_IOUserServerCheckInCancellationHandler *IOUserServerCheckInToken::setCancellationHandler(IOUserServerCheckInCancellationHandler h, void *a) { (void)h; (void)a; return nullptr; }
void IOUserServerCheckInToken::removeCancellationHandler(_IOUserServerCheckInCancellationHandler *h) { (void)h; }
void IOUserServerCheckInToken::free() { OSObject::free(); }
void IOUserServerCheckInToken::cancel() {}
void IOUserServerCheckInToken::cancelAll() {}

IOService *IOSystemStateNotification::initialize(void) {
    IOSystemStateNotification *inst = OSTypeAlloc(IOSystemStateNotification);
    if (!inst) return nullptr;
    if (!inst->init()) { inst->release(); return nullptr; }
    return inst;
}
OSDefineMetaClassAndStructors(IOSystemStateNotification, IOService)
IOReturn IOSystemStateNotification::setProperties(OSObject *p) { return IOService::setProperties(p); }
bool IOSystemStateNotification::serializeProperties(OSSerialize *s) const { return IOService::serializeProperties(s); }

void IOUserServer::systemHalt(int h) { (void)h; }
bool IOUserServer::checkPMReady(void) { return true; }
IOUserServer *IOUserServer::launchUserServer(OSString *b, const OSSymbol *n, OSNumber *t, bool r, IOUserServerCheckInToken **tok, OSData *d) { (void)b;(void)n;(void)t;(void)r;(void)tok;(void)d; if(tok) *tok=nullptr; return nullptr; }
bool IOUserServer::shouldLeakObjects(void) { return false; }
void IOUserServer::beginLeakingObjects(void) {}
void IOUserServer::powerSourceChanged(bool a) { (void)a; }
IOReturn IOUserServer::serviceSetPowerState(IOService *c, IOService *s, IOPMPowerFlags f, IOPMPowerStateIndex p) { (void)c;(void)s;(void)f;(void)p; return kIOReturnUnsupported; }
IOReturn IOUserServer::kill(const char *r) { (void)r; return kIOReturnUnsupported; }
IOWorkLoop *IOUserServer::getWorkLoop() const { return nullptr; }

IOReturn IOService::_ConfigureReport(IOReportChannelList *ch, IOReportConfigureAction a, void *res, void *dst) {
    if (!ch) return kIOReturnBadArgument;
    (void)a; (void)res; (void)dst;
    return kIOReturnUnsupported;
}
IOReturn IOService::_UpdateReport(IOReportChannelList *ch, IOReportUpdateAction a, void *res, void *dst) {
    if (!ch) return kIOReturnBadArgument;
    (void)a; (void)res; (void)dst;
    return kIOReturnUnsupported;
}

kern_return_t IOExtensiblePaniclog::Dispatch(const IORPC r) { (void)r; return kIOReturnUnsupported; }
kern_return_t IOExtensiblePaniclog::MetaClass::Dispatch(const IORPC r) { (void)r; return kIOReturnUnsupported; }
// ubsan provided by libsa/nonlto.c
