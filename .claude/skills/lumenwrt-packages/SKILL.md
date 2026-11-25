---
name: lumenwrt-packages
description: Change what goes into LumenWRT — add/remove packages, add third-party package repos, change first-boot defaults, bump pinned sources (qosmio fork, QModem, modemdata, Aurora, netstat), and judge NSS compatibility of new features (e.g. xlite, VPNs, TTL). Use when editing config/lumenwrt.seed, config/sources.env, files/, or evaluating a package for this firmware.
---

# Changing LumenWRT contents

After any change: `scripts/build.sh prepare` (must end "Config OK"), commit,
push, then build (skill `lumenwrt-build`). Update `CLAUDE.md` decisions if the
change is a decision, and README if user-visible.

## Adding a package

1. Find it: `cd openwrt && ./scripts/feeds search <name>`; check
   `CONFIG_PACKAGE_<name>` exists in `tmp/.config-package.in`.
2. Add `CONFIG_PACKAGE_<name>=y` to the right section of `config/lumenwrt.seed`.
   To force something off, add `# CONFIG_PACKAGE_<name> is not set` (enforced).
3. **Kernel modules must be in the seed** — upstream kmods won't install on
   this NSS kernel. Think about what kmods a feature needs at runtime
   (e.g. xlite tproxy → `kmod-nft-tproxy`).
4. Choices inside packages (Kconfig `choice`) are set by their symbol, e.g.
   `CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_nss-qmi-wwan=y`. These choice
   symbols are active even when the owning package (luci-app-qmodem) isn't selected.

## Adding a third-party repo

- Review it first: who maintains it, what it executes (rpcd ACLs, exec'd
  commands, external URLs it contacts), licence. Note findings in sources.env.
- Pin it in `config/sources.env` (`<NAME>_REPO`, `<NAME>_REF` = full SHA, date comment).
- Package Makefile at repo root → clone via `pin_repo` into
  `openwrt/package/lumenwrt/<pkg>` in `scripts/build.sh` (like Aurora, netstat).
- Packages in subdirectories → add a feed line in build.sh's feeds block:
  `src-git <name> ${URL}^${REF}` and `# CONFIG_FEED_<name> is not set` in the seed.
- Never commit proprietary binaries (e.g. xlite) — the repo and releases are public.

## First-boot defaults

- `files/etc/uci-defaults/99-lumenwrt` — runs once on a fresh config (uci batch).
  Wireless already exists when it runs, but prefer board.d for Wi-Fi.
- `files/etc/board.d/99-lumenwrt` — merged into /etc/board.json before
  wireless/network are generated: `ucidef_set_country`, `ucidef_set_wireless
  <band> <ssid> <enc> <key>` (SSID default ⇒ iface enabled).
- Keep scripts executable (`chmod +x`; git keeps the mode). Check with `sh -n`.
- Defaults don't apply on sysupgrade with kept settings.

## Bumping pinned sources

1. Look at upstream first (GitHub API): new commits/tags, what changed, open
   issues. qosmio branches: `24.10-nss`, `25.12-nss`, `main-nss`. QModem: `main`
   (rc tags `vX.Y.Z_rcN`) and `stable` (`vX.Y.Z`); VoIP/SIP needs ≥ 3.4.
2. Edit the SHA in `config/sources.env`, `prepare`, fix any dropped symbols.
3. Re-check things this project depends on: AW1000 device profile in
   `target/linux/qualcommax/image/ipq807x.mk`, NSS FW default (11.4 needed for
   rmnet), QModem `driver/nss/*` still present, ttlfw4 init behaviour.
4. Build, verify artifact, flash only with the user's OK (skill `lumenwrt-device`).

## NSS compatibility checklist (for any new networking feature)

NSS ECM accelerates **forwarded** flows between NSS-known interfaces; accelerated
packets skip netfilter after the first few packets. So ask:

- Does it rely on per-packet netfilter (marks, TTL/mangle, TPROXY, counters, QoS)?
  → accelerated flows escape it. Either the feature stops ECM (QModem TTL does),
  or flush ECM after installing rules (`echo 1 > /sys/kernel/debug/ecm/ecm_db/defunct_all`).
- Does traffic terminate on the router (proxies, VPN servers, redirect/tproxy)?
  → never accelerated, CPU-bound, but correct.
- Does it use tun/wg/other non-NSS netdevs? → ECM won't accelerate flows through
  them (correct, CPU-bound).
- Fw4 flow offloading and packet steering must stay off with NSS.
- Bridge VLAN filtering (`config bridge-vlan`) breaks NSS Wi-Fi offload — use
  plain bridges/VLAN devices.
