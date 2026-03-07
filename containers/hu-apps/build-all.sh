#!/bin/sh
# HU 앱 4개 전체 이미지 빌드 스크립트
# Jetson 위에서 직접 실행
#
# 사용법: sh build-all.sh [버전태그]
# 예시:   sh build-all.sh 1.0.0

VERSION=${1:-1.0.0}

# 앱 목록: "이미지명:바이너리명:VSOMEIP_APP_NAME:QML공유디렉토리"
APPS="
hu-gearapp:GearApp:GearApp:gearapp
hu-homescreen:HomeScreenApp:HomeScreenApp:homescreenapp
hu-media:MediaApp:MediaApp:mediaapp
hu-ambient:AmbientApp:AmbientApp:ambientapp
"

WORKDIR="/tmp/hu-build"

for entry in $APPS; do
    IMAGE=$(echo $entry | cut -d: -f1)
    BINARY=$(echo $entry | cut -d: -f2)
    VSOMEIP_NAME=$(echo $entry | cut -d: -f3)
    SHARE_DIR=$(echo $entry | cut -d: -f4)

    echo ""
    echo "=== 빌드: ${IMAGE}:${VERSION} ==="

    BUILD_DIR="${WORKDIR}/${IMAGE}"
    mkdir -p "${BUILD_DIR}/rootfs/usr/bin"
    mkdir -p "${BUILD_DIR}/rootfs/usr/share/${SHARE_DIR}"

    # 바이너리 복사
    if [ ! -f "/usr/bin/${BINARY}" ]; then
        echo "WARNING: /usr/bin/${BINARY} 없음, 건너뜀"
        continue
    fi
    cp /usr/bin/${BINARY} ${BUILD_DIR}/rootfs/usr/bin/

    # QML 리소스 복사
    if [ -d "/usr/share/${SHARE_DIR}/qml" ]; then
        cp -r /usr/share/${SHARE_DIR}/qml ${BUILD_DIR}/rootfs/usr/share/${SHARE_DIR}/
    fi

    # Dockerfile 생성
    cat > ${BUILD_DIR}/Dockerfile << EOF
FROM scratch
COPY rootfs/ /
USER 1000:1000
ENV WAYLAND_DISPLAY=wayland-2
ENV XDG_RUNTIME_DIR=/run/user/1000
ENV QT_QPA_PLATFORM=wayland
ENV QT_WAYLAND_DISABLE_WINDOWDECORATION=1
ENV QSG_RENDER_LOOP=basic
ENV QT_QUICK_BACKEND=software
ENV QT_QPA_FONTDIR=/usr/share/fonts
ENV FONTCONFIG_FILE=/etc/fonts/fonts.conf
ENV LD_LIBRARY_PATH=/usr/lib
ENV QT_PLUGIN_PATH=/usr/lib/plugins
ENV QML2_IMPORT_PATH=/usr/lib/qml
ENV VSOMEIP_APPLICATION_NAME=${VSOMEIP_NAME}
CMD ["/usr/bin/${BINARY}"]
EOF

    cd ${BUILD_DIR}
    docker build -t "${IMAGE}:${VERSION}" . 2>&1 | grep -E 'Step|Successfully|Error|error'
    echo "완료: ${IMAGE}:${VERSION}"
done

echo ""
echo "=== 전체 빌드 완료 ==="
docker images | grep -E 'hu-|REPOSITORY'
