#!/usr/bin/sh
# mediaapp entrypoint - wait for wayland-2 socket then exec the app.
SOCKET="${XDG_RUNTIME_DIR}/wayland-2"
i=0
while [ ! -S "$SOCKET" ]; do
    sleep 0.5; i=$((i+1))
    [ $i -ge 40 ] && echo "[mediaapp] ERROR: wayland-2 not ready after 20s" && exit 1
done
echo "[mediaapp] wayland-2 ready - exec MediaApp"
exec /usr/bin/MediaApp
