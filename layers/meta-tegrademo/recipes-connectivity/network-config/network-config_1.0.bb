SUMMARY = "Network configuration for SEAME Jetson Head Unit"
DESCRIPTION = "Static IP configuration for Ethernet and WiFi settings"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://10-eth0.network \
    file://20-wlan0.network \
    file://wpa_supplicant-wlan0.conf \
"

S = "${WORKDIR}"

inherit allarch

RDEPENDS:${PN} = "systemd wpa-supplicant"

do_install() {
    # systemd-networkd configuration
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/10-eth0.network ${D}${sysconfdir}/systemd/network/
    install -m 0644 ${WORKDIR}/20-wlan0.network ${D}${sysconfdir}/systemd/network/
    
    # WPA supplicant configuration
    install -d ${D}${sysconfdir}/wpa_supplicant
    install -m 0600 ${WORKDIR}/wpa_supplicant-wlan0.conf ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-wlP1p1s0.conf
}

FILES:${PN} = " \
    ${sysconfdir}/systemd/network/* \
    ${sysconfdir}/wpa_supplicant/* \
"
