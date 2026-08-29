/*
 * Copyright (c) 2021 Apple Inc. All rights reserved.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. The rights granted to you under the License
 * may not be used to create, or enable the creation or redistribution of,
 * unlawful or unlicensed copies of an Apple operating system, or to
 * circumvent, violate, or enable the circumvention or violation of, any
 * terms of an Apple operating system software license agreement.
 *
 * Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_END@
 */

#ifndef _IOKIT_IOEXTENSIBLEPANICLOG_H
#define _IOKIT_IOEXTENSIBLEPANICLOG_H

#include <libkern/c++/OSObject.h>
#include <libkern/c++/OSPtr.h>
#include <IOKit/IOLib.h>
#include <DriverKit/IOExtensiblePaniclog.h>
#include <IOKit/IOBufferMemoryDescriptor.h>

struct ext_paniclog_handle;
typedef struct ext_paniclog_handle ext_paniclog_handle_t;

class IOExtensiblePaniclog : public OSObject
{
	OSDeclareDefaultStructorsWithDispatch(IOExtensiblePaniclog);

private:
	ext_paniclog_handle_t *extPaniclogHandle;

	IOBufferMemoryDescriptor *iomd;

protected:
	bool init() APPLE_KEXT_OVERRIDE;

	void free(void) APPLE_KEXT_OVERRIDE;

public:

	/*!
	 * @brief      Set a handle active in the extensible paniclog
	 * @return     kIOReturnSuccess on success, or other IOReturn error
	 */
	virtual kern_return_t
	SetActive();

	/*!
	 * @brief      Set a handle inactive in the extensible paniclog
	 * @return     kIOReturnSuccess on success, or other IOReturn error
	 */
	virtual kern_return_t
	SetInactive();

	/*!
	 * @brief      Insert data into the extensible paniclog
	 * @param      data The data to insert
	 * @return     kIOReturnSuccess on success, or other IOReturn error
	 */
	virtual kern_return_t
	InsertData(OSData *data);

	/*!
	 * @brief      Append data into the extensible paniclog
	 * @param      data The data to append
	 * @return     kIOReturnSuccess on success, or other IOReturn error
	 */
	virtual kern_return_t
	AppendData(OSData *data);

	/*!
	 * @brief      Copy the memory descriptor associated with the paniclog data buffer
	 * @param      mem  The returned memory descriptor
	 * @return     kIOReturnSuccess on success, or other IOReturn error
	 */
	virtual kern_return_t
	CopyMemoryDescriptor(IOBufferMemoryDescriptor **mem);

	/*!
	 * @brief      Set the used length of the buffer associated with the paniclog handle
	 * @param      used_len The used length of the buffer
	 * @return     kIOReturnSuccess on success, or other IOReturn error
	 */
	virtual kern_return_t
	SetUsedLen(uint32_t used_len);
};

#endif /* _IOKIT_IOEXTENSIBLEPANICLOG_H */
