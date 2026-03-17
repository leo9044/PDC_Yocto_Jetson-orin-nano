#!/usr/bin/sh
# HU Cluster container entrypoint.
#
# Option B2: UnifiedCompositor runs on the HOST as a native service.
# It connects to Weston (wayland-1) and creates wayland-2.
# HU apps in this container connect directly to wayland-2.
#
# Each app is wrapped in a restart_app watchdog: if an individual app crashes
# it is restarted independently without tearing down the whole container.

WAYLAND_SOCKET="${XDG_RUNTIME_DIR}/wayland-2"
SOCKET_TIMEOUT=20

# Poll for wayland-2 socket — created by host UnifiedCompositor service
echo "[HU] Waiting for wayland-2 socket (UnifiedCompositor on host)..."
i=0
while [ ! -S "$WAYLAND_SOCKET" ]; do
    sleep 0.5
    i=$((i + 1))
    if [ $i -ge $((SOCKET_TIMEOUT * 2)) ]; then
        echo "[HU] ERROR: wayland-2 not ready after ${SOCKET_TIMEOUT}s"
        exit 1
    fi
done

echo "[HU] wayland-2 ready. Starting HU apps..."

# HU apps connect to wayland-2 (UnifiedCompositor)
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
        echo "[HU] Starting $label..."
        (
            for kv in "$@"; do export "$kv"; done
            exec "$binary"
        ) &
        app_pid=$!
        wait $app_pid
        exit_code=$?
        echo "[HU] $label exited (code $exit_code). Restarting in 2s..."
        sleep 2
    done
}

restart_app GearApp /usr/bin/GearApp \
    VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_gearapp.json \
    VSOMEIP_APPLICATION_NAME=GearApp \
    COMMONAPI_CONFIG=/etc/commonapi/commonapi_gearapp.ini &

restart_app MediaApp /usr/bin/MediaApp \
    VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_mediaapp.json \
    VSOMEIP_APPLICATION_NAME=MediaApp \
    COMMONAPI_CONFIG=/etc/commonapi/commonapi_mediaapp.ini &

restart_app AmbientApp /usr/bin/AmbientApp \
    VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_ambientapp.json \
    VSOMEIP_APPLICATION_NAME=AmbientApp \
    COMMONAPI_CONFIG=/etc/commonapi/commonapi_ambientapp.ini &

restart_app HomeScreenApp /usr/bin/HomeScreenApp \
    VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_homescreen.json \
    VSOMEIP_APPLICATION_NAME=HomeScreenApp \
    COMMONAPI_CONFIG=/etc/commonapi/commonapi_homescreen.ini &

echo "[HU] All HU watchdogs started. Waiting..."
wait
echo "[HU] All watchdogs exited — tearing down HU cluster."
