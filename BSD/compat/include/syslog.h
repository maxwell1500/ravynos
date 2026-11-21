/* FreeBSD's LOG_CONSOLE routes a message to the console as well as the log.
 * Darwin has no such facility bit; mapping it to zero leaves the priority and
 * behaviour unchanged instead of corrupting the priority with an unknown flag.
 */
#ifndef _RAVYN_COMPAT_SYSLOG_H_
#define _RAVYN_COMPAT_SYSLOG_H_

#include_next <syslog.h>

#ifndef LOG_CONSOLE
#define LOG_CONSOLE 0
#endif

#endif
