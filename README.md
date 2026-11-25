# LumenWRT

OpenWrt firmware for the **Arcadyan AW1000** (Qualcomm IPQ8072A + Quectel RG500Q-EA),
built on the [qosmio/openwrt-ipq](https://github.com/qosmio/openwrt-ipq) **25.12-nss** fork
with Qualcomm NSS hardware offload and [QModem](https://github.com/FUjr/QModem).

## What's inside

- NSS offload (FW 11.4, ECM, bridge/VLAN managers), NSS-aware modem path
  (`kmod-qmi_wwan_q_nss` + `kmod-rmnet-nss`)
- QModem 3.4.0_rc3.1: `luci-app-qmodem-next` (status, SMS, band lock), VoIP/SIP
  (`qmodem-voip`, `qmodem-sipd`), TTL (`luci-app-qmodem-ttlfw4`, off by default)
- modemdata, WireGuard, kmod-tun, TCP BBR, adb, btop, tmux, iperf3
- Aurora theme, LuCI Dashboard (`luci-mod-dashboard`), "At a Glance" status widget
  (`luci-mod-netstat`; fetches your public IP from api.ipify.org every 5 min while open)

> Enabling QModem TTL stops NSS ECM (routing falls back to the CPU) so the TTL
> rewrite applies to every packet. Leave it off unless your carrier needs it.

## Layout

```
config/sources.env     pinned commits for every source
config/lumenwrt.seed   target + package selection (verified after defconfig)
files/                 rootfs overlay: first-boot defaults, Wi-Fi country, banner
scripts/build.sh       prepare | build | all | menuconfig
openwrt/               build tree (git-ignored, created by the script)
out/                   images (git-ignored)
```

## Build

Host (Ubuntu/Mint) needs the usual OpenWrt build dependencies plus `clang` and
`lld` (QModem VoIP builds a helper with them):

```sh
sudo apt install build-essential clang lld flex bison g++ gawk gettext git \
  libncurses-dev libssl-dev python3-setuptools rsync swig unzip zlib1g-dev file wget
scripts/build.sh all        # first build: ~1-1.5 h on 12 threads
```

Images land in `out/`. Use `*-squashfs-sysupgrade.bin` on a device already running OpenWrt.

### GitHub Actions

`.github/workflows/build.yml` runs the same script on GitHub:

- **Actions → Build LumenWRT → Run workflow** builds and uploads the images as an artifact.
- Pushing a tag (`git tag v0.1.0 && git push --tags`) also publishes a GitHub Release.

Downloads and ccache are cached between runs, so rebuilds are much faster than the first one.

## First boot defaults

| Setting | Default |
|---|---|
| Hostname / LAN | `LumenWRT` / `192.168.1.1` |
| Timezone | Asia/Kuala_Lumpur |
| Wi-Fi | **on**, country MY, SSIDs `LumenWRT` (2.4 GHz) and `LumenWRT_5G`, WPA2, password **`lumenwrt`** |
| Root password | none; LuCI asks you to set one |
| Offloading | flow offloading and packet steering forced off (NSS handles it) |

Change the Wi-Fi password after first login. These defaults only apply on a fresh
config (first flash, or sysupgrade without keeping settings).
