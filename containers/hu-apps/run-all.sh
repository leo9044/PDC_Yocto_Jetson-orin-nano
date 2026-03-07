#!/bin/sh
# HU 앱 4개 전체 컨테이너 실행 스크립트 (PoC용 - 앱별 단독 실행)
# Jetson 위에서 직접 실행
#
# 사용법: sh run-all.sh [버전태그]
# 예시:   sh run-all.sh 1.0.0

VERSION=${1:-1.0.0}

# 공통 마운트/환경 옵션
COMMON_MOUNTS="\
  -v /run/user/1000:/run/user/1000 \
  -v /tmp:/tmp \
  -v /usr/lib:/usr/lib:ro \
  -v /usr/lib/plugins:/usr/lib/plugins:ro \
  -v /usr/lib/qml:/usr/lib/qml:ro \
  -v /usr/share/fonts:/usr/share/fonts:ro \
  -v /etc/fonts:/etc/fonts:ro \
  -v /usr/share/X11:/usr/share/X11:ro \
  -v /var/cache/fontconfig:/var/cache/fontconfig"

COMMON_ENV="\
  -e WAYLAND_DISPLAY=wayland-2 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
  -e QSG_RENDER_LOOP=basic \
  -e QT_QUICK_BACKEND=software \
  -e QT_QPA_FONTDIR=/usr/share/fonts \
  -e FONTCONFIG_FILE=/etc/fonts/fonts.conf \
  -e LD_LIBRARY_PATH=/usr/lib \
  -e QT_PLUGIN_PATH=/usr/lib/plugins \
  -e QML2_IMPORT_PATH=/usr/lib/qml"

# wayland-2 소켓 대기
for i in $(seq 1 20); do
    test -S /run/user/1000/wayland-2 && break
    echo "wayland-2 소켓 대기 중... (${i}/20)"
    sleep 1
done

if ! test -S /run/user/1000/wayland-2; then
    echo "ERROR: wayland-2 소켓 없음"
    exit 1
fi

# 기존 컨테이너 정리
for name in hu-gearapp hu-homescreen hu-media hu-ambient; do
    docker rm -f $name 2>/dev/null
done

# 앱별 실행 (VSOMEIP_APPLICATION_NAME만 다름)
echo "=== hu-gearapp 실행 ==="
docker run -d --name hu-gearapp --network=host \
  $COMMON_MOUNTS $COMMON_ENV \
  -e VSOMEIP_APPLICATION_NAME=GearApp \
  --user 1000:1000 --memory=512m --memory-swap=512m \
  hu-gearapp:${VERSION}

sleep 2

echo "=== hu-homescreen 실행 ==="
docker run -d --name hu-homescreen --network=host \
  $COMMON_MOUNTS $COMMON_ENV \
  -e VSOMEIP_APPLICATION_NAME=HomeScreenApp \
  --user 1000:1000 --memory=512m --memory-swap=512m \
  hu-homescreen:${VERSION}

sleep 2

echo "=== hu-media 실행 ==="
docker run -d --name hu-media --network=host \
  $COMMON_MOUNTS $COMMON_ENV \
  -e VSOMEIP_APPLICATION_NAME=MediaApp \
  --user 1000:1000 --memory=512m --memory-swap=512m \
  hu-media:${VERSION}

sleep 2

echo "=== hu-ambient 실행 ==="
docker run -d --name hu-ambient --network=host \
  $COMMON_MOUNTS $COMMON_ENV \
  -e VSOMEIP_APPLICATION_NAME=AmbientApp \
  --user 1000:1000 --memory=512m --memory-swap=512m \
  hu-ambient:${VERSION}

echo ""
echo "=== 실행 상태 ==="
docker ps --filter name=hu- --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
