#!/usr/bin/env ucode
'use strict';

import * as rtnl from "rtnl";

const RTM_GETROUTE = rtnl.const.RTM_GETROUTE;
const NLM_F_DUMP = rtnl.const.NLM_F_DUMP;
const AF_INET = rtnl.const.AF_INET;
const AF_INET6 = rtnl.const.AF_INET6;
const RT_TABLE_MAIN = rtnl.const.RT_TABLE_MAIN;

function is_cidr_route(route, family_num) {
	let dst = route.dst;
	if (dst == null) return false;
	let slash = index(dst, "/");
	if (slash < 0) return false;
	let prefix_len = +substr(dst, slash + 1);
	return (family_num == AF_INET) ? (prefix_len < 32) : (prefix_len < 128);
}

function is_default_route(route) {
	return (route.dst == null ||
	        route.dst == "0.0.0.0/0" ||
	        route.dst == "::/0");
}

function is_linklocal_route(route) {
	return (route.dst != null &&
	        (match(route.dst, /^fe80::\//) != null ||
	         match(route.dst, /^169\.254\./) != null));
}

let family_num = (ARGV[0] == "6") ? AF_INET6 : AF_INET;
let table_arg = ARGV[1];
let table_num = (table_arg == "main") ? RT_TABLE_MAIN : +table_arg;

let routes = rtnl.request(RTM_GETROUTE, NLM_F_DUMP, { family: family_num }) ?? [];
let seen = {};

for (let route in routes) {
	if (route.table != table_num) continue;
	if (!is_cidr_route(route, family_num)) continue;
	if (is_default_route(route)) continue;
	if (is_linklocal_route(route)) continue;
	if (family_num == AF_INET) {
		let first_octet = +split(route.dst, ".")[0];
		if (first_octet >= 224) continue;
	}
	if (seen[route.dst]) continue;
	seen[route.dst] = true;
	printf("%s\n", route.dst);
}
