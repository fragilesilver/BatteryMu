#!/bin/sh
# HELP: Live battery voltage, current and charge monitor for the RG35XX family
# ICON: batterymu
# GRID: BatteryMu

. /opt/muos/script/var/func.sh

APP_NAME="BatteryMu"

# ---------------------------------------------------------------------------
# App directory: Andromeda bind-mounts "application" from SD1/SD2, so prefer
# $MUOS_SHARE_DIR; fall back to the store, then the legacy rom-mount path
# (keeps this launcher working on Jacaranda too).
# ---------------------------------------------------------------------------
APP_SUBPATH="application/$APP_NAME"
APP_DIR="$MUOS_SHARE_DIR/$APP_SUBPATH"
[ -d "$APP_DIR" ] || APP_DIR="$MUOS_STORE_DIR/$APP_SUBPATH"
[ -d "$APP_DIR" ] || APP_DIR="$(GET_VAR "device" "storage/rom/mount")/MUOS/$APP_SUBPATH"

BIN_DIR="$APP_DIR/bin"
LOVE_BIN="$BIN_DIR/love"
LOG_FILE="$APP_DIR/batterymu.log"

# Persistent, always-writable store for the theme + usage tracking. Written
# from Lua with plain io (see main.lua) so persistence never depends on LÖVE's
# save-dir resolution or bind-mount behaviour.
DATA_DIR="$APP_DIR/save"
mkdir -p "$DATA_DIR"
export BATTERYMU_DATA="$DATA_DIR"

# ---------------------------------------------------------------------------
# Battery source (Andromeda-native, all-variant safe). Every RG35XX is
# Allwinner H700 / AXP2202 with identical sysfs paths, but resolve via the
# per-device muOS vars so this also works on any other muOS device.
# ---------------------------------------------------------------------------
BAT_VOLT_NODE="$(GET_VAR "device" "battery/voltage" 2>/dev/null)"
if [ -n "$BAT_VOLT_NODE" ]; then
    # strip "voltage_now" -> sysfs base dir
    export BATTERYMU_BASE="${BAT_VOLT_NODE%/*}/"
fi
[ -f "$MUOS_RUN_DIR/battery/capacity" ] && export BATTERYMU_CAP_NODE="$MUOS_RUN_DIR/battery/capacity"
[ -f "$MUOS_RUN_DIR/battery/charging" ] && export BATTERYMU_CHG_NODE="$MUOS_RUN_DIR/battery/charging"
[ -d "$MUOS_RUN_DIR/battery_usage"    ] && export BATTERYMU_USAGE_DIR="$MUOS_RUN_DIR/battery_usage"
BV_MIN="$(GET_VAR "device" "battery/volt_min" 2>/dev/null)"
BV_MAX="$(GET_VAR "device" "battery/volt_max" 2>/dev/null)"
[ -n "$BV_MIN" ] && export BATTERYMU_VMIN="$BV_MIN"
[ -n "$BV_MAX" ] && export BATTERYMU_VMAX="$BV_MAX"

# Render target: internal 640x480, or 1280x720 on HDMI. LÖVE letterboxes it.
SCREEN_W="$(GET_VAR device mux/width)"
SCREEN_H="$(GET_VAR device mux/height)"
SCREEN_RES="${SCREEN_W:-640}x${SCREEN_H:-480}"

CAFFEINE="$(command -v CAFFEINE 2>/dev/null || true)"
trap '[ -n "$CAFFEINE" ] && "$CAFFEINE" off' EXIT INT TERM HUP

SET_ENV() {
    export HOME="$APP_DIR"
    export XDG_DATA_HOME="$APP_DIR/.local/share"
    export XDG_CONFIG_HOME="$APP_DIR/.local/config"
    export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
    export LD_LIBRARY_PATH="$BIN_DIR/libs.aarch64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}

command -v STOP_MUSIC >/dev/null 2>&1 && STOP_MUSIC
killall -q playbgm.sh mpg123 2>/dev/null || true

echo app >/tmp/act_go

chmod +x "$LOVE_BIN" 2>/dev/null || true
cd "$APP_DIR" || exit 1

SET_ENV
[ -n "$CAFFEINE" ] && "$CAFFEINE" on
SET_VAR "system" "foreground_process" "love"
"$LOVE_BIN" . "$SCREEN_RES" >"$LOG_FILE" 2>&1
