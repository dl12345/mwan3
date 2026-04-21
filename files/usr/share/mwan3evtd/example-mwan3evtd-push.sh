#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Example: request a dnsmasq SIGHUP via mwan3evtd-push.
#
# This form assumes the caller's package depends on mwan3evtd
# (DEPENDS:=+mwan3evtd in its Makefile), so mwan3evtd-push is guaranteed
# to be present.  mwan3evtd-push handles its own fallback: if the
# ubus call to mwan3evtd fails, it looks up the handler command in
# /etc/config/mwan3evtd and execs it directly, so the operator's
# configured action is always honoured.

exec mwan3evtd-push dnsmasq-hup
