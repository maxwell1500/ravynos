#import "ArchiveEngine.h"
#import <zlib.h>
#import <sys/stat.h>
#import <dirent.h>

static void setError(NSString **e, NSString *msg) {
    if (e) *e = msg;
}

static BOOL safeEntryPath(NSString *entry) {
    if (!entry || entry.length == 0) return NO;
    if ([entry hasPrefix:@"/"]) return NO;
    NSArray *comps = [entry pathComponents];
    for (NSString *c in comps) {
        if ([c isEqualToString:@".."]) return NO;
    }
    return YES;
}

static NSString *uniquePath(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return path;
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSString *name = [path lastPathComponent];
    NSString *base = [name stringByDeletingPathExtension];
    NSString *ext = [name pathExtension];
    for (int i = 2; i < 10000; i++) {
        NSString *candidate;
        if (ext.length > 0) candidate = [NSString stringWithFormat:@"%@ %@.%@", base, @(i), ext];
        else candidate = [NSString stringWithFormat:@"%@ %@", name, @(i)];
        // use " 2" style with space before number? macOS uses space. Use " 2".
        if (ext.length > 0) candidate = [NSString stringWithFormat:@"%@ %d.%@", base, i, ext];
        else candidate = [NSString stringWithFormat:@"%@ %d", name, i];
        NSString *full = [dir stringByAppendingPathComponent:candidate];
        if (![fm fileExistsAtPath:full]) return full;
    }
    return path;
}

// ---------- gzip ----------

static NSData *gunzipData(NSData *input) {
    if (input.length < 2) return nil;
    z_stream strm; memset(&strm, 0, sizeof(strm));
    // +16 for gzip
    if (inflateInit2(&strm, 16 + 15) != Z_OK) return nil;
    strm.next_in = (Bytef *)input.bytes;
    strm.avail_in = (uInt)input.length;
    NSMutableData *out = [NSMutableData dataWithLength:input.length * 4 + 4096];
    int ret;
    do {
        if (strm.total_out >= out.length) [out setLength:out.length * 2 + 4096];
        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);
        ret = inflate(&strm, Z_NO_FLUSH);
        if (ret == Z_NEED_DICT || ret == Z_DATA_ERROR || ret == Z_MEM_ERROR) {
            inflateEnd(&strm);
            return nil;
        }
    } while (ret != Z_STREAM_END && strm.avail_out == 0);
    inflateEnd(&strm);
    if (ret != Z_STREAM_END) return nil;
    [out setLength:strm.total_out];
    return out;
}

// ---------- deflate / inflate for zip ----------

static NSData *deflateRaw(NSData *input) {
    z_stream strm; memset(&strm, 0, sizeof(strm));
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;
    strm.next_in = (Bytef *)input.bytes;
    strm.avail_in = (uInt)input.length;
    NSMutableData *out = [NSMutableData dataWithLength:input.length + 256 + (input.length / 100 + 1)];
    int ret;
    do {
        if (strm.total_out >= out.length) [out setLength:out.length * 2 + 256];
        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);
        ret = deflate(&strm, Z_FINISH);
        if (ret == Z_STREAM_ERROR) { deflateEnd(&strm); return nil; }
    } while (ret != Z_STREAM_END);
    [out setLength:strm.total_out];
    deflateEnd(&strm);
    return out;
}

static NSData *inflateRaw(NSData *input, NSUInteger expectedSize) {
    z_stream strm; memset(&strm, 0, sizeof(strm));
    if (inflateInit2(&strm, -15) != Z_OK) return nil;
    strm.next_in = (Bytef *)input.bytes;
    strm.avail_in = (uInt)input.length;
    NSMutableData *out = [NSMutableData dataWithLength:expectedSize > 0 ? expectedSize : input.length * 4 + 4096];
    int ret;
    do {
        if (strm.total_out >= out.length) [out setLength:out.length * 2 + 4096];
        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);
        ret = inflate(&strm, Z_NO_FLUSH);
        if (ret == Z_NEED_DICT || ret == Z_DATA_ERROR || ret == Z_MEM_ERROR) { inflateEnd(&strm); return nil; }
    } while (ret != Z_STREAM_END && strm.avail_out == 0);
    inflateEnd(&strm);
    if (ret != Z_STREAM_END) return nil;
    [out setLength:strm.total_out];
    return out;
}

// ---------- little endian helpers ----------

static void put16(NSMutableData *d, uint16_t v) { uint8_t b[2] = {v & 0xff, (v>>8)&0xff}; [d appendBytes:b length:2]; }
static void put32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v & 0xff, (v>>8)&0xff, (v>>16)&0xff, (v>>24)&0xff}; [d appendBytes:b length:4]; }
static uint16_t get16(const uint8_t *p) { return p[0] | (p[1]<<8); }
static uint32_t get32(const uint8_t *p) { return p[0] | (p[1]<<8) | (p[2]<<16) | (p[3]<<24); }

// ---------- ZIP reading ----------

typedef struct { NSString *name; uint16_t method; uint32_t crc; uint32_t csize; uint32_t usize; uint32_t offset; BOOL isDir; } ZipEntry;

static NSArray *readZipEntries(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    // find EOCD
    long eocd = -1;
    for (long i = (long)len - 22; i >= 0; i--) {
        if (get32(bytes + i) == 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) return nil;
    uint32_t cdOffset = get32(bytes + eocd + 16);
    uint32_t cdSize = get32(bytes + eocd + 12);
    uint16_t numEntries = get16(bytes + eocd + 10);
    NSUInteger pos = cdOffset;
    // Re-parse into dictionaries
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < numEntries; i++) {
        if (get32(bytes + pos) != 0x02014b50) break;
        uint16_t fnLen = get16(bytes + pos + 28);
        uint16_t exLen = get16(bytes + pos + 30);
        uint16_t cmLen = get16(bytes + pos + 32);
        uint16_t method = get16(bytes + pos + 10);
        uint32_t crc = get32(bytes + pos + 16);
        uint32_t csize = get32(bytes + pos + 20);
        uint32_t usize = get32(bytes + pos + 24);
        uint32_t lho = get32(bytes + pos + 42);
        NSData *nameData = [NSData dataWithBytes:bytes + pos + 46 length:fnLen];
        NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
        if (!name) name = [[NSString alloc] initWithData:nameData encoding:NSISOLatin1StringEncoding];
        BOOL isDir = [name hasSuffix:@"/"];
        if (isDir && name.length > 0) name = [name substringToIndex:name.length-1];
        // read local header to find data offset
        NSUInteger dataOffset = lho;
        // local header: signature 4, then 26 bytes to filename length? local header fixed 30 bytes
        uint16_t lfnLen = get16(bytes + lho + 26);
        uint16_t lexLen = get16(bytes + lho + 28);
        dataOffset = lho + 30 + lfnLen + lexLen;
        NSData *compData = [NSData dataWithBytes:bytes + dataOffset length:csize];
        NSData *fileData = nil;
        uint32_t extAttr = get32(bytes + pos + 38);
        BOOL isSymlink = (((extAttr >> 16) & S_IFMT) == S_IFLNK);
        if (isDir) {
            fileData = [NSData data];
        } else if (method == 0) {
            fileData = compData;
        } else if (method == 8) {
            fileData = inflateRaw(compData, usize);
        } else {
            fileData = nil;
        }

        if (!isDir && !isSymlink && fileData != nil && fileData.length > 0) {
            uLong actual = crc32(0L, (const Bytef *)fileData.bytes,
                                 (uInt)fileData.length);
            if ((uint32_t)actual != crc)
                return nil; /* corrupt entry: refuse the whole archive */
        }
        if (isSymlink && fileData != nil) {
            NSString *target = [[NSString alloc] initWithData:fileData
                                                     encoding:NSUTF8StringEncoding];
            /* A symlink escaping the destination would let the extraction
             * write outside it. */
            if (target != nil && ([target hasPrefix:@"/"] ||
                                  [target rangeOfString:@".."].location != NSNotFound))
                return nil;
        }
        [result addObject:@{@"name": name, @"data": fileData ?: [NSData data],
                            @"isDir": @(isDir), @"symlink": @(isSymlink),
                            @"size": @(usize)}];
        pos += 46 + fnLen + exLen + cmLen;
    }
    return result;
}

// ---------- TAR reading ----------

static NSString *tarReadString(const uint8_t *p, NSUInteger maxLen) {
    // null-terminated
    NSUInteger len = 0;
    while (len < maxLen && p[len] != 0) len++;
    NSData *d = [NSData dataWithBytes:p length:len];
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    return s ?: @"";
}

static unsigned long long tarOctal(const uint8_t *p, NSUInteger maxLen) {
    // parse octal, handle leading spaces
    unsigned long long val = 0;
    NSUInteger i = 0;
    while (i < maxLen && (p[i] == ' ' || p[i] == 0)) i++;
    while (i < maxLen && p[i] >= '0' && p[i] <= '7') {
        val = val * 8 + (p[i] - '0');
        i++;
    }
    return val;
}

static NSArray *readTarEntries(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    NSMutableArray *entries = [NSMutableArray array];
    NSUInteger offset = 0;
    while (offset + 512 <= len) {
        const uint8_t *hdr = bytes + offset;
        // check all zeros -> end
        BOOL allZero = YES;
        for (int i = 0; i < 512; i++) if (hdr[i] != 0) { allZero = NO; break; }
        if (allZero) break;
        NSString *name = tarReadString(hdr, 100);
        if (name.length == 0) { offset += 512; continue; }
        NSString *prefix = tarReadString(hdr + 345, 155);
        if (prefix.length > 0) name = [prefix stringByAppendingPathComponent:name];
        unsigned long long size = tarOctal(hdr + 124, 12);
        char typeflag = (char)hdr[156];
        BOOL isDir = (typeflag == '5');
        if (typeflag == '0' || typeflag == '\0' || typeflag == ' ' || isDir) {
            // read data
            NSData *fileData = [NSData data];
            if (!isDir && size > 0) {
                if (offset + 512 + size <= len) fileData = [NSData dataWithBytes:bytes + offset + 512 length:size];
            }
            [entries addObject:@{@"name": name, @"data": fileData, @"isDir": @(isDir), @"size": @(size)}];
        }
        // advance
        NSUInteger blocks = (size + 511) / 512;
        offset += 512 + blocks * 512;
    }
    return entries;
}

// ---------- collect files for compression ----------

static void collectForZip(NSString *path, NSString *base, NSMutableArray *items) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return;
    if (isDir) {
        [items addObject:@{@"path": path, @"arcname": base.length ? [base stringByAppendingString:@"/"] : [[path lastPathComponent] stringByAppendingString:@"/"], @"isDir": @YES}];
        NSArray *contents = [fm contentsOfDirectoryAtPath:path error:nil];
        for (NSString *c in contents) {
            collectForZip([path stringByAppendingPathComponent:c], base.length ? [base stringByAppendingPathComponent:c] : c, items);
        }
    } else {
        NSString *arcname = base.length ? base : [path lastPathComponent];
        [items addObject:@{@"path": path, @"arcname": arcname, @"isDir": @NO}];
    }
}

// ---------- ArchiveEngine ----------

@implementation ArchiveEngine

+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                    progress:(ArchiveProgressCallback)progress
                     context:(void *)context
                       error:(NSString **)errorOut {
    NSData *raw = [NSData dataWithContentsOfFile:archivePath];
    if (!raw || raw.length == 0) { setError(errorOut, @"Cannot read archive"); return NO; }

    NSArray *entries = nil;
    // detect
    const uint8_t *b = raw.bytes;
    BOOL isZip = NO;
    if (raw.length >= 4 && b[0]==0x50 && b[1]==0x4B && (b[2]==0x03 || b[2]==0x05 || b[2]==0x07)) isZip = YES;
    NSString *lower = [archivePath lowercaseString];
    if ([lower hasSuffix:@".zip"]) isZip = YES;

    /* bzip2 and xz are not linked into this image; say so instead of feeding
     * compressed bytes to the tar reader. */
    if ((raw.length >= 3 && b[0]=='B' && b[1]=='Z' && b[2]=='h') ||
        (raw.length >= 6 && b[0]==0xFD && b[1]=='7' && b[2]=='z' &&
         b[3]=='X' && b[4]=='Z' && b[5]==0x00)) {
        setError(errorOut, @"bzip2/xz extraction is not available in this build");
        return NO;
    }

    if (isZip) {
        entries = readZipEntries(raw);
    } else if ([lower hasSuffix:@".gz"] || [lower hasSuffix:@".tgz"] || (raw.length>=2 && b[0]==0x1f && b[1]==0x8b)) {
        NSData *tarData = gunzipData(raw);
        if (!tarData) { setError(errorOut, @"Failed to gunzip"); return NO; }
        entries = readTarEntries(tarData);
    } else {
        entries = readTarEntries(raw);
    }

    if (!entries) { setError(errorOut, @"Unsupported or corrupt archive"); return NO; }

    // validate all paths first
    for (NSDictionary *e in entries) {
        NSString *name = e[@"name"];
        if (!safeEntryPath(name)) { setError(errorOut, [NSString stringWithFormat:@"Unsafe path in archive: %@", name]); return NO; }
    }

    // determine top-level
    NSMutableSet *tops = [NSMutableSet set];
    for (NSDictionary *e in entries) {
        NSString *name = e[@"name"];
        NSString *first = [[name pathComponents] firstObject];
        if (first.length > 0) [tops addObject:first];
    }

    NSString *parent = [archivePath stringByDeletingLastPathComponent];
    NSString *root = parent;
    if (tops.count > 1) {
        NSString *base = [archivePath lastPathComponent];
        // strip extensions
        if ([base.lowercaseString hasSuffix:@".tar.gz"]) base = [base substringToIndex:base.length - 7];
        else if ([base.lowercaseString hasSuffix:@".tgz"]) base = [base substringToIndex:base.length - 4];
        else base = [base stringByDeletingPathExtension];
        root = [parent stringByAppendingPathComponent:base];
        root = uniquePath(root);
        [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // total bytes
    long long totalBytes = 0;
    for (NSDictionary *e in entries) totalBytes += [e[@"size"] longLongValue];
    if (totalBytes == 0) totalBytes = 1;

    long long done = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSDictionary *e in entries) {
        NSString *name = e[@"name"];
        if (name.length == 0) continue;
        NSString *target = [root stringByAppendingPathComponent:name];
        BOOL isDir = [e[@"isDir"] boolValue];
        NSData *fileData = e[@"data"];
        if (isDir) {
            [fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:nil];
        } else {
            [fm createDirectoryAtPath:[target stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            // collision handling
            if ([fm fileExistsAtPath:target]) target = uniquePath(target);
            [fileData writeToFile:target atomically:YES];
        }
        done += [e[@"size"] longLongValue];
        if (progress) progress(context, name, done, totalBytes);
    }
    return YES;
}

+ (BOOL)compressPaths:(NSArray<NSString *> *)sourcePaths
          destination:(NSString *)destZipPath
             progress:(ArchiveProgressCallback)progress
              context:(void *)context
                error:(NSString **)errorOut {
    if (!sourcePaths || sourcePaths.count == 0) { setError(errorOut, @"No input paths"); return NO; }
    // determine destination
    NSString *dest = destZipPath;
    if (dest.length == 0) {
        NSString *parent = [[sourcePaths[0] stringByDeletingLastPathComponent] stringByStandardizingPath];
        if (sourcePaths.count == 1) {
            NSString *name = [[sourcePaths[0] lastPathComponent] stringByAppendingString:@".zip"];
            dest = [parent stringByAppendingPathComponent:name];
        } else {
            dest = [parent stringByAppendingPathComponent:@"Archive.zip"];
        }
    }
    dest = uniquePath(dest);

    // collect items
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *p in sourcePaths) {
        NSString *base = [p lastPathComponent];
        collectForZip(p, base, items);
    }

    // total bytes
    long long totalBytes = 0;
    for (NSDictionary *it in items) {
        if ([it[@"isDir"] boolValue]) continue;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:it[@"path"] error:nil];
        totalBytes += [attrs[NSFileSize] longLongValue];
    }
    if (totalBytes == 0) totalBytes = 1;

    // write zip
    NSMutableData *out = [NSMutableData data];
    NSMutableArray *central = [NSMutableArray array];
    long long done = 0;
    for (NSDictionary *it in items) {
        NSString *arcname = it[@"arcname"];
        BOOL isDir = [it[@"isDir"] boolValue];
        NSData *fileData = [NSData data];
        if (!isDir) fileData = [NSData dataWithContentsOfFile:it[@"path"]] ?: [NSData data];
        NSData *deflated = nil;
        uint16_t method = 0;
        if (!isDir && fileData.length > 0) {
            NSData *d = deflateRaw(fileData);
            if (d && d.length < fileData.length) { deflated = d; method = 8; }
        }
        NSData *payload = (method == 8) ? deflated : fileData;

        uint32_t crc = (uint32_t)crc32(0, (const Bytef *)fileData.bytes, (uInt)fileData.length);
        uint32_t usize = (uint32_t)fileData.length;
        uint32_t csize = (uint32_t)payload.length;

        uint32_t localOffset = (uint32_t)out.length;
        // local header
        put32(out, 0x04034b50);
        put16(out, 20); // version needed
        put16(out, 0); // flags
        put16(out, method);
        // mod time/date (dummy)
        put16(out, 0); put16(out, 0);
        put32(out, crc);
        put32(out, csize);
        put32(out, usize);
        NSData *nameBytes = [arcname dataUsingEncoding:NSUTF8StringEncoding];
        put16(out, (uint16_t)nameBytes.length);
        put16(out, 0); // extra len
        [out appendData:nameBytes];
        [out appendData:payload];

        // central dir entry
        NSMutableData *cd = [NSMutableData data];
        put32(cd, 0x02014b50);
        put16(cd, 20); put16(cd, 20);
        put16(cd, 0); // flags
        put16(cd, method);
        put16(cd, 0); put16(cd, 0);
        put32(cd, crc);
        put32(cd, csize);
        put32(cd, usize);
        put16(cd, (uint16_t)nameBytes.length);
        put16(cd, 0); put16(cd, 0);
        put16(cd, 0); put16(cd, 0);
        put32(cd, 0); // external attr
        put32(cd, localOffset);
        [cd appendData:nameBytes];
        [central addObject:cd];

        done += fileData.length;
        if (progress) progress(context, arcname, done, totalBytes);
    }

    // write central directory
    uint32_t cdOffset = (uint32_t)out.length;
    for (NSData *cd in central) [out appendData:cd];
    uint32_t cdSize = (uint32_t)out.length - cdOffset;

    // EOCD
    put32(out, 0x06054b50);
    put16(out, 0); put16(out, 0);
    put16(out, (uint16_t)central.count);
    put16(out, (uint16_t)central.count);
    put32(out, cdSize);
    put32(out, cdOffset);
    put16(out, 0); // comment len

    BOOL ok = [out writeToFile:dest atomically:YES];
    if (!ok) { setError(errorOut, @"Failed to write zip"); return NO; }
    return YES;
}

@end