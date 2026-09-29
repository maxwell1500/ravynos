/*
 * AvailabilityInternalPrivate.h - private (SPI) availability annotations.
 *
 * ravynOS ships Kernel/xnu headers such as sys/resource_private.h and
 * mach/exclaves.h that unconditionally include this header when building
 * userspace, but the header itself was missing from the tree, which broke
 * every Libsystem component that pulls those headers in.
 *
 * The only annotation they actually need is __SPI_AVAILABLE. SPI symbols
 * carry the same availability constraints as the public interfaces they
 * shadow, so it maps straight onto __API_AVAILABLE.
 */
#ifndef _AVAILABILITY_INTERNAL_PRIVATE_H_
#define _AVAILABILITY_INTERNAL_PRIVATE_H_

#include <Availability.h>

/*
 * Usage: __SPI_AVAILABLE(macos(12.4), ios(15.4), watchos(8.5), tvos(15.4))
 *
 * Some SDK revisions already define this in Availability.h; only supply it
 * when it is genuinely absent so this header is safe to add to either.
 */
#ifndef __SPI_AVAILABLE
#define __SPI_AVAILABLE(...) __API_AVAILABLE(__VA_ARGS__)
#endif

#endif /* _AVAILABILITY_INTERNAL_PRIVATE_H_ */
