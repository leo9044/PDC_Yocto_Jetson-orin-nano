SUMMARY = "Unified Wayland Compositor (IC + HU, single display)"
DESCRIPTION = "Single nested Wayland compositor managing both IC and HU app windows on one display"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "qtbase qtdeclarative qtwayland"
RDEPENDS:${PN} = "qtbase qtdeclarative qtwayland-qmlplugins weston"

SRC_URI = " \
    file://CMakeLists.txt \
    file://src/ \
    file://qml/ \
    file://asset/ \
    file://qml_compositor.qrc \
    file://unified-compositor.service \
"

S = "${WORKDIR}"

inherit cmake_qt5 systemd

EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
"

do_install:append() {
    # systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/unified-compositor.service ${D}${systemd_system_unitdir}/
}

SYSTEMD_SERVICE:${PN} = "unified-compositor.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += "${bindir}/UnifiedCompositor"
