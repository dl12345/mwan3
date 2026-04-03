# mwan3 nftables Implementation

**Developer Reference** — OpenWrt 25.12+
Covers the nftables port of the mwan3 multi-WAN policy routing framework.
*Package version: 3.1*

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

---

## 1. Architecture Overview

mwan3 is OpenWrt's multi-WAN policy routing framework. It classifies packets using **firewall marks**, then uses `ip rule` entries to route marked packets through per-interface routing tables. The nftables port replaces all iptables/ipset usage with nftables equivalents while keeping the ip rule/route management, health tracking (`mwan3track`), and socket-level mark injection (`libwrap_mwan3_sockopt.so`) completely unchanged.

### Key Design Decisions

- **Lives inside `table inet fw4`** — mwan3 chains and sets are defined inside fw4's own table, not a separate table. This is how fw4 extension points (`table-post/*.nft`) work.
- **Own-priority hook chains** — `mwan3_prerouting` and `mwan3_output` are registered at `priority mangle + 1`, running after fw4's own mangle chains but before any higher-priority processing.
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

```
Bit:   31 ...... 14 13 12 11 10  9  8  7 ...... 0
       [  unused  ] [    MMX_MASK    ] [ unused  ]
                     0  0  1  1  1  1
                     ^  ^  ^  ^  ^  ^
                     |  |  +--+--+--+-- 6 bits = values 0..63
                     |  +-- bit 13
                     +-- bit 14
```

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

```
# Restore mark from conntrack (first packet of existing flow):
meta mark set ct mark & $MMX_MASK

# Save mark to conntrack:
ct mark set meta mark
```

> [!NOTE]
> **Why not preserve non-mwan3 bits?** The ideal connmark save would be `ct mark set ct mark & ~MASK | meta mark & MASK` to preserve other bits. However, the kernel does not support compound two-source bitwise expressions (mixing `ct mark` and `meta mark` in one set expression fails with "Operation not supported"). Since mwan3 owns its mask bits exclusively, saving the full `meta mark` is safe and equivalent in practice.

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
| `mwan3_sticky_v4_<rule>` | map (ipv4_addr : mark) | `mwan3_set_sticky_map()` |
| `mwan3_sticky_v6_<rule>` | map (ipv6_addr : mark) | `mwan3_set_sticky_map()` |

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
  |     +-- YES: Restore mark from conntrack (ct mark & MMX_MASK)
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
  |-- Save mark to conntrack:
  |     ct mark = meta mark
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

The static nftables framework file. Included inside `table inet fw4 { }` by fw4 at startup. Defines 6 named sets (all empty, with `flags interval` and `auto-merge` for CIDR support with overlapping element handling) and 7 skeleton chains (all empty). No rules are present — all rules are added dynamically by the shell scripts because they depend on the configurable `MMX_MASK` value.

The `mwan3_prerouting` chain is type `filter` at priority `mangle + 1`. The `mwan3_output` chain is type `route` at the same priority.

### 5.2 `lib/mwan3/common.sh`

Shared helper library sourced by all mwan3 shell scripts. Provides:

- **Tool variables**: `$IP4`, `$IP6`, `$NFT`
- **IPv6 detection**: Checks `/proc/sys/net/ipv6` existence (instead of the old `command -v ip6tables`)
- **nft batch helpers**: `mwan3_nft_batch_start()`, `mwan3_nft_push()`, `mwan3_nft_batch_commit()`
- **`mwan3_nft_exec()`**: Wrapper that runs `nft` commands with error logging
- **`mwan3_nft_mark_expr()`**: Generates nftables mark-set expressions equivalent to iptables `--set-xmark`. Outputs `meta mark set meta mark & COMPLEMENT | VALUE` using `&`/`|` symbols (not `and`/`or` keywords).
- **`mwan3_ensure_nft_framework()`**: Guarantees all mwan3 nftables objects (sets and chains) exist with correct flags. Deletes and recreates all 6 sets to ensure the `auto-merge` flag is present (since `nft add set` is idempotent but won't update flags on existing sets). Then creates all chains. Called early in `start_service()`.
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
- **`stop_service()`**: Tears down in reverse: shuts down interfaces, flushes ip routes/rules, flushes all mwan3 nft chains, deletes dynamic chains (keeps skeleton chains from the static .nft file), flushes sets, deletes sticky maps.
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

Between the guard checks and the per-action processing, the hotplug script detects whether fw4 has reloaded (wiping all dynamic mwan3 rules). It checks whether `mwan3_prerouting` contains any `meta mark` rules. If the chain is empty (skeleton only), it performs a full rebuild of all nft rules, interface chains, policies, and user rules. It also signals dnsmasq (`killall -HUP dnsmasq`) to clear its cache so that subsequent DNS queries re-populate any nftset-based sets. See [Section 10](#10-fw4-reload-recovery) for full details.

#### Actions

| Action | Operations |
|---|---|
| `ifup` | Update peer track IP (if `track_gateway` enabled), create interface nft chain, create ip rules, set hotplug state, create routes (if not init), set general rules, rebuild policies (if online and not init). Signal tracker with USR2. |
| `ifdown` | Set offline state, selectively flush conntrack entries for this interface's fwmark, delete sticky map entries, delete ip rules, delete routes, delete interface nft chain. Signal tracker with USR1. Rebuild policies. |
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

ucode RPC service providing the `mwan3.status` ubus method. Used by LuCI for the web interface. Returns JSON data for interfaces, connected networks, and policies.

Uses `nft -j` (JSON output mode) for reliable parsing instead of text scraping. Key changes from the iptables version:

- **Connected IPs**: Parses `nft -j list set inet fw4 mwan3_connected_v4/v6`. Handles JSON element types: plain strings, prefix objects (`{prefix: {addr, len}}`), and range objects.
- **Policies**: Enumerates chains matching `mwan3_policy_*` via `nft -j list chains`, then parses each chain's JSON looking for `numgen` map expressions to extract weight/mark information.
- **Interfaces**: Unchanged — reads status files from `/var/run/mwan3track/` and queries procd/netifd via ubus.

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

The `+nftables-json` package provides the `nft` binary with JSON output support, needed by the rpcd ucode module.

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
7. Signals dnsmasq to clear its cache (`killall -HUP dnsmasq`)

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
| `mwan3_ensure_nft_framework` | Deletes all 6 mwan3 sets (to clear stale flags), then batch-creates sets with `interval` + `auto-merge` flags and all 7 skeleton chains. Idempotent for chains (`add chain` is a no-op on existing chains). Called from `start_service()`. |
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
| `mwan3_set_general_nft` | Populates all hook chain rules: connmark restore/save, jumps to ifaces_in/custom/connected/dynamic/rules chains, IPv6 RA bypass, and post-rules connected re-check. Idempotent: checks if rules already exist before adding. Uses a single batch for all operations. |

#### Rules added by `mwan3_set_general_nft()`

For each of connected/custom/dynamic chains, adds mark-setting rules that match against the corresponding sets and apply `MMX_DEFAULT`.

For the prerouting and output hook chains, adds (in order):

1. [prerouting only] IPv6 RA bypass (accept ICMPv6 types: nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect)
2. Connmark restore: `meta mark set ct mark & $MMX_MASK` (if mark is 0)
3. Jump to `mwan3_ifaces_in` (if still 0)
4. Jump to custom, connected, dynamic chains (if still 0)
5. Jump to `mwan3_rules` (if still 0)
6. Connmark save: `ct mark set meta mark` (always)
7. Post-rules: jump to custom/connected/dynamic again for non-default marks

### 6.4 Interface Management

| Function | Purpose |
|---|---|
| `mwan3_create_iface_nft iface device` | Creates (or flushes) `mwan3_iface_in_<iface>` chain. Adds rules matching on `iifname` and address family: source in connected/custom/dynamic → MMX_DEFAULT; otherwise → interface mark. Adds jump from `mwan3_ifaces_in` if not already present. |
| `mwan3_rebuild_iface_nft iface` | Rebuilds a single interface's nft chain if the interface is enabled, the correct family is available, and the interface is currently up (verified via ubus). Used during fw4 reload recovery to restore all interface chains. Calls `mwan3_create_iface_nft()` after resolving the L3 device from netifd. |
| `mwan3_delete_iface_nft iface` | Removes the jump rule from `mwan3_ifaces_in` (by handle lookup) then flushes and deletes the interface chain. |
| `mwan3_delete_iface_map_entries iface` | Iterates all `mwan3_sticky_*` maps, finds entries whose mark matches this interface, and deletes them. |
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
| `mwan3_set_policies_nft` | Iterates all policy configs and calls `mwan3_create_policies_nft` for each. |

### 6.6 Sticky Routing

| Function | Purpose |
|---|---|
| `mwan3_set_sticky_map rule timeout` | Creates `mwan3_sticky_v4_<rule>` and `_v6_` maps if they don't exist. Maps are type `ipv4_addr : mark` with `flags dynamic,timeout`. |
| `mwan3_set_sticky_nft iface rule ipv policy` | (Legacy sticky approach) Inserts per-interface restore/clear rules at the beginning of a sticky rule chain. Not used in the primary sticky path (map approach is used instead). |

### 6.7 User Rules

| Function | Purpose |
|---|---|
| `mwan3_set_user_nft_rule rule ipv` | Builds and adds a single nft rule to `mwan3_rules`. Translates UCI config options (proto, src_ip, dest_ip, src_port, dest_port, src_iface, ipset) into nft match expressions. Handles sticky routing (creates sticky map, map lookup chain). Handles logging rules. Pre-creates missing nft sets (e.g., dnsmasq nftsets that haven't started yet) to prevent batch failures. |
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
| `use_policy balanced` | `jump mwan3_policy_balanced` |
| `use_policy default` | `meta mark set ... \| MMX_DEFAULT` |

#### Missing nft Set Pre-creation

When a user rule references an `ipset` (nft set) that doesn't exist yet (e.g., a dnsmasq `nftset` that will be created when dnsmasq starts, which is later at START=60+), the batch file would fail atomically since `nft -f` rolls back the entire batch if any referenced set is missing. To prevent this, `mwan3_set_user_nft_rule()` checks for the set's existence and pre-creates it with the appropriate type if missing.

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

Sticky routing ensures that repeat connections from the same source IP use the same WAN interface (important for HTTPS sessions, banking sites, etc.). The iptables version used `ipset hash:ip,mark` sets. The nftables version uses **maps** with regular `map` lookup (not `vmap` — see note below).

### Data Structure

```
# Created per sticky rule:
nft add map inet fw4 mwan3_sticky_v4_https \
    '{ type ipv4_addr : mark; flags dynamic,timeout; timeout 600s; }'
```

This is a dynamic map that stores `source_ip → mark_value` entries, each with a configurable timeout.

### Rule Chain Structure (for sticky rule "https")

```
chain mwan3_rule_https {
    # 1. Try to restore from sticky map (regular map lookup)
    #    If source IP is in the map, the stored mark is applied
    meta mark set ip saddr map @mwan3_sticky_v4_https

    # 2. New flows (no map entry) fall through to the policy
    meta mark & 0x3f00 == 0 jump mwan3_policy_balanced

    # 3. After policy selection: record the chosen mark
    meta mark & 0x3f00 != 0 update @mwan3_sticky_v4_https \
        { ip saddr timeout 600s : meta mark & 0x3f00 }
}
```

> [!WARNING]
> **map vs vmap:** An earlier implementation used `vmap` (verdict map) for sticky lookup. This is incorrect: `vmap` expects verdict values (`accept`, `drop`, `jump`) as the mapped value, not marks. For IP→mark lookup, a regular `map` must be used: `meta mark set ip saddr map @mapname`.

### Flow for a Sticky Rule

1. Packet arrives at `mwan3_rules` chain
2. Matches the user rule → `jump mwan3_rule_https`
3. **Returning source**: map finds IP, sets mark via `meta mark set ip saddr map @...`, then the `meta mark & MMX_MASK == 0` guard on the policy jump is false (mark already set), so policy is skipped. The update rule refreshes the timeout.
4. **New source**: map lookup produces no match (mark stays 0), falls through to policy chain which sets a mark, then the update rule records `src_ip → mark` in the map with the configured timeout
5. After timeout seconds of inactivity, the map entry expires and the source gets re-evaluated

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
       +--> mwan3_delete_iface_map_entries()  clean sticky maps
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
  +--> delete sticky maps
  +--> rm -rf status dirs

Result: skeleton chains and empty sets remain (harmless).
        Removed on fw4 restart or package removal.
```

---

## 10. fw4 Reload Recovery

This section documents the mechanisms that handle fw4 reload events, which would otherwise destroy all mwan3 dynamic rules.

### The Problem

fw4 reload (triggered by `/etc/init.d/firewall restart`, `fw4 reload`, or the `20-firewall` hotplug script on ifup/ifupdate events for interfaces in firewall zones) flushes the **entire** `table inet fw4` and recreates it from scratch. Only the static skeleton from `10-mwan3.nft` survives (empty chains and sets with correct types/flags), but all dynamically-added rules, interface chains, policy chains, and set contents are lost.

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
       +--> killall -HUP dnsmasq                 clear DNS cache to re-populate nft sets
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
                 +--> killall -HUP dnsmasq
```

> [!NOTE]
> **Why fork?** The fw4 script include runs inside fw4's shell environment, which overrides the `config()` function to block UCI access. `mwan3-fw-rebuild.sh` runs as a separate process with a clean shell, allowing it to call `config_load mwan3` normally.

### dnsmasq nftset Recovery

When fw4 reloads, it also destroys any nft sets populated by dnsmasq (via the `nftset` option). These sets are dynamically populated as DNS queries arrive. The rebuild process signals dnsmasq with `SIGHUP` to clear its cache, which forces fresh upstream resolution on next client queries, thereby re-populating the nft sets. User rules that reference external nft sets also pre-create them if missing (see [Section 6.7](#67-user-rules)).

---

## 11. Unchanged Files

| File | Reason |
|---|---|
| `usr/sbin/mwan3track` | Uses `libwrap_mwan3_sockopt.so` (socket-level SO_MARK), no firewall interaction |
| `etc/hotplug.d/iface/26-mwan3-user` | Just calls `/etc/mwan3.user`, no firewall code |
| `etc/config/mwan3` | UCI schema is firewall-agnostic |
| `etc/mwan3.user` | User script template, no firewall code |
| `src/sockopt_wrap.c` | Uses SO_MARK kernel API, works with any firewall backend |
| `etc/uci-defaults/mwan3-migrate-flush_conntrack` | UCI migration, no firewall code |

---

## 12. Diagnostic Commands

```sh
# List all mwan3 chains with their rules
nft list table inet fw4 | grep -A 50 'chain mwan3_'

# List specific chain
nft list chain inet fw4 mwan3_prerouting
nft list chain inet fw4 mwan3_ifaces_in
nft list chain inet fw4 mwan3_policy_balanced

# Check set contents
nft list set inet fw4 mwan3_connected_v4
nft list set inet fw4 mwan3_custom_v4

# Check sticky map entries
nft list map inet fw4 mwan3_sticky_v4_https

# List all mwan3 chains (names only)
nft list chains inet fw4 | grep mwan3_

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

The LuCI rule editor view allows users to configure mwan3 traffic classification rules. It populates a dropdown of available sets for the "ipset" UCI option (the UCI option name is unchanged for backwards compatibility).

#### Changes

| Aspect | Old (iptables) | New (nftables) |
|---|---|---|
| Data fetch | `fs.exec_direct('/usr/libexec/luci-mwan3', ['ipset', 'dump'])` | `fs.exec_direct('/usr/libexec/luci-mwan3', ['nftset', 'dump'])` |
| Field label | `_('IPset')` | `_('NFT set')` |
| Help text | `Name of IPset rule. Requires IPset rule in /etc/dnsmasq.conf (eg "ipset=/youtube.com/youtube")` | `Name of nft set. Requires nftset rule in /etc/dnsmasq.conf (eg "nftset=/youtube.com/4#inet#fw4#youtube")` |
| Variable names | `ipsets`, `ips` | `nftsets`, `s_name` |

> [!NOTE]
> **dnsmasq nftset syntax:** The dnsmasq `nftset` option uses a different format from the old `ipset` option. The format is `nftset=/domain/FAMILY#TABLE_FAMILY#TABLE#SET`. For example, `nftset=/youtube.com/4#inet#fw4#youtube` means: for `youtube.com` A records (family `4` = IPv4), add addresses to the set named `youtube` in `table inet fw4`.

> [!NOTE]
> **UCI option name preserved:** The underlying UCI option remains `ipset` (not renamed to `nftset`) to maintain backwards compatibility with existing configurations. The mwan3 shell code reads `config_get ipset_name "$1" ipset` regardless of the firewall backend. Only the UI labels and help text were updated to reflect the nftables terminology.

### 13.2 `luci-mwan3` — Helper Script

The `/usr/libexec/luci-mwan3` shell script provides backend commands called by the LuCI JavaScript frontend. The `ipset` subcommand was renamed to `nftset` and the underlying implementation changed from querying ipset to querying nftables.

#### Changes

| Aspect | Old (iptables) | New (nftables) |
|---|---|---|
| Subcommand name | `ipset` | `nftset` |
| Function name | `ipset_dump()` / `ipset_cmd()` | `nftset_dump()` / `nftset_cmd()` |
| Implementation | `ipset -n -L 2>/dev/null \| grep -v mwan3_ \| sort -u` | `nft list sets inet fw4 2>/dev/null \| awk '/^\tset / {print $2}' \| grep -v '^mwan3_' \| sort -u` |
| Help text | `dump: show all configured ipset names` | `dump: show all non-mwan3 nft set names in inet fw4` |

The `nftset_dump()` function lists all sets in `table inet fw4`, extracts set names using awk (matching lines that start with a tab followed by `set`), filters out mwan3's own internal sets (prefixed with `mwan3_`), and returns the sorted unique names. This provides the dropdown list of available nft sets in the rule editor UI.

The `diag` subcommand and its functions (`diag_gateway`, `diag_tracking`, `diag_rules`, `diag_routes`) are unchanged — they use `ip rule`/`ip route` and the `mwan3 use` command, none of which depend on the firewall backend.

### 13.3 `luci-app-mwan3.json` — ACL Permissions

The rpcd ACL file controls which commands the LuCI frontend is permitted to execute. The permission entry was updated to match the renamed subcommand:

| Old | New |
|---|---|
| `"/usr/libexec/luci-mwan3 ipset dump": ["exec"]` | `"/usr/libexec/luci-mwan3 nftset dump": ["exec"]` |

This entry appears under the `luci-app-mwan3` ACL group in the `read.file` section. Without this change, the LuCI frontend would receive a permission denied error when trying to populate the nft set dropdown in the rule editor.

### 13.4 `interface.js` — Interface Settings UI

A "Track gateway" checkbox was added to the interface configuration modal, visible only when the internet protocol is set to IPv4. This exposes the `track_gateway` UCI option for automatic point-to-point peer/gateway discovery (see [Section 15.3](#153-automatic-gateway-tracking-track_gateway)).

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
| `-j CONNMARK --restore-mark --nfmask M` | `meta mark set ct mark & MASK` | Single-source expression; kernel doesn't support compound `meta mark \| ct mark & X` |
| `-j CONNMARK --save-mark --nfmask M` | `ct mark set meta mark` | Full overwrite; kernel doesn't support compound `ct mark & ~M \| meta mark & M` |
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
> - **No compound two-source bitwise:** Expressions like `meta mark set meta mark | ct mark & X` or `ct mark set ct mark & ~M | meta mark & M` fail with "Operation not supported". Each set expression can only draw from one register source.
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
3. `mwan3track` reads this file as an additional tracking IP alongside any static `track_ip` entries
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

---

*mwan3 nftables port — OpenWrt 25.12 — Updated 2026-04-03*
