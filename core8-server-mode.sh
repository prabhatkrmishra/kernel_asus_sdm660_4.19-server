#!/system/bin/sh
# core8-server-mode.sh - toggle SDM660 between server (plugged) and battery
# Kernel: msm-4.19 core8server_defconfig (WQ_POWER_EFFICIENT_DEFAULT=n, PM_DEBUG=y)
# Works on LineageOS 16 / Android 16 + KernelSU-Next. Run as root.
# Usage: core8-server-mode.sh [server|battery|auto|status]
#   server  - plugged in, no sleep, no lag (holds wakelock)
#   battery - normal phone power saving
#   auto    - daemon: watch charger, switch automatically (run at boot)
#   status  - show current state
#
# Install (KernelSU boot script, survives OTA):
#   adb push tools/core8-server-mode.sh /data/adb/service.d/core8-server-mode.sh
#   adb shell chmod 755 /data/adb/service.d/core8-server-mode.sh
#   adb shell /data/adb/service.d/core8-server-mode.sh server
#
# Or via init.rc (device/asus/X00TD):
#   on property:sys.boot_completed=1
#       exec u:r:su:s0 root -- /data/adb/service.d/core8-server-mode.sh auto &

WAKELOCK="core8_server"
WLAN_IF="wlan0"

log() { echo "[core8] $*" >&2; }
write() { [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null && log "$1 <- $2" || true; }

is_plugged() {
    # returns 0 if plugged (AC/USB/Wireless)
    for f in /sys/class/power_supply/battery/status /sys/class/power_supply/usb/status /sys/class/power_supply/ac/status; do
        [ -f "$f" ] && grep -qi "charging\|full\|not charging" "$f" 2>/dev/null && return 0
    done
    # fallback: online files
    for f in /sys/class/power_supply/*/online; do
        [ "$(cat "$f" 2>/dev/null)" = "1" ] && return 0
    done
    return 1
}

set_wlan_ps() {
    # $1: on|off  (on = power save enabled, off = disabled for server)
    local state="$1"
    # qcacld-3.0 / prima
    for f in /sys/module/wlan/parameters/fw_power_save /sys/module/qcacld/parameters/power_save; do
        [ -w "$f" ] && write "$f" "$([ "$state" = "off" ] && echo 0 || echo 1)"
    done
    # nl80211 (works on all)
    if command -v iw >/dev/null 2>&1; then
        if [ "$state" = "off" ]; then
            iw dev "$WLAN_IF" set power_save off 2>/dev/null && log "iw $WLAN_IF power_save off"
        else
            iw dev "$WLAN_IF" set power_save on 2>/dev/null && log "iw $WLAN_IF power_save on"
        fi
    fi
}

set_cpu_gov() {
    # $1: performance|schedutil
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        write "$f" "$1"
    done
}

set_cpu_idle() {
    # $1: 0 = disable deep idle (server), 1 = enable (battery)
    local en="$1"
    for f in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        # state0 is WFI (keep), disable state1+ (deep)
        case "$f" in */state0/disable) continue;; esac
        write "$f" "$([ "$en" = "0" ] && echo 1 || echo 0)"
    done
}

mode_server() {
    log "=== SERVER mode (plugged) ==="
    # 1. Hold kernel wakelock - prevents suspend entirely
    echo "$WAKELOCK" > /sys/power/wake_lock 2>/dev/null && log "wakelock $WAKELOCK held"
    # 2. Block autosleep
    write /sys/power/autosleep off
    write /sys/power/wake_lock "$WAKELOCK"
    # 3. WLAN: no power save
    set_wlan_ps off
    # 4. CPU: performance, no deep idle
    set_cpu_gov performance
    set_cpu_idle 0
    # 5. Workqueue: already WQ_POWER_EFFICIENT_DEFAULT=n in kernel, but also runtime
    write /sys/module/workqueue/parameters/power_efficient 0
    # 6. USB autosuspend off (for USB-Ethernet)
    write /sys/module/usbcore/parameters/autosuspend -1
    for f in /sys/bus/usb/devices/*/power/autosuspend_delay_ms; do write "$f" -1; done
    for f in /sys/bus/usb/devices/*/power/control; do write "$f" on; done
    # 7. Android Doze: disable while in server mode
    dumpsys deviceidle disable 2>/dev/null && log "deviceidle disabled"
    settings put global wifi_sleep_policy 2 2>/dev/null
    svc power stayon true 2>/dev/null
    log "server mode active - will NOT sleep, expect higher temp/battery drain"
}

mode_battery() {
    log "=== BATTERY mode ==="
    # 1. Release wakelock
    echo "$WAKELOCK" > /sys/power/wake_unlock 2>/dev/null && log "wakelock $WAKELOCK released"
    write /sys/power/autosleep mem 2>/dev/null || write /sys/power/autosleep off
    # 2. WLAN: power save on
    set_wlan_ps on
    # 3. CPU: schedutil, deep idle on
    set_cpu_gov schedutil
    set_cpu_idle 1
    write /sys/module/workqueue/parameters/power_efficient 1
    # 4. USB autosuspend on
    write /sys/module/usbcore/parameters/autosuspend 2
    for f in /sys/bus/usb/devices/*/power/control; do write "$f" auto; done
    # 5. Android Doze: re-enable
    dumpsys deviceidle enable 2>/dev/null && log "deviceidle enabled"
    svc power stayon false 2>/dev/null
    log "battery mode active - normal suspend"
}

mode_status() {
    echo "--- core8 status ---"
    echo "wakelock: $(cat /proc/wakelocks 2>/dev/null | grep -q "$WAKELOCK" && echo "held ($WAKELOCK)" || echo "released")"
    echo "autosleep: $(cat /sys/power/autosleep 2>/dev/null || echo n/a)"
    echo "wlan ps: $(iw dev "$WLAN_IF" get power_save 2>&1 | head -n1)"
    echo "gov: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
    echo "wq_power_efficient: $(cat /sys/module/workqueue/parameters/power_efficient 2>/dev/null)"
    echo "plugged: $(is_plugged && echo yes || echo no)"
    echo "deviceidle: $(dumpsys deviceidle get deep 2>&1 | head -n1)"
}

mode_auto() {
    log "auto daemon started (poll 10s)"
    # apply initial
    is_plugged && mode_server || mode_battery
    while true; do
        sleep 10
        if is_plugged; then
            grep -q "$WAKELOCK" /proc/wakelocks 2>/dev/null || mode_server
        else
            grep -q "$WAKELOCK" /proc/wakelocks 2>/dev/null && mode_battery || true
        fi
    done
}

case "$1" in
    server)  mode_server ;;
    battery) mode_battery ;;
    auto)    mode_auto ;;
    status)  mode_status ;;
    *) echo "Usage: $0 [server|battery|auto|status]"; mode_status; exit 1 ;;
esac
