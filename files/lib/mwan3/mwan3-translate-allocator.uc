#!/usr/bin/env ucode
'use strict';

// IPv6 1:1 prefix-translation target allocator.
//
// Given a translating WAN's carve pool (its delegation, or a configured sub-block),
// the LAN segments it already occupies inside that pool, and the source segments to
// be carried for other WANs, assign each carried segment a disjoint, equal-length
// target prefix carved from the pool, or mark it for the always-on stateful floor when
// no aligned target of its length is free. The carved map renders as conntrack NETMAP
// prefix maps, so the host part of the address and the ports are preserved and each
// carried host gets a stable, individually reachable external address.
//
// A largest-first first-fit allocator plus an independent disjointness gate.
// It works entirely in slot-index space at the finest carried length, so the body
// is integer interval packing rather than 128-bit address arithmetic; the address
// is reconstructed only when a target is emitted, and all arithmetic stays inside
// the lower 32 bits of the top-64, which is always positive, so global unicast and
// ULA (fd00::/8, top bit set) render the same.
//
// Placement is lowest-free-slot deterministic: a rebuild with unchanged inputs produces
// an identical map, so a live carried flow is never reshuffled onto a different target.
//
// Entry points:
//   selftest        run the built-in placement cases and print their results.
//   canon <cidr...> mask each argument to its prefix length, for the shell's intake.
//   <json-object>   a single JSON-object argument { dev, pool, own, units } (every
//                   address a CIDR string). A carried unit is either a carve unit (a
//                   src segment), which takes a disjoint target carved from the pool,
//                   or a fixed-target override unit (a src delegation plus an explicit
//                   target), which is mapped whole onto that target and occupies no
//                   pool slot, so its target may lie outside the pool. A disjointness
//                   gate in address space then drops any target overlapping an own
//                   segment or an already-accepted target, fencing carve and override
//                   alike. Render typed lines on stdout for the shell:
//                     rule <nft statement>      the snat then the dnat prefix-map rule,
//                                               two when any map was accepted, none if not
//                     target <cidr>             one carved or override target, observability
//                     stateful <src> <reason>   a unit left to the stateful floor,
//                                               reason in { capacity, overlap, fine }
//                     absorbed <src> <by>       a unit absorbed into a coarser unit's map
//                   addresses are converted with the core iptoarr built-in (the
//                   inet_pton wrapper), so no IPv6 text is ever hand-parsed.

import { log_open, log_msg, cidr_split, render, mask_cidr, aligned, prefix_overlap } from 'mwan3.common';

const MAXLEN = 64;    // carry granularity floor: nothing finer than a /64 is a LAN segment
const MINPOOL = 32;   // pool no larger than /32, so the slot field stays in the low 32 bits

// pool  = { h: [h0,h1,h2,h3], D }     carve pool: top-64 hextets and length D
// own   = [ {h:[h0..h3], len} ... ]   segments the translating WAN already uses; only those
//                                     inside the pool occupy a slot, the rest are ignored
// units = [ {src, len} ... ]          carried source segments; src is the prefix string
//                                     carried through to the nft rule, len picks the target size
//
// returns { slot_len, nslots, maps: [{src, target}], stateful: [{src, reason}] }

function allocate(pool, own, units) {
	let maps = [], stateful = [];

	// Domain guard: a pool larger than /32 would push the slot field out of the low
	// 32 bits; no real delegation is that large. Carry everything stateful.

	if (pool.D < MINPOOL || pool.D > MAXLEN) {
		for (let u in units) push(stateful, { src: u.src, reason: "capacity" });
		return { slot_len: 0, nslots: 0, maps, stateful };
	}

	let pool_high = (pool.h[0] << 16) + pool.h[1];   // bits 0..31, always in the /D prefix
	let pool_low  = (pool.h[2] << 16) + pool.h[3];   // bits 32..63

	function in_pool(h) {
		if (((h[0] << 16) + h[1]) != pool_high) return false;
		let lo = (h[2] << 16) + h[3];
		return (lo >> (64 - pool.D)) == (pool_low >> (64 - pool.D));
	}

	// A unit finer than /64 is not a LAN segment and cannot be carved as a translation
	// target; send it straight to the stateful floor. A unit coarser than the pool cannot fit
	// in it at all. Everything else is a carry candidate.

	let carry = [];
	for (let u in units) {
		if (u.len > MAXLEN || u.len < pool.D)
			push(stateful, { src: u.src, reason: (u.len > MAXLEN) ? "fine" : "capacity" });
		else push(carry, u);
	}

	// Slot granularity is the longest (most specific) length present, capped at /64.

	let slot_len = pool.D;
	for (let u in carry) if (u.len > slot_len) slot_len = u.len;
	for (let o in own)   if (o.len > slot_len && o.len <= MAXLEN) slot_len = o.len;
	if (slot_len > MAXLEN) slot_len = MAXLEN;

	let nslots = (1 << (slot_len - pool.D));

	function slot_of(h) {
		return (((h[2] << 16) + h[3]) - pool_low) >> (64 - slot_len);
	}

	// Occupied [s,e) intervals from the translating WAN's own in-pool segments.

	let occ = [];
	for (let o in own) {
		if (o.len > MAXLEN || !in_pool(o.h)) continue;
		let s = slot_of(o.h);
		push(occ, { s, e: s + (1 << (slot_len - o.len)) });
	}

	function overlaps(s, e) {
		for (let iv in occ) if (s < iv.e && iv.s < e) return true;
		return false;
	}

	// Largest-first: place the coarsest (smallest length) units before the finer ones,
	// so a big aligned block is not blocked by fragments the fine units would leave.

	let order = [];
	for (let i = 0; i < length(carry); i++) push(order, i);
	sort(order, function(a, b) { return carry[a].len - carry[b].len; });

	for (let idx in order) {
		let u = carry[idx];
		let sz = (1 << (slot_len - u.len));
		let placed = false;
		for (let start = 0; start + sz <= nslots; start += sz) {   // step == sz keeps alignment
			if (!overlaps(start, start + sz)) {
				push(occ, { s: start, e: start + sz });
				let lo = pool_low + (start << (64 - slot_len));
				let th = [ pool.h[0], pool.h[1], (lo >> 16) & 0xffff, lo & 0xffff ];
				push(maps, { src: u.src, target: render(th, u.len), _s: start, _e: start + sz });
				placed = true;
				break;
			}
		}
		if (!placed) push(stateful, { src: u.src, reason: "capacity" });
	}

	return { slot_len, nslots, maps, stateful };
}

// Independent correctness gate (self-test form): assert no two emitted targets
// overlap. A violation means an allocator bug; the production gate below converts
// the same check into a drop-to-stateful so it can never install a colliding rule.

function gate(res) {
	let ok = true;
	for (let i = 0; i < length(res.maps); i++)
		for (let j = i + 1; j < length(res.maps); j++) {
			let a = res.maps[i], b = res.maps[j];
			if (a._s < b._e && b._s < a._e) {
				printf("    GATE VIOLATION: %s overlaps %s\n", a.target, b.target);
				ok = false;
			}
		}
	return ok;
}

// Source-key disjointness filter. The rendered map's keys must not nest: nft rejects
// nested map keys at load, and an overlapping source key is ambiguous. A unit whose src
// is contained in (or equal to) another unit's src is therefore absorbed by the coarser
// unit, whose structure-preserving map carries the contained space too. Containment includes
// equality, with the first of an exact duplicate kept. The filter runs over carve and
// override units together, on the full unit set, before any placement, and records each drop
// as { src, by } for the caller to log. Reuses prefix_overlap() (two positive 32-bit halves).

function filter_contained(units, absorbed) {
	let p = [];
	for (let u in units)
		push(p, cidr_split(u.src));

	let keep = [];
	for (let i = 0; i < length(units); i++) {
		let a = p[i];
		if (a == null) {
			push(keep, units[i]);
			continue;
		}
		let by = null;
		for (let j = 0; j < length(units); j++) {
			if (j == i)
				continue;
			let b = p[j];
			if (b == null)
				continue;

			// b covers a when b is strictly coarser, or equal and earlier (keep the first).

			if ((b.len < a.len || (b.len == a.len && j < i)) && prefix_overlap(a.h, a.len, b.h, b.len)) {
				by = j;
				break;
			}
		}
		if (by != null)
			push(absorbed, { src: units[i].src, by: units[by].src });
		else
			push(keep, units[i]);
	}
	return keep;
}

// Production driver: parse the input contract's own/units, carve the pool units, place
// the fixed-target override units whole, gate the full target set in address space, and
// return the accepted maps plus the stateful-floor list for the caller to render.
//
// A unit carrying a target is an override: it is mapped src->target directly, with the
// target rendered at the src (delegation) length so an oversized target is carved down to
// its first delegation-sized sub-block, and it never consumes a pool slot. A unit with no
// target is a carve unit, placed from the pool by allocate(); with no pool every carve
// unit falls to the stateful floor (an override needs no pool). The gate then walks the
// carved and override targets together in config order, dropping to the stateful floor
// (reason overlap) any whose prefix overlaps an own segment or an earlier-accepted target.
// That backstop keeps an allocator or override mistake costing only the 1:1 translation
// rather than reintroducing a collision.

function process(input) {
	let own = [];
	for (let o in (input.own ?? [])) {
		let hl = cidr_split(o);
		if (hl != null)
			push(own, hl);
	}

	let absorbed = [];
	let units = filter_contained(input.units ?? [], absorbed);

	let carve_units = [];
	for (let u in units)
		if (u.target == null) {
			let hl = cidr_split(u.src);
			if (hl != null)
				push(carve_units, { src: u.src, len: hl.len });
		}

	let res;
	let pool = (input.pool != null) ? cidr_split(input.pool) : null;
	if (pool == null) {
		res = { maps: [], stateful: [] };
		for (let u in carve_units)
			push(res.stateful, { src: u.src, reason: "capacity" });
	} else {
		pool.D = pool.len;
		res = allocate(pool, own, carve_units);
	}

	// Index the carved targets by source so the config-order walk can pick each up.

	let placed = {};
	for (let m in res.maps)
		placed[m.src] = m;

	// Build the full target set in config order: an override unit becomes a direct map
	// (target rendered at the src length), a carve unit takes its allocated target, and a
	// carve unit that could not be placed is already on the stateful list.

	let all_maps = [];
	for (let u in units) {
		if (u.target != null) {
			let s = cidr_split(u.src), t = cidr_split(u.target);
			if (s == null || t == null)
				continue;
			push(all_maps, { src: u.src, target: render(t.h, s.len) });
		} else if (placed[u.src] != null) {
			push(all_maps, placed[u.src]);
		}
	}

	// Address-space disjointness gate over carve and override targets alike.

	let accepted = [];
	for (let m in all_maps) {
		let mt = cidr_split(m.target);
		let bad = false;
		for (let o in own)
			if (prefix_overlap(mt.h, mt.len, o.h, o.len)) { bad = true; break; }
		if (!bad)
			for (let a in accepted) {
				let at = cidr_split(a.target);
				if (prefix_overlap(mt.h, mt.len, at.h, at.len)) { bad = true; break; }
			}
		if (bad)
			push(res.stateful, { src: m.src, reason: "overlap" });
		else
			push(accepted, m);
	}

	return { accepted, stateful: res.stateful, absorbed };
}

// ---- self-test -------------------------------------------------------------------

// Failure counter shared by the run(), show() and canon checks below, so the selftest exits
// nonzero on any failure, like the get-segments and reserved-prefixes selftests.

let fails = 0;

function seg(h0, h1, h2, h3, len) {
	return { h: [h0, h1, h2, h3], len };
}

function run(name, pool, own, units) {
	printf("== %s ==\n", name);
	let res = allocate(pool, own, units);
	printf("  pool /%d, slot granularity /%d, %d slots\n", pool.D, res.slot_len, res.nslots);
	for (let m in res.maps)
		printf("  MAP   %-22s -> %s\n", m.src, m.target);
	for (let s in res.stateful)
		printf("  MASQ  %-22s (stateful)\n", s.src);
	let g = gate(res);
	if (!g) fails++;
	printf("  gate: %s\n\n", g ? "ok" : "FAILED");
}

// Entry point: canonicalize operator-supplied prefixes at intake. One typed line per
// argument so the shell can mask a value with host bits (with a warning) and drop an
// unparseable one before it ever reaches a map element.

if (ARGV[0] == "canon") {
	for (let i = 1; i < length(ARGV); i++) {
		let r = mask_cidr(ARGV[i]);
		if (r == null)
			printf("bad\n");
		else
			printf("%s %s\n", r.changed ? "masked" : "ok", r.canonical);
	}
	exit(0);
}

if (ARGV[0] == "selftest") {
	let P48  = { h: [0x2001, 0x0db8, 0xf000, 0x0000], D: 48 };
	let P60  = { h: [0x2001, 0x0db8, 0xf000, 0x0000], D: 60 };
	let P62  = { h: [0x2001, 0x0db8, 0xf000, 0x0000], D: 62 };
	let ULA  = { h: [0xfd00, 0x0db8, 0xf000, 0x0000], D: 48 };

	// 1. Uniform /64 (the common case).

	run("uniform /64, own uses slots 0 and 5", P48,
	    [ seg(0x2001,0x0db8,0xf000,0,64), seg(0x2001,0x0db8,0xf000,5,64) ],
	    [ {src:"2001:db8:a::/64",len:64}, {src:"2001:db8:b::/64",len:64}, {src:"2001:db8:c::/64",len:64} ]);

	// 2. Mixed /64 + downstream /60 (cascaded-PD): coarse first, /64s fill around it.

	run("mixed /64 + downstream /60, own uses slot 0", P48,
	    [ seg(0x2001,0x0db8,0xf000,0,64) ],
	    [ {src:"2001:db8:a::/64",len:64}, {src:"2001:db8:b::/64",len:64}, {src:"2001:db8:d::/60",len:60} ]);

	// 3. Fragmentation: a /63 cannot be placed though two /64s are free but non-adjacent.

	run("fragmentation: /63 into a /62 pool, own at slots 0 and 2", P62,
	    [ seg(0x2001,0x0db8,0xf000,0,64), seg(0x2001,0x0db8,0xf000,2,64) ],
	    [ {src:"2001:db8:e::/63",len:63} ]);

	// 4. Capacity exhaustion: a /60 pool has 16 /64s, own takes 1, ask for 20.

	let many = [];
	for (let i = 0; i < 20; i++) push(many, { src: sprintf("2001:db8:%x::/64", i), len: 64 });
	run("capacity: 20 x /64 into a /60 pool, own uses slot 0", P60,
	    [ seg(0x2001,0x0db8,0xf000,0,64) ], many);

	// 5. ULA pool: proves the rendering is sign-safe with the top bit set.

	run("ULA fd00::/48 pool, uniform /64", ULA,
	    [ seg(0xfd00,0x0db8,0xf000,0,64) ],
	    [ {src:"2001:db8:a::/64",len:64}, {src:"2001:db8:b::/64",len:64} ]);

	// 6. Guards: an own segment outside the pool is ignored (so slot 0 is free), and a
	//    finer-than-/64 unit goes straight to stateful.

	run("guards: out-of-pool own ignored, sub-/64 unit forced stateful", P48,
	    [ seg(0x2001,0x0db8,0xe000,0,64) ],
	    [ {src:"2001:db8:a::/64",len:64}, {src:"2001:db8:b:0:1::/96",len:96} ]);

	// Override (fixed-target) units and the address-space gate, driven through process()
	// so the full production path is exercised: a valid override maps whole onto its
	// target, an override onto an own segment or onto an already-placed target is dropped
	// to the stateful floor by the gate, config order decides a carve/override collision,
	// and an oversized override target is carved down to a delegation-sized sub-block.

	function show(name, input, want_maps, want_state, want_absorbed) {
		if (want_absorbed == null) want_absorbed = "";
		printf("== %s ==\n", name);
		let r = process(input);
		let got_maps = "";
		for (let m in r.accepted)
			got_maps += sprintf("%s>%s ", m.src, m.target);
		let got_state = "";
		for (let s in r.stateful)
			got_state += sprintf("%s(%s) ", s.src, s.reason);
		let got_abs = "";
		for (let a in (r.absorbed ?? []))
			got_abs += sprintf("%s<%s ", a.src, a.by);
		got_maps = trim(got_maps); got_state = trim(got_state); got_abs = trim(got_abs);
		printf("  maps:     %s\n", got_maps);
		printf("  stateful: %s\n", got_state);
		if (want_absorbed != "" || got_abs != "")
			printf("  absorbed: %s\n", got_abs);
		let ok = (got_maps == want_maps && got_state == want_state && got_abs == want_absorbed);
		if (!ok) fails++;
		printf("  result: %s\n\n", ok ? "PASS" : "FAIL");
		return ok;
	}

	let ovok = true;

	ovok = show("override valid + override-on-own dropped + carve",
	    { dev: "lb0", pool: "2001:db8:f000::/60", own: [ "2001:db8:f000::/64" ],
	      units: [ { src: "2001:db8:a::/64", target: "2001:db8:f000:5::/64" },
	               { src: "2001:db8:b::/64", target: "2001:db8:f000::/64" },
	               { src: "2001:db8:c::/64" } ] },
	    "2001:db8:a::/64>2001:db8:f000:5::/64 2001:db8:c::/64>2001:db8:f000:1::/64",
	    "2001:db8:b::/64(overlap)") && ovok;

	ovok = show("carve before colliding override: carve wins",
	    { dev: "lb0", pool: "2001:db8:f000::/60", own: [],
	      units: [ { src: "2001:db8:a::/64" },
	               { src: "2001:db8:b::/64", target: "2001:db8:f000::/64" } ] },
	    "2001:db8:a::/64>2001:db8:f000:0::/64",
	    "2001:db8:b::/64(overlap)") && ovok;

	ovok = show("override before colliding carve: override wins",
	    { dev: "lb0", pool: "2001:db8:f000::/60", own: [],
	      units: [ { src: "2001:db8:b::/64", target: "2001:db8:f000::/64" },
	               { src: "2001:db8:a::/64" } ] },
	    "2001:db8:b::/64>2001:db8:f000:0::/64",
	    "2001:db8:a::/64(overlap)") && ovok;

	ovok = show("oversized override target carved down to a /64",
	    { dev: "lb0", pool: null, own: [],
	      units: [ { src: "2001:db8:a::/64", target: "2001:db8:e000::/60" } ] },
	    "2001:db8:a::/64>2001:db8:e000:0::/64", "") && ovok;

	// Cascaded sub-delegation placement through the full process() path, exact-matched: a
	// downstream /60 carried alongside two /64 LAN segments lands on its own equal-length
	// target (internal structure preserved), disjoint, with the /64s filling the fragments
	// around the WAN's own slot 0; and an odd /63 that finds no two adjacent free slots
	// falls to the stateful floor.

	ovok = show("cascaded mixed-length: downstream /60 placed disjoint from /64s",
	    { dev: "lb0", pool: "2001:db8:f000::/48", own: [ "2001:db8:f000::/64" ],
	      units: [ { src: "2001:db8:a::/64" }, { src: "2001:db8:b::/64" }, { src: "2001:db8:d::/60" } ] },
	    "2001:db8:a::/64>2001:db8:f000:1::/64 2001:db8:b::/64>2001:db8:f000:2::/64 2001:db8:d::/60>2001:db8:f000:10::/60",
	    "") && ovok;

	ovok = show("odd /63 with no adjacent free pair falls to the floor",
	    { dev: "lb0", pool: "2001:db8:f000::/62", own: [ "2001:db8:f000::/64", "2001:db8:f000:2::/64" ],
	      units: [ { src: "2001:db8:e::/63" } ] },
	    "", "2001:db8:e::/63(capacity)") && ovok;

	// Source-key disjointness: a segment contained in a coarser unit's src is
	// absorbed, keeping the map keys disjoint. A whole-delegation override absorbs the
	// segments inside it (the shell emits carve units regardless of overrides),
	// while a segment outside the override still carves from the pool; exact duplicates keep
	// the first; disjoint units are untouched.

	ovok = show("override absorbs a contained segment",
	    { dev: "lb0", pool: "2001:db8:f000::/48", own: [],
	      units: [ { src: "2001:db8:b000::/56", target: "2001:db8:c000::/56" },
	               { src: "2001:db8:b000:1::/64" } ] },
	    "2001:db8:b000::/56>2001:db8:c000:0::/56", "",
	    "2001:db8:b000:1::/64<2001:db8:b000::/56") && ovok;

	ovok = show("override absorbs its inside segment, a disjoint segment still carves",
	    { dev: "lb0", pool: "2001:db8:f000::/48", own: [],
	      units: [ { src: "2001:db8:b000::/56", target: "2001:db8:c000::/56" },
	               { src: "2001:db8:b000:1::/64" },
	               { src: "2001:db8:e::/64" } ] },
	    "2001:db8:b000::/56>2001:db8:c000:0::/56 2001:db8:e::/64>2001:db8:f000:0::/64", "",
	    "2001:db8:b000:1::/64<2001:db8:b000::/56") && ovok;

	ovok = show("exact duplicate src keeps the first",
	    { dev: "lb0", pool: "2001:db8:f000::/48", own: [],
	      units: [ { src: "2001:db8:a::/64" }, { src: "2001:db8:a::/64" } ] },
	    "2001:db8:a::/64>2001:db8:f000:0::/64", "",
	    "2001:db8:a::/64<2001:db8:a::/64") && ovok;

	ovok = show("disjoint units are not absorbed",
	    { dev: "lb0", pool: "2001:db8:f000::/48", own: [],
	      units: [ { src: "2001:db8:a::/64" }, { src: "2001:db8:b::/64" } ] },
	    "2001:db8:a::/64>2001:db8:f000:0::/64 2001:db8:b::/64>2001:db8:f000:1::/64", "",
	    "") && ovok;

	printf("override cases: %s\n", ovok ? "ALL PASS" : "SOME FAILED");

	// ULA carve units through the full process() path. ULA sources are plain carve
	// units and take the same placement, absorption and floor behaviour as GUA
	// sources; these cases pin that down. The own array in the second case carries
	// LAN ULA entries exactly as the reserved sweep emits them: out-of-pool own
	// fd-entries occupy no slot and never suppress the unit, even when one of them
	// IS the carried segment.

	printf("\n");
	let ulaok = true;

	ulaok = show("ULA carve unit alongside GUA units, all placed disjoint",
	    { dev: "lb0", pool: "2001:db8:f000::/60", own: [],
	      units: [ { src: "2001:db8:a::/64" },
	               { src: "fd00:db8:1::/64" },
	               { src: "2001:db8:b::/64" } ] },
	    "2001:db8:a::/64>2001:db8:f000:0::/64 fd00:db8:1::/64>2001:db8:f000:1::/64 2001:db8:b::/64>2001:db8:f000:2::/64",
	    "") && ulaok;

	ulaok = show("own LAN ULA entries occupy no slot, never suppress the unit",
	    { dev: "lb0", pool: "2001:db8:f000::/60",
	      own: [ "fd00:db8:1::/64", "fd00:db8:2::/64" ],
	      units: [ { src: "fd00:db8:1::/64" } ] },
	    "fd00:db8:1::/64>2001:db8:f000:0::/64",
	    "") && ulaok;

	ulaok = show("exact-duplicate ULA unit (auto + explicit) keeps the first",
	    { dev: "lb0", pool: "2001:db8:f000::/60", own: [],
	      units: [ { src: "fd00:db8:1::/64" }, { src: "fd00:db8:1::/64" } ] },
	    "fd00:db8:1::/64>2001:db8:f000:0::/64", "",
	    "fd00:db8:1::/64<fd00:db8:1::/64") && ulaok;

	ulaok = show("ULA unit into a fully carved single-slot pool falls to the floor",
	    { dev: "lb0", pool: "2001:db8:f000::/64", own: [],
	      units: [ { src: "2001:db8:a::/64" }, { src: "fd00:db8:1::/64" } ] },
	    "2001:db8:a::/64>2001:db8:f000:0::/64",
	    "fd00:db8:1::/64(capacity)") && ulaok;

	printf("ULA cases: %s\n", ulaok ? "ALL PASS" : "SOME FAILED");

	// Intake canonicalization (canon mode): an aligned value passes through unchanged, a
	// value with host bits below its length is masked, and an unparseable literal is
	// rejected. The two review corruption regressions are the /60 pool with a stray low bit
	// and the /56 override with junk in the fourth hextet.

	function ckcanon(input, want) {
		let r = mask_cidr(input);
		let got = (r == null) ? "bad" : sprintf("%s %s", r.changed ? "masked" : "ok", r.canonical);
		let ok = (got == want);
		if (!ok) fails++;
		printf("  [%s] canon %-24s -> %-30s want %s\n", ok ? "PASS" : "FAIL", input, got, want);
	}

	printf("\n== intake canonicalization (canon mode) ==\n");
	ckcanon("2001:db8:f000:1::/60",  "masked 2001:db8:f000::/60");
	ckcanon("2001:db8:aa00:ff::/56", "masked 2001:db8:aa00::/56");
	ckcanon("2001:db8:f000::/48",    "ok 2001:db8:f000::/48");
	ckcanon("2001:db8:abcd::/64",    "ok 2001:db8:abcd::/64");
	ckcanon("2001:db8:9:1028::/64", "ok 2001:db8:9:1028::/64");
	ckcanon("2001:db8::/129",        "bad");
	ckcanon("2001:db8::/0a",         "bad");
	ckcanon("2001:db8::",            "bad");
	ckcanon("garbage",               "bad");

	printf("\n%s (%d failure%s)\n", fails ? "OVERALL: FAIL" : "OVERALL: PASS", fails, (fails == 1) ? "" : "s");
	exit(fails ? 1 : 0);
}

// Production: a single JSON object argument { dev, pool, own, units } per the input
// contract. Drive the placement and gate, then render one typed line per result so the
// shell can push the rule lines verbatim, add the targets to the stateful floor's
// exclusion set, and warn on each unit left to the floor.

log_open("mwan3-translate-allocator");

let input = json(ARGV[0]);
if (type(input) != "object") {
	log_msg("err", "expected a JSON object argument");
	exit(1);
}

let dev = input.dev;
let res = process(input);

// Render-side guard: every accepted map's src and target base must be aligned to its
// length. Intake masking makes a misaligned base impossible by construction; if one reaches
// here it would corrupt the emitted element, so refuse the whole render (the shell then
// emits floor only) rather than install a bad rule.

for (let m in res.accepted)
	if (!aligned(m.src) || !aligned(m.target)) {
		log_msg("err", sprintf("misaligned map element %s -> %s, refusing to render", m.src, m.target));
		exit(1);
	}

// Build the snat and dnat prefix maps from the accepted set in deterministic allocator
// order. Emit nothing when the set is empty: an empty nft map literal is a syntax error, so
// suppression is a correctness requirement, and a WAN with no accepted map is carried
// entirely by the stateful floor the shell emits. The snat map keys each carried source on
// its target; the dnat map is the inverse for inbound reachability.

if (length(res.accepted) > 0) {
	let snat_map = [], dnat_map = [];
	for (let m in res.accepted) {
		push(snat_map, sprintf("%s : %s", m.src, m.target));
		push(dnat_map, sprintf("%s : %s", m.target, m.src));
	}
	printf("rule add rule inet mwan3 mwan3_snat_v6 oifname \"%s\" fib saddr type != local snat ip6 prefix to ip6 saddr map { %s }\n",
	       dev, join(", ", snat_map));
	printf("rule add rule inet mwan3 mwan3_dnat_v6 iifname \"%s\" dnat ip6 prefix to ip6 daddr map { %s }\n",
	       dev, join(", ", dnat_map));
	for (let m in res.accepted)
		printf("target %s\n", m.target);
}
for (let s in res.stateful)
	printf("stateful %s %s\n", s.src, s.reason);
for (let a in res.absorbed)
	printf("absorbed %s %s\n", a.src, a.by);

exit(0);
