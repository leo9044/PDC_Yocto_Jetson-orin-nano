#!/bin/sh
# HU 앱 systemd → docker-compose 교체 설치 스크립트
# Jetson 위에서 직접 실행
#
# 사용법: sh install.sh [버전태그]
# 예시:   sh install.sh 1.0.0

VERSION=${1:-1.0.0}
COMPOSE_DIR="/etc/hu-apps"

echo "=== Step 1: 이미지 빌드 ==="
sh /home/weston/hu-apps/build-all.sh ${VERSION}

echo ""
echo "=== Step 2: docker-compose 설치 ==="
mkdir -p ${COMPOSE_DIR}
cp /home/weston/hu-apps/docker-compose.yml ${COMPOSE_DIR}/docker-compose.yml

# docker-compose.yml의 이미지 버전 태그 업데이트
sed -i "s|:1.0.0|:${VERSION}|g" ${COMPOSE_DIR}/docker-compose.yml
echo "설치 위치: ${COMPOSE_DIR}/docker-compose.yml"

echo ""
echo "=== Step 3: 기존 systemd 서비스 비활성화 ==="
systemctl stop gearapp homescreenapp mediaapp ambientapp 2>/dev/null
systemctl disable gearapp homescreenapp mediaapp ambientapp 2>/dev/null
echo "기존 서비스 비활성화 완료"

echo ""
echo "=== Step 4: hu-apps.service 설치 ==="
cp /home/weston/hu-apps/hu-apps.service /lib/systemd/system/hu-apps.service
systemctl daemon-reload
systemctl enable hu-apps.service
systemctl start hu-apps.service

echo ""
echo "=== 설치 완료 ==="
echo "서비스 상태:"
systemctl status hu-apps.service --no-pager | grep -E 'Active|Main PID'
echo ""
echo "컨테이너 상태:"
docker ps --filter name=hu- --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
