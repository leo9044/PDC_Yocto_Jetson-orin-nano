SUMMARY = "vsomeip Routing Manager Service"
DESCRIPTION = "Systemd service for vsomeip routing manager daemon"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS:${PN} = "vsomeip"

inherit systemd

SRC_URI = "file://vsomeip-routing-manager.service \
           file://vsomeip-routing-manager.json \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/vsomeip-routing-manager.service ${D}${systemd_system_unitdir}/
    
    install -d ${D}${sysconfdir}/vsomeip
    install -m 0644 ${WORKDIR}/vsomeip-routing-manager.json ${D}${sysconfdir}/vsomeip/
}

SYSTEMD_SERVICE:${PN} = "vsomeip-routing-manager.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${systemd_system_unitdir}/vsomeip-routing-manager.service \
    ${sysconfdir}/vsomeip/vsomeip-routing-manager.json \
"
