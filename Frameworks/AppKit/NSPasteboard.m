/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE. */

#import <AppKit/NSPasteboard.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSRaise.h>

#include <fcntl.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <mach/mach.h>
#include <servers/bootstrap.h>

#include "pasteboardd/pasteboard_ipc.h"

extern mach_port_t bootstrap_port;
extern void bootstrap_init(void);

NSString *const NSPasteboardTypeString = @"public.utf8-plain-text";
NSString *const NSPasteboardTypePDF = @"com.adobe.pdf";
NSString *const NSPasteboardTypeTIFF = @"public.tiff";
NSString *const NSPasteboardTypeRTF = @"public.rtf";
NSString *const NSPasteboardTypeRTFD = @"public.rtf-rtfd";
NSString *const NSPasteboardTypeHTML = @"public.html";
NSString *const NSPasteboardTypeTabularText = @"public.utf8-tabular-text";
NSString *const NSPasteboardTypeFont = @"public.font";
NSString *const NSPasteboardTypeRuler = @"com.apple.pasteboard.ruler";
NSString *const NSPasteboardTypeColor = @"com.apple.pasteboard.color";
NSString *const NSPasteboardTypePNG = @"public.png";
NSString *const NSPasteboardTypeFileURL = @"public.file-url";

NSString * const NSColorPboardType=@"NSColorPboardType";
NSString * const NSFileContentsPboardType=@"NSFileContentsPboardType";
NSString * const NSFilenamesPboardType=@"NSFilenamesPboardType";
NSString * const NSFontPboardType=@"NSFontPboardType";
NSString * const NSPDFPboardType=@"NSPDFPboardType";
NSString * const NSPICTPboardType=@"NSPICTPboardType";
NSString * const NSPostScriptPboardType=@"NSPostScriptPboardType";
NSString * const NSRTFDPboardType=@"NSRTFDPboardType";
NSString * const NSRTFPboardType=@"NSRTFPboardType";
NSString * const NSRulerPboardType=@"NSRulerPboardType";
NSString * const NSStringPboardType=@"NSStringPboardType";
NSString * const NSTabularTextPboardType=@"NSTabularTextPboardType";
NSString * const NSTIFFPboardType=@"NSTIFFPboardType";
NSString * const NSURLPboardType=@"NSURLPboardType";

NSString * const NSDragPboard=@"NSDragPboard";
NSString * const NSFindPboard=@"NSFindPboard";
NSString * const NSFontPboard=@"NSFontPboard";
NSString * const NSGeneralPboard=@"NSGeneralPboard";
NSString * const NSRulerPboard=@"NSRulerPboard";

/* Canonical type mapping.
 *
 * A ravynOS app may spell a pasteboard type either with the canonical
 * uniform type identifier (public.utf8-plain-text) or with the legacy
 * AppKit name (NSStringPboardType).  Both spellings name the same payload,
 * so every read and write goes through _canonicalType() and the board keeps
 * one entry per payload.
 */
static NSString *_canonicalType(NSString *type) {
    if(type == nil)
        return nil;

    if([type isEqualToString:@"NSStringPboardType"] ||
       [type isEqualToString:@"public.plain-text"])
        return NSPasteboardTypeString;
    if([type isEqualToString:@"NSRTFPboardType"])
        return NSPasteboardTypeRTF;
    if([type isEqualToString:@"NSRTFDPboardType"])
        return NSPasteboardTypeRTFD;
    if([type isEqualToString:@"NSTIFFPboardType"])
        return NSPasteboardTypeTIFF;
    if([type isEqualToString:@"NSPICTPboardType"])
        return NSPasteboardTypePNG;
    if([type isEqualToString:@"NSPDFPboardType"])
        return NSPasteboardTypePDF;
    if([type isEqualToString:@"NSURLPboardType"])
        return NSPasteboardTypeFileURL;

    return type;
}

/* The legacy spellings a canonical type is also known under. */
static NSArray *_legacyAliases(NSString *canonical) {
    if([canonical isEqualToString:NSPasteboardTypeString])
        return [NSArray arrayWithObjects:NSStringPboardType, nil];
    if([canonical isEqualToString:NSPasteboardTypeRTF])
        return [NSArray arrayWithObjects:NSRTFPboardType, nil];
    if([canonical isEqualToString:NSPasteboardTypeRTFD])
        return [NSArray arrayWithObjects:NSRTFDPboardType, nil];
    if([canonical isEqualToString:NSPasteboardTypeTIFF])
        return [NSArray arrayWithObjects:NSTIFFPboardType, nil];
    if([canonical isEqualToString:NSPasteboardTypePNG])
        return [NSArray arrayWithObjects:NSPICTPboardType, nil];
    if([canonical isEqualToString:NSPasteboardTypePDF])
        return [NSArray arrayWithObjects:NSPDFPboardType, nil];
    if([canonical isEqualToString:NSPasteboardTypeFileURL])
        return [NSArray arrayWithObjects:NSURLPboardType, nil];

    return [NSArray array];
}

@interface NSPasteboard ()
- (NSString *)_filePath;
- (NSMutableDictionary *)_load;
- (BOOL)_save:(NSDictionary *)dict;
- (mach_port_t)_serverPort;
- (BOOL)_rpc:(PBoardMessage *)msg reply:(PBoardMessage *)outReply;
@end

@implementation NSPasteboard

+(NSPasteboard *)generalPasteboard {
   return [self pasteboardWithName:NSGeneralPboard];
}

+(NSPasteboard *)pasteboardWithName:(NSString *)name {
   return [[NSDisplay currentDisplay] pasteboardWithName:name];
}

-(id)_initWithName:(NSString *)name {
   self = [super init];
   if(self != nil) {
    _name = [name copy];
    _serverPort = MACH_PORT_NULL;
   }
   return self;
}

-(void)dealloc {
   [_name release];
   [super dealloc];
}

/* ------------------------------------------------------------------ */
/* Mach transport                                                      */
/* ------------------------------------------------------------------ */

-(mach_port_t)_serverPort {
   if(_serverPort != MACH_PORT_NULL)
    return _serverPort;

   if(bootstrap_port == MACH_PORT_NULL)
    bootstrap_init();

   kern_return_t kr = bootstrap_look_up(bootstrap_port, PBOARD_SVC_NAME, &_serverPort);
   if(kr != KERN_SUCCESS) {
    /* The canonical macOS name must resolve to the very same daemon. */
    kr = bootstrap_look_up(bootstrap_port, PBOARD_SVC_NAME_APPLE, &_serverPort);
    if(kr != KERN_SUCCESS)
     _serverPort = MACH_PORT_NULL;
   }

   return _serverPort;
}

-(BOOL)_rpc:(PBoardMessage *)msg reply:(PBoardMessage *)outReply {
   mach_port_t port = [self _serverPort];
   mach_port_t replyPort = MACH_PORT_NULL;
   kern_return_t kr;

   if(port == MACH_PORT_NULL)
    return NO;

   if(mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &replyPort) != KERN_SUCCESS)
    return NO;
   if(mach_port_insert_right(mach_task_self(), replyPort, replyPort, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
    mach_port_deallocate(mach_task_self(), replyPort);
    return NO;
   }

   msg->header.msgh_remote_port = port;
   msg->header.msgh_local_port = replyPort;
   msg->header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
   msg->header.msgh_size = sizeof(PBoardMessage);

   kr = mach_msg((mach_msg_header_t *)msg, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                 sizeof(PBoardMessage), 0, MACH_PORT_NULL, 2000, MACH_PORT_NULL);
   if(kr != MACH_MSG_SUCCESS) {
    mach_port_deallocate(mach_task_self(), replyPort);
    return NO;
   }

   memset(outReply, 0, sizeof(PBoardMessage));
   kr = mach_msg((mach_msg_header_t *)outReply, MACH_RCV_MSG, 0, sizeof(PBoardMessage),
                 replyPort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
   mach_port_deallocate(mach_task_self(), replyPort);

   return kr == MACH_MSG_SUCCESS;
}

-(void)_fillRequest:(PBoardMessage *)msg {
   memset(msg, 0, sizeof(PBoardMessage));
   snprintf(msg->board, sizeof(msg->board), "%s", [_name UTF8String]);
}

/* Read a payload the daemon published in a shared memory segment. */
-(NSData *)_readSegment:(const char *)name length:(uint32_t)length {
   int fd = shm_open(name, O_RDONLY, 0600);
   void *map;
   NSData *data;

   if(fd < 0)
    return nil;

   map = mmap(NULL, length ? length : 1, PROT_READ, MAP_SHARED, fd, 0);
   close(fd);
   if(map == MAP_FAILED)
    return nil;

   data = [NSData dataWithBytes:map length:length];
   munmap(map, length ? length : 1);

   return data;
}

/* ------------------------------------------------------------------ */
/* Local fallback store (used when the daemon is not running)          */
/* ------------------------------------------------------------------ */

-(NSString *)_filePath {
   NSMutableString *safe = [NSMutableString string];
   const char *c = [_name UTF8String];

   while(c != NULL && *c != 0){
    if((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') ||
       (*c >= '0' && *c <= '9') || *c == '_' || *c == '-')
     [safe appendFormat:@"%c", *c];
    c++;
   }

   return [NSString stringWithFormat:@"/tmp/ravynos_pboard_%@.plist", safe];
}

-(NSMutableDictionary *)_load {
   NSData *data = [NSData dataWithContentsOfFile:[self _filePath]];

   if(data != nil) {
    id plist = [NSPropertyListSerialization propertyListFromData:data
        mutabilityOption:NSPropertyListMutableContainers
        format:NULL errorDescription:NULL];
    if([plist isKindOfClass:[NSDictionary class]])
     return [[plist mutableCopy] autorelease];
   }

   return [NSMutableDictionary dictionaryWithObjectsAndKeys:
       [NSNumber numberWithInt:0], @"changeCount",
       [NSArray array], @"types",
       [NSMutableDictionary dictionary], @"data",
       nil];
}

-(BOOL)_save:(NSDictionary *)dict {
   NSData *data = [NSPropertyListSerialization dataFromPropertyList:dict
       format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];

   if(data == nil)
    return NO;

   /* flock() keeps two writers from losing a paste while the daemon is
    * unavailable (single-process test setups). */
   NSString *path = [self _filePath];
   int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0600);
   if(fd < 0)
    return NO;
   flock(fd, LOCK_EX);
   BOOL ok = write(fd, [data bytes], [data length]) == (ssize_t)[data length];
   flock(fd, LOCK_UN);
   close(fd);

   return ok;
}

/* ------------------------------------------------------------------ */
/* Public interface                                                    */
/* ------------------------------------------------------------------ */

-(int)changeCount {
   PBoardMessage msg;
   PBoardMessage reply;

   [self _fillRequest:&msg];
   msg.op = PBOARD_OP_GET_CHANGE_COUNT;
   if([self _rpc:&msg reply:&reply])
    return reply.changeCount;

   return [[[self _load] objectForKey:@"changeCount"] intValue];
}

-(NSArray *)types {
   PBoardMessage msg;
   PBoardMessage reply;
   NSMutableArray *result = [NSMutableArray array];

   [self _fillRequest:&msg];
   msg.op = PBOARD_OP_GET_TYPES;
   if([self _rpc:&msg reply:&reply]) {
    uint32_t off = 0;
    while(off < reply.dataLen && reply.data[off] != 0) {
     NSString *canonical = [NSString stringWithUTF8String:reply.data + off];
     if(canonical != nil) {
      [result addObject:canonical];
      [result addObjectsFromArray:_legacyAliases(canonical)];
      off += [canonical length] + 1;
     } else {
      break;
     }
    }
    return result;
   }

   NSArray *stored = [[self _load] objectForKey:@"types"];
   for(unsigned i = 0; i < [stored count]; i++) {
    NSString *canonical = _canonicalType([stored objectAtIndex:i]);
    if(![result containsObject:canonical])
     [result addObject:canonical];
   }
   return result;
}

-(NSString *)availableTypeFromArray:(NSArray *)types {
   NSArray *available = [self types];
   unsigned count = [types count];

   for(unsigned i = 0; i < count; i++) {
    NSString *check = [types objectAtIndex:i];
    NSString *canonical = _canonicalType(check);

    if([available containsObject:check])
     return check;
    if(canonical != nil && [available containsObject:canonical])
     return canonical;
   }

   return nil;
}

-(NSData *)dataForType:(NSString *)type {
   PBoardMessage msg;
   PBoardMessage reply;
   NSString *canonical = _canonicalType(type);

   if(canonical == nil)
    return nil;

   [self _fillRequest:&msg];
   msg.op = PBOARD_OP_GET_DATA;
   snprintf(msg.type, sizeof(msg.type), "%s", [canonical UTF8String]);
   if([self _rpc:&msg reply:&reply]) {
    if(reply.flags & PBOARD_F_INLINE)
     return [NSData dataWithBytes:reply.data length:reply.dataLen];
    if(reply.totalLen > 0 && reply.shmName[0] != 0)
     return [self _readSegment:reply.shmName length:reply.totalLen];
    return nil;
   }

   NSDictionary *data = [[self _load] objectForKey:@"data"];
   NSData *stored = [data objectForKey:canonical];
   if(stored == nil)
    stored = [data objectForKey:type];
   return stored;
}

-(NSString *)stringForType:(NSString *)type {
   NSData *data = [self dataForType:type];
   NSString *str;

   if(data == nil)
    return nil;

   /* UTF-8 first: the canonical text type is UTF-8.  UTF-16 is the fallback
    * for payloads written by older clients. */
   str = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
   if(str == nil)
    str = [[[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding] autorelease];

   return str;
}

-(id)propertyListForType:(NSString *)type {
	NSData* data = [self dataForType: type];
	NSString* errorDesc = nil;
	id plist = [NSPropertyListSerialization propertyListFromData: data mutabilityOption: NSPropertyListImmutable format: NULL errorDescription: &errorDesc];
	if (plist && errorDesc == nil) {
		return plist;
	}
	NSLog(@"propertyListForType: produced error: %@", errorDesc);
	return nil;
}

-(int)declareTypes:(NSArray *)types owner:(id)owner {
   PBoardMessage msg;
   PBoardMessage reply;
   NSMutableArray *canonical = [NSMutableArray array];
   NSMutableData *list = [NSMutableData data];
   unsigned i;

   for(i = 0; i < [types count]; i++) {
    NSString *canonicalType = _canonicalType([types objectAtIndex:i]);
    if(canonicalType == nil || [canonical containsObject:canonicalType])
     continue;
    [canonical addObject:canonicalType];
    [list appendData:[canonicalType dataUsingEncoding:NSUTF8StringEncoding]];
    [list appendBytes:"\0" length:1];
   }

   [self _fillRequest:&msg];
   msg.op = PBOARD_OP_DECLARE_TYPES;
   msg.dataLen = (uint32_t)[list length];
   if(msg.dataLen > PBOARD_INLINE_MAX)
    msg.dataLen = PBOARD_INLINE_MAX;
   memcpy(msg.data, [list bytes], msg.dataLen);

   if([self _rpc:&msg reply:&reply])
    return reply.changeCount;

   NSMutableDictionary *dict = [self _load];
   [dict setObject:[NSNumber numberWithInt:[[dict objectForKey:@"changeCount"] intValue] + 1]
            forKey:@"changeCount"];
   [dict setObject:canonical forKey:@"types"];
   [dict setObject:[NSMutableDictionary dictionary] forKey:@"data"];
   [self _save:dict];

   return [[dict objectForKey:@"changeCount"] intValue];
}

-(int)addTypes:(NSArray *)types owner:(id)owner {
   PBoardMessage msg;
   PBoardMessage reply;
   NSMutableData *list = [NSMutableData data];
   unsigned i;

   for(i = 0; i < [types count]; i++) {
    NSString *canonicalType = _canonicalType([types objectAtIndex:i]);
    if(canonicalType == nil)
     continue;
    [list appendData:[canonicalType dataUsingEncoding:NSUTF8StringEncoding]];
    [list appendBytes:"\0" length:1];
   }

   [self _fillRequest:&msg];
   msg.op = PBOARD_OP_ADD_TYPES;
   msg.dataLen = (uint32_t)[list length];
   if(msg.dataLen > PBOARD_INLINE_MAX)
    msg.dataLen = PBOARD_INLINE_MAX;
   memcpy(msg.data, [list bytes], msg.dataLen);

   if([self _rpc:&msg reply:&reply])
    return reply.changeCount;

   NSMutableDictionary *dict = [self _load];
   NSMutableArray *all = [NSMutableArray arrayWithArray:[dict objectForKey:@"types"]];
   for(i = 0; i < [types count]; i++) {
    NSString *canonicalType = _canonicalType([types objectAtIndex:i]);
    if(canonicalType != nil && ![all containsObject:canonicalType])
     [all addObject:canonicalType];
   }
   [dict setObject:all forKey:@"types"];
   [dict setObject:[NSNumber numberWithInt:[[dict objectForKey:@"changeCount"] intValue] + 1]
            forKey:@"changeCount"];
   [self _save:dict];

   return [[dict objectForKey:@"changeCount"] intValue];
}

-(BOOL)setData:(NSData *)data forType:(NSString *)type {
   PBoardMessage msg;
   PBoardMessage reply;
   NSString *canonical = _canonicalType(type);

   if(data == nil || canonical == nil)
    return NO;

   [self _fillRequest:&msg];
   msg.op = PBOARD_OP_SET_DATA;
   snprintf(msg.type, sizeof(msg.type), "%s", [canonical UTF8String]);
   msg.dataLen = (uint32_t)[data length];
   msg.totalLen = (uint32_t)[data length];

   if(msg.dataLen > PBOARD_INLINE_MAX) {
    /* Too large for the inline buffer (a screenshot PNG, for example).
     * Stage it in a POSIX shm segment the daemon copies from; xnu allows one
     * ftruncate per segment, so every upload gets a fresh name. */
    static unsigned int uploadSeq = 0;
    int fd;

    snprintf(msg.shmName, sizeof(msg.shmName), "/pboard_up_%d_%u",
             (int)getpid(), ++uploadSeq);
    shm_unlink(msg.shmName);
    fd = shm_open(msg.shmName, O_CREAT | O_EXCL | O_RDWR, 0600);
    if(fd < 0)
     return NO;
    if(ftruncate(fd, (off_t)msg.totalLen) != 0) {
     close(fd);
     shm_unlink(msg.shmName);
     return NO;
    }
    {
     void *mapped = mmap(NULL, msg.totalLen, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
     if(mapped == MAP_FAILED) {
      close(fd);
      shm_unlink(msg.shmName);
      return NO;
     }
     memcpy(mapped, [data bytes], msg.totalLen);
     munmap(mapped, msg.totalLen);
    }
    close(fd);

    msg.flags = PBOARD_F_SHM_UPLOAD;
    msg.dataLen = 0;
   } else if(msg.dataLen) {
    memcpy(msg.data, [data bytes], msg.dataLen);
   }

   if([self _rpc:&msg reply:&reply]) {
    /* A file URL also exposes the legacy filename list, and vice versa. */
    if([canonical isEqualToString:NSPasteboardTypeFileURL] && !_fillingFileTypes) {
     NSString *url = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
     NSString *path = [url hasPrefix:@"file://"] ? [url substringFromIndex:7] : nil;
     if(path != nil) {
      _fillingFileTypes = YES;
      [self setPropertyList:[NSArray arrayWithObject:path] forType:NSFilenamesPboardType];
      _fillingFileTypes = NO;
     }
    }
    return YES;
   }

   NSMutableDictionary *dict = [self _load];
   NSMutableDictionary *store = [NSMutableDictionary dictionaryWithDictionary:[dict objectForKey:@"data"]];
   NSMutableArray *all = [NSMutableArray arrayWithArray:[dict objectForKey:@"types"]];

   if(![all containsObject:canonical])
    [all addObject:canonical];

   [store setObject:data forKey:canonical];
   [dict setObject:store forKey:@"data"];
   [dict setObject:all forKey:@"types"];
   [dict setObject:[NSNumber numberWithInt:[[dict objectForKey:@"changeCount"] intValue] + 1]
            forKey:@"changeCount"];

   if(![self _save:dict])
    return NO;

   if([canonical isEqualToString:NSPasteboardTypeFileURL] && !_fillingFileTypes) {
    NSString *url = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    NSString *path = [url hasPrefix:@"file://"] ? [url substringFromIndex:7] : nil;
    if(path != nil) {
     _fillingFileTypes = YES;
     [self setPropertyList:[NSArray arrayWithObject:path] forType:NSFilenamesPboardType];
     _fillingFileTypes = NO;
    }
   }

   return YES;
}

-(BOOL)setString:(NSString *)string forType:(NSString *)type {
   NSData *data;

   if(string == nil)
    return NO;

   data = [string dataUsingEncoding:NSUTF8StringEncoding];
   if(data == nil)
    data = [string dataUsingEncoding:NSUnicodeStringEncoding];
   if(data == nil)
    return NO;

   return [self setData:data forType:type];
}

-(BOOL)setPropertyList:(id)plist forType:(NSString *)type {
	NSString* errorDesc = nil;
	NSData* data = [NSPropertyListSerialization dataFromPropertyList: plist format: NSPropertyListXMLFormat_v1_0 errorDescription: &errorDesc];
	if (data && errorDesc == nil) {
		BOOL ok = [self setData: data forType: type];
		/* A filename list also publishes the canonical file URL. */
		if(ok && !_fillingFileTypes && [type isEqualToString:NSFilenamesPboardType] &&
		   [plist isKindOfClass:[NSArray class]] && [plist count] > 0) {
			NSString *first = [plist objectAtIndex:0];
			if([first isKindOfClass:[NSString class]]) {
				NSString *url = [NSString stringWithFormat:@"file://%@", first];
				_fillingFileTypes = YES;
				[self setString:url forType:NSPasteboardTypeFileURL];
				_fillingFileTypes = NO;
			}
		}
		return ok;
	}
	NSLog(@"setPropertyList:forType: produced error: %@", errorDesc);
   return NO;
}

-(BOOL)clearContents {
   return [self declareTypes:[NSArray array] owner:nil] > 0;
}

-(BOOL)writeObjects:(NSArray *)objects {
   unsigned i;

   if(objects == nil)
    return NO;

   for(i = 0; i < [objects count]; i++) {
    id object = [objects objectAtIndex:i];

    if([object isKindOfClass:[NSString class]]) {
     [self declareTypes:[NSArray arrayWithObjects:NSPasteboardTypeString, NSStringPboardType, nil] owner:nil];
     [self setString:object forType:NSPasteboardTypeString];
    } else if([object isKindOfClass:[NSURL class]]) {
     [self declareTypes:[NSArray arrayWithObjects:NSPasteboardTypeFileURL, NSURLPboardType, nil] owner:nil];
     [self setString:[object absoluteString] forType:NSPasteboardTypeFileURL];
    } else if([object isKindOfClass:[NSData class]]) {
     [self declareTypes:[NSArray arrayWithObjects:NSPasteboardTypeTIFF, NSPasteboardTypePNG, nil] owner:nil];
     [self setData:object forType:NSPasteboardTypeTIFF];
    } else if([object isKindOfClass:[NSArray class]]) {
     [self declareTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil] owner:nil];
     [self setPropertyList:object forType:NSFilenamesPboardType];
    } else if(object != nil) {
     return NO;
    }
   }

   return YES;
}

-(NSArray *)readObjectsForClasses:(NSArray *)classArray options:(NSDictionary *)options {
   NSMutableArray *result = [NSMutableArray array];
   unsigned i;

   for(i = 0; i < [classArray count]; i++) {
    Class class = [classArray objectAtIndex:i];

    if(class == [NSString class]) {
     NSString *text = [self stringForType:NSPasteboardTypeString];
     if(text == nil)
      text = [self stringForType:NSStringPboardType];
     if(text != nil)
      [result addObject:text];
    } else if(class == [NSURL class]) {
     NSString *url = [self stringForType:NSPasteboardTypeFileURL];
     if(url == nil)
      url = [self stringForType:NSURLPboardType];
     if(url != nil)
      [result addObject:[NSURL URLWithString:url]];
    } else if(class == [NSData class]) {
     NSData *data = [self dataForType:NSPasteboardTypeTIFF];
     if(data == nil)
      data = [self dataForType:NSPasteboardTypePNG];
     if(data != nil)
      [result addObject:data];
    } else if(class == [NSArray class]) {
     id list = [self propertyListForType:NSFilenamesPboardType];
     if(list != nil)
      [result addObject:list];
    }
   }

   return result;
}

@end
