#!/usr/bin/env ucode
'use strict';

// Discover the delegated IPv6 prefix(es) of an mwan3 WAN interface.
//
// ARGV[0] = ubus network interface name (the true_iface resolved by
//           mwan3_get_true_iface, e.g. "wan6" or "wan6_6").
// ARGV[1] = the mwan3/config interface name (e.g. "wan6"); optional, used only
//           for the static fallback below.
//
// Prints one "address/mask" line per delegated prefix, read from the interface's
// ipv6-prefix array in network.interface.<iface> status. This is the prefix that
// source-derived marking matches and that translate failover carries.
//
// The parent delegated prefix is emitted, not the per-LAN sub-assignments, so a
// single match covers a prefix split across several downstream LAN segments.
//
// Static fallback: when ubus yields no ipv6-prefix - whether the status is empty
// of prefixes (the _6 alias not yet populated) or absent entirely (the WAN is
// administratively down, status null) - and ARGV[1] names a config interface
// carrying a static option ip6prefix, that configured prefix is emitted instead.
// This makes discovery deterministic for statically-delegated WANs, so the failover
// prefix cache is reliably seeded while the WAN is up and a failover can always
// carry the orphaned prefix. It is a no-op for DHCPv6-PD WANs, which carry no static
// ip6prefix and rely on ubus (which holds the PD prefix once the link is up). A WAN
// with no delegation at all prints nothing and exits 0.

import * as ubus from "ubus";
import * as uci from "uci";

let iface = ARGV[0];
if (iface == null || iface == "")
	exit(1);

let conn = ubus.connect();
if (!conn)
	exit(1);

let status = conn.call("network.interface." + iface, "status");
conn.disconnect();

let printed = false;
for (let prefix in ((status ?? {})["ipv6-prefix"] ?? []))
	if (prefix.address != null && prefix.mask != null) {
		printf("%s/%d\n", prefix.address, prefix.mask);
		printed = true;
	}

// Fall back to the statically configured ip6prefix only when ubus yielded nothing.
if (!printed && ARGV[1] != null && ARGV[1] != "") {
	let p = uci.cursor().get("network", ARGV[1], "ip6prefix");
	if (type(p) == "array") {
		for (let one in p)
			if (one != null && one != "")
				printf("%s\n", one);
	} else if (p != null && p != "") {
		printf("%s\n", p);
	}
}

exit(0);
