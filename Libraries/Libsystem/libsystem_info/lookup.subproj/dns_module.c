/*
 * dns_module.c -- unicast DNS as a libinfo si module.
 *
 * macOS resolves a name through mDNSResponder, which is the "mdns" module.
 * This system ships no mDNSResponder daemon, so the search order
 * (cache, file, mdns) has no module that can reach a nameserver: /etc/hosts
 * answers and every other name fails.  getaddrinfo() therefore cannot
 * resolve a public site, which is exactly what a browser needs first.
 *
 * This module asks the servers in /etc/resolv.conf directly.  The BIND
 * resolver already ships as libresolv.9.dylib; it is loaded with dlopen so
 * libinfo does not take a link-time dependency on it (libinfo defines its
 * own res_query, which delegates to mdns, so a plain call would recurse).
 *
 * Only the two pieces the search module needs are implemented: name to
 * hostent, and addrinfo via the generic _gai_simple() helper.  Reverse
 * lookups stay with "mdns"/"file".
 */

#include "libinfo_common.h"

#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include <arpa/nameser_compat.h>
#include <nameser.h>

#include "ils.h"
#include "si_module.h"

/* BIND entry points, looked up in libresolv.9.dylib.  The res_9_ prefix is
 * the versioned ABI libresolv exports; the unversioned res_query belongs to
 * libsystem_info (mdns), so it must not be used here. */
typedef int (*res_init_fn)(void);
typedef int (*res_query_fn)(const char *, int, int, u_char *, int);

static res_query_fn s_res_query = NULL;
static pthread_once_t s_res_once = PTHREAD_ONCE_INIT;

static void
dns_load_resolver(void)
{
	void *h = dlopen("/usr/lib/libresolv.9.dylib", RTLD_NOW | RTLD_LOCAL);
	if (h == NULL) h = dlopen("/usr/lib/system/libresolv.9.dylib", RTLD_NOW | RTLD_LOCAL);
	if (h == NULL) h = dlopen("libresolv.9.dylib", RTLD_NOW | RTLD_LOCAL);
	if (h == NULL) return;

	res_init_fn init = (res_init_fn)dlsym(h, "res_9_init");
	res_query_fn query = (res_query_fn)dlsym(h, "res_9_query");
	if (query == NULL) return;
	if (init != NULL) init();
	s_res_query = query;
}

/*
 * Skip a possibly-compressed domain name.  Returns the offset of the byte
 * after the name, or -1 if the name runs past the end of the message.
 */
static int
dns_skip_name(const u_char *msg, int off, int len)
{
	int guard = 0;
	while (off >= 0 && off < len) {
		u_char c = msg[off];
		if (c == 0) return off + 1;
		if ((c & 0xc0) == 0xc0) {
			/* compression pointer: two bytes and the name ends here */
			if (off + 1 >= len) return -1;
			return off + 2;
		}
		off += c + 1;
		if (++guard > 128) return -1;
	}
	return -1;
}

static si_item_t *
dns_make_host_item(si_mod_t *si, const char *name, int af,
                   u_char *addrs, int count)
{
	int addrlen = (af == AF_INET) ? 4 : 16;
	char *alias_list[1] = { NULL };
	char *addr_list[17];   /* MAXNS-style bound: count is clamped below */
	int i;

	if (count <= 0) return NULL;
	if (count > (int)(sizeof(addr_list) / sizeof(addr_list[0])) - 1)
		count = (int)(sizeof(addr_list) / sizeof(addr_list[0])) - 1;

	for (i = 0; i < count; i++)
		addr_list[i] = (char *)&addrs[i * addrlen];
	addr_list[count] = NULL;

	if (af == AF_INET) {
		return (si_item_t *)LI_ils_create("L4488s*44a",
		    (unsigned long)si, CATEGORY_HOST_IPV4, 1, 0LL, 0LL,
		    (char *)name, alias_list, AF_INET, addrlen, addr_list);
	}
	return (si_item_t *)LI_ils_create("L4488s*44c",
	    (unsigned long)si, CATEGORY_HOST_IPV6, 1, 0LL, 0LL,
	    (char *)name, alias_list, AF_INET6, addrlen, addr_list);
}

static si_item_t *
dns_host_byname(si_mod_t *si, const char *name, int af,
                const char *interface, uint32_t *err)
{
	u_char answer[2048];
	u_char addrs[16 * 16];
	int addrcount = 0;
	int addrlen, want, len, off, i;
	HEADER *hp;
	si_item_t *out;

	(void)interface;

	if (err != NULL) *err = SI_STATUS_H_ERRNO_HOST_NOT_FOUND;
	if (name == NULL) return NULL;
	if (af == AF_INET) { want = ns_t_a; addrlen = 4; }
	else if (af == AF_INET6) { want = ns_t_aaaa; addrlen = 16; }
	else return NULL;

	pthread_once(&s_res_once, dns_load_resolver);
	if (s_res_query == NULL) {
		if (err != NULL) *err = SI_STATUS_H_ERRNO_NO_RECOVERY;
		return NULL;
	}

	len = s_res_query((const char *)name, ns_c_in, want, answer, (int)sizeof(answer));
	if (len < (int)sizeof(HEADER))
		return NULL;

	hp = (HEADER *)answer;
	if (ntohs(hp->ancount) == 0) return NULL;

	/* Skip the question section, then walk the answer RRs. */
	off = (int)sizeof(HEADER);
	for (i = 0; i < ntohs(hp->qdcount); i++) {
		off = dns_skip_name(answer, off, len);
		if (off < 0) return NULL;
		off += 4; /* qtype + qclass */
		if (off > len) return NULL;
	}

	for (i = 0; i < ntohs(hp->ancount) && addrcount < 16; i++) {
		int type, rdlength;

		off = dns_skip_name(answer, off, len);
		if (off < 0 || off + 10 > len) break;
		type = (answer[off] << 8) | answer[off + 1];
		rdlength = (answer[off + 8] << 8) | answer[off + 9];
		off += 10;
		if (off + rdlength > len) break;
		if (type == want && rdlength == addrlen) {
			memcpy(&addrs[addrcount * addrlen], &answer[off], addrlen);
			addrcount++;
		}
		off += rdlength;
	}

	if (addrcount == 0) return NULL;

	out = dns_make_host_item(si, (const char *)name, (af == AF_INET) ? AF_INET : AF_INET6,
	                         addrs, addrcount);
	if (out != NULL && err != NULL) *err = SI_STATUS_NO_ERROR;
	return out;
}

si_mod_t *
si_module_static_dns(void)
{
	static const struct si_mod_vtable_s dns_vtable =
	{
		.sim_close = NULL,
		.sim_is_valid = NULL,
		.sim_host_byname = &dns_host_byname,
		.sim_addrinfo = &_gai_simple,
	};

	static si_mod_t si =
	{
		.vers = 1,
		.refcount = 1,
		.flags = SI_MOD_FLAG_STATIC,
		.private = NULL,
		.vtable = &dns_vtable,
	};

	static pthread_once_t once = PTHREAD_ONCE_INIT;
	/* name must be a stable string: si_module_name() returns it. */
	static const char dns_name[] = "dns";

	(void)once;
	si.name = (char *)dns_name;
	return &si;
}
