#!/bin/sh
# LumenWRT: front-panel LED controller for the Arcadyan AW1000.
# Started by /etc/init.d/qmodem_led (qmodem_led "modem_status" section with
# script 'lumenwrt_aw1000'):   lumenwrt_aw1000.sh <modem_cfg> [off]
#
# Indications
#   Power     always on
#   Signal    (RGB) white = booting / SIM initialising, yellow blink = SIM ready,
#             registering; then by signal: green >= -95 dBm, blue -110..-95,
#             red < -110 (RSRP estimated from AT+CSQ). Red = no SIM.
#   5G        (RGB) white = 5G SA, green = 5G NSA, blue = LTE, red = 3G or no SIM,
#             yellow blink = registering
#   Internet  on + blinking on traffic when the modem link reaches the internet
#   Wi-Fi     solid = 2.4 + 5 GHz up, fast blink = 5 GHz only,
#             slow blink = 2.4 GHz only, off = no Wi-Fi
#   Phone     on; blinks ~30 s when a new SMS arrives
#
# The LEDs sit on a 74HC164 shift register: every write glitches all outputs
# briefly, so the power LED is re-asserted after each batch of writes.

. /usr/share/qmodem/modem_util.sh
. /usr/share/qmodem/led_scripts/connectivity.sh
. /lib/functions.sh
. /usr/share/libubox/jshn.sh

LED_POWER="green:power"
LED_WIFI="green:wifi"
LED_INTERNET="green:internet"
LED_PHONE="green:phone"
SIG_R="red:signal";  SIG_G="green:signal"; SIG_B="blue:signal"
NET_R="red:5g";      NET_G="green:5g";     NET_B="blue:5g"

MODEM_CFG="$1"
ON_OFF="$2"

SMS_BLINK_LOOPS=6          # ~30 s at the 5 s connected poll interval
STABLE_READS=2             # consecutive identical SIM reads before acting

# ---------------------------------------------------------------- helpers

led_path() { echo "/sys/class/leds/$1"; }

led_set() {                # led_set <name> 0|1
	local p; p="$(led_path "$1")"
	[ -d "$p" ] || return 0
	echo none > "$p/trigger" 2>/dev/null
	if [ "$2" = 1 ]; then cat "$p/max_brightness" > "$p/brightness" 2>/dev/null
	else echo 0 > "$p/brightness" 2>/dev/null; fi
}

led_blink() {              # led_blink <name> <on_ms> <off_ms>
	local p; p="$(led_path "$1")"
	[ -d "$p" ] || return 0
	[ "$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$p/trigger")" = timer ] || echo timer > "$p/trigger" 2>/dev/null
	echo "$2" > "$p/delay_on" 2>/dev/null
	echo "$3" > "$p/delay_off" 2>/dev/null
}

power_on() { led_set "$LED_POWER" 1; }

rgb() {                    # rgb <r-led> <g-led> <b-led> <r> <g> <b>
	led_set "$1" "$4"; led_set "$2" "$5"; led_set "$3" "$6"
}
signal_rgb() { rgb "$SIG_R" "$SIG_G" "$SIG_B" "$1" "$2" "$3"; }
net_rgb()    { rgb "$NET_R" "$NET_G" "$NET_B" "$1" "$2" "$3"; }

# ---------------------------------------------------------------- modem

load_cfg() {
	config_load qmodem
	config_get AT_PORT "$MODEM_CFG" at_port
	config_get ALIAS "$MODEM_CFG" alias
	config_get USE_UBUS "$MODEM_CFG" use_ubus 1
	[ -n "$AT_PORT" ] || AT_PORT=/dev/ttyUSB2
	use_ubus_flag=""
	[ "$USE_UBUS" = 1 ] && use_ubus_flag="-u"
}

load_netdev() {
	local iface="$MODEM_CFG"
	[ -n "$ALIAS" ] && [ "$ALIAS" != "-" ] && iface="$ALIAS"
	NET_DEV=""
	config_load network
	config_get NET_DEV "$iface" device
	[ -n "$NET_DEV" ] || config_get NET_DEV "$iface" ifname
}

sim_state() {              # prints: ready | locked | absent | (empty = no answer)
	local r; r="$(at "$AT_PORT" 'AT+CPIN?' 2>/dev/null)"
	[ -n "$r" ] || return 0
	case "$r" in
		*"CPIN: READY"*) echo ready ;;
		*"CPIN:"*)       echo locked ;;
		*)               echo absent ;;
	esac
}

rat() {                    # prints: 5G-SA | 5G-NSA | 4G | 3G | NONE
	local r code
	r="$(at "$AT_PORT" 'AT+QENG="servingcell"' 2>/dev/null)"
	case "$r" in
		*ERROR*|"") ;;
		*NR5G-SA*)  echo 5G-SA;  return ;;
		*NR5G-NSA*) echo 5G-NSA; return ;;
		*'"LTE"'*)  echo 4G;     return ;;
		*WCDMA*|*UMTS*|*HSPA*) echo 3G; return ;;
	esac
	code="$(at "$AT_PORT" 'AT+COPS?' 2>/dev/null | sed -n 's/.*+COPS:[^,]*,[^,]*,[^,]*,\([0-9]*\).*/\1/p' | head -n1)"
	case "$code" in
		[0-6]) echo 3G ;;
		7|8|9|1[0-9]) echo 4G ;;
		*) echo NONE ;;
	esac
}

signal_level() {           # prints 2 (good) | 1 (medium) | 0 (poor)
	local rssi rsrp
	rssi="$(at "$AT_PORT" 'AT+CSQ' 2>/dev/null | sed -n 's/.*+CSQ: *\([0-9]*\),.*/\1/p' | head -n1)"
	case "$rssi" in ''|99|*[!0-9]*) echo 0; return ;; esac
	rsrp=$(( -140 + rssi * 2 ))
	if   [ "$rsrp" -ge -95 ];  then echo 2
	elif [ "$rsrp" -ge -110 ]; then echo 1
	else echo 0; fi
}

# ---------------------------------------------------------------- indicators

show_status() {            # show_status <rat> <level>
	case "$1" in
		5G-SA)  net_rgb 1 1 1 ;;
		5G-NSA) net_rgb 0 1 0 ;;
		4G)     net_rgb 0 0 1 ;;
		3G)     net_rgb 1 0 0 ;;
		*)      net_rgb 0 0 0 ;;
	esac
	case "$2" in
		2) signal_rgb 0 1 0 ;;
		1) signal_rgb 0 0 1 ;;
		*) signal_rgb 1 0 0 ;;
	esac
	power_on
}

internet_led() {
	local p; p="$(led_path "$LED_INTERNET")"
	[ -d "$p" ] || return 0
	if [ "$PHASE" = connected ] && [ -n "$NET_DEV" ] && qmodem_connectivity_probe 3; then
		if [ "$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$p/trigger")" != netdev ] || \
		   [ "$(cat "$p/device_name" 2>/dev/null)" != "$NET_DEV" ]; then
			echo netdev > "$p/trigger" 2>/dev/null
			echo "$NET_DEV" > "$p/device_name" 2>/dev/null
			echo 1 > "$p/link" 2>/dev/null
			echo 1 > "$p/tx" 2>/dev/null
			echo 1 > "$p/rx" 2>/dev/null
		fi
	else
		led_set "$LED_INTERNET" 0
	fi
}

wifi_led() {
	local status radios r band up has2=0 has5=0 state
	status="$(ubus call network.wireless status 2>/dev/null)"
	if [ -n "$status" ] && json_load "$status" 2>/dev/null; then
		json_get_keys radios
		for r in $radios; do
			json_select "$r" || continue
			up=0; band=""
			json_get_var up up
			if json_select config; then
				json_get_var band band
				json_select ..
			fi
			json_select ..
			[ "$up" = 1 ] || continue
			case "$band" in 2g) has2=1 ;; 5g|6g) has5=1 ;; esac
		done
	fi
	state="$has2$has5"
	[ "$state" = "$LAST_WIFI" ] && return 0
	LAST_WIFI="$state"
	case "$state" in
		11) led_set "$LED_WIFI" 1 ;;
		01) led_blink "$LED_WIFI" 500 500 ;;
		10) led_blink "$LED_WIFI" 1000 1000 ;;
		*)  led_set "$LED_WIFI" 0 ;;
	esac
	power_on
}

phone_led() {
	local count
	count="$(at "$AT_PORT" 'AT+CPMS?' 2>/dev/null | sed -n 's/.*+CPMS: *"[^"]*", *\([0-9]*\),.*/\1/p' | head -n1)"
	if [ -n "$count" ]; then
		if [ -z "$SMS_BASE" ]; then
			SMS_BASE="$count"
		elif [ "$count" -gt "$SMS_BASE" ]; then
			SMS_BLINK=$SMS_BLINK_LOOPS
			SMS_BASE="$count"
		elif [ "$count" -lt "$SMS_BASE" ]; then
			SMS_BASE="$count"
		fi
	fi
	if [ "${SMS_BLINK:-0}" -gt 0 ]; then
		SMS_BLINK=$((SMS_BLINK - 1))
		led_blink "$LED_PHONE" 1000 1000
		PHONE_ON=""
	elif [ -z "$PHONE_ON" ]; then
		led_set "$LED_PHONE" 1
		PHONE_ON=1
		power_on
	fi
}

# ---------------------------------------------------------------- main

all_off() {
	signal_rgb 0 0 0; net_rgb 0 0 0
	led_set "$LED_WIFI" 0; led_set "$LED_PHONE" 0; led_set "$LED_INTERNET" 0
}

[ -n "$MODEM_CFG" ] || { logger -t lumenwrt_led "no modem section given"; exit 1; }
load_cfg

if [ "$ON_OFF" = off ]; then
	all_off
	led_set "$LED_POWER" 0
	exit 0
fi

PHASE=booting              # booting | sim_wait | registering | connected
LAST=""; LAST_SIM=""; STABLE=0; LOOP=0; LAST_WIFI=""; SMS_BASE=""; SMS_BLINK=0; PHONE_ON=""

all_off
signal_rgb 1 1 1           # white: alive, booting
power_on

while true; do
	LOOP=$((LOOP + 1))
	load_netdev
	sim="$(sim_state)"

	if [ "$sim" = "$LAST_SIM" ]; then STABLE=$((STABLE + 1)); else STABLE=1; LAST_SIM="$sim"; fi

	if [ -z "$sim" ] || [ "$sim" = locked ] || [ "$STABLE" -lt "$STABLE_READS" ]; then
		# No AT answer yet, SIM initialising, or not stable: boot indication
		if [ "$PHASE" != connected ]; then
			[ "$sim" = locked ] && PHASE=sim_wait
			net_rgb 0 0 0; signal_rgb 1 1 1; power_on
		fi
	elif [ "$sim" = absent ]; then
		[ "$PHASE" = connected ] || PHASE=booting
		if [ "$LAST" != nosim ]; then
			LAST=nosim
			net_rgb 1 0 0; signal_rgb 1 0 0; power_on
		fi
	else
		r="$(rat)"
		if [ "$r" = NONE ]; then
			if [ "$PHASE" != connected ]; then
				PHASE=registering
				if [ $((LOOP % 2)) -eq 0 ]; then net_rgb 1 1 0; signal_rgb 1 1 0
				else net_rgb 0 0 0; signal_rgb 0 0 0; fi
				power_on
			fi
		else
			PHASE=connected
			lvl="$(signal_level)"
			if [ "$LAST" != "${r}_${lvl}" ]; then
				LAST="${r}_${lvl}"
				show_status "$r" "$lvl"
			fi
		fi
	fi

	internet_led
	wifi_led
	phone_led

	if [ "$PHASE" = connected ]; then sleep 5; else sleep 2; fi
done
