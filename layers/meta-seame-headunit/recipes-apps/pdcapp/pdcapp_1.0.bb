SUMMARY = "PDC (Park Distance Control) Application"
DESCRIPTION = "Qt5/QML rear-view camera display and PDC sensor visualization. \
               Runs inside the hu-cluster Docker container. \
               Connects to wayland-2 (UnifiedCompositor) and appears when gear = R."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "qtbase qtdeclarative qtquickcontrols2 gstreamer1.0 gstreamer1.0-plugins-base \
           vsomeip commonapi-core commonapi-someip-runtime commonapi-generated"
RDEPENDS:${PN} = "qtwayland qtgraphicaleffects qtquickcontrols2-qmlplugins vsomeip \
                  gstreamer1.0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good"

SRC_URI = " \
    file://CMakeLists.txt \
    file://src/ \
    file://qml/ \
    file://asset/ \
    file://qml.qrc \
    file://config/vsomeip_pdc.json \
    file://config/commonapi_pdc.ini \
"

S = "${WORKDIR}"

inherit cmake_qt5

EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DCOMMONAPI_GEN_DIR=${STAGING_INCDIR}/commonapi-generated \
    -DDEPLOY_PREFIX=${STAGING_DIR_HOST}${prefix} \
    -DQt5_DIR=${STAGING_LIBDIR}/cmake/Qt5 \
"

do_install:append() {
    install -d ${D}${bindir}
    if [ -f ${B}/PDCApp ]; then
        install -m 0755 ${B}/PDCApp ${D}${bindir}/
    fi

    install -d ${D}${sysconfdir}/commonapi
    install -m 0644 ${WORKDIR}/config/vsomeip_pdc.json ${D}${sysconfdir}/commonapi/
    install -m 0644 ${WORKDIR}/config/commonapi_pdc.ini ${D}${sysconfdir}/commonapi/
}

FILES:${PN} += " \
    ${bindir}/PDCApp \
    ${sysconfdir}/commonapi/vsomeip_pdc.json \
    ${sysconfdir}/commonapi/commonapi_pdc.ini \
"

INSANE_SKIP:${PN} += "already-stripped"
