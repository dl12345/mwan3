#!/bin/sh
# Rebuild mwan3 dynamic rules after fw4 reload.
# Called from mwan3-fw-include.sh as a background process with a clean
# shell environment (no fw4 UCI blocking).
#
# This handles the case where /etc/init.d/firewall restart (or any
# manual fw4 reload) wipes all dynamic mwan3 rules from table inet fw4.
# The static skeleton from 10-mwan3.nft survives but is empty.

. /lib/functions.sh
. /lib/functions/network.sh
. /lib/mwan3/mwan3.sh

initscript=/etc/init.d/mwan3
. /lib/functions/procd.sh

SCRIPTNAME="mwan3-fw-rebuild"
mwan3_init

procd_lock

# Re-check under lock: 25-mwan3 may have rebuilt while we were waiting.
$NFT list chain inet fw4 mwan3_prerouting 2>/dev/null | grep -q "meta mark" && exit 0

LOG notice "Rebuilding mwan3 rules after fw4 reload"
mwan3_set_connected_sets
mwan3_set_custom_sets
mwan3_set_dynamic_sets
config_foreach mwan3_rebuild_iface_nft interface
mwan3_set_general_nft
mwan3_set_policies_nft
mwan3_set_user_rules

# Signal dnsmasq to clear cache - next client queries will trigger
# fresh upstream resolution which re-populates nft sets via nftset option.
# Multiple rebuild paths (fw4 include and 25-mwan3 hotplug) can both call
# mwan3_dnsmasq_hup in close succession. A ubus event coalescing daemon
# (analogous to mwan3rtmon's debounce pattern) could eliminate this, but
# the bootstrapping dependency, silent-failure risk, and the fact that
# dnsmasq_hup is currently the only candidate make it premature. Revisit
# if a second coalesceable operation emerges.
mwan3_dnsmasq_hup
mwan3_flush_stale_conntrack

exit 0
