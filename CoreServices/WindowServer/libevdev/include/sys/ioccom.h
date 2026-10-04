/* Minimal FreeBSD-compatible sys/ioccom.h for libevdev on macOS */
#ifndef _SYS_IOCCOM_H_
#define _SYS_IOCCOM_H_

#define IOC_IN          0x40000000
#define IOC_OUT         0x80000000
#define IOC_INOUT       (IOC_IN | IOC_OUT)
#define IOC_NONE        0x00000000

#define _IOC(inout,group,num,len) \
    ((inout) | (((len) & 0x1fff) << 16) | ((group) << 8) | (num))
#define _IOR(g,n,t)      _IOC(IOC_OUT, g, n, sizeof(t))
#define _IOW(g,n,t)      _IOC(IOC_IN, g, n, sizeof(t))
#define _IOWR(g,n,t)     _IOC(IOC_INOUT, g, n, sizeof(t))
#define _IOWINT(g,n)    _IOC(IOC_IN, g, n, sizeof(int))
#define _IO(g,n)        _IOC(IOC_NONE, g, n, 0)

#endif /* _SYS_IOCCOM_H_ */
