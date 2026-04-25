#!/bin/sh
# One-shot migration: scan /etc/config/mwan3 rules for ipset references and
# emit config ipset sections into /etc/config/mwan3, copying family, loadfile
# and inline entry values from /etc/config/firewall where available.
# Safe to run multiple times -- skips sets that already have a mwan3 declaration.

. /lib/functions.sh

LOG_TAG="mwan3-migrate-v4"

config_load mwan3

# Collect set names referenced by any mwan3 rule.
referenced_sets=""
_collect_refs()
{
	local ipset_name ipset_src
	config_get ipset_name "$1" ipset
	config_get ipset_src  "$1" ipset_src
	[ -n "$ipset_name" ] && referenced_sets="$referenced_sets $ipset_name"
	[ -n "$ipset_src"  ] && referenced_sets="$referenced_sets $ipset_src"
}
config_foreach _collect_refs rule

[ -n "$referenced_sets" ] || exit 0

# Collect existing mwan3-side declarations for idempotency.
existing=""
_collect_existing()
{
	local name
	config_get name "$1" name
	[ -n "$name" ] && existing="$existing $name"
}
config_foreach _collect_existing ipset

# For each referenced set not yet declared on the mwan3 side, pick up
# family, loadfile and inline entries from /etc/config/firewall and emit
# a section in /etc/config/mwan3.
for name in $referenced_sets; do
	case " $existing " in *" $name "*) continue ;; esac

	fw4_family=""
	fw4_loadfile=""
	fw4_section=""
	found=0
	_fw4_find()
	{
		local fname
		config_get fname "$1" name
		[ "$fname" = "$name" ] || return
		config_get fw4_family   "$1" family   ipv4
		config_get fw4_loadfile "$1" loadfile
		fw4_section="$1"
		found=1
	}
	reset_cb
	config_load firewall
	config_foreach _fw4_find ipset

	if [ "$found" -eq 1 ]; then
		sid=$(uci -q add mwan3 ipset)
		uci -q set mwan3."$sid".name="$name"
		uci -q set mwan3."$sid".family="$fw4_family"
		[ -n "$fw4_loadfile" ] && uci -q set mwan3."$sid".loadfile="$fw4_loadfile"
		_add_entry() { uci -q add_list mwan3."$sid".entry="$1"; }
		config_list_foreach "$fw4_section" entry _add_entry
		logger -t "$LOG_TAG" \
			"added config ipset '$name' (family=$fw4_family) to /etc/config/mwan3"
		existing="$existing $name"
	else
		logger -t "$LOG_TAG" \
			"WARN: mwan3 rule references set '$name' not found in /etc/config/firewall; declare manually in /etc/config/mwan3 with name, family, and population source"
	fi

	reset_cb
	config_load mwan3
done

uci -q commit mwan3
exit 0
