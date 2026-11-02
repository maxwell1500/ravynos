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

/*
 * Volume information.  XUL binds _FSGetVolumeInfo lazily while reading
 * its profile directory and dyld aborts on the bind if CoreServices lacks
 * the symbol.  The layout below is CarbonCore's Files.h: 128 bytes with
 * UTCDateTime as a packed 2+4+2 triple and 32-bit allocation-block counts,
 * so the caller's struct is filled byte for byte.
 */
#include <sys/mount.h>

typedef unsigned short UInt16;
typedef unsigned short UniChar;
typedef unsigned short UniCharCount;
typedef unsigned long long UInt64;
/* FSIORefNum is a 16-bit field; the file's SInt16 typedef is int. */
typedef short FSIORefNum;

typedef struct {
	UInt16	highSeconds;
	UInt32	lowSeconds;
	SInt16	fraction;
} UTCDateTime;

typedef struct {
	UInt16		length;
	UniChar		unicode[255];
} HFSUniStr255;

typedef struct {
	UTCDateTime	createDate;
	UTCDateTime	modifyDate;
	UTCDateTime	backupDate;
	UTCDateTime	checkedDate;
	UInt32		fileCount;
	UInt32		folderCount;
	UInt64		totalBytes;
	UInt64		freeBytes;
	UInt32		blockSize;
	UInt32		totalBlocks;
	UInt32		freeBlocks;
	UInt32		nextAllocation;
	UInt32		rsrcClumpSize;
	UInt32		dataClumpSize;
	UInt32		nextCatalogID;
	UInt8		finderInfo[32];
	UInt16		flags;
	UInt16		filesystemID;
	UInt16		signature;
	UInt16		driveNumber;
	FSIORefNum	driverRefNum;
} FSVolumeInfo;

enum {
	kFSVolInfoCreateDate	= 0x0001,
	kFSVolInfoModDate	= 0x0002,
	kFSVolInfoBackupDate	= 0x0004,
	kFSVolInfoCheckedDate	= 0x0008,
	kFSVolInfoFileCount	= 0x0010,
	kFSVolInfoDirCount	= 0x0020,
	kFSVolInfoSizes		= 0x0040,
	kFSVolInfoBlocks	= 0x0080,
	kFSVolInfoNextAlloc	= 0x0100,
	kFSVolInfoRsrcClump	= 0x0200,
	kFSVolInfoDataClump	= 0x0400,
	kFSVolInfoNextID	= 0x0800,
	kFSVolInfoFinderInfo	= 0x1000,
	kFSVolInfoFlags		= 0x2000,
	kFSVolInfoFSInfo	= 0x4000,
	kFSVolInfoDriveInfo	= 0x8000
};

#define nsvErr		(-35)
#define kFSInvalidVolumeRefNum ((FSIORefNum)-1)

static int
volume_is_root(FSIORefNum volume, unsigned long volumeIndex)
{
	if (volumeIndex > 1)
		return (0);
	if (volumeIndex == 1)
		return (1);
	return (volume == kFSInvalidVolumeRefNum || volume == 0 || volume == 1);
}

static void
volume_name_for(const struct statfs *fs, HFSUniStr255 *name)
{
	const char *base;
	size_t i, len;

	memset(name, 0, sizeof(*name));
	base = fs->f_mntonname;
	len = strlen(base);
	i = len;
	while (i > 1 && base[i - 1] == '/')
		i--;
	while (i > 1 && base[i - 1] != '/')
		i--;
	if (i >= len) {
		name->length = 0;
		return;
	}
	base += i;
	len = strlen(base);
	if (len > 255)
		len = 255;
	for (i = 0; i < len; i++)
		name->unicode[i] = (unsigned char)base[i];
	name->length = (UniCharCount)len;
}

OSStatus
FSGetVolumeInfo(FSIORefNum volume, unsigned long volumeIndex,
    FSIORefNum *actualVolume, UInt32 whichInfo, FSVolumeInfo *info,
    HFSUniStr255 *volumeName, FSRef *rootDirectory)
{
	struct statfs fs;

	if (!volume_is_root(volume, volumeIndex))
		return (nsvErr);
	if (statfs("/", &fs) != 0)
		return (fnfErr);

	if (actualVolume != NULL)
		*actualVolume = 1;

	if (info != NULL) {
		memset(info, 0, sizeof(*info));
		if (whichInfo & kFSVolInfoSizes) {
			info->blockSize = (UInt32)fs.f_bsize;
			info->totalBytes = (UInt64)fs.f_blocks * (UInt64)fs.f_bsize;
			info->freeBytes = (UInt64)fs.f_bavail * (UInt64)fs.f_bsize;
		}
		if (whichInfo & kFSVolInfoBlocks) {
			info->blockSize = (UInt32)fs.f_bsize;
			info->totalBlocks = (UInt32)((UInt64)fs.f_blocks * (UInt64)fs.f_bsize / (UInt64)fs.f_bsize);
			info->freeBlocks = (UInt32)((UInt64)fs.f_bavail * (UInt64)fs.f_bsize / (UInt64)fs.f_bsize);
			info->nextAllocation = 0;
		}
		if (whichInfo & kFSVolInfoFSInfo) {
			info->filesystemID = 0;
			info->signature = 0;
		}
		if (whichInfo & kFSVolInfoDriveInfo) {
			info->driveNumber = 0;
			info->driverRefNum = 0;
		}
	}

	if (volumeName != NULL)
		volume_name_for(&fs, volumeName);

	if (rootDirectory != NULL)
		ref_set_path(rootDirectory, "/");

	return (noErr);
}

/*
 * Two references are the same object when their (device, inode) pair is the
 * same; comparing the stored paths alone would say a symlink and its target
 * differ.  errFSRefsDifferent is MacErrors.h's -1420.
 */
#define errFSRefsDifferent	(-1420)

OSStatus
FSCompareFSRefs(const FSRef *ref1, const FSRef *ref2)
{
	struct stat st1, st2;

	if (ref1 == NULL || ref2 == NULL)
		return (paramErr);
	if (ref1 == ref2 || strcmp(ref_path(ref1), ref_path(ref2)) == 0)
		return (noErr);
	if (stat(ref_path(ref1), &st1) != 0 || stat(ref_path(ref2), &st2) != 0)
		return (fnfErr);
	if (st1.st_dev == st2.st_dev && st1.st_ino == st2.st_ino)
		return (noErr);
	return (errFSRefsDifferent);
}

/*
 * FSResolveAlias on a plain file simply hands the reference back, which is
 * what the callers in XUL ask for (profile and cache paths).  Alias files
 * themselves are not decoded here; a file that does not exist is fnfErr.
 */
OSStatus
FSResolveAlias(const FSRef *fromFile, Boolean resolveAliasChains,
    FSRef *target, Boolean *wasAliased)
{
	struct stat st;

	(void)resolveAliasChains;
	if (fromFile == NULL || target == NULL)
		return (paramErr);
	if (stat(ref_path(fromFile), &st) != 0)
		return (fnfErr);
	*target = *fromFile;
	if (wasAliased != NULL)
		*wasAliased = 0;
	return (noErr);
}
