'use strict';

// common.uc: the shared mwan3 ucode library, the ucode analogue of common.sh.
// Each shared ucode routine is defined here so it lives, and is tested, in one
// place.

import { openlog, syslog, LOG_PID, LOG_DAEMON } from 'log';

// ---- Logging ---------------------------------------------------------------
//
// All mwan3 ucode logs through these functions so the sink, tag format and
// verbose gate live in one place. Output goes to syslog, the same destination
// logger(1) reaches, so it appears in logread regardless of how procd handles
// the process stderr.

let verbose = false;

// Map the level names mwan3 uses (the shell's warn/error vocabulary and the
// canonical syslog names) onto the exact tokens parse_priority() accepts. It
// rejects "warn" and "error", so an unmapped name would be dropped; an unknown
// level falls back to notice so a mislabelled message still logs.

const PRIO = {
	emerg: "emerg", alert: "alert", crit: "crit",
	err: "err", error: "err",
	warn: "warning", warning: "warning",
	notice: "notice", info: "info", debug: "debug",
};

// Open the syslog connection with the given identity. LOG_PID appends the pid
// so the tag reads ident[pid], matching the shell's "${SCRIPTNAME}[$$]"
// convention. Facility daemon suits these long-running and service-invoked
// components.

function log_open(ident) {
	openlog(ident, LOG_PID, LOG_DAEMON);
}

// Set the verbose gate. The caller reads mwan3.globals.verbose_logging and
// pushes the parsed bool here; debug is suppressed unless verbose, exactly as
// common.sh:LOG() gates the debug facility behind MWAN3_VERBOSE_LOGGING.

function log_verbose(enable) {
	verbose = enable;
}

// Emit one message. debug is dropped unless verbose; every other level always
// logs. Message content is passed as a %s argument so it is never treated as a
// format string.

function log_msg(level, msg) {
	if (level == "debug" && !verbose)
		return;
	syslog(PRIO[level] ?? "notice", "%s", msg);
}

// ---- Config helpers --------------------------------------------------------

// Parse a UCI bool the way the shell's config_get_bool does: 1/on/true/yes/
// enabled are true, everything else is false. Kept here so every ucode
// consumer interprets a UCI bool identically to the shell. It reads no config
// itself, so it does not couple the module to uci.

function ucibool(val) {
	switch (val) {
	case 'yes':
	case 'on':
	case 'true':
	case 'enabled':
		return true;
	default:
		return !!int(val);
	}
}

// ---- Route classification --------------------------------------------------

// The width classifier for the bypass sweeps: a route is default-equivalent
// when its destination is absent (a literal default) or its prefix is wide
// enough that it can only exist as a component of an in-substance default
// route - /2 or wider for IPv4, /3 or wider for IPv6, which covers the
// split-half pairs VPN clients install and the 2000::/3 global-unicast
// aggregate. Each route is judged alone, so a half-installed pair is still
// excluded. The family comes from iptoarr, the inet_pton wrapper, so no
// address text is hand-parsed; a destination it cannot parse is not
// default-equivalent. The strict literal-default predicate the mirroring and
// route-state paths use is deliberately not widened and lives on beside this.

function is_default_equivalent(route) {
	let dst = route.dst;
	if (dst == null)
		return true;
	let slash = index(dst, "/");
	if (slash < 0)
		return false;
	let a = iptoarr(substr(dst, 0, slash));
	if (a == null)
		return false;
	return +substr(dst, slash + 1) <= (length(a) == 16 ? 3 : 2);
}

// ---- IPv6 prefix arithmetic ------------------------------------------------
//
// The IPv6 prefix functions shared by the 1:1 prefix-translation producers and
// the allocator: the canonical render, the CIDR and address parsers, the mask
// and alignment helpers, and the overlap and containment predicates.

// Render the top four hextets plus a prefix length to the canonical
// "h0:h1:h2:h3::/len" string. Hextets are 16-bit and always positive, so this
// is sign-safe across the whole address space; global unicast and ULA
// (fd00::/8, top bit set) render alike.

function render(h, len) {
	return sprintf("%x:%x:%x:%x::/%d", h[0], h[1], h[2], h[3], len);
}

// Split a "prefix/len" CIDR into its top four hextets and length. iptoarr is
// the inet_pton wrapper, so the address is never hand-parsed; null on a
// malformed literal, which callers treat as a skip.

function cidr_split(cidr) {
	let parts = split(cidr, "/");
	let a = iptoarr(parts[0]);
	if (a == null || length(a) != 16)
		return null;
	return {
		h: [ (a[0] << 8) + a[1], (a[2] << 8) + a[3], (a[4] << 8) + a[5], (a[6] << 8) + a[7] ],
		len: int(parts[1]),
	};
}

// The canonical /len prefix string containing a bare address. iptoarr is the
// inet_pton wrapper, so the address is never hand-parsed; null on a malformed
// literal, which callers treat as a skip.

function prefix_canon(addr, len) {
	let a = iptoarr(addr);
	if (a == null || length(a) != 16)
		return null;
	return render([ (a[0] << 8) + a[1], (a[2] << 8) + a[3], (a[4] << 8) + a[5], (a[6] << 8) + a[7] ], len);
}

// Parse a CIDR and mask it to its prefix length, returning { canonical,
// changed } or null for an invalid literal. The slash is found with
// index/substr so a bare address or an empty length is rejected, iptoarr is
// the inet_pton wrapper, and the prefix string is validated explicitly because
// int() silently accepts trailing garbage and leading zeros. IPv6 only. The
// masked bytes are rendered with arrtoip (inet_ntop), so the canonical address
// is never hand-built.

function mask_cidr(cidr) {
	let slash = index(cidr, "/");
	if (slash < 0)
		return null;
	let pfxstr = substr(cidr, slash + 1);
	if (pfxstr == "" || !match(pfxstr, /^[0-9]+$/))
		return null;
	if (length(pfxstr) > 1 && substr(pfxstr, 0, 1) == "0")
		return null;
	let len = int(pfxstr);
	let a = iptoarr(substr(cidr, 0, slash));
	if (a == null || length(a) != 16 || len > 128)
		return null;
	let m = [], changed = false;
	for (let i = 0; i < 16; i++) {
		let keep;
		if ((i + 1) * 8 <= len) keep = 0xff;
		else if (i * 8 >= len) keep = 0;
		else keep = (0xff << (8 - (len - i * 8))) & 0xff;
		let b = a[i] & keep;
		if (b != a[i]) changed = true;
		push(m, b);
	}
	return { canonical: sprintf("%s/%d", arrtoip(m), len), changed };
}

// True when a CIDR's base is already aligned to its prefix length (no host
// bits set below it). The render-side guard so a misaligned map element is
// never emitted.

function aligned(cidr) {
	let r = mask_cidr(cidr);
	return r != null && !r.changed;
}

// The top and bottom 32-bit halves of the four top hextets, as positive
// integers.

function hi32(h) { return (h[0] << 16) + h[1]; }
function lo32(h) { return (h[2] << 16) + h[3]; }

// Address-space prefix-overlap predicate: two prefixes overlap iff their top
// min(la, lb) bits agree. Lengths are in [1,64], so only the four top hextets
// matter, held in two positive 32-bit halves so global unicast and ULA (top
// bit set) compare alike.

function prefix_overlap(ha, la, hb, lb) {
	let l = (la < lb) ? la : lb;
	if (l <= 32) {
		let sh = 32 - l;
		return (hi32(ha) >> sh) == (hi32(hb) >> sh);
	}
	if (hi32(ha) != hi32(hb)) return false;
	let sh = 64 - l;
	return (lo32(ha) >> sh) == (lo32(hb) >> sh);
}

// True when child child_addr/child_len lies within parent_addr/parent_len: the
// parent is no longer than the child and the child's top parent_len bits match
// the parent's. Bytes come from iptoarr (inet_pton), so no address text is
// hand-parsed. General over any prefix length, where prefix_overlap is scoped
// to the top 64 bits.

function prefix_contains(child_addr, child_len, parent_addr, parent_len) {
	if (parent_len > child_len)
		return false;
	let c = iptoarr(child_addr), p = iptoarr(parent_addr);
	if (c == null || p == null || length(c) != 16 || length(p) != 16)
		return false;
	let full = int(parent_len / 8), rem = parent_len % 8;
	for (let i = 0; i < full; i++)
		if (c[i] != p[i])
			return false;
	if (rem > 0) {
		let mask = (0xff << (8 - rem)) & 0xff;
		if ((c[full] & mask) != (p[full] & mask))
			return false;
	}
	return true;
}

// ---- DHCPv6-PD lease traversal ----------------------------------------------

// Every downstream DHCPv6-PD sub-delegation in a dhcp ipv6leases reply, as
// { address, length } pairs. Each lease carries its IA_PD prefixes in an
// ipv6-prefix array, each entry an { address, prefix-length, ... } table; an
// entry missing either field is a single address or malformed, not a
// sub-delegation, and is skipped. Pure traversal of the passed-in reply, no
// filtering and no rendering: the discovery helpers consuming it apply
// different predicates (containment in a WAN's delegations, none, containment
// in fc00::/7), so those stay in the callers, and taking the reply as an
// argument keeps the module decoupled from ubus the way ucibool is decoupled
// from uci.

function lease_pd_entries(leases) {
	let out = [];
	let devs = (leases ?? {}).device ?? {};
	for (let dn in devs)
		for (let lease in (devs[dn].leases ?? []))
			for (let p in (lease["ipv6-prefix"] ?? [])) {
				if (p.address == null || p["prefix-length"] == null)
					continue;
				push(out, { address: p.address, length: p["prefix-length"] });
			}
	return out;
}

// ---- Exports ---------------------------------------------------------------

// The module's public interface. Declared as an export list rather than inline
// on each function, which this ucode build does not accept.

export { log_open, log_verbose, log_msg, ucibool, is_default_equivalent, render, cidr_split, prefix_canon, mask_cidr, aligned, prefix_overlap, prefix_contains, lease_pd_entries };
