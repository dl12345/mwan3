# mwan3 nftables User and Developer Reference
### mwan3 version: 3.6.9
Covers the nftables port of the mwan3 multi-WAN policy routing framework.

---

## Contents

1. [Architecture Overview](#1-architecture-overview)
2. [The Mark Bitmask System](#2-the-mark-bitmask-system)
3. [table inet mwan3 Architecture](#3-table-inet-mwan3-architecture)
4. [Packet Flow Through Chains](#4-packet-flow-through-chains)
5. [IP Rules and Lookup Tables](#5-ip-rules-and-lookup-tables)
   - 5.1 [Per-Interface Routing Tables](#51-per-interface-routing-tables)
   - 5.2 [Three ip Rule Tiers Per Interface](#52-three-ip-rule-tiers-per-interface)
   - 5.3 [Global Policy Rules](#53-global-policy-rules)
   - 5.4 [MMX_DEFAULT Fall-Through](#54-mmxdefault-fall-through)
   - 5.5 [Configurable Rule Base Priorities](#55-configurable-rule-base-priorities)
   - 5.6 [Example: Live ip rule Output](#56-example-live-ip-rule-output)
6. [File Reference](#6-file-reference)
   - 6.1 [mwan3-skeleton.nft](#61-libmwan3mwan3-skeletonnft-static)
   - 6.2 [common.sh](#62-libmwan3commonsh)
   - 6.3 [mwan3.sh](#63-libmwan3mwan3sh)
   - 6.4 [init.d/mwan3](#64-etcinitdmwan3)
   - 6.5 [25-mwan3 - hotplug](#65-etchotplugdiface25-mwan3)
   - 6.6 [usr/sbin/mwan3 - CLI](#66-usrsbinmwan3-cli)
   - 6.7 [mwan3rtmon](#67-usrsbinmwan3rtmon)
   - 6.8 [rpcd/ucode/mwan3](#68-usrsharerpcducodemwan3)
   - 6.9 [Makefile](#69-makefile)
   - 6.10 [mwan3track](#610-usrsbinmwan3track)
   - 6.11 [mwan3-lb-test](#611-usrsbinmwan3-lb-test)
   - 6.12 [mwan3-diag](#612-usrsbinmwan3-diag)
   - 6.13 [mwan3ct](#613-usrsbinmwan3ct)
   - 6.14 [mwan3-get-addr.uc](#614-libmwan3mwan3-get-addruc)
   - 6.15 [mwan3-manage-rules.uc](#615-libmwan3mwan3-manage-rulesuc)
   - 6.16 [mwan3-list-routes.uc](#616-libmwan3mwan3-list-routesuc)
   - 6.17 [mwan3-create-iface-route.uc](#617-libmwan3mwan3-create-iface-routeuc)
   - 6.18 [mwan3ipcheck](#618-usrbinmwan3ipcheck)
7. [Function Reference](#7-function-reference)
   - 7.1 [common.sh Functions](#71-commonsh-functions)
   - 7.2 [Set Management Functions](#72-set-management-functions)
   - 7.3 [General Rule Setup](#73-general-rule-setup)
   - 7.4 [Interface Management](#74-interface-management)
   - 7.5 [Policy & Load Balancing](#75-policy--load-balancing)
   - 7.6 [Sticky Routing](#76-sticky-routing)
   - 7.7 [User Rules](#77-user-rules)
   - 7.8 [User-defined nft Set Management](#78-user-defined-nft-set-management)
   - 7.9 [Status Reporting](#79-status-reporting)
   - 7.10 [Lifecycle & Hotplug](#710-lifecycle--hotplug)
8. [Load Balancing with numgen](#8-load-balancing-with-numgen)
9. [Sticky Routing Detail](#9-sticky-routing-detail)
10. [Service Lifecycle and Conntrack Management](#10-service-lifecycle-and-conntrack-management)
    - 10.1 [Start](#101-start)
    - 10.2 [Reload](#102-reload)
    - 10.3 [Interface Up (hotplug)](#103-interface-up-hotplug)
    - 10.4 [Interface Down (hotplug)](#104-interface-down-hotplug)
    - 10.5 [Stop](#105-stop)
    - 10.6 [Conntrack Management](#106-conntrack-management)
11. [Atomic Non-destructive Reload](#11-atomic-non-destructive-reload)
12. [User-defined nft Sets](#12-user-defined-nft-sets)
13. [Unchanged Files](#13-unchanged-files)
14. [Diagnostic Commands](#14-diagnostic-commands)
15. [luci-app-mwan3](#15-luci-app-mwan3)
    - 15.1 [Network App](#151-network-app)
        - 15.1.1 [Globals](#1511-globals)
        - 15.1.2 [Interface](#1512-interface)
        - 15.1.3 [Member](#1513-member)
        - 15.1.4 [Policy](#1514-policy)
        - 15.1.5 [Rule](#1515-rule)
        - 15.1.6 [IP Sets](#1516-ip-sets)
        - 15.1.7 [Simulator](#1517-simulator)
        - 15.1.8 [Configuration](#1518-configuration)
        - 15.1.9 [Notify](#1519-notify)
    - 15.2 [Status App](#152-status-app)
        - 15.2.1 [Overview](#1521-overview)
        - 15.2.2 [Interface Status](#1522-interface-status)
        - 15.2.3 [Routing Health](#1523-routing-health)
        - 15.2.4 [IP Sets (Status)](#1524-ip-sets-status)
        - 15.2.5 [Diagnostics](#1525-diagnostics)
        - 15.2.6 [Troubleshooting](#1526-troubleshooting)
    - 15.3 [Backend: Helper Script and ACL](#153-backend-helper-script-and-acl)
    - 15.4 [rpcd Methods](#154-rpcd-methods)
16. [Iptables-to-nftables Porting Notes](#16-iptables-to-nftables-porting-notes)
17. [Command Line Tools](#17-command-line-tools)
    - 17.1 [mwan3-lb-test: Load Balancing Distribution Verifier](#171-mwan3-lb-test-load-balancing-distribution-verifier)
    - 17.2 [mwan3-diag: Network Diagnostic Report](#172-mwan3-diag-network-diagnostic-report)
18. [Changelog](#18-changelog)
    - 18.1 [Version 3.6.9](#181-version-369)
    - 18.2 [Version 3.6.8](#182-version-368)
    - 18.3 [Version 3.6.7](#183-version-367)
    - 18.4 [Version 3.6.6](#184-version-366)
    - 18.5 [Version 3.6.5](#185-version-365)
    - 18.6 [Version 3.6.4](#186-version-364)
    - 18.7 [Version 3.6.3](#187-version-363)
    - 18.8 [Version 3.6.2](#188-version-362)
    - 18.9 [Version 3.6.1](#189-version-361)
    - 18.10 [Version 3.6](#1810-version-36)
    - 18.11 [Version 3.5.3](#1811-version-353)
    - 18.12 [Version 3.5.2](#1812-version-352)
    - 18.13 [Version 3.5.1](#1813-version-351)
    - 18.14 [Version 3.5](#1814-version-35)
    - 18.15 [Version 3.4.1 (Unreleased)](#1815-version-341-unreleased)
    - 18.16 [Version 3.4](#1816-version-34)
    - 18.17 [Version 3.3.5](#1817-version-335)
    - 18.18 [Version 3.3.4](#1818-version-334)
    - 18.19 [Version 3.3.3](#1819-version-333)
    - 18.20 [Version 3.3.2](#1820-version-332)
    - 18.21 [Version 3.3.1](#1821-version-331)
    - 18.22 [Version 3.3](#1822-version-33)
    - 18.23 [Version 3.2.3](#1823-version-323)
    - 18.24 [Version 3.2.2](#1824-version-322)
    - 18.25 [Version 3.2.1](#1825-version-321)
    - 18.26 [Version 3.2](#1826-version-32)
    - 18.27 [Version 3.1.4](#1827-version-314)
    - 18.28 [Version 3.1.3](#1828-version-313)
    - 18.29 [Version 3.1.2](#1829-version-312)
    - 18.30 [Version 3.1.1](#1830-version-311)
19. [Specific use-cases](#19-specific-use-cases)
    - 19.1 [Tailscale](#191-tailscale)

---

## 1. Architecture Overview

mwan3 is OpenWrt's multi-WAN policy routing framework. It classifies packets using **firewall marks**, then uses `ip rule` entries to route marked packets through per-interface routing tables. The nftables port replaces all iptables/ipset usage with nftables equivalents while keeping the ip rule/route management largely unchanged. `mwan3rtmon` is ported to a ucode implementation.

### Key Design Decisions

- **Own standalone table** - mwan3 lives in `table inet mwan3`, completely independent of `table inet fw4`. fw4 reload, restart, or reconfiguration has no effect on mwan3 rules.
- **Static skeleton + dynamic rules** - `mwan3-skeleton.nft` defines empty sets and chains loaded by `nft -f` at service start using the atomic table-replace idiom. All rules are added dynamically by shell scripts since they depend on the configurable `MMX_MASK`.
- **Hook priority `mangle + 1`** - `mwan3_prerouting` and `mwan3_output` register at priority `-149`, placing them after fw4's mangle chains and any other packages registering at `-150`. Mark operations use masked OR-immediate setter chains via vmap-dispatch so they are non-destructive with respect to bits owned by other packages regardless of execution order.
- **Non-destructive mark save/restore** - Connmark save and restore are masked to mwan3's own bit-range (`MMX_MASK`) and never touch bits owned by other packages. The kernel rejects compound two-source bitwise expressions; mwan3 synthesises masked save/restore through a vmap-dispatch technique built from per-mark OR-immediate setter chains. See [Section 2 - Connmark Operations](#connmark-operations).
- **inet family** - Chains handle both IPv4 and IPv6 in a single pass. Sets remain type-specific (separate v4/v6 sets) since nftables requires a single address type per set.
- **Atomic non-destructive reload** - `reload_service` rebuilds the entire mwan3 ruleset in a single `nft -f` batch while the old ruleset serves traffic, committing atomically with zero downtime window. See [Section 11](#11-atomic-non-destructive-reload).
- **User-defined nft sets** - `config ipset` sections in `/etc/config/mwan3` create named nft sets in `table inet mwan3` supporting inline entries, file loading, and dnsmasq domain population. See [Section 12](#12-user-defined-nft-sets).

### Component Map

```diagram
                                                UCI Config (/etc/config/mwan3)
                                                              |
                            +---------------------------------+---------------------------------+
                            |                                 |                                 |
                       init.d/mwan3                      mwan3track                         mwan3rtmon
                    (service lifecycle)                (health probes)                 (route replication)
                            |                                 |                                 |
       +--------------------+--------------------+            |                                 |
       |                    |                    |            |                                 |
       v                    v                    v            |                                 |
    common.sh           mwan3.sh        mwan3-skeleton.nft    |                                 |
    (helpers)           (engine)        (static skeleton)     |                                 |
       |                    |                    |            |                                 |
       v                    v                    |            |                                 |
 mwan3-get-addr.uc       mwan3ct                 |            |                                 |
       |          mwan3-manage-rules.uc          |            |                                 |
       |          mwan3-list-routes.uc           |            |                                 |
       |       mwan3-create-iface-route.uc       |            |                                 |
       |                    |                    |            |                                 |
       v                    v                    v            v                                 v
   nft / netlink    netlink / conntrack         nft     writes STATUS files                nft / netlink
                                                      to /var/run/mwan3track
  

        Hotplug:       25-mwan3                      --calls-->   mwan3.sh functions
        Hotplug user:  26-mwan3-user                 --calls-->   /etc/mwan3.user
        CLI:           /usr/sbin/mwan3               --calls-->   mwan3.sh functions
        RPC:           rpcd/ucode/mwan3              --calls-->   nft -j (JSON output)
        dnsmasq:       mwan3_write_dnsmasq_fragments --writes-->  confdir nftset fragments
        mwan3rtmon:                                  --uses-->    ucode-mod-rtnl (netlink) + nft
        mwan3ct:                                     --uses-->    libnetfilter_conntrack + libmnl
        mwan3.sh:                                    --calls-->   mwan3ct (conntrack flush)
        mwan3.sh:                                    --calls-->   mwan3-manage-rules.uc (ip rule management)
        mwan3.sh:                                    --calls-->   mwan3-list-routes.uc (route enumeration)
        mwan3.sh:                                    --calls-->   mwan3-create-iface-route.uc (route install)
        mwan3-get-addr.uc:                           --uses-->    ucode-mod-rtnl (netlink)
        mwan3-manage-rules.uc:                       --uses-->    ucode-mod-rtnl (netlink)
        mwan3-list-routes.uc:                        --uses-->    ucode-mod-rtnl (netlink)
        mwan3-create-iface-route.uc:                 --uses-->    ucode-mod-rtnl (netlink)
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

mwan3 synthesises the masked-restore and masked-save from primitives the kernel does allow: OR-ing a *literal immediate* into a single register (restore), or masking and OR-ing in a single expression (save).

```
meta mark set meta mark | <constant>                   # restore: only sets bits, never clears
ct mark set ct mark & MMX_MASK_COMPLEMENT | <constant>  # save: atomic clear+set in one expression
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

# Save: atomic clear+set via vmap dispatch
meta mark & MMX_MASK vmap {
    0x0100 : jump mwan3_or_ct_0x0100,
    ...
}

chain mwan3_or_ct_0x0100 { ct mark set ct mark & MMX_MASK_COMPLEMENT | 0x0100 ; return }
...
```

**Properties:**

- **Restore** is purely additive (`meta mark | <imm>`); bits in meta mark not owned by mwan3 are preserved across restore.
- **Save** atomically clears mwan3's own bits and sets the new value in a single nft expression (`ct mark & MMX_MASK_COMPLEMENT | <imm>`, where `MMX_MASK_COMPLEMENT = ~MMX_MASK & 0xFFFFFFFF`). The ct mark goes directly from old-value to new-value with no intermediate state visible to other CPUs. Bits owned by other packages survive the save unchanged.
- The dispatch tables are bounded: with the default `MMX_MASK = 0x3F00`, there are 63 possible non-zero mwan3 mark values, so 63 setter chains per direction (126 total). All chains are 2-statement skeletons (a mark-set expression + `return`).
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
| `mwan3_postrouting` | chain (nat, postrouting, srcnat-1) | Opt-in IPv6 SNAT for router-originated rerouted traffic - see [§4](#router-originated-traffic-and-source-address-rewriting) |
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
  |     meta mark & MMX_MASK -> jump mwan3_or_ct_<mark>
  |     (atomic clear+set in one expression; preserves non-mwan3 bits in ct mark)
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

### Router-Originated Traffic and Source Address Rewriting

When the router itself originates a packet (via `mwan3_output`), the kernel binds the source address at `sendto()` time using the initial, unmarked route lookup. mwan3's mark is not set at that point, so the kernel picks the source address corresponding to whichever WAN the unmarked default route points to - call it WAN-A. Later in the egress path, `mwan3_output` sets a mark and the kernel performs a re-lookup (because the chain is `type route`) that may move the outgoing interface to WAN-B. The re-lookup updates `oif` but does not rewrite the source address - that was already committed. The packet leaves WAN-B carrying WAN-A's source address and is dropped upstream by BCP38 or uRPF filtering.

mwan3track is unaffected by this problem: it sets `SO_BINDTODEVICE` at socket creation, which forces the correct source address at bind time before any of this occurs.

**IPv4:** fw4's `srcnat_wan` masquerade rule applies to all outgoing traffic including locally-originated packets. When a rerouted packet reaches the `srcnat` hook, masquerade picks the primary IP of the actual outgoing interface and rewrites the source address correctly. No per-interface SNAT rule is needed from mwan3 - fw4 handles it automatically.

**IPv6:** fw4 does not masquerade IPv6 by default, so there is no automatic safety net. mwan3 provides an opt-in per-interface UCI option `snat6` to address this. Blanket NAT66 is deliberately not the default for several reasons: RFC 6724 source-address selection with SADR routing tables can solve the problem without NAT in correctly-configured dual-stack deployments; NAT66 is harmful in ULA+delegated-PA topologies and breaks address-embedding protocols; some upstreams (tunnel brokers, fixed-address WireGuard endpoints) require a specific source address; and the IPv6 community treats address translation as an explicit opt-in.

The `snat6` option accepts three values:

| Value | Meaning |
|---|---|
| unset / `0` | No IPv6 SNAT (default) |
| `1` | SNAT to the interface's primary global address, looked up via `mwan3_get_src_ip` |
| `<v6 addr>` | SNAT to the literal address - used for fixed-source pinning from a delegated prefix |

When `snat6` is set, mwan3 installs a rule in the `mwan3_postrouting` base chain:

```
oifname "<dev>" meta nfproto ipv6
    meta mark & MMX_MASK == <iface_mark>
    fib saddr type local
    ip6 saddr != <iface_src_ip>
    snat to <iface_src_ip>
```

The `fib saddr type local` guard limits the rule to router-originated traffic. Stale rules are cleaned up by tag (`mwan3_snat_<iface>`) in `mwan3_create_iface_nft()` and `mwan3_delete_iface_nft()`. The literal-address form is not validated against the egress interface - some deployments deliberately pin a source from a delegated prefix not directly configured on the device.

`snat6` only addresses the router-originated rerouted case. It does not extend mwan3's IPv6 capability to forwarded LAN traffic, SADR integration, or NPTv6 prefix translation.

The LuCI control for `snat6` is described in [Section 15.1.2](#1512-interface).

---

## 5. IP Rules and Lookup Tables

mwan3 uses Linux policy routing as the actual packet-steering mechanism. The nftables chains (Section 4) write a firewall mark onto each packet; the kernel's `ip rule` database then selects the right routing table based on that mark. The nftables side and the policy-routing side are independent: nftables writes marks, the kernel routes according to them.

### 5.1 Per-Interface Routing Tables

Each mwan3 `config interface` section is assigned a sequential integer ID by `mwan3_update_iface_to_table()`. Interface sections are enumerated in UCI declaration order; the first enabled interface is ID 1, the second is ID 2, and so on. The ID is both the routing table number and the input to `mwan3_id2mask()` that generates the interface's mark value (see Section 2). Routing tables 1 through `MWAN3_INTERFACE_MAX` (derived from `MMX_MASK`) are reserved for mwan3 and should not be used for other purposes.

Each per-interface routing table is built by `mwan3_create_iface_route()` from two sources:

- CIDR routes from the main routing table (host routes are excluded)
- Routes from any additional tables listed in UCI `globals.rt_table_lookup`

The `MWAN3_ROUTE_LINE_EXP` sed expression strips transient attributes (`linkdown`, `offload`, expiry timestamps, `error` codes) before copying routes. Routes whose device matches the mwan3 interface's network device keep their original `dev` clause; the interface's default gateway (`default via ... dev ...`) is the critical entry that directs all policy-routed traffic to the correct WAN path.

### 5.2 Three ip Rule Tiers Per Interface

`mwan3_create_iface_rules()` installs three `ip rule` entries for each mwan3 interface. For IPv4 interfaces these are installed via `ip rule`; for IPv6 via `ip -6 rule`. All three tiers are installed together when the interface comes up (`ifup` hotplug event) and removed together when it goes down (`ifdown`).

**Tier 1 - iif lookup** (priority `id + iif_rule_base`, default `id + 1000`):

```
ip rule add pref <id+1000> iif <device> lookup <id>
```

Matches packets arriving on this interface's network device, regardless of mark. Routes them by looking up the interface's own routing table. This handles traffic that arrived on a WAN interface and needs to exit the router via the same WAN - the interface's table contains the WAN's default gateway. Without this rule, reply packets from the router (such as responses to health-check probes from the WAN's remote host) would reach the routing decision without a mark, fall through to the main table, and potentially exit via a different WAN.

**Tier 2 - fwmark lookup** (priority `id + fwmark_rule_base`, default `id + 2000`):

```
ip rule add pref <id+2000> fwmark <mark>/<MMX_MASK> lookup <id>
```

The primary steering rule. Matches packets whose mark, after masking with `MMX_MASK`, equals this interface's mark value (computed by `mwan3_id2mask(id, MMX_MASK)`). Routes them through the interface's per-interface routing table, which contains the WAN's default gateway. This is the rule that causes policy-classified traffic to exit via the correct WAN.

**Tier 3 - fwmark unreachable** (priority `id + unreachable_rule_base`, default `id + 3000`):

```
ip rule add pref <id+3000> fwmark <mark>/<MMX_MASK> unreachable
```

Matches the same fwmark as Tier 2 but returns ICMP unreachable instead of routing. Sits below Tier 2 in priority (higher priority number = lower precedence). Serves as a safety net: if the Tier 2 lookup finds an empty or incomplete routing table (e.g. the default route is transiently absent during route installation), the packet receives an explicit unreachable response instead of silently falling through to the main routing table and potentially leaking out a different WAN.

### 5.3 Global Policy Rules

`mwan3_set_general_rules()` installs two rules that are not tied to any specific interface. These handle the mark values reserved for policy `last_resort` actions:

**Blackhole rule** (priority `MM_BLACKHOLE + fwmark_rule_base`):

```
ip rule add pref <priority> fwmark <MMX_BLACKHOLE>/<MMX_MASK> blackhole
```

Silently drops packets marked with `MMX_BLACKHOLE`. Applied when a policy chain marks traffic with this value via a `last_resort blackhole` policy option.

**Unreachable rule** (priority `MM_UNREACHABLE + fwmark_rule_base`):

```
ip rule add pref <priority> fwmark <MMX_UNREACHABLE>/<MMX_MASK> unreachable
```

Returns ICMP unreachable for packets marked with `MMX_UNREACHABLE`. This is the default `last_resort` for policies with no available members.

With `MMX_MASK = 0x3F00` (6 mask bits): `MM_BLACKHOLE = 61`, priority `61 + 2000 = 2061`; `MM_UNREACHABLE = 62`, priority `62 + 2000 = 2062`. Both fall within the fwmark tier, above all per-interface Tier 2 entries.

### 5.4 MMX_DEFAULT Fall-Through

Packets marked with `MMX_DEFAULT` (= `MMX_MASK`, all mask bits set) do not match any per-interface fwmark rule or the global blackhole/unreachable rules. They fall through to the kernel's standard policy database, which includes the `main` routing table at priority 32766. Traffic stamped `MMX_DEFAULT` is routed normally via the main table without any mwan3 policy steering. This is the intended path for traffic destined for directly-connected, custom-table, or dynamically bypassed networks (see the bypass set groups in Section 4).

### 5.5 Configurable Rule Base Priorities

The three rule-base offsets are configurable in UCI `config globals`:

| UCI option | Default | Priority range used (60 interfaces, default MMX_MASK) |
|---|---|---|
| `iif_rule_base` | 1000 | 1001 - 1060 (one per interface) |
| `fwmark_rule_base` | 2000 | 2001 - 2062 (per-interface + 2 global) |
| `unreachable_rule_base` | 3000 | 3001 - 3060 (one per interface) |

Two ordering constraints must hold at startup:

```
iif_rule_base + MWAN3_INTERFACE_MAX < fwmark_rule_base
fwmark_rule_base + MWAN3_INTERFACE_MAX + 1 < unreachable_rule_base
```

The `+ 1` in the second constraint accounts for the global blackhole and unreachable entries at the top of the fwmark tier (`MM_BLACKHOLE + fwmark_rule_base` and `MM_UNREACHABLE + fwmark_rule_base`). If either constraint is violated, `mwan3_init` logs a warning and reverts all three to 1000/2000/3000.

`mwan3_delete_face_rules()` uses content-based matching to find and delete rules: it scans `ip rule list` for entries referencing `lookup <id>` to identify iif rules, and derives the fwmark value from the fwmark lookup rule before deleting the matching unreachable rule. This approach remains correct if the bases or `MMX_MASK` are changed between service restarts.

### 5.6 Example: Live ip rule Output

```
0:      from all lookup local
1001:   from all iif eth1 lookup 1
1002:   from all iif eth2 lookup 2
2001:   from all fwmark 0x100/0x3f00 lookup 1
2002:   from all fwmark 0x200/0x3f00 lookup 2
2061:   from all fwmark 0x3d00/0x3f00 blackhole
2062:   from all fwmark 0x3e00/0x3f00 unreachable
3001:   from all fwmark 0x100/0x3f00 unreachable
3002:   from all fwmark 0x200/0x3f00 unreachable
32766:  from all lookup main
32767:  from all lookup default
```

The corresponding per-interface routing table (`ip route show table 1`) contains the WAN gateway and a copy of connected routes:

```
default via 192.0.2.1 dev eth1
192.0.2.0/24 dev eth1 proto kernel scope link src 192.0.2.2
192.168.1.0/24 dev br-lan proto kernel scope link src 192.168.1.1
```

The priority gap between 2002 and 2061 is intentional: per-interface Tier 2 entries occupy priorities 2001-2060 (with the default 60-interface capacity) and the global entries occupy 2061-2062 at the top of the fwmark tier.

---

## 6. File Reference

### 6.1 `lib/mwan3/mwan3-skeleton.nft` [static]

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
- `mwan3_postrouting` - type `nat` at priority `srcnat - 1`. Opt-in IPv6 SNAT chain. See [§4](#router-originated-traffic-and-source-address-rewriting).

### 6.2 `lib/mwan3/common.sh`

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
- **`mwan3_or_chain_suffix()`**: Converts a numeric mark value to the canonical lowercase `0x%x` hex string used as the suffix for OR-immediate setter chain names (e.g. `0x100` for interface 1 with default mask). Called by `mwan3_build_or_chains_nft()`, `mwan3_or_vmap_body()`, `mwan3_all_marks()`, and `mwan3_create_policies_nft()`.
- **`mwan3_or_vmap_body()`**: Builds the body string for a vmap statement dispatching on masked mark values into OR-immediate setter chains. Called by `mwan3_set_general_nft()`.
- **`mwan3_all_marks()`**: Enumerates every mark value that needs to appear in the restore/save vmaps: all per-interface marks plus `MMX_DEFAULT`, `MMX_BLACKHOLE`, and `MMX_UNREACHABLE`. Echoes a space-separated list. Used by `mwan3_set_general_nft()`.
- **`mwan3_build_or_chains_nft()`**: Materialises the per-mark setter chains used by the non-destructive vmap-dispatch save/restore. Iterates all 63 possible non-zero values within `MMX_MASK` and emits two chains per value: `mwan3_or_meta_<imm>` (non-destructive restore from ct mark to meta mark) and `mwan3_or_ct_<imm>` (atomic clear+set save from meta mark to ct mark, non-destructive to bits outside MMX_MASK). Called from `mwan3_set_general_nft()`. Always flushes and re-populates the chain bodies - an earlier idempotency check that returned early on chain *existence* alone could leave the chain bodies empty after a partial-failure first run, which is fatal to packet flow.
- **`mwan3_init()`**: Loads config, computes mask constants (`MMX_DEFAULT`, `MMX_BLACKHOLE`, `MMX_UNREACHABLE`, `MMX_MASK_COMPLEMENT`)
- **`mwan3_id2mask()`**: Bit-spreading function that maps interface IDs onto the mask
- **`mwan3_count_one_bits()`**: Counts set bits in a value
- **Utility functions**: `LOG()`, `readfile()`, `mwan3_get_src_ip()`, `mwan3_get_true_iface()`, `mwan3_get_mwan3track_status()`, `get_uptime()`, `get_online_time()`

> [!NOTE]
> **Shell scoping note:** Functions like `mwan3_id2mask` and `mwan3_count_one_bits` receive *variable names* as arguments (e.g., `mwan3_id2mask mmdefault MMX_MASK`) and use arithmetic expansion `$(($1))` to resolve them. This works in busybox ash (OpenWrt's default shell) because it uses dynamic scoping - local variables from the caller are visible in called functions.

### 6.3 `lib/mwan3/mwan3.sh`

The core engine. Contains all functions for managing nftables chains/sets/maps, ip rules, ip routes, policy creation, user rule classification, and status reporting. This is the largest file and the heart of the implementation. Sourced by init.d, hotplug, CLI, and rtmon scripts.

See [Section 7](#7-function-reference) for detailed function reference.

### 6.4 `etc/init.d/mwan3`

procd service script. Handles:

- **`start_service()`**: Loads `mwan3-skeleton.nft` via `nft -f` first (aborts if this fails), then runs the full init sequence: ensure framework, render ipsets, dnsmasq fragments, trackers, sets, general rules, ifup hotplug loop, nft chains, policies, user rules, conntrack flush (if flow offloading), dnsmasq HUP, rtmons.
- **`stop_service()`**: Guards with `service_running || exit 0`. Shuts down interfaces, flushes ip routes/rules, flushes all mwan3 nft chains, deletes dynamic chains (keeps skeleton chains), flushes sets, flushes and deletes sticky maps, then `$NFT delete table inet mwan3` (complete removal).
- **`reload_service()`**: Atomically rebuilds the entire mwan3 ruleset in a single kernel transaction via `mwan3_nft_reload_start` / all build functions / `mwan3_nft_reload_commit`. Then updates ip rules/routing tables (outside nft), updates dnsmasq fragments if changed, and checks tracker count - falls through to `stop; start` if tracker count mismatches (procd cannot add/remove service instances in reload).
- **`start_tracker()`**: Launches a `mwan3track` procd instance per enabled interface with track IPs or `track_gateway`.
- **`service_running()`**: Returns true if `$MWAN3_STATUS_DIR` exists.

#### Startup Sequence

```
nft -f /lib/mwan3/mwan3-skeleton.nft         # load standalone table (abort if fails)
mwan3_init()                                 # load UCI config, compute mask constants
mwan3_ensure_nft_framework()                 # recreate 6 internal sets, ensure chains
mwan3_render_config_ipsets()                 # create user-defined sets from config ipset
mwan3_write_dnsmasq_fragments()              # write nftset confdir fragments; restart dnsmasq if changed
config_foreach start_tracker interface       # launch health probes
mwan3_update_iface_to_table()                # build iface->table mapping
mwan3_set_dynamic_sets()                     # populate dynamic sets
mwan3_set_connected_sets()                   # populate connected sets
mwan3_set_custom_sets()                      # populate custom sets
mwan3_set_general_rules()                    # ip rule add (blackhole/unreachable)
config_foreach mwan3_ifup interface "init"   # trigger ifup hotplug per interface
wait $hotplug_pids
mwan3_set_general_nft()                      # populate hook chain rules
mwan3_set_policies_nft()                     # create policy chains
mwan3_set_user_rules()                       # populate user rules chain
mwan3_flush_stale_conntrack()                # flush zero-mark conntrack entries
mwan3_dnsmasq_hup()                          # HUP dnsmasq to re-populate nftset domains
[if flow_offloading=1] flush conntrack       # force flow re-establishment under new policy
start rtmon_ipv4 + rtmon_ipv6                # route monitor daemons
```

### 6.5 `etc/hotplug.d/iface/25-mwan3`

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

### 6.6 `usr/sbin/mwan3` (CLI)

User-facing command-line tool. Provides `start`/`stop`/`restart`/`ifup`/`ifdown` commands plus status reporting: `interfaces`, `policies`, `connected`, `rules`, `status` (all combined), and `internal` (detailed dump).

The `use` command runs an arbitrary command bound to a specific interface using `LD_PRELOAD` with `libwrap_mwan3_sockopt.so`.

The `internal` command shows `nft list table inet mwan3` output instead of the old iptables dump.

### 6.7 `usr/sbin/mwan3rtmon`

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

### 6.8 `usr/share/rpcd/ucode/mwan3`

ucode RPC service exposing ubus methods under the `mwan3` object. Used by LuCI for the web interface.

Uses `nft -j` (JSON output mode) for reliable parsing. All set/chain queries are scoped to `table inet mwan3`. Rule and route queries use `ucode-mod-rtnl` (RTM_GETRULE, RTM_GETROUTE) directly rather than spawning `ip -j` subprocesses.

- **`mwan3.status`**: Returns JSON data for interfaces, connected networks, and policies.
  - **Connected IPs**: Parses `nft -j list set inet mwan3 mwan3_connected_v4/v6`.
  - **Policies**: Reads membership from UCI config and cross-references mwan3track `STATUS` files. Every member is always reported with traffic share percentage.
  - **Interfaces**: Reads status from `/var/run/mwan3track/` files and queries procd/netifd via ubus. Tracking IPs discovered by globbing `TRACK_*` files. Per-IP `latency` and `packetloss` populated when `check_quality=1`.
- **`mwan3.nftset_members { set: "<name>" }`**: Returns members of a named nft set in `table inet mwan3` as a flat array of strings. Correctly unwraps counter-decorated elements (`{"elem":{"val":"...","counter":{...}}}`) that nft emits for sets with the `counter` flag. Used by the Simulator tab for nftset rule matching and connected-network bypass detection.
- **`mwan3.nftset_info {}`**: Returns the name, address-family type, counters flag, and runtime element count of all non-mwan3 sets in `table inet mwan3`. Used by the rule editor and IP Sets status tab.
- **`mwan3.nftset_elements { set: "<name>", max: N }`**: Returns paginated elements of a named user-defined set with per-element packet/byte counters (when the set has `counter` enabled). Default maximum 200 elements; supports up to 5000. Used by the IP Sets status tab for runtime member display.
- **`mwan3.resolve_host { host: "<name>", family: "" }`**: Resolves a hostname to IP addresses by invoking `/bin/busybox nslookup` against the local DNS server (127.0.0.1). Returns `{ v4: [...], v6: [...] }`. The `family` parameter can be set to `ipv4` or `ipv6` to restrict resolution to A or AAAA records respectively; omit or leave empty for both. Querying via the local DNS server has the side effect of populating any dnsmasq nftset entries configured for the domain. Used by the Simulator tab to support hostname input in the source and destination fields.
- **`mwan3.nftset_flush { set: "<name>" }`**: Flushes all elements from the named set via `nft flush set inet mwan3 <name>`. Returns `{}` on success or `{ error: "..." }` on failure. Used by the Flush button on the IP Sets status tab.
- **`mwan3.nftset_reload { set: "<name>" }`**: Flushes the set then re-adds all static entries from the UCI `config ipset` section (`list entry` values and the `loadfile` if configured). Returns `{}` on success or `{ error: "..." }` on failure. Used by the Reload button on the IP Sets status tab.
- **`mwan3.nftset_resolve { set: "<name>" }`**: Sends SIGHUP to dnsmasq to clear its cache, then queries each domain configured under the set's `list domain` option via the local dnsmasq instance (127.0.0.1). The DNS queries trigger dnsmasq's `nftset=` population mechanism as a side effect. Returns `{ resolved: N }` where N is the count of domains that resolved successfully. Only applicable for sets with `list domain` entries. Used by the Resolve button on the IP Sets status tab.
- **`mwan3.routing_health {}`**: Compares UCI configuration against live kernel state. Reads `iif_rule_base`, `fwmark_rule_base`, and `unreachable_rule_base` from UCI globals (with the same defaults and ordering constraint validation as `mwan3_init`) and derives `iface_max` dynamically from `mmx_mask`. Per interface, checks presence of the iif rule, fwmark lookup rule, and unreachable rule, and reports routing table default route presence. Reports stale ip rules across all three priority tiers. Returns a `rule_bases` object so the frontend can display configured priorities dynamically rather than assuming fixed offsets.

### 6.9 `Makefile`

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
| | `+ucode-mod-socket` |
| | `+libnetfilter-conntrack` |

`PKG_BUILD_DEPENDS` adds `libnetfilter_conntrack` and `libmnl` for the headers and libraries needed to compile `mwan3ct.c`. The runtime `+libnetfilter-conntrack` dependency provides the shared library that `mwan3ct` links against on the target.

`mwan3ipcheck.c` is also compiled in the same build step. It links only against libc (`inet_pton`, `strtol`, standard string functions) and requires no additional build or runtime dependencies.

The ucode dependencies are required by the reimplemented `mwan3rtmon` route monitor daemon. `ucode-mod-socket` is required by `mwan3-diag` for address normalisation.

Also installs:

- `mwan3-skeleton.nft` to `$(1)/lib/mwan3/`
- `mwan3-migrate-ipset-v4.sh` to `$(1)/lib/mwan3/` (one-shot migration helper, deleted from the router after postinst runs it)
- `mwan3-remove-firewall-include` UCI defaults to `$(1)/etc/uci-defaults/` (removes legacy `firewall.mwan3_reload` UCI section from v3.x)
- `mwan3-lb-test` to `$(1)/usr/sbin/`
- `mwan3ct` to `$(1)/usr/sbin/`
- `mwan3ipcheck` to `$(1)/usr/bin/`

The `preinst` script stops mwan3 before APK replaces any files. This handles the upgrade case where procd watches `/etc/init.d/` via inotify and auto-starts mwan3 when the init script is replaced.

The `postinst` script:
1. Removes any mwan3 chains and sets still in `table inet fw4` (from v3.x upgrades)
2. Conditionally reloads fw4 only if the legacy `firewall.mwan3_reload` UCI section exists (v3.x only; avoids triggering queued hotplug events on a clean v3.5 install)
3. Runs `mwan3-migrate-ipset-v4.sh` to copy `config ipset` sections from `/etc/config/firewall` to `/etc/config/mwan3`, then removes the migration script
4. Restarts rpcd
5. Stops mwan3 a second time (by this point procd's auto-start has completed, so this stop removes auto-start's ip rules)
6. Starts mwan3 cleanly

### 6.10 `usr/sbin/mwan3track`

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

### 6.11 `usr/sbin/mwan3-lb-test`

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

See [§17.1](#171-mwan3-lb-test-load-balancing-distribution-verifier) for context on why this tool was added and the numgen contamination issues it was designed to detect.

---

### 6.12 `usr/sbin/mwan3-diag`

Network diagnostic report generator.

```
mwan3-diag
```

A ucode script that collects a comprehensive snapshot of the network state relevant to mwan3 operation and prints it to stdout. Intended to produce a complete, shareable report without manual redaction.

Collects: interface addresses, routing tables (including all per-WAN tables), policy rules, neighbour cache, mwan3 interface status, mwan3 UCI configuration, the complete mwan3 nftables ruleset, the fw4 mangle chains that interact with mwan3 packet marking, and the last 200 lines of the mwan3 log.

Before printing any output the script builds a map of every public routable IPv4 and IPv6 address present in the collected data and replaces each one with a stable placeholder -- `PUB4_1`, `PUB4_2`, `PUB6_1` and so on -- throughout the entire report. The same address always receives the same placeholder, so cross-references between sections remain consistent. Private addresses (RFC1918, link-local `fe80::`, ULA `fc00::/7`, loopback) are left unchanged. The elements of user-defined nftables sets are replaced with `{ ... }`.

See [§17.2](#172-mwan3-diag-network-diagnostic-report) for context.

---

### 6.13 `usr/sbin/mwan3ct`

Targeted conntrack entry flush helper.

mwan3 needs to flush conntrack entries at multiple places in the code. These flushes are designed to be as targeted as possible in order to leave other unrelated conntrack entries unmolested. 

In some cases, the conntrack CLI tool is unable to perform the necessary targeted flush. For example, mwan3 needs to flush only UNREPLIED conntrack entries when an interface comes online to break the cycle where a stale mark pins traffic to the wrong WAN. `conntrack -D` silently ignores the `-u` status filter because the delete path in conntrack-tools omits the status filter from the kernel request, making UNREPLIED-only deletion impossible via the CLI. 

The workaround is to parse `conntrack -L` output in shell, extract 5-tuple fields from each matching entry, and issue a separate `conntrack -D` call per entry. However, this is sensitive to output format changes and requires multiple subprocesses per entry. 

Additionally, flushing all mwan3-marked entries with conntrack requires a shell loop spawning one conntrack process per mark value (up to 63 for the default 6-bit mask). 

mwan3ct is a small C binary that calls libnetfilter_conntrack's `NFCT_Q_FLUSH_FILTER` directly, passing mark and status filters to the kernel in a single netlink message. The kernel performs the filtered delete atomically - no dump, no iteration, no per-entry delete is needed.

```
mwan3ct flush [--mark <val>/<mask>] [--mark-any <mask>] [--status <val>/<mask>]
```

- **`--mark <val>/<mask>`**: delete entries with an exact mark match. Single kernel call.
- **`--mark-any <mask>`**: delete entries with any non-zero mark value within the mask. Internally loops over all possible mark IDs (up to 63 for the default 6-bit mask), issuing one kernel call per ID. All within a single process and netlink socket.
- **`--status <val>/<mask>`**: filter by conntrack status bits. For example, `--status 0/0x2` matches entries where IPS_SEEN_REPLY (0x2) is not set, i.e. UNREPLIED entries.
- **`--mark` and `--mark-any` are mutually exclusive.** At least one filter option is required.
- **`--mark`** and **`--status`** filters can be combined.

Exit code 0 on success, including when no entries were matched. Errors are printed to stderr.

---

### 6.14 `lib/mwan3/mwan3-get-addr.uc`

Address lookup helper.

Queries the kernel via RTM_GETADDR (netlink) to find an IP address in one of two modes:

- **By device**: given `<family> <device>`, returns the first suitable address on that device. For IPv6, skips link-local (fe80::/10) and non-global-scope addresses. For IPv4, accepts scope 0 (global) and scope 253 (link).
- **By prefix**: given `<family> "" <prefix>`, returns the first global-scope address whose string representation begins with the prefix. Used for IPv6 prefix matching.

Prints the address stripped of any prefix-length to stdout and exits 0, or exits 1 if no matching address is found. Replaces `ip -f inet[6] addr show dev <device>` shell parsing.

---

### 6.15 `lib/mwan3/mwan3-manage-rules.uc`

Routing policy rule manager.

Manages ip rules (policy routing entries) via netlink (RTM_GETRULE, RTM_NEWRULE, RTM_DELRULE). Supports four modes:

- **`check <family> <prio1> [prio2...]`**: returns a decimal bitmask where bit N is set if the Nth listed priority is absent from the live rule table. Used by mwan3.sh to decide which rules need to be created.
- **`check-route <family> <table_id> <device>`**: exits 0 if a default route for the given output device exists in the specified table, 1 otherwise. Used before populating per-interface tables to detect whether the route is already present.
- **`delete-iface <id> <iif_base> <fwmark_base> <unreachable_base> <mmx_mask>`**: removes the iif lookup, fwmark lookup, and unreachable rules for a single interface (identified by its sequential index). Each rule is located by priority and verified by type before deletion; rules not present are silently skipped.
- **`add-general <family> <bh_prio> <bh_mark> <ur_prio> <ur_mark> <mask>`**: adds the shared blackhole and unreachable rules common to all interfaces. Rules already present at those priorities are not re-added.

Replaces `ip rule add/del` shell invocations that required fork-exec per operation and text parsing for presence checks.

---

### 6.16 `lib/mwan3/mwan3-list-routes.uc`

Route table lister.

Dumps routes from a given routing table via RTM_GETROUTE and prints destination prefixes to stdout, one per line. Accepts a numeric table ID or the special value `main`. Filters out: default routes (0.0.0.0/0, ::/0), host routes (prefix-length 32/128), link-local prefixes (fe80::/10, 169.254.0.0/16), IPv4 multicast (first octet >= 224), and duplicate destinations.

Used by mwan3.sh to enumerate routes that need to be copied into per-interface routing tables.

---

### 6.17 `lib/mwan3/mwan3-create-iface-route.uc`

Per-interface routing table populator.

Copies routes from the main routing table (and any additional tables listed in the `rt_table_lookup` UCI global) into a single per-interface routing table via RTM_NEWROUTE with NLM_F_CREATE | NLM_F_REPLACE. Uses ubus (`network.interface dump`) to map interface names to their kernel devices and table IDs; the `_4`/`_6` suffix convention for dual-stack interface pairs is recognised. Routes already present in the target table (matched by dst/oif/gateway/priority) are skipped. When `source_routing` is set, the route's source address is included in the copy.

Replaces `ip route add table <id>` shell invocations that required fork-exec and text parsing of `ip route show` output.

### 6.18 `usr/bin/mwan3ipcheck`

IP address and CIDR validation binary. Accepts a single argument and prints one of four classification strings to stdout, exiting 0 on success or 1 on failure.

| Output | Exit | Meaning |
|---|---|---|
| `ipv4` | 0 | All elements are valid IPv4 addresses or IPv4 CIDR prefixes |
| `ipv6` | 0 | All elements are valid IPv6 addresses or IPv6 CIDR prefixes |
| `mixed` | 1 | Comma-separated list contains a mix of IPv4 and IPv6 elements |
| `invalid` | 1 | Any element failed validation, input is empty, or argument count is wrong |

The argument may be a single address, a single CIDR prefix, or a comma-separated list of addresses and prefixes. Leading and trailing whitespace around each comma-separated token is stripped before classification.

**Address validation** uses `inet_pton()` - first trying `AF_INET`, then `AF_INET6`. Any address accepted by `mwan3ipcheck` is guaranteed to be accepted by nft, which uses the same parser internally.

**CIDR validation:** when a `/` is present, the prefix length is validated against the family maximum (32 for IPv4, 128 for IPv6). Out-of-range values and leading zeros in the prefix length are rejected. A trailing `/` with no digits is rejected.

**Comma-separated lists:** each token is classified individually. If all tokens are the same family the list returns that family. If tokens span both families the result is `"mixed"`, which the rule-building path rejects since a single nft anonymous set cannot contain both IPv4 and IPv6 elements.

The binary has no dependencies beyond libc (`inet_pton`, `strtol`, and standard string functions only).

---

## 7. Function Reference

### 7.1 common.sh Functions

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
| `mwan3_build_or_chains_nft` | Builds the 126 per-mark setter chains used by vmap-dispatch save/restore (63 `mwan3_or_meta_<imm>` restore chains + 63 `mwan3_or_ct_<imm>` atomic clear+set save chains). Always flushes and re-populates chain bodies. See [§2 Connmark Operations](#connmark-operations). |
| `mwan3_or_chain_suffix mark` | Converts a numeric mark value to the canonical lowercase `0x%x` hex string used as the suffix for OR-immediate setter chain names (e.g. `0x100` for interface 1 with default mask). Called by `mwan3_build_or_chains_nft`, `mwan3_or_vmap_body`, `mwan3_all_marks`, and `mwan3_create_policies_nft`. |
| `mwan3_or_vmap_body reg mark...` | Builds the body string for a vmap statement dispatching on masked mark values into OR-immediate setter chains. Called by `mwan3_set_general_nft()`. |
| `mwan3_all_marks` | Enumerates every mark value that needs to appear in the restore/save vmaps: all per-interface marks (IDs 1..`MWAN3_INTERFACE_MAX` bit-spread through `MMX_MASK`) plus `MMX_DEFAULT`, `MMX_BLACKHOLE`, and `MMX_UNREACHABLE`. Echoes a space-separated list. Used by `mwan3_set_general_nft()` to build the vmap body. |
| `mwan3_init` | Loads UCI config, creates status dirs, computes all mask constants (`MMX_MASK`, `MMX_DEFAULT`, `MMX_BLACKHOLE`, `MMX_UNREACHABLE`, `MMX_MASK_COMPLEMENT`, `MWAN3_INTERFACE_MAX`), and reads `iif_rule_base`, `fwmark_rule_base`, `unreachable_rule_base` from UCI globals into `MWAN3_IIF_RULE_BASE`, `MWAN3_FWMARK_RULE_BASE`, `MWAN3_UNREACHABLE_RULE_BASE`, reverting all three to defaults (1000/2000/3000) if either ordering constraint is violated. |
| `mwan3_id2mask id mask` | Bit-spreads `id`'s bits into positions where `mask` has 1-bits. Arguments are variable names (indirect evaluation). |
| `mwan3_count_one_bits var` | Counts 1-bits in the value named by `var` (indirect evaluation). Uses `n&(n-1)` trick. |
| `mwan3_get_true_iface out_var iface` | Resolves virtual interface names (appends _4 or _6 suffix if that interface exists in netifd). |
| `mwan3_get_src_ip out_var iface` | Gets the source IP for an interface, with fallbacks for IPv6-PD prefixes. |
| `readfile var path` | Reads entire file into variable. Returns 1 if file doesn't exist. |
| `mwan3_get_mwan3track_status out_var iface` | Returns tracker status: `disabled`, `down`, `paused`, or `active`. |
| `get_uptime [out_var]` | Returns system uptime in seconds (integer). |
| `get_online_time out_var iface` | Returns how long the interface has been online. |

### 7.2 Set Management Functions

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

### 7.3 General Rule Setup

| Function | Purpose |
|---|---|
| `mwan3_set_general_rules` | Adds `ip rule` entries for blackhole and unreachable marks (both IPv4 and IPv6) at priorities `MWAN3_FWMARK_RULE_BASE + MM_BLACKHOLE` and `MWAN3_FWMARK_RULE_BASE + MM_UNREACHABLE`. These are ip policy rules, not nftables rules. |
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
7. **Atomic connmark save** (always): `meta mark & MMX_MASK vmap { ... -> jump mwan3_or_ct_<imm> }` dispatches into setter chains that clear mwan3's bits and set the new value in a single nft expression (`ct mark set ct mark & MMX_MASK_COMPLEMENT | <imm>`). No intermediate state is visible to other CPUs. Bits in ct mark owned by other packages survive unchanged.
8. Post-rules: jump to custom/connected/dynamic again for non-default marks

See [§2 Connmark Operations](#connmark-operations) for the rationale and the kernel-limitation context.

### 7.4 Interface Management

| Function | Purpose |
|---|---|
| `mwan3_update_iface_to_table` | Populates `mwan3_iface_tbl`: a space-separated string of `name=id` pairs for all configured interfaces, where `id` is the sequential table number. Called lazily (on first use) by `mwan3_get_iface_id()`. Also called explicitly during `start_service()` to prime the cache before interface chains are created. |
| `mwan3_get_iface_id out_var iface` | Looks up `mwan3_iface_tbl` for the given interface name and writes its table ID into the named output variable. Calls `mwan3_update_iface_to_table()` on first use if the cache is empty. |
| `mwan3_create_iface_nft iface device` | Creates (or flushes) `mwan3_iface_in_<iface>` chain. Adds rules matching on `iifname` and address family: source in connected/custom/dynamic → MMX_DEFAULT; otherwise → interface mark. Adds jump from `mwan3_ifaces_in` if not already present. Also installs a per-interface `mwan3_postrouting` SNAT rule for IPv6 interfaces when the `snat6` UCI option is set. Stale `mwan3_snat_<iface>`-tagged rules from a prior incarnation are removed first. See [§4](#router-originated-traffic-and-source-address-rewriting). |
| `mwan3_rebuild_iface_nft iface` | Rebuilds a single interface's nft chain if the interface is enabled, the correct family is available, and the interface is currently up (verified via ubus). Used during `reload_service` to rebuild all interface chains within the atomic batch. Calls `mwan3_create_iface_nft()` after resolving the L3 device from netifd. |
| `mwan3_delete_iface_nft iface` | Removes the jump rule from `mwan3_ifaces_in` (by handle lookup), removes any `mwan3_snat_<iface>`-tagged rules from `mwan3_postrouting` (comment-tag match), then flushes and deletes the interface chain. |
| `mwan3_delete_iface_map_entries iface` | Iterates all `mwan3_sticky_v[46]_*` sets in the `inet` family, finds sets whose name ends with `_<id>` (this interface's id), and flushes them. Sets are flushed rather than deleted because rule chains may still reference the set name. |
| `mwan3_create_iface_rules iface device` | Adds `ip rule` entries: pref `id+MWAN3_IIF_RULE_BASE` (iif lookup), pref `id+MWAN3_FWMARK_RULE_BASE` (fwmark lookup), pref `id+MWAN3_UNREACHABLE_RULE_BASE` (fwmark unreachable). |
| `mwan3_delete_iface_rules iface` | Removes ip rules for this interface (both IPv4 and IPv6) by delegating to `mwan3-manage-rules.uc delete-iface`. The ucode script locates the iif lookup rule, fwmark lookup rule, and unreachable rule by priority offset and table ID, and deletes each via RTM_DELRULE. Handles rule-base changes and `mmx_mask` changes transparently. |
| `mwan3_create_iface_route iface` | Copies routes from the main routing table (and any `rt_table_lookup` extra tables) into the per-interface routing table by invoking `mwan3-create-iface-route.uc`. The ucode script reads source routes via rtnl, skips routes already present in the target table, and writes each qualifying route with RTM_NEWROUTE. Passes the `source_routing` UCI flag to control whether source addresses are copied. |
| `mwan3_delete_iface_route iface` | Flushes the per-interface routing table. *Unchanged.* |

#### Handle-Based Rule Deletion

nftables doesn't support deleting rules by match criteria (like iptables `-D chain match...`). Instead, `mwan3_delete_iface_nft()` uses:

```sh
handle=$($NFT -a list chain inet mwan3 mwan3_ifaces_in | \
    grep "jump mwan3_iface_in_$1" | sed -n 's/.*# handle \([0-9]*\)/\1/p')
$NFT delete rule inet mwan3 mwan3_ifaces_in handle "$handle"
```

The `-a` flag shows rule handles in comments, which can then be used for targeted deletion.

### 7.5 Policy & Load Balancing

| Function | Purpose |
|---|---|
| `mwan3_set_policy member_config` | Callback per policy member. Tracks lowest metric and accumulates online members as `iface:id:weight` tuples into `$policy_members`. Tracks offline devices into `$policy_offline_devices`. Uses caller's variables (dynamic scoping). |
| `mwan3_create_policies_nft policy` | Creates/flushes the `mwan3_policy_<name>` chain. Iterates members via `mwan3_set_policy`, then builds the chain: single member gets a direct mark-set rule; multiple members get a `numgen` rule; offline devices get out-device fallback rules; last-resort rule (unreachable/blackhole/default) is appended. |
| `mwan3_set_policies_nft` | Before creating policy chains, enumerates all existing `mwan3_policy_*` chains in `inet mwan3` and deletes any whose name is not in the current UCI policy config (orphaned chain sweep). Then iterates all policy configs and calls `mwan3_create_policies_nft` for each. |

### 7.6 Sticky Routing

| Function | Purpose |
|---|---|
| `mwan3_get_policy_members_for_family policy family` | Iterates the members of a policy config via `config_list_foreach`. For each member whose interface matches the requested family, resolves the interface id and computes its mark, and accumulates `<id>:<mark>` tuples into `$_policy_member_marks`. Used by the sticky path in `mwan3_set_user_nft_rule()` to enumerate per-member sets. |

### 7.7 User Rules

| Function | Purpose |
|---|---|
| `mwan3_set_user_nft_rule rule ipv` | Builds and adds a single nft rule to `mwan3_rules`. Translates UCI config options (proto, src_ip, dest_ip, src_port, dest_port, src_iface, ipset, ipset_src) into nft match expressions. For sticky rules, calls `mwan3_get_policy_members_for_family()` and builds a `mwan3_rule_<name>` chain with per-member address sets and OR-immediate restore/save (see §8). Handles logging rules. Pre-creates missing nft sets (e.g., dnsmasq nftsets that haven't started yet) to prevent batch failures. When `family` is explicitly `ipv4` or `ipv6` but none of `src_ip`, `dest_ip`, `ipset`, or `ipset_src` are set, prepends `meta nfproto ipv4/ipv6` to the nft match to prevent a bare rule from matching both address families. Also translates `proto icmp` to `meta l4proto ipv6-icmp` when `family` is `ipv6` (in an inet table, proto 1 is ICMPv4 only). `src_ip` and `dest_ip` are validated via `mwan3ipcheck`; a result of `"invalid"` or `"mixed"` causes the rule to be skipped with a warning log. When a comma is present in `src_ip` or `dest_ip`, the value is wrapped in nft anonymous set syntax (`{ addr1, addr2 }`) for the generated match expression. |
| `mwan3_set_user_rules` | Flushes `mwan3_rules` chain, then iterates all rule configs for both ipv4 and ipv6, calling `mwan3_set_user_nft_rule` for each. Uses a single batch. |
| `mwan3_set_user_iface_rules iface device` | Called on ifup to check if the rules chain needs rebuilding (if this interface is a `src_iface` in any rule). |

#### UCI-to-nft Match Translation

| UCI Option | nft Expression |
|---|---|
| `proto tcp` | `meta l4proto tcp` |
| `src_ip 10.0.0.0/8` | `ip saddr 10.0.0.0/8` (or `ip6 saddr`) |
| `src_ip 10.0.0.1,10.0.0.2` | `ip saddr { 10.0.0.1, 10.0.0.2 }` |
| `dest_ip 1.2.3.4` | `ip daddr 1.2.3.4` |
| `dest_ip 1.2.3.4,5.6.7.8` | `ip daddr { 1.2.3.4, 5.6.7.8 }` |
| `src_iface lan` | `iifname "br-lan"` |
| `src_port 80,443` | `th sport { 80, 443 }` |
| `dest_port 8080` | `th dport { 8080 }` |
| `ipset my_set` | `ip daddr @my_set` |
| `ipset_src my_set` | `ip saddr @my_set` |
| `use_policy balanced` | `jump mwan3_policy_balanced` |
| `use_policy default` | `meta mark set ... \| MMX_DEFAULT` |

#### Missing nft Set Pre-creation

When a user rule references an `ipset` (destination nft set) or `ipset_src` (source nft set) that doesn't exist yet in `table inet mwan3`, `nft -f` would roll back the entire batch atomically. To prevent this, `mwan3_set_user_nft_rule()` pre-creates any missing referenced sets with the appropriate type. The same logic applies to both `ipset` and `ipset_src`.

### 7.8 User-defined nft Set Management

| Function | Purpose |
|---|---|
| `mwan3_render_config_ipsets` | Iterates all `config ipset` UCI sections and calls `_mwan3_render_one_ipset` for each. Creates user-defined sets in `table inet mwan3`. Called from `start_service` and `reload_service`. |
| `_mwan3_nft_time_to_sec str` | Converts an nft human-unit timeout string (e.g. `1h`, `5m`, `300s`) to an integer number of seconds. Recognised suffixes: `d` (days), `h` (hours), `m` (minutes), `s` (seconds, default if no suffix). Used by `_mwan3_ipset_needs_delete` to compare the live kernel timeout against the desired spec in a common unit. |
| `_mwan3_ipset_needs_delete name type counter timeout maxelem` | Returns 0 (true) if the named set exists in `table inet mwan3` AND its flags (type, counter, timeout, size) differ from the desired spec; returns 1 if the set is absent or all flags match. Called by `_mwan3_render_one_ipset` during reload to decide whether to queue a `delete set` before recreating the set with new flags. Timeout values are compared in seconds after converting nft's human-unit display (e.g. `1h`, `5m`) via `_mwan3_nft_time_to_sec`. |
| `_mwan3_render_one_ipset name` | Creates one user-defined nft set. Builds a `type ipv4_addr/ipv6_addr; flags interval; auto-merge;` declaration, optionally appending `counter;` (standalone statement, NOT a flag keyword) and `timeout Ns;`. On the start path, unconditionally deletes any existing set before creating. On the reload path, calls `_mwan3_ipset_needs_delete` and only queues a `delete set` when flags differ; otherwise `add set` is idempotent and dnsmasq-populated elements survive. Sets `MWAN3_NEED_DNSMASQ_HUP` if a domain-populated set is deleted. Adds inline `list entry` elements and `loadfile` contents. |
| `mwan3_write_dnsmasq_fragments` | For each `config ipset` with `list domain` entries, writes a dnsmasq confdir fragment enabling `nftset=/domain/FAMILY#inet#mwan3#setname`. Compares against previously written fragments; restarts dnsmasq only when content changes. Silently does nothing if no domain sets are configured. |
| `mwan3_cleanup_orphaned_ipsets` | Queries `nft list table inet mwan3` for user-defined sets (those not prefixed `mwan3_`), compares against configured set names, and pushes `delete set` for any orphans. Called in `reload_service` after `mwan3_render_config_ipsets`. Prevents stale sets accumulating when a set is removed from UCI config. |

### 7.9 Status Reporting

| Function | Purpose |
|---|---|
| `mwan3_report_iface_status iface` | Shows interface online/offline status with uptime. Checks ip rules, nft chain existence in `table inet mwan3`, and default route presence. |
| `_mwan3_report_policies_for_family family` | Calls ubus `mwan3 status` for the policies section, then iterates the policy/member hierarchy for the given family (`ipv4` or `ipv6`), printing each policy name with its member interfaces and current traffic percentages. Called by `mwan3_report_policies_v4()` and `mwan3_report_policies_v6()`. |
| `mwan3_report_policies_v4/v6` | Delegates to `_mwan3_report_policies_for_family()` for IPv4 and IPv6 respectively. |
| `_mwan3_report_connected_set set_name` | Parses the named connected set using `nft -j list set inet mwan3 <set_name>` and `jshn.sh`. Iterates the JSON element array and prints prefix elements as `addr/len` and range elements as `start-end`. Handles both address families. Called by `mwan3_report_connected_v4()` and `mwan3_report_connected_v6()`. |
| `mwan3_report_connected_v4/v6` | Thin wrappers that call `_mwan3_report_connected_set` with `mwan3_connected_v4` and `mwan3_connected_v6` respectively. `mwan3_report_connected_v6` returns early if `$NO_IPV6` is set. |
| `mwan3_report_rules_v4/v6` | Parses `nft list chain inet mwan3 mwan3_rules`. |
| `mwan3_mark_to_name mark` | Resolves a numeric mark value to an interface name (or "default"/"blackhole"/"unreachable"). |

### 7.10 Lifecycle & Hotplug

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
| `mwan3_flush_unreplied_conntrack` | Flushes all mwan3-marked conntrack entries that have never received a reply (`IPS_SEEN_REPLY` not set). Called after `mwan3_set_policies_nft` on the `connected` action and on `ifup` when `status=online`. Breaks the cycle where a stale mark from a previous policy state pins traffic to the wrong WAN: because no reply arrives the application keeps retrying, refreshing the conntrack timeout indefinitely. Flushing only UNREPLIED entries leaves established connections untouched. |

---

## 8. Load Balancing with numgen

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

## 9. Sticky Routing Detail

Sticky routing ensures that repeat connections from the same source IP use the same WAN interface (important for HTTPS sessions, banking sites, etc.). The iptables version used `ipset hash:ip,mark` sets. The nftables version uses per-member **address sets** with OR-immediate vmap dispatch for non-destructive mark restore.

### Why Per-Member Sets Instead of a Single Map

With the vmap-dispatch infrastructure, the correct approach is a plain address set per policy member, with the mark encoded in the chain name rather than the map value. The corresponding `mwan3_or_meta_<mark>` setter chain ORs only the mwan3 bits into meta mark, preserving everything else.

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

## 10. Service Lifecycle and Conntrack Management

### 10.1 Start

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

### 10.2 Reload

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

### 10.3 Interface Up (hotplug)

```
netifd signals ifup for $INTERFACE
  +--> 25-mwan3 hotplug script
       +--> mwan3_update_peer_track_ip()                write gateway IP (if track_gateway)
       +--> mwan3_create_iface_nft()                    create/flush chain, add rules
       +--> mwan3_create_iface_rules()                  ip rule add (iif, fwmark, unreachable)
       +--> mwan3_create_iface_route()                  copy routes to per-iface table
       +--> mwan3_set_iface_hotplug_state "online/offline"
       +--> [if not init startup:]
       |    +--> mwan3_set_general_rules()              ensure ip rules exist
       |    +--> [if online:] mwan3_set_policies_nft()  rebuild policy chains
       |                      mwan3_flush_unreplied_conntrack()  flush UNREPLIED entries
       +--> procd_send_signal track_$INTERFACE USR2
```

```
netifd signals connected for $INTERFACE
  +--> 25-mwan3 hotplug script
       +--> mwan3_set_iface_hotplug_state "online"
       +--> mwan3_create_iface_nft()                    flush chain, update rules
       +--> mwan3_set_policies_nft()                    rebuild policy chains
       +--> mwan3_flush_unreplied_conntrack()            flush UNREPLIED entries
```

The `connected` event fires when an interface completes its link-layer negotiation (e.g., PPPoE authentication) after the `ifup` routing state is already in place. It skips rule and route creation (those are done on `ifup`) and goes straight to policy rebuild and the unreplied flush.

#### Automatic Gateway Tracking (`track_gateway`)

When `option track_gateway '1'` is set on a `config interface` section, mwan3 automatically discovers the point-to-point peer/gateway IP and adds it to the tracking list at runtime. This is useful for PPPoE and other point-to-point links where the next-hop gateway IP changes on each connection and is not known in advance. Without this option, users must manually configure static `track_ip` addresses (typically public DNS servers) that may not test the actual link peer.

`mwan3_update_peer_track_ip()` queries `ifstatus` for the interface's `ptpaddress` field (the point-to-point peer IP). If found, the gateway IP is written to `$MWAN3TRACK_STATUS_DIR/<iface>/GATEWAY`. `mwan3track` reads this file and prepends the gateway IP to the front of the probe list, ensuring it is always probed first on every round regardless of the `reliability` threshold; static `track_ip` entries follow after the gateway. On interface bounce, the hotplug `ifup` action calls `mwan3_update_peer_track_ip()` again, overwriting the state file with the new peer IP.

The gateway IP is stored as ephemeral state rather than committed to UCI, preventing stale IP accumulation across reboots or gateway changes. An interface definition may specify only `track_gateway` and omit static tracking IPs entirely. The option is silently ignored if no next-hop peer address is found (e.g., on Ethernet WAN interfaces).

> [!WARNING]
> **IPv4 only in practice.** For IPv6 point-to-point links, the peer is typically a link-local address (e.g., `fe80::1`). Pinging link-local addresses requires interface scope specification (`ping6 fe80::1%pppoe-wan`), which mwan3track's probe mechanism does not handle. The option will be silently ignored if no peer address is found.

**UCI Configuration:**

```
config interface 'wan'
    option enabled '1'
    option track_gateway '1'
    # track_ip entries are optional when track_gateway is used
    # list track_ip '8.8.8.8'
```

The corresponding LuCI control is the "Track gateway" checkbox in the Interface tab (see [Section 15.1.2](#1512-interface)).

### 10.4 Interface Down (hotplug)

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

### 10.5 Stop

```
/etc/init.d/mwan3 stop
  +--> service_running || exit 0
  +--> mwan3_interface_shutdown per interface   trigger ifdown hotplug
  +--> flush ip routing tables (1..MWAN3_INTERFACE_MAX)
  +--> delete ip rules in configured ranges
  +--> flush ALL mwan3_* chains (rules removed, skeleton chains kept)
  +--> delete dynamic chains (iface_in_*, policy_*, etc.)
  +--> final safety flush of skeleton chains
  +--> flush ALL mwan3_* sets; flush and delete sticky maps
  +--> $NFT delete table inet mwan3   (complete removal)
  +--> rm -rf status dirs

Result: table inet mwan3 no longer exists. Clean slate.
```

### 10.6 Conntrack Management

mwan3 uses the Linux connection tracking table (conntrack) to persist routing decisions across the packets of a single connection. On the first packet of a new flow, mwan3 stamps the packet with an interface fwmark and saves that mark into the conntrack entry's ct mark field. All subsequent packets in the same connection restore the ct mark back to the packet mark at the start of the prerouting/output chain, bypassing policy re-evaluation entirely. This means that routing policy changes do not take effect for established connections until their conntrack entries are removed.

**What mwan3 does not do** is often as important as what it does:

- **Stop** performs no conntrack flush. All conntrack entries survive `mwan3 stop` intact. The marks are inert while the service is down since the nft table no longer exists to restore them. On restart with an unchanged config, interface IDs are assigned in the same order, so the saved marks remain valid and established connections survive the stop+start cycle without disruption. Flushing on stop would destroy that benefit for no practical gain.

- **Reload** also performs no conntrack flush. Existing connections keep their saved ct marks and continue routing via whatever interface they were assigned at classification time. New connections are classified immediately under the new rules. This is intentional: a conntrack flush on every UCI commit would disrupt all active connections. The tradeoff is that existing flows are not rerouted when policy rules change. If that behaviour is needed, a stop followed by start (which does flush; see below) is required.

**Conntrack actions mwan3 does take:**

**1. Start - zero-mark flush (`mwan3_flush_stale_conntrack`)**

At the end of `start_service`, after all nft rules are in place, mwan3 runs:

```
mwan3ct flush --mark 0x0/$MMX_MASK
```

This removes every conntrack entry whose mwan3 mark bits are all zero. The target is entries created during the mwan3 startup window: the skeleton loads the hook chains immediately, making them live, but those chains are empty until `mwan3_set_general_nft` populates them at the end of the start sequence. Connections established during that window pass through prerouting with no classification rules present and are recorded in conntrack with ct mark=0. WireGuard's PersistentKeepalive refreshes the entry every 25 seconds, so without this flush the entry can survive indefinitely, causing the traffic to miss the mwan3 mark restore and fall through to the main routing table.

Only zero-mark entries are removed. Correctly-marked active connections are untouched.

**2. Start - flow offloading flush**

If software flow offloading is enabled (`uci get firewall.@defaults[0].flow_offloading` is `1`), mwan3 flushes the entire conntrack table immediately after the zero-mark flush:

```
echo f > /proc/net/nf_conntrack
```

When flow offloading is active, the kernel fast-paths established flows directly through the flowtable, bypassing nftables entirely. Any flow that was offloaded before mwan3 started will never see the mwan3 prerouting chain and will never get a mark. Flushing everything forces all connections to re-enter the nftables pipeline and be classified correctly.

This does not apply to hardware flow offloading, which uses different kernel mechanisms and is not affected by writing to `/proc/net/nf_conntrack`.

**3. Interface down - selective flush (`mwan3_flush_conntrack`)**

Immediately after `mwan3_set_policies_nft` rebuilds the policies for a failing interface, the hotplug script calls `mwan3_flush_conntrack`. This function has two independent paths that both run on `ifdown`:

First, the UCI `flush_conntrack` path: if the per-interface `flush_conntrack` UCI option contains `ifdown`, mwan3 writes `f` to `/proc/net/nf_conntrack`, flushing the entire global conntrack table. This is the legacy behaviour, retained for users who need it. Because it disrupts all connections on all interfaces simultaneously, it is not set by default.

Second, the selective flush path, which always runs on `ifdown` regardless of the UCI option:

```
mwan3ct flush --mark <iface_mark>/$MMX_MASK
```

This removes only the conntrack entries that belong to the failing interface (those whose masked mark bits equal that interface's assigned fwmark). The effect is that TCP and UDP flows that were using the failed WAN immediately re-establish under the new failover policy rather than waiting out a TCP retransmit timeout (typically 15-30 seconds). Connections on healthy interfaces are completely undisturbed.

**4. Interface up - UCI flush only**

On `ifup` the `mwan3_flush_conntrack` function runs the same UCI `flush_conntrack` check: if the option contains `ifup`, the entire conntrack table is flushed. New connections will be classified correctly by the rebuilt chains; existing connections that survived will re-use their stored ct marks as before.

**5. Interface online - unreplied flush (`mwan3_flush_unreplied_conntrack`)**

When an interface transitions to online - either via the `connected` action (mwan3track declares the interface online) or via `ifup` when `status=online` (interface comes up with `initial_state` set to online) - mwan3 runs:

```
mwan3ct flush --mark-any $MMX_MASK --status 0/0x2
```

This removes all mwan3-marked conntrack entries that have never received a reply (`IPS_SEEN_REPLY` not set). These UNREPLIED entries can result from a race during startup or policy rebuild where a flow gets classified before the nft chains reflect the current state. The stale mark pins traffic to the wrong WAN; because no reply arrives the application keeps retrying, refreshing the conntrack timeout indefinitely. Flushing only UNREPLIED entries is non-disruptive to established connections. The next packet from the affected application creates a fresh conntrack entry that is classified under the current policy. This flush is not performed during init - the zero-mark flush in `start_service` handles the startup window.

**Summary table**

| Event | Selective (per-iface) flush | Unreplied flush | Global flush | Zero-mark flush |
|---|---|---|---|---|
| `start` | - | - | if flow_offloading | yes (always) |
| `reload` | - | - | - | - |
| `ifdown` | yes (always) | - | if `flush_conntrack` includes `ifdown` | - |
| `ifup` | - | if `status=online` | if `flush_conntrack` includes `ifup` | - |
| `connected` | - | yes (always) | - | - |
| `stop` | - | - | - | - |

**Implications for users**

Changing mwan3 policy (via `reload`) does not reroute existing TCP connections. If a load-balance rule changes from 50/50 to 80/20, existing flows continue on whatever interface they were originally assigned. This is usually the right behaviour - rerouting mid-session would break most protocols - but means the new distribution only takes effect as connections naturally expire and re-establish.

The selective ifdown flush is the most operationally important flush. Its effect depends on the protocol.

For UDP-based protocols that identify connections by something other than the IP 4-tuple - WireGuard being the primary example - the flush allows transparent failover. WireGuard authenticates peers by cryptographic identity rather than source address. When the conntrack entry is removed and the next keepalive is reclassified via the failover WAN, the packet arrives at the remote peer from a new source IP, the peer authenticates it by key, updates its roaming endpoint, and the tunnel continues without interruption.

For TCP connections - file downloads, SSH sessions, browser connections - the picture is different. TCP identifies connections by the 4-tuple including source IP. When packets exit via the failover WAN, masquerade applies the new WAN's IP, and the remote end has no connection matching that source. It sends RST and the connection terminates. The connection was already dead the moment the WAN failed; what the flush controls is how quickly the application finds out. Without the flush, packets are silently blackholed (the old interface's ip rule no longer exists) and the application hangs in retransmit limbo until the TCP timeout expires - potentially minutes. With the flush, the RST arrives immediately and the application can reconnect at once.

The zero-mark flush on start is defensive infrastructure against a corner case that most users never notice explicitly. Its absence manifests as a WireGuard tunnel that routes through the wrong interface after a reboot, or a DNAT connection that falls to the main routing table immediately after mwan3 restarts following an fw4 reload.

**Custom behaviour via mwan3.user**

The default conntrack management fits most deployments. Three cases where additional action on interface recovery may be useful or desirable for some are:

- **Load-balanced configurations:** when a failed WAN recovers, the automatic ifdown flush has already cleared entries for the failed interface, but all surviving flows remain pinned to the WANs that carried the load during the outage. They will not redistribute until they expire naturally.

- **Failover with a preferred primary:** when the primary WAN recovers, existing connections stay on the failover WAN until natural expiry rather than snapping back. In cost-sensitive setups where the primary is cheaper or unmetered, lingering on the failover WAN has a direct cost.

- **Application of new policies / rules to *all* flows immediately:** a config save will cause all *new* connections be be immediately routed according to the new policy / ruleset, but will leave existing connections intact rather than interrupting them. Users can choose to override that behaviour and make the new policy take effect immediately even for existing connections, but at the cost of interrupting connections such as SSH, file downloads, etc.

In both cases, flushing all mwan3-marked conntrack entries on `ifup` causes connections to be reclassified immediately and routed according to the current policy:

```sh
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0

. /lib/functions.sh
. /lib/mwan3/common.sh
. /lib/mwan3/mwan3.sh
config_load mwan3
mwan3_init
mwan3_flush_marked_conntrack
```

Note that the flush is broader than strictly necessary, although it's still a lot less of a hammer than `conntrack -F`. Since the recovering interface has no conntrack entries (they were removed on ifdown), the flush affects connections on all other interfaces, including any that were healthy throughout the outage. There is no way to target only those connections that moved as a result of the failure. The trade-off is that every connection is briefly interrupted on any interface recovery event. For most TCP connections the interruption is imperceptible; long-lived sessions such as SSH or active file transfers will be reset.

For this reason, default behaviour is not to flush all marked conntrack entries but to allow this action to fall-back on a per-installation level to `mwan3.user` through use of the `mwan3_flush_marked_conntrack` supplied expressly for this purpose.

---

## 11. Atomic Non-destructive Reload

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

## 12. User-defined nft Sets

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

### Rule Integration (`ipset` and `ipset_src`)

The `ipset` UCI option on a rule section matches the destination address against a named nft set. The `ipset_src` option provides the complementary source address match. Both can be set on the same rule and are ANDed together.

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

If the named set does not yet exist in `table inet mwan3` at rule-install time, `mwan3_set_user_nft_rule()` pre-creates it with the appropriate type to prevent the nft batch from failing atomically. A present `ipset_src` is treated as an implicit family qualifier by the `meta nfproto` guard condition in `mwan3_set_user_nft_rule()`, consistent with `src_ip`, `dest_ip`, and `ipset`.

---

## 13. Unchanged Files

| File | Reason |
|---|---|
| `etc/hotplug.d/iface/26-mwan3-user` | Just calls `/etc/mwan3.user`, no firewall code |
| `etc/mwan3.user` | User script template, no firewall code |
| `etc/uci-defaults/mwan3-migrate-flush_conntrack` | UCI migration, no firewall code |

---

## 14. Diagnostic Commands

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

## 15. luci-app-mwan3

`luci-app-mwan3` is the LuCI web interface for mwan3, installed as a separate package from the core mwan3 daemon. It is organised into two menu groups: **Network > MultiWAN Manager** for configuration and **Status > MultiWAN Manager** for runtime monitoring and diagnostics.

### 15.1 Network App

The Network app provides tabs for configuring every aspect of mwan3: global parameters, WAN interfaces, policy members, policies, traffic rules, nftables IP sets, a traffic simulator, a static configuration analyser, and user notification scripts.

#### 15.1.1 Globals

The Globals tab (`globals.js`) edits the `config globals` UCI section.

**Mark mask (`mmx_mask`):** The hexadecimal bitmask used for policy mark operations. Determines the number of bits available for interface encoding, which sets `MWAN3_INTERFACE_MAX` (the maximum number of simultaneously active interfaces). A live computed display shows the derived interface limit as the value is changed. Default `0x3F00` (6 bits, 60 interfaces).

**Rule base priorities:** Three numeric fields set `iif_rule_base`, `fwmark_rule_base`, and `unreachable_rule_base`. Live cross-field validation enforces both ordering constraints (see [Section 5.5](#55-configurable-rule-base-priorities)) on blur; an error is shown if either constraint would be violated. When any rule base priority changes, saving and applying the form triggers `mwan3 restart` to rebuild all ip rules at the new priorities.

**Additional routing tables (`rt_table_lookup`):** A dynamic list of extra routing table IDs whose routes are merged into each per-interface routing table alongside routes from the main table.

**Bypass networks (`bypass_network`):** A dynamic list of CIDRs added to the connected-network bypass sets (`mwan3_connected_v4`/`mwan3_connected_v6`), causing traffic to those networks to skip mwan3 policy routing.

**Logging:** A checkbox to enable mwan3 logging and a numeric loglevel field (0-7 following syslog severity levels).

**Verbose logging (`verbose_logging`):** A checkbox that enables debug-level log output from mwan3 daemons. When enabled, the `LOG()` function emits debug messages to syslog from `mwan3.sh`, `common.sh`, and `mwan3track`. Takes effect on `HUP`-triggered config reloads without requiring a full restart.

#### 15.1.2 Interface

The Interface tab (`interface.js`) presents a `GridSection` where each row represents a `config interface` section in the mwan3 UCI config. Clicking a row opens the per-interface modal editor.

**Tracking configuration:** The tracking method field supports `ping` (always available), `httping`, `nping`, and `arping`. The httping, nping, and arping options are only shown if the corresponding binary is detected on the router via `fs.stat`. The `track_ip` field accepts a dynamic list of addresses or hostnames to probe. `track_method`, `reliability`, `count`, `size`, `max_ttl`, `timeout`, `interval`, `failure_interval`, `recovery_interval`, `keep_failure_interval`, `down`, and `up` thresholds are all configurable.

**Quality tracking:** The `check_quality` checkbox enables latency and loss threshold monitoring. When enabled, four additional fields appear: `failure_latency`, `failure_loss`, `recovery_latency`, and `recovery_loss`.

**Track gateway (`track_gateway`):** A checkbox shown only for IPv4 interfaces. When enabled, mwan3 automatically uses the interface's network gateway as the tracking target (see [Section 10.3](#automatic-gateway-tracking-track_gateway)).

**IPv6 SNAT (`snat6`):** A text field shown only for IPv6 interfaces. Accepts empty/`0` (disabled), `1` (SNAT to the interface's primary global address), or a literal IPv6 address for fixed-source pinning (see [Section 4](#router-originated-traffic-and-source-address-rewriting)).

**Conntrack flushing (`flush_conntrack`):** Controls whether the global conntrack table is flushed on interface state changes. Per-interface conntrack entries are flushed automatically on ifdown regardless of this setting.

**Validation:** Interface section names must be 15 characters or fewer and unique across all section types in the mwan3 config. The interface's current network metric is shown as a read-only value derived from the netifd network configuration.

#### 15.1.3 Member

The Member tab (`member.js`) presents a `GridSection` for `config member` sections. Each member has three fields: `interface` (a dropdown of currently configured mwan3 interfaces), `metric` (1-256), and `weight` (1-1000). Members are the atomic routing units referenced by policies.

An informational banner at the top of the section directs users to the Policy Builder (see [Section 15.1.4](#1514-policy)) for normal member management. The Member tab is preserved for direct inspection and manual adjustment of metric and weight values.

#### 15.1.4 Policy

The Policy tab (`policy.js`) presents a `GridSection` where each row represents a `config policy` section. The grid shows two read-only derived columns - "IPv4 Priority order" and "IPv6 Priority order" - alongside an editable `last_resort` column. The derived columns render the policy behaviour in symbolic form: a single interface name for single-interface policies; `[iface N%, iface N%, ...]` for load-balanced tiers; `[primary] --> [failover] --> ...` for failover chains.

**Policy Builder modal:** Clicking "Add..." or the edit button on an existing policy opens the policy builder. The builder presents the policy as an ordered list of tiers. Tier 1 is labelled "Primary"; subsequent tiers are labelled "Failover (N)". Each tier contains one or more interface entries, each with a family selector (IPv4/IPv6), an interface selector filtered to interfaces of the chosen family, and a percentage share field.

Shares are per-family within each tier: all IPv4 entries in a tier must sum to 100%, and similarly for IPv6. When an entry is added to a family group its share is computed by redistributing 100% equally across all entries in that family group (first entry absorbs any rounding remainder). Changing an entry's family redistributes both the old and new family groups. A single-entry family group has its share field locked at 100 and shown greyed out.

**Member management:** On save the builder computes GCD-reduced integer weights from the percentage inputs, then for each (interface, metric, weight) tuple finds an existing member section with exactly those values and reuses it (regardless of name), or creates a new section named `<iface>_m<metric>_w<weight>`. After saving, any member sections that were in the old `use_member` list but are no longer referenced by any policy become orphans. A "Delete unused member definitions" checkbox in the page header (persisted in `localStorage`) controls automatic versus prompted orphan cleanup.

**Validation:** Real-time validation reports missing or invalid policy name, name already in use, unselected interface on any entry, and family share totals that do not equal 100%. The Save button is disabled while any error is present.

#### 15.1.5 Rule

The Rule tab (`rule.js`) presents a `GridSection` where each row represents a `config rule` section. Rules are evaluated in UCI declaration order; order matters.

**Fields:** `family` (ipv4/ipv6/any), `proto` (all/tcp/udp/icmp/icmpv6/...), `src_ip`, `src_port`, `dest_ip`, `dest_port`, `fwmark`, `sticky`, `timeout`, `ipset_src` (source NFT set), `ipset` (destination NFT set), `logging`, `use_policy`, and `enabled`.

**NFT set dropdowns:** The `ipset_src` and `ipset` fields are populated from the `mwan3.nftset_info` rpcd method. Disabled sets are excluded from the dropdowns. A destination set must match the rule's selected address family; combining a set with a same-dimension IP field (`ipset` with `dest_ip`, or `ipset_src` with `src_ip`) is flagged as an error since both constrain the same traffic dimension. A cross-set family mismatch between `ipset_src` and `ipset` on the same rule is also flagged.

**Fwmark field:** The fwmark field renders as a combined `value/mask` input. On read, the stored `fwmark` and `fwmask` UCI options are combined; on write they are split back. Validation checks hex format and flags any overlap between the user mask and `MMX_MASK`.

**Column merging:** The grid merges source port into the Source column and destination port into the Destination column. The merged cell renders as `address:port` or `set_name:port` when both are set, `address` or `set_name` alone when only an address or set is present, `*:port` when only a port is set, and `-` when neither is set. `src_port` and `dest_port` are `modalonly`, remaining fully editable in the modal.

**Enable column:** An inline Enable checkbox in the grid uses `o.editable = true` for direct toggle without opening the modal. The checkbox is rendered non-interactive when the rule is disabled and references at least one currently disabled set, preventing re-enable into a broken state.

**Address family validation:** `src_ip` and `dest_ip` accept a single address or CIDR, or a comma-separated list of addresses and CIDRs. Each element in a comma-separated list is individually validated for format and family consistency. A list containing a mix of IPv4 and IPv6 elements is rejected. Family consistency between the rule and any referenced NFT set is checked on save.

#### 15.1.6 IP Sets

The IP Sets configuration tab (`ipset.js`) presents a `GridSection` for `config ipset` sections.

| Field | UCI option | Description |
|---|---|---|
| Name | `name` | Identifier referenced in rule `ipset`/`ipset_src` fields. Must start with a letter or `_`; may contain letters, digits, `_`, `.`, `-`. Names beginning with `mwan3_` are reserved. |
| Family | `family` | `ipv4` or `ipv6`. Sets the nftables element type (`ipv4_addr` or `ipv6_addr`). |
| IPs / Networks | `entry` | Static addresses or CIDR subnets. Validated against the selected family on blur. |
| Domains | `domain` | Domain names resolved by dnsmasq and added to the set at runtime. mwan3 generates corresponding `nftset=` fragments in the dnsmasq config. |
| Include File | `loadfile` | Path to a file of addresses or CIDRs (one per line, `#` comments ignored) loaded at service start. |
| Max Entries | `maxelem` | Maximum element count. Empty means no limit. |
| Timeout | `timeout` | Per-element lifetime in seconds. `0` means entries do not expire. |
| Counters | `counters` | Enables per-element packet and byte counters in the nftables set. |
| Enabled | `enabled` | Whether the set is created and populated at service start. |

Deletion of a set is blocked in the UI if any rule references the set name in its `ipset` or `ipset_src` field; the user is shown which rules reference the set. The `enabled` checkbox is rendered non-interactive when the set is referenced by at least one enabled rule, preventing the set from being disabled while a rule depends on it.

The `entry` and `loadfile` fields define the static content restored by the Reload button on the IP Sets status tab. The `domain` fields define the domains queried by the Resolve button; the Resolve button is only shown for sets that have at least one domain entry.

#### 15.1.7 Simulator

The Traffic Path Simulator (`simulator.js`) accepts source IP or hostname, destination IP or hostname, fwmark (hex), protocol, source port, destination port, and address family, then reports which mwan3 rule would match and which policy would handle that traffic.

**Hostname resolution:** If a hostname is entered in either IP field, the simulator calls `mwan3.resolve_host` before running the simulation. This invokes `busybox nslookup` against 127.0.0.1, which has the side effect of populating any dnsmasq nftset entries configured for that domain. Resolved addresses are shown inline below the field. If resolution fails or returns no addresses for the selected family the simulation is aborted with an error message. When family is "IPv4 and IPv6", IPv4 addresses are preferred. Strings that are not valid IP addresses and do not resemble a valid hostname are rejected before simulation. IP address inputs are validated before the simulation runs; malformed addresses are rejected.

**Port fields:** Source and destination port fields are shown only when the protocol is set to TCP or UDP. All fields except protocol are optional; a blank field means "any" and rules with a constraint on that field will not match. The fwmark field accepts a hex value and is matched against rules that have an `fwmark`/`fwmask` constraint; a blank fwmark is treated as `0x0` (unmarked packet).

**Simulation logic:** On each simulate press, UCI configuration, live policy state, and the connected-network sets (`mwan3_connected_v4`/`mwan3_connected_v6`) are reloaded fresh. The simulator first checks whether the destination falls in a directly-connected network and, if so, reports that mwan3 rules are bypassed. Otherwise it evaluates each enabled UCI rule in declaration order, fetching live nftset membership via `mwan3.nftset_members` for any sets referenced by those rules. Elements in counter-enabled sets are correctly unwrapped from the `{"elem":{"val":"...","counter":{...}}}` JSON structure used by nft. The first matching rule is the result; any additional rules that also match are listed as shadowed rules.

#### 15.1.8 Configuration

The Configuration tab (`configuration.js`) performs a static analysis of the mwan3 UCI configuration with no live system state consulted. It loads the current UCI config, builds lookup tables for interfaces, members, policies, and rules, then reports issues at two severity levels: **error** (a broken reference or empty policy that will cause traffic to be silently misrouted or blackholed) and **warning** (an orphaned object that is defined but has no effect).

**Checks performed:**

- Member references an undefined interface
- Member is defined but not used by any policy
- Policy has no members
- Policy references an undefined member
- Policy has multiple members that all reference the same interface (no real redundancy; failover will not occur if that interface goes down)
- Policy is defined but not used by any rule
- Rule references an undefined policy
- Rule is shadowed by an earlier rule (the earlier rule matches a superset of the later rule's traffic, so the later rule is unreachable)
- Interface is defined but not referenced by any member

**Rule shadowing check:** `ruleAContainsB()` determines whether rule A (earlier) is a superset of rule B (later). The check is deliberately conservative: it only flags clear containment. CIDR containment is computed precisely for both IPv4 (32-bit unsigned arithmetic) and IPv6 (BigInt). Port specs use conservative matching: a rule with no port restriction contains any other; two rules with non-empty port specs are only flagged as contained when the specs are identical strings. When both rules reference an NFT set, the set names are compared: if both rules reference the same nftset the shadowing check proceeds normally; if the set names differ the check is skipped conservatively since set membership cannot be evaluated statically. If only one rule uses a set the check is also skipped. Address family is respected: an IPv4-only rule does not shadow an IPv6-only rule.

#### 15.1.9 Notify

The Notify tab (`notify.js`) provides a raw textarea editor for `/etc/mwan3.user`. This file is sourced by the mwan3 hotplug handler at the end of interface up/down events, allowing site-specific shell commands to run in response to WAN state changes. The tab reads the file via `fs.read` on load and writes it back via `fs.write` on save; no UCI is involved.

### 15.2 Status App

The Status app provides live monitoring and diagnostic tools. All tabs that show runtime data poll automatically via the LuCI poll mechanism.

#### 15.2.1 Overview

The Overview tab (`overview.js`) polls `mwan3.status` and displays a three-section summary of all mwan3 interface states, active policies, and configured rules.

**Interfaces section:** A CSS grid (`repeat(auto-fill, 13em)`) of per-interface status cards. Each card has a coloured border (green/red/orange/grey by status) and shows the interface name, status label, and uptime or online/offline duration. Duration is rendered without seconds by `formatDuration()` (days, hours, minutes) to keep the display stable under polling.

**Policies section:** A CSS grid of per-policy cards in the same bordered card style. Each card lists its member interfaces with live traffic share percentages. Member lines use `white-space: nowrap`. A member's line is coloured green when its share is nonzero, yellow when it is online but carrying zero percent (standby or failover member not currently active), and grey when offline.

**Rules section:** A table of enabled rules. The Match column summarises the rule in compact `addr:port` format by `fmtAddr()`: `address:port` when both are set, `address` alone, `*:port` for port-only, or `(all traffic)` for unconstrained rules. Both source (`ipset_src`) and destination (`ipset`) NFT sets are shown where configured.

#### 15.2.2 Interface Status

The Interface Status tab (`detail.js`) provides per-interface tracking detail, live-polled from `mwan3.status`. An interface selector at the top of the page drives the display.

For the selected interface, the tab shows a header card with status, tracking method, and composite reliability score, followed by a table of individual tracking targets. Each row shows the target address, probe status (up/down/skipped), current latency, and current loss percentage. When `check_quality` is disabled, the latency and loss columns show "Not enabled". Down targets show an infinity symbol for latency. Rows are sorted: up targets first, then down, then skipped.

#### 15.2.3 Routing Health

The Routing Health tab (`routing.js`) polls `mwan3.routing_health` and performs a live sanity check of the ip rules and routing tables mwan3 maintains for each configured interface.

**Per-interface cards:** Each card shows the interface name, sequential index, and mwan3track-reported status, followed by four status rows:

- **IP rule (iif)** at priority `iif_base + index`: expected present when the interface is online.
- **IP rule (fwmark)** at priority `fwmark_base + index`: expected present when the interface is online.
- **IP rule (unreachable)** at priority `unreachable_base + index`: expected present when the interface is online.
- **Routing table** (table ID = index): whether the per-interface routing table has a default route.

Each row renders a status badge: "Present" (green) or "Missing" (red) when the item is expected to be present (interface online); "Present (unexpected)" (yellow) or "Absent" (grey) when expected to be absent (interface offline); neutral grey "Present"/"Absent" for unknown or disabled interfaces. The card border is green when all four items are in the expected state, yellow for partial state, red when the interface is online and items are missing, and grey for offline or disabled interfaces in the expected state.

**Summary card:** A single line at the top reports total healthy, degraded, and failing interface counts, plus stale rule count if any.

**Stale rules:** ip rules whose priority falls within the mwan3 priority ranges but do not correspond to any currently configured UCI interface are listed in a separate table. Stale rules indicate that mwan3 was not cleanly shut down after an interface was removed from the configuration.

**Field guide:** A reference panel at the bottom explains each field (Index, iif rule, fwmark rule, unreachable rule) in plain language, using the actual configured base priority values read from the `routing_health` response rather than hardcoded defaults.

#### 15.2.4 IP Sets (Status)

The IP Sets status tab (`ipsets.js`) displays runtime information about all user-defined sets currently present in `table inet mwan3`. At page load it calls `mwan3.nftset_info` to enumerate sets and their metadata, then renders each as a collapsible panel.

**Panel header:** Shows the set name, family, element count (with `N+` suffix when the display is truncated), a Counters badge when per-element counters are enabled, and action buttons: Resolve (only for sets with at least one `domain` entry), Reload, Flush, and Expand/Collapse.

**Panel body:** Shows UCI metadata (static entry count, domain count, loadfile name, maxelem, timeout), the list of configured domain names, and a table of current set members. Members are loaded lazily on first expand via `mwan3.nftset_elements` with a default limit of 200 elements. "Load more (1000)" and "Load all (5000)" buttons are shown when the set has more elements than the current display. Elements in counter-enabled sets show packet count and byte count (formatted as B/KiB/MiB/GiB) alongside the address.

**Actions:**

- **Flush** (`mwan3.nftset_flush`): empties the set.
- **Reload** (`mwan3.nftset_reload`): flushes then re-adds static entries from UCI (`entry` values and `loadfile` contents).
- **Resolve** (`mwan3.nftset_resolve`): HUPs dnsmasq and re-queries each configured domain, triggering dnsmasq's nftset population as a side effect.

After each action the header count and, if the panel is expanded, the member table refresh automatically.

#### 15.2.5 Diagnostics

The Diagnostics tab (`diagnostics.js`) provides an interactive runner for per-interface diagnostic commands. An interface selector and a task selector drive the operation; a Run button executes the selected task and displays output in a `<pre>` element. All buttons are disabled during execution.

| Task | Implementation | Description |
|---|---|---|
| Ping gateway | `luci-mwan3 diag gateway <iface>` | Pings the interface's current gateway 5 times via `mwan3 use` |
| Ping tracking IPs | `luci-mwan3 diag tracking <iface>` | Pings each configured track_ip 5 times via `mwan3 use` |
| Check IP rules | `luci-mwan3 diag rules <iface>` | Checks presence of all three ip rules for the interface |
| Check routing table | `luci-mwan3 diag routes <iface>` | Shows `ip route list table <id>` for the interface |
| Force interface up | `mwan3 ifup <iface>` | Triggers the ifup hotplug sequence |
| Force interface down | `mwan3 ifdown <iface>` | Triggers the ifdown hotplug sequence |

#### 15.2.6 Troubleshooting

The Troubleshooting tab (`troubleshooting.js`) presents the full output of `mwan3 internal ipv4` and `mwan3 internal ipv6` as a set of collapsible `<details>` panels, one panel per output section. The output is parsed by splitting on underline-delimited section headings (lines of `=` characters).

The nftables dump section is filtered to remove the `mwan3_or_(meta|ct)_*` vmap setter chains from the display, replacing them with a comment indicating how many chains were removed. These chains are an implementation detail of the connmark operation (see [Section 2](#2-the-mark-bitmask-system)) and would otherwise dominate the output. The IPv6 internal output deduplicates sections that are identical to the IPv4 output (Software Version and nft tables), showing only the IPv6-specific sections. Each section's content is shown in a `<pre>` element with `max-height: 250px` and vertical scroll.

### 15.3 Backend: Helper Script and ACL

#### Helper Script (`luci-mwan3`)

The `/usr/libexec/luci-mwan3` shell script provides backend commands invoked by the diagnostics tab.

**`diag` subcommand:** `diag gateway <iface>`, `diag tracking <iface>`, `diag rules <iface>`, and `diag routes <iface>`. The `diag rules` function reads `iif_rule_base`, `fwmark_rule_base`, and `unreachable_rule_base` from UCI config globals, computes the expected priority for each of the three ip rule tiers, queries `ip rule`, and reports found/missing counts. The `diag routes` function shows `ip route list table <id>` for the interface's sequential table ID.

**`nftset` subcommand:** `nftset dump` lists all user-defined set names in `table inet mwan3` by running `nft list table inet mwan3` and extracting set names via awk, then filtering out mwan3's own internal sets (prefixed `mwan3_`). This subcommand is no longer called by the rule editor (which uses the `mwan3.nftset_info` rpcd method directly) but is retained for command-line use.

> [!NOTE]
> `nft list sets inet mwan3` is not used because it lists sets from all inet tables, not just mwan3's table. `nft list table inet mwan3` is the correct form.

#### ACL Permissions (`luci-app-mwan3.json`)

The rpcd ACL file grants the LuCI frontend permission to call rpcd methods and execute files. It defines two ACL groups:

**`luci-app-mwan3`** (configuration access): Read permission for `mwan3.status`, `mwan3.nftset_info`, `mwan3.nftset_members`, `mwan3.nftset_elements`, `mwan3.resolve_host`, and the mwan3 and network UCI packages. Write permission for `mwan3.nftset_flush`, `mwan3.nftset_reload`, `mwan3.nftset_resolve`, and the mwan3 UCI package. Also grants `fs.stat` read access for detecting optional binaries (httping, nping, arping) and exec permission for `luci-mwan3 nftset dump`.

**`luci-app-mwan3-status`** (status and diagnostic access): Read permission for `mwan3.status`, `mwan3.nftset_info`, `mwan3.nftset_members`, `mwan3.nftset_elements`, `mwan3.resolve_host`, and `mwan3.routing_health`. Write permission for `mwan3.nftset_flush`, `mwan3.nftset_reload`, `mwan3.nftset_resolve`, and exec permission for the `luci-mwan3 diag` subcommands, `mwan3 internal`, `mwan3 ifup`, and `mwan3 ifdown`.

---

### 15.4 rpcd Methods

The following methods are implemented in `usr/share/rpcd/ucode/mwan3` and declared in `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`.

**`mwan3.status {}`**

Returns JSON data for interfaces, connected networks, and policies. Used by the Status tab.

- **Connected IPs**: Parses `nft -j list set inet mwan3 mwan3_connected_v4/v6`.
- **Policies**: Reads membership from UCI config and cross-references mwan3track `STATUS` files. Every member is always reported with traffic share percentage.
- **Interfaces**: Reads status from `/var/run/mwan3track/` files and queries procd/netifd via ubus. Tracking IPs discovered by globbing `TRACK_*` files. Per-IP `latency` and `packetloss` populated when `check_quality=1`.

**`mwan3.nftset_info {}`**

Returns the name, address-family type, counters flag, and runtime element count of all non-mwan3 sets in `table inet mwan3`. Used by the rule editor nftset dropdown and the IP Sets status tab.

**`mwan3.nftset_elements { set: "<name>", max: N }`**

Returns paginated elements of a named user-defined set with per-element packet/byte counters (when the set has `counter` enabled). The set name is validated against `^[a-zA-Z0-9_-]+$`. Default maximum 200 elements; supports up to 5000. Returns `{ elements: [...], truncated: true/false }`. Each element has `value`, and optionally `packets` and `bytes` for counter-enabled sets. Used by the IP Sets status tab for runtime member display.

**`mwan3.nftset_members { set: "<name>" }`**

Returns the current members of a named nft set in `table inet mwan3`. The set name is validated against `^[a-zA-Z0-9_-]+$`. Returns `{ members: [ ... ] }`. Used by the Simulator for ipset rule matching and connected-network bypass detection.

When a set has the `counters` flag enabled, nft wraps each element in the JSON output as `{"elem": {"val": "<addr>", "counter": {...}}}` rather than returning the address directly. `nftset_members` unwraps this structure so that counter-enabled sets return the same flat address list as non-counter sets.

**`mwan3.resolve_host { host: "<name>", family: "<ipv4|ipv6|>" }`**

Resolves a hostname by querying the local dnsmasq instance via `/bin/busybox nslookup`. Querying 127.0.0.1 populates any dnsmasq nftset entries configured for the domain as a side effect. Returns `{ v4: [ ... ], v6: [ ... ] }`. When `family` is `"ipv4"` only A records are queried; when `"ipv6"` only AAAA records; when empty (or omitted), both are resolved. The hostname is validated against `^[a-zA-Z0-9._-]+$` before any shell invocation; invalid input returns `{ error: "invalid hostname", v4: [], v6: [] }`. The DNS server echo line in nslookup output (which also contains an `Address:` prefix) is filtered by checking for the loopback address.

**`mwan3.nftset_flush { set: "<name>" }`**

Flushes all elements from the named set via `nft flush set inet mwan3 <name>`. The set name is validated against `^[a-zA-Z0-9_-]+$`. Returns `{}` on success or `{ error: "..." }` on failure. Used by the Flush button on the IP Sets status tab.

**`mwan3.nftset_reload { set: "<name>" }`**

Flushes the set then re-adds all static entries from the corresponding UCI `config ipset` section. Collects `list entry` values and, if `loadfile` is set, reads addresses line by line from the file (stripping comments and whitespace). Passes all entries to `nft add element inet mwan3 <name> { ... }` in a single invocation. Returns `{}` on success or `{ error: "..." }` on failure. If no UCI section is found for the set name, or the section is disabled (`enabled=0`), returns `{}` without error after flushing. Used by the Reload button on the IP Sets status tab.

**`mwan3.nftset_resolve { set: "<name>" }`**

Looks up the named set in UCI, collects `list domain` entries, sends SIGHUP to dnsmasq via `ubus.call('service', 'signal', {name:'dnsmasq', signal:1})` to clear its DNS cache, then queries each domain through the local dnsmasq instance (127.0.0.1) using `nslookup_resolve()`. The queries trigger dnsmasq's `nftset=` population mechanism as a side effect; no explicit `nft add element` call is needed. The address family (`A` or `AAAA`) is derived from the set's `family` UCI option. Returns `{ resolved: N }` where N is the count of domains that returned at least one address. Returns `{ error: "..." }` if the set is not found in UCI or has no `list domain` entries. Used by the Resolve button on the IP Sets status tab (only shown for sets with domain entries).

**`mwan3.routing_health {}`**

Compares the UCI configuration against live kernel state. For each mwan3 interface (by 1-based UCI order index N):

- Checks for ip rule at priority IIF_BASE+N (iif), FWMARK_BASE+N (fwmark), and UNREACHABLE_BASE+N (unreachable) via rtnl RTM_GETRULE. Base values read from UCI globals, defaulting to 1000/2000/3000.
- Checks routing table N for a default route via rtnl RTM_GETROUTE
- Reads `/var/run/mwan3track/<ifname>/STATUS` for current online/offline state
- Reports stale ip rules (priorities in mwan3's range with no matching UCI interface)
- Reports whether mwan3 is actively running (presence of any `STATUS` file under `/var/run/mwan3track/`)

---

## 16. Iptables-to-nftables Porting Notes

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

## 17. Command Line Tools

### 17.1 mwan3-lb-test: Load Balancing Distribution Verifier

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

### 17.2 mwan3-diag: Network Diagnostic Report

`mwan3-diag` is a ucode diagnostic script installed to `/usr/sbin/mwan3-diag` that collects a comprehensive snapshot of the network state relevant to mwan3 operation. It is intended to produce a report that can be posted in a forum thread or bug report without manual redaction.

#### Usage

```
mwan3-diag
```

The script collects interface addresses, routing tables (including all per-WAN tables), policy rules, neighbour cache, mwan3 interface status, the mwan3 UCI configuration, the complete mwan3 nftables ruleset, the fw4 mangle chains that interact with mwan3 packet marking, and the last 200 lines of the mwan3 log.

Before printing any output the script builds a map of every public routable IPv4 and IPv6 address present in the collected data and replaces each one with a stable placeholder -- `PUB4_1`, `PUB4_2`, `PUB6_1` and so on -- throughout the entire report, including free-form text such as nftables rules and log lines. The same address always receives the same placeholder, so cross-references between sections remain consistent. Private addresses (RFC1918, link-local `fe80::`, ULA `fc00::/7`, loopback) are left unchanged as they are diagnostically important. The elements of user-defined nftables sets are replaced with `{ ... }` rather than disclosed.

**Files changed:** `usr/sbin/mwan3-diag` (new), `Makefile`

---

## 18. Changelog

### 18.1 Version 3.6.9

**Summary:** Stop router-originated IPv6 link-local traffic, most visibly odhcpd's DHCPv6 replies to LAN clients, from being policy-routed into a WAN routing table and failing, by accepting single-link scopes before classification. Clear an inherited skb mark on ingress so a tunnelled-WAN reply is no longer pinned to the wrong routing table. Emit dnsmasq `nftset=` directives correctly when a domain is shared across multiple ipset sections, and stage the fragment atomically under the runtime directory.

---

### mwan3: clear inherited mark on ingress before conntrack restore

A packet decapsulated from a tunnel interface can inherit the outer packet's skb mark. On a tunnelled WAN (a tunnel broker or an L2TP link, for example) an inbound packet can therefore arrive already carrying mwan3's mark bits; the reply of a LAN-initiated flow is the common case. The inherited mark is independent of the inner address family, so the same failure occurs for IPv4 as for IPv6.

That stale mark defeats the conntrack mark restore in the prerouting chain, which is guarded on the mwan3 mark bits being clear, so the restore is skipped. The unguarded save that follows writes the inherited mark to the connection's conntrack mark, overwriting the classification the forward direction stored. Every subsequent packet of the flow then restores the wrong mark and is dispatched to the wrong routing table, pinning established flows to the wrong WAN.

Add a rule at the start of the prerouting chain, before the restore, that clears mwan3's mask bits. The restore and the interface and policy classification then re-derive the mark from a clean slate. The rule is a no-op for traffic that arrives with the bits already clear, the normal case on non-tunnel WANs, and it preserves any bits outside mwan3's mask. Mwan3 owns its mask exclusively and the coexisting policy-routing and firewall layers use disjoint bits, so no upstream hook legitimately sets these bits on ingress; the clear is therefore unconditional and covers both address families.

---

### mwan3: combine dnsmasq nftset directives for multi-family domains

dnsmasq silently ignores duplicate `nftset=` directives for the same domain: when a second directive names a domain already seen, it is discarded. This means that if an IPv4 and IPv6 ipset section both list the same domain, emitting separate per-section `nftset=` lines causes only the first set to populate.

Replace the per-section emission with a two-pass approach: pass 1 collects all (domain, set-specifier) mappings into a temp file, pass 2 sorts by domain and emits one `nftset=` line per unique domain with all its set targets comma-separated. The comma-separated multi-set format is documented dnsmasq grammar for the `nftset` directive.

This also fixes the same-family variant of the bug: a domain appearing in two sets of the same address family previously populated only the first set, and now correctly populates both.

---

### mwan3: stage dnsmasq nftset fragment atomically under the runtime dir

The per-instance dnsmasq nftset fragment was staged at a fixed `<fragment>.new` path inside the dnsmasq confdir. This has two defects:

- Two concurrent mwan3 invocations both write the same staging path and then rename it, so one can clobber or read the other's half-written file.

- The transient `.new` file sits inside the directory dnsmasq scans, meaning dnsmasq can attempt to parse a partially-written or stale staging file depending on `conf-dir` filter configuration.

Stage under the mwan3 runtime directory using a per-process, per-instance unique name. The existing `mv -f` swap remains and is now a guaranteed atomic same-filesystem rename (both paths are on tmpfs), so dnsmasq only ever observes the complete final fragment. Concurrent runs never share a staging path by construction.

---

### mwan3: never policy-route IPv6 link-local traffic

A catch-all `dest_ip ::/0` rule also matches link-local destinations. Router-originated link-local packets, most visibly odhcpd's DHCPv6 replies to LAN clients, then get a WAN fwmark and are re-routed into that WAN's routing table. That table has no link-local route for LAN devices, so sending fails with `ENETUNREACH`: `odhcpd[1234]: Failed to send to fe80::...%lan@br-lan.10 (Network unreachable)`. This breaks DHCPv6 on all LANs whenever an IPv6 WAN member is online.

Link-local traffic can never leave its link, so policy-routing it is never correct. Accept it before classification in `mwan3_output` and `mwan3_prerouting`. Covered are exactly the scopes that are single-link by definition (RFC 4291): link-local unicast (`fe80::/10`) and interface-/link-scope multicast (`ff01::/16`, `ff02::/16`). Wider multicast scopes remain subject to policy routing.

The existing ICMPv6 ND bypass stays: NS/NA can also target global unicast addresses, which a link-local destination match does not cover. Its stale comment is rewritten.

---

### 18.2 Version 3.6.8

**Summary:** Fix an operator precedence regression in 3.6.7 in the address family guard.

---

### mwan3: fix operator precedence in the address-family guard

The address-family guard in `mwan3_set_user_nft_rule()`combined its tests as `[ ] && [ ] || [ ] && [ ]`, which POSIX shell evaluates as `((A && B) || C) && D` rather than the intended `(A && B) || (C && D)`, so the guard no longer skipped a mismatched-family pass. Group each `&&` pair to restore the intended behaviour.

---

### 18.3 Version 3.6.7

**Summary:** 

Comma-separated address lists are now accepted in `src_ip` and `dest_ip` rule options, with each element individually validated and the list converted to nft anonymous set syntax at rule-build time.

IP address validation has been overhauled. A new `mwan3ipcheck` binary replaces the fragile regex-based validation, using the `inet_pton()` function for  address parsing that correctly rejects invalid input the old regex accepted silently. Of a list of 168 test cases, including both valid and invalid addresses, the regex expressions incorrectly passed 53 that were syntactically incorrect, meaning that mwan3ipcheck is a substantial reliability enhancement.

The `mwan3 status` command now parses `nft list set` output via `nft -j` and `jshn.sh` rather than a hand-built regex, fixing a bug where IPv6 prefix lengths were silently dropped and range elements were split into unrelated bare addresses.  

Interface tracking log output has been substantially cleaned up. A new `verbose_logging` globals option activates the existing debug-level `LOG()` calls, which were previously permanently suppressed; the option takes effect on `HUP`-triggered reloads without a full restart. Several messages that fired at notice level during normal operation have been demoted to debug level, including per-host probe results during recovery, the "lost host(s)" recovery message, the "skip disconnected event" notice, and the check failure message produced when an interface is brought down manually before the hotplug `USR1` signal arrives. 

The lost host count reported in tracking log messages has been corrected; it previously multiplied the host failure count by pings-per-host and reported the result as "lost ping(s)" rather than "lost host(s)".

Two tracking robustness fixes have been applied. When a signal (`HUP`, `USR1`, or `USR2`) arrives mid-round, the partially-completed ping loop now aborts immediately rather than continuing to remaining targets and scoring the killed pings as genuine failures. During service stop, `mwan3track` instances are now terminated via `procd_kill` before the routing infrastructure is torn down, eliminating spurious 100% loss messages that appeared on every restart. A syntax error in the `nping` tracking method has also been fixed: when `nping` produces no output the `result` variable was empty, causing a bare `[ -eq 0 ]` test error; it now defaults to `1`.

In `luci-app-mwan3`, the `verbose_logging` option is exposed as a checkbox on the Globals page. The rule editor's source and destination IP fields now accept comma-separated address lists with per-element validation and family consistency checking, matching the support added in mwan3. IPv6 validation across all files has been switched to `validation.parseIPv6()`, replacing heuristic detection. The configuration checker's rule shadowing detection now recognises when two rules reference the same nftset. A LuCI framework bug where the datatype validator corrupts CIDR values passed to custom validate functions has been worked around in the ipset entry validator.

---

### mwan3: suppress spurious check failure log on manual ifdown

When an interface is manually brought down, the tracking pings fail immediately but the `USR1` signal from hotplug has not yet arrived. This produces a misleading check failure log message moments before the interface is marked offline anyway.

The hotplug script writes the interface state to the hotplug state file before sending `USR1`, so `mwan3track` can read it to detect that an ifdown is already in progress. Skip the failure log when the hotplug state is already offline, since the message is redundant and misleading in that context.

---

### mwan3: demote "lost host(s)" recovery message to debug

This message fires every tracking round where score has not fully recovered and at least one host failed, even though the reliability threshold was met. During recovery this adds per-round noise alongside the connecting and connected notices that already communicate the state transition.

Demote to debug since it is only useful for detailed recovery diagnostics.

---

### mwan3: fix misleading "lost ping(s)" count in tracking log message

The `lost` variable counts how many track hosts failed to respond, not how many individual pings were lost. Multiplying by `count` (pings per host) and reporting the result as "lost ping(s)" overstated the actual loss. For example, with `count=5` and 1 of 3 hosts unreachable, it reported "Lost 5 ping(s)" when only 1 host failed.

Report the host count directly as "Lost N host(s)" instead.

---

### mwan3: demote "skip disconnected event" message to debug

This notice-level message logged when `disconnected()` was called on an interface that was already offline or connecting. It sat at the same syslog priority as genuine state transitions like "is offline" and "is online", adding noise that obscured real status changes.

Demote to debug since it is only useful for diagnosing redundant state transitions.

---

### mwan3: demote per-host recovery success messages to debug

During recovery (`score <= up`), `mwan3track` logged an info message for every track IP that responded successfully, every tracking round. With multiple track IPs and a default `up` threshold of 5, this produced up to 15 info messages per recovery episode.

The connecting and connected notices already communicate recovery progress at the operational level. Per-host probe results during recovery are diagnostic detail, now available via the `verbose_logging` option.

---

### mwan3: add verbose_logging option to enable debug log output

The `LOG()` function has historically suppressed all debug-level messages unconditionally, making the existing debug log calls across `common.sh`, `mwan3.sh`, and `mwan3track` permanently dead code.

Add a globals UCI option `verbose_logging` (default `0`) that controls whether debug-level messages are emitted to syslog. When enabled, all existing `LOG` debug calls become active, providing detailed diagnostic output for troubleshooting interface tracking and nft rule setup.

The option is loaded in `mwan3_init()` for all scripts, and also in `mwan3track`'s `load_tracking_config()` so that changes take effect on `HUP`-triggered config reloads without requiring a full restart.

---

### mwan3: fix test syntax error in nping tracking method

The `nping` tracking method extracts the lost-packet count from `nping` output via `grep` and `awk`. If `nping` produces no output or the output does not contain a "Lost" line, the `result` variable is empty. The subsequent arithmetic comparison expands to `[ -eq 0 ]`, which is a test syntax error in POSIX sh.

Default `result` to `1` (failure) when the extraction produces an empty string, so a missing "Lost" line is correctly treated as packet loss.

---

### mwan3: terminate trackers before infrastructure teardown on stop

During service stop, `stop_service()` tears down ip rules, routing tables, and nft chains before procd sends `TERM` to the `mwan3track` instances. The trackers continue pinging during this window but their packets can no longer be routed (the fwmark-based ip rules are gone), causing every tracking target to report 100% loss. This produces spurious failure log messages on every service restart.

Stop all `mwan3track` instances at the start of `stop_service` via `procd_kill`, which tells procd to terminate them and mark them as intentionally stopped.

---

### mwan3: skip tracking round when signal interrupts ping loop

When a signal (`HUP`, `USR1`, or `USR2`) arrives while `mwan3track` is mid-way through a ping round, the signal handler kills the current ping subprocess and sets an event flag. The killed ping returns non-zero, and the for loop continues to remaining tracking targets, all of which also fail. The event flags are not checked until after the for loop completes, so the entire round of killed-ping failures is scored and logged as genuine tracking failures.

Add an event flag check inside the per-IP for loop that breaks immediately when any signal flag is set. After the for loop, if any flag is set, reset the round counters and continue to the top of the while loop where event handling already runs, skipping the scoring, logging, and sleep for the aborted round.

---

### mwan3: support comma-separated addresses in src_ip and dest_ip rule options

The `mwan3ipcheck` binary returns `"mixed"` for comma-separated address lists containing both IPv4 and IPv6 elements. Add `"mixed"` to the validation rejection check alongside `"invalid"`, since a single nft anonymous set cannot contain both address families.

When a comma is present in `src_ip` or `dest_ip`, convert the value to nft anonymous set syntax by wrapping in `{ }` with normalized spacing. Single addresses (no comma) pass through unchanged, preserving identical nft output to prior behaviour.

CIDR elements within comma lists are supported natively by nft anonymous sets and require no special handling.

---

### mwan3: replace IPv4/IPv6 regex parsing with nft JSON in mwan3 status

The IPv6 regex had a bug where the CIDR suffix `(/[0-9]+)?` only bound to the final alternation branch because the 12-branch regex was joined with bare `|` and no outer grouping. This caused all IPv6 prefix lengths to be silently dropped from `mwan3 status` output. Range elements (produced by nft auto-merge on interval sets) were also mishandled, split into two unrelated bare addresses with no indication they form a range.

Replace the regex-based text parsing of `nft list set` output with structured JSON parsing using `nft -j` and `jshn.sh`. A new helper `_mwan3_report_connected_set()` handles both v4 and v6 sets, extracting prefix elements as `addr/len` and range elements as `start-end`.

Delete the `IPv4_REGEX` and `IPv6_REGEX` variables which are now unused.

---

### mwan3: replace regex IP validation with mwan3ipcheck

Replace the `grep`-based IPv4/IPv6 regex validation in the rule-building path with calls to the `mwan3ipcheck` binary, which uses the `inet_pton()` function.

The previous validation used a 12-line IPv6 extended regular expression and a separate IPv4 regex via `grep`, which matched substrings rather than whole strings. This caused it to accept invalid input such as addresses with trailing garbage, leading zeros in octets, extra octets, and out-of-range values.

Additionally, the validation only detected family mismatches (an IPv6 address in an IPv4 rule pass, or vice versa). An invalid IP address that matched neither regex would silently pass through and produce a nft syntax error at batch commit time.

`inet_pton()` is the authoritative address parser used by nftables. It handles all valid representations by definition and rejects everything else, eliminating both the substring-matching problem and the missing validation for invalid addresses.

---

### mwan3: add mwan3ipcheck address validation binary

Add a small C binary that validates and classifies IP addresses and CIDR notation using the POSIX `inet_pton()` function. Given a string argument, `mwan3ipcheck` prints `"ipv4"`, `"ipv6"`, or `"invalid"` to stdout and exits 0 on valid input or 1 on invalid input.

When a CIDR prefix is present (e.g. `192.168.1.0/24` or `2001:db8::/32`), the prefix length is validated against the appropriate maximum for the detected family (32 for IPv4, 128 for IPv6). Leading zeros in the prefix length are rejected.

This binary replaces the fragile regex-based IP address validation currently used in the rule-building path. `inet_pton()` is the authoritative POSIX address parser and handles all valid IPv4 and IPv6 representations by definition, eliminating the need for a hand-built 12-branch IPv6 extended regular expression.

The binary has no dependencies beyond libc (uses only `inet_pton`, `strtol`, and standard string functions).

---

### luci-app-mwan3: fix column alignment across IP set member tables

Set fixed column widths (50%/25%/25%) on both header and data cells so all expanded set tables align consistently.

---

### luci-app-mwan3: add verbose logging option to globals page

Add a checkbox for the `verbose_logging` UCI option to the Network > MultiWAN Manager > Globals page, positioned below the existing Logging checkbox. This exposes the mwan3 debug-level logging toggle.

---

### luci-app-mwan3: add comma-separated address support and enhanced validation

Add comma-separated address support to the rule editor's source and destination IP fields, matching the support already present in mwan3. Each address in a comma-separated list is individually validated for format and family consistency.

Replace IP family detection heuristics with `validation.parseIPv6()` across all files for robust IPv6 validation.

Improve validation in the simulator by tightening `looksLikeFqdn()` to reject malformed IPv4s instead of sending them to DNS resolution and validate addresses so that malformed ones are rejected before simulation.

Work around a LuCI framework bug where the datatype validator corrupts the value passed to custom validate functions for CIDR inputs. The ipset entry validator now performs its own format checking via a stub validator instead of relying on `o.datatype`.

Improve the configuration checker's rule shadowing detection to recognise when two rules reference the same nftset, rather than conservatively skipping all nftset comparisons.

---

### 18.4 Version 3.6.6

**Summary:** A race condition in the ct mark save logic has been fixed. The previous two-step clear and set sequence first cleared the MMX bits to zero and then set the new value in a consecutive rule, but between those two rules, under the right conditions, a packet on another CPU core could read the intermediate zero state, causing connections to be re-evaluated by the rules chain instead of being pinned to their assigned WAN. The clear is now folded into each setter chain as a single atomic expression, eliminating the race window and ensuring clear-set atomicity.

Adds a startup guard: mwan3 exits cleanly during startup if all interfaces are disabled, avoiding unnecessary nft chain loading and daemon startup. The default configuration now disables all interfaces and rules. Previously, a fresh install with no explicit user configuration would break the IPv6 internet because the balanced policy had no enabled IPv6 members, causing all IPv6 traffic to hit fall through to the unreachable last resort. A fresh install is now inert until explicitly configured by the user.

---

### mwan3: skip startup when no interfaces are enabled

Add a guard in `start_service` after `mwan3_init` loads the configuration: if no interface section has `option enabled '1'`, return without loading the nft framework or starting any daemons.

---

### mwan3: disable all interfaces and rules in default config

The default configuration ships with the wan interface enabled and three rules (`https`, `default_rule_v4`, `default_rule_v6`) active. On a fresh install with no user customisation, this breaks IPv6 internet: the balanced policy has no enabled IPv6 members, so all IPv6 traffic that reaches the policy chain hits the unreachable last resort.

IPv4 works by coincidence (wan is the only enabled member and routes traffic normally), but the tracking pings and nft chain overhead serve no purpose on a single-WAN setup.

Set all interfaces and all rules to enabled=0 so a fresh install is completely inert until the user explicitly configures mwan3.

---

### mwan3: fix ct mark save race by folding clear into setter chains

The nftables `ct mark save` operation used a two-step sequence: clear the MMX bits in ct mark to zero, then `vmap-dispatch` into a setter chain that ORed the new value in. Between those two rules, a packet on another CPU could observe ct mark with zeroed MMX bits, causing the restore step to miss the vmap lookup and allowing the connection to be reclassified to a random WAN.

Fold the clear into each save setter chain so that ct mark goes directly from old-value to new-value in a single nft expression (`ct mark set ct mark & COMPLEMENT | VALUE`). This eliminates the intermediate zero state entirely, providing the same single-write atomicity that `iptables CONNMARK --save-mark` had.

The standalone clear rules in the prerouting and output chains are removed since the setter chains now handle the masking internally.

---

### 18.5 Version 3.6.5

**Summary:** Replaces all `ip` command output parsing with direct `ucode-mod-rtnl` netlink calls via four new helper scripts in `/lib/mwan3`: `mwan3-create-iface-route.uc`,  `mwan3-get-addr.uc`,  `mwan3-list-routes.uc`,  `mwan3-manage-rules.uc`. These scripts replace the shell invocations of the ip binary and consequent (fragile) parsing of the ip output using `sed`, `awk` and `grep`, helping to make mwan3 more robust and future proofing it against potential changes in the output format of ip commands, since the helper scripts return precisely the information needed by mwan3 and do not require any parsing of the output. The scripts also contribute to a substantially enhanced efficiency profile, since there is now only one call per operation instead of multiple `ip` subprocesses each invoking `ip`, `sed`, `grep` and `awk`.

Adds `mwan3ct`, a small C-language replacement for the conntrack user-space CLI tool that takes over all conntrack flush operations previously handled by the `conntrack` CLI tool. `mwan3ct` makes possible several highly targeted flush operations currently not possible with the `conntrack` CLI tool without extensive (fragile) parsing of the output and multiple invocations of `conntrack -D`.

`mwan3ct` flushes `UNREPLIED` conntrack entries when an interface comes online to prevent stale marks from pinning traffic to the wrong WAN. This was previously not possible and is now enabled via `mwan3ct`. It's particularly helpful in the scenario of a load-balanced connection that has keepalives that could pin a connection to a failed WAN because the keepalives maintain the conntrack entry current.

Applies minor hardening by moving nft batch files from `/tmp` to the root-owned `/var/run/mwan3` directory and applies more restrictive umasks to the directory and file creation.

Fixes a scoping issue / buggy behaviour in nft that returns ipsets from other tables even though the query is scoped to a specific table, leading to a slow load time on `luci-app-mwan3` `Ipset` and `Rule` tabs if the other tables contain large set-based blocklists (eg., adblock packages, banIP).

---

### mwan3: fix nftset_info fetching all inet family sets

`nft 1.1.6` does not scope `nft list sets <family> <table>` to the named table - it returns every set in the family, including sets from unrelated tables. On systems with firewall packages that maintain large element sets (e.g. IP blocklists), `nft -j list sets inet mwan3` would return several megabytes of JSON containing elements from those foreign sets, making the rpcd `nftset_info` call take much longer than it should.

Replace `nft -j list sets inet mwan3` with `nft -j list table inet mwan3`, which is correctly scoped to the mwan3 table and returns only its content.

Since `nft list table` includes set element data inline, the separate `count_nftset_elements()` subprocess call per set is also eliminated: replace it with a direct `length()` of the elem array already present in the parsed JSON.

---

### mwan3: remove conntrack runtime dependency

`mwan3ct` replaced all `conntrack` CLI invocations in `mwan3.sh`. The `+conntrack` package dependency is no longer needed.

---

### mwan3: improve readability of shell source files

Added blank lines around comment blocks in `mwan3.sh` and `common.sh` to improve readability. Whitespace-only change, no functional modifications.

---

### mwan3: replace ip output parsing with ucode-mod-rtnl helpers

Replace all `ip` command invocations that parse output with calls to the ucode helper scripts added in the previous commit. This eliminates fragile `sed`/`awk` text parsing and reduces subprocess spawning.

Shell changes:
- `mwan3_get_src_ip`: replace `$IP address ls | sed` with `mwan3-get-addr.uc`
- `mwan3_set_general_rules`: replace `$IP rule list | awk` with `mwan3-manage-rules.uc add-general`
- `mwan3_delete_iface_rules`: replace `$IP rule list | awk` with `mwan3-manage-rules.uc delete-iface`
- `mwan3_report_iface_status`: replace `$IP rule/route` checks with `mwan3-manage-rules.uc check` and `check-route`
- `mwan3_set_custom_set`, `mwan3_set_connected_ipv4/v6`: replace `$IP route | awk | grep` pipelines with `mwan3-list-routes.uc`
- `mwan3_create_iface_route`: replace `$IP route list | sed | while read` with `mwan3-create-iface-route.uc`

Define `MWAN3_GET_ADDR`, `MWAN3_LIST_ROUTES`, `MWAN3_MANAGE_RULES`, and `MWAN3_CREATE_IFACE_ROUTE` variables in `common.sh` for consistent path references.

Remove dead code no longer reachable after these changes: `mwan3_update_dev_to_table`, `mwan3_route_line_dev`, `mwan3_get_routes`, `mwan3_extra_tables_routes`, and the `MWAN3_ROUTE_LINE_EXP` construction.

rpcd plugin: replace `popen ip -j rule/route` calls with direct `rtnl.request()` netlink queries, and fix field name mappings for rtnl (`oif` not `dev`, `null` not `"default"`, family as integer).

Makefile: add `INSTALL_BIN` lines for the four `.uc` scripts.

---

### mwan3: add ucode helper scripts for rtnl netlink access

Add four ucode scripts that use `ucode-mod-rtnl` for direct netlink communication instead of spawning `ip` subprocesses and parsing their text output through `sed`, `awk`, and `grep` pipelines. The existing approach is both fragile (sensitive to output format changes) and inefficient (each `ip` invocation forks a subprocess, and the subsequent text processing requires further subprocesses for each filter stage).

- `mwan3-get-addr.uc`: query interface addresses via `RTM_GETADDR`
- `mwan3-manage-rules.uc`: check, add, and delete policy rules via `RTM_GETRULE`/`RTM_NEWRULE`/`RTM_DELRULE`
- `mwan3-list-routes.uc`: list CIDR routes from a routing table via `RTM_GETROUTE`, used for nft set population
- `mwan3-create-iface-route.uc`: replicate routes from the main table into per-interface tables via `RTM_GETROUTE`/`RTM_NEWROUTE`

Each script produces exactly the output needed with no text parsing required. In several cases a single ucode invocation replaces what previously required multiple `ip` subprocess calls: `delete-iface` handles both address families in one call, `create-iface-route` performs route dump, filtering, deduplication, and table writes in a single process, and the rule `check` mode tests all three rule priorities from a single netlink dump.

---

### mwan3: move nft batch files from /tmp to /var/run/mwan3

Move nft batch file paths out of the world-writable `/tmp` directory into the existing `/var/run/mwan3` runtime directory, which is root-owned and created by `mwan3_init` at service start.

Restrict the runtime directory to mode `0700` and create batch files with mode `0600` via `umask` in `common.sh` and an explicit mode argument in `mwan3rtmon`. Nothing outside of mwan3's own root-running code accesses this directory.

This is a minor hardening change that eliminates a theoretical symlink/race window in `/tmp` for the nft batch files used by `common.sh` and `mwan3rtmon`.

---

### mwan3: flush unreplied conntrack entries on interface online

When an interface transitions to online, flush conntrack entries that carry an mwan3 mark but have never received a reply. These entries can result from a race during startup or policy rebuild where a flow gets classified before the nft chains reflect the new state. The stale mark pins traffic to the wrong WAN, and because no reply arrives (the traffic is misrouted or blackholed), the application keeps retrying, refreshing the conntrack timeout indefinitely.

Flushing only UNREPLIED entries is non-disruptive to established connections. The next packet from the application creates a fresh conntrack entry that gets classified under the current policy.

The flush is called after `mwan3_set_policies_nft` in both the `connected` action (mwan3track declares interface online) and the `ifup` action with `status=online` (interface comes up with `initial_state` online). It is not called during init - the existing `mwan3_flush_stale_conntrack` handles the startup window.

---

### mwan3: use mwan3ct for all conntrack flush operations

Replace all `conntrack` CLI invocations in `mwan3.sh` with `mwan3ct` calls:

- `mwan3_flush_stale_conntrack()`: `conntrack -D --mark 0x0/MASK` becomes `mwan3ct flush --mark 0x0/MASK`
- `mwan3_flush_marked_conntrack()`: shell loop spawning up to 63 `conntrack -D` processes becomes a single `mwan3ct flush --mark-any`
- `mwan3_flush_conntrack()` ifdown branch: `conntrack -D --mark VAL/MASK` becomes `mwan3ct flush --mark VAL/MASK`

Since `mwan3ct` is part of the mwan3 package, the `command -v conntrack` guards and missing-tool warnings are no longer needed.

---

### mwan3: add mwan3ct conntrack flush helper

Add a small C helper that uses libnetfilter_conntrack's `NFCT_Q_FLUSH_FILTER` to perform kernel-side filtered conntrack entry deletion by mark and/or status bits. This replaces all `conntrack` CLI usage in mwan3 with a purpose-built tool that is part of the package.

Motivations:

- Fragility: the previous approach for targeted unreplied-entry deletion required parsing `conntrack -L` output in shell, extracting fields with parameter expansion, and issuing per-entry `conntrack -D` calls. `mwan3ct` uses the library API directly with no text parsing.
- Efficiency: the "flush all marked entries" operation previously spawned up to 63 separate `conntrack` processes in a shell loop. `mwan3ct` handles this in a single process with one netlink socket.
- Correctness: the `conntrack` CLI ignores the `-u` status filter on delete operations, making it impossible to selectively delete only UNREPLIED entries. `mwan3ct` passes status filters to the kernel correctly via `NFCT_Q_FLUSH_FILTER`.

The tool supports `--mark <val>/<mask>` for exact match, `--mark-any <mask>` for any non-zero mark within the mask, `--status <val>/<mask>` for status bit filtering, and combinations of these.

The Makefile gains build dependencies on `libnetfilter_conntrack` and `libmnl`, a runtime dependency on `libnetfilter-conntrack`, and removes the incorrect `PKGARCH:=all` (the package already compiled architecture-specific code via `sockopt_wrap.c`).

---

### mwan3: fix diagnostic sanitizer treating 0.0.0.0 as a public address

The `is_public_v4()` function in `mwan3-diag` only excluded loopback, RFC1918, and link-local addresses. The "this network" block (`0.0.0.0/8`, RFC 1122) and multicast/reserved ranges (`224.0.0.0/4` and above) were not excluded, causing them to be replaced with placeholder addresses in the diagnostic output rather than shown verbatim.

Add exclusions for `0.0.0.0/8` and `224.0.0.0/3` so that these non-routable addresses are preserved in diagnostic output alongside the other non-routable ranges already excluded.

---

### 18.6 Version 3.6.4

**Summary:** Fixes a regression in 3.6.3 that prevents mwan3's hotplug handler from running when the service is started but not explicitly enabled

---

### mwan3: remove enabled check from hotplug handler

The enabled guard added in b363e9b50 causes the hotplug handler to exit silently when the rc.d symlink is absent. This breaks the startup path: start_service spawns per-interface hotplug handlers via mwan3_ifup using env -i, and those handlers exit at the enabled check without creating per-interface nft chains, ip rules, or routing tables. All WAN-bound traffic then hits the unreachable last-resort rule and connectivity is lost.

The guard was intended to prevent hotplug side effects when mwan3 is disabled, but it is redundant. The nft table existence check that follows already covers every practical scenario: the table is created by start_service and deleted by stop_service, so it is present only while the service is running. A service that was started manually without being enabled should still process hotplug events.

---

### 18.7 Version 3.6.3

**Summary:** Correctness fixes for edge cases and incomplete feature implementations: fixes ipset and ICMP protocol translation issues when rules use family=any; rebuilds ip rules and routing tables on reload to handle interface reordering and family changes; completes track_gateway support that was missing from two tracking status checks; adds runtime configuration reload to mwan3track via a SIGHUP handler and fixes hotplug handler initialization issues and boot race conditions.

---

### mwan3: fix ipset+family=any batch failure and sticky chain orphan

When a rule has `family=any` and references a UCI ipset whose declared family is ipv6, both the ipv4 and ipv6 passes run. The ipv4 pass finds the set absent from the kernel and pre-creates it as `ipv4_addr`. The ipv6 pass then generates an "ip6 daddr @setname" expression against an `ipv4_addr` set, causing the atomic nft batch to fail and killing all user rules.

Fix by adding a UCI lookup before the absent-set guard. The new helper `_mwan3_uci_ipset_addrtype()` maps a set name to its UCI-declared address type. When a referenced set is absent from the kernel but present in UCI, the incompatible pass is silently skipped and the compatible pass proceeds without pre-creation, since `mwan3_render_config_ipsets` will add the set to the same batch. The existing external-set guard (skip ipv6 pass, let ipv4 pre-create as `ipv4_addr`) is retained for sets absent from both kernel and UCI.

Separately, the preamble in `mwan3_set_user_rules()` that pre-creates and flushes per-rule sticky chains sourced chain names by listing `mwan3_rule_*` chains already present in the kernel table. After a UCI rule section is deleted, `mwan3_nft_reload_start` removes the chain in the same batch; however, because the batch has not yet been committed when the kernel is enumerated, the chain is still visible. The old code therefore flushes and reinserts the deleted chain into the batch, causing it to survive the reload as an orphan. Change the preamble to iterate over enabled UCI rule sections instead, so only chains for active rules are created and chains for deleted rules are not recreated.

---

### mwan3: fix ICMP protocol translation for family=any rules

UCI `proto=icmp` is family-agnostic, meaning ICMP appropriate to the address family of the rule. For `family=any` rules, mwan3 generates nft rules on two passes (ipv4 and ipv6). The ipv4 pass should emit "meta l4proto icmp" (protocol 1) and the ipv6 pass should emit "meta l4proto ipv6-icmp" (protocol 58).

Two interacting defects prevented the ipv6 translation from occurring:

The dedup optimisation that skips the ipv6 pass for `family=any` rules with no IP-version-specific elements incorrectly treated `proto=icmp` as family-agnostic. While TCP, UDP, and other L4 protocols share the same protocol number across families, ICMP (1) and ICMPv6 (58) are distinct protocols with distinct nft keywords. The dedup now excludes `proto=icmp` so both passes run.

The ICMP translation guard checked the UCI family config value instead of the current address-family pass variable. For `family=any`, the config value is "any", never "ipv6", so the translation never fired. The guard now checks the pass variable.

Without this fix, `family=any` rules with `proto=icmp` silently fail to match IPv6 ICMPv6 traffic.

---

### mwan3: rebuild ip rules and routing tables on reload

The trigger conditions for this bug are narrow - all three must hold: mwan3 must be running with two or more interfaces, the user must reorder config interface sections in `/etc/config/mwan3` without adding or removing interfaces, and the user must trigger a reload rather than a full restart.

When `reload_service` is called, it atomically rebuilds the entire nft ruleset using the current UCI configuration, but never rebuilds the kernel ip rules or per-interface routing tables. These kernel-side structures encode the interface table ID (tid), which is derived from the ordinal position of config interface sections in `/etc/config/mwan3`.

If the UCI section ordering changes between start and reload, the nft rules use the new tid-to-mark mapping while the ip rules and routing tables still reflect the old mapping. Traffic is silently routed to the wrong WAN interface.

A secondary manifestation of the same root cause: if an interface's family option changes (e.g. ipv4 to ipv6), the old ip rules remain in the wrong address family and new rules are never created.

Add `mwan3_rebuild_iface_rules`, called from `reload_service` via `config_foreach`, which deletes and recreates ip rules and routing tables for each enabled, up interface. Modify `mwan3_delete_iface_rules` and `mwan3_delete_iface_route` to search both address families unconditionally, so that a family change cleans up rules left behind in the old family.

---

### mwan3: fix mwan3rtmon has_tracking ignoring track_gateway

The `load_config` function in mwan3rtmon determines whether an interface has tracking enabled by checking only `track_ip`. Interfaces configured with `track_gateway` but no `track_ip` are incorrectly treated as having tracking disabled. This causes `get_track_status` to return "disabled" without consulting the tracker's PID and STARTED state files, bypassing the secondary health check guard in `handle_route_event`.

The shell equivalent in `common.sh` (`mwan3_get_mwan3track_status`) and the init script (`start_tracker`) both correctly account for `track_gateway`. Align mwan3rtmon's `has_tracking` logic to match by including `track_gateway` in the check.

---

### mwan3: reload tracker configuration on service reload

`mwan3track` reads UCI tracking parameters (interval, reliability, count, timeout, quality thresholds, etc.) once at startup and has no mechanism to update them at runtime. When `reload_service` rebuilds the nft ruleset, it does not restart tracker instances unless the tracker count changes, so any parameter changes made via UCI are silently ignored until a full service restart.

Add a `load_tracking_config()` function that extracts the parameter reads from `main()` into a reusable function called both at startup and on reload. Add a HUP signal handler to `mwan3track` that sets a reload flag and interrupts the current sleep/probe cycle. The main loop checks the flag at the same two points where IFDOWN and IFUP events are processed, re-reads UCI config, refreshes tracking parameters and track IPs, and clamps the score to the new down+up ceiling if it exceeds it.

In `reload_service`, send HUP to each running tracker instance after the existing rtmon HUP signals.

---

### mwan3: fix mwan3_get_mwan3track_status ignoring track_gateway

The `mwan3_get_mwan3track_status` function in `common.sh` returns "disabled" when no `track_ip` list entries are configured, without checking the `track_gateway` option. This causes the "mwan3 interfaces" CLI command to report "tracking is disabled" for interfaces that use gateway-only tracking, even though a tracker instance is actively running and monitoring the interface.

The rpcd ucode equivalent (`get_mwan3track_status`) already checks both `track_ip` and `track_gateway` before returning "disabled". Align the shell function with the same logic by also reading `track_gateway` before the early return.

---

### mwan3: fix hotplug handler to exit silently when mwan3 is not running

Add `/etc/init.d/mwan3` enabled guard before `procd_lock` and `mwan3_init` so that hotplug events are silently ignored when mwan3 has no rc.d symlink.

Move the nft table existence check to before `mwan3_init`. Previously `mwan3_init` was called unconditionally, which created `/var/run/mwan3` as a side effect and corrupted the stopped-service indicator in the case where mwan3 is enabled but has been manually stopped. With the check before `mwan3_init`, the handler exits without side effects whenever the nft table is absent, covering both the boot-race window and the stopped-but-enabled case.

Remove the running check that followed `mwan3_init`. It was dead code: `mwan3_init` created `/var/run/mwan3` before the check ran, so `service_running()` always returned true and the exit path was unreachable.

---

### 18.8 Version 3.6.2

**Summary:** A set of defensive edge-case fixes and correctness improvements. Binds the mwan3rtmon route listener before the initial netlink dumps to close a narrow startup race window, and replaces `main_route_cache` with an on-demand kernel query to eliminate a class of cache-drift failures that could only manifest if route events arrived during the dump phase. Aligns shell and mwan3rtmon custom-set filtering so both paths apply identical exclusions. Adds a dormant `is_default_route` guard to `populate_connected_set` as a forward-compatibility precaution. Clamps `check_quality` to 0 when the configured track method cannot produce quality samples, preventing an arithmetic error in the unusual case where `check_quality` is paired with a non-ping method. Fixes `mwan3_track_clean` which targeted incorrect paths and was a no-op, and tightens ip rule deletion at `stop_service` to use content-based matching rather than a priority-range regex, which matters only when rule bases are configured outside the default 1000-3999 band.

---

#### mwan3: exclude default routes from mwan3rtmon connected set population

`populate_connected_set` filters routes with `is_cidr_route` and `is_linklocal_route` but does not check `is_default_route`. Currently dormant because rtnl returns `dst=null` for default routes, which `is_cidr_route` already rejects. Add an explicit `is_default_route` guard so the filter remains correct if the rtnl module ever emits "0.0.0.0/0" or "::/0" as a string instead of null.

---

#### mwan3: replace main_route_cache with on-demand kernel query in mwan3rtmon

`main_route_cache` replaced an on-demand kernel query (`route_still_exists`, originally from e119a57e9) with a `route_key` map built from the initial dump and maintained incrementally from listener events.

The cache made the per-event ECMP-suppress check O(1) but introduced a class of dump-vs-listener race failure modes: any event arriving between the snapshot used to build the cache and the listener becoming active can double-count or undercount the cache, leading to stuck suppressions or premature cleanups of per-interface routing table entries with no self-healing path. The listener-first swap in an earlier commit shifts but does not eliminate this race.

`route_still_exists` queries the kernel directly on every delete and is unaffected by cache drift. Cost is one `RTM_GETROUTE` dump per `DELROUTE` event whose per-iface table entry exists, single-digit milliseconds on typical routing-table sizes and infrequent in practice.

---

#### mwan3: align shell custom-set population with mwan3rtmon filtering

The shell `mwan3_set_custom_set` function seeds `mwan3_custom_v4/v6` at start and reload so the sets are populated before mwan3rtmon starts. mwan3rtmon takes over incremental maintenance once procd schedules it.

Previously the shell and mwan3rtmon disagreed on filtering: the shell matched via IPv4_REGEX / IPv6_REGEX without excluding defaults or link-locals, while mwan3rtmon's `repopulate_custom_sets` excludes both via is_default_route and `is_linklocal_route`. Rewrite the shell function to apply the same exclusions (default, 0.0.0.0/0, ::/0, 169.254.*, fe80::*) and require a CIDR slash in IPv4 matches, so both paths produce identical set contents.

Also extend mwan3rtmon's `repopulate_custom_sets` to flush the set when no `rt_table_lookup` entries are configured, so removal of all `rt_table_lookup` entries followed by a reload correctly empties the set.

---

#### mwan3: bind mwan3rtmon route listener before initial dumps

mwan3rtmon's `main()` previously ran the initial netlink dumps before creating the route listener. Any `RTM_NEWROUTE` or `RTM_DELROUTE` emitted between mwan3rtmon process start and the rtnl.listener() call was discarded by the kernel (no multicast subscriber existed), leaving per-iface tables and the mwan3_custom_v4/v6 sets diverged from kernel state with no self-healing path.

Bind the listener first so its multicast socket starts buffering route events immediately, then issue the dumps. `ucode-mod-rtnl` creates the netlink socket and joins the multicast group synchronously inside the `rtnl.listener()` call, so the socket buffer captures concurrent events during the dump phase even before uloop.run() begins draining them.

Also add an explicit `repopulate_custom_sets()` call at startup so mwan3rtmon reconciles the `mwan3_custom_v4/v6` sets with kernel state once it begins running. The shell seeds these sets during `start_service`, but custom-table route changes between the shell pass and mwan3rtmon startup are unobserved by either side; the startup dump closes that window.

The connected set is unchanged; it already self-heals through a debounced rebuild triggered by every CIDR-route event.

---

#### mwan3: clamp check_quality for track methods that lack loss/latency

mwan3track's per-iteration case statement only populates `$loss` and `$latency` for the ping and httping methods. arping, nslookup, and nping-* set only `$result`. With `check_quality=1` configured against one of those methods the post-case decision block reaches

    `[ "$loss" -ge "$failure_loss" ] || [ "$latency" -ge ... ]`

with empty (or stale from a previous iteration) operands, which raises a busybox ash arithmetic error and leaves the per-host up/down classification undefined.

Clamp `check_quality` to 0 at startup when the configured `track_method` cannot produce quality samples, and emit a notice so the user can see that the option was overridden. Apply the same clamp in `mwan3_load_track_ips` so that `LATENCY_/LOSS_` state files are still cleaned up after a config edit that transitions the interface from a quality-capable method to one that is not.

---

#### mwan3: clean correct per-interface state paths in `mwan3_track_clean`

`mwan3_track_clean` is called from `stop_service` via `mwan3_interface_shutdown` to tear down per-interface runtime state. The original implementation removed `$MWAN3_STATUS_DIR/<iface>` and attempted to rmdir `$MWAN3_STATUS_DIR`. Neither matched where the per-interface state actually lives:

  - tracker runtime state at `$MWAN3TRACK_STATUS_DIR/<iface>/(PID, STATUS, LATENCY_*, LOSS_*, TRACK_*, GATEWAY, ...)`, written by mwan3track;
  - hotplug state file at `$MWAN3_STATUS_DIR/iface_state/<iface>`, written by `mwan3_set_iface_hotplug_state`.

The `$MWAN3_STATUS_DIR/<iface>` path the old code targeted does not exist, and the bare `$MWAN3_STATUS_DIR` rmdir always failed because that directory holds session-wide pinned state (mmx_mask and the iif_rule_base/fwmark_rule_base/unreachable_rule_base records used by mwan3_init across stop/start cycles), so the function was a no-op despite its name.

Point the rm at the correct per-interface paths and replace the bogus rmdir with a best-effort rmdir of `$MWAN3TRACK_STATUS_DIR` itself, which is the dir that should be empty once every iface has been cleaned. `$MWAN3_STATUS_DIR` is left intact because it holds state that must survive a stop/start cycle.

Errors are redirected to `/dev/null` so transient mismatches do not hit the console or logs. A comment in the function documents a small residual race with mwan3track that can briefly recreate the tracker dir between `rm` and `procd_kill`; the leak is bounded to one iteration and harmless on tmpfs.

---

#### mwan3: identify ip rules to delete precisely at stop_service

`stop_service` identified mwan3-owned ip rules with a fixed regex match on `^[1-3][0-9]{3}:`, limiting cleanup to priorities 1000-3999 and deleting every rule in that band regardless of origin. Two problems:

 1. When iif_rule_base, fwmark_rule_base or unreachable_rule_base are configured outside 1000-3999 (all three are exposed as globals and validated in mwan3_init), the affected tier of rules is leaked across service mwan3 stop and accumulates across stop/start cycles.

 2. Even within the band, a rule placed by another package or by a local admin override sitting at one of those priorities is indistinguishable from a mwan3 rule and gets deleted.

Replace the regex with a two-gate filter parsed in pure shell from ip rule list output. A rule is deleted only when it passes both:

* Priority gate: priority falls in one of the three configured rule-base ranges. The fwmark range extends to `fwmark_base + MM_UNREACHABLE` so the global blackhole and unreachable rules at `fwmark_base + MM_BLACKHOLE / MM_UNREACHABLE` are included.

* Content gate: the line references a mwan3-owned routing table (`lookup <N>` with N in `1..MWAN3_INTERFACE_MAX`), or carries an fwmark masked by mwan3's `MMX_MASK`.

To make the gates trustworthy at stop time, `mwan3_init` now persists `iif_rule_base`, `fwmark_rule_base` and `unreachable_rule_base` to state via `uci_toggle_state` at `start_service`, mirroring the existing `iface_max` persistence, and reads them back via `uci_get_state` on subsequent invocations. The state values reflect the rule bases the running instance actually created its rules with, even if `/etc/config/mwan3` has been edited since start. The `mmx_mask` state file doubles as the "instance started" indicator. The validation step that reverts to default bases on ordering-constraint violation runs only in the fresh-start branch, so persisted values are always post-validation.

---

### 18.9 Version 3.6.1

**Summary:** Extends the legacy mwan3 custom sets that were previously only loaded statically during `start_service()` and `reload_service()` from the tables defined in the UCI global config list option `rt_table_lookup` to be fully dynamic, using mwan3rtmon to listen for and to add and remove routes from the custom sets in response to `RTM_NEWROUTE` and `RTM_DELROUTE` events on the tables defined with `list rt_table_lookup <tableid>`. Adds a `SIGHUP` handler to mwan3rtmon to cause it to flush and repopulate these custom sets, ensuring that their contents remain in sync with any newly added or removed `list rt_table_lookup <tableid>` options in the mwan3 config.

---

#### mwan3: reload mwan3rtmon config on mwan3 reload via SIGHUP

mwan3rtmon loads its UCI configuration once at startup and holds it in memory for the lifetime of the process.  This includes `extra_table_set`, the in-memory set of routing table IDs derived from the `rt_table_lookup` UCI option.  When mwan3 reloads without a full restart (the common path when interface count does not change), mwan3rtmon stays running with its original `extra_table_set` intact.  If the operator changes `rt_table_lookup` during that reload, mwan3rtmon will continue routing events against the old table list until it is manually restarted.

Fix this by adding a `SIGHUP` handler to mwan3rtmon.  On receipt of `SIGHUP` it calls `load_config()` to refresh all in-memory UCI state and then `repopulate_custom_sets()` which performs a live netlink route dump of every table now in `extra_table_set` and rebuilds `mwan3_custom_v4/v6` from scratch. The flush-then-add pattern ensures that tables removed from rt_table_lookup have their routes evicted from the custom sets as well as tables newly added having their current routes immediately mirrored in.

`reload_service()` in the init script sends `SIGHUP` to the rtmon_ipv4 (and rtmon_ipv6 if IPv6 is enabled) procd instances via `procd_send_signal` after `mwan3_nft_reload_commit` and the ip rule updates, so the nft sets and ip rules are fully consistent before mwan3rtmon re-dumps.

The shell-level `mwan3_set_custom_sets()` call already present in `reload_service()` is retained. It runs inside the atomic nft batch and provides a synchronous static snapshot that ensures the sets are never empty during the reload window. The SIGHUP-triggered re-dump that follows is the authoritative update because it runs after the batch commits and picks up any route changes that occurred in the interval between the shell dump and the signal delivery.

---

#### mwan3: handle `rt_table_lookup` route events dynamically

The `rt_table_lookup` feature populated the `mwan3_custom_v4` and `mwan3_custom_v6` nftables sets at startup by reading existing routes from the configured tables, but did not update those sets when routes changed at runtime. Route additions and deletions in `rt_table_lookup` tables were therefore not reflected until mwan3 was restarted.

Add `handle_custom_set_event()`, called from `handle_route_event()` whenever a route event arrives for a table listed in `extra_table_set`. `RTM_NEWROUTE` events add the destination to the appropriate custom set; `RTM_DELROUTE` events remove it. Default routes and link-local routes are excluded, matching the exclusions already applied at startup.

---

### 18.10 Version 3.6

**Summary:** Version 3.6 adds three user-visible features to mwan3 rules. Rules now support an `fwmark`/`fwmask` option to match packets by meta mark using a masked comparison, working alongside or instead of address and ipset matching; mwan3 logs a warning if the fwmask overlaps its internal `MMX_MASK` since such a mask would match packets already carrying an mwan3 classification mark. The ip rule priority tiers for per-interface rules are now configurable via three new globals UCI options (`iif_rule_base`, `fwmark_rule_base`, `unreachable_rule_base`), shifting from the fixed 1000/2000/3000 defaults; two ordering constraints are enforced at startup and rule deletion is rewritten to use content-based matching so it remains correct across base or `mmx_mask` changes. Rules gain `option enabled 0/1`, consistent with interfaces, ipsets, and members.

The LuCI interface is updated throughout to reflect all three additions. The rule modal gains an Fwmark field with `MMX_MASK` overlap validation; the Globals tab gains the three base priority fields with live cross-field ordering validation and an automatic mwan3 restart when any base changes. The Routing Health tab gains the unreachable rule row per interface and marks an interface as degraded if the unreachable rule is absent; base priorities are now displayed dynamically from the rpcd endpoint rather than assumed from fixed offsets. The Traffic Simulator, rule shadowing analysis, Status Overview, and diagnostics helper are all updated to handle fwmark matching, disabled rules, and configurable bases. Mutual enable protection is added to prevent the silent misconfiguration of an enabled rule referencing a disabled IP set. mwan3track now validates that `libwrap_mwan3_sockopt.so` is present at startup, exiting with a clear error rather than silently producing incorrect tracking results if the library is missing.

---

### mwan3: add per-interface unreachable rule to rpcd routing_health

The `routing_health()` rpcd endpoint reported iif and fwmark rule presence per interface but omitted the unreachable rule. This meant the Routing Health tab could not detect a missing unreachable rule, and would show a fully healthy interface even if its unreachable safety net was absent.

Add `unreach_rule` (present + priority) to each interface in the response, and include the unreachable base priority in the rule_bases object returned to the frontend.

---

### mwan3: update rpcd `routing_health` for configurable bases and dynamic mmx_mask

The `routing_health()` function in the rpcd ucode module used hardcoded constants for the ip rule base priorities (1000/2000) and the maximum interface count (63). This meant the Routing Health tab reported incorrect data when configurable rule base priorities were in use, and would also be wrong for any installation with a non-default `mmx_mask`.

Read `iif_rule_base`, `fwmark_rule_base`, and `unreachable_rule_base` from UCI globals with the same defaults and ordering constraint validation as `mwan3_init` in `common.sh`. Derive `mmdefault` and `iface_max` dynamically from the configured `mmx_mask` by counting set bits, replacing the hardcoded `MAX_IFACES` constant. This ensures the blackhole and unreachable global policy rule priorities, stale rule range detection, and ordering constraint validation all reflect the actual runtime configuration.

Add the unreachable rule tier to valid priority tracking and stale rule detection. Previously only the iif and fwmark tiers were checked, so per-interface unreachable rules were invisible to the health report and could be falsely flagged as stale.

Return the active rule base priorities in the rpcd response so the frontend can display them dynamically rather than assuming fixed offsets.

---

### mwan3: add configurable ip rule base priorities and fwmark rule matching

fwmark/fwmask rule matching is added to `mwan3_set_user_nft_rule()`. A policy rule may now specify an fwmark and fwmask to match against the packet's meta mark using a masked comparison. The match is address-family agnostic, operating on meta mark rather than IP-layer fields. fwmark and fwmask must be specified together; a rule with only one set is skipped with a warning. A warning is also logged if the fwmask overlaps mwan3's internal `MMX_MASK`, since such a mask would match packets already carrying an mwan3 classification mark.

Three new globals UCI options: `iif_rule_base`, `fwmark_rule_base`, and `unreachable_rule_base` allow the ip rule priority tiers at which mwan3 installs its per-interface rules to be shifted from the original fixed offsets of 1000/2000/3000. Defaults are unchanged, so existing installations are unaffected and other packages that rely on mwan3's rules being inserted at those priorities remain unaffected insofar as the defaults are not overridden.

Two ordering constraints are enforced at startup:

  `iif_rule_base + MWAN3_INTERFACE_MAX < fwmark_rule_base`
  `fwmark_rule_base + MWAN3_INTERFACE_MAX + 1 < unreachable_rule_base`

If either constraint is violated, all three values are reverted to defaults with a logged warning.

The ip rule deletion logic in `mwan3_delete_iface_rules()` is rewritten to use content-based matching rather than a numeric range filter. Previously rules were deleted by checking whether their priority modulo 1000 equalled the interface id and fell in the range 1001-3999. This breaks when configurable bases place rules outside that range or at priorities that collide modulo 1000. The new logic identifies the iif rule by the iif keyword and table id, then discovers the fwmark/mask value from the lookup rule and deletes both the fwmark lookup and unreachable rules by content. This also handles upgrades from pre-configurable-base versions and `MMX_MASK` changes transparently.

For rules with `family=any` that have no IP-layer match criteria (no `src_ip`, `dest_ip`, or `pset`), the nft expression is address-family agnostic and would be emitted identically on both the ipv4 and ipv6 generation passes. The ipv6 pass is now skipped in that case to avoid installing a duplicate chain rule.

---

### mwan3: add missing `ucode-mod-socket` dependency 

mwan3-diag imports the ucode socket module to normalise IPv4 and IPv6  address strings via `sock.sockaddr()`. The `ucode-mod-socket` package was not listed in DEPENDS, so on a fresh install the module would be absent and mwan3-diag would abort at startup with an import error.    
    
Add `+ucode-mod-socket` to the package DEPENDS.

---

### mwan3: wire `validate_wrap()` startup check for `libwrap_mwan3_sockopt`

If `libwrap_mwan3_sockopt.so` is absent, mwan3track now exits with a clear error at startup rather than silently producing incorrect tracking results. Also define the library path as a single `WRAP_LIB` constant, and fix the file test from `-x` to `-f`.

---

### mwan3: add option enabled support for rules

UCI rules lacked the `option enabled 0/1` guard that interfaces, ipsets, and members already support. Add `config_get_bool` checks in two places:

- `mwan3_set_user_nft_rule(`: skip disabled rules at install time, consistent with the default of 1 (enabled) so existing configs without the option are unaffected. 

- `iface_rule()` inside `mwan3_set_user_iface_rules()`: skip disabled rules when scanning for `src_iface` matches so a disabled rule with a matching src_iface does not trigger a needless mwan3_set_user_rules rebuild on ifup hotplug events.

---

### luci-app-mwan3: fix hardcoded rule base priorities in diagnostics helper

The luci-mwan3 helper script used hardcoded iif (1000) and fwmark (2000) base priorities when checking ip rules for an interface. With configurable rule base priorities, the diagnostic "Check IP rules" would grep for the wrong priorities and report rules as missing when they are present at different priorities.

Read `iif_rule_base`, `fwmark_rule_base`, and `unreachable_rule_base` from UCI globals with the same defaults as the backend. Add the unreachable rule check that was missing entirely. Improve the output format to show each rule type individually with its expected priority and a summary count.

---

### luci-app-mwan3: filter disabled rules from Status Overview

The Overview tab displayed all configured rules regardless of enabled state. Disabled rules have no runtime effect and their presence in the overview misrepresents the active ruleset.

Skip rules with enabled=0 so the overview reflects what mwan3 actually evaluates at runtime.

---

### luci-app-mwan3: display per-interface unreachable rule in Routing Health

The Routing Health tab showed only the iif and fwmark ip rules per interface. The unreachable rule, which prevents packets marked for a down interface from being silently misrouted via the main routing table, was not visible.

Add an unreachable rule row to the per-interface health card using the `unreach_rule` data now provided by the rpcd endpoint. Include the unreachable rule in the health calculation so a missing unreachable rule is flagged as degraded. Update the field guide to describe all three rule tiers and display the unreachable base priority dynamically.

---

### luci-app-mwan3: add fwmark rule support and configurable rule base priorities

Adds an Fwmark field to the rule edit modal. The field takes a combined combined value/mask hex expression (e.g. `0x80000/0xff0000`) and splits it across the fwmark and fwmask UCI options on write. Validation checks hex format and rejects masks that overlap mwan3's internal `MMX_MASK` bits. The Destination column in the rule list is extended to append a `mark:value/mask` token when fwmark/fwmask are set, so fwmark-only rules do not appear as wildcard entries.

Traffic Simulator tab is extended to match fwmark rules. An Fwmark input field is added to the simulator form; its value is compared against each rule's fwmark/fwmask pair using a masked comparison, with an empty or absent mark treated as zero. `matchSummary` is updated to include the fwmark expression in the match description, and a pre-existing bug is fixed where `family=any` was displayed as IPv6 rather than being omitted.

Status Overview tab is extended to display the fwmark/fwmask expression in the Match column of the status page rules grid. Previously, rules that match solely on packet mark displayed as '(all traffic)'.

Globals tab gains three new form fields: `iif_rule_base`, `fwmark_rule_base`, and `unreachable_rule_base`, exposing the ip rule base priority options added to mwan3. Each field carries live cross-field validation enforcing the two ordering constraints required by the backend:

  `iif_rule_base + MWAN3_INTERFACE_MAX < fwmark_rule_base`
  `fwmark_rule_base + MWAN3_INTERFACE_MAX + 1 < unreachable_rule_base`

The tooltip for the `fwmark` and `unreachable` fields shows the minimum required offset above the preceding base, computed at render time from the current firewall mask setting so the displayed value reflects the actual interface capacity.

Changing any of the three base values requires a full mwan3 restart to delete and recreate all ip rules at the new priorities. `handleSaveApply` is overridden to detect base changes by comparing pre- and post-save UCI values and, if a change is found, registers a one-shot uci-applied event listener that calls mwan3 restart after the config is committed to disk. Pages that change only unrelated globals settings (logging, loglevel) do not trigger a restart.

Routing Health field guide displays the actual configured rule base priorities dynamically rather than hardcoded 1000/2000 labels, using the rule_bases object returned by the rpcd routing_health endpoint.

Configuration tab rule shadowing analysis is extended to account for fwmark/fwmask matching, and disabled rules (enabled=0) are filtered out before the analysis since mwan3 skips them at runtime.

---

### luci-app-mwan3: simulator: skip disabled rules during matching

The introduction of the enabled flag for rules created a gap in the traffic path simulator: disabled rules were still evaluated and could appear as matching results, giving incorrect output.

Filter disabled rules from both the nftset collection pass and the rule matching loop so that the simulator reflects the active ruleset as mwan3 sees it at runtime.

---

### luci-app-mwan3: ipset/rule: add mutual enable protection

An enabled rule referencing a disabled IP set silently misfires at runtime: mwan3 auto-creates the set as empty and the rule never matches any traffic. Three guards are added to prevent this misconfiguration.

On the IP sets tab, the Enable checkbox is rendered disabled (greyed out) when the set is currently enabled and referenced by at least one enabled rule. This prevents the user from disabling a set that is in active use.

On the rules tab, the Enable checkbox is rendered disabled when the rule is currently disabled and references at least one disabled IP set. This prevents the user from re-enabling a rule whose set dependency is not yet satisfied. The guard applies only when the rule is currently disabled; if the rule is already enabled the checkbox remains free so the user can uncheck it to correct the state.

On the rules tab, the Source NFT set and Destination NFT set dropdowns exclude any set that is explicitly disabled in the mwan3 UCI config. This prevents a disabled set from being assigned to an already-enabled rule via the modal form.

Both tabs also show an explanatory note in the section header describing when the checkbox will be greyed.

The implementation uses this.readonly set temporarily before calling the parent `form.Flag renderWidget`, which passes disabled: true to ui.Checkbox and sets the HTML disabled attribute on the input element. The enabled state is read via `uci.get()` rather than the `cfgvalue` argument, which is unreliable for options stored at their default value.


---

### luci-app-mwan3: use `addr:port` format in Overview rule listing

The Status-->Overview rule grid was displaying source and destination match fields as separate tokens (src:, src ipset:, sport:, dst:, dst ipset:, dport:), inconsistent with the Network-->Rules grid which combines address/ipset and port into a single addr:port expression.

Add a `fmtAddr()` helper mirroring the textvalue logic used in `rule.js`: address (or ipset if no address) is joined with port as `addr:port`, or `*:port` when only a port is set. The overview now shows `proto`, `src:` and `dst:` in the same compact format as the Rules grid.

---

### luci-app-mwan3: add Enable column to rules grid

Add an inline Enable checkbox to the rules GridSection. The checkbox uses `o.editable = true` so it is interactive directly in the grid row without requiring the modal to be opened.

To accommodate the new column without widening the grid, the separate Source port and Destination port columns are merged into the Source and Destination columns respectively. The merged `textvalue` format is `ddress:port` or `ipset_name:port` when both are set, `address` or `ipset_name` when only an address is present, `*:port` when only a port is set, and `-` when neither is set. `src_port` and `dest_port` are marked modalonly so they remain editable via the modal.

The Policy assigned column label is shortened to Policy.

---

### 18.11 Version 3.5.3

**Summary:** Version 3.5.3 adds two major LuCI features and a set of bug fixes and routing reliability improvements.

The Policy tab is rewritten with a tier-based policy builder that lets users specify failover tiers and per-interface load-balancing weights without manually creating member definitions. The builder handles member creation and garbage-collects orphaned members automatically, and updates the policy list to display IPv4 and IPv6 policies in symbolic form. The traffic simulator gains hostname resolution: Source and Destination fields now accept hostnames as well as IP addresses, resolved via the new `resolve_host` rpcd method against the local DNS server. The new Policy tab metaphor and layout should greatly improve how both new and existing users get to grips with mwan3, whose flexible but less than intuitive interface-member-policy definitions sometimes pose a substantial barrier to immediate use.

Three new rpcd methods - `nftset_flush`, `nftset_reload`, and `nftset_resolve` - allow the LuCI IP Sets tab to flush a set, repopulate it from UCI static entries and a loadfile, or trigger fresh DNS resolution by sending SIGHUP to dnsmasq before resolving configured domains. Matching Flush, Reload, and Resolve buttons appear on each set panel alongside the existing Expand button. `get_nftset_members` is fixed to unwrap the counter-decorated element wrapper that nft emits for counter-enabled sets, which previously caused all members of such sets to be silently dropped, breaking simulator rule matching for counter-enabled nftsets.

`mwan3_create_iface_route` is changed to use `ip route replace` instead of `ip route add`, making route installation unconditionally idempotent and eliminating spurious `EEXIST` errors when mwan3rtmon or a racing event had already inserted the route. A missing default argument in the `config_get_bool` call for the `enabled` option is added, suppressing cosmetic `sh: out of range` noise on startup.

---

#### mwan3: add nftset_flush, nftset_reload, and nftset_resolve RPC methods

`nftset_flush` empties a named nft set via `nft flush set`.

`nftset_reload` flushes the set then repopulates it from the UCI ipset config: static entries from the `entry` list and any entries read from the `loadfile` path.

`nftset_resolve` sends `SIGHUP` to dnsmasq to clear its cache, then iterates the `domain` list for the ipset and calls `nslookup_resolve` for each, triggering fresh DNS lookups that cause dnsmasq to populate the set via its nftset integration.

---

#### mwan3: fix missing default in config_get_bool enabled call

`mwan3_update_dev_to_table` iterates all mwan3 interface sections to build the device-to-routing-table map. The `config_get_bool` call for the enabled option had no default argument. When an interface section has no explicit option enabled set, get_bool receives an empty value and an empty default, falls through to the wildcard case, and returns an empty string. The subsequent `[ "$enabled" -eq 0 ]` comparison then receives an empty string as its left operand, causing busybox ash to emit sh: out of range (empty string has no digits consumed, triggering the error path in the test builtin's integer conversion).`

The error is cosmetic. The failed test exits non-zero, so the && return does not fire and the interface is treated as enabled, which is correct, but the error messages are misleading and concern users.

Fix by adding the missing default of 1, consistent with all other `config_get_bool` enabled calls in the file.

---

#### mwan3: use ip route replace in mwan3_create_iface_route

The previous ip route add would fail with `EEXIST` if the route was already present in the per-interface table -- for example when mwan3rtmon had already copied it from the main table, or when a connected event raced an ifup event. The string-match dedup check intended to prevent this was fragile: ip route list output for the same route can differ in text representation between table main and a per-interface table (field ordering, explicit metric 0, etc.), causing the check to miss a match and fall through to a duplicate add.

ip route replace uses `NLM_F_CREATE | NLM_F_REPLACE` at the kernel level, making the operation unconditionally idempotent. This is the same semantics mwan3rtmon already uses for its route copies. The duplicate-detection pre-check is retained as a cheap optimisation to avoid a redundant syscall when the route is already known to be present, but it is no longer safety-critical.

---

#### mwan3: add resolve_host RPC method for hostname resolution

Add `nslookup_resolve()` helper and `resolve_host` RPC method to allow the LuCI traffic simulator to accept hostnames in addition to IP addresses. The resolver invokes `/bin/busybox nslookup` against the local DNS server (127.0.0.1), populating any dnsmasq nftset entries configured for the queried domain as a side effect. Returns separate v4 and v6 address arrays; the family parameter restricts resolution to A or AAAA records. Input is validated against [a-zA-Z0-9._-]+ before use.

---

#### mwan3: fix get_nftset_members to unwrap counter-decorated elements

nft wraps set elements in `{"elem":{"val":"...","counter":{...}}}` objects when the set has the counter flag. The previous code passed these wrapper objects directly to `parse_elem_val()`, which returned null, silently dropping all members of counter-enabled sets. This caused the traffic simulator to fail to match rules that reference counter-enabled nftsets.

`get_nftset_elements()` already handled this case correctly; apply the same unwrap logic to `get_nftset_members()`.

---

#### luci-app-mwan3: add Flush, Reload, and Resolve buttons to IP Sets tab

Each set panel gains Flush, Reload, and Resolve action buttons alongside the existing Expand button. Flush empties the nft set. Reload flushes and repopulates from UCI static entries and the loadfile. Resolve is shown only for sets with configured domains; it sends SIGHUP to dnsmasq to clear its cache and triggers fresh DNS lookups to repopulate the set via dnsmasq's nftset integration.

All three buttons disable during the async operation and refresh the element count on completion. A page-level description explains each button's behaviour.

ACL grants for nftset_flush, nftset_reload, and nftset_resolve are added to both read-only and read-write rpcd permission groups.

---

#### luci-app-mwan3: reimplement the Policy tab

mwan3's use of members, metrics and weights is counter-intuitive for new users and even a barrier to effective use for some.

Create a new policy builder modal that allows policies to be specified by choosing interfaces and percentages to create a load balanced policy and policy tiers to allow for failover configurations.

The policy builder automatically handles member definitions, meaning that users never have to be concerned with creating members and with calculating appropriate metrics and weights. The policy builder does it all according to the configured tiers (metrics) and weights.

Update the policy list to remove the member column and instead show the IPv4 and IPv6 policies in a symbolic form that makes the configuration immediately obvious to the user.

Policy builder will automatically garbage collect orphaned members; a "Delete unused member definitions" checkbox in the policy tab header controls whether orphaned members are removed on save or not.

The Member tab is kept visible for manual inspection and editing of metric/weight values, although with the advent of policy builder, it is entirely redundant. Preserved more as a comfort to users who've been using mwan3 for a long time than for any really functional need.

---

#### luci-app-mwan3: add hostname resolution to traffic simulator

Allow the Source IP/Name and Destination IP/Name fields in the traffic simulator to accept hostnames in addition to IP addresses.

When a hostname is entered, the simulator calls the resolve_host RPC method to resolve it via the local DNS server before running the simulation. The resolved address is displayed inline as `Resolved: x.x.x.x (+N more)`. Resolution errors abort the simulation with an error message.

The address family selector controls A vs AAAA record resolution; IPv4 is preferred when the selector is set to both families. Update the ACL to permit the resolve_host method, update field labels and placeholder text to indicate hostname support, and widen the input fields.

---

### 18.12 Version 3.5.2

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

### 18.13 Version 3.5.1

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

### 18.14 Version 3.5

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

### 18.15 Version 3.4.1 (Unreleased)

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

### 18.16 Version 3.4

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

### 18.17 Version 3.3.5

**Summary:** Version 3.3.5 is a single-fix release that suppresses the per-deleted-entry output that `conntrack -D` writes to stdout, which was previously appearing on the console whenever mwan3 start or an fw4 reload triggered the zero-mark conntrack flush.

---

#### mwan3: suppress conntrack -D output to console

`conntrack -D` prints each deleted entry to stdout. The call in `mwan3_flush_stale_conntrack()` redirected only stderr, causing all deleted zero-mark conntrack entries to appear on the console whenever mwan3 start or fw4 reload triggered the flush.

Fix: redirect stdout to `/dev/null` alongside stderr.

---

### 18.18 Version 3.3.4

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

### 18.19 Version 3.3.3

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

### 18.20 Version 3.3.2

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

### 18.21 Version 3.3.1

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

### 18.22 Version 3.3

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

### 18.23 Version 3.2.3

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

### 18.24 Version 3.2.2

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

### 18.25 Version 3.2.1

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

### 18.26 Version 3.2

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

### 18.27 Version 3.1.4

**Summary:** Version 3.1.4 fixes interoperability with pbr by moving mwan3's prerouting and output chains from priority `mangle + 1` to `mangle - 1`, so mwan3 restores and saves its ct mark bits before pbr injects its own marks at `mangle` priority. With the previous ordering pbr's marks were zeroed before the routing decision and its ip rules never matched.

---

#### mwan3: fix pbr interoperability by running at priority mangle - 1

Move `mwan3_prerouting` and `mwan3_output` from priority `mangle + 1` to `mangle - 1` so mwan3 runs before pbr, which injects into fw4's `mangle_prerouting` at priority `mangle` (-150).

With the old priority, pbr set marks in `0x00ff0000` first, then mwan3's unmasked restore (`meta mark set ct mark & MMX_MASK`) zeroed them before the routing decision, causing pbr's ip rules to never match.

With `mangle - 1`, mwan3 restores and saves its mark before pbr runs. pbr then adds its bits on top, and both sets of marks are present at the routing decision -- matching the coexistence behaviour of the original iptables implementation.

Add `postinst` migration to flush and delete the old chains on upgrade, since nftables rejects a chain redeclaration with a different priority.

---

### 18.28 Version 3.1.3

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

### 18.29 Version 3.1.2

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

### 18.30 Version 3.1.1

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

---
## 19. Specific use-cases

### 19.1 Tailscale

Tailscale's specific routing architecture is incompatible with legacy mwan3, meaning that Tailscale had to explicitly bypass mwan3 and to that end, has specific detection code and a bypass. Tailscale cannot be managed with legacy mwan3 policies.

mwan3 nf tables, however, has the requisite functionality to enable peaceful co-existence between the two packages. If mwan3 is left in default configuration, Tailscale will continue to bypass mwan3 as it has always done and users will notice no difference. 

However, mwan3 can be specifically configured to policy route Tailscale bypass-marked traffic. The rest of this section explains how to do that.

#### Configuring mwan3 failover for tailscale control traffic

Tailscale marks every socket it opens for its own outbound connections (DERP relay servers, coordination server, STUN) with `SO_MARK = 0x80000` at socket creation time via `SetsockoptInt`. In normal operation with mwan3, it then installs an ip rule at priority 1310 that intercepts these marked packets and routes them to the main routing table (table 254, managed by netifd), bypassing mwan3's per-interface tables entirely:

```
1310: fwmark 0x80000/0xff0000 lookup main (254)
1330: fwmark 0x80000/0xff0000 lookup default (253)
1350: fwmark 0x80000/0xff0000 unreachable
1370: (unconditional) lookup tailscale (52)
```

Tailscale installs these rules at the 1300 base specifically because it detects OpenWrt with mwan3 active (`checkOpenWRTUsingMWAN3()` in `wgengine/router/osrouter/router_linux.go`) and shifts its default base from 5200 to 1300. The 1300 base is chosen to fit between mwan3's default iif rules (1001-1060) and mwan3's default fwmark lookup rules (2001-2060). The rules at 1310-1350 are an anti-loop mechanism: if tailscaled's own outbound traffic fell through to rule 1370 and was routed into `tailscale0`, it would re-enter the overlay indefinitely.

The problem is that rule 1310 routes tailscale's bypass-marked traffic via the main routing table, which is maintained exclusively by netifd and is not subject to mwan3's failover machinery. In the most common real-world WAN outage (upstream unreachable with carrier still up), netifd sees carrier and leaves the primary WAN route in the main table, so tailscale's control traffic continues trying to reach DERP servers via the dead upstream while mwan3 has already failed LAN traffic over to the backup WAN.

Tailscale requires this in order to prevent a routing loop, whereby bypass-marked packets enter the tailscale device via routing table 52 and was necessary when using Tailscale with legacy mwan3.

Making use of three features in mwan3 nftables, it is possible to get tailscale to benefit from mwan3 while also avoiding the aforementioned loop.

The solution has three parts:

1. A new mwan3 rule type that matches on a fwmark/fwmask.

2. The ability to shift the mwan3 rule priorities to a new base

3. Dynamic route monitoring by mwan3rtmon that mirrors routes from Tailscale's table 52  defined with `list rt_table_lookup '52'` in the globals section of `/etc/config/mwan3`.  mwan3rtmon will dynamically mirror peer IP/CIDRs in table 52 to the mwan3 sets `mwan3_custom_v4/v6`. Anything present in these sets will thus bypass mwan3's rules, fall through to the next rules in the list and get correctly routed by Tailscale's table 52. 

#### How the three parts work to integrate mwan3 and tailscale

1. The mwan3 rule matches on `fwmark 0x80000/0xff0000` and assigns the tailscale bypass marked packets to an mwan3 policy
2. The mwan3 rule fires before tailscale's bypass because of the route ordering priority change and routes out whichever is the active WAN. This gives the failover: the bypass marked packets are the outer tunnel / control plane
3. Traffic destined for the tailscale inner tunnel, which is normally looked up in table 52, has matching IPs and CIDRs in the `mwan3_custom_v4/6` sets put there by mwan3rtmon. Any destination IP in those sets will now bypass mwan3's specific handling and fall through to tailscale's rule that looks them up in table 52, routing them out the `tailscale0` device.

#### mwan3's fwmark and tailscale's bypass mark do not interfere with each other

mwan3 uses bits 8-13 of the packet mark (`0x3f00` default mask). Tailscale's bypass mark uses bits 16-23 (`0xff0000`). The two ranges do not overlap. mwan3's mark-set operation is non-destructive: it uses a bitwise OR via vmap-dispatch setter chains, so it writes only to the bits it owns and leaves all other bits intact.

After `mwan3_output` fires on a tailscale bypass packet, the packet carries both marks simultaneously in separate bit fields:

- bits 16-23: `0x80000` (tailscale bypass mark, unchanged)
- bits 8-13: `0x100` (mwan3 policy mark for interface id 1, ORed in)
- final mark: `0x80100`

#### Choosing the priority values

The only constraint is that mwan3's fwmark rules must fall outside of tailscale's mwan3 detection window. `checkOpenWRTUsingMWAN3()` looks for ip rules at priorities 2001-2004 with a non-zero fwmark. If any fwmark rule falls in that range, tailscale detects mwan3 and shifts its rules to a 1300 base, which would interleave with mwan3's fwmark rules. The constraint is:

```
fwmark_rule_base + MWAN3_INTERFACE_MAX < 2001
```

With the default mask `0x3f00` (6 bits, 60 maximum interfaces), this gives `fwmark_rule_base < 1941`. The recommended value is `fwmark_rule_base = 1100`, which places the highest-numbered fwmark lookup rule at 1160, well clear of the detection window. Tailscale therefore does not detect mwan3 and installs at its default 5210 base instead.

Because `iif_rule_base` defaults to 1000 and can stay there, only two UCI options need to be changed from their defaults:

| Option                  | Default | Recommended for tailscale |
| ----------------------- | ------- | ------------------------- |
| `iif_rule_base`         | 1000    | 1000 (unchanged)          |
| `fwmark_rule_base`      | 2000    | 1100                      |
| `unreachable_rule_base` | 3000    | 1200                      |

The ordering constraints validated by mwan3 at startup both hold:

- `1000 + 60 = 1060 < 1100` (iif tier clears fwmark tier)
- `1100 + 60 + 1 = 1161 < 1200` (fwmark tier including global blackhole/unreachable at 1161/1162 clears unreachable tier)

#### Why rule 5270 (table 52) still works correctly

Tailscale's rule 5270 is unconditional - it fires for every packet that reaches it. With mwan3's fwmark rules at 1101-1160, rule 5270 is reached only by packets whose `mark & 0x3f00` did not match any live per-interface id mark. The relevant case is packets carrying `MMX_DEFAULT` (mark = `0x3f00`).

`mwan3_prerouting` marks packets destined for networks in `mwan3_connected_v4` and `mwan3_custom_v4` with `MMX_DEFAULT` as an early-return bypass. `MMX_DEFAULT` does not match any per-interface fwmark rule (those require specific id marks, not all-bits-set), so these packets fall through to rule 5270, which looks up table 52 and routes them to `tailscale0`.

Ensuring tailscale peer destinations appear in `mwan3_custom_v4` is therefore the prerequisite for correct tailnet routing after the `fwmark_rule_base` change. This is described in the next section.

#### Ensuring tailnet-destined traffic reaches `tailscale0`

Tailscale installs peer routes exclusively into table 52 via netlink. The main routing table receives no tailscale peer routes. With mwan3's fwmark rules moved to 1101-1160, the default catch-all mwan3 rule assigns a WAN policy mark to all LAN traffic including packets destined for tailscale peers. That marked traffic hits rule 1101 before it reaches rule 5270. The per-interface routing table has a default route to the internet gateway but no route to the tailscale peer. The packet exits via the WAN unencrypted.

Under the default mwan3 configuration (fwmark rules at 2001+), tailscale rule 1370 fires at priority 1370, before the fwmark lookup rules at 2001+. The WAN policy mark is shadowed by rule 1370 and the packet reaches tailscale0 correctly. Moving the fwmark base to 1100 removes that shadowing.

The fix does not require touching routing tables. mwan3 provides `mwan3_custom_v4` and `mwan3_custom_v6`, nftables sets whose members receive `MMX_DEFAULT` in `mwan3_prerouting` and thereby bypass WAN policy selection entirely. The `rt_table_lookup` option in mwan3 globals instructs mwan3 to populate `mwan3_custom_v4/v6` from the routes in a specified routing table at start. Adding table 52 to this list:

```
list rt_table_lookup '52'
```

causes mwan3 to read all current table 52 routes at start and add their destinations to `mwan3_custom_v4/v6`. Packets to tailscale peers receive `MMX_DEFAULT`, pass through all per-interface fwmark rules without matching, and reach rule 5270 (`from all lookup tailscale`), which routes them to `tailscale0` via table 52. No per-interface routing table needs a tailscale route.

This is the correct treatment for the inner tailnet packets. `tailscale0` is a locally-connected TUN device: the inner packets are delivered to the tailscale daemon, which wireguard-encapsulates them into UDP. Those outer packets carry SO_MARK=0x80000 and are subject to mwan3 WAN failover via the dual-mark mechanism. `MMX_DEFAULT` on the inner packets correctly expresses that WAN selection does not apply at this layer; it is applied at the outer encrypted layer instead.

Tailscale adds and removes peer routes from table 52 dynamically as peers join and leave the tailnet. mwan3rtmon watches for `RTM_NEWROUTE` and `RTM_DELROUTE` events on tables listed in `rt_table_lookup` and updates `mwan3_custom_v4/v6` accordingly, so the set remains current without any external script or daemon.

If mwan3 starts before tailscale has populated table 52 (for example, on boot), the initial `rt_table_lookup` pass reads an empty or partial table 52 and `mwan3_custom_v4` is initially partially complete. mwan3rtmon's event handler fills in the missing entries as tailscale adds routes after its own startup, so the set converges to the correct state within seconds of tailscale coming up. 

#### The resulting rule layout

With `fwmark_rule_base = 1100` and `unreachable_rule_base = 1200`, and four mwan3 interfaces for illustration. Tailscale's ip rules are shown in their steady-state position, explained below. The moving of mwan3's base priority means that tailscale won't actually detect mwan3 to be running and will revert its own rule priority to the default of 5210 instead of installing at 1310.

```
 0:       from all lookup local
 1001:    iif <wan1-dev> lookup 1                      # mwan3 iif
 1002:    iif <wan2-dev> lookup 2                      # mwan3 iif
 1003:    iif <wan3-dev> lookup 3                      # mwan3 iif
 1004:    iif <wan4-dev> lookup 4                      # mwan3 iif
 1101:    fwmark 0x100/0x3f00 lookup 1                 # mwan3 fwmark  
 1102:    fwmark 0x200/0x3f00 lookup 2                 # mwan3 fwmark
 1103:    fwmark 0x300/0x3f00 lookup 3                 # mwan3 fwmark  
 1104:    fwmark 0x400/0x3f00 lookup 4                 # mwan3 fwmark
 1161:    fwmark 0x3d00/0x3f00 blackhole               # mwan3 blackhole
 1162:    fwmark 0x3e00/0x3f00 unreachable             # mwan3 unreachable
 1201:    fwmark 0x100/0x3f00 unreachable              # mwan3 unreachable
 1202:    fwmark 0x200/0x3f00 unreachable              # mwan3 unreachable
 1203:    fwmark 0x300/0x3f00 unreachable              # mwan3 unreachable
 1204:    fwmark 0x400/0x3f00 unreachable              # mwan3 unreachable
 5210:    fwmark 0x80000/0xff0000 lookup main (254)    # tailscale anti-loop
 5230:    fwmark 0x80000/0xff0000 lookup default (253) # tailscale anti-loop
 5250:    fwmark 0x80000/0xff0000 unreachable          # tailscale anti-loop
 5270:    from all lookup tailscale (52)               # tailscale overlay routing
 32766:   from all lookup main
 32767:   from all lookup default
```

Tailscale's mwan3 detection (`checkOpenWRTUsingMWAN3()` in `wgengine/router/osrouter/router_linux.go`) identifies mwan3 by looking for ip rules at priorities 2001-2004 with a non-zero fwmark. With `fwmark_rule_base = 1100` those rules are at 1101-1104, outside the detection window. Tailscale therefore does not detect mwan3 and installs its rules at its default base of 5200 (priorities 5210, 5230, 5250, 5270) .

This does not affect correctness. Tailscale bypass-marked packets (`0x80000`) acquire an mwan3 policy mark in `mwan3_output` and are caught at 1101-1104, well before tailscale's rules at 5210. The anti-loop concern that motivated rules 5210-5250 does not apply: the per-interface routing tables contain internet routes, not tailscale overlay routes, so there is no loop path. Tailnet-destined LAN traffic carries `MMX_DEFAULT` (via `mwan3_custom_v4`, described above) and passes through all fwmark rules without matching before reaching rule 5270, which routes via table 52 to `tailscale0`.

#### Configuration

In `/etc/config/mwan3`, in the `config globals` section, change the two rule base options and add the `rt_table_lookup` entry for tailscale's routing table (this can also be done on the Globals tab in Luci, as well as a bypass network `list bypass_network '100.64.0.0/10'`:

```
config globals 'globals'
    option mmx_mask '0x3F00'
    option fwmark_rule_base '1100'
    option unreachable_rule_base '1200'
    list rt_table_lookup '52'
    list bypass_network '100.64.0.0/10'
```

Add a rule section for tailscale bypass traffic, placed before any catch-all default rules, preferably as the very first rule in the list:

```
config rule 'tailscale_bypass'
    option fwmark '0x80000'
    option fwmask '0xff0000'
    option family 'any'
    option use_policy '<my_failover_policy>'
    option enabled '1'
```

Replace `<my_failover_policy>` with whichever mwan3 policy should carry tailscale's control traffic. Recommend you use a failover policy and not a balanced policy for this purpose. After saving, run:

```
service mwan3 restart
service tailscale restart
```

A reload (`service mwan3 reload`) updates the nftables rules and the ip rules atomically via `mwan3_delete_iface_rules` (which finds and removes old rules by routing table id regardless of their previous priority), so old rules at the legacy 2000/3000 bases are correctly cleaned up.

After restart, verify:

```sh
# mwan3's fwmark rules at 1101-1160, tailscale's rules at 5210-5270
ip rule list

# The tailscale bypass rule appears in mwan3_rules
nft list chain inet mwan3 mwan3_rules | grep fwmark
# Expected: meta mark & 0x00ff0000 == 0x00080000 ... jump mwan3_policy_<name>

# Tailscale peer destinations are in mwan3_custom_v4
nft list set inet mwan3 mwan3_custom_v4
```

#### Forcing immediate failover of tailscale DERP connections

DERP connections that were open at the moment of WAN failover remain on the old WAN until they close naturally. Only sockets opened after tailscale reconnects pick up the new fwmark ip rule. They should failover quite quickly anyway, but to force immediate failover, put the following into `/etc/mwan3.user`

```sh
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0

. /lib/functions.sh
. /lib/mwan3/common.sh
. /lib/mwan3/mwan3.sh
config_load mwan3
mwan3_init
mwan3_flush_marked_conntrack
```

