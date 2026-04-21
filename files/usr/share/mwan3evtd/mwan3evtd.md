# mwan3evtd Documentation

mwan3evtd is a small ucode event bouncer daemon that solves the fan-in coordination problem: multiple independent packages each signal or restart the same shared system services (dnsmasq, rpcd, firewall) when network state changes. Without coordination, a single interface event can trigger a dozen redundant restarts in rapid succession, wasting CPU, reducing service availability, disrupting active connections, and producing unnecessary log noise.

mwan3evtd receives named events over ubus, debounces bursts of identical pushes within a configurable debounce window, and runs the registered handler at most once per burst.

mwan3evtd causes a O(N) --> O(1) reduction in the number of SIGHUPs sent to dnsmasq by mwan3 when interface flaps occur as a result of hotplug handlers being triggered during a config apply of a package or a `fw4 reload`

mwan3evtd is a generic debounce handler that can be used by other packages if desired. The more that use it, the greater the effect in terms of eliminating spurious dnsmasq HUPs and restarts. Default handlers already exist for other configurations that might need it.

Users wishing to conserve memory can simply disable mwan3evtd and mwan3 behaviour will fall back to the per-interface HUP that existed prior to mwan3evtd. mwan3evtd uses approximately 600KB of private (non-shared) pages and is resource-light for a daemon.

&nbsp;

## 1. How it works

Each named event has two timing parameters. `window_ms` is a trailing debounce: every push resets the timer, and the handler fires only after `window_ms` of silence. `max_window_ms` is a hard deadline from the first push: even if pushes keep arriving continuously, the handler fires within `max_window_ms` of the first one. This combination absorbs short bursts quickly and bounds latency under sustained churn.

Handlers run sequentially. If a push arrives while a handler is already running, mwan3evtd queues a single deferred invocation that fires when the current run completes.

&nbsp;

## 2. Configuration

Handlers are declared in `/etc/config/mwan3evtd` as UCI sections of type `handler`.

```
config handler
    option event 'dnsmasq-hup'
    option command "ubus call service signal '{\"name\":\"dnsmasq\",\"signal\":1}'"
    option window_ms '5000'
    option max_window_ms '30000'
    option handler_timeout_ms '10000'
    list superseded_by 'dnsmasq-restart'
```

&nbsp;

### 2.1. Options

**`event`** — unique name for the event. Must match `[A-Za-z0-9_.:-]{1,64}`. Required.

**`command`** — shell command to execute when the window closes. Runs under `/bin/sh -c` inside a new session (via `setsid`) so the entire process group can be killed on timeout. Required.

**`window_ms`** — trailing debounce window in milliseconds. Each push resets it. Default: 500.

**`max_window_ms`** — hard deadline from first push in milliseconds. Default: 5000.

**`handler_timeout_ms`** — maximum handler runtime. When elapsed, mwan3evtd sends SIGTERM to the handler's process group; if the process has not exited after a further 5 seconds, SIGKILL follows. Default: 30000.

**`list supersedes`** — events that this event cancels when they have a pending timer. A push of this event will discard any pending (but not running) invocation of the listed events. Used to express severity hierarchies, e.g. `dnsmasq-restart` supersedes `dnsmasq-hup`.

**`list superseded_by`** — events that cause pushes of this event to be silently discarded while they are pending. Should be the mirror of a `supersedes` declaration on the stronger event.

See `/usr/share/mwan3evtd/timing.md` for guidance on choosing timer values.

&nbsp;

### 2.2 Supersession

Supersession relationships let you declare that one event is strictly stronger than another. For example, if `dnsmasq-restart` is pending and a `dnsmasq-hup` push arrives, the HUP is discarded because a restart is already coming. Conversely, if `dnsmasq-hup` is pending and a `dnsmasq-restart` push arrives, the pending HUP timer is cancelled and the restart takes over.

This is always declared as a pair:

```
config handler
    option event 'dnsmasq-hup'
    list superseded_by 'dnsmasq-restart'

config handler
    option event 'dnsmasq-restart'
    list supersedes 'dnsmasq-hup'
```

Supersession only operates on pending timers, never on handlers that are already running.

&nbsp;

## 4. Pushing events

&nbsp;

### 4.1 Direct ubus call

```sh
ubus call mwan3evtd push '{"event":"dnsmasq-hup"}'
```

Returns immediately. mwan3evtd handles the debouncing and fires the handler asynchronously.

&nbsp;

### 4.2 mwan3evtd-push wrapper

`/usr/sbin/mwan3evtd-push` is a shell wrapper for callers that prefer a simple command-line interface. It tries the ubus call first and, if mwan3evtd is unreachable, falls back to looking up the handler command in `/etc/config/mwan3evtd` and executing it directly. This fallback ensures the action still happens during early boot or if mwan3evtd has crashed.

```sh
mwan3evtd-push dnsmasq-hup
```

&nbsp;

## 5. Integration patterns

&nbsp;

### 5.1 Caller depends on mwan3evtd

Add `+mwan3evtd` to `DEPENDS` in the caller's Makefile. Call `mwan3evtd-push <event>` or `ubus call mwan3evtd push` directly. The `mwan3evtd-push` fallback means the action still fires if mwan3evtd is temporarily unavailable.

&nbsp;

### 5.2 Caller treats mwan3evtd as optional

Try the ubus call inline and fall back to the native action if it fails. This pattern works without any package dependency on mwan3evtd. Example scripts for both shell and ucode are in `/usr/share/mwan3evtd/`.

&nbsp;

## 6. Observability

```sh
# List configured handlers with current state and timer countdowns
ubus call mwan3evtd list

# Per-event counters and timing statistics
ubus call mwan3evtd status

# Reset all counters and timing fields to zero (useful before a tuning run)
ubus call mwan3evtd reset

# Force a pending handler to fire immediately without waiting for the window
ubus call mwan3evtd flush '{"event":"dnsmasq-hup"}'

# Reload /etc/config/mwan3evtd without restarting the daemon
ubus call mwan3evtd reload
```

See `/usr/share/mwan3evtd/counters.md` for a full description of the status counters and how to use them to tune `window_ms` and `max_window_ms` for your system.

&nbsp;

## 7. Access control

`push`, `flush`, and `reload` are root-only (not listed in any rpcd ACL grant). `list` and `status` are readable by rpcd clients via `/usr/share/rpcd/acl.d/mwan3evtd.json`.

&nbsp;

## 8. Default handlers

The default `/etc/config/mwan3evtd` ships handlers for the most common fan-in scenarios. Timings are set conservatively based on observed behaviour on a system running mwan3 and pbr concurrently; see `/usr/share/mwan3evtd/timing.md` for the rationale.

| Event | Action | Notes |
|-------|--------|-------|
| `dnsmasq-hup` | SIGHUP all dnsmasq instances via procd | Direct `ubus call service signal`; no wrapper script |
| `dnsmasq-restart` | `/etc/init.d/dnsmasq restart` | Supersedes `dnsmasq-hup` |
| `rpcd-reload` | `/etc/init.d/rpcd reload` | Superseded by `rpcd-restart` |
| `rpcd-restart` | `/etc/init.d/rpcd restart` | Supersedes `rpcd-reload` |
| `firewall-reload` | `/etc/init.d/firewall reload` | Superseded by `firewall-restart` |
| `firewall-restart` | `/etc/init.d/firewall restart` | Supersedes `firewall-reload` |
| `unbound-restart` | `/etc/init.d/unbound restart` | |
| `smartdns-restart` | `/etc/init.d/smartdns restart` | |
| `kresd-restart` | `/etc/init.d/kresd restart` | |
| `named-restart` | `/etc/init.d/named restart` | |

&nbsp;

## Further reading

- `/usr/share/mwan3mwan3evtd/timing.md`: rationale for the default timer values and guidance on adjusting them
- `/usr/share/mwan3mwan3evtd/counters.md`: description of all status counters and a step-by-step tuning workflow
- `/usr/share/mwan3mwan3evtd/example.sh` and `example.uc`: caller examples for the optional-mwan3evtd pattern
- `/usr/share/mwan3mwan3evtd/example-mwan3evtd-push.sh` and `example-mwan3evtd-push.uc`: caller examples for the dependent-mwan3evtd pattern
- `/usr/share/mwan3mwan3evtd/mwan3evtd-analysis.md`: why does mwan3evtd exist?
