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

# Only rebuild if rules are actually missing (chain exists but empty)
$NFT list chain inet fw4 mwan3_prerouting 2>/dev/null | grep -q "meta mark" && exit 0

procd_lock

LOG notice "Rebuilding mwan3 rules after fw4 reload"
mwan3_set_connected_sets
mwan3_set_custom_sets
mwan3_set_general_nft
config_foreach mwan3_rebuild_iface_nft interface
mwan3_set_policies_nft
mwan3_set_user_rules

# Signal dnsmasq to clear cache — next client queries will trigger
# fresh upstream resolution which re-populates nft sets via nftset option
killall -HUP dnsmasq 2>/dev/null

exit 0
