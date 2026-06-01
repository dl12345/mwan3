#!/bin/sh

. "${IPKG_INSTROOT}/usr/share/libubox/jshn.sh"
. "${IPKG_INSTROOT}/lib/mwan3/common.sh"

CONNTRACK_FILE="/proc/net/nf_conntrack"
MWAN3IPCHECK="mwan3ipcheck"

DEFAULT_LOWEST_METRIC=256


mwan3_dnsmasq_hup()
{
	ubus call service signal '{"name":"dnsmasq","signal":1}' >/dev/null 2>&1
}

mwan3_flush_stale_conntrack()
{
	# After an fw4 rebuild or mwan3 restart, conntrack entries created during
	# the rule-rebuild window have ct mark=0 (iface_in chains were absent).
	# WireGuard persistent-keepalive and similar long-lived UDP traffic can
	# keep these zero-mark entries alive indefinitely, causing persistent
	# misrouting. Flush only zero-mark entries; correctly-marked connections
	# are untouched. Requires conntrack-tools; logs a warning if absent.

	[ -e "$CONNTRACK_FILE" ] || return
	mwan3ct flush --mark "0x0/$MMX_MASK" 2>/dev/null
	LOG notice "Flushed zero-mark conntrack entries"
}

mwan3_flush_marked_conntrack()
{
	# Flush every conntrack entry whose mark has any mwan3 (MMX_MASK) bit
	# set. Used on `service mwan3 reload` / uci-commit-triggered reload so
	# live flows re-enter the classification chains and re-evaluate
	# against the new rules instead of staying pinned to a previously
	# saved ct mark.
	#
	# Complements mwan3_flush_stale_conntrack (zero-mark only). The two
	# cover distinct cleanup needs:
	#   stale  : flow slipped through unclassified (fw4-rebuild window)
	#   marked : policy changed after the flow was classified
	#
	# conntrack's -D --mark VALUE/MASK filter does exact-match on the
	# masked bits; there is no "any bit set" predicate. We therefore
	# iterate the mwan3 id-space (default 6 bits => 63 ids) and issue
	# one targeted -D per id. Bounded and fast.

	[ -e "$CONNTRACK_FILE" ] || return
	mwan3ct flush --mark-any "$MMX_MASK" 2>/dev/null
	LOG notice "Flushed mwan3-marked conntrack entries for reclassification"
}

mwan3_flush_unreplied_conntrack()
{
	[ -e "$CONNTRACK_FILE" ] || return
	mwan3ct flush --mark-any "$MMX_MASK" --status 0/0x2 2>/dev/null
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
	local custom_network table_arg

	table_arg="$1"

	for custom_network in $(${MWAN3_LIST_ROUTES} 4 "$table_arg"); do
		mwan3_nft_push "add element inet mwan3 mwan3_custom_v4 { $custom_network }"
	done

	[ $NO_IPV6 -eq 0 ] || return
	for custom_network in $(${MWAN3_LIST_ROUTES} 6 "$table_arg"); do
		mwan3_nft_push "add element inet mwan3 mwan3_custom_v6 { $custom_network }"
	done
}

mwan3_set_custom_sets()
{
	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet mwan3 mwan3_custom_v4"
	[ $NO_IPV6 -eq 0 ] && mwan3_nft_push "flush set inet mwan3 mwan3_custom_v6"

	config_list_foreach "globals" "rt_table_lookup" mwan3_set_custom_set

	mwan3_nft_batch_commit
}

mwan3_set_connected_ipv4()
{
	local connected_network_v4

	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet mwan3 mwan3_connected_v4"

	for connected_network_v4 in $(${MWAN3_LIST_ROUTES} 4 main); do
		mwan3_nft_push "add element inet mwan3 mwan3_connected_v4 { $connected_network_v4 }"
	done

	mwan3_nft_push "add element inet mwan3 mwan3_connected_v4 { 224.0.0.0/3 }"

	mwan3_nft_batch_commit
}

mwan3_set_connected_ipv6()
{
	local connected_network_v6
	local elements

	[ $NO_IPV6 -eq 0 ] || return

	elements=""
	for connected_network_v6 in $(${MWAN3_LIST_ROUTES} 6 main); do
		[ -n "$elements" ] && elements="$elements, "
		elements="$elements$connected_network_v6"
	done

	[ -z "$elements" ] && return

	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet mwan3 mwan3_connected_v6"
	mwan3_nft_push "add element inet mwan3 mwan3_connected_v6 { $elements }"
	mwan3_nft_batch_commit
}

mwan3_set_connected_sets()
{
	mwan3_set_connected_ipv4
	mwan3_set_connected_ipv6
}

mwan3_set_dynamic_network()
{
	local network="$1"
	case "$network" in
		*:*) [ $NO_IPV6 -eq 0 ] && {
			LOG notice "Adding bypass_network $network to mwan3_dynamic_v6 set"
			mwan3_nft_push "add element inet mwan3 mwan3_dynamic_v6 { $network }"
		} ;;
		*.*) LOG notice "Adding bypass_network $network to mwan3_dynamic_v4 set"
			mwan3_nft_push "add element inet mwan3 mwan3_dynamic_v4 { $network }" ;;
	esac
}

mwan3_set_dynamic_sets()
{
	mwan3_nft_batch_start
	mwan3_nft_push "flush set inet mwan3 mwan3_dynamic_v4"
	[ $NO_IPV6 -eq 0 ] && mwan3_nft_push "flush set inet mwan3 mwan3_dynamic_v6"

	config_list_foreach "globals" "bypass_network" mwan3_set_dynamic_network

	mwan3_nft_batch_commit
}

# Convert an nft time string (1h, 5m, 300s, 3600) to seconds.
# Used when comparing a config timeout value against the kernel's display value.

_mwan3_nft_time_to_sec()
{
	local t="$1" n u
	n="${t%[smhdwSMHDW]}"
	u="${t#$n}"
	case "$u" in
		s|S|"") printf '%s\n' "$n" ;;
		m|M)    printf '%s\n' "$((n * 60))" ;;
		h|H)    printf '%s\n' "$((n * 3600))" ;;
		d|D)    printf '%s\n' "$((n * 86400))" ;;
		w|W)    printf '%s\n' "$((n * 604800))" ;;
		*)      printf '%s\n' "$n" ;;
	esac
}

# Return 0 (true) if the named set exists in the kernel AND its flags differ
# from the desired spec; return 1 otherwise (set absent, or flags all match).
# Used during reload to decide whether to queue a delete before recreating.
#   $1 name         -- set name
#   $2 want_type    -- ipv4_addr or ipv6_addr
#   $3 want_counter -- 0 or 1
#   $4 want_timeout -- 0 (none) or timeout in seconds
#   $5 want_maxelem -- 0 (default) or explicit element limit

_mwan3_ipset_needs_delete()
{
	local name="$1" want_type="$2" want_counter="$3" want_timeout="$4" want_maxelem="$5"
	local out cur_type has_counter has_timeout_flag cur_timeout_raw cur_timeout_sec cur_size

	out=$($NFT list set inet mwan3 "$name" 2>/dev/null) || return 1  # absent -- no delete

	cur_type=$(printf '%s\n' "$out" | awk '/^[[:space:]]+type[[:space:]]/{print $2; exit}')
	[ "$cur_type" != "$want_type" ] && return 0

	# 'counter' as a standalone keyword line; does not match 'counter packets N bytes N'
	# in elements because those lines are indented inside 'elements = { ... }'.

	has_counter=0
	printf '%s\n' "$out" | grep -qE '^[[:space:]]+counter[[:space:]]*$' && has_counter=1
	[ "$has_counter" -ne "$want_counter" ] && return 0

	has_timeout_flag=0
	printf '%s\n' "$out" | grep -q 'flags.*timeout' && has_timeout_flag=1
	if [ "$want_timeout" -gt 0 ]; then
		[ "$has_timeout_flag" -eq 0 ] && return 0
		cur_timeout_raw=$(printf '%s\n' "$out" | awk '/^[[:space:]]+timeout[[:space:]]/{print $2; exit}')
		cur_timeout_sec=$(_mwan3_nft_time_to_sec "$cur_timeout_raw")
		[ "$cur_timeout_sec" != "$want_timeout" ] && return 0
	else
		[ "$has_timeout_flag" -ne 0 ] && return 0
	fi

	cur_size=$(printf '%s\n' "$out" | awk '/^[[:space:]]+size[[:space:]]/{print $2; exit}')
	if [ "$want_maxelem" -gt 0 ]; then
		[ "$cur_size" != "$want_maxelem" ] && return 0
	else
		[ -n "$cur_size" ] && return 0
	fi

	return 1  # all flags match
}

# Render one config ipset section from /etc/config/mwan3 into table inet mwan3.
# Called by config_foreach from mwan3_render_config_ipsets.

_mwan3_render_one_ipset()
{
	local section="$1"
	local enabled name family maxelem timeout loadfile counters
	local addr_type set_flags set_decl

	config_get_bool enabled  "$section" enabled  1
	[ "$enabled" -eq 1 ] || return 0

	config_get name     "$section" name
	config_get family   "$section" family   ipv4
	config_get maxelem  "$section" maxelem  0
	config_get timeout  "$section" timeout  0
	config_get loadfile "$section" loadfile
	config_get_bool counters "$section" counters 0

	[ -n "$name" ] || { LOG warn "config ipset section '$section' missing 'name'"; return 0; }

	case "$family" in
		ipv4) addr_type="ipv4_addr" ;;
		ipv6) addr_type="ipv6_addr" ;;
		*)    LOG warn "config ipset '$name': unknown family '$family'"; return 0 ;;
	esac

	set_decl="type ${addr_type}; flags interval"
	[ "$timeout" -gt 0 ] && set_decl="$set_decl, timeout"
	set_decl="$set_decl; auto-merge;"
	[ "$counters" -eq 1 ] && set_decl="$set_decl counter;"
	[ "$timeout" -gt 0 ] && set_decl="$set_decl timeout ${timeout}s;"
	[ "$maxelem" -gt 0 ] && set_decl="$set_decl size ${maxelem};"

	# Delete-and-recreate when flags change so the new spec takes effect.
	# On the start path (BATCH_DEPTH=0): always delete immediately -- no rules
	# exist yet; suppress the error if the set is absent.
	# On the reload path (BATCH_DEPTH>0): only delete when flags actually differ.
	# The preamble (mwan3_nft_reload_start) has already queued a flush of
	# mwan3_rules and all dynamic chains, so all references to user sets are
	# removed before the delete fires at commit time. When flags are unchanged
	# the 'add set' below is idempotent and dnsmasq-populated elements survive.

	if [ "$MWAN3_BATCH_DEPTH" -eq 0 ]; then
		$NFT delete set inet mwan3 "$name" >/dev/null 2>&1
	elif _mwan3_ipset_needs_delete "$name" "$addr_type" "$counters" "$timeout" "$maxelem"; then
		mwan3_nft_push "delete set inet mwan3 $name"
		local _dom_found=""
		_mwan3_hup_check() { _dom_found=1; }
		config_list_foreach "$section" domain _mwan3_hup_check
		[ -n "$_dom_found" ] && MWAN3_NEED_DNSMASQ_HUP=1
	fi

	# Collect all elements (inline list + loadfile) before entering batch.
	local elements="" line
	_add_entry() { elements="${elements:+$elements, }$1"; }
	config_list_foreach "$section" entry _add_entry
	if [ -n "$loadfile" ] && [ -f "$loadfile" ]; then
		while IFS= read -r line; do
			line="${line%%#*}"
			line=$(echo "$line" | xargs 2>/dev/null)
			[ -n "$line" ] && elements="${elements:+$elements, }$line"
		done < "$loadfile"
	fi

	# nft CLI cannot parse { ... } as a single quoted argument; use batch mode.

	mwan3_nft_batch_start
	mwan3_nft_push "add set inet mwan3 $name { $set_decl }"
	[ -n "$elements" ] && mwan3_nft_push "add element inet mwan3 $name { $elements }"
	mwan3_nft_batch_commit || return 1
}

# Create all user-declared sets from config ipset sections in /etc/config/mwan3.
# Must be called after mwan3_ensure_nft_framework and before mwan3_set_user_rules.

mwan3_render_config_ipsets()
{
	config_foreach _mwan3_render_one_ipset ipset
}

# Delete user-defined nft sets that exist in the kernel but are no longer in
# the current config. Must be called inside the reload batch so that the kernel
# still reflects pre-commit state (making the query accurate) and so that the
# deletes are queued via mwan3_nft_push rather than executed immediately.

mwan3_cleanup_orphaned_ipsets()
{
	local setname config_names="" n found

	_collect_configured_name() {
		local enabled name
		config_get_bool enabled "$1" enabled 1
		[ "$enabled" -eq 1 ] || return 0
		config_get name "$1" name
		[ -n "$name" ] && config_names="${config_names} $name"
	}
	config_foreach _collect_configured_name ipset

	for setname in $($NFT list table inet mwan3 2>/dev/null | \
	                 awk '$1 == "set" && $2 !~ /^mwan3_/ {print $2}'); do
		found=0
		for n in $config_names; do
			[ "$n" = "$setname" ] && found=1 && break
		done
		[ "$found" -eq 0 ] && mwan3_nft_push "delete set inet mwan3 $setname"
	done
}

# Write per-instance dnsmasq confdir fragments containing nftset= directives
# for all mwan3 config ipset sections that have list domain entries.
# Triggers /etc/init.d/dnsmasq reload only if any fragment content changed.

mwan3_write_dnsmasq_fragments()
{
	local any_changed=0

	_wdf_collect_mappings()
	{
		local section="$1" mapfile="$2"
		local enabled name family fam_ch elements

		config_get_bool enabled "$section" enabled 1
		[ "$enabled" -eq 1 ] || return
		config_get name   "$section" name
		config_get family "$section" family ipv4
		[ -n "$name" ] || return

		elements=""
		_check_domain() { elements="yes"; }
		config_list_foreach "$section" domain _check_domain
		[ -n "$elements" ] || return

		[ "$family" = "ipv4" ] && fam_ch=4 || fam_ch=6

		_record_mapping()
		{
			printf '%s %s\n' "$1" "$fam_ch#inet#mwan3#$name" >> "$mapfile"
		}
		config_list_foreach "$section" domain _record_mapping
	}

	_wdf_emit_grouped()
	{
		local mapfile="$1"
		local prev_domain="" sets="" domain setspec sorted

		[ -s "$mapfile" ] || return

		sorted="${mapfile}.sorted"
		LC_ALL=C sort -u "$mapfile" > "$sorted"
		while IFS=' ' read -r domain setspec; do
			if [ "$domain" != "$prev_domain" ]; then
				[ -n "$prev_domain" ] && printf 'nftset=/%s/%s\n' "$prev_domain" "$sets"
				prev_domain="$domain"
				sets="$setspec"
			else
				sets="$sets,$setspec"
			fi
		done < "$sorted"
		[ -n "$prev_domain" ] && printf 'nftset=/%s/%s\n' "$prev_domain" "$sets"
		rm -f "$sorted"
	}

	_wdf_for_instance()
	{
		local cfg="$1"
		local confdir final tmp

		config_get confdir "$cfg" confdir "/tmp/dnsmasq${cfg:+.$cfg}.d"
		final="${confdir}/mwan3-nftsets.conf"
		tmp="${MWAN3_STATUS_DIR}/dnsmasq-nftset.${cfg:-default}.$$"

		mkdir -p "$confdir"

		(
			config_load mwan3
			_mapfile="${MWAN3_STATUS_DIR}/dnsmasq-nftset-map.${cfg:-default}.$$"
			: > "$_mapfile"
			config_foreach _wdf_collect_mappings ipset "$_mapfile"
			_wdf_emit_grouped "$_mapfile"
			rm -f "$_mapfile"
		) > "$tmp"

		if [ ! -s "$tmp" ]; then
			# No domain entries: remove stale fragment if present
			rm -f "$tmp"
			if [ -f "$final" ]; then
				rm -f "$final"
				any_changed=1
			fi
		elif ! cmp -s "$tmp" "$final" 2>/dev/null; then
			mv -f "$tmp" "$final"
			any_changed=1
		else
			rm -f "$tmp"
		fi
	}

	config_load dhcp
	config_foreach _wdf_for_instance dnsmasq

	# Restore mwan3 config context: config_load dhcp above replaces it,
	# and callers (start_service) still need to iterate mwan3 sections.

	config_load mwan3

	# restart (not reload) so dnsmasq re-reads the confdir and picks up new
	# nftset directives. At boot, dnsmasq hasn't started yet (START=60 > mwan3
	# START=20), so skip the restart -- dnsmasq will find the fragment when it
	# starts naturally.

	[ "$any_changed" -eq 1 ] && pidof dnsmasq >/dev/null 2>&1 && \
		/etc/init.d/dnsmasq restart
}

mwan3_set_general_rules()
{
	${MWAN3_MANAGE_RULES} add-general \
		4 "$((MM_BLACKHOLE+MWAN3_FWMARK_RULE_BASE))" "$MMX_BLACKHOLE" \
		  "$((MM_UNREACHABLE+MWAN3_FWMARK_RULE_BASE))" "$MMX_UNREACHABLE" \
		  "$MMX_MASK"
	[ $NO_IPV6 -eq 0 ] || return
	${MWAN3_MANAGE_RULES} add-general \
		6 "$((MM_BLACKHOLE+MWAN3_FWMARK_RULE_BASE))" "$MMX_BLACKHOLE" \
		  "$((MM_UNREACHABLE+MWAN3_FWMARK_RULE_BASE))" "$MMX_UNREACHABLE" \
		  "$MMX_MASK"
}

mwan3_set_general_nft()
{
	local chain_exists restore_vmap save_vmap all_marks

	# Check if rules are already populated (skip inside a batch: kernel still
	# shows old rules since the preamble teardown is queued but not committed)

	if [ "$MWAN3_BATCH_DEPTH" -eq 0 ]; then
		chain_exists=$($NFT list chain inet mwan3 mwan3_prerouting 2>/dev/null | grep -c "meta mark")
		[ "$chain_exists" -gt 0 ] && return
	fi

	# Build (idempotently) the per-mark OR-immediate setter chains used by
	# the non-destructive restore/save vmap dispatch below. These chains
	# must exist before any rule that jumps to them.

	mwan3_build_or_chains_nft

	all_marks=$(mwan3_all_marks)
	restore_vmap=$(mwan3_or_vmap_body meta $all_marks)
	save_vmap=$(mwan3_or_vmap_body ct $all_marks)

	mwan3_nft_batch_start

	# Populate mwan3_connected chain

	mwan3_nft_push "flush chain inet mwan3 mwan3_connected"
	mwan3_nft_push "add rule inet mwan3 mwan3_connected ip daddr @mwan3_connected_v4 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"
	[ $NO_IPV6 -eq 0 ] && \
		mwan3_nft_push "add rule inet mwan3 mwan3_connected ip6 daddr @mwan3_connected_v6 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"

	# Populate mwan3_custom chain

	mwan3_nft_push "flush chain inet mwan3 mwan3_custom"
	mwan3_nft_push "add rule inet mwan3 mwan3_custom ip daddr @mwan3_custom_v4 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"
	[ $NO_IPV6 -eq 0 ] && \
		mwan3_nft_push "add rule inet mwan3 mwan3_custom ip6 daddr @mwan3_custom_v6 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"

	# Populate mwan3_dynamic chain

	mwan3_nft_push "flush chain inet mwan3 mwan3_dynamic"
	mwan3_nft_push "add rule inet mwan3 mwan3_dynamic ip daddr @mwan3_dynamic_v4 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"
	[ $NO_IPV6 -eq 0 ] && \
		mwan3_nft_push "add rule inet mwan3 mwan3_dynamic ip6 daddr @mwan3_dynamic_v6 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK) return"

	# Populate mwan3_prerouting hook chain

	mwan3_nft_push "flush chain inet mwan3 mwan3_prerouting"

	# IPv6 RA bypass

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect } accept"

	# Clear mwan3's mark bits on ingress, before the restore below. A packet
	# decapsulated from a tunnel WAN (a tunnel broker or an L2TP link, for
	# example) can inherit the outer packet's skb mark, so it can arrive
	# already carrying mwan3 bits. That stale mark would skip the conntrack
	# restore (which is guarded on the mark being clear) and then be saved
	# back to the connection, clobbering the real classification and pinning
	# later packets of the flow to the wrong table. Re-deriving from a clean
	# slate fixes this; it is a no-op for ordinary traffic and preserves bits
	# outside mwan3's mask. The inherited mark is independent of the inner
	# address family, and mwan3 owns its mask exclusively (pbr and fw4 use
	# disjoint bits), so the clear is unconditional and covers IPv4 and IPv6.

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark set meta mark & $MMX_MASK_COMPLEMENT"

	# Bypass single-link IPv6 destinations: link-local unicast (fe80::/10)
	# and interface-/link-scope multicast (ff01::/16, ff02::/16) are confined
	# to one link by definition (RFC 4291) and must never be policy-routed or
	# ct-marked. Keeps inbound link-local flows (e.g. DHCPv6 Solicits to
	# ff02::1:2) out of mwan3_rules and avoids writing pointless ct marks.

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting ip6 daddr { fe80::/10, ff01::/16, ff02::/16 } accept"

	# Restore mark from conntrack — non-destructive in unmasked bits.
	# A direct compound "meta mark set (meta mark & ~MMX) | (ct mark & MMX)"
	# is rejected by the kernel (a set-statement expression tree may reference
	# at most one runtime source register). We synthesise the same effect via
	# vmap dispatch on (ct mark & MMX): each branch jumps to a tiny chain that
	# does "meta mark set meta mark | <imm>". Lookup miss (ct mark MMX bits = 0)
	# falls through cleanly. Pbr's bits in meta mark are preserved across the
	# restore, which is what removes mwan3's prior priority dependency on pbr.

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK == 0 ct mark & $MMX_MASK vmap { $restore_vmap }"

	# Jump to interface classification

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_ifaces_in"

	# Skip mwan3 processing for traffic destined for the router on non-WAN interfaces
	# (LAN, loopback, etc.). Traffic arriving on a mwan3 WAN interface is already
	# marked by the iface_in catchall above, so meta mark != 0 and this rule is a
	# no-op for that traffic. The guard ensures DNAT connections are not affected:
	# the original packet gets its ct mark set by the iface_in catchall, so the
	# DNAT reply can restore it correctly.

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK == 0 fib daddr type local return"

	# Check custom/connected/dynamic destinations

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_custom"
	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_connected"
	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_dynamic"

	# User rules

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK == 0 jump mwan3_rules"

	# Save mark to conntrack — non-destructive in unmasked bits of ct mark.
	# Vmap-dispatch on (meta mark & MMX) into per-mark setter chains that
	# atomically clear+set the MMX bits in a single nft expression, so ct
	# mark is never visible with zeroed MMX bits to concurrent packets.
	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK vmap { $save_vmap }"

	# Post-rules: check custom/connected/dynamic for non-default marks

	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_custom"
	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_connected"
	mwan3_nft_push "add rule inet mwan3 mwan3_prerouting meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_dynamic"

	# Populate mwan3_output hook chain

	mwan3_nft_push "flush chain inet mwan3 mwan3_output"

	# Bypass NDP: NS/NA may legitimately target global unicast addresses
	# (NUD probes, NA replies to global-sourced NS), which the link-local
	# daddr bypass below does not cover. Kernel-generated probes (mark=0)
	# must not be classified and re-routed, or NDP state cycles to FAILED.

	mwan3_nft_push "add rule inet mwan3 mwan3_output icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect } accept"

	# Bypass single-link IPv6 destinations: without this, a catch-all
	# 'dest_ip ::/0' user rule marks router-originated link-local traffic
	# (e.g. odhcpd DHCPv6 replies, fe80 -> fe80 UDP 547 -> 546) with a WAN
	# member's fwmark; this type-route hook then re-routes it into the WAN's
	# per-interface table, which (correctly) contains no fe80::/64 route for
	# LAN devices, and the 'fwmark ... unreachable' ip rule at pref
	# unreachable_rule_base + id returns ENETUNREACH to the sender's
	# sendmsg(). Link-local and link-scope multicast destinations must
	# always be routed via the main table.

	mwan3_nft_push "add rule inet mwan3 mwan3_output ip6 daddr { fe80::/10, ff01::/16, ff02::/16 } accept"

	# Restore mark from conntrack (see prerouting comment above)

	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK == 0 ct mark & $MMX_MASK vmap { $restore_vmap }"

	# Jump to interface classification

	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_ifaces_in"

	# Check custom/connected/dynamic destinations

	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_custom"
	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_connected"
	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_dynamic"

	# User rules

	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK == 0 jump mwan3_rules"

	# Save mark to conntrack - atomic clear+set (see prerouting comment)
	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK vmap { $save_vmap }"

	# Post-rules: check custom/connected/dynamic for non-default marks

	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_custom"
	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_connected"
	mwan3_nft_push "add rule inet mwan3 mwan3_output meta mark & $MMX_MASK != $MMX_DEFAULT jump mwan3_dynamic"

	mwan3_nft_batch_commit
}

mwan3_create_iface_nft()
{
	local id family iface_mark device src_ip handle snat6

	iface_mark=""
	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv6" ] && [ $NO_IPV6 -ne 0 ]; then
		return
	fi

	device="$2"
	iface_mark=$(mwan3_id2mask id MMX_MASK)

	# IPv6 opt-in SNAT for router-originated traffic rerouted by mwan3_output.
	# fw4 does not masquerade IPv6 by default, so packets whose saddr was
	# bound to WAN-A's prefix but rerouted onto WAN-B would egress with the
	# wrong source and be dropped upstream by BCP38/uRPF. Enable per-interface
	# via the 'snat6' UCI option (default OFF — RFC 6724 source-address
	# selection and SADR routing can solve the same problem without
	# translation, and NAT66 is harmful in PA/ULA designs).
	# snat6 values:
	#   unset / 0 : no v6 SNAT (default)
	#   1         : SNAT to the interface's primary GUA via mwan3_get_src_ip
	#   <addr>    : SNAT to the literal v6 address (NPTv6-style fixed pin)
	#
	# Stale rules from a prior incarnation of this interface are removed first;
	# comment-tagged for unambiguous identification across reloads.
	# Inside a batch the preamble already flushed mwan3_postrouting entirely.

	if [ "$MWAN3_BATCH_DEPTH" -eq 0 ]; then
		while handle=$($NFT -a list chain inet mwan3 mwan3_postrouting 2>/dev/null | \
				sed -n "s/.*comment \"mwan3_snat_$1\".*# handle \([0-9]*\)/\1/p" | head -n1); \
		      [ -n "$handle" ]; do
			mwan3_nft_exec delete rule inet mwan3 mwan3_postrouting handle "$handle"
		done
	fi

	if [ "$family" = "ipv6" ]; then
		config_get snat6 "$1" snat6 ""
		src_ip=""
		case "$snat6" in
			""|"0")
				: # disabled — no rule
				;;
			"1")
				mwan3_get_src_ip src_ip "$1"
				;;
			*)
				src_ip="$snat6"
				;;
		esac
		if [ -n "$src_ip" ] && [ "$src_ip" != "::" ]; then
			mwan3_nft_exec add rule inet mwan3 mwan3_postrouting \
				oifname "\"$device\"" meta nfproto ipv6 \
				meta mark \& "$MMX_MASK" == "$iface_mark" \
				fib saddr type local ip6 saddr != "$src_ip" \
				snat to "$src_ip" comment "\"mwan3_snat_$1\""
		fi
	fi

	# Add chain (idempotent) then flush. Inside a batch the preamble has already
	# queued a delete for this chain, but add+flush is safe: the kernel sees the
	# delete only when the batch commits, so add chain here recreates it fresh.

	mwan3_nft_exec add chain inet mwan3 "mwan3_iface_in_$1"
	mwan3_nft_exec flush chain inet mwan3 "mwan3_iface_in_$1"

	mwan3_nft_batch_start

	# For packets from connected/custom/dynamic sources, mark as default
	if [ "$family" = "ipv4" ]; then
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv4 ip saddr @mwan3_connected_v4 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv4 ip saddr @mwan3_custom_v4 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv4 ip saddr @mwan3_dynamic_v4 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
	elif [ "$family" = "ipv6" ]; then
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv6 ip6 saddr @mwan3_connected_v6 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv6 ip6 saddr @mwan3_custom_v6 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv6 ip6 saddr @mwan3_dynamic_v6 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
	fi

	# Mark with interface-specific mark — scoped to address family so that an
	# IPv4 chain's catchall cannot misclassify IPv6 packets when two mwan3
	# interfaces (one IPv4, one IPv6) share the same physical device.

	if [ "$family" = "ipv4" ]; then
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv4 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $iface_mark $MMX_MASK)"
	elif [ "$family" = "ipv6" ]; then
		mwan3_nft_push "add rule inet mwan3 mwan3_iface_in_$1 iifname \"$device\" meta nfproto ipv6 meta mark & $MMX_MASK == 0 $(mwan3_nft_mark_expr $iface_mark $MMX_MASK)"
	fi

	mwan3_nft_batch_commit

	# Add jump rule from mwan3_ifaces_in if not already present.
	# Inside a batch the preamble flushed mwan3_ifaces_in but the kernel still
	# shows old rules — skip the grep check and always push the jump.

	if [ "$MWAN3_BATCH_DEPTH" -gt 0 ] || \
	   ! $NFT list chain inet mwan3 mwan3_ifaces_in 2>/dev/null | grep -qw "mwan3_iface_in_$1"; then
		mwan3_nft_exec add rule inet mwan3 mwan3_ifaces_in meta mark \& "$MMX_MASK" == 0 jump "mwan3_iface_in_$1"
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

	[ "$(mwan3_get_iface_hotplug_state "$interface")" = "online" ] || return

	mwan3_create_iface_nft "$interface" "$l3_device"
}

mwan3_rebuild_iface_rules()
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

	mwan3_create_iface_rules "$interface" "$l3_device"
	mwan3_delete_iface_route "$interface"
	mwan3_create_iface_route "$interface"
}

mwan3_delete_iface_nft()
{
	local family handle

	config_get family "$1" family ipv4

	if [ "$family" = "ipv6" ] && [ $NO_IPV6 -ne 0 ]; then
		return
	fi

	# Remove all jump rules for this interface from mwan3_ifaces_in (loop handles
	# the case where duplicate rules accumulated due to repeated fw4 reload cycles)

	while handle=$($NFT -a list chain inet mwan3 mwan3_ifaces_in 2>/dev/null | \
			grep -w "mwan3_iface_in_$1" | sed -n 's/.*# handle \([0-9]*\)/\1/p' | head -n1); \
	      [ -n "$handle" ]; do
		mwan3_nft_exec delete rule inet mwan3 mwan3_ifaces_in handle "$handle"
	done

	# Remove the per-iface postrouting SNAT rule (loop in case both v4/v6
	# rules exist for the same interface name).

	while handle=$($NFT -a list chain inet mwan3 mwan3_postrouting 2>/dev/null | \
			sed -n "s/.*comment \"mwan3_snat_$1\".*# handle \([0-9]*\)/\1/p" | head -n1); \
	      [ -n "$handle" ]; do
		mwan3_nft_exec delete rule inet mwan3 mwan3_postrouting handle "$handle"
	done

	# Delete the interface chain

	$NFT list chain inet mwan3 "mwan3_iface_in_$1" &>/dev/null && {
		mwan3_nft_exec flush chain inet mwan3 "mwan3_iface_in_$1"
		mwan3_nft_exec delete chain inet mwan3 "mwan3_iface_in_$1"
	}
}

mwan3_delete_iface_map_entries()
{
	local id setname

	mwan3_get_iface_id id "$1"
	[ -n "$id" ] || return 0

	# Sticky scheme: one set per (rule, family, iface_id) holding
	# only saddrs (no value side). Removing an interface invalidates every
	# such set whose name ends in "_<id>"; we flush rather than delete since
	# rule chains may still reference the set name.

	for setname in $($NFT list sets inet 2>/dev/null | \
			 awk '$1=="set" && $2 ~ /^mwan3_sticky_v[46]_/ { print $2 }'); do
		case "$setname" in
			*_"$id") $NFT flush set inet mwan3 "$setname" 2>/dev/null ;;
		esac
	done
}

mwan3_create_iface_route()
{
	local family id source_routing _fam_num
	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"
	[ -n "$id" ] || return 0
	config_get_bool source_routing globals source_routing 0
	_fam_num=4
	[ "$family" = "ipv6" ] && _fam_num=6
	${MWAN3_CREATE_IFACE_ROUTE} "$_fam_num" "$id" "$source_routing"
}

mwan3_delete_iface_route()
{
	local id

	mwan3_get_iface_id id "$1"

	if [ -z "$id" ]; then
		LOG warn "delete_iface_route: could not find table id for interface $1"
		return 0
	fi

	# Flush both families so that a family change does not leave stale
	# routes from the old family in the routing table.

	$IP4 route flush table "$id" 2>/dev/null
	[ $NO_IPV6 -eq 0 ] && $IP6 route flush table "$id" 2>/dev/null
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

	$IP rule add pref $((id+MWAN3_IIF_RULE_BASE)) iif "$2" lookup "$id" 2>/dev/null
	$IP rule add pref $((id+MWAN3_FWMARK_RULE_BASE)) fwmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK" lookup "$id" 2>/dev/null
	$IP rule add pref $((id+MWAN3_UNREACHABLE_RULE_BASE)) fwmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK" unreachable 2>/dev/null
}

mwan3_delete_iface_rules()
{
	local id

	mwan3_get_iface_id id "$1"
	[ -n "$id" ] || return 0

	${MWAN3_MANAGE_RULES} delete-iface "$id" \
		"$MWAN3_IIF_RULE_BASE" "$MWAN3_FWMARK_RULE_BASE" \
		"$MWAN3_UNREACHABLE_RULE_BASE" "$MMX_MASK"
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

		# New lowest metric for this family: reset only that family's member list

		if [ "$family" = "ipv4" ]; then
			policy_members_v4=""
		else
			policy_members_v6=""
		fi
	fi

	if [ $is_offline -eq 0 ]; then

		# Accumulate members per family: "iface_name:id:weight" tuples

		if [ "$family" = "ipv4" ]; then
			policy_members_v4="$policy_members_v4 $iface:$id:$weight"
		else
			policy_members_v6="$policy_members_v6 $iface:$id:$weight"
		fi
	elif [ -n "$device" ]; then

		# Offline interface with device: record for fallback out-device rule

		policy_offline_devices="$policy_offline_devices $iface:$device"
	fi
}

mwan3_create_policies_nft()
{
	local last_resort lowest_metric_v4 lowest_metric_v6 total_weight_v4 total_weight_v6
	local policy policy_members_v4 policy_members_v6 policy_offline_devices

	policy="$1"
	policy_members_v4=""
	policy_members_v6=""
	policy_offline_devices=""

	config_get last_resort "$1" last_resort unreachable

	if [ "$1" != "$(echo "$1" | cut -c1-15)" ]; then
		LOG warn "Policy $1 exceeds max of 15 chars. Not setting policy" && return 0
	fi

	# Add chain (idempotent) then flush. Inside a batch the preamble deleted the
	# chain already, so add recreates it; outside a batch add is a no-op if it
	# exists. Either way flush leaves a clean slate for the new policy rules.

	mwan3_nft_exec add chain inet mwan3 "mwan3_policy_$1"
	mwan3_nft_exec flush chain inet mwan3 "mwan3_policy_$1"

	lowest_metric_v4=$DEFAULT_LOWEST_METRIC
	total_weight_v4=0
	lowest_metric_v6=$DEFAULT_LOWEST_METRIC
	total_weight_v6=0

	config_list_foreach "$1" use_member mwan3_set_policy

	# Now build the policy chain rules from accumulated members.
	# For mixed IPv4/IPv6 policies, add per-family nfproto guards so each
	# family's traffic is only directed to members of the matching address family.

	local member iface id weight mark total_weight running map_entries nfproto_guard
	local _fam _members_cur _total_fam _has_v4 _has_v6

	_has_v4=0; [ -n "$(echo "$policy_members_v4" | tr -d ' ')" ] && _has_v4=1
	_has_v6=0; [ -n "$(echo "$policy_members_v6" | tr -d ' ')" ] && _has_v6=1

	total_weight=0
	for member in $policy_members_v4 $policy_members_v6; do
		weight="${member##*:}"
		total_weight=$((total_weight + weight))
	done

	if [ "$total_weight" -gt 0 ]; then
		for _fam in v4 v6; do
			if [ "$_fam" = "v4" ]; then
				[ $_has_v4 -eq 0 ] && continue
				_members_cur="$policy_members_v4"
				[ $_has_v6 -eq 1 ] && nfproto_guard="meta nfproto ipv4" || nfproto_guard=""
			else
				[ $_has_v6 -eq 0 ] && continue
				_members_cur="$policy_members_v6"
				[ $_has_v4 -eq 1 ] && nfproto_guard="meta nfproto ipv6" || nfproto_guard=""
			fi

			_total_fam=0
			for member in $_members_cur; do
				weight="${member##*:}"
				_total_fam=$((_total_fam + weight))
			done

			if [ "$(echo "$_members_cur" | wc -w)" -eq 1 ]; then

				# Single member: direct mark set, no numgen needed

				member=$(echo "$_members_cur" | tr -d ' ')
				id="${member#*:}"
				id="${id%%:*}"
				mark=$(mwan3_id2mask id MMX_MASK)
				mwan3_nft_exec add rule inet mwan3 "mwan3_policy_$policy" \
					$nfproto_guard meta mark \& "$MMX_MASK" == 0 \
					"$(mwan3_nft_mark_expr $mark $MMX_MASK)"
			else
				# Multiple members: use numgen for load balancing.
				# Non-destructive: dispatch via verdict map into per-mark
				# OR-immediate setter chains. The previous form
				#   meta mark set numgen ... map { range : 0xMARK }
				# is single-source but destructive in unmasked bits, so it
				# would clobber pbr's marks if pbr ran first. The vmap form
				# preserves all bits outside MMX.

				running=0
				map_entries=""
				for member in $_members_cur; do
					iface="${member%%:*}"
					id="${member#*:}"
					id="${id%%:*}"
					weight="${member##*:}"
					mark=$(mwan3_id2mask id MMX_MASK)
					local end=$((running + weight - 1))
					if [ -n "$map_entries" ]; then
						map_entries="$map_entries, "
					fi
					map_entries="${map_entries}${running}-${end} : jump mwan3_or_meta_$(mwan3_or_chain_suffix "$mark")"
					running=$((end + 1))
				done
				mwan3_nft_exec add rule inet mwan3 "mwan3_policy_$policy" \
					$nfproto_guard meta mark \& "$MMX_MASK" == 0 \
					"numgen inc mod $_total_fam vmap { $map_entries }"
			fi
		done
	fi

	# Add offline device fallback rules

	local dev_entry offline_iface offline_device

	# Only add if no online members

	if [ "$total_weight" -eq 0 ]; then
		for dev_entry in $policy_offline_devices; do
			offline_iface="${dev_entry%%:*}"
			offline_device="${dev_entry#*:}"
			mwan3_nft_exec add rule inet mwan3 "mwan3_policy_$policy" \
				oifname "$offline_device" meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
		done
	fi

	# Add last resort rule

	case "$last_resort" in
		blackhole)
			mwan3_nft_exec add rule inet mwan3 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_BLACKHOLE $MMX_MASK)"
			;;
		default)
			mwan3_nft_exec add rule inet mwan3 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_DEFAULT $MMX_MASK)"
			;;
		*)
			mwan3_nft_exec add rule inet mwan3 "mwan3_policy_$policy" \
				meta mark \& "$MMX_MASK" == 0 \
				"$(mwan3_nft_mark_expr $MMX_UNREACHABLE $MMX_MASK)"
			;;
	esac
}

mwan3_set_policies_nft()
{
	# Delete orphaned mwan3_policy_* chains - chains that exist in nft but
	# have no corresponding UCI policy config. These accumulate when a policy
	# is removed from config without a service restart.
	# Inside a batch the preamble already deleted all dynamic chains.

	if [ "$MWAN3_BATCH_DEPTH" -eq 0 ]; then
		local valid_policies="" chain

		collect_valid_policy() { valid_policies="$valid_policies ${1} "; }
		config_foreach collect_valid_policy policy

		for chain in $($NFT list chains inet 2>/dev/null \
				| awk '/mwan3_policy_/{gsub(/.*mwan3_policy_/,""); gsub(/ \{.*/,""); print}'); do
			case "$valid_policies" in
				*" ${chain} "*) ;;
				*)
					LOG debug "Deleting orphaned policy chain mwan3_policy_${chain}"
					$NFT delete chain inet mwan3 "mwan3_policy_${chain}" 2>/dev/null
					;;
			esac
		done
	fi

	config_foreach mwan3_create_policies_nft policy
}

# Enumerate the iface members of a policy whose family matches $2 (ipv4|ipv6).
# Sets _policy_member_marks to a space-separated list of "id:mark" tuples.
# Used by the sticky implementation to size the per-member sticky set fan-out.

mwan3_get_policy_members_for_family()
{
	local policy="$1" want_family="$2"
	_policy_member_marks=""

	_mwan3_pmf_accum() {
		local m_iface m_id m_family m_mark
		config_get m_iface "$1" interface
		[ -n "$m_iface" ] || return
		config_get m_family "$m_iface" family ipv4
		[ "$m_family" = "$want_family" ] || return
		mwan3_get_iface_id m_id "$m_iface"
		[ -n "$m_id" ] || return
		m_mark=$(mwan3_id2mask m_id MMX_MASK)
		_policy_member_marks="$_policy_member_marks $m_id:$m_mark"
	}
	config_list_foreach "$policy" use_member _mwan3_pmf_accum
}

# Look up the nft address type of a UCI-managed ipset by set name.
# Usage: _mwan3_uci_ipset_addrtype <set_name> <output_var>
# Sets <output_var> to "ipv4_addr" or "ipv6_addr" if a UCI ipset section with
# option name == <set_name> exists, or to empty string if none matches.

_mwan3_uci_ipset_addrtype() {
	local _mwuia_target="$1" _mwuia_outvar="$2"
	eval "$_mwuia_outvar="

	_mwuia_check_section() {
		local _mwuia_n _mwuia_f _mwuia_t
		config_get _mwuia_n "$1" name
		[ "$_mwuia_n" = "$_mwuia_target" ] || return
		config_get _mwuia_f "$1" family ipv4
		case "$_mwuia_f" in
			ipv4) _mwuia_t="ipv4_addr" ;;
			ipv6) _mwuia_t="ipv6_addr" ;;
			*) return ;;
		esac
		eval "$_mwuia_outvar=$_mwuia_t"
	}
	config_foreach _mwuia_check_section ipset
}

mwan3_set_user_nft_rule()
{
	local ipset_name ipset_src family proto policy src_ip src_port src_iface src_dev
	local sticky dest_ip dest_port use_policy timeout policy
	local global_logging rule_logging loglevel rule_policy rule ipv
	local enabled fwmark fwmask _check_set _set_info

	config_get_bool enabled "$1" enabled 1
	[ "$enabled" -eq 1 ] || return

	rule="$1"
	ipv="$2"
	rule_policy=0
	config_get sticky "$1" sticky 0
	config_get timeout "$1" timeout 600
	config_get ipset_name "$1" ipset
	config_get ipset_src "$1" ipset_src
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
	config_get fwmark "$1" fwmark
	config_get fwmask "$1" fwmask

	# fwmark and fwmask must be specified together. Skip the rule if only one
	# is set. Warn (not error) if the user-supplied mask overlaps mwan3's
	# internal MMX_MASK: the match would then fire on packets already carrying
	# an mwan3 classification mark, which can cause unexpected double-policy
	# assignment. The rule is still installed in that case.

	if [ -n "$fwmark" ] && [ -z "$fwmask" ]; then
		LOG warn "Rule $1: fwmark specified without fwmask; rule skipped"
		return
	fi
	if [ -z "$fwmark" ] && [ -n "$fwmask" ]; then
		LOG warn "Rule $1: fwmask specified without fwmark; rule skipped"
		return
	fi
	if [ -n "$fwmask" ] && [ $(( fwmask & MMX_MASK )) -ne 0 ]; then
		LOG warn "Rule $1: fwmask $fwmask overlaps mwan3 internal mask $MMX_MASK; unexpected behaviour possible"
	fi

	[ "$ipv" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && return
	[ "$family" = "ipv4" ] && [ "$ipv" = "ipv6" ] && return
	[ "$family" = "ipv6" ] && [ "$ipv" = "ipv4" ] && return

	# family=any rules whose nft expression has no IP-version-specific element
	# (no src_ip/dest_ip/ipset/ipset_src) generate identical output on both the
	# ipv4 and ipv6 passes. Skip the ipv6 pass to avoid pushing a duplicate
	# rule. The ipv4 pass output already matches IPv6 traffic at runtime
	# because the match operates on family-agnostic fields (meta mark, l4proto,
	# port, iifname). Exception: proto=icmp requires both passes because ICMP
	# (protocol 1) and ICMPv6 (protocol 58) are distinct L4 protocols.

	if [ "$family" = "any" ] && [ "$ipv" = "ipv6" ] && \
	   [ -z "$src_ip" ] && [ -z "$dest_ip" ] && \
	   [ -z "$ipset_name" ] && [ -z "$ipset_src" ] && \
	   [ "$proto" != "icmp" ]; then
		return
	fi

	for ipaddr in "$src_ip" "$dest_ip"; do
		[ -z "$ipaddr" ] && continue
		local _addr_family
		_addr_family=$($MWAN3IPCHECK "$ipaddr")
		if [ "$_addr_family" = "invalid" ] || [ "$_addr_family" = "mixed" ]; then
			LOG warn "invalid address $ipaddr specified for rule $rule"
			return
		fi
		if { [ "$ipv" = "ipv4" ] && [ "$_addr_family" = "ipv6" ]; } ||
		   { [ "$ipv" = "ipv6" ] && [ "$_addr_family" = "ipv4" ]; }; then
			if [ "$family" = "any" ]; then
				return
			fi
			LOG warn "invalid $ipv address $ipaddr specified for rule $rule"
			return
		fi
	done

	# For family=any rules with nft set references, skip the pass whose
	# address family does not match the set's element type. Analogous to
	# the src_ip/dest_ip address validation above: a set of type ipv4_addr
	# cannot appear in an "ip6 daddr @set" expression, and vice versa.

	local _ipset_name_uci_type="" _ipset_src_uci_type=""
	for _check_set in "$ipset_name" "$ipset_src"; do
		[ -z "$_check_set" ] && continue
		local _set_info
		_set_info=$($NFT list set inet mwan3 "$_check_set" 2>/dev/null)
		if [ -n "$_set_info" ]; then
			if [ "$ipv" = "ipv4" ] && ! echo "$_set_info" | grep -q "type ipv4_addr"; then
				[ "$family" = "any" ] && return
				LOG warn "Rule $rule: set '$_check_set' is not type ipv4_addr, incompatible with family $family"
				return
			fi
			if [ "$ipv" = "ipv6" ] && ! echo "$_set_info" | grep -q "type ipv6_addr"; then
				[ "$family" = "any" ] && return
				LOG warn "Rule $rule: set '$_check_set' is not type ipv6_addr, incompatible with family $family"
				return
			fi
		else
			# Set absent from kernel. Check UCI to determine pass compatibility
			# before falling back to the external-set guard.

			local _uci_addrtype
			if [ "$_check_set" = "$ipset_name" ]; then
				[ -z "$_ipset_name_uci_type" ] && \
					_mwan3_uci_ipset_addrtype "$_check_set" _ipset_name_uci_type
				_uci_addrtype="$_ipset_name_uci_type"
			else
				[ -z "$_ipset_src_uci_type" ] && \
					_mwan3_uci_ipset_addrtype "$_check_set" _ipset_src_uci_type
				_uci_addrtype="$_ipset_src_uci_type"
			fi
			if [ -n "$_uci_addrtype" ]; then

				# UCI-managed set: skip the incompatible pass, continue for the
				# compatible one (bypasses the external-set guard below).

				[ "$ipv" = "ipv4" ] && [ "$_uci_addrtype" = "ipv6_addr" ] && return
				[ "$ipv" = "ipv6" ] && [ "$_uci_addrtype" = "ipv4_addr" ] && return
				continue
			fi
			# Not UCI-managed: apply existing guard for external sets.
			# For family=any, skip the ipv6 pass; the ipv4 pass will pre-create
			# the set as ipv4_addr until an external creator establishes its type.

			if [ "$family" = "any" ] && [ "$ipv" = "ipv6" ]; then
				return
			fi
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
	[ -z "$ipset_src" ] && unset ipset_src
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
	# 'icmp' in UCI means ICMPv4 (proto 1). For IPv6 rules, translate to
	# 'ipv6-icmp' (proto 58) so the generated nftables match is not inert.

	if [ "$proto" != "all" ]; then
		[ "$proto" = "icmp" ] && [ "$ipv" = "ipv6" ] && proto="ipv6-icmp"
		nft_match="$nft_match meta l4proto $proto"
	fi

	# Source IP

	if [ -n "$src_ip" ]; then
		local nft_src_ip="$src_ip"
		if echo "$src_ip" | grep -q ','; then
			nft_src_ip="{ $(echo "$src_ip" | sed 's/,/, /g') }"
		fi
		if [ "$ipv" = "ipv4" ]; then
			nft_match="$nft_match ip saddr $nft_src_ip"
		else
			nft_match="$nft_match ip6 saddr $nft_src_ip"
		fi
	fi

	# Source interface

	if [ -n "$src_dev" ]; then
		nft_match="$nft_match iifname \"$src_dev\""
	fi

	# Destination IP

	if [ -n "$dest_ip" ]; then
		local nft_dest_ip="$dest_ip"
		if echo "$dest_ip" | grep -q ','; then
			nft_dest_ip="{ $(echo "$dest_ip" | sed 's/,/, /g') }"
		fi
		if [ "$ipv" = "ipv4" ]; then
			nft_match="$nft_match ip daddr $nft_dest_ip"
		else
			nft_match="$nft_match ip6 daddr $nft_dest_ip"
		fi
	fi

	# ipset/nft set destination match

	if [ -n "$ipset_name" ]; then

		# Pre-create the set if it doesn't exist yet (e.g. dnsmasq nftset
		# hasn't started). nft -f batch fails atomically if any referenced
		# set is missing, which would kill ALL user rules.
		# UCI-managed sets are already added to the batch by mwan3_render_config_ipsets;
		# skip the kernel check and pre-creation for those.

		if [ -z "$_ipset_name_uci_type" ] && \
		   ! $NFT list set inet mwan3 "$ipset_name" &>/dev/null; then
			LOG notice "Creating missing nft set '$ipset_name' for rule $rule"
			if [ "$ipv" = "ipv4" ]; then
				mwan3_nft_push "add set inet mwan3 $ipset_name { type ipv4_addr; flags interval; auto-merge; }"
			else
				mwan3_nft_push "add set inet mwan3 $ipset_name { type ipv6_addr; flags interval; auto-merge; }"
			fi
		fi
		if [ "$ipv" = "ipv4" ]; then
			nft_match="$nft_match ip daddr @$ipset_name"
		else
			nft_match="$nft_match ip6 daddr @$ipset_name"
		fi
	fi

	# nft set source match

	if [ -n "$ipset_src" ]; then
		if [ -z "$_ipset_src_uci_type" ] && \
		   ! $NFT list set inet mwan3 "$ipset_src" &>/dev/null; then
			LOG notice "Creating missing nft set '$ipset_src' for rule $rule"
			if [ "$ipv" = "ipv4" ]; then
				mwan3_nft_push "add set inet mwan3 $ipset_src { type ipv4_addr; flags interval; auto-merge; }"
			else
				mwan3_nft_push "add set inet mwan3 $ipset_src { type ipv6_addr; flags interval; auto-merge; }"
			fi
		fi
		if [ "$ipv" = "ipv4" ]; then
			nft_match="$nft_match ip saddr @$ipset_src"
		else
			nft_match="$nft_match ip6 saddr @$ipset_src"
		fi
	fi

	# Source port

	if [ -n "$src_port" ]; then

		# UCI stores port ranges as x:y; nft requires x-y. Also expand comma list.

		local nft_src_port
		nft_src_port=$(echo "$src_port" | sed 's/:/-/g; s/,/, /g')
		nft_match="$nft_match th sport { $nft_src_port }"
	fi

	# Destination port

	if [ -n "$dest_port" ]; then
		local nft_dest_port
		nft_dest_port=$(echo "$dest_port" | sed 's/:/-/g; s/,/, /g')
		nft_match="$nft_match th dport { $nft_dest_port }"
	fi

	# fwmark/fwmask: classify traffic by an externally-applied socket/packet
	# mark (e.g. SO_MARK from a userspace daemon). Operates on meta mark, so
	# it is address-family agnostic: a rule with only fwmark/fwmask set and
	# family=any applies to both IPv4 and IPv6.

	if [ -n "$fwmark" ]; then
		nft_match="$nft_match meta mark & $fwmask == $fwmark"
	fi

	# If family is explicitly ipv4 or ipv6 but nft_match has no implicit family
	# qualifier (i.e. no src_ip/dest_ip/ipset match to anchor it to a specific
	# protocol version), add an explicit meta nfproto guard. Without this, a rule
	# like default_rule (family ipv4, no saddr/daddr) generates a bare
	# "meta mark ... jump policy" that matches IPv6 traffic too.

	if [ -z "$src_ip" ] && [ -z "$dest_ip" ] && [ -z "$ipset_name" ] && [ -z "$ipset_src" ]; then
		if [ "$family" = "ipv4" ]; then
			nft_match="${nft_match:+$nft_match }meta nfproto ipv4"
		elif [ "$family" = "ipv6" ]; then
			nft_match="${nft_match:+$nft_match }meta nfproto ipv6"
		fi
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

	fi

	# Create policy chain if it doesn't exist

	if [ $rule_policy -eq 1 ]; then
		$NFT list chain inet mwan3 "mwan3_policy_$use_policy" &>/dev/null || \
			mwan3_nft_push "add chain inet mwan3 mwan3_policy_$use_policy"
	fi

	if [ $rule_policy -eq 1 ] && [ "$sticky" -eq 1 ]; then

		# Non-destructive sticky implementation:
		#   The legacy form  meta mark set ip saddr map @stickymap
		# is single-source destructive — it overwrites meta mark with the
		# looked-up mark, wiping any pbr bits that may already be present.
		# We replace the single ip->mark map with one ip-only set per policy
		# member, plus per-member lookup rules that "jump mwan3_or_meta_<mark>"
		# to OR the member's mark into meta mark while preserving every other
		# bit. The save side mirrors this with per-member "update @set" rules
		# guarded on (meta mark & MMX) == <member_mark>.

		local _policy_member_marks _entry _m_id _m_mark _setname
		local _fam_short _saddr_kw _addr_type
		if [ "$ipv" = "ipv4" ]; then
			_fam_short="v4"; _saddr_kw="ip saddr"; _addr_type="ipv4_addr"
		else
			_fam_short="v6"; _saddr_kw="ip6 saddr"; _addr_type="ipv6_addr"
		fi

		mwan3_get_policy_members_for_family "$use_policy" "$ipv"

		# Create sticky rule chain if it doesn't exist yet. The chain was
		# already flushed in the preamble of mwan3_set_user_rules, so both
		# ipv4 and ipv6 passes can add their rules without interference.

		mwan3_nft_push "add chain inet mwan3 mwan3_rule_$1"

		# Per-member sticky sets and lookup rules.

		for _entry in $_policy_member_marks; do
			_m_id="${_entry%%:*}"
			_m_mark="${_entry##*:}"
			_setname="mwan3_sticky_${_fam_short}_${rule}_${_m_id}"

			$NFT list set inet mwan3 "$_setname" &>/dev/null || \
				mwan3_nft_push "add set inet mwan3 $_setname { type ${_addr_type}; flags timeout; timeout ${timeout}s; }"

			mwan3_nft_push "add rule inet mwan3 mwan3_rule_$1 ${_saddr_kw} @${_setname} jump mwan3_or_meta_$(mwan3_or_chain_suffix "$_m_mark")"
		done

		# Fall through to policy for new flows (no sticky entry hit -> mark still 0).

		mwan3_nft_push "add rule inet mwan3 mwan3_rule_$1 meta mark & $MMX_MASK == 0 jump mwan3_policy_$use_policy"

		# After the policy assigns a mark, populate the matching per-member
		# sticky set so subsequent packets from this saddr stay on the same WAN.

		for _entry in $_policy_member_marks; do
			_m_id="${_entry%%:*}"
			_m_mark="${_entry##*:}"
			_setname="mwan3_sticky_${_fam_short}_${rule}_${_m_id}"

			mwan3_nft_push "add rule inet mwan3 mwan3_rule_$1 meta mark & $MMX_MASK == $_m_mark update @${_setname} { ${_saddr_kw} timeout ${timeout}s }"
		done

		policy_action="jump mwan3_rule_$1"
	fi

	# Add logging rule if enabled

	if [ "$global_logging" = "1" ] && [ "$rule_logging" = "1" ]; then
		mwan3_nft_push "add rule inet mwan3 mwan3_rules $nft_match meta mark & $MMX_MASK == 0 log prefix \"MWAN3($1)\" level $loglevel"
	fi

	# Add the actual rule

	mwan3_nft_push "add rule inet mwan3 mwan3_rules $nft_match meta mark & $MMX_MASK == 0 $policy_action"
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

	$NFT list chain inet mwan3 mwan3_rules 2>/dev/null | grep -q "iifname \"$device\"" && return

	is_src_iface=0

	iface_rule()
	{
		local src_iface enabled
		config_get_bool enabled "$1" enabled 1
		[ "$enabled" -eq 1 ] || return
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

	mwan3_nft_push "flush chain inet mwan3 mwan3_rules"

	# Pre-create and flush per-rule chains for all enabled UCI rules, before
	# the per-family loop. Sourcing names from UCI (not the kernel) prevents
	# chains for deleted rules from being recreated after reload. "add chain"
	# is idempotent: it recreates a chain deleted by mwan3_nft_reload_start or
	# is a no-op if the chain already exists (hotplug path).

	_init_rule_chain() {
		local _irc_enabled
		config_get_bool _irc_enabled "$1" enabled 1
		[ "$_irc_enabled" -eq 0 ] && return
		mwan3_nft_push "add chain inet mwan3 mwan3_rule_$1"
		mwan3_nft_push "flush chain inet mwan3 mwan3_rule_$1"
	}
	config_foreach _init_rule_chain rule

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

mwan3_update_peer_track_ip() {
	local interface="$1"
	local track_gateway peer family

	config_get_bool track_gateway "$interface" track_gateway 0
	[ "$track_gateway" -eq 1 ] || return 0

	config_get family "$interface" family ipv4

	# Get ptpaddress from ifstatus JSON (no-op if not p2p)

	peer=$(ifstatus "$interface" 2>/dev/null | \
		jsonfilter -qe "@[\"${family}-address\"][0].ptpaddress")

	if [ -n "$peer" ]; then
		mkdir -p "$MWAN3TRACK_STATUS_DIR/$interface"
		echo "$peer" > "$MWAN3TRACK_STATUS_DIR/${interface}/GATEWAY"
		LOG notice "track_gateway: $interface peer IP is $peer"
	else
		rm -f "$MWAN3TRACK_STATUS_DIR/${interface}/GATEWAY"
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
	local device result tracking
	local status online uptime result

	mwan3_get_iface_id id "$1"
	network_get_device device "$1"
	config_get_bool enabled "$1" enabled 0
	config_get family "$1" family ipv4

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
		local _fam_num=4
		[ "$family" = "ipv6" ] && _fam_num=6
		local _check
		_check=$(${MWAN3_MANAGE_RULES} check "$_fam_num" \
			"$((id+MWAN3_IIF_RULE_BASE))" \
			"$((id+MWAN3_FWMARK_RULE_BASE))" \
			"$((id+MWAN3_UNREACHABLE_RULE_BASE))")
		[ $((_check & 1)) -eq 0 ] || result=$((result+1))
		[ $((_check & 2)) -eq 0 ] || result=$((result+2))
		[ $((_check & 4)) -eq 0 ] || result=$((result+4))
		[ -n "$($NFT list chain inet mwan3 mwan3_iface_in_$1 2>/dev/null)" ] ||
			result=$((result+8))
		${MWAN3_MANAGE_RULES} check-route "$_fam_num" "$id" "$device" ||
			result=$((result+16))
		[ "$result" = "0" ] && result=""
	fi

	mwan3_get_mwan3track_status tracking $1
	if [ -n "$result" ]; then
		echo " interface $1 is $status and tracking is $tracking ($result)"
	else
		echo " interface $1 is $status and tracking is $tracking"
	fi

	local tip_f tip_ip tip_status tip_lat tip_loss tip_detail check_quality
	check_quality=0
	for tip_f in "$MWAN3TRACK_STATUS_DIR/${1}/LATENCY_"*; do
		[ -f "$tip_f" ] || break
		readfile tip_lat "$tip_f"
		[ -n "$tip_lat" ] && { check_quality=1; break; }
	done
	for tip_f in "$MWAN3TRACK_STATUS_DIR/${1}/TRACK_"*; do
		[ -f "$tip_f" ] || continue
		tip_ip="${tip_f##*TRACK_}"
		[ "$tip_ip" = "OUTPUT" ] && continue
		readfile tip_status "$tip_f"
		tip_status="${tip_status:-unknown}"
		if [ "$check_quality" = "1" ]; then
			case "$tip_status" in
				up)
					readfile tip_lat "$MWAN3TRACK_STATUS_DIR/${1}/LATENCY_${tip_ip}"
					readfile tip_loss "$MWAN3TRACK_STATUS_DIR/${1}/LOSS_${tip_ip}"
					tip_detail="${tip_lat}ms, ${tip_loss}% loss"
					;;
				down)
					readfile tip_loss "$MWAN3TRACK_STATUS_DIR/${1}/LOSS_${tip_ip}"
					tip_detail="-, ${tip_loss}% loss"
					;;
				*)
					tip_detail=""
					;;
			esac
			if [ -n "$tip_detail" ]; then
				echo "   track $tip_ip: $tip_status ($tip_detail)"
			else
				[ "$tip_status" = "skipped" ] && tip_status="ignored"
				echo "   track $tip_ip: $tip_status"
			fi
		else
			[ "$tip_status" = "skipped" ] && tip_status="ignored"
			echo "   track $tip_ip: $tip_status"
		fi
	done
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

_mwan3_report_policies_for_family()
{
	local family="$1"
	local json pkeys pname mkeys midx iface percent status

	json=$(ubus call mwan3 status '{"section":"policies"}' 2>/dev/null)
	if [ -z "$json" ]; then
		echo " (ubus unavailable)"
		return
	fi

	json_load "$json"
	json_select "policies" || return
	json_select "$family" || return
	json_get_keys pkeys
	for pname in $pkeys; do
		echo "$pname:"
		json_select "$pname"
		json_get_keys mkeys
		for midx in $mkeys; do
			json_select "$midx"
			json_get_var iface interface
			json_get_var percent percent
			echo " $iface (${percent:-0}%)"
			json_select ".."
		done
		json_select ".."
	done
}

mwan3_report_policies_v4()
{
	_mwan3_report_policies_for_family "ipv4"
}

mwan3_report_policies_v6()
{
	_mwan3_report_policies_for_family "ipv6"
}

_mwan3_report_connected_set()
{
	local json nft_keys idx type elem_keys eidx etype addr len rstart rend

	json=$($NFT -j list set inet mwan3 "$1" 2>/dev/null) || return
	json_load "$json"
	json_select "nftables" || return

	json_get_keys nft_keys
	for idx in $nft_keys; do
		json_select "$idx"
		json_get_type type "set"
		if [ "$type" = "object" ]; then
			json_select "set"
			json_select "elem" || { json_select ".."; json_select ".."; continue; }
			json_get_keys elem_keys
			for eidx in $elem_keys; do
				json_select "$eidx"
				json_get_type etype "prefix"
				if [ "$etype" = "object" ]; then
					json_select "prefix"
					json_get_var addr addr
					json_get_var len len
					echo "$addr/$len"
					json_select ".."
				else
					json_get_type etype "range"
					if [ "$etype" = "array" ]; then
						json_select "range"
						json_get_var rstart 1
						json_get_var rend 2
						echo "$rstart-$rend"
						json_select ".."
					fi
				fi
				json_select ".."
			done
			json_select ".."
			json_select ".."
		fi
		json_select ".."
	done
}

mwan3_report_connected_v4()
{
	_mwan3_report_connected_set mwan3_connected_v4
}

mwan3_report_connected_v6()
{
	[ $NO_IPV6 -ne 0 ] && return
	_mwan3_report_connected_set mwan3_connected_v6
}

mwan3_report_rules_v4()
{
	$NFT list chain inet mwan3 mwan3_rules 2>/dev/null | \
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

	# On ifdown, selectively flush conntrack entries for this interface's mark.
	# This forces flows that were using the failed WAN to immediately re-establish
	# via the new policy rather than waiting for a TCP retransmit timeout.
	# More targeted than the UCI flush_conntrack mechanism which flushes everything.

	if [ "$action" = "ifdown" ] && [ -e "$CONNTRACK_FILE" ]; then
		local iface_id iface_mark
		mwan3_get_iface_id iface_id "$interface"
		if [ -n "$iface_id" ]; then
			iface_mark=$(mwan3_id2mask "$iface_id" "$MMX_MASK")
			mwan3ct flush --mark "${iface_mark}/${MMX_MASK}" 2>/dev/null
			LOG info "Selectively flushed conntrack entries for interface '$interface' (mark ${iface_mark}/${MMX_MASK})"
		fi
	fi
}

mwan3_track_clean()
{
	# Per-interface state lives in two places: the tracker's runtime
	# directory under $MWAN3TRACK_STATUS_DIR/<iface>, and the hotplug
	# state file at $MWAN3_STATUS_DIR/iface_state/<iface>. Only called
	# from stop_service, so we're tearing down per-iface state, not
	# session-wide state (mmx_mask and the iif_rule_base/fwmark_rule_base/
	# unreachable_rule_base records under $MWAN3_STATUS_DIR are pinned
	# across stop/start and must survive).
	#
	# Race note: at stop_service time the tracker process is still
	# alive (procd_kill runs after stop_service returns). If the
	# tracker is mid-iteration its next mkdir -p / echo > can recreate
	# a few files in the directory we just removed; mwan3track is
	# almost always sleeping so this is rare and bounded to one cycle.

	rm -rf "${MWAN3TRACK_STATUS_DIR:?}/${1}" 2>/dev/null
	rm -f "${MWAN3_STATUS_DIR:?}/iface_state/${1}" 2>/dev/null
	rmdir --ignore-fail-on-non-empty "$MWAN3TRACK_STATUS_DIR" 2>/dev/null
}
