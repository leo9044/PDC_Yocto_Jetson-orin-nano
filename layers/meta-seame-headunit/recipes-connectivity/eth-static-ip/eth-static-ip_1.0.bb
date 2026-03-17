SUMMARY = "Static IP configuration for ethernet and vsomeip multicast route"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://eth-static.nmconnection \
    file://vsomeip-multicast-route.service \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/NetworkManager/system-connections
    install -m 0600 ${WORKDIR}/eth-static.nmconnection \
        ${D}${sysconfdir}/NetworkManager/system-connections/eth-static.nmconnection

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/vsomeip-multicast-route.service \
        ${D}${systemd_system_unitdir}/vsomeip-multicast-route.service
}

FILES:${PN} = " \
    ${sysconfdir}/NetworkManager/system-connections/eth-static.nmconnection \
    ${systemd_system_unitdir}/vsomeip-multicast-route.service \
"

SYSTEMD_SERVICE:${PN} = "vsomeip-multicast-route.service"
SYSTEMD_AUTO_ENABLE = "enable"

RDEPENDS:${PN} = "networkmanager"
