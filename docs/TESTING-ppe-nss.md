# Testing the ppe-nss branch on the AW1000

The `ppe-nss` image has never run on hardware. Test it only with a way back.

## Before flashing

- [ ] **Wired access**: a PC or the homelab on a LAN port (Wi-Fi may not come up).
- [ ] **Known-good image** on that machine: the latest `main` build's
      `*-squashfs-sysupgrade.bin` and its sha256.
- [ ] **Config backup**: `sysupgrade -b /tmp/backup.tar.gz`, copied off the router.
- [ ] Optional but recommended: serial (115200 8N1, 3.3 V) + U-Boot TFTP, practised
      first. Needed only if the image does not boot at all.
- [ ] Image is from this repo's CI (Actions → `ppe-nss` run), sha256 checked.

## Flash

Clean, **without keeping settings** (configs from the 25.12/QModem line don't carry over):

```sh
sysupgrade -T /tmp/fw.bin      # image check, no write
sysupgrade -n -v /tmp/fw.bin   # -n = erase config
```

Expect 2–4 minutes. Then: Wi-Fi `LumenWRT` / `LumenWRT_5G`, key `lumenwrt`, or a LAN
cable; LuCI at https://192.168.1.1 asks for a root password.

## Checks (on the router)

```sh
grep DESCRIPTION /etc/openwrt_release                # LumenWRT ... 0514ded08c
iwinfo | grep -E 'ESSID|Channel'                     # both radios up, country MY
logread -e nss-wifi | tail -3                        # "bring-up survived"
ubus call wwand status                               # modem, registration, signal
ifstatus wwan0 | jsonfilter -e '@.up' -e '@["ipv4-address"][0].address'
ping -c3 1.1.1.1
uci show lumenwrt; nft list chain inet fw4 lumenwrt_ttl   # TTL 64 on wwand*
uci get firewall.@defaults[0].flow_offloading_hw     # 0 while TTL is on
for l in /sys/class/leds/*; do echo "$(basename $l)=$(cat $l/brightness)"; done
```

- [ ] Boot time under ~4 min
- [ ] Both Wi-Fi bands up, clients can join
- [ ] 5G connects (wwand autosetup picked the APN), internet works
- [ ] LEDs: power on; 5G/signal colours from wwand; Internet blinks with traffic; Wi-Fi on
- [ ] LuCI: Modem pages (luci-app-wwand) show signal, SMS inbox works, send an SMS
- [ ] Phone LED blinks ~30 s on an incoming SMS
- [ ] TTL off → offload on: `uci set lumenwrt.ttl.enabled=0; uci commit lumenwrt; reload_config`, then
      during a download `grep -c HW_OFFLOAD /proc/net/nf_conntrack` > 0
- [ ] Speed test with TTL on and off, `top` on the router (CPU load)
- [ ] Reboot once more: everything comes back on its own

## If it goes wrong

- Router answers on a LAN cable but something is broken: `sysupgrade -n -v` the
  known-good `main` image from the wired machine.
- Router does not boot: serial + U-Boot TFTP with the known-good image (or the
  `*-initramfs-uImage.itb`, then sysupgrade from it).
