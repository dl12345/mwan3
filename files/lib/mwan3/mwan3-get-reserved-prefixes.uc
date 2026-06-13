#!/usr/bin/env ucode
'use strict';

// Emit every IPv6 prefix the router holds an address in, or has delegated downstream,
// across ALL network interfaces, for the 1:1 prefix-translation carve's reserved
// skip set. The carve maps each carried WAN's LAN segment onto a target carved from a
// translating WAN's pool, and both the carve and the allocator's disjointness gate avoid
// only the prefixes in this set. So any router-held /64 that is NOT in the set can have a
// target placed on it, and the inbound dnat prefix-map then reverse-translates and forwards
// traffic destined to that /64 before the local-input decision: traffic to the router's own
// address, to a second WAN addressed from the same provider delegation, or to a LAN, is
// hijacked. A
// per-interface or mwan3-only view is not enough, because a single provider delegation can
// feed several interfaces (multiple tunnels from one broker, the zero-configuration 'auto'
// case especially), so a sibling interface's address sits inside the pool a translating WAN
// carves from. Sweeping every interface and feeding the union into the skip set is what
// makes the carve safe regardless of how the delegation is spread across the router.
//
// ARGV[0] = the literal "selftest" runs the built-in cases; with no argument the helper
//           sweeps the live system.
//
// Sources, all router-held:
//   - every interface's ipv6-address  -> the containing /64 of each non-link-local address
//                                        (a WAN address is commonly carried at /127; the
//                                        translation matches the whole /64, so the /64 is the
//                                        unit to reserve)
//   - every interface's ipv6-prefix[].assigned -> each LAN sub-prefix at its own length
//   - the dhcp ipv6leases reply        -> each downstream DHCPv6-PD sub-delegation; the
//                                        router holds no address in these, so only the
//                                        lease data reveals them
//
// Prefixes outside any pool are emitted too: the allocator scopes the carve to in-pool
// entries and its gate is a no-op outside the pool, so the full set is emitted and filtered
// there. Duplicate prefixes (one /64 reached two ways) are collapsed. This set feeds the
// allocator's 'own' (skip) array only, never its carried 'units', so reserving a prefix
// never turns it into a translation target.

import * as ubus from "ubus";
import { prefix_canon, lease_pd_entries } from 'mwan3.common';

// The /64 containing addr; the address-source case (a WAN address is commonly carried at
// /127, but the translation matches the whole /64).

function addr_to_64(addr) {
	return prefix_canon(addr, 64);
}

// The emission core, factored out so the selftest can drive it on synthetic input the way
// mwan3-get-delegated-segments.uc tests pd_segments. ifaces is the network.interface dump's
// interface array; leases is the dhcp ipv6leases reply, walked through the shared
// lease_pd_entries() traversal in mwan3.common. Returns the deduplicated reserved prefixes
// in discovery order: each interface's own non-link-local address /64s, each assigned LAN
// sub-prefix, then each delegated PD sub-prefix. Incomplete entries are skipped; link-local
// (fe80::/10) addresses are skipped, as they never sit inside a pool.

function reserved_prefixes(ifaces, leases) {
	let out = [];
	let seen = {};
	function add(p) {
		if (p == null || p == "" || seen[p])
			return;
		seen[p] = true;
		push(out, p);
	}

	for (let ifc in (ifaces ?? [])) {
		for (let a in (ifc["ipv6-address"] ?? [])) {
			if (a.address == null || a.address == "")
				continue;
			if (match(a.address, /^fe80:/))
				continue;
			add(addr_to_64(a.address));
		}
		for (let pfx in (ifc["ipv6-prefix"] ?? [])) {
			let assigned = pfx.assigned ?? {};
			for (let lan in assigned) {
				let sub = assigned[lan];
				if (sub != null && sub.address != null && sub.mask != null)
					add(prefix_canon(sub.address, sub.mask));
			}
		}
	}

	for (let p in lease_pd_entries(leases))
		add(prefix_canon(p.address, p.length));

	return out;
}

// ---- self-test -------------------------------------------------------------------
// Documentation address space only (RFC 3849 2001:db8::/32 and generic fd00:: ULA); never
// a live network's addresses, so this suite is safe to read and run when debugging a user
// report. Targets render in canonical "h0:h1:h2:h3::/len" form, so a zero fourth hextet
// reads "h:h:h:0::" - that is the allocator's own render, not a typo.

if (ARGV[0] == "selftest") {
	let fails = 0;
	function cks(label, got, want) {
		let ok = (got == want);
		if (!ok) fails++;
		printf("  [%s] %-44s got=%-26s want=%s\n", ok ? "PASS" : "FAIL", label, got ?? "(null)", want);
	}
	function ckr(label, ifaces, leases, want) {
		let got = join(" ", reserved_prefixes(ifaces, leases));
		if (got == "") got = "(none)";
		let ok = (got == want);
		if (!ok) fails++;
		printf("  [%s] %-44s\n        got=  %s\n        want= %s\n", ok ? "PASS" : "FAIL", label, got, want);
	}

	printf("== prefix rendering ==\n");
	cks("GUA /127 own address to /64",   addr_to_64("2001:db8:a:b::"),                   "2001:db8:a:b::/64");
	cks("host bits dropped",             addr_to_64("2001:db8:a:b::1"),                  "2001:db8:a:b::/64");
	cks("full 8-hextet GUA to /64",      addr_to_64("2001:db8:1234:5678:9abc:def0:1:2"), "2001:db8:1234:5678::/64");
	cks("ULA /127 own address to /64",   addr_to_64("fd00:1234:5:abcd::3"),              "fd00:1234:5:abcd::/64");
	cks("zero fourth hextet renders :0", addr_to_64("2001:db8:a::5"),                    "2001:db8:a:0::/64");
	cks("segment keeps its own length",  prefix_canon("2001:db8:a:40::", 62),            "2001:db8:a:40::/62");
	cks("malformed literal yields null", addr_to_64("nonsense") ?? "(null)",             "(null)");

	printf("\n== reserved_prefixes sweep (synthetic dump + leases) ==\n");

	ckr("single iface: addresses (fe80 skipped) + assigned LAN",
	    [ { interface: "wan6",
	        "ipv6-address": [ { address: "2001:db8:a:1::", mask: 127 },
	                          { address: "fe80::1", mask: 64 },
	                          { address: "fd00:a:1:2::3", mask: 127 } ],
	        "ipv6-prefix": [ { address: "2001:db8:a::", mask: 60,
	                           assigned: { lan: { address: "2001:db8:a::", mask: 64 } } } ] } ],
	    null,
	    "2001:db8:a:1::/64 fd00:a:1:2::/64 2001:db8:a:0::/64");

	ckr("two ifaces, one delegation: sibling WAN address reserved",
	    [ { interface: "wan6",  "ipv6-address": [ { address: "2001:db8:a:1::", mask: 127 } ] },
	      { interface: "wan6b", "ipv6-address": [ { address: "2001:db8:a:3::", mask: 127 } ] } ],
	    null,
	    "2001:db8:a:1::/64 2001:db8:a:3::/64");

	ckr("downstream PD sub-delegation from leases",
	    [],
	    { device: { "br-lan": { leases: [
	        { "ipv6-prefix": [ { address: "2001:db8:a:40::", "prefix-length": 62 } ] } ] } } },
	    "2001:db8:a:40::/62");

	ckr("duplicate /64 from two sources collapses",
	    [ { interface: "lan",
	        "ipv6-address": [ { address: "2001:db8:a::1", mask: 64 } ],
	        "ipv6-prefix": [ { address: "2001:db8:a::", mask: 60,
	                           assigned: { lan: { address: "2001:db8:a::", mask: 64 } } } ] } ],
	    null,
	    "2001:db8:a:0::/64");

	ckr("incomplete entries skipped (null/empty/malformed/no-mask/no-len)",
	    [ { interface: "wan6",
	        "ipv6-address": [ { address: null }, { address: "" }, { address: "nonsense" },
	                          { address: "2001:db8:a:3::", mask: 127 } ],
	        "ipv6-prefix": [ { address: "2001:db8:a::", mask: 60,
	                           assigned: { lan: { address: "2001:db8:a::" } } } ] } ],
	    { device: { "br-lan": { leases: [
	        { "ipv6-prefix": [ { address: "2001:db8:a:80::" } ] } ] } } },
	    "2001:db8:a:3::/64");

	ckr("empty dump and leases emit nothing", [], null, "(none)");

	printf("\n%s (%d failure%s)\n", fails ? "OVERALL: FAIL" : "OVERALL: PASS", fails, (fails == 1) ? "" : "s");
	exit(fails ? 1 : 0);
}

let conn = ubus.connect();
if (!conn)
	exit(1);

let dump = conn.call("network.interface", "dump");
let leases = conn.call("dhcp", "ipv6leases");
conn.disconnect();

// Fail closed when the interface dump is null. An online translator always holds at least
// its own WAN address /64, so a null dump is an anomalous discovery failure (the object
// went away or the call failed), never a legitimately empty sweep. The shell treats this
// nonzero exit as "carve nothing this rebuild" and emits only the masquerade floor, rather
// than carving with an empty skip set that could place a translation target on a
// router-held prefix. Leases are genuinely optional and never force a failure.

if (dump == null)
	exit(1);

// One line per distinct reserved prefix across every interface; see reserved_prefixes.

for (let p in reserved_prefixes(dump.interface ?? [], leases))
	printf("%s\n", p);

exit(0);
