#
# Copyright (C) 2006-2014 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=mwan3
PKG_VERSION:=3.6.9
PKG_RELEASE:=1

PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
PKG_LICENSE:=GPL-2.0
PKG_CONFIG_DEPENDS:=CONFIG_IPV6
PKG_BUILD_DEPENDS:=libnetfilter_conntrack libmnl

include $(INCLUDE_DIR)/package.mk

define Package/mwan3
   SECTION:=net
   CATEGORY:=Network
   SUBMENU:=Routing and Redirection
   DEPENDS:= \
     +ip-full \
     +libnetfilter-conntrack \
     +kmod-nft-core \
     +nftables-json \
     +rpcd-mod-ucode \
     +jshn \
     +ucode \
     +ucode-mod-rtnl \
     +ucode-mod-uloop \
     +ucode-mod-uci \
     +ucode-mod-ubus \
     +ucode-mod-fs \
     +ucode-mod-socket
   TITLE:=Multiwan hotplug script with connection tracking support (ucode rtmon)
   MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
endef

define Package/mwan3/description
Hotplug script which makes configuration of multiple WAN interfaces simple
and manageable. With loadbalancing/failover support for up to 250 wan
interfaces, connection tracking and an easy to manage traffic ruleset.
mwan3rtmon now uses a ucode implementation leveraging ucode-mod-rtnl
for direct netlink access instead of forking ip commands.
endef

define Package/mwan3/conffiles
/etc/config/mwan3
/etc/mwan3.user
endef

define Package/mwan3/preinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	# Stop mwan3evtd if present (older installs included this daemon). The
	# pre-upgrade hook runs before APK removes files no longer in the
	# package, so this must happen here to avoid leaving a running process
	# with no init script or binary after the file swap.
	/etc/init.d/mwan3evtd stop 2>/dev/null
	/etc/init.d/mwan3evtd disable 2>/dev/null
	# Record whether this is a fresh install so postinst can auto-enable
	# without overriding an explicit disable by the user on upgrade.
	[ -f /etc/init.d/mwan3 ] || touch /tmp/mwan3_first_install
	# Stop mwan3 before APK replaces any files. This is critical for
	# upgrades: if mwan3 is running when the init script is replaced,
	# procd's inotify trigger restarts the service while the old ip rules
	# are still installed, producing RTNETLINK "File exists" errors when
	# start_service tries to re-add them. Stopping here puts the service
	# into procd's "stopped" state before the init script changes, so
	# procd does not auto-restart it.
	/etc/init.d/mwan3 stop 2>/dev/null
fi
exit 0
endef

define Package/mwan3/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	# Safety-net stop in case preinst did not run or procd restarted the
	# service between preinst and postinst.
	/etc/init.d/mwan3 stop 2>/dev/null
	# mwan3_prerouting/mwan3_output run at priority mangle + 1, backed by
	# non-destructive vmap-dispatch save/restore so the placement is
	# order-independent w.r.t. pbr. Older installs used mangle - 1.
	# nftables rejects a base chain redeclaration at a different priority,
	# so flush+delete the old chains before start recreates them.
	for chain in mwan3_prerouting mwan3_output; do
		if nft list chain inet fw4 "$$chain" 2>/dev/null | grep -q "priority mangle - 1"; then
			nft flush chain inet fw4 "$$chain" 2>/dev/null
			nft delete chain inet fw4 "$$chain" 2>/dev/null
		fi
	done
	# Drop legacy ip->mark sticky maps (replaced by per-(rule,family,member)
	# ip-only sets). Leftover legacy maps are unreferenced after upgrade
	# but waste a name and confuse status.
	for mapname in $$(nft list maps inet 2>/dev/null | \
			  awk '$$1=="map" && $$2 ~ /^mwan3_sticky_v[46]_/ { print $$2 }'); do
		nft delete map inet fw4 "$$mapname" 2>/dev/null
	done
	# mwan3 now operates in table inet mwan3 rather than table inet fw4.
	# fw4 uses flush-table (not delete-table) on reload, so any mwan3
	# chains/sets left in fw4 survive fw4 reloads and must be explicitly
	# removed.
	for chain in mwan3_prerouting mwan3_output mwan3_postrouting \
	             mwan3_ifaces_in mwan3_rules mwan3_connected mwan3_custom mwan3_dynamic; do
		nft flush chain inet fw4 "$$chain" 2>/dev/null
		nft delete chain inet fw4 "$$chain" 2>/dev/null
	done
	for setname in mwan3_connected_v4 mwan3_connected_v6 \
	               mwan3_custom_v4 mwan3_custom_v6 \
	               mwan3_dynamic_v4 mwan3_dynamic_v6; do
		nft delete set inet fw4 "$$setname" 2>/dev/null
	done
	for mapname in $$(nft list maps inet fw4 2>/dev/null | \
			  awk '$$1=="map" && $$2 ~ /^mwan3_sticky_/ { print $$2 }'); do
		nft flush map inet fw4 "$$mapname" 2>/dev/null
		nft delete map inet fw4 "$$mapname" 2>/dev/null
	done
	# Remove stale firewall.mwan3_reload UCI section if present and reload
	# fw4 only if it was. An unconditional fw4 -q reload would trigger
	# queued ifup hotplug events that race with mwan3_create_iface_rules
	# in the init hotplug, producing RTNETLINK "File exists" errors.
	if uci -q delete firewall.mwan3_reload; then
		uci commit firewall
		fw4 -q reload
	fi
	# Migrate any fw4-side set references in mwan3 rules to config ipset
	# declarations in /etc/config/mwan3 (one-shot, idempotent).
	/lib/mwan3/mwan3-migrate-ipset-v4.sh
	rm -f /lib/mwan3/mwan3-migrate-ipset-v4.sh
	/etc/init.d/rpcd restart
	# Second stop immediately before start: procd may have auto-started mwan3
	# when the init script was installed (the first stop above runs before that
	# happens and is therefore a no-op). By this point the auto-start has
	# completed, so this stop calls stop_service and removes its ip rules.
	# Without this, mwan3 start below calls procd_close_service (which tells
	# procd to replace the service instances) but never calls stop_service,
	# so the ip rules from the auto-start are still present when the init
	# hotplug events try to add them again.
	# Auto-enable on fresh install so mwan3 starts at boot without requiring
	# a manual /etc/init.d/mwan3 enable. On upgrade the flag is absent, so
	# an explicit disable by the user is preserved.
	if [ -f /tmp/mwan3_first_install ]; then
		rm -f /tmp/mwan3_first_install
		/etc/init.d/mwan3 enable
	fi
	/etc/init.d/mwan3 stop 2>/dev/null
	/etc/init.d/mwan3 start
fi
exit 0
endef

define Package/mwan3/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/rpcd restart
	for f in /tmp/dnsmasq.*.d/mwan3-nftsets.conf /tmp/dnsmasq.d/mwan3-nftsets.conf; do
		[ -f "$$f" ] && rm -f "$$f"
	done
	/etc/init.d/dnsmasq restart 2>/dev/null
fi
exit 0
endef

define Build/Compile
	$(TARGET_CC) $(CFLAGS) $(LDFLAGS) $(FPIC) \
		-shared \
		-o $(PKG_BUILD_DIR)/libwrap_mwan3_sockopt.so.1.0 \
		$(if $(CONFIG_IPV6),-DCONFIG_IPV6) \
		$(PKG_BUILD_DIR)/sockopt_wrap.c \
		-ldl
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		-o $(PKG_BUILD_DIR)/mwan3ct \
		$(PKG_BUILD_DIR)/mwan3ct.c \
		-lnetfilter_conntrack -lmnl -lnfnetlink
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		-o $(PKG_BUILD_DIR)/mwan3ipcheck \
		$(PKG_BUILD_DIR)/mwan3ipcheck.c
endef

define Package/mwan3/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/mwan3 \
		$(1)/etc/config/

	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DATA) ./files/etc/hotplug.d/iface/25-mwan3 \
		$(1)/etc/hotplug.d/iface/
	$(INSTALL_DATA) ./files/etc/hotplug.d/iface/26-mwan3-user \
		$(1)/etc/hotplug.d/iface/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/mwan3 \
		$(1)/etc/init.d/

	$(INSTALL_DIR) $(1)/lib/mwan3
	$(INSTALL_DATA) ./files/lib/mwan3/common.sh \
		$(1)/lib/mwan3/
	$(INSTALL_DATA) ./files/lib/mwan3/mwan3.sh \
		$(1)/lib/mwan3/
	$(INSTALL_DATA) ./files/lib/mwan3/mwan3-skeleton.nft \
		$(1)/lib/mwan3/
	$(INSTALL_BIN) ./files/lib/mwan3/mwan3-migrate-ipset-v4.sh \
		$(1)/lib/mwan3/
	$(INSTALL_BIN) ./files/lib/mwan3/mwan3-get-addr.uc \
		$(1)/lib/mwan3/
	$(INSTALL_BIN) ./files/lib/mwan3/mwan3-manage-rules.uc \
		$(1)/lib/mwan3/
	$(INSTALL_BIN) ./files/lib/mwan3/mwan3-list-routes.uc \
		$(1)/lib/mwan3/
	$(INSTALL_BIN) ./files/lib/mwan3/mwan3-create-iface-route.uc \
		$(1)/lib/mwan3/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode/
	$(INSTALL_BIN) ./files/usr/share/rpcd/ucode/mwan3 \
		$(1)/usr/share/rpcd/ucode/

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/mwan3 \
		$(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/mwan3rtmon \
		$(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/mwan3track \
		$(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/mwan3-lb-test \
		$(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/mwan3-diag \
		$(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_BIN) ./files/etc/mwan3.user \
		$(1)/etc/

	$(CP) $(PKG_BUILD_DIR)/libwrap_mwan3_sockopt.so.1.0 $(1)/lib/mwan3/

	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mwan3ct $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mwan3ipcheck $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DATA) ./files/etc/uci-defaults/mwan3-migrate-flush_conntrack \
		$(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./files/etc/uci-defaults/mwan3-remove-firewall-include \
		$(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,mwan3))
