/*
 * SystemConfiguration component keys.
 *
 * XUL binds kSCComp* at load ("Symbol not found: _kSCCompAnyRegex",
 * "Expected in: SystemConfiguration").  This build's CoreFoundation headers
 * expand CFSTR() to a run-time call, so the constants cannot be static
 * initialisers; they are created once by the constructor below, so no caller
 * can ever see a NULL key.
 */
#include <CoreFoundation/CoreFoundation.h>

CFStringRef kSCCompAnyRegex = NULL;
CFStringRef kSCCompNetwork = NULL;
CFStringRef kSCCompInterface = NULL;
CFStringRef kSCCompGlobal = NULL;
CFStringRef kSCCompHostNames = NULL;
CFStringRef kSCCompService = NULL;
CFStringRef kSCCompSystem = NULL;
CFStringRef kSCCompUsers = NULL;
CFStringRef kSCEntNetDNS = NULL;
CFStringRef kSCEntNetIPv4 = NULL;
CFStringRef kSCEntNetIPv6 = NULL;
CFStringRef kSCEntNetProxies = NULL;
CFStringRef kSCEntNetLink = NULL;
CFStringRef kSCEntNetInterface = NULL;
CFStringRef kSCEntNetAirPort = NULL;
CFStringRef kSCEntNetEthernet = NULL;
CFStringRef kSCEntNetModem = NULL;
CFStringRef kSCEntNet6to4 = NULL;
CFStringRef kSCEntNetIPSec = NULL;
CFStringRef kSCEntNetPPP = NULL;
CFStringRef kSCEntNetVPN = NULL;
CFStringRef kSCEntNetSMB = NULL;


__attribute__((constructor)) static void
SCComponentKeysInit(void)
{
	struct { CFStringRef *slot; const char *value; } keys[] = {
		{ &kSCCompAnyRegex, ".*" },
		{ &kSCCompNetwork, "Network" },
		{ &kSCCompInterface, "Interface" },
		{ &kSCCompGlobal, "Global" },
		{ &kSCCompHostNames, "HostNames" },
		{ &kSCCompService, "Service" },
		{ &kSCCompSystem, "System" },
		{ &kSCCompUsers, "Users" },
		{ &kSCEntNetDNS, "DNS" },
		{ &kSCEntNetIPv4, "IPv4" },
		{ &kSCEntNetIPv6, "IPv6" },
		{ &kSCEntNetProxies, "Proxies" },
		{ &kSCEntNetLink, "Link" },
		{ &kSCEntNetInterface, "Interface" },
		{ &kSCEntNetAirPort, "AirPort" },
		{ &kSCEntNetEthernet, "Ethernet" },
		{ &kSCEntNetModem, "Modem" },
		{ &kSCEntNet6to4, "6to4" },
		{ &kSCEntNetIPSec, "IPSec" },
		{ &kSCEntNetPPP, "PPP" },
		{ &kSCEntNetVPN, "VPN" },
		{ &kSCEntNetSMB, "SMB" },
	};
	for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
		if (*keys[i].slot == NULL) {
			*keys[i].slot = CFStringCreateWithCString(kCFAllocatorDefault,
			    keys[i].value, kCFStringEncodingUTF8);
		}
	}
}
