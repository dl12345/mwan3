#!/usr/bin/env ucode
'use strict';

import * as rtnl from "rtnl";

const RTM_GETADDR = rtnl.const.RTM_GETADDR;
const NLM_F_DUMP = rtnl.const.NLM_F_DUMP;
const AF_INET = rtnl.const.AF_INET;
const AF_INET6 = rtnl.const.AF_INET6;

let family_num = (ARGV[0] == "6") ? AF_INET6 : AF_INET;
let device = ARGV[1];
let prefix = ARGV[2];

let addrs = rtnl.request(RTM_GETADDR, NLM_F_DUMP, { family: family_num }) ?? [];

let result = null;

if (device != null && device != "" && prefix == null) {
	for (let a in addrs) {
		if (a.dev != device) continue;
		let addr = split(a.local ?? a.address ?? "", "/")[0];
		if (!addr) continue;
		if (family_num == AF_INET6) {
			if (match(addr, /^fe80:/)) continue;
			if (a.scope != 0) continue;
		} else {
			if (a.scope != 0 && a.scope != 253) continue;
		}
		result = addr;
		break;
	}
} else if ((device == null || device == "") && prefix != null) {
	let pfx = prefix + ":";
	for (let a in addrs) {
		let addr = split(a.local ?? a.address ?? "", "/")[0];
		if (!addr) continue;
		if (a.scope != 0) continue;
		if (substr(addr, 0, length(pfx)) == pfx) {
			result = addr;
			break;
		}
	}
}

if (result != null) {
	printf("%s\n", result);
	exit(0);
} else {
	exit(1);
}
