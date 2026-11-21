/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSWorkspace.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSThread-Private.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import "LaunchServices.h"
#import "UTTypes.h"

#include <sys/mount.h>
#include <sys/param.h>
#include <unistd.h>
#include <string.h>

NSString * const NSWorkspaceWillPowerOffNotification=@"NSWorkspaceWillPowerOffNotification";

NSString * const NSWorkspaceRecycleOperation=@"NSWorkspaceRecycleOperation";
NSString * const NSWorkspaceCopyOperation=@"NSWorkspaceCopyOperation";
NSString * const NSWorkspaceLinkOperation=@"NSWorkspaceLinkOperation";
NSString * const NSWorkspaceMoveOperation=@"NSWorkspaceMoveOperation";
NSString * const NSWorkspaceDestroyOperation=@"NSWorkspaceDestroyOperation";

NSString * const NSWorkspaceApplicationKey=@"NSWorkspaceApplicationKey";
NSString * const NSApplicationPath=@"NSApplicationPath";
NSString * const NSApplicationName=@"NSApplicationName";
NSString * const NSApplicationProcessIdentifier=@"NSApplicationProcessIdentifier";

static NSArray *NSWorkspaceApplicationSearchRoots(void) {
   return [NSArray arrayWithObjects:
       @"/Applications",
       @"/Applications/Utilities",
       @"/System/Applications",
       @"/System/Applications/Utilities",
       @"/System/Library/CoreServices",
       nil];
}

@implementation NSWorkspace

+(NSWorkspace *)sharedWorkspace {
   return NSThreadSharedInstance(@"NSWorkspace");
}

/* Accessibility display preferences (10.12+).  There is no accessibility
 * preferences domain in this tree; the system defaults are all NO. */
-(BOOL)accessibilityDisplayShouldIncreaseContrast {
   return NO;
}

-(BOOL)accessibilityDisplayShouldReduceTransparency {
   return NO;
}

-(BOOL)accessibilityDisplayShouldReduceMotion {
   return NO;
}

-(BOOL)accessibilityDisplayShouldInvertColors {
   return NO;
}

-(BOOL)accessibilityDisplayShouldDifferentiateWithoutColor {
   return NO;
}

-init {
   _notificationCenter=[[NSNotificationCenter alloc] init];
   return self;
}

/* Resolve an app bundle's icon the way the Dock does: CFBundleIconFile,
 * then that name with .png/.icns, then Contents/Resources/icon.png. */
static NSImage *NSWorkspaceIconForBundlePath(NSString *path) {
   NSFileManager *fileManager=[NSFileManager defaultManager];
   NSBundle *bundle=[NSBundle bundleWithPath:path];
   NSString *iconFile=[bundle objectForInfoDictionaryKey:@"CFBundleIconFile"];
   NSString *iconPath=nil;

   if(iconFile==nil)
    iconFile=[bundle objectForInfoDictionaryKey:@"NSIcon"];

   if(iconFile!=nil && [iconFile length]>0){
    NSArray *candidates=[NSArray arrayWithObjects:
        [NSString stringWithFormat:@"%@/Contents/Resources/%@",path,iconFile],
        [NSString stringWithFormat:@"%@/Contents/Resources/%@.png",path,iconFile],
        [NSString stringWithFormat:@"%@/Contents/Resources/%@.icns",path,iconFile],
        nil];
    unsigned i;

    for(i=0;i<[candidates count];i++){
     NSString *candidate=[candidates objectAtIndex:i];

     if([fileManager fileExistsAtPath:candidate]){
      iconPath=candidate;
      break;
     }
    }
   }

   if(iconPath==nil){
    NSString *fallback=[NSString stringWithFormat:@"%@/Contents/Resources/icon.png",path];

    if([fileManager fileExistsAtPath:fallback])
     iconPath=fallback;
   }

   if(iconPath==nil)
    return nil;

   return [[[NSImage alloc] initWithContentsOfFile:iconPath] autorelease];
}

-(NSImage *)iconForFile:(NSString *)path {
   BOOL isDirectory=NO;

   if(path==nil)
    return nil;

   if(![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory)
    return nil;

   return NSWorkspaceIconForBundlePath(path);
}

-(NSImage *)iconForFiles:(NSArray *)array {
   if([array count]==0)
    return nil;

   return [self iconForFile:[array objectAtIndex:0]];
}

-(NSImage *)iconForFileType:(NSString *)type {
   /* There is no type-to-icon database; document icons are supplied by the
    * owning application. */
   return nil;
}

-(NSString *)localizedDescriptionForType:(NSString *)type {
   /* UTTypeCopyDescription is not implemented by this LaunchServices. */
   return nil;
}

-(NSString *)preferredFilenameExtensionForType:(NSString *)type {
   if(type==nil)
    return nil;

   CFStringRef extension=UTTypeCopyPreferredTagWithClass((CFStringRef)type,kUTTagClassFilenameExtension);

   if(extension==NULL)
    return nil;

   return [(NSString *)extension autorelease];
}

-(BOOL)filenameExtension:(NSString *)extension isValidForType:(NSString *)type {
   NSString *preferred;

   if(extension==nil || type==nil)
    return NO;

   preferred=[self preferredFilenameExtensionForType:type];

   if(preferred==nil)
    return NO;

   return [preferred caseInsensitiveCompare:extension]==NSOrderedSame;
}

-(BOOL)type:(NSString *)type conformsToType:(NSString *)conformsToType {
   if(type==nil || conformsToType==nil)
    return NO;

   return UTTypeConformsTo((CFStringRef)type,(CFStringRef)conformsToType)?YES:NO;
}

-(NSString *)typeOfFile:(NSString *)path error:(NSError **)error {
   NSString *extension=[path pathExtension];

   if(extension==nil || [extension length]==0)
    return nil;

   CFStringRef type=UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
       (CFStringRef)extension,NULL);

   if(type==NULL)
    return nil;

   return [(NSString *)type autorelease];
}

-(BOOL)openFile:(NSString *)path {
   if(path==nil)
    return NO;

   return [self openURL:[NSURL fileURLWithPath:path]];
}

-(BOOL)openFile:(NSString *)path withApplication:(NSString *)application {
   return [self openFile:path withApplication:application andDeactivate:NO];
}

-(BOOL)openTempFile:(NSString *)path {
   return [self openFile:path];
}

-(BOOL)openFile:(NSString *)path fromImage:(NSImage *)image at:(NSPoint)point inView:(NSView *)view {
   /* Window positioning on launch is not supported by LaunchServices. */
   return [self openFile:path];
}

-(BOOL)openFile:(NSString *)path withApplication:(NSString *)application andDeactivate:(BOOL)deactivate {
   NSString *applicationPath;
   LSLaunchURLSpec spec;
   OSStatus status;

   if(path==nil)
    return NO;

   applicationPath=[self pathForApplication:application];

   if(applicationPath==nil)
    return NO;

   spec.appURL=(CFURLRef)[NSURL fileURLWithPath:applicationPath];
   spec.asyncRefCon=NULL;
   spec.itemURLs=(CFArrayRef)[NSArray arrayWithObject:[NSURL fileURLWithPath:path]];
   spec.launchFlags=kLSLaunchDefaults | (deactivate?kLSLaunchAndHide:0);
   spec.passThruParams=NULL;
   spec.taskArgs=NULL;
   spec.taskEnv=NULL;

   status=LSOpenFromURLSpec(&spec,NULL);

   return status==0;
}

-(BOOL)openURL:(NSURL *)url {
   if(url==nil)
    return NO;

   return LSOpenCFURLRef((CFURLRef)url,NULL)==0;
}

-(BOOL)selectFile:(NSString *)path inFileViewerRootedAtPath:(NSString *)rootedAtPath {
   if(path==nil)
    return NO;

   LSRevealInFiler((CFArrayRef)[NSArray arrayWithObject:[NSURL fileURLWithPath:path]]);
   return YES;
}

-(void)slideImage:(NSImage *)image from:(NSPoint)from to:(NSPoint)to {
   /* No window-server animation primitive. */
}

-(BOOL)performFileOperation:(NSString *)operation source:(NSString *)source destination:(NSString *)destination files:(NSArray *)files tag:(int *)tag {
   NSFileManager *fileManager=[NSFileManager defaultManager];
   NSError *error=nil;
   unsigned i;

   if(operation==nil || files==nil)
    return NO;

   for(i=0;i<[files count];i++){
    NSString *name=[files objectAtIndex:i];
    NSString *fromPath=[source stringByAppendingPathComponent:name];
    NSString *toPath=[destination stringByAppendingPathComponent:name];
    BOOL result;

    if([operation isEqualToString:NSWorkspaceCopyOperation])
     result=[fileManager copyItemAtPath:fromPath toPath:toPath error:&error];
    else if([operation isEqualToString:NSWorkspaceMoveOperation])
     result=[fileManager moveItemAtPath:fromPath toPath:toPath error:&error];
    else if([operation isEqualToString:NSWorkspaceLinkOperation])
     result=[fileManager linkItemAtPath:fromPath toPath:toPath error:&error];
    else if([operation isEqualToString:NSWorkspaceDestroyOperation] ||
            [operation isEqualToString:NSWorkspaceRecycleOperation])
     result=[fileManager removeItemAtPath:fromPath error:&error];
    else
     result=NO;

    if(!result){
     if(tag!=NULL)
      *tag=i;
     return NO;
    }
   }

   return YES;
}

-(BOOL)getFileSystemInfoForPath:(NSString *)path isRemovable:(BOOL *)isRemovable isWritable:(BOOL *)isWritable isUnmountable:(BOOL *)isUnmountable description:(NSString **)description type:(NSString **)type {
   struct statfs fs;
   BOOL parsed=NO;

   if(path!=nil && statfs([path fileSystemRepresentation],&fs)==0){
    if(description!=NULL)
     *description=[NSString stringWithCString:fs.f_fstypename];
    if(type!=NULL)
     *type=[NSString stringWithCString:fs.f_fstypename];
    parsed=YES;
   }

   if(isRemovable!=NULL)
    *isRemovable=NO;
   if(isWritable!=NULL)
    *isWritable=access([path fileSystemRepresentation],W_OK)==0;
   if(isUnmountable!=NULL)
    *isUnmountable=YES;

   return parsed;
}

-(BOOL)getInfoForFile:(NSString *)path application:(NSString **)application type:(NSString **)type {
   BOOL isDirectory=NO;

   if(path==nil || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory])
    return NO;

   if(application!=NULL)
    *application=nil;

   if(type!=NULL){
    NSString *uti=[self typeOfFile:path error:NULL];

    if(uti==nil)
     uti=isDirectory?@"public.folder":@"public.data";
    *type=uti;
   }

   return YES;
}

-(void)checkForRemovableMedia {
}

-(NSArray *)mountNewRemovableMedia {
   return [NSArray array];
}

-(NSArray *)mountedRemovableMedia {
   return [NSArray array];
}

-(NSArray *)mountedLocalVolumePaths {
   struct statfs *mounts;
   int count,i;
   NSMutableArray *result=[NSMutableArray array];

   count=getmntinfo(&mounts,MNT_NOWAIT);

   for(i=0;i<count;i++)
    [result addObject:[NSString stringWithCString:mounts[i].f_mntonname]];

   return result;
}

-(BOOL)unmountAndEjectDeviceAtPath:(NSString *)path {
   if(path==nil)
    return NO;

   return unmount([path fileSystemRepresentation],0)==0;
}

-(BOOL)fileSystemChanged {
   return NO;
}

-(BOOL)userDefaultsChanged {
   return NO;
}

-(void)noteFileSystemChanged {
}

-(void)noteFileSystemChanged:(NSString *)path {
}

-(void)noteUserDefaultsChanged {
}

-(BOOL)isFilePackageAtPath:(NSString *)path {
   BOOL isDirectory=NO;
   NSString *extension;

   if(![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory)
    return NO;

   extension=[[path pathExtension] lowercaseString];

   return [extension isEqualToString:@"app"] ||
          [extension isEqualToString:@"bundle"] ||
          [extension isEqualToString:@"framework"] ||
          [extension isEqualToString:@"plugin"] ||
          [extension isEqualToString:@"kext"] ||
          [extension isEqualToString:@"prefpane"] ||
          [extension isEqualToString:@"xpc"];
}

-(NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)identifier {
   NSFileManager *fileManager=[NSFileManager defaultManager];
   NSArray *roots=NSWorkspaceApplicationSearchRoots();
   unsigned r;

   if(identifier==nil)
    return nil;

   for(r=0;r<[roots count];r++){
    NSString *root=[roots objectAtIndex:r];
    NSArray *contents=[fileManager contentsOfDirectoryAtPath:root error:NULL];
    unsigned i;

    for(i=0;i<[contents count];i++){
     NSString *name=[contents objectAtIndex:i];

     if(![[[name pathExtension] lowercaseString] isEqualToString:@"app"])
      continue;

     NSString *bundlePath=[root stringByAppendingPathComponent:name];
     NSBundle *bundle=[NSBundle bundleWithPath:bundlePath];

     if([[bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"] isEqualToString:identifier])
      return bundlePath;
    }
   }

   return nil;
}

-(NSString *)pathForApplication:(NSString *)application {
   NSFileManager *fileManager=[NSFileManager defaultManager];
   NSArray *roots=NSWorkspaceApplicationSearchRoots();
   unsigned r;

   if(application==nil)
    return nil;

   if([application isAbsolutePath] && [fileManager fileExistsAtPath:application])
    return application;

   for(r=0;r<[roots count];r++){
    NSString *root=[roots objectAtIndex:r];
    NSString *candidate=[root stringByAppendingPathComponent:application];
    NSString *candidateApp=[candidate stringByAppendingPathExtension:@"app"];

    if([fileManager fileExistsAtPath:candidate])
     return candidate;
    if([fileManager fileExistsAtPath:candidateApp])
     return candidateApp;
   }

   /* Fall back to matching the bundle name rather than the file name. */
   for(r=0;r<[roots count];r++){
    NSString *root=[roots objectAtIndex:r];
    NSArray *contents=[fileManager contentsOfDirectoryAtPath:root error:NULL];
    unsigned i;

    for(i=0;i<[contents count];i++){
     NSString *name=[contents objectAtIndex:i];

     if(![[[name pathExtension] lowercaseString] isEqualToString:@"app"])
      continue;

     if([[name stringByDeletingPathExtension] isEqualToString:application])
      return [root stringByAppendingPathComponent:name];
    }
   }

   return nil;
}

-(NSArray *)launchedApplications {
   /* The WindowServer owns the running-application registry and does not
    * expose it to clients yet. */
   return [NSArray array];
}

-(BOOL)launchApplication:(NSString *)application {
   NSString *path=[self pathForApplication:application];

   if(path==nil)
    return NO;

   return [self launchApplication:path showIcon:YES autolaunch:NO];
}

-(BOOL)launchApplication:(NSString *)application showIcon:(BOOL)showIcon autolaunch:(BOOL)autolaunch {
   NSString *path=[self pathForApplication:application];
   LSLaunchURLSpec spec;
   OSStatus status;

   if(path==nil)
    return NO;

   spec.appURL=(CFURLRef)[NSURL fileURLWithPath:path];
   spec.asyncRefCon=NULL;
   spec.itemURLs=NULL;
   spec.launchFlags=kLSLaunchDefaults;
   spec.passThruParams=NULL;
   spec.taskArgs=NULL;
   spec.taskEnv=NULL;

   status=LSOpenFromURLSpec(&spec,NULL);

   return status==0;
}

-(void)findApplications {
   /* LaunchServices owns the application database; nothing to rescan here. */
}

-(NSDictionary *)activeApplication {
   NSApplication *application=[NSApplication sharedApplication];

   /* Only the calling process's activation state is available to clients;
    * the frontmost application belongs to the WindowServer. */
   if(![application isActive])
    return nil;

   NSString *path=[[NSBundle mainBundle] bundlePath];
   NSString *name=[[path lastPathComponent] stringByDeletingPathExtension];
   NSDictionary *info=[NSDictionary dictionaryWithObjectsAndKeys:
       path,NSApplicationPath,
       name,NSApplicationName,
       [NSNumber numberWithInt:getpid()],NSApplicationProcessIdentifier,
       nil];

   return [NSDictionary dictionaryWithObject:info forKey:NSWorkspaceApplicationKey];
}

-(void)hideOtherApplications {
}

-(int)extendPowerOffBy:(int)milliseconds {
   return 0;
}

@end

@implementation NSWorkspace (CocotronAdditions)

- (BOOL)isFileHiddenAtPath:(NSString*)path
{
	return NO;
}

@end
