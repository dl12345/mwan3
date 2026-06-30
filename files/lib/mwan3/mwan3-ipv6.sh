#!/bin/sh

# mwan3-ipv6.sh: the IPv6 multi-WAN subsystem. Holds source-derived routing, the
# 1:1 prefix-translation install path with its prefix and segment caches and
# survivor selection, and the prefix-deprecation failover actuator. Sourced by
# mwan3.sh after common.sh; every function resolves its common.sh primitives and
# mwan3.sh helpers at call time, so this file defines functions only and runs no
# top-level code. It is reached only when mwan3.sh, or the hotplug and reload
# paths that source it, invoke one of these functions.

# IPv6 translate failover, prefix cache. At failover the orphaned WAN's prefix
# must be re-marked and translated, but a long outage can age it out of ubus
# (the delegation lease expires while the interface stays up), so each IPv6 WAN's
# last-known prefix is cached while it is online and read back at failover. The
# refresh is a no-op on empty input so a transient empty discovery never clobbers
# a good entry.

mwan3_prefix_cache_refresh()
{
	[ -n "$2" ] || return 0
	mkdir -p "$MWAN3_PREFIX_CACHE_DIR"
	printf '%s\n' "$2" > "$MWAN3_PREFIX_CACHE_DIR/$1"
}

mwan3_prefix_cache_read()
{
	cat "$MWAN3_PREFIX_CACHE_DIR/$1" 2>/dev/null
}

# IPv6 translate per-segment cache, parallel to the parent-prefix cache above. The
# carve needs each WAN's active LAN segments, not just its parent delegation, and a
# segment can age out of ubus during a long outage, so each online WAN's segments are
# cached here and read back at failover. Refresh is a no-op on empty input so a
# transient empty discovery never clobbers a good entry.

mwan3_segment_cache_refresh()
{
	[ -n "$2" ] || return 0
	mkdir -p "$MWAN3_SEGMENT_CACHE_DIR"
	printf '%s\n' "$2" > "$MWAN3_SEGMENT_CACHE_DIR/$1"
}

mwan3_segment_cache_read()
{
	cat "$MWAN3_SEGMENT_CACHE_DIR/$1" 2>/dev/null
}

# Find the surviving IPv6 WAN for a failed one: an enabled, online IPv6 mwan3
# interface other than the failed interface. Sets the variable named by $1;
# returns 1 if there is none.

mwan3_get_ipv6_survivor()
{
	local _failed="$2" _surv=""

	_mwan3_pick_survivor()
	{
		local cand="$1" en fam
		[ -z "$_surv" ] || return
		[ "$cand" != "$_failed" ] || return
		config_get_bool en "$cand" enabled 0
		[ "$en" -eq 1 ] || return
		config_get fam "$cand" family ipv4
		[ "$fam" = "ipv6" ] || return
		[ "$(mwan3_get_iface_hotplug_state "$cand")" = "online" ] || return
		_surv="$cand"
	}

	config_foreach _mwan3_pick_survivor interface
	[ -n "$_surv" ] || return 1
	export "$1=$_surv"
}

# Populate the IPv6 source-derived routing chain and the foreign-source translation
# chains (the SNAT chain holding the snat prefix-map and the masquerade floor, and the
# DNAT chain holding the inverse prefix-map). When globals ipv6_routing is 'on',
# forwarded IPv6 that no user rule has marked is stamped by its source prefix so each
# delegated prefix egresses its own WAN's table with no NAT, and each WAN gets an
# always-on translation that makes a foreign source valid on it (the substrate failover
# and per-rule steering both reuse), scoped so native traffic stays transparent. The
# three IPv6 chains are flushed and rebuilt on every event that rebuilds policies, plus
# the ifupdate (prefix refresh) hotplug event. When ipv6_routing is not 'on' they are
# left empty, so their jumps and hooks are no-ops.

mwan3_set_src_routing_nft()
{
	local ipv6_routing _v6_mark_records="" _len _prefix _mark

	[ $NO_IPV6 -eq 0 ] || return
	config_get ipv6_routing globals ipv6_routing off

	mwan3_nft_batch_start
	mwan3_nft_push "flush chain inet mwan3 mwan3_src_routing_v6"
	mwan3_nft_push "flush chain inet mwan3 mwan3_snat_v6"
	mwan3_nft_push "flush chain inet mwan3 mwan3_dnat_v6"
	[ "$ipv6_routing" = "on" ] && config_foreach mwan3_add_src_routing_iface interface

	# The source-prefix marking rules are non-terminal mark sets where the last match wins,
	# so a packet inside two nested delegations takes the mark of whichever rule comes last.
	# mwan3_add_src_routing_iface accumulates "<length> <prefix> <mark>" records rather than
	# pushing rules directly; emit them here sorted by ascending prefix length so the most
	# specific delegation is emitted last and wins regardless of configuration order. The
	# emission runs in a pipeline subshell, which is fine because mwan3_nft_push appends to
	# the batch file, not to shell state.

	printf '%s' "$_v6_mark_records" | sort -n | while read -r _len _prefix _mark; do
		[ -n "$_prefix" ] || continue
		mwan3_nft_push "add rule inet mwan3 mwan3_src_routing_v6 ip6 saddr $_prefix $(mwan3_nft_mark_expr $_mark $MMX_MASK)"
	done

	mwan3_nft_batch_commit
}

# Warn on each ipv6_translate_prefix_<X> override list on WAN $1 whose suffix X cannot be
# a carried IPv6 WAN: X names no mwan3 interface, names this WAN itself, or names an
# IPv4-only interface. Such an override can never apply and is almost certainly a typo or
# stale config, so reporting it is honest flagging of an unreachable option, not a guess.
# Enumeration is from the config library's own CONFIG_LIST_STATE (every loaded
# "<section>_<option>" list), so no option name is guessed and no extra fork is added; it
# matches exactly the list form config_list_foreach reads the override from.
#
# $2 is the WAN's resolved carve pool; two further checks cover the ULA carve list:
# ipv6_translate_ula set with no pool (a carve unit cannot map without one, so every
# entry would use the stateful floor and the list is ignored), and an explicit entry
# outside fc00::/7 (ignored at intake, keeping the option's name honest).

mwan3_translate_lint()
{
	local _self="$1" _pool="$2" entry suffix sectype fam

	for entry in $CONFIG_LIST_STATE; do
		case "$entry" in
		"${_self}_ipv6_translate_prefix_"?*)
			suffix="${entry#${_self}_ipv6_translate_prefix_}"
			if [ "$suffix" = "$_self" ]; then
				LOG warn "ipv6 translate ($_self): override ipv6_translate_prefix_$suffix names this WAN itself and is ignored"
				continue
			fi
			config_get sectype "$suffix" TYPE ""
			if [ "$sectype" != "interface" ]; then
				LOG warn "ipv6 translate ($_self): override ipv6_translate_prefix_$suffix names no mwan3 interface and is ignored"
				continue
			fi
			config_get fam "$suffix" family ipv4
			[ "$fam" = "ipv6" ] || \
				LOG warn "ipv6 translate ($_self): override ipv6_translate_prefix_$suffix names IPv4-only interface $suffix and is ignored"
			;;
		esac
	done

	if [ -z "$_pool" ]; then
		for entry in $CONFIG_LIST_STATE; do
			case "$entry" in
			"${_self}_ipv6_translate_ula")
				LOG warn "ipv6 translate ($_self): ipv6_translate_ula is set but there is no carve pool, the list is ignored and the stateful floor carries its traffic"
				;;
			esac
		done
	fi

	_mwan3_translate_lint_ula()
	{
		local _entry="$1" _canon
		[ "$_entry" != "auto" ] || return
		_canon=$(${MWAN3_TRANSLATE_ALLOCATOR} canon "$_entry")
		case "$_canon" in
		"masked "*) _canon="${_canon#masked }" ;;
		"ok "*)     _canon="${_canon#ok }" ;;
		*)          return ;;
		esac
		case "$_canon" in
		f[cd][0-9a-f][0-9a-f]:*) ;;
		*) LOG warn "ipv6 translate ($_self): ipv6_translate_ula entry $_entry is outside fc00::/7 and is ignored" ;;
		esac
	}
	config_list_foreach "$_self" ipv6_translate_ula _mwan3_translate_lint_ula
}

# True (0) when WAN $1 carries any ipv6_translate_prefix_<X> override list, scanning the
# same CONFIG_LIST_STATE the lint does. Used to decide whether the per-WAN unit resolution
# must run for a WAN with no carve pool, since an override needs no pool; a floor-only WAN
# (no pool, no override) skips it entirely and emits only its stateful floor.

mwan3_translate_has_override()
{
	local _self="$1" entry
	for entry in $CONFIG_LIST_STATE; do
		case "$entry" in
		"${_self}_ipv6_translate_prefix_"?*) return 0 ;;
		esac
	done
	return 1
}

# True (0) when any interface configures the 1:1 translation: an
# ipv6_translate_prefix_<X> override list on any section (the same
# CONFIG_LIST_STATE scan as above), or a carve pool (option
# ipv6_translate_pool) on any interface. Fork-free. Used by the hotplug
# script to decide whether an event on an interface mwan3 does not manage
# needs a source-routing rebuild: only a configured translator places carve
# targets that a new interface's assignment could land on, so floor-only
# deployments skip the rebuild entirely.

mwan3_translate_configured()
{
	local entry _found=""

	for entry in $CONFIG_LIST_STATE; do
		case "$entry" in
		*_ipv6_translate_prefix_?*) return 0 ;;
		esac
	done

	_mwan3_translate_pool_set()
	{
		local _pool
		[ -z "$_found" ] || return
		config_get _pool "$1" ipv6_translate_pool ""
		[ -n "$_pool" ] && _found=1
	}

	config_foreach _mwan3_translate_pool_set interface
	[ -n "$_found" ]
}

# config_foreach callback for mwan3_install_translate_iface: resolve one candidate IPv6
# WAN into allocator units, appending to the open jshn units array. The translating WAN
# (xlate_self) and its carve pool (xlate_pool) are read from the calling frame, and
# xlate_have_units is set when any unit is produced. A per-WAN override
# (list ipv6_translate_prefix_<cand>) wins: with target length t at most the delegation
# length d it becomes a fixed-target unit mapping the whole delegation onto that target
# (the allocator carves an oversized target down to a delegation-sized sub-block); with
# d below t at most 64 it warns and falls through to the pool carve; over /64 it warns and
# is left to the stateful floor. With no override, or as the undersized fall-through, each
# active LAN segment of the WAN becomes a carve unit when a pool is set. Segments come live
# from discovery when the WAN is online and from the segment cache while it is in soft
# failover, mirroring the marking path.

_mwan3_translate_add_units()
{
	local cand="$1"
	local en fam true_c prefixes_c segs_c overrides ovr del d t seg canon_line ovr_count del_count

	[ "$cand" != "$xlate_self" ] || return
	config_get_bool en "$cand" enabled 0
	[ "$en" -eq 1 ] || return
	config_get fam "$cand" family ipv4
	[ "$fam" = "ipv6" ] || return

	mwan3_get_true_iface true_c "$cand"
	if [ "$(mwan3_get_iface_hotplug_state "$cand")" = "online" ]; then
		prefixes_c=$(${MWAN3_GET_PREFIX} "$true_c" "$cand")
		segs_c=$(${MWAN3_GET_DELEGATED_SEGMENTS} "$true_c" "$cand")
	else
		prefixes_c=$(mwan3_prefix_cache_read "$cand")
		segs_c=$(mwan3_segment_cache_read "$cand")
	fi

	overrides=""
	_mwan3_translate_collect_override() { overrides="${overrides:+$overrides }$1"; }
	config_list_foreach "$xlate_self" "ipv6_translate_prefix_${cand}" _mwan3_translate_collect_override

	if [ -n "$overrides" ]; then

		# The override list pairs positionally with the delegations; a count mismatch is
		# almost certainly a config error, so flag it.

		set -- $prefixes_c; del_count=$#
		set -- $overrides;  ovr_count=$#
		[ "$ovr_count" = "$del_count" ] || \
			LOG warn "ipv6 translate ($xlate_self): $ovr_count override target(s) for $cand but $del_count delegated prefix(es); the list pairs positionally"

		# Pair each delegation prefix positionally with an override target (the common case
		# is one of each), canonicalize the target to its length (masking host bits with a
		# warning, dropping an unparseable value), length-check, and emit a fixed-target unit
		# per valid pair. A delegation with no usable override is simply not emitted here; its
		# segments are carried by the pool carve below, which the containment filter keeps
		# disjoint from any override that does cover them.

		for del in $prefixes_c; do
			ovr="$1"
			[ $# -gt 0 ] && shift
			[ -n "$ovr" ] || continue
			canon_line=$(${MWAN3_TRANSLATE_ALLOCATOR} canon "$ovr")
			case "$canon_line" in
			"masked "*)
				LOG warn "ipv6 translate ($xlate_self): override target $ovr for $cand has host bits below its length, using ${canon_line#masked }"
				ovr="${canon_line#masked }"
				;;
			"ok "*)
				ovr="${canon_line#ok }"
				;;
			*)
				LOG warn "ipv6 translate ($xlate_self): override target $ovr for $cand is not a valid prefix, using pool carve for this delegation"
				continue
				;;
			esac
			d="${del##*/}"
			t="${ovr##*/}"
			if [ "$t" -le "$d" ]; then
				json_add_object
				json_add_string src "$del"
				json_add_string target "$ovr"
				json_close_object
				xlate_have_units=1
			elif [ "$t" -le 64 ]; then
				LOG warn "ipv6 translate ($xlate_self): override target $ovr (/$t) too small for the /$d delegation of $cand, using pool carve"
			else
				LOG warn "ipv6 translate ($xlate_self): override target $ovr (/$t) is finer than /64 for $cand, using stateful masquerade"
			fi
		done
	fi

	# Pool carve: emit a carve unit for each active LAN segment whenever a pool is set,
	# regardless of any override. The allocator's containment filter absorbs the segments an
	# override already covers, so an override and the carve never produce overlapping map
	# keys, while the unpaired or undersized-override delegations of a multi-delegation WAN
	# still get carved.

	if [ -n "$xlate_pool" ]; then
		for seg in $segs_c; do
			json_add_object
			json_add_string src "$seg"
			json_close_object
			xlate_have_units=1
		done
	fi
}

# Append the translating WAN's ULA carve units (list ipv6_translate_ula) to the open
# jshn units array, after the carried-WAN units so config-order placement stays stable.
# xlate_self, xlate_pool, xlate_have_units and ula_discovery_failed are read from the
# calling frame by dynamic scope. An entry of 'auto' runs the router-global ULA sweep,
# exactly once no matter how many auto entries appear, and appends every discovered
# segment (already canonical from the helper); a nonzero sweep exit sets
# ula_discovery_failed and returns, since the caller then emits the floor only and
# appending the remaining entries would be dead work. Any other entry is canonicalised
# through the allocator's canon intake (host bits below the length masked with a
# warning, an unparseable value dropped with a warning) and appended when inside
# fc00::/7; a non-ULA entry is skipped silently here because the lint already warned.
# Without a pool a carve unit cannot map, so the whole list is skipped (the lint warns
# there too). An exact duplicate between 'auto' and an explicit entry is left for the
# allocator's containment filter, which absorbs it with a notice log.

_mwan3_translate_add_ula_units()
{
	local entries="" entry segs seg canon_line

	_mwan3_translate_collect_ula() { entries="${entries:+$entries }$1"; }
	config_list_foreach "$xlate_self" ipv6_translate_ula _mwan3_translate_collect_ula

	[ -n "$entries" ] || return 0
	[ -n "$xlate_pool" ] || return 0

	case " $entries " in
	*" auto "*)
		segs=$(${MWAN3_GET_ULA_SEGMENTS})
		if [ $? -ne 0 ]; then
			ula_discovery_failed=1
			return 0
		fi
		for seg in $segs; do
			json_add_object
			json_add_string src "$seg"
			json_close_object
			xlate_have_units=1
		done
		;;
	esac

	for entry in $entries; do
		[ "$entry" != "auto" ] || continue
		canon_line=$(${MWAN3_TRANSLATE_ALLOCATOR} canon "$entry")
		case "$canon_line" in
		"masked "*)
			LOG warn "ipv6 translate ($xlate_self): ULA segment $entry has host bits below its length, using ${canon_line#masked }"
			entry="${canon_line#masked }"
			;;
		"ok "*)
			entry="${canon_line#ok }"
			;;
		*)
			LOG warn "ipv6 translate ($xlate_self): ULA segment $entry is not a valid prefix and is ignored"
			continue
			;;
		esac

		# fc00::/7 membership on the canonical form. All four digits of the first
		# hextet are matched: a bare f[cd]* would falsely accept a canonical first
		# hextet like fc0: (0x0fc0), which is not ULA.

		case "$entry" in
		f[cd][0-9a-f][0-9a-f]:*)
			json_add_object
			json_add_string src "$entry"
			json_close_object
			xlate_have_units=1
			;;
		esac
	done
}

# Install one online IPv6 WAN's always-on, foreign-source egress translation. This is
# the substrate both failover and per-rule steering/balancing reuse: anything that
# marks a flow onto this WAN whose source is not the WAN's own delegated prefix has
# that source made valid on the wire, while native traffic stays transparent.
#
# A WAN with a carve pool (option ipv6_translate_pool 'auto' for its own delegation,
# or an explicit block) is a translating WAN: each active LAN segment of every other
# IPv6 WAN is mapped 1:1 onto a disjoint, equal-length target carved from the pool by
# conntrack NETMAP, host id and ports preserved, so each carried host gets a stable,
# individually reachable external address. Carving a disjoint target per segment is what
# keeps two or more carried segments collision-free, where a single shared target would
# alias them on the return path. A per-WAN override (list ipv6_translate_prefix_<wan>)
# instead names an explicit target for one carried WAN and maps its whole delegation onto
# that target at whole-delegation granularity, preserving its internal subnet structure;
# it is length-checked and takes precedence over the pool carve for that WAN. A
# translating WAN can additionally carry ULA LAN segments (list ipv6_translate_ula):
# 'auto' carries every ULA segment the router-global sweep discovers, an explicit CIDR
# names one directly (a segment discovery cannot see, such as a ULA network behind a
# downstream router), and each becomes a plain carve unit exactly like a carried GUA
# segment. The carve, the disjointness gate and the rule rendering are done by the
# allocator helper, which emits one snat prefix-map rule and one inverse dnat prefix-map
# rule; this function gathers its inputs, pushes those rule lines and warns on a
# shortfall or overlap.
#
# On top of that, and as the only translation for a WAN with no pool, an always-on
# masquerade floor follows the snat map in the same chain and catches any foreign source
# the map does not cover (NAT statements are terminal, so a mapped flow binds first and
# never reaches the floor), excluding the WAN's own delegated prefix(es) so native traffic
# stays transparent. So a covered segment is carried 1:1 and anything else foreign (an
# uncovered segment, an aged-out entry, a capacity overflow) degrades to the masquerade
# floor rather than dropping. Router-originated traffic is excluded by fib saddr type and
# left to the per-interface snat6 option.
#
# $1 iface, $2 its true (ubus) iface, $3 its delegated prefix(es) (may be empty),
# $4 its own active LAN segments (may be empty).

mwan3_install_translate_iface()
{
	local iface="$1" true_iface="$2" prefixes="$3" own_segments="$4"
	local dev pool seg p excl jblob alloc tok rest src reason reserved_prefixes reserved_failed
	local xlate_self xlate_pool xlate_have_units ula_discovery_failed canon_line alloc_rc

	network_get_device dev "$true_iface"

	# Without a resolvable egress device this WAN gets no floor this rebuild; its marking is
	# still in place, so log the gap rather than returning silently.

	if [ -z "$dev" ]; then
		LOG warn "ipv6 translate ($iface): no egress device for $true_iface, leaving it with marking but no floor this rebuild"
		return
	fi

	config_get pool "$iface" ipv6_translate_pool ""

	# Canonicalize an operator-supplied explicit pool to its prefix length: a value with
	# host bits set is masked with a warning, an unparseable value drops to floor-only. The
	# 'auto' keyword resolves below to a netifd-canonical delegation and needs no masking.

	if [ -n "$pool" ] && [ "$pool" != "auto" ]; then
		canon_line=$(${MWAN3_TRANSLATE_ALLOCATOR} canon "$pool")
		case "$canon_line" in
		"masked "*)
			LOG warn "ipv6 translate ($iface): pool $pool has host bits below its length, using ${canon_line#masked }"
			pool="${canon_line#masked }"
			;;
		"ok "*)
			pool="${canon_line#ok }"
			;;
		*)
			LOG warn "ipv6 translate ($iface): pool $pool is not a valid prefix, emitting stateful masquerade floor only this rebuild"
			pool=""
			;;
		esac
	fi

	# 'auto' carves from this WAN's own live delegation (its first delegated prefix);
	# an explicit value carves from that block; absence means no carve unless
	# a per-WAN override is set, just the stateful floor below.

	if [ "$pool" = "auto" ]; then
		pool=""
		for p in $prefixes; do pool="$p"; break; done
	fi

	# Flag override options whose suffix names no usable carried WAN, an ipv6_translate_ula
	# list with no pool to carve from, and any non-ULA entry in that list.

	mwan3_translate_lint "$iface" "$pool"

	# Resolve every other enabled IPv6 WAN into allocator units: a per-WAN override maps
	# that WAN's whole delegation onto an explicit target and wins, otherwise its active
	# LAN segments (live when it is online, cached when it is in soft failover) are carve
	# units for the pool, skipping this WAN's own segments ($own_segments). The allocator
	# carves, gates and renders; act on its typed output: push the snat and dnat prefix-map
	# rules, log each mapped target, and warn when a unit fell to the
	# stateful floor for want of an aligned slot or because of an overlap. An override
	# needs no pool, so the allocator runs whenever a pool is set or any unit was produced.

	xlate_self="$iface"
	xlate_pool="$pool"
	xlate_have_units=0
	ula_discovery_failed=0

	# Add every IPv6 prefix the router holds an address in or has delegated, across all
	# network interfaces, to the carve's skip set. The carve and the gate avoid only the
	# prefixes in this set, so a router-held /64 left out of it can have a target placed on
	# it and the dnat map then hijacks traffic to it: the router's own address, a
	# second WAN addressed from the same provider delegation, or a LAN. A per-interface view
	# is not enough, since one delegation can feed several interfaces (the zero-config 'auto'
	# case especially). The allocator ignores entries outside the pool, so the full set is
	# emitted and filtered there. Gathered only for a translating WAN (one with a pool or an
	# override); a floor-only WAN makes no allocator call and needs none.

	reserved_prefixes=""
	reserved_failed=0
	if [ -n "$pool" ] || mwan3_translate_has_override "$iface"; then

		# Fail closed on a reserved-sweep failure: a nonzero exit (ubus down or a null
		# interface dump) or empty output is anomalous for an online translator, whose own
		# WAN address /64 must appear, so treat either as an unknown skip set and carve
		# nothing this rebuild rather than place a target on a router-held prefix the sweep
		# failed to report.

		reserved_prefixes=$(${MWAN3_GET_RESERVED_PREFIXES})
		[ $? -eq 0 ] && [ -n "$reserved_prefixes" ] || reserved_failed=1
	fi

	json_init
	json_add_string dev "$dev"
	[ -n "$pool" ] && json_add_string pool "$pool"
	json_add_array own
	for seg in $own_segments $reserved_prefixes; do
		json_add_string "" "$seg"
	done
	json_close_array
	json_add_array units

	# Resolve the carried WANs only when this WAN can translate (it has a pool
	# or at least one override); a floor-only WAN skips the discovery and emits just its
	# floor, exactly as before this option set existed. The WAN's configured ULA segments
	# are appended after the carried-WAN units so config-order placement stays stable.

	if [ -n "$pool" ] || mwan3_translate_has_override "$iface"; then
		config_foreach _mwan3_translate_add_units interface
		_mwan3_translate_add_ula_units
	fi
	json_close_array
	jblob=$(json_dump)

	if [ -n "$pool" ] || [ "$xlate_have_units" = 1 ]; then
		if [ "$reserved_failed" = 1 ] || [ "${own_seg_discovery_failed:-0}" = 1 ] || [ "$ula_discovery_failed" = 1 ]; then

			# Discovery failed this rebuild (the reserved sweep, this WAN's own
			# segments, or the ULA sweep): skip the carve and fall through to the
			# floor only, the fail-closed posture.

			LOG warn "ipv6 translate ($iface): prefix discovery failed, emitting stateful masquerade floor only this rebuild"
		else
			alloc=$(${MWAN3_TRANSLATE_ALLOCATOR} "$jblob")
			alloc_rc=$?

			# The allocator exits nonzero only if it refused to render a misaligned map
			# element (made impossible by intake masking above): treat that like a
			# discovery failure and emit floor only this rebuild.

			if [ "$alloc_rc" -ne 0 ]; then
				LOG warn "ipv6 translate ($iface): allocator failed, emitting stateful masquerade floor only this rebuild"
				alloc=""
			fi

			while read -r tok rest; do
				case "$tok" in
				rule)
					mwan3_nft_push "$rest"
					;;
				target)
					LOG debug "ipv6 translate ($iface): mapped target $rest"
					;;
				absorbed)
					LOG notice "ipv6 translate ($iface): segment ${rest%% *} absorbed into the covering map of ${rest##* }"
					;;
				stateful)
					src="${rest%% *}"
					reason="${rest##* }"
					case "$reason" in
					capacity)
						LOG warn "ipv6 translate ($iface): delegation too small to carve a translation target for $src, using stateful masquerade"
						;;
					overlap)
						LOG warn "ipv6 translate ($iface): target for $src overlaps another target or an own segment, using stateful masquerade"
						;;
					fine)
						LOG warn "ipv6 translate ($iface): target for $src is finer than /64, using stateful masquerade"
						;;
					esac
					;;
				esac
			done <<-EOF
			$alloc
			EOF
		fi
	fi

	# Always-on masquerade floor (see header): pushed after any snat prefix-map rule so a
	# mapped flow binds first and never reaches it (NAT statements are terminal), while an
	# uncovered foreign source falls through here and is masqueraded to the WAN's address.
	# Exclude only the WAN's own delegated prefixes so native traffic stays transparent;
	# with nothing to exclude, every forwarded source is foreign and the match is
	# unconditional.

	excl=""
	for p in $prefixes; do
		excl="${excl:+$excl, }$p"
	done

	if [ -n "$excl" ]; then
		mwan3_nft_push "add rule inet mwan3 mwan3_snat_v6 oifname \"$dev\" ip6 saddr != { $excl } fib saddr type != local masquerade"
	else
		mwan3_nft_push "add rule inet mwan3 mwan3_snat_v6 oifname \"$dev\" meta nfproto ipv6 fib saddr type != local masquerade"
	fi
}

# For an enabled IPv6 mwan3 interface. When online: emit native source-prefix
# marking (each delegated prefix to the interface's own mark), refresh the prefix
# cache, and install this WAN's always-on foreign-source egress translation. When
# offline under ipv6_failover_type 'translate': carry the orphaned prefix over the
# surviving WAN by re-marking the cached prefix to the survivor's mark. That
# re-mark is the only failover-specific step, since the survivor's always-on
# translation is what makes the carried-over source valid on the wire. The offline
# path is scoped to a soft failure, where the interface is still up at netifd but
# its path is dead; network_is_up rejects an admin or hard ifdown (netifd down), so
# those tear down cleanly without engaging failover.

mwan3_add_src_routing_iface()
{
	local iface="$1"
	local enabled family id mark true_iface prefix prefixes segments ipv6_failover_type
	local surv surv_id surv_mark seg_rc own_seg_discovery_failed

	config_get_bool enabled "$iface" enabled 0
	[ "$enabled" -eq 1 ] || return
	config_get family "$iface" family ipv4
	[ "$family" = "ipv6" ] || return

	mwan3_get_iface_id id "$iface"
	[ -n "$id" ] || return
	mark=$(mwan3_id2mask id MMX_MASK)
	mwan3_get_true_iface true_iface "$iface"

	if [ "$(mwan3_get_iface_hotplug_state "$iface")" = "online" ]; then
		prefixes=$(${MWAN3_GET_PREFIX} "$true_iface" "$iface")
		segments=$(${MWAN3_GET_DELEGATED_SEGMENTS} "$true_iface" "$iface")
		seg_rc=$?
		for prefix in $prefixes; do
			_v6_mark_records="${_v6_mark_records}${prefix##*/} $prefix $mark
"
		done
		mwan3_prefix_cache_refresh "$iface" "$prefixes"

		# Fail closed on a segment-discovery failure: keep the last good segment cache and
		# signal the failure to mwan3_install_translate_iface (dynamic scope) so it carves
		# nothing and emits only the floor this rebuild, rather than translating on an
		# incomplete view of this WAN's own segments.

		if [ "$seg_rc" -eq 0 ]; then
			own_seg_discovery_failed=0
			mwan3_segment_cache_refresh "$iface" "$segments"
		else
			own_seg_discovery_failed=1
		fi
		mwan3_install_translate_iface "$iface" "$true_iface" "$prefixes" "$segments"
		return
	fi

	config_get ipv6_failover_type globals ipv6_failover_type off
	[ "$ipv6_failover_type" = "translate" ] || return
	network_is_up "$true_iface" || return
	mwan3_get_ipv6_survivor surv "$iface" || return
	mwan3_get_iface_id surv_id "$surv"
	[ -n "$surv_id" ] || return
	surv_mark=$(mwan3_id2mask surv_id MMX_MASK)

	for prefix in $(mwan3_prefix_cache_read "$iface"); do
		_v6_mark_records="${_v6_mark_records}${prefix##*/} $prefix $surv_mark
"
	done
}

# IPv6 prefix-deprecation failover (ipv6_failover_type=deprecate), the strictly-no-NAT
# alternative to translate for a dual-prefix LAN. On a soft failure of an IPv6 WAN it
# deprecates the downstream LAN router-address(es) in that WAN's delegated prefix
# (preferred_lft 0); odhcpd then advertises the prefix deprecated (RFC 4862), and RFC
# 6724 rule 3 moves clients' new connections to the surviving WAN's prefix, which the
# source-derived routing chain sends out the survivor with no NAT. On recovery the
# preferred lifetime is restored. This acts on downstream addresses, not on the
# egress translation substrate (which stays installed under ipv6_routing), so NAT66
# steering keeps working under deprecate. The failed prefix needs no source-routing
# entry: the offline branch of mwan3_add_src_routing_iface already returns unless the
# mode is translate, so under deprecate the orphan is simply omitted, which is
# correct once its clients have migrated off it.
#
# Discovery and the lifetime change are both done by mwan3-ipv6-deprecate.uc: it
# finds the LAN addresses from netifd delegation state (ubus) and (un)deprecates them
# by a netlink read-modify-write (rtnl), preserving valid_lft and the address flags,
# with no forked ip command. $1 = mwan3 interface, $2 = "deprecate" or "restore".
# Scoped to a soft failure: network_is_up rejects an admin or hard ifdown, where
# netifd owns the prefix lifecycle and there is nothing for mwan3 to do.

mwan3_ipv6_deprecate_lan()
{
	local iface="$1" action="$2"
	local family ipv6_failover_type true_iface

	[ $NO_IPV6 -eq 0 ] || return
	config_get family "$iface" family ipv4
	[ "$family" = "ipv6" ] || return
	config_get ipv6_failover_type globals ipv6_failover_type off
	[ "$ipv6_failover_type" = "deprecate" ] || return

	mwan3_get_true_iface true_iface "$iface"
	network_is_up "$true_iface" || return

	${MWAN3_IPV6_DEPRECATE} "$true_iface" "$action"
	LOG notice "ipv6_failover_type deprecate ($iface): $action"
}

# Re-assert deprecation after a prefix refresh. netifd can overwrite preferred_lft 0
# when it re-applies a refreshed prefix at DHCPv6-PD renewal (NLM_F_REPLACE) and it
# signals that refresh with an ifupdate hotplug event (IFUPDATE_PREFIXES=1). Re-apply
# preferred_lft 0 to every IPv6 WAN still tracked-down under deprecate mode,
# idempotently and regardless of which interface the event named, so the deprecation
# survives the renewal with no polling or timer.

mwan3_ipv6_redeprecate_all()
{
	local ipv6_failover_type

	[ $NO_IPV6 -eq 0 ] || return
	config_get ipv6_failover_type globals ipv6_failover_type off
	[ "$ipv6_failover_type" = "deprecate" ] || return

	_mwan3_redeprecate_one() {
		local cand="$1" en fam
		config_get_bool en "$cand" enabled 0
		[ "$en" -eq 1 ] || return
		config_get fam "$cand" family ipv4
		[ "$fam" = "ipv6" ] || return
		[ "$(mwan3_get_iface_hotplug_state "$cand")" = "online" ] && return
		mwan3_ipv6_deprecate_lan "$cand" deprecate
	}
	config_foreach _mwan3_redeprecate_one interface
}
