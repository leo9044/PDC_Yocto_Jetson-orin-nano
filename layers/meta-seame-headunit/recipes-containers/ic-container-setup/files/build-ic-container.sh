#!/bin/sh
# Builds the ic-cluster Docker image on the Jetson device.
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
# Usage: build-ic-container.sh [--force]

IMAGE="ic-cluster:latest"

if [ "$1" != "--force" ] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[IC build] $IMAGE already exists, skipping. Use --force to rebuild."
    exit 0
fi

echo "[IC build] Preparing build context..."

BUILD_DIR=$(mktemp -d /tmp/ic-build.XXXXXX)
trap "rm -rf $BUILD_DIR" EXIT

mkdir -p $BUILD_DIR/rootfs/usr/bin
mkdir -p $BUILD_DIR/rootfs/etc/vsomeip
mkdir -p $BUILD_DIR/rootfs/etc/commonapi

# ── Binaries ──────────────────────────────────────────────────────────────────
# No compositor inside this container (Option B2: UnifiedCompositor runs on host).
# Only the 3 IC app binaries are needed.
for BIN in GearState_app Speedometer_app BatteryMeter_app; do
    if [ ! -f /usr/bin/$BIN ]; then
        echo "[IC build] ERROR: /usr/bin/$BIN not found"
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

# Entrypoint script (manages start order of IC apps)
cp /usr/bin/ic-entrypoint.sh $BUILD_DIR/rootfs/usr/bin/ic-entrypoint.sh
chmod +x $BUILD_DIR/rootfs/usr/bin/ic-entrypoint.sh

# ── Configs ───────────────────────────────────────────────────────────────────
# vsomeip and CommonAPI configs installed by Yocto into /etc/
for CFG in vsomeip_gearstate.json vsomeip_speedometer.json vsomeip_batterymeter.json; do
    cp /etc/vsomeip/$CFG $BUILD_DIR/rootfs/etc/vsomeip/
done

for CFG in commonapi_gearstate.ini commonapi_speedometer.ini commonapi_batterymeter.ini; do
    cp /etc/commonapi/$CFG $BUILD_DIR/rootfs/etc/commonapi/
done

echo "[IC build] rootfs:"
find $BUILD_DIR/rootfs -type f

# ── Dockerfile ────────────────────────────────────────────────────────────────
# No base OS — the Yocto host rootfs IS the runtime environment via mounts.
# ENTRYPOINT uses /usr/bin/sh (copied above) so we have a shell in scratch.
cat > $BUILD_DIR/Dockerfile << 'EOF'
FROM scratch
COPY rootfs/ /
USER 1000:1000
ENTRYPOINT ["/usr/bin/sh", "/usr/bin/ic-entrypoint.sh"]
EOF

cd $BUILD_DIR
docker build -t "$IMAGE" .

echo "[IC build] Done: $IMAGE"
