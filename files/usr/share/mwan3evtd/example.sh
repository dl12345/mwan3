#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Example: request a dnsmasq SIGHUP via mwan3evtd, falling back to a
# direct SIGHUP if mwan3evtd is not installed or not responding.
#
# The ubus call fails the same way whether mwan3evtd is absent (no
# "mwan3evtd" object published), stopped, or hung (timeout), so a single
# check covers all three cases.

if ubus -t 1 call mwan3evtd push '{"event":"dnsmasq-hup","caller":"mypkg"}' >/dev/null 2>&1; then
	exit 0
fi

# Fallback: send SIGHUP directly to every running dnsmasq.
kill -HUP $(cat /var/run/dnsmasq/*.pid 2>/dev/null) 2>/dev/null
