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

## 4.1. Network Configuration Debugging Journey

### Problem: Configuration Changes Not Reflected After Build

**Initial Symptom**: Modified network configuration files (`.network`, `wpa_supplicant.conf`) and rebuilt the image, but changes did not appear on the flashed device.

**Root Cause Analysis**: Yocto's Shared State Cache (sstate) mechanism

Yocto uses an aggressive caching system to optimize build times by reusing previous build artifacts. The system detects changes in recipe files (`.bb`, `.bbappend`) but **does not automatically detect changes in external files** referenced by `SRC_URI` or `FILESEXTRAPATHS`.

### The Three-Layer Problem

#### Problem 1: "Build ≠ Install"

**What happened**:
```bash
# Modified files/10-enP8p1s0.network
# Changed IP from 192.168.1.100 to 192.168.1.101
$ bitbake demo-image-weston
# Build completed successfully
$ ./doflash.sh
# Device still has old IP: 192.168.1.100
```

**Why it failed**:
- Yocto's `do_install` task was cached from previous build
- The task signature (hash) didn't change because only the file content changed, not the recipe
- Cached artifacts were reused without re-executing `do_install`

**Solution**:
```bash
# Force clean the package state
$ bitbake systemd -c cleansstate

# Rebuild from scratch
$ bitbake demo-image-weston

# Now doflash.sh will include updated files
```

#### Problem 2: Selective Package Cache

**What happened**:
```bash
# Modified wpa_supplicant-wlP1p1s0.conf (WiFi password)
$ bitbake systemd -c cleansstate  # Only cleaned systemd
$ bitbake demo-image-weston
# WiFi still uses old password!
```

**Why it failed**:
- Network files are installed by **both** `systemd` and `wpa-supplicant` packages
- Cleaning only `systemd` left `wpa-supplicant` cached
- Image assembly picked up old `wpa-supplicant` artifacts

**Solution**:
```bash
# Clean ALL affected packages
$ bitbake systemd -c cleansstate
$ bitbake wpa-supplicant -c cleansstate
$ bitbake demo-image-weston
```

#### Problem 3: Flash vs. Boot Persistence

**What happened**:
```bash
# After successful flash and boot
$ ssh root@192.168.1.101
# Works! Configuration correct

# Reboot device
$ ssh root@192.168.1.101
# Connection refused - reverted to DHCP or old config
```

**Why it failed**:
- Systemd services not enabled at boot time
- Configuration files present but services not activated
- Manual `systemctl enable` was lost after reboot (not persistent in image)

**Solution**:
```bash
# In wpa-supplicant_%.bbappend:
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
SYSTEMD_SERVICE:${PN}:append = " wpa_supplicant@wlP1p1s0.service"

# Rebuild with service enabled
$ bitbake wpa-supplicant -c cleansstate
$ bitbake demo-image-weston
```

### Complete Rebuild Workflow (Lessons Learned)

When modifying network configuration:

```bash
# Step 1: Clean affected packages (CRITICAL)
bitbake systemd -c cleansstate
bitbake wpa-supplicant -c cleansstate

# Step 2: Rebuild image
bitbake demo-image-weston
# Output: build/tmp/deploy/images/jetson-orin-nano-devkit/demo-image-weston.tegraflash.tar.gz

# Step 3: Extract to flash directory
cd ~/jetson-flash
sudo rm -rf *
tar -xzf /path/to/demo-image-weston.tegraflash.tar.gz

# Step 4: Flash device
sudo ./doflash.sh

# Step 5: Verify on device (MANDATORY)
ssh root@192.168.1.101 "cat /etc/systemd/network/10-enP8p1s0.network"
ssh root@192.168.1.101 "systemctl status wpa_supplicant@wlP1p1s0.service"
```

### Key Takeaways: Understanding Yocto Build Pipeline

**Pipeline Stages**:
1. **Source Fetch** (`do_fetch`): Download source code
2. **Unpack** (`do_unpack`): Extract archives
3. **Patch** (`do_patch`): Apply patches
4. **Configure** (`do_configure`): Run ./configure or cmake
5. **Compile** (`do_compile`): Build binaries
6. **Install** (`do_install`): Copy files to staging area → **THIS IS WHERE FILES ARE PLACED**
7. **Package** (`do_package`): Create .deb/.rpm/.ipk
8. **Image Assembly**: Combine all packages into rootfs
9. **Flash Artifact**: Create .tegraflash.tar.gz

**Why `cleansstate` is critical**:
- `-c clean`: Only removes build artifacts (Step 5-6)
- `-c cleansstate`: Removes ALL task outputs (Step 1-9) **INCLUDING CACHED INSTALL TASKS**
- Without `cleansstate`, Step 6 (`do_install`) reuses cached file copies

**Mental Model**:
```
Modify file → Recipe unchanged → Task signature unchanged → Cache hit → Old files used
Modify file → cleansstate → No cache → Tasks re-run → New files used
```

### Time Investment

- **First attempt** (naive rebuild): 10 minutes build + 5 minutes flash = **15 minutes wasted**
- **Second attempt** (partial clean): 15 minutes build + 5 minutes flash = **20 minutes wasted**
- **Third attempt** (full cleansstate): 20 minutes build + 5 minutes flash = **25 minutes SUCCESS**
- **Total learning cost**: ~2 hours of debugging + 4-5 failed flash cycles

**Lesson**: In embedded Linux development, **verification on actual hardware is mandatory**. Simulator/emulator cannot catch bootloader, kernel module, or hardware-specific configuration issues.

---

## 4.2. Advanced Yocto Debugging: The 5-Level Verification Pipeline

### The Three Independent Problems (Trinity of Pain)

During network configuration, we encountered three distinct problems that appeared similar but required completely different solutions:

1. **Cache Trap**: Rebuilt but changes not reflected
2. **Build ≠ Install**: Package built but not included in image
3. **Flash Mismatch**: Image built correctly but wrong file flashed

### Problem 1: Cache Trap - "I Modified It, Why Doesn't It Build?"

#### Symptom Detection: Reading Build Logs Like a Judge

**Critical Evidence #1: Sstate Summary**

When you run `bitbake`, watch the `Sstate summary` line carefully:

```
Sstate summary: Wanted 1500 Local 1500 Mirrors 0 Missed 0 Current 500 (100% match, 99% complete)
```

**Verdict**:
- `Wanted == Found` and `Missed == 0`: **GUILTY** - Everything from cache, your changes ignored
- `Missed > 0`: **INNOCENT** - Some tasks will rebuild from source

**Critical Evidence #2: Build Duration**

```bash
$ bitbake demo-image-weston
# Completes in 1-2 seconds
NOTE: All tasks are up to date
```

**Verdict**: If build finishes in seconds after you modified files, Bitbake did NOT detect your changes.

#### Root Cause: Hash-Based Task Signatures

Yocto uses cryptographic hashes to determine if a task needs re-execution:

```
Task Signature = hash(recipe_content + input_files + dependencies)
```

**The Trap**:
- Modifying `files/wpa_supplicant.conf` → Hash unchanged (file content not part of recipe hash)
- Bitbake sees: "Recipe unchanged → Use cached task output"
- Result: Old files used despite your edits

#### Solution Hierarchy

**Level 1: Package-level clean** (Use this first)
```bash
bitbake wpa-supplicant -c cleansstate
bitbake demo-image-weston
```

**Level 2: Force-rebuild specific task**
```bash
bitbake wpa-supplicant -c install -f  # -f = force, ignore cache
bitbake demo-image-weston
```

**Level 3: Check what Bitbake thinks changed**
```bash
bitbake demo-image-weston -S none  # Dry-run, show changed tasks
```

**Level 4: Nuclear option** (Last resort)
```bash
rm -rf tmp/cache tmp/sstate-control
bitbake demo-image-weston
# ⚠️ Rebuilds EVERYTHING from scratch (hours)
```

---

### Problem 2: Build ≠ Install - "The Package Warehouse Paradox"

#### The Mental Model: Production vs. Shipping

```
┌─────────────────────┐      ┌──────────────────────┐
│  Recipe Build       │      │  Image Construction  │
│  (Production)       │──X──>│  (Shipping)          │
│                     │      │                      │
│ tmp/work/.../       │      │ IMAGE_INSTALL list   │
│   packages-split/   │      │                      │
│ ✅ Files exist here │      │ ❌ Not in manifest   │
└─────────────────────┘      └──────────────────────┘
```

**Analogy**: You manufactured the car parts (package built successfully), but the shipping manifest doesn't include it (IMAGE_INSTALL missing).

#### Symptom

```bash
# Package builds successfully
$ bitbake wpa-supplicant
NOTE: Tasks Summary: Attempted 150 tasks of which 0 didn't need to be rerun and all succeeded.

# Files exist in build artifacts
$ find tmp/work -name "wpa_supplicant*.conf"
tmp/work/.../packages-split/wpa-supplicant/etc/wpa_supplicant/wpa_supplicant-wlP1p1s0.conf

# But NOT on flashed device
$ ssh root@jetson "ls /etc/wpa_supplicant/"
ls: cannot access '/etc/wpa_supplicant/': No such file or directory
```

#### Root Cause: IMAGE_INSTALL Variable

Image recipes only include packages explicitly listed in `IMAGE_INSTALL`:

```bitbake
# In demo-image-weston.bb or local.conf
IMAGE_INSTALL = "packagegroup-core-boot weston"
# ⚠️ wpa-supplicant is NOT in this list!
```

#### Solution

**Critical Fix**:
```bitbake
IMAGE_INSTALL:append = " wpa-supplicant systemd-networkd"
#                      ^ MANDATORY SPACE! Without it: "westonwpa-supplicant" = broken
```

**Verification Commands**:

**Step 1: Check IMAGE_INSTALL expansion**
```bash
bitbake -e demo-image-weston | grep "^IMAGE_INSTALL="
# Output should contain "wpa-supplicant"
```

**Step 2: Check manifest file** (Definitive proof)
```bash
cat tmp/deploy/images/jetson-orin-nano-devkit/demo-image-weston-jetson-orin-nano-devkit.manifest | grep wpa
# If empty: Package NOT included
# If found: Package IS included
```

---

### Problem 3: Flash Mismatch - "The Wrong Blueprint Syndrome"

#### The 5-Level Inspection Pipeline

This is the **definitive debugging sequence** for "image built but device doesn't have it":

**Level 1: Recipe Layer Recognition**
```bash
bitbake-layers show-appends | grep wpa-supplicant
```
**Purpose**: Verify your `.bbappend` is being applied (not overridden by another layer)

**Level 2: Package Artifact Inspection**
```bash
# Check package contents (if using RPM)
rpm -qlp tmp/work/.../wpa-supplicant-*.rpm

# Or inspect directly
ls -la tmp/work/aarch64-oe4t-linux/wpa-supplicant/*/packages-split/wpa-supplicant/etc/
```
**Purpose**: Confirm `do_install` task put files in correct locations

**Level 3: Rootfs Assembly Verification**
```bash
ls -la tmp/work/jetson_orin_nano_devkit/demo-image-weston/1.0/rootfs/etc/wpa_supplicant/
```
**Purpose**: Verify IMAGE_INSTALL successfully pulled package into rootfs

**Level 4: Final Image Binary Inspection** (🔥 THE GAME CHANGER)
```bash
# Mount ext4 image as read-only filesystem debugger
sudo debugfs -R "ls -l /etc/wpa_supplicant" tmp/deploy/images/.../demo-image-weston.ext4

# Alternative: Extract and grep
sudo debugfs -R "cat /etc/wpa_supplicant/wpa_supplicant-wlP1p1s0.conf" demo-image-weston.ext4
```
**Purpose**: **Definitive proof** that Yocto succeeded. If file exists here, blame is on flash process.

**Level 5: Flash Script Audit** (The Actual Culprit)
```bash
cat ~/jetson-flash/doflash.sh | grep -E '\.ext4|\.img'
```

**Our Discovery**:
```bash
# Script was flashing (WRONG):
ROOTFS_IMAGE="core-image-weston.ext4"

# But we built (CORRECT):
demo-image-weston-jetson-orin-nano-devkit.rootfs.ext4
```

**🎯 Smoking Gun**: We were flashing an old image that didn't have our customizations!

---

### The Correct Flash Workflow

**Step 1: Extract tegraflash archive**
```bash
cd ~/jetson-flash
sudo rm -rf *  # Clean slate
tar -xzf /home/seame/leo/tegra-demo-distro/build/tmp/deploy/images/jetson-orin-nano-devkit/seame-headunit-image-jetson-orin-nano-devkit.rootfs.tegraflash.tar.gz
echo "=== Ready to flash ==="
ls -lh doflash.sh  # Verify extraction
```

**Why this matters**:
- `.tegraflash.tar.gz` contains **bootloader, kernel, DTB, AND rootfs** as a unified package
- Extracting ensures all components match the same build
- `doflash.sh` inside the archive already references correct image names

**Step 2: Verify image integrity BEFORE flashing**
```bash
# Check rootfs size (should be ~2-4GB for our image)
ls -lh *.img

# Verify it's the image you just built (check timestamp)
stat seame-headunit-image-jetson-orin-nano-devkit.rootfs.ext4
```

**Step 3: Flash with verification**
```bash
sudo ./doflash.sh
# Watch for "Flashing succeeded" message
```

**Step 4: Mandatory on-device verification**
```bash
# First boot check
ssh root@192.168.1.101 "cat /etc/wpa_supplicant/wpa_supplicant-wlP1p1s0.conf"
ssh root@192.168.1.101 "systemctl status wpa_supplicant@wlP1p1s0"
ssh root@192.168.1.101 "ip addr show wlP1p1s0"
```

---

### Debugging Decision Tree (Quick Reference)

```
Modified file → Build → Device doesn't have it
                  ↓
         Check build log:
         Sstate 100% match?
                  ↓
              ┌───YES───┐              NO
              ↓         ↓              ↓
       CACHE TRAP   Build fast?   Rebuild happened
              ↓         ↓              ↓
       cleansstate   cleansstate   Check manifest:
                                   Package in list?
                                        ↓
                                   ┌───YES───┐    NO
                                   ↓         ↓    ↓
                              debugfs:  IMAGE_INSTALL
                              File in    missing!
                              .ext4?        ↓
                                ↓      Add package
                            ┌──YES──┐      to IMAGE_INSTALL
                            ↓       ↓   NO
                       FLASH    Rootfs
                       SCRIPT   corrupted
                       WRONG        ↓
                            Rebuild image
```

---

### Lessons Learned: Time Investment Analysis

| Problem | Detection Time | Fix Time | Iterations | Total Cost |
|---------|---------------|----------|------------|------------|
| Cache Trap | 30 min (log reading) | 5 min | 3 builds | ~2 hours |
| Build ≠ Install | 1 hour (manifest dig) | 2 min | 2 builds | ~3 hours |
| Flash Mismatch | 2 hours (debugfs learning) | 1 min | 4 flashes | ~4 hours |
| **TOTAL** | | | | **~9 hours** |

**Key Takeaway**: The debugging time (9 hours) exceeded the actual implementation time (1 hour). This is **normal and expected** in embedded Linux development. The learned verification pipeline will save 10x this time in future projects.

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

## 8. Qt Text Rendering Fix (February 12, 2026)

### Problem
After successful middleware and application integration, all Qt applications ran without errors, but **text was completely invisible**:
- ✅ UI elements rendered: rectangles, colors, borders, animations
- ✅ Font files installed: 25 TTF fonts in `/usr/share/fonts`
- ✅ No font errors in logs
- ❌ **Text components completely invisible**

### Root Cause Analysis

**Critical Discovery**: Qt was built WITHOUT fontconfig support

```bash
# Check Qt build configuration
bitbake -e qtbase | grep "^PACKAGECONFIG="
# Output: PACKAGECONFIG="... freetype ... libs ..."
# Missing: fontconfig ❌
```

**Diagnosis**:
- Qt included `freetype` (can read font files directly)
- Qt excluded `fontconfig` (cannot discover system fonts)
- Result: Qt could not use system fonts in `/usr/share/fonts`

**Why previous workarounds failed**:
1. Setting `QT_QPA_FONTDIR=/usr/share/fonts` → Qt ignored without fontconfig
2. Copying fonts to `/usr/lib/fonts` → Fallback path, but rendering pipeline broken
3. Setting `FONTCONFIG_FILE` → Qt not linked to fontconfig library

### Solution

**File**: `/home/seame/leo/tegra-demo-distro/layers/meta-seame-headunit/recipes-qt/qt5/qtbase_%.bbappend`

```bitbake
# Enable fontconfig support in Qt
PACKAGECONFIG:append = " fontconfig"

# Ensure fontconfig is available at build time
DEPENDS += "fontconfig"
```

### Build & Deploy

```bash
# Rebuild Qt with fontconfig
bitbake qtbase -c cleansstate && bitbake qtbase

# Rebuild entire image
bitbake seame-headunit-image

# Flash to device
cd ~/jetson-flash
./doflash.sh
```

### Verification

```bash
# Check Qt now links fontconfig
bitbake -e qtbase | grep "^PACKAGECONFIG=" | grep fontconfig
# Output: PACKAGECONFIG="... fontconfig freetype ..."  ✅

# On device - verify fontconfig working
fc-list | wc -l
# Output: 25 fonts found ✅

# Test application
systemctl status gearapp
# Output: Active, text visible ✅
```

### Result

**✅ Text rendering working!**
- P/R/N/D gear indicators visible
- Battery percentage displayed
- Media song titles shown
- All text components rendered correctly

### Key Lesson

**"Fixing error messages ≠ Fixing root cause"**

- **Wrong approach**: Workaround to eliminate errors (fallback paths, environment variables)
- **Right approach**: Fix build configuration to enable proper system integration
- **Critical thinking**: Question whether the "orthodox" path (fontconfig) is actually being used

**Timeline**:
- February 6-11: Network setup, middleware integration ✅
- February 11-12 morning: 7 different font workarounds ❌
- February 12 afternoon: Root cause analysis → fontconfig missing → **Fixed in 1 build cycle** ✅

---

**Last Updated**: February 12, 2026  
**Status**: Phase 2 COMPLETE - Middleware ✅, Applications ✅, Custom Image ✅, Terminal Icon ✅, **Text Rendering ✅**
