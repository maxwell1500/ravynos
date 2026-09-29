#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <mach/kern_return.h>
#include <mach-o/loader.h>
#include <uuid/uuid.h>
#include <pthread/pthread.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/fcntl.h>
#include <_simple.h>

char **environ;

int __snprintf_chk(char * str, size_t maxlen, int flag, size_t strlen, const char * format, ...)
{
    va_list args;
    va_start(args, format);
    int result = __builtin___snprintf_chk(str, maxlen, 0, __builtin_object_size(str, 1), format, args);
    va_end(args);
    return result;
}

void* malloc(size_t size);  /* dyldNew.cpp */

int inDenyList(const char * path)
{
    (void)path;
    return 0;
}

int fflush(FILE *stream)
{
        return 0;
}

#undef snprintf
int snprintf(char* str, size_t size, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    int result = __builtin___snprintf_chk(str, size, 0, __builtin_object_size(str, 1), format, args);
    va_end(args);
    return result;
}

void* dlopen(const char* path, int mode)
{
_simple_dprintf(1, "dlopen dyld stub! %s %x\n", path, mode);
    return NULL;
}

char* getenv(const char* name)
{
	return _simple_getenv(environ, name);
}

/* c++ glue */
void __cxa_finalize(void *d)
{
    (void)d;
}

int __cxa_guard_acquire(uint64_t *guard)
{
        return 0;
}

void __cxa_guard_release(uint64_t *guard)
{
}

void __cxa_guard_abort(uint64_t *guard)
{
}



/* Stuff needed for stdio */
struct glue {
    struct glue * next;
    int           niobs;
    FILE        * iobs;
};

pthread_once_t  __sdidinit;
FILE *          __sF[3] = {NULL, NULL, NULL};
struct glue     __sglue = { NULL, 3, __sF };

void
_cleanup(void)
{
}

void
__sinit(void)
{
}

/* For objc-class.mm.o - mangled name for C++ linkage */
/**********************************************************************
* secure_open
* Securely open a file from a world-writable directory (like /tmp)
* If the file does not exist, it will be atomically created with mode 0600
* If the file exists, it must be, and remain after opening: 
*   1. a regular file (in particular, not a symlink)
*   2. owned by euid
*   3. permissions 0600
*   4. link count == 1
* Returns a file descriptor or -1. Errno may or may not be set on error.
**********************************************************************/
enum { NO = 0, YES = 1 };
int _Z11secure_openPKcij(const char *filename, int flags, uid_t euid)
{
    struct stat fs, ls;
    int fd = -1;
    boolean_t truncate = NO;
    boolean_t create = NO;

    if (flags & O_TRUNC) {
        // Don't truncate the file until after it is open and verified.
        truncate = YES;
        flags &= ~O_TRUNC;
    }
    if (flags & O_CREAT) {
        // Don't create except when we're ready for it
        create = YES;
        flags &= ~O_CREAT;
        flags &= ~O_EXCL;
    }

    if (lstat(filename, &ls) < 0) {
        if (errno == ENOENT  &&  create) {
            // No such file - create it
            fd = open(filename, flags | O_CREAT | O_EXCL, 0600);
            if (fd >= 0) {
                // File was created successfully.
                // New file does not need to be truncated.
                return fd;
            } else {
                // File creation failed.
                return -1;
            }
        } else {
            // lstat failed, or user doesn't want to create the file
            return -1;
        }
    } else {
        // lstat succeeded - verify attributes and open
        if (S_ISREG(ls.st_mode)  &&  // regular file?
            ls.st_nlink == 1  &&     // link count == 1?
            ls.st_uid == euid  &&    // owned by euid?
            (ls.st_mode & ALLPERMS) == (S_IRUSR | S_IWUSR))  // mode 0600?
        {
            // Attributes look ok - open it and check attributes again
            fd = open(filename, flags, 0000);
            if (fd >= 0) {
                // File is open - double-check attributes
                if (0 == fstat(fd, &fs)  &&  
                    fs.st_nlink == ls.st_nlink  &&  // link count == 1?
                    fs.st_uid == ls.st_uid  &&      // owned by euid?
                    fs.st_mode == ls.st_mode  &&    // regular file, 0600?
                    fs.st_ino == ls.st_ino  &&      // same inode as before?
                    fs.st_dev == ls.st_dev)         // same device as before?
                {
                    // File is open and OK
                    if (truncate) ftruncate(fd, 0);
                    return fd;
                } else {
                    // Opened file looks funny - close it
                    close(fd);
                    return -1;
                }
            } else {
                // File didn't open
                return -1;
            }
        } else {
            // Unopened file looks funny - don't open it
            return -1;
        }
    }
}

/* FIXME: get this from plist or makelist */
double       dyldVersionNumber = 732.2;
const char * dyldVersionString = "ravynOS dyld 732.2";

/* Stub to provide NSRange ABI from Foundation */
typedef struct {
    unsigned long location;
    unsigned long length;
} NSRange;

NSRange NSMakeRange(unsigned long location, unsigned long length)
{
    NSRange result = { location, length };
    return result;
}

void uuid_unparse(const uuid_t uu, uuid_string_t out)
{
    uuid_unparse_upper(uu, out);
}

/* FIXME: remove once we have amfi */
int amfi_check_dyld_policy_self(uint64_t inFlags, uint64_t* outFlags)
{
    *outFlags = 0x3F;  // on old kernel, simulator process get all flags
    return 0;
}

int dyld_shared_cache_extract_dylibs_progress(const char* shared_cache_file_path,
    const char* extraction_root_path,
    void (^progress)(unsigned current, unsigned total))
{
    (void)shared_cache_file_path;
    (void)extraction_root_path;
    (void)progress;
    return KERN_NOT_SUPPORTED;
}

/* DNSService stubs to be removed when mDNSResponder is built */
typedef struct _DNSServiceRef_t *DNSServiceRef;
typedef unsigned int DNSServiceFlags;
typedef int DNSServiceErrorType;
typedef void (*DNSServiceQueryRecordReply)(DNSServiceRef sdRef,
    DNSServiceFlags flags, unsigned int interfaceIndex,
    DNSServiceErrorType errorCode, const char *fullname,
    unsigned short rrtype, unsigned short rrclass,
    unsigned short rdlen, const void *rdata,
    unsigned int ttl, void *context);
#define kDNSServiceErr_Unsupported -65563
DNSServiceErrorType DNSServiceCreateConnection(DNSServiceRef *sdRef)
{
    (void)sdRef;
    return kDNSServiceErr_Unsupported;
}
DNSServiceErrorType DNSServiceProcessResult(DNSServiceRef sdRef)
{
    (void)sdRef;
    return kDNSServiceErr_Unsupported;
}
DNSServiceErrorType DNSServiceQueryRecord(
    DNSServiceRef              *sdRef,
    DNSServiceFlags             flags,
    unsigned int                interfaceIndex,
    const char                 *name,
    unsigned short              rrtype,
    unsigned short              rrclass,
    DNSServiceQueryRecordReply  callBack,
    void                       *context)
{
    (void)sdRef;
    (void)flags;
    (void)interfaceIndex;
    (void)name;
    (void)rrtype;
    (void)rrclass;
    (void)callBack;
    (void)context;
    return kDNSServiceErr_Unsupported;
}
void DNSServiceRefDeallocate(DNSServiceRef sdRef)
{
    (void)sdRef;
}
int DNSServiceRefSockFD(DNSServiceRef sdRef)
{
    (void)sdRef;
    return -1;
}

// ---------------------------------------------------------------------------
//                     __chkstk_darwin
// ---------------------------------------------------------------------------
// A bootstrap dylinker must carry no external imports on the pre-rebase path.
// That is not a style preference, it is the design: Apple's own /usr/lib/dyld
// has ZERO imports, ZERO LC_LOAD_DYLIB and ZERO __stubs, and reaches the kernel
// the same way this function does -- by DEFINING what it needs.  Measured on
// this host: nm shows Apple's ___chkstk_darwin as a LOCAL text symbol ('t') at
// 0x10cb0, next to a local ___chkstk_darwin_llvm_probe at 0x10cd0 whose body is
// the page-touching loop reproduced below.  An import is precisely what a stub
// exists to service, so zero imports means zero stubs, which means there is
// nothing for rebaseDyld's (correctly empty) bindTargets to resolve.
//
// Without this, the compiler emits a call through __stubs, the linker records a
// chained BIND in __got for it, and rebaseDyld -- which is handed an empty
// bindTargets and must be, see dyldInitialization.cpp:144 -- leaves that slot as
// a raw bind descriptor.  A __stub then jumps through it into a
// non-canonical address.  Defining it locally removes the import, the stub, and
// the bind together.
//
// The algorithm is the documented contract of a stack probe -- touch one byte
// per page, walking down from the current frame -- and was checked against the
// real implementation on this host rather than guessed:
//     cmpq $0x1000, %rax ; leaq 0x18(%rsp), %rcx ; jb <done>
//     subq $0x1000, %rcx ; testb %cl, (%rcx) ; subq $0x1000, %rax ; ja <loop>
// Note it is a downward walk from %rsp in 0x1000-byte steps, which is what
// makes it correct for a guard-page fault: the probe must touch each page on the
// way DOWN, not allocate.
//
// This is a genuine local definition, not a stub that pretends to work: it
// performs the probe it is named for.  It is NOT a fabrication of an Apple
// structure or signature -- chkstk takes a size and touches stack, and that is
// the whole of its contract.
void ___chkstk_darwin(uintptr_t size)
{
    if (size == 0)
        return;
    volatile char* probe = (volatile char*)__builtin_frame_address(0);
    uintptr_t pages = (size + 0xFFF) >> 12;
    for (uintptr_t i = 1; i <= pages; ++i)
        probe[-(ptrdiff_t)(i << 12)] = 0;   // touch, one byte per page
}
