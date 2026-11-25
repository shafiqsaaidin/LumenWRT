---
name: lumenwrt-build
description: Build LumenWRT firmware for the AW1000 locally or on GitHub Actions, and verify the resulting images (checksums, package manifest, rootfs contents). Use when asked to build, rebuild, release, or check a build/artifact, or when a build fails.
---

# Building LumenWRT

Everything goes through `scripts/build.sh`; CI runs the same script.

## Locally

```sh
scripts/build.sh prepare   # clone/pin sources, feeds, overlay, defconfig, verify seed
scripts/build.sh build     # make download + make -j$(nproc); images -> out/
scripts/build.sh all
scripts/build.sh menuconfig  # explore; writes out/diffconfig.txt, copy wanted lines into the seed
```

- Host needs the OpenWrt deps plus **clang and lld** (qmodem-voip). Machine:
  12 threads, 14 GB RAM, Mint 22.3. First local build ~1-1.5 h, tree ~30 GB.
- `prepare` is idempotent and cheap after the first run; run it after any
  change to `config/` or `files/` — it re-syncs the overlay and re-verifies.
- Verification fails the run if a seed `=y` line was dropped (typo or unmet
  dependency) or a `# ... is not set` line came back as `=y/=m`. Fix the seed;
  don't weaken the check. Find who selects a symbol with:
  `awk '/^config PACKAGE_/{p=$2} /select PACKAGE_<name>( |$)/{print p}' openwrt/tmp/.config-package.in`
  (or `grep -n -B30 "select PACKAGE_<name>$"` and read the nearest `config` line).
- On failure `build.sh` reruns `make -j1 V=s` for a readable error; per-package
  logs are in `openwrt/logs/` (`CONFIG_BUILD_LOG=y`).

## GitHub Actions

- Workflow `.github/workflows/build.yml`, runner ubuntu-24.04 (4 cores, public repo).
- Trigger: `gh workflow run build.yml --ref main`, or push a tag `v*` (also
  creates a GitHub Release with the images). Plain pushes do NOT build.
- `concurrency: cancel-in-progress` — dispatching again cancels a running build.
- Wait with a background `gh run watch <id> --interval 120 --exit-status`, don't poll.
- ~65 min per build so far. dl/ and ccache are restored/saved as separate steps
  (saved even on failure); ccache key includes the seed hash, so seed changes
  mostly miss the cache.
- On failure download `build-logs-<n>` artifact: `gh run download <id> -n build-logs-<n>`.

## Verifying an artifact

Download into the scratchpad, never into the repo:

```sh
gh run download <id> -D <scratch>/art
cd <scratch>/art/*
sha256sum -c sha256sums --ignore-missing        # every listed file must be OK
grep -E '^(kmod-rmnet-nss|kmod-qmi_wwan_q_nss|qmodem|luci-app-qmodem-next) - ' *.manifest
grep -E '^(kmod-qmi_wwan_q|wpad-basic-mbedtls|qmodem-seal) - ' *.manifest   # must be empty
tail -c 2000 *sysupgrade.bin | strings | grep supported_devices             # arcadyan,aw1000
```

Inspect the rootfs (overlay files, enabled services, kernel modules):

```sh
mkdir img && tar -xf *sysupgrade.bin -C img && unsquashfs -q -d img/root img/sysupgrade-*/root
ls -l img/root/etc/uci-defaults/99-lumenwrt img/root/etc/board.d/99-lumenwrt
ls img/root/etc/rc.d | grep -E 'ttl|ecm'      # S95qmodem_ttl, S26qca-nss-ecm
ls img/root/lib/modules/*/ | grep -E 'tproxy|rmnet|qmi_wwan|ecm|tun.ko'
```

Expected outputs: `*-squashfs-sysupgrade.bin` (~23 MB, for devices already on
OpenWrt), `*-squashfs-factory.ubi`, `*-initramfs-uImage.itb` (recovery via
U-Boot TFTP), manifest, `*.buildinfo`, `profiles.json`, `sha256sums`.
Image names start with `lumenwrt-25.12-snapshot-...` (VERSION_DIST).
