/*
 * Carbon File Manager, the part Firefox actually calls.
 *
 * XUL binds _FSFindFolder lazily during startup and aborts when CoreServices
 * does not export it:
 *
 *   dyld: lazy symbol binding failed: Symbol not found: _FSFindFolder
 *   Expected in: /System/Library/Frameworks/CoreServices.framework/...
 *
 * This file implements the FSRef round trip the Finder-era APIs are built
 * on: FSFindFolder returns a reference to a real directory, FSPathMakeRef
 * turns a path into one, and FSRefMakePath turns it back.  Apple's FSRef is
 * an 80-byte opaque value; this implementation stores the NUL-terminated
 * POSIX path inside it, so every FS* function here agrees on the encoding.
 * An FSRef produced by one macOS process is never reinterpreted by another.
 */
#include <sys/stat.h>
#include <sys/types.h>

#include <errno.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef unsigned char UInt8;
typedef unsigned int UInt32;
typedef int OSStatus;
typedef int SInt16;
typedef unsigned int OSType;
typedef unsigned char Boolean;
typedef unsigned int OptionBits;

typedef struct {
	UInt8 opaque[80];
} FSRef;

#define noErr		0
#define fnfErr		(-43)
#define paramErr	(-50)
#define bdNamErr	(-37)

/* Carbon domain constants (Files.h). */
enum {
	kOnSystemDisk		= -32768,
	kOnAppropriateDisk	= -32767,
	kSystemDomain		= -32766,
	kLocalDomain		= -32765,
	kNetworkDomain		= -32764,
	kUserDomain		= -32763,
	kClassicDomain		= -32762
};

/* Folder types (Files.h), spelled as FourCCs. */
#define FOURCC(a, b, c, d) \
	(((OSType)(a) << 24) | ((OSType)(b) << 16) | ((OSType)(c) << 8) | (OSType)(d))

#define kSystemFolderType		FOURCC('m','a','c','s')
#define kDesktopFolderType		FOURCC('d','e','s','k')
#define kTrashFolderType		FOURCC('t','r','s','h')
#define kFontsFolderType		FOURCC('f','o','n','t')
#define kPreferencesFolderType		FOURCC('p','r','e','f')
#define kTemporaryFolderType		FOURCC('t','e','m','p')
#define kCachesFolderType		FOURCC('c','a','c','h')
#define kApplicationSupportFolderType	FOURCC('a','s','u','p')
#define kDocumentsFolderType		FOURCC('d','o','c','u')
#define kDomainLibraryFolderType	FOURCC('d','l','i','b')
#define kLibraryFolderType		FOURCC('l','i','b','f')

static const char *
user_home(void)
{
	static char home[1024];
	const char *env = getenv("HOME");

	if (env != NULL && env[0] != '\0') {
		snprintf(home, sizeof(home), "%s", env);
		return (home);
	}

	struct passwd *pw = getpwuid(getuid());
	if (pw != NULL && pw->pw_dir != NULL && pw->pw_dir[0] != '\0') {
		snprintf(home, sizeof(home), "%s", pw->pw_dir);
		return (home);
	}
	return (NULL);
}

static const char *
domain_root(SInt16 vRefNum)
{
	switch (vRefNum) {
	case kUserDomain:
		return (user_home());
	case kLocalDomain:
		return ("/Library");
	case kSystemDomain:
	case kOnSystemDisk:
		return ("/System");
	case kNetworkDomain:
		return ("/Network");
	case kOnAppropriateDisk:
	case kClassicDomain:
	default:
		return ("/");
	}
}

static int
mkdir_p(const char *path)
{
	char buf[1024];
	size_t len;

	if (path == NULL)
		return (-1);
	len = strlen(path);
	if (len == 0 || len >= sizeof(buf))
		return (-1);
	memcpy(buf, path, len + 1);

	for (char *p = buf + 1; *p; p++) {
		if (*p != '/')
			continue;
		*p = '\0';
		if (mkdir(buf, 0755) != 0 && errno != EEXIST)
			return (-1);
		*p = '/';
	}
	if (mkdir(buf, 0755) != 0 && errno != EEXIST)
		return (-1);
	return (0);
}

/*
 * Unknown folder types still get a usable directory (the domain root) rather
 * than an error, but say so once per type: a caller that needed a specific
 * folder must not mistake the root for it silently.
 */
static void
note_unmapped(SInt16 domain, OSType type)
{
	static OSType seen[8];
	static int nseen;

	for (int i = 0; i < nseen; i++)
		if (seen[i] == type)
			return;
	if (nseen < 8)
		seen[nseen++] = type;
	fprintf(stderr, "[compat] CoreServices: FSFindFolder domain=%d type=0x%08x "
	    "is not mapped; using the domain root\n", domain, type);
}

static void
ref_set_path(FSRef *ref, const char *path)
{
	size_t n = strlen(path);

	memset(ref, 0, sizeof(*ref));
	if (n >= sizeof(ref->opaque))
		n = sizeof(ref->opaque) - 1;
	memcpy(ref->opaque, path, n);
	ref->opaque[n] = '\0';
}

static const char *
ref_path(const FSRef *ref)
{
	return ((const char *)ref->opaque);
}

OSStatus
FSPathMakeRef(const UInt8 *path, FSRef *ref, Boolean *isDirectory)
{
	struct stat st;

	if (path == NULL || ref == NULL)
		return (paramErr);
	if (path[0] == '\0' || strlen((const char *)path) >= sizeof(ref->opaque))
		return (bdNamErr);
	if (stat((const char *)path, &st) != 0)
		return (fnfErr);

	ref_set_path(ref, (const char *)path);
	if (isDirectory != NULL)
		*isDirectory = S_ISDIR(st.st_mode) ? 1 : 0;
	return (noErr);
}

OSStatus
FSPathMakeRefWithOptions(const UInt8 *path, OptionBits options, FSRef *ref,
    Boolean *isDirectory)
{
	(void)options;
	return (FSPathMakeRef(path, ref, isDirectory));
}

OSStatus
FSRefMakePath(const FSRef *ref, UInt8 *path, UInt32 maxPathSize)
{
	const char *stored;
	size_t len;

	if (ref == NULL || path == NULL || maxPathSize == 0)
		return (paramErr);
	stored = ref_path(ref);
	if (stored[0] == '\0')
		return (fnfErr);
	len = strlen(stored);
	if (len + 1 > maxPathSize)
		return (bdNamErr);

	memcpy(path, stored, len + 1);
	return (noErr);
}

OSStatus
FSFindFolder(SInt16 vRefNum, OSType folderType, Boolean createFolder,
    FSRef *foundRef)
{
	char path[1024];
	const char *root = domain_root(vRefNum);
	const char *home = user_home();
	int user;

	if (foundRef == NULL || root == NULL)
		return (paramErr);
	memset(foundRef, 0, sizeof(*foundRef));
	user = (vRefNum == kUserDomain);

	switch (folderType) {
	case kTemporaryFolderType:
		snprintf(path, sizeof(path), "/tmp");
		break;
	case kSystemFolderType:
		snprintf(path, sizeof(path), "/System");
		break;
	case kFontsFolderType:
		snprintf(path, sizeof(path), "/System/Library/Fonts");
		break;
	case kDesktopFolderType:
		if (home == NULL)
			return (fnfErr);
		snprintf(path, sizeof(path), "%s/Desktop", home);
		break;
	case kDocumentsFolderType:
		if (home == NULL)
			return (fnfErr);
		snprintf(path, sizeof(path), "%s/Documents", home);
		break;
	case kTrashFolderType:
		if (home == NULL)
			return (fnfErr);
		snprintf(path, sizeof(path), "%s/.Trash", home);
		break;
	case kCachesFolderType:
		if (user)
			snprintf(path, sizeof(path), "%s/Library/Caches", home);
		else
			snprintf(path, sizeof(path), "%s/Caches", root);
		break;
	case kPreferencesFolderType:
		if (user)
			snprintf(path, sizeof(path), "%s/Library/Preferences", home);
		else
			snprintf(path, sizeof(path), "%s/Preferences", root);
		break;
	case kApplicationSupportFolderType:
		if (user)
			snprintf(path, sizeof(path), "%s/Library/Application Support", home);
		else
			snprintf(path, sizeof(path), "%s/Application Support", root);
		break;
	case kDomainLibraryFolderType:
		if (user)
			snprintf(path, sizeof(path), "%s/Library", home);
		else
			snprintf(path, sizeof(path), "%s", root);
		break;
	case kLibraryFolderType:
		snprintf(path, sizeof(path), "%s/Library", root);
		break;
	default:
		note_unmapped(vRefNum, folderType);
		snprintf(path, sizeof(path), "%s", root);
		break;
	}

	if (createFolder && mkdir_p(path) != 0)
		return (fnfErr);

	return (FSPathMakeRef((const UInt8 *)path, foundRef, NULL));
}
