SUMMARY = "batterymeter per-app container (IC domain)"
DESCRIPTION = "BatteryMeter_app in its own Docker container for OTA-independent updates. IC domain - Safety-Critical: cpuset=0,1, cpu-shares=1024, memory=256m."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS:${PN} = "docker-moby"

inherit systemd

SRC_URI = " \
    file://build-batterymeter-container.sh \
    file://batterymeter-entrypoint.sh \
    file://batterymeter-container.service \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/build-batterymeter-container.sh ${D}${bindir}/build-batterymeter-container.sh
    install -m 0755 ${WORKDIR}/batterymeter-entrypoint.sh      ${D}${bindir}/batterymeter-entrypoint.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/batterymeter-container.service  ${D}${systemd_system_unitdir}/

    # Mask the native (non-containerised) service to prevent conflict
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/batterymeter-app.service
}

SYSTEMD_SERVICE:${PN} = "batterymeter-container.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/build-batterymeter-container.sh \
    ${bindir}/batterymeter-entrypoint.sh \
    ${systemd_system_unitdir}/batterymeter-container.service \
    ${sysconfdir}/systemd/system/batterymeter-app.service \
"
