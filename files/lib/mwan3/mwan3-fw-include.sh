#!/bin/sh
# fw4 script include: triggers mwan3 rule rebuild after firewall reload.
# This runs AFTER fw4 has loaded its nftables ruleset (ACTION=includes phase).
# fw4 blocks UCI access in this shell (overrides config()), so we fork a
# clean shell process for the actual rebuild.

/etc/init.d/mwan3 running || return 0
sh /lib/mwan3/mwan3-fw-rebuild.sh &
return 0
