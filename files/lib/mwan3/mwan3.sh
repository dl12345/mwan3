#!/bin/sh

. "${IPKG_INSTROOT}/usr/share/libubox/jshn.sh"
. "${IPKG_INSTROOT}/lib/mwan3/common.sh"

CONNTRACK_FILE="/proc/net/nf_conntrack"
IPv6_REGEX="([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,7}:|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|"
IPv6_REGEX="${IPv6_REGEX}[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|"
IPv6_REGEX="${IPv6_REGEX}:((:[0-9a-fA-F]{1,4}){1,7}|:)|"
IPv6_REGEX="${IPv6_REGEX}fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|"
IPv6_REGEX="${IPv6_REGEX}::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"
IPv4_REGEX="((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"

DEFAULT_LOWEST_METRIC=256

mwan3_update_dev_to_table()
{
	local _tid
	# shellcheck disable=SC2034
	mwan3_dev_tbl_ipv4=" "
	# shellcheck disable=SC2034
	mwan3_dev_tbl_ipv6=" "

	update_table()
	{
		local family curr_table device enabled
		let _tid++
		config_get family "$1" family ipv4
		network_get_device device "$1"
		[ -z "$device" ] && return
		config_get_bool enabled "$1" enabled
		[ "$enabled" -eq 0 ] && return
		curr_table=$(eval "echo	 \"\$mwan3_dev_tbl_${family}\"")
		export "mwan3_dev_tbl_$family=${curr_table}${device}=$_tid "
	}
	network_flush_cache
	config_foreach update_table interface
}

mwan3_update_iface_to_table()
{
	local _tid
	mwan3_iface_tbl=" "
	update_table()
	{
		let _tid++
		export mwan3_iface_tbl="${mwan3_iface_tbl}${1}=$_tid "
	}
	config_foreach update_table interface
}

mwan3_route_line_dev()
{
	# must have mwan3 config already loaded
	# arg 1 is route device
	local _tid route_line route_device route_family entry curr_table
	route_line=$2
	route_family=$3
	route_device=$(echo "$route_line" | sed -ne "s/.*dev \([^ ]*\).*/\1/p")
	unset "$1"
	[ -z "$route_device" ] && return

	curr_table=$(eval "echo \"\$mwan3_dev_tbl_${route_family}\"")
	for entry in $curr_table; do
		if [ "${entry%%=*}" = "$route_device" ]; then
			_tid=${entry##*=}
			export "$1=$_tid"
			return
		fi
	done
}

# counts how many bits are set to 1
# n&(n-1) clears the lowest bit set to 1
mwan3_count_one_bits()
{
	local count n
	count=0
	n=$(($1))
	while [ "$n" -gt "0" ]; do
		n=$((n&(n-1)))
		count=$((count+1))
	done
	echo $count
}

mwan3_get_iface_id()
{
	local _tmp
	[ -z "$mwan3_iface_tbl" ] && mwan3_update_iface_to_table
	_tmp="${mwan3_iface_tbl##* ${2}=}"
	_tmp=${_tmp%% *}
	export "$1=$_tmp"
}

mwan3_set_custom_set()
{
	local custom_network family_flag IP table_arg

	table_arg="$1"

	for custom_network in $($IP4 route list table "$table_arg" | awk '{print $1}' | grep -E "$IPv4_REGEX"); do
		LOG notice "Adding network $custom_network from table $table_arg to mwan3_custom_v4 set"
		mwan3_nft_push "add element inet fw4 mwan3_custom_v4 { $custom_network }"
	done

	[ $NO_IPV6 -eq 0 ] || return
	for custom_network in $($IP6 route list table "$table_arg" | awk '{print $1}' | grep -E "$IPv6_REGEX"); do
		LOG notice "Adding network $custom_network from table $table_arg to mwan3_custom_v6 set"
		mwan3_nft_push "add element inet fw4 mwan3_custom_v6 { $custom_network }"
	done
}

mwan3_set_custom_sets()
{
	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet fw4 mwan3_custom_v4"
	[ $NO_IPV6 -eq 0 ] && mwan3_nft_push "flush set inet fw4 mwan3_custom_v6"

	config_list_foreach "globals" "rt_table_lookup" mwan3_set_custom_set

	mwan3_nft_batch_commit
}

mwan3_set_connected_ipv4()
{
	local connected_network_v4

	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet fw4 mwan3_connected_v4"

	# Add CIDR routes from the main routing table. Skip host routes — they
	# are either within a CIDR already (local/broadcast from table 0) or are
	# remote destinations that should NOT bypass mwan3.
	for connected_network_v4 in $($IP4 route | awk '{print $1}' | grep -E "$IPv4_REGEX/" | sort -u); do
		mwan3_nft_push "add element inet fw4 mwan3_connected_v4 { $connected_network_v4 }"
	done

	mwan3_nft_push "add element inet fw4 mwan3_connected_v4 { 224.0.0.0/3 }"

	mwan3_nft_batch_commit
}

mwan3_set_connected_ipv6()
{
	local connected_network_v6
	local elements

	[ $NO_IPV6 -eq 0 ] || return

	elements=""
	for connected_network_v6 in $($IP6 route | awk '{print $1}' | grep -E "$IPv6_REGEX" | sort -u); do
		[ -n "$elements" ] && elements="$elements, "
		elements="$elements$connected_network_v6"
	done

	[ -z "$elements" ] && return

	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet fw4 mwan3_connected_v6"
	mwan3_nft_push "add element inet fw4 mwan3_connected_v6 { $elements }"
	mwan3_nft_batch_commit
}

mwan3_set_connected_sets()
{
	mwan3_set_connected_ipv4
	mwan3_set_connected_ipv6
}

mwan3_set_dynamic_sets()
{
	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet fw4 mwan3_dynamic_v4"
	[ $NO_IPV6 -eq 0 ] && mwan3_nft_push "flush set inet fw4 mwan3_dynamic_v6"
	mwan3_nft_batch_commit
}

mwan3_set_general_rules()
{
	local IP

	for IP in "$IP4" "$IP6"; do
		[ "$IP" = "$IP6" ] && [ $NO_IPV6 -ne 0 ] && continue
		RULE_NO=$((MM_BLACKHOLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_BLACKHOLE/$MMX_MASK blackhole
		fi

		RULE_NO=$((MM_UNREACHABLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_UNREACHABLE/$MMX_MASK unreachable
		fi
	done
}

mwan3_set_general_nft()
{
	local chain_exists

	# Check if rules are already populated
	chain_exists=$($NFT list chain inet fw4 mwan3_prerouting 2>/dev/null | grep -c "meta mark")
	[ "$chain_exists" -gt 0 ] && return

	mwan3_nft_batch_start

	# Populate mwan3_connected chain
	mwan3_nft_push "flush chain inet fw4 mwan3_connected"
	mwan3_nft_push "add rule inet fw4 mwan3_connected ip daddr @mwan3_connected_v4 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"
	[ $NO_IPV6 -eq 0 ] && \
		mwan3_nft_push "add rule inet fw4 mwan3_connected ip6 daddr @mwan3_connected_v6 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"

	# Populate mwan3_custom chain
	mwan3_nft_push "flush chain inet fw4 mwan3_custom"
	mwan3_nft_push "add rule inet fw4 mwan3_custom ip daddr @mwan3_custom_v4 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"
	[ $NO_IPV6 -eq 0 ] && \
		mwan3_nft_push "add rule inet fw4 mwan3_custom ip6 daddr @mwan3_custom_v6 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"

	# Populate mwan3_dynamic chain
	mwan3_nft_push "flush chain inet fw4 mwan3_dynamic"
	mwan3_nft_push "add rule inet fw4 mwan3_dynamic ip daddr @mwan3_dynamic_v4 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"
	[ $NO_IPV6 -eq 0 ] && \
		mwan3_nft_push "add rule inet fw4 mwan3_dynamic ip6 daddr @mwan3_dynamic_v6 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"

	# Populate mwan3_prerouting hook chain
	mwan3_nft_push "flush chain inet fw4 mwan3_prerouting"
	# IPv6 RA bypass
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect } accept"
	# Restore mark from conntrack
	# Kernel doesn't support compound "meta mark | ct mark" in one expression,
	# so we use ct mark directly. Since we only restore when meta mark mwan3 bits
	# are 0, and ct mark was saved from meta mark, this is equivalent.
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK == 0 meta mark set ct mark & $MMX_MASK"
	# Jump to interface classification
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_ifaces_in"
	# Check custom/connected/dynamic destinations
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_custom"
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_connected"
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_dynamic"
	# User rules
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_rules"
	# Save mark to conntrack
	# Kernel doesn't support compound "ct mark & X | meta mark & Y", so we
	# save the full meta mark. mwan3 owns its mask bits exclusively.
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting ct mark set meta mark"
	# Post-rules: check custom/connected/dynamic for non-default marks
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_custom"
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_connected"
	mwan3_nft_push "add rule inet fw4 mwan3_prerouting meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_dynamic"

	# Populate mwan3_output hook chain
	mwan3_nft_push "flush chain inet fw4 mwan3_output"
	# Restore mark from conntrack (see prerouting comment above)
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK == 0 meta mark set ct mark & $MMX_MASK"
	# Jump to interface classification
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_ifaces_in"
	# Check custom/connected/dynamic destinations
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_custom"
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_connected"
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_dynamic"
	# User rules
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_rules"
	# Save mark to conntrack (see prerouting comment above)
	mwan3_nft_push "add rule inet fw4 mwan3_output ct mark set meta mark"
	# Post-rules: check custom/connected/dynamic for non-default marks
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_custom"
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_connected"
	mwan3_nft_push "add rule inet fw4 mwan3_output meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_dynamic"

	mwan3_nft_batch_commit
}

mwan3_create_iface_nft()
{
	local id family iface_mark device

	iface_mark=""
	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv6" ] && [ $NO_IPV6 -ne 0 ]; then
		return
	fi

	device="$2"
	iface_mark=$(mwan3_id2mask id MMX_MASK)

	# Check if chain already exists, if so flush it; otherwise create it
	if $NFT list chain inet fw4 "mwan3_iface_in_$1" &>/dev/null; then
		mwan3_nft_exec flush chain inet fw4 "mwan3_iface_in_$1"
	else
		mwan3_nft_exec add chain inet fw4 "mwan3_iface_in_$1"
	fi

	mwan3_nft_batch_start

	# For packets from connected/custom/dynamic sources, mark as default
	if [ "$family" = "ipv4" ]; then
		mwan3_nft_push "add rule inet fw4 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv4 ip saddr @mwan3_connected_v4 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet fw4 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv4 ip saddr @mwan3_custom_v4 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet fw4 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv4 ip saddr @mwan3_dynamic_v4 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
	elif [ "$family" = "ipv6" ]; then
		mwan3_nft_push "add rule inet fw4 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv6 ip6 saddr @mwan3_connected_v6 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet fw4 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv6 ip6 saddr @mwan3_custom_v6 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet fw4 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv6 ip6 saddr @mwan3_dynamic_v6 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
	fi

	# Mark with interface-specific mark
	mwan3_nft_push "add rule inet fw4 mwan3_iface_in_$1 iifname \"$device\" meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $iface_mark $MMX_MASK)"

	mwan3_nft_batch_commit

	# Add jump rule from mwan3_ifaces_in if not already present
	if ! $NFT list chain inet fw4 mwan3_ifaces_in 2>/dev/null | grep -q "jump mwan3_iface_in_$1"; then
		mwan3_nft_exec add rule inet fw4 mwan3_ifaces_in meta mark \& "$MMX_MASK" == 0 jump "mwan3_iface_in_$1"
		LOG debug "create_iface_nft: mwan3_iface_in_$1 added to mwan3_ifaces_in"
	else
		LOG debug "create_iface_nft: mwan3_iface_in_$1 already in mwan3_ifaces_in, skip"
	fi
}

mwan3_rebuild_iface_nft()
{
	local interface="$1"
	local true_iface l3_device up enabled family status_json

	config_get_bool enabled "$interface" enabled 0
	[ "$enabled" -eq 1 ] || return

	config_get family "$interface" family ipv4
	[ "$family" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && return

	mwan3_get_true_iface true_iface "$interface"
	status_json=$(ubus -S call "network.interface.$true_iface" status 2>/dev/null)
	[ -n "$status_json" ] || return

	json_load "$status_json"
	json_get_vars up l3_device
	[ "$up" = "1" ] && [ -n "$l3_device" ] || return

	mwan3_create_iface_nft "$interface" "$l3_device"
}

mwan3_delete_iface_nft()
{
	local family handle

	config_get family "$1" family ipv4

	if [ "$family" = "ipv6" ] && [ $NO_IPV6 -ne 0 ]; then
		return
	fi

	# Remove jump rule from mwan3_ifaces_in
	handle=$($NFT -a list chain inet fw4 mwan3_ifaces_in 2>/dev/null | \
		grep "jump mwan3_iface_in_$1" | sed -n 's/.*# handle \([0-9]*\)/\1/p')
	[ -n "$handle" ] && mwan3_nft_exec delete rule inet fw4 mwan3_ifaces_in handle "$handle"

	# Delete the interface chain
	$NFT list chain inet fw4 "mwan3_iface_in_$1" &>/dev/null && {
		mwan3_nft_exec flush chain inet fw4 "mwan3_iface_in_$1"
		mwan3_nft_exec delete chain inet fw4 "mwan3_iface_in_$1"
	}
}

mwan3_delete_iface_map_entries()
{
	local id iface_mark mapname entry

	mwan3_get_iface_id id "$1"
	[ -n "$id" ] || return 0

	iface_mark=$(mwan3_id2mask id MMX_MASK)

	# Iterate through all sticky maps and remove entries matching this interface's mark
	for mapname in $($NFT list maps inet fw4 2>/dev/null | grep "map mwan3_sticky_" | awk '{print $2}'); do
		$NFT list map inet fw4 "$mapname" 2>/dev/null | \
			grep -oE '[0-9a-f.:]+\s*:\s*'"$(printf '0x%08x' $((iface_mark)))" | \
			while read -r entry; do
				local addr="${entry%%:*}"
				addr=$(echo "$addr" | sed 's/[[:space:]]//g')
				[ -n "$addr" ] && $NFT delete element inet fw4 "$mapname" "{ $addr }" 2>/dev/null
			done
	done
}

mwan3_extra_tables_routes()
{
	$IP route list table "$1"
}

mwan3_get_routes()
{
	{
		$IP route list table main
		config_list_foreach "globals" "rt_table_lookup" mwan3_extra_tables_routes
	} | sed -ne "$MWAN3_ROUTE_LINE_EXP" | sort -u
}

mwan3_create_iface_route()
{
	local tid route_line family IP id tbl
	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ]; then
		IP="$IP6"
	fi

	tbl=$($IP route list table $id 2>/dev/null)$'\n'
	mwan3_update_dev_to_table
	mwan3_get_routes | while read -r route_line; do
		mwan3_route_line_dev "tid" "$route_line" "$family"
		{ [ -z "${route_line##default*}" ] || [ -z "${route_line##fe80::/64*}" ]; } && [ "$tid" != "$id" ] && continue
		if [ -z "$tid" ] || [ "$tid" = "$id" ]; then
			# possible that routes are already in the table
			# if 'connected' was called after 'ifup'
			[ -n "$tbl" ] && [ -z "${tbl##*$route_line$'\n'*}" ] && continue
			$IP route add table $id $route_line ||
				LOG debug "Route '$route_line' already added to table $id"
		fi

	done
}

mwan3_delete_iface_route()
{
	local id family

	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	if [ -z "$id" ]; then
		LOG warn "delete_iface_route: could not find table id for interface $1"
		return 0
	fi

	if [ "$family" = "ipv4" ]; then
		$IP4 route flush table "$id"
	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ]; then
		$IP6 route flush table "$id"
	fi
}

mwan3_create_iface_rules()
{
	local id family IP

	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	mwan3_delete_iface_rules "$1"

	$IP rule add pref $((id+1000)) iif "$2" lookup "$id"
	$IP rule add pref $((id+2000)) fwmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK" lookup "$id"
	$IP rule add pref $((id+3000)) fwmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK" unreachable
}

mwan3_delete_iface_rules()
{
	local id family IP rule_id

	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	for rule_id in $(ip rule list | awk -F : '$1 % 1000 == '$id' && $1 > 1000 && $1 < 4000 {print $1}'); do
		$IP rule del pref $rule_id
	done
}

mwan3_set_policy()
{
	local id iface family metric weight device is_lowest is_offline

	is_lowest=0
	config_get iface "$1" interface
	config_get metric "$1" metric 1
	config_get weight "$1" weight 1

	[ -n "$iface" ] || return 0
	network_get_device device "$iface"
	[ "$metric" -gt $DEFAULT_LOWEST_METRIC ] && LOG warn "Member interface $iface has >$DEFAULT_LOWEST_METRIC metric. Not appending to policy" && return 0

	mwan3_get_iface_id id "$iface"

	[ -n "$id" ] || return 0

	[ "$(mwan3_get_iface_hotplug_state "$iface")" = "online" ]
	is_offline=$?

	config_get family "$iface" family ipv4

	if [ "$family" = "ipv4" ] && [ $is_offline -eq 0 ]; then
		if [ "$metric" -lt "$lowest_metric_v4" ]; then
			is_lowest=1
			total_weight_v4=$weight
			lowest_metric_v4=$metric
		elif [ "$metric" -eq "$lowest_metric_v4" ]; then
			total_weight_v4=$((total_weight_v4+weight))
		else
			return
		fi
	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ] && [ $is_offline -eq 0 ]; then
		if [ "$metric" -lt "$lowest_metric_v6" ]; then
			is_lowest=1
			total_weight_v6=$weight
			lowest_metric_v6=$metric
		elif [ "$metric" -eq "$lowest_metric_v6" ]; then
			total_weight_v6=$((total_weight_v6+weight))
		else
			return
		fi
	fi

	if [ $is_lowest -eq 1 ]; then
		# New lowest metric: reset the member list
		policy_members=""
	fi

	if [ $is_offline -eq 0 ]; then
		# Accumulate members: "iface_name:id:weight" tuples
		policy_members="$policy_members $iface:$id:$weight"
	elif [ -n "$device" ]; then
		# Offline interface with device: record for fallback out-device rule
		policy_offline_devices="$policy_offline_devices $iface:$device"
	fi
}

mwan3_create_policies_nft()
{
	local last_resort lowest_metric_v4 lowest_metric_v6 total_weight_v4 total_weight_v6
	local policy policy_members policy_offline_devices

	policy="$1"
	policy_members=""
	policy_offline_devices=""

	config_get last_resort "$1" last_resort unreachable

	if [ "$1" != "$(echo "$1" | cut -c1-15)" ]; then
		LOG warn "Policy $1 exceeds max of 15 chars. Not setting policy" && return 0
	fi

	# Create chain if it doesn't exist
	$NFT list chain inet fw4 "mwan3_policy_$1" &>/dev/null || \
		mwan3_nft_exec add chain inet fw4 "mwan3_policy_$1"

	mwan3_nft_exec flush chain inet fw4 "mwan3_policy_$1"

	lowest_metric_v4=$DEFAULT_LOWEST_METRIC
	total_weight_v4=0
	lowest_metric_v6=$DEFAULT_LOWEST_METRIC
	total_weight_v6=0

	config_list_foreach "$1" use_member mwan3_set_policy

	# Now build the policy chain rules from accumulated members
	local member iface id weight mark total_weight running map_entries

	# Count and build numgen map entries
	total_weight=0
	for member in $policy_members; do
		weight="${member##*:}"
		total_weight=$((total_weight + weight))
	done

	if [ "$total_weight" -gt 0 ]; then
		if [ "$total_weight" -eq "$(echo "$policy_members" | awk -F: '{print $NF}')" ] && \
		   [ "$(echo "$policy_members" | wc -w)" -eq 1 ]; then
			# Single member: direct mark set, no numgen needed
			member=$(echo "$policy_members" | tr -d ' ')
			id="${member#*:}"
			id="${id%%:*}"
			mark=$(mwan3_id2mask id MMX_MASK)
			mwan3_nft_exec add rule inet fw4 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $mark $MMX_MASK)"
		else
			# Multiple members: use numgen for load balancing
			running=0
			map_entries=""
			for member in $policy_members; do
				iface="${member%%:*}"
				id="${member#*:}"
				id="${id%%:*}"
				weight="${member##*:}"
				mark=$(mwan3_id2mask id MMX_MASK)
				local end=$((running + weight - 1))
				if [ -n "$map_entries" ]; then
					map_entries="$map_entries, "
				fi
				map_entries="${map_entries}${running}-${end} : $mark"
				running=$((end + 1))
			done
			mwan3_nft_exec add rule inet fw4 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				meta mark set "numgen inc mod $total_weight map { $map_entries }"
		fi
	fi

	# Add offline device fallback rules
	local dev_entry offline_iface offline_device
	# Only add if no online members
	if [ "$total_weight" -eq 0 ]; then
		for dev_entry in $policy_offline_devices; do
			offline_iface="${dev_entry%%:*}"
			offline_device="${dev_entry#*:}"
			mwan3_nft_exec add rule inet fw4 "mwan3_policy_$policy" \
				oifname "$offline_device" meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		done
	fi

	# Add last resort rule
	case "$last_resort" in
		blackhole)
			mwan3_nft_exec add rule inet fw4 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_BLACKHOLE $MMX_MASK)"
			;;
		default)
			mwan3_nft_exec add rule inet fw4 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
			;;
		*)
			mwan3_nft_exec add rule inet fw4 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_UNREACHABLE $MMX_MASK)"
			;;
	esac
}

mwan3_set_policies_nft()
{
	config_foreach mwan3_create_policies_nft policy
}

mwan3_set_sticky_nft()
{
	local interface="$1"
	local rule="$2"
	local ipv="$3"
	local policy="$4"

	local id iface mark

	# Check which interfaces are in the policy chain (by examining policy_members)
	for iface in $($NFT list chain inet fw4 "mwan3_policy_$policy" 2>/dev/null | \
			grep "numgen\|meta mark set" | grep -oE '0x[0-9a-f]+' | sort -u); do
		# This is complex; for sticky we need to check if the interface is online
		:
	done

	# For each online interface in the policy, add sticky restore rules
	mwan3_get_iface_id id "$interface"
	[ -n "$id" ] || return 0
	mark=$(mwan3_id2mask id MMX_MASK)

	# Check that interface chain exists (meaning interface is up)
	$NFT list chain inet fw4 "mwan3_iface_in_${interface}" &>/dev/null || return 0

	local sticky_map_name
	if [ "$ipv" = "ipv4" ]; then
		sticky_map_name="mwan3_sticky_v4_${rule}"
	else
		sticky_map_name="mwan3_sticky_v6_${rule}"
	fi

	# Insert rules at beginning of rule chain:
	# If mark matches this interface AND source NOT in sticky map -> clear mark (force re-evaluation)
	# If mark is 0 AND source in sticky map for this interface -> set mark
	# (These are inserted in reverse order since we use 'insert' to prepend)

	# Insert: if mark is zero, try to restore from sticky map
	mwan3_nft_push "insert rule inet fw4 mwan3_rule_$rule meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $mark $MMX_MASK)"
	# Insert before that: if mark matches this iface and src not in sticky, clear mark
	if [ "$ipv" = "ipv4" ]; then
		mwan3_nft_push "insert rule inet fw4 mwan3_rule_$rule meta mark & $MMX_MASK == $mark ip saddr != @$sticky_map_name $(mwan3_nft_mark_expr 0 $MMX_MASK)"
	else
		mwan3_nft_push "insert rule inet fw4 mwan3_rule_$rule meta mark & $MMX_MASK == $mark ip6 saddr != @$sticky_map_name $(mwan3_nft_mark_expr 0 $MMX_MASK)"
	fi
}

mwan3_set_sticky_map()
{
	local rule="$1"
	local timeout="$2"

	$NFT list map inet fw4 "mwan3_sticky_v4_${rule}" &>/dev/null || \
		mwan3_nft_exec add map inet fw4 "mwan3_sticky_v4_${rule}" \
			"{ type ipv4_addr : mark ; flags dynamic,timeout ; timeout ${timeout}s ; }"

	[ $NO_IPV6 -eq 0 ] && {
		$NFT list map inet fw4 "mwan3_sticky_v6_${rule}" &>/dev/null || \
			mwan3_nft_exec add map inet fw4 "mwan3_sticky_v6_${rule}" \
				"{ type ipv6_addr : mark ; flags dynamic,timeout ; timeout ${timeout}s ; }"
	}
}

mwan3_set_user_nft_rule()
{
	local ipset_name family proto policy src_ip src_port src_iface src_dev
	local sticky dest_ip dest_port use_policy timeout policy
	local global_logging rule_logging loglevel rule_policy rule ipv

	rule="$1"
	ipv="$2"
	rule_policy=0
	config_get sticky "$1" sticky 0
	config_get timeout "$1" timeout 600
	config_get ipset_name "$1" ipset
	config_get proto "$1" proto all
	config_get src_ip "$1" src_ip
	config_get src_iface "$1" src_iface
	config_get src_port "$1" src_port
	config_get dest_ip "$1" dest_ip
	config_get dest_port "$1" dest_port
	config_get use_policy "$1" use_policy
	config_get family "$1" family any
	config_get rule_logging "$1" logging 0
	config_get global_logging globals logging 0
	config_get loglevel globals loglevel notice

	[ "$ipv" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && return
	[ "$family" = "ipv4" ] && [ "$ipv" = "ipv6" ] && return
	[ "$family" = "ipv6" ] && [ "$ipv" = "ipv4" ] && return

	for ipaddr in "$src_ip" "$dest_ip"; do
		if [ -n "$ipaddr" ] && { { [ "$ipv" = "ipv4" ] && echo "$ipaddr" | grep -qE "$IPv6_REGEX"; } ||
						 { [ "$ipv" = "ipv6" ] && echo "$ipaddr" | grep -qE $IPv4_REGEX; } }; then
			if [ "$family" = "any" ]; then
				# family "ipv4 and ipv6": silently skip the non-matching pass
				return
			fi
			LOG warn "invalid $ipv address $ipaddr specified for rule $rule"
			return
		fi
	done

	if [ -n "$src_iface" ]; then
		network_get_device src_dev "$src_iface"
		if [ -z "$src_dev" ]; then
			LOG notice "could not find device corresponding to src_iface $src_iface for rule $1"
			return
		fi
	fi

	[ -z "$dest_ip" ] && unset dest_ip
	[ -z "$src_ip" ] && unset src_ip
	[ -z "$ipset_name" ] && unset ipset_name
	[ -z "$src_port" ] && unset src_port
	[ -z "$dest_port" ] && unset dest_port
	if [ "$proto" != 'tcp' ] && [ "$proto" != 'udp' ]; then
		[ -n "$src_port" ] && {
			LOG warn "src_port set to '$src_port' but proto set to '$proto' not tcp or udp. src_port will be ignored"
		}

		[ -n "$dest_port" ] && {
			LOG warn "dest_port set to '$dest_port' but proto set to '$proto' not tcp or udp. dest_port will be ignored"
		}
		unset src_port
		unset dest_port
	fi

	if [ "$1" != "$(echo "$1" | cut -c1-15)" ]; then
		LOG warn "Rule $1 exceeds max of 15 chars. Not setting rule" && return 0
	fi

	if [ -z "$use_policy" ]; then
		return
	fi

	# Build nft match expression
	local nft_match=""

	# Protocol
	if [ "$proto" != "all" ]; then
		nft_match="$nft_match meta l4proto $proto"
	fi

	# Source IP
	if [ -n "$src_ip" ]; then
		if [ "$ipv" = "ipv4" ]; then
			nft_match="$nft_match ip saddr $src_ip"
		else
			nft_match="$nft_match ip6 saddr $src_ip"
		fi
	fi

	# Source interface
	if [ -n "$src_dev" ]; then
		nft_match="$nft_match iifname \"$src_dev\""
	fi

	# Destination IP
	if [ -n "$dest_ip" ]; then
		if [ "$ipv" = "ipv4" ]; then
			nft_match="$nft_match ip daddr $dest_ip"
		else
			nft_match="$nft_match ip6 daddr $dest_ip"
		fi
	fi

	# ipset/nft set match
	if [ -n "$ipset_name" ]; then
		# Pre-create the set if it doesn't exist yet (e.g. dnsmasq nftset
		# hasn't started). nft -f batch fails atomically if any referenced
		# set is missing, which would kill ALL user rules.
		if ! $NFT list set inet fw4 "$ipset_name" &>/dev/null; then
			LOG notice "Creating missing nft set '$ipset_name' for rule $rule"
			if [ "$ipv" = "ipv4" ]; then
				mwan3_nft_push "add set inet fw4 $ipset_name { type ipv4_addr; flags interval; auto-merge; }"
			else
				mwan3_nft_push "add set inet fw4 $ipset_name { type ipv6_addr; flags interval; auto-merge; }"
			fi
		fi
		if [ "$ipv" = "ipv4" ]; then
			nft_match="$nft_match ip daddr @$ipset_name"
		else
			nft_match="$nft_match ip6 daddr @$ipset_name"
		fi
	fi

	# Source port
	if [ -n "$src_port" ]; then
		# Convert comma-separated ports to nft syntax
		local nft_src_port
		nft_src_port=$(echo "$src_port" | sed 's/,/, /g')
		nft_match="$nft_match th sport { $nft_src_port }"
	fi

	# Destination port
	if [ -n "$dest_port" ]; then
		local nft_dest_port
		nft_dest_port=$(echo "$dest_port" | sed 's/,/, /g')
		nft_match="$nft_match th dport { $nft_dest_port }"
	fi

	local policy_action
	if [ "$use_policy" = "default" ]; then
		policy_action="$(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
	elif [ "$use_policy" = "unreachable" ]; then
		policy_action="$(mwan3_nft_mark_expr $MMX_UNREACHABLE $MMX_MASK)"
	elif [ "$use_policy" = "blackhole" ]; then
		policy_action="$(mwan3_nft_mark_expr $MMX_BLACKHOLE $MMX_MASK)"
	else
		rule_policy=1
		policy_action="jump mwan3_policy_$use_policy"

		if [ "$sticky" -eq 1 ]; then
			mwan3_set_sticky_map "$rule" "$timeout"
		fi
	fi

	# Create policy chain if it doesn't exist
	if [ $rule_policy -eq 1 ]; then
		$NFT list chain inet fw4 "mwan3_policy_$use_policy" &>/dev/null || \
			mwan3_nft_push "add chain inet fw4 mwan3_policy_$use_policy"
	fi

	if [ $rule_policy -eq 1 ] && [ "$sticky" -eq 1 ]; then
		# Create sticky rule chain
		$NFT list chain inet fw4 "mwan3_rule_$1" &>/dev/null || \
			mwan3_nft_push "add chain inet fw4 mwan3_rule_$1"
		mwan3_nft_push "flush chain inet fw4 mwan3_rule_$1"

		# Restore mark from sticky map (regular map lookup, not vmap which requires verdicts)
		if [ "$ipv" = "ipv4" ]; then
			mwan3_nft_push "add rule inet fw4 mwan3_rule_$1 meta mark set ip saddr map @mwan3_sticky_v4_${rule}"
		else
			mwan3_nft_push "add rule inet fw4 mwan3_rule_$1 meta mark set ip6 saddr map @mwan3_sticky_v6_${rule}"
		fi

		# Fall through to policy for new flows (mark still 0 means no sticky entry)
		mwan3_nft_push "add rule inet fw4 mwan3_rule_$1 meta mark & $MMX_MASK == 0 jump mwan3_policy_$use_policy"

		# After policy marks, update sticky map
		if [ "$ipv" = "ipv4" ]; then
			mwan3_nft_push "add rule inet fw4 mwan3_rule_$1 meta mark & $MMX_MASK != 0 update @mwan3_sticky_v4_${rule} { ip saddr timeout ${timeout}s : meta mark & $MMX_MASK }"
		else
			mwan3_nft_push "add rule inet fw4 mwan3_rule_$1 meta mark & $MMX_MASK != 0 update @mwan3_sticky_v6_${rule} { ip6 saddr timeout ${timeout}s : meta mark & $MMX_MASK }"
		fi

		policy_action="jump mwan3_rule_$1"
	fi

	# Add logging rule if enabled
	if [ "$global_logging" = "1" ] && [ "$rule_logging" = "1" ]; then
		mwan3_nft_push "add rule inet fw4 mwan3_rules $nft_match meta mark & $MMX_MASK == 0 log prefix \"MWAN3($1)\" level $loglevel"
	fi

	# Add the actual rule
	mwan3_nft_push "add rule inet fw4 mwan3_rules $nft_match meta mark & $MMX_MASK == 0 $policy_action"
}

mwan3_set_user_iface_rules()
{
	local iface device is_src_iface
	iface=$1
	device=$2

	if [ -z "$device" ]; then
		LOG notice "set_user_iface_rules: could not find device corresponding to iface $iface"
		return
	fi

	# Check if rules already reference this device
	$NFT list chain inet fw4 mwan3_rules 2>/dev/null | grep -q "iifname \"$device\"" && return

	is_src_iface=0

	iface_rule()
	{
		local src_iface
		config_get src_iface "$1" src_iface
		[ "$src_iface" = "$iface" ] && is_src_iface=1
	}
	config_foreach iface_rule rule
	[ $is_src_iface -eq 1 ] && mwan3_set_user_rules
}

mwan3_set_user_rules()
{
	local ipv

	mwan3_nft_batch_start

	mwan3_nft_push "flush chain inet fw4 mwan3_rules"

	for ipv in ipv4 ipv6; do
		[ "$ipv" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && continue
		config_foreach mwan3_set_user_nft_rule rule "$ipv"
	done

	mwan3_nft_batch_commit
}

mwan3_interface_hotplug_shutdown()
{
	local interface status device ifdown
	interface="$1"
	ifdown="$2"
	[ -f $MWAN3TRACK_STATUS_DIR/$interface/STATUS ] && {
		readfile status $MWAN3TRACK_STATUS_DIR/$interface/STATUS
	}

	[ "$status" != "online" ] && [ "$ifdown" != 1 ] && return

	if [ "$ifdown" = 1 ]; then
		env -i ACTION=ifdown \
			INTERFACE=$interface \
			DEVICE=$device \
			sh /etc/hotplug.d/iface/25-mwan3
	else
		[ "$status" = "online" ] && {
			env -i MWAN3_SHUTDOWN="1" \
				ACTION="disconnected" \
				INTERFACE="$interface" \
				DEVICE="$device" /sbin/hotplug-call iface
		}
	fi

}

mwan3_interface_shutdown()
{
	mwan3_interface_hotplug_shutdown $1
	mwan3_track_clean $1
}

mwan3_ifup()
{
	local interface=$1
	local caller=$2

	local up l3_device status true_iface

	if [ "${caller}" = "cmd" ]; then
		# It is not necessary to obtain a lock here, because it is obtained in the hotplug
		# script, but we still want to do the check to print a useful error message
		/etc/init.d/mwan3 running || {
			echo 'The service mwan3 is global disabled.'
			echo 'Please execute "/etc/init.d/mwan3 start" first.'
			exit 1
		}
		config_load mwan3
	fi
	mwan3_get_true_iface true_iface $interface
	status=$(ubus -S call network.interface.$true_iface status)

	[ -n "$status" ] && {
		json_load "$status"
		json_get_vars up l3_device
	}
	hotplug_startup()
	{
		env -i MWAN3_STARTUP=$caller ACTION=ifup \
		    INTERFACE=$interface DEVICE=$l3_device \
		    sh /etc/hotplug.d/iface/25-mwan3
	}

	if [ "$up" != "1" ] || [ -z "$l3_device" ]; then
		return
	fi

	if [ "${caller}" = "init" ]; then
		hotplug_startup &
		hotplug_pids="$hotplug_pids $!"
	else
		hotplug_startup
	fi

}

mwan3_set_iface_hotplug_state() {
	local iface=$1
	local state=$2

	echo "$state" > "$MWAN3_STATUS_DIR/iface_state/$iface"
}

mwan3_get_iface_hotplug_state() {
	local iface=$1
	local state=offline
	readfile state "$MWAN3_STATUS_DIR/iface_state/$iface"
	echo "$state"
}

mwan3_report_iface_status()
{
	local device result tracking IP
	local status online uptime result

	mwan3_get_iface_id id "$1"
	network_get_device device "$1"
	config_get_bool enabled "$1" enabled 0
	config_get family "$1" family ipv4

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	fi

	if [ "$family" = "ipv6" ]; then
		IP="$IP6"
	fi

	if [ -f "$MWAN3TRACK_STATUS_DIR/${1}/STATUS" ]; then
		readfile status "$MWAN3TRACK_STATUS_DIR/${1}/STATUS"
	else
		status="unknown"
	fi

	if [ "$status" = "online" ]; then
		get_online_time online "$1"
		network_get_uptime uptime "$1"
		online="$(printf '%02dh:%02dm:%02ds\n' $((online/3600)) $((online%3600/60)) $((online%60)))"
		uptime="$(printf '%02dh:%02dm:%02ds\n' $((uptime/3600)) $((uptime%3600/60)) $((uptime%60)))"
		result="$(mwan3_get_iface_hotplug_state $1) $online, uptime $uptime"
	else
		result=0
		[ -n "$($IP rule | awk '$1 == "'$((id+1000)):'"')" ] ||
			result=$((result+1))
		[ -n "$($IP rule | awk '$1 == "'$((id+2000)):'"')" ] ||
			result=$((result+2))
		[ -n "$($IP rule | awk '$1 == "'$((id+3000)):'"')" ] ||
			result=$((result+4))
		[ -n "$($NFT list chain inet fw4 mwan3_iface_in_$1 2>/dev/null)" ] ||
			result=$((result+8))
		[ -n "$($IP route list table $id default dev $device 2> /dev/null)" ] ||
			result=$((result+16))
		[ "$result" = "0" ] && result=""
	fi

	mwan3_get_mwan3track_status tracking $1
	if [ -n "$result" ]; then
		echo " interface $1 is $status and tracking is $tracking ($result)"
	else
		echo " interface $1 is $status and tracking is $tracking"
	fi
}

mwan3_mark_to_name()
{
	local target="$1" entry iface _id _mark
	[ -z "$mwan3_iface_tbl" ] && mwan3_update_iface_to_table
	for entry in $mwan3_iface_tbl; do
		[ -z "$entry" ] && continue
		iface="${entry%%=*}"
		_id="${entry#*=}"
		[ -z "$_id" ] && continue
		_mark=$(mwan3_id2mask _id MMX_MASK)
		# Arithmetic comparison to handle format differences (0x100 vs 0x00000100)
		[ $((_mark)) -eq $((target)) ] && echo "$iface" && return
	done
	[ $((target)) -eq $((MMX_DEFAULT)) ] && echo "default" && return
	[ $((target)) -eq $((MMX_BLACKHOLE)) ] && echo "blackhole" && return
	[ $((target)) -eq $((MMX_UNREACHABLE)) ] && echo "unreachable" && return
	echo "$target"
}

mwan3_report_policies()
{
	local policy="$1"
	local output iface weight total mark

	output=$($NFT list chain inet fw4 "mwan3_policy_$policy" 2>/dev/null)
	[ -z "$output" ] && return

	# Check if numgen is used (load balancing)
	if echo "$output" | grep -q "numgen"; then
		# Parse numgen map entries to extract marks and weights
		# Format: numgen inc mod N map { 0-2 : 0xMARK1, 3-5 : 0xMARK2, ... }
		# Note: nft may wrap the map across multiple lines
		total=$(echo "$output" | grep -oE 'mod [0-9]+' | awk '{print $2}')
		# Extract ranges from entire output (map may span lines)
		echo "$output" | grep -oE '[0-9]+-[0-9]+ : 0x[0-9a-f]+' | while read -r entry; do
			local range_start range_end mark_val
			range_start="${entry%%-*}"
			entry="${entry#*-}"
			range_end="${entry%% *}"
			mark_val="${entry##* }"
			weight=$((range_end - range_start + 1))
			local percent=$((weight * 100 / total))
			echo " $(mwan3_mark_to_name "$mark_val") ($percent%)"
		done
	else
		# Single member or last resort — extract mark and resolve to name
		local mark_line mark_val
		mark_line=$(echo "$output" | grep "meta mark set" | head -1)
		if [ -n "$mark_line" ]; then
			mark_val=$(echo "$mark_line" | grep -oE '0x[0-9a-f]+' | tail -1)
			echo " $(mwan3_mark_to_name "$mark_val")"
		fi
	fi
}

mwan3_report_policies_v4()
{
	_report_one_policy() {
		local output
		output=$($NFT list chain inet fw4 "mwan3_policy_$1" 2>/dev/null)
		[ -z "$output" ] && return
		echo "$1:"
		mwan3_report_policies "$1"
	}
	config_foreach _report_one_policy policy
}

mwan3_report_policies_v6()
{
	# With nftables inet family, policies are shared; report same as v4
	mwan3_report_policies_v4
}

mwan3_report_connected_v4()
{
	$NFT list set inet fw4 mwan3_connected_v4 2>/dev/null | \
		sed -n '/elements/,/}/p' | grep -oE "$IPv4_REGEX(/[0-9]+)?"
}

mwan3_report_connected_v6()
{
	[ $NO_IPV6 -ne 0 ] && return
	$NFT list set inet fw4 mwan3_connected_v6 2>/dev/null | \
		sed -n '/elements/,/}/p' | grep -oE "$IPv6_REGEX(/[0-9]+)?"
}

mwan3_report_rules_v4()
{
	$NFT list chain inet fw4 mwan3_rules 2>/dev/null | \
		grep -v "^[[:space:]]*$\|^table \|^[[:space:]]*chain \|^[[:space:]]*type \|^[[:space:]]*policy \|{$\|^[[:space:]]*}$" | \
		sed 's/^[[:space:]]*/ /; s/jump mwan3_policy_/- /; s/jump mwan3_rule_/S /'
}

mwan3_report_rules_v6()
{
	# With nftables inet family, rules are shared; report same as v4
	mwan3_report_rules_v4
}

mwan3_flush_conntrack()
{
	local interface="$1"
	local action="$2"

	handle_flush() {
		local flush_conntrack="$1"
		local action="$2"

		if [ "$action" = "$flush_conntrack" ]; then
			echo f > ${CONNTRACK_FILE}
			LOG info "Connection tracking flushed for interface '$interface' on action '$action'"
		fi
	}

	if [ -e "$CONNTRACK_FILE" ]; then
		config_list_foreach "$interface" flush_conntrack handle_flush "$action"
	fi
}

mwan3_track_clean()
{
	rm -rf "${MWAN3_STATUS_DIR:?}/${1}" &> /dev/null
	rmdir --ignore-fail-on-non-empty "$MWAN3_STATUS_DIR"
}
