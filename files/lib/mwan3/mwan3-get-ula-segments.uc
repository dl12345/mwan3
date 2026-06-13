#!/usr/bin/env ucode
'use strict';

// Emit every ULA segment the router assigns or has delegated downstream, across ALL
// network interfaces, for the 1:1 prefix-translation carve's ULA intake (the 'auto'
// entry of list ipv6_translate_ula). A translating WAN listing 'auto' carries every
// segment printed here as a carve unit, so each ULA LAN gets a disjoint target carved
// from that WAN's pool exactly like a carried GUA segment.
//
// ARGV[0] = the literal "selftest" runs the built-in cases; with no argument the helper
//           sweeps the live system.
//
// Sources, both filtered to fc00::/7 containment:
//   - every interface's ipv6-prefix-assignment -> each ULA prefix netifd assigned to
//     that interface, at its assigned length. This is a router-global sweep with no
//     interface argument: the dump exposes each interface's own assignments, where the
//     per-WAN mwan3-get-delegated-segments.uc reads the WAN-side ipv6-prefix[].assigned
//     map instead.
//   - the dhcp ipv6leases reply -> each downstream DHCPv6-PD sub-delegation inside
//     fc00::/7 (a ULA network behind a downstream router).
//
// Prints one canonical "address/length" line per segment, deduplicated in discovery
// order. Exits nonzero on a null interface dump (fail closed, like
// mwan3-get-reserved-prefixes.uc); empty output with a successful dump is legitimate,
// not an error, because a router genuinely without ULA assignments exists. Leases are
// optional and never force a failure. Writes nothing to syslog: failure is signalled
// by exit code only, and the shell logs the consequence.

import * as ubus from "ubus";
import { prefix_canon, prefix_contains, lease_pd_entries } from 'mwan3.common';

// The emission core, factored out so the selftest can drive it on synthetic input the
// way reserved_prefixes() is tested in mwan3-get-reserved-prefixes.uc. ifaces is the
// network.interface dump's interface array; leases is the dhcp ipv6leases reply, walked
// through the shared lease_pd_entries() traversal in mwan3.common. Returns the
// deduplicated ULA segments in discovery order: each interface's ipv6-prefix-assignment
// entries inside fc00::/7 at their assigned length, then each downstream lease PD entry
// inside fc00::/7 at its own length. Incomplete entries are skipped; both sources render
// through prefix_canon and one seen-set, so a /64 reached as an assignment and as a
// lease PD yields a single line.

function ula_segments(ifaces, leases) {
	let out = [];
	let seen = {};
	function add(p) {
		if (p == null || p == "" || seen[p])
			return;
		seen[p] = true;
		push(out, p);
	}

	for (let ifc in (ifaces ?? []))
		for (let pfx in (ifc["ipv6-prefix-assignment"] ?? [])) {
			if (pfx.address == null || pfx.mask == null)
				continue;
			if (prefix_contains(pfx.address, pfx.mask, "fc00::", 7))
				add(prefix_canon(pfx.address, pfx.mask));
		}

	for (let p in lease_pd_entries(leases))
		if (prefix_contains(p.address, p.length, "fc00::", 7))
			add(prefix_canon(p.address, p.length));

	return out;
}

// ---- self-test -------------------------------------------------------------------
// Documentation address space only (RFC 3849 2001:db8::/32 and generic fd00:: ULA);
// never a live network's addresses, so this suite is safe to read and run when
// debugging a user report. Segments render in canonical "h0:h1:h2:h3::/len" form, so a
// zero fourth hextet reads "h:h:h:0::" - that is the allocator's own render, not a typo.

if (ARGV[0] == "selftest") {
	let fails = 0;
	function cku(label, ifaces, leases, want) {
		let got = join(" ", ula_segments(ifaces, leases));
		if (got == "") got = "(none)";
		let ok = (got == want);
		if (!ok) fails++;
		printf("  [%s] %-52s\n        got=  %s\n        want= %s\n", ok ? "PASS" : "FAIL", label, got, want);
	}

	printf("== ula_segments sweep (synthetic dump + leases) ==\n");

	cku("ULA assignment emitted at its assigned length",
	    [ { interface: "lan", "ipv6-prefix-assignment": [ { address: "fd00:db8:0:10::", mask: 60 } ] } ],
	    null,
	    "fd00:db8:0:10::/60");

	cku("GUA assignment excluded",
	    [ { interface: "lan", "ipv6-prefix-assignment": [ { address: "2001:db8:a:1::", mask: 64 } ] } ],
	    null,
	    "(none)");

	cku("interface carrying both emits only the ULA",
	    [ { interface: "lan", "ipv6-prefix-assignment": [
	        { address: "2001:db8:a:1::", mask: 64 },
	        { address: "fd00:db8:a:1::", mask: 64 } ] } ],
	    null,
	    "fd00:db8:a:1::/64");

	cku("ULA lease PD included, GUA lease PD excluded",
	    [],
	    { device: { "br-lan": { leases: [
	        { "ipv6-prefix": [ { address: "fd00:db8:a:40::", "prefix-length": 62 },
	                           { address: "2001:db8:a:40::", "prefix-length": 62 } ] } ] } } },
	    "fd00:db8:a:40::/62");

	cku("same ULA /64 as assignment and lease PD collapses",
	    [ { interface: "lan", "ipv6-prefix-assignment": [ { address: "fd00:db8:a:1::", mask: 64 } ] } ],
	    { device: { "br-lan": { leases: [
	        { "ipv6-prefix": [ { address: "fd00:db8:a:1::", "prefix-length": 64 } ] } ] } } },
	    "fd00:db8:a:1::/64");

	cku("incomplete entries skipped (no addr/no mask/malformed/no-len)",
	    [ { interface: "lan", "ipv6-prefix-assignment": [
	        { mask: 64 },
	        { address: "fd00:db8:a:2::" },
	        { address: "nonsense", mask: 64 },
	        { address: "fd00:db8:a:1::", mask: 64 } ] } ],
	    { device: { "br-lan": { leases: [
	        { "ipv6-prefix": [ { address: "fd00:db8:a:80::" } ] } ] } } },
	    "fd00:db8:a:1::/64");

	cku("segments across multiple interfaces all collected",
	    [ { interface: "lan",  "ipv6-prefix-assignment": [ { address: "fd00:db8:a:1::", mask: 64 } ] },
	      { interface: "test", "ipv6-prefix-assignment": [ { address: "fd00:db8:a:2::", mask: 64 } ] } ],
	    null,
	    "fd00:db8:a:1::/64 fd00:db8:a:2::/64");

	cku("empty dump and null leases emit nothing", [], null, "(none)");

	cku("zero fourth hextet renders :0 (canonical form)",
	    [ { interface: "lan", "ipv6-prefix-assignment": [ { address: "fd00:db8:a::", mask: 64 } ] } ],
	    null,
	    "fd00:db8:a:0::/64");

	printf("\n%s (%d failure%s)\n", fails ? "OVERALL: FAIL" : "OVERALL: PASS", fails, (fails == 1) ? "" : "s");
	exit(fails ? 1 : 0);
}

let conn = ubus.connect();
if (!conn)
	exit(1);

let dump = conn.call("network.interface", "dump");
let leases = conn.call("dhcp", "ipv6leases");
conn.disconnect();

// Fail closed when the interface dump is null: an anomalous discovery failure (the
// object went away or the call failed), which the shell treats as "carve nothing this
// rebuild", emitting only the masquerade floor. A successful dump with no ULA
// assignment legitimately prints nothing and exits 0.

if (dump == null)
	exit(1);

// One line per distinct ULA segment across every interface; see ula_segments.

for (let s in ula_segments(dump.interface ?? [], leases))
	printf("%s\n", s);

exit(0);
