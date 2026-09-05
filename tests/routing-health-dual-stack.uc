'use strict';
import { readfile } from 'fs';

// Read-only fixtures: run the shipped function without live ubus or netlink.
const source = readfile(ARGV[0] || 'files/usr/share/rpcd/ucode/mwan3');
const start = index(source, 'function routing_health() {');
const end = index(source, '\nfunction get_connected_ips(');
const run = loadstring('return function(cursor, get_ip_rules, get_table_routes, get_str, glob) {\n' +
	substr(source, start, end - start) + '\nreturn routing_health();\n};', {raw_mode: true})();
let checks = 0;
function check(ok, name) { assert(ok, name); checks++; printf('PASS %s\n', name); }
const readerStart = index(source, 'function get_ip_rules()');
const readerEnd = index(source, 'function get_table_routes(');
const readRules = loadstring('return function(popen, glob) {\n' + substr(source, readerStart, readerEnd - readerStart) + '\nreturn get_ip_rules();};', {raw_mode:true})();
const decoded = readRules(command => ({read: () => index(command, '-6') >= 0 ? '[{"priority":2502,"table":"2","src":"all","oif":"eth2"},{"priority":900,"table":"2","src":"all","dst":"2001:db8::","dstlen":32}]' : '[{"priority":2001,"table":"1","src":"all","fwmark":"0xf8000000","fwmask":"0xf8000000"},{"priority":3001,"action":"7","src":"all"}]', close: () => 0}), () => ['/fixture']);
check(decoded[0].fwmark == 4160749568 && decoded[0].table == 1 && decoded[0].src == null, 'numeric JSON preserves high-bit marks and lookup IDs');
check(decoded[1].action == 7 && decoded[2].family == 10 && decoded[2].oif == 'eth2', 'JSON retains action and IPv6 oif selector');
check(decoded[3].dst == '2001:db8::/32', 'JSON destination prefix length retained');
let failed = false;
try { readRules(() => ({read: () => 'not JSON', close: () => 1}), () => []); } catch (e) { failed = true; }
check(failed, 'failed rule read is not an empty successful report');
function report(rules, routes, enabled) {
	return run(() => ({
		get: () => null,
		foreach: (c, t, fn) => {
			fn({'.name': 'v4', family: 'ipv4'});
			fn({'.name': 'v6', family: 'ipv6', enabled: enabled});
		}
	}), () => rules, () => routes || [], () => 'online', () => ['/fixture']);
}
const valid = [
	{family: 2, priority: 1001, action: 1, table: 1, iif: 'eth1'},
	{family: 2, priority: 2001, action: 1, table: 1, fwmark: 0x100, fwmask: 0x3f00},
	{family: 2, priority: 3001, action: 7, fwmark: 0x100, fwmask: 0x3f00},
	{family: 2, priority: 3062, action: 1, table: 1, src: '192.0.2.1/32'},
	{family: 10, priority: 1002, action: 1, table: 2, iif: 'eth2'},
	{family: 10, priority: 2002, action: 1, table: 2, fwmark: 0x200, fwmask: 0x3f00},
	{family: 10, priority: 3002, action: 7, fwmark: 0x200, fwmask: 0x3f00}
];
let r = report(valid);
check(r.interfaces.v4.src_rule.present && r.interfaces.v6.src_rule == null, 'IPv4 source / IPv6 not applicable');
check(r.interfaces.v6.family == 'ipv6', 'family survives a missing default route');
check(report(valid, [], '0').interfaces.v6.status == 'disabled', 'disabled overrides stale tracker status');
for (let kind in ['iif_rule', 'fwmark_rule', 'unreach_rule']) {
	const priority = r.interfaces.v6[kind].priority;
	const wrong_family = map(valid, x => x.priority == priority ? { ...x, family: 2 } : x);
	check(!report(wrong_family).interfaces.v6[kind].present, kind + ' rejects other-family same priority');
	const wrong_type = map(valid, x => x.priority == priority ? { ...x, action: 6 } : x);
	check(!report(wrong_type).interfaces.v6[kind].present, kind + ' rejects wrong action');
	const duplicate = [...valid, { family: 10, priority: priority, action: 6 }];
	check(report(duplicate).interfaces.v6[kind].present, kind + ' finds match among duplicate priorities');
}
check(!report(map(valid, x => x.priority == 2002 ? {...x, table: 9} : x)).interfaces.v6.fwmark_rule.present, 'wrong lookup table');
check(!report(map(valid, x => x.priority == 2002 ? {...x, fwmask: 0xff} : x)).interfaces.v6.fwmark_rule.present, 'wrong fwmark namespace');
check(!report(map(valid, x => x.priority == 1002 ? {...x, iif: null, oif: 'eth2'} : x)).interfaces.v6.iif_rule.present, 'oif cannot masquerade as iif');
check(!report(map(valid, x => x.priority == 3062 ? {...x, src: null} : x)).interfaces.v4.src_rule.present, 'source selector required');
check(!report(map(valid, x => x.priority == 3062 ? {...x, inverted: true} : x)).interfaces.v4.src_rule.present, 'inverted source is not a match');
r = report(valid, [{family: 2, type: 1, dst: '0.0.0.0/0'}]);
check(r.interfaces.v4.table.has_default && !r.interfaces.v6.table.has_default, 'IPv4 default cannot satisfy IPv6');
r = report(valid, [{family: 10, type: 1, dst: '::/0'}]);
check(!r.interfaces.v4.table.has_default && r.interfaces.v6.table.has_default, 'IPv6 default cannot satisfy IPv4');
check(!report(valid, [{family: 10, type: 7}]).interfaces.v6.table.has_default, 'unreachable default is not a usable default');
check(report(valid, [{family: 10, type: 1}]).interfaces.v6.table.has_default, 'netlink implicit default');
r = report([...valid, {family: 10, priority: 2502, action: 1, table: 2, oif: 'eth2'},
	{family: 10, priority: 900, action: 1, table: 2, dst: '2001:db8::/32'}]);
check(length(r.interfaces.v6.additional_rules) == 2 && length(r.interfaces.v4.additional_rules) == 0, 'observed oif/destination rules stay in their family and table');
check(length(report(valid).interfaces.v6.additional_rules) == 0, 'no invented oif/destination rule');
r = report([...valid, {family: 10, priority: 1001, action: 1, table: 1, iif: 'old'}]);
check(length(r.stale_rules) == 1 && r.stale_rules[0].family == 'ipv6', 'other-family orphan is not hidden by IPv4 priority');
r = report([...valid, {family: 10, priority: 1001, action: 1, table: 354, fwmark: 354, fwmask: 0xffffffff}]);
check(length(r.stale_rules) == 0, 'foreign mark namespace is not a mwan3 orphan');
r = report([...valid, {family: 2, priority: 2061, action: 6, fwmark: 0x3d00, fwmask: 0x3f00}]);
check(r.global_rules[0].present && !r.global_rules[2].present, 'global blackhole checked per family');
printf('%d dual-stack checks passed\n', checks);
