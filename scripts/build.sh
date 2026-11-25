#!/usr/bin/env bash
# LumenWRT build driver for Arcadyan AW1000 (qualcommax/ipq807x, NSS).
#
#   scripts/build.sh prepare   clone/pin sources, feeds, apply seed + files, defconfig, verify
#   scripts/build.sh build     download sources and compile, copy images to out/
#   scripts/build.sh all       prepare + build
#   scripts/build.sh menuconfig  open menuconfig on the prepared tree, then print the diff
#
# Env: JOBS (default nproc), V (e.g. V=s for verbose make)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRT="$ROOT/openwrt"
OUT="$ROOT/out"
JOBS="${JOBS:-$(nproc)}"
# shellcheck source=../config/sources.env
. "$ROOT/config/sources.env"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Clone repo $1 into dir $2 and check out commit $3 (detached).
pin_repo() {
	local url="$1" dir="$2" ref="$3"
	if [ ! -d "$dir/.git" ]; then
		git clone --filter=blob:none "$url" "$dir"
	fi
	if ! git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null; then
		git -C "$dir" fetch --tags origin
	fi
	git -C "$dir" -c advice.detachedHead=false checkout --force "$ref"
}

prepare() {
	log "Base tree: $OPENWRT_REPO @ ${OPENWRT_REF:0:12}"
	pin_repo "$OPENWRT_REPO" "$WRT" "$OPENWRT_REF"

	log "Feeds"
	{
		grep -v '^[[:space:]]*#' "$WRT/feeds.conf.default" | sed '/^[[:space:]]*$/d'
		echo "src-git qmodem ${QMODEM_REPO}^${QMODEM_REF}"
		echo "src-git modemdata ${MODEMDATA_REPO}^${MODEMDATA_REF}"
		echo "src-git modemdata_luci ${MODEMDATA_LUCI_REPO}^${MODEMDATA_LUCI_REF}"
	} > "$WRT/feeds.conf"
	cat "$WRT/feeds.conf"
	(cd "$WRT" && ./scripts/feeds update -a && ./scripts/feeds install -a)

	log "Extra packages"
	mkdir -p "$WRT/package/lumenwrt"
	pin_repo "$AURORA_REPO"     "$WRT/package/lumenwrt/luci-theme-aurora"     "$AURORA_REF"
	pin_repo "$AURORA_CFG_REPO" "$WRT/package/lumenwrt/luci-app-aurora-config" "$AURORA_CFG_REF"
	pin_repo "$NETSTAT_REPO"    "$WRT/package/lumenwrt/luci-mod-netstat"       "$NETSTAT_REF"

	log "Overlay files"
	rsync -a --delete "$ROOT/files/" "$WRT/files/"

	log "Config"
	cp "$ROOT/config/lumenwrt.seed" "$WRT/.config"
	(cd "$WRT" && make defconfig >/dev/null)
	verify_config
}

# Every "=y" line in the seed must survive defconfig; otherwise a package name
# is wrong or a dependency is unmet and Kconfig silently dropped it.
verify_config() {
	local missing=0 line
	while IFS= read -r line; do
		grep -qxF "$line" "$WRT/.config" || { echo "  dropped: $line"; missing=1; }
	done < <(grep -E '^CONFIG_[A-Za-z0-9_.+-]+=y$' "$ROOT/config/lumenwrt.seed")
	[ "$missing" = 0 ] || die "seed options were dropped by defconfig (see above)"
	log "Config OK: all seed options present"
}

build() {
	[ -f "$WRT/.config" ] || die "run 'prepare' first"
	cd "$WRT"
	log "Downloading sources"
	make download -j"$JOBS" ${V:+V=$V}
	log "Compiling with $JOBS jobs"
	make -j"$JOBS" ${V:+V=$V} || {
		log "Parallel build failed, retrying single-threaded for a readable error"
		make -j1 V=s
	}
	mkdir -p "$OUT"
	cp -v bin/targets/qualcommax/ipq807x/*arcadyan_aw1000* "$OUT/"
	# Build metadata listed in sha256sums (seed diff, feed revisions, version, profiles)
	cp -v bin/targets/qualcommax/ipq807x/{sha256sums,*.buildinfo,profiles.json} "$OUT/" 2>/dev/null || true
	log "Images in $OUT"
}

menuconfig() {
	cd "$WRT"
	make menuconfig
	./scripts/diffconfig.sh > "$OUT/diffconfig.txt" 2>/dev/null || true
	log "Diff vs defaults written to $OUT/diffconfig.txt; copy what you want into config/lumenwrt.seed"
}

case "${1:-}" in
	prepare) prepare ;;
	build) build ;;
	all) prepare; build ;;
	menuconfig) mkdir -p "$OUT"; menuconfig ;;
	*) sed -n '2,10p' "$0"; exit 1 ;;
esac
