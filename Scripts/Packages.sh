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
	local PREPARE_BLOCK

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

	if ! grep -q 'git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR)' \
		"$DAED_MAKEFILE"; then
		echo "ERROR: Expected dae-wing clone command was not found."
		exit 1
	fi

	if ! grep -q 'pnpm install ;' "$DAED_MAKEFILE"; then
		echo "ERROR: Expected pnpm install command was not found."
		exit 1
	fi

	if ! grep -q 'pnpm build --filter daed ;' "$DAED_MAKEFILE"; then
		echo "ERROR: Expected Daed frontend build command was not found."
		echo "Expected: pnpm build --filter daed ;"
		exit 1
	fi

	if ! grep -q 'apps/web/dist' "$DAED_MAKEFILE"; then
		echo "ERROR: Daed Makefile does not contain apps/web/dist."
		exit 1
	fi

	# daed 源码包中可能已存在 wing 目录。克隆 dae-wing 前先删除，
	# 防止 git clone 因目标目录非空而失败。
	sed -i \
		's@			git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR) && \\@			rm -rf $(PKG_BUILD_DIR) ; \\@' \
		"$DAED_MAKEFILE"

	sed -i \
		'/^[[:space:]]*rm -rf $(PKG_BUILD_DIR) ; \\$/a\
			git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR) \&\& \\' \
		"$DAED_MAKEFILE"

	# GitHub Actions 中 pnpm 默认启用 frozen-lockfile。
	# 当前 snapshot 的 package.json 与 pnpm-lock.yaml 不完全一致，
	# 因此允许 pnpm 更新锁文件后安装依赖。
	sed -i \
		's@			pnpm install ; \\@			pnpm install --no-frozen-lockfile ; \\@' \
		"$DAED_MAKEFILE"

	# 保留上游 workspace 构建命令，在构建结束后检查实际前端产物。
	# 不使用 shell 的 $()，避免被 OpenWrt Make 提前展开。
	sed -i \
		's@			pnpm build --filter daed ; \\@			pnpm build --filter daed ; \\\
			test -d apps/web/dist ; \\\
			find apps/web/dist -type f -print -quit | grep -q . ; \\@' \
		"$DAED_MAKEFILE"

	# Build/Prepare 中任意命令失败时立即停止。
	sed -i \
		'/^define Build\/Prepare$/,/^endef$/ s/^[[:space:]]*( \\$/	( set -e; \\/' \
		"$DAED_MAKEFILE"

	PREPARE_BLOCK=$(sed -n \
		'/^define Build\/Prepare$/,/^endef$/p' \
		"$DAED_MAKEFILE")

	if ! grep -q 'rm -rf $(PKG_BUILD_DIR)' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to add dae-wing directory cleanup."
		exit 1
	fi

	if ! grep -q 'git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR)' \
		<<< "$PREPARE_BLOCK"; then
		echo "ERROR: The dae-wing clone command was lost while patching."
		exit 1
	fi

	if ! grep -q 'pnpm install --no-frozen-lockfile' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to disable pnpm frozen-lockfile mode."
		exit 1
	fi

	if ! grep -q 'pnpm build --filter daed' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: The Daed frontend build command was lost while patching."
		exit 1
	fi

	if ! grep -q 'find apps/web/dist -type f -print -quit | grep -q .' \
		<<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to add the Daed frontend output check."
		exit 1
	fi

	if ! grep -q 'set -e;' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to enable error checking in Build/Prepare."
		exit 1
	fi

	echo "Daed Makefile patched successfully."
	echo "Web UI embedding: enabled"
	echo "Frontend build command: pnpm build --filter daed"
	echo "PNPM lockfile mode: no-frozen-lockfile"
	echo "Frontend output check: enabled"
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

# GecoosAC 上游仓库当前不可匿名访问。
# Config/GENERAL.txt 已移除 luci-app-gecoosac，因此这里不再下载。

# Glass 是必需主题。
UPDATE_PACKAGE \
	"luci-theme-glass" \
	"rchen14b/luci-theme-glass" \
	"main" \
	"" \
	"glass" \
	"true"
