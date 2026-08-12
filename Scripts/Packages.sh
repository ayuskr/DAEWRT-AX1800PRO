#!/bin/bash

UPDATE_PACKAGE() {
	local PKG_NAME="$1"
	local PKG_REPO="$2"
	local PKG_BRANCH="$3"
	local PKG_SPECIAL="$4"
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME="${PKG_REPO#*/}"

	echo

	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS
		FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "./$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME/"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# 移除源码及 feeds 中的冲突插件
rm -rf ../feeds/luci/applications/luci-app-{passwall*,mosdns,dockerman,dae*,bypass*}
rm -rf ../feeds/packages/net/{dae*,lucky,microsocks}
rm -rf ../feeds/luci/themes/luci-theme-{argon,aurora,glass}

# Daed LuCI 管理界面
UPDATE_PACKAGE "luci-app-daed" "QiuSimons/luci-app-daed" "kix"

# Lucky
UPDATE_PACKAGE "luci-app-lucky" "gdy666/luci-app-lucky" "main" "" "lucky"

# Gecoosac
UPDATE_PACKAGE "luci-app-gecoosac" "lwb1978/openwrt-gecoosac" "main" "" "gecoosac"

# Glass主题
UPDATE_PACKAGE "luci-theme-glass" "Luci-theme/luci-theme-glass" "main" "" "glass"

# 更新软件包版本函数
UPDATE_VERSION() {
	local PKG_NAME="$1"
	local PKG_MARK="${2:-false}"
	local PKG_FILES
	PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo
	echo "$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO
		local PKG_TAG
		local OLD_VER
		local OLD_URL
		local OLD_FILE
		local OLD_HASH
		local PKG_URL
		local NEW_VER
		local NEW_URL
		local NEW_HASH

		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE")
		PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")
		PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}
