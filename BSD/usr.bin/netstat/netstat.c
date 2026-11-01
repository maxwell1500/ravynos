/*
 * netstat -- interface and routing-table summary.
 *
 * Reads the BSD routing sysctl tree (NET_RT_IFLIST / NET_RT_DUMP); there is
 * no /proc in ravynOS and the kernel already exports these messages.
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
#include <sys/sysctl.h>
#include <sys/types.h>

static void
print_sockaddr(const struct sockaddr *sa)
{
	char buf[INET6_ADDRSTRLEN];

	if (sa == NULL || sa->sa_len == 0)
		return;
	switch (sa->sa_family) {
	case AF_INET:
		inet_ntop(AF_INET, &((const struct sockaddr_in *)sa)->sin_addr,
		    buf, sizeof(buf));
		printf("%s", buf);
		break;
	case AF_INET6:
		inet_ntop(AF_INET6, &((const struct sockaddr_in6 *)sa)->sin6_addr,
		    buf, sizeof(buf));
		printf("%s", buf);
		break;
	default:
		break;
	}
}

static int
show_interfaces(void)
{
	int mib[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST, 0 };
	size_t len = 0;
	char *buf, *next;

	if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0)
		return -1;
	buf = malloc(len);
	if (buf == NULL)
		return -1;
	if (sysctl(mib, 6, buf, &len, NULL, 0) != 0) {
		free(buf);
		return -1;
	}

	printf("%-8s %-6s %-8s %s\n", "Name", "Mtu", "Network", "Address");
	for (next = buf; next < buf + len; ) {
		struct rt_msghdr *rtm = (struct rt_msghdr *)next;
		if (rtm->rtm_msglen == 0)
			break;
		if (rtm->rtm_type == RTM_IFINFO) {
			struct if_msghdr *ifm = (struct if_msghdr *)rtm;
			char name[IFNAMSIZ];
			if (if_indextoname(ifm->ifm_index, name) != NULL)
				printf("%-8s %-6d %-8s ", name,
				    ifm->ifm_data.ifi_mtu, "-");
		} else if (rtm->rtm_type == RTM_NEWADDR) {
			struct ifa_msghdr *ifam = (struct ifa_msghdr *)rtm;
			struct sockaddr *sa = (struct sockaddr *)(ifam + 1);
			int i;
			for (i = 0; i < RTAX_MAX; i++) {
				if (ifam->ifam_addrs & (1 << i)) {
					if (i == RTAX_IFA) {
						print_sockaddr(sa);
						printf("\n");
					}
					sa = (struct sockaddr *)((char *)sa +
					    ((sa->sa_len + sizeof(uint32_t) - 1) &
					    ~(sizeof(uint32_t) - 1)));
				}
			}
		}
		next += rtm->rtm_msglen;
	}
	free(buf);
	return 0;
}

static int
show_routes(void)
{
	int mib[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_DUMP, 0 };
	size_t len = 0;
	char *buf, *next;

	if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0)
		return -1;
	buf = malloc(len);
	if (buf == NULL)
		return -1;
	if (sysctl(mib, 6, buf, &len, NULL, 0) != 0) {
		free(buf);
		return -1;
	}

	printf("%-20s %-20s %s\n", "Destination", "Gateway", "Flags");
	for (next = buf; next < buf + len; ) {
		struct rt_msghdr *rtm = (struct rt_msghdr *)next;
		struct sockaddr *sa;
		int i;

		if (rtm->rtm_msglen == 0)
			break;
		if (rtm->rtm_type != RTM_GET)
			goto skip;
		sa = (struct sockaddr *)(rtm + 1);
		for (i = 0; i < RTAX_MAX; i++) {
			if (rtm->rtm_addrs & (1 << i)) {
				if (i == RTAX_DST) {
					print_sockaddr(sa);
					printf("%*s", 21, "");
				} else if (i == RTAX_GATEWAY) {
					print_sockaddr(sa);
					printf("%*s", 21, "");
				}
				sa = (struct sockaddr *)((char *)sa +
				    ((sa->sa_len + sizeof(uint32_t) - 1) &
				    ~(sizeof(uint32_t) - 1)));
			}
		}
		printf("%s%s\n", (rtm->rtm_flags & RTF_UP) ? "U" : "",
		    (rtm->rtm_flags & RTF_GATEWAY) ? "G" : "");
skip:
		next += rtm->rtm_msglen;
	}
	free(buf);
	return 0;
}

int
main(int argc, char **argv)
{
	if (argc > 1 && strcmp(argv[1], "-rn") == 0)
		return show_routes() == 0 ? 0 : 1;
	if (argc > 1 && strcmp(argv[1], "-i") == 0)
		return show_interfaces() == 0 ? 0 : 1;
	if (show_interfaces() != 0)
		err(1, "NET_RT_IFLIST");
	return 0;
}
