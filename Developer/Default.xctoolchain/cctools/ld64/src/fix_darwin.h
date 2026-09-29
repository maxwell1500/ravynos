#pragma once
#include <stdint.h>
#include <sys/types.h>
#ifndef CPU_SUBTYPE_X86_ALL
#define CPU_SUBTYPE_X86_ALL ((cpu_subtype_t)3)
#endif
#ifndef CPU_SUBTYPE_X86_64_H
#define CPU_SUBTYPE_X86_64_H ((cpu_subtype_t)8)
#endif
#ifndef CPU_SUBTYPE_X86_64_ALL
#define CPU_SUBTYPE_X86_64_ALL CPU_SUBTYPE_X86_ALL
#endif
#ifndef CTL_KERN
#define CTL_KERN 1
#endif
#ifndef KERN_OSRELEASE
#define KERN_OSRELEASE 2
#endif
#ifndef MAXPATHLEN
#define MAXPATHLEN 1024
#endif
#ifndef reallocf
#define reallocf realloc
#endif
#ifndef PLATFORM_UNKNOWN
#define PLATFORM_UNKNOWN 0
#endif
#ifndef PLATFORM_MACOS
#define PLATFORM_MACOS 1
#endif
#ifndef PLATFORM_IOS
#define PLATFORM_IOS 2
#endif
#ifndef _NSGetExecutablePath
extern "C" int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
#endif
extern "C" int sysctl(int *, unsigned int, void *, size_t *, void *, size_t);
