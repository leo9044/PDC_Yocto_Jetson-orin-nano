SUMMARY = "SEAME Jetson Orin Nano Head Unit Image"
DESCRIPTION = "Tegra demo-image-weston extended with SEAME HU applications"
LICENSE = "MIT"

# demo-image-weston을 베이스로 사용 (이미 Weston + Tegra 최적화 포함)
require recipes-demo/images/demo-image-weston.bb

# Exclude gtk4 dependencies (Vulkan link error, Qt5 used instead)
# matchbox-terminal depends on vte which depends on gtk4, so exclude it
# Use weston-terminal instead (already in weston package)
PACKAGE_EXCLUDE += "matchbox-terminal vte gtk4"
IMAGE_INSTALL:remove = "matchbox-terminal packagegroup-demo-x11tests nvgstapps gstreamer1.0-plugins-tegra"

# Ensure Weston is installed (includes weston-terminal)
IMAGE_INSTALL:append = " weston weston-init weston-examples"

# Qt 5.15 (Wayland support)
IMAGE_INSTALL:append = " \
    qtbase \
    qtdeclarative \
    qtquickcontrols2 \
    qtquickcontrols2-qmlplugins \
    qtwayland \
    qtgraphicaleffects \
    qtmultimedia \
    qtsvg \
    qtsvg-plugins \
"

# Fonts for Qt applications
IMAGE_INSTALL:append = " \
    fontconfig \
    fontconfig-utils \
    freetype \
    ttf-dejavu-sans \
    ttf-dejavu-sans-mono \
    ttf-dejavu-serif \
"

# vsomeip & CommonAPI middleware
IMAGE_INSTALL:append = " \
    vsomeip \
    vsomeip-service \
    commonapi-core \
    commonapi-someip-runtime \
    commonapi-generated \
    boost \
"

# SEAME HU Applications
IMAGE_INSTALL:append = " \
    unified-compositor \
    gearapp \
    mediaapp \
    ambientapp \
    homescreenapp \
"

# SEAME IC Applications
IMAGE_INSTALL:append = " \
    ic-compositor \
    batterymeter-app \
    gearstate-app \
    speedometer-app \
"

# Network tools
IMAGE_INSTALL:append = " \
    iproute2 \
    iputils \
    openssh \
    openssh-sftp-server \
    wpa-supplicant \
    linux-firmware \
    iw \
    networkmanager \
    networkmanager-nmcli \
    wifi-config \
    eth-static-ip \
"

# Development/debug tools
IMAGE_INSTALL:append = " \
    htop \
    nano \
    vim \
    sudo \
"

# Docker engine + IC/HU container setup
IMAGE_INSTALL:append = " \
    docker-moby \
    ic-container-setup \
    hu-container-setup \
"

SYSTEMD_DEFAULT_TARGET = "graphical.target"

# Allow weston user (uid 1000) to run any command with sudo without password.
setup_sudo() {
    install -d ${IMAGE_ROOTFS}/etc/sudoers.d
    echo "weston ALL=(ALL) NOPASSWD: ALL" > ${IMAGE_ROOTFS}/etc/sudoers.d/weston
    chmod 440 ${IMAGE_ROOTFS}/etc/sudoers.d/weston
}
ROOTFS_POSTPROCESS_COMMAND += "setup_sudo; "

# Pre-create fontconfig cache directory so fontconfig can write on first boot.
generate_font_cache_dir() {
    install -d ${IMAGE_ROOTFS}/var/cache/fontconfig
}
ROOTFS_POSTPROCESS_COMMAND += "generate_font_cache_dir; "

# Mask systemd-networkd-wait-online — image uses NetworkManager, not networkd.
# Without this, boot is delayed ~2 minutes waiting for all interfaces.
mask_networkd_wait_online() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system
    ln -sf /dev/null ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/systemd-networkd-wait-online.service
}
ROOTFS_POSTPROCESS_COMMAND += "mask_networkd_wait_online; "
