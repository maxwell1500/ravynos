/*
 * IONetworkFamily implementation.
 *
 * Copyright (C) 2026 ravynOS Project. All rights reserved.
 *
 * The interface owns the BSD ifnet created through the ifnet KPI; the
 * controller owns transmit.  A received frame enters the stack through
 * ifnet_input(), which calls the ifnet's demux (ether_demux) exactly as the
 * kernel's own loopback interface does.
 */

#include <IOKit/IOLib.h>
#include <net/kpi_interface.h>
#include <net/if.h>
#include <net/if_types.h>
#include <net/if_ether.h>
#include <net/ethernet.h>
#include <sys/kpi_mbuf.h>
#include <sys/mbuf.h>
#include <net/if_var.h>

#include "IONetworkFamily.h"

#define super IOService

OSDefineMetaClassAndStructors(IONetworkInterface, IOService)
OSDefineMetaClassAndAbstractStructors(IONetworkController, IOService)
OSDefineMetaClassAndAbstractStructors(IOEthernetController, IONetworkController)

/* ---------------------------------------------------------------- interface */

IONetworkInterface *
IONetworkInterface::withController(IONetworkController *controller)
{
    IONetworkInterface *iface = new IONetworkInterface;

    if (iface != NULL && !iface->init(controller)) {
        iface->release();
        iface = NULL;
    }
    return iface;
}

bool
IONetworkInterface::init(IONetworkController *controller)
{
    if (!super::init()) {
        return false;
    }
    fController = controller;
    fIfnet = NULL;
    fUnit = 0;
    return true;
}

errno_t
IONetworkInterface::sOutput(ifnet_t ifp, mbuf_t packet)
{
    IONetworkInterface *iface = (IONetworkInterface *)ifnet_softc(ifp);

    if (iface == NULL || iface->fController == NULL) {
        mbuf_freem(packet);
        return EIO;
    }
    return (errno_t)iface->fController->outputPacket(packet, NULL);
}

errno_t
IONetworkInterface::sFramer(ifnet_t ifp, mbuf_t *packet,
    const struct sockaddr *dest, const char *dest_linkaddr,
    const char *frame_type)
{
    struct ether_header eh;

    (void)dest;
    if (packet == NULL || *packet == NULL) {
        return EINVAL;
    }

    IONetworkInterface *self = (IONetworkInterface *)ifnet_softc(ifp);
    UInt8 mac[6] = { 0, 0, 0, 0, 0, 0 };
    UInt32 macLen = sizeof(mac);

    (void)self;
    /* The protocol module hands us the resolved link address; when it has
     * none (a limited broadcast before any ARP entry exists) the only
     * correct destination is the Ethernet broadcast address. */
    if (dest_linkaddr != NULL) {
        bcopy(dest_linkaddr, eh.ether_dhost, ETHER_ADDR_LEN);
    } else {
        memset(eh.ether_dhost, 0xff, ETHER_ADDR_LEN);
    }
    if (self != NULL && self->getController() != NULL) {
        IOEthernetController *eth =
            OSDynamicCast(IOEthernetController, self->getController());
        if (eth != NULL) {
            eth->getHardwareAddress(mac, &macLen);
        }
    }
    bcopy(mac, eh.ether_shost, ETHER_ADDR_LEN);
    bcopy(frame_type, &eh.ether_type, sizeof(eh.ether_type));

    if (mbuf_prepend(packet, sizeof(eh), MBUF_WAITOK) != 0) {
        return ENOBUFS;
    }
    bcopy(&eh, mbuf_data(*packet), sizeof(eh));
    return 0;
}

bool
IONetworkInterface::attachInterface()
{
    struct ifnet_init_eparams init;
    IONetworkController *controller = fController;
    IOEthernetController *ethernet = OSDynamicCast(IOEthernetController, controller);
    UInt8 mac[6] = { 0, 0, 0, 0, 0, 0 };
    UInt32 macLen = sizeof(mac);
    static const UInt8 broadcast[6] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
    errno_t result;

    if (fIfnet != NULL) {
        return true;
    }
    if (controller == NULL || ethernet == NULL) {
        return false;
    }
    if (!ethernet->getHardwareAddress(mac, &macLen) || macLen != sizeof(mac)) {
        IOLog("IONetworkInterface: controller has no hardware address\n");
        return false;
    }

    /* Extended allocation on purpose: only this path copies broadcast_addr
     * into ifp->if_broadcast.  With the legacy allocator the field stays
     * empty, ifnet_llbroadcast_copy_bytes() returns ENXIO, the Ethernet
     * framer cannot resolve 255.255.255.255 and the frame leaves with an
     * uninitialised header (measured on the wire: destination MAC
     * 02:0f:ff:ff:ff:ff instead of ff:ff:ff:ff:ff:ff). */
    bzero(&init, sizeof(init));
    init.ver             = IFNET_INIT_CURRENT_VERSION;
    init.len             = sizeof(init);
    init.flags           = IFNET_INIT_LEGACY | IFNET_INIT_NX_NOAUTO;
    init.name            = "en";
    init.unit            = fUnit;
    init.family          = IFNET_FAMILY_ETHERNET;
    init.type            = IFT_ETHER;
    init.output          = &IONetworkInterface::sOutput;
    init.framer          = &IONetworkInterface::sFramer;
    init.demux           = &ether_demux;
    init.add_proto       = &ether_add_proto;
    init.del_proto       = &ether_del_proto;
    init.check_multi     = &ether_check_multi;
    init.softc           = this;
    init.broadcast_addr  = broadcast;
    init.broadcast_len   = sizeof(broadcast);

    result = ifnet_allocate_extended(&init, &fIfnet);
    if (result != 0) {
        IOLog("IONetworkInterface: ifnet_allocate failed (%d)\n", result);
        fIfnet = NULL;
        return false;
    }

    ifnet_set_mtu(fIfnet, 1500);
    ifnet_set_hdrlen(fIfnet, sizeof(struct ether_header));

    result = ifnet_attach(fIfnet, NULL);
    if (result != 0) {
        IOLog("IONetworkInterface: ifnet_attach failed (%d)\n", result);
        /* No detach happened, so the stack still owns the ifnet; leave it
         * rather than freeing storage the stack may reference.  This path
         * only runs when a driver half-initialised. */
        fIfnet = NULL;
        return false;
    }

    /* ifnet_set_lladdr() refuses while the interface is embryonic
     * (IFRF_EMBRYONIC, ENXIO), so the hardware address has to be installed
     * after ifnet_attach().  Setting it before attach silently left
     * sdl_alen == 0, which made SIOCGIFLLADDR fail with EADDRNOTAVAIL and
     * left a DHCP client with no chaddr to send. */
    /* if_addrlen starts at 0 for a KPI-allocated ifnet, and
     * ifnet_set_lladdr() rejects (EINVAL) any length that does not match it.
     * Ethernet addresses are six bytes. */
    ifnet_set_addrlen(fIfnet, sizeof(mac));
    result = ifnet_set_lladdr(fIfnet, mac, sizeof(mac));
    if (result != 0) {
        IOLog("IONetworkInterface: ifnet_set_lladdr failed (%d)\n", result);
        ifnet_detach(fIfnet);
        fIfnet = NULL;
        return false;
    }
    ifnet_set_flags(fIfnet, IFF_BROADCAST | IFF_MULTICAST,
                    IFF_BROADCAST | IFF_MULTICAST);

    IOLog("IONetworkInterface: %s attached, %02x:%02x:%02x:%02x:%02x:%02x\n",
        ifnet_name(fIfnet), mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    return true;
}

void
IONetworkInterface::detachInterface()
{
    if (fIfnet != NULL) {
        ifnet_detach(fIfnet);
        fIfnet = NULL;
    }
}

void
IONetworkInterface::inputPacket(mbuf_t packet)
{
    if (packet == NULL) {
        return;
    }
    if (fIfnet == NULL) {
        mbuf_freem(packet);
        return;
    }
    /* The stack takes the link-layer header from m_pkthdr.pkt_hdr and hands
     * that pointer to the demux.  Leaving it NULL makes ether_demux read
     * eh->ether_type through a null pointer (measured: page fault at
     * ether_demux+0x44, CR2 = 0xc) the first time a frame is received. */
    if ((mbuf_flags(packet) & MBUF_PKTHDR) != 0) {
        /* The demux classifies the frame from m_pkthdr.pkt_hdr, but the
         * protocol input (ip_input) expects m_data to start at the network
         * header.  Hand up the link header in pkt_hdr and strip it from the
         * packet itself: leaving it in place made ip_input read the MAC
         * addresses as an IP header and drop every frame (no UDP input, no
         * DHCP OFFER, no log). */
        /* Do NOT use mbuf_adj() here: on a packet mbuf it releases the
         * leading space, and the demux then reads a zeroed frame header
         * (measured: eth_dhost 00:00:00:00:00:00, ether_type 0x0000), marks
         * every unicast frame M_PROMISC and dlil frees it before any
         * protocol sees it.  Moving only the data pointer keeps the header
         * bytes behind m_data where pkt_hdr points. */
        mbuf_pkthdr_setheader(packet, mbuf_data(packet));
        mbuf_adj(packet, sizeof(struct ether_header));
        mbuf_pkthdr_setrcvif(packet, fIfnet);
        /* ip_input() asserts that the receiving interface is recorded on
         * the packet; a driver that skips this panics the machine on the
         * first inbound frame (measured: assertion inifp != NULL at
         * ip_input.c:1745). */
        mbuf_pkthdr_setrcvif(packet, fIfnet);
    }
    /* ifnet_input takes ownership: it frees the chain if demux fails. */
    (void)ifnet_input(fIfnet, packet, NULL);
}

/* --------------------------------------------------------------- controller */

bool
IONetworkController::start(IOService *provider)
{
    if (!super::start(provider)) {
        return false;
    }

    fInterface = createInterface();
    if (fInterface == NULL) {
        IOLog("IONetworkController: createInterface failed\n");
        return false;
    }
    if (!fInterface->attachInterface()) {
        fInterface->release();
        fInterface = NULL;
        return false;
    }
    if (enable(fInterface) != kIOReturnSuccess) {
        IOLog("IONetworkController: enable failed\n");
        fInterface->detachInterface();
        fInterface->release();
        fInterface = NULL;
        return false;
    }
    return true;
}

void
IONetworkController::stop(IOService *provider)
{
    if (fInterface != NULL) {
        disable(fInterface);
        fInterface->detachInterface();
        fInterface->release();
        fInterface = NULL;
    }
    super::stop(provider);
}

IOReturn
IONetworkController::enable(IONetworkInterface *interface)
{
    (void)interface;
    return kIOReturnSuccess;
}

IOReturn
IONetworkController::disable(IONetworkInterface *interface)
{
    (void)interface;
    return kIOReturnSuccess;
}

IONetworkInterface *
IONetworkController::createInterface()
{
    return IONetworkInterface::withController(this);
}

/* --------------------------------------------------------------- ethernet */

IOReturn
IOEthernetController::setMulticastMode(bool enabled)
{
    (void)enabled;
    return kIOReturnSuccess;
}

IOReturn
IOEthernetController::setPromiscuousMode(bool enabled)
{
    (void)enabled;
    return kIOReturnSuccess;
}
