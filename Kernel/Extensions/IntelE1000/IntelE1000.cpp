/*
 * IntelE1000 driver implementation.
 *
 * Copyright (C) 2026 ravynOS Project. All rights reserved.
 *
 * Scope: the QEMU e1000 (8086:100e) and the 82574/82579 parts used in the
 * supported Intel Macs.  Receive is drained by a 10 ms timer on a workloop
 * rather than an interrupt source: the ring protocol is identical, and a
 * polling driver that demonstrably moves packets is a better first step than
 * an interrupt path nobody can watch.  The timer is a real IOTimerEventSource,
 * not a busy loop.
 */

#include <IOKit/IOLib.h>
#include <net/kpi_interface.h>
#include <sys/kpi_mbuf.h>
#include <sys/kpi_mbuf.h>
#include <net/ethernet.h>

#include "IntelE1000.h"

#define super IOEthernetController
OSDefineMetaClassAndStructors(IntelE1000, IOEthernetController)

/* Registers (8254x) */
#define E1000_CTRL      0x0000
#define E1000_STATUS    0x0008
#define E1000_ICR       0x00C0
#define E1000_IMS       0x00D0
#define E1000_IMC       0x00D8
#define E1000_RCTL      0x0100
#define E1000_TCTL      0x0400
#define E1000_TIPG      0x0410
#define E1000_RDBAL     0x2800
#define E1000_RDBAH     0x2804
#define E1000_RDLEN     0x2808
#define E1000_RDH       0x2810
#define E1000_RDT       0x2818
#define E1000_TDBAL     0x3800
#define E1000_TDBAH     0x3804
#define E1000_TDLEN     0x3808
#define E1000_TDH       0x3810
#define E1000_TDT       0x3818
#define E1000_RAL       0x5400
#define E1000_RAH       0x5404

/* CTRL */
#define E1000_CTRL_FD       0x00000001
#define E1000_CTRL_LRST     0x00000008
#define E1000_CTRL_ASDE     0x00000020
#define E1000_CTRL_SLU      0x00000040
#define E1000_CTRL_RST      0x04000000

/* STATUS */
#define E1000_STATUS_LU     0x00000002

/* RCTL */
#define E1000_RCTL_EN       0x00000002
#define E1000_RCTL_SBP      0x00000004
#define E1000_RCTL_UPE      0x00000008
#define E1000_RCTL_MPE      0x00000010
#define E1000_RCTL_BAM      0x00008000
#define E1000_RCTL_SECRC    0x04000000

/* TCTL */
#define E1000_TCTL_EN       0x00000002
#define E1000_TCTL_PSP      0x00000008
#define E1000_TCTL_CT       0x00000100
#define E1000_TCTL_COLD     0x00040000

/* Descriptor bits */
#define E1000_TXD_CMD_EOP   0x01
#define E1000_TXD_CMD_IFCS  0x02
#define E1000_TXD_CMD_RS    0x08
#define E1000_TXD_STAT_DD   0x01
#define E1000_RXD_STAT_DD   0x01
#define E1000_RXD_STAT_EOP  0x02

static bool
readMemoryBAR(IOPCIDevice *provider, UInt8 reg, UInt64 *base, UInt64 *size)
{
    UInt16 cmd = provider->configRead16(kIOPCIConfigCommand);
    UInt32 lo = provider->configRead32(reg);
    bool is64 = ((lo & 0x6) == 0x4);
    UInt32 hi = is64 ? provider->configRead32(reg + 4) : 0;

    if (lo & 0x1) {
        return false;                       /* I/O BAR, not MMIO */
    }

    provider->configWrite16(kIOPCIConfigCommand, cmd & ~(UInt16)0x3);
    provider->configWrite32(reg, 0xffffffffU);
    if (is64) provider->configWrite32(reg + 4, 0xffffffffU);

    UInt32 sizeLo = provider->configRead32(reg);
    UInt32 sizeHi = is64 ? provider->configRead32(reg + 4) : 0;

    provider->configWrite32(reg, lo);
    if (is64) provider->configWrite32(reg + 4, hi);
    provider->configWrite16(kIOPCIConfigCommand, cmd);

    UInt64 b = (UInt64)(lo & ~0xfU);
    UInt64 sz = (UInt64)(sizeLo & ~0xfU);
    if (is64) {
        b  |= (UInt64)hi << 32;
        sz |= (UInt64)sizeHi << 32;
    }
    *base = b;
    *size = sz ? (~sz + 1) : 0;
    return *base != 0 && *size != 0;
}


bool
IntelE1000::start(IOService *provider)
{
    fProvider = OSDynamicCast(IOPCIDevice, provider);
    if (fProvider == NULL) {
        return false;
    }
    if (!initHardware()) {
        return false;
    }
    /* The family creates the BSD interface and attaches it; it queries
     * getHardwareAddress(), so the MAC must be valid by now. */
    if (!super::start(provider)) {
        return false;
    }

    fWorkLoop = IOWorkLoop::workLoop();
    if (fWorkLoop != NULL) {
        fTimer = IOTimerEventSource::timerEventSource(this,
            &IntelE1000::timerFiredStatic);
        if (fTimer != NULL && fWorkLoop->addEventSource(fTimer) == kIOReturnSuccess) {
            fTimer->setTimeoutUS(10000);    /* 100 Hz receive poll */
        } else {
            if (fTimer != NULL) {
                fTimer->release();
                fTimer = NULL;
            }
        }
    }

    registerService();
    IOLog("IntelE1000: up, %02x:%02x:%02x:%02x:%02x:%02x\n",
        fMAC[0], fMAC[1], fMAC[2], fMAC[3], fMAC[4], fMAC[5]);
    return true;
}

void
IntelE1000::stop(IOService *provider)
{
    if (fTimer != NULL) {
        fTimer->cancelTimeout();
        if (fWorkLoop != NULL) {
            fWorkLoop->removeEventSource(fTimer);
        }
        fTimer->release();
        fTimer = NULL;
    }
    if (fWorkLoop != NULL) {
        fWorkLoop->release();
        fWorkLoop = NULL;
    }
    if (fBAR != NULL) {
        writeReg(E1000_RCTL, 0);
        writeReg(E1000_TCTL, 0);
        writeReg(E1000_IMC, 0xffffffff);
    }
    super::stop(provider);
}

void
IntelE1000::free()
{
    if (fBARMap != NULL) { fBARMap->release(); fBARMap = NULL; }
    if (fTxRingMem != NULL) { fTxRingMem->release(); fTxRingMem = NULL; }
    if (fRxRingMem != NULL) { fRxRingMem->release(); fRxRingMem = NULL; }
    if (fTxBufMem != NULL) { fTxBufMem->release(); fTxBufMem = NULL; }
    if (fRxBufMem != NULL) { fRxBufMem->release(); fRxBufMem = NULL; }
    super::free();
}

UInt32
IntelE1000::readReg(UInt32 reg)
{
    return *(volatile UInt32 *)(fBAR + reg);
}

void
IntelE1000::writeReg(UInt32 reg, UInt32 value)
{
    *(volatile UInt32 *)(fBAR + reg) = value;
}

bool
IntelE1000::readMAC(UInt8 mac[6])
{
    UInt32 ral = readReg(E1000_RAL);
    UInt32 rah = readReg(E1000_RAH);

    if (ral == 0 && (rah & 0xffff) == 0) {
        return false;
    }
    mac[0] = (UInt8)(ral);
    mac[1] = (UInt8)(ral >> 8);
    mac[2] = (UInt8)(ral >> 16);
    mac[3] = (UInt8)(ral >> 24);
    mac[4] = (UInt8)(rah);
    mac[5] = (UInt8)(rah >> 8);
    return true;
}

void
IntelE1000::resetHardware()
{
    writeReg(E1000_IMC, 0xffffffff);
    writeReg(E1000_CTRL, readReg(E1000_CTRL) | E1000_CTRL_RST);
    for (int i = 0; i < 1000; i++) {
        if ((readReg(E1000_CTRL) & E1000_CTRL_RST) == 0) {
            break;
        }
        IOSleep(1);
    }
    writeReg(E1000_CTRL, E1000_CTRL_SLU | E1000_CTRL_ASDE | E1000_CTRL_FD);
}

bool
IntelE1000::initHardware()
{
    UInt16 cmd = fProvider->configRead16(kIOPCIConfigCommand);

    /* Bus-master and memory space must be on before the BAR is usable. */
    cmd |= 0x0006;      /* MEMORY | MASTER */
    fProvider->configWrite16(kIOPCIConfigCommand, cmd);

    fBARMap = fProvider->mapDeviceMemoryWithRegister(kIOPCIConfigBaseAddress0, 0);
    if (fBARMap == NULL) {
        /* The device nub was published by the PCI bridge, but this tree does
         * not always have a memory range assigned for it, so fall back to the
         * BAR the firmware left in config space (same technique as the AHCI
         * kext's ABAR fallback). */
        UInt64 barBase = 0, barSize = 0;
        if (!readMemoryBAR(fProvider, kIOPCIConfigBaseAddress0, &barBase, &barSize)) {
            IOLog("IntelE1000: BAR0 is not a usable memory BAR\n");
            return false;
        }
        /* A 64-bit BAR whose upper half is not implemented reads back all
         * ones, which makes the size arithmetic nonsense (measured:
         * 0xffffffff00020000).  The register window this driver touches ends
         * at 0x5404, so 128 KB is both sufficient and safe. */
        if (barSize < 0x1000 || barSize > 0x1000000) {
            barSize = 0x20000;
        }
        IOLog("IntelE1000: BAR0 phys=0x%llx size=0x%llx\n",
            (unsigned long long)barBase, (unsigned long long)barSize);
        IOMemoryDescriptor *desc = IOMemoryDescriptor::withPhysicalAddress(
            (IOPhysicalAddress)barBase, (IOByteCount)barSize,
            kIODirectionNone | kIOMemoryMapperNone);
        if (desc == NULL) {
            return false;
        }
        fBARMap = desc->map(kIOMapAnywhere);
        desc->release();
        if (fBARMap == NULL) {
            IOLog("IntelE1000: cannot map BAR0 at 0x%llx\n",
                (unsigned long long)barBase);
            return false;
        }
    }
    fBAR = (volatile UInt8 *)fBARMap->getVirtualAddress();

    resetHardware();

    if (!readMAC(fMAC)) {
        IOLog("IntelE1000: no MAC address in RAL/RAH\n");
        return false;
    }

    fTxRingMem = IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,
        kIOMemoryPhysicallyContiguous | kIODirectionInOut,
        sizeof(struct e1000_tx_desc) * E1000_TX_RING_SIZE, 0xffffffffULL);
    fRxRingMem = IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,
        kIOMemoryPhysicallyContiguous | kIODirectionInOut,
        sizeof(struct e1000_rx_desc) * E1000_RX_RING_SIZE, 0xffffffffULL);
    fTxBufMem = IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,
        kIOMemoryPhysicallyContiguous | kIODirectionInOut,
        E1000_TX_BUFSIZE * E1000_TX_RING_SIZE, 0xffffffffULL);
    fRxBufMem = IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,
        kIOMemoryPhysicallyContiguous | kIODirectionInOut,
        E1000_RX_BUFSIZE * E1000_RX_RING_SIZE, 0xffffffffULL);

    if (!fTxRingMem || !fRxRingMem || !fTxBufMem || !fRxBufMem) {
        IOLog("IntelE1000: descriptor/buffer allocation failed\n");
        return false;
    }

    fTxRing = (volatile struct e1000_tx_desc *)fTxRingMem->getBytesNoCopy();
    fRxRing = (volatile struct e1000_rx_desc *)fRxRingMem->getBytesNoCopy();
    fTxBufs = (UInt8 *)fTxBufMem->getBytesNoCopy();
    fRxBufs = (UInt8 *)fRxBufMem->getBytesNoCopy();
    if (!fTxRing || !fRxRing || !fTxBufs || !fRxBufs) {
        return false;
    }

    bzero((void *)fTxRing, (size_t)fTxRingMem->getLength());
    bzero((void *)fRxRing, (size_t)fRxRingMem->getLength());

    /* TX ring */
    UInt64 txPhys = fTxRingMem->getPhysicalAddress();
    UInt64 txBufPhys = fTxBufMem->getPhysicalAddress();

    for (UInt32 i = 0; i < E1000_TX_RING_SIZE; i++) {
        fTxRing[i].addr = txBufPhys + (UInt64)i * E1000_TX_BUFSIZE;
        fTxRing[i].status = E1000_TXD_STAT_DD;   /* free */
    }
    writeReg(E1000_TDBAL, (UInt32)txPhys);
    writeReg(E1000_TDBAH, (UInt32)(txPhys >> 32));
    writeReg(E1000_TDLEN, sizeof(struct e1000_tx_desc) * E1000_TX_RING_SIZE);
    writeReg(E1000_TDH, 0);
    writeReg(E1000_TDT, 0);
    fTxTail = 0;

    /* RX ring */
    UInt64 rxPhys = fRxRingMem->getPhysicalAddress();
    UInt64 rxBufPhys = fRxBufMem->getPhysicalAddress();

    for (UInt32 i = 0; i < E1000_RX_RING_SIZE; i++) {
        fRxRing[i].addr = rxBufPhys + (UInt64)i * E1000_RX_BUFSIZE;
        fRxRing[i].status = 0;
    }
    writeReg(E1000_RDBAL, (UInt32)rxPhys);
    writeReg(E1000_RDBAH, (UInt32)(rxPhys >> 32));
    writeReg(E1000_RDLEN, sizeof(struct e1000_rx_desc) * E1000_RX_RING_SIZE);
    writeReg(E1000_RDH, 0);
    writeReg(E1000_RDT, E1000_RX_RING_SIZE - 1);
    fRxHead = 0;

    /* Program the unicast filter explicitly.  Reading RAL/RAH only tells us
     * what the EEPROM loaded; the Address Valid bit in RAH is what makes the
     * receiver accept a frame addressed to this MAC, and without it every
     * unicast frame (a DHCP OFFER, for one) is dropped in hardware. */
    writeReg(E1000_RAL, (UInt32)fMAC[0] | ((UInt32)fMAC[1] << 8) |
        ((UInt32)fMAC[2] << 16) | ((UInt32)fMAC[3] << 24));
    writeReg(E1000_RAH, (UInt32)fMAC[4] | ((UInt32)fMAC[5] << 8) | 0x80000000u);

    /* Filters: broadcast + own MAC, multicast off. */
    writeReg(E1000_RCTL, E1000_RCTL_EN | E1000_RCTL_BAM | E1000_RCTL_SECRC);
    writeReg(E1000_TCTL, E1000_TCTL_EN | E1000_TCTL_PSP |
        (0x10 << 4) | (0x40 << 12));
    writeReg(E1000_TIPG, 0x0060200A);

    writeReg(E1000_IMC, 0xffffffff);    /* no interrupts: timer polls */
    writeReg(E1000_ICR, 0xffffffff);
    return true;
}

bool
IntelE1000::getHardwareAddress(void *addr, UInt32 *len)
{
    if (addr == NULL || len == NULL || *len < sizeof(fMAC)) {
        return false;
    }
    memcpy(addr, fMAC, sizeof(fMAC));
    *len = sizeof(fMAC);
    return true;
}

UInt32
IntelE1000::outputPacket(mbuf_t packet, void *param)
{
    (void)param;

    if (packet == NULL) {
        return kIOReturnBadArgument;
    }
    if (fBAR == NULL || fTxRing == NULL) {
        mbuf_freem(packet);
        return kIOReturnNotReady;
    }

    size_t len = mbuf_pkthdr_len(packet);
    if (len == 0 || len > E1000_TX_BUFSIZE) {
        mbuf_freem(packet);
        return kIOReturnBadArgument;
    }

    UInt32 tail = fTxTail;
    if ((fTxRing[tail].status & E1000_TXD_STAT_DD) == 0) {
        /* Ring full: one short wait for the hardware, then drop. */
        for (int i = 0; i < 100; i++) {
            if (fTxRing[tail].status & E1000_TXD_STAT_DD) {
                break;
            }
            IOSleep(1);
        }
        if ((fTxRing[tail].status & E1000_TXD_STAT_DD) == 0) {
            mbuf_freem(packet);
            return kIOReturnNoResources;
        }
    }

    if (mbuf_copydata(packet, 0, len, fTxBufs + tail * E1000_TX_BUFSIZE) != 0) {
        mbuf_freem(packet);
        return kIOReturnBadArgument;
    }
    mbuf_freem(packet);

    fTxRing[tail].length = (UInt16)len;
    fTxRing[tail].cso = 0;
    fTxRing[tail].css = 0;
    fTxRing[tail].special = 0;
    fTxRing[tail].status = 0;
    fTxRing[tail].cmd = E1000_TXD_CMD_EOP | E1000_TXD_CMD_IFCS |
        E1000_TXD_CMD_RS;

    fTxTail = (tail + 1) % E1000_TX_RING_SIZE;
    writeReg(E1000_TDT, fTxTail);

    /* Opportunistically drain receive while we are here. */
    receivePackets();
    return kIOReturnSuccess;
}

void
IntelE1000::receivePackets()
{
    if (fRxRing == NULL) {
        return;
    }

    for (UInt32 budget = 0; budget < E1000_RX_RING_SIZE; budget++) {
        UInt32 head = fRxHead;
        UInt8 status = fRxRing[head].status;

        if ((status & E1000_RXD_STAT_DD) == 0) {
            break;
        }
        UInt16 len = fRxRing[head].length;
        if ((status & E1000_RXD_STAT_EOP) && len > 0 && len <= E1000_RX_BUFSIZE) {
            mbuf_t m = NULL;
            /* mbuf_allocpacket() returns a zero-length packet-header mbuf
             * with the frame bytes chained after it, so the demux read the
             * link header from an empty head (measured: dhost
             * 00:00:00:00:00:00, ether_type 0x0000, every unicast frame
             * marked M_PROMISC and freed).  A header mbuf followed by one
             * cluster keeps the link header in the head, where
             * m_pkthdr.pkt_hdr can point. */
            if (mbuf_gethdr(MBUF_WAITOK, MBUF_TYPE_DATA, &m) == 0 && m != NULL) {
                mbuf_t cluster = NULL;
                if (len > 0 &&
                    mbuf_getcluster(MBUF_WAITOK, MBUF_TYPE_DATA, (size_t)len,
                        &cluster) == 0 && cluster != NULL) {
                    mbuf_setnext(m, cluster);
                }
                if (mbuf_copyback(m, 0, len,
                        fRxBufs + head * E1000_RX_BUFSIZE, MBUF_WAITOK) == 0) {
                    IONetworkInterface *iface = getInterface();
                    if (iface != NULL) {
                        iface->inputPacket(m);
                    } else {
                        mbuf_freem(m);
                    }
                } else {
                    mbuf_freem(m);
                }
            }
        }

        fRxRing[head].status = 0;
        fRxHead = (head + 1) % E1000_RX_RING_SIZE;
        writeReg(E1000_RDT, head);
    }

    /* Link state bookkeeping once per poll. */
    bool up = (readReg(E1000_STATUS) & E1000_STATUS_LU) != 0;
    if (up != fLinkUp) {
        fLinkUp = up;
        /* The IPv4 output module refuses to frame a packet unless the
         * interface is both UP and RUNNING (ether_inet_pr_module.c), and the
         * stack never sets RUNNING on its own: link state is the driver's
         * only evidence for it. */
        IONetworkInterface *iface = getInterface();
        if (iface != NULL && iface->getIfnet() != NULL) {
            if (up) {
                ifnet_set_flags(iface->getIfnet(), IFF_RUNNING, IFF_RUNNING);
            } else {
                ifnet_set_flags(iface->getIfnet(), 0, IFF_RUNNING);
            }
        }
        IOLog("IntelE1000: link %s\n", up ? "up" : "down");
    }
}

void
IntelE1000::timerFiredStatic(OSObject *owner, IOTimerEventSource *sender)
{
    (void)sender;
    IntelE1000 *self = OSDynamicCast(IntelE1000, owner);
    if (self != NULL) {
        self->timerFired();
    }
}

void
IntelE1000::timerFired()
{
    receivePackets();
    if (fTimer != NULL) {
        fTimer->setTimeoutUS(10000);
    }
}
