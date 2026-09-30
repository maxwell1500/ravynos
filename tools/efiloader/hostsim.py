#!/usr/bin/env python3
"""Load a packed EFI application into this process and run it against a
mock UEFI environment (ctypes).  This exercises the loader's real EFI
protocol code -- HandleProtocol / LocateHandle / OpenVolume / Open / Read
-- without needing QEMU, which another worker is using.

Usage: python3 hostsim.py <image.efi>
"""
import ctypes
import struct
import sys

KERNEL = '/Users/max/Projects/ravynos/tools/bootlab/work/stripped_kernel.development'

U64 = ctypes.c_uint64
VOIDP = ctypes.c_void_p
STATUS = ctypes.c_uint64

out = []


class SimpleTextOut(ctypes.Structure):
    _fields_ = [('Reserved', U64), ('Write', ctypes.CFUNCTYPE(
        STATUS, VOIDP, ctypes.POINTER(U64), ctypes.POINTER(ctypes.c_uint16)))]


def text_out_write(this, n, buf):
    n = n.contents.value
    for i in range(n):
        out.append(chr(buf[i]))
    return 0


class FileProto(ctypes.Structure):
    pass


OPEN = ctypes.CFUNCTYPE(STATUS, VOIDP, ctypes.POINTER(VOIDP),
                        ctypes.POINTER(ctypes.c_uint16), U64, VOIDP)
CLOSE = ctypes.CFUNCTYPE(STATUS, VOIDP)
READ = ctypes.CFUNCTYPE(STATUS, VOIDP, ctypes.POINTER(U64), VOIDP)
GETPOS = ctypes.CFUNCTYPE(STATUS, VOIDP, ctypes.POINTER(U64))
SETPOS = ctypes.CFUNCTYPE(STATUS, VOIDP, U64)


class FileStruct(ctypes.Structure):
    _fields_ = [('Revision', U64), ('Open', OPEN), ('Close', CLOSE),
                ('Delete', CLOSE), ('Read', READ), ('Write', READ),
                ('GetPosition', GETPOS), ('SetPosition', SETPOS),
                ('GetInfo', VOIDP), ('SetInfo', VOIDP), ('Flush', VOIDP)]


class RootFile(ctypes.Structure):
    _fields_ = [('Revision', U64), ('Open', OPEN), ('Close', CLOSE),
                ('Delete', CLOSE), ('Read', READ), ('Write', READ),
                ('GetPosition', GETPOS), ('SetPosition', SETPOS),
                ('GetInfo', VOIDP), ('SetInfo', VOIDP), ('Flush', VOIDP),
                ('impl', ctypes.py_object), ('pos', ctypes.c_size_t)]


OPENVOL = ctypes.CFUNCTYPE(STATUS, VOIDP, ctypes.POINTER(VOIDP))
class SimpleFS(ctypes.Structure):
    _fields_ = [('Revision', U64), ('OpenVolume', OPENVOL)]


class LoadedImage(ctypes.Structure):
    _fields_ = [('Revision', ctypes.c_uint32), ('FileHandle', VOIDP),
                ('DeviceHandle', VOIDP), ('ImageBase', VOIDP),
                ('ImageSize', U64), ('ImageCode', VOIDP), ('ImageData', VOIDP),
                ('Unload', U64)]


HANDLEPROTO = ctypes.CFUNCTYPE(STATUS, U64, VOIDP, ctypes.POINTER(VOIDP))
LOCATEHANDLE = ctypes.CFUNCTYPE(STATUS, ctypes.c_uint32, VOIDP, VOIDP,
                                ctypes.POINTER(U64), ctypes.POINTER(U64))
GETMEMMAP = ctypes.CFUNCTYPE(STATUS, ctypes.POINTER(U64), ctypes.POINTER(U64),
                             ctypes.POINTER(U64), ctypes.POINTER(U64),
                             ctypes.POINTER(U64))


class BootServices(ctypes.Structure):
    _fields_ = [('Hdr', ctypes.c_byte * 24), ('RaiseTPL', VOIDP),
                ('RestoreTPL', VOIDP), ('AllocatePages', VOIDP),
                ('FreePages', VOIDP), ('GetMemoryMap', GETMEMMAP),
                ('AllocatePool', VOIDP), ('FreePool', VOIDP),
                ('CreateEvent', VOIDP), ('SetTimer', VOIDP),
                ('WaitForEvent', VOIDP), ('SignalEvent', VOIDP),
                ('CloseEvent', VOIDP), ('CheckEvent', VOIDP),
                ('InstallProtocolInterface', VOIDP),
                ('ReinstallProtocolInterface', VOIDP),
                ('UninstallProtocolInterface', VOIDP),
                ('HandleProtocol', HANDLEPROTO), ('Reserved', U64),
                ('RegisterProtocolNotify', VOIDP), ('LocateHandle', LOCATEHANDLE)]


class SystemTable(ctypes.Structure):
    _fields_ = [('Hdr', ctypes.c_byte * 24), ('FirmwareVendor', U64),
                ('FirmwareRevision', ctypes.c_uint32), ('pad', ctypes.c_uint32),
                ('ConsoleInHandle', U64), ('ConIn', VOIDP),
                ('ConsoleOutHandle', U64), ('ConOut', ctypes.POINTER(SimpleTextOut)),
                ('StdErrHandle', U64), ('StdErr', VOIDP),
                ('RT', VOIDP), ('BS', ctypes.POINTER(BootServices)),
                ('NumberOfTableEntries', U64), ('ConfigurationTable', VOIDP)]


GUID_LI = (0x5B1B31A1, 0x9562, 0x11D2, (0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B))
GUID_FS = (0x964E5B22, 0x6459, 0x11D2, (0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B))


def guid_eq(a, b):
    """a/b are (u32,u16,u16,tuple8) packed as 16 bytes by the caller."""
    return a == b


def load_pe(path):
    d = open(path, 'rb').read()
    e = struct.unpack_from('<I', d, 0x3C)[0]
    nsec, = struct.unpack_from('<H', d, e + 6)
    optsz, = struct.unpack_from('<H', d, e + 20)
    oh = e + 24
    ep, = struct.unpack_from('<I', d, oh + 16)
    size_of_image, = struct.unpack_from('<I', d, oh + 56)
    subsys, = struct.unpack_from('<H', d, oh + 68)
    reloc_rva, reloc_size = struct.unpack_from('<II', d, oh + 112 + 5 * 8)
    buf = ctypes.create_string_buffer(size_of_image)
    so = oh + optsz
    sections = []
    for i in range(nsec):
        o = so + 40 * i
        name = d[o:o + 8].rstrip(b'\0').decode()
        vs, va, rawsz, rawptr = struct.unpack_from('<IIII', d, o + 8)
        sections.append((name, vs, va, rawsz, rawptr))
        if rawsz:
            ctypes.memmove(ctypes.byref(buf, va), d[rawptr:rawptr + rawsz], rawsz)
    # apply base relocations the way the DXE core would
    nrel = 0
    if reloc_size:
        i = 0
        while i < reloc_size:
            page, size = struct.unpack_from('<II', buf.raw, reloc_rva + i)
            for j in range(i + 8, i + size, 2):
                rtype, off = struct.unpack_from('<HH', buf.raw, reloc_rva + j)
                if rtype != 10:
                    raise SystemExit('unsupported reloc type %d' % rtype)
                addr = page + off
                v, = struct.unpack_from('<Q', buf.raw, addr)
                struct.pack_into('<Q', buf.raw, addr, v + size_of_image)
                nrel += 1
            i += size
    print('loaded %s: subsystem=%d entry=0x%x SizeOfImage=0x%x relocs=%d'
          % (path, subsys, ep, size_of_image, nrel))
    for s in sections:
        print('   %-8s vaddr 0x%06x vsize 0x%05x raw 0x%05x' % (s[0], s[2], s[1], s[3]))
    return buf, ep


def main():
    buf, ep = load_pe(sys.argv[1])
    image_base = ctypes.addressof(buf)

    sto = SimpleTextOut(0, ctypes.CFUNCTYPE(
        STATUS, VOIDP, ctypes.POINTER(U64),
        ctypes.POINTER(ctypes.c_uint16))(text_out_write))

    kernel = open(KERNEL, 'rb').read()

    def file_open(this, outp, namep, attrs, mode):
        name = []
        i = 0
        while namep[i]:
            name.append(chr(namep[i])); i += 1
        path = ''.join(name)
        if path.lower().endswith('kernel.development'):
            f = RootFile()
            f.impl = kernel
            f.pos = 0
            outp[0] = ctypes.cast(ctypes.pointer(f), VOIDP)
            return 0
        return 0x800000000000000E   # EFI_NOT_FOUND

    def file_read(this, size, bufp):
        f = ctypes.cast(this, ctypes.POINTER(RootFile)).contents
        n = min(size.contents.value, len(f.impl) - f.pos)
        ctypes.memmove(bufp, f.impl[f.pos:f.pos + n], n)
        f.pos += n
        size.contents.value = n
        return 0

    def file_close(this):
        return 0

    root = RootFile()
    root.impl = b''
    root.pos = 0
    root.Open = ctypes.CFUNCTYPE(STATUS, VOIDP, ctypes.POINTER(VOIDP),
                                 ctypes.POINTER(ctypes.c_uint16), U64, VOIDP)(file_open)
    root.Read = ctypes.CFUNCTYPE(STATUS, VOIDP, ctypes.POINTER(U64), VOIDP)(file_read)
    root.Close = ctypes.CFUNCTYPE(STATUS, VOIDP)(file_close)
    root.Delete = root.Close

    def open_volume(this, rootp):
        rootp[0] = ctypes.cast(ctypes.pointer(root), VOIDP)
        return 0

    fs = SimpleFS(0, ctypes.CFUNCTYPE(STATUS, VOIDP, ctypes.POINTER(VOIDP))(open_volume))
    li = LoadedImage(0x1000, 0, 0, image_base, 0, 0, 0, 0)

    def handle_protocol(handle, guidp, outp):
        g = ctypes.cast(guidp, ctypes.POINTER(ctypes.c_byte * 16)).contents
        gb = bytes(g)
        if gb == struct.pack('<IHH8B', *GUID_LI):
            outp[0] = ctypes.cast(ctypes.pointer(li), VOIDP)
            return 0
        if gb == struct.pack('<IHH8B', *GUID_FS):
            outp[0] = ctypes.cast(ctypes.pointer(fs), VOIDP)
            return 0
        return 0x8000000000000002

    fs_handle_buf = (U64 * 1)(0xF00D)
    fs_handle = ctypes.addressof(fs_handle_buf)

    def locate_handle(search, guidp, devp, nptr, bufp):
        nptr[0] = 1
        bufp[0] = fs_handle
        return 0

    def get_memory_map(mmsz, mm, key, dsz, dver):
        return 0x8000000000000004   # EFI_BUFFER_TOO_SMALL

    bs = BootServices()
    bs.HandleProtocol = ctypes.CFUNCTYPE(STATUS, U64, VOIDP, ctypes.POINTER(VOIDP))(handle_protocol)
    bs.LocateHandle = ctypes.CFUNCTYPE(STATUS, ctypes.c_uint32, VOIDP, VOIDP,
                                      ctypes.POINTER(U64), ctypes.POINTER(U64))(locate_handle)
    bs.GetMemoryMap = ctypes.CFUNCTYPE(STATUS, ctypes.POINTER(U64), ctypes.POINTER(U64),
                                       ctypes.POINTER(U64), ctypes.POINTER(U64),
                                       ctypes.POINTER(U64))(get_memory_map)

    st = SystemTable()
    st.ConOut = ctypes.pointer(sto)
    st.BS = ctypes.pointer(bs)

    wc = ctypes.CDLL('./libwincall.dylib')
    wc.win_call.restype = U64
    wc.win_call.argtypes = [U64, U64, U64]
    rc = wc.win_call(0x1234, ctypes.addressof(st), image_base + ep)
    print(''.join(out))
    print('efi_main returned 0x%x' % rc)


if __name__ == '__main__':
    main()
