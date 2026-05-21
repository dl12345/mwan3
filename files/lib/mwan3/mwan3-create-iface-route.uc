#!/usr/bin/env ucode
'use strict';

import * as rtnl from "rtnl";
import * as uci from "uci";
import * as ubus from "ubus";

const RTM_GETROUTE = rtnl.const.RTM_GETROUTE;
const RTM_NEWROUTE = rtnl.const.RTM_NEWROUTE;
const NLM_F_DUMP = rtnl.const.NLM_F_DUMP;
const NLM_F_CREATE = rtnl.const.NLM_F_CREATE;
const NLM_F_REPLACE = rtnl.const.NLM_F_REPLACE;
const RT_TABLE_MAIN = rtnl.const.RT_TABLE_MAIN;
const AF_INET = rtnl.const.AF_INET;
const AF_INET6 = rtnl.const.AF_INET6;

const ROUTE_FIELDS = ["dst", "gateway", "oif", "prefsrc", "priority",
                      "scope", "type", "tos", "metrics"];

function is_default_route(route) {
	return (route.dst == null ||
	        route.dst == "0.0.0.0/0" ||
	        route.dst == "::/0");
}

function build_route_for_table(route, tid, src_routing) {
	let r = { family: route.family, table: tid };
	for (let f in ROUTE_FIELDS)
		if (route[f] != null)
			r[f] = route[f];
	if (r.tos == 0) delete r.tos;
	if (src_routing && route.src != null)
		r.src = route.src;
	return r;
}

let family_num = (ARGV[0] == "6") ? AF_INET6 : AF_INET;
let family_name = (ARGV[0] == "6") ? "ipv6" : "ipv4";
let table_id = +ARGV[1];
let source_routing = +ARGV[2];

let cur = uci.cursor();
cur.load("mwan3");

let extra_table_set = {};
let rt_tables = cur.get("mwan3", "globals", "rt_table_lookup");
if (type(rt_tables) == "array") {
	for (let t in rt_tables)
		extra_table_set[+t] = true;
} else if (rt_tables != null) {
	extra_table_set[+rt_tables] = true;
}

let name_tid = {};
let tid = 0;
cur.foreach("mwan3", "interface", function(s) {
	tid++;
	let fam = s.family ?? "ipv4";
	let enabled = +(s.enabled ?? "1");
	if (enabled && fam == family_name)
		name_tid[s[".name"]] = tid;
});
cur.unload("mwan3");

let dev_table_map = {};
let uconn = ubus.connect();
if (uconn) {
	let dump = uconn.call("network.interface", "dump");
	if (dump && dump.interface) {
		for (let intf in dump.interface) {
			let name = intf.interface;
			let t = name_tid[name];
			if (t == null) {
				let m = match(name, /^(.+)_([46])$/);
				if (m) {
					let suffix_fam = (m[2] == "4") ? "ipv4" : "ipv6";
					if (suffix_fam == family_name)
						t = name_tid[m[1]];
				}
			}
			if (t != null && intf.l3_device)
				dev_table_map[intf.l3_device] = t;
		}
	}
	uconn.disconnect();
}

let all_routes = rtnl.request(RTM_GETROUTE, NLM_F_DUMP, { family: family_num }) ?? [];

let source_routes = [];
for (let r in all_routes) {
	if (r.table == RT_TABLE_MAIN || extra_table_set[r.table])
		push(source_routes, r);
}

let existing_keys = {};
for (let r in all_routes) {
	if (r.table != table_id) continue;
	let key = (r.dst ?? "") + "|" + (r.oif ?? "") + "|" + (r.gateway ?? "") + "|" + (r.priority ?? "");
	existing_keys[key] = true;
}

for (let route in source_routes) {
	let dev = route.oif;
	let target_tid = (dev != null) ? dev_table_map[dev] : null;

	if (is_default_route(route) || route.dst == "fe80::/64") {
		if (target_tid != table_id) continue;
	} else if (target_tid != null && target_tid != table_id) {
		continue;
	}

	let key = (route.dst ?? "") + "|" + (route.oif ?? "") + "|" + (route.gateway ?? "") + "|" + (route.priority ?? "");
	if (existing_keys[key]) continue;

	let r = build_route_for_table(route, table_id, source_routing);
	rtnl.request(RTM_NEWROUTE, NLM_F_CREATE | NLM_F_REPLACE, r);
	let err = rtnl.error();
	if (err)
		warn(sprintf("mwan3-create-iface-route: table %d: %s\n", table_id, err));
}
