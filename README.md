# mwan3 nftables User and Developer Reference
### mwan3 version: 3.5.2
Covers the nftables port of the mwan3 multi-WAN policy routing framework.

---

## Contents

1. [Architecture Overview](#1-architecture-overview)
2. [The Mark Bitmask System](#2-the-mark-bitmask-system)
3. [table inet mwan3 Architecture](#3-table-inet-mwan3-architecture)
4. [Packet Flow Through Chains](#4-packet-flow-through-chains)
5. [File Reference](#5-file-reference)
   - 5.1 [mwan3-skeleton.nft](#51-libmwan3mwan3-skeletonnft-static)
   - 5.2 [common.sh](#52-libmwan3commonsh)
   - 5.3 [mwan3.sh](#53-libmwan3mwan3sh)
   - 5.4 [init.d/mwan3](#54-etcinitdmwan3)
   - 5.5 [25-mwan3 - hotplug](#55-etchotplugdiface25-mwan3)
   - 5.6 [usr/sbin/mwan3 - CLI](#56-usrsbinmwan3-cli)
   - 5.7 [mwan3rtmon](#57-usrsbinmwan3rtmon)
   - 5.8 [rpcd/ucode/mwan3](#58-usrsharerpcducodemwan3)
   - 5.9 [Makefile](#59-makefile)
   - 5.10 [mwan3track](#510-usrsbinmwan3track)
   - 5.11 [mwan3-lb-test](#511-usrsbinmwan3-lb-test)
   - 5.12 [mwan3-diag](#512-usrsbinmwan3-diag)
6. [Function Reference](#6-function-reference)
   - 6.1 [common.sh Functions](#61-commonsh-functions)
   - 6.2 [Set Management Functions](#62-set-management-functions)
   - 6.3 [General Rule Setup](#63-general-rule-setup)
   - 6.4 [Interface Management](#64-interface-management)
   - 6.5 [Policy & Load Balancing](#65-policy--load-balancing)
   - 6.6 [Sticky Routing](#66-sticky-routing)
   - 6.7 [User Rules](#67-user-rules)
   - 6.8 [User-defined nft Set Management](#68-user-defined-nft-set-management)
   - 6.9 [Status Reporting](#69-status-reporting)
   - 6.10 [Lifecycle & Hotplug](#610-lifecycle--hotplug)
7. [Load Balancing with numgen](#7-load-balancing-with-numgen)
8. [Sticky Routing Detail](#8-sticky-routing-detail)
9. [Service Lifecycle](#9-service-lifecycle)
10. [Atomic Non-destructive Reload](#10-atomic-non-destructive-reload)
11. [User-defined nft Sets](#11-user-defined-nft-sets)
12. [Unchanged Files](#12-unchanged-files)
13. [Diagnostic Commands](#13-diagnostic-commands)
14. [luci-app-mwan3 Changes](#14-luci-app-mwan3-changes)
    - 14.1 [rule.js - Rule Editor UI](#141-rulejs---rule-editor-ui)
    - 14.2 [luci-mwan3 - Helper Script](#142-luci-mwan3---helper-script)
    - 14.3 [luci-app-mwan3.json - ACL Permissions](#143-luci-app-mwan3json---acl-permissions)
    - 14.4 [interface.js - Interface Settings UI](#144-interfacejs---interface-settings-ui)
15. [Iptables-to-nftables Porting Notes](#15-iptables-to-nftables-porting-notes)
16. [Enhancements](#16-enhancements)
    - 16.1 [Selective Conntrack Flush on Interface Down](#161-selective-conntrack-flush-on-interface-down)
    - 16.2 [Software Flow Offloading Co-existence](#162-software-flow-offloading-co-existence)
    - 16.3 [Automatic Gateway Tracking - track_gateway](#163-automatic-gateway-tracking-track_gateway)
    - 16.4 [Postrouting SNAT for Rerouted Router-Originated Traffic - IPv4](#164-postrouting-snat-for-rerouted-router-originated-traffic-ipv4)
    - 16.5 [Opt-in IPv6 SNAT via Per-Interface snat6](#165-opt-in-ipv6-snat-via-per-interface-snat6)
    - 16.6 [Tabs: Simulator, Configuration Checker, Routing Health and IP Sets](#166-tabs-simulator-configuration-checker-routing-health-and-ip-sets)
    - 16.7 [mwan3-lb-test: Load Balancing Distribution Verifier](#167-mwan3-lb-test-load-balancing-distribution-verifier)
    - 16.8 [Source NFT Set Matching - ipset_src](#168-source-nft-set-matching-ipset_src)
    - 16.9 [mwan3-diag: Network Diagnostic Report](#169-mwan3-diag-network-diagnostic-report)
17. [Changelog](#17-changelog)
    - 17.1 [Version 3.5.2](#171-version-352)
    - 17.2 [Version 3.5.1](#172-version-351)
    - 17.3 [Version 3.5](#173-version-35)
    - 17.4 [Version 3.4.1 (Unreleased)](#174-version-341-unreleased) 
    - 17.5 [Version 3.4](#175-version-34)
    - 17.6 [Version 3.3.5](#176-version-335)
    - 17.7 [Version 3.3.4](#177-version-334)
    - 17.8 [Version 3.3.3](#178-version-333)
    - 17.9 [Version 3.3.2](#179-version-332)
    - 17.10 [Version 3.3.1](#1710-version-331)
    - 17.11 [Version 3.3](#1711-version-33)
    - 17.12 [Version 3.2.3](#1712-version-323)
    - 17.13 [Version 3.2.2](#1713-version-322)
    - 17.14 [Version 3.2.1](#1714-version-321)
    - 17.15 [Version 3.2](#1715-version-32)
    - 17.16 [Version 3.1.4](#1716-version-314)
    - 17.17 [Version 3.1.3](#1717-version-313)
    - 17.18 [Version 3.1.2](#1718-version-312)
    - 17.19 [Version 3.1.1](#1719-version-311)

---

## 1. Architecture Overview

mwan3 is OpenWrt's multi-WAN policy routing framework. It classifies packets using **firewall marks**, then uses `ip rule` entries to route marked packets through per-interface routing tables. The nftables port replaces all iptables/ipset usage with nftables equivalents while keeping the ip rule/route management largely unchanged. `mwan3rtmon` is ported to a ucode implementation.

### Key Design Decisions

- **Own standalone table** - mwan3 lives in `table inet mwan3`, completely independent of `table inet fw4`. fw4 reload, restart, or reconfiguration has no effect on mwan3 rules.
- **Static skeleton + dynamic rules** - `mwan3-skeleton.nft` defines empty sets and chains loaded by `nft -f` at service start using the atomic table-replace idiom. All rules are added dynamically by shell scripts since they depend on the configurable `MMX_MASK`.
- **Hook priority `mangle + 1`** - `mwan3_prerouting` and `mwan3_output` register at priority `-149`, placing them after fw4's mangle chains and any other packages registering at `-150`. Mark operations use masked OR-immediate setter chains via vmap-dispatch so they are non-destructive with respect to bits owned by other packages regardless of execution order.
- **Non-destructive mark save/restore** - Connmark save and restore are masked to mwan3's own bit-range (`MMX_MASK`) and never touch bits owned by other packages. The kernel rejects compound two-source bitwise expressions; mwan3 synthesises masked save/restore through a vmap-dispatch technique built from per-mark OR-immediate setter chains. See [Section 2 - Connmark Operations](#connmark-operations).
- **inet family** - Chains handle both IPv4 and IPv6 in a single pass. Sets remain type-specific (separate v4/v6 sets) since nftables requires a single address type per set.
- **Atomic non-destructive reload** - `reload_service` rebuilds the entire mwan3 ruleset in a single `nft -f` batch while the old ruleset serves traffic, committing atomically with zero downtime window. See [Section 10](#10-atomic-non-destructive-reload).
- **User-defined nft sets** - `config ipset` sections in `/etc/config/mwan3` create named nft sets in `table inet mwan3` supporting inline entries, file loading, and dnsmasq domain population. See [Section 11](#11-user-defined-nft-sets).

### Component Map

```diagram
                 UCI Config (/etc/config/mwan3)
                          |
           +--------------+--------------+
           |                             |
     init.d/mwan3                   mwan3track
    (service lifecycle)           (health probes)
           |                             |
+----------+----------+          writes STATUS files
|          |          |          to /var/run/mwan3track/
v          v          v
common.sh  mwan3.sh  mwan3-skeleton.nft
(helpers)  (engine)  (static skeleton, own table)
|          |
v          v
nft tool   ip tool
|          |
v          v
table inet mwan3    ip rule / ip route
(in-kernel)         (in-kernel)

Hotplug:       25-mwan3                      --calls-->   mwan3.sh functions
Hotplug user:  26-mwan3-user                 --calls-->   /etc/mwan3.user
CLI:           /usr/sbin/mwan3               --calls-->   mwan3.sh functions
RPC:           rpcd/ucode/mwan3              --calls-->   nft -j (JSON output)
Rtmon:         mwan3rtmon                    --uses-->    ucode-mod-rtnl (netlink) + nft
dnsmasq:       mwan3_write_dnsmasq_fragments --writes-->  confdir nftset fragments
```

---

## 2. The Mark Bitmask System

mwan3 uses a configurable bitmask (`MMX_MASK`, default `0x3F00`) within the 32-bit packet mark to encode routing decisions. The mask determines how many interfaces can be supported and which mark values are reserved.

### Mark Layout (default 0x3F00)

| Bits | Mask | Owner | Purpose |
|------|------|-------|---------|
| 0-7 | `0x000000FF` | free | - |
| 8-13 | `0x00003F00` | mwan3 | interface/policy marks |
| 14-15 | `0x0000C000` | free | - |
| 16-23 | `0x00FF0000` | pbr | policy routing marks |
| 24-31 | `0xFF000000` | free | - |

| Value | Meaning | With 0x3F00 |
|---|---|---|
| 0 | Unmarked (needs classification) | `0x0000` |
| 1 .. N | Interface marks (N = max interfaces) | `0x0100` .. depends on mask |
| mmdefault-2 | MM_BLACKHOLE | Routes to blackhole |
| mmdefault-1 | MM_UNREACHABLE | Routes to unreachable |
| mmdefault (all bits set) | MMX_DEFAULT (= MMX_MASK) | `0x3F00` = use default routing |

### Bit Spreading: `mwan3_id2mask()`

Interface IDs (sequential integers 1, 2, 3...) are mapped onto the mask bits using `mwan3_id2mask()`. This "spreads" the ID's bits into only the positions where the mask has a 1-bit. For example, with mask `0x3F00`:

```
Interface 1 (binary 000001) -> 0x0100   (bit 8 set)
Interface 2 (binary 000010) -> 0x0200   (bit 9 set)
Interface 3 (binary 000011) -> 0x0300   (bits 8+9)
Interface 5 (binary 000101) -> 0x0500   (bits 8+10)
```

### nftables Mark Manipulation

The iptables operation `-j MARK --set-xmark VALUE/MASK` means `mark = (mark & ~MASK) | VALUE`. In nftables this becomes:

```
meta mark set meta mark & COMPLEMENT | VALUE
```

where `COMPLEMENT = ~MASK & 0xFFFFFFFF`. The helper `mwan3_nft_mark_expr()` generates this expression.

> [!WARNING]
> **Operator syntax:** Always use the `&` and `|` *symbols*, not the `and`/`or` keywords. The nft parser treats keywords ambiguously after expressions like `meta mark set ct mark` - it cannot tell if `and` starts a new match or a bitwise operation. Symbols are unambiguous.

### Connmark Operations

mwan3's connmark save and restore are scoped to its own bit-range (`MMX_MASK`) so that mark bits owned by other packages are never disturbed in either direction.

The natural nftables expression for a masked restore would be:

```
meta mark set (meta mark & ~MMX_MASK) | (ct mark & MMX_MASK)
```

The kernel rejects this with "Operation not supported": an nft set-statement can reference at most one runtime source register on its right-hand side.

#### vmap-dispatch save/restore

mwan3 synthesises the masked-restore and masked-save from a primitive the kernel does allow: OR-ing a *literal immediate* into a single register.

```
meta mark set meta mark | <constant>     # non-destructive: only sets bits, never clears
ct mark   set ct   mark | <constant>     # same on the conntrack side
```

The runtime source value is bridged to the constant immediate via a verdict map (`vmap`) that dispatches on the masked source bits into per-mark setter chains:

```
# Restore: copy mwan3 bits from ct mark into meta mark, non-destructively
meta mark & MMX_MASK == 0 ct mark & MMX_MASK vmap {
    0x0100 : jump mwan3_or_meta_0x100,
    0x0200 : jump mwan3_or_meta_0x200,
    ...
    0x3f00 : jump mwan3_or_meta_0x3f00
}

chain mwan3_or_meta_0x0100 { meta mark set meta mark | 0x0100 ; return }
chain mwan3_or_meta_0x0200 { meta mark set meta mark | 0x0200 ; return }
...

# Save: same trick, opposite direction
ct mark set ct mark & MMX_MASK_COMPLEMENT     # clear ONLY mwan3 bits in ct mark
meta mark & MMX_MASK vmap {
    0x0100 : jump mwan3_or_ct_0x0100,
    ...
}

chain mwan3_or_ct_0x0100 { ct mark set ct mark | 0x0100 ; return }
...
```

**Properties:**

- **Restore** is purely additive (`meta mark | <imm>`); bits in meta mark not owned by mwan3 are preserved across restore.
- **Save** clears only mwan3's own bits (`ct mark & MMX_MASK_COMPLEMENT`, where `MMX_MASK_COMPLEMENT = ~MMX_MASK & 0xFFFFFFFF`) before OR-ing the new value in. Bits in ct mark owned by other packages survive the save unchanged.
- The dispatch tables are bounded: with the default `MMX_MASK = 0x3F00`, there are 63 possible non-zero mwan3 mark values, so 63 setter chains per direction (126 total). All chains are 2-statement skeletons (`meta/ct mark set ... | <imm>` + `return`).
- The technique is *order-independent*: whether mwan3's hook fires before or after another package's hook in the prerouting stack, both packages' mark bits arrive at the routing decision intact.

**Why this works where a direct expression does not:** the kernel constraint is on the expression, not the control flow. The kernel will not let one rule combine two register sources, but it will happily let a vmap dispatch on a runtime register value into a chain whose body uses a literal immediate. The dispatch chain materialises at runtime exactly the value you wanted to OR, baked into a constant when the mwan3 init scripts emit the rule.

**Cost:** chain count, not packet-path overhead. Each packet traverses one extra `vmap` lookup (O(log) in the kernel's set lookup) and one extra `jump`/`return` per save and per restore. The 126 setter chains add no fast-path cost - they are visited via constant-time dispatch, and most never fire on any given packet.

> [!NOTE]
> Compound two-source bitwise set expressions are rejected by the kernel. vmap-dispatch is built from primitives that are permitted and does not require any new kernel capability.

---

## 3. table inet mwan3 Architecture

mwan3 operates in its own standalone nftables table, `table inet mwan3`. This table is completely independent of fw4: fw4 reloads, restarts, and reconfiguration do not affect it. The table is created at service start from `mwan3-skeleton.nft` using the atomic table-replace idiom, and torn down at service stop.

### Static Objects (from mwan3-skeleton.nft)

| Object | Type | Purpose |
|---|---|---|
| `mwan3_connected_v4` | set (ipv4_addr, interval, auto-merge) | Directly connected IPv4 networks |
| `mwan3_connected_v6` | set (ipv6_addr, interval, auto-merge) | Directly connected IPv6 networks |
| `mwan3_custom_v4` | set (ipv4_addr, interval, auto-merge) | Networks from routing tables in UCI `globals.rt_table_lookup` |
| `mwan3_custom_v6` | set (ipv6_addr, interval, auto-merge) | Networks from routing tables in UCI `globals.rt_table_lookup` |
| `mwan3_dynamic_v4` | set (ipv4_addr, interval, auto-merge) | IPv4 CIDRs from UCI `globals.bypass_network` |
| `mwan3_dynamic_v6` | set (ipv6_addr, interval, auto-merge) | IPv6 CIDRs from UCI `globals.bypass_network` |
| `mwan3_prerouting` | chain (filter, prerouting, mangle+1) | Entry point for forwarded/incoming traffic |
| `mwan3_output` | chain (route, output, mangle+1) | Entry point for locally-originated traffic |
| `mwan3_postrouting` | chain (nat, postrouting, srcnat-1) | Opt-in IPv6 SNAT for router-originated rerouted traffic - see [§16.5](#165-opt-in-ipv6-snat-via-per-interface-snat6) |
| `mwan3_ifaces_in` | chain (regular) | Dispatches to per-interface chains |
| `mwan3_rules` | chain (regular) | User-defined classification rules |
| `mwan3_connected` | chain (regular) | Marks traffic to connected networks as default |
| `mwan3_custom` | chain (regular) | Marks traffic to custom-table networks as default |
| `mwan3_dynamic` | chain (regular) | Marks traffic to dynamic networks as default |

> [!NOTE]
> **auto-merge flag:** All sets include the `auto-merge` flag in addition to `interval`. This allows nftables to merge overlapping elements (e.g., a host address and a containing CIDR) automatically, preventing insertion failures. The `nft add set` command is idempotent for creation but does *not* update flags on existing sets - `mwan3_ensure_nft_framework()` deletes and recreates the six internal sets at startup to guarantee the flag is present.

### Dynamic Objects (created at runtime, in table inet mwan3)

| Object Pattern | Type | Created By |
|---|---|---|
| `mwan3_iface_in_<name>` | chain | `mwan3_create_iface_nft()` |
| `mwan3_policy_<name>` | chain | `mwan3_create_policies_nft()` |
| `mwan3_rule_<name>` | chain | `mwan3_set_user_nft_rule()` (sticky rules only) |
| `mwan3_or_meta_<mark>` | chain (×63 with default `MMX_MASK`) | `mwan3_build_or_chains_nft()` - non-destructive restore setter chains |
| `mwan3_or_ct_<mark>` | chain (×63 with default `MMX_MASK`) | `mwan3_build_or_chains_nft()` - non-destructive save setter chains |
| `mwan3_sticky_v4_<rule>_<id>` | set (ipv4_addr, timeout) | `mwan3_set_user_nft_rule()` - one set per policy member (id = interface id) |
| `mwan3_sticky_v6_<rule>_<id>` | set (ipv6_addr, timeout) | `mwan3_set_user_nft_rule()` - one set per policy member (id = interface id) |
| `<name>` (user-defined) | set (ipv4_addr or ipv6_addr, interval, auto-merge) | `mwan3_render_config_ipsets()` from `config ipset` UCI sections |

> [!NOTE]
> **Why `type route` for output?** The output chain uses `type route` (not `type filter`) because changing a packet's mark on locally-originated traffic must trigger a routing re-lookup. This matches fw4's own `mangle_output` chain type.

> [!NOTE]
> **`fw4 reload` is a non-event for mwan3.** `fw4 reload` rewrites only `table inet fw4`. `table inet mwan3` is untouched. No recovery, detection, or rebuild is needed on `fw4 reload`.

---

## 4. Packet Flow Through Chains

The same logical flow applies to both `mwan3_prerouting` and `mwan3_output`, with one difference: prerouting includes an IPv6 RA bypass at the top.

```
Packet enters mwan3_prerouting (or mwan3_output)
  |
  |-- [prerouting only] ICMPv6 RA/NS/NA/redirect? --> ACCEPT (bypass)
  |
  |-- mark & MMX_MASK == 0?
  |     |
  |     +-- YES: Restore mwan3 bits from conntrack via vmap-dispatch
  |     |        (ct mark & MMX_MASK -> jump mwan3_or_meta_<mark>;
  |     |         non-destructive - preserves non-mwan3 bits in meta mark)
  |     |
  |     +-- Still mark == 0?
  |           |
  |           +-- jump mwan3_ifaces_in
  |           |     Per-interface chains check source address:
  |           |       - src in connected/custom/dynamic? -> mark = MMX_DEFAULT
  |           |       - otherwise -> mark = interface mark
  |           |
  |           +-- [prerouting only] Still mark == 0? fib daddr type local? --> RETURN
  |           |
  |           +-- Still mark == 0?
  |           |     jump mwan3_custom    (dst in custom sets? -> MMX_DEFAULT)
  |           |     jump mwan3_connected (dst in connected?   -> MMX_DEFAULT)
  |           |     jump mwan3_dynamic   (dst in dynamic?     -> MMX_DEFAULT)
  |           |
  |           +-- Still mark == 0?
  |                 jump mwan3_rules     (user classification rules)
  |                   -> jump to policy chain / set mark directly
  |
  |-- Save mwan3 bits to conntrack via vmap-dispatch:
  |     ct mark &= MMX_MASK_COMPLEMENT          (clear only mwan3 bits)
  |     meta mark & MMX_MASK -> jump mwan3_or_ct_<mark>
  |     (non-destructive - preserves non-mwan3 bits in ct mark)
  |
  |-- mark & MMX_MASK != MMX_DEFAULT?
  |     (Traffic that got a specific interface mark, not "default")
  |     Re-check against custom/connected/dynamic destinations
  |     This allows connected-destination traffic to be overridden
  |     back to default routing even if it was marked by user rules
  |
  +-- ACCEPT (policy accept; packet continues to routing decision)
```

### The Three Bypass Set Groups

mwan3 maintains three parallel groups of destination-bypass sets. Each group has a v4 and v6 set, a corresponding regular chain (jumped from both `mwan3_prerouting` and `mwan3_output`), and matching rules in every `mwan3_iface_in_*` chain. They differ only in how their sets are populated:

| Set group | Populated by | Source |
|---|---|---|
| `mwan3_connected_v4/v6` | `mwan3rtmon` (continuous) and `mwan3_set_connected_sets()` at startup | CIDR routes in the kernel's main routing table |
| `mwan3_custom_v4/v6` | `mwan3_set_custom_sets()` at startup | Prefixes from routing tables listed in UCI `globals.rt_table_lookup` |
| `mwan3_dynamic_v4/v6` | `mwan3_set_dynamic_sets()` at startup; also writable at runtime via `nft add element` | UCI `globals.bypass_network` CIDR list |

Each group appears in **two distinct contexts** with different match directions:

**Destination match - `mwan3_connected` / `mwan3_custom` / `mwan3_dynamic` chains:**
These chains are jumped from `mwan3_prerouting` and `mwan3_output` before the user rules chain. Rules match `ip daddr @set` / `ip6 daddr @set`. If the packet's destination falls in one of the sets, the packet is stamped `MMX_DEFAULT` (mwan3 mark bits cleared to zero) and returned - the user rules chain is never reached. Traffic destined for directly-connected, custom-table, or explicitly listed bypass networks is not policy-routed.

**Source match - `mwan3_iface_in_*` chains:**
Each per-interface chain includes source-match rules against all three set groups (`ip saddr @set`, scoped to the interface's address family). If an inbound WAN packet's source address is in any of the sets, it is stamped `MMX_DEFAULT`. Traffic arriving on a WAN interface from a connected or bypassed address does not get the WAN's interface mark, so replies to it use the main routing table rather than the WAN-specific policy route.

### Per-Interface Chain Detail

Each `mwan3_iface_in_<name>` chain handles packets arriving on a specific WAN device:

1. **`iifname` and `meta nfproto` match** - only processes packets arriving on the correct physical device and address family. The `meta nfproto ipv4`/`meta nfproto ipv6` guard is critical when two mwan3 interfaces share the same physical device (e.g. dual-stack PPPoE): without it, an IPv4 interface's catchall would misclassify incoming IPv6 packets.

2. **Source in bypass sets → `MMX_DEFAULT`** - if the arriving packet's source is in `mwan3_connected_v4/v6`, `mwan3_custom_v4/v6`, or `mwan3_dynamic_v4/v6`, the packet is marked `MMX_DEFAULT`. This connection will use the main routing table for replies rather than being pinned to this WAN's policy route.

3. **Otherwise → interface mark** - the packet is stamped with the interface's unique fwmark. The conntrack save step in the calling prerouting/output chain then records this mark so subsequent packets in the same connection have their mark restored from ct mark.

4. **Address-family-scoped catchall** - the rule that marks unmatched packets with the interface fwmark carries a `meta nfproto` guard matching the interface's configured family, completing the dual-stack isolation begun in step 1.

---

## 5. File Reference

### 5.1 `lib/mwan3/mwan3-skeleton.nft` [static]

The static nftables skeleton file. Loaded by `start_service()` via `nft -f /lib/mwan3/mwan3-skeleton.nft` before any dynamic rule installation. Uses the canonical atomic table-replace idiom:

```
table inet mwan3
delete table inet mwan3
table inet mwan3 { ... }
```

The three statements execute as one atomic `nft -f` transaction: the first ensures the table exists so the delete can succeed, the second wipes it, and the third recreates it fresh. This is idempotent: safe to run whether the table already exists or not.

Defines 6 named sets (all empty, `flags interval` and `auto-merge`) and 8 skeleton chains (all empty). No rules are present - all rules are added dynamically because they depend on the configurable `MMX_MASK` value.

The hook chains:

- `mwan3_prerouting` - type `filter` at priority `mangle + 1`
- `mwan3_output` - type `route` at priority `mangle + 1` (`type route` is required so mark mutations trigger a routing re-lookup for locally-originated traffic)
- `mwan3_postrouting` - type `nat` at priority `srcnat - 1`. Opt-in IPv6 SNAT chain. See [§16.5](#165-opt-in-ipv6-snat-via-per-interface-snat6).

### 5.2 `lib/mwan3/common.sh`

Shared helper library sourced by all mwan3 shell scripts. Provides:

- **Tool variables**: `$IP4`, `$IP6`, `$NFT`
- **IPv6 detection**: Checks `/proc/sys/net/ipv6` existence (instead of the old `command -v ip6tables`)
- **MWAN3_BATCH_DEPTH counter**: Integer depth counter (default 0). `mwan3_nft_batch_start` increments it, truncating the batch file only at depth 0->1. `mwan3_nft_batch_commit` decrements it, committing to the kernel only at depth 1->0. `mwan3_nft_exec` routes to `mwan3_nft_push` when depth > 0, accumulating all operations into the global batch.
- **MWAN3_NEED_DNSMASQ_HUP flag**: integer flag that gets set to 1 if a user nft set has been deleted and recreated as a result of a change to one of the flags. After `mwan3_write_dnsmasq_fragments`, if the flag is set then a call will be made to `mwan3_dnsmasq_hup()`.
- **Batch file**: Per-process temp file `/tmp/mwan3_nft_batch.$$` (PID-scoped, avoids conflicts between concurrent mwan3 instances).
- **nft batch helpers**: `mwan3_nft_batch_start()`, `mwan3_nft_push()`, `mwan3_nft_batch_commit()`
- **`mwan3_nft_reload_start()`**: Opens the outermost batch level (depth 0->1), then writes a preamble that (1) flushes all 8 skeleton chains, (2) two-pass flush+delete all dynamic chains (`mwan3_iface_in_*`, `mwan3_policy_*`, `mwan3_rule_*`, `mwan3_or_meta_*`, `mwan3_or_ct_*`), (3) deletes the 6 internal mwan3 sets so `mwan3_ensure_nft_framework` can recreate them. User-defined sets and sticky sets are never in the delete path.
- **`mwan3_nft_reload_commit()`**: Thin wrapper around `mwan3_nft_batch_commit`. At depth 1->0 this commits the entire accumulated batch atomically. On failure the kernel rolls back and the old ruleset continues serving.
- **`mwan3_nft_exec()`**: Wrapper that runs `nft` commands with error logging; routes to `mwan3_nft_push` when `MWAN3_BATCH_DEPTH > 0`.
- **`mwan3_nft_mark_expr()`**: Generates nftables mark-set expressions equivalent to iptables `--set-xmark`. Outputs `meta mark set meta mark & COMPLEMENT | VALUE` using `&`/`|` symbols (not `and`/`or` keywords).
- **`mwan3_ensure_nft_framework()`**: Guarantees all mwan3 nftables objects exist with correct flags. When called inside a batch (`MWAN3_BATCH_DEPTH > 0`), skips the direct delete loop (deletes already in the preamble batch). Recreates all 6 internal sets with `interval` + `auto-merge` flags and all skeleton chains in `table inet mwan3`.
- **`mwan3_build_or_chains_nft()`**: Materialises the per-mark setter chains used by the non-destructive vmap-dispatch save/restore. Iterates all 63 possible non-zero values within `MMX_MASK` and emits two chains per value: `mwan3_or_meta_<imm>` (non-destructive restore from ct mark to meta mark) and `mwan3_or_ct_<imm>` (non-destructive save from meta mark to ct mark). Called from `mwan3_set_general_nft()`. Always flushes and re-populates the chain bodies - an earlier idempotency check that returned early on chain *existence* alone could leave the chain bodies empty after a partial-failure first run, which is fatal to packet flow.
- **`mwan3_init()`**: Loads config, computes mask constants (`MMX_DEFAULT`, `MMX_BLACKHOLE`, `MMX_UNREACHABLE`, `MMX_MASK_COMPLEMENT`)
- **`mwan3_id2mask()`**: Bit-spreading function that maps interface IDs onto the mask
- **`mwan3_count_one_bits()`**: Counts set bits in a value
- **Utility functions**: `LOG()`, `readfile()`, `mwan3_get_src_ip()`, `mwan3_get_true_iface()`, `mwan3_get_mwan3track_status()`, `get_uptime()`, `get_online_time()`

> [!NOTE]
> **Shell scoping note:** Functions like `mwan3_id2mask` and `mwan3_count_one_bits` receive *variable names* as arguments (e.g., `mwan3_id2mask mmdefault MMX_MASK`) and use arithmetic expansion `$(($1))` to resolve them. This works in busybox ash (OpenWrt's default shell) because it uses dynamic scoping - local variables from the caller are visible in called functions.

### 5.3 `lib/mwan3/mwan3.sh`

The core engine. Contains all functions for managing nftables chains/sets/maps, ip rules, ip routes, policy creation, user rule classification, and status reporting. This is the largest file and the heart of the implementation. Sourced by init.d, hotplug, CLI, and rtmon scripts.

See [Section 6](#6-function-reference) for detailed function reference.

### 5.4 `etc/init.d/mwan3`

procd service script. Handles:

- **`start_service()`**: Loads `mwan3-skeleton.nft` via `nft -f` first (aborts if this fails), then runs the full init sequence: ensure framework, render ipsets, dnsmasq fragments, trackers, sets, general rules, ifup hotplug loop, nft chains, policies, user rules, conntrack flush (if flow offloading), dnsmasq HUP, rtmons.
- **`stop_service()`**: Guards with `service_running || exit 0`. Shuts down interfaces, flushes ip routes/rules, flushes all mwan3 nft chains, deletes dynamic chains (keeps skeleton chains), flushes sets, flushes and deletes sticky maps, then `$NFT delete table inet mwan3` (complete removal).
- **`reload_service()`**: Atomically rebuilds the entire mwan3 ruleset in a single kernel transaction via `mwan3_nft_reload_start` / all build functions / `mwan3_nft_reload_commit`. Then updates ip rules/routing tables (outside nft), updates dnsmasq fragments if changed, and checks tracker count - falls through to `stop; start` if tracker count mismatches (procd cannot add/remove service instances in reload).
- **`start_tracker()`**: Launches a `mwan3track` procd instance per enabled interface with track IPs or `track_gateway`.
- **`service_running()`**: Returns true if `$MWAN3_STATUS_DIR` exists.

#### Startup Sequence

```
nft -f /lib/mwan3/mwan3-skeleton.nft         # load standalone table (abort if fails)
mwan3_init()
  mwan3_ensure_nft_framework()                # recreate 6 internal sets, ensure chains
  mwan3_render_config_ipsets()                # create user-defined sets from config ipset
  mwan3_write_dnsmasq_fragments()             # write nftset confdir fragments; restart dnsmasq if changed
  config_foreach start_tracker interface      # launch health probes
  mwan3_update_iface_to_table()               # build iface->table mapping
  mwan3_set_dynamic_sets()                    # populate dynamic sets
  mwan3_set_connected_sets()                  # populate connected sets
  mwan3_set_custom_sets()                     # populate custom sets
  mwan3_set_general_rules()                   # ip rule add (blackhole/unreachable)
  config_foreach mwan3_ifup interface "init"  # trigger ifup hotplug per interface
  wait $hotplug_pids
  mwan3_set_general_nft()                     # populate hook chain rules
  mwan3_set_policies_nft()                    # create policy chains
  mwan3_set_user_rules()                      # populate user rules chain
  mwan3_flush_stale_conntrack()               # flush zero-mark conntrack entries
  mwan3_dnsmasq_hup()                         # HUP dnsmasq to re-populate nftset domains
  [if flow_offloading=1] flush conntrack      # force flow re-establishment under new policy
  start rtmon_ipv4 + rtmon_ipv6               # route monitor daemons
```

### 5.5 `etc/hotplug.d/iface/25-mwan3`

Handles interface state change events from netifd. Triggered on `ifup`, `ifdown`, `connected`, and `disconnected` actions.

#### Guard Checks

1. Valid action and interface name
2. Not first-connect or shutdown
3. Device present for ifup/connected
4. procd lock (unless called from init)
5. Service is running (`$MWAN3_STATUS_DIR` exists)
6. nft framework is loaded (`nft list chain inet mwan3 mwan3_prerouting` succeeds)
7. Interface is enabled in UCI

There is no `fw4 reload` detection. `table inet mwan3` is unaffected by fw4 reloads; no recovery path is needed.

#### Actions

| Action | Operations |
|---|---|
| `ifup` | Update peer track IP (if `track_gateway` enabled), create interface nft chain, create ip rules, set hotplug state, create routes, set general rules (if not init), rebuild policies (if online and not init). Signal tracker with USR2. |
| `ifdown` | Set offline state, delete map entries, delete ip rules, delete routes, delete interface nft chain. Signal tracker with USR1. Rebuild policies. |
| `connected` | Set online state, create interface nft chain, rebuild policies. |
| `disconnected` | Set offline state, rebuild policies. |

All actions call `mwan3_flush_conntrack` at end.

> [!NOTE]
> **ifup conditional policy rebuild:** During init (`MWAN3_STARTUP=init`), the ifup action skips general rules and policy rebuild because the init sequence handles those after all interfaces are up. Route creation runs unconditionally on every ifup, including during init. During normal operation, policies are only rebuilt if the interface state is "online" (not for interfaces with `initial_state=offline`).

### 5.6 `usr/sbin/mwan3` (CLI)

User-facing command-line tool. Provides `start`/`stop`/`restart`/`ifup`/`ifdown` commands plus status reporting: `interfaces`, `policies`, `connected`, `rules`, `status` (all combined), and `internal` (detailed dump).

The `use` command runs an arbitrary command bound to a specific interface using `LD_PRELOAD` with `libwrap_mwan3_sockopt.so`.

The `internal` command shows `nft list table inet mwan3` output instead of the old iptables dump.

### 5.7 `usr/sbin/mwan3rtmon`

Route monitor daemon, reimplemented in **ucode**. Runs one instance per address family (ipv4/ipv6) as a procd service. Uses `ucode-mod-rtnl` for direct netlink access and `ucode-mod-uloop` for the event loop, eliminating all `ip` command fork+exec overhead from the original shell implementation.

Key improvements over the shell version:

- **Direct netlink route monitoring** via `rtnl.listener()` instead of `ip monitor route` piped to a shell read loop
- **Structured route data** from netlink messages instead of text parsing with sed/awk
- **O(1) per-event cost** - the refactored handler avoids per-interface ubus calls, popen subprocesses, and UCI cursor creation on each route event. Device-to-table mapping and interface state are cached and refreshed only when needed
- **Debounced connected set rebuild** - route add and delete events trigger a 100ms debounce timer rather than an immediate full set rebuild, coalescing bursts of route changes (e.g., during interface flap) into a single rebuild. Add events for the connected set additionally check to see if any change has occurred.
- **Proper event loop** via `uloop.run()` instead of a shell pipe+read loop

On startup, it performs an initial synchronization: dumps the current routing table via netlink, populates the connected set, and replicates routes into active per-interface tables. It then enters the uloop event loop to process route change notifications asynchronously.

- **New route**: Adds CIDR networks to the connected set via `nft add element`, then replicates the route into active per-interface tables. Host routes (bare IPs without prefix length) are skipped as they are remote destinations. Schedules via the debouncer.
- **Deleted route**: Schedules a debounced connected set rebuild, then removes the route from per-interface tables.

### 5.8 `usr/share/rpcd/ucode/mwan3`

ucode RPC service exposing ubus methods under the `mwan3` object. Used by LuCI for the web interface.

Uses `nft -j` (JSON output mode) for reliable parsing. All set/chain queries are scoped to `table inet mwan3`.

- **`mwan3.status`**: Returns JSON data for interfaces, connected networks, and policies.
  - **Connected IPs**: Parses `nft -j list set inet mwan3 mwan3_connected_v4/v6`.
  - **Policies**: Reads membership from UCI config and cross-references mwan3track `STATUS` files. Every member is always reported with traffic share percentage.
  - **Interfaces**: Reads status from `/var/run/mwan3track/` files and queries procd/netifd via ubus. Tracking IPs discovered by globbing `TRACK_*` files. Per-IP `latency` and `packetloss` populated when `check_quality=1`.
- **`mwan3.nftset_members { set: "<name>" }`**: Returns members of a named nft set in `table inet mwan3`. Used by the Simulator tab for ipset rule matching and connected-network bypass detection.
- **`mwan3.nftset_info {}`**: Returns the name, address-family type, counters flag, and runtime element count of all non-mwan3 sets in `table inet mwan3`. Used by the rule editor and IP Sets status tab.
- **`mwan3.nftset_elements { set: "<name>", max: N }`**: Returns paginated elements of a named user-defined set with per-element packet/byte counters (when the set has `counter` enabled). Default maximum 200 elements; supports up to 5000. Used by the IP Sets status tab for runtime member display.
- **`mwan3.routing_health {}`**: Compares UCI configuration against live kernel state. Checks ip rules and routing tables per interface, reports stale ip rules.

### 5.9 `Makefile`

Package build recipe. Key dependency changes:

| Old Dependency | New Dependency |
|---|---|
| `+ip` | `+ip-full` |
| `+ipset` | `+kmod-nft-core` |
| `+iptables` | `+nftables-json` |
| `+IPV6:ip6tables` | `+ucode` |
| `+iptables-mod-conntrack-extra` | `+ucode-mod-rtnl` |
| `+iptables-mod-ipopt` | `+ucode-mod-uloop` |
| | `+ucode-mod-uci` |
| | `+ucode-mod-ubus` |
| | `+ucode-mod-fs` |
| | `+conntrack` |

The ucode dependencies are required by the reimplemented `mwan3rtmon` route monitor daemon. mwan3 now also requires the userspace `conntrack` tool to be installed as it's used to selectively purge stale conntrack entries when interface flap occurs.

Also installs:

- `mwan3-skeleton.nft` to `$(1)/lib/mwan3/`
- `mwan3-migrate-ipset-v4.sh` to `$(1)/lib/mwan3/` (one-shot migration helper, deleted from the router after postinst runs it)
- `mwan3-remove-firewall-include` UCI defaults to `$(1)/etc/uci-defaults/` (removes legacy `firewall.mwan3_reload` UCI section from v3.x)
- `mwan3-lb-test` to `$(1)/usr/sbin/`

The `preinst` script stops mwan3 before APK replaces any files. This handles the upgrade case where procd watches `/etc/init.d/` via inotify and auto-starts mwan3 when the init script is replaced.

The `postinst` script:
1. Removes any mwan3 chains and sets still in `table inet fw4` (from v3.x upgrades)
2. Conditionally reloads fw4 only if the legacy `firewall.mwan3_reload` UCI section exists (v3.x only; avoids triggering queued hotplug events on a clean v3.5 install)
3. Runs `mwan3-migrate-ipset-v4.sh` to copy `config ipset` sections from `/etc/config/firewall` to `/etc/config/mwan3`, then removes the migration script
4. Restarts rpcd
5. Stops mwan3 a second time (by this point procd's auto-start has completed, so this stop removes auto-start's ip rules)
6. Starts mwan3 cleanly

### 5.10 `usr/sbin/mwan3track`

Interface health probe daemon. One procd service instance is launched per enabled mwan3 interface that has tracking IPs configured. Runs as a shell script; largely unchanged from the iptables version except for the addition of `track_gateway` and `check_quality` support.

#### Probe methods

Configured via the `track_method` UCI option. Supported values: `ping` (default), `arping`, `httping`, `nping-tcp`/`nping-udp`/etc., `nslookup`. All probes are wrapped via `LD_PRELOAD` with `libwrap_mwan3_sockopt.so` (the `WRAP` helper), which intercepts `setsockopt` to set `SO_BINDTODEVICE` on the probe socket. This binds the probe to the physical interface device regardless of mwan3 routing marks, ensuring the probe exits on the correct WAN.

#### Score-based hysteresis

mwan3track maintains a score counter for each interface:

- Each probe round: if `host_up_count >= reliability` (enough IPs responded), score increments; otherwise score decrements.
- When score reaches `up` threshold from below: fires `connected` hotplug event.
- When score reaches `up` threshold from above (on decline): fires `disconnecting` then `disconnected` hotplug events.
- Score is clamped between 0 and `down + up`.

Once the reliability threshold is met in a round, remaining unprobed IPs are marked `skipped` - they are not probed further that round.

#### Status files

Written to `$MWAN3TRACK_STATUS_DIR/<iface>/` (default `/var/run/mwan3track/<iface>/`):

| File | Content |
|---|---|
| `STATUS` | Current state: `online`, `offline`, `connecting`, `disconnecting`, `disabled` |
| `SCORE` | Current score counter |
| `TURN` | Number of probe rounds completed |
| `LOST`, `ONLINE`, `OFFLINE`, `TIME` | Loss count, uptime timestamps |
| `TRACK_<ip>` | Per-IP probe result: `up`, `down`, or `skipped`. Always a status string, regardless of `check_quality`. |
| `LATENCY_<ip>` | [check_quality=1 only] Latency in ms for this IP from the most recent probe round. |
| `LOSS_<ip>` | [check_quality=1 only] Packet loss as a percentage for this IP from the most recent probe round. |
| `GATEWAY` | Gateway IP written by `mwan3_update_peer_track_ip()` when `track_gateway=1`. Read by `mwan3_load_track_ips()` and prepended to the probe list. |

#### check_quality

When `check_quality=1`, probes capture latency (ms) and packet loss (%) per IP. Three-state evaluation: fail (`loss >= failure_loss` OR `latency >= failure_latency`), pass (`loss <= recovery_loss` AND `latency <= recovery_latency`), grey zone (neither - probe result neither increments nor decrements score). Default thresholds (1000ms/500ms/40%/10%) are conservative, suited for monitoring without frequent false failovers.

#### Signal handling

procd sends `SIGUSR1` (ifdown event) and `SIGUSR2` (ifup event) to trigger immediate state transitions without waiting for the next probe interval.

### 5.11 `usr/sbin/mwan3-lb-test`

Load balancing distribution verifier.

```
mwan3-lb-test [-6] -c <client_ip> <policy_name> [ip1 ip2 ...]
mwan3-lb-test cleanup
```

Verifies that numgen-based load balancing produces the expected traffic distribution across policy members. Key design:

- **Iteration count** (`NITER`): computed from member weights as `base_N = total_weight / GCD(weights)`, `NITER = base_N * ceil(30 / base_N)`. Ensures per-member expected counts are whole numbers and `NITER >= 30` always.
- **Test rule**: inserts a temporary ICMP-only rule into `mwan3_rules` matching a nft address set. Using ICMP prevents TCP/UDP traffic to the same IPs (DNS forwarders, Android clients bypassing local DNS, etc.) from contaminating the counter.
- **Client isolation** (`-c <client_ip>`, required): inserts a `forward` chain drop rule blocking pings to the test set from all LAN clients except the nominated test client, and an `mwan3_output` return rule bypassing mwan3 marking for any router process pinging the same IPs. Both rules are scoped to the test set and removed by cleanup.
- **Destination pool**: well-known public IPs. Excludes any IPs already configured as mwan3 `track_ip` values - mwan3track pings those via `mwan3_output -> mwan3_rules`, which would match the test rule and inflate counts.
- **IPv6 mode** (`-6`): uses `meta l4proto ipv6-icmp ip6 daddr @set`, `ping6`, and a separate pool of well-known public IPv6 IPs.
- **IP overrides**: `mwan3-lb-test -c <client_ip> <policy> ip1 ip2 ...` for sites where defaults are unreachable or fully tracked.
- **Windows command**: outputs a `cmd.exe` `for` loop alongside the Linux shell loop. Windows `ping` uses a fixed ICMP identifier (id=1), causing conntrack entry reuse on repeated pings to the same destination; the Windows command uses a longer inter-ping delay (`30/TRACK_COUNT + 3` seconds) so the full cycle exceeds the 30s ICMP conntrack timeout. The IP list is formatted with `^` line continuation at 4 IPs per line.
- **`cleanup` subcommand**: removes stale `mwan3_lb_test_*` sets and rules left by a run that was killed before cleanup could execute.
- **Cleanup on exit**: removes test set and rules on normal exit, SIGINT, SIGTERM, and SIGPIPE. Startup sweep removes stale artifacts from aborted prior runs.

See [§16.7](#167-mwan3-lb-test-load-balancing-distribution-verifier) for context on why this tool was added and the numgen contamination issues it was designed to detect.

---

### 5.12 `usr/sbin/mwan3-diag`

Network diagnostic report generator.

```
mwan3-diag
```

A ucode script that collects a comprehensive snapshot of the network state relevant to mwan3 operation and prints it to stdout. Intended to produce a complete, shareable report without manual redaction.

Collects: interface addresses, routing tables (including all per-WAN tables), policy rules, neighbour cache, mwan3 interface status, mwan3 UCI configuration, the complete mwan3 nftables ruleset, the fw4 mangle chains that interact with mwan3 packet marking, and the last 200 lines of the mwan3 log.

Before printing any output the script builds a map of every public routable IPv4 and IPv6 address present in the collected data and replaces each one with a stable placeholder -- `PUB4_1`, `PUB4_2`, `PUB6_1` and so on -- throughout the entire report. The same address always receives the same placeholder, so cross-references between sections remain consistent. Private addresses (RFC1918, link-local `fe80::`, ULA `fc00::/7`, loopback) are left unchanged. The elements of user-defined nftables sets are replaced with `{ ... }`.

See [§16.9](#169-mwan3-diag-network-diagnostic-report) for context.

---

## 6. Function Reference

### 6.1 common.sh Functions

| Function | Purpose |
|---|---|
| `LOG facility message...` | Logs to syslog. Suppresses `debug` level by default. |
| `mwan3_nft_exec args...` | Runs `nft` with arguments, logs errors. Returns 1 on failure. When `MWAN3_BATCH_DEPTH > 0`, routes to `mwan3_nft_push` instead. |
| `mwan3_nft_batch_start` | Increments `MWAN3_BATCH_DEPTH`; truncates `/tmp/mwan3_nft_batch.$$` only at depth 0->1. |
| `mwan3_nft_push line` | Appends a line to the batch file. |
| `mwan3_nft_batch_commit` | Decrements `MWAN3_BATCH_DEPTH`; executes `nft -f /tmp/mwan3_nft_batch.$$` and removes the temp file only at depth 1->0. |
| `mwan3_nft_reload_start` | Opens outermost batch (depth 0->1) and writes preamble: flush 8 skeleton chains, two-pass flush+delete all dynamic chains, delete 6 internal sets. User-defined sets and sticky sets are untouched. |
| `mwan3_nft_reload_commit` | Thin wrapper around `mwan3_nft_batch_commit`. Commits entire accumulated batch atomically at depth 1->0. On failure, kernel rolls back and old ruleset continues. |
| `mwan3_nft_mark_expr value mask` | Outputs `meta mark set meta mark & COMPLEMENT \| VALUE`. Uses `&` and `\|` symbols (not keywords). Equivalent to iptables `--set-xmark VALUE/MASK`. |
| `mwan3_ensure_nft_framework` | Recreates the 6 internal mwan3 sets with `interval` + `auto-merge` flags (skipping the direct delete loop when inside a batch - deletes already in the preamble). Adds all 8 skeleton chains in `table inet mwan3`. Idempotent for chains. |
| `mwan3_build_or_chains_nft` | Builds the 126 per-mark setter chains used by non-destructive vmap-dispatch save/restore (63 `mwan3_or_meta_<imm>` + 63 `mwan3_or_ct_<imm>` chains). Always flushes and re-populates chain bodies. See [§2 Connmark Operations](#connmark-operations). |
| `mwan3_or_chain_suffix mark` | Converts a numeric mark value to the canonical lowercase `0x%x` hex string used as the suffix for OR-immediate setter chain names (e.g. `0x100` for interface 1 with default mask). Called by `mwan3_build_or_chains_nft`, `mwan3_or_vmap_body`, `mwan3_all_marks`, and `mwan3_create_policies_nft`. |
| `mwan3_or_vmap_body reg mark...` | Builds the body string for a vmap statement dispatching on masked mark values into OR-immediate setter chains. Called by `mwan3_set_general_nft()`. |
| `mwan3_all_marks` | Enumerates every mark value that needs to appear in the restore/save vmaps: all per-interface marks (IDs 1..`MWAN3_INTERFACE_MAX` bit-spread through `MMX_MASK`) plus `MMX_DEFAULT`, `MMX_BLACKHOLE`, and `MMX_UNREACHABLE`. Echoes a space-separated list. Used by `mwan3_set_general_nft()` to build the vmap body. |
| `mwan3_init` | Loads UCI config, creates status dirs, computes all mask constants (`MMX_MASK`, `MMX_DEFAULT`, `MMX_BLACKHOLE`, `MMX_UNREACHABLE`, `MMX_MASK_COMPLEMENT`, `MWAN3_INTERFACE_MAX`). |
| `mwan3_id2mask id mask` | Bit-spreads `id`'s bits into positions where `mask` has 1-bits. Arguments are variable names (indirect evaluation). |
| `mwan3_count_one_bits var` | Counts 1-bits in the value named by `var` (indirect evaluation). Uses `n&(n-1)` trick. |
| `mwan3_get_true_iface out_var iface` | Resolves virtual interface names (appends _4 or _6 suffix if that interface exists in netifd). |
| `mwan3_get_src_ip out_var iface` | Gets the source IP for an interface, with fallbacks for IPv6-PD prefixes. |
| `readfile var path` | Reads entire file into variable. Returns 1 if file doesn't exist. |
| `mwan3_get_mwan3track_status out_var iface` | Returns tracker status: `disabled`, `down`, `paused`, or `active`. |
| `get_uptime [out_var]` | Returns system uptime in seconds (integer). |
| `get_online_time out_var iface` | Returns how long the interface has been online. |

### 6.2 Set Management Functions

| Function | Purpose |
|---|---|
| `mwan3_set_connected_ipv4` | Flushes and repopulates `mwan3_connected_v4` from main routing table. Adds `224.0.0.0/3` for multicast. Self-contained: starts and commits its own nft batch. |
| `mwan3_set_connected_ipv6` | Same for IPv6. Skips if `$NO_IPV6`. Self-contained batch. |
| `mwan3_set_connected_sets` | Calls both `_ipv4` and `_ipv6` functions. |
| `mwan3_set_custom_set table_id` | Callback for `config_list_foreach`. Adds routes from the given table to custom sets. Pushes to an existing batch (does not start/commit). |
| `mwan3_set_custom_sets` | Flushes and repopulates custom sets from all `rt_table_lookup` entries in globals config. |
| `mwan3_set_dynamic_network` | Callback for `config_list_foreach`. Classifies a single `bypass_network` CIDR as IPv4 (contains `.`) or IPv6 (contains `:`) and pushes the appropriate `add element` command to the current batch. |
| `mwan3_set_dynamic_sets` | Flushes `mwan3_dynamic_v4/v6` then repopulates from `bypass_network` entries in globals UCI config. Called at startup and in both fw4 reload recovery paths. |

> [!NOTE]
> **Why are connected functions self-contained?** `mwan3_set_connected_ipv4/ipv6` each manage their own batch because they may be called from contexts that are not already inside a larger batch (init.d, hotplug). `mwan3rtmon` does not call these shell functions; it has its own independent `populate_connected_set()` that operates via direct netlink calls and writes to the same sets using its own `nft_batch`.

### 6.3 General Rule Setup

| Function | Purpose |
|---|---|
| `mwan3_set_general_rules` | Adds `ip rule` entries for blackhole and unreachable marks (both IPv4 and IPv6). These are ip policy rules, not nftables rules - unchanged from the iptables version. |
| `mwan3_set_general_nft` | Builds the per-mark OR setter chains via `mwan3_build_or_chains_nft()`, then populates all hook chain rules: IPv6 RA bypass (prerouting), vmap-dispatched connmark restore (if mark unset), jump to `mwan3_ifaces_in`, `fib daddr type local return` (prerouting, after ifaces_in), jumps to custom/connected/dynamic/rules chains, connmark save, and post-rules connected re-check. Idempotent: checks if rules already exist before adding. Uses a single batch for all operations. |

#### Rules added by `mwan3_set_general_nft()`

For each of connected/custom/dynamic chains, adds mark-setting rules that match against the corresponding sets and apply `MMX_DEFAULT`.

For the prerouting and output hook chains, adds (in order):

1. [prerouting only] IPv6 RA bypass (accept ICMPv6 types: nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect)
2. **Non-destructive connmark restore** (if `meta mark & MMX_MASK == 0`): `ct mark & MMX_MASK vmap { ... -> jump mwan3_or_meta_<imm> }`. The setter chains contain `meta mark set meta mark | <imm>`, so non-mwan3 bits in meta mark are preserved across the restore.
3. Jump to `mwan3_ifaces_in` (if still 0)
4. [prerouting only] `fib daddr type local return` (if still 0): packets destined for the router's own IP return immediately. Placed after `mwan3_ifaces_in` so that WAN traffic arriving on a mwan3 interface is already marked by the iface_in catchall (mark != 0) and never reaches this check. Only traffic on non-WAN interfaces (LAN, loopback) with mark still zero reaches the fib local check. See [§c4bcd951e](#mwan3-fix-numgen-counter-contamination-from-inbound-and-reply-traffic).
5. Jump to custom, connected, dynamic chains (if still 0)
6. Jump to `mwan3_rules` (if still 0)
7. **Non-destructive connmark save** (always): first `ct mark set ct mark & MMX_MASK_COMPLEMENT` clears only mwan3's own bits in ct mark, then `meta mark & MMX_MASK vmap { ... -> jump mwan3_or_ct_<imm> }` ORs the new value back in. Bits in ct mark owned by other packages survive unchanged.
8. Post-rules: jump to custom/connected/dynamic again for non-default marks

See [§2 Connmark Operations](#connmark-operations) for the rationale and the kernel-limitation context.

### 6.4 Interface Management

| Function | Purpose |
|---|---|
| `mwan3_update_iface_to_table` | Populates `mwan3_iface_tbl`: a space-separated string of `name=id` pairs for all configured interfaces, where `id` is the sequential table number. Called lazily (on first use) by `mwan3_get_iface_id()`. Also called explicitly during `start_service()` to prime the cache before interface chains are created. |
| `mwan3_update_dev_to_table` | Populates `mwan3_dev_tbl_ipv4` and `mwan3_dev_tbl_ipv6`: space-separated `device=id` pairs indexed by address family. Used by `mwan3_route_line_dev()` to map a route's output device to its per-interface table ID during route replication in `mwan3_create_iface_route()`. |
| `mwan3_get_iface_id out_var iface` | Looks up `mwan3_iface_tbl` for the given interface name and writes its table ID into the named output variable. Calls `mwan3_update_iface_to_table()` on first use if the cache is empty. |
| `mwan3_create_iface_nft iface device` | Creates (or flushes) `mwan3_iface_in_<iface>` chain. Adds rules matching on `iifname` and address family: source in connected/custom/dynamic → MMX_DEFAULT; otherwise → interface mark. Adds jump from `mwan3_ifaces_in` if not already present. Also installs a per-interface `mwan3_postrouting` SNAT rule for IPv6 interfaces when the `snat6` UCI option is set. Stale `mwan3_snat_<iface>`-tagged rules from a prior incarnation are removed first. See [§16.5](#165-opt-in-ipv6-snat-via-per-interface-snat6). |
| `mwan3_rebuild_iface_nft iface` | Rebuilds a single interface's nft chain if the interface is enabled, the correct family is available, and the interface is currently up (verified via ubus). Used during `reload_service` to rebuild all interface chains within the atomic batch. Calls `mwan3_create_iface_nft()` after resolving the L3 device from netifd. |
| `mwan3_delete_iface_nft iface` | Removes the jump rule from `mwan3_ifaces_in` (by handle lookup), removes any `mwan3_snat_<iface>`-tagged rules from `mwan3_postrouting` (comment-tag match), then flushes and deletes the interface chain. |
| `mwan3_delete_iface_map_entries iface` | Iterates all `mwan3_sticky_v[46]_*` sets in the `inet` family, finds sets whose name ends with `_<id>` (this interface's id), and flushes them. Sets are flushed rather than deleted because rule chains may still reference the set name. |
| `mwan3_create_iface_rules iface device` | Adds `ip rule` entries: pref id+1000 (iif lookup), pref id+2000 (fwmark lookup), pref id+3000 (fwmark unreachable). *Unchanged from iptables version.* |
| `mwan3_delete_iface_rules iface` | Removes ip rules matching this interface's ID range using `$IP rule list` (correct address family for IPv4 or IPv6). |
| `mwan3_create_iface_route iface device` | Copies routes from main table into the per-interface table. *Unchanged.* |
| `mwan3_delete_iface_route iface` | Flushes the per-interface routing table. *Unchanged.* |

#### Handle-Based Rule Deletion

nftables doesn't support deleting rules by match criteria (like iptables `-D chain match...`). Instead, `mwan3_delete_iface_nft()` uses:

```sh
handle=$($NFT -a list chain inet mwan3 mwan3_ifaces_in | \
    grep "jump mwan3_iface_in_$1" | sed -n 's/.*# handle \([0-9]*\)/\1/p')
$NFT delete rule inet mwan3 mwan3_ifaces_in handle "$handle"
```

The `-a` flag shows rule handles in comments, which can then be used for targeted deletion.

### 6.5 Policy & Load Balancing

| Function | Purpose |
|---|---|
| `mwan3_set_policy member_config` | Callback per policy member. Tracks lowest metric and accumulates online members as `iface:id:weight` tuples into `$policy_members`. Tracks offline devices into `$policy_offline_devices`. Uses caller's variables (dynamic scoping). |
| `mwan3_create_policies_nft policy` | Creates/flushes the `mwan3_policy_<name>` chain. Iterates members via `mwan3_set_policy`, then builds the chain: single member gets a direct mark-set rule; multiple members get a `numgen` rule; offline devices get out-device fallback rules; last-resort rule (unreachable/blackhole/default) is appended. |
| `mwan3_set_policies_nft` | Before creating policy chains, enumerates all existing `mwan3_policy_*` chains in `inet mwan3` and deletes any whose name is not in the current UCI policy config (orphaned chain sweep). Then iterates all policy configs and calls `mwan3_create_policies_nft` for each. |

### 6.6 Sticky Routing

| Function | Purpose |
|---|---|
| `mwan3_get_policy_members_for_family policy family` | Iterates the members of a policy config via `config_list_foreach`. For each member whose interface matches the requested family, resolves the interface id and computes its mark, and accumulates `<id>:<mark>` tuples into `$_policy_member_marks`. Used by the sticky path in `mwan3_set_user_nft_rule()` to enumerate per-member sets. |

### 6.7 User Rules

| Function | Purpose |
|---|---|
| `mwan3_set_user_nft_rule rule ipv` | Builds and adds a single nft rule to `mwan3_rules`. Translates UCI config options (proto, src_ip, dest_ip, src_port, dest_port, src_iface, ipset, ipset_src) into nft match expressions. For sticky rules, calls `mwan3_get_policy_members_for_family()` and builds a `mwan3_rule_<name>` chain with per-member address sets and OR-immediate restore/save (see §8). Handles logging rules. Pre-creates missing nft sets (e.g., dnsmasq nftsets that haven't started yet) to prevent batch failures. When `family` is explicitly `ipv4` or `ipv6` but none of `src_ip`, `dest_ip`, `ipset`, or `ipset_src` are set, prepends `meta nfproto ipv4/ipv6` to the nft match to prevent a bare rule from matching both address families. Also translates `proto icmp` to `meta l4proto ipv6-icmp` when `family` is `ipv6` (in an inet table, proto 1 is ICMPv4 only). |
| `mwan3_set_user_rules` | Flushes `mwan3_rules` chain, then iterates all rule configs for both ipv4 and ipv6, calling `mwan3_set_user_nft_rule` for each. Uses a single batch. |
| `mwan3_set_user_iface_rules iface device` | Called on ifup to check if the rules chain needs rebuilding (if this interface is a `src_iface` in any rule). |

#### UCI-to-nft Match Translation

| UCI Option | nft Expression |
|---|---|
| `proto tcp` | `meta l4proto tcp` |
| `src_ip 10.0.0.0/8` | `ip saddr 10.0.0.0/8` (or `ip6 saddr`) |
| `dest_ip 1.2.3.4` | `ip daddr 1.2.3.4` |
| `src_iface lan` | `iifname "br-lan"` |
| `src_port 80,443` | `th sport { 80, 443 }` |
| `dest_port 8080` | `th dport { 8080 }` |
| `ipset my_set` | `ip daddr @my_set` |
| `ipset_src my_set` | `ip saddr @my_set` |
| `use_policy balanced` | `jump mwan3_policy_balanced` |
| `use_policy default` | `meta mark set ... \| MMX_DEFAULT` |

#### Missing nft Set Pre-creation

When a user rule references an `ipset` (destination nft set) or `ipset_src` (source nft set) that doesn't exist yet in `table inet mwan3`, `nft -f` would roll back the entire batch atomically. To prevent this, `mwan3_set_user_nft_rule()` pre-creates any missing referenced sets with the appropriate type. The same logic applies to both `ipset` and `ipset_src`.

### 6.8 User-defined nft Set Management

| Function | Purpose |
|---|---|
| `mwan3_render_config_ipsets` | Iterates all `config ipset` UCI sections and calls `_mwan3_render_one_ipset` for each. Creates user-defined sets in `table inet mwan3`. Called from `start_service` and `reload_service`. |
| `_mwan3_nft_time_to_sec str` | Converts an nft human-unit timeout string (e.g. `1h`, `5m`, `300s`) to an integer number of seconds. Recognised suffixes: `d` (days), `h` (hours), `m` (minutes), `s` (seconds, default if no suffix). Used by `_mwan3_ipset_needs_delete` to compare the live kernel timeout against the desired spec in a common unit. |
| `_mwan3_ipset_needs_delete name type counter timeout maxelem` | Returns 0 (true) if the named set exists in `table inet mwan3` AND its flags (type, counter, timeout, size) differ from the desired spec; returns 1 if the set is absent or all flags match. Called by `_mwan3_render_one_ipset` during reload to decide whether to queue a `delete set` before recreating the set with new flags. Timeout values are compared in seconds after converting nft's human-unit display (e.g. `1h`, `5m`) via `_mwan3_nft_time_to_sec`. |
| `_mwan3_render_one_ipset name` | Creates one user-defined nft set. Builds a `type ipv4_addr/ipv6_addr; flags interval; auto-merge;` declaration, optionally appending `counter;` (standalone statement, NOT a flag keyword) and `timeout Ns;`. On the start path, unconditionally deletes any existing set before creating. On the reload path, calls `_mwan3_ipset_needs_delete` and only queues a `delete set` when flags differ; otherwise `add set` is idempotent and dnsmasq-populated elements survive. Sets `MWAN3_NEED_DNSMASQ_HUP` if a domain-populated set is deleted. Adds inline `list entry` elements and `loadfile` contents. |
| `mwan3_write_dnsmasq_fragments` | For each `config ipset` with `list domain` entries, writes a dnsmasq confdir fragment enabling `nftset=/domain/FAMILY#inet#mwan3#setname`. Compares against previously written fragments; restarts dnsmasq only when content changes. Silently does nothing if no domain sets are configured. |
| `mwan3_cleanup_orphaned_ipsets` | Queries `nft list table inet mwan3` for user-defined sets (those not prefixed `mwan3_`), compares against configured set names, and pushes `delete set` for any orphans. Called in `reload_service` after `mwan3_render_config_ipsets`. Prevents stale sets accumulating when a set is removed from UCI config. |

### 6.9 Status Reporting

| Function | Purpose |
|---|---|
| `mwan3_report_iface_status iface` | Shows interface online/offline status with uptime. Checks ip rules, nft chain existence in `table inet mwan3`, and default route presence. |
| `mwan3_report_policies policy` | Parses `nft list chain` output for a policy chain. Detects `numgen` for load balancing or direct mark-set for single member. |
| `mwan3_report_policies_v4/v6` | Lists all `mwan3_policy_*` chains. With inet family both are identical. |
| `mwan3_report_connected_v4/v6` | Parses `nft list set` output for connected set elements. |
| `mwan3_report_rules_v4/v6` | Parses `nft list chain inet mwan3 mwan3_rules`. |
| `mwan3_mark_to_name mark` | Resolves a numeric mark value to an interface name (or "default"/"blackhole"/"unreachable"). |

### 6.10 Lifecycle & Hotplug

| Function | Purpose |
|---|---|
| `mwan3_ifup iface caller` | Resolves interface status via ubus, then triggers the 25-mwan3 hotplug script with `ACTION=ifup`. When called from init, runs in background. |
| `mwan3_interface_hotplug_shutdown iface [ifdown]` | Triggers ifdown or disconnected hotplug event for an interface. |
| `mwan3_interface_shutdown iface` | Calls hotplug shutdown then cleans track state files. |
| `mwan3_set_iface_hotplug_state iface state` | Writes state (`online`/`offline`) to status file. |
| `mwan3_get_iface_hotplug_state iface` | Reads state from status file (defaults to `offline`). |
| `mwan3_flush_conntrack iface action` | Two-path conntrack flush. First, iterates the `flush_conntrack` UCI list for this interface: for each configured action that matches the current hotplug action, writes `f` to `$CONNTRACK_FILE` to flush the entire global conntrack table. Second, on `ifdown`, uses `conntrack -D --mark MARK/MMX_MASK` to selectively delete only the conntrack entries for this interface's fwmark. Both paths run; the global flush path runs first. |
| `mwan3_flush_marked_conntrack` | Flushes all conntrack entries that have any `MMX_MASK` bit set, iterating the full mwan3 id-space (IDs 1..`MWAN3_INTERFACE_MAX` plus default/blackhole/unreachable marks). Called from `reload_service` so that live flows re-enter the classification chains and are re-evaluated against new rules rather than staying pinned to a previously saved ct mark. |
| `mwan3_update_peer_track_ip iface` | If `track_gateway` is enabled, queries `ifstatus` for the point-to-point peer address and writes it to `$MWAN3TRACK_STATUS_DIR/<iface>/GATEWAY`. |
| `mwan3_track_clean iface` | Removes track status directory for the interface. |
| `mwan3_dnsmasq_hup` | Sends SIGHUP to running dnsmasq instances via `ubus call service signal '{"name":"dnsmasq","signal":1}'`. Called once from `start_service` after sets are created so dnsmasq resolves domain entries into nft sets. No longer uses mwan3evtd (which was removed ). |
| `mwan3_flush_stale_conntrack` | Flushes conntrack entries with no mwan3 mark (`0x0/MMX_MASK`) after mwan3 restart. New connections arriving during the brief startup window before iface_in chains exist get ct mark=0; this clears them so they re-establish correctly. Called from `start_service`. |

---

## 7. Load Balancing with numgen

The iptables version used `-m statistic --mode random --probability P` to distribute traffic. This required inserting rules in specific order and computing running probabilities. The nftables version uses `numgen inc mod N map { ... }`, which is simpler and more deterministic.

### How numgen Works

`numgen inc mod N` generates a counter that increments on each packet and wraps at N. The `map { range : value }` maps counter values to marks.

```
# Example: wan (weight 3) + wanb (weight 2) = mod 5
# wan gets range 0-2 (3 values), wanb gets range 3-4 (2 values)

nft add rule inet mwan3 mwan3_policy_balanced \
    meta mark & 0x3f00 == 0 \
    meta mark set numgen inc mod 5 map { 0-2 : 0x0100, 3-4 : 0x0200 }
```

> [!WARNING]
> **Kernel limitation on compound set expressions:** An early implementation tried `meta mark set meta mark & COMP | numgen inc mod ...` to preserve non-mwan3 bits while applying the numgen result. This fails with "Operation not supported" because the kernel cannot mix two register sources (meta mark and numgen) in one set expression. The solution is to use `meta mark set numgen ...` directly; the `meta mark & MMX_MASK == 0` guard condition ensures the mwan3 bits are already zero before the numgen result is applied.

### Build Algorithm (in `mwan3_create_policies_nft`)

1. Iterate policy members via `config_list_foreach`
2. Track lowest metric per family (v4/v6 separately); only members at the lowest metric are included
3. Accumulate online members as `iface:id:weight` tuples
4. Calculate total weight = sum of all member weights
5. If single member: direct `meta mark set` (no numgen overhead)
6. If multiple members: build numgen map entries with ranges proportional to weight
7. Append offline device fallback rules (only if no online members)
8. Append last-resort rule (unreachable/blackhole/default)

> [!NOTE]
> **Difference from iptables version:** The iptables version used probabilistic matching (`--probability`) which is statistically correct over many packets but can have short-term imbalance. The nftables `numgen inc` counter gives perfectly deterministic round-robin distribution at the configured weights.

---

## 8. Sticky Routing Detail

Sticky routing ensures that repeat connections from the same source IP use the same WAN interface (important for HTTPS sessions, banking sites, etc.). The iptables version used `ipset hash:ip,mark` sets. The nftables version uses per-member **address sets** with OR-immediate vmap dispatch for non-destructive mark restore.

### Why Per-Member Sets Instead of a Single Map

An early implementation used a single `ipv4_addr : mark` map per rule with `meta mark set ip saddr map @mwan3_sticky_v4_https`. This is destructive: the map lookup overwrites meta mark entirely with the stored value, wiping any bits set by other packages (pbr etc.). With the vmap-dispatch infrastructure, the correct approach is a plain address set per policy member, with the mark encoded in the chain name rather than the map value. The corresponding `mwan3_or_meta_<mark>` setter chain ORs only the mwan3 bits into meta mark, preserving everything else.

### Data Structure

```
# Created per policy member for rule "https"
# (policy "balanced" has members: wan id=1 mark=0x100, wanb id=2 mark=0x200)
nft add set inet mwan3 mwan3_sticky_v4_https_1 { type ipv4_addr; flags timeout; timeout 600s; }
nft add set inet mwan3 mwan3_sticky_v4_https_2 { type ipv4_addr; flags timeout; timeout 600s; }
```

One set per policy member, per rule, per address family. Sets hold source addresses only (no value side). The mark to apply is encoded in which set the saddr is found in.

### Rule Chain Structure (for sticky rule "https", policy "balanced", wan=id1 wanb=id2)

```
chain mwan3_rule_https {
    # Restore: if saddr is in this member's set, OR its mark into meta mark
    # (non-destructive - pbr bits in meta mark are preserved)
    ip saddr @mwan3_sticky_v4_https_1 jump mwan3_or_meta_0x100
    ip saddr @mwan3_sticky_v4_https_2 jump mwan3_or_meta_0x200

    # New flows (no set match, mark still 0) fall through to policy
    meta mark & 0x3f00 == 0 jump mwan3_policy_balanced

    # Save: after policy assigns a mark, record saddr in the matching member's set
    meta mark & 0x3f00 == 0x100 update @mwan3_sticky_v4_https_1 { ip saddr timeout 600s }
    meta mark & 0x3f00 == 0x200 update @mwan3_sticky_v4_https_2 { ip saddr timeout 600s }
}
```

### Flow for a Sticky Rule

1. Packet arrives at `mwan3_rules` chain
2. Matches the user rule → `jump mwan3_rule_https`
3. **Returning source**: saddr is found in one of the per-member sets → `jump mwan3_or_meta_<mark>` ORs only the mwan3 bits into meta mark (non-destructive). The policy jump guard is false (mark already set), so policy is skipped. The matching update rule refreshes the timeout.
4. **New source**: no set match, mark stays 0. Falls through to the policy chain which assigns a mark. The matching update rule then adds saddr to the corresponding member's set with the configured timeout.
5. After timeout seconds of inactivity the set entry expires and the source is re-evaluated at next connection.

---

## 9. Service Lifecycle

### Start

```
/etc/init.d/mwan3 start
  +--> nft -f /lib/mwan3/mwan3-skeleton.nft  (abort if fails)
  +--> mwan3_init()                    compute masks
  +--> mwan3_ensure_nft_framework()    recreate 6 internal sets, ensure chains
  +--> mwan3_render_config_ipsets()    create user-defined sets from config ipset
  +--> mwan3_write_dnsmasq_fragments() write nftset confdir fragments; restart dnsmasq if changed
  +--> start_tracker per interface     launch mwan3track
  +--> mwan3_update_iface_to_table()   build iface->table mapping
  +--> mwan3_set_dynamic/connected/custom sets
  +--> mwan3_set_general_rules()       ip rule add blackhole/unreachable
  +--> mwan3_ifup per interface        trigger hotplug (creates iface chains + ip rules)
  +--> wait for hotplug completion
  +--> mwan3_set_general_nft()         populate hook chain rules
  +--> mwan3_set_policies_nft()        create policy chains
  +--> mwan3_set_user_rules()          populate user rules chain
  +--> mwan3_flush_stale_conntrack()   flush zero-mark conntrack entries
  +--> mwan3_dnsmasq_hup()             SIGHUP dnsmasq to populate nftset domain sets
  +--> [if flow_offloading=1]          flush conntrack (force flow re-establishment)
  +--> start mwan3rtmon (ipv4 + ipv6)  route monitor daemons
```

### Reload

```
/etc/init.d/mwan3 reload
  +--> mwan3_nft_reload_start()        open batch + write preamble (flush/delete dynamic state)
  +--> mwan3_ensure_nft_framework()    recreate 6 internal sets
  +--> mwan3_render_config_ipsets()    add user-defined sets (skips delete inside batch)
  +--> mwan3_cleanup_orphaned_ipsets() delete user sets not in current config
  +--> mwan3_set_dynamic/connected/custom sets
  +--> config_foreach mwan3_rebuild_iface_nft  (checks ubus for up status)
  +--> mwan3_set_general_nft()
  +--> mwan3_set_policies_nft()
  +--> mwan3_set_user_rules()
  +--> mwan3_nft_reload_commit()       commit all as single atomic kernel transaction
  +--> mwan3_update_iface_to_table()   (outside nft)
  +--> mwan3_set_general_rules()       (outside nft)
  +--> mwan3_write_dnsmasq_fragments() restart dnsmasq only if fragment content changed
  +--> [if MWAN3_NEED_DNSMASQ_HUP=1]   mwan3_dnsmasq_hup() repopulate domain sets lost on flag change
  +--> [tracker count check]           if mismatch: stop + start (procd cannot add/remove
                                       service instances in reload_service)
```

User-defined sets (config ipset) and sticky sets (`mwan3_sticky_*`) survive the reload intact - they are never in the preamble delete path.

### Interface Up (hotplug)

```
netifd signals ifup for $INTERFACE
  +--> 25-mwan3 hotplug script
       +--> mwan3_update_peer_track_ip()                write gateway IP (if track_gateway)
       +--> mwan3_create_iface_nft()                    create/flush chain, add rules
       +--> mwan3_create_iface_rules()                  ip rule add (iif, fwmark)
       +--> mwan3_create_iface_route()                  copy routes to per-iface table
       +--> mwan3_set_iface_hotplug_state "online/offline"
       +--> [if not init startup:]
       |    +--> mwan3_set_general_rules()              ensure ip rules exist
       |    +--> [if online:] mwan3_set_policies_nft()  rebuild policy chains
       +--> procd_send_signal track_$INTERFACE USR2
```

### Interface Down (hotplug)

```
netifd signals ifdown for $INTERFACE
  +--> 25-mwan3 hotplug script
       +--> mwan3_set_iface_hotplug_state "offline"
       +--> mwan3_delete_iface_map_entries()           flush sticky sets for this iface
       +--> mwan3_delete_iface_rules()                 ip rule del
       +--> mwan3_delete_iface_route()                 ip route flush table
       +--> mwan3_delete_iface_nft()                   remove chain + jump rule
       +--> procd_send_signal track_$INTERFACE USR1
       +--> mwan3_set_policies_nft()                   rebuild policies (failover)
       +--> mwan3_flush_conntrack()                    flush conntrack entries for this iface's fwmark
```

### Stop

```
/etc/init.d/mwan3 stop
  +--> service_running || exit 0
  +--> mwan3_interface_shutdown per interface   trigger ifdown hotplug
  +--> flush ip routing tables (1..MWAN3_INTERFACE_MAX)
  +--> delete ip rules in 1000-3999 range
  +--> flush ALL mwan3_* chains (rules removed, skeleton chains kept)
  +--> delete dynamic chains (iface_in_*, policy_*, etc.)
  +--> final safety flush of skeleton chains
  +--> flush ALL mwan3_* sets; flush and delete sticky maps
  +--> $NFT delete table inet mwan3   (complete removal)
  +--> rm -rf status dirs

Result: table inet mwan3 no longer exists. Clean slate.
```

---

## 10. Atomic Non-destructive Reload

`reload_service` is a single atomic `nft -f` batch that rebuilds the entire ruleset while the old one is still serving traffic, committing in one kernel transaction with zero traffic disruption window.

### MWAN3_BATCH_DEPTH Counter

`MWAN3_BATCH_DEPTH` is an integer counter (default 0) in `common.sh`. It enables nested batch accumulation:

- `mwan3_nft_batch_start`: increments depth; truncates batch file only at depth 0->1.
- `mwan3_nft_batch_commit`: decrements depth; commits to kernel only at depth 1->0.
- `mwan3_nft_exec`: routes to `mwan3_nft_push` when depth > 0, accumulating all operations.

This means individual build functions (which each call `mwan3_nft_batch_start` / `mwan3_nft_batch_commit` internally) work correctly both standalone (immediate kernel commit) and when called from inside a reload batch (operations accumulate, committed as one transaction at the end).

### Preamble (mwan3_nft_reload_start)

Opens the outermost batch (depth 0->1), then writes:

1. Flush all 8 skeleton chains (`mwan3_prerouting`, `mwan3_output`, `mwan3_postrouting`, `mwan3_ifaces_in`, `mwan3_rules`, `mwan3_connected`, `mwan3_custom`, `mwan3_dynamic`).
2. Two-pass flush then delete all dynamic chains (`mwan3_iface_in_*`, `mwan3_policy_*`, `mwan3_rule_*`, `mwan3_or_meta_*`, `mwan3_or_ct_*`). Two passes are required because `mwan3_or_meta_*` chains are referenced by `mwan3_rule_*` sticky chains; a single alphabetical pass would attempt to delete `or_meta` before flushing `rule`, producing "Device or resource busy".
3. Delete the 6 internal `mwan3_*` sets so `mwan3_ensure_nft_framework` recreates them with correct flags.

**What is NOT in the preamble:** user-defined sets (from `config ipset`), sticky sets (`mwan3_sticky_*`). These survive the reload intact, preserving dnsmasq-populated addresses and sticky routing state.

### Batch Guards in Build Functions

Six locations in build functions query kernel state (chain/set existence) that are bypassed when inside a batch (`MWAN3_BATCH_DEPTH > 0`), because the kernel still shows the pre-preamble state until the batch commits:

- `mwan3_set_general_nft` idempotency guard
- `mwan3_create_iface_nft` SNAT loop / jump rule check
- `mwan3_create_policies_nft` (unconditional add+flush inside batch)
- `mwan3_set_policies_nft` orphan cleanup
- `mwan3_ensure_nft_framework` delete set loop
- `_mwan3_render_one_ipset` delete set (skipped inside batch when flags are unchanged, to preserve dnsmasq-populated elements; queued inside batch when flags differ)

### Commit

`mwan3_nft_reload_commit` calls `mwan3_nft_batch_commit`. At depth 1->0 the entire accumulated batch is submitted to the kernel as a single transaction. If `nft -f` returns non-zero, the kernel rolls back completely and the old ruleset continues serving traffic. No partial states are possible.

---

## 11. User-defined nft Sets

`config ipset` sections in `/etc/config/mwan3` create named nft sets in `table inet mwan3`. These sets can be referenced in rules via the `ipset` (destination) and `ipset_src` (source) UCI options.

### UCI Configuration

```
config ipset 'youtube_ipv4'
    option name     'youtube_v4'
    option family   'ipv4'
    option enabled  '1'
    option maxelem  '0'          # 0 = unlimited (default)
    option timeout  '0'          # 0 = no timeout (default), seconds
    option counters '0'          # 0 = no per-element counters (default)
    list entry  '8.8.8.8'
    list entry  '203.0.113.0/24'
    list domain 'youtube.com'
    list domain 'googlevideo.com'
    option loadfile '/etc/mwan3/custom-ips.txt'
```

### Options

| Option | Values | Purpose |
|---|---|---|
| `name` | string | nft set name in `table inet mwan3`. Must be unique. |
| `family` | `ipv4` or `ipv6` | Address family. Determines set type (`ipv4_addr` or `ipv6_addr`). |
| `enabled` | `0`/`1` | Skip this set if `0`. |
| `maxelem` | integer | Maximum elements. `0` = unlimited (default). |
| `timeout` | integer | Per-element timeout in seconds. `0` = no timeout. |
| `counters` | `0`/`1` | Enable per-element packet/byte counter tracking. |
| `list entry` | CIDR or address | Inline address/CIDR added at startup. |
| `list domain` | domain name | Causes mwan3 to write a dnsmasq `nftset=` confdir fragment for this domain. dnsmasq populates the set via DNS resolution. |
| `loadfile` | path | File containing addresses/CIDRs, one per line. Loaded at startup. |

### counter Syntax

`counter` is a **standalone nft set statement**, NOT a flag keyword. It appears after the type/flags declarations on its own line:

```
set youtube_v4 {
    type ipv4_addr
    flags interval
    auto-merge
    counter
}
```

Placing `counter` inside the `flags` list causes an nft parse error.

### dnsmasq Integration

For each `list domain` entry, `mwan3_write_dnsmasq_fragments` writes a dnsmasq confdir fragment:

```
nftset=/youtube.com,googlevideo.com/4#inet#mwan3#youtube_v4
```

The fragment restarts dnsmasq only when its content has changed (comparing against the previously written fragment). On the next DNS query for the domain, dnsmasq adds the resolved address to the nft set automatically. A `mwan3_dnsmasq_hup` call from `start_service` forces initial resolution. `reload_service` also calls `mwan3_dnsmasq_hup` when `MWAN3_NEED_DNSMASQ_HUP` is set -- see Flag Changes below.

### Flag Changes

`nft add set` is idempotent and does NOT update flags (type, counter, timeout, size) on an existing set. When a set's flags are changed via LuCI or UCI command and the config is applied, `_mwan3_ipset_needs_delete` detects the mismatch by querying the live kernel set and comparing against the desired spec. If any flag differs, the set is queued for deletion inside the reload batch before being recreated with the new flags. The reload batch preamble has already flushed `mwan3_rules` (removing all references to user sets) before the delete fires at commit time, so the delete is safe.

If the deleted set had `list domain` entries, its dnsmasq-populated elements are lost when it is recreated empty. `_mwan3_render_one_ipset` sets `MWAN3_NEED_DNSMASQ_HUP=1` in this case. After `mwan3_write_dnsmasq_fragments` completes in `reload_service`, a `mwan3_dnsmasq_hup` call is issued to repopulate the set via DNS re-resolution.

### Migration from fw4 ipsets

`mwan3-migrate-ipset-v4.sh` (a one-shot script run from postinst and immediately deleted) copies `config ipset` sections from `/etc/config/firewall` to `/etc/config/mwan3` if any of the sets in `/etc/config/firewall` are referenced in an mwan3 user rule. The `match` UCI option required by fw4 is silently ignored by mwan3 (mwan3 does not call `config_get match`).

### Orphan Cleanup

`mwan3_cleanup_orphaned_ipsets` is called in `reload_service` after `mwan3_render_config_ipsets`. It queries `nft list table inet mwan3` for user-defined sets (those not prefixed `mwan3_`), compares against currently configured set names, and emits `delete set` for any orphans. This prevents stale sets accumulating when a set is removed from UCI config via LuCI.

---

## 12. Unchanged Files

| File | Reason |
|---|---|
| `etc/hotplug.d/iface/26-mwan3-user` | Just calls `/etc/mwan3.user`, no firewall code |
| `etc/config/mwan3` | UCI schema is firewall-agnostic |
| `etc/mwan3.user` | User script template, no firewall code |
| `etc/uci-defaults/mwan3-migrate-flush_conntrack` | UCI migration, no firewall code |

---

## 13. Diagnostic Commands

```sh
# Full mwan3 table dump
nft list table inet mwan3

# List specific chain
nft list chain inet mwan3 mwan3_prerouting
nft list chain inet mwan3 mwan3_output
nft list chain inet mwan3 mwan3_postrouting
nft list chain inet mwan3 mwan3_ifaces_in
nft list chain inet mwan3 mwan3_policy_balanced

# Check internal set contents
nft list set inet mwan3 mwan3_connected_v4
nft list set inet mwan3 mwan3_connected_v6
nft list set inet mwan3 mwan3_custom_v4
nft list set inet mwan3 mwan3_dynamic_v4

# Check user-defined sets (config ipset)
nft list set inet mwan3 youtube_v4
nft list table inet mwan3 | grep '^\tset '   # all sets in mwan3 table only

# Check sticky set entries (per-member sets, id suffix = interface id)
nft list set inet mwan3 mwan3_sticky_v4_https_1
nft list set inet mwan3 mwan3_sticky_v6_https_1

# List all mwan3 chains (names only)
# Note: nft list chains only accepts an optional family, not a table name
nft list chains inet | grep mwan3_

# List OR-immediate setter chains (vmap dispatch)
nft list chains inet | grep mwan3_or_

# Verify marks are being set (add temporary counter)
nft add rule inet mwan3 mwan3_prerouting meta mark and 0x3f00 != 0 counter

# Check connmarks
conntrack -L -o mark

# Check ip rules
ip rule list | grep -E '^[1-3][0-9]{3}:'

# Check per-interface routing table (table N for interface N)
ip route list table 1

# JSON output (for scripting/debugging)
nft -j list set inet mwan3 mwan3_connected_v4
nft -j list chain inet mwan3 mwan3_policy_balanced

# Check mwan3 status
mwan3 status
mwan3 internal

# RPC query
ubus call mwan3 status '{"section":"interfaces"}'
ubus call mwan3 status '{"section":"connected"}'
ubus call mwan3 status '{"section":"policies"}'

# Query user-defined set info and members
ubus call mwan3 nftset_info '{}'
ubus call mwan3 nftset_elements '{"set":"youtube_v4","max":200}'
```

---

## 14. luci-app-mwan3 Changes

The LuCI web interface application (`luci-app-mwan3`) required changes to update nftset references from `table inet fw4` to `table inet mwan3`, add the IP Sets configuration and status tabs, and update RPC methods. The LuCI app lives in the `feeds/luci` feed, separate from the core mwan3 package.

### Changed Files

| File | Package Path |
|---|---|
| `rule.js` | `applications/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/network/rule.js` |
| `interface.js` | `applications/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/network/interface.js` |
| `luci-mwan3` | `applications/luci-app-mwan3/root/usr/libexec/luci-mwan3` |
| `luci-app-mwan3.json` | `applications/luci-app-mwan3/root/usr/share/rpcd/acl.d/luci-app-mwan3.json` |

### 14.1 `rule.js` - Rule Editor UI

The LuCI rule editor view allows users to configure mwan3 traffic classification rules. It populates dropdowns of available nft sets for the `ipset` (destination) and `ipset_src` (source) UCI options.

#### iptables-to-nftables Changes

| Aspect | Old (iptables) | New (nftables) |
|---|---|---|
| Data fetch | `fs.exec_direct('/usr/libexec/luci-mwan3', ['ipset', 'dump'])` | `ubus.call('mwan3', 'nftset_info', {})` |
| Field label | `_('IPset')` | `_('NFT set')` |
| Help text | `Name of IPset rule. Requires IPset rule in /etc/dnsmasq.conf (eg "ipset=/youtube.com/youtube")` | `Name of nft set in table inet mwan3 (eg "nftset=/youtube.com/4#inet#mwan3#youtube")` |
| Variable names | `ipsets`, `ips` | `nftsets`, `s_name` |

> [!NOTE]
> **dnsmasq nftset syntax:** The format is `nftset=/domain/FAMILY#TABLE_FAMILY#TABLE#SET`. For example, `nftset=/youtube.com/4#inet#mwan3#youtube` means: for `youtube.com` A records (family `4` = IPv4), add addresses to the set named `youtube` in `table inet mwan3`. mwan3 writes these fragments automatically for sets with `list domain` entries; manual dnsmasq config is needed only for sets not managed via `config ipset`.

> [!NOTE]
> **UCI option name preserved:** The underlying UCI option remains `ipset` (not renamed to `nftset`) to maintain backwards compatibility with existing configurations. The mwan3 shell code reads `config_get ipset_name "$1" ipset` regardless of the firewall backend. Only the UI labels and help text were updated to reflect the nftables terminology.

#### v3.3.1 Enhancements

**nftset dropdown via rpcd:** The nftset dropdown is now populated via the `mwan3.nftset_info` rpcd ubus method instead of the `luci-mwan3 nftset dump` helper script. Sets are annotated with `(IPv4)` or `(IPv6)` in the dropdown label based on the address-family type returned by `nftset_info`.

**Source NFT set field (`ipset_src`):** A new "Source NFT set" field is shown before the existing "Destination NFT set" field in the rule modal. It sets the `ipset_src` UCI option. Both source and destination sets can be set on the same rule and are ANDed together. The grid listing shows the nftset name in the Source or Destination column when no IP address is configured, preventing the rule from appearing as a wildcard match in the listing.

**Address family validation:** `src_ip` and `dest_ip` fields validate against the selected address family on blur - an error is shown if an IPv4 address is entered when family is set to IPv6 or vice versa. Family consistency is also validated on save: a destination nftset must match the selected family, and combining a destination nftset with `dest_ip` (or source nftset with `src_ip`) is flagged as an error since both constrain the same traffic dimension.

### 14.2 `luci-mwan3` - Helper Script

The `/usr/libexec/luci-mwan3` shell script provides backend commands called by the LuCI JavaScript frontend. The `ipset` subcommand was renamed to `nftset` and the underlying implementation changed from querying ipset to querying nftables.

#### Changes

| Aspect | Old (iptables) | New (nftables) |
|---|---|---|
| Subcommand name | `ipset` | `nftset` |
| Function name | `ipset_dump()` / `ipset_cmd()` | `nftset_dump()` / `nftset_cmd()` |
| Implementation | `ipset -n -L 2>/dev/null \| grep -v mwan3_ \| sort -u` | `nft list table inet mwan3 2>/dev/null \| awk '/^\tset / {print $2}' \| grep -v '^mwan3_' \| sort -u` |
| Help text | `dump: show all configured ipset names` | `dump: show all user-defined nft set names in table inet mwan3` |

The `nftset_dump()` function lists all sets in `table inet mwan3`, extracts set names using awk (matching lines that start with a tab followed by `set`), filters out mwan3's own internal sets (prefixed with `mwan3_`), and returns the sorted unique names. Note: `nft list sets inet mwan3` is NOT used because it lists sets from all inet tables, not just mwan3's table; use `nft list table inet mwan3` instead.

In v3.3.1, rule.js switched from calling `luci-mwan3 nftset dump` to the `mwan3.nftset_info` rpcd ubus method. The `nftset dump` subcommand is therefore no longer called by the rule editor - it remains in the script but is effectively unused.

The `diag` subcommand and its functions (`diag_gateway`, `diag_tracking`, `diag_rules`, `diag_routes`) are unchanged - they use `ip rule`/`ip route` and the `mwan3 use` command, none of which depend on the firewall backend.

### 14.3 `luci-app-mwan3.json` - ACL Permissions

The rpcd ACL file controls which commands the LuCI frontend is permitted to execute. It contains two ACL groups with separate permission sets.

**`luci-app-mwan3`** (configuration access): The `read.file` exec entry was updated to match the renamed subcommand:

| Old | New |
|---|---|
| `"/usr/libexec/luci-mwan3 ipset dump": ["exec"]` | `"/usr/libexec/luci-mwan3 nftset dump": ["exec"]` |

In v3.3.1, rule.js switched from calling the helper script via `fs.exec_direct('/usr/libexec/luci-mwan3', ['nftset', 'dump'])` to the `mwan3.nftset_info` rpcd ubus method. The `read.file` exec entry for `luci-mwan3 nftset dump` is therefore no longer exercised by the rule editor. It is retained in the ACL file for compatibility but is effectively obsolete.

The `read.ubus` section for this group grants permission to call: `mwan3.status`, `mwan3.nftset_members`, `mwan3.nftset_info`, and `mwan3.nftset_elements` (added in v3.5 for the IP Sets status tab).

**`luci-app-mwan3-status`** (status/diagnostic access): The `read.ubus` section grants permission to call: `mwan3.status`, `mwan3.nftset_members`, `mwan3.nftset_info`, `mwan3.nftset_elements`, and `mwan3.routing_health`. The `write.file` section grants exec permission for the `diag` subcommands, `mwan3 internal`, `mwan3 ifup`, and `mwan3 ifdown`.

### 14.4 `interface.js` - Interface Settings UI

A "Track gateway" checkbox was added to the interface configuration modal, visible only when the internet protocol is set to IPv4. This exposes the `track_gateway` UCI option for automatic point-to-point peer/gateway discovery (see [Section 16.3](#163-automatic-gateway-tracking-track_gateway)).

An "IPv6 SNAT" text field was added to the same modal, visible only when the internet protocol is set to IPv6. This exposes the `snat6` UCI option for opt-in IPv6 SNAT of mwan3-rerouted router-originated traffic (see [Section 16.5](#165-opt-in-ipv6-snat-via-per-interface-snat6)). The field accepts an empty value or `0` (default - disabled), `1` (SNAT to the interface's primary global address resolved via `mwan3_get_src_ip`), or a literal IPv6 address (NPTv6-style fixed-source pinning).

The help text for the `flush_conntrack` option was also updated to clarify that it flushes the entire global conntrack table, and that per-interface conntrack entries are now flushed automatically on ifdown (see [Section 16.1](#161-selective-conntrack-flush-on-interface-down)).

---

## 15. Iptables-to-nftables Porting Notes

Key translation patterns used in this port, useful for anyone maintaining or extending the code:

| iptables Concept | nftables Equivalent | Notes |
|---|---|---|
| `iptables -t mangle` | Chains in `table inet mwan3` | mwan3's own standalone table at mangle priority |
| `-A PREROUTING -j chain` | Own hook chain at `priority mangle + 1` | No need to jump from fw4's chain; own table is independent |
| `-A OUTPUT -j chain` | Own `type route` hook chain | Must be `type route` for mark-based rerouting |
| `iptables-restore -T mangle -n` | `nft -f batchfile` | Batch file for atomic multi-command operations |
| `-N chain` | `nft add chain inet mwan3 name` | |
| `-F chain` | `nft flush chain inet mwan3 name` | |
| `-X chain` | `nft delete chain inet mwan3 name` | Must be empty first |
| `-D chain match...` | `nft delete rule ... handle N` | Must look up handle with `nft -a` |
| `-j MARK --set-xmark V/M` | `meta mark set meta mark & ~M \| V` | See `mwan3_nft_mark_expr()`; use `&`/`\|` symbols not keywords |
| `-j CONNMARK --restore-mark --nfmask M` | vmap-dispatch into `mwan3_or_meta_<imm>` setter chains | Non-destructive masked restore. Kernel rejects the compound `(meta mark & ~M) \| (ct mark & M)`; vmap-dispatch synthesises the same effect via per-mark OR-immediate setter chains. See [§2 Connmark Operations](#connmark-operations). |
| `-j CONNMARK --save-mark --nfmask M` | `ct mark set ct mark & ~M`, then vmap-dispatch into `mwan3_or_ct_<imm>` setter chains | Non-destructive masked save. Same kernel limitation, same vmap-dispatch workaround. |
| `-m mark --mark V/M` | `meta mark & M == V` | |
| `-m set --match-set S dst` | `ip daddr @S` | Set lives in `table inet mwan3` |
| `-m statistic --probability P` | `numgen inc mod N map { ... }` | Deterministic round-robin instead of probabilistic |
| `-m multiport --dports P` | `th dport { P1, P2 }` | `th` = transport header (works for tcp/udp) |
| `-m icmp6 --icmpv6-type T` | `icmpv6 type { T1, T2, ... }` | |
| `-p ipv6-icmp` | `icmpv6 type { ... }` | Protocol match is implicit |
| `ipset create S hash:net` | `set S { type ipv4_addr; flags interval; auto-merge; }` | Defined via `config ipset` in mwan3 UCI; `auto-merge` handles overlapping elements |
| `ipset add S element` | `nft add element inet mwan3 S { element }` | |
| `ipset flush S` | `nft flush set inet mwan3 S` | |
| `ipset create S hash:ip,mark` | `map S { type addr : mark; flags dynamic,timeout; }` | Maps store key->value pairs |
| `-j SET --add-set S src,src` | `update @S { ip saddr : meta mark & M }` | |
| `-m set --match-set S src,src` | `meta mark set ip saddr map @S` | Regular map lookup (not `vmap` which requires verdicts) |
| Separate ipv4/ipv6 chains | Single `inet` chain + `meta nfproto` | Or just `ip`/`ip6` selectors in rules |

> [!WARNING]
> **Key kernel limitations to be aware of:**
>
> - **No compound two-source bitwise:** Expressions like `meta mark set meta mark | ct mark & X` or `ct mark set ct mark & ~M | meta mark & M` fail with "Operation not supported". Each set expression can only draw from one register source. **Workaround:** synthesise the masked operation via `vmap`-dispatch into per-mark setter chains whose body is a single-source `meta/ct mark | <constant immediate>`. mwan3 uses this for masked connmark save and restore - see [§2 Connmark Operations](#connmark-operations).
> - **No numgen in compound expressions:** `meta mark set meta mark & COMP | numgen inc mod N map { ... }` fails for the same reason. Use `meta mark set numgen ...` with a guard condition ensuring the target bits are already zero.
> - **vmap vs map:** `vmap` expects verdict values (accept/drop/jump), not data values like marks. For IP→mark lookups, use regular `map`.
> - **`nft add set` flag immutability:** Creating a set is idempotent, but flags (like `auto-merge`) cannot be updated on existing sets. Must delete and recreate to change flags.

---

## 16. Enhancements

The following enhancements were made after the initial nftables port, building on the new architecture.

### 16.1 Selective Conntrack Flush on Interface Down

**Problem:** When a WAN interface fails, mwan3track detects the failure and triggers an ifdown event. The policies are rebuilt to exclude the failed interface, but existing conntrack entries still carry the old interface's fwmark. TCP flows on the failed WAN wait for retransmit timeout (typically 15-30 seconds) before re-establishing via the updated policy. The existing UCI `flush_conntrack` mechanism flushes the *entire* global conntrack table, which is disruptive to all connections including those on healthy WANs.

**Solution:** On ifdown, `mwan3_flush_conntrack()` now uses the `conntrack` tool to selectively delete only the conntrack entries matching the failed interface's fwmark:

```sh
conntrack -D --mark "${iface_mark}/${MMX_MASK}"
```

This forces only the flows that were using the failed WAN to immediately re-establish via the updated policy, while leaving connections on healthy interfaces untouched. The feature requires the `conntrack` package and falls back gracefully (no-op) if it is not installed.

> [!NOTE]
> This is independent of the UCI `flush_conntrack` option. The selective flush always runs on ifdown when `conntrack` is available, regardless of the UCI setting. The UCI option continues to control the legacy behaviour of flushing the entire conntrack table on specific events.

**Files changed:** `lib/mwan3/mwan3.sh` (`mwan3_flush_conntrack()`)

### 16.2 Software Flow Offloading Co-existence

**Problem:** When fw4 software flow offloading (`option flow_offloading '1'`) is active, the kernel's flowtable caches routing decisions for established flows. These flowtable entries bypass mwan3's PREROUTING chains entirely, so when mwan3 rules/policies change (e.g., on `start_service` or reload), existing offloaded flows continue using stale routing decisions until they naturally expire.

**Solution:** At the end of `start_service()`, after all nft rules and policies are in place, mwan3 checks whether software flow offloading is enabled. If so, it flushes all conntrack entries by writing to `/proc/net/nf_conntrack`:

```sh
echo f > /proc/net/nf_conntrack
```

This destroys the flowtable entries, forcing all flows to re-enter the normal packet path where they are classified by the new mwan3 rules. The flush occurs only at service start/reload, not on every interface event.

> [!NOTE]
> This does not apply to hardware flow offloading, which uses different kernel mechanisms. Hardware offloaded flows are not affected by conntrack flushes.

**Files changed:** `etc/init.d/mwan3` (`start_service()`)

### 16.3 Automatic Gateway Tracking (`track_gateway`)

**Problem:** On point-to-point links (such as PPPoE), the next-hop gateway IP changes on each connection and is not known in advance. Users must manually configure `track_ip` addresses (typically public DNS servers) for mwan3track health probes. While this works, it doesn't test the actual link peer and requires external IP addresses to be reachable.

**Solution:** A new per-interface UCI option `option track_gateway '1'` causes mwan3 to automatically discover the point-to-point peer/gateway IP and add it to the tracking list at runtime.

#### How It Works

1. `mwan3_update_peer_track_ip()` queries `ifstatus` for the interface's `ptpaddress` field (the point-to-point peer IP)
2. If found, the gateway IP is written to `$MWAN3TRACK_STATUS_DIR/<iface>/GATEWAY`
3. `mwan3track` reads this file and **prepends** the gateway IP to the front of the probe list, ensuring it is always probed first on every round regardless of the `reliability` threshold. (Static `track_ip` entries follow after the gateway.)
4. On interface bounce, the hotplug `ifup` action calls `mwan3_update_peer_track_ip()` again, overwriting the state file with the new peer IP

The gateway IP is stored as ephemeral state rather than committed to UCI, preventing stale IP accumulation across reboots or gateway changes. An interface definition may specify only `track_gateway` and omit static tracking IPs. The option is silently ignored if no next-hop peer exists (e.g., on Ethernet WAN interfaces).

> [!WARNING]
> **IPv4 only in practice.** For IPv6 point-to-point links, the peer is typically a link-local address (e.g., `fe80::1`). Pinging link-local addresses requires interface scope specification (`ping6 fe80::1%pppoe-wan`), which mwan3track's WRAP/ping mechanism does not handle. The option will be silently ignored if no peer address is found.

#### UCI Configuration

```
config interface 'wan'
    option enabled '1'
    option track_gateway '1'
    # track_ip entries are optional when track_gateway is used
    # list track_ip '8.8.8.8'
```

**Files changed:** `lib/mwan3/mwan3.sh` (`mwan3_update_peer_track_ip()`), `etc/init.d/mwan3` (`start_tracker()`), `etc/hotplug.d/iface/25-mwan3` (ifup action)

### 16.4 Postrouting SNAT for Rerouted Router-Originated Traffic (IPv4)

**Problem:** When the router itself originates an IPv4 packet, the kernel binds the source address at `sendto()` time using the *unmarked* initial route lookup. mwan3's mark is not set at that point, so the kernel picks the saddr corresponding to whichever WAN the unmarked default route points at - call it WAN-A. Later in the egress path, `mwan3_output` sets a mark and (because the chain is `type route`) the kernel performs a re-lookup that may move the outgoing interface to WAN-B. The reroute updates `oif` but does *not* rewrite the source address - that was already set. The packet would leave WAN-B with WAN-A's source address and be dropped upstream by BCP38 / uRPF filtering.

mwan3track is unaffected: it sets `SO_BINDTODEVICE` at socket creation, which forces the correct saddr at bind time before any of this happens.

**Why no explicit SNAT is needed for IPv4:** fw4's `srcnat_wan` masquerade applies to all outgoing traffic, including locally-originated. When a rerouted packet reaches the `srcnat` hook, masquerade picks the primary IP of the actual outgoing interface and rewrites the source address correctly. No per-interface SNAT rule is required from mwan3 - fw4 handles it.

The IPv6 case is different because fw4 does not masquerade IPv6 by default. See [§16.5](#165-opt-in-ipv6-snat-via-per-interface-snat6).

### 16.5 Opt-in IPv6 SNAT via Per-Interface `snat6`

**Problem:** The router-originated, mark-rerouted, wrong-saddr failure mode described in §16.4 also exists for IPv6, but fw4 provides no masquerade fallback for IPv6. The iptables version of mwan3 also did not address it. A packet whose saddr was bound to WAN-A's prefix but rerouted onto WAN-B will egress with WAN-A's source prefix and be dropped upstream by BCP38/uRPF.

- IPv6 has no equivalent of fw4's IPv4 masquerade, so unlike the IPv4 case there is no automatic safety net.

**Why a default-on fix is wrong for v6:** Several reasons make blanket NAT66 a bad default:

1. **RFC 6724 source-address selection sometimes solves it without NAT.** A host with multiple v6 addresses configured and source-address-dependent routes (SADR) in the routing table can pick the correct saddr at socket-bind time and the problem never arises. A default-on SNAT would silently mask working RFC 6724 / SADR machinery and degrade deployments that were doing v6 multihoming correctly.
2. **NAT66 is actively harmful in some topologies.** ULA + delegated-PA designs depend on end-to-end addressing. Address-embedding protocols (SIP, FTP, IPsec keying, anything using referrals) break.
3. **Some upstreams require a specific source.** Tunnel brokers (Hurricane Electric), fixed-address WireGuard endpoints, and similar links only accept packets from a specific saddr.
4. **RFC 4864 / RFC 6296 stance.** The IPv6 community treats address translation as a deliberate, opt-in choice - never a default.

**Solution:** Version 3.2 introduces an opt-in per-interface UCI option `snat6`. The semantics are:

| value | meaning |
|---|---|
| unset / `0` | no v6 SNAT - current default behaviour, preserves the iptables-era v6 baseline |
| `1` | SNAT to the interface's primary global address, looked up via `mwan3_get_src_ip` (which already handles ipv6 family with prefix-delegation fallback) |
| `<v6 addr>` | SNAT to the literal address. Used for NPTv6-style fixed mappings or where the operator wants to pin a specific source from a delegated /64. The literal value is not validated against the device - some deployments deliberately use addresses not configured on the egress interface. |

The installed nft rule mirrors the v4 form structurally but uses `meta nfproto ipv6` and `ip6 saddr`:

```
oifname "<dev>" meta nfproto ipv6
    meta mark & MMX_MASK == <iface_mark>
    fib saddr type local
    ip6 saddr != <iface_src_ip>
    snat to <iface_src_ip>
```

The `mwan3_postrouting` base chain hosts v6 SNAT rules. The stale-rule cleanup loop in `mwan3_create_iface_nft()` and `mwan3_delete_iface_nft()` matches by comment tag (`mwan3_snat_<iface>`).

#### UCI Configuration

```
config interface 'wan6'
    option enabled '1'
    option family 'ipv6'
    option snat6 '1'
```

The corresponding LuCI control is described in [§14.4](#144-interfacejs--interface-settings-ui).

#### Scope of this enhancement

`snat6` only addresses the router-originated rerouted case (`fib saddr type local`). It does **not** extend mwan3's IPv6 capability beyond what the iptables version offered. A more complete v6 multihoming story (forwarded LAN traffic, dual-PA + SADR integration, NPTv6 prefix translation, PD renewal handling) is intentionally out of scope for this release.

**Files changed:** `lib/mwan3/mwan3.sh` (`mwan3_create_iface_nft()`), `applications/luci-app-mwan3/.../interface.js` (LuCI form field).

---

### 16.6 Tabs: Simulator, Configuration Checker, Routing Health and IP Sets

**Problem:** mwan3's routing model - ip rules, fwmark values, routing tables, and nft sets - is opaque to users who did not build it themselves. When traffic takes an unexpected path, or when a configuration change silently breaks policy routing, a non-expert user has no way to understand why without knowing which tools to run and how to interpret their output. Three diagnostic tabs were added to luci-app-mwan3 to close this gap.

---

#### 16.6.1 Traffic Path Simulator

**Location:** Network > MultiWAN Manager > Simulator

The Simulator tab lets the user describe a packet (source IP, destination IP, protocol, ports, address family) and see which mwan3 rule would match it first, what policy that rule assigns, and the live state of the policy's members at the moment of simulation.

**Input semantics:** all fields are optional. A blank field acts as a constraint on the *user's packet*, not a wildcard that bypasses rule matching. Specifically, if a field is left blank and a rule has a constraint on that field, the rule will not match. This mirrors mwan3's runtime behaviour: a rule with `dest_ip 10.0.0.0/8` never matches traffic with no destination.

**Connected-network bypass:** Before the rule walk, the tab checks the destination IP against the `mwan3_connected_v4` and `mwan3_connected_v6` nft sets in `table inet mwan3`. If the destination falls in a directly connected subnet, a dedicated card is shown explaining that mwan3 exempts connected networks from policy routing entirely.

**Matching implementation:**

- IPv4 CIDR matching uses uint32 arithmetic with `>>> 0` to maintain unsigned semantics throughout (JavaScript bitwise operators produce signed 32-bit results).
- IPv6 CIDR matching uses BigInt with `::` expansion; the mask is computed as `all_ones XOR bottom_bits` to avoid shift-by-more-than-31 issues.
- Port matching handles single ports, comma- or space-separated lists, and colon-delimited ranges (`1024:2048`).
- nft set membership for rules that use `ipset` is fetched live via the `mwan3.nftset_members` ubus method at simulation time.

**Result display:** The first matching rule is shown in a bordered card coloured green (policy has active members), red (all members offline or policy not found in UCI), or orange (terminal built-in policy). Subsequent rules that also matched but are superseded are listed in a shadowed-rules table below. If no rule matches, a muted card reports that traffic will use the main routing table.

**Files:** `htdocs/luci-static/resources/view/mwan3/network/simulator.js`

---

#### 16.6.2 Configuration Consistency Checker

**Location:** Network > MultiWAN Manager > Configuration

The Configuration tab performs static analysis of the mwan3 UCI configuration without consulting any live system state. It runs automatically when the tab loads.

**Checks performed:**

*Errors (definite misconfiguration):*

- Member references an interface not defined in mwan3 UCI
- Policy references a member not defined in mwan3 UCI
- Rule references a policy not defined in mwan3 UCI (traffic silently blackholed)
- Policy has no members

*Warnings (likely misconfiguration):*

- Member not used by any policy (orphaned)
- Policy not used by any rule (orphaned)
- Interface not referenced by any member (orphaned)
- Policy has multiple members but all reference the same physical interface (no failover if that interface goes down)
- Rule is unreachable because an earlier rule matches a superset of its traffic

**Rule shadowing check:** Rule A is conservatively considered a superset of rule B if A has no tighter constraint than B on every field (family, protocol, source IP CIDR, destination IP CIDR, source port, destination port). The CIDR containment is implemented for both IPv4 (uint32) and IPv6 (BigInt). ipset containment is not checked - only clear-cut address-range cases are flagged.

**Built-in policies:** `unreachable`, `blackhole`, and `default` are hardcoded as valid policy names and are not flagged as undefined when referenced by rules.

**Files:** `htdocs/luci-static/resources/view/mwan3/network/configuration.js`

---

#### 16.6.3 Routing Table Health Check

**Location:** Status > MultiWAN Manager > Routing

The Routing tab compares the live kernel ip rule and routing table state against the mwan3 UCI configuration. It refreshes automatically via `poll.add`.

**Per-interface cards:** One card per UCI interface, colour-coded by health:

| State | Colour | Meaning |
|---|---|---|
| Green | success | Online, both ip rules present, routing table has a default route |
| Orange | warning | Degraded - online with a rule missing, or offline with rules unexpectedly present |
| Red | danger | Online but ip rules or routing table default route missing |
| Grey | muted | Offline or unknown status, rules absent - normal state |

Each card shows the interface's UCI index N, its current mwan3track status, and for each of the two ip rules (iif at priority 1000+N, fwmark at priority 2000+N) and the routing table (table N) whether the expected state is present or absent. Rule badges use `online` as the `expectedPresent` value so that absent rules on an offline interface show as "Absent" (grey) rather than "Missing" (red).

**Stale rule detection:** Any ip rule with a priority in mwan3's iif range (1001-1063) or fwmark range (2001-2063) that does not correspond to a current UCI interface is reported as stale. The built-in blackhole (`FWMARK_BASE + MAX_IFACES - 2 = 2061`) and unreachable (`FWMARK_BASE + MAX_IFACES - 1 = 2062`) policy rules are explicitly excluded from stale detection.

**Field reference panel:** A static explanatory panel below the interface cards describes the Index (N), iif rule, and fwmark rule fields for users unfamiliar with policy routing internals.

**Files:** `htdocs/luci-static/resources/view/mwan3/status/routing.js`

---

#### 16.6.4 IP Sets Configuration Tab

**Location:** Network > MultiWAN Manager > IP Sets (order 52, between Rule and Simulator)

A dedicated tab for managing `config ipset` sections in `/etc/config/mwan3`. Each section corresponds to a named nft set in `table inet mwan3`.

**Fields:**

- `name`: nft set name. Validated against `^[a-zA-Z0-9_]+$`. Marked pristine on new-section render so the red validation indicator does not appear until the user interacts or clicks Save.
- `family`: IPv4 or IPv6. Controls set type and cross-validates against `entry` values.
- `entry`: DynamicList. Family cross-check validates each entry on blur (keyup suppressed). IPv4 addresses are rejected when family is IPv6 and vice versa.
- `domain`: DynamicList. Domain names for dnsmasq nftset population.
- `loadfile`: FileUpload for a file containing addresses/CIDRs.
- `maxelem`: placeholder shows "unlimited" (value 0 means no limit, matching fw4 behaviour).
- `timeout`: seconds, 0 = no timeout.
- `counters`: checkbox enabling per-element packet/byte counter tracking.
- `enabled`: enable/disable the set without removing it.

**Deletion guard:** Deleting a set referenced by mwan3 rules is blocked with a warning notification listing the referencing rules.

All sets in this tab live in `table inet mwan3` and do not overlap with the firewall's IP Sets tab which manages `table inet fw4`.

---

#### 16.6.5 IP Sets Status Tab

**Location:** Status > MultiWAN Manager > IP Sets (order 27, between Routing and Diagnostics)

Displays runtime state for all user-defined nft sets. Calls `nftset_info` on page load for set metadata (type, counters flag, runtime element count) and loads UCI config for static parameters.

Each set is rendered as a collapsible panel. On first expand, domain names from UCI are shown immediately, then runtime members are loaded via `nftset_elements` RPC. Members display as a 3-column table (Address / Packets / Bytes); Packets and Bytes are empty for sets without counters.

Large sets: 200 default, Load more (1000) and Load all (5000) buttons shown when the set is truncated.

---

#### 16.6.6 rpcd Methods

Two new methods were added to `usr/share/rpcd/ucode/mwan3` and declared in `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`.

**`mwan3.nftset_members { set: "<name>" }`**

Returns the current members of a named nft set in `table inet mwan3`. The set name is validated against `^[a-zA-Z0-9_-]+$`. Returns `{ members: [ ... ] }`. Used by the Simulator for ipset rule matching and connected-network bypass detection.

**`mwan3.routing_health {}`**

Compares the UCI configuration against live kernel state. For each mwan3 interface (by 1-based UCI order index N):

- Checks for ip rule at priority 1000+N (iif) and 2000+N (fwmark) via `ip -j rule list`
- Checks routing table N for a default route via `ip -4/-6 -j route list table N`
- Reads `/var/run/mwan3track/<ifname>/STATUS` for current online/offline state
- Reports stale ip rules (priorities in mwan3's range with no matching UCI interface)
- Reports whether mwan3 is actively running (presence of any `STATUS` file under `/var/run/mwan3track/`)

**Files changed:** `files/usr/share/rpcd/ucode/mwan3`, `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`, `root/usr/share/luci/menu.d/luci-app-mwan3.json`

---

### 16.7 mwan3-lb-test: Load Balancing Distribution Verifier

A diagnostic tool `/usr/sbin/mwan3-lb-test` verifies that load balancing is distributing traffic across policy members in the expected proportions.

#### Usage

```
mwan3-lb-test [-6] -c <client_ip> <policy_name> [ip1 ip2 ...]
mwan3-lb-test cleanup
```

`-6` selects IPv6 mode. `-c <client_ip>` is mandatory and specifies the LAN client that will run the test pings. Optional IP arguments override the default destination pool. The `cleanup` subcommand removes stale sets and rules from an aborted run.

#### Design

- **NITER computation:** The number of test iterations is computed from member weights using GCD: `base_N = total_weight / GCD(weights)`, `NITER = base_N * ceil(30 / base_N)`. This ensures per-member expected hit counts are whole numbers and that NITER is always at least 30.
- **ICMP-only test rule:** A temporary `meta l4proto icmp ip daddr @mwan3_lb_test_<PID>` counter rule is inserted into `mwan3_rules` ahead of user rules. The ICMP restriction prevents DNS queries, TCP connections, and other traffic from contaminating the count. `-6` mode uses `meta l4proto ipv6-icmp ip6 daddr @set`.
- **Client isolation:** A `forward` chain drop rule blocks pings to the test destination set from all LAN clients except the nominated test client (`-c`). An `mwan3_output` return rule bypasses mwan3 marking for any router process pinging the same IPs. Both rules are scoped to the test set and removed on exit.
- **Tracking IP exclusion:** The default destination pool excludes IPs already configured as mwan3 `track_ip` values. mwan3track pings those IPs via `mwan3_output -> mwan3_rules`, which would match the test rule and inflate the count.
- **Windows command:** A `cmd.exe` `for` loop is output alongside the Linux shell loop. Windows `ping` uses a fixed ICMP identifier (id=1), causing conntrack entry reuse on repeated pings to the same destination. The Windows command uses an inter-ping delay of `30/TRACK_COUNT + 3` seconds so the full cycle through all test IPs exceeds the 30s ICMP conntrack timeout, ensuring each revisit generates a fresh conntrack entry. The IP list is formatted with `^` line continuation at 4 IPs per line.
- **Cleanup:** Removes the temporary set and rules on normal exit, SIGINT, SIGTERM, and SIGPIPE. A startup sweep removes stale `mwan3_lb_test_*` sets and rules from any aborted previous run.

**Files changed:** `usr/sbin/mwan3-lb-test` (new), `Makefile`

---

### 16.8 Source NFT Set Matching (`ipset_src`)

A new `ipset_src` UCI option on rule sections enables source address matching via nft sets, complementing the existing `ipset` option (destination address matching).

#### UCI Example

```
config rule 'corp_to_wan2'
    option ipset_src corp_clients
    option ipset     blocked_dests
    option use_policy wan2_policy
```

This generates:

```
ip saddr @corp_clients ip daddr @blocked_dests meta mark & 0x3f00 == 0 jump mwan3_policy_wan2_policy
```

Both `ipset_src` and `ipset` can be set on the same rule and are ANDed together. The existing `ipset` option (destination) is unchanged for backward compatibility with existing configurations.

The same pre-creation logic used for `ipset` applies to `ipset_src`: if the named set does not yet exist in `table inet mwan3`, `mwan3_set_user_nft_rule()` pre-creates it with the appropriate type to prevent the nft batch from failing atomically. A present `ipset_src` is treated as an implicit family qualifier by the `meta nfproto` guard condition in `mwan3_set_user_nft_rule()`, consistent with `src_ip`, `dest_ip`, and `ipset`.

**Files changed:** `lib/mwan3/mwan3.sh`

---

### 16.9 mwan3-diag: Network Diagnostic Report

`mwan3-diag` is a ucode diagnostic script installed to `/usr/sbin/mwan3-diag` that collects a comprehensive snapshot of the network state relevant to mwan3 operation. It is intended to produce a report that can be posted in a forum thread or bug report without manual redaction.

#### Usage

```
mwan3-diag
```

The script collects interface addresses, routing tables (including all per-WAN tables), policy rules, neighbour cache, mwan3 interface status, the mwan3 UCI configuration, the complete mwan3 nftables ruleset, the fw4 mangle chains that interact with mwan3 packet marking, and the last 200 lines of the mwan3 log.

Before printing any output the script builds a map of every public routable IPv4 and IPv6 address present in the collected data and replaces each one with a stable placeholder -- `PUB4_1`, `PUB4_2`, `PUB6_1` and so on -- throughout the entire report, including free-form text such as nftables rules and log lines. The same address always receives the same placeholder, so cross-references between sections remain consistent. Private addresses (RFC1918, link-local `fe80::`, ULA `fc00::/7`, loopback) are left unchanged as they are diagnostically important. The elements of user-defined nftables sets are replaced with `{ ... }` rather than disclosed.

**Files changed:** `usr/sbin/mwan3-diag` (new), `Makefile`

---

## 17. Changelog

### 17.1 Version 3.5.2

**Summary:** Version 3.5.2 is a bug-fix and maintenance release. It corrects a misrouting bug where kernel-generated NDP Neighbor Solicitation probes entered `mwan3_output` without a conntrack entry, fell through to `mwan3_rules`, and received a WAN policy mark that caused the kernel to probe the gateway via the wrong interface, cycling the NDP entry to FAILED state and breaking WRAP ping tracking for that interface. It updates the package dependency from `ip` to `ip-full` to ensure the full iproute2 implementation is always present, since the busybox `ip` is a minimal subset that does not support all options mwan3 requires. It adds `mwan3-diag`, a ucode diagnostic script installed to `/usr/sbin/mwan3-diag` that collects a comprehensive snapshot of mwan3 state -- interface status, policy routing rules, nftables ruleset, routing tables, conntrack summary and system log -- with all public IP addresses anonymised with stable placeholders so output can be shared safely.

---

#### mwan3: add mwan3-diag network diagnostic script

mwan3-diag is a ucode script that collects a comprehensive snapshot of mwan3 state. It gathers interface status, policy routing rules, nftables ruleset, routing tables, conntrack summary, system log and anonymises all public IP addresses with stable placeholders so output can be shared safely.

---

#### mwan3: depend on ip-full instead of ip

The busybox ip implementation is a minimal subset of iproute2 and does not support all options and subcommands that mwan3 requires for correct operation. Depend on ip-full to ensure the full iproute2 implementation is always present.

---

#### mwan3: bypass NDP in mwan3_output to prevent re-routing of NDP probes

Kernel-generated NDP Neighbor Solicitation probes start with mark=0 and enter mwan3_output. They have no conntrack entry, so the ct mark restore is a no-op. They are not matched by mwan3_connected, mwan3_custom, or mwan3_dynamic. They fall through to mwan3_rules, where the default IPv6 rule (ip6 daddr ::/0) applies a WAN policy mark -- the same mark that would be assigned to outbound user traffic. Because mwan3_output is type route, the mark change triggers a routing re-evaluation, which may route the probe to a different WAN interface than the one whose gateway the kernel is trying to resolve. The gateway NDP entry cycles to FAILED state, and subsequent WRAP ping probes are dropped because the kernel cannot resolve the gateway MAC address.

Add an icmpv6 NDP accept rule at the top of mwan3_output, mirroring the equivalent rule already present in mwan3_prerouting.

---

### 17.2 Version 3.5.1

**Summary:** Version 3.5.1 is a bug-fix and maintenance release. It corrects a silent failure in `mwan3rtmon` where route replication to per-interface routing tables was completely non-functional, adds nft set flag-change detection on reload so that changing a set's timeout, counter, or size options takes effect immediately without requiring a full service restart, suppresses spurious stderr noise from ip rule and ip route operations during upgrades and teardown, and removes version number references from comments.

---

#### mwan3: fix mwan3rtmon route replication broken by stale table name

`refresh_active_chains()` filtered for chains in `table inet fw4` instead of `table inet mwan3`. Because mwan3's interface chains live in `table inet mwan3`, the `active_chains` cache was always empty. Every caller that depended on it -- `is_iface_nft_active`, `get_active_tids`, `populate_iface_routes`, and the route-replication path in `handle_route_event` -- silently did nothing. Route replication from the main routing table to per-interface routing tables was completely non-functional.

Most deployments did not notice because `mwan3_create_iface_route` in the hotplug script populates per-interface tables at ifup time, covering the static routing table case. The bug manifests when routes are added to or removed from the main table after mwan3 starts (VPN tunnels, PPPoE reconnection, etc.).

The connected set population path (`populate_connected_set`) was unaffected by the bug and continues to work correctly.

---

#### mwan3: detect nft set flag changes on reload and delete+recreate as needed

`nft add set` is idempotent on existence: if a set already exists it returns without error but does not update its flags (timeout, counters, size). A reload that changed any of these flags silently left the live set with the old configuration until the next full service restart.

Add `_mwan3_nft_time_to_sec` to parse nft time unit strings (`1h`, `5m`, `300s`) into a common integer-seconds representation for comparison. Add `_mwan3_ipset_needs_delete` which queries the live set via `nft list set` and returns true if the live flags differ from the desired spec.

`_mwan3_render_one_ipset` now calls `_mwan3_ipset_needs_delete` before the `add set` statement. If flags differ the set is deleted first, clearing its elements but ensuring the recreated set has the correct type, timeout, counter, and size flags.

When a set is deleted and recreated its dnsmasq-populated domain entries are lost. Set `MWAN3_NEED_DNSMASQ_HUP` when this occurs and call `mwan3_dnsmasq_hup` after the reload batch in `reload_service` to repopulate those entries.

Move the ipset and dnsmasq fragment functions from `common.sh` to `mwan3.sh`. They are only called from `mwan3.sh` or `init.d/mwan3`, and the new helpers (`_mwan3_nft_time_to_sec`, `_mwan3_ipset_needs_delete`) naturally belong with them.

---

#### mwan3: remove version number references from comments

Comments referencing specific version numbers become misleading as the codebase evolves. Replace all such references with descriptions of the actual state or behaviour they document.

---

#### mwan3: suppress stderr on unguarded ip rule/route operations

Four locations in `mwan3.sh` produced noise on stderr during package upgrades and edge-case teardown:

- `mwan3_create_iface_rules`: ip rule add calls had no error suppression. `mwan3_delete_iface_rules` runs first, so a "File exists" error means the rule is already in the desired state - a valid outcome that should not be reported as an error.

- `mwan3_delete_iface_route`: ip route flush on a never-populated table produces "FIB table does not exist". This is a normal teardown scenario when an interface was never brought online.

- `mwan3_extra_tables_routes`: ip route list on a missing rt_table_lookup table produces the same error. Suppressed here without a warning since this is called per-interface per-connect; `mwan3_set_custom_set` provides the warning at a more appropriate point.

- `mwan3_set_custom_set`: ip route list calls restructured to capture output and check exit code separately, so a missing rt_table_lookup table is suppressed on stderr but logged via LOG warn. This preserves the error as a diagnosable signal without printing raw kernel errors to the console.

---

### 17.3 Version 3.5

**Summary:** Version 3.5 is a major architectural release that moves mwan3 out of `table inet fw4` and into its own `table inet mwan3`, eliminating the fw4 rebuild scaffold and the mwan3evtd debounce daemon entirely. 

The reload path is replaced with a single atomic nft batch that commits the complete new ruleset while the old one is still serving traffic, with zero window of misrouted connections. User-declared nft sets are now configured directly in `/etc/config/mwan3` with inline, file, and dnsmasq-populated modes, and per-element packet and byte counters are optionally available. The APK install lifecycle is hardened to eliminate RTNETLINK errors on both fresh install and upgrade. LuCI gains a full IP Sets configuration tab and a new IP Sets status view with paginated element display, and the overview layout is redesigned with CSS grid cards. Additional bug fix to debounce `RTM_NEWROUTE` calls in `mwan3rtmon`.

---
#### mwan3: update mwan3rtmon to debounce RTM_NEWROUTE calls

`RTM_NEWROUTE` events for connected routes were fast-pathed directly to `nft_exec`, bypassing the debounce timer that was only applied to deletes. On IPv6 systems with prefix delegation, the kernel appears to send repeated `RTM_NEWROUTE` updates for already-present connected routes, causing nft processes to be spawned multiple times per second and producing measurable CPU load.

Fix: route both `RTM_NEWROUTE` and `RTM_DELROUTE` for CIDR routes through the same 100ms debounce timer, calling `populate_connected_set()` once after the burst settles rather than once per event. Add a fingerprint (sorted, joined element list) to `opulate_connected_set()` so that calls where the connected set content has not changed skip the `nft_batch` call entirely. Also add ECMP deduplication (seen map) and link-local filtering to the element build loop in `populate_connected_set()`.

---

#### mwan3: add conntrack as a hard dependency

mwan3 relies on the conntrack userspace tool in several places: `flush_conntrack` is called when interfaces go down or policies change to force existing connections to be re-evaluated under the new routing state. Without conntrack installed these operations silently fail, leaving stale connections pinned to a dead or reconfigured WAN interface. Making the dependency explicit ensures conntrack is always present when mwan3 is installed.

---

#### mwan3: add counters support, nftset_elements RPC, and orphaned set cleanup

Add option counters (bool, default 0) to config ipset sections. When set, enables per-element packet and byte count tracking via nft set counter statement.

Change `maxelem` default from 65536 to 0 (unlimited), matching fw4 behaviour where sets have no size limit unless explicitly configured.

Add `mwan3_cleanup_orphaned_ipsets`, called during reload_service after `mwan3_render_config_ipsets`. Queries nft for user-defined sets not prefixed mwan3_, compares against configured set names, and deletes any orphans. Prevents stale sets accumulating when a set is removed via LuCI and the config is applied.

rpcd ucode: refactor `get_nftset_members` to use a shared `parse_elem_val` helper; add `get_nftset_elements` which returns elements with optional per-element counter data (packets/bytes) and supports pagination via a max parameter; add `count_nftset_elements` for lightweight element counting; enhance `nftset_info` to include flags, counters, and count fields; add `nftset_elements` RPC method with a 5000-element hard cap.

---

#### mwan3: atomic non-destructive reload via single nft batch

Replaces the stop/start reload_service with an atomic single `nft -f` batch that rebuilds the entire ruleset while the old one serves traffic. The batch commits in one kernel transaction with zero window of misrouted traffic.

No conntrack flush in reload: existing connections keep their ct marks and current routing; new connections use new rules immediately.

Race condition immunity:

Reload: the entire rebuild is a single `nft -f` batch. The kernel commits the complete new ruleset atomically or rolls back to the old one. There is no intermediate state where prerouting exists but iface_in chains are absent. Adding or removing an interface requires a full restart because procd service instances for new trackers can only be registered during `start_service`. The tracker mismatch check at the end of reload_service detects the discrepancy and falls through to stop/start automatically.

Startup: the `wait $hotplug_pids` barrier in `start_service` ensures all background ifup jobs complete before `mwan3_set_general_nft` populates prerouting. Prerouting's vmap dispatch never references a chain that does not yet exist.

---

#### mwan3: update mwan3-lb-test for standalone table inet mwan3

`mwan3-lb-test` creates a temporary test set and inserts rules into `mwan3_output`, `mwan3_rules`, and fw4's forward chain. Moving mwan3 to its own `table inet mwan3` requires two changes.

Rename TABLE from "inet fw4" to "inet mwan3" so that `mwan3_output`, `mwan3_rules`, and the test set creation all target the correct table.

Introduce `FORWARD_TABLE="inet fw4"` for the forward isolation rule. nft sets are table-scoped: the forward chain lives in `table inet fw4`, so the test set and the drop rule that references it must both exist in fw4. All forward chain operations (rule insertion, handle lookup, rule deletion, set creation/deletion, and stale-set cleanup) are updated to use `FORWARD_TABLE`.

---

#### mwan3: fix APK preinst and postinst for table inet mwan3

Fix the APK install lifecycle to ensure clean operation on both fresh install and upgrade from an installation that used table inet fw4.

Add a preinst script that stops mwan3 before APK replaces any files so that procd's inotify trigger does not auto-restart it during package installation. A safety-net stop at the start of postinst covers the case where preinst did not run or procd restarted the service between preinst and postinst.

Make the fw4 reload in postinst conditional on the `firewall.mwan3_reload` UCI section existing. On a fresh install that section is absent, so an unconditional reload triggers queued ifup hotplug events that cause a race with `mwan3_create_iface_rules`, producing `RTNETLINK "File exists"` errors. On upgrade the section exists, so the delete succeeds, and fw4 is reloaded exactly as before.

Add a second mwan3 stop immediately before the final mwan3 start in postinst. By this point the procd auto-start has completed and its ip rules are present. The second stop calls `stop_service` and removes them before `start_service` re-adds them, eliminating the remaining source of `RTNETLINK "File exists"` errors.

---

#### mwan3: remove mwan3evtd debounce daemon

`mwan3evtd` was introduced to debounce rapid-fire mwan3 rebuild events and deliver a single safe dnsmasq `SIGHUP` after each fw4 reload. Since mwan3 now lives in its own `table inet mwan3` which `fw4 reload` does not touch, there are no fw4-triggered rebuilds, no dnsmasq `SIGHUP`s from mwan3, and no event storms to debounce. `mwan3evtd` is redundant.

Remove the daemon, its init script, config file, helper binary, example files, and ACL. Remove the `ucode-mod-log` dependency (used only by `mwan3evtd`). Remove `/etc/config/mwan3evtd` from conffiles. Remove the `postinst enable/start` and `postrm stop/disable` calls.

The `postrm dnsmasq` cleanup (removing `mwan3-nftsets.conf` fragments and restarting dnsmasq) is retained since mwan3 still writes those fragments for domain-based config ipset population; removal of the package should clean them up so dnsmasq stops attempting to populate sets that no longer exist.

---

#### mwan3: fix port-range rendering for nftables

UCI stores port ranges as `x:y` (e.g. `'47813:47814'`) but nftables requires `x-y` (e.g. `'47813-47814'`). The colon is map-element syntax in nft; a set element like `{ 47813:47814 }` is rejected with "mapping outside of map context", causing the entire mwan3_rules batch to fail atomically and leaving the chain empty.

Fix: add `s/:/-/g` to the sed transform in `mwan3_set_user_nft_rule` for both `src_port` and `dest_port`. Old configs with colon separators and new configs with dash separators both work correctly after this change.

---

#### mwan3: auto-flush mwan3-marked conntrack on service reload

Add `mwan3_flush_marked_conntrack()` in `mwan3.sh` and invoke it from a new `reload_service` override in `init.d/mwan3`. Flushes every conntrack entry whose mark has any `MMX_MASK` bit set, so UCI-driven reloads (including the `uci-commit-trigger` path via `procd_add_reload_trigger`) cause live flows to re-enter the classification chains and re-evaluate against the new rules instead of staying pinned to a previously saved ct mark.

Complements the existing `mwan3_flush_stale_conntrack`, which handles the distinct zero-mark case (flow slipped through unclassified during the fw4-rebuild window). The two cover orthogonal cleanup needs.

conntrack's `-D --mark VALUE/MASK` filter does exact-match on the masked bits; there is no "any bit set" predicate. The helper iterates the mwan3 id-space (default 6 bits => 63 ids) and issues one targeted -D per id. Bounded and fast.

Not called from `start_service`: `service mwan3 restart` should leave live TCP flows intact; only a config-driven reload reclassifies them. The `mwan3_init` at the top of `reload_service` ensures `MMX_MASK` is populated before the flush, since stop wipes the persisted status dir.

Fixes the stale-ct-mark class of issues where a rule change does not take effect on a live flow, leaving it pinned to the old interface even after the user adds a mwan3 rule that should reclassify it.

---

#### mwan3: add table inet mwan3 nft set support

Add support for user-declared nft sets via a new config ipset section type in `/etc/config/mwan3` that matches fw4 syntax and replaces sets declared in /etc/config/firewall and which live within table inet fw4's namespace, which is not in scope in table inet mwan3.

Three population modes are supported: inline entries via list entry, file-based population via option loadfile, and dnsmasq-populated sets via list domain (mwan3 writes confdir fragments and signals dnsmasq only when fragment content changes).

Add `mwan3-migrate-ipset-v4.sh`, a one-shot idempotent migration helper that copies existing config ipset declarations from `/etc/config/firewall` to `/etc/config/mwan3` on upgrade from v3.x.  Called from postinst.  Makefile gains the corresponding install line and a postrm cleanup block that removes dnsmasq confdir fragments and reloads dnsmasq on package removal.

Update rpcd `nftset_info`: nftset membership lookup was filtering on `s.table == 'fw4'` but sets now live in `table inet mwan3`, so the filter is updated to `s.table == 'mwan3'`.

---

#### mwan3: move to standalone table inet mwan3, remove fw4 rebuild scaffold

Move mwan3 from `table inet fw4` to its own `table inet mwan3`.

Rename every inet fw4 literal to `inet mwan3` across `common.sh`, `mwan3.sh`, `init.d/mwan3`, `hotplug.d/iface/25-mwan3`, `usr/sbin/mwan3`, `mwan3rtmon`, and `usr/share/rpcd/ucode/mwan3`. The Makefile postinst retains its `inet fw4` references: those are legacy cleanup of v3.x-era chains that remain correct.

Add `files/lib/mwan3/mwan3-skeleton.nft`: a standalone nftables ruleset that creates (or atomically re-creates) `table inet mwan3` with its base chains and sets using the delete+recreate idiom for idempotency. Wire the skeleton load into `init.d/mwan3 start_service` with an early return on failure so subsequent nft add calls cannot paper over a missing table.

Delete `mwan3-fw-include.sh` and `mwan3-fw-rebuild.sh`. `fw4 reload` no longer touches `table inet mwan3`, so there is nothing to detect or rebuild. The fw4-include UCI registration script `mwan3-firewall-include` is replaced with `mwan3-remove-firewall-include`, a one-shot `uci-defaults` script that removes the stale `firewall.mwan3_reload` section left by v3.x installs. Remove the `fw4 reload` detection block from `25-mwan3`.

`stop_service` gains a final `nft delete table inet mwan3` so a clean stop leaves no nft residue.

Add postinst cleanup of legacy mwan3 chains, sets, and sticky maps from `table inet fw4` so upgrading from a v3.x install removes the old hooked chains that would otherwise remain after `fw4 reload` (fw4 uses `flush-table` not `delete-table`, so they survive indefinitely).

Simplify `mwan3_dnsmasq_hup` in `mwan3.sh` to a direct ubus call. The `mwan3evtd` dispatch path is no longer needed as mwan3 now lives in its own table and `fw4 reload` does not trigger rebuilds or `SIGHUP` storms. Call `mwan3_dnsmasq_hup` from `start_service` after all sets are created so dnsmasq clears its cache and re-populates the new nft sets.luci-app-mwan3: improve overview status layout

Switch the interface and policy card grids from flexbox to CSS grid with fixed 13em columns using repeat(auto-fill). Cards wrap gracefully as the browser is resized rather than forcing all items onto one row regardless of available width.

Replace the LuCI `%t` format with a custom `formatDuration()` that omits seconds, keeping the uptime display stable in width and removing the visual noise of a ticking seconds counter.

Add Interfaces and Policies section headings above each grid, matching the existing Rules heading, which also cleanly separates the two grids visually so their differing column counts do not appear misaligned.

Remove the indent from policy member entries and add white-space:nowrap to prevent wrapping within a member line on narrow columns.

---

#### luci-app-mwan3: add IP Sets status tab

New status view at Status > MultiWAN Manager > IP Sets (order 27, between Routing and Diagnostics).

- Page load calls `nftset_info` to get all user-defined mwan3 set metadata (type, counters flag, runtime element count) and loads mwan3 UCI config for each set's static parameters (entries, domains, loadfile, maxelem, timeout); element counts are shown in the panel header without requiring any user interaction

- Each set is shown as a collapsible panel with an Expand/Collapse toggle; on first expand, configured domain names (from list domain) are shown immediately from UCI, then the runtime member table is loaded via the new nftset_elements RPC; subsequent collapse/expand cycles reuse the already-loaded DOM without re-fetching

- Members are displayed in a consistent 3-column table (Address / Packets / Bytes) regardless of whether counters are enabled; Packets and Bytes cells are empty for sets without counters

- Large sets: elements load up to 200 by default; Load more (1000) and Load all (5000) buttons appear when the result is truncated

- ACL: add `nftset_info` and `nftset_elements` to both `luci-app-mwan3-status` and `luci-app-mwan3` ACL sections

---

#### luci-app-mwan3: improve IP Sets network configuration tab

- Block deletion of a set that is referenced by mwan3 rules; show a warning notification naming the referencing rules so the user knows what to fix first

- Suppress premature validation red on the Name field when a new set modal opens with an empty name; the field is marked pristine until the user interacts with it or clicks Save, at which point the red border appears if the field is still empty

- Change `maxelem` description and placeholder from 65536 to "unlimited" to match fw4 behaviour (sets have no size limit unless explicitly configured)

---

#### luci-app-mwan3: add IP Sets configuration tab

Add a new IP Sets tab to the MultiWAN Manager network section (order 52, between Rule and Simulator). The tab provides a GridSection UI for managing config ipset sections in /etc/config/mwan3.

Fields: `name` (validated: safe chars, no `mwan3_` prefix, unique across sections), `family` (IPv4/IPv6), `entry` (DynamicList, ipaddr datatype, family cross-check validation), `domain` (DynamicList, for dnsmasq nftset population), `loadfile` (FileUpload to `/etc/luci-uploads`), `maxelem`, `timeout`, `counters`, enabled.

IP address entry fields use blur-only validation matching `rule.js` behaviour, implemented via `makeBlurOnlyList` which attaches a capture-phase keyup suppressor to existing inputs at render time and to dynamically added inputs via `MutationObserver`.

ACL updated to add `ubus file read/list` (read) and `file write/remove` (write) permissions required by `form.FileUpload`.

---

#### luci-app-mwan3: update nftset references to table inet mwan3

`nftset_dump` in luci-mwan3 now lists sets from `inet mwan3` rather than `inet fw4`; the `mwan3_` prefix filter correctly hides internal skeleton sets and surfaces only user-declared config ipset sections.

The ipset dropdown placeholder text in `rule.js` is updated to show the `inet#mwan3` nftset directive syntax and explain that fw4-side sets need a parallel config ipset declaration in `/etc/config/mwan3` to be usable in mwan3 rules.

---

#### luci-app-mwan3: update port-range hint to use dash separator

mwan3 now renders port ranges using `x-y` (nft native format); the colon separator `x:y` is still accepted in UCI for backwards compatibility but is no longer the recommended input format. Update the `src_port` and `dest_port` help text from `"1024:2048"` to `"1024-2048"` so new entries match nft syntax directly.


---

### 17.4 Version 3.4.1 (Unreleased)

**Summary:** Builds the per-interface `mwan3_iface_in_*` chains before `mwan3_set_general_nft()` activates `mwan3_prerouting` to avoid a race condition that leads to a wrong interface mark being assigned. Fixes bugs in the `nft list chains` syntax in `stop_service()` and a grep expression that was causing a too-broad match and resulting in traffic for interface `wan` bypassing mwan3 marking.

---

#### mwan3: fix nft list chains syntax error in stop_service

`nft list chains` only accepts an optional family argument, not a table name. The two chain-enumeration loops in stop_service used `nft list chains inet fw4`, which is invalid syntax. The fw4 argument caused nft to exit with an error; `2>/dev/null` suppressed it, producing no output. Both loops therefore silently iterated over nothing on every `service mwan3 stop` or `service mwan3 restart`.

Consequence: dynamic chains (`mwan3_iface_in_*`, `mwan3_policy_*`, `mwan3_or_meta_*`, `mwan3_or_ct_*`) were never flushed or deleted on stop. They persisted in `table inet fw4` as empty orphan objects. The final hardcoded skeleton-chain flush at the end of `stop_service` was unaffected and continued to work correctly, so functional impact was limited to residual chain objects after stop.

Fixed by changing both occurrences to `nft list chains inet`. The `grep "chain mwan3_"` filter is sufficient to scope results to mwan3's chains, which only exist in `table inet fw4`.

---

#### mwan3: fix grep substring match in mwan3_ifaces_in chain wiring

`mwan3_create_iface_nft` used `grep -q "jump mwan3_iface_in_$1"` as an idempotency check before adding a jump from `mwan3_ifaces_in` to the per-interface chain. `grep -q` does substring matching, so for `$1=wan` the pattern also matches lines containing `mwan3_iface_in_wan2`, `mwan3_iface_in_wan6`, etc. If those interfaces had already added their jumps, wan's check returned a false positive and its jump was skipped, leaving wan absent from `mwan3_ifaces_in` and all wan traffic bypassing mwan3 marking entirely.

The same bug in `mwan3_delete_iface_nft` caused the handle lookup for wan's jump to return the handle of a different interface's rule.

The bug existed before this patch but was masked by the old sequential ordering, where wan (first in UCI order) always checked `mwan3_ifaces_in` before any other process had added jumps. The preceding commit changed to parallel execution, exposing the race.

Fixed with `grep -qw` (whole-word match) in both functions. Only affects configurations where one interface name is a prefix of another (e.g. wan/wan2, eth0/eth0b).

---

#### mwan3: build iface_in chains before activating prerouting

The per-interface `mwan3_iface_in_*` chains are now fully populated before `mwan3_set_general_nft()` activates `mwan3_prerouting`. Previously the ordering was reversed: prerouting became live first, then each `mwan3_ifup` background process added rules to `mwan3_ifaces_in` one by one. During that window, packets arriving on any interface whose chain was not yet wired got no ct mark. For DNAT traffic (`fib daddr type local` return with no mark save) the reply could hit numgen and acquire a random interface mark, which WireGuard PersistentKeepalive then locked in permanently by refreshing the conntrack entry every 25s.

Changed in all three rebuild code paths:

- `init.d/mwan3 start_service`: moved `config_foreach mwan3_ifup` and `wait $hotplug_pids` before `mwan3_set_general_nft`
- `25-mwan3` fw4-reload detection block: `config_foreach mwan3_rebuild_iface_nft` before `mwan3_set_general_nft`
- `mwan3-fw-rebuild.sh`: same reorder as `25-mwan3`

Also removed the flush of `mwan3_postrouting` from `mwan3_set_general_nft`. That flush was a leftover from when `general_nft` ran before iface setup; with the new ordering it ran after `mwan3_create_iface_nft` had already written snat6 rules to postrouting, silently deleting them. `mwan3_delete_iface_nft` and the per-chain cleanup in `mwan3_create_iface_nft` already handle postrouting cleanup correctly.

---

### 17.5 Version 3.4

**Summary:** Version 3.4 introduces mwan3evtd, a generalised ucode debounce daemon that coalesces rapid-fire events - such as simultaneous interface flaps triggering multiple fw4 reloads - into a single handler execution after the activity settles. This prevents the repeated dnsmasq SIGHUPs that previously caused cache thrash and, in tight-timing scenarios, dnsmasq crashes during concurrent startup.

---

#### mwan3: mwan3evtd debounce daemon

Add `mwan3evtd`, a generalised ucode debounce daemon that debounces rapid-fire events and executes a single safe handler for all identical events received during the debounce window.

Background: fw4 recreates the entire `inet fw4` nftables table on every reload, which flushes mwan3's nftsets. dnsmasq must be SIGHUPed after each rebuild to repopulate those sets. Without debouncing, simultaneous interface events (e.g. N-interface flap) would fire N independent mwan3 rebuilds in quick succession, each attempting to `SIGHUP` dnsmasq.

`mwan3evtd` coalesces all pushes within a window into a single fire: `window_ms` (default 5 s) resets on each push, and the HUP is delivered only once after activity has settled or on `max_window_ms`.

The debounce daemon exists to avoid unnecessary cache flushes and to make dnsmasq HUPs safe, since in some cases, and with tight timing, a HUP on a starting instance was observed to crash dnsmasq, resulting in loss of connectivity for clients.

`mwan3evtd` exposes a ubus object `mwan3evtd` with push/list/status/flush/reload/reset methods. Callers push named events via:

 `ubus call mwan3evtd push '{"event":"dnsmasq-hup"}'`

or via the fast-path helper `/usr/sbin/mwan3evtd-push` (falls back to direct UCI config parsing when ubus is unavailable, e.g. early boot).

Each handler is configured in `/etc/config/mwan3evtd` with:

```
  window_ms:          debounce window reset on each push
  max_window_ms:      hard cap, fires even under continuous pressure
  command:            shell command to run on fire
  handler_timeout_ms: kill handler if it runs longer than this
```

Default handlers: `dnsmasq-hup`, `dnsmasq-restart`, `rpcd-reload`, `rpcd-restart`, `firewall-reload`, `firewall-restart`, `unbound-restart`, `smartdns-restart`, `kresd-restart`, `named-restart`.

Shell injection in the handler fire path is prevented by passing the command through `EVTD_CMD` env var and using `eval "$EVTD_CMD"`, avoiding any brace-grouping that an adversarial `}` in command could escape.

`mwan3evtd` is a generalised debounce daemon, capable of accepting any event type and any handler and can be used by other packages if desired.

---

### 17.6 Version 3.3.5

**Summary:** Version 3.3.5 is a single-fix release that suppresses the per-deleted-entry output that `conntrack -D` writes to stdout, which was previously appearing on the console whenever mwan3 start or an fw4 reload triggered the zero-mark conntrack flush.

---

#### mwan3: suppress conntrack -D output to console

`conntrack -D` prints each deleted entry to stdout. The call in `mwan3_flush_stale_conntrack()` redirected only stderr, causing all deleted zero-mark conntrack entries to appear on the console whenever mwan3 start or fw4 reload triggered the flush.

Fix: redirect stdout to `/dev/null` alongside stderr.

---

### 17.7 Version 3.3.4

**Summary:** Version 3.3.4 closes a class of misrouting bugs caused by the brief window between fw4 flushing `table inet fw4` and mwan3 completing its nft rebuild. Connections established during that window acquire `ct mark=0`; the new `mwan3_flush_stale_conntrack` helper removes all zero-mark conntrack entries after every rebuild and restart, preventing WireGuard persistent-keepalive and similar long-lived UDP from locking in a bad entry indefinitely. A double-rebuild race in `mwan3-fw-rebuild.sh` is also fixed by acquiring the procd lock before checking for empty chains.

---

#### mwan3: flush zero-mark conntrack entries after fw4 rebuild and restart

During the brief window between fw4 wiping `table inet fw4` and the nft rebuild completing, new connections (DNAT, WireGuard) can be established with `ct mark=0`. The `iface_in` chains do not yet exist so incoming packets are not marked; the conntrack entry is created with `ct mark=0`.

For most protocols the bad entry expires within 120 seconds and self-heals on the next connection attempt. Long-lived UDP with persistent keepalives (WireGuard `persistent-keepalive`) refreshes the entry before expiry, keeping it alive indefinitely and causing persistent misrouting of DNAT replies.

Add `mwan3_flush_stale_conntrack()` to `mwan3.sh`. Flushes conntrack entries with no mwan3 mark (`0x0/MMX_MASK`) using the conntrack tool. Only zero-mark entries are removed; correctly-marked active connections are untouched. Even for users without the persistent-keepalive problem, the flush causes stale connections to re-establish immediately rather than waiting up to 120 seconds for natural conntrack expiry. If `conntrack-tools` is not installed, logs a notice suggesting installation.

Called from three sites:

- `mwan3-fw-rebuild.sh`: covers fw4 reload triggered by any means
- `25-mwan3` fw4 rebuild detection block: covers ifup-triggered fw4 reload
- `start_service` in `init.d/mwan3`: covers `service mwan3 restart`, which runs `25-mwan3` with `MWAN3_STARTUP=init` bypassing both guarded blocks and does not invoke `26-mwan3-user` where a `mwan3.user` workaround would
  otherwise run

---

#### mwan3: fix double rebuild race in mwan3-fw-rebuild.sh

mwan3-fw-rebuild.sh` checked for empty `mwan3_prerouting` before acquiring `procd_lock`. If `25-mwan3` was already holding the lock and rebuilding, the `fw-rebuild` script could pass the check, then queue behind `25-mwan3`, and proceed to rebuild and call `mwan3_dnsmasq_hup` a second time after the lock was released.

Fix by acquiring `procd_lock` first and re-checking under the lock, so only one of the two rebuild paths does the actual work.

---

### 17.8 Version 3.3.3

**Summary:** Version 3.3.3 is a broad bug-fix release addressing several correctness issues: DNAT reply routing was broken by a misplaced `fib daddr type local return` rule that fired before DNAT translation, causing replies to exit via a randomly load-balanced interface; IPv6 ip rules were silently leaked on ifdown because `delete_iface_rules` queried the IPv4 rule table; `mwan3_dnsmasq_hup` never sent SIGHUP because `json_get_var` stores booleans as integers not strings; and the numgen counter was contaminated by inbound and reply traffic. Additional fixes cover a grep substring false-positive in iface chain wiring, unquoted regex variables, a dead function stub, a duplicate function, and missing `mwan3_postrouting` in the stop_service chain lists. A new `bypass_network` UCI option populates the dynamic bypass sets from config, and `mwan3-lb-test` gains fw4 reload detection.

---

#### mwan3: add mwan3_postrouting to stop_service skeleton chain lists

`mwan3_postrouting` is defined in the static `10-mwan3.nft` skeleton alongside the other named skeleton chains, but was absent from both the deletion exclusion list and the safety-flush list in `stop_service()`. This caused it to be deleted on stop rather than preserved, relying on `start_service`/`mwan3_ensure_nft_framework` to recreate it. Add it to both lists for consistency with the other skeleton chains.

---

#### mwan3: remove duplicate mwan3_count_one_bits from mwan3.sh

An identical copy of `mwan3_count_one_bits()` existed in both `mwan3.sh` and `common.sh`. Since `mwan3.sh` sources `common.sh`, the `mwan3.sh` copy shadowed the canonical definition without any functional difference. Remove the duplicate; all call sites continue to use the `common.sh` definition.

---

#### mwan3: remove dead mwan3_set_sticky_nft function

`mwan3_set_sticky_nft()` was an incomplete stub from an earlier sticky routing design that was superseded by the current per-member ip-only set + OR-immediate vmap-dispatch implementation in `mwan3_set_user_nft_rule()`. The stub had a no-op loop body and was never called. Remove it.

`mwan3_get_policy_members_for_family()` is retained - it is called by the active sticky implementation at line 1131.

---

#### mwan3: quote $cmdline in mwan3_get_mwan3track_status

`$cmdline` was unquoted in the `[ $cmdline != ... ]` test. If readfile returns nothing (narrow race where the tracked process exits between the PID file read and the `/proc/$pid/cmdline` read), the empty expansion produces a malformed two-argument test expression. In busybox ash this happens to evaluate correctly (falls through to `export -n "$1=down"`), but the unquoted form is fragile. Quote it.

---

#### mwan3: quote $IPv4_REGEX in mwan3_set_user_nft_rule

`$IPv4_REGEX` was unquoted in the `grep -qE` call on line 951 while the adjacent `$IPv6_REGEX` on line 950 was correctly quoted. The IPv4 regex contains characters (`?`, `[`, `]`) that the shell interprets as glob patterns before passing to grep if unquoted. Quote it for consistency and correctness.

---

#### mwan3: fix IPv6 ip rule leak in mwan3_delete_iface_rules

`mwan3_delete_iface_rules()` sets `IP="$IP6"` for IPv6 interfaces but used bare `ip rule list` (which defaults to IPv4) to find rule priorities to delete. No IPv6 rules were found, so the for loop never executed and all three ip rules (at priorities `IIF_BASE+id`, `FWMARK_BASE+id`, and `3000+id`) were leaked on every IPv6 interface ifdown.

On the next ifup, `mwan3_create_iface_rules` calls `mwan3_delete_iface_rules` before adding new rules, but the delete fails for the same reason, so stale rules accumulate on each ifdown/ifup cycle.

Fix: change `ip rule list` to `$IP rule list` so the correct address family is used.

---

#### mwan3: fix dnsmasq_hup running check - json_get_var returns 1 not "true" for boolean true

`json_get_var` stores JSON boolean values as integers (`1` for true, `0` for false), not as strings. The previous check `[ "$running" = "true" ]` never matched, so `mwan3_dnsmasq_hup` never actually sent `SIGHUP` to dnsmasq after fw4 reloads. DNS cache was therefore not cleared, leaving stale nftset entries in place.

---

#### mwan3: fix DNAT reply routing broken by misplaced fib-local return rule

The v3.3.1 numgen contamination fix added an unguarded `fib daddr type local return` as the first substantive rule in `mwan3_prerouting`. Because `mwan3_prerouting` runs at priority `mangle+1` (-149), before the `nat/prerouting` DNAT hook (-100), the rule fires on the original packet of a DNAT connection while its destination is still the router's own WAN IP. The packet is returned immediately with no ct mark saved. When the DNAT reply arrives from the internal host on the LAN interface, the ct mark restore finds zero, the packet falls to the policy chain, numgen assigns a random WAN mark, and the reply exits via whichever interface numgen picks rather than the one the original packet arrived on.

Fix: remove the unguarded `fib-local` return from its position before the `ifaces_in` dispatch and reinsert it after, guarded by `meta mark & MMX_MASK == 0`. Traffic arriving on a mwan3 WAN interface is already marked by the `iface_in` catchall before reaching this rule, so the guard makes it a no-op for WAN traffic while still blocking non-WAN (LAN, loopback) local-destined traffic from reaching the policy chain. DNAT original packets are now marked by the `iface_in` catchall, ct mark is saved correctly, and DNAT replies restore it and route back via the correct interface.

Also remove `ct direction reply return` from `mwan3_output`. That rule was added to compensate for ct mark being zero (a consequence of the misplaced `fib-local` return). With the `fib-local` return correctly placed and guarded, ct mark is non-zero for inbound WAN connections, the ct mark restore in `mwan3_output` works correctly, the policy chain guard (`meta mark != 0`) prevents numgen from firing, and router-level service replies route back via the correct WAN table rather than the main routing table.

---

#### mwan3: add bypass_network UCI option to populate dynamic sets from globals config

Add `mwan3_set_dynamic_network()` callback and update `mwan3_set_dynamic_sets()` to read the `bypass_network` list from UCI globals config and populate `mwan3_dynamic_v4`/`v6` from it at startup, rather than just flushing the sets empty. Each entry is classified as IPv4 (contains `.`) or IPv6 (contains `:`) and added to the appropriate set via the existing nft batch.

Add `mwan3_set_dynamic_sets` to the fw4 reload rebuild sequence in both `25-mwan3` and `mwan3-fw-rebuild.sh` so that `bypass_network` entries are restored after fw4 reload alongside the connected and custom sets.

The `mwan3_dynamic_v4`/`v6` sets and `mwan3_dynamic` chain already existed and were already referenced in `mwan3_prerouting`, `mwan3_output`, and `mwan3_iface_in_*` chains. This change makes the feature accessible via UCI rather than requiring direct nft element injection.

---

#### mwan3: add fw4 reload detection and timestamp to mwan3-lb-test

When fw4 reload occurs during the test wait period, the `25-mwan3` hotplug rebuilds the policy chain without the injected counter rules. Previously this produced `TOTAL=unknown` and silent per-member zeros with a generic `FAIL`.

Now: detect missing counter rules explicitly and report "fw4 reload likely occurred during the test". Also add a human-readable completion timestamp to the summary output.

---

#### luci-app-mwan3: add Bypass networks field to globals page and improve rt_table_lookup UI

Add a Bypass networks `DynamicList` field (UCI option `bypass_network`) to the globals page. Accepts IPv4 and IPv6 CIDRs directly; traffic to these networks bypasses mwan3 policy routing and uses the default route. Validation uses the `cidr` datatype with blur-only firing (suppress keyup) via a capture-phase event delegation listener on the container node, covering dynamically added items without a MutationObserver.

Improve the `rt_table_lookup` field: rename label from "Routing table lookup" to "Routing table bypass" with a description that explains the bypass effect and that both table numbers and names are accepted. Remove the `uinteger` datatype constraint which incorrectly rejected table names, since the backend (`ip route list table`) accepts both.

---

### 17.9 Version 3.3.2

**Summary:** Version 3.3.2 fixes a spurious tracked-IP entry in ubus status output caused by a naming collision between mwan3track's temporary output file and the `TRACK_*` glob used by rpcd. The `mwan3-lb-test` tool gains mandatory client isolation, a Windows test command, and a stale-artifact cleanup subcommand. LuCI receives cross-field family consistency validation in the rule editor, a fix for false "Present (unexpected)" health badges during interface bring-up, source nftset display in the overview rules column, and source nftset support in the traffic path simulator.

---

#### mwan3: rename TRACK_OUTPUT temp file to PING_OUTPUT

The rpcd status module globs `TRACK_*` files in each interface's status directory to discover tracked IPs, using the suffix as the IP address. The temporary output file used by `mwan3track` for ping/httping/nping/nslookup output was named `TRACK_OUTPUT`, causing the rpcd glob to yield `OUTPUT` as a spurious tracked IP address in `ubus call mwan3 status`.

Rename the variable and its backing file to `PING_OUTPUT` to avoid the collision with the `TRACK_*` namespace.

---

#### mwan3: enhance mwan3-lb-test with client isolation and Windows test command

Add mandatory `-c <client_ip>` parameter: inserts a forward chain drop rule blocking pings to the test destination set from all LAN clients except the nominated test client, and an `mwan3_output` return rule bypassing mwan3 marking for router processes pinging the same IPs. Both rules are scoped to the test set and removed by `cleanup()`.

Add `cleanup` subcommand to remove stale rules and sets left by a `SIGKILL`-terminated run.

Add Windows `cmd.exe` test command output alongside the existing Linux shell loop. Windows ping uses a fixed ICMP identifier (`id=1`), causing conntrack entry reuse on repeated pings to the same destination. The generated Windows command uses a longer inter-ping delay (`30/TRACK_COUNT + 3` seconds) so that the full cycle through all test IPs exceeds the 30s ICMP conntrack timeout, ensuring each revisit creates a new conntrack entry.

---

#### luci-app-mwan3: fix missing cross-field family consistency checks in rule editor

`nftset_validate()` only checked set type against the explicit family field and returned true immediately when family was unset. This allowed invalid combinations such as an IPv6 source NFT set paired with an IPv4 destination address to pass validation silently.

Add cross-field checks:

- `ipset_src` type vs `dest_ip` address family
- `ipset` type vs `src_ip` address family
- `ipset_src` type vs `ipset` type (mixed families on the same rule)

Add `ip_family()` helper to derive `ipv4`/`ipv6` from an IP address string.

---

#### luci-app-mwan3: fix routing health showing Present (unexpected) during interface bring-up

During interface bring-up, mwan3 adds ip rules on the connected hotplug event before mwan3track has confirmed `STATUS=online`. The routing health page was calling `renderStatusBadge` with `expectedPresent=false` (derived from `online=false`), causing rules to be labelled Present (unexpected) even though their presence is normal and correct in this state.

Fix by introducing a tri-state `expectedPresent` parameter:
  `true`  - expected present: green Present / red Missing
  `false` - expected absent: orange Present (unexpected) / muted Absent
  `null`  - no expectation: muted Present / muted Absent (neutral)

Pass `true` when online, `null` otherwise. The card border colour already conveys health for non-online interfaces; the individual badges no longer need to second-guess presence during transitional states.

---

#### luci-app-mwan3: add src ipset to overview rules match column

Display `ipset_src` (source NFT set) in the Match column of the rules table on the Overview tab. Rename the existing `ipset:` label to `dst ipset:` to distinguish it from the new `src ipset:` label.

---

#### luci-app-mwan3: add ipset_src support to traffic path simulator

Extend the rule matching simulation to handle the source NFT set option (`ipset_src`) added alongside the existing destination NFT set (`ipset`). Updates `ruleMatches()` to check `src_ip` membership in the source set, `matchSummary()` to display it, and the set fetch loop to collect `ipset_src` names alongside `ipset` names.

---

#### luci-app-mwan3: improve rule modal family consistency and nftset support

Family validation: `src_ip` and `dest_ip` now validate against the selected address family on blur, showing a clear error if an IPv4 address is entered with family set to IPv6 or vice versa.

nftset improvements: the nftset dropdown is now populated via the new `mwan3.nftset_info` rpcd method instead of `luci-mwan3 nftset dump`. Sets are annotated with their address family (`(IPv4)`/`(IPv6)`) in the dropdown label. Family consistency is validated on save. Combining a destination nftset with `dest_ip` or a source nftset with `src_ip` is flagged as an error since both match the same dimension.

Source nftset: new `ipset_src` field allows matching source addresses against an nftset, complementing the existing destination nftset. Both src and dst nftsets can be set on the same rule and are ANDed together.

Grid display: Source and Destination columns now show the nftset name when no IP address is configured, preventing the rule from appearing as a wildcard match in the listing.

---

### 17.10 Version 3.3.1

**Summary:** Version 3.3.1 adds source nftset matching (`ipset_src`) as a complement to the existing destination nftset, fixes three distinct numgen counter contamination bugs that caused load-balancing distributions to skew under inbound or reply traffic, sweeps orphaned policy chains that accumulate when policies are removed from UCI without an fw4 reload, and corrects IPv6 ip rule detection in the routing health check. The release also adds `nftset_info` as an rpcd ubus method and introduces the `mwan3-lb-test` CLI tool for verifying load-balancing weight distributions against configured policy members.

---

#### mwan3: add ipset_src option for source nftset matching in rules

User rules previously supported only a destination nftset match via the `ipset` UCI option (`ip daddr @set`). Add `ipset_src` as an independent source nftset match (`ip saddr @set`), allowing both src and dst nftsets to be specified on the same rule and ANDed together.

The existing `ipset` option is unchanged for backward compatibility. `ipset_src` follows the same pre-creation and family handling logic as the destination set. The `nfproto` guard condition is updated to include `ipset_src` as an implicit family qualifier.

---

#### mwan3: add nftset_info rpcd ubus method

Returns the name and address-family type of all non-mwan3 nftables sets in `table inet fw4`. Used by `luci-app-mwan3` to annotate the nftset dropdown with family information and validate that a selected set is consistent with the rule's configured address family.

---

#### mwan3: translate icmp to ipv6-icmp for IPv6 family rules

In nftables inet tables, `meta l4proto icmp` matches protocol 1 (ICMPv4) only. A UCI rule with `proto=icmp` and `family=ipv6` previously generated `meta nfproto ipv6 meta l4proto icmp`, a contradiction that silently matched nothing.

Translate `proto icmp` to `ipv6-icmp` (proto 58) when `family` is `ipv6` in `mwan3_set_user_nft_rule()` so the generated rule correctly matches IPv6 ICMP traffic. All other proto/family combinations are unaffected.

---

#### mwan3: add mwan3-lb-test load balancing distribution verifier

CLI tool that verifies a load-balancing policy distributes traffic according to configured member weights. Inserts temporary nft counter rules into the policy chain, generates a test ping command, waits for completion, then reports per-member actual vs expected hit counts with PASS/FAIL verdict.

Key design points:

- Computes N from member weights (LCM/GCD) so expected counts per member are always whole numbers
- Temporary nft set + ICMP-only rule inserted into `mwan3_rules` ensures only test pings hit the policy chain; DNS and other traffic to the same IPs is not matched
- Default destination pool excludes any IPs already configured as mwan3 tracking IPs (`mwan3track` pings those via `mwan3_output`, which would contaminate the counter)
- `-6` flag selects IPv6 mode (`ip6 daddr` + `ping6` + IPv6 well-known IPs)
- Optional IP override arguments for sites with non-standard reachability
- Cleanup on exit, `SIGINT`, `SIGTERM` and `SIGPIPE`; startup sweep removes stale artifacts from aborted previous runs
- Installed as `/usr/sbin/mwan3-lb-test` alongside `mwan3track` and `mwan3rtmon`

---

#### mwan3: fix numgen counter contamination from inbound and reply traffic

Three bugs caused the numgen load-balancing counter in policy chains to be incremented by traffic that should never reach a policy chain. The effect is non-strict alternation and a skewed distribution that does not match the configured member weights.

Bug 1: inbound internet traffic (port scanners, bots) destined for the router's own WAN IP traversed `mwan3_prerouting` with `mark=0`, found no matching user rule, fell to the default policy, and fired numgen. Fix: add `fib daddr type local return` in `mwan3_prerouting` after the ICMPv6 ND bypass.

Bug 2: the router's replies to inbound connections (ICMP echo replies, TCP responses) passed through `mwan3_output` with `ct mark=0` -- because bug 1's fix caused the inbound packet to bypass prerouting without saving a ct mark -- and fell through to the policy chain firing numgen. On a public IPv6 address receiving frequent external pings this generates ~10-20 spurious hits per second. Fix: add `ct direction reply return` as the first rule in `mwan3_output`.

Bug 3: a UCI rule with `family ipv4` or `ipv6` but no `src_ip`, `dest_ip`, or `ipset` generates a bare `meta mark ... jump policy` rule with no IP version restriction. Rules with address-based criteria get an implicit family qualifier from the `ip`/`ip6` keyword; rules without any address criteria do not. Combined with bug 2, the router's IPv6 ICMP replies fell through all `ip saddr`/`ip daddr` rules and hit the bare default rule, firing numgen at high rate. Fix: in `mwan3_set_user_nft_rule()`, if none of `src_ip`/`dest_ip`/`ipset_name` are set and `family` is explicitly `ipv4` or `ipv6`, prepend `meta nfproto ipv4`/`ipv6` to `nft_match`.

---

#### mwan3: sweep orphaned policy chains on startup

When a policy is removed from UCI config, its `mwan3_policy_*` chain persists in `table inet fw4` until the next fw4 reload flushes the table. mwan3 restart only manages chains it knows about from current config, leaving orphans indefinitely.

`mwan3_set_policies_nft()` now enumerates all `mwan3_policy_*` chains in the live ruleset and deletes any that have no corresponding UCI policy config before rebuilding the policy chains from config.

---

#### mwan3: fix routing_health ip rule detection for IPv6 interfaces

`get_ip_rules()` called `ip -j rule list` which is IPv4-only. mwan3 adds ip rules for IPv6 interfaces via `ip -6 rule add`, making them invisible to the IPv4 rule list. `routing_health()` therefore reported iif and fwmark rules as missing for any IPv6 mwan3 interface, showing a false red card even when mwan3 was functioning correctly.

Fix by querying both `-4` and `-6` rule tables and merging the results, matching the same pattern already used by `get_table_routes()`. The stale rule detection also benefits as it now sees IPv6 stale rules too.

---

### 17.11 Version 3.3

**Summary:** Version 3.3 adds three major LuCI diagnostic tools - a traffic path Simulator, a static Configuration analyser, and a live Routing health view - backed by two new rpcd ubus methods (`nftset_members` and `routing_health`). The configuration analyser detects undefined references, orphaned sections, and rule shadowing including correct IPv6 CIDR containment checks. The routing health view colour-codes per-interface ip rule and routing table state against live kernel state. The `apk info` vs `apk list -I` version display bug is also fixed.

---

#### mwan3: add nftset_members and routing_health rpcd ubus methods

`nftset_members { set: "<name>" }` returns the current members of a named nft set in `table inet fw4`. The set name is validated against `[a-zA-Z0-9_-]+` before being passed to nft. Used by the `luci-app-mwan3` Simulator tab for ipset rule matching and connected-network bypass detection.

`routing_health {}` compares the UCI configuration against live kernel state. For each mwan3 interface (by 1-based UCI order index N) it checks for ip rules at priorities `1000+N` (iif) and `2000+N` (fwmark), checks routing table N for a default route, and reads the mwan3track `STATUS` file. Reports stale ip rules in mwan3's priority range that have no matching UCI interface. Built-in blackhole (`FWMARK_BASE + MAX_IFACES - 2 = 2061`) and unreachable (`FWMARK_BASE + MAX_IFACES - 1 = 2062`) policy rules are explicitly excluded from stale detection.

Both methods are declared in the `luci-app-mwan3` ACL files.

---

#### mwan3: fix software version display in troubleshooting output

`apk info mwan3` returns the version from the repository index, not the installed version. When the installed package version differs from the repo version, the Software-Version section of `mwan3 internal` output shows the wrong version.

Use `apk list -I` to query installed packages only, ensuring the correct installed version is displayed.

---

#### luci-app-mwan3: extend rule-shadowing check to cover IPv6 CIDRs

The Configuration tab's rule-shadowing analysis previously skipped all IPv6 addresses, treating every IPv6 pair as 'may shadow'. Add proper IPv6 CIDR containment using BigInt arithmetic (`expandIPv6`, `ipv6ToBigInt`, `ipv6CidrContains`) so shadowed IPv6 rules are correctly identified. Refactor the IPv4 path into `ipv4CidrContains` to match the new structure.

---

#### luci-app-mwan3: add Simulator, Configuration, and Routing diagnostic tabs

Three new tabs backed by mwan3 internals:

Simulator (Network > MultiWAN Manager > Simulator): simulates which mwan3 rule matches a described packet and shows live policy state. Supports IPv4 and IPv6 CIDR matching, port ranges, nft set membership via `nftset_members` ubus method, and connected-network bypass detection via `mwan3_connected_v4`/`v6` sets. Enter key in any field triggers simulation.

Configuration (Network > MultiWAN Manager > Configuration): static analysis of the mwan3 UCI configuration. Detects undefined references, orphaned sections, policies with no members, all-same-interface policies, and rule shadowing via IPv4 and IPv6 CIDR containment.

Routing (Status > MultiWAN Manager > Routing): live comparison of ip rules and routing tables against UCI configuration via `routing_health` ubus method. Per-interface cards show iif rule, fwmark rule, and routing table state with colour-coded health badges. Includes a field reference explaining the ip rule priority scheme for non-expert users. Stale rule detection excludes built-in blackhole/unreachable policy priorities (`2061`/`2062`).

Also adds `nftset_members` and `routing_health` methods to the rpcd module with appropriate ACL entries in both `luci-app-mwan3` and `luci-app-mwan3-status`.

---

### 17.12 Version 3.2.3

**Summary:** Version 3.2.3 improves tracking status visibility by adding per-IP latency and packet-loss detail to `mwan3 status` output and fixing the `check_quality` display to derive its state from mwan3track's runtime files rather than UCI, so changes to UCI without a restart no longer cause the status page to disagree with what is actually running. Stale gateway `TRACK_*`/`LATENCY_*`/`LOSS_*` files from previous PPPoE sessions are cleaned up on each probe list rebuild. The `luci-app-mwan3` PKG_VERSION scheme is fixed to prevent `apk upgrade` from reverting to the official package, and the GitHub Actions APK rename step is corrected to avoid i18n sub-packages overwriting the main package.

---

#### mwan3: add per-IP tracking detail to interfaces status output

`mwan3_report_iface_status` now prints each tracking IP below the interface status line, showing its status and (when `check_quality=1`) latency and packet loss:

```sh
  interface wan is online and tracking is active
    track 8.8.4.4: up (12ms, 0% loss)
    track 8.8.8.8: down (-, 100% loss)
    track 192.168.1.1: ignored
```

`check_quality` is derived from `LATENCY_*` file presence (not UCI) to reflect actual mwan3track runtime state. The kernel status value "skipped" is displayed as "ignored" for consistency with the LuCI status page.

---

#### mwan3: fix check_quality display inconsistency when UCI is changed without restart

When `check_quality` is changed in UCI without restarting mwan3track, the rpcd status reported the new UCI value immediately while mwan3track continued running with the old setting, causing the status page to show "Not enabled" for latency/loss even though measurements were still being taken (or vice versa).

Fix in two parts:

rpcd: derive `check_quality` from `LATENCY_*` file content rather than UCI. mwan3track only writes `LATENCY_*` files when `check_quality=1`, so file presence with content is the authoritative indicator of actual runtime state. A fresh read of UCI is not needed on the rpcd side.

mwan3track: in `mwan3_load_track_ips()`, re-read `check_quality` from the current UCI config and remove any stale `LATENCY_*`/`LOSS_*` files when it is 0. This runs at startup and on every ifup event, so stale files from a previous check_quality=1` run are cleaned up as soon as the interface next comes up with `check_quality=0`, ensuring the rpcd file-based detection also returns the correct result after restart.

---

#### mwan3: remove stale gateway TRACK_*/LATENCY_*/LOSS_* files on probe list rebuild

When `track_gateway=1` and the gateway IP changes (e.g. PPPoE reconnect), `mwan3_load_track_ips` builds a new probe list with the new gateway but leaves `TRACK_*`, `LATENCY_*`, and `LOSS_*` files from the old gateway IP on disk. The rpcd status function globs all `TRACK_*` files to build the tracking IP list, so stale files from previous gateways appear in `ubus call mwan3 status` alongside the current ones.

Fix: after building `track_ips`, scan the interface directory and delete any `TRACK_*`/`LATENCY_*`/`LOSS_*` files for IPs not in the current probe list. Runs at startup and on every ifup event, covering both initial cleanup of files left by a previous mwan3track instance and gateway changes during operation.

---

#### luci-app-mwan3: set explicit PKG_VERSION and fix release workflow

Without explicit versioning, `luci.mk` auto-generates the package version from git commit metadata. In the GitHub Actions SDK build environment the feed directory has no `.git` (excluded by rsync), so git walks up to the SDK repo and picks up the SDK commit hash and timestamp. The resulting version (e.g. `26.099.76803~8a085e7`) is indistinguishable from the official OpenWrt package version format, causing apk to install the official repo version.

Set `PKG_VERSION` to `$(PKG_SRC_PREFIX).$(PKG_SRC_SUFFIX)` where `PKG_SRC_PREFIX` is derived from the build year and a fixed day value of `999` (not a valid calendar day), ensuring it is always higher than any real date-based official package version for that year. `PKG_SRC_SUFFIX` encodes the mwan3 version number for readability.

Also fix the APK rename step to only match the main `luci-app-mwan3` package (pattern: `PKG_NAME[_-][0-9]*.ext`) instead of all APKs in the feed directory. The previous pattern matched all i18n sub-packages as well; since they all got renamed to the same target filename, the last one alphabetically clobbered the main package and was what actually got uploaded to the release.

---

#### luci-app-mwan3: improve tracking IP latency/loss display for down/skipped/disabled states

When `check_quality=1`, tracker latency/loss sentinel values (`999999ms`, `100%`) are replaced with more informative indicators:

* Tracker down: latency shows `∞` (scaled to be legible), packet loss retains `100%` since it is accurate
* Tracker skipped: both show `-` since no probe was run that round
* Interface disabled: tracker status shows 'Disabled' (muted) instead of 'Down', and both latency and loss show `-`

---

### 17.13 Version 3.2.2

**Summary:** Version 3.2.2 fixes two misrouting bugs: duplicate jump rules accumulating from repeated fw4 reload cycles caused iface_in chain deletion to fail with "Resource busy", and the unguarded catchall rule in each `mwan3_iface_in_*` chain was stamping IPv6 packets with the IPv4 interface mark on dual-stack physical devices, breaking QUIC/HTTP3 streams that resumed after conntrack expiry. The gateway IP is moved to the front of the tracking probe list so it is always tested. LuCI receives a visual redesign replacing solid alert cards with bordered flex cards, and adds latency and packet-loss columns to the tracking IP table.

---

#### mwan3: fix iface_in jump rule deletion failing with multiple handles

`mwan3_delete_iface_nft` used a single-shot handle lookup to remove the jump rule for an interface from `mwan3_ifaces_in`. If repeated fw4 reload cycles caused duplicate jump rules to accumulate, the handle variable received multiple space-separated values and the resulting nft command was syntactically invalid. The chain delete that followed then failed with "Resource busy" since the jump rule was still present.

Replace the single-shot lookup with a while loop using `head -n1`, matching the pattern already used for SNAT rule deletion in the same function. This correctly removes all copies of the jump rule one at a time and self-heals any pre-existing duplicates on the next ifdown.

---

#### mwan3: fix iface_in catchall misclassifying IPv6 on shared-device interfaces

The catchall rule in each `mwan3_iface_in_*` chain lacked a `meta nfproto` filter. When an IPv4 and IPv6 mwan3 interface share the same physical device (e.g. a dual-stack PPPoE or L2TP WAN), `mwan3_ifaces_in` dispatches to the IPv4 chain first. The IPv4-specific `ip saddr` bypass rules do not match IPv6 packets, but the unguarded catchall does, stamping incoming IPv6 packets with the IPv4 interface mark instead of the IPv6 mark.

The ct mark is then saved with the wrong value. Subsequent packets for that connection restore the IPv4 mark, find no matching `ip -6` rule, and fall to the main routing table. For established TCP connections the bug is invisible because ct mark is set on the first outbound packet before any inbound packet arrives. For QUIC (UDP), conntrack entries expire after ~120-180s of inactivity; when the server resumes first the entry has `ct mark 0`, the catchall fires, and the connection is disrupted - manifesting as stalled streams or a gray page on sites using HTTP/3.

Fix by adding `meta nfproto ipv4`/`ipv6` to the catchall based on interface family, consistent with the protocol filters already applied to the `connected`/`custom`/`dynamic` bypass rules above it.

---

#### mwan3: ping gateway IP first when track_gateway=1

`mwan3_load_track_ips()` previously appended the gateway IP to the end of the `track_ips` list. Since mwan3track stops probing once `host_up_count` reaches the reliability threshold, the gateway would be skipped whenever an earlier IP responded.

Prepend the gateway instead so it is always probed first. This gives the gateway probe priority and ensures its reachability is tested on every round regardless of `reliability` setting.

---

#### mwan3: fix rpcd status to include gateway tracking IP and restore latency/loss

`interfaces_status()` built the `track_ip` list from UCI `track_ip` options only, so the gateway IP (added dynamically by mwan3track when `track_gateway=1`) was never visible in ubus status output.

Replace the UCI iteration with a glob scan of the `TRACK_*` files that mwan3track actually writes, so all tracked IPs appear regardless of whether they come from UCI config or the dynamic gateway.

Also correct `get_mwan3track_status()` to treat `track_gateway=1` as an active tracking configuration (not disabled), and restore the latency/packetloss fields to the per-IP output (populated when `check_quality=1` is configured).

---

#### luci-app-mwan3: visual redesign of status cards across overview and main status page

Replace solid alert-message background cards with bordered flex cards throughout: interface status boxes now use a 2px border coloured to match the interface status (green/red/orange/grey) with no background fill.

`detail.js`: status box border colour matches interface status; paused tracking state changed from warning orange to muted grey; tracking IP table rows sorted by status (up first, then down, then ignored).

`overview.js`: policy section replaced with per-policy flex cards matching the interface card style; interface card borders coloured by status.

`90_mwan3.js`: main LuCI status overview page cards converted from alert-message solid backgrounds to the same bordered card style.

---

#### luci-app-mwan3: add latency and packet loss columns to tracking IP status table

The rpcd mwan3 status now returns `latency`, `packetloss` and `check_quality` fields per interface. Extend the Status tab tracking IP table with Latency and Packet Loss columns.

When `check_quality` is disabled (the default), the columns display "Not enabled" in muted text rather than zeroed values.

---

### 17.14 Version 3.2.1

**Summary:** Version 3.2.1 fixes policy status reporting to include all members with their live traffic share percentages (not just the currently-routing member), replaces `killall -HUP dnsmasq` with a procd-aware targeted SIGHUP to avoid crashing instances still in the startup phase, adds the installed mwan3 package version to `mwan3 internal` output, and redesigns the LuCI status pages with structured collapsible sections and an IPv6 troubleshooting pane. LuCI also exposes the `snat6` IPv6 SNAT option on interface configuration.

---

#### mwan3: show mwan3 package version in internal troubleshooting output

Replace the OpenWrt release string in the Software-Version section of `mwan3 internal` with the installed mwan3 package version from apk.

---

#### mwan3: fix policy status to show all members with traffic share

`mwan3_report_policies()` read the live nftables policy chain to determine members, which only contains the currently-routing member. Metric-2 standby members have no nft rules while metric-1 is up, so they were invisible in the status output.

The rpcd ucode `get_policies()` had the same problem, and additionally returned the raw nft mark value instead of the interface name.

Fix both by reading policy membership from UCI config and cross-referencing with mwan3track `STATUS` files to determine which metric is active and what the traffic share is for each member.

Every member now shows a percentage: `100%` for a sole active member, the load-balanced share for equal-priority members, and `0%` for standby/offline members. This makes failover and load-balancing configuration immediately readable at a glance.

The shell status command now calls ubus rather than duplicating the metric/weight/status logic in shell.

---

#### mwan3: fix dnsmasq SIGHUP race during concurrent startup

`killall -HUP dnsmasq` signals every process named dnsmasq, including instances that are mid-initialisation. A dnsmasq receiving `SIGHUP` before it has completed startup exits, which can happen when mwan3's fw4-reload recovery (`25-mwan3` at position 25) fires concurrently with anything else restarting dnsmasq.

Replace `killall -HUP dnsmasq` with `mwan3_dnsmasq_hup()`, which queries procd via ubus for the dnsmasq service instances and sends `SIGHUP` only to PIDs that procd reports as `running=true`. Instances still in the startup phase are invisible to the function and are not signalled.

`json_set_namespace` is used to protect the caller's jshn state since `mwan3.sh` uses jshn elsewhere.

---

#### luci-app-mwan3: redesign status pages with structured views

Overview tab: replace simple interface cards with full operational view showing interface status cards (flex layout), policies table with per-member traffic share percentages, and rules table.

Status tab: replace static interface cards with per-interface tracking health panels showing tracking mode, score, and a table of probe IPs with up/down/ignored status using coloured text indicators.

Troubleshooting tab: replace raw pre-formatted text dump with collapsible sections (collapsed by default with expand arrow), IPv6 sections alongside IPv4, and vmap-dispatch boilerplate chains filtered from the nftables output. Add ACL entry for `mwan3 internal ipv6`.

---

#### luci-app-mwan3: expose mwan3 snat6 option for IPv6 interfaces

Adds an "IPv6 SNAT" form field to the interface configuration modal, visible only when `family` is set to `ipv6`. Mirrors the placement of the existing "Track gateway" field. Accepts unset/0 (off, default), `1` (SNAT to the interface's primary GUA), or a literal IPv6 address for NPTv6-style fixed-source pinning. The control is opt-in by design -- see the mwan3 package for the rationale (RFC 6724 source-address selection, NAT66 harm in PA/ULA designs, fixed-saddr upstream requirements).

---

### 17.15 Version 3.2

**Summary:** Version 3.2 adds two significant features. First, opt-in per-interface IPv6 SNAT via the `snat6` UCI option, which corrects BCP38/uRPF drops for router-originated traffic rerouted by `mwan3_output` onto a different WAN than the kernel initially selected at `sendto()`. Second, non-destructive vmap-dispatch mark save/restore: 126 per-mark OR-immediate setter chains replace the previous unmasked connmark operations, making mwan3 fully order-independent with respect to pbr and other fwmark-using packages without requiring coordinated chain priority ordering.

---

#### mwan3: add opt-in IPv6 postrouting SNAT via snat6 UCI option

Adds a `mwan3_postrouting` base chain (`type nat hook postrouting priority srcnat - 1`) and opt-in per-interface IPv6 SNAT for router-originated traffic that `mwan3_output` has rerouted onto a different WAN.

The kernel binds saddr at `sendto()` using the unmarked initial route; `mwan3_output` then reroutes oif onto a different WAN; without SNAT the packet egresses with the wrong source prefix and is dropped upstream by BCP38/uRPF. fw4 does not masquerade IPv6 by default so there is no automatic fallback. `mwan3track` is unaffected because it uses `SO_BINDTODEVICE`. IPv4 router-originated traffic does not require explicit SNAT -- fw4's masquerade handles it.

IPv6 SNAT is opt-in per interface via the new `snat6` UCI option, defaulting to off because RFC 6724 source-address selection / SADR routing can solve the same problem without translation, NAT66 is harmful in PA/ULA designs, and some upstreams require a specific saddr. `snat6` values: unset/0 (off), `1` (SNAT to interface primary GUA via `mwan3_get_src_ip`), or a literal v6 address (NPTv6-style fixed-source pinning). Cleanup is via comment-tag matching (`"mwan3_snat_<iface>"`).

---

#### mwan3: non-destructive vmap-dispatch save/restore

Restores iptables-equivalent non-destructive masked CONNMARK semantics by synthesising masked save/restore via vmap dispatch into 126 per-mark OR-immediate setter chains (`mwan3_or_meta_*`, `mwan3_or_ct_*`, 63 each). Each setter chain is a 2-statement skeleton `"meta/ct mark set ... | <imm>; return"`. The kernel rejects the obvious compound form `"(meta mark & ~M) | (ct mark & M)"` because a set-statement may reference at most one runtime source register; vmap-dispatch routes around this by materialising the constant immediate at rule-emit time.

Because the save and restore operations are now non-destructive, mwan3's fwmark bits are ORed in and out of the conntrack mark without disturbing bits owned by other packages. This makes mwan3 order-independent with respect to other fwmark-using packages such as pbr, regardless of chain priority ordering.

The same vmap-dispatch primitive is reused by `mwan3_create_policies_nft` for load-balancing numgen rules and by the sticky implementation in `mwan3_set_user_nft_rule`, both of which were previously destructive in unmasked bits. Sticky routing is rebuilt around per-(rule, family, member) ip-only sets that pair with the per-mark setter chains, replacing the legacy `ip->mark` map. `mwan3_delete_iface_map_entries` and `mwan3_report_policies` are updated for the new sticky and numgen forms.

---

### 17.16 Version 3.1.4

**Summary:** Version 3.1.4 fixes interoperability with pbr by moving mwan3's prerouting and output chains from priority `mangle + 1` to `mangle - 1`, so mwan3 restores and saves its ct mark bits before pbr injects its own marks at `mangle` priority. With the previous ordering pbr's marks were zeroed before the routing decision and its ip rules never matched.

---

#### mwan3: fix pbr interoperability by running at priority mangle - 1

Move `mwan3_prerouting` and `mwan3_output` from priority `mangle + 1` to `mangle - 1` so mwan3 runs before pbr, which injects into fw4's `mangle_prerouting` at priority `mangle` (-150).

With the old priority, pbr set marks in `0x00ff0000` first, then mwan3's unmasked restore (`meta mark set ct mark & MMX_MASK`) zeroed them before the routing decision, causing pbr's ip rules to never match.

With `mangle - 1`, mwan3 restores and saves its mark before pbr runs. pbr then adds its bits on top, and both sets of marks are present at the routing decision -- matching the coexistence behaviour of the original iptables implementation.

Add `postinst` migration to flush and delete the old chains on upgrade, since nftables rejects a chain redeclaration with a different priority.

---

### 17.17 Version 3.1.3

**Summary:** Version 3.1.3 fixes three status and policy rendering bugs: single-member policies were emitting spurious "unreachable" entries because the empty-string guard on `mwan3_mark_to_name` never matched; mixed IPv4/IPv6 policies lost one family's members because both shared a single reset list; and equal-weight load-balancing entries were invisible in `mwan3 status` because nft normalises single-element numgen ranges to plain values that the reporting regex did not match.

---

#### mwan3: fix status reporting for single-member and mixed-family policies

`mwan3_report_policies` used `mwan3_mark_to_name` on the mark from the single-member branch and tested `[ -n "$iface_name" ]` to skip special marks. However `mwan3_mark_to_name` never returns an empty string: it returns "unreachable", "blackhole", "default", or the raw hex value as a fallthrough for unrecognised marks. The empty-string test therefore never filtered anything, causing spurious "unreachable" output.

Replace the empty-string guard with a `case` statement that explicitly skips the known non-interface values (`unreachable`, `blackhole`, `default`, and raw `0x...` hex fallthrough). Also iterate all `"meta mark set"` rules in the chain rather than only the first, so mixed-family policies with one IPv4 and one IPv6 member both appear in the status output.

---

#### mwan3: fix cross-family member reset in mixed IPv4/IPv6 policies

When a policy contains members from both IPv4 and IPv6 interfaces, the previous code used a single `policy_members` list that was reset on each new lowest-metric member regardless of address family. This caused IPv4 members to be erased when a lower-metric IPv6 member was processed (or vice versa), leaving the policy with only the last-processed family.

Fix by maintaining separate `policy_members_v4` and `policy_members_v6` lists, each reset only when a new lowest-metric member of the same family is encountered. When both families have members, emit per-family nft rules guarded with `meta nfproto ipv4`/`ipv6` so traffic is only directed to members of the matching address family.

---

#### mwan3: fix load balancing policy not shown in status

nft normalizes single-element ranges (e.g. `0-0`) to plain values (e.g. `0`) when listing rules. The reporting regex only matched the range format `N-M : 0xMARK`, so equal-weight load balancing entries (weight=1, displayed as `N : 0xMARK`) were silently skipped, causing the policy to appear empty in `mwan3 status` despite working correctly.

Handle both `N-M : 0xMARK` (weight>1, range preserved by nft) and `N : 0xMARK` (weight=1, normalized by nft) formats.

---

### 17.18 Version 3.1.2

**Summary:** Version 3.1.2 improves mwan3rtmon with two fixes: an in-memory route cache replaces the per-event `RTM_GETROUTE` dump for O(1) ECMP path checks, and a ucode-mod-rtnl double-destructor bug that caused a reliable segfault on clean shutdown is eliminated by letting the GC collect the route listener rather than calling `close()` explicitly.

---

#### mwan3rtmon: replace route_still_exists() with an in-memory route cache

`route_still_exists()` issued a full `RTM_GETROUTE` dump on every route-delete event to check whether an ECMP path still existed before removing per-interface table entries. This is unnecessary overhead.

Replace with `main_route_cache`: a `{ route_key: count }` map built from the initial route snapshot in `populate_iface_routes()` and maintained incrementally in `handle_route_event()`. The ECMP check becomes an O(1) cache lookup with no rtnl round-trip.

---

#### mwan3rtmon: fix segfault on exit caused by ucode-mod-rtnl double-destructor bug

Calling `route_listener.close()` explicitly zeroes the resource data pointer while the ucode variable still holds a live reference. When that reference is later released at scope exit, `uc_nl_listener_free()` fires a second time with `arg=NULL` and reads `uc_nl_listener_t.index` at `NULL+0x10`, producing a reliable "segfault at 10" on every clean shutdown.

Fix: omit the explicit `close()` call and let the GC collect the listener naturally. The destructor then fires exactly once with a valid pointer.


---

### 17.19 Version 3.1.1

**Summary:** Version 3.1.1 is a broad mwan3track hardening release: the disconnecting threshold is raised to suppress false alarms from single transient ping losses, an exclusive flock prevents ghost duplicate tracker processes per interface, `sockopt_wrap` replaces `exit()` with graceful error returns so a stale source IP or disappearing interface does not abruptly terminate the tracked process, per-host failure logs are suppressed when the reliability threshold is still met, and interface events are processed at the top of the main loop before pinging to avoid a spurious disconnecting state on wakeup from disabled. LuCI adds a track_gateway checkbox to the interface modal and clarifies the flush_conntrack help text.

---

#### mwan3track: raise disconnecting threshold and log recovery

Raise the threshold at which the disconnecting state fires from the first score drop to `ceil(down/3)` failures below the maximum score. This prevents single or double transient ping losses (e.g. to a public DNS server) from spuriously triggering the disconnecting state.

Log an explicit notice when the score recovers out of the disconnecting state, making the transition back to online visible in the log.

---

#### mwan3track: use flock to prevent ghost processes for same interface

Use an exclusive flock on a per-interface lock file to ensure only one mwan3track instance runs per interface at a time. The lock is held for the lifetime of the process and released unconditionally on exit.

---

#### mwan3: sockopt_wrap: replace exit() with graceful error returns

A `LD_PRELOAD` shim must not call `exit()` on recoverable errors; doing so terminates the tracked process abruptly with no log from mwan3track, making it indistinguishable from a genuine connectivity failure.

Three cases are fixed:

* Source IP bind failure in `dobind()`: can occur when `SRC_IP` becomes stale after a DHCP address change that does not generate an ifup event. Close the socket and return; the subsequent `sendto()`/`connect()` call will fail with `EBADF`, causing the ping to exit with a normal error code that mwan3track records as a ping failure.

* `SO_BINDTODEVICE` failure in `socket()`: can occur if the interface disappears between m### mwan3track: suppress per-host failure logs when reliability threshold is met

With multiple track IPs and `reliability < number of IPs`, a single host failure was logged as "Check failed for target X" even when a subsequent host met the reliability threshold and the round succeeded. 95% of all logged failures are false alarms of this kind, making it appear the interfaces are degrading when they are in fact healthy.

Fix the excessive log noise by accumulating failed host names during the probe loop and logging them in a single message after the loop, when `host_up_count` is still below the reliability threshold (round genuinely failed). Rounds that succeed via a later host produce no failure log. The success log during recovery remains per-host and unchanged.

For `check_quality` mode the accumulated entry includes per-host latency and loss: `"target(s) \"1.2.3.4(999999ms/100%)\""`.

---

#### mwan3track: process interface events before ping round on wakeup

When `USR2` (ifup) wakes mwan3track from disabled state, the main loop resumes past the `MAX_SLEEP` wait and immediately starts a ping round before reaching the `IFUP_EVENT` handler at the bottom of the loop. At that point `DEVICE` is still stale (empty string at first start), so `sockopt_wrap` skips `SO_BINDTODEVICE`, the unbound ping fails, and a spurious "disconnecting" state is logged.

Fix this by checking `IFDOWN_EVENT`/`IFUP_EVENT` at the top of the loop, before any pinging, and using `continue` to restart the iteration cleanly after `firstconnect()` has refreshed `DEVICE` and `SRC_IP`. The existing handlers at the bottom of the loop are retained for events that arrive during a ping round or the inter-round sleep.

---

#### luci-app-mwan3: clarify flush_conntrack help text

Update the help text for the `flush_conntrack` option to clarify that it flushes the entire global conntrack table, and that per-interface conntrack entries are already flushed automatically on ifdown since commit ("mwan3: selectively flush conntrack entries for failed WAN interface on ifdown").

---

#### luci-app-mwan3: add track_gateway option to interface settings

Add a "Track gateway" checkbox to the interface configuration modal, visible only when the internet protocol is set to IPv4. This exposes the `track_gateway` UCI option added to the mwan3 backend for automatic point-to-point peer/gateway tracking.
