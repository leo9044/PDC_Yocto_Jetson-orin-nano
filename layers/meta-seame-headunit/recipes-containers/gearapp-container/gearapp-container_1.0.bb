SUMMARY = "gearapp per-app container (HU domain)"
DESCRIPTION = "GearApp in its own Docker container for OTA-independent updates. HU domain - Safety-Relevant: cpuset=2,3,4,5, cpu-shares=800, memory=256m."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS:${PN} = "docker-moby"

inherit systemd

SRC_URI = " \
    file://build-gearapp-container.sh \
    file://gearapp-entrypoint.sh \
    file://gearapp-container.service \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/build-gearapp-container.sh ${D}${bindir}/build-gearapp-container.sh
    install -m 0755 ${WORKDIR}/gearapp-entrypoint.sh      ${D}${bindir}/gearapp-entrypoint.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/gearapp-container.service  ${D}${systemd_system_unitdir}/

    # Mask the native (non-containerised) service to prevent conflict
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/gearapp.service
}

SYSTEMD_SERVICE:${PN} = "gearapp-container.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/build-gearapp-container.sh \
    ${bindir}/gearapp-entrypoint.sh \
    ${systemd_system_unitdir}/gearapp-container.service \
    ${sysconfdir}/systemd/system/gearapp.service \
"
