'use strict';
import { readfile } from 'fs';
const source = readfile(ARGV[0] || 'files/usr/share/rpcd/ucode/mwan3');
const part = substr(source, index(source, 'function read_nftset('), index(source, 'function get_nftset_members(') - index(source, 'function read_nftset('));
const run = loadstring('return function(popen, name) {' + part + 'return read_nftset(name);};', {raw_mode:true})();
let checks = 0;
function expectFailure(data, status, name) {
 let failed = false;
 try { run(() => ({read:()=>data, close:()=>status}), name || 'fixture'); } catch(e) { failed=true; }
 assert(failed); checks++;
}
expectFailure('', 1);
expectFailure('not JSON', 0);
expectFailure('{"nftables":[]}', 0);
expectFailure('{"nftables":[{"set":{"name":"other"}}]}', 0);
expectFailure('{"nftables":[{"set":{"name":"fixture"}}]}', 1);
expectFailure('', 0, 'invalid;name');
const empty = run(() => ({read:()=>'{"nftables":[{"set":{"name":"fixture","type":"ipv6_addr"}}]}',close:()=>0}), 'fixture');
assert(empty.nftables[0].set.name == 'fixture'); checks++;
printf('%d IP set read checks passed\n', checks);
