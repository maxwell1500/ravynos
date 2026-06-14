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
#include <dirent.h>

#define COND_RETAIN(o) (o ? CFRetain(o) : o)

struct __CFURLEnumerator {
    CFRuntimeBase _cfBase;
    CFAllocatorRef _alloc;
    CFURLRef _rootURL;
    CFArrayRef _propertyKeys;
    CFURLEnumeratorOptions options;
    CFBoolean _mountedVolume;
    CFIndex _level;
    DIR* _dirp;
    struct dirent _entry;
    CFStringRef _path;
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
    CFURLEnumeratorRef ref = CFAllocatorAllocate(alloc,
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
    if (path) {
        char pathbuf[PATH_MAX];
        CFStringGetCString(path, pathbuf, PATH_MAX - 1, kCFStringUTF8Encoding);
        ref->_path = path;
        ref->_dirp = opendir(pathbuf);
    }
    
    return ref;
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
    CFURLEnumeratorRef ref;

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
    
    return ref;
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
    enumerator->_skipDir = true;
}

extern CFURLEnumeratorResult
CFURLEnumeratorGetNextURL(CFURLEnumeratorRef enumerator,
                          CFURLRef* url,
                          CFErrorRef* error)
{
    CFMutableStringRef path;

    /* We descend if we last returned a directory and have not been 
     * told to skip it since the last call to this function
     */
    if (enumerator->_entry.d_name[0] != 0
        && enumerator->_entry.d_type == DT_DIR
        && enumerator->_skipDir) {
        enumerator->_skipDir = false;

        path = CFStringCreateMutableCopy(enumerator->_path);
        CFStringAppendCString(path, "/", kCFStringEncodingUTF8);
        CFStringAppendCString(path,
                              enumerator->_entry.d_name,
                              kCFStringEncodingUTF8);
        CFURLRef subdirURL
            = CFURLCreateWithFileSystemRepresentation(enumerator->_alloc,
                                                      path,
                                                      strlen(path),
                                                      true /* isDir */);
        if (url)
            *url = subdirURL;

        CFURLEnumeratorRef subdir
            = CFURLEnumeratorCreateForDirectoryURL(subdirURL);
        subdir->_level++;
        return CFURLEnumeratorGetNextURL(subdir, url, error);
    }
    
    struct dirent *d = readdir(enumerator->_dirp);
    
    if (!d)
        return CFURLEnumeratorError;

    memcpy(&enumerator->_entry, d, sizeof(struct dirent));

    path = CFStringCreateMutableCopy(enumerator->_path);
    CFStringAppendCString(path, "/", kCFStringEncodingUTF8);
    CFStringAppendCString(path,
                          enumerator->_entry.d_name,
                          kCFStringEncodingUTF8);    
    
    if (url) {
        *url = CFURLCreateFromFileSystemRepresentation(path,
                                                       kCFURLPOSIXPathStyle);
    }
}

/* deprecated from macOS 10.7 */
extern Boolean
CFURLEnumeratorGetSourceDidChange(CFURLEnumeratorRef enumerator)
{
    (void)enumerator;
    return false;
}
