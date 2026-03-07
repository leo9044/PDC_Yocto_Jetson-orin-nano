#!/bin/sh
# hu-gearapp 컨테이너 빌드 스크립트
# Jetson 위에서 직접 실행
#
# 사용법: ./build.sh [버전태그]
# 예시:   ./build.sh 1.0.0

VERSION=${1:-1.0.0}
IMAGE_NAME="hu-gearapp:${VERSION}"

echo "=== hu-gearapp 이미지 빌드: ${IMAGE_NAME} ==="

# rootfs 디렉토리 구성 (호스트에서 필요한 파일만 추출)
mkdir -p rootfs/usr/bin
mkdir -p rootfs/usr/share/gearapp

# GearApp 바이너리 복사
cp /usr/bin/GearApp rootfs/usr/bin/GearApp

# QML 리소스 복사
if [ -d /usr/share/gearapp/qml ]; then
    cp -r /usr/share/gearapp/qml rootfs/usr/share/gearapp/
fi

echo "rootfs 구성 완료:"
find rootfs/ -type f

# Docker 이미지 빌드
docker build -t "${IMAGE_NAME}" .

echo ""
echo "=== 빌드 완료 ==="
echo "이미지: ${IMAGE_NAME}"
echo "크기: $(docker image inspect ${IMAGE_NAME} --format '{{.Size}}' | awk '{printf \"%.1f MB\", $1/1024/1024}')"
echo ""
echo "실행하려면: ./run.sh ${VERSION}"
