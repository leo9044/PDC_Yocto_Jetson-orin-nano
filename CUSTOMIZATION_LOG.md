# Tegra Demo Distro Customization Log

## Table of Contents

1. [Build Environment Setup](#1-build-environment-setup)
2. [Build Fixes Applied](#2-build-fixes-applied)
3. [Network Configuration](#3-network-configuration)
4. [Image Customization](#4-image-customization)


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

### Recipe Location
```
layers/meta-tegrademo/recipes-connectivity/network-config/
├── network-config_1.0.bb
└── files/
    ├── 10-eth0.network
    ├── 20-wlan0.network
    └── wpa_supplicant-wlan0.conf
```

### Recipe: `network-config_1.0.bb`

**Purpose**: Configure static IP for Ethernet and WiFi connection

**Dependencies**:
- systemd-networkd
- wpa-supplicant

**Files Installed**:
- `/etc/systemd/network/10-eth0.network` - Ethernet static IP configuration
- `/etc/systemd/network/20-wlan0.network` - WiFi DHCP configuration
- `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` - WiFi credentials

### Ethernet Configuration: `10-eth0.network`

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
# SEAME Network Configuration
CORE_IMAGE_BASE_INSTALL += "network-config"
```

**Purpose**: Include network-config package in the demo-image-weston image

**Why demo-image-weston instead of core-image-weston?**
- `core-image-weston`: Base Yocto image with Weston compositor (upstream, unmodified)
- `demo-image-weston`: OE4T tegra-demo custom image that extends core-image-weston
- Our `network-config` package was added to `demo-image-weston.bb` only
- Building `core-image-weston` will NOT include custom network configuration
- Always build `demo-image-weston` to include SEAME customizations

**Features Already Included**:
- SSH server (openssh) - via demo-image-common.inc
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

**Last Updated**: February 6, 2026  
**Status**: Phase 1 (Network Configuration) - Build pending
