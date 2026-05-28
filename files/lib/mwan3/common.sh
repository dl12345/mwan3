#!/bin/sh

IP4="ip -4"
IP6="ip -6"
UCODE="ucode"
MWAN3_LIB_PATH="/lib/mwan3"
MWAN3_CREATE_IFACE_ROUTE="${UCODE} ${MWAN3_LIB_PATH}/mwan3-create-iface-route.uc"
MWAN3_GET_ADDR="${UCODE} ${MWAN3_LIB_PATH}/mwan3-get-addr.uc"
MWAN3_LIST_ROUTES="${UCODE} ${MWAN3_LIB_PATH}/mwan3-list-routes.uc"
MWAN3_MANAGE_RULES="${UCODE} ${MWAN3_LIB_PATH}/mwan3-manage-rules.uc"
SCRIPTNAME="$(basename "$0")"

MWAN3_STATUS_DIR="/var/run/mwan3"
MWAN3TRACK_STATUS_DIR="/var/run/mwan3track"

MWAN3_INTERFACE_MAX=""

MMX_MASK=""
MMX_DEFAULT=""
MMX_BLACKHOLE=""
MM_BLACKHOLE=""

MMX_UNREACHABLE=""
MM_UNREACHABLE=""
MAX_SLEEP=$(((1<<31)-1))

# nftables inet family handles both IPv4 and IPv6
# Check if IPv6 is disabled in the kernel

[ -d /proc/sys/net/ipv6 ]
NO_IPV6=$?

NFT="nft"
MWAN3_NFT_BATCH="$MWAN3_STATUS_DIR/mwan3_nft_batch.$$"
MWAN3_BATCH_DEPTH=0
MWAN3_NEED_DNSMASQ_HUP=0

LOG()
{
	local facility=$1; shift

	[ "$facility" = "debug" ] && [ "${MWAN3_VERBOSE_LOGGING:-0}" = "0" ] && return
	logger -t "${SCRIPTNAME}[$$]" -p $facility "$*"
}

# Execute an nft command. When inside a batch (MWAN3_BATCH_DEPTH > 0), push
# the command into the batch file instead of running nft immediately.

mwan3_nft_exec()
{
	if [ "$MWAN3_BATCH_DEPTH" -gt 0 ]; then
		mwan3_nft_push "$@"
		return
	fi
	local error
	error=$($NFT "$@" 2>&1) || {
		LOG error "nft $*: $error"
		return 1
	}
}

# Start an nft batch. Truncates the batch file only when opening the outermost
# level (depth 0 -> 1). Nested calls increment depth and are otherwise no-ops,
# so callers can open their own mini-batches inside a larger reload batch
# without inadvertently truncating it.

mwan3_nft_batch_start()
{
	if [ "$MWAN3_BATCH_DEPTH" -eq 0 ]; then
		local old_umask
		old_umask=$(umask)
		umask 077
		: > "$MWAN3_NFT_BATCH"
		umask "$old_umask"
	fi
	MWAN3_BATCH_DEPTH=$((MWAN3_BATCH_DEPTH + 1))
}

# Append a line to the nft batch. Called directly with a pre-formatted nft
# statement, or indirectly via mwan3_nft_exec when MWAN3_BATCH_DEPTH > 0.

mwan3_nft_push()
{
	echo "$*" >> "$MWAN3_NFT_BATCH"
}

# Commit the nft batch. Decrements depth; only commits to the kernel when
# reaching depth 0 (the outermost level). Inner commits from nested callers
# are no-ops: they just decrement the counter and return.

mwan3_nft_batch_commit()
{
	MWAN3_BATCH_DEPTH=$((MWAN3_BATCH_DEPTH - 1))
	[ "$MWAN3_BATCH_DEPTH" -gt 0 ] && return 0
	local error
	error=$($NFT -f "$MWAN3_NFT_BATCH" 2>&1) || {
		LOG error "nft batch: $error"
		rm -f "$MWAN3_NFT_BATCH"
		return 1
	}
	rm -f "$MWAN3_NFT_BATCH"
}

# Begin an atomic reload batch. Opens the outermost batch level (depth 0->1)
# so all subsequent mwan3_nft_batch_start/commit calls from build functions
# accumulate into the same global batch rather than committing immediately.
# The preamble: flushes all skeleton chains, then flushes+deletes all dynamic
# chains (iface_in, policy, rule, or-setter, etc.).
# Internal mwan3_* sets are deleted so mwan3_ensure_nft_framework can recreate
# them with correct flags. User-defined sets are never touched.

mwan3_nft_reload_start()
{
	local chain setname
	mwan3_nft_batch_start
	for chain in mwan3_prerouting mwan3_output mwan3_postrouting \
	             mwan3_ifaces_in mwan3_rules mwan3_connected mwan3_custom mwan3_dynamic; do
		mwan3_nft_push "flush chain inet mwan3 $chain"
	done

	# Two-pass: flush all dynamic chains first to remove cross-references
	# (e.g. mwan3_rule_* chains jump to mwan3_or_meta_* chains), then delete.
	# A single-pass flush+delete in alphabetical order fails with "Device or
	# resource busy" because mwan3_or_meta_* sorts before mwan3_rule_*, so
	# the delete fires while the rule chain still holds a jump reference.

	local _dyn_chains=""
	for chain in $($NFT list chains inet 2>/dev/null | grep "chain mwan3_" | awk '{gsub(/ \{.*/, ""); print $2}'); do
		case "$chain" in
			mwan3_prerouting|mwan3_output|mwan3_postrouting|\
			mwan3_ifaces_in|mwan3_rules|mwan3_connected|mwan3_custom|mwan3_dynamic)
				;;
			*)
				mwan3_nft_push "flush chain inet mwan3 $chain"
				_dyn_chains="$_dyn_chains $chain"
				;;
		esac
	done
	for chain in $_dyn_chains; do
		mwan3_nft_push "delete chain inet mwan3 $chain"
	done
	for setname in mwan3_connected_v4 mwan3_connected_v6 \
	               mwan3_custom_v4 mwan3_custom_v6 \
	               mwan3_dynamic_v4 mwan3_dynamic_v6; do
		mwan3_nft_push "delete set inet mwan3 $setname"
	done
}

# Commit the reload batch atomically to the kernel (thin wrapper around
# mwan3_nft_batch_commit, which handles the depth decrement and actual commit).

mwan3_nft_reload_commit()
{
	mwan3_nft_batch_commit
}

# Build an nft mark set expression
# iptables: -j MARK --set-xmark VALUE/MASK
# means: mark = (mark & ~MASK) | VALUE
# nftables: meta mark set (meta mark & ~MASK) | VALUE
# Uses & and | symbols (not 'and'/'or' keywords) to avoid parser ambiguity

mwan3_nft_mark_expr()
{
	local value="$1" mask="$2"
	local complement
	complement=$(printf "0x%08x" $(( (~mask) & 0xFFFFFFFF )))
	echo "meta mark set meta mark & $complement | $value"
}

# Canonicalise a mark value (e.g. 0x100, 0x00000100) to a stable chain-name suffix.
# Used to name the per-mark OR-immediate setter chains. Always emits lowercase
# 0x%x form so two callers computing the same mark land on the same chain name.

mwan3_or_chain_suffix()
{
	printf "0x%x" $(($1))
}

# Build the per-mark OR-immediate setter chains used to synthesise non-destructive
# cross-register copies via vmap dispatch. For each mark M in the configured set
# of valid mwan3 mark values we create:
#   chain mwan3_or_meta_<M>:  meta mark set meta mark | M
#   chain mwan3_or_ct_<M>  :  ct   mark set ct   mark | M
# These chains are jumped into from vmap statements that key on the masked value
# of the source register; the runtime register value is "lifted" into the
# immediate operand of each branch's set statement, sidestepping the kernel
# limitation that an nft set-statement expression tree may reference at most one
# runtime source register. With these helpers in place, both restore (ct -> meta)
# and save (meta -> ct) become non-destructive in the unmasked bits, which
# removes mwan3's previous priority dependency on pbr.

mwan3_build_or_chains_nft()
{
	local id mark suffix want

	# Compute the full set of mark values that may need a setter chain:
	# every per-iface mark id 1..MWAN3_INTERFACE_MAX, plus the three special
	# marks (default, blackhole, unreachable).

	want=""
	for id in $(seq 1 "$MWAN3_INTERFACE_MAX"); do
		mark=$(mwan3_id2mask id MMX_MASK)
		suffix=$(mwan3_or_chain_suffix "$mark")
		want="$want $suffix"
	done
	want="$want $(mwan3_or_chain_suffix "$MMX_DEFAULT")"
	want="$want $(mwan3_or_chain_suffix "$MMX_BLACKHOLE")"
	want="$want $(mwan3_or_chain_suffix "$MMX_UNREACHABLE")"

	# Always flush+repopulate. A previous idempotency check that only verified
	# chain *existence* could leave empty chain bodies wedged after a partial
	# batch failure, with no recovery path. ~126 trivial statements; cheap.

	mwan3_nft_batch_start
	for suffix in $want; do
		mwan3_nft_push "add chain inet mwan3 mwan3_or_meta_${suffix}"
		mwan3_nft_push "add chain inet mwan3 mwan3_or_ct_${suffix}"
		mwan3_nft_push "flush chain inet mwan3 mwan3_or_meta_${suffix}"
		mwan3_nft_push "flush chain inet mwan3 mwan3_or_ct_${suffix}"
		mwan3_nft_push "add rule inet mwan3 mwan3_or_meta_${suffix} meta mark set meta mark | ${suffix}"
		mwan3_nft_push "add rule inet mwan3 mwan3_or_ct_${suffix} ct mark set ct mark & $MMX_MASK_COMPLEMENT | ${suffix}"
	done
	mwan3_nft_batch_commit
}

# Build the verdict-map body of a vmap statement that, given a key set of
# mark values, jumps to the matching mwan3_or_<reg>_<mark> setter chain.
# Args: $1 = "meta" or "ct" (target register), $2... = mark values
# Result echoed as the body for use as: <key-expr> vmap { <body> }

mwan3_or_vmap_body()
{
	local reg="$1"; shift
	local mark suffix first=1 body=""
	for mark in "$@"; do
		suffix=$(mwan3_or_chain_suffix "$mark")
		if [ $first -eq 1 ]; then
			body="${suffix} : jump mwan3_or_${reg}_${suffix}"
			first=0
		else
			body="${body}, ${suffix} : jump mwan3_or_${reg}_${suffix}"
		fi
	done
	echo "$body"
}

# Enumerate every mark value that needs to appear in the restore/save vmaps:
# all per-iface marks plus the three specials. Echoes a space-separated list.

mwan3_all_marks()
{
	local id
	for id in $(seq 1 "$MWAN3_INTERFACE_MAX"); do
		mwan3_id2mask id MMX_MASK
		printf " "
	done
	printf "%s %s %s\n" "$MMX_DEFAULT" "$MMX_BLACKHOLE" "$MMX_UNREACHABLE"
}

# Ensure all mwan3 nftables framework objects exist with correct flags.
# Always deletes and recreates sets to guarantee auto-merge is present.

mwan3_ensure_nft_framework()
{
	local setname

	# Always delete existing sets — nft 'add set' is idempotent and won't
	# update flags (like auto-merge) on existing sets, so we must recreate.
	# stop_service() flushes chains first, so no rules reference the sets.
	# Inside a reload batch the deletions are already in the preamble.

	if [ "$MWAN3_BATCH_DEPTH" -eq 0 ]; then
		for setname in mwan3_connected_v4 mwan3_connected_v6 \
		               mwan3_custom_v4 mwan3_custom_v6 \
		               mwan3_dynamic_v4 mwan3_dynamic_v6; do
			$NFT delete set inet mwan3 "$setname" >/dev/null 2>&1
		done
	fi

	mwan3_nft_batch_start

	# Sets for network classification (interval + auto-merge for CIDR support)

	mwan3_nft_push "add set inet mwan3 mwan3_connected_v4 { type ipv4_addr; flags interval; auto-merge; }"
	mwan3_nft_push "add set inet mwan3 mwan3_connected_v6 { type ipv6_addr; flags interval; auto-merge; }"
	mwan3_nft_push "add set inet mwan3 mwan3_custom_v4 { type ipv4_addr; flags interval; auto-merge; }"
	mwan3_nft_push "add set inet mwan3 mwan3_custom_v6 { type ipv6_addr; flags interval; auto-merge; }"
	mwan3_nft_push "add set inet mwan3 mwan3_dynamic_v4 { type ipv4_addr; flags interval; auto-merge; }"
	mwan3_nft_push "add set inet mwan3 mwan3_dynamic_v6 { type ipv6_addr; flags interval; auto-merge; }"

	# Hook chains (base chains with type/hook/priority)

	mwan3_nft_push "add chain inet mwan3 mwan3_prerouting { type filter hook prerouting priority mangle + 1; policy accept; }"
	mwan3_nft_push "add chain inet mwan3 mwan3_output { type route hook output priority mangle + 1; policy accept; }"

	# IPv6 SNAT chain (opt-in per interface via 'snat6'). See 10-mwan3.nft
	# for the rationale; per-iface rules are added by mwan3_create_iface_nft.

	mwan3_nft_push "add chain inet mwan3 mwan3_postrouting { type nat hook postrouting priority srcnat - 1; policy accept; }"

	# Internal chains (jumped to from hook chains)

	mwan3_nft_push "add chain inet mwan3 mwan3_ifaces_in"
	mwan3_nft_push "add chain inet mwan3 mwan3_rules"
	mwan3_nft_push "add chain inet mwan3 mwan3_connected"
	mwan3_nft_push "add chain inet mwan3 mwan3_custom"
	mwan3_nft_push "add chain inet mwan3 mwan3_dynamic"

	mwan3_nft_batch_commit
}

mwan3_get_true_iface()
{
	local family V
	_true_iface=$2
	config_get family "$2" family ipv4
	if [ "$family" = "ipv4" ]; then
		V=4
	elif [ "$family" = "ipv6" ]; then
		V=6
	fi
	ubus call "network.interface.${2}_${V}" status &>/dev/null && _true_iface="${2}_${V}"
	export "$1=$_true_iface"
}

mwan3_get_src_ip()
{
	local family _src_ip interface true_iface device addr_cmd default_ip
	interface=$2
	mwan3_get_true_iface true_iface $interface

	unset "$1"
	config_get family "$interface" family ipv4
	if [ "$family" = "ipv4" ]; then
		addr_cmd='network_get_ipaddr'
		default_ip="0.0.0.0"
	elif [ "$family" = "ipv6" ]; then
		addr_cmd='network_get_ipaddr6'
		default_ip="::"
	fi

	$addr_cmd _src_ip "$true_iface"
	if [ -z "$_src_ip" ]; then
		if [ "$family" = "ipv6" ]; then

			# on IPv6-PD interfaces (like PPPoE interfaces) we don't
			# have a real address, just a prefix, that can be delegated
			# to interfaces, because using :: (the fallback above) or
			# the link-local address will not work (reliably, if at
			# all) try to find an address which we can use instead

			network_get_prefix6 _src_ip "$true_iface"
			if [ -n "$_src_ip" ]; then

				# got a prefix like 2001:xxxx:yyyy::/48, clean it up to
				# only contain the prefix -> 2001:xxxx:yyyy

				_src_ip=$(echo "$_src_ip" | sed -e 's;:*/.*$;;')
				_src_ip=$(${MWAN3_GET_ADDR} 6 "" "$_src_ip")
			fi
		fi
		if [ -z "$_src_ip" ]; then
			network_get_device device $true_iface
			local _fam_num=4
			[ "$family" = "ipv6" ] && _fam_num=6
			_src_ip=$(${MWAN3_GET_ADDR} "$_fam_num" "$device")
		fi
		if [ -n "$_src_ip" ]; then
			LOG warn "no src $family address found from netifd for interface '$true_iface' dev '$device' guessing $_src_ip"
		else
			_src_ip="$default_ip"
			LOG warn "no src $family address found for interface '$true_iface' dev '$device'"
		fi
	fi
	export "$1=$_src_ip"
}

readfile() {
	[ -f "$2" ] || return 1

	# read returns 1 on EOF
	read -d'\0' $1 <"$2" || :
}

mwan3_get_mwan3track_status()
{
	local interface=$2
	local track_ips track_gateway pid cmdline started
	mwan3_list_track_ips()
	{
		track_ips="$1 $track_ips"
	}
	config_list_foreach "$interface" track_ip mwan3_list_track_ips
	config_get_bool track_gateway "$interface" track_gateway 0

	if [ -z "$track_ips" ] && [ "$track_gateway" -eq 0 ]; then
		export -n "$1=disabled"
		return
	fi
	readfile pid $MWAN3TRACK_STATUS_DIR/$interface/PID 2>/dev/null
	if [ -z "$pid" ]; then
		export -n "$1=down"
		return
	fi
	readfile cmdline /proc/$pid/cmdline 2>/dev/null
	if [ "$cmdline" != "/bin/sh/usr/sbin/mwan3track${interface}" ]; then
		export -n "$1=down"
		return
	fi
	readfile started $MWAN3TRACK_STATUS_DIR/$interface/STARTED
	case "$started" in
		0)
			export -n "$1=paused"
			;;
		1)
			export -n "$1=active"
			;;
		*)
			export -n "$1=down"
			;;
	esac
}

mwan3_init()
{
	local bitcnt mmdefault source_routing

	config_load mwan3
	config_get_bool MWAN3_VERBOSE_LOGGING globals verbose_logging 0

	[ -d $MWAN3_STATUS_DIR ] || { mkdir -m 0700 $MWAN3_STATUS_DIR && mkdir -m 0700 $MWAN3_STATUS_DIR/iface_state; }

	# mwan3's MARKing mask (at least 3 bits should be set)
	if [ -e "${MWAN3_STATUS_DIR}/mmx_mask" ]; then
		readfile MMX_MASK "${MWAN3_STATUS_DIR}/mmx_mask"
		MWAN3_INTERFACE_MAX=$(uci_get_state mwan3 globals iface_max)
	else
		config_get MMX_MASK globals mmx_mask '0x3F00'
		echo "$MMX_MASK"| tr 'A-F' 'a-f' > "${MWAN3_STATUS_DIR}/mmx_mask"
		LOG debug "Using firewall mask ${MMX_MASK}"

		bitcnt=$(mwan3_count_one_bits MMX_MASK)
		mmdefault=$(((1<<bitcnt)-1))
		MWAN3_INTERFACE_MAX=$((mmdefault-3))
		uci_toggle_state mwan3 globals iface_max "$MWAN3_INTERFACE_MAX"
		LOG debug "Max interface count is ${MWAN3_INTERFACE_MAX}"
	fi

	# mark mask constants

	bitcnt=$(mwan3_count_one_bits MMX_MASK)
	mmdefault=$(((1<<bitcnt)-1))
	MM_BLACKHOLE=$((mmdefault-2))
	MM_UNREACHABLE=$((mmdefault-1))

	# MMX_DEFAULT should equal MMX_MASK

	MMX_DEFAULT=$(mwan3_id2mask mmdefault MMX_MASK)
	MMX_BLACKHOLE=$(mwan3_id2mask MM_BLACKHOLE MMX_MASK)
	MMX_UNREACHABLE=$(mwan3_id2mask MM_UNREACHABLE MMX_MASK)

	# Precompute mask complement for nft rules

	MMX_MASK_COMPLEMENT=$(printf "0x%08x" $(( (~MMX_MASK) & 0xFFFFFFFF )))

	# Configurable ip rule base priorities. Defaults preserve the historical
	# layout exactly: per-interface iif lookup rules at id+1000, fwmark lookup
	# rules at id+2000, fwmark unreachable rules at id+3000. Two ordering
	# constraints must hold to avoid priority collisions:
	#   iif_rule_base + MWAN3_INTERFACE_MAX < fwmark_rule_base
	#   fwmark_rule_base + MWAN3_INTERFACE_MAX + 1 < unreachable_rule_base
	# (the +1 reflects that the fwmark tier also contains the global blackhole
	# and unreachable rules at fwmark_rule_base + MM_BLACKHOLE / MM_UNREACHABLE,
	# the highest of which is fwmark_rule_base + MWAN3_INTERFACE_MAX + 2.)
	# If either constraint is violated, all three values are reverted to defaults.
	#
	# Like MMX_MASK, the post-validation values are persisted to /var/state/mwan3
	# at start time and read back from state on subsequent mwan3_init invocations
	# (including from stop_service). This ensures the values seen by stop_service
	# identify the rules the running instance actually created, even if
	# /etc/config/mwan3 has been edited since start. The mmx_mask state file
	# doubles as the "instance started" indicator.

	if [ -e "${MWAN3_STATUS_DIR}/mmx_mask" ]; then
		MWAN3_IIF_RULE_BASE=$(uci_get_state mwan3 globals iif_rule_base 1000)
		MWAN3_FWMARK_RULE_BASE=$(uci_get_state mwan3 globals fwmark_rule_base 2000)
		MWAN3_UNREACHABLE_RULE_BASE=$(uci_get_state mwan3 globals unreachable_rule_base 3000)
	else
		config_get MWAN3_IIF_RULE_BASE globals iif_rule_base 1000
		config_get MWAN3_FWMARK_RULE_BASE globals fwmark_rule_base 2000
		config_get MWAN3_UNREACHABLE_RULE_BASE globals unreachable_rule_base 3000

		if [ "$((MWAN3_IIF_RULE_BASE + MWAN3_INTERFACE_MAX))" -ge "$MWAN3_FWMARK_RULE_BASE" ] || \
		   [ "$((MWAN3_FWMARK_RULE_BASE + MWAN3_INTERFACE_MAX + 1))" -ge "$MWAN3_UNREACHABLE_RULE_BASE" ]; then
			LOG warn "Rule base ordering constraint violated (iif=$MWAN3_IIF_RULE_BASE, fwmark=$MWAN3_FWMARK_RULE_BASE, unreachable=$MWAN3_UNREACHABLE_RULE_BASE, max_interfaces=$MWAN3_INTERFACE_MAX); reverting all to defaults 1000/2000/3000"
			MWAN3_IIF_RULE_BASE=1000
			MWAN3_FWMARK_RULE_BASE=2000
			MWAN3_UNREACHABLE_RULE_BASE=3000
		fi

		uci_toggle_state mwan3 globals iif_rule_base "$MWAN3_IIF_RULE_BASE"
		uci_toggle_state mwan3 globals fwmark_rule_base "$MWAN3_FWMARK_RULE_BASE"
		uci_toggle_state mwan3 globals unreachable_rule_base "$MWAN3_UNREACHABLE_RULE_BASE"
	fi
}

# maps the 1st parameter so it only uses the bits allowed by the bitmask (2nd parameter)
# which means spreading the bits of the 1st parameter to only use the bits that are set to 1 in the 2nd parameter
# 0 0 0 0 0 1 0 1 (0x05) 1st parameter
# 1 0 1 0 1 0 1 0 (0xAA) 2nd parameter
#     1   0   1          result

mwan3_id2mask()
{
	local bit_msk bit_val result
	bit_val=0
	result=0
	for bit_msk in $(seq 0 31); do
		if [ $((($2>>bit_msk)&1)) = "1" ]; then
			if [ $((($1>>bit_val)&1)) = "1" ]; then
				result=$((result|(1<<bit_msk)))
			fi
			bit_val=$((bit_val+1))
		fi
	done
	printf "0x%x" $result
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

get_uptime() {
	local _tmp
	readfile _tmp /proc/uptime
	if [ $# -eq 0 ]; then
		echo "${_tmp%%.*}"
	else
		export -n "$1=${_tmp%%.*}"
	fi
}

get_online_time() {
	local time_n time_u iface
	iface="$2"
	readfile time_u "$MWAN3TRACK_STATUS_DIR/${iface}/ONLINE" 2>/dev/null
	[ -z "${time_u}" ] || [ "${time_u}" = "0" ] || {
		get_uptime time_n
		export -n "$1=$((time_n-time_u))"
	}
}

