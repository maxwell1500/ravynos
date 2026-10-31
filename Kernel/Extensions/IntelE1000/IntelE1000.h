/*
 * IntelE1000: driver for Intel 8254x/82574/82579 Ethernet controllers.
 *
 * Copyright (C) 2026 ravynOS Project. All rights reserved.
 */

#ifndef _INTELE1000_H
#define _INTELE1000_H

#include <IOKit/IOService.h>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/pci/IOPCIDevice.h>
#include "IONetworkFamily/IONetworkFamily.h"

#define E1000_TX_RING_SIZE  32
#define E1000_RX_RING_SIZE  128
#define E1000_TX_BUFSIZE    2048
#define E1000_RX_BUFSIZE    2048

struct e1000_tx_desc {
    UInt64 addr;
    UInt16 length;
    UInt8  cso;
    UInt8  cmd;
    UInt8  status;
    UInt8  css;
    UInt16 special;
} __attribute__((packed));

struct e1000_rx_desc {
    UInt64 addr;
    UInt16 length;
    UInt16 checksum;
    UInt8  status;
    UInt8  errors;
    UInt16 special;
} __attribute__((packed));

class IntelE1000 : public IOEthernetController
{
    OSDeclareDefaultStructors(IntelE1000)

public:
    virtual bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void free() APPLE_KEXT_OVERRIDE;

    virtual bool getHardwareAddress(void *addr, UInt32 *len) APPLE_KEXT_OVERRIDE;
    virtual UInt32 outputPacket(mbuf_t packet, void *param) APPLE_KEXT_OVERRIDE;

private:
    static void timerFiredStatic(OSObject *owner, IOTimerEventSource *sender);
    void timerFired();

    bool  initHardware();
    void  resetHardware();
    UInt32 readReg(UInt32 reg);
    void  writeReg(UInt32 reg, UInt32 value);
    bool  readMAC(UInt8 mac[6]);
    void  receivePackets();

    IOPCIDevice              *fProvider;
    IOMemoryMap              *fBARMap;
    volatile UInt8           *fBAR;
    IOTimerEventSource       *fTimer;
    IOWorkLoop               *fWorkLoop;

    IOBufferMemoryDescriptor *fTxRingMem;
    IOBufferMemoryDescriptor *fRxRingMem;
    IOBufferMemoryDescriptor *fTxBufMem;
    IOBufferMemoryDescriptor *fRxBufMem;

    volatile struct e1000_tx_desc *fTxRing;
    volatile struct e1000_rx_desc *fRxRing;
    UInt8                    *fTxBufs;
    UInt8                    *fRxBufs;

    UInt32                    fTxTail;
    UInt32                    fRxHead;
    UInt8                     fMAC[6];
    bool                      fLinkUp;
};

#endif /* _INTELE1000_H */
