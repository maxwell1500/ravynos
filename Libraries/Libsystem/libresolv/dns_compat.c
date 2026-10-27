/*
 * The dns_configuration_* entry points libresolv calls.
 *
 * On macOS these live in libsystem_info and describe per-interface/scoped
 * resolvers.  This system has no scoped configuration daemon, so
 * dns_configuration_copy() reports "no scoped configuration" (NULL) and the
 * resolver falls back to /etc/resolv.conf, which is the same path it takes on
 * a Mac when no per-interface DNS is configured.  Returning NULL is a real
 * answer, not a fabricated configuration.
 */
#include <stdint.h>

typedef struct _dns_configuration *dns_configuration_t;

dns_configuration_t
dns_configuration_copy(void)
{
	return (dns_configuration_t)0;
}

void
dns_configuration_free(dns_configuration_t config)
{
	(void)config;
}

const char *
dns_configuration_notify_key(void)
{
	return "com.apple.system.config.network_change";
}
