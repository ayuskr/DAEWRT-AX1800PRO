#!/bin/bash

. "$(dirname "$(realpath "$0")")/function.sh"

# 修改默认主题依赖
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" "$(find ./feeds/luci/collections/ -type f -name "Makefile")"

# 修改 LuCI 默认访问地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")"

# 添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ DaeWRT-$WRT_DATE')/g" "$(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")"

# 修改默认IP和主机名
CFG_FILE="./package/base-files/files/bin/config_generate"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"

# 强制删除无线默认配置和无线初始化文件
rm -f ./package/base-files/files/etc/config/wireless
rm -f ./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc

# 设置Glass为LuCI默认主题
mkdir -p ./files/etc/uci-defaults
cat > ./files/etc/uci-defaults/99-default-theme <<'EOF'
#!/bin/sh
uci -q set luci.main.mediaurlbase='/luci-static/glass'
uci -q commit luci
rm -f /etc/uci-defaults/99-default-theme
exit 0
EOF
chmod 0755 ./files/etc/uci-defaults/99-default-theme

# 配置编译包
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-glass=y" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-bootstrap is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-argon is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-aurora is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-argon-config is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-aurora-config is not set" >> ./.config

# 手动调整插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

# 高通平台调整
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"

if [[ "$WRT_TARGET" == *"QUALCOMMAX"* ]]; then
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config

	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find "$DTS_PATH" -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi
