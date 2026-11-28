---
name: lumenwrt-device
description: Work on the real Arcadyan AW1000 router — reaching it, read-only inspection, backup, flashing a LumenWRT sysupgrade image, post-flash checks and recovery. Use before running anything on the router, flashing, or diagnosing the modem/NSS/Wi-Fi/TTL on the device.
---

# The AW1000 router

Credentials are in `CLAUDE.local.md` (git-ignored). If a login fails, ask; don't guess.

## Hard rules

- **It is this PC's internet uplink** (PC on its Wi-Fi, default route 192.168.1.1).
  Reboot / flash / Wi-Fi or WAN changes take this PC and the session offline.
  Get the user's explicit OK for that specific step, warn them first, and give
  them the steps to finish on their own (rejoin Wi-Fi, check things) since you
  may not come back until they reconnect.
- **Only flash LumenWRT images built by this repo's CI and verified with the
  `lumenwrt-build` skill** — never a third-party prebuilt image. Ask "flash
  <image>?" and wait for an explicit yes every time; offers of help or tools
  are not a yes.
- Read-only by default. Back up before any change; say what you changed after.
- Never paste credentials, IMEI/IMSI/ICCID, phone numbers or SMS content into
  commits, issues or anything public.

## Access and facts

- SSH: `sshpass -p "$PW" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.1.1 '<cmd>'`
- qualcommax/ipq807x, aarch64_cortex-a53, ~865 MB RAM, UBI volumes kernel/rootfs/rootfs_data.
- Modem: Quectel RG500Q-EA, USB 2c7c:0800 on bus 4-1 at 5 Gbps. QMI RawIP + QMAP
  → `wwan0` / `wwan0_1`. AT ports `/dev/ttyUSB2` (QModem uses it) and `ttyUSB3`.
- Package manager is **apk** (25.12). `kmod-*` from upstream feeds won't install.

## Read-only health check

```sh
cat /etc/openwrt_release; ubus call system board
cat /sys/kernel/debug/usb/devices | grep -A8 'ProdID=0800' | grep Driver   # qmi_wwan_q on If#4
lsmod | grep -E 'qca_nss|ecm|rmnet_nss|qmi_wwan'
ip -br addr; ip route
cat /sys/kernel/debug/ecm/ecm_db/connection_count_simple 2>/dev/null       # absent = ECM unloaded
uci show qmodem_ttl; ls /etc/nftables.d/; nft list ruleset | grep -E 'ttl|hoplimit'
uci show wireless | grep -E '\.(country|ssid|disabled|encryption)='
uci get luci.main.mediaurlbase
uci show network | grep -E '^network\.(wan|wwan)\.'; uci show qmodem_led
ps w | grep led_scripts | grep -v grep
for l in /sys/class/leds/*; do echo "$(basename $l): $(cat $l/brightness) [$(sed -n 's/.*\[\(.*\)\].*/\1/p' $l/trigger)]"; done
```

Expected on LumenWRT defaults: TTL enabled → `99-reset-ttl-from-br-lan.nft`
present, `ecm` module NOT loaded (that's by design while TTL is on); radios up
with country MY; theme `/luci-static/aurora`; `wwan` (metric 11) + `wan`
(defaultroute 0); `lumenwrt_aw1000.sh 4_1` running; LED colours per README
(e.g. LTE + medium signal = blue 5G + blue signal).

## Flashing (only with explicit OK)

1. Backup to the repo's git-ignored `backup/`:
   `ssh ... 'sysupgrade -b /tmp/backup.tar.gz'` then
   `ssh ... 'cat /tmp/backup.tar.gz' > backup/<date>-backup.tar.gz`; also
   `/etc/qmodem/sms.sqlite3` if the user wants SMS history.
2. Copy the image (no scp on dropbear needed): `ssh ... 'cat > /tmp/fw.bin' < image.bin`,
   then compare `sha256sum /tmp/fw.bin` with the artifact's `sha256sums`.
3. Test: `sysupgrade -T /tmp/fw.bin` (no flash). Must pass.
4. Flash clean: `sysupgrade -n -v /tmp/fw.bin` (keep-settings is wrong when
   coming from another firmware or changing QModem major config). Connection drops now.
5. User rejoins Wi-Fi `LumenWRT_5G` / key `lumenwrt` (or LAN cable), opens
   https://192.168.1.1, sets a root password, re-enters APN in QModem if needed.
   Remind them to change the Wi-Fi key.

## Post-flash checks

Run the health check above, plus: QModem shows the modem and an IP on `wwan`;
`logread | grep -iE 'qmodem|ttl|ecm|ath11k' | tail -50`; a speed test from a LAN
client with `top` running on the router (CPU load tells you whether NSS is doing
the work — with TTL on, routing is on the CPU by design).

## Recovery

- Bad config: failsafe (press reset during boot when LED blinks) → 192.168.1.1 telnet/ssh.
- Bad image: boot `*-initramfs-uImage.itb` from U-Boot via TFTP (normally needs
  UART on the AW1000), then sysupgrade a good image.
