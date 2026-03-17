#!/usr/bin/sh
# IC Cluster container entrypoint.
#
# Option B2: UnifiedCompositor runs on the HOST as a native service.
# It connects to Weston (wayland-1) and creates wayland-2.
# IC apps in this container connect directly to wayland-2.
#
# Each app is wrapped in a restart_app watchdog: if an individual app crashes
# it is restarted independently without tearing down the whole container.

WAYLAND_SOCKET="${XDG_RUNTIME_DIR}/wayland-2"
SOCKET_TIMEOUT=20

# Poll for wayland-2 socket — created by host UnifiedCompositor service
echo "[IC] Waiting for wayland-2 socket (UnifiedCompositor on host)..."
i=0
while [ ! -S "$WAYLAND_SOCKET" ]; do
    sleep 0.5
    i=$((i + 1))
    if [ $i -ge $((SOCKET_TIMEOUT * 2)) ]; then
        echo "[IC] ERROR: wayland-2 not ready after ${SOCKET_TIMEOUT}s"
        exit 1
    fi
done

echo "[IC] wayland-2 ready. Starting IC apps..."

# IC apps connect to wayland-2 (UnifiedCompositor)
export WAYLAND_DISPLAY=wayland-2

# restart_app <label> <binary> [VAR=VALUE ...]
# Loops forever: starts the app in a subshell with exported env vars,
# waits for it to exit, then restarts after 2s.
# Does not require 'env' — uses only POSIX sh built-ins.
restart_app() {
    label="$1"
    binary="$2"
    shift 2
    while true; do
        echo "[IC] Starting $label..."
        (
            for kv in "$@"; do export "$kv"; done
            exec "$binary"
        ) &
        app_pid=$!
        wait $app_pid
        exit_code=$?
        echo "[IC] $label exited (code $exit_code). Restarting in 2s..."
        sleep 2
    done
}

restart_app GearState /usr/bin/GearState_app \
    VSOMEIP_CONFIGURATION=/etc/vsomeip/vsomeip_gearstate.json \
    VSOMEIP_APPLICATION_NAME=GearState \
    COMMONAPI_CONFIG=/etc/commonapi/commonapi_gearstate.ini &

restart_app Speedometer /usr/bin/Speedometer_app \
    VSOMEIP_CONFIGURATION=/etc/vsomeip/vsomeip_speedometer.json \
    VSOMEIP_APPLICATION_NAME=Speedometer \
    COMMONAPI_CONFIG=/etc/commonapi/commonapi_speedometer.ini &

restart_app BatteryMeter /usr/bin/BatteryMeter_app \
    VSOMEIP_CONFIGURATION=/etc/vsomeip/vsomeip_batterymeter.json \
    VSOMEIP_APPLICATION_NAME=BatteryMeter \
    COMMONAPI_CONFIG=/etc/commonapi/commonapi_batterymeter.ini &

echo "[IC] All IC watchdogs started. Waiting..."
wait
echo "[IC] All watchdogs exited — tearing down IC cluster."
