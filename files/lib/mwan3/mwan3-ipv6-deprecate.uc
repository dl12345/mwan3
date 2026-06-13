#!/usr/bin/env ucode
'use strict';

// Prefix-deprecation failover actuator (ipv6_failover_type=deprecate). Given a failed
// or recovered IPv6 WAN, (un)deprecate the downstream LAN router-address(es) in that
// WAN's delegated prefix so odhcpd advertises the prefix deprecated (RFC 4862) or
// preferred again, and RFC 6724 rule 3 moves clients off the dead prefix and back.
//
// ARGV[0] = the WAN's ubus interface name (true_iface, e.g. "wan6").
// ARGV[1] = "deprecate" (preferred_lft 0) or "restore" (preferred_lft = valid_lft).
//
// Discovery is netifd delegation state (ubus): the WAN's ipv6-prefix[].assigned maps
// each downstream LAN to its sub-prefix, and that LAN's ipv6-prefix-assignment
// local-address is the router address to act on (covers a /56 split across several
// LANs). The lifetime change is a netlink read-modify-write (RTM_GETADDR then
// RTM_NEWADDR), so valid_lft, scope and the address flags are preserved and the
// kernel toggles the deprecated flag from the preferred lifetime itself; no ip
// command is forked. Restore sets preferred to the address's own valid_lft, so it
// never advertises a preferred lifetime beyond the prefix's validity (correct for a
// finite DHCPv6-PD lease) and netifd writes its exact figure at the next renewal.

import * as ubus from "ubus";
import * as rtnl from "rtnl";
import { log_open, log_msg } from 'mwan3.common';

const RTM_GETADDR = rtnl.const.RTM_GETADDR;
const RTM_NEWADDR = rtnl.const.RTM_NEWADDR;
const NLM_F_DUMP = rtnl.const.NLM_F_DUMP;
const NLM_F_REPLACE = rtnl.const.NLM_F_REPLACE;
const AF_INET6 = rtnl.const.AF_INET6;

let wan = ARGV[0];
let action = ARGV[1];
if (wan == null || wan == "" || (action != "deprecate" && action != "restore"))
	exit(1);

log_open("mwan3-ipv6-deprecate");

let conn = ubus.connect();
if (!conn)
	exit(1);
let dump = conn.call("network.interface", "dump");
conn.disconnect();
if (!dump || !dump.interface)
	exit(1);

let by_name = {};
for (let intf in dump.interface)
	by_name[intf.interface] = intf;

let wan_intf = by_name[wan];
if (!wan_intf)
	exit(0);

// Collect the downstream LAN router-addresses sitting in this WAN's delegated
// prefix(es), via the WAN's assigned map and each LAN's prefix-assignment.

let targets = [];
for (let prefix in (wan_intf["ipv6-prefix"] ?? [])) {
	let assigned = prefix.assigned ?? {};
	for (let lan_name in assigned) {
		let sub = assigned[lan_name];
		if (sub == null || sub.address == null)
			continue;
		let lan = by_name[lan_name];
		if (!lan || !lan.l3_device)
			continue;
		for (let pa in (lan["ipv6-prefix-assignment"] ?? [])) {
			if (pa.address != sub.address)
				continue;
			let la = pa["local-address"];
			if (la != null && la.address != null)
				push(targets, { dev: lan.l3_device, addr: la.address });
		}
	}
}

if (length(targets) == 0)
	exit(0);

// Apply the lifetime change by netlink read-modify-write, preserving valid_lft.

let addrs = rtnl.request(RTM_GETADDR, NLM_F_DUMP, { family: AF_INET6 }) ?? [];

for (let t in targets) {
	for (let a in addrs) {
		if (a.dev != t.dev || a.cacheinfo == null)
			continue;
		if (split(a.address ?? "", "/")[0] != t.addr)
			continue;
		a.cacheinfo.preferred = (action == "deprecate") ? 0 : a.cacheinfo.valid;
		rtnl.request(RTM_NEWADDR, NLM_F_REPLACE, a);
		let err = rtnl.error();
		if (err)
			log_msg("err", sprintf("%s %s on %s: %s",
			                       action, t.addr, t.dev, err));
		break;
	}
}

exit(0);
