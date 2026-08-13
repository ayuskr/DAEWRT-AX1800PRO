#!/bin/bash

set -e

export GIT_TERMINAL_PROMPT=0

UPDATE_PACKAGE() {
	local PKG_NAME="$1"
	local PKG_REPO="$2"
	local PKG_BRANCH="$3"
	local PKG_SPECIAL="${4:-}"
	local PKG_EXTRA_NAMES="${5:-}"
	local PKG_REQUIRED="${6:-true}"
	local REPO_NAME="${PKG_REPO#*/}"
	local REPO_URL="https://github.com/${PKG_REPO}.git"
	local PKG_LIST=("$PKG_NAME")

	if [ -n "$PKG_EXTRA_NAMES" ]; then
		local EXTRA_NAMES
		read -r -a EXTRA_NAMES <<< "$PKG_EXTRA_NAMES"
		PKG_LIST+=("${EXTRA_NAMES[@]}")
	fi

	echo
	echo "Preparing package: $PKG_NAME"

	if ! git ls-remote --exit-code --heads "$REPO_URL" "$PKG_BRANCH" >/dev/null 2>&1; then
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
		local FOUND_DIRS

		echo "Search directory: $NAME"

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

PATCH_DAED_MAKEFILE() {
	local DAED_MAKEFILE="./luci-app-daed/daed/Makefile"

	if [ ! -f "$DAED_MAKEFILE" ]; then
		echo "ERROR: Daed Makefile not found:"
		echo "$DAED_MAKEFILE"
		exit 1
	fi

	if ! grep -q '^GO_PKG_TAGS:=embedallowed,trace$' "$DAED_MAKEFILE"; then
		echo "ERROR: Daed Web UI embedding is disabled."
		echo "Expected: GO_PKG_TAGS:=embedallowed,trace"
		exit 1
	fi

	if ! grep -q 'pnpm install' "$DAED_MAKEFILE"; then
		echo "ERROR: Daed Makefile does not contain pnpm install."
		exit 1
	fi

	if ! grep -q 'pnpm build --filter daed' "$DAED_MAKEFILE"; then
		echo "ERROR: Daed Makefile does not contain the expected frontend build command."
		echo "Expected: pnpm build --filter daed"
		exit 1
	fi

	if ! grep -q 'apps/web/dist' "$DAED_MAKEFILE"; then
		echo "ERROR: Daed Makefile does not contain the apps/web/dist output path."
		exit 1
	fi

	# 上游源码包自带 wing 目录；删除后才能克隆指定 dae-wing 提交。
	sed -i \
		's|git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR) &&|rm -rf $(PKG_BUILD_DIR) ; git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR) &&|' \
		"$DAED_MAKEFILE"

	# CI 环境默认要求锁文件完全一致，但当前 daed snapshot 的 pnpm-lock.yaml 已过期。
	sed -i \
		's|pnpm install ;|pnpm install --no-frozen-lockfile ;|' \
		"$DAED_MAKEFILE"

	# 只构建 daed workspace 不会产出 apps/web/dist。
	# 直接构建 Web workspace，并在继续前确认存在前端文件。
	# 此处故意不使用 $()，避免被 OpenWrt Make 当成变量再次展开。
	sed -i \
		's|pnpm build --filter daed ;|pnpm --dir apps/web run build ; test -d apps/web/dist ; find apps/web/dist -type f -print -quit | grep -q . ;|' \
		"$DAED_MAKEFILE"

	# 原 Build/Prepare 未启用 set -e；前端失败时可能仍继续编译空目录。
	sed -i \
		'/^define Build\/Prepare$/,/^endef$/ s/^[[:space:]]*( \\$/\t( set -e; \\/' \
		"$DAED_MAKEFILE"

	if ! grep -q 'pnpm install --no-frozen-lockfile' "$DAED_MAKEFILE"; then
		echo "ERROR: Failed to allow the outdated pnpm lockfile."
		exit 1
	fi

	if ! grep -q 'pnpm --dir apps/web run build' "$DAED_MAKEFILE"; then
		echo "ERROR: Failed to configure the Daed Web UI build command."
		exit 1
	fi

	if ! grep -q 'rm -rf $(PKG_BUILD_DIR) ; git clone https://github.com/daeuniverse/dae-wing' "$DAED_MAKEFILE"; then
		echo "ERROR: Failed to fix the dae-wing clone directory conflict."
		exit 1
	fi

	if ! sed -n '/^define Build\/Prepare$/,/^endef$/p' "$DAED_MAKEFILE" | grep -q 'set -e;'; then
		echo "ERROR: Failed to enable error checking in Daed Build/Prepare."
		exit 1
	fi

	echo "Daed Makefile patched successfully."
	echo "Web UI embedding: enabled"
	echo "Web UI build: apps/web"
	echo "PNPM lockfile mode: no-frozen-lockfile"
}

# 删除可能冲突的官方软件包。
rm -rf ../feeds/luci/applications/luci-app-passwall*
rm -rf ../feeds/luci/applications/luci-app-mosdns*
rm -rf ../feeds/luci/applications/luci-app-dockerman*
rm -rf ../feeds/luci/applications/luci-app-dae*
rm -rf ../feeds/luci/applications/luci-app-bypass*
rm -rf ../feeds/packages/net/dae*

# 删除旧主题，统一使用 Glass。
rm -rf ../feeds/luci/themes/luci-theme-argon
rm -rf ../feeds/luci/themes/luci-theme-aurora
rm -rf ../feeds/luci/themes/luci-theme-glass

# Daed 是必需组件。
UPDATE_PACKAGE \
	"luci-app-daed" \
	"QiuSimons/luci-app-daed" \
	"kix" \
	"" \
	"" \
	"true"

PATCH_DAED_MAKEFILE

# Lucky 是必需组件。
UPDATE_PACKAGE \
	"luci-app-lucky" \
	"gdy666/luci-app-lucky" \
	"main" \
	"" \
	"lucky" \
	"true"

# GecoosAC 上游仓库无法匿名访问，已从 GENERAL.txt 移除，不再下载。

# Glass 是必需主题。
UPDATE_PACKAGE \
	"luci-theme-glass" \
	"rchen14b/luci-theme-glass" \
	"main" \
	"" \
	"glass" \
	"true"
