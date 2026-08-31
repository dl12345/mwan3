#!/usr/bin/env ucode
'use strict';

import * as rtnl from "rtnl";
import { log_open, log_msg } from 'mwan3.common';

const RTM_GETRULE = rtnl.const.RTM_GETRULE;
const RTM_DELRULE = rtnl.const.RTM_DELRULE;
const RTM_NEWRULE = rtnl.const.RTM_NEWRULE;
const RTM_GETROUTE = rtnl.const.RTM_GETROUTE;
const RTM_GETADDR = rtnl.const.RTM_GETADDR;
const NLM_F_DUMP = rtnl.const.NLM_F_DUMP;
const NLM_F_CREATE = rtnl.const.NLM_F_CREATE;
const AF_INET = rtnl.const.AF_INET;
const AF_INET6 = rtnl.const.AF_INET6;

const FR_ACT_TO_TBL = 1;
const FR_ACT_BLACKHOLE = 6;
const FR_ACT_UNREACHABLE = 7;

function is_default_route(route) {
	return (route.dst == null ||
	        route.dst == "0.0.0.0/0" ||
	        route.dst == "::/0");
}

log_open("mwan3-manage-rules");

let mode = ARGV[0];

if (mode == "check") {
	let family_num = (ARGV[1] == "6") ? AF_INET6 : AF_INET;
	let priorities = [];
	for (let i = 2; i < length(ARGV); i++)
		push(priorities, +ARGV[i]);

	let rules = rtnl.request(RTM_GETRULE, NLM_F_DUMP, { family: family_num }) ?? [];
	let existing = {};
	for (let r in rules)
		if (r.priority != null)
			existing[r.priority] = true;

	let result = 0;
	for (let i = 0; i < length(priorities); i++)
		if (!existing[priorities[i]])
			result |= (1 << i);

	printf("%d\n", result);

} else if (mode == "check-route") {
	let family_num = (ARGV[1] == "6") ? AF_INET6 : AF_INET;
	let table_id = +ARGV[2];
	let device = ARGV[3];

	let routes = rtnl.request(RTM_GETROUTE, NLM_F_DUMP, { family: family_num }) ?? [];
	for (let r in routes) {
		if (r.table == table_id && is_default_route(r) && r.oif == device)
			exit(0);
	}
	exit(1);

} else if (mode == "delete-iface") {
	let id = +ARGV[1];
	let iif_base = +ARGV[2];
	let fwmark_base = +ARGV[3];
	let mmx_mask = +ARGV[4];
	let src_prio = +ARGV[5];
	let oif_base = +ARGV[6];

	let iif_prio = iif_base + id;
	let fwmark_prio = fwmark_base + id;
	let oif_prio = oif_base + id;

	for (let family in [AF_INET, AF_INET6]) {
		let rules = rtnl.request(RTM_GETRULE, NLM_F_DUMP, { family: family }) ?? [];

		for (let rule in rules) {
			if (rule.table != id) continue;
			if (rule.action != FR_ACT_TO_TBL) continue;

			if (rule.src != null && rule.priority == src_prio) {
				rtnl.request(RTM_DELRULE, 0, {
					family: family,
					priority: rule.priority,
					src: rule.src,
					table: rule.table,
					action: rule.action
				});
				let err = rtnl.error();
				if (err)
					log_msg("err", sprintf("delete src rule failed: %s", err));
				continue;
			}

			if (rule.src != null || rule.dst != null) continue;

			if (rule.fwmark == null && rule.priority == iif_prio) {
				rtnl.request(RTM_DELRULE, 0, {
					family: family,
					priority: rule.priority,
					table: rule.table,
					action: rule.action
				});
				let err = rtnl.error();
				if (err)
					log_msg("err", sprintf("delete iif rule failed: %s", err));
			} else if (rule.fwmark == null && rule.priority == oif_prio) {

				// The iif and oif rules are indistinguishable in the dump
				// beyond their priority, so the band each one belongs to is
				// what tells them apart.

				rtnl.request(RTM_DELRULE, 0, {
					family: family,
					priority: rule.priority,
					table: rule.table,
					action: rule.action
				});
				let err = rtnl.error();
				if (err)
					log_msg("err", sprintf("delete oif rule failed: %s", err));
			} else if (rule.fwmark != null && rule.priority == fwmark_prio && rule.fwmask == mmx_mask) {
				rtnl.request(RTM_DELRULE, 0, {
					family: family,
					priority: rule.priority,
					fwmark: rule.fwmark,
					fwmask: rule.fwmask,
					table: rule.table,
					action: rule.action
				});
				let err = rtnl.error();
				if (err)
					log_msg("err", sprintf("delete fwmark rule failed: %s", err));
			}
		}
	}

} else if (mode == "add-general") {
	let family_num = (ARGV[1] == "6") ? AF_INET6 : AF_INET;
	let bh_prio = +ARGV[2], bh_mark = +ARGV[3];
	let ur_prio = +ARGV[4], ur_mark = +ARGV[5];
	let mask = +ARGV[6];

	let rules = rtnl.request(RTM_GETRULE, NLM_F_DUMP, { family: family_num }) ?? [];
	let existing = {};
	for (let r in rules)
		if (r.priority != null)
			existing[r.priority] = true;

	if (!existing[bh_prio]) {
		rtnl.request(RTM_NEWRULE, NLM_F_CREATE, {
			family: family_num,
			priority: bh_prio,
			fwmark: bh_mark,
			fwmask: mask,
			action: FR_ACT_BLACKHOLE
		});
		let err = rtnl.error();
		if (err)
			log_msg("err", sprintf("add blackhole rule failed: %s", err));
	}

	if (!existing[ur_prio]) {
		rtnl.request(RTM_NEWRULE, NLM_F_CREATE, {
			family: family_num,
			priority: ur_prio,
			fwmark: ur_mark,
			fwmask: mask,
			action: FR_ACT_UNREACHABLE
		});
		let err = rtnl.error();
		if (err)
			log_msg("err", sprintf("add unreachable rule failed: %s", err));
	}

} else if (mode == "add-backstop") {
	let family_num = (ARGV[1] == "6") ? AF_INET6 : AF_INET;
	let prio = +ARGV[2], mark = +ARGV[3];
	let mask = +ARGV[4];

	let rules = rtnl.request(RTM_GETRULE, NLM_F_DUMP, { family: family_num }) ?? [];
	let existing = {};
	for (let r in rules)
		if (r.priority != null)
			existing[r.priority] = true;

	if (!existing[prio]) {
		rtnl.request(RTM_NEWRULE, NLM_F_CREATE, {
			family: family_num,
			priority: prio,
			fwmark: mark,
			fwmask: mask,
			action: FR_ACT_UNREACHABLE
		});
		let err = rtnl.error();
		if (err)
			log_msg("err", sprintf("add backstop rule failed: %s", err));
	}

} else if (mode == "add-src") {
	// IPv4 only

	let device = ARGV[1];
	let table_id = +ARGV[2];
	let prio = +ARGV[3];

	let addrs = rtnl.request(RTM_GETADDR, NLM_F_DUMP, { family: AF_INET }) ?? [];
	for (let a in addrs) {
		if (a.dev != device) continue;
		if (a.scope != 0) continue;
		let addr = split(a.local ?? a.address ?? "", "/")[0];
		if (!addr) continue;
		rtnl.request(RTM_NEWRULE, NLM_F_CREATE, {
			family: AF_INET,
			priority: prio,
			src: addr,
			table: table_id,
			action: FR_ACT_TO_TBL
		});
		let err = rtnl.error();
		if (err)
			log_msg("err", sprintf("add src rule failed: %s", err));
	}
}
