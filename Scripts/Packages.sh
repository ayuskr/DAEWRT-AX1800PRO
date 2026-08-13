#!/bin/bash

set -e

UPDATE_PACKAGE() {
	local PKG_NAME="$1"
	local PKG_REPO="$2"
	local PKG_BRANCH="$3"
	local PKG_SPECIAL="$4"
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME="${PKG_REPO#*/}"

	echo
	echo "Preparing package: $PKG_NAME"

	for NAME in "${PKG_LIST[@]}"; do
		local FOUND_DIRS
		FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ \
			-maxdepth 3 \
			-type d \
			-iname "*$NAME*" \
			2>/dev/null || true)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				[ -n "$DIR" ] || continue
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		fi
	done

	rm -rf "$REPO_NAME"

	git clone \
		--depth=1 \
		--single-branch \
		--branch "$PKG_BRANCH" \
		"https://github.com/$PKG_REPO.git" \
		"$REPO_NAME"

	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "./$REPO_NAME"/*/ \
			-maxdepth 3 \
			-type d \
			-iname "*$PKG_NAME*" \
			-prune \
			-exec cp -rf {} ./ \;

		rm -rf "$REPO_NAME"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

rm -rf ../feeds/luci/applications/luci-app-passwall*
rm -rf ../feeds/luci/applications/luci-app-mosdns*
rm -rf ../feeds/luci/applications/luci-app-dockerman*
rm -rf ../feeds/luci/applications/luci-app-dae*
rm -rf ../feeds/luci/applications/luci-app-bypass*
rm -rf ../feeds/packages/net/dae*

rm -rf ../feeds/luci/themes/luci-theme-argon
rm -rf ../feeds/luci/themes/luci-theme-aurora
rm -rf ../feeds/luci/themes/luci-theme-glass

UPDATE_PACKAGE \
	"luci-app-daed" \
	"QiuSimons/luci-app-daed" \
	"kix"

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

UPDATE_PACKAGE \
	"luci-app-lucky" \
	"gdy666/luci-app-lucky" \
	"main" \
	"" \
	"lucky"

UPDATE_PACKAGE \
	"luci-app-gecoosac" \
	"lwb1978/openwrt-gecoosac" \
	"main" \
	"" \
	"gecoosac"

UPDATE_PACKAGE \
	"luci-theme-glass" \
	"rchen14b/luci-theme-glass" \
	"main" \
	"" \
	"glass"
