#!/bin/sh
# Builds the ambientapp Docker image on the Jetson device.
# One binary per image - rebuild only this image for OTA updates.
IMAGE="ambientapp:latest"

if [ "$1" != "--force" ] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[ambientapp] $IMAGE already exists. Use --force to rebuild."
    exit 0
fi

echo "[ambientapp] Building container image..."
BUILD_DIR=$(mktemp -d /tmp/ambientapp-build.XXXXXX)
trap "rm -rf $BUILD_DIR" EXIT

mkdir -p $BUILD_DIR/rootfs/usr/bin
    mkdir -p $BUILD_DIR/rootfs/etc/commonapi

[ ! -f /usr/bin/AmbientApp ] && echo "[ambientapp] ERROR: /usr/bin/AmbientApp not found" && exit 1
cp /usr/bin/AmbientApp $BUILD_DIR/rootfs/usr/bin/

cp "$(readlink -f /bin/sh)"    $BUILD_DIR/rootfs/usr/bin/sh
cp "$(readlink -f /bin/sleep)" $BUILD_DIR/rootfs/usr/bin/sleep

cp /usr/bin/ambientapp-entrypoint.sh $BUILD_DIR/rootfs/usr/bin/entrypoint.sh
chmod +x $BUILD_DIR/rootfs/usr/bin/entrypoint.sh

    cp /etc/commonapi/vsomeip_ambientapp.json  $BUILD_DIR/rootfs/etc/commonapi/
    cp /etc/commonapi/commonapi_ambientapp.ini  $BUILD_DIR/rootfs/etc/commonapi/

cat > $BUILD_DIR/Dockerfile << 'EOF'
FROM scratch
COPY rootfs/ /
USER 1000:1000
ENTRYPOINT ["/usr/bin/sh", "/usr/bin/entrypoint.sh"]
EOF

cd $BUILD_DIR && docker build -t "$IMAGE" .
echo "[ambientapp] Done: $IMAGE"
