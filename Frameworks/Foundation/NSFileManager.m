/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/NSFileManager.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSError.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSData.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSConcreteDirectoryEnumerator.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSPathUtilities.h>
#include <dirent.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <pwd.h>
#include <grp.h>

static NSError *NSFileManagerError(NSString *path,int err) {
   NSDictionary *userInfo=nil;

   if(path!=nil)
    userInfo=[NSDictionary dictionaryWithObjectsAndKeys:
       path,NSFilePathErrorKey,
       [NSString stringWithCString:strerror(err) encoding:NSUTF8StringEncoding],NSLocalizedDescriptionKey,
       nil];

   return [NSError errorWithDomain:@"NSPOSIXErrorDomain" code:err userInfo:userInfo];
}

static NSString *NSFileManagerTypeString(mode_t mode) {
   if(S_ISREG(mode)) return NSFileTypeRegular;
   if(S_ISDIR(mode)) return NSFileTypeDirectory;
   if(S_ISLNK(mode)) return NSFileTypeSymbolicLink;
   if(S_ISCHR(mode)) return NSFileTypeCharacterSpecial;
   if(S_ISBLK(mode)) return NSFileTypeBlockSpecial;
   if(S_ISFIFO(mode)) return NSFileTypeFIFO;
   if(S_ISSOCK(mode)) return NSFileTypeSocket;
   return @"NSFileTypeUnknown";
}

NSString * const NSFileType = @"NSFileType";
NSString * const NSFileTypeRegular = @"NSFileTypeRegular";
NSString * const NSFileTypeDirectory = @"NSFileTypeDirectory";
NSString * const NSFileTypeSymbolicLink = @"NSFileTypeSymbolicLink";
NSString * const NSFileTypeCharacterSpecial = @"NSFileTypeCharacterSpecial";
NSString * const NSFileTypeBlockSpecial = @"NSFileTypeBlockSpecial";
NSString * const NSFileTypeFIFO = @"NSFileTypeFIFO";
NSString * const NSFileTypeSocket = @"NSFileTypeSocket";
NSString * const NSFileTypeUnknown = @"NSFileTypeUnknown";

NSString * const NSFileSize = @"NSFileSize";
NSString * const NSFileCreationDate = @"NSFileCreationDate";
NSString * const NSFileModificationDate = @"NSFileModificationDate";
NSString * const NSFileOwnerAccountName = @"NSFileOwnerAccountName";
NSString * const NSFileGroupOwnerAccountName = @"NSFileGroupOwnerAccountName";

NSString * const NSFileReferenceCount = @"NSFileReferenceCount";
NSString * const NSFileIdentifier = @"NSFileIdentifier";
NSString * const NSFileDeviceIdentifier = @"NSFileDeviceIdentifier";
NSString * const NSFilePosixPermissions = @"NSFilePosixPermissions";
NSString * const NSFileHFSCreatorCode = @"NSFileHFSCreatorCode";
NSString * const NSFileHFSTypeCode = @"NSFileHFSTypeCode";

NSString * const NSFileSystemNumber=@"NSFileSystemNumber";
NSString * const NSFileSystemSize=@"NSFileSystemSize";
NSString * const NSFileSystemFreeSize=@"NSFileSystemFreeSize";

@implementation NSFileManager

+(NSFileManager *)defaultManager {
   return NSThreadSharedInstance(@"NSFileManager");
}

-delegate {
   //NSUnimplementedMethod();
   return 0;
}
-(void)setDelegate:delegate {
   //NSUnimplementedMethod();
}

-(NSDictionary *)attributesOfFileSystemForPath:(NSString *)path error:(NSError **)errorp {
   struct statfs st;

   if(statfs([path fileSystemRepresentation],&st)!=0){
    if(errorp!=NULL) *errorp=NSFileManagerError(path,errno);
    return nil;
   }

   return [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithUnsignedLongLong:(unsigned long long)st.f_bsize*st.f_blocks],NSFileSystemSize,
      [NSNumber numberWithUnsignedLongLong:(unsigned long long)st.f_bsize*st.f_bfree],NSFileSystemFreeSize,
      [NSNumber numberWithUnsignedLong:(unsigned long)st.f_fsid.val[0]],NSFileSystemNumber,
      nil];
}
-(NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
   struct stat st;
   NSMutableDictionary *result;

   if(lstat([path fileSystemRepresentation],&st)!=0){
    if(error!=NULL)
     *error=NSFileManagerError(path,errno);
    return nil;
   }

   result=[NSMutableDictionary dictionary];
   [result setObject:NSFileManagerTypeString(st.st_mode) forKey:NSFileType];
   [result setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_size] forKey:NSFileSize];
   [result setObject:[NSNumber numberWithUnsignedLong:(unsigned long)st.st_mode] forKey:NSFilePosixPermissions];
   [result setObject:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)st.st_mtime] forKey:NSFileModificationDate];
   [result setObject:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)st.st_birthtime] forKey:NSFileCreationDate];
   [result setObject:[NSNumber numberWithUnsignedLong:(unsigned long)st.st_nlink] forKey:NSFileReferenceCount];

   {
    struct passwd *pw=getpwuid(st.st_uid);
    struct group *gr=getgrgid(st.st_gid);

    if(pw!=NULL)
     [result setObject:[NSString stringWithCString:pw->pw_name encoding:NSUTF8StringEncoding] forKey:NSFileOwnerAccountName];
    if(gr!=NULL)
     [result setObject:[NSString stringWithCString:gr->gr_name encoding:NSUTF8StringEncoding] forKey:NSFileGroupOwnerAccountName];
   }

   return result;
}
-(BOOL)changeCurrentDirectoryPath:(NSString *)path {
   return chdir([path fileSystemRepresentation])==0;
}
-(NSArray *)componentsToDisplayForPath:(NSString *)path {
   //NSUnimplementedMethod();
   return 0;
}
-(BOOL)contentsEqualAtPath:(NSString *)path1 andPath:(NSString *)path2 {
   NSData *a=[NSData dataWithContentsOfFile:path1];
   NSData *b=[NSData dataWithContentsOfFile:path2];

   if(a==nil || b==nil)
    return NO;
   return [a isEqualToData:b];
}
-(NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
   //NSUnimplementedMethod();
   return 0;
}
-(BOOL)copyItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error {
   struct stat st;

   if(lstat([fromPath fileSystemRepresentation],&st)!=0){
    if(error!=NULL) *error=NSFileManagerError(fromPath,errno);
    return NO;
   }

   if(S_ISLNK(st.st_mode)){
    char target[PATH_MAX];
    ssize_t length=readlink([fromPath fileSystemRepresentation],target,sizeof(target)-1);

    if(length<0){
     if(error!=NULL) *error=NSFileManagerError(fromPath,errno);
     return NO;
    }
    target[length]=0;

    if(symlink(target,[toPath fileSystemRepresentation])!=0){
     if(error!=NULL) *error=NSFileManagerError(toPath,errno);
     return NO;
    }
    return YES;
   }

   if(S_ISDIR(st.st_mode)){
    NSArray *contents=[self directoryContentsAtPath:fromPath];

    if(mkdir([toPath fileSystemRepresentation],st.st_mode&07777)!=0 && errno!=EEXIST){
     if(error!=NULL) *error=NSFileManagerError(toPath,errno);
     return NO;
    }

    for(NSString *name in contents){
     NSString *from=[fromPath stringByAppendingPathComponent:name];
     NSString *to=[toPath stringByAppendingPathComponent:name];

     if(![self copyItemAtPath:from toPath:to error:error])
      return NO;
    }
    return YES;
   }

   {
    int in=open([fromPath fileSystemRepresentation],O_RDONLY);
    int out;
    char buffer[65536];
    ssize_t got;

    if(in<0){
     if(error!=NULL) *error=NSFileManagerError(fromPath,errno);
     return NO;
    }

    out=open([toPath fileSystemRepresentation],O_WRONLY|O_CREAT|O_TRUNC,st.st_mode&07777);
    if(out<0){
     if(error!=NULL) *error=NSFileManagerError(toPath,errno);
     close(in);
     return NO;
    }

    while((got=read(in,buffer,sizeof(buffer)))>0){
     ssize_t put=0;

     while(put<got){
      ssize_t wrote=write(out,buffer+put,(size_t)(got-put));

      if(wrote<0){
       if(error!=NULL) *error=NSFileManagerError(toPath,errno);
       close(in); close(out);
       return NO;
      }
      put+=wrote;
     }
    }

    close(in);
    close(out);

    if(got<0){
     if(error!=NULL) *error=NSFileManagerError(fromPath,errno);
     return NO;
    }
   }

   return YES;
}
-(NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error {
   //NSInvalidAbstractInvocation();
   return 0;
}

-(NSString *)displayNameAtPath:(NSString *)path {
   NSBundle *bundle=[NSBundle bundleWithPath:path];
   NSString *name=nil;
   if(bundle) {
    NSDictionary *localizedInfo=[bundle localizedInfoDictionary];
    name=[localizedInfo objectForKey:@"CFBundleDisplayName"];
    if(!name)
     name=[localizedInfo objectForKey:@"CFBundleName"];
   }
   if(!name)
    name=[path lastPathComponent];
   return name;
}

-(NSDictionary *)fileSystemAttributesAtPath:(NSString *)path
{
	return [self attributesOfFileSystemForPath: path error: NULL];
}

-(BOOL)isDeletableFileAtPath:(NSString *)path {
   return access([path fileSystemRepresentation],W_OK)==0;
}

-(BOOL)linkItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error {
   if(link([fromPath fileSystemRepresentation],[toPath fileSystemRepresentation])!=0){
    if(error!=NULL) *error=NSFileManagerError(toPath,errno);
    return NO;
   }
   return YES;
}
-(BOOL)linkPath:(NSString *)source toPath:(NSString *)destination handler:handler {
   //NSUnimplementedMethod();
   return 0;
}
-(BOOL)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error {
   if(rename([fromPath fileSystemRepresentation],[toPath fileSystemRepresentation])==0)
    return YES;

   if(errno==EXDEV){
    if(![self copyItemAtPath:fromPath toPath:toPath error:error])
     return NO;
    return [self removeItemAtPath:fromPath error:error];
   }

   if(error!=NULL) *error=NSFileManagerError(fromPath,errno);
   return NO;
}
-(BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
   struct stat st;

   if(lstat([path fileSystemRepresentation],&st)!=0){
    if(error!=NULL) *error=NSFileManagerError(path,errno);
    return NO;
   }

   if(S_ISDIR(st.st_mode)){
    NSArray *contents=[self directoryContentsAtPath:path];

    for(NSString *name in contents){
     if(![self removeItemAtPath:[path stringByAppendingPathComponent:name] error:error])
      return NO;
    }

    if(rmdir([path fileSystemRepresentation])!=0){
     if(error!=NULL) *error=NSFileManagerError(path,errno);
     return NO;
    }
    return YES;
   }

   if(unlink([path fileSystemRepresentation])!=0){
    if(error!=NULL) *error=NSFileManagerError(path,errno);
    return NO;
   }
   return YES;
}

-(BOOL)removeItemAtURL:(NSURL *)url error:(NSError **)error {
    // Default to the AtPath implementation
    return [self removeItemAtPath:[url path] error:error];
}

-(BOOL)moveItemAtURL:(NSURL *)url toURL:(NSURL *)dstURL error:(NSError **)error {
    // Default to the AtPath implementation
    return [self moveItemAtPath:[url path] toPath:[dstURL path] error:error];
}

-(BOOL)linkItemAtURL:(NSURL *)url toURL:(NSURL *)dstURL error:(NSError **)error {
    // Default to the AtPath implementation
    return [self linkItemAtPath:[url path] toPath:[dstURL path] error:error];
}

-(BOOL)copyItemAtURL:(NSURL *)url toURL:(NSURL *)dstURL error:(NSError **)error {
    // Default to the AtPath implementation
    return [self copyItemAtPath:[url path] toPath:[dstURL path] error:error];
}

-(BOOL)setAttributes:(NSDictionary *)attributes ofItemAtPath:(NSString *)path error:(NSError **)error {
   //NSUnimplementedMethod();
   return 0;
}

-(NSString *)stringWithFileSystemRepresentation:(const char *)string length:(NSUInteger)length {
   //NSUnimplementedMethod();
   return 0;
}

-(void)_subpathsAtPath:(NSString *)path basePath:(NSString*)basePath
paths:(NSMutableArray*)paths
{
	NSArray* files = [self directoryContentsAtPath:path];

	int x; for (x = 0; x < [files count]; x++)
	{
		[paths addObject:[basePath stringByAppendingPathComponent:[files objectAtIndex:x]]];
	}

	for (x = 0; x < [files count]; x++)
	{
		BOOL isDir = NO;
		NSString* newPath = [path stringByAppendingPathComponent:[files objectAtIndex:x]];
		[self fileExistsAtPath:newPath isDirectory:&isDir];
		if (isDir)
			[self _subpathsAtPath:newPath basePath:[basePath
stringByAppendingPathComponent:[files objectAtIndex:x]] paths:paths];
	}
}

-(NSArray *)subpathsAtPath:(NSString *)path {
	NSMutableArray *result=[NSMutableArray array];

	[self _subpathsAtPath:path basePath:@"" paths:result];
	return result;
}

-(NSArray *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
   NSMutableArray *result=[NSMutableArray array];

   [self _subpathsAtPath:path basePath:@"" paths:result];
   return result;
}

-(NSData *)contentsAtPath:(NSString *)path {
   return [NSData dataWithContentsOfFile:path];
}

-(BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data
             attributes:(NSDictionary *)attributes {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(NSArray *)directoryContentsAtPath:(NSString *)path {
   DIR *dirp = opendir([path fileSystemRepresentation]);
   if (dirp == NULL)
      return nil;
   NSMutableArray *result=[NSMutableArray array];
   struct dirent *dire;
   while ((dire = readdir(dirp))) {
      if (strcmp(dire->d_name, ".") == 0) continue;
      if (strcmp(dire->d_name, "..") == 0) continue;
      [result addObject:[NSString stringWithCString:dire->d_name encoding:NSUTF8StringEncoding]];
   }
   closedir(dirp);
   return result;
}

-(NSDirectoryEnumerator *)enumeratorAtPath:(NSString *)path {
    return [[[NSConcreteDirectoryEnumerator alloc] initWithPath: path] autorelease];
}

-(BOOL)createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)intermediates attributes:(NSDictionary *)attributes error:(NSError **)error {
	BOOL result = YES;
	BOOL isDirectory = NO;
	if (intermediates) {
		NSArray *components = [path pathComponents];
		int i, count = [components count];
		for (i=1; i<=count && result; i++) {
			NSString *makePath = [NSString pathWithComponents:[components subarrayWithRange:NSMakeRange(0,i)]];
			if (![self fileExistsAtPath:makePath isDirectory:&isDirectory]) {
				result = [self createDirectoryAtPath:makePath attributes:attributes];
			}
		}
	}
	else {
		result = [self createDirectoryAtPath:path attributes:attributes];
	}
	// TODO: fill error
	return result;
}

-(BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)intermediates attributes:(NSDictionary *)attributes error:(NSError **)error
{
    return [self createDirectoryAtPath:[url path] withIntermediateDirectories:intermediates attributes:attributes error:error];
}

-(BOOL)createSymbolicLinkAtPath:(NSString *)path pathContent:(NSString *)destination {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)destPath error:(NSError **)error {
   if(symlink([destPath fileSystemRepresentation],[path fileSystemRepresentation])!=0){
    if(error!=NULL) *error=NSFileManagerError(path,errno);
    return NO;
   }
   return YES;
}

-(NSString *)pathContentOfSymbolicLinkAtPath:(NSString *)path {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)fileExistsAtPath:(NSString *)path {
   BOOL foo;
   return [self fileExistsAtPath:path isDirectory:&foo];
}

-(BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
   struct stat buf;
   if (stat([path fileSystemRepresentation], &buf) < 0)
      return NO;
   if (isDirectory != NULL)
      *isDirectory = S_ISDIR(buf.st_mode);
   return YES;
}

-(BOOL)removeFileAtPath:(NSString *)path handler:handler {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)movePath:(NSString *)src toPath:(NSString *)dest handler:handler {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)copyPath:(NSString *)src toPath:(NSString *)dest handler:handler {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(NSString *)currentDirectoryPath {
   //NSInvalidAbstractInvocation();
   return nil;
}

-(NSDictionary *)fileAttributesAtPath:(NSString *)path traverseLink:(BOOL)traverse {
   //NSInvalidAbstractInvocation();
   return nil;
}

-(BOOL)isReadableFileAtPath:(NSString *)path {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)isWritableFileAtPath:(NSString *)path {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)isExecutableFileAtPath:(NSString *)path {
   //NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)changeFileAttributes:(NSDictionary *)attributes atPath:(NSString *)path {
    return [self setAttributes:(NSDictionary *)attributes ofItemAtPath:(NSString *)path error:NULL];
}

-(const char *)fileSystemRepresentationWithPath:(NSString *)path {
   return [path cString];
}

-(const uint16_t *)fileSystemRepresentationWithPathW:(NSString *)path {
   //NSInvalidAbstractInvocation();
   return NULL;
}


@end

@implementation NSDictionary(NSFileAttributes)

-(NSDate *)fileModificationDate {
   return [self objectForKey:NSFileModificationDate];
}

-(NSUInteger)filePosixPermissions {
   return [[self objectForKey:NSFilePosixPermissions] unsignedIntegerValue];
}

-(NSString *)fileOwnerAccountName {
   return [self objectForKey:NSFileOwnerAccountName];
}

-(NSString *)fileGroupOwnerAccountName {
   return [self objectForKey:NSFileGroupOwnerAccountName];
}

-(NSString *)fileType {
   return [self objectForKey:NSFileType];
}

-(uint64_t)fileSize {
   return [[self objectForKey:NSFileSize] unsignedLongLongValue];
}

@end
