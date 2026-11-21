/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#ifdef PLATFORM_IS_POSIX
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSThread-Private.h>
#import <Foundation/NSRaiseException.h>
#import <Foundation/NSPlatform_posix.h>

#import "NSFileManager_posix.h"
#import "../NSString/NSString_cString.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/time.h>
#include <unistd.h>
#include <fcntl.h>
#include <pwd.h>
#include <grp.h>
#include <time.h>
#include <dirent.h>
#include <errno.h>
#include <string.h>

static void _NSFileManagerSetPOSIXError(NSError **error,NSString *path);

@implementation NSFileManager(posix)

/* This category exists ONLY to swap the concrete implementation class, and
 * the original ignored its receiver entirely -- so `[AnySubclass alloc]`
 * also produced an NSFileManager_posix.  That was latent until
 * bbd85b31cd changed +[NSObject alloc] to route through +allocWithZone:,
 * which made [X alloc] reach this method for the first time.  Restore the
 * invariant that a +allocWithZone: returns an instance of its receiver:
 * redirect only when the receiver really is NSFileManager, and otherwise
 * fall through to NSObject's implementation so subclasses get themselves.
 */
+allocWithZone:(NSZone *)zone {
   if (self == [NSFileManager class])
      return NSAllocateObject([NSFileManager_posix class],0,zone);

   return NSAllocateObject(self,0,zone);
}

@end

@implementation NSFileManager_posix

-(BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data
             attributes:(NSDictionary *)attributes {
    return [[NSPlatform currentPlatform] writeContentsOfFile:path bytes:[data bytes] length:[data length] options:NSAtomicWrite error:NULL];
}

-(NSArray *)directoryContentsAtPath:(NSString *)path {
    return [self contentsOfDirectoryAtPath:path error:NULL];
}

-(NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error
{
//TODO fill error
    NSMutableArray *result=nil;
    DIR *dirp = NULL;
    struct dirent *dire;

    if(path == nil) {
        return nil;
    }

    dirp = opendir([path fileSystemRepresentation]);
    
    if (dirp == NULL)
        return nil;

    result=[NSMutableArray array];

    while ((dire = readdir(dirp))){
	 if(strcmp(".",dire->d_name)==0)
	  continue;
	 if(strcmp("..",dire->d_name)==0)
	  continue;
     [result addObject:[NSString stringWithCString:dire->d_name]];
    }

    closedir(dirp);
    
    return result;
}


-(BOOL)createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes {
    // you can set all these, but we don't respect 'em all yet
    //NSDate *date = [attributes objectForKey:NSFileModificationDate];
    //NSString *owner = [attributes objectForKey:NSFileOwnerAccountName];
    //NSString *group = [attributes objectForKey:NSFileGroupOwnerAccountName];
    int mode = [[attributes objectForKey:NSFilePosixPermissions] intValue];

    if (mode == 0)
        mode = FOUNDATION_DIR_MODE;

    return (mkdir([path fileSystemRepresentation], mode) == 0);
}

-(BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    struct stat buf;

    if(stat([path fileSystemRepresentation],&buf)<0)
        return NO;

    if(isDirectory!=NULL)
     *isDirectory=S_ISDIR(buf.st_mode);

    return YES;
}

// we dont want to use fileExists... because it chases links
-(BOOL)_isDirectory:(NSString *)path {
    struct stat buf;

    if(lstat([path fileSystemRepresentation],&buf)<0)
        return NO;

    if (buf.st_mode & S_IFDIR && !(buf.st_mode & S_IFLNK))
        return YES;

    return NO;
}

-(BOOL)_errorHandler:handler src:(NSString *)src dest:(NSString *)dest operation:(NSString *)op {
    if ([handler respondsToSelector:@selector(fileManager:shouldProceedAfterError:)]) {
        NSDictionary *errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
            src, @"Path",
            [NSString stringWithFormat:@"%@: %s", op, strerror(errno)], @"Error",
            dest, @"ToPath",
            nil];

        if ([handler fileManager:self shouldProceedAfterError:errorInfo])
            return YES;
    }

    return NO;
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    if([path isEqualToString:@"."] || [path isEqualToString:@".."])
        NSRaiseException(NSInvalidArgumentException, self, _cmd, @"%@: invalid path", path);

    if(![self _isDirectory:path]){
        if(remove([path fileSystemRepresentation]) == -1) {
            if(error!=NULL)
				*error=nil; //TODO set error
            return NO;
        }
    }
    else{
        NSArray *contents=[self directoryContentsAtPath:path];
        NSInteger i,count=[contents count];
        
        for(i=0;i<count;i++){
            NSString *name = [contents objectAtIndex:i];
            NSString *fullPath;
            
            if([name isEqualToString:@"."] || [name isEqualToString:@".."])
                continue;
            
            fullPath=[path stringByAppendingPathComponent:name];
            if(![self removeItemAtPath:fullPath error:error]) {
                if(error!=NULL)
                    *error=nil; //TODO set error
                return NO;
            }
        }
        
        if(rmdir([path fileSystemRepresentation]) == -1) {
            if(error!=NULL)
				*error=nil; //TODO set error
            return NO;
        }
    }
    return YES;
}

-(BOOL)removeFileAtPath:(NSString *)path handler:handler {
    NSError *error = nil;
    
    if ([handler respondsToSelector:@selector(fileManager:willProcessPath:)])
        [handler fileManager:self willProcessPath:path];

    if ([self removeItemAtPath:path error:&error] == NO && handler != nil) {
        [self _errorHandler:handler src:path dest:@"" operation:[error description]];
        return NO;
    }
    
    return YES;
}


-(BOOL)movePath:(NSString *)src toPath:(NSString *)dest handler:handler {
    NSError *error = nil;
    
    if ([handler respondsToSelector:@selector(fileManager:willProcessPath:)])
        [handler fileManager:self willProcessPath:src];

    if ([self moveItemAtPath:src toPath:dest error:&error] == NO && handler != nil) {
        [self _errorHandler:handler src:src dest:dest operation:[error description]];
        return NO;
    }
    
    return YES;
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error
{
    
    /*
     It's not this easy...
     return rename([src fileSystemRepresentation],[dest fileSystemRepresentation])?NO:YES;
     */

    BOOL isDirectory;

    if ([self fileExistsAtPath:srcPath isDirectory:&isDirectory] == NO) {
        _NSFileManagerSetPOSIXError(error, srcPath);
        return NO;
    }
    if ([self fileExistsAtPath:dstPath isDirectory:&isDirectory] == YES) {
        errno = EEXIST;
        _NSFileManagerSetPOSIXError(error, dstPath);
        return NO;
    }

    /* rename(2) is atomic and preserves everything; copy/remove is only the
     * cross-device fallback. */
    if (rename([srcPath fileSystemRepresentation],
               [dstPath fileSystemRepresentation]) == 0)
        return YES;
    if (errno != EXDEV) {
        _NSFileManagerSetPOSIXError(error, srcPath);
        return NO;
    }

    if ([self copyItemAtPath:srcPath toPath:dstPath error:error] == NO) {
        [self removeItemAtPath:dstPath error:NULL];
        return NO;
    }
    if ([self removeItemAtPath:srcPath error:error] == NO) {
        [self removeItemAtPath:dstPath error:NULL];
        return NO;
    }
    return YES;
}

-(BOOL)copyPath:(NSString *)src toPath:(NSString *)dest handler:handler {
    NSError *error = nil;
    if ([self copyItemAtPath:src toPath:dest error:&error] == NO && handler != nil) {
        [self _errorHandler:handler src:src dest:dest operation:[error description]];
        return NO;
    }
    
    return YES;
}

-(BOOL)copyItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error
{
    struct stat st;
    const char *src = [fromPath fileSystemRepresentation];
    const char *dst = [toPath fileSystemRepresentation];

    if (lstat(src, &st) != 0) {
        _NSFileManagerSetPOSIXError(error, fromPath);
        return NO;
    }

    if (S_ISLNK(st.st_mode)) {
        char target[MAXPATHLEN + 1];
        ssize_t len = readlink(src, target, MAXPATHLEN);

        if (len < 0 || len >= MAXPATHLEN) {
            _NSFileManagerSetPOSIXError(error, fromPath);
            return NO;
        }
        target[len] = '\0';
        if (symlink(target, dst) != 0) {
            _NSFileManagerSetPOSIXError(error, toPath);
            return NO;
        }
        return YES;
    }

    if (S_ISDIR(st.st_mode)) {
        DIR *dir;
        struct dirent *ent;

        if (mkdir(dst, st.st_mode & 07777) != 0 && errno != EEXIST) {
            _NSFileManagerSetPOSIXError(error, toPath);
            return NO;
        }
        if ((dir = opendir(src)) == NULL) {
            _NSFileManagerSetPOSIXError(error, fromPath);
            return NO;
        }
        while ((ent = readdir(dir)) != NULL) {
            NSString *name, *subsrc, *subdst;

            if (strcmp(ent->d_name, ".") == 0 ||
                strcmp(ent->d_name, "..") == 0)
                continue;
            name = [NSString stringWithCString:ent->d_name
                                      encoding:NSUTF8StringEncoding];
            subsrc = [fromPath stringByAppendingPathComponent:name];
            subdst = [toPath stringByAppendingPathComponent:name];
            if (![self copyItemAtPath:subsrc toPath:subdst error:error]) {
                closedir(dir);
                return NO;
            }
        }
        closedir(dir);
        return YES;
    }

    if (S_ISREG(st.st_mode)) {
        int in, out;
        char buf[65536];
        ssize_t n;

        if ((in = open(src, O_RDONLY)) == -1) {
            _NSFileManagerSetPOSIXError(error, fromPath);
            return NO;
        }
        if ((out = open(dst, O_WRONLY | O_CREAT | O_TRUNC,
                        st.st_mode & 07777)) == -1) {
            _NSFileManagerSetPOSIXError(error, toPath);
            close(in);
            return NO;
        }
        while ((n = read(in, buf, sizeof(buf))) > 0) {
            ssize_t off = 0;

            while (off < n) {
                ssize_t w = write(out, buf + off, (size_t)(n - off));

                if (w <= 0) {
                    _NSFileManagerSetPOSIXError(error, toPath);
                    close(in);
                    close(out);
                    return NO;
                }
                off += w;
            }
        }
        if (n < 0) {
            _NSFileManagerSetPOSIXError(error, fromPath);
            close(in);
            close(out);
            return NO;
        }
        fchmod(out, st.st_mode & 07777);
        close(in);
        close(out);
        return YES;
    }

    /* Device nodes and sockets are recreated by their owning subsystem, not
     * copied; report the failure instead of silently succeeding. */
    errno = ENOTSUP;
    _NSFileManagerSetPOSIXError(error, fromPath);
    return NO;
}

-(NSString *)currentDirectoryPath {
    char  path[MAXPATHLEN+1];

    if (getcwd(path, sizeof(path)) != NULL)
        return [NSString stringWithCString:path];

    return nil;
}

-(NSString *)pathContentOfSymbolicLinkAtPath:(NSString *)path {
    char linkbuf[MAXPATHLEN+1];
    size_t length;

    length = readlink([path fileSystemRepresentation], linkbuf, MAXPATHLEN);
    if (length ==-1)
        return nil;

    linkbuf[length] = 0;
    return [NSString stringWithCString:linkbuf];
}


-(NSDictionary *)fileAttributesAtPath:(NSString *)path traverseLink:(BOOL)traverse {
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    struct stat statBuf;
    struct passwd *pwd;
    struct group *grp;

    if (lstat([path fileSystemRepresentation], &statBuf) != 0)
        return nil;

    // (Not in POSIX.1-1996.)
    if (S_ISLNK(statBuf.st_mode) && traverse) {
        NSString *linkContents = [self pathContentOfSymbolicLinkAtPath:path];
        return [self fileAttributesAtPath:linkContents traverseLink:traverse];
    }

    [result setObject:[NSNumber numberWithUnsignedLong:statBuf.st_size]
               forKey:NSFileSize];
    [result setObject:[NSDate dateWithTimeIntervalSince1970:statBuf.st_mtime]
               forKey:NSFileModificationDate];
    [result setObject:[NSDate dateWithTimeIntervalSince1970:statBuf.st_birthtimespec.tv_sec]
               forKey:NSFileCreationDate];

    // User/group names don't always exist for the IDs in the filesystem.
    // If we don't check for NULLs, we'll segfault.
    pwd = getpwuid(statBuf.st_uid);
    if (pwd != NULL)
        [result setObject:[NSString stringWithCString:pwd->pw_name]
                   forKey:NSFileOwnerAccountName];

    grp = getgrgid(statBuf.st_gid);
    if (grp != NULL)
        [result setObject:[NSString stringWithCString:grp->gr_name]
                   forKey:NSFileGroupOwnerAccountName];

    [result setObject:[NSNumber numberWithUnsignedLong:statBuf.st_nlink]
               forKey:NSFileReferenceCount];
    [result setObject:[NSNumber numberWithUnsignedLong:statBuf.st_ino]
               forKey:NSFileIdentifier];
    [result setObject:[NSNumber numberWithUnsignedLong:statBuf.st_dev]
               forKey:NSFileDeviceIdentifier];
    [result setObject:[NSNumber numberWithUnsignedLong:statBuf.st_mode]
               forKey:NSFilePosixPermissions];

    // ugh.. skip this if we can
    if (!S_ISREG(statBuf.st_mode)) {
        if (S_ISDIR(statBuf.st_mode))
            [result setObject:NSFileTypeDirectory forKey:NSFileType];
        else if (S_ISCHR(statBuf.st_mode))
            [result setObject:NSFileTypeCharacterSpecial forKey:NSFileType];
        else if (S_ISBLK(statBuf.st_mode))
            [result setObject:NSFileTypeBlockSpecial forKey:NSFileType];
        else if (S_ISFIFO(statBuf.st_mode))
            [result setObject:NSFileTypeFIFO forKey:NSFileType];
        else if (S_ISLNK(statBuf.st_mode))
            [result setObject:NSFileTypeSymbolicLink forKey:NSFileType];
        else if (S_ISSOCK(statBuf.st_mode))
            [result setObject:NSFileTypeSocket forKey:NSFileType];
    }
    else
        [result setObject:NSFileTypeRegular forKey:NSFileType];

    return result;
}

-(BOOL)isReadableFileAtPath:(NSString *)path {
    return access([path fileSystemRepresentation], R_OK) ? NO : YES;
}

-(BOOL)isWritableFileAtPath:(NSString *)path {
    return access([path fileSystemRepresentation], W_OK) ? NO : YES;
}

-(BOOL)isExecutableFileAtPath:(NSString *)path {
    return access([path fileSystemRepresentation], X_OK) ? NO : YES;
}

-(BOOL)createSymbolicLinkAtPath:(NSString *)path pathContent:(NSString *)otherPath {
    return (symlink([otherPath fileSystemRepresentation], [path fileSystemRepresentation]) == 0);
}


-(const char *)fileSystemRepresentationWithPath:(NSString *)path {
    return [path cStringUsingEncoding:NSUTF8StringEncoding];
}

-(NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error {
   char destination[MAXPATHLEN+1];
   ssize_t bytes;

   bytes = readlink([path fileSystemRepresentation], destination, MAXPATHLEN);

   if (bytes == -1) {
        //TODO fill error
        return nil;
   }

   destination[bytes] = 0;

   return [NSString stringWithCString:destination encoding:NSUTF8StringEncoding];
}

/* --- Cocoa-modern API ---
 * The base class returns nil/NO for all of these, which made every
 * -attributesOfItemAtPath: / -linkItemAtPath: / -changeCurrentDirectoryPath:
 * caller silently fail. */

static void _NSFileManagerSetPOSIXError(NSError **error,NSString *path) {
    if (error == NULL)
        return;

    int err = errno;
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSString stringWithUTF8String:strerror(err)], NSLocalizedDescriptionKey,
        path, NSFilePathErrorKey,
        nil];

    *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:userInfo];
}

-(NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    NSDictionary *result = [self fileAttributesAtPath:path traverseLink:NO];

    if (result == nil)
        _NSFileManagerSetPOSIXError(error,path);

    return result;
}

-(NSDictionary *)attributesOfFileSystemForPath:(NSString *)path error:(NSError **)error {
    struct statfs fs;
    struct stat st;

    if (statfs([path fileSystemRepresentation], &fs) != 0) {
        _NSFileManagerSetPOSIXError(error,path);
        return nil;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    [result setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)fs.f_blocks * fs.f_bsize]
               forKey:NSFileSystemSize];
    [result setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)fs.f_bfree * fs.f_bsize]
               forKey:NSFileSystemFreeSize];

    if (stat([path fileSystemRepresentation], &st) == 0)
        [result setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_dev]
                   forKey:NSFileSystemNumber];

    return result;
}

-(BOOL)changeCurrentDirectoryPath:(NSString *)path {
    if (chdir([path fileSystemRepresentation]) != 0) {
        return NO;
    }
    return YES;
}

-(BOOL)contentsEqualAtPath:(NSString *)path1 andPath:(NSString *)path2 {
    BOOL isDirectory1 = NO, isDirectory2 = NO;

    if (![self fileExistsAtPath:path1 isDirectory:&isDirectory1] ||
        ![self fileExistsAtPath:path2 isDirectory:&isDirectory2])
        return NO;

    if (isDirectory1 != isDirectory2)
        return NO;

    if (!isDirectory1) {
        NSData *a = [NSData dataWithContentsOfFile:path1];
        NSData *b = [NSData dataWithContentsOfFile:path2];

        if (a == nil || b == nil)
            return NO;

        return [a isEqualToData:b];
    }

    NSArray *subpaths1 = [self subpathsAtPath:path1];
    NSArray *subpaths2 = [self subpathsAtPath:path2];

    if (![subpaths1 isEqualToArray:subpaths2])
        return NO;

    NSInteger i, count = [subpaths1 count];

    for (i = 0; i < count; i++) {
        NSString *sub = [subpaths1 objectAtIndex:i];
        NSString *sub1 = [path1 stringByAppendingPathComponent:sub];
        NSString *sub2 = [path2 stringByAppendingPathComponent:sub];

        if (![self contentsEqualAtPath:sub1 andPath:sub2])
            return NO;
    }

    return YES;
}

-(BOOL)isDeletableFileAtPath:(NSString *)path {
    /* Deletion permission comes from the parent directory, not the item. */
    NSString *parent = [path stringByDeletingLastPathComponent];

    if ([parent length] == 0)
        parent = @".";

    return access([parent fileSystemRepresentation], W_OK|X_OK) == 0;
}

-(BOOL)linkItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error {
    if (link([fromPath fileSystemRepresentation], [toPath fileSystemRepresentation]) != 0) {
        _NSFileManagerSetPOSIXError(error,fromPath);
        return NO;
    }
    return YES;
}

-(BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)destPath error:(NSError **)error {
    if (symlink([destPath fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
        _NSFileManagerSetPOSIXError(error,path);
        return NO;
    }
    return YES;
}

-(NSArray *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    struct stat st;

    if (lstat([path fileSystemRepresentation], &st) != 0) {
        _NSFileManagerSetPOSIXError(error,path);
        return nil;
    }

    return [self subpathsAtPath:path];
}

-(NSString *)stringWithFileSystemRepresentation:(const char *)string length:(NSUInteger)length {
    return [[[NSString alloc] initWithBytes:string length:length encoding:NSUTF8StringEncoding] autorelease];
}

-(BOOL)setAttributes:(NSDictionary *)attributes ofItemAtPath:(NSString *)path error:(NSError **)error {
    NSString *modeString = [attributes objectForKey:NSFilePosixPermissions];
    NSString *owner = [attributes objectForKey:NSFileOwnerAccountName];
    NSString *group = [attributes objectForKey:NSFileGroupOwnerAccountName];
    NSDate *modificationDate = [attributes objectForKey:NSFileModificationDate];

    if (modeString != nil) {
        mode_t mode = (mode_t)[modeString unsignedLongValue];

        if (chmod([path fileSystemRepresentation], mode) != 0) {
            _NSFileManagerSetPOSIXError(error,path);
            return NO;
        }
    }

    if (owner != nil || group != nil) {
        uid_t uid = (uid_t)-1;
        gid_t gid = (gid_t)-1;

        if (owner != nil) {
            struct passwd *pwd = getpwnam([owner UTF8String]);

            if (pwd == NULL) {
                _NSFileManagerSetPOSIXError(error,path);
                return NO;
            }
            uid = pwd->pw_uid;
        }

        if (group != nil) {
            struct group *grp = getgrnam([group UTF8String]);

            if (grp == NULL) {
                _NSFileManagerSetPOSIXError(error,path);
                return NO;
            }
            gid = grp->gr_gid;
        }

        if (chown([path fileSystemRepresentation], uid, gid) != 0) {
            _NSFileManagerSetPOSIXError(error,path);
            return NO;
        }
    }

    if (modificationDate != nil) {
        struct timeval times[2];
        struct stat st;

        if (stat([path fileSystemRepresentation], &st) != 0) {
            _NSFileManagerSetPOSIXError(error,path);
            return NO;
        }

        times[0].tv_sec = st.st_atime;
        times[0].tv_usec = 0;
        times[1].tv_sec = (time_t)[modificationDate timeIntervalSince1970];
        times[1].tv_usec = 0;

        if (utimes([path fileSystemRepresentation], times) != 0) {
            _NSFileManagerSetPOSIXError(error,path);
            return NO;
        }
    }

    return YES;
}

@end
#endif
