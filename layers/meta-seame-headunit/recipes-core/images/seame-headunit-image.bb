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
    hu-mainapp-compositor \
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

# Network tools (already in demo-image-weston but ensure presence)
IMAGE_INSTALL:append = " \
    iproute2 \
    iputils \
"

# Development tools (already added openssh in phase 1)
IMAGE_INSTALL:append = " \
    htop \
    nano \
    vim \
"

# systemd: graphical.target으로 부팅
SYSTEMD_DEFAULT_TARGET = "graphical.target"
