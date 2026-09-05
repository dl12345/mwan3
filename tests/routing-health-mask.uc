'use strict';

import { readfile } from 'fs';

// Run from the repository root:
//   ucode tests/routing-health-mask.uc [path/to/rpcd/mwan3]
// Exercise the shipped function, not a duplicate implementation. Only that
// function is compiled, with read-only fixtures replacing UCI, rtnl and /var.
// No live ubus connection, configuration changes or kernel writes occur.
const path = ARGV[0] || 'files/usr/share/rpcd/ucode/mwan3';
const source = readfile(path);
assert(source != null, 'Cannot read ' + path);
const start = index(source, 'function routing_health() {');
const end = index(source, '\nfunction get_connected_ips(');
assert(start >= 0 && end > start, 'Cannot locate routing_health()');
const run = loadstring(
	'return function(cursor, get_ip_rules, get_table_routes, get_str, glob) {\n' +
	'const ubus = {call: () => ({interface:map(["wan_a","wan_b","wan_c","wan_a6"], n=>({interface:n,l3_device:"fixture"}))})}; const rtnl = {const:{},request:()=>[]};\n' +
	substr(source, start, end - start) + '\nreturn routing_health();\n};',
	{ raw_mode: true }
)();

let checks = 0;
function check(condition, message) {
	assert(condition, message);
	checks++;
}

function verify(name, mask, maxmark, bases) {
	const b = bases || { iif: 1000, fwmark: 2000, unreach: 3000 };
	const iface_max = maxmark - 3;
	const src_base = b.unreach + iface_max + 1;
	const interfaces = [
		{ '.name': 'wan_a', family: 'ipv4' },
		{ '.name': 'wan_b', family: 'ipv4' },
		{ '.name': 'wan_c', family: 'ipv4' },
		{ '.name': 'wan_a6', family: 'ipv6' }
	];
	const globals = {
		mmx_mask: mask,
		iif_rule_base: '' + b.iif,
		fwmark_rule_base: '' + b.fwmark,
		unreachable_rule_base: '' + b.unreach
	};
	const rules = [];
	const parsed_mask = int(mask, 0) || 0x3F00;
	function encoded(id) {
		let value = 0, bit = 0;
		for (let pos = 0; pos < 32; pos++)
			if ((parsed_mask >> pos) & 1) {
				if ((id >> bit) & 1) value |= 1 << pos;
				bit++;
			}
		return value;
	}
	for (let i = 0; i < length(interfaces); i++) {
		const family = interfaces[i].family == 'ipv6' ? 10 : 2;
		push(rules, { family: family, priority: b.iif + i + 1, action: 1, table: i + 1, iif: 'fixture' });
		push(rules, { family: family, priority: b.fwmark + i + 1, action: 1, table: i + 1, fwmark: encoded(i + 1), fwmask: parsed_mask });
		push(rules, { family: family, priority: b.unreach + i + 1, action: 7, fwmark: encoded(i + 1), fwmask: parsed_mask });
		if (family == 2)
			push(rules, { family: family, priority: src_base + i + 1, action: 1, table: i + 1, src: '192.0.2.' + (i + 1) + '/32' });
	}
	for (let family in [2, 10]) {
		push(rules, { family: family, priority: b.fwmark + maxmark - 2 });
		push(rules, { family: family, priority: b.fwmark + maxmark - 1 });
	}
	// An actually unassigned priority must remain visible to the diagnostic.
	const orphan = b.iif + 7;
	push(rules, { family: 2, priority: orphan });
	const report = run(
		() => ({
			get: (config, section, option) => globals[option],
			foreach: (config, section, cb) => { for (let iface in interfaces) cb(iface); }
		}),
		() => rules,
		id => [{ family: id == 4 ? 10 : 2, oif: 'fixture', type: 1 }],
		() => 'online',
		() => ['/fixture/STATUS']
	);
	check(report.rule_bases.src == src_base, name + ': source base');
	for (let i = 0; i < 3; i++) {
		const info = report.interfaces[interfaces[i]['.name']];
		check(info.src_rule.priority == src_base + i + 1, name + ': source priority');
		check(info.src_rule.present, name + ': existing source rule not found');
		check(info.iif_rule.present && info.fwmark_rule.present && info.unreach_rule.present,
			name + ': unchanged interface rules');
	}
	check(report.interfaces.wan_a6.src_rule == null, name + ': no IPv6 source rule');
	check(length(report.stale_rules) == 1 && report.stale_rules[0].priority == orphan,
		name + ': valid source/global rules misreported or orphan hidden');
	printf('PASS %s\n', name);
}

verify('five-bit hexadecimal mask', '0x1F000000', 31);
verify('lowercase hexadecimal mask', '0x1f000000', 31);
verify('uppercase prefix', '0X1F000000', 31);
verify('equivalent decimal mask', '520093696', 31);
verify('high-bit mask', '0xF8000000', 31);
verify('default hexadecimal mask', '0x3F00', 63);
verify('omitted mask keeps default', null, 63);
verify('empty mask keeps default', '', 63);
verify('zero mask keeps default', '0', 63);
verify('invalid mask keeps default', 'invalid', 63);
verify('custom priority bases', '0x1F000000', 31, { iif: 1100, fwmark: 2200, unreach: 4400 });
printf('%d routing-health checks passed\n', checks);
