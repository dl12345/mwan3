#!/usr/bin/ucode
// SPDX-License-Identifier: GPL-2.0
//
// Example: request a dnsmasq SIGHUP via mwan3evtd, falling back to a
// direct SIGHUP if mwan3evtd is not installed or not responding.
//
// The ubus call fails the same way whether mwan3evtd is absent (no
// "mwan3evtd" object published), stopped, or hung (timeout), so a single
// check covers all three cases.

import * as ubus from "ubus";

let bus = ubus.connect(null, 1000);
if (bus) {
	let reply = bus.call("mwan3evtd", "push", { event: "dnsmasq-hup", caller: "mypkg" });
	bus.disconnect();
	if (reply != null)
		exit(0);
}

// Fallback: send SIGHUP directly to every running dnsmasq.
system("kill -HUP $(cat /var/run/dnsmasq/*.pid 2>/dev/null) 2>/dev/null");
