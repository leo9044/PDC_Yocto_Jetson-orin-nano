SUMMARY = "IC Compositor - Instrument Cluster Wayland Compositor"
DESCRIPTION = "Separate Wayland compositor for instrument cluster display"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = " \
    qtbase \
    qtdeclarative \
    qtwayland \
"

RDEPENDS:${PN} = " \
    qtbase \
    qtdeclarative \
    qtwayland \
    qtquickcontrols2 \
"

SRC_URI = " \
    file://main.cpp \
    file://resources \
    file://qml \
    file://CMakeLists.txt \
"

S = "${WORKDIR}"

do_configure:prepend() {
    mkdir -p ${S}/src
    cp ${WORKDIR}/main.cpp ${S}/src/
}

inherit cmake_qt5 systemd

EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=${STAGING_DIR_TARGET}${prefix} \
"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/IC_Compositor ${D}${bindir}/
    
    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    cat > ${D}${systemd_system_unitdir}/ic-compositor.service << 'EOF'
[Unit]
Description=IC Compositor - Instrument Cluster Wayland Compositor
After=weston.service
Requires=weston.service

[Service]
Type=simple
User=weston
Environment="XDG_RUNTIME_DIR=/run/user/1000"
Environment="WAYLAND_DISPLAY=wayland-1"
Environment="QT_QPA_PLATFORM=wayland"
ExecStart=/usr/bin/IC_Compositor
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF
}

SYSTEMD_SERVICE:${PN} = "ic-compositor.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/IC_Compositor \
    ${systemd_system_unitdir}/ic-compositor.service \
"
