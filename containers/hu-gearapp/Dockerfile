# hu-gearapp Dockerfile
# Yocto 빌드 결과물을 호스트 rootfs에서 직접 마운트하는 방식
# → 이미지 크기 최소화, 라이브러리 버전 호스트와 완전 일치
#
# 빌드: docker build -t hu-gearapp:1.0.0 .
# 실행: docker run 스크립트 참고 → run.sh

FROM scratch

# Yocto 호스트 rootfs를 통째로 베이스로 사용
# (실제 배포 시에는 Yocto SDK로 빌드한 sysroot를 COPY하는 방식으로 전환 가능)
# 현재는 호스트 /usr, /lib 마운트 방식으로 동작 검증 우선

# 앱 바이너리 및 QML 리소스만 이미지에 포함
COPY rootfs/ /

# 실행 사용자: weston (UID=1000, Wayland 소켓 소유자)
USER 1000:1000

# vsomeip IPC: /tmp/vsomeip-0 소켓 (호스트 /tmp 마운트 필요)
# Wayland: /run/user/1000/wayland-2 소켓 (호스트 /run/user/1000 마운트 필요)

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
ENV VSOMEIP_APPLICATION_NAME=GearApp

CMD ["/usr/bin/GearApp"]
