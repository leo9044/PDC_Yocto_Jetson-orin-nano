SUMMARY = "homescreen per-app container (HU domain)"
DESCRIPTION = "HomeScreenApp in its own Docker container for OTA-independent updates. HU domain - Standard: cpuset=2,3,4,5, cpu-shares=512, memory=512m."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS:${PN} = "docker-moby"

inherit systemd

SRC_URI = " \
    file://build-homescreen-container.sh \
    file://homescreen-entrypoint.sh \
    file://homescreen-container.service \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/build-homescreen-container.sh ${D}${bindir}/build-homescreen-container.sh
    install -m 0755 ${WORKDIR}/homescreen-entrypoint.sh      ${D}${bindir}/homescreen-entrypoint.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/homescreen-container.service  ${D}${systemd_system_unitdir}/

    # Mask the native (non-containerised) service to prevent conflict
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/homescreenapp.service
}

SYSTEMD_SERVICE:${PN} = "homescreen-container.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/build-homescreen-container.sh \
    ${bindir}/homescreen-entrypoint.sh \
    ${systemd_system_unitdir}/homescreen-container.service \
    ${sysconfdir}/systemd/system/homescreenapp.service \
"
