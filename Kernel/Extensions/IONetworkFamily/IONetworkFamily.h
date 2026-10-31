/*
 * IONetworkFamily: the kernel-side base classes a network driver builds on.
 *
 * Copyright (C) 2026 ravynOS Project. All rights reserved.
 *
 * Only the surface this tree's drivers need is implemented: controller
 * enable/disable and transmit, an Ethernet controller that owns a MAC
 * address, and an interface that owns the BSD ifnet and hands received
 * packets to the stack.  The Apple headers in Frameworks/IOKit/network are
 * documentation-only (constants, no classes), so the classes below are the
 * definition of what a kext in this tree can call.
 */

#ifndef _IONETWORKFAMILY_H
#define _IONETWORKFAMILY_H

#include <IOKit/IOService.h>
#include <sys/kpi_mbuf.h>
#include <net/if.h>

class IONetworkController;
class IOEthernetController;

class IONetworkInterface : public IOService
{
    OSDeclareDefaultStructors(IONetworkInterface)

public:
    static IONetworkInterface *withController(IONetworkController *controller);

    virtual bool init(IONetworkController *controller);
    virtual bool attachInterface();
    virtual void detachInterface();

    /* Called by the controller for each received frame.  The interface owns
     * the packet from here on. */
    virtual void inputPacket(mbuf_t packet);

    virtual ifnet_t getIfnet() const { return fIfnet; }
    IONetworkController *getController() const { return fController; }

private:
    static errno_t sOutput(ifnet_t ifp, mbuf_t packet);
    static errno_t sFramer(ifnet_t ifp, mbuf_t *packet,
        const struct sockaddr *dest, const char *dest_linkaddr,
        const char *frame_type);

    IONetworkController *fController;
    ifnet_t              fIfnet;
    UInt32               fUnit;
};

class IONetworkController : public IOService
{
    OSDeclareDefaultStructors(IONetworkController)

public:
    virtual bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void stop(IOService *provider) APPLE_KEXT_OVERRIDE;

    virtual IOReturn enable(IONetworkInterface *interface);
    virtual IOReturn disable(IONetworkInterface *interface);

    /* Transmit one frame.  The controller consumes the packet whatever the
     * result: free it on success and on error. */
    virtual UInt32 outputPacket(mbuf_t packet, void *param) = 0;

    IONetworkInterface *getInterface() const { return fInterface; }

protected:
    virtual IONetworkInterface *createInterface();

    IONetworkInterface *fInterface;
};

class IOEthernetController : public IONetworkController
{
    OSDeclareDefaultStructors(IOEthernetController)

public:
    /* Fills addr with the six-byte hardware address, sets *len to 6. */
    virtual bool getHardwareAddress(void *addr, UInt32 *len) = 0;

    virtual IOReturn setMulticastMode(bool enabled);
    virtual IOReturn setPromiscuousMode(bool enabled);
};

#endif /* _IONETWORKFAMILY_H */
