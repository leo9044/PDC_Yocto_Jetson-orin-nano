SUMMARY = "IC Cluster Container Setup"
DESCRIPTION = "Installs the on-device Docker image build script, container \
entrypoint, and systemd service for the IC safety-critical domain. \
The container is built on first boot from the Yocto-installed binaries."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# docker-moby must be present on the image (provides /usr/bin/docker)
# The native IC app packages must also be installed — their binaries
# are what build-ic-container.sh copies into the container rootfs.
RDEPENDS:${PN} = "docker-moby"

inherit systemd

SRC_URI = " \
    file://build-ic-container.sh \
    file://ic-entrypoint.sh \
    file://ic-container.service \
"

S = "${WORKDIR}"

do_install() {
    # ── Scripts ───────────────────────────────────────────────────────────────
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/build-ic-container.sh ${D}${bindir}/build-ic-container.sh
    install -m 0755 ${WORKDIR}/ic-entrypoint.sh      ${D}${bindir}/ic-entrypoint.sh

    # ── Systemd unit ──────────────────────────────────────────────────────────
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/ic-container.service  ${D}${systemd_system_unitdir}/

    # ── Mask native IC app services ───────────────────────────────────────────
    # /etc/systemd/system/ takes precedence over /usr/lib/systemd/system/.
    # A symlink to /dev/null here masks the unit without touching the
    # package-owned file in /usr/lib/systemd/system/ — no file conflict.
    install -d ${D}${sysconfdir}/systemd/system
    for SVC in ic-compositor.service gearstate-app.service \
                speedometer-app.service batterymeter-app.service; do
        ln -sf /dev/null ${D}${sysconfdir}/systemd/system/${SVC}
    done
}

SYSTEMD_SERVICE:${PN} = "ic-container.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${bindir}/build-ic-container.sh \
    ${bindir}/ic-entrypoint.sh \
    ${systemd_system_unitdir}/ic-container.service \
    ${sysconfdir}/systemd/system/ic-compositor.service \
    ${sysconfdir}/systemd/system/gearstate-app.service \
    ${sysconfdir}/systemd/system/speedometer-app.service \
    ${sysconfdir}/systemd/system/batterymeter-app.service \
"
