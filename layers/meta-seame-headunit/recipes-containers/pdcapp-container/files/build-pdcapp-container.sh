#!/bin/sh
# Builds the pdcapp Docker image on the Jetson device.
# One binary per image - rebuild only this image for OTA updates.
IMAGE="pdcapp:latest"

if [ "$1" != "--force" ] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[pdcapp] $IMAGE already exists. Use --force to rebuild."
    exit 0
fi

echo "[pdcapp] Building container image..."
BUILD_DIR=$(mktemp -d /tmp/pdcapp-build.XXXXXX)
trap "rm -rf $BUILD_DIR" EXIT

mkdir -p $BUILD_DIR/rootfs/usr/bin
    mkdir -p $BUILD_DIR/rootfs/etc/commonapi

[ ! -f /usr/bin/PDCApp ] && echo "[pdcapp] ERROR: /usr/bin/PDCApp not found" && exit 1
cp /usr/bin/PDCApp $BUILD_DIR/rootfs/usr/bin/

cp "$(readlink -f /bin/sh)"    $BUILD_DIR/rootfs/usr/bin/sh
cp "$(readlink -f /bin/sleep)" $BUILD_DIR/rootfs/usr/bin/sleep

cp /usr/bin/pdcapp-entrypoint.sh $BUILD_DIR/rootfs/usr/bin/entrypoint.sh
chmod +x $BUILD_DIR/rootfs/usr/bin/entrypoint.sh

    cp /etc/commonapi/vsomeip_pdc.json  $BUILD_DIR/rootfs/etc/commonapi/
    cp /etc/commonapi/commonapi_pdc.ini  $BUILD_DIR/rootfs/etc/commonapi/

cat > $BUILD_DIR/Dockerfile << 'EOF'
FROM scratch
COPY rootfs/ /
USER 1000:1000
ENTRYPOINT ["/usr/bin/sh", "/usr/bin/entrypoint.sh"]
EOF

cd $BUILD_DIR && docker build -t "$IMAGE" .
echo "[pdcapp] Done: $IMAGE"
