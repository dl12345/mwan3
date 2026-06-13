#!/usr/bin/env ucode
'use strict';

// Discover the delegated IPv6 prefix(es) of an mwan3 WAN interface.
//
// ARGV[0] = ubus network interface name (the true_iface resolved by
//           mwan3_get_true_iface, e.g. "wan6" or "wan_6").
//
// Prints one "address/mask" line per delegated prefix, read from the
// interface's ipv6-prefix array in network.interface.<iface> status. This is
// the prefix that source-derived marking matches: a packet whose source falls
// in this prefix is stamped with the interface's mark and routed out the
// interface's own table.
//
// The parent delegated prefix is emitted, not the per-LAN sub-assignments, so
// a single match covers a prefix split across several downstream LAN segments.
// A WAN with no delegation (empty ipv6-prefix) prints nothing and exits 0.

import * as ubus from "ubus";

let iface = ARGV[0];
if (iface == null || iface == "")
	exit(1);

let conn = ubus.connect();
if (!conn)
	exit(1);

let status = conn.call("network.interface." + iface, "status");
conn.disconnect();
if (!status)
	exit(1);

for (let prefix in (status["ipv6-prefix"] ?? []))
	if (prefix.address != null && prefix.mask != null)
		printf("%s/%d\n", prefix.address, prefix.mask);

exit(0);
