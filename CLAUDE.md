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
- Read-only on the router unless asked. Back up (`sysupgrade -b`) before any change.
- Sources are pinned by commit in `config/sources.env`. Never build from moving
  branches; bump deliberately (see skill `lumenwrt-packages`).
- Don't invent default passwords/keys beyond the documented ones. The repo is public.

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
| Builds | GitHub Actions (public repo, 4-core runners), ~65 min | user choice; local build also works |

## Layout

- `config/sources.env` — pinned repos/SHAs (OpenWrt fork, QModem, modemdata, Aurora, netstat)
- `config/lumenwrt.seed` — diffconfig. `=y` lines must survive defconfig and
  `# ... is not set` lines must stay off; `scripts/build.sh` enforces both
- `files/` — rootfs overlay: `etc/board.d/99-lumenwrt` (Wi-Fi defaults),
  `etc/uci-defaults/99-lumenwrt` (hostname, TZ, NSS offload off, Aurora, TTL),
  `etc/uci-defaults/99-zz-lumenwrt-modem` (WAN interfaces, QModem slot, LED setup),
  `usr/share/qmodem/led_scripts/lumenwrt_aw1000.sh` (LED controller),
  `etc/firewall.d/qmodem_ttl` (no-op the ttlfw4 init calls), `etc/banner`
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
