#!/bin/sh
# hu-gearapp 컨테이너 실행 스크립트
#
# 사용법: ./run.sh [버전태그]
# 예시:   ./run.sh 1.0.0

VERSION=${1:-1.0.0}
IMAGE_NAME="hu-gearapp:${VERSION}"
CONTAINER_NAME="hu-gearapp"

echo "=== ${IMAGE_NAME} 실행 ==="

# 기존 컨테이너 정리
docker rm -f "${CONTAINER_NAME}" 2>/dev/null

# wayland-2 소켓 대기
for i in $(seq 1 20); do
    test -S /run/user/1000/wayland-2 && break
    echo "wayland-2 소켓 대기 중... (${i}/20)"
    sleep 1
done

if ! test -S /run/user/1000/wayland-2; then
    echo "ERROR: wayland-2 소켓 없음. unified-compositor가 실행 중인지 확인하세요."
    exit 1
fi

docker run -d \
    --name "${CONTAINER_NAME}" \
    --network=host \
    -v /run/user/1000:/run/user/1000 \
    -v /tmp:/tmp \
    -v /usr/lib:/usr/lib:ro \
    -v /usr/lib/plugins:/usr/lib/plugins:ro \
    -v /usr/lib/qml:/usr/lib/qml:ro \
    -v /usr/share/fonts:/usr/share/fonts:ro \
    -v /etc/fonts:/etc/fonts:ro \
    -v /usr/share/X11:/usr/share/X11:ro \
    -v /var/cache/fontconfig:/var/cache/fontconfig \
    --user 1000:1000 \
    --memory=512m \
    --memory-swap=512m \
    --cpus=2.0 \
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
    -e QML2_IMPORT_PATH=/usr/lib/qml \
    -e VSOMEIP_APPLICATION_NAME=GearApp \
    "${IMAGE_NAME}"

echo ""
echo "컨테이너 상태: $(docker inspect -f '{{.State.Status}}' ${CONTAINER_NAME})"
echo "로그 확인: docker logs -f ${CONTAINER_NAME}"
