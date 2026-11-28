# LumenWRT — project memory

OpenWrt firmware for the **Arcadyan AW1000** (IPQ8072A, Quectel RG500Q-EA 5G over
USB 3), built on **qosmio/openwrt-ipq `25.12-nss`** (Qualcomm NSS offload) with
**QModem**. Public repo: https://github.com/shafiqsaaidin/LumenWRT

This file is public. Credentials and private notes go in `CLAUDE.local.md`
(git-ignored), never here.

## Hard rules

- **The AW1000 (192.168.1.1) is this PC's internet uplink** (PC joins its Wi-Fi).
  Flashing, rebooting, or changing its Wi-Fi/WAN cuts this PC — and this session —
  offline. A clean flash also changes the SSID/password, so the PC won't rejoin
  by itself. Never reboot/flash/reconfigure it without the user's explicit OK
  for that step, and tell them beforehand that the connection will drop.
- **Never flash an image we didn't build and verify ourselves** (no third-party
  prebuilt images, even if their device list includes the AW1000). Every flash
  needs the user's explicit "flash it" for that image, in that message — an
  offer of help (e.g. a machine to run it from) is not a go-ahead.
  (2026-11-28: a prebuilt ppe-nss image left the AW1000 without Wi-Fi and the
  user had to recover it by hand.)
- Read-only on the router unless asked. Back up (`sysupgrade -b`) before any change.
- Sources are pinned by commit in `config/sources.env`. Never build from moving
  branches; bump deliberately (see skill `lumenwrt-packages`).
- Don't invent default passwords/keys beyond the documented ones. The repo is public.

## Business model (decided 2026-11-28)

LumenWRT is a **commercial product**: the firmware with a custom web UI is sold,
plus paid support. Consequences for engineering:

- **No non-commercial or unlicensed components in the image.** QModem
  (MPL-2.0 + "no commercial use"), quectel-CM ("Quectel Proprietary and
  Confidential"), obsy modemdata and 4IceG apps without a licence file are out.
  Check the licence of every new package before adding it (see skill
  `lumenwrt-packages`).
- GPL/LGPL parts: ship complete corresponding source for every release.
  Qualcomm NSS/Wi-Fi firmware: binary redistribution only, unmodified, on
  Qualcomm chips; include its licence text.
- The custom UI/API is our own work and is meant to stay proprietary: keep it
  a separate program (no GPL code copied into it) and out of this public repo.
- Plan: replace QModem with upstream `qmi_wwan` + netifd `qmi` (uqmi) +
  `sms-tool` (Apache-2.0) + our own `lumen` API, on the current qosmio
  25.12-nss base.
- ppe-nss (JuliusBairaktaris, prebuilt 2026-11-22, kernel 6.18) on the AW1000:
  booted after ~11 min, 5G worked with upstream qmi_wwan + netifd qmi (APN
  `internet`, uqmi signal/serving JSON fine), but **no Wi-Fi APs came up** and
  most LEDs were off. Rejected as a base for now.

## Branches

- `main`: the working line on the device (qosmio 25.12-nss + QModem). Not
  sellable as-is (QModem/quectel-CM licences).
- `ppe-nss` (2026-11-28; **our CI build #1 runs on the AW1000**, flashed clean
  by the user: boot ~20 s to init, both Wi-Fi bands up with NSS Wi-Fi offload,
  wwand autosetup → APN `diginet`, IPv4 internet over `wwand0` (qmi_wwan),
  LEDs right (green 5G = LTE, green signal), TTL rule active, CPU idle;
  SMS / speed / reboot still to test). **TTL off (= flow offloading on) breaks
  LAN traffic over 5G**: flows enter the sw flowtable, PPE rejects them
  (ingress_not_switch_port), downloads stall at 0 B. wwand uses QMAP
  (`mux_id auto`: `wwan0` raw_ip+pass_through, virtual `wwand0` child);
  ppe-nss PR #41 was tested with vendor qmi_wwan_q (plain `wwan0_1`). Next
  experiment: `network.wwan0.mux_id='0'`. Until fixed keep TTL on. Link speed
  measured 2.9 Mbit/s both router-originated and forwarded (line-limited, LTE
  RSRP −97). `uci commit` alone doesn't apply lumenwrt-ttl: use `reload_config`.
  Base: openwrt-ppe-nss @ 0514ded,
  all feeds pinned in `FEEDS` (sources.env), modem via upstream qmi_wwan +
  wwand (GPL-2.0, AW1000 board profile drives 5G/signal LEDs + modem power),
  own TTL service `/etc/init.d/lumenwrt-ttl` (TTL on => fw4 flow offloading
  off), LED rules in `99-lumenwrt`, SMS LED via `/etc/hotplug.d/wwand`.
  Licence audit of the resolved config: nothing non-commercial; only firmware
  blobs (nss-firmware, ath11k, ipq-wifi BDF) and adb lack PKG_LICENSE.
  First flash must be clean (`sysupgrade -n`), wired access ready (homelab).

## Decisions (and why)

| Decision | Choice | Why |
|---|---|---|
| Base | qosmio `25.12-nss` @ pinned SHA | NSS offload; release feeds instead of snapshot |
| QModem | `v3.4.0_rc3.1` (not stable 3.3.0) | user wants VoIP/SIP; `qmodem-sipd` only exists in 3.4 |
| Modem driver | `kmod-qmi_wwan_q_nss` + `kmod-rmnet-nss` (QModem feed) | NSS-offloaded 5G path; 25.12-nss's nss-packages has no wwan dir |
| QModem driver choice | `CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_nss-qmi-wwan=y` | default "vendor" choice also pulls `kmod-qmi_wwan_q` (same .ko → conflict) |
| UI | `luci-app-qmodem-next` (has SMS) | legacy `luci-app-qmodem`/`-sms`/`-ttl` can't coexist with `-next` |
| TTL | `luci-app-qmodem-ttlfw4`, **on by default, TTL 64** | user choice. While on, it **stops NSS ECM** (CPU routing) |
| Theme | Aurora default, Bootstrap kept as fallback | user choice |
| Extras | modemdata (obsy + 4IceG feeds), luci-mod-dashboard, luci-mod-netstat (cjayacopra), WireGuard, kmod-tun, kmod-tcp-bbr, kmod-nft-tproxy, adb, btop, tmux | user list; nft-tproxy is for xlite |
| Wi-Fi | on by default, `LumenWRT`/`LumenWRT_5G`, WPA2, key `lumenwrt`, country MY | user wants Wi-Fi on; set via board.d so it applies at wireless generation |
| WAN | `wwan` (5G, QMAP `wwan0_1`, metric 11, default route) + `wan` (Ethernet port, DHCP, `defaultroute 0`), no `wan6`; both in fw zone `wan` | matches the pre-LumenWRT router |
| LEDs | own script `files/usr/share/qmodem/led_scripts/lumenwrt_aw1000.sh`, run by QModem's `qmodem_led` (`modem_status` section `cellular`, bind any) | reproduces the old router's behaviour; the ShiranekoWrt `aw1000.sh` it replaces has no licence and isn't upstream, so it was not copied |
| Dashboard | `luci-mod-dashboard` from LuCI master (pinned) over the 25.12 feed copy | user wants eamonxg's rewrite (luci#9022); 25.12 has it via backport, master adds temperature + WAN fix for wwan/@wwan; JS + rpcd ucode only, same deps |
| Builds | GitHub Actions (public repo, 4-core runners), ~65 min | user choice; local build also works |

## Layout

- `config/sources.env` — pinned repos/SHAs (OpenWrt fork, QModem, modemdata, Aurora, netstat)
- `config/lumenwrt.seed` — diffconfig. `=y` lines must survive defconfig and
  `# ... is not set` lines must stay off; `scripts/build.sh` enforces both
- `files/` — rootfs overlay: `etc/board.d/99-lumenwrt` (Wi-Fi defaults),
  `etc/uci-defaults/99-lumenwrt` (hostname, TZ, NSS offload off, Aurora, TTL),
  `etc/uci-defaults/99-zz-lumenwrt-modem` (WAN interfaces, QModem slot, LED setup),
  `usr/share/qmodem/led_scripts/lumenwrt_aw1000.sh` (LED controller),
  `etc/hotplug.d/iface/90-lumenwrt-modemdata` (modemdata AT port),
  `etc/firewall.d/qmodem_ttl` (no-op the ttlfw4 init calls), `etc/banner`
- `patches/<feed>/*.patch` — local fixes applied with `git apply` to
  `openwrt/feeds/<feed>` after each feeds update (feed reset first). Each patch
  header says which upstream commit makes it obsolete.
- Feed overrides (`apply_overrides` in build.sh, refs in sources.env): a package
  dir in a feed checkout is replaced by the same path from another repo/commit.
  Currently `luci/modules/luci-mod-dashboard` from LuCI master (`DASHBOARD_REF`).
  Runs after patches; don't patch an overridden dir. Sparse clones live in
  `openwrt/.lumenwrt-src/`.
- `scripts/build.sh prepare|build|all|menuconfig` — single entry point, used by CI
- `.github/workflows/build.yml` — manual dispatch or `v*` tag (tag = GitHub Release)
- `openwrt/`, `out/` — git-ignored build tree and images

## Gotchas learned

- Kernel modules can't come from upstream apk feeds (NSS-patched kernel, vermagic
  differs). Every `kmod-*` must be in the seed.
- `uqmi` (AW1000 device profile) pulls generic `kmod-usb-net-qmi-wwan`; it also
  matches 2c7c:0800 but `qmi_wwan_q` (modules.d `81-`) loads first and binds. Verify
  `Driver=qmi_wwan_q` after flashing.
- Packages living at a repo root (Aurora, netstat) are cloned into
  `openwrt/package/lumenwrt/`; repos with packages in subdirs are added as
  `src-git name url^sha` feeds. Feed names: letters/digits/underscore only.
- Set `# CONFIG_FEED_<name> is not set` for custom feeds so they aren't written
  into the image's apk repositories.
- Overlay files get no `%D/%V` substitution (banner is static text).
- Wi-Fi defaults must go through `ucidef_set_wireless`/`ucidef_set_country` in
  board.d; an SSID default makes the iface enabled, so always give a key.
- qmodem-voip compiles a helper with host `clang` + `lld` (`-fuse-ld=lld`).
- `make defconfig` prints "recursive dependency" errors for dnsdist, snort3, etc.
  — upstream feed noise, harmless.
- QModem `v3.4.0_rc3.1`'s `luci-app-qmodem-next` installed its views to
  `/www/resources/` (cp into a missing `$(1)/www`), so LuCI 404'd on
  `view/qmodem/overview.js` in the first flashed image. Fixed by
  `patches/qmodem/0001-*`; upstream fix a06124f9a0. A green build + manifest
  check doesn't catch this: also check web files in the rootfs
  (`www/luci-static/resources/view/<app>/`).
- modemdata shows nothing until a modem is defined in `/etc/config/defmodems`
  (section type `defmodems`: modem, modemdata=serial, comm_port/comm_serial,
  network=wwan, forced_plmn; `general.main_modem`). We define `defmodems.aw1000`
  in `99-zz`. QModem's AT port isn't stable across boots (first port that
  answers, readdir order: ttyUSB3 or ttyUSB2), so
  `files/etc/hotplug.d/iface/90-lumenwrt-modemdata` moves modemdata to the
  other valid port on `ifup wwan`. ShiranekoWrt's Status-page widget
  `12_modemdata.js` is not upstream (no source) — not included.
- uci-defaults order is alphabetical: `99-lumenwrt` runs **before** QModem's
  `99-qmodem-board`, `99-zz-lumenwrt-modem` after it. qmodem-board only fills
  missing options (`uci_set_missing`), so anything QModem-related we set must
  be in the `99-zz` file. Both LumenWRT scripts exit early on a marker in
  `system.@system[0]` (`lumenwrt_defaults`, `lumenwrt_modem_defaults`) because
  keep-settings sysupgrades re-run uci-defaults.
- QModem's modem interface name = modem-device `alias`, which `modem_scand`
  copies from the matching slot (`qmodem.usb0.alias`) only when it first creates
  the modem section (`4_1` for USB 4-1). Don't pre-create the modem-device
  section: scand then skips setting path/enable_dial/metric. Metric comes from
  slot `default_metric`, else modem_count+10.
- Upstream QModem AW1000 board defaults set `net_led 'ipq::led9'`/`sim_led
  'ipq::led2'` (QSDK names, don't exist on 25.12); the dialer would write junk
  `system.n*` LED sections, so we delete them.
- Board LED rules from `01_leds` (green:5g, green:internet, WAN-port link) are
  removed in `99-zz`; `/etc/init.d/led` (S96) would otherwise override the LED
  script (qmodem_led S79).
- AW1000 LEDs hang off a 74HC164 shift register: each write glitches all
  outputs; re-assert `green:power` after writes. RGB groups: `{red,green,blue}:signal`,
  `{red,green,blue}:5g`.
- To test router-side scripts without changing the device: copy them to
  `/tmp`, stub LED writes, and run uci-defaults against `cp -a /etc/config`
  with `uci() { command uci -c /tmp/x "$@"; }`. Use `-X` when deleting
  anonymous sections in a loop.
- The ttlfw4 init writes `/etc/nftables.d/99-reset-ttl-from-br-lan.nft`, stops
  `qca-nss-ecm` (front ends stop, defunct_all, conntrack flush, rmmod) and
  restarts fw4. It needs `qmodem_ttl.main.ttl` set or the nft rule is invalid.

## Router state before LumenWRT (for reference)

ShiranekoWrt 1.2.2 (qosmio `main-nss` snapshot, kernel 6.12.92, apk), already
OpenWrt UBI layout (kernel/rootfs/rootfs_data) → install with plain sysupgrade.
RAM ~865 MB usable, overlay 209 MB. Modem on USB bus 4-1, QMI RawIP + QMAP
(`wwan0_1`), AT port `/dev/ttyUSB2`, QModem section `4_1`, interface `wwan`.

## Future: xlite (`../xlite-core`)

Deferred by the user. NSS analysis: redirect/tproxy modes terminate locally so
ECM never accelerates them (fine, CPU-bound). tun/mixed mark per packet, so flows
ECM accelerated before xlite connected keep bypassing the tunnel — xlite should
`echo 1 > /sys/kernel/debug/ecm/ecm_db/defunct_all` after installing rules (moot
while TTL keeps ECM stopped). Kernel side is ready (kmod-nft-tproxy, kmod-tun).
QModem's licence forbids commercial use — matters if xlite+LumenWRT is sold.
Packaging (in-image vs post-install via xlite's install.sh) is undecided; don't
put xlite binaries in this public repo.
