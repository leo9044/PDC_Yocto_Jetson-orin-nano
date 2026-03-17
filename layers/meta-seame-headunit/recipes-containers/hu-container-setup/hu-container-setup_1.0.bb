SUMMARY = "HU Cluster Container Setup"
DESCRIPTION = "Installs the on-device Docker image build script, container \
entrypoint, and systemd service for the HU infotainment domain. \
The container is built on first boot from the Yocto-installed binaries."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# docker-moby must be present on the image (provides /usr/bin/docker)
# The native HU app packages must also be installed — their binaries
# are what build-hu-container.sh copies into the container rootfs.
RDEPENDS:${PN} = "docker-moby"

inherit systemd

SRC_URI = " \
    file://build-hu-container.sh \
    file://hu-entrypoint.sh \
    file://hu-container.service \
"

S = "${WORKDIR}"

do_install() {
    # ── Scripts ───────────────────────────────────────────────────────────────
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/build-hu-container.sh ${D}${bindir}/build-hu-container.sh
    install -m 0755 ${WORKDIR}/hu-entrypoint.sh      ${D}${bindir}/hu-entrypoint.sh

    # ── Systemd unit ──────────────────────────────────────────────────────────
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/hu-container.service  ${D}${systemd_system_unitdir}/

    # ── Mask native HU app services ───────────────────────────────────────────
    # /etc/systemd/system/ takes precedence over /usr/lib/systemd/system/.
    # A symlink to /dev/null here masks the unit without touching the
    # package-owned file in /usr/lib/systemd/system/ — no file conflict.
    #
    # NOTE: unified-compositor.service is NOT masked here (Option B2).
    # UnifiedCompositor runs on the HOST and creates wayland-2.
    # Both ic-container and hu-container apps connect to that wayland-2 socket.
    install -d ${D}${sysconfdir}/systemd/system
    for SVC in gearapp.service mediaapp.service ambientapp.service homescreenapp.service; do
        ln -sf /dev/null ${D}${sysconfdir}/systemd/system/${SVC}
    done
}

SYSTEMD_SERVICE:${PN} = "hu-container.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/build-hu-container.sh \
    ${bindir}/hu-entrypoint.sh \
    ${systemd_system_unitdir}/hu-container.service \
    ${sysconfdir}/systemd/system/gearapp.service \
    ${sysconfdir}/systemd/system/mediaapp.service \
    ${sysconfdir}/systemd/system/ambientapp.service \
    ${sysconfdir}/systemd/system/homescreenapp.service \
"
