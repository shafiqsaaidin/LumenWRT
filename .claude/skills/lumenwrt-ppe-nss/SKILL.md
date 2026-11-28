---
name: lumenwrt-ppe-nss
description: Work on the ppe-nss branch of LumenWRT (openwrt-ppe-nss base, wwand modem stack, PPE/NSS offload) — building it, its moving parts (wwand, TTL/offload switches, RPS hook, LEDs, Wi-Fi), diagnosing the modem and offload on the AW1000, and measuring speed/CPU. Use for anything on branch ppe-nss or when the router runs a ppe-nss LumenWRT image.
---

# LumenWRT ppe-nss line

Read `CLAUDE.md` first (hard rules: never flash unless the user says "flash it"
for that image; only our CI images). Router credentials are in
`CLAUDE.local.md`. Combine with skills `lumenwrt-build` (artifact checks),
`lumenwrt-device` (backup/flash/recovery) and `lumenwrt-packages` (licences).

## What this branch is

| Part | What | Where |
|---|---|---|
| Base | JuliusBairaktaris/openwrt-ppe-nss @ pinned SHA, kernel 6.18 | `config/sources.env` `OPENWRT_*` |
| Feeds | OpenWrt main feeds pinned to commits just before the base SHA, `nss` (nss-firmware only), `wwand` (ddimension/openwrt-repo) | `FEEDS` in sources.env; build.sh refuses unpinned lines |
| Wired offload | PPE via fw4 flowtable (`flow_offloading_hw`) | target's `99-flow-offload` turns it on; our TTL service then decides |
| Wi-Fi | ath11k with `nss-wifi-drv` (NSS data path), `/etc/config/nss-wifi` | 5 GHz ch 36 HE160, 2.4 GHz HE20, country MY |
| Modem | upstream `qmi_wwan` + `rmnet`, managed by **wwand** (GPL-2.0) | autosetup: modem `wwmodem_auto`, interface `wwan0`, L3 `wwand0` |
| LEDs | 5G + signal RGB: wwand AW1000 board profile; Internet/Wi-Fi/Phone: `system.led_*` | `files/etc/uci-defaults/99-lumenwrt`, SMS blink `files/etc/hotplug.d/wwand/50-lumenwrt-sms-led` |
| TTL + offload | `/etc/config/lumenwrt` (`ttl.enabled/value`, `offload.enabled`), `/etc/init.d/lumenwrt-ttl` | TTL on ⇒ offload forced off |
| 5G CPU spread | RPS on `wwand*` to all CPUs except the modem-IRQ CPU | `files/etc/hotplug.d/iface/30-lumenwrt-modem-rps` |

Not in this image: QModem, quectel-CM, modemdata, VoIP (licences), Julius's
`ppe-update` (would pull his images).

## Building

```sh
BUILD_DIR=openwrt-ppe scripts/build.sh prepare   # keep it apart from the main tree
gh workflow run build.yml --ref ppe-nss          # CI, ~80 min
```

Bumping the base: pick a new SHA, re-pin every main feed to its last commit
before that SHA's date (GitHub API `commits?sha=master&until=<date>`), re-pin
the wwand feed, `prepare`, check the AW1000 device profile and wwand's
`board.uc` still have `arcadyan,aw1000`, re-run the licence audit (see below).

Licence audit of the resolved config (must find nothing non-commercial):
parse `openwrt-ppe/tmp/.packageinfo` for `License:` of every
`CONFIG_PACKAGE_*=y`. Known without PKG_LICENSE: nss-firmware, ath11k
firmware, ipq-wifi BDF, adb.

## Router commands (ppe-nss image)

```sh
ubus call wwand status                         # modem state, attach (APN), nr5g, temperature
ubus call wwand modem_signal '{"modem":"wwmodem_auto"}'
ubus call wwand modem_cells  '{"modem":"wwmodem_auto"}'   # dsd (LTE/NSA/SA), serving, neighbours
ubus call wwand modem_at '{"modem":"wwmodem_auto","command":"AT+QCAINFO"}'   # read-only AT
ifstatus wwan0
logread -e wwand | tail                        # datapath, WDA aggregation, mux
```

Useful read-only AT: `AT+QCAINFO` (carrier aggregation), `AT+QENG="servingcell"`,
`AT+QNWPREFCFG="mode_pref"` / `"lte_band"` / `"nsa_nr5g_band"` /
`"nr5g_disable_mode"`. Band locks live in the modem's NVRAM and survive
firmware changes (seen: `lte_band 1:3:7:28` left from ShiranekoWrt).

Config changes to `lumenwrt`: `uci set ...; uci commit lumenwrt; reload_config`
(`uci commit` alone does not apply). Wi-Fi: `uci commit wireless` then
`(sleep 2; wifi reload radio0) &` so the SSH command returns first.

## Known issues / findings (2026-11-28, AW1000)

- **Flow offloading on ⇒ LAN/Wi-Fi traffic over the modem stalls** (hw and
  sw-only flowtable, wwand QMAP and `mux_id 0` alike). Afterwards stale NSS
  rules can hang every new TLS handshake until offloading is off again. Keep
  `lumenwrt.offload.enabled=0`. Open experiment: remove `wwand0` from
  `inet fw4 ft` **right after a fresh boot** and re-test.
- wwand datapath: QMAP v5 over kernel rmnet, DL 32 × 31744 B, UL 11 × 4096 B
  (same aggregation as the old Quectel stack). Changing `network.wwan0.mux_id`
  re-dials (~10-70 s without 5G).
- Speed: Ookla on the homelab 70-117 Mbit/s down, 30-36 up on LTE-A
  (B3+B3+B1). CPU0 carries the USB IRQ + QMAP; with the RPS hook CPU0 load per
  Mbit/s ~-40 %. Single-stream Cloudflare downloads (~3 Mbit/s) are not a
  valid throughput test.
- Country MY: 5 GHz 149-165 are `NO_160MHZ` (ShiranekoWrt used 149/HE160 only
  because it ran country US). HE160 options: 36-64 (DFS upper half) or 100-128.

## Measuring

- Speed: `speedtest --accept-license --accept-gdpr -f json` on the homelab
  (Ookla CLI is installed there; `-s 70827` = CelcomDigi PJ). ~150-200 MB of
  mobile data per run — keep runs few.
- Per-CPU load during a test: sample `/proc/stat` deltas on the router every
  2 s (`top` only shows the total); IRQ placement in `/proc/interrupts`,
  `NET_RX` in `/proc/softirqs`, RPS masks in
  `/sys/class/net/<dev>/queues/rx-*/rps_cpus`.
- Offload state: `uci get firewall.@defaults[0].flow_offloading{,_hw}`,
  `nft list flowtable inet fw4 ft`, `grep -c HW_OFFLOAD /proc/net/nf_conntrack`,
  `cat /sys/kernel/debug/3a000000.ppe/offload` (mount debugfs first).

## Test procedure after flashing

`docs/TESTING-ppe-nss.md`. Run every check from the homelab or this PC; take
the wired homelab as the client for routing tests (its traffic is forwarded).
Restore any setting you change for a test and say so.
