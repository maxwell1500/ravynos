/*
 * CFURLEnumerator.c - an implementation of the CFURLEnumerator* APIs
 *
 * Copyright (C) 2026 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "CFURLEnumerator.h"
#include "CFInternal.h"
#include <dirent.h>

#define COND_RETAIN(o) (o ? CFRetain(o) : o)

struct __CFURLEnumerator {
    CFRuntimeBase _cfBase;
    CFAllocatorRef _alloc;
    CFURLRef _rootURL;
    CFArrayRef _propertyKeys;
    CFURLEnumeratorOptions _options;
    Boolean _mountedVolume;
    Boolean _skipDir;
    CFIndex _level;
    DIR* _dirp;
    struct dirent _entry;
    CFStringRef _path;
    char _dirpath[PATH_MAX];
    Boolean _pendingDescend;
    struct __CFURLEnumerator* _child;
};

static CFTypeID __kCFURLEnumeratorTypeID = _kCFRuntimeNotATypeID;

extern CFTypeID
CFURLEnumeratorGetTypeID()
{
    return __kCFURLEnumeratorTypeID;
}

extern CFURLEnumeratorRef
CFURLEnumeratorCreateForDirectoryURL(CFAllocatorRef alloc,
                                     CFURLRef directoryURL,
                                     CFURLEnumeratorOptions option,
                                     CFArrayRef propertyKeys)
{
    struct __CFURLEnumerator* ref
        = CFAllocatorAllocate(alloc,
                              sizeof(struct __CFURLEnumerator),
                              0);
    if (!ref)
        return NULL;

    CFStringRef path = CFURLCopyFileSystemPath(directoryURL,
                                               kCFURLPOSIXPathStyle);

    ref->_alloc = COND_RETAIN(alloc);
    ref->_options = option;
    ref->_propertyKeys = COND_RETAIN(propertyKeys);
    ref->_rootURL = COND_RETAIN(directoryURL);
    ref->_mountedVolume = false;
    ref->_skipDir = false;
    ref->_level = 1;

    ref->_dirp = NULL;
    ref->_dirpath[0] = 0;
    ref->_pendingDescend = false;
    ref->_child = NULL;
    if (path) {
        char pathbuf[PATH_MAX];
        CFStringGetCString(path, pathbuf, PATH_MAX - 1, kCFStringEncodingUTF8);
        ref->_path = path;
        snprintf(ref->_dirpath, sizeof(ref->_dirpath), "%s", pathbuf);
        ref->_dirp = opendir(pathbuf);
    }
    
    return (CFURLEnumeratorRef)ref;
}

extern CFURLEnumeratorRef
CFURLEnumeratorCreateForMountedVolumes(CFAllocatorRef alloc,
                                       CFURLEnumeratorOptions option,
                                       CFArrayRef propertyKeys)
{
    /* I'm not sure how this really works, but iterating /Volumes
     * seems reasonable for now.
     */
    CFURLRef dirURL;
    struct __CFURLEnumerator* ref;

    const char* path = "/Volumes";
    const int pathlen = strlen(path);
    
    dirURL = CFURLCreateFromFileSystemRepresentation(alloc,
                                                     path,
                                                     pathlen,
                                                     true /* isDir */);
    if (!dirURL)
        return NULL;

    ref = CFURLEnumeratorCreateForDirectoryURL(alloc,
                                               dirURL,
                                               option,
                                               propertyKeys);
    ref->_mountedVolume = true;
    
    return (CFURLEnumeratorRef)ref;
}

extern CFIndex
CFURLEnumeratorGetDescendentLevel(CFURLEnumeratorRef enumerator)
{
    return enumerator->_level;
}

extern void
CFURLEnumeratorSkipDescendents(CFURLEnumeratorRef enumerator)
{
    if ((enumerator->_entry.d_type != DT_DIR) ||
        !(enumerator->_options & kCFURLEnumeratorDescendRecursively))
        return;
    struct __CFURLEnumerator* ref = (struct __CFURLEnumerator*)enumerator;
    ref->_skipDir = true;
}

extern CFURLEnumeratorResult
CFURLEnumeratorGetNextURL(CFURLEnumeratorRef enumerator,
                          CFURLRef* url,
                          CFErrorRef* error)
{
    struct __CFURLEnumerator* ref = (struct __CFURLEnumerator*)enumerator;
    Boolean hadChild = false;

    if (url) *url = NULL;
    if (error) *error = NULL;

    for (;;) {
        /* Finish the subdirectory started for the directory returned by the
         * previous call.  Without this cursor the parent re-descended into the
         * same directory on every call and returned its first entry forever:
         * Firefox's font thread spun in this function and never finished
         * enumerating /System/Library/Fonts. */
        if (ref->_child) {
            CFURLEnumeratorResult r =
                CFURLEnumeratorGetNextURL(ref->_child, url, error);
            if (r != kCFURLEnumeratorEnd)
                return r;
            CFRelease(ref->_child);
            ref->_child = NULL;
            hadChild = true;
            continue;
        }

        /* A directory that could not be opened (missing, or not readable) has
         * no URLs.  Returning Error here made every subsequent call return
         * Error again, and a caller that loops until End (Firefox enumerating
         * a font directory under a fresh HOME) never terminated. */
        if (enumerator->_dirp == NULL)
            return kCFURLEnumeratorEnd;

        /* Descend into the directory that the previous call returned. */
        if (ref->_pendingDescend) {
            ref->_pendingDescend = false;
            if (!ref->_skipDir &&
                (enumerator->_options & kCFURLEnumeratorDescendRecursively)) {
                char pathbuf[PATH_MAX];
                CFURLRef subdirURL;
                CFURLEnumeratorRef subdir;

                snprintf(pathbuf, sizeof(pathbuf), "%s/%s",
                         ref->_dirpath, ref->_entry.d_name);
                subdirURL = CFURLCreateFromFileSystemRepresentation(
                    enumerator->_alloc, pathbuf, strlen(pathbuf), true);
                subdir = subdirURL
                    ? CFURLEnumeratorCreateForDirectoryURL(enumerator->_alloc,
                        subdirURL, enumerator->_options, enumerator->_propertyKeys)
                    : NULL;
                if (subdirURL)
                    CFRelease(subdirURL);
                ref->_skipDir = false;
                if (subdir) {
                    ((struct __CFURLEnumerator*)subdir)->_level =
                        ref->_level + 1;
                    ref->_child = (struct __CFURLEnumerator*)subdir;
                    continue;
                }
            }
            ref->_skipDir = false;
        }

        struct dirent *d = readdir(enumerator->_dirp);
        if (!d)
            return kCFURLEnumeratorEnd;
        memcpy(&enumerator->_entry, d, sizeof(struct dirent));

        /* "." and ".." are directories too; descending into them recursed
         * forever (".", then "..", then ...). */
        if (strcmp(d->d_name, ".") == 0 || strcmp(d->d_name, "..") == 0)
            continue;

        if (url) {
            char pathbuf[PATH_MAX];
            snprintf(pathbuf, sizeof(pathbuf), "%s/%s",
                     ref->_dirpath, d->d_name);
            *url = CFURLCreateFromFileSystemRepresentation(enumerator->_alloc,
                                                           pathbuf,
                                                           strlen(pathbuf),
                                                           d->d_type == DT_DIR);
        }

        if (d->d_type == DT_DIR)
            ref->_pendingDescend = true;
        return kCFURLEnumeratorSuccess;
    }
}

/* deprecated from macOS 10.7 */
extern Boolean
CFURLEnumeratorGetSourceDidChange(CFURLEnumeratorRef enumerator)
{
    (void)enumerator;
    return false;
}
