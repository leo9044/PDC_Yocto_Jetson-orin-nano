#!/bin/sh
# Builds the hu-cluster Docker image on the Jetson device.
#
# Why on-device?
#   The app binaries are compiled by Yocto for this specific rootfs.
#   Building here avoids cross-compilation and keeps the image tiny
#   (FROM scratch — only binaries, no OS layer).
#
# Why FROM scratch?
#   Qt5 libs, vsomeip, fonts are all already on the Yocto rootfs.
#   We volume-mount /usr/lib at runtime, so no need to bundle them.
#
# Usage: build-hu-container.sh [--force]

IMAGE="hu-cluster:latest"

if [ "$1" != "--force" ] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[HU build] $IMAGE already exists, skipping. Use --force to rebuild."
    exit 0
fi

echo "[HU build] Preparing build context..."

BUILD_DIR=$(mktemp -d /tmp/hu-build.XXXXXX)
trap "rm -rf $BUILD_DIR" EXIT

mkdir -p $BUILD_DIR/rootfs/usr/bin
mkdir -p $BUILD_DIR/rootfs/etc/commonapi

# ── Binaries ──────────────────────────────────────────────────────────────────
# No compositor inside this container (Option B2: UnifiedCompositor runs on host).
# Only the 4 HU app binaries are needed.
for BIN in GearApp MediaApp AmbientApp HomeScreenApp; do
    if [ ! -f /usr/bin/$BIN ]; then
        echo "[HU build] ERROR: /usr/bin/$BIN not found"
        exit 1
    fi
    cp /usr/bin/$BIN $BUILD_DIR/rootfs/usr/bin/
done

# Shell binary needed to run the entrypoint script inside FROM scratch container.
# With Yocto usrmerge, /bin/sh resolves to the actual bash/dash binary.
cp "$(readlink -f /bin/sh)" $BUILD_DIR/rootfs/usr/bin/sh

# sleep is used in the entrypoint to poll for the wayland-2 socket.
# It is a separate binary (not a shell builtin) so must be explicitly copied.
cp "$(readlink -f /bin/sleep)" $BUILD_DIR/rootfs/usr/bin/sleep

# Entrypoint script (manages start order of HU apps)
cp /usr/bin/hu-entrypoint.sh $BUILD_DIR/rootfs/usr/bin/hu-entrypoint.sh
chmod +x $BUILD_DIR/rootfs/usr/bin/hu-entrypoint.sh

# ── Configs ───────────────────────────────────────────────────────────────────
# HU apps store both vsomeip and CommonAPI configs under /etc/commonapi/
for CFG in \
    vsomeip_gearapp.json    commonapi_gearapp.ini \
    vsomeip_mediaapp.json   commonapi_mediaapp.ini \
    vsomeip_ambientapp.json commonapi_ambientapp.ini \
    vsomeip_homescreen.json commonapi_homescreen.ini; do
    if [ -f /etc/commonapi/$CFG ]; then
        cp /etc/commonapi/$CFG $BUILD_DIR/rootfs/etc/commonapi/
    fi
done

echo "[HU build] rootfs:"
find $BUILD_DIR/rootfs -type f

# ── Dockerfile ────────────────────────────────────────────────────────────────
# No base OS — the Yocto host rootfs IS the runtime environment via mounts.
# ENTRYPOINT uses /usr/bin/sh (copied above) so we have a shell in scratch.
cat > $BUILD_DIR/Dockerfile << 'EOF'
FROM scratch
COPY rootfs/ /
USER 1000:1000
ENTRYPOINT ["/usr/bin/sh", "/usr/bin/hu-entrypoint.sh"]
EOF

cd $BUILD_DIR
docker build -t "$IMAGE" .

echo "[HU build] Done: $IMAGE"
