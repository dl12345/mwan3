#
# Copyright (C) 2006-2014 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=mwan3
PKG_VERSION:=3.4.1
PKG_RELEASE:=1

PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
PKG_LICENSE:=GPL-2.0
PKG_CONFIG_DEPENDS:=CONFIG_IPV6

include $(INCLUDE_DIR)/package.mk

define Package/mwan3
   SECTION:=net
   CATEGORY:=Network
   SUBMENU:=Routing and Redirection
   DEPENDS:= \
     +ip \
     +kmod-nft-core \
     +nftables-json \
     +rpcd-mod-ucode \
     +jshn \
     +ucode \
     +ucode-mod-rtnl \
     +ucode-mod-uloop \
     +ucode-mod-uci \
     +ucode-mod-ubus \
     +ucode-mod-fs
   TITLE:=Multiwan hotplug script with connection tracking support (ucode rtmon)
   MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
   PKGARCH:=all
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

define Package/mwan3/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	# v3.2+: priority is mangle + 1 (was mangle - 1 in v3.1.4),
	# backed by non-destructive vmap-dispatch save/restore so the
	# placement is order-independent w.r.t. pbr. nftables rejects a base
	# chain redeclaration at a different priority, so flush+delete first.
	for chain in mwan3_prerouting mwan3_output; do
		if nft list chain inet fw4 "$$chain" 2>/dev/null | grep -q "priority mangle - 1"; then
			nft flush chain inet fw4 "$$chain" 2>/dev/null
			nft delete chain inet fw4 "$$chain" 2>/dev/null
		fi
	done
	# Drop legacy ip->mark sticky maps from <=v3.1.4. They are replaced by
	# per-(rule,family,member) ip-only sets. Leftover legacy maps are
	# unreferenced after upgrade but waste a name and confuse status.
	for mapname in $$(nft list maps inet 2>/dev/null | \
			  awk '$$1=="map" && $$2 ~ /^mwan3_sticky_v[46]_/ { print $$2 }'); do
		nft delete map inet fw4 "$$mapname" 2>/dev/null
	done
	# v4+: mwan3 moved from table inet fw4 to table inet mwan3. fw4 uses
	# flush-table (not delete-table) on reload, so chains/sets added by
	# v3.x survive across fw4 reloads and must be explicitly removed.
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
	# Remove stale firewall.mwan3_reload UCI section and reload fw4 once
	# to drop the (now-uninstalled) mwan3 include from fw4's config.
	uci -q delete firewall.mwan3_reload && uci commit firewall
	fw4 -q reload
	# Migrate any fw4-side set references in mwan3 rules to config ipset
	# declarations in /etc/config/mwan3 (one-shot, idempotent).
	/lib/mwan3/mwan3-migrate-ipset-v4.sh
	rm -f /lib/mwan3/mwan3-migrate-ipset-v4.sh
	/etc/init.d/rpcd restart
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

	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_BIN) ./files/etc/mwan3.user \
		$(1)/etc/

	$(CP) $(PKG_BUILD_DIR)/libwrap_mwan3_sockopt.so.1.0 $(1)/lib/mwan3/

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DATA) ./files/etc/uci-defaults/mwan3-migrate-flush_conntrack \
		$(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./files/etc/uci-defaults/mwan3-remove-firewall-include \
		$(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,mwan3))
