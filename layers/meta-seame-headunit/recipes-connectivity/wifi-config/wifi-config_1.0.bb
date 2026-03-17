SUMMARY = "Pre-configured WiFi connection for SEAME network"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = "file://seame-wifi.nmconnection"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/NetworkManager/system-connections
    install -m 0600 ${WORKDIR}/seame-wifi.nmconnection \
        ${D}${sysconfdir}/NetworkManager/system-connections/seame-wifi.nmconnection
}

FILES:${PN} = "${sysconfdir}/NetworkManager/system-connections/seame-wifi.nmconnection"

RDEPENDS:${PN} = "networkmanager"
