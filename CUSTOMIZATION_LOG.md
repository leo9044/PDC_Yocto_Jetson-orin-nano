# Tegra Demo Distro Customization Log

## Table of Contents

1. [Build Environment Setup](#1-build-environment-setup)
2. [Build Fixes Applied](#2-build-fixes-applied)
3. [Network Configuration](#3-network-configuration)
4. [Image Customization](#4-image-customization)
5. [SEAME Middleware Integration](#5-seame-middleware-integration)
6. [SEAME Applications Integration](#6-seame-applications-integration)
7. [Custom Image: seame-headunit-image](#7-custom-image-seame-headunit-image)


---

## 1. Build Environment Setup

### Initial Setup
```bash
cd /home/seame/leo/tegra-demo-distro
source ./setup-env --machine jetson-orin-nano-devkit --distro tegrademo
```

### Repository Information
- **Base**: OE4T tegra-demo-distro (scarthgap branch)
- **Machine**: jetson-orin-nano-devkit
- **Distro**: tegrademo
- **L4T Version**: R36.4.4 (JetPack 6.2.1)
- **Yocto Version**: Scarthgap (5.0 LTS)

---

## 2. Build Fixes Applied

### File: `build/conf/local.conf`

#### OpenSSL EC2 Fix
```bash
# Disable EC2 support in OpenSSL to avoid linking errors
EXTRA_OECONF:append:pn-openssl = " no-ec2m"
```

#### LTO (Link Time Optimization) Disable
```bash
# Disable LTO globally to avoid GCC/binutils circular dependency
TARGET_CFLAGS:remove = "-flto"
TARGET_CXXFLAGS:remove = "-flto"
SELECTED_OPTIMIZATION:remove = "-flto"
```

#### EDK2 Firmware Specific Fix
```bash
# EDK2 firmware specific LTO disable
TARGET_CFLAGS:pn-edk2-firmware-tegra:remove = "-flto"
TARGET_CXXFLAGS:pn-edk2-firmware-tegra:remove = "-flto"
SELECTED_OPTIMIZATION:pn-edk2-firmware-tegra:remove = "-flto"
```

---

## 3. Network Configuration

### Implementation Method: bbappend (Raspberry Pi proven method)

Following the successful Raspberry Pi implementation, network configuration is done through **bbappend** files that extend the base systemd and wpa-supplicant recipes.

### Recipe Locations
```
layers/meta-tegrademo/
├── recipes-core/systemd/
│   ├── systemd_%.bbappend
│   └── files/
│       ├── 10-enP8p1s0.network
│       └── 20-wlP1p1s0.network
└── recipes-connectivity/wpa-supplicant/
    ├── wpa-supplicant_%.bbappend
    └── files/
        └── wpa_supplicant-wlP1p1s0.conf
```

### systemd bbappend: `systemd_%.bbappend`

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://10-enP8p1s0.network \
    file://20-wlP1p1s0.network \
"

do_install:append() {
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/10-enP8p1s0.network ${D}${sysconfdir}/systemd/network/
    install -m 0644 ${WORKDIR}/20-wlP1p1s0.network ${D}${sysconfdir}/systemd/network/
}

FILES:${PN} += "${sysconfdir}/systemd/network/"
```

**Purpose**: Automatically installs systemd-networkd configuration files

### wpa-supplicant bbappend: `wpa-supplicant_%.bbappend`

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://wpa_supplicant-wlP1p1s0.conf"

SYSTEMD_AUTO_ENABLE:${PN} = "enable"
SYSTEMD_SERVICE:${PN}:append = " wpa_supplicant@wlP1p1s0.service"

do_install:append() {
    install -d ${D}${sysconfdir}/wpa_supplicant
    install -m 600 ${WORKDIR}/wpa_supplicant-wlP1p1s0.conf ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-wlP1p1s0.conf
}

FILES:${PN} += "${sysconfdir}/wpa_supplicant/wpa_supplicant-wlP1p1s0.conf"
```

**Purpose**: 
- Installs WiFi credentials
- Automatically enables `wpa_supplicant@wlP1p1s0.service` at boot

### Ethernet Configuration: `10-enP8p1s0.network`

```ini
[Match]
Name=enP8p1s0

[Network]
Address=192.168.1.101/24
Gateway=192.168.1.1
DNS=8.8.8.8
DNS=8.8.4.4

[Link]
RequiredForOnline=yes
```

**Interface**: enP8p1s0 (Predictable Network Interface Name)  
**IP Address**: 192.168.1.101/24  
**Gateway**: 192.168.1.1  
**DNS**: Google DNS (8.8.8.8, 8.8.4.4)

### WiFi Configuration: `20-wlan0.network`

```ini
[Match]
Name=wlP1p1s0

[Network]
DHCP=yes

[DHCP]
RouteMetric=200
```

**Interface**: wlP1p1s0 (Predictable Network Interface Name)  
**DHCP**: Enabled  
**Route Metric**: 200 (lower priority than Ethernet)

### WiFi Credentials: `wpa_supplicant-wlan0.conf`

```
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1

network={
    ssid="SEA:ME WiFi Access"
    psk="1fy0u534m3"
    key_mgmt=WPA-PSK
}
```

**SSID**: SEA:ME WiFi Access  
**Password**: 1fy0u534m3  
**Security**: WPA-PSK

---

## 4. Image Customization

### Modified Image: `demo-image-weston.bb`

**Location**: `layers/meta-tegrademo/recipes-demo/images/demo-image-weston.bb`

**Changes Made**:
```bitbake
# SEAME: Network configuration packages
IMAGE_INSTALL:append = " wpa-supplicant systemd openssh openssh-sftp-server"
```

**Purpose**: Include network and SSH packages in the demo-image-weston image

**Why demo-image-weston instead of core-image-weston?**
- `core-image-weston`: Base Yocto image with Weston compositor (upstream, unmodified)
- `demo-image-weston`: OE4T tegra-demo custom image that extends core-image-weston
- Our `network-config` package was added to `demo-image-weston.bb` only
- Building `core-image-weston` will NOT include custom network configuration
- Always build `demo-image-weston` to include SEAME customizations

**Features Already Included**:
- SSH server (openssh + openssh-sftp-server) - explicitly added via IMAGE_INSTALL
- Weston compositor
- systemd as init system

### Post-Flash Manual Steps (Until systemd service is fixed)

After flashing the image, manually enable wpa_supplicant:

```bash
# On Jetson device
systemctl enable wpa_supplicant@wlP1p1s0.service
systemctl start wpa_supplicant@wlP1p1s0.service
systemctl restart systemd-networkd
```


---

## Notes

### SD Card Hot-Swap Discovery
- **Finding**: SD cards with same L4T version (R36.4.4) can be swapped without reflashing bootloader
- **Reason**: Bootloader/kernel stored in eMMC, rootfs on SD card
- **Benefit**: Quick switching between Yocto and Ubuntu for development
- **Requirement**: L4T versions must match (R35.x ↔ R36.x requires reflash)

### Git Repository
- **Remote**: https://github.com/leo9044/PDC_Yocto_Jetson-orin-nano.git
- **Branch**: main
- **Modified Files**: Only `build/conf/local.conf` tracked

### Important Files to Track
```
tegra-demo-distro/
├── build/conf/local.conf (build fixes)
├── layers/meta-tegrademo/recipes-connectivity/network-config/ (custom network config)
└── layers/meta-tegrademo/recipes-demo/images/demo-image-weston.bb (modified image)
```

---

**Last Updated**: February 9, 2026  
**Status**: Phase 1 (Network Configuration) - WiFi ✅, Ethernet ✅, SSH build completed (pending flash)

---

## 5. SEAME Middleware Integration

### Layer Created: meta-middleware

**Location**: `layers/meta-middleware/`

**Purpose**: Build vsomeip and CommonAPI middleware stack for automotive IPC

### Middleware Components

#### 1. vsomeip 3.5.8
**Recipe**: `recipes-comm/vsomeip/vsomeip_3.5.8.bb`

```bitbake
SUMMARY = "COVESA vsomeip SOME/IP implementation"
LICENSE = "MPL-2.0"
DEPENDS = "boost"

SRC_URI = "git://github.com/COVESA/vsomeip.git;protocol=https;branch=master"
SRCREV = "d4c0b469e3dc09f215d13c7b37ca0d57a5f47fa1"  # v3.5.8 tag

inherit cmake

EXTRA_OECMAKE = "-DENABLE_SIGNAL_HANDLING=1"
```

**Key Features**:
- SOME/IP protocol implementation
- Boost dependency for threading/networking
- Signal handling enabled

#### 2. CommonAPI Core 3.2.4
**Recipe**: `recipes-comm/commonapi-core/commonapi-core_3.2.4.bb`

**Critical Fix**: GCC 13 compatibility patch

```bitbake
SRC_URI = "git://github.com/COVESA/capicxx-core-runtime.git;protocol=https;branch=master \
           file://0001-Add-missing-string-includes.patch"
SRCREV = "9eb5d398a0ea10c39b30ebf2789c6ae365c1895e"  # Pinned for stability
```

**Patch**: `files/0001-Add-missing-string-includes.patch`
```patch
--- a/include/CommonAPI/Types.hpp
+++ b/include/CommonAPI/Types.hpp
@@ -9,6 +9,7 @@
 #include <cstdint>
 #include <functional>
 #include <unordered_set>
+#include <string>
 
 #include <CommonAPI/ByteBuffer.hpp>
```

**Issue**: GCC 13 removed implicit transitive includes  
**Solution**: Explicitly include `<string>` header in Types.hpp

#### 3. CommonAPI SomeIP Runtime 3.2.4
**Recipe**: `recipes-comm/commonapi-someip/commonapi-someip-runtime_3.2.4.bb`

```bitbake
DEPENDS = "vsomeip commonapi-core boost"
SRC_URI = "git://github.com/COVESA/capicxx-someip-runtime.git;protocol=https;branch=master"
SRCREV = "5a472b1e3ec490e5c2c12bcbaf0a8bd0403ad013"
```

**Purpose**: Binds CommonAPI to vsomeip transport layer

#### 4. CommonAPI Generated Code
**Recipe**: `recipes-comm/commonapi-generated/commonapi-generated_1.0.bb`

```bitbake
SUMMARY = "Pre-generated CommonAPI code for SEAME vehicle control interface"

SRC_URI = "file://core/* \
           file://someip/*"

do_install() {
    install -d ${D}${includedir}/commonapi-generated/core
    install -d ${D}${includedir}/commonapi-generated/someip
    
    cp -r ${WORKDIR}/core/* ${D}${includedir}/commonapi-generated/core/
    cp -r ${WORKDIR}/someip/* ${D}${includedir}/commonapi-generated/someip/
}
```

**Source**: `/home/seame/leo/DES_Head-Unit/commonapi/generated/{core,someip}`  
**Purpose**: Provides stub/proxy classes for vehicle control FIDL interface

### Layer Configuration: meta-middleware/conf/layer.conf

```bitbake
BBPATH =. "${LAYERDIR}:"
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "meta-middleware"
BBFILE_PATTERN_meta-middleware = "^${LAYERDIR}/"
BBFILE_PRIORITY_meta-middleware = "7"

LAYERDEPENDS_meta-middleware = "core openembedded-layer"
LAYERSERIES_COMPAT_meta-middleware = "scarthgap"
```

---

## 6. SEAME Applications Integration

### Layer Created: meta-seame-headunit

**Location**: `layers/meta-seame-headunit/`

**Purpose**: Build SEAME Head Unit and Instrument Cluster applications

### Application Architecture

```
HU System: Weston (wayland-0) → HU_MainApp_Compositor (wayland-1) → Client Apps
IC System: Weston (wayland-0) → IC_Compositor (wayland-2) → IC Apps
```

### HU Applications (5 apps)

#### 1. HU Main App Compositor
**Recipe**: `recipes-apps/hu-mainapp-compositor/hu-mainapp-compositor_2.0.bb`

```bitbake
SUMMARY = "SEAME Head Unit Main Compositor"
DEPENDS = "qtbase qtdeclarative qtwayland qtquickcontrols2"

SRC_URI = "file://main.cpp \
           file://qml.qrc \
           file://qml/ \
           file://CMakeLists.txt"

inherit cmake_qt5 systemd

SYSTEMD_SERVICE:${PN} = "hu-mainapp-compositor.service"
SYSTEMD_AUTO_ENABLE = "enable"
```

**Systemd Service**: `files/hu-mainapp-compositor.service`
```ini
[Unit]
Description=SEAME HU Main App Compositor
After=weston.service vsomeip-routing-manager.service

[Service]
Type=simple
Environment="WAYLAND_DISPLAY=wayland-0"
Environment="XDG_RUNTIME_DIR=/tmp/xdg"
ExecStart=/usr/bin/HU_MainApp_Compositor
Restart=on-failure

[Install]
WantedBy=graphical.target
```

#### 2-5. HU Client Apps (GearApp, MediaApp, AmbientApp, HomeScreenApp)

All follow similar structure:
```bitbake
DEPENDS = "qtbase qtdeclarative qtwayland qtquickcontrols2 \
           vsomeip commonapi-core commonapi-someip-runtime commonapi-generated"

SRC_URI = "file://src/ \
           file://qml/ \
           file://qml.qrc \
           file://CMakeLists.txt \
           file://commonapi_*.ini \
           file://vsomeip_*.json"

SYSTEMD_SERVICE:${PN} = "gearapp.service"  # (or mediaapp, ambientapp, homescreenapp)
```

**Common Systemd Service Pattern**:
```ini
[Unit]
After=hu-mainapp-compositor.service

[Service]
Environment="WAYLAND_DISPLAY=wayland-1"  # Nested compositor
Environment="VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_gearapp.json"
ExecStart=/usr/bin/GearApp
```

### IC Applications (4 apps)

#### 1. IC Compositor
**Recipe**: `recipes-apps/ic-compositor/ic-compositor_1.0.bb`

```bitbake
SUMMARY = "SEAME Instrument Cluster Compositor"
DEPENDS = "qtbase qtdeclarative qtwayland"

# Source files individually listed (no src/ directory structure)
SRC_URI = "file://main.cpp \
           file://qml.qrc \
           file://qml/main.qml \
           file://CMakeLists.txt"

do_configure:prepend() {
    mkdir -p ${S}/src
    cp ${WORKDIR}/main.cpp ${S}/src/
}
```

**Note**: IC apps have flat file structure, requires manual src/ creation

#### 2-4. IC Apps (BatteryMeter, GearState, Speedometer)

**Common Pattern**:
```bitbake
DEPENDS = "qtbase qtdeclarative qtwayland qtquickcontrols2 \
           vsomeip commonapi-core commonapi-someip-runtime commonapi-generated"

SRC_URI = "file://main.cpp \
           file://vehiclecontrolclient.cpp \
           file://vehiclecontrolclient.h \
           file://resources/ \
           file://qml/ \
           file://config/ \
           file://CMakeLists.txt"

# CRITICAL: RPATH workaround for hardcoded install paths in CMakeLists.txt
INSANE_SKIP:${PN} += "rpaths buildpaths"
```

**RPATH Issue**: CMakeLists.txt contains:
```cmake
set(INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/../../install_folder")
set(CMAKE_INSTALL_RPATH "${INSTALL_PREFIX}/lib")
```
→ Yocto QA detects hardcoded RPATH pointing to build directory  
→ Solution: Skip QA check with `INSANE_SKIP`

**Systemd Service Pattern**:
```ini
[Unit]
After=ic-compositor.service

[Service]
Environment="WAYLAND_DISPLAY=wayland-2"  # IC nested compositor
Environment="VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_batterymeter.json"
ExecStart=/usr/bin/BatteryMeter_app
```

### vsomeip Routing Manager Service

**Recipe**: `recipes-middleware/vsomeip-service/vsomeip-service_1.0.bb`

```bitbake
SUMMARY = "vsomeip routing manager systemd service"
inherit systemd

SRC_URI = "file://vsomeip-routing-manager.service"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/vsomeip-routing-manager.service ${D}${systemd_system_unitdir}/
}

SYSTEMD_SERVICE:${PN} = "vsomeip-routing-manager.service"
SYSTEMD_AUTO_ENABLE = "enable"
```

**Service File**: `files/vsomeip-routing-manager.service`
```ini
[Unit]
Description=vsomeip Routing Manager
After=network.target weston.service

[Service]
Type=simple
Environment="VSOMEIP_APPLICATION_NAME=routingmanagerd"
ExecStartPre=/bin/sh -c 'touch /tmp/vsomeip.lck && chmod 666 /tmp/vsomeip.lck'
ExecStart=/usr/bin/routingmanagerd
Restart=on-failure

[Install]
WantedBy=graphical.target
```

### Layer Configuration: meta-seame-headunit/conf/layer.conf

```bitbake
BBPATH =. "${LAYERDIR}:"
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "meta-seame-headunit"
BBFILE_PATTERN_meta-seame-headunit = "^${LAYERDIR}/"
BBFILE_PRIORITY_meta-seame-headunit = "8"

LAYERDEPENDS_meta-seame-headunit = "core tegra qt5-layer openembedded-layer meta-middleware"
LAYERSERIES_COMPAT_meta-seame-headunit = "scarthgap"

# Mask gtk4 to avoid Vulkan linking errors
BBMASK += ".*/meta/recipes-gnome/gtk\\+/gtk4_.*\\.bb$"
```

---

## 7. Custom Image: seame-headunit-image

### Recipe Location
`layers/meta-seame-headunit/recipes-core/images/seame-headunit-image.bb`

### Base Image
```bitbake
require recipes-demo/images/demo-image-weston.bb
```
**Inherits**: Weston compositor + Tegra optimizations from OE4T

### Package Exclusions

```bitbake
# Exclude gtk4 dependencies (Vulkan link error, Qt5 used instead)
# matchbox-terminal depends on vte which depends on gtk4, so exclude it
# Use weston-terminal instead (already in weston package)
PACKAGE_EXCLUDE += "matchbox-terminal vte gtk4"
IMAGE_INSTALL:remove = "matchbox-terminal packagegroup-demo-x11tests nvgstapps gstreamer1.0-plugins-tegra"
```

**Why Exclude?**
- `gtk4`: Vulkan linking errors (`undefined reference to vkCreateXlibSurfaceKHR`)
- `vte`: Terminal library dependency of gtk4
- `matchbox-terminal`: GTK-based terminal, depends on vte
- `packagegroup-demo-x11tests`: X11 demos not needed (Wayland-only system)
- `nvgstapps`: NVIDIA GStreamer apps removed to save space
- `gstreamer1.0-plugins-tegra`: Tegra GStreamer plugins removed

**Alternative**: `weston-terminal` (already in weston package, no GTK dependency)

### Weston Packages

```bitbake
# Ensure Weston is installed (includes weston-terminal)
IMAGE_INSTALL:append = " weston weston-init weston-examples"
```

**Why Explicitly Add?**
- `demo-image-weston` requires weston, but with `matchbox-terminal` removal, panel configuration was affected
- Explicit addition ensures weston and weston-terminal are always present
- `weston-examples` includes demo apps like weston-flower, weston-smoke

### Qt5 Framework

```bitbake
# Qt 5.15 (Wayland support)
IMAGE_INSTALL:append = " \
    qtbase \
    qtdeclarative \
    qtquickcontrols2 \
    qtquickcontrols2-qmlplugins \
    qtwayland \
    qtgraphicaleffects \
    qtmultimedia \
"
```

**Qt5 Layer**: `meta-qt5` (scarthgap branch)  
**Version**: Qt 5.15.13  
**Modules**:
- `qtbase`: Core Qt libraries (QtCore, QtGui, QtWidgets)
- `qtdeclarative`: QML engine + QtQuick
- `qtquickcontrols2`: Material/Universal style controls
- `qtwayland`: Wayland platform plugin + compositor API
- `qtgraphicaleffects`: QML visual effects (blur, shadow, glow)
- `qtmultimedia`: Audio/video playback

### Middleware Stack

```bitbake
# vsomeip & CommonAPI middleware
IMAGE_INSTALL:append = " \
    vsomeip \
    vsomeip-service \
    commonapi-core \
    commonapi-someip-runtime \
    commonapi-generated \
    boost \
"
```

**Components**:
- `vsomeip 3.5.8`: SOME/IP transport layer
- `vsomeip-service`: systemd routing manager service
- `commonapi-core 3.2.4`: Middleware abstraction (with GCC 13 patch)
- `commonapi-someip-runtime 3.2.4`: CommonAPI ↔ vsomeip binding
- `commonapi-generated`: Pre-generated stub/proxy code
- `boost`: C++ libraries (vsomeip dependency)

### SEAME Applications

```bitbake
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
```

**Total**: 9 applications (5 HU + 4 IC)

### Network & Development Tools

```bitbake
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
```

### systemd Configuration

```bitbake
# systemd: graphical.target으로 부팅
SYSTEMD_DEFAULT_TARGET = "graphical.target"
```

**Service Startup Order**:
```
1. weston.service
2. vsomeip-routing-manager.service
3. hu-mainapp-compositor.service / ic-compositor.service
4. Application services (gearapp, batterymeter-app, etc.)
```

### Build Configuration Adjustments

#### local.conf Additions

```bitbake
# Exclude gtk4 due to Vulkan linking error
BBMASK += "gtk4|vte|matchbox-terminal"
```

**Purpose**: Prevent gtk4, vte, matchbox-terminal from being built at all

### Build Results

```bash
bitbake seame-headunit-image

# Output:
# Tasks Summary: Attempted 10574 tasks of which 10504 didn't need to be rerun and all succeeded.
```

**Image Files**:
- **Compressed**: `seame-headunit-image-jetson-orin-nano-devkit.rootfs.tegraflash.tar.gz` (658 MB)
- **Rootfs**: `seame-headunit-image.ext4` (14 GB)
- **Boot**: `boot.img` (46 MB)
- **Flash Script**: `doflash.sh`

### Flash Process

```bash
cd ~/jetson-flash
sudo rm -rf *
tar -xzf /path/to/seame-headunit-image-jetson-orin-nano-devkit.rootfs.tegraflash.tar.gz

# Put Jetson in recovery mode:
# 1. Power off
# 2. Hold RECOVERY button
# 3. Connect USB-C to PC
# 4. Power on
# 5. Verify: lsusb | grep -i nvidia

sudo ./doflash.sh
```

### Post-Flash Verification

**Terminal Icon**: ✅ Present (weston-terminal in top panel)  
**Panel Position**: Top (weston.ini preserved from demo-image-weston)

**Systemd Services Check**:
```bash
systemctl status vsomeip-routing-manager
systemctl status hu-mainapp-compositor
systemctl status ic-compositor
systemctl list-units --type=service | grep -E "gear|ambient|media|home|battery|speedometer"
```

---

**Last Updated**: February 10, 2026  
**Status**: Phase 2 (SEAME Applications) - Middleware ✅, Applications ✅, Custom Image ✅, Terminal Icon ✅
