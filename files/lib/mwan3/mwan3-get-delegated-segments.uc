#!/usr/bin/env ucode
'use strict';

// Discover the active LAN segments of an mwan3 WAN interface: the per-LAN
// sub-prefixes netifd has assigned out of the WAN's delegated prefix(es), plus any
// cascaded downstream DHCPv6-PD sub-delegation carved from this WAN's delegation.
//
// ARGV[0] = ubus network interface name (the true_iface resolved by
//           mwan3_get_true_iface, e.g. "wan6"); the literal "selftest" instead runs
//           the built-in containment and PD-discovery cases.
// ARGV[1] = the mwan3/config interface name (e.g. "wan6"); optional, used only
//           for the static fallback below.
//
// Prints one "address/mask" line per active segment. The first source is each entry
// of the interface's ipv6-prefix[].assigned map in network.interface.<iface> status:
// a sub-prefix netifd carved from the WAN's delegation for a directly-attached
// downstream LAN, normally a /64. Unlike mwan3-get-prefix.uc, which emits the parent
// delegated prefix for coarse source marking, this emits the segments the clients
// actually occupy, which is the unit the prefix-translation carve maps one-to-one
// onto a disjoint target.
//
// The second source is a cascaded downstream DHCPv6-PD sub-delegation: a prefix
// odhcpd handed to a separate downstream router. That is not in netifd's assigned
// map, but appears in the dhcp object's ipv6leases method under each lease's
// ipv6-prefix array. Any such prefix that falls within this WAN's delegated
// prefix(es) is emitted too, at its own delegated length, so the carve covers the
// downstream clients as well; the association to this WAN is by prefix containment,
// and a sub-delegation inside no delegated prefix of this WAN is ignored.
//
// Static fallback: when ubus yields no segment at all - whether the status is empty
// of prefixes or absent entirely (the WAN administratively down, status null) - and
// ARGV[1] names a config interface carrying a static option ip6prefix, that
// configured prefix is emitted instead, mirroring mwan3-get-prefix.uc so a
// statically-delegated WAN still yields a segment while up. A WAN with no delegation
// at all prints nothing and exits 0.

import * as ubus from "ubus";
import * as uci from "uci";
import { prefix_canon, prefix_contains, lease_pd_entries } from 'mwan3.common';

// Collect the cascaded downstream PD sub-delegations from a dhcp ipv6leases reply that
// fall within this WAN's delegated prefixes (deleg = [{address, mask}, ...]). The lease
// walk is the shared lease_pd_entries() traversal in mwan3.common, which yields every
// complete PD entry as an { address, length } pair; each entry contained in one of this
// WAN's delegations is emitted as an "address/length" segment, and an entry inside no
// delegation of this WAN is ignored.

function pd_segments(leases, deleg) {
	let out = [];
	for (let p in lease_pd_entries(leases))
		for (let d in deleg)
			if (prefix_contains(p.address, p.length, d.address, d.mask)) {
				push(out, sprintf("%s/%d", p.address, p.length));
				break;
			}
	return out;
}

// Re-render a pd_segments "address/length" result through prefix_canon so a downstream
// lease PD and a netifd assigned segment that designate the same prefix collapse in the
// dedup below. pd_segments keeps its string form for its own selftest; only this canonical
// pass feeds the dedup.

function canon_seg(seg) {
	let parts = split(seg, "/");
	if (length(parts) != 2)
		return null;
	return prefix_canon(parts[0], int(parts[1]));
}

// The emission core, factored out so the selftest can drive it on synthetic input the way
// pd_segments is tested directly, and mirroring reserved_prefixes() in
// mwan3-get-reserved-prefixes.uc. status_prefixes is the interface status ipv6-prefix
// array; leases is the dhcp ipv6leases reply. Returns the deduplicated, canonically
// rendered active segments in discovery order: each netifd assigned LAN sub-prefix, then
// each cascaded downstream DHCPv6-PD sub-delegation that falls within this WAN's
// delegation. Both sources pass through prefix_canon and one seen-set, so a /64 reached as
// an assigned segment and as a lease PD yields a single line.

function segments(status_prefixes, leases) {
	let out = [];
	let seen = {};
	function add(p) {
		if (p == null || p == "" || seen[p])
			return;
		seen[p] = true;
		push(out, p);
	}

	let deleg = [];
	for (let prefix in (status_prefixes ?? [])) {
		if (prefix.address != null && prefix.mask != null)
			push(deleg, { address: prefix.address, mask: prefix.mask });
		let assigned = prefix.assigned ?? {};
		for (let lan_name in assigned) {
			let sub = assigned[lan_name];
			if (sub != null && sub.address != null && sub.mask != null)
				add(prefix_canon(sub.address, sub.mask));
		}
	}

	for (let seg in pd_segments(leases, deleg))
		add(canon_seg(seg));

	return out;
}

// ---- self-test -------------------------------------------------------------------

if (ARGV[0] == "selftest") {
	let fails = 0;
	function ck(label, got, want) {
		let ok = (got == want);
		if (!ok) fails++;
		printf("  [%s] %-44s got=%-5s want=%s\n", ok ? "PASS" : "FAIL", label, got ? "true" : "false", want ? "true" : "false");
	}
	function cks(label, got, want) {
		let ok = (got == want);
		if (!ok) fails++;
		printf("  [%s] %-44s\n        got=  %s\n        want= %s\n", ok ? "PASS" : "FAIL", label, got, want);
	}

	printf("== prefix_contains containment ==\n");
	ck("/60 within /56",         prefix_contains("2001:db8:1234:5640::", 60, "2001:db8:1234:5600::", 56), true);
	ck("/62 within /56",         prefix_contains("2001:db8:1234:5644::", 62, "2001:db8:1234:5600::", 56), true);
	ck("/64 within /48",         prefix_contains("2001:db8:1234:9999::", 64, "2001:db8:1234::",      48), true);
	ck("/56 exact /56",          prefix_contains("2001:db8:1234:5600::", 56, "2001:db8:1234:5600::", 56), true);
	ck("/60 outside /56 (b5)",   prefix_contains("2001:db8:1235:5640::", 60, "2001:db8:1234:5600::", 56), false);
	ck("/60 outside /56 (b6)",   prefix_contains("2001:db8:1234:5740::", 60, "2001:db8:1234:5600::", 56), false);
	ck("parent finer (/60>/56)", prefix_contains("2001:db8:1234:5600::", 56, "2001:db8:1234:5640::", 60), false);
	ck("ULA /60 within /48",     prefix_contains("fd00:1234:5:60::",     60, "fd00:1234:5::",        48), true);

	printf("\n== pd_segments discovery ==\n");
	let leases = {
		device: {
			"br-lan": {
				leases: [
					{ duid: "00030001abcdef", iaid: 1, hostname: "downstream",
					  "accept-reconf": 0, assigned: 64, flags: [ "bound" ],
					  "ipv6-prefix": [ { address: "2001:db8:1234:5640::", "preferred-lifetime": 3600,
					                     "valid-lifetime": 7200, "prefix-length": 60 } ],
					  valid: 7200 },
					{ "ipv6-prefix": [ { address: "2001:db8:9999:5650::", "prefix-length": 60 } ] },
					{ "ipv6-prefix": [ { address: "2001:db8:1234:5641::abcd" } ] }
				]
			},
			"br-guest": {
				leases: [
					{ "ipv6-prefix": [ { address: "2001:db8:1234:5644::", "prefix-length": 62 } ] }
				]
			}
		}
	};
	let deleg = [ { address: "2001:db8:1234:5600::", mask: 56 } ];
	let got = join(" ", pd_segments(leases, deleg));
	cks("PDs within /56 deleg, others ignored", got,
	    "2001:db8:1234:5640::/60 2001:db8:1234:5644::/62");

	let got2 = join(" ", pd_segments(leases, [ { address: "2001:db8::", mask: 32 } ]));
	cks("/32 deleg catches all three sub-delegations", got2,
	    "2001:db8:1234:5640::/60 2001:db8:9999:5650::/60 2001:db8:1234:5644::/62");

	let got3 = join(" ", pd_segments({ device: {} }, deleg));
	cks("empty leases yield nothing", got3 == "" ? "(none)" : got3, "(none)");

	printf("\n== segments() dedup + canonicalization ==\n");

	cks("assigned + lease PD naming one /64 collapse to one line",
	    join(" ", segments(
	        [ { address: "2001:db8:a::", mask: 60,
	            assigned: { lan: { address: "2001:db8:a:5::", mask: 64 } } } ],
	        { device: { "br-lan": { leases: [
	            { "ipv6-prefix": [ { address: "2001:db8:a:5::", "prefix-length": 64 } ] } ] } } })),
	    "2001:db8:a:5::/64");

	cks("assigned segment canonicalizes (zero fourth hextet renders :0)",
	    join(" ", segments(
	        [ { address: "2001:db8:a::", mask: 60,
	            assigned: { lan: { address: "2001:db8:a::", mask: 64 } } } ],
	        null)),
	    "2001:db8:a:0::/64");

	cks("distinct assigned and lease PD both emitted, in discovery order",
	    join(" ", segments(
	        [ { address: "2001:db8:a::", mask: 56,
	            assigned: { lan: { address: "2001:db8:a:1::", mask: 64 } } } ],
	        { device: { "br-lan": { leases: [
	            { "ipv6-prefix": [ { address: "2001:db8:a:40::", "prefix-length": 60 } ] } ] } } })),
	    "2001:db8:a:1::/64 2001:db8:a:40::/60");

	cks("no prefixes and no leases yield nothing",
	    join(" ", segments([], null)) == "" ? "(none)" : join(" ", segments([], null)),
	    "(none)");

	printf("\n%s (%d failure%s)\n", fails ? "OVERALL: FAIL" : "OVERALL: PASS", fails, (fails == 1) ? "" : "s");
	exit(fails ? 1 : 0);
}

let iface = ARGV[0];
if (iface == null || iface == "")
	exit(1);

let conn = ubus.connect();
if (!conn)
	exit(1);

let status = conn.call("network.interface." + iface, "status");

// Fail closed when the interface status is null. This helper is only ever called for an
// online WAN, whose status object always exists, so a null reply is an anomalous discovery
// failure (netifd unreachable or the interface object absent), not a prefixless WAN. The
// shell treats the nonzero exit as a discovery failure and emits the masquerade floor only
// this rebuild rather than carving on an incomplete view. A non-null status that merely
// lacks prefixes still falls through to the static ip6prefix fallback below.

if (status == null) {
	conn.disconnect();
	exit(1);
}

let leases = conn.call("dhcp", "ipv6leases");
conn.disconnect();

// One canonical line per active segment, deduplicated across the assigned-segment and
// downstream-PD sources (see segments()).

let segs = segments(status["ipv6-prefix"] ?? [], leases);
for (let seg in segs)
	printf("%s\n", seg);

// Fall back to the statically configured ip6prefix only when ubus yielded no segment.

if (length(segs) == 0 && ARGV[1] != null && ARGV[1] != "") {
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
