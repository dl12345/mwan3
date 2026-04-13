# mwan3 nftables Implementation

**Developer Reference** — OpenWrt 25.12+
Covers the nftables port of the mwan3 multi-WAN policy routing framework.
*Package version: 3.3.1*

---

## Contents

1. [Architecture Overview](#1-architecture-overview)
2. [The Mark Bitmask System](#2-the-mark-bitmask-system)
3. [nftables / fw4 Integration](#3-nftables--fw4-integration)
4. [Packet Flow Through Chains](#4-packet-flow-through-chains)
5. [File Reference](#5-file-reference)
   - [5.1 10-mwan3.nft](#51-usrsharenftablesdtable-post10-mwan3nft)
   - [5.2 common.sh](#52-libmwan3commonsh)
   - [5.3 mwan3.sh](#53-libmwan3mwan3sh)
   - [5.4 init.d/mwan3](#54-etcinitdmwan3)
   - [5.5 25-mwan3 (hotplug)](#55-etchotplugdiface25-mwan3)
   - [5.6 usr/sbin/mwan3 (CLI)](#56-usrsbinmwan3-cli)
   - [5.7 mwan3rtmon](#57-usrsbinmwan3rtmon)
   - [5.8 rpcd/ucode/mwan3](#58-usrsharerpcdуcodemwan3)
   - [5.9 Makefile](#59-makefile)
   - [5.10 mwan3-fw-include.sh](#510-libmwan3mwan3-fw-includesh)
   - [5.11 mwan3-fw-rebuild.sh](#511-libmwan3mwan3-fw-rebuildsh)
   - [5.12 mwan3-firewall-include (UCI defaults)](#512-etcuci-defaultsmwan3-firewall-include)
   - [5.13 mwan3track](#513-usrsbinmwan3track)
   - [5.14 mwan3-lb-test](#514-usrsbinmwan3-lb-test)
6. [Function Reference](#6-function-reference)
   - [6.1 common.sh Functions](#61-commonsh-functions)
   - [6.2 Set Management Functions](#62-set-management-functions)
   - [6.3 General Rule Setup](#63-general-rule-setup)
   - [6.4 Interface Management](#64-interface-management)
   - [6.5 Policy & Load Balancing](#65-policy--load-balancing)
   - [6.6 Sticky Routing](#66-sticky-routing)
   - [6.7 User Rules](#67-user-rules)
   - [6.8 Status Reporting](#68-status-reporting)
   - [6.9 Lifecycle & Hotplug](#69-lifecycle--hotplug)
7. [Load Balancing with numgen](#7-load-balancing-with-numgen)
8. [Sticky Routing Detail](#8-sticky-routing-detail)
9. [Service Lifecycle](#9-service-lifecycle)
10. [fw4 Reload Recovery](#10-fw4-reload-recovery)
11. [Unchanged Files](#11-unchanged-files)
12. [Diagnostic Commands](#12-diagnostic-commands)
13. [luci-app-mwan3 Changes](#13-luci-app-mwan3-changes)
    - [13.1 rule.js (Rule Editor UI)](#131-rulejs--rule-editor-ui)
    - [13.2 luci-mwan3 (Helper Script)](#132-luci-mwan3--helper-script)
    - [13.3 ACL Permissions](#133-luci-app-mwan3json--acl-permissions)
    - [13.4 interface.js (Interface Settings UI)](#134-interfacejs--interface-settings-ui)
14. [Iptables-to-nftables Porting Notes](#14-iptables-to-nftables-porting-notes)
15. [Enhancements](#15-enhancements)
    - [15.1 Selective Conntrack Flush on Interface Down](#151-selective-conntrack-flush-on-interface-down)
    - [15.2 Software Flow Offloading Co-existence](#152-software-flow-offloading-co-existence)
    - [15.3 Automatic Gateway Tracking (track_gateway)](#153-automatic-gateway-tracking-track_gateway)
    - [15.4 Postrouting SNAT for Rerouted Router-Originated Traffic (IPv4)](#154-postrouting-snat-for-rerouted-router-originated-traffic-ipv4)
    - [15.5 Opt-in IPv6 SNAT via Per-Interface snat6](#155-opt-in-ipv6-snat-via-per-interface-snat6)
    - [15.6 Diagnostic Tabs: Simulator, Configuration Checker, and Routing Health](#156-diagnostic-tabs-simulator-configuration-checker-and-routing-health)
    - [15.7 mwan3-lb-test: Load Balancing Distribution Verifier](#157-mwan3-lb-test-load-balancing-distribution-verifier)
    - [15.8 Source NFT Set Matching (`ipset_src`)](#158-source-nft-set-matching-ipset_src)
16. [Changelog](#changelog)
    - [Version 3.3.1](#version-331)
    - [Version 3.3](#version-33)
    - [Version 3.2.3](#version-323)
    - [Version 3.2.2](#version-322)
    - [Version 3.2.1](#version-321)
    - [Version 3.2](#version-32)
    - [Version 3.1.4](#version-314)
    - [Version 3.1.3](#version-313)
    - [Version 3.1.2](#version-312)
    - [Version 3.1.1](#version-311)

---

## 1. Architecture Overview

mwan3 is OpenWrt's multi-WAN policy routing framework. It classifies packets using **firewall marks**, then uses `ip rule` entries to route marked packets through per-interface routing tables. The nftables port replaces all iptables/ipset usage with nftables equivalents while keeping the ip rule/route management unchanged.

### Key Design Decisions

- **Lives inside `table inet fw4`** — mwan3 chains and sets are defined inside fw4's own table, not a separate table. This is how fw4 extension points (`table-post/*.nft`) work.
- **Own-priority hook chains** — `mwan3_prerouting` and `mwan3_output` are registered at `priority mangle + 1`, running after fw4's own mangle chains but before any higher-priority processing.
- **Non-destructive mark save/restore** — Connmark save and restore are masked to mwan3's own bit-range (`MMX_MASK`) and never touch bits owned by other packages such as pbr. This is the same property the iptables version had implicitly via `CONNMARK --restore-mark --nfmask`. The naive nftables translation cannot do it in one rule because the kernel rejects compound two-source bitwise expressions; mwan3 synthesises masked save/restore through a vmap-dispatch technique built from per-mark OR-immediate setter chains. See [Section 2 — Connmark Operations](#connmark-operations).
- **Static skeleton + dynamic rules** — A static `.nft` file defines empty sets and chains at fw4 startup. All rules are added dynamically by shell scripts since they depend on the configurable `MMX_MASK`.
- **inet family** — Chains handle both IPv4 and IPv6 in a single pass. Sets remain type-specific (separate v4/v6 sets) since nftables requires a single address type per set.
- **Batch operations** — Multi-element operations (connected set rebuild, policy chain rebuild, user rules) are batched via a temp file and committed with `nft -f` for atomicity and performance.
- **Dual fw4 reload recovery** — Since fw4 reload flushes the entire `table inet fw4`, mwan3 detects and rebuilds its dynamic rules via two complementary paths: a hotplug script (position 25, after fw4's position 20) and an fw4 script include that triggers on firewall restart. See [Section 10](#10-fw4-reload-recovery).

### Component Map

```
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
common.sh  mwan3.sh  10-mwan3.nft
(helpers)  (engine)  (static skeleton)
|          |
v          v
nft tool   ip tool
|          |
v          v
nftables    ip rule / ip route
(in-kernel)  (in-kernel)

Hotplug:       25-mwan3  --calls-->  mwan3.sh functions
Hotplug user:  26-mwan3-user  --calls-->  /etc/mwan3.user
CLI:           /usr/sbin/mwan3  --calls-->  mwan3.sh functions
RPC:           rpcd/ucode/mwan3  --calls-->  nft -j (JSON output)
Rtmon:         mwan3rtmon  --uses-->   ucode-mod-rtnl (netlink) + nft
fw4 include:   mwan3-fw-include.sh  --forks-->  mwan3-fw-rebuild.sh
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
> **Operator syntax:** Always use the `&` and `|` *symbols*, not the `and`/`or` keywords. The nft parser treats keywords ambiguously after expressions like `meta mark set ct mark` — it cannot tell if `and` starts a new match or a bitwise operation. Symbols are unambiguous.

### Connmark Operations

The iptables version of mwan3 used:

```
-j CONNMARK --restore-mark --nfmask $MMX_MASK --ctmask $MMX_MASK
-j CONNMARK --save-mark    --nfmask $MMX_MASK --ctmask $MMX_MASK
```

The `--nfmask`/`--ctmask` arguments scope both operations to mwan3's bit-range only — bits owned by other packages (such as pbr's `0x00ff0000` range) are left untouched in both directions. This non-destructive coexistence is essential when mwan3 shares the mark register with another mark-using package.

The naive nftables translation would be a compound two-source bitwise:

```
# Naive masked restore (does NOT compile):
meta mark set (meta mark & ~MMX_MASK) | (ct mark & MMX_MASK)

# Naive masked save (does NOT compile):
ct mark set (ct mark & ~MMX_MASK) | (meta mark & MMX_MASK)
```

The kernel rejects both with "Operation not supported": an nft set-statement can reference at most one runtime source register on its right-hand side. The single-source forms that *do* compile are:

```
meta mark set ct mark & MMX_MASK     # destructive: clobbers all non-mwan3 bits in meta mark
ct mark   set meta mark              # destructive: clobbers all non-mwan3 bits in ct   mark
```

Earlier port revisions used these destructive forms and worked around the resulting pbr breakage by changing chain priorities so that mwan3 ran *before* pbr (see [Changelog Version 3.1.4](#version-314)). That ordering papered over the symptom for one specific package but left the underlying behaviour broken — any second mark-using package would still have its bits zeroed.

#### vmap-dispatch save/restore (Version 3.2)

Version 3.2 restores iptables-equivalent masked semantics by synthesising the masked-restore and masked-save from a primitive that the kernel *does* allow: OR-ing a *literal immediate* into a single register.

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
- The technique is *order-independent* with respect to any other package that operates on a disjoint bit-range. Whether mwan3 runs before or after pbr in the prerouting hook stack, both packages' mark bits arrive at the routing decision intact.

**Why this works where the naive form does not:** the kernel constraint is on the *expression*, not the *control flow*. The kernel will not let one rule combine two register sources, but it will happily let a vmap dispatch on a runtime register value into a chain whose body uses a literal immediate. The dispatch chain materialises at runtime exactly the value you wanted to OR, baked into a constant when the mwan3 init scripts emit the rule.

**Cost:** chain count, not packet-path overhead. Each packet traverses one extra `vmap` lookup (O(log) in the kernel's set lookup) and one extra `jump`/`return` per save and per restore. The 126 setter chains add no fast-path cost — they are visited via constant-time dispatch, and most never fire on any given packet.

> [!NOTE]
> **The kernel limitation has not changed.** Compound two-source bitwise set expressions are still rejected. vmap-dispatch is a workaround built from primitives that *are* permitted; it does not require any new kernel capability.

---

## 3. nftables / fw4 Integration

OpenWrt's fw4 firewall includes files from `/usr/share/nftables.d/table-post/` inside its `table inet fw4 { }` block. mwan3 installs `10-mwan3.nft` there, which defines:

### Static Objects (from 10-mwan3.nft)

| Object | Type | Purpose |
|---|---|---|
| `mwan3_connected_v4` | set (ipv4_addr, interval, auto-merge) | Directly connected IPv4 networks |
| `mwan3_connected_v6` | set (ipv6_addr, interval, auto-merge) | Directly connected IPv6 networks |
| `mwan3_custom_v4` | set (ipv4_addr, interval, auto-merge) | Networks from custom routing tables |
| `mwan3_custom_v6` | set (ipv6_addr, interval, auto-merge) | Networks from custom routing tables |
| `mwan3_dynamic_v4` | set (ipv4_addr, interval, auto-merge) | Dynamically managed networks |
| `mwan3_dynamic_v6` | set (ipv6_addr, interval, auto-merge) | Dynamically managed networks |
| `mwan3_prerouting` | chain (filter, prerouting, mangle+1) | Entry point for forwarded/incoming traffic |
| `mwan3_output` | chain (route, output, mangle+1) | Entry point for locally-originated traffic |
| `mwan3_postrouting` | chain (nat, postrouting, srcnat-1) | Opt-in IPv6 SNAT for router-originated traffic rerouted by mwan3 — see [§15.5](#155-opt-in-ipv6-snat-via-per-interface-snat6) |
| `mwan3_ifaces_in` | chain (regular) | Dispatches to per-interface chains |
| `mwan3_rules` | chain (regular) | User-defined classification rules |
| `mwan3_connected` | chain (regular) | Marks traffic to connected networks as default |
| `mwan3_custom` | chain (regular) | Marks traffic to custom-table networks as default |
| `mwan3_dynamic` | chain (regular) | Marks traffic to dynamic networks as default |

> [!NOTE]
> **auto-merge flag:** All sets include the `auto-merge` flag in addition to `interval`. This allows nftables to merge overlapping elements (e.g., a host address and a containing CIDR) automatically, preventing insertion failures. The `nft add set` command is idempotent for creation but does *not* update flags on existing sets — so `mwan3_ensure_nft_framework()` deletes and recreates sets at startup to guarantee the flag is present.

### Dynamic Objects (created at runtime)

| Object Pattern | Type | Created By |
|---|---|---|
| `mwan3_iface_in_<name>` | chain | `mwan3_create_iface_nft()` |
| `mwan3_policy_<name>` | chain | `mwan3_create_policies_nft()` |
| `mwan3_rule_<name>` | chain | `mwan3_set_user_nft_rule()` (sticky rules only) |
| `mwan3_or_meta_<mark>` | chain (×63 with default `MMX_MASK`) | `mwan3_build_or_chains_nft()` — non-destructive restore setter chains |
| `mwan3_or_ct_<mark>` | chain (×63 with default `MMX_MASK`) | `mwan3_build_or_chains_nft()` — non-destructive save setter chains |
| `mwan3_sticky_v4_<rule>_<id>` | set (ipv4_addr, timeout) | `mwan3_set_user_nft_rule()` — one set per policy member (id = interface id) |
| `mwan3_sticky_v6_<rule>_<id>` | set (ipv6_addr, timeout) | `mwan3_set_user_nft_rule()` — one set per policy member (id = interface id) |

> [!NOTE]
> **Why `type route` for output?** The output chain uses `type route` (not `type filter`) because changing a packet's mark on locally-originated traffic must trigger a routing re-lookup. This matches fw4's own `mangle_output` chain type.

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
  |     |         non-destructive — preserves non-mwan3 bits in meta mark)
  |     |
  |     +-- Still mark == 0?
  |           |
  |           +-- jump mwan3_ifaces_in
  |           |     Per-interface chains check source address:
  |           |       - src in connected/custom/dynamic? -> mark = MMX_DEFAULT
  |           |       - otherwise -> mark = interface mark
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
  |     (non-destructive — preserves non-mwan3 bits in ct mark)
  |
  |-- mark & MMX_MASK != MMX_DEFAULT?
  |     (Traffic that got a specific interface mark, not "default")
  |     Re-check against custom/connected/dynamic destinations
  |     This allows connected-destination traffic to be overridden
  |     back to default routing even if it was marked by user rules
  |
  +-- ACCEPT (policy accept; packet continues to routing decision)
```

### Per-Interface Chain Detail

Each `mwan3_iface_in_<name>` chain:

1. Matches on `iifname` (device name) and address family
2. If source address is in connected/custom/dynamic sets → mark as `MMX_DEFAULT` (don't route through this WAN for local-origin traffic)
3. Otherwise → mark with the interface's unique mark (classify as "arrived via this WAN")

---

## 5. File Reference

### 5.1 `usr/share/nftables.d/table-post/10-mwan3.nft` [static]

The static nftables framework file. Included inside `table inet fw4 { }` by fw4 at startup. Defines 6 named sets (all empty, with `flags interval` and `auto-merge` for CIDR support with overlapping element handling) and 8 skeleton chains (all empty). No rules are present — all rules are added dynamically by the shell scripts because they depend on the configurable `MMX_MASK` value.

The hook chains:

- `mwan3_prerouting` — type `filter` at priority `mangle + 1`
- `mwan3_output` — type `route` at priority `mangle + 1` (`type route` is required so mark mutations trigger a routing re-lookup for locally-originated traffic)
- `mwan3_postrouting` — type `nat` at priority `srcnat - 1`. Opt-in IPv6 SNAT chain for router-originated traffic that mwan3 has rerouted onto a different WAN. IPv4 router-originated traffic is handled by fw4's unguarded `masquerade` and needs no explicit rule here. See [§15.5](#155-opt-in-ipv6-snat-via-per-interface-snat6).

### 5.2 `lib/mwan3/common.sh`

Shared helper library sourced by all mwan3 shell scripts. Provides:

- **Tool variables**: `$IP4`, `$IP6`, `$NFT`
- **IPv6 detection**: Checks `/proc/sys/net/ipv6` existence (instead of the old `command -v ip6tables`)
- **nft batch helpers**: `mwan3_nft_batch_start()`, `mwan3_nft_push()`, `mwan3_nft_batch_commit()`
- **`mwan3_nft_exec()`**: Wrapper that runs `nft` commands with error logging
- **`mwan3_nft_mark_expr()`**: Generates nftables mark-set expressions equivalent to iptables `--set-xmark`. Outputs `meta mark set meta mark & COMPLEMENT | VALUE` using `&`/`|` symbols (not `and`/`or` keywords).
- **`mwan3_ensure_nft_framework()`**: Guarantees all mwan3 nftables objects (sets and chains) exist with correct flags. Deletes and recreates all 6 sets to ensure the `auto-merge` flag is present (since `nft add set` is idempotent but won't update flags on existing sets). Then creates all skeleton chains, including `mwan3_postrouting`. Called early in `start_service()`.
- **`mwan3_build_or_chains_nft()`**: Materialises the per-mark setter chains used by the non-destructive vmap-dispatch save/restore. Iterates all 63 possible non-zero values within `MMX_MASK` and emits two chains per value: `mwan3_or_meta_<imm>` (non-destructive restore from ct mark to meta mark) and `mwan3_or_ct_<imm>` (non-destructive save from meta mark to ct mark). Called from `mwan3_set_general_nft()`. Always flushes and re-populates the chain bodies — an earlier idempotency check that returned early on chain *existence* alone could leave the chain bodies empty after a partial-failure first run, which is fatal to packet flow.
- **`mwan3_init()`**: Loads config, computes mask constants (`MMX_DEFAULT`, `MMX_BLACKHOLE`, `MMX_UNREACHABLE`, `MMX_MASK_COMPLEMENT`)
- **`mwan3_id2mask()`**: Bit-spreading function that maps interface IDs onto the mask
- **`mwan3_count_one_bits()`**: Counts set bits in a value
- **Utility functions**: `LOG()`, `readfile()`, `mwan3_get_src_ip()`, `mwan3_get_true_iface()`, `mwan3_get_mwan3track_status()`, `get_uptime()`, `get_online_time()`

> [!NOTE]
> **Shell scoping note:** Functions like `mwan3_id2mask` and `mwan3_count_one_bits` receive *variable names* as arguments (e.g., `mwan3_id2mask mmdefault MMX_MASK`) and use arithmetic expansion `$(($1))` to resolve them. This works in busybox ash (OpenWrt's default shell) because it uses dynamic scoping — local variables from the caller are visible in called functions.

### 5.3 `lib/mwan3/mwan3.sh`

The core engine. Contains all functions for managing nftables chains/sets/maps, ip rules, ip routes, policy creation, user rule classification, and status reporting. This is the largest file and the heart of the implementation. Sourced by init.d, hotplug, CLI, and rtmon scripts.

See [Section 6](#6-function-reference) for detailed function reference.

### 5.4 `etc/init.d/mwan3`

procd service script. Handles:

- **`start_service()`**: Initializes everything in order: ensure nft framework → sets → general rules → general nft chains → interface hotplug → policies → user rules. Starts `mwan3track` instances and `mwan3rtmon` (one per address family).
- **`stop_service()`**: Tears down in reverse: shuts down interfaces, flushes ip routes/rules, flushes all mwan3 nft chains, deletes dynamic chains (keeps skeleton chains from the static .nft file), flushes sets, flushes sticky sets.
- **`start_tracker()`**: Launches a `mwan3track` procd instance per enabled interface with track IPs.
- **`service_running()`**: Returns true if `$MWAN3_STATUS_DIR` exists.

#### Startup Sequence

```
mwan3_init()
  mwan3_ensure_nft_framework()            # delete/recreate sets with auto-merge, create chains
  config_foreach start_tracker interface  # launch health probes
  mwan3_update_iface_to_table()           # build iface->table mapping
  mwan3_set_dynamic_sets()                # flush dynamic sets
  mwan3_set_connected_sets()              # populate connected sets
  mwan3_set_custom_sets()                 # populate custom sets
  mwan3_set_general_rules()              # ip rule add (blackhole/unreachable)
  mwan3_set_general_nft()                # populate hook chain rules
  config_foreach mwan3_ifup interface "init"  # trigger ifup hotplug per interface
  wait $hotplug_pids                     # wait for parallel hotplug
  mwan3_set_policies_nft()               # create policy chains
  mwan3_set_user_rules()                 # populate user rules chain
  [if flow_offloading=1] flush conntrack # force flow re-establishment under new policy
  start rtmon_ipv4 + rtmon_ipv6          # route monitor daemons
```

### 5.5 `etc/hotplug.d/iface/25-mwan3`

Handles interface state change events from netifd. Triggered on `ifup`, `ifdown`, `connected`, and `disconnected` actions. Positioned at **priority 25** to run after fw4's `20-firewall` hotplug script, which is critical for fw4 reload recovery.

#### Guard Checks

1. Valid action and interface name
2. Not first-connect or shutdown
3. Device present for ifup/connected
4. procd lock (unless called from init)
5. Service is running (`$MWAN3_STATUS_DIR` exists)
6. nft framework is loaded (`nft list chain inet fw4 mwan3_prerouting` succeeds)
7. Interface is enabled in UCI

#### fw4 Reload Detection

Between the guard checks and the per-action processing, the hotplug script detects whether fw4 has reloaded (wiping all dynamic mwan3 rules). It checks whether `mwan3_prerouting` contains any `meta mark` rules. If the chain is empty (skeleton only), it performs a full rebuild of all nft rules, interface chains, policies, and user rules. It also calls `mwan3_dnsmasq_hup()` to clear the dnsmasq DNS cache so that subsequent DNS queries re-populate any nftset-based sets. See [Section 10](#10-fw4-reload-recovery) for full details.

#### Actions

| Action | Operations |
|---|---|
| `ifup` | Update peer track IP (if `track_gateway` enabled), create interface nft chain, create ip rules, set hotplug state, create routes (if not init), set general rules, rebuild policies (if online and not init). Signal tracker with USR2. |
| `ifdown` | Set offline state, selectively flush conntrack entries for this interface's fwmark, flush sticky set entries for this interface, delete ip rules, delete routes, delete interface nft chain. Signal tracker with USR1. Rebuild policies. |
| `connected` | Set online state, rebuild policies |
| `disconnected` | Set offline state, rebuild policies |

> [!NOTE]
> **ifup conditional policy rebuild:** During init (`MWAN3_STARTUP=init`), the ifup action skips route creation, general rules, and policy rebuild because the init sequence handles those after all interfaces are up. During normal operation, policies are only rebuilt if the interface state is "online" (not for interfaces with `initial_state=offline`).

### 5.6 `usr/sbin/mwan3` (CLI)

User-facing command-line tool. Provides `start`/`stop`/`restart`/`ifup`/`ifdown` commands plus status reporting: `interfaces`, `policies`, `connected`, `rules`, `status` (all combined), and `internal` (detailed dump).

The `use` command runs an arbitrary command bound to a specific interface using `LD_PRELOAD` with `libwrap_mwan3_sockopt.so`.

The `internal` command now shows `nft list table inet fw4` output (filtered for mwan3 chains) instead of the old iptables dump.

### 5.7 `usr/sbin/mwan3rtmon`

Route monitor daemon, reimplemented in **ucode**. Runs one instance per address family (ipv4/ipv6) as a procd service. Uses `ucode-mod-rtnl` for direct netlink access and `ucode-mod-uloop` for the event loop, eliminating all `ip` command fork+exec overhead from the original shell implementation.

Key improvements over the shell version:

- **Direct netlink route monitoring** via `rtnl.listener()` instead of `ip monitor route` piped to a shell read loop
- **Structured route data** from netlink messages instead of text parsing with sed/awk
- **O(1) per-event cost** — the refactored handler avoids per-interface ubus calls, popen subprocesses, and UCI cursor creation on each route event. Device-to-table mapping and interface state are cached and refreshed only when needed
- **Debounced connected set rebuild** — route delete events trigger a 100ms debounce timer rather than an immediate full set rebuild, coalescing bursts of route changes (e.g., during interface flap) into a single rebuild
- **Proper event loop** via `uloop.run()` instead of a shell pipe+read loop

On startup, it performs an initial synchronization: dumps the current routing table via netlink, populates the connected set, and replicates routes into active per-interface tables. It then enters the uloop event loop to process route change notifications asynchronously.

- **New route**: Adds CIDR networks to the connected set via `nft add element`, then replicates the route into active per-interface tables. Host routes (bare IPs without prefix length) are skipped as they are remote destinations.
- **Deleted route**: Schedules a debounced connected set rebuild, then removes the route from per-interface tables.

### 5.8 `usr/share/rpcd/ucode/mwan3`

ucode RPC service exposing four ubus methods under the `mwan3` object. Used by LuCI for the web interface.

Uses `nft -j` (JSON output mode) for reliable parsing instead of text scraping. Key changes from the iptables version:

- **`mwan3.status`**: Returns JSON data for interfaces, connected networks, and policies.
  - **Connected IPs**: Parses `nft -j list set inet fw4 mwan3_connected_v4/v6`. Handles JSON element types: plain strings, prefix objects (`{prefix: {addr, len}}`), and range objects.
  - **Policies**: Reads policy membership from UCI config and cross-references with mwan3track `STATUS` files to determine which metric tier is active and the traffic share for each member. Every member is always reported — 100% for a sole active member, proportional share for equal-priority active members, 0% for standby or offline members. (Earlier revisions enumerated live nft policy chains instead, which made standby members invisible.)
  - **Interfaces**: Reads interface status from `/var/run/mwan3track/` status files and queries procd/netifd via ubus. Tracking IPs are discovered by globbing the `TRACK_*` files that mwan3track writes (covering both UCI-configured IPs and the dynamically added gateway IP when `track_gateway=1`). Per-IP `latency` and `packetloss` fields are populated when `check_quality=1`. The `check_quality` field is derived from the presence and content of `LATENCY_*` files (not UCI) so it reflects actual mwan3track runtime state rather than config. A `check_quality` field is returned per interface so the UI can suppress latency/loss display when quality checking is disabled.
- **`mwan3.nftset_members { set: "<name>" }`**: Returns the current members of a named nft set in `table inet fw4`. The set name is validated against `^[a-zA-Z0-9_-]+$`. Used by the Simulator tab for ipset rule matching and connected-network bypass detection via `mwan3_connected_v4`/`mwan3_connected_v6`.
- **`mwan3.routing_health {}`**: Compares UCI configuration against live kernel state. For each configured interface, checks ip rules at priorities `IIF_BASE + N` (iif lookup) and `FWMARK_BASE + N` (fwmark lookup), and checks routing table N for a default route. Reads mwan3track `STATUS` files and reports stale ip rules (rules in mwan3's priority range with no matching UCI interface). Built-in blackhole and unreachable rules are excluded from stale detection. IPv6 ip rules are checked separately from IPv4. Used by the Routing Health diagnostic tab.
- **`mwan3.nftset_info {}`**: Returns the name and address-family type (`ipv4_addr`/`ipv6_addr`) of all non-mwan3 sets in `table inet fw4`. Used by the rule editor UI to annotate the nftset dropdown and validate family consistency.

### 5.9 `Makefile`

Package build recipe. Key dependency changes:

| Old Dependency | New Dependency |
|---|---|
| `+ipset` | `+kmod-nft-core` |
| `+iptables` | `+nftables-json` |
| `+IPV6:ip6tables` | `+ucode` |
| `+iptables-mod-conntrack-extra` | `+ucode-mod-rtnl` |
| `+iptables-mod-ipopt` | `+ucode-mod-uloop` |
| | `+ucode-mod-uci` |
| | `+ucode-mod-ubus` |
| | `+ucode-mod-fs` |

The ucode dependencies are required by the reimplemented `mwan3rtmon` route monitor daemon.

Also installs:

- `10-mwan3.nft` to `$(1)/usr/share/nftables.d/table-post/`
- `mwan3-fw-include.sh` and `mwan3-fw-rebuild.sh` to `$(1)/lib/mwan3/`
- `mwan3-firewall-include` UCI defaults to `$(1)/etc/uci-defaults/`
- `mwan3-lb-test` to `$(1)/usr/sbin/`

The `+nftables-json` package provides the `nft` binary with JSON output support, needed by the rpcd ucode module.

The `postinst` script handles migration from older versions: flushes and deletes any mwan3 chains still at `mangle - 1` priority (the v3.1.4 pbr workaround position), removes legacy `mwan3_sticky_v[46]_*` maps if present, then runs `fw4 -q reload` and `rpcd restart` to activate the updated framework.

### 5.10 `lib/mwan3/mwan3-fw-include.sh` [new]

fw4 script include. Registered in the firewall UCI config by the `mwan3-firewall-include` UCI defaults file. Called by fw4 during the "includes" phase of a firewall reload/restart, *after* fw4 has loaded its nftables ruleset.

This script checks if mwan3 is running, and if so, forks `mwan3-fw-rebuild.sh` as a background process. The forking is necessary because fw4 overrides the `config()` function in its shell environment, blocking UCI access — the rebuild script needs a clean shell to call `config_load mwan3`.

### 5.11 `lib/mwan3/mwan3-fw-rebuild.sh` [new]

Performs the actual mwan3 rule rebuild after fw4 reload. Called as a background process from `mwan3-fw-include.sh`. Acquires a procd lock, then:

1. Checks if rules are actually missing (chain exists but empty)
2. Rebuilds connected and custom sets
3. Repopulates hook chain rules via `mwan3_set_general_nft()`
4. Rebuilds all interface chains via `mwan3_rebuild_iface_nft()`
5. Rebuilds policy chains
6. Rebuilds user rules
7. Calls `mwan3_dnsmasq_hup()` to clear the dnsmasq DNS cache

> [!NOTE]
> **Why both hotplug and fw4 include?** The hotplug script (`25-mwan3`) handles recovery when fw4 reloads in response to interface events (since `20-firewall` calls `fw4 -q reload` on ifup/ifupdate). The fw4 script include handles recovery when the firewall is manually restarted via `/etc/init.d/firewall restart` or `fw4 reload` without an interface event. Together they cover all fw4 reload scenarios.

### 5.12 `etc/uci-defaults/mwan3-firewall-include` [new]

UCI defaults script that runs once at first boot (or package install). Registers `/lib/mwan3/mwan3-fw-include.sh` as an fw4 script include in the firewall UCI config:

```
firewall.mwan3_reload=include
firewall.mwan3_reload.type=script
firewall.mwan3_reload.path=/lib/mwan3/mwan3-fw-include.sh
firewall.mwan3_reload.fw4_compatible=1
```

### 5.13 `usr/sbin/mwan3track`

Interface health probe daemon. One procd service instance is launched per enabled mwan3 interface that has tracking IPs configured. Runs as a shell script; unchanged from the iptables version except for the addition of `track_gateway` and `check_quality` support.

#### Probe methods

Configured via the `track_method` UCI option. Supported values: `ping` (default), `arping`, `httping`, `nping-tcp`/`nping-udp`/etc., `nslookup`. All probes are wrapped via `LD_PRELOAD` with `libwrap_mwan3_sockopt.so` (the `WRAP` helper), which intercepts `setsockopt` to set `SO_BINDTODEVICE` on the probe socket. This binds the probe to the physical interface device regardless of mwan3 routing marks, ensuring the probe exits on the correct WAN.

#### Score-based hysteresis

mwan3track maintains a score counter for each interface:

- Each probe round: if `host_up_count >= reliability` (enough IPs responded), score increments; otherwise score decrements.
- When score reaches `up` threshold from below: fires `connected` hotplug event.
- When score reaches `up` threshold from above (on decline): fires `disconnecting` then `disconnected` hotplug events.
- Score is clamped between 0 and `down + up`.

Once the reliability threshold is met in a round, remaining unprobed IPs are marked `skipped` — they are not probed further that round.

#### Status files

Written to `$MWAN3TRACK_STATUS_DIR/<iface>/` (default `/var/run/mwan3track/<iface>/`):

| File | Content |
|---|---|
| `STATUS` | Current state: `online`, `offline`, `connecting`, `disconnecting`, `disabled` |
| `SCORE` | Current score counter |
| `TURN` | Number of probe rounds completed |
| `LOST`, `ONLINE`, `OFFLINE`, `TIME` | Loss count, uptime timestamps |
| `TRACK_<ip>` | Per-IP probe result: `up`, `down`, or `skipped`. With `check_quality=1`: `latency loss` values instead of status strings. |
| `GATEWAY` | Gateway IP written by `mwan3_update_peer_track_ip()` when `track_gateway=1`. Read by `mwan3_load_track_ips()` and prepended to the probe list. |

#### check_quality

When `check_quality=1`, probes capture latency (ms) and packet loss (%) per IP. Three-state evaluation: fail (`loss >= failure_loss` OR `latency >= failure_latency`), pass (`loss <= recovery_loss` AND `latency <= recovery_latency`), grey zone (neither — probe result neither increments nor decrements score). Default thresholds (1000ms/500ms/40%/10%) are conservative, suited for monitoring without frequent false failovers.

#### Signal handling

procd sends `SIGUSR1` (ifdown event) and `SIGUSR2` (ifup event) to trigger immediate state transitions without waiting for the next probe interval.

### 5.14 `usr/sbin/mwan3-lb-test`

Load balancing distribution verifier. Usage: `mwan3-lb-test [-6] <policy_name> [ip1 ip2 ...]`

Verifies that numgen-based load balancing produces the expected traffic distribution across policy members. Key design:

- **Iteration count** (`NITER`): computed from member weights as `base_N = total_weight / GCD(weights)`, `NITER = base_N * ceil(30 / base_N)`. Ensures per-member expected counts are whole numbers and `NITER >= 30` always.
- **Test rule**: inserts a temporary ICMP-only rule into `mwan3_rules` matching a nft address set. Using ICMP prevents TCP/UDP traffic to the same IPs (DNS forwarders, Android clients bypassing local DNS, etc.) from contaminating the counter.
- **Destination pool**: well-known public IPs. Excludes any IPs already configured as mwan3 `track_ip` values — mwan3track pings those via `mwan3_output -> mwan3_rules`, which would match the test rule and inflate counts.
- **IPv6 mode** (`-6`): uses `meta l4proto ipv6-icmp ip6 daddr @set`, `ping6`, and a separate pool of well-known public IPv6 IPs.
- **IP overrides**: `mwan3-lb-test <policy> ip1 ip2 ...` for sites where defaults are unreachable or fully tracked.
- **Cleanup**: removes test set and rule on exit (normal, SIGINT, SIGTERM, SIGPIPE). Startup sweep removes any stale `mwan3_lb_test_*` sets and rules left by aborted prior runs.

See [§15.7](#157-mwan3-lb-test-load-balancing-distribution-verifier) for context on why this tool was added and the numgen contamination issues it was designed to detect.

---

## 6. Function Reference

### 6.1 common.sh Functions

| Function | Purpose |
|---|---|
| `LOG facility message...` | Logs to syslog. Suppresses `debug` level by default. |
| `mwan3_nft_exec args...` | Runs `nft` with arguments, logs errors. Returns 1 on failure. |
| `mwan3_nft_batch_start` | Creates/truncates `/tmp/mwan3_nft_batch`. |
| `mwan3_nft_push line` | Appends a line to the batch file. |
| `mwan3_nft_batch_commit` | Executes `nft -f /tmp/mwan3_nft_batch`, logs errors, removes temp file. |
| `mwan3_nft_mark_expr value mask` | Outputs `meta mark set meta mark & COMPLEMENT \| VALUE`. Uses `&` and `\|` symbols (not keywords). Equivalent to iptables `--set-xmark VALUE/MASK`. |
| `mwan3_ensure_nft_framework` | Deletes all 6 mwan3 sets (to clear stale flags), then batch-creates sets with `interval` + `auto-merge` flags and all 8 skeleton chains (including `mwan3_postrouting`). Idempotent for chains (`add chain` is a no-op on existing chains). Called from `start_service()`. |
| `mwan3_build_or_chains_nft` | Builds the 126 per-mark setter chains used by non-destructive vmap-dispatch save/restore (63 `mwan3_or_meta_<imm>` + 63 `mwan3_or_ct_<imm>` chains, each containing one OR-immediate rule and a return). Always flushes and re-populates chain bodies — never returns early on existence alone. Called from `mwan3_set_general_nft()`. See [§2 Connmark Operations](#connmark-operations). |
| `mwan3_or_vmap_body reg mark...` | Builds the body string for a vmap statement that dispatches on masked mark values into the OR-immediate setter chains. `reg` is `meta` or `ct`; remaining args are the mark values to include. Outputs `0x100 : jump mwan3_or_meta_0x100, 0x200 : jump mwan3_or_meta_0x200, ...` for inline use in nft rules. Called by `mwan3_set_general_nft()` when constructing the connmark restore and save vmap statements. |
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
| `mwan3_set_dynamic_sets` | Flushes dynamic sets (they start empty; populated externally). |

> [!NOTE]
> **Why are connected functions self-contained?** `mwan3_set_connected_ipv4/ipv6` each manage their own batch because they are called standalone from `mwan3rtmon` on route-delete events, not just from the combined `mwan3_set_connected_sets()`.

### 6.3 General Rule Setup

| Function | Purpose |
|---|---|
| `mwan3_set_general_rules` | Adds `ip rule` entries for blackhole and unreachable marks (both IPv4 and IPv6). These are ip policy rules, not nftables rules — unchanged from the iptables version. |
| `mwan3_set_general_nft` | Builds the per-mark OR setter chains via `mwan3_build_or_chains_nft()`, flushes `mwan3_postrouting`, then populates all hook chain rules: IPv6 RA bypass, `fib daddr type local return` (prerouting), `ct direction reply return` (output), vmap-dispatched connmark restore/save, jumps to ifaces_in/custom/connected/dynamic/rules chains, and post-rules connected re-check. Idempotent: checks if rules already exist before adding. Uses a single batch for all operations. |

#### Rules added by `mwan3_set_general_nft()`

For each of connected/custom/dynamic chains, adds mark-setting rules that match against the corresponding sets and apply `MMX_DEFAULT`.

For the prerouting and output hook chains, adds (in order):

1. [prerouting only] IPv6 RA bypass (accept ICMPv6 types: nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect)
2. [prerouting only] `fib daddr type local return` — packets destined for the router's own IP return immediately. Prevents inbound internet traffic (port scans, probes) from reaching the policy chain and advancing numgen counters pointlessly. See [§c4bcd951e](#mwan3-fix-numgen-counter-contamination-from-inbound-and-reply-traffic).
3. [output only] `ct direction reply return` — reply-direction packets (ICMP echo replies, TCP responses to inbound connections) return immediately. These lack an mwan3 ct mark because their conntrack entries were never processed by prerouting (the `fib` return bypassed that path), so restoring from ct mark would find zero and let them fall through to the policy chain. See [§c4bcd951e](#mwan3-fix-numgen-counter-contamination-from-inbound-and-reply-traffic).
4. **Non-destructive connmark restore** (if `meta mark & MMX_MASK == 0`): `ct mark & MMX_MASK vmap { ... -> jump mwan3_or_meta_<imm> }`. The setter chains contain `meta mark set meta mark | <imm>`, so non-mwan3 bits in meta mark are preserved across the restore.
5. Jump to `mwan3_ifaces_in` (if still 0)
6. Jump to custom, connected, dynamic chains (if still 0)
7. Jump to `mwan3_rules` (if still 0)
8. **Non-destructive connmark save** (always): first `ct mark set ct mark & MMX_MASK_COMPLEMENT` clears only mwan3's own bits in ct mark, then `meta mark & MMX_MASK vmap { ... -> jump mwan3_or_ct_<imm> }` ORs the new value back in. Bits in ct mark owned by other packages survive unchanged.
9. Post-rules: jump to custom/connected/dynamic again for non-default marks

See [§2 Connmark Operations](#connmark-operations) for the rationale and the kernel-limitation context.

### 6.4 Interface Management

| Function | Purpose |
|---|---|
| `mwan3_update_iface_to_table` | Populates `mwan3_iface_tbl`: a space-separated string of `name=id` pairs for all configured interfaces, where `id` is the sequential table number. Called lazily (on first use) by `mwan3_get_iface_id()`. Also called explicitly during `start_service()` to prime the cache before interface chains are created. |
| `mwan3_update_dev_to_table` | Populates `mwan3_dev_tbl_ipv4` and `mwan3_dev_tbl_ipv6`: space-separated `device=id` pairs indexed by address family. Used by `mwan3_route_line_dev()` to map a route's output device to its per-interface table ID during route replication in `mwan3_create_iface_route()`. |
| `mwan3_get_iface_id out_var iface` | Looks up `mwan3_iface_tbl` for the given interface name and writes its table ID into the named output variable. Calls `mwan3_update_iface_to_table()` on first use if the cache is empty. |
| `mwan3_create_iface_nft iface device` | Creates (or flushes) `mwan3_iface_in_<iface>` chain. Adds rules matching on `iifname` and address family: source in connected/custom/dynamic → MMX_DEFAULT; otherwise → interface mark. Adds jump from `mwan3_ifaces_in` if not already present. Also installs a per-interface `mwan3_postrouting` SNAT rule for IPv6 interfaces when the `snat6` UCI option is set. Stale `mwan3_snat_<iface>`-tagged rules from a prior incarnation are removed first. See [§15.5](#155-opt-in-ipv6-snat-via-per-interface-snat6). |
| `mwan3_rebuild_iface_nft iface` | Rebuilds a single interface's nft chain if the interface is enabled, the correct family is available, and the interface is currently up (verified via ubus). Used during fw4 reload recovery to restore all interface chains. Calls `mwan3_create_iface_nft()` after resolving the L3 device from netifd. |
| `mwan3_delete_iface_nft iface` | Removes the jump rule from `mwan3_ifaces_in` (by handle lookup), removes any `mwan3_snat_<iface>`-tagged rules from `mwan3_postrouting` (comment-tag match), then flushes and deletes the interface chain. |
| `mwan3_delete_iface_map_entries iface` | Iterates all `mwan3_sticky_v[46]_*` sets in the `inet` family, finds sets whose name ends with `_<id>` (this interface's id), and flushes them. Sets are flushed rather than deleted because rule chains may still reference the set name. |
| `mwan3_create_iface_rules iface device` | Adds `ip rule` entries: pref id+1000 (iif lookup), pref id+2000 (fwmark lookup), pref id+3000 (fwmark unreachable). *Unchanged from iptables version.* |
| `mwan3_delete_iface_rules iface` | Removes ip rules matching this interface's ID range. *Unchanged.* |
| `mwan3_create_iface_route iface device` | Copies routes from main table into the per-interface table. *Unchanged.* |
| `mwan3_delete_iface_route iface` | Flushes the per-interface routing table. *Unchanged.* |

#### Handle-Based Rule Deletion

nftables doesn't support deleting rules by match criteria (like iptables `-D chain match...`). Instead, `mwan3_delete_iface_nft()` uses:

```sh
handle=$($NFT -a list chain inet fw4 mwan3_ifaces_in | \
    grep "jump mwan3_iface_in_$1" | sed -n 's/.*# handle \([0-9]*\)/\1/p')
$NFT delete rule inet fw4 mwan3_ifaces_in handle "$handle"
```

The `-a` flag shows rule handles in comments, which can then be used for targeted deletion.

### 6.5 Policy & Load Balancing

| Function | Purpose |
|---|---|
| `mwan3_set_policy member_config` | Callback per policy member. Tracks lowest metric and accumulates online members as `iface:id:weight` tuples into `$policy_members`. Tracks offline devices into `$policy_offline_devices`. Uses caller's variables (dynamic scoping). |
| `mwan3_create_policies_nft policy` | Creates/flushes the `mwan3_policy_<name>` chain. Iterates members via `mwan3_set_policy`, then builds the chain: single member gets a direct mark-set rule; multiple members get a `numgen` rule; offline devices get out-device fallback rules; last-resort rule (unreachable/blackhole/default) is appended. |
| `mwan3_set_policies_nft` | Before creating policy chains, enumerates all existing `mwan3_policy_*` chains in `inet fw4` and deletes any whose name is not in the current UCI policy config (orphaned chain sweep — prevents stale chains accumulating after a policy is removed from UCI). Then iterates all policy configs and calls `mwan3_create_policies_nft` for each. |

### 6.6 Sticky Routing

| Function | Purpose |
|---|---|
| `mwan3_get_policy_members_for_family policy family` | Iterates the members of a policy config via `config_list_foreach`. For each member whose interface matches the requested family, resolves the interface id and computes its mark, and accumulates `<id>:<mark>` tuples into `$_policy_member_marks`. Used by the sticky path in `mwan3_set_user_nft_rule()` to enumerate per-member sets. |
| `mwan3_set_sticky_nft iface rule ipv policy` | **Unused (dead code).** Defined but never called. Inserts sticky restore/invalidate rules into `mwan3_rule_<rule>` for a single interface member. The active sticky implementation is handled inline within `mwan3_set_user_nft_rule()` using per-member address sets and OR-immediate vmap dispatch as described in [§8](#8-sticky-routing-detail). |

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

When a user rule references an `ipset` (destination nft set) or `ipset_src` (source nft set) that doesn't exist yet (e.g., a dnsmasq `nftset` that will be created when dnsmasq starts, which is later at START=60+), the batch file would fail atomically since `nft -f` rolls back the entire batch if any referenced set is missing. To prevent this, `mwan3_set_user_nft_rule()` checks for the set's existence and pre-creates it with the appropriate type if missing. The same pre-creation logic applies to both `ipset` and `ipset_src`.

### 6.8 Status Reporting

| Function | Purpose |
|---|---|
| `mwan3_report_iface_status iface` | Shows interface online/offline status with uptime. Checks ip rules, nft chain existence, and default route presence as health indicators. Uses `nft list chain inet fw4 mwan3_iface_in_<name>` instead of old `$IPT -S`. |
| `mwan3_report_policies policy` | Parses `nft list chain` output for a policy chain. Detects `numgen` for load balancing or direct mark-set for single member. |
| `mwan3_report_policies_v4/v6` | Lists all `mwan3_policy_*` chains. With inet family both are identical. |
| `mwan3_report_connected_v4/v6` | Parses `nft list set` output for connected set elements. |
| `mwan3_report_rules_v4/v6` | Parses `nft list chain inet fw4 mwan3_rules`. |
| `mwan3_mark_to_name mark` | Resolves a numeric mark value to an interface name (or "default"/"blackhole"/"unreachable") by iterating the iface-to-table mapping and computing each interface's mark. |

### 6.9 Lifecycle & Hotplug

| Function | Purpose |
|---|---|
| `mwan3_ifup iface caller` | Resolves interface status via ubus, then triggers the 25-mwan3 hotplug script with `ACTION=ifup`. When called from init, runs in background. |
| `mwan3_interface_hotplug_shutdown iface [ifdown]` | Triggers ifdown or disconnected hotplug event for an interface. |
| `mwan3_interface_shutdown iface` | Calls hotplug shutdown then cleans track state files. |
| `mwan3_set_iface_hotplug_state iface state` | Writes state (`online`/`offline`) to status file. |
| `mwan3_get_iface_hotplug_state iface` | Reads state from status file (defaults to `offline`). |
| `mwan3_flush_conntrack iface action` | Flushes conntrack if configured for this interface/action pair. On `ifdown`, also selectively flushes conntrack entries matching this interface's fwmark using the `conntrack` tool (if installed), forcing stale flows to re-establish via the updated policy immediately. |
| `mwan3_update_peer_track_ip iface` | If `track_gateway` is enabled for the interface, queries `ifstatus` for the point-to-point peer address and writes it to `$MWAN3TRACK_STATUS_DIR/<iface>/GATEWAY`. Called from `start_tracker()` and on `ifup` hotplug events. |
| `mwan3_track_clean iface` | Removes track status directory for the interface. |
| `mwan3_dnsmasq_hup` | Sends `SIGHUP` to running dnsmasq instances. Queries procd via `ubus call service list`, finds PIDs for the dnsmasq service, and signals only instances where procd reports `running: true`. Instances mid-startup are skipped to avoid the race where SIGHUP received during initialisation causes dnsmasq to exit. Uses `json_set_namespace` to protect the caller's jshn state. Called after fw4 reload recovery to clear the DNS cache and force fresh queries that re-populate nftset-based sets. |

---

## 7. Load Balancing with numgen

The iptables version used `-m statistic --mode random --probability P` to distribute traffic. This required inserting rules in specific order and computing running probabilities. The nftables version uses `numgen inc mod N map { ... }`, which is simpler and more deterministic.

### How numgen Works

`numgen inc mod N` generates a counter that increments on each packet and wraps at N. The `map { range : value }` maps counter values to marks.

```
# Example: wan (weight 3) + wanb (weight 2) = mod 5
# wan gets range 0-2 (3 values), wanb gets range 3-4 (2 values)

nft add rule inet fw4 mwan3_policy_balanced \
    meta mark & 0x3f00 == 0 \
    meta mark set numgen inc mod 5 map { 0-2 : 0x0100, 3-4 : 0x0200 }
```

> [!WARNING]
> **Kernel limitation on compound set expressions:** An earlier implementation tried `meta mark set meta mark & COMP | numgen inc mod ...` to preserve non-mwan3 bits while applying the numgen result. This fails with "Operation not supported" because the kernel cannot mix two register sources (meta mark and numgen) in one set expression. The solution is to use `meta mark set numgen ...` directly; the `meta mark & MMX_MASK == 0` guard condition ensures the mwan3 bits are already zero before the numgen result is applied.

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

An earlier implementation used a single `ipv4_addr : mark` map per rule with `meta mark set ip saddr map @mwan3_sticky_v4_https`. This is destructive: the map lookup overwrites meta mark entirely with the stored value, wiping any bits set by other packages (pbr etc.). With the vmap-dispatch infrastructure introduced in v3.2, the correct approach is a plain address set per policy member, with the mark encoded in the chain name rather than the map value. The corresponding `mwan3_or_meta_<mark>` setter chain ORs only the mwan3 bits into meta mark, preserving everything else.

### Data Structure

```
# Created per policy member for rule "https"
# (policy "balanced" has members: wan id=1 mark=0x100, wanb id=2 mark=0x200)
nft add set inet fw4 mwan3_sticky_v4_https_1 { type ipv4_addr; flags timeout; timeout 600s; }
nft add set inet fw4 mwan3_sticky_v4_https_2 { type ipv4_addr; flags timeout; timeout 600s; }
```

One set per policy member, per rule, per address family. Sets hold source addresses only (no value side). The mark to apply is encoded in which set the saddr is found in.

### Rule Chain Structure (for sticky rule "https", policy "balanced", wan=id1 wanb=id2)

```
chain mwan3_rule_https {
    # Restore: if saddr is in this member's set, OR its mark into meta mark
    # (non-destructive — pbr bits in meta mark are preserved)
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
fw4 startup
  +--> loads 10-mwan3.nft (empty sets with auto-merge + skeleton chains)

/etc/init.d/mwan3 start
  +--> mwan3_init()                    compute masks
  +--> mwan3_ensure_nft_framework()    delete/recreate sets, ensure chains
  +--> start_tracker per interface     launch mwan3track
  +--> mwan3_set_dynamic_sets()        flush dynamic sets
  +--> mwan3_set_connected_sets()      populate from routing table
  +--> mwan3_set_custom_sets()         populate from custom tables
  +--> mwan3_set_general_rules()       ip rule add blackhole/unreachable
  +--> mwan3_set_general_nft()         populate hook chain rules
  +--> mwan3_ifup per interface        trigger hotplug (creates iface chains)
  +--> wait for hotplug completion
  +--> mwan3_set_policies_nft()        create policy chains
  +--> mwan3_set_user_rules()          populate user rules chain
  +--> [if flow_offloading=1]          flush conntrack (force flow re-establishment)
  +--> start mwan3rtmon (ipv4)         route monitor (ucode)
  +--> start mwan3rtmon (ipv6)         route monitor (ucode)
```

### Interface Up (hotplug)

```
netifd signals ifup for $INTERFACE
  +--> 25-mwan3 hotplug script
       +--> [check for fw4 reload, rebuild if needed]
       +--> mwan3_update_peer_track_ip() write gateway IP (if track_gateway)
       +--> mwan3_create_iface_nft()    create/flush chain, add rules
       +--> mwan3_create_iface_rules()  ip rule add (iif, fwmark)
       +--> mwan3_set_iface_hotplug_state "online/offline"
       +--> [if not init startup:]
       |    +--> mwan3_create_iface_route()  copy routes to per-iface table
       |    +--> mwan3_set_general_rules()   ensure ip rules exist
       |    +--> [if online:] mwan3_set_policies_nft()  rebuild policy chains
       +--> procd_send_signal track_$INTERFACE USR2
```

### Interface Down (hotplug)

```
netifd signals ifdown for $INTERFACE
  +--> 25-mwan3 hotplug script
       +--> mwan3_set_iface_hotplug_state "offline"
       +--> mwan3_flush_conntrack()            flush conntrack entries for this iface's fwmark
       +--> mwan3_delete_iface_map_entries()  flush sticky sets for this iface
       +--> mwan3_delete_iface_rules()        ip rule del
       +--> mwan3_delete_iface_route()        ip route flush table
       +--> mwan3_delete_iface_nft()          remove chain + jump rule
       +--> procd_send_signal track_$INTERFACE USR1
       +--> mwan3_set_policies_nft()          rebuild policies (failover)
```

### Stop

```
/etc/init.d/mwan3 stop
  +--> mwan3_interface_shutdown per interface   trigger ifdown hotplug
  +--> flush ip routing tables (1..MWAN3_INTERFACE_MAX)
  +--> delete ip rules in 1000-3999 range
  +--> flush ALL mwan3_* chains (remove rules)
  +--> delete dynamic chains (keep skeleton chains from .nft file)
  +--> final safety flush of skeleton chains
  +--> flush ALL mwan3_* sets
  +--> flush sticky sets
  +--> rm -rf status dirs

Result: skeleton chains and empty sets remain (harmless).
        Removed on fw4 restart or package removal.
```

---

## 10. fw4 Reload Recovery

This section documents the mechanisms that handle fw4 reload events, which would otherwise destroy all mwan3 dynamic rules.

### The Problem

fw4 reload (triggered by `/etc/init.d/firewall restart`, `fw4 reload`, or the `20-firewall` hotplug script on ifup/ifupdate events for interfaces in firewall zones) flushes the **entire** `table inet fw4` and recreates it from scratch. Only the static skeleton from `10-mwan3.nft` survives (empty chains and sets with correct types/flags), but all dynamically-added rules, interface chains, policy chains, set contents, and the 126 vmap-dispatch OR setter chains are lost. Any IPv6 SNAT rules in `mwan3_postrouting` are also wiped. The recovery path rebuilds all of these by calling the same code paths used at initial start.

### Detection Mechanism

Both recovery paths use the same detection: check if `mwan3_prerouting` contains any `meta mark` rules. If the chain exists but has no rules (empty skeleton), a fw4 reload has occurred and rebuilding is needed.

```sh
$NFT list chain inet fw4 mwan3_prerouting 2>/dev/null | grep -q "meta mark"
```

### Recovery Path 1: Hotplug Script (25-mwan3)

When fw4 reloads in response to an interface event, the `20-firewall` hotplug script runs first (at position 20), calling `fw4 -q reload`. The mwan3 hotplug script at position 25 runs immediately after and detects the empty state:

```
Interface event (ifup/ifupdate)
  +--> 20-firewall hotplug: fw4 -q reload (wipes everything)
  +--> 25-mwan3 hotplug: detects empty mwan3_prerouting
       +--> mwan3_set_connected_sets()           rebuild connected sets
       +--> mwan3_set_custom_sets()              rebuild custom sets
       +--> mwan3_set_general_nft()              rebuild hook chain rules
       +--> config_foreach mwan3_rebuild_iface_nft interface
       |    (iterates all interfaces, checks ubus for up/device, rebuilds nft chains)
       +--> mwan3_set_policies_nft()             rebuild policy chains
       +--> mwan3_set_user_rules()               rebuild user rules
       +--> mwan3_dnsmasq_hup()                  clear DNS cache to re-populate nft sets
```

### Recovery Path 2: fw4 Script Include (mwan3-fw-include.sh)

When the firewall is manually restarted (`/etc/init.d/firewall restart`) without an interface event, there is no hotplug trigger. Instead, the fw4 script include mechanism handles recovery:

```
Manual firewall restart
  +--> fw4 loads nftables ruleset (including 10-mwan3.nft skeleton)
  +--> fw4 runs script includes
       +--> mwan3-fw-include.sh
            +--> checks if mwan3 is running
            +--> forks mwan3-fw-rebuild.sh as background process
                 +--> checks if rules are actually missing
                 +--> acquires procd lock
                 +--> same rebuild sequence as hotplug path
                 +--> mwan3_dnsmasq_hup()
```

> [!NOTE]
> **Why fork?** The fw4 script include runs inside fw4's shell environment, which overrides the `config()` function to block UCI access. `mwan3-fw-rebuild.sh` runs as a separate process with a clean shell, allowing it to call `config_load mwan3` normally.

### dnsmasq nftset Recovery

When fw4 reloads, it also destroys any nft sets populated by dnsmasq (via the `nftset` option). These sets are dynamically populated as DNS queries arrive. The rebuild process calls `mwan3_dnsmasq_hup()` to send `SIGHUP` to running dnsmasq instances, clearing the DNS cache and forcing fresh upstream resolution on next client queries, thereby re-populating the nft sets. Only instances that procd reports as fully running are signalled — instances mid-startup are skipped to avoid the race where a SIGHUP received during dnsmasq initialisation causes it to exit. User rules that reference external nft sets also pre-create them if missing (see [Section 6.7](#67-user-rules)).

---

## 11. Unchanged Files

| File | Reason |
|---|---|
| `etc/hotplug.d/iface/26-mwan3-user` | Just calls `/etc/mwan3.user`, no firewall code |
| `etc/config/mwan3` | UCI schema is firewall-agnostic |
| `etc/mwan3.user` | User script template, no firewall code |
| `etc/uci-defaults/mwan3-migrate-flush_conntrack` | UCI migration, no firewall code |

---

## 12. Diagnostic Commands

```sh
# List all mwan3 chains with their rules
nft list table inet fw4 | grep -A 50 'chain mwan3_'

# List specific chain
nft list chain inet fw4 mwan3_prerouting
nft list chain inet fw4 mwan3_output
nft list chain inet fw4 mwan3_postrouting
nft list chain inet fw4 mwan3_ifaces_in
nft list chain inet fw4 mwan3_policy_balanced

# Check set contents
nft list set inet fw4 mwan3_connected_v4
nft list set inet fw4 mwan3_connected_v6
nft list set inet fw4 mwan3_custom_v4
nft list set inet fw4 mwan3_dynamic_v4

# Check sticky set entries (per-member sets, id suffix = interface id)
nft list set inet fw4 mwan3_sticky_v4_https_1
nft list set inet fw4 mwan3_sticky_v6_https_1
# List all sticky sets for a rule
nft list sets inet fw4 | grep mwan3_sticky_v4_https

# List all mwan3 chains (names only)
# Note: nft list chains only accepts an optional family, not a table name
nft list chains inet | grep mwan3_

# List OR-immediate setter chains (vmap dispatch, v3.2+)
nft list chains inet | grep mwan3_or_

# List all mwan3 sets (names only)
nft list sets inet fw4 | grep mwan3_

# List all mwan3 maps
nft list maps inet fw4 | grep mwan3_

# Verify marks are being set (add temporary counter)
nft add rule inet fw4 mwan3_prerouting meta mark and 0x3f00 != 0 counter

# Check connmarks
conntrack -L -o mark

# Check ip rules
ip rule list | grep -E '^[1-3][0-9]{3}:'

# Check per-interface routing table (table N for interface N)
ip route list table 1

# JSON output (for scripting/debugging)
nft -j list set inet fw4 mwan3_connected_v4
nft -j list chain inet fw4 mwan3_policy_balanced

# Check mwan3 status
mwan3 status
mwan3 internal

# RPC query
ubus call mwan3 status '{"section":"interfaces"}'
ubus call mwan3 status '{"section":"connected"}'
ubus call mwan3 status '{"section":"policies"}'

# Verify fw4 include is registered
uci show firewall.mwan3_reload

# Test fw4 reload recovery
/etc/init.d/firewall restart
# then check: nft list chain inet fw4 mwan3_prerouting
# should show rules within a few seconds
```

---

## 13. luci-app-mwan3 Changes

The LuCI web interface application (`luci-app-mwan3`) required changes to replace ipset references with nftables equivalents, add the new `track_gateway` option, and update help text for `flush_conntrack`. The LuCI app lives in the `feeds/luci` feed, separate from the core mwan3 package.

### Changed Files

| File | Package Path |
|---|---|
| `rule.js` | `applications/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/network/rule.js` |
| `interface.js` | `applications/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/network/interface.js` |
| `luci-mwan3` | `applications/luci-app-mwan3/root/usr/libexec/luci-mwan3` |
| `luci-app-mwan3.json` | `applications/luci-app-mwan3/root/usr/share/rpcd/acl.d/luci-app-mwan3.json` |

### 13.1 `rule.js` — Rule Editor UI

The LuCI rule editor view allows users to configure mwan3 traffic classification rules. It populates dropdowns of available nft sets for the `ipset` (destination) and `ipset_src` (source) UCI options.

#### iptables-to-nftables Changes

| Aspect | Old (iptables) | New (nftables) |
|---|---|---|
| Data fetch | `fs.exec_direct('/usr/libexec/luci-mwan3', ['ipset', 'dump'])` | `ubus.call('mwan3', 'nftset_info', {})` |
| Field label | `_('IPset')` | `_('NFT set')` |
| Help text | `Name of IPset rule. Requires IPset rule in /etc/dnsmasq.conf (eg "ipset=/youtube.com/youtube")` | `Name of nft set. Requires nftset rule in /etc/dnsmasq.conf (eg "nftset=/youtube.com/4#inet#fw4#youtube")` |
| Variable names | `ipsets`, `ips` | `nftsets`, `s_name` |

> [!NOTE]
> **dnsmasq nftset syntax:** The dnsmasq `nftset` option uses a different format from the old `ipset` option. The format is `nftset=/domain/FAMILY#TABLE_FAMILY#TABLE#SET`. For example, `nftset=/youtube.com/4#inet#fw4#youtube` means: for `youtube.com` A records (family `4` = IPv4), add addresses to the set named `youtube` in `table inet fw4`.

> [!NOTE]
> **UCI option name preserved:** The underlying UCI option remains `ipset` (not renamed to `nftset`) to maintain backwards compatibility with existing configurations. The mwan3 shell code reads `config_get ipset_name "$1" ipset` regardless of the firewall backend. Only the UI labels and help text were updated to reflect the nftables terminology.

#### v3.3.1 Enhancements

**nftset dropdown via rpcd:** The nftset dropdown is now populated via the `mwan3.nftset_info` rpcd ubus method instead of the `luci-mwan3 nftset dump` helper script. Sets are annotated with `(IPv4)` or `(IPv6)` in the dropdown label based on the address-family type returned by `nftset_info`.

**Source NFT set field (`ipset_src`):** A new "Source NFT set" field is shown before the existing "Destination NFT set" field in the rule modal. It sets the `ipset_src` UCI option. Both source and destination sets can be set on the same rule and are ANDed together. The grid listing shows the nftset name in the Source or Destination column when no IP address is configured, preventing the rule from appearing as a wildcard match in the listing.

**Address family validation:** `src_ip` and `dest_ip` fields validate against the selected address family on blur - an error is shown if an IPv4 address is entered when family is set to IPv6 or vice versa. Family consistency is also validated on save: a destination nftset must match the selected family, and combining a destination nftset with `dest_ip` (or source nftset with `src_ip`) is flagged as an error since both constrain the same traffic dimension.

### 13.2 `luci-mwan3` — Helper Script

The `/usr/libexec/luci-mwan3` shell script provides backend commands called by the LuCI JavaScript frontend. The `ipset` subcommand was renamed to `nftset` and the underlying implementation changed from querying ipset to querying nftables.

#### Changes

| Aspect | Old (iptables) | New (nftables) |
|---|---|---|
| Subcommand name | `ipset` | `nftset` |
| Function name | `ipset_dump()` / `ipset_cmd()` | `nftset_dump()` / `nftset_cmd()` |
| Implementation | `ipset -n -L 2>/dev/null \| grep -v mwan3_ \| sort -u` | `nft list sets inet fw4 2>/dev/null \| awk '/^\tset / {print $2}' \| grep -v '^mwan3_' \| sort -u` |
| Help text | `dump: show all configured ipset names` | `dump: show all non-mwan3 nft set names in inet fw4` |

The `nftset_dump()` function lists all sets in `table inet fw4`, extracts set names using awk (matching lines that start with a tab followed by `set`), filters out mwan3's own internal sets (prefixed with `mwan3_`), and returns the sorted unique names.

In v3.3.1, rule.js switched from calling `luci-mwan3 nftset dump` to the `mwan3.nftset_info` rpcd ubus method. The `nftset dump` subcommand is therefore no longer called by the rule editor — it remains in the script but is effectively unused.

The `diag` subcommand and its functions (`diag_gateway`, `diag_tracking`, `diag_rules`, `diag_routes`) are unchanged — they use `ip rule`/`ip route` and the `mwan3 use` command, none of which depend on the firewall backend.

### 13.3 `luci-app-mwan3.json` — ACL Permissions

The rpcd ACL file controls which commands the LuCI frontend is permitted to execute. It contains two ACL groups with separate permission sets.

**`luci-app-mwan3`** (configuration access): The `read.file` exec entry was updated to match the renamed subcommand:

| Old | New |
|---|---|
| `"/usr/libexec/luci-mwan3 ipset dump": ["exec"]` | `"/usr/libexec/luci-mwan3 nftset dump": ["exec"]` |

In v3.3.1, rule.js switched from calling the helper script via `fs.exec_direct('/usr/libexec/luci-mwan3', ['nftset', 'dump'])` to the `mwan3.nftset_info` rpcd ubus method. The `read.file` exec entry for `luci-mwan3 nftset dump` is therefore no longer exercised by the rule editor. It is retained in the ACL file for compatibility but is effectively obsolete.

The `read.ubus` section for this group grants permission to call: `mwan3.status`, `mwan3.nftset_members` (both added in v3.3), and `mwan3.nftset_info` (added in v3.3.1 so the rule editor can query available nft sets with address-family annotations).

**`luci-app-mwan3-status`** (status/diagnostic access): The `read.ubus` section grants permission to call: `mwan3.status`, `mwan3.nftset_members`, and `mwan3.routing_health` (the last added in v3.3 for the Routing Health diagnostic tab). The `write.file` section grants exec permission for the `diag` subcommands (`diag gateway`, `diag tracking`, `diag rules`, `diag routes`), `mwan3 internal`, `mwan3 ifup`, and `mwan3 ifdown`.

### 13.4 `interface.js` — Interface Settings UI

A "Track gateway" checkbox was added to the interface configuration modal, visible only when the internet protocol is set to IPv4. This exposes the `track_gateway` UCI option for automatic point-to-point peer/gateway discovery (see [Section 15.3](#153-automatic-gateway-tracking-track_gateway)).

An "IPv6 SNAT" text field was added to the same modal, visible only when the internet protocol is set to IPv6. This exposes the `snat6` UCI option for opt-in IPv6 SNAT of mwan3-rerouted router-originated traffic (see [Section 15.5](#155-opt-in-ipv6-snat-via-per-interface-snat6)). The field accepts an empty value or `0` (default — disabled), `1` (SNAT to the interface's primary global address resolved via `mwan3_get_src_ip`), or a literal IPv6 address (NPTv6-style fixed-source pinning).

The help text for the `flush_conntrack` option was also updated to clarify that it flushes the entire global conntrack table, and that per-interface conntrack entries are now flushed automatically on ifdown (see [Section 15.1](#151-selective-conntrack-flush-on-interface-down)).

---

## 14. Iptables-to-nftables Porting Notes

Key translation patterns used in this port, useful for anyone maintaining or extending the code:

| iptables Concept | nftables Equivalent | Notes |
|---|---|---|
| `iptables -t mangle` | Chains in `table inet fw4` | No separate mangle table; use own chains at mangle priority |
| `-A PREROUTING -j chain` | Own hook chain at `priority mangle + 1` | No need to jump from fw4's chain |
| `-A OUTPUT -j chain` | Own `type route` hook chain | Must be `type route` for mark-based rerouting |
| `iptables-restore -T mangle -n` | `nft -f batchfile` | Batch file for atomic multi-command operations |
| `-N chain` | `nft add chain inet fw4 name` | |
| `-F chain` | `nft flush chain inet fw4 name` | |
| `-X chain` | `nft delete chain inet fw4 name` | Must be empty first |
| `-D chain match...` | `nft delete rule ... handle N` | Must look up handle with `nft -a` |
| `-j MARK --set-xmark V/M` | `meta mark set meta mark & ~M \| V` | See `mwan3_nft_mark_expr()`; use `&`/`\|` symbols not keywords |
| `-j CONNMARK --restore-mark --nfmask M` | vmap-dispatch into `mwan3_or_meta_<imm>` setter chains | Non-destructive masked restore. Kernel rejects the compound `(meta mark & ~M) \| (ct mark & M)`; vmap-dispatch synthesises the same effect via per-mark OR-immediate setter chains. See [§2 Connmark Operations](#connmark-operations). |
| `-j CONNMARK --save-mark --nfmask M` | `ct mark set ct mark & ~M`, then vmap-dispatch into `mwan3_or_ct_<imm>` setter chains | Non-destructive masked save. Same kernel limitation, same vmap-dispatch workaround in the opposite direction. |
| `-m mark --mark V/M` | `meta mark & M == V` | |
| `-m set --match-set S dst` | `ip daddr @S` | |
| `-m statistic --probability P` | `numgen inc mod N map { ... }` | Deterministic round-robin instead of probabilistic |
| `-m multiport --dports P` | `th dport { P1, P2 }` | `th` = transport header (works for tcp/udp) |
| `-m icmp6 --icmpv6-type T` | `icmpv6 type { T1, T2, ... }` | |
| `-p ipv6-icmp` | `icmpv6 type { ... }` | Protocol match is implicit |
| `ipset create S hash:net` | `set S { type ipv4_addr; flags interval; auto-merge; }` | Defined in static .nft file; `auto-merge` handles overlapping elements |
| `ipset add S element` | `nft add element inet fw4 S { element }` | |
| `ipset flush S` | `nft flush set inet fw4 S` | |
| `ipset create S hash:ip,mark` | `map S { type addr : mark; flags dynamic,timeout; }` | Maps store key→value pairs |
| `-j SET --add-set S src,src` | `update @S { ip saddr : meta mark & M }` | |
| `-m set --match-set S src,src` | `meta mark set ip saddr map @S` | Regular map lookup (not `vmap` which requires verdicts) |
| Separate ipv4/ipv6 chains | Single `inet` chain + `meta nfproto` | Or just `ip`/`ip6` selectors in rules |

> [!WARNING]
> **Key kernel limitations to be aware of:**
>
> - **No compound two-source bitwise:** Expressions like `meta mark set meta mark | ct mark & X` or `ct mark set ct mark & ~M | meta mark & M` fail with "Operation not supported". Each set expression can only draw from one register source. **Workaround:** synthesise the masked operation via `vmap`-dispatch into per-mark setter chains whose body is a single-source `meta/ct mark | <constant immediate>`. mwan3 uses this for masked connmark save and restore — see [§2 Connmark Operations](#connmark-operations).
> - **No numgen in compound expressions:** `meta mark set meta mark & COMP | numgen inc mod N map { ... }` fails for the same reason. Use `meta mark set numgen ...` with a guard condition ensuring the target bits are already zero.
> - **vmap vs map:** `vmap` expects verdict values (accept/drop/jump), not data values like marks. For IP→mark lookups, use regular `map`.
> - **`nft add set` flag immutability:** Creating a set is idempotent, but flags (like `auto-merge`) cannot be updated on existing sets. Must delete and recreate to change flags.

---

## 15. Enhancements

The following enhancements were made after the initial nftables port, building on the new architecture.

### 15.1 Selective Conntrack Flush on Interface Down

**Problem:** When a WAN interface fails, mwan3track detects the failure and triggers an ifdown event. The policies are rebuilt to exclude the failed interface, but existing conntrack entries still carry the old interface's fwmark. TCP flows on the failed WAN wait for retransmit timeout (typically 15-30 seconds) before re-establishing via the updated policy. The existing UCI `flush_conntrack` mechanism flushes the *entire* global conntrack table, which is disruptive to all connections including those on healthy WANs.

**Solution:** On ifdown, `mwan3_flush_conntrack()` now uses the `conntrack` tool to selectively delete only the conntrack entries matching the failed interface's fwmark:

```sh
conntrack -D --mark "${iface_mark}/${MMX_MASK}"
```

This forces only the flows that were using the failed WAN to immediately re-establish via the updated policy, while leaving connections on healthy interfaces untouched. The feature requires the `conntrack-tools` package and falls back gracefully (no-op) if it is not installed.

> [!NOTE]
> This is independent of the UCI `flush_conntrack` option. The selective flush always runs on ifdown when conntrack-tools is available, regardless of the UCI setting. The UCI option continues to control the legacy behaviour of flushing the entire conntrack table on specific events.

**Files changed:** `lib/mwan3/mwan3.sh` (`mwan3_flush_conntrack()`)

### 15.2 Software Flow Offloading Co-existence

**Problem:** When fw4 software flow offloading (`option flow_offloading '1'`) is active, the kernel's flowtable caches routing decisions for established flows. These flowtable entries bypass mwan3's PREROUTING chains entirely, so when mwan3 rules/policies change (e.g., on `start_service` or reload), existing offloaded flows continue using stale routing decisions until they naturally expire.

**Solution:** At the end of `start_service()`, after all nft rules and policies are in place, mwan3 checks whether software flow offloading is enabled. If so, it flushes all conntrack entries by writing to `/proc/net/nf_conntrack`:

```sh
echo f > /proc/net/nf_conntrack
```

This destroys the flowtable entries, forcing all flows to re-enter the normal packet path where they are classified by the new mwan3 rules. The flush occurs only at service start/reload, not on every interface event.

> [!NOTE]
> This does not apply to hardware flow offloading, which uses different kernel mechanisms. Hardware offloaded flows are not affected by conntrack flushes.

**Files changed:** `etc/init.d/mwan3` (`start_service()`)

### 15.3 Automatic Gateway Tracking (`track_gateway`)

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

### 15.4 Postrouting SNAT for Rerouted Router-Originated Traffic (IPv4)

**Problem:** When the router itself originates an IPv4 packet, the kernel binds the source address at `sendto()` time using the *unmarked* initial route lookup. mwan3's mark is not set at that point, so the kernel picks the saddr corresponding to whichever WAN the unmarked default route points at — call it WAN-A. Later in the egress path, `mwan3_output` sets a mark and (because the chain is `type route`) the kernel performs a re-lookup that may move the outgoing interface to WAN-B. The reroute updates `oif` but does *not* rewrite the source address — that was already set. The packet would leave WAN-B with WAN-A's source address and be dropped upstream by BCP38 / uRPF filtering.

mwan3track is unaffected: it sets `SO_BINDTODEVICE` at socket creation, which forces the correct saddr at bind time before any of this happens.

**Why no explicit SNAT is needed for IPv4:** fw4's `srcnat_wan` masquerade applies to all outgoing traffic, including locally-originated. When a rerouted packet reaches the `srcnat` hook, masquerade picks the primary IP of the actual outgoing interface and rewrites the source address correctly. No per-interface SNAT rule is required from mwan3 — fw4 handles it.

The IPv6 case is different because fw4 does not masquerade IPv6 by default. See [§15.5](#155-opt-in-ipv6-snat-via-per-interface-snat6).

### 15.5 Opt-in IPv6 SNAT via Per-Interface `snat6`

**Problem:** The router-originated, mark-rerouted, wrong-saddr failure mode described in §15.4 also exists for IPv6, but fw4 provides no masquerade fallback for IPv6. The iptables version of mwan3 also did not address it. A packet whose saddr was bound to WAN-A's prefix but rerouted onto WAN-B will egress with WAN-A's source prefix and be dropped upstream by BCP38/uRPF.

- IPv6 has no equivalent of fw4's IPv4 masquerade, so unlike the IPv4 case there is no automatic safety net.

**Why a default-on fix is wrong for v6:** Several reasons make blanket NAT66 a bad default:

1. **RFC 6724 source-address selection sometimes solves it without NAT.** A host with multiple v6 addresses configured and source-address-dependent routes (SADR) in the routing table can pick the correct saddr at socket-bind time and the problem never arises. A default-on SNAT would silently mask working RFC 6724 / SADR machinery and degrade deployments that were doing v6 multihoming correctly.
2. **NAT66 is actively harmful in some topologies.** ULA + delegated-PA designs depend on end-to-end addressing. Address-embedding protocols (SIP, FTP, IPsec keying, anything using referrals) break.
3. **Some upstreams require a specific source.** Tunnel brokers (Hurricane Electric), fixed-address WireGuard endpoints, and similar links only accept packets from a specific saddr.
4. **RFC 4864 / RFC 6296 stance.** The IPv6 community treats address translation as a deliberate, opt-in choice — never a default.

**Solution:** Version 3.2 introduces an opt-in per-interface UCI option `snat6`. The semantics are:

| value | meaning |
|---|---|
| unset / `0` | no v6 SNAT — current default behaviour, preserves the iptables-era v6 baseline |
| `1` | SNAT to the interface's primary global address, looked up via `mwan3_get_src_ip` (which already handles ipv6 family with prefix-delegation fallback) |
| `<v6 addr>` | SNAT to the literal address. Used for NPTv6-style fixed mappings or where the operator wants to pin a specific source from a delegated /64. The literal value is not validated against the device — some deployments deliberately use addresses not configured on the egress interface. |

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

The corresponding LuCI control is described in [§13.4](#134-interfacejs--interface-settings-ui).

#### Scope of this enhancement

`snat6` only addresses the router-originated rerouted case (`fib saddr type local`). It does **not** extend mwan3's IPv6 capability beyond what the iptables version offered. A more complete v6 multihoming story (forwarded LAN traffic, dual-PA + SADR integration, NPTv6 prefix translation, PD renewal handling) is intentionally out of scope for this release.

**Files changed:** `lib/mwan3/mwan3.sh` (`mwan3_create_iface_nft()`), `applications/luci-app-mwan3/.../interface.js` (LuCI form field).

---

### 15.6 Diagnostic Tabs: Simulator, Configuration Checker, and Routing Health

**Problem:** mwan3's routing model - ip rules, fwmark values, routing tables, and nft sets - is opaque to users who did not build it themselves. When traffic takes an unexpected path, or when a configuration change silently breaks policy routing, a non-expert user has no way to understand why without knowing which tools to run and how to interpret their output. Three diagnostic tabs were added to luci-app-mwan3 to close this gap.

---

#### 15.6.1 Traffic Path Simulator

**Location:** Network > MultiWAN Manager > Simulator

The Simulator tab lets the user describe a packet (source IP, destination IP, protocol, ports, address family) and see which mwan3 rule would match it first, what policy that rule assigns, and the live state of the policy's members at the moment of simulation.

**Input semantics:** all fields are optional. A blank field acts as a constraint on the *user's packet*, not a wildcard that bypasses rule matching. Specifically, if a field is left blank and a rule has a constraint on that field, the rule will not match. This mirrors mwan3's runtime behaviour: a rule with `dest_ip 10.0.0.0/8` never matches traffic with no destination.

**Connected-network bypass:** Before the rule walk, the tab checks the destination IP against the `mwan3_connected_v4` and `mwan3_connected_v6` nft sets. If the destination falls in a directly connected subnet, a dedicated card is shown explaining that mwan3 exempts connected networks from policy routing entirely. This mirrors the kernel behaviour: the connected-network check in mwan3's nftables chains fires before any rule is evaluated.

**Matching implementation:**

- IPv4 CIDR matching uses uint32 arithmetic with `>>> 0` to maintain unsigned semantics throughout (JavaScript bitwise operators produce signed 32-bit results).
- IPv6 CIDR matching uses BigInt with `::` expansion; the mask is computed as `all_ones XOR bottom_bits` to avoid shift-by-more-than-31 issues.
- Port matching handles single ports, comma- or space-separated lists, and colon-delimited ranges (`1024:2048`).
- nft set membership for rules that use `ipset` is fetched live via the `mwan3.nftset_members` ubus method at simulation time.

**Result display:** The first matching rule is shown in a bordered card coloured green (policy has active members), red (all members offline or policy not found in UCI), or orange (terminal built-in policy). Subsequent rules that also matched but are superseded are listed in a shadowed-rules table below. If no rule matches, a muted card reports that traffic will use the main routing table.

**Files:** `htdocs/luci-static/resources/view/mwan3/network/simulator.js`

---

#### 15.6.2 Configuration Consistency Checker

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

#### 15.6.3 Routing Table Health Check

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

#### 15.6.4 New rpcd Methods

Two new methods were added to `usr/share/rpcd/ucode/mwan3` and declared in `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`.

**`mwan3.nftset_members { set: "<name>" }`**

Returns the current members of a named nft set in `table inet fw4`. The set name is validated against `^[a-zA-Z0-9_-]+$` before being passed to `nft -j list set`. Returns `{ members: [ ... ] }`. Used by the Simulator for ipset rule matching and connected-network bypass detection.

**`mwan3.routing_health {}`**

Compares the UCI configuration against live kernel state. For each mwan3 interface (by 1-based UCI order index N):

- Checks for ip rule at priority 1000+N (iif) and 2000+N (fwmark) via `ip -j rule list`
- Checks routing table N for a default route via `ip -4/-6 -j route list table N`
- Reads `/var/run/mwan3track/<ifname>/STATUS` for current online/offline state
- Reports stale ip rules (priorities in mwan3's range with no matching UCI interface)
- Reports whether mwan3 is actively running (presence of any `STATUS` file under `/var/run/mwan3track/`)

**Files changed:** `files/usr/share/rpcd/ucode/mwan3`, `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`, `root/usr/share/luci/menu.d/luci-app-mwan3.json`

---

### 15.7 mwan3-lb-test: Load Balancing Distribution Verifier

A new diagnostic tool `/usr/sbin/mwan3-lb-test` verifies that load balancing is distributing traffic across policy members in the expected proportions.

#### Usage

```
mwan3-lb-test [-6] <policy_name> [ip1 ip2 ...]
```

`-6` selects IPv6 mode. Optional IP arguments override the default destination pool.

#### Design

- **NITER computation:** The number of test iterations is computed from member weights using GCD: `base_N = total_weight / GCD(weights)`, `NITER = base_N * ceil(30 / base_N)`. This ensures per-member expected hit counts are whole numbers and that NITER is always at least 30.
- **ICMP-only test rule:** A temporary `meta l4proto icmp ip daddr @mwan3_lb_test_<policy>` counter rule is inserted into `mwan3_rules` ahead of user rules. The ICMP restriction prevents DNS queries, TCP connections, and other traffic from contaminating the count. `-6` mode uses `meta l4proto ipv6-icmp ip6 daddr @set`.
- **Tracking IP exclusion:** The default destination pool excludes IPs already configured as mwan3 `track_ip` values. mwan3track pings those IPs via `mwan3_output -> mwan3_rules`, which would match the test rule and inflate the count.
- **Cleanup:** Removes the temporary set and rule on normal exit, SIGINT, SIGTERM, and SIGPIPE. A startup sweep removes stale `mwan3_lb_test_*` sets and rules from any aborted previous run.

**Files changed:** `usr/sbin/mwan3-lb-test` (new), `Makefile`

---

### 15.8 Source NFT Set Matching (`ipset_src`)

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
ip saddr @corp_clients ip daddr @blocked_dests meta mark & MMX == 0 jump mwan3_policy_wan2_policy
```

Both `ipset_src` and `ipset` can be set on the same rule and are ANDed together. The existing `ipset` option (destination) is unchanged for backward compatibility with existing configurations.

The same pre-creation logic used for `ipset` applies to `ipset_src`: if the named set does not yet exist in `table inet fw4`, `mwan3_set_user_nft_rule()` pre-creates it with the appropriate type to prevent the nft batch from failing atomically. A present `ipset_src` is treated as an implicit family qualifier by the `meta nfproto` guard condition in `mwan3_set_user_nft_rule()`, consistent with `src_ip`, `dest_ip`, and `ipset`.

**Files changed:** `lib/mwan3/mwan3.sh`

---

*mwan3 nftables port — OpenWrt 25.12 — Updated 2026-04-13*

---

# Changelog

## Version 3.3.1

Fixes three numgen counter contamination bugs, adds the `mwan3-lb-test` load balancing verifier, fixes icmp/ipv6-icmp protocol translation for IPv6 rules, adds the `nftset_info` rpcd ubus method and `ipset_src` UCI option for source nft set matching, and updates the luci-app-mwan3 rule editor to support all new options with family consistency validation.

### mwan3: fix routing_health ip rule detection for IPv6 interfaces

`get_ip_rules()` called `ip -j rule list` (IPv4-only), making ip rules added for IPv6 interfaces via `ip -6 rule add` invisible to the routing health check. All IPv6 interface ip rules were therefore always reported as missing regardless of actual state.

Fixed by querying both `ip -4 -j rule list` and `ip -6 -j rule list` and merging the results.

**Files changed:** `files/usr/share/rpcd/ucode/mwan3`

---

### mwan3: sweep orphaned policy chains on startup

When a policy is removed from UCI config and mwan3 is restarted, the old `mwan3_policy_<name>` chain persisted in nftables because `mwan3_set_policies_nft()` only created chains it knew about from the current config. The orphaned chain consumed memory and could confuse diagnostic output.

Fixed by enumerating all `mwan3_policy_*` chains present in `inet fw4` at the start of `mwan3_set_policies_nft()` and deleting any whose name is not in the current UCI policy list before rebuilding.

**Files changed:** `files/lib/mwan3/mwan3.sh`

---

### mwan3: fix numgen counter contamination from inbound and reply traffic

Three related bugs caused `numgen inc mod N` load balancing counters to be advanced by traffic that should never reach a policy chain, producing non-strict alternation and a skewed distribution.

- Bug 1: inbound internet traffic destined for the router's own WAN IP traversed `mwan3_prerouting` with mark=0 and fell to the default policy. Fix: `fib daddr type local return` added early in `mwan3_prerouting`.
- Bug 2: router replies to inbound connections (ICMP echo replies, TCP responses) passed through `mwan3_output` with ct mark=0 and fell to the policy chain. Fix: `ct direction reply return` as the first rule in `mwan3_output`.
- Bug 3: a UCI rule with `family ipv4` or `ipv6` but no address criteria generated a bare rule with no IP version restriction, causing IPv6 replies to match IPv4-intended rules. Fix: prepend `meta nfproto ipv4/ipv6` in `mwan3_set_user_nft_rule()` when no address-based qualifier is present.

**Files changed:** `files/lib/mwan3/mwan3.sh` (`mwan3_set_general_nft()`, `mwan3_set_user_nft_rule()`)

---

### mwan3: add mwan3-lb-test load balancing distribution verifier

New `/usr/sbin/mwan3-lb-test` diagnostic tool. Inserts a temporary ICMP-only nft counter rule into the policy chain, pings destination IPs for NITER rounds, and reports per-member actual vs expected hit counts with PASS/FAIL. NITER is computed from member weights via GCD so expected counts are always whole numbers. Default destination pool excludes mwan3 tracking IPs. `-6` flag for IPv6 mode. Cleans up on exit and signals. See [§15.7](#157-mwan3-lb-test-load-balancing-distribution-verifier).

**Files changed:** `files/usr/sbin/mwan3-lb-test` (new), `Makefile`

---

### mwan3: translate icmp to ipv6-icmp for IPv6 family rules

In nftables inet tables, `meta l4proto icmp` matches protocol 1 (ICMPv4) only. A UCI rule with `proto=icmp` and `family=ipv6` previously generated `meta nfproto ipv6 meta l4proto icmp` - a contradiction that silently matched nothing. In the iptables version, separate `iptables` and `ip6tables` invocations handled this implicitly.

Fixed by translating `proto icmp` to `meta l4proto ipv6-icmp` (protocol 58) in `mwan3_set_user_nft_rule()` when `family` is `ipv6`.

**Files changed:** `files/lib/mwan3/mwan3.sh`

---

### mwan3: add nftset_info rpcd ubus method

New `mwan3.nftset_info {}` ubus method. Returns the name and address-family type of all non-mwan3 nftables sets in `table inet fw4`:

```json
{"sets": {"youtube": {"type": "ipv4_addr"}, "netflix6": {"type": "ipv6_addr"}}}
```

Used by the luci-app-mwan3 rule editor to annotate the nftset dropdown with `(IPv4)`/`(IPv6)` labels and validate family consistency.

**Files changed:** `files/usr/share/rpcd/ucode/mwan3`, `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`

---

### mwan3: add ipset_src option for source nftset matching in rules

New `ipset_src` UCI option on rule sections. Generates `ip saddr @setname` / `ip6 saddr @setname` match for source address filtering via nft sets. The existing `ipset` option (destination) is unchanged for backward compatibility. Both can be set on the same rule and are ANDed together. Same pre-creation and family handling logic as the destination set. See [§15.8](#158-source-nft-set-matching-ipset_src).

**Files changed:** `files/lib/mwan3/mwan3.sh`

---

### luci-app-mwan3: improve rule modal family consistency and nftset support

Several enhancements to the rule editor modal and grid listing:

- `src_ip` and `dest_ip` fields validate against the selected address family on blur (error shown if an IPv4 address is entered with family=IPv6 or vice versa).
- The nftset dropdown is now populated via the `mwan3.nftset_info` rpcd method. Sets are annotated with `(IPv4)` or `(IPv6)` in the dropdown label. Family consistency is validated on save.
- Combining a destination nftset with `dest_ip`, or a source nftset with `src_ip`, is flagged as an error.
- New "Source NFT set" field (`ipset_src`) shown before the existing "Destination NFT set" in the modal.
- Grid listing: Source and Destination columns now show the nftset name when no IP address is configured, preventing a rule from appearing as a wildcard match in the listing.
- `nftset_info` added to ACL ubus permissions.

**Files changed:** `htdocs/luci-static/resources/view/mwan3/network/rule.js`, `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`

---

## Version 3.3

Adds three diagnostic tabs to luci-app-mwan3 and two new rpcd ubus methods to support them.

### luci-app-mwan3: add Traffic Path Simulator tab

New tab at Network > MultiWAN Manager > Simulator. Simulates which mwan3 rule matches a described packet (source IP, destination IP, protocol, ports, address family) and shows live policy member state. Implements IPv4 and IPv6 CIDR matching, port range matching, live nft set membership queries via the new `nftset_members` ubus method, and connected-network bypass detection via the `mwan3_connected_v4`/`mwan3_connected_v6` nft sets.

### luci-app-mwan3: add Configuration Consistency Checker tab

New tab at Network > MultiWAN Manager > Configuration. Performs static analysis of the mwan3 UCI configuration without consulting live system state. Detects undefined member/policy/interface references, orphaned sections, policies with no members, all-same-interface policies (no real redundancy), and shadowed rules via IPv4 and IPv6 CIDR containment.

### luci-app-mwan3: add Routing Table Health Check tab

New tab at Status > MultiWAN Manager > Routing. Compares live kernel ip rule and routing table state against the mwan3 UCI configuration. Refreshes automatically. Per-interface cards show iif rule, fwmark rule, and routing table health with colour-coded badges. Reports stale ip rules (priorities in mwan3's range with no matching UCI interface). Includes a field reference panel explaining the ip rule priority scheme for non-expert users.

### mwan3: add nftset_members and routing_health rpcd ubus methods

`mwan3.nftset_members { set: "<name>" }` returns the current members of a named nft set in `table inet fw4`. Used by the Simulator tab for ipset rule matching and connected-network bypass detection.

`mwan3.routing_health {}` compares UCI configuration against live kernel state: checks ip rules at priorities 1000+N (iif) and 2000+N (fwmark) per interface, checks routing table N for a default route, reads mwan3track STATUS files, and reports stale ip rules. Built-in blackhole (2061) and unreachable (2062) policy rules are excluded from stale detection.

**Files changed:** `files/usr/share/rpcd/ucode/mwan3`, `root/usr/share/rpcd/acl.d/luci-app-mwan3.json`, `root/usr/share/luci/menu.d/luci-app-mwan3.json`, `htdocs/luci-static/resources/view/mwan3/network/simulator.js` (new), `htdocs/luci-static/resources/view/mwan3/network/configuration.js` (new), `htdocs/luci-static/resources/view/mwan3/status/routing.js` (new).

---

## Version 3.2.3

Adds per-IP tracking detail to the `mwan3 interfaces` CLI status output, fixes two post-v3.2.2 issues with stale tracking state files, corrects the `check_quality` display inconsistency in both the rpcd status interface and mwan3track, and extends the luci-app-mwan3 status page with improved display for down and skipped tracking IPs.

### mwan3: remove stale gateway TRACK_*/LATENCY_*/LOSS_* files on probe list rebuild

When `track_gateway=1` and the gateway IP changes (e.g. on PPPoE reconnect), `mwan3_load_track_ips()` rebuilt the probe list with the new gateway IP but left `TRACK_*`, `LATENCY_*` and `LOSS_*` files from the old gateway on disk. The rpcd status module globs all `TRACK_*` files to build the per-interface tracking IP list, so stale files from previous gateway IPs appeared alongside the current ones in `ubus call mwan3 status` output.

Fixed by scanning the interface status directory at the end of `mwan3_load_track_ips()` and deleting any `TRACK_*/LATENCY_*/LOSS_*` files for IPs not present in the current probe list. Runs on every startup and ifup event.

**File changed:** `files/usr/sbin/mwan3track`

### mwan3: fix check_quality display inconsistency when UCI is changed without restart

When `check_quality` was changed in UCI without restarting mwan3track, the rpcd status reported the new UCI value while mwan3track continued operating with the old setting. Users saw "Not enabled" for latency and loss in the LuCI status page even though measurements were still being taken, or conversely saw stale measurement values after disabling `check_quality`.

Fixed in two parts. In the rpcd ucode module, `check_quality` is now derived from `LATENCY_*` file content rather than UCI - mwan3track only writes these files when `check_quality=1`, so file presence with content is the authoritative indicator of runtime state. In mwan3track, `mwan3_load_track_ips()` now re-reads `check_quality` from current UCI config and removes any stale `LATENCY_*/LOSS_*` files when it is 0, ensuring the file-based detection also returns the correct result after a restart with `check_quality=0`.

**Files changed:** `files/usr/share/rpcd/ucode/mwan3`, `files/usr/sbin/mwan3track`

### mwan3: add per-IP tracking detail to interfaces status output

`mwan3 interfaces` and `mwan3 status` now display each tracking IP below the interface status line, showing its individual probe status and (when `check_quality=1`) latency and packet loss:

```
 interface wan is online and tracking is active
   track 8.8.4.4: up (12ms, 0% loss)
   track 8.8.8.8: down (-, 100% loss)
   track 192.168.1.1: ignored
```

The `check_quality` state is derived from `LATENCY_*` file presence rather than UCI, consistent with the rpcd status module. The kernel-internal status value `skipped` is displayed as `ignored` for consistency with the LuCI status page.

**File changed:** `files/lib/mwan3/mwan3.sh`

### luci-app-mwan3: improve tracking IP latency/loss display for down/skipped/disabled states

The Status tab tracking IP table previously showed `0ms` and `0%` for tracking IPs that were down, skipped, or on disabled interfaces. Replaced with more informative sentinel values:

- **Tracker down (`check_quality=1`):** latency shows `-`, packet loss shows the measured loss percentage
- **Skipped/ignored:** both columns show `-`
- **Interface disabled:** status shows "Disabled", both metric columns show `-`

**File changed:** `applications/luci-app-mwan3/htdocs/luci-static/resources/view/mwan3/status/detail.js`

---

## Version 3.2.2

Fixes two bugs in mwan3, corrects two incomplete behaviours in the rpcd status interface and mwan3track, and extends the luci-app-mwan3 status pages with latency and packet loss data and a visual redesign.

The most significant fix corrects a long-standing misclassification of inbound IPv6 packets when an IPv4 and IPv6 mwan3 interface share the same physical device (e.g. dual-stack PPPoE or L2TP). The catchall mark rule in each `mwan3_iface_in_*` chain lacked an address-family guard, causing the IPv4 chain to stamp IPv6 packets with the wrong interface mark. This could manifest as stalled QUIC (HTTP/3) connections - visible as gray YouTube pages or sites loading partway and stopping - on setups where IPv6 is preferred by clients. A second bug in `mwan3_delete_iface_nft` could produce nft syntax errors and `Resource busy` failures on ifdown when duplicate jump rules had accumulated.

Two further corrections address the rpcd status interface and mwan3track: gateway tracking IPs are now included in the ubus status output, and the gateway is probed first when `track_gateway=1` rather than last.

### mwan3: fix iface_in catchall misclassifying IPv6 on shared-device interfaces

The catchall rule in each `mwan3_iface_in_*` chain lacked a `meta nfproto` filter. When an IPv4 and IPv6 mwan3 interface share the same physical device (e.g. a dual-stack PPPoE or L2TP WAN), `mwan3_ifaces_in` dispatches to the IPv4 chain first. The IPv4-specific `ip saddr` bypass rules do not match IPv6 packets, but the unguarded catchall does, stamping incoming IPv6 packets with the IPv4 interface mark instead of the IPv6 mark.

The ct mark is then saved with the wrong value. Subsequent packets for that connection restore the IPv4 mark, find no matching `ip -6 rule`, and fall to the main routing table. For established TCP connections the bug is invisible because ct mark is set on the first outbound packet before any inbound packet arrives. For QUIC (UDP), conntrack entries expire after approximately 120-180 seconds of inactivity; when the server resumes first the entry has ct mark 0, the catchall fires, and the connection is disrupted - manifesting as stalled streams or a gray page on sites using HTTP/3.

Fixed by adding `meta nfproto ipv4` or `meta nfproto ipv6` to the catchall based on interface family, consistent with the protocol filters already applied to the connected/custom/dynamic bypass rules above it.

**File changed:** `files/lib/mwan3/mwan3.sh`

### mwan3: fix iface_in jump rule deletion failing with multiple handles

`mwan3_delete_iface_nft` used a single-shot handle lookup to remove the jump rule for an interface from `mwan3_ifaces_in`. If repeated fw4 reload cycles caused duplicate jump rules to accumulate, the `handle` variable received multiple space-separated values and `nft delete rule inet fw4 mwan3_ifaces_in handle "4220 4225 4230 4235"` is syntactically invalid - nft requires one handle per command. The chain delete that followed then failed with `Resource busy` since the jump rule was still present, causing the duplicate to persist into the next rebuild cycle.

Duplicate rules accumulate when an ifdown fails to clean up its jump rule and a subsequent fw4 reload + rebuild adds another copy. Fixed by replacing the single-shot lookup with a while loop using `head -n1`, matching the pattern already used for SNAT rule deletion in the same function. The loop also self-heals any pre-existing duplicates on the next ifdown.

**File changed:** `files/lib/mwan3/mwan3.sh`

### mwan3: fix rpcd status to include gateway tracking IP and restore latency/loss

`interfaces_status()` in the rpcd ucode module built the `track_ip` list from UCI `track_ip` options only. The gateway IP - added dynamically by mwan3track when `track_gateway=1` - was therefore never visible in `ubus call mwan3 status` output.

Replaced the UCI iteration with a glob scan of the `TRACK_*` status files that mwan3track actually writes, so all tracked IPs appear regardless of whether they originate from UCI config or from the dynamic gateway detection. Also corrected `get_mwan3track_status()` to treat `track_gateway=1` as an active tracking configuration rather than disabled, and restored the `latency` and `packetloss` fields to the per-IP output (populated when `check_quality=1` is configured).

**File changed:** `files/usr/share/rpcd/ucode/mwan3`

### mwan3: ping gateway IP first when track_gateway=1

`mwan3_load_track_ips()` previously appended the gateway IP to the end of the `track_ips` list. Since mwan3track stops probing once `host_up_count` reaches the reliability threshold, the gateway would be skipped whenever an earlier IP responded, defeating the purpose of tracking the gateway specifically.

The gateway IP is now prepended so it is always probed first on every round regardless of the reliability setting.

**File changed:** `files/usr/sbin/mwan3track`

### luci-app-mwan3: add latency and packet loss columns to tracking IP status table

The rpcd mwan3 status now returns `latency`, `packetloss` and `check_quality` fields per interface. The Status tab tracking IP table is extended with Latency and Packet Loss columns. When `check_quality` is disabled (the default), the columns display "Not enabled" in muted text rather than zeroed values.

**File changed:** `applications/luci-app-mwan3/.../status/detail.js`

### luci-app-mwan3: visual redesign of status cards across overview and main status page

Replaced solid alert-message background cards with bordered flex cards throughout. Interface status boxes now use a 2px border coloured to match the interface status (green/red/orange/grey) with no background fill.

`detail.js`: status box border colour matches interface status; paused tracking state changed from warning orange to muted grey; tracking IP table rows sorted by status (up first, then down, then ignored).

`overview.js`: policy section replaced with per-policy flex cards matching the interface card style; interface card borders coloured by status.

`90_mwan3.js`: main LuCI status overview page cards converted from alert-message solid backgrounds to the same bordered card style.

**Files changed:** `applications/luci-app-mwan3/.../status/detail.js`, `applications/luci-app-mwan3/.../status/overview.js`, `applications/luci-app-mwan3/.../view/status/include/90_mwan3.js`

---

## Version 3.2.1

Fixes a dnsmasq SIGHUP race that could kill dnsmasq during fw4-reload recovery, corrects policy status reporting to show all configured members with traffic share percentages, and shows the installed mwan3 package version in `mwan3 internal` output. The v3.2 postinst chain-cleanup migration was also corrected - the original v3.2 tag had the upgrade direction backwards for users coming from v3.1.4; the v3.2-1 tag has been updated.

The luci-app-mwan3 status pages have been substantially redesigned. The Overview tab now shows interface status cards in a flex layout alongside a full policies table with per-member traffic share percentages and a rules summary. The Status tab replaces the previous static cards with per-interface tracking health panels showing probe IP status, tracking mode and score. The Troubleshooting tab replaces the raw text dump with collapsible per-section panels, adds IPv6 diagnostic output alongside IPv4, and filters vmap-dispatch boilerplate from the nftables listing.

### mwan3: fix dnsmasq SIGHUP race during concurrent startup

`killall -HUP dnsmasq` sends SIGHUP to every process named dnsmasq, including instances mid-initialization. When mwan3's fw4-reload recovery hotplug (position 25) fires concurrently with anything restarting dnsmasq - for example pbr restarting dnsmasq as part of its own startup sequence - the mid-init dnsmasq receives SIGHUP before it has finished initializing and exits.

Replaced with `mwan3_dnsmasq_hup()` in `mwan3.sh`. The function queries procd via `ubus call service list`, finds instances of the dnsmasq service, and sends SIGHUP only to PIDs that procd reports as `running: true`. Instances still in the startup phase are not signalled. `json_set_namespace` is used to protect the caller's jshn state.

**Files changed:** `files/etc/hotplug.d/iface/25-mwan3`, `files/lib/mwan3/mwan3-fw-rebuild.sh`, `files/lib/mwan3/mwan3.sh`

### mwan3: fix policy status to show all members with traffic share

`mwan3_report_policies()` (shell status command) and the rpcd ucode `get_policies()` both read live nftables policy chains to determine membership. Only the actively-routing member has rules in the chain - standby members (metric 2+) have no nft rules while a metric-1 member is up, so they were invisible in both the CLI output and the LuCI overview. The rpcd function additionally returned raw nft mark hex values instead of interface names.

Both functions now read policy membership from UCI config and cross-reference with mwan3track `STATUS` files to determine which metric tier is active and the traffic share for each member. Every member is always shown: 100% for a sole active member, the load-balanced share for equal-priority active members, and 0% for standby or offline members.

**Files changed:** `files/lib/mwan3/mwan3.sh`, `files/usr/share/rpcd/ucode/mwan3`

### mwan3: show mwan3 package version in internal troubleshooting output

The `Software-Version` section of `mwan3 internal` previously showed the OpenWrt OS release string (`DISTRIB_RELEASE` from `/etc/openwrt_release`). Replaced with the installed mwan3 package version queried from apk (`apk info mwan3`), which is the version relevant for troubleshooting reports.

**File changed:** `files/usr/sbin/mwan3`

### luci-app-mwan3: redesign status pages with structured views

**Overview tab:** Replaces the previous simple interface list with a full operational view - interface status cards in a flex-wrap layout, a policies table showing every configured policy member with its current traffic share percentage, and a rules table.

**Status tab:** Replaces static interface cards with per-interface tracking health panels. Each panel shows interface name, status, tracking mode and score in a header bar, and a table of probe IPs with up/down/ignored status in coloured text indicators. Polls live via the mwan3 ubus status interface.

**Troubleshooting tab:** Replaces the raw pre-formatted text dump with collapsible sections (collapsed by default with expand arrow indicators). IPv6 diagnostic sections now appear alongside IPv4 - previously only IPv4 output was shown because the IPv6 exec permission was missing from the ACL. vmap-dispatch boilerplate chains are filtered from the nftables output and replaced with a count annotation.

**ACL:** Added `mwan3 internal ipv6` exec permission to `luci-app-mwan3.json`.

---

## Version 3.2

A substantive release. Restores iptables-equivalent non-destructive masked connmark save/restore via a new vmap-dispatch architecture, moves base-chain priority back to its original `mangle + 1` placement, and adds opt-in IPv6 SNAT via the new per-interface `snat6` UCI option. IPv4 router-originated traffic rerouted by mwan3 is handled by fw4's unguarded masquerade and requires no explicit rule.

### mwan3: rearchitect mark save/restore as non-destructive vmap-dispatch

The original nftables port translated iptables's `CONNMARK --restore-mark --nfmask $MMX_MASK` to a single-source `meta mark set ct mark & MMX_MASK`, and `CONNMARK --save-mark --nfmask $MMX_MASK` to a single-source `ct mark set meta mark`. Both forms are *destructive* — they overwrite the entire target register, including bits owned by other mark-using packages such as pbr. The kernel rejects the obvious compound forms (`(meta mark & ~M) | (ct mark & M)`) with "Operation not supported" because an nft set-statement may reference at most one runtime source register.

Version 3.1.4 worked around the resulting pbr coexistence breakage by moving mwan3's chains to `priority mangle - 1` so that mwan3 ran *before* pbr in the prerouting hook stack. That ordering papered over the symptom for one specific package but left the underlying behaviour broken — any second mark-using package would still have its bits zeroed.

Version 3.2 fixes this properly. mwan3 now synthesises masked save and restore through `vmap`-dispatch into 126 trivial per-mark setter chains (63 per direction with the default `MMX_MASK = 0x3F00`):

```
chain mwan3_or_meta_0x0100 { meta mark set meta mark | 0x0100 ; return }
chain mwan3_or_ct_0x0100   { ct   mark set ct   mark | 0x0100 ; return }
...
```

Restore looks up `ct mark & MMX_MASK` in a vmap and dispatches into the matching setter chain, which OR-s the immediate value into `meta mark` without touching any other bit. Save does the same in the opposite direction, after first clearing only mwan3's own bits in `ct mark` (`& MMX_MASK_COMPLEMENT`). The result is functionally equivalent to iptables's masked CONNMARK operations.

Because the operation is now non-destructive in both directions, mwan3's chain priority moves back to the original `mangle + 1` (the placement the iptables-era mwan3 occupied). Order-independence with pbr is now an architectural property, not a side-effect of priority ordering — verified live at `mangle + 1` with pbr at `mangle` (-150), and structurally guaranteed at any other relative ordering.

The Makefile postinst migration removes any chains created at the v3.1.4 `mangle - 1` priority on upgrade so that nft will accept the chain redeclaration at the new priority.

See [§2 Connmark Operations](#connmark-operations) for the full architectural narrative.

### mwan3: opt-in IPv6 SNAT via per-interface `snat6` UCI option

Adds the `mwan3_postrouting` base chain (`type nat hook postrouting priority srcnat - 1`) and an opt-in IPv6 SNAT path gated by a new per-interface UCI option `snat6`. Addresses the router-originated, mark-rerouted, wrong-saddr failure mode for IPv6: when mwan3 reroutes a packet from WAN-A onto WAN-B, the saddr was bound at `sendto()` to WAN-A's prefix; without SNAT it egresses WAN-B with the wrong prefix and is dropped upstream. Default is off because RFC 6724 source-address selection / SADR routing can solve the same problem without translation, NAT66 is harmful in PA/ULA designs, and some upstreams require a specific saddr. Three values: unset/`0` (off, default), `1` (SNAT to the interface's primary global address via `mwan3_get_src_ip`), or `<v6 addr>` (literal — NPTv6-style fixed-source pinning).

IPv4 router-originated traffic does not require an explicit mwan3 SNAT rule — fw4's masquerade handles it.

See [§15.5 Opt-in IPv6 SNAT via Per-Interface `snat6`](#155-opt-in-ipv6-snat-via-per-interface-snat6).

### luci-app-mwan3: expose `snat6` option for IPv6 interfaces

Adds a corresponding "IPv6 SNAT" form field to the interface configuration modal, visible only when the internet protocol is set to IPv6. See [§13.4](#134-interfacejs--interface-settings-ui).

---

## Version 3.1.4

Fix interoperability between mwan3 and pbr (Policy Based Routing). The nftables port's unmasked mark restore zeroed pbr's fwmark bits on every packet, causing pbr's `ip rule` entries to never match. Fixed by running mwan3 at `priority mangle - 1` so mwan3 processes before pbr. A postinst migration removes old chains so fw4 can recreate them at the new priority on upgrade.

### mwan3: fix pbr interoperability by running at priority mangle - 1

The original iptables implementation used `CONNMARK --restore-mark --nfmask $MMX_MASK --ctmask $MMX_MASK`, which selectively merged only mwan3's bits into the packet mark, leaving bits owned by other packages (such as pbr's `0x00ff0000` range) untouched. The nftables equivalent requires a compound two-source bitwise expression that the Linux kernel rejects with "Operation not supported", so the port uses an unmasked restore instead:

```
meta mark set ct mark & MMX_MASK
```

This replaces the entire packet mark with only mwan3's bits. Since pbr injects into fw4's `mangle_prerouting` at `priority mangle` (−150) and mwan3's chains were at `priority mangle + 1` (−149), pbr ran first and its marks were zeroed by mwan3 before the routing decision. pbr's `ip rule` entries never matched.

The fix moves mwan3's chains to `priority mangle - 1` (−151) so mwan3 runs before pbr. mwan3 restores and saves its mark while the packet mark is still zero, then pbr adds its bits on top. Both sets of marks are present at the routing decision, matching the coexistence behaviour of the iptables version.

A postinst script detects existing chains with the old priority and removes them before calling `fw4 reload`, since nftables rejects a chain redeclaration with a different priority.

**Files changed:** `files/usr/share/nftables.d/table-post/10-mwan3.nft`, `files/lib/mwan3/common.sh`, `Makefile`

---

## Version 3.1.3

Fix three bugs in `mwan3_create_policies_nft` and `mwan3_report_policies`. Equal-weight load balancing policies were incorrectly shown as empty in `mwan3 status`. Mixed IPv4/IPv6 policies silently lost members from one address family when the other family's members were processed. Single-member and mixed-family policies showed spurious `unreachable` entries in `mwan3 status` instead of interface names.

### mwan3: fix load balancing policy not shown in status

When all members in a load-balancing policy have equal weight of 1, nft
normalises numgen map entries from the range form `N-N : 0xMARK` to the
plain form `N : 0xMARK`. The regex used by `mwan3_report_policies` to
parse the chain output only matched the `N-M` range form, so equal-weight
policies produced no output and appeared empty in `mwan3 status`. The
load balancing itself was unaffected — only the status display was wrong.

Fixed by extending the regex to match both `N-M : 0xMARK` and
`N : 0xMARK`, and updating the weight calculation to handle both forms.

**File changed:** `files/lib/mwan3/mwan3.sh`

### mwan3: fix cross-family member reset in mixed IPv4/IPv6 policies

When a policy contained members from both IPv4 and IPv6 interfaces, a
single shared `policy_members` list was reset on each new lowest-metric
member regardless of address family. This caused IPv4 members to be
erased when a lower-metric IPv6 member was processed (or vice versa),
leaving the policy with only the last-processed family's members. The
generated nft rules were therefore incomplete.

Fixed by maintaining separate `policy_members_v4` and `policy_members_v6`
lists, each reset only when a new lowest-metric member of the same family
is encountered. When both families have members, per-family nft rules are
emitted with `meta nfproto ipv4`/`meta nfproto ipv6` guards so traffic is
only directed to members of the matching address family.

**File changed:** `files/lib/mwan3/mwan3.sh`

### mwan3: fix status reporting for single-member and mixed-family policies

`mwan3_report_policies` resolved nft marks to interface names using
`mwan3_mark_to_name` and tested `[ -n "$iface_name" ]` to skip special
marks. However `mwan3_mark_to_name` never returns an empty string — it
returns `"unreachable"`, `"blackhole"`, `"default"`, or the raw hex value
as a fallthrough for unrecognised marks. The empty-string check therefore
never filtered anything, causing spurious `unreachable` entries in the
status output. Additionally, only the first `meta mark set` rule in the
chain was examined, so mixed-family policies with one IPv4 and one IPv6
member only ever showed one interface.

Fixed by replacing the empty-string guard with a `case` statement that
explicitly skips the known non-interface values (`unreachable`, `blackhole`,
`default`, and raw `0x...` hex fallthrough), and by iterating all
`meta mark set` rules in the chain rather than only the first.

**File changed:** `files/lib/mwan3/mwan3.sh`

## Version 3.1.2

Fix a segfault in mwan3rtmon on process exit, and replace an unnecessary
netlink round-trip with an in-memory route cache.

### mwan3rtmon: fix segfault on exit caused by ucode-mod-rtnl double-destructor bug

Calling `route_listener.close()` explicitly zeroed the resource data pointer
while the ucode variable still held a live reference. When that reference was
later released at scope exit, `uc_nl_listener_free()` fired a second time with
`arg=NULL` and read `uc_nl_listener_t.index` at `NULL+0x10`, producing a
reliable `segfault at 10` on every clean shutdown.

Fixed by omitting the explicit `close()` call and letting the GC collect the
listener naturally. The destructor then fires exactly once with a valid pointer.

**File changed:** `usr/sbin/mwan3rtmon`

### mwan3rtmon: replace route_still_exists() with an in-memory route cache

`route_still_exists()` issued a full `RTM_GETROUTE` dump on every route-delete
event to check whether an ECMP path still existed before removing per-interface
table entries. This is unnecessary overhead.

Replaced with `main_route_cache`: a `{ route_key: count }` map built from the
initial route snapshot in `populate_iface_routes()` and maintained
incrementally in `handle_route_event()`. The ECMP check becomes an O(1) cache
lookup with no rtnl round-trip.

**File changed:** `usr/sbin/mwan3rtmon`

## Version 3.1.1

Fix mwan3track. Eliminate a number of legacy bugs and reduce spurious and incorrect log messages that make healthy interfaces appear to be unstable when they're not.

### mwan3track: process interface events before ping round on wakeup

When a USR2 signal (ifup) woke mwan3track from disabled state, the main loop
resumed immediately into a ping round before the IFUP_EVENT handler at the
bottom of the loop ran. At that point `DEVICE` was still stale (empty string
on first start), causing `sockopt_wrap` to skip `SO_BINDTODEVICE`, the
unbound ping to fail, and a spurious `disconnecting` state to be logged.

Fixed by checking `IFDOWN_EVENT`/`IFUP_EVENT` at the **top** of the main
loop before any pinging, and using `continue` to restart the iteration after
`firstconnect()` has refreshed `DEVICE` and `SRC_IP`. The existing handlers
at the bottom of the loop are retained for events that arrive during a ping
round or the inter-round sleep.

**File changed:** `usr/sbin/mwan3track`

### mwan3track: suppress per-host failure logs when reliability threshold is met

With multiple `track_ip` entries and `reliability` less than the total number
of IPs, a single host failure was logged as `Check failed for target X` even
when a subsequent host met the reliability threshold and the round succeeded.
In practice around 95% of all logged failures were false alarms of this kind,
making it appear the interface was degrading when it was healthy.

Fixed by accumulating failed host names during the probe loop and emitting a
single `Check failed for target(s) "..."` message after the loop, only when
`host_up_count` is still below `reliability` (i.e. the round genuinely
failed). Rounds that succeed via a later host produce no failure log.
In `check_quality` mode the accumulated entry includes per-host latency and
loss: `target(s) "1.2.3.4(999ms/10%)"`.

**File changed:** `usr/sbin/mwan3track`

### mwan3: sockopt_wrap: replace exit() with graceful error returns

The `libwrap_mwan3_sockopt.so` LD_PRELOAD shim was calling `exit()` on
recoverable socket errors, terminating the tracked ping process abruptly with
no output. mwan3track received no indication of why the probe process exited
and could not distinguish this from a genuine connectivity failure.

Three cases are fixed:

- **`dobind()` source IP bind failure** — can occur when `SRC_IP` becomes
  stale after a DHCP address change that does not generate an ifup event.
  The socket is now closed and the function returns; the subsequent
  `sendto()`/`connect()` call fails with `EBADF`, causing the ping to exit
  with a normal error code that mwan3track records as a ping failure.
- **`SO_BINDTODEVICE` failure in `socket()`** — can occur if the interface
  disappears between mwan3track reading `DEVICE` and the next ping round.
  Returns `-1` instead of calling `exit()`.
- **`SO_MARK` failure and over-length interface name** — both return `-1`
  instead of calling `exit()`.

`exit()` is retained in `dlerror_handle()` (unresolvable libc symbols) and
the `inet_pton` `EAFNOSUPPORT` case, as these are genuinely unrecoverable.

**File changed:** `src/sockopt_wrap.c`

### mwan3track: use flock to prevent ghost processes for same interface

When procd respawned mwan3track (after a crash or service restart) without
cleanly terminating the previous instance, both processes ran concurrently for
the same interface. The ghost instance did not receive signals from
`procd_send_signal`, so its internal score diverged from reality. Eventually
it crossed the disconnecting threshold and fired a spurious
`ACTION=disconnecting` hotplug event.

Fixed by acquiring an exclusive `flock` on a per-interface lock file at
startup. The lock is held for the lifetime of the process and released
unconditionally on exit. If another instance already holds the lock, the
existing holder is identified via the PID file, sent `SIGTERM`, and the new
instance blocks until the lock is released.

**File changed:** `usr/sbin/mwan3track`

### mwan3track: raise disconnecting threshold and log recovery

The `disconnecting` state fired immediately on the first score drop (any
single ping failure), causing spurious warnings for transient packet loss.

Raised the threshold to `ceil(down/3)` failures below the maximum score
(3 failures with the default `down=5`), so single or double transient losses
no longer trigger the warning. An explicit notice is also logged when the
score recovers out of the `disconnecting` state, making the transition back
to online visible in the log.

**File changed:** `usr/sbin/mwan3track`
