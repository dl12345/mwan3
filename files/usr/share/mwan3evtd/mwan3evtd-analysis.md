# mwan3evtd Analysis
&nbsp;
## 1. Introduction

Under the legacy iptables firewall, mwan3's ipsets existed independently of the firewall table. A firewall reload left them intact. Packages that depended on those sets,  and the DNS entries that populated them,  were unaffected.

fw4 places everything in a single `inet fw4` nftables table, including mwan3's nftsets. When fw4 reloads for any reason,  a config change, a package installing firewall rules, an interface event,  it destroys and recreates the entire table. mwan3's nftsets are recreated empty.

Something must then cause dnsmasq to repopulate them. dnsmasq populates nftsets when it resolves DNS queries, but cached answers do not trigger nftset population,  only actual resolutions do. A SIGHUP flushes the cache, forcing re-resolution of cached names and immediate nftset repopulation. Without this, nftsets remain empty until the cache entry expires, forcing re-resolution of the name, and packages depending on dnsmasq's nft sets are broken in the interim.

This means the dnsmasq HUP after mwan3 rebuilds its nft rules is not an optimisation,  it is a correctness requirement introduced by the move to fw4. mwan3evtd exists to optimise redundant calls and to deliver that HUP safely, after the fw4 rebuild has settled and dnsmasq is confirmed running.

Since mwan3evtd is used only by mwan3, it can only optimise the mwan3 calls, but that in and of itself reduces the number of HUPs from O(N) to O(1) where N is the number of interfaces managed by mwan3 and flapping either due to connectivity instability or reload / restart events occasioned by other packages such as pbr, various adblocks and other packages, and so is justified purely in terms of the mwan3 use-case.

&nbsp;

## 2. Fan-in signal collisions

On an Openwrt router running multiple network management packages, a single network event,  an interface coming up, a firewall rebuild or a config change,  triggers reactions from several independent packages simultaneously. Each package, knowing nothing about the others, signals or restarts the same shared system services. The result is a cascade of redundant operations that keeps those services unavailable far longer than necessary.

The concrete case that motivated mwan3evtd was the observation that on a system running mwan3 and pbr simultaneously, when an interface flaps, the following sequence occurs with no coordination:

1. pbr's interface trigger fires --> pbr restarts dnsmasq synchronously once for each interface (an update to pbr causes pbr to restart dnsmasq only once, which ameliorates this one-per-interface restart)
2. mwan3's hotplug fires --> mwan3 rebuilds its nft rules --> HUPs dnsmasq
3. fw4 reloads --> mwan3-fw-rebuild fires --> mwan3 rebuilds again --> signals dnsmasq again
4. Steps 1- 3 repeat independently for each interface that came up

On a 4-interface flap, this produces multiple dnsmasq kill/start sequences by pbr and 4 dnsmasq HUP cycles over 42 seconds. 

&nbsp;

## 3. Poor coordination of SIGTERM and SIGHUP can cause service crashes

A dnsmasq receiving SIGHUP before it has completed startup may in some cases exit fatally (this was observed on a live system, but the race is not easily reproducible due to tight timing constraints). In this case, DNS and DHCP go down. The router's clients lose network access entirely.

&nbsp;

## 4. Why SIGHUP and not restart

The dnsmasq man page documents that SIGHUP only reloads DHCP host files and `/etc/ethers`. Configuration options,  `--server`, `--nftset`, `--no-resolv`,  are only read at startup. mwan3's use of SIGHUP is correct: mwan3 does not change nftset configuration. It signals dnsmasq to re-resolve names and repopulate existing nftsets with current DNS answers. That is precisely what SIGHUP does.

Packages that change dnsmasq's server list or nftset configuration,  pbr, https-dns-proxy,  legitimately require a full synchronous restart and cannot substitute a HUP. Their restarts are not addressable by mwan3evtd's `dnsmasq-restart` event unless the restart requirement can be reduced to an asynchronous requirement.

&nbsp;

## 4. What mwan3evtd does

mwan3evtd is a small ucode event bouncer daemon that solves the fan-in coordination problem: multiple independent packages each signal or restart the same shared system services (dnsmasq, rpcd, firewall) when network state changes. Without coordination, a single interface event can trigger a dozen redundant restarts in rapid succession, wasting CPU, reducing service availability, disrupting active connections, and producing unnecessary log noise.

mwan3evtd receives named events over ubus, debounces bursts of identical pushes within a configurable debounce window, and runs the registered handler at most once per burst.

The result is a O(N) --> O(1) reduction in the number of SIGHUPs sent to dnsmasq by mwan3 when interface flaps occur as a result of hotplug handlers being triggered during a config apply of a package or a `fw4 reload`

&nbsp;



## 6. Memory footprint


mwan3evtd runs as a ucode script under `/usr/bin/ucode`. On a typical Openwrt 25.12 system, the incremental memory footprint of mwan3evtd was observed to be in the order of 600KB (not including already resident pages shared with mwan3rtmon).

Users wishing to conserve memory can simply disable mwan3evtd and behaviour will fall back to the per-interface HUP that existed prior to mwan3evtd

&nbsp;

## Appendix A - dnsmasq fan-in coordination in Openwrt

A (non-exhaustive scan) of the Openwrt codebase revealed that the dnsmasq fan-in problem is widespread. Any optimisation by packages is a good thing. The following results will help to reinforce why mwan3evtd was conceived.

A better solution would ultimately be a `fw4.reload_complete` ubus event sent by fw4 after finishing its reload, but this will require a change to fw4, which is beyond the scope of mwan3

Findings of the codebase scan are as follows

&nbsp;

### A.1 SIGHUP senders (cache flush only)

Note that the mwan3 behaviour applies to the port to nftables, not yet in the official repo.

| Package | Method | Trigger | Notes |
|---------|--------|---------|-------|
| mwan3 | `ubus call service signal` via `mwan3_dnsmasq_hup()` | fw4 reload detected (two independent code paths) | Fires from both `25-mwan3` hotplug and `mwan3-fw-rebuild.sh` background process; both paths called from a single WAN ifup event, but serialised via procd_lock |
| pbr | `kill -HUP "$(pidof dnsmasq)"` and `killall -q -s HUP dnsmasq` | pbr resolver switch path | pbr also has a full restart path (see 4.1b); two distinct call sites within the same init script |
| bmx7-dnsupdate | `killall -s HUP dnsmasq` | inotifywait loop; fires on every BMX7 originator list change | Continuous loop; frequency determined by BMX7 mesh activity, entirely independent of network events |
| travelmate | `/etc/init.d/dnsmasq reload` | Captive portal domain configuration change | |
| safe-search | `/etc/init.d/dnsmasq reload` | DNS filter config update via `safe-search-update`; also in package postinst | safe-search also performs a full restart on a weekly cron (see 4.1b) |
| family-dns | `/etc/init.d/dnsmasq reload` | DNS provider change via `family-dns-update` | Same script also triggers `/etc/init.d/network reload` and `/etc/init.d/firewall reload` unconditionally |

&nbsp;

### A.2 Full restart senders (`/etc/init.d/dnsmasq restart`)

A full restart tears down dnsmasq and recreates it, temporarily releasing port 53. Any DNS query arriving during the restart window receives a connection refused. This is strictly more disruptive than SIGHUP and should not be issued concurrently with another restart or SIGHUP.

| Package | Trigger | Notes |
|---------|---------|-------|
| pbr | pbr `restart` action | pbr has both a SIGHUP path (resolver switch) and a full restart path (service restart); both can fire in close succession during a WAN ifup event |
| https-dns-proxy | Service start (`on_boot`), config update (`on_config_update`), interface hotplug (`on_hotplug`), and service stop | Restarts dnsmasq to pick up DoH resolver configuration changes; fires on every interface event when https-dns-proxy is managing the dnsmasq upstream resolver |
| vpnc-scripts | VPN connect and VPN disconnect | The vpnc proto script restarts dnsmasq on every VPN tunnel establishment and teardown to update split-DNS configuration |
| antiblock | Every `antiblock start` or `antiblock restart` | Called unconditionally at the end of `start_service()` |
| cache-domains | After updating UCI with new domain cache configuration | Uses `/etc/init.d/dnsmasq "restart"` after each cache-domains script run |
| safe-search | Weekly cron (`1 1 * * 1`) scheduled in Makefile postinst via `safe-search-maintenance` | safe-search thus both reloads dnsmasq on config update and restarts it weekly via two distinct code paths |
| luci-app-adblock-fast | User toggles "debug logging" for dnsmasq backend in LuCI | `system('/etc/init.d/dnsmasq restart')` in rpcd ucode module |

&nbsp;

### A.3 Other DNS backend restarts

The fan-in problem is not limited to dnsmasq. Two packages, adblock and adblock-fast, use the configured DNS backend as a variable, restarting whichever resolver is active. This means the same fan-in pattern that affects dnsmasq users also affects users of smartdns, unbound, kresd (knot-resolver), and named (BIND9).

adblock's `adblock.sh` uses `$adb_dns` as the backend variable and calls `/etc/init.d/${adb_dns} reload` on some paths and `/etc/init.d/${adb_dns} restart` on its main blocklist update path. Supported backends: dnsmasq, unbound, named, kresd, smartdns, raw.

adblock-fast uses a `service_restart(name)` function in its ucode module that calls `/etc/init.d/${name} restart`. This fires on blocklist download/update cycles, service start/stop, and user allow-domain actions. The LuCI layer (luci-app-adblock-fast) additionally calls `/etc/init.d/dnsmasq restart`, `/etc/init.d/smartdns restart`, and `/etc/init.d/unbound restart` independently when the user toggles debug logging for each respective backend.

| Target daemon | Restarted by | Trigger |
|---------------|-------------|---------|
| dnsmasq | adblock, adblock-fast, luci-app-adblock-fast, https-dns-proxy, vpnc-scripts, antiblock, cache-domains, safe-search, pbr | Blocklist update, config change, VPN connect/disconnect, service start |
| smartdns | adblock, adblock-fast, luci-app-adblock-fast | Blocklist update, service start/stop, debug toggle |
| unbound | adblock, adblock-fast, luci-app-adblock-fast | Blocklist update, service start/stop, debug toggle |
| kresd (knot-resolver) | adblock | Blocklist update, service start/stop |
| named (BIND9) | adblock | Blocklist update, service start/stop |

The implication is that the problem is not specific to dnsmasq: any resolver used as a DNS backend by an adblocking package faces the same fan-in problem. 

&nbsp;

### A.4 Severity Assessment Summary

| Problem | Packages Involved | Trigger Frequency | Impact | Severity |
|---------|------------------|-------------------|--------|----------|
| dnsmasq restart storm (WAN ifup with mwan3 + pbr + https-dns-proxy) | mwan3, pbr, https-dns-proxy | Every WAN ifup / ifupdate | Two racing SIGHUPs followed by full restart; DNS service interruption | Very High |
| dnsmasq SIGHUP fan-in (ecosystem-wide) | mwan3, pbr, bmx7-dnsupdate, travelmate, safe-search, family-dns | Various; bmx7-dnsupdate is continuous | Redundant cache flushes; potential mid-init SIGHUP | High |
| dnsmasq full restart (multiple packages) | https-dns-proxy, vpnc-scripts, antiblock, cache-domains, safe-search (weekly), pbr, luci-app-adblock-fast | Interface events, VPN connect/disconnect, weekly cron, user actions | Full DNS service interruption per restart; multiple packages may race | High |
| Generic DNS backend restart (adblock/adblock-fast) | adblock, adblock-fast, luci-app-adblock-fast | Blocklist update cycle, service start/stop, user actions | Full restart of whatever DNS backend is configured (dnsmasq, smartdns, unbound, kresd, named) | Medium-High |
