#!/bin/bash

set -e

export GIT_TERMINAL_PROMPT=0

UPDATE_PACKAGE() {
	local PKG_NAME="$1"
	local PKG_REPO="$2"
	local PKG_BRANCH="$3"
	local PKG_SPECIAL="$4"
	local PKG_EXTRA_NAMES="$5"
	local PKG_REQUIRED="${6:-true}"
	local PKG_LIST=("$PKG_NAME")
	local REPO_NAME="${PKG_REPO#*/}"
	local REPO_URL="https://github.com/$PKG_REPO.git"

	if [ -n "$PKG_EXTRA_NAMES" ]; then
		read -r -a EXTRA_NAMES <<< "$PKG_EXTRA_NAMES"
		PKG_LIST+=("${EXTRA_NAMES[@]}")
	fi

	echo
	echo "Preparing package: $PKG_NAME"

	if ! git ls-remote \
		--exit-code \
		--heads \
		"$REPO_URL" \
		"$PKG_BRANCH" >/dev/null 2>&1; then

		if [ "$PKG_REQUIRED" = "true" ]; then
			echo "ERROR: Required repository or branch is unavailable."
			echo "Repository: $REPO_URL"
			echo "Branch: $PKG_BRANCH"
			exit 1
		fi

		echo "WARNING: Optional repository or branch is unavailable."
		echo "Repository: $REPO_URL"
		echo "Branch: $PKG_BRANCH"
		echo "Skipping optional package: $PKG_NAME"
		return 0
	fi

	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"

		local FOUND_DIRS
		FOUND_DIRS=$(find \
			../feeds/luci/ \
			../feeds/packages/ \
			-maxdepth 3 \
			-type d \
			-iname "*$NAME*" \
			2>/dev/null || true)

		if [ -n "$FOUND_DIRS" ]; then
			while IFS= read -r DIR; do
				[ -n "$DIR" ] || continue

				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	rm -rf "$REPO_NAME"

	git clone \
		--depth=1 \
		--single-branch \
		--branch "$PKG_BRANCH" \
		"$REPO_URL" \
		"$REPO_NAME"

	if [ "$PKG_SPECIAL" = "pkg" ]; then
		local COPIED=false

		while IFS= read -r PACKAGE_DIR; do
			[ -n "$PACKAGE_DIR" ] || continue

			cp -rf "$PACKAGE_DIR" ./
			echo "Copy package directory: $PACKAGE_DIR"
			COPIED=true
		done < <(
			find "./$REPO_NAME" \
				-mindepth 1 \
				-maxdepth 4 \
				-type d \
				-iname "*$PKG_NAME*" \
				-prune
		)

		rm -rf "$REPO_NAME"

		if [ "$COPIED" != "true" ]; then
			if [ "$PKG_REQUIRED" = "true" ]; then
				echo "ERROR: Package directory was not found: $PKG_NAME"
				exit 1
			fi

			echo "WARNING: Optional package directory was not found: $PKG_NAME"
			return 0
		fi
	elif [ "$PKG_SPECIAL" = "name" ]; then
		rm -rf "$PKG_NAME"
		mv "$REPO_NAME" "$PKG_NAME"
	fi
}

# 删除可能冲突的官方软件包。
rm -rf ../feeds/luci/applications/luci-app-passwall*
rm -rf ../feeds/luci/applications/luci-app-mosdns*
rm -rf ../feeds/luci/applications/luci-app-dockerman*
rm -rf ../feeds/luci/applications/luci-app-dae*
rm -rf ../feeds/luci/applications/luci-app-bypass*
rm -rf ../feeds/packages/net/dae*

# 删除旧主题。
rm -rf ../feeds/luci/themes/luci-theme-argon
rm -rf ../feeds/luci/themes/luci-theme-aurora
rm -rf ../feeds/luci/themes/luci-theme-glass

# 下载 Daed。Daed 是必需包，下载失败时终止编译。
UPDATE_PACKAGE \
	"luci-app-daed" \
	"QiuSimons/luci-app-daed" \
	"kix" \
	"" \
	"" \
	"true"

DAED_MAKEFILE="./luci-app-daed/daed/Makefile"

if [ ! -f "$DAED_MAKEFILE" ]; then
	echo "ERROR: Daed Makefile not found:"
	echo "$DAED_MAKEFILE"
	exit 1
fi

if ! grep -q '^GO_PKG_TAGS:=embedallowed,trace$' "$DAED_MAKEFILE"; then
	echo "ERROR: Daed Makefile does not enable Web UI embedding."
	echo "Expected: GO_PKG_TAGS:=embedallowed,trace"
	exit 1
fi

if ! grep -q 'pnpm build --filter daed' "$DAED_MAKEFILE"; then
	echo "ERROR: Daed frontend build command not found."
	exit 1
fi

if ! grep -q 'apps/web/dist' "$DAED_MAKEFILE"; then
	echo "ERROR: Daed frontend output copy command not found."
	exit 1
fi

echo "Daed Makefile verified."
echo "Web UI embedding: enabled"

# 下载 Lucky。Lucky 是必需包。
UPDATE_PACKAGE \
	"luci-app-lucky" \
	"gdy666/luci-app-lucky" \
	"main" \
	"" \
	"lucky" \
	"true"

# 下载 GecoosAC。
#
# lwb1978/openwrt-gecoosac 当前无法匿名访问，因此暂时作为可选包。
# 仓库恢复公开后，此处会自动重新下载并参与编译。
UPDATE_PACKAGE \
	"luci-app-gecoosac" \
	"lwb1978/openwrt-gecoosac" \
	"main" \
	"" \
	"gecoosac" \
	"false"

# 下载 Glass 主题。Glass 是必需包。
UPDATE_PACKAGE \
	"luci-theme-glass" \
	"rchen14b/luci-theme-glass" \
	"main" \
	"" \
	"glass" \
	"true"

UPDATE_VERSION() {
	local PKG_NAME="$1"
	local PKG_MARK="${2:-false}"
	local PKG_FILES

	PKG_FILES=$(find \
		./ \
		../feeds/packages/ \
		-maxdepth 3 \
		-type f \
		-wholename "*/$PKG_NAME/Makefile" \
		2>/dev/null || true)

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return 0
	fi

	echo
	echo "$PKG_NAME version update has started!"

	while IFS= read -r PKG_FILE; do
		[ -n "$PKG_FILE" ] || continue

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

		PKG_REPO=$(grep -Po \
			'PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+' \
			"$PKG_FILE" || true)

		if [ -z "$PKG_REPO" ]; then
			echo "Cannot determine GitHub repository: $PKG_FILE"
			continue
		fi

		PKG_TAG=$(curl -fsSL \
			"https://api.github.com/repos/$PKG_REPO/releases" |
			jq -r \
				"map(select(.prerelease == $PKG_MARK)) | first | .tag_name" \
			2>/dev/null || true)

		if [ -z "$PKG_TAG" ] || [ "$PKG_TAG" = "null" ]; then
			echo "No release found: $PKG_REPO"
			continue
		fi

		OLD_VER=$(grep -Po 'PKG_VERSION:=\K.*' "$PKG_FILE" || true)
		OLD_URL=$(grep -Po 'PKG_SOURCE_URL:=\K.*' "$PKG_FILE" || true)
		OLD_FILE=$(grep -Po 'PKG_SOURCE:=\K.*' "$PKG_FILE" || true)
		OLD_HASH=$(grep -Po 'PKG_HASH:=\K.*' "$PKG_FILE" || true)

		if [ -z "$OLD_VER" ] || [ -z "$OLD_URL" ]; then
			echo "Incomplete package metadata: $PKG_FILE"
			continue
		fi

		if [[ "$OLD_URL" == *"releases"* ]]; then
			PKG_URL="${OLD_URL%/}/$OLD_FILE"
		else
			PKG_URL="${OLD_URL%/}"
		fi

		NEW_VER=$(echo "$PKG_TAG" |
			sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')

		NEW_URL=$(echo "$PKG_URL" |
			sed \
				-e "s/\$(PKG_VERSION)/$NEW_VER/g" \
				-e "s/\$(PKG_NAME)/$PKG_NAME/g")

		if [ -z "$NEW_URL" ]; then
			echo "Cannot determine source URL: $PKG_FILE"
			continue
		fi

		NEW_HASH=$(curl -fsSL "$NEW_URL" |
			sha256sum |
			cut -d ' ' -f 1 || true)

		if [ -z "$NEW_HASH" ]; then
			echo "Cannot download new source: $NEW_URL"
			continue
		fi

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] &&
			dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then

			sed -i \
				"s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" \
				"$PKG_FILE"

			if grep -q '^PKG_HASH:=' "$PKG_FILE"; then
				sed -i \
					"s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" \
					"$PKG_FILE"
			fi

			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done <<< "$PKG_FILES"
}
