# mwan3evtd handler timing defaults

This document explains how the default `window_ms`, `max_window_ms`, and `handler_timeout_ms` values in `/etc/config/mwan3evtd` were chosen. The numbers are educated starting points rather than measured values: they were picked against the cost and user-visibility of the underlying operation, and should be revisited with real telemetry from `ubus call mwan3evtd status` on a live system.

&nbsp;

## 1. The three parameters

**`window_ms`** is the trailing-debounce window. Each push resets it. When the window closes with no further push for that event, the handler fires. Short windows feel responsive; long windows coalesce better but delay the action.

**`max_window_ms`** is a hard deadline from the first push. It bounds worst-case latency under sustained pushing: no matter how many pushes arrive back-to-back, the handler will fire within `max_window_ms` of the first one.

**`handler_timeout_ms`** bounds handler runtime. When it elapses, mwan3evtd sends `SIGTERM` to the handler's process group and, five seconds later, `SIGKILL`. Pick a value that is a generous ceiling over a healthy handler's normal runtime, not a tight budget.

&nbsp;

## 2. Per-handler rationale

&nbsp;

### 2.1 `dnsmasq-hup` — 5000 / 30000 / 10000

These values are derived from observation on a live system running pbr and mwan3 concurrently. A pbr config change triggers a chain that spans roughly 9 seconds: pbr sets up per-WAN routing (several seconds), installs an fw4 nft ruleset which triggers mwan3 to rebuild its rules, then pbr restarts dnsmasq. The whole sequence, from first push to last, regularly exceeds 11 seconds. With additional callers such as https-dns-proxy also pushing HUPs in response to the same change, the window would be longer still, so 30 s is a conservative deadline.

A 5 s trailing debounce means the handler fires 5 seconds after the last push, once all callers have settled. The 30 s deadline ensures a hard cap even if pushing is continuous. The 10 s handler timeout is generous for a signal send: the handler calls `ubus call service signal` which completes in milliseconds under normal conditions.

&nbsp;

### 2.2 `dnsmasq-restart` — 5000 / 30000 / 30000

Kept intentionally in step with `dnsmasq-hup` on window and deadline so the severity pair composes predictably. If a restart push arrives during a pending hup window, supersession cancels the hup cleanly; misaligned windows would cause edge cases where the stronger action fires either too early or too late relative to its weaker sibling. A full restart re-parses configuration, rebinds sockets, and reloads leases; 30 s accommodates low-end targets under load.

&nbsp;

### 2.3 `rpcd-reload` and `rpcd-restart` — 2000 / 10000 / 30000

Rpcd churn is dominated by package install and upgrade, where several ACL-providing packages push in sequence with seconds between them rather than milliseconds. A 2 s window captures that cluster. Rpcd is not on any latency-critical path — a user clicking in LuCI can tolerate a few seconds of extra wait — so the 10 s deadline is generous. The 30 s timeout is consistent with other reload/restart handlers.

&nbsp;

### 2.4 `firewall-reload` and `firewall-restart` — 1000 / 5000 / 30000

Firewall reloads are expensive: nftables rebuild, ruleset reparse, and implications for conntrack. At the same time, stale rules are security-relevant, so the 1 s window and 5 s deadline are kept deliberately tight. This is a trade-off: more CPU churn for bounded exposure to an outdated ruleset. On very busy systems with rapid interface flapping, operators may want to raise the window; the cost is a longer blind window where rules do not reflect current state.

&nbsp;

### 2.5 `dns-backend-restart-*` — 2000 / 30000 / 30000

The backend-restart family (`dnsmasq`, `unbound`, `smartdns`, `kresd`, `named`) represents the heaviest DNS action available. Callers are typically interface-state transitions (DHCP lease changes, link flaps) that arrive in bursts, so a 2 s window coalesces the common case. The deliberately long 30 s deadline reflects that these events are the fallback of last resort: if something really is pushing continuously, letting coalescing keep the handler quiet is usually the correct behaviour, and the next push after the deadline fire will start a fresh window.

&nbsp;

## 3. General principles

Paired events such as `dnsmasq-hup`/`dnsmasq-restart` or `firewall-reload`/`firewall-restart` share `window_ms` and `max_window_ms` so that the severity hierarchy behaves consistently under supersession: a stronger push cancelling a weaker pending timer must not accidentally shift the deadline.

`handler_timeout_ms` scales with the nature of the work. Signal-based handlers use roughly 10 s; reload and restart handlers use 30 s. These are ceilings on observed healthy runtime, not target budgets.

The windows are the most arguable values in this file. They encode assumptions about how callers batch their pushes, which vary by deployment. Real tuning needs measurement: check `max_inter_push_ms` and `last_batch_duration_ms` from `ubus call mwan3evtd status` on the target system, compare against the pattern of pushes you are seeing in syslog, and adjust. See `counters.md` for the full tuning workflow.

&nbsp;

## 4. When to change these

Raise `window_ms` when you see many single-push fires for the same event in close succession. Lower it when the handler feels laggy to users or to dependent systems.

Raise `max_window_ms` when sustained pushing is expected and you would rather coalesce further than fire eagerly. Lower it when the operation's staleness matters more than its cost (firewall rules, for example).

Raise `handler_timeout_ms` if you observe the handler being killed mid-run on healthy systems. Lower it only if you have a reason to believe a stuck handler is likely and must be reaped quickly.
