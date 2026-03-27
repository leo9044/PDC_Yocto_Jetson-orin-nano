SUMMARY = "pdcapp per-app container (HU domain)"
DESCRIPTION = "PDCApp in its own Docker container for OTA-independent updates. HU domain - Safety-Relevant: cpuset=2,3,4,5, cpu-shares=800, memory=512m."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS:${PN} = "docker-moby"

inherit systemd

SRC_URI = " \
    file://build-pdcapp-container.sh \
    file://pdcapp-entrypoint.sh \
    file://pdcapp-container.service \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/build-pdcapp-container.sh ${D}${bindir}/build-pdcapp-container.sh
    install -m 0755 ${WORKDIR}/pdcapp-entrypoint.sh      ${D}${bindir}/pdcapp-entrypoint.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/pdcapp-container.service  ${D}${systemd_system_unitdir}/

    # Mask the native (non-containerised) service to prevent conflict
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/pdcapp.service
}

SYSTEMD_SERVICE:${PN} = "pdcapp-container.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/build-pdcapp-container.sh \
    ${bindir}/pdcapp-entrypoint.sh \
    ${systemd_system_unitdir}/pdcapp-container.service \
    ${sysconfdir}/systemd/system/pdcapp.service \
"
