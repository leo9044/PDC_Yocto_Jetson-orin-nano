SUMMARY = "Speedometer App - IC Speed Display"
DESCRIPTION = "Instrument Cluster speedometer application with CommonAPI integration"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = " \
    qtbase \
    qtdeclarative \
    vsomeip \
    commonapi-core \
    commonapi-someip-runtime \
    commonapi-generated \
"

RDEPENDS:${PN} = " \
    qtbase \
    qtdeclarative \
    qtquickcontrols2 \
    vsomeip \
    commonapi-core \
    commonapi-someip-runtime \
    commonapi-generated \
"

SRC_URI = " \
    file://main.cpp \
    file://vehiclecontrolclient.cpp \
    file://vehiclecontrolclient.h \
    file://resources \
    file://qml \
    file://config \
    file://CMakeLists.txt \
"

S = "${WORKDIR}"

do_configure:prepend() {
    mkdir -p ${S}/src
    cp ${WORKDIR}/main.cpp ${S}/src/
    cp ${WORKDIR}/vehiclecontrolclient.cpp ${S}/src/
    cp ${WORKDIR}/vehiclecontrolclient.h ${S}/src/
}

inherit cmake_qt5 systemd

# Skip QA checks for RPATH (CMakeLists.txt has hardcoded install_folder references)
INSANE_SKIP:${PN} += "rpaths buildpaths"

EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=${STAGING_DIR_TARGET}${prefix} \
    -DCOMMONAPI_GEN_DIR=${STAGING_INCDIR}/commonapi-generated \
"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/Speedometer_app ${D}${bindir}/
    
    # Install config files
    install -d ${D}${sysconfdir}/commonapi
    install -m 0644 ${WORKDIR}/config/*.json ${D}${sysconfdir}/commonapi/
    
    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    cat > ${D}${systemd_system_unitdir}/speedometer-app.service << 'EOF'
[Unit]
Description=Speedometer App - IC Speed Display
After=ic-compositor.service
Requires=ic-compositor.service

[Service]
Type=simple
Environment="XDG_RUNTIME_DIR=/run/user/1000"
Environment="WAYLAND_DISPLAY=wayland-1"
Environment="VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_speedometer.json"
ExecStart=/usr/bin/Speedometer_app
Restart=on-failure
RestartSec=5
User=weston

[Install]
WantedBy=graphical.target
EOF
}

SYSTEMD_SERVICE:${PN} = "speedometer-app.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/Speedometer_app \
    ${sysconfdir}/commonapi/*.json \
    ${systemd_system_unitdir}/speedometer-app.service \
"
