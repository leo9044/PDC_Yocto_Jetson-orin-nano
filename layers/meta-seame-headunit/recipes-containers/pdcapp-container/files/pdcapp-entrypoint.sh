#!/usr/bin/sh
# pdcapp entrypoint - wait for wayland-2 socket then exec the app.
SOCKET="${XDG_RUNTIME_DIR}/wayland-2"
i=0
while [ ! -S "$SOCKET" ]; do
    sleep 0.5; i=$((i+1))
    [ $i -ge 40 ] && echo "[pdcapp] ERROR: wayland-2 not ready after 20s" && exit 1
done
echo "[pdcapp] wayland-2 ready - exec PDCApp"
exec /usr/bin/PDCApp
