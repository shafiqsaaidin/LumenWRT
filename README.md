# LumenWRT

OpenWrt firmware for the **Arcadyan AW1000** (Qualcomm IPQ8072A + Quectel RG500Q-EA).

> **Branch `ppe-nss` (experimental, untested on hardware).** Built on
> [openwrt-ppe-nss](https://github.com/JuliusBairaktaris/openwrt-ppe-nss) (OpenWrt main,
> kernel 6.18): wired offload in the PPE through the standard fw4 flowtable, Wi-Fi and the
> raw-IP modem path on the NSS cores (`nss-wifi-drv`). No vendor NSS stack, no QModem.
> The stable line (25.12-nss + QModem) is on `main`.

## What's inside (ppe-nss)

- PPE + NSS offload: fw4 hardware flow offloading (on unless TTL is on), `nss-wifi-drv`
- Modem: upstream `qmi_wwan` + [wwand](https://github.com/ddimension/wwand) (GPL-2.0):
  dialling, SMS, USSD, band/cell lock, SIM/eSIM, recovery incl. AW1000 modem power cycle,
  RGB 5G/signal LEDs from its AW1000 board profile; LuCI via `luci-app-wwand`
- TTL rewrite on 5G egress (`/etc/config/lumenwrt`, **on by default, TTL 64**)
- WireGuard, kmod-tun, kmod-nft-tproxy (for xlite), TCP BBR, adb, btop, tmux, iperf3
- Aurora theme, LuCI Dashboard (LuCI main: live charts, temperature), "At a Glance" widget
  (`luci-mod-netstat`; fetches your public IP from api.ipify.org every 5 min while open)

> **TTL vs offload:** while TTL rewriting is on, `lumenwrt-ttl` turns fw4 flow offloading
> off so every packet passes the nftables rule (routing on the CPU). Turn it off with
> `uci set lumenwrt.ttl.enabled=0; uci commit lumenwrt; reload_config` to get PPE/NSS offload back.

> **Installing packages later:** the image's apk feeds point at upstream OpenWrt
> (snapshot on this branch). Regular packages install fine, but **kernel modules (`kmod-*`) won't**:
> this kernel carries PPE/NSS patches, so upstream kmods don't match it. Add any
> kernel module you need to `config/lumenwrt.seed` and rebuild.

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

Host (Ubuntu/Mint) needs the usual OpenWrt build dependencies:

```sh
sudo apt install build-essential clang lld flex bison g++ gawk gettext git \
  libncurses-dev libssl-dev python3-setuptools rsync swig unzip zlib1g-dev file wget
scripts/build.sh all                          # tree in ./openwrt
BUILD_DIR=openwrt-ppe scripts/build.sh all    # keep a second tree side by side
```

Sources and feeds are pinned in `config/sources.env`; images land in `out/`.

### GitHub Actions

`.github/workflows/build.yml` runs the same script on GitHub:

- **Actions → Build LumenWRT → Run workflow** (pick the branch) builds and uploads the images.
- Pushing a tag (`git tag v0.1.0 && git push --tags`) also publishes a GitHub Release.

## First boot defaults (ppe-nss)

| Setting | Default |
|---|---|
| Hostname / LAN | `LumenWRT` / `192.168.1.1` |
| Timezone | Asia/Kuala_Lumpur |
| Wi-Fi | **on**, country MY, SSIDs `LumenWRT` (2.4 GHz) and `LumenWRT_5G`, WPA2, password **`lumenwrt`** |
| Root password | none; LuCI asks you to set one |
| LuCI theme | Aurora (Bootstrap kept as a fallback) |
| 5G | wwand autosetup: interface `wwan0` (device `wwand0`) in the wan zone, APN from the SIM's ICCID/IMSI table |
| Ethernet WAN | `wan` as DHCP client without default route (5G stays primary); no `wan6` |
| TTL | on, 64, on `wwand*` egress; flow offloading off while on |

### Front-panel LEDs

| LED | Driven by | Meaning |
|---|---|---|
| Power | device tree | always on |
| 5G | wwand (AW1000 profile) | green = LTE, blue = 5G (blinks when weak), red = searching |
| Signal | wwand (AW1000 profile) | red / yellow / green by signal bars, red blink = searching |
| Internet | netdev `wwand0` | on and blinking with 5G traffic |
| Wi-Fi | netdev `phy0-ap0` | on and blinking with Wi-Fi traffic |
| Phone | default-on + `/etc/hotplug.d/wwand` | on; blinks ~30 s on a new SMS |

Change the Wi-Fi password after first login. These defaults apply on a fresh config
(first flash, or sysupgrade without keeping settings); a keep-settings upgrade
doesn't re-apply them. **Flash this branch without keeping settings** when coming
from the 25.12/QModem line: their configs don't carry over.
