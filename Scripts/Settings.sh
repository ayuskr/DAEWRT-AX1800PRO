#!/bin/bash

. "$(dirname "$(realpath "$0")")/function.sh"

# 修改默认主题依赖。
THEME_MAKEFILES=$(find ./feeds/luci/collections/ -type f -name "Makefile")

if [ -n "$THEME_MAKEFILES" ]; then
	sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $THEME_MAKEFILES
fi

# 修改 LuCI 默认访问地址。
FLASH_JS=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")

if [ -n "$FLASH_JS" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $FLASH_JS
fi

# 添加编译日期标识。
SYSTEM_JS=$(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

if [ -n "$SYSTEM_JS" ]; then
	sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ DaeWRT-$WRT_DATE')/g" $SYSTEM_JS
fi

# 修改默认 IP 地址和主机名。
CFG_FILE="./package/base-files/files/bin/config_generate"

if [ -f "$CFG_FILE" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
fi

# 将 Glass 设置为 LuCI 默认主题。
mkdir -p ./files/etc/uci-defaults

cat > ./files/etc/uci-defaults/99-default-theme <<'EOF'
#!/bin/sh

uci -q set luci.main.mediaurlbase='/luci-static/glass'
uci -q commit luci

rm -f /etc/uci-defaults/99-default-theme
exit 0
EOF

chmod 0755 ./files/etc/uci-defaults/99-default-theme

# 启用 LuCI、中文语言包和 Glass 主题。
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-glass=y" >> ./.config

# 禁用原默认主题与其配置页面。
echo "# CONFIG_PACKAGE_luci-theme-bootstrap is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-argon is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-argon-config is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-aurora is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-aurora-config is not set" >> ./.config

# 完整禁用 ZN-M2 WiFi 软件栈。
echo "# CONFIG_PACKAGE_ipq-wifi-zn_m2 is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-ath11k is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-ath11k-ahb is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-ath11k-pci is not set" >> ./.config
echo "# CONFIG_PACKAGE_ath11k-firmware-ipq6018 is not set" >> ./.config
echo "# CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-mac80211 is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-cfg80211 is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-lib80211 is not set" >> ./.config
echo "# CONFIG_PACKAGE_wifi-scripts is not set" >> ./.config
echo "# CONFIG_PACKAGE_wpad-openssl is not set" >> ./.config
echo "# CONFIG_PACKAGE_wpad-basic-mbedtls is not set" >> ./.config
echo "# CONFIG_PACKAGE_wpad-basic-wolfssl is not set" >> ./.config
echo "# CONFIG_PACKAGE_hostapd-common is not set" >> ./.config
echo "# CONFIG_PACKAGE_iw is not set" >> ./.config
echo "# CONFIG_PACKAGE_iwinfo is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-wireless is not set" >> ./.config

# 手动触发工作流时附加的插件配置。
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

# 高通 NSS 配置。不要改写 DTS 文件，LiBwrt 6.x 没有 ipq6018-nowifi.dtsi。
if [[ "$WRT_TARGET" == *"QUALCOMMAX"* ]]; then
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
fi
