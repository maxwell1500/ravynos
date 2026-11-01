/*
 * route -- read and modify the BSD routing table through the PF_ROUTE
 * socket.  The kernel owns the table; this is a thin rtmsg client.
 */
#include <arpa/inet.h>
#include <err.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

static int
open_route(void)
{
	int s = socket(PF_ROUTE, SOCK_RAW, 0);
	if (s < 0)
		err(1, "socket(PF_ROUTE)");
	return s;
}

static void
fill_sockaddr(struct sockaddr_in *sin, const char *addr)
{
	memset(sin, 0, sizeof(*sin));
	sin->sin_len = sizeof(*sin);
	sin->sin_family = AF_INET;
	if (addr != NULL && inet_pton(AF_INET, addr, &sin->sin_addr) != 1)
		errx(1, "bad address: %s", addr);
}

static int
route_get(const char *dest)
{
	struct {
		struct rt_msghdr hdr;
		struct sockaddr_in dst;
	} msg;
	struct sockaddr_in *sin;
	char buf[1024];
	ssize_t n;
	int s = open_route();

	memset(&msg, 0, sizeof(msg));
	msg.hdr.rtm_msglen = sizeof(msg);
	msg.hdr.rtm_version = RTM_VERSION;
	msg.hdr.rtm_type = RTM_GET;
	msg.hdr.rtm_addrs = RTA_DST;
	msg.hdr.rtm_seq = 1;
	fill_sockaddr(&msg.dst, dest);

	if (write(s, &msg, sizeof(msg)) != (ssize_t)sizeof(msg))
		err(1, "RTM_GET write");
	n = read(s, buf, sizeof(buf));
	close(s);
	if (n < (ssize_t)sizeof(struct rt_msghdr))
		errx(1, "no route to %s", dest);

	struct rt_msghdr *rtm = (struct rt_msghdr *)buf;
	printf("route to %s: flags=%x\n", dest, rtm->rtm_flags);
	sin = (struct sockaddr_in *)(rtm + 1);
	for (int i = 0; i < RTAX_MAX && (char *)sin < buf + n; i++) {
		if ((rtm->rtm_addrs & (1 << i)) == 0)
			continue;
		if (i == RTAX_GATEWAY && sin->sin_family == AF_INET) {
			char a[INET_ADDRSTRLEN];
			inet_ntop(AF_INET, &sin->sin_addr, a, sizeof(a));
			printf("  gateway: %s\n", a);
		}
		sin = (struct sockaddr_in *)((char *)sin +
		    ((sin->sin_len + 3) & ~3));
	}
	return 0;
}

static int
route_change(int type, const char *dest, const char *gateway)
{
	struct {
		struct rt_msghdr hdr;
		struct sockaddr_in dst;
		struct sockaddr_in gw;
		struct sockaddr_in mask;
	} msg;
	int s = open_route();

	memset(&msg, 0, sizeof(msg));
	msg.hdr.rtm_msglen = sizeof(msg);
	msg.hdr.rtm_version = RTM_VERSION;
	msg.hdr.rtm_type = type;
	msg.hdr.rtm_flags = RTF_UP | RTF_GATEWAY;
	msg.hdr.rtm_addrs = RTA_DST | RTA_GATEWAY | RTA_NETMASK;
	msg.hdr.rtm_seq = 2;
	fill_sockaddr(&msg.dst, dest);
	fill_sockaddr(&msg.gw, gateway);
	fill_sockaddr(&msg.mask, "255.255.255.255");

	if (write(s, &msg, sizeof(msg)) != (ssize_t)sizeof(msg))
		err(1, "route %s", type == RTM_ADD ? "add" : "delete");
	close(s);
	return 0;
}

int
main(int argc, char **argv)
{
	int i = 1;
	if (i < argc && strcmp(argv[i], "-n") == 0)
		i++;
	if (i >= argc) {
		fprintf(stderr, "usage: route [-n] get <dest> | add <dest> <gateway> | delete <dest>\n");
		return 2;
	}
	if (strcmp(argv[i], "get") == 0 && i + 1 < argc)
		return route_get(argv[i + 1]);
	if (strcmp(argv[i], "add") == 0 && i + 2 < argc)
		return route_change(RTM_ADD, argv[i + 1], argv[i + 2]);
	if (strcmp(argv[i], "delete") == 0 && i + 1 < argc)
		return route_change(RTM_DELETE, argv[i + 1], NULL);
	fprintf(stderr, "route: bad arguments\n");
	return 2;
}
