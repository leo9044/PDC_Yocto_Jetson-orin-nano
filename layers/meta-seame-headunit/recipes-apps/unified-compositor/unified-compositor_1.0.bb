SUMMARY = "Unified Wayland Compositor (IC + HU, single display)"
DESCRIPTION = "Single nested Wayland compositor managing both IC and HU app windows on one display. \
               Acts as a vsomeip client to receive gear state and show the PDC overlay when gear = R."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "qtbase qtdeclarative qtwayland vsomeip commonapi-core commonapi-someip-runtime commonapi-generated"
RDEPENDS:${PN} = "qtbase qtdeclarative qtwayland-qmlplugins weston vsomeip"

SRC_URI = " \
    file://CMakeLists.txt \
    file://src/ \
    file://qml/ \
    file://asset/ \
    file://qml_compositor.qrc \
    file://unified-compositor.service \
    file://config/vsomeip_compositor.json \
    file://config/commonapi_compositor.ini \
"

S = "${WORKDIR}"

inherit cmake_qt5 systemd

EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DCOMMONAPI_GEN_DIR=${STAGING_INCDIR}/commonapi-generated \
    -DDEPLOY_PREFIX=${STAGING_DIR_HOST}${prefix} \
    -DQt5_DIR=${STAGING_LIBDIR}/cmake/Qt5 \
"

do_install:append() {
    # systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/unified-compositor.service ${D}${systemd_system_unitdir}/

    # vsomeip / CommonAPI config files
    install -d ${D}${sysconfdir}/commonapi
    install -m 0644 ${WORKDIR}/config/vsomeip_compositor.json ${D}${sysconfdir}/commonapi/
    install -m 0644 ${WORKDIR}/config/commonapi_compositor.ini ${D}${sysconfdir}/commonapi/
}

SYSTEMD_SERVICE:${PN} = "unified-compositor.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/UnifiedCompositor \
    ${sysconfdir}/commonapi/vsomeip_compositor.json \
    ${sysconfdir}/commonapi/commonapi_compositor.ini \
"

INSANE_SKIP:${PN} += "already-stripped"
