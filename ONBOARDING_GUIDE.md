# SEA:ME Project Onboarding Guide

**Welcome to the Team!** 🚗

This guide provides a comprehensive overview of what we've built, how the system is architected, and how to get started with our automotive infotainment platform.

---

## 📋 Table of Contents

1. [Project Overview](#project-overview)
2. [System Architecture](#system-architecture)
3. [Technology Stack](#technology-stack)
4. [Hardware Setup](#hardware-setup)
5. [Software Components](#software-components)
6. [Development Environment](#development-environment)
7. [Build & Deployment](#build--deployment)
8. [Project Timeline & Achievements](#project-timeline--achievements)
9. [Repository Structure](#repository-structure)
10. [Getting Started Checklist](#getting-started-checklist)
11. [Resources & References](#resources--references)

---

## 📖 Project Overview

### What is SEA:ME?

**SEA:ME (Software Engineering in Automotive and Mobility Ecosystems)** is a comprehensive automotive software engineering program focusing on building real-world embedded systems for vehicles.

Our team has completed three major projects:

1. **DES Instrument Cluster** - Real-time vehicle dashboard displaying speed, gear, battery status
2. **DES Head Unit** - Infotainment system with media player, ambient lighting, gear control
3. **DES PDC System** - Park Distance Control using ultrasonic sensors

### Our Implementation

We've built a **centralized automotive architecture** that mimics modern vehicle designs, distributed across:

- **NVIDIA Jetson Orin Nano** (Central Compute Unit) - Running Yocto Linux
- **Raspberry Pi 4** (Zonal ECU) - Vehicle control and sensor interface
- **Dual Display Setup** - Head Unit (touchscreen) + Instrument Cluster (dashboard)

**Key Achievement**: Full-stack automotive platform with production-grade middleware (vsomeip/CommonAPI), custom Yocto Linux, and Qt5-based applications.

---

## 🏗️ System Architecture

### Hardware Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    NVIDIA Jetson Orin Nano                       │
│                  (Central Compute / Infotainment)                │
│                                                                  │
│  ┌─────────────────────┐          ┌─────────────────────┐      │
│  │   Head Unit Apps    │          │ Instrument Cluster  │      │
│  │  • GearApp          │          │ • Speedometer       │      │
│  │  • MediaApp         │          │ • BatteryMeter      │      │
│  │  │  • AmbientApp       │          │ • GearState         │      │
│  │  • HomeScreenApp    │          │ • RPM Gauge         │      │
│  └─────────────────────┘          └─────────────────────┘      │
│           │                                   │                  │
│           └───────────────┬───────────────────┘                  │
│                           │                                      │
│                ┌──────────▼──────────┐                           │
│                │  vsomeip Middleware │                           │
│                └──────────┬──────────┘                           │
│                           │                                      │
│                  ┌────────▼────────┐                             │
│                  │  Ethernet (SOME/IP)                           │
│                  └────────┬────────┘                             │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                      Ethernet Switch (192.168.1.0/24)
                                  │
┌─────────────────────────────────▼───────────────────────────────┐
│                    Raspberry Pi 4 (Zonal ECU)                    │
│                  IP: 192.168.1.100 (ECU1)                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           VehicleControlECU Service                      │  │
│  │  • Motor Control (speed commands)                        │  │
│  │  • Servo Control (steering)                              │  │
│  │  • Sensor Interface (speed, ultrasonic)                  │  │
│  │  • CAN Bus Communication                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                  ┌────────▼────────┐                             │
│                  │    CAN Bus      │                             │
│                  └────────┬────────┘                             │
│                           │                                      │
│  ┌────────────────────────▼──────────────────────────┐          │
│  │  PiRacer Hardware (Arduino-based sensors)         │          │
│  │  • Speed Sensor                                   │          │
│  │  • Ultrasonic Sensors (PDC)                       │          │
│  │  • Motor Controller                               │          │
│  │  • Servo Controller                               │          │
│  └───────────────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────────────────┘
```

### Software Architecture (Jetson Orin Nano)

```
┌─────────────────────────────────────────────────────────────┐
│                      User Space                             │
│                                                             │
│  ┌──────────────────┐        ┌──────────────────┐          │
│  │  Head Unit Apps  │        │  IC Apps         │          │
│  │  (wayland-1)     │        │  (wayland-2)     │          │
│  └────────┬─────────┘        └────────┬─────────┘          │
│           │                           │                     │
│  ┌────────▼──────────────────────────▼─────────┐           │
│  │      Qt5 Application Framework              │           │
│  │  • QtWayland (nested compositor support)    │           │
│  │  • QtQuick/QML (UI rendering)               │           │
│  └────────┬────────────────────────────────────┘           │
│           │                                                 │
│  ┌────────▼──────────────────────────────────────┐         │
│  │  CommonAPI / vsomeip Middleware              │         │
│  │  • Service 0x1234:0x5678 (VehicleControl)   │         │
│  │  • Multicast routing (224.0.0.0/4)          │         │
│  └────────┬────────────────────────────────────┘         │
│           │                                               │
│  ┌────────▼──────────────────────────────────────┐       │
│  │  Wayland Compositor Stack                    │       │
│  │  Layer 1: Weston (wayland-0) - Root          │       │
│  │  Layer 2: IC_Compositor (wayland-2)          │       │
│  │  Layer 3: HU_MainApp_Compositor (wayland-1)  │       │
│  └────────┬────────────────────────────────────┘       │
│           │                                             │
├───────────▼─────────────────────────────────────────────┤
│                    Kernel Space                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Tegra L4T R36.4.4 (Linux for Tegra)           │   │
│  │  • Mesa/EGL (GPU acceleration)                  │   │
│  │  • Network stack (vsomeip over TCP/IP)         │   │
│  │  • systemd (service management)                 │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Communication Flow

```
User Input (Gear Change)
    │
    ▼
GearApp (Qt5 QML)
    │
    ▼
CommonAPI Proxy (Generated Code)
    │
    ▼
vsomeip Runtime
    │
    ▼
Ethernet (SOME/IP Protocol)
    │
    ▼
VehicleControlECU (Raspberry Pi)
    │
    ▼
Motor/Servo Control
    │
    ▼
Physical Hardware Response
```

---

## 🛠️ Technology Stack

### Platform

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Central ECU** | NVIDIA Jetson Orin Nano | - | Main compute unit |
| **Zonal ECU** | Raspberry Pi 4 Model B | - | Vehicle control interface |
| **Build System** | Yocto Project | Scarthgap (5.0 LTS) | Custom Linux distribution |
| **BSP Layer** | meta-tegra (OE4T) | L4T R36.4.4 | Jetson hardware support |
| **OS** | Custom Yocto Linux | Kernel 5.15 | Embedded operating system |

### Middleware

| Component | Version | Purpose |
|-----------|---------|---------|
| **vsomeip** | 3.5.8 | SOME/IP protocol implementation |
| **CommonAPI Core** | 3.2.4 | IPC abstraction layer |
| **CommonAPI SomeIP Runtime** | 3.2.4 | CommonAPI ↔ vsomeip binding |
| **Boost** | 1.83 | C++ libraries (vsomeip dependency) |

### Application Framework

| Component | Version | Purpose |
|-----------|---------|---------|
| **Qt Framework** | 5.15.13 | Application framework |
| **QtWayland** | 5.15 | Wayland compositor + client |
| **QtQuick/QML** | 2.15 | Declarative UI language |
| **QtQuickControls2** | 2.15 | Modern UI controls |
| **QtMultimedia** | 5.15 | Audio/video playback |

### Display System

| Component | Purpose |
|-----------|---------|
| **Weston** | Root Wayland compositor (wayland-0) |
| **IC_Compositor** | Nested compositor for IC apps (wayland-2) |
| **HU_MainApp_Compositor** | Nested compositor for HU apps (wayland-1) |
| **MST Hub** | Dual DisplayPort output (DP-2: HU, DP-3: IC) |

### Development Tools

| Tool | Purpose |
|------|---------|
| **CMake** | Build system generator |
| **GCC** | 13.2 (cross-compilation) |
| **debugfs** | ext4 filesystem inspection |
| **bitbake** | Yocto build engine |
| **tegraflash** | Jetson flashing utility |

---

## 🖥️ Hardware Setup

### Bill of Materials (BOM)

| Item | Model | Quantity | Purpose |
|------|-------|----------|---------|
| **Central ECU** | NVIDIA Jetson Orin Nano Developer Kit | 1 | Main compute unit |
| **Zonal ECU** | Raspberry Pi 4 Model B (4GB+) | 1 | Vehicle control ECU |
| **HU Display** | 7" Touchscreen (HDMI/DP) | 1 | Head Unit interface |
| **IC Display** | 7" LCD (HDMI/DP) | 1 | Instrument Cluster display |
| **MST Hub** | DisplayPort Multi-Stream Transport | 1 | Dual display enablement |
| **Network** | Gigabit Ethernet Switch | 1 | ECU interconnect |
| **Storage (Jetson)** | microSD Card (64GB+) | 1 | Rootfs storage |
| **Storage (RPi)** | microSD Card (32GB+) | 1 | OS + applications |
| **Power Supply** | 5V/4A USB-C (Jetson) | 1 | Jetson power |
| **Power Supply** | 5V/3A USB-C (RPi) | 1 | RPi power |
| **CAN Interface** | MCP2515 CAN Bus Module | 1 | CAN communication |
| **Sensors** | HC-SR04 Ultrasonic (x4) | 4 | Park Distance Control |
| **Vehicle Platform** | PiRacer Standard Kit | 1 | Hardware integration platform |

### Network Configuration

**Jetson Orin Nano (ECU2)**:
```
Interface: enP8p1s0
IP Address: 192.168.1.101/24
Gateway: 192.168.1.1
DNS: 8.8.8.8, 8.8.4.4
Role: Service consumer (Head Unit + IC apps)
```

**Raspberry Pi 4 (ECU1)**:
```
Interface: eth0
IP Address: 192.168.1.100/24
Gateway: 192.168.1.1
Role: Service provider (VehicleControlECU)
```

### Display Configuration

**Dual Display via MST Hub**:
- **DP-2** → Head Unit Display (1024x600)
- **DP-3** → Instrument Cluster Display (800x480)

**Compositor Mapping**:
```
Weston (wayland-0) → Physical displays
  ├─ IC_Compositor (wayland-2) → DP-3 (IC display)
  │   ├─ Speedometer_app
  │   ├─ BatteryMeter_app
  │   └─ GearState_app
  │
  └─ HU_MainApp_Compositor (wayland-1) → DP-2 (HU display)
      ├─ GearApp
      ├─ MediaApp
      ├─ AmbientApp
      └─ HomeScreenApp
```

---

## 💻 Software Components

### Applications (9 Total)

#### Head Unit Applications (5 apps)

| App | Function | Tech Stack |
|-----|----------|------------|
| **HU_MainApp_Compositor** | Root compositor for HU apps | Qt5, QtWayland Compositor API |
| **GearApp** | Gear selection (P/R/N/D) | Qt5 QML + CommonAPI client |
| **MediaApp** | USB media playback | Qt5 QML + QtMultimedia |
| **AmbientApp** | Interior lighting control | Qt5 QML + GPIO control |
| **HomeScreenApp** | Main navigation menu | Qt5 QML |

#### Instrument Cluster Applications (4 apps)

| App | Function | Tech Stack |
|-----|----------|------------|
| **IC_Compositor** | Root compositor for IC apps | Qt5, QtWayland Compositor API |
| **Speedometer** | Real-time speed display | Qt5 QML + CommonAPI client |
| **BatteryMeter** | Battery level gauge | Qt5 QML + CommonAPI client |
| **GearState** | Current gear indicator | Qt5 QML + CommonAPI client |

### Middleware Layer

**vsomeip Routing Manager**:
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

**Service Definition (FIDL)**:
```fidl
package commonapi.VehicleControl

interface VehicleControl {
    version { major 1 minor 0 }
    
    method setGear {
        in {
            UInt8 gear  // 0=P, 1=R, 2=N, 3=D
        }
    }
    
    method setSpeed {
        in {
            UInt16 speed_kmh
        }
    }
    
    attribute UInt8 currentGear readonly
    attribute UInt16 currentSpeed readonly
    attribute UInt8 batteryLevel readonly
}
```

### System Services

**Startup Order** (systemd dependencies):
```
1. weston.service                    # Root compositor
2. vsomeip-routing-manager.service  # Middleware
3. hu-mainapp-compositor.service    # HU compositor
4. ic-compositor.service            # IC compositor
5. Application services             # All apps
```

**Critical Service Configuration**:
```ini
# Example: GearApp service
[Unit]
Description=SEAME Gear Selection App
After=hu-mainapp-compositor.service

[Service]
Type=simple
Environment="WAYLAND_DISPLAY=wayland-1"
Environment="VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_gearapp.json"
ExecStart=/usr/bin/GearApp
Restart=on-failure

[Install]
WantedBy=graphical.target
```

---

## 🧰 Development Environment

### Prerequisites

**Host System Requirements**:
- OS: Ubuntu 22.04 LTS or later
- RAM: 16GB minimum (32GB recommended)
- Disk: 100GB+ free space
- CPU: Multi-core (8+ cores recommended)

### Software Installation

```bash
# Essential build tools
sudo apt-get update
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev pylint xterm \
    make xsltproc docbook-utils fop dblatex xmlto \
    git-core libncurses5-dev libssl-dev libreadline-dev

# Qt5 development (for local testing)
sudo apt-get install -y \
    qt5-qmake qtbase5-dev qtdeclarative5-dev \
    qtquickcontrols2-5-dev qtwayland5 qtmultimedia5-dev

# Cross-compilation tools
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
```

### Repository Setup

```bash
# Clone main repository
git clone https://github.com/leo9044/DES_Head-Unit.git
cd DES_Head-Unit

# Initialize Yocto workspace
cd /home/seame/leo/tegra-demo-distro
source ./setup-env --machine jetson-orin-nano-devkit --distro tegrademo

# Verify layers
bitbake-layers show-layers
# Expected: meta-tegra, meta-middleware, meta-seame-headunit
```

### IDE Setup (VS Code Recommended)

**Extensions**:
- C/C++ (Microsoft)
- CMake Tools
- QML (Qt Company)
- Yocto Project BitBake

**Settings** (`.vscode/c_cpp_properties.json`):
```json
{
    "configurations": [
        {
            "name": "ARM64",
            "includePath": [
                "${workspaceFolder}/**",
                "/home/seame/leo/tegra-demo-distro/build/tmp/sysroots-components/aarch64/qtbase/usr/include/**"
            ],
            "defines": [],
            "compilerPath": "/usr/bin/aarch64-linux-gnu-gcc",
            "cStandard": "c17",
            "cppStandard": "c++17"
        }
    ]
}
```

---

## 🔨 Build & Deployment

### Local Development Build (x86_64)

**Quick Test on Host PC**:
```bash
cd /home/seame/leo/DES_Head-Unit/app/GearApp
./build.sh  # Automated build script

# Manual build
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
./GearApp
```

### Yocto Production Build (ARM64)

**Full System Build** (takes 4-8 hours first time):
```bash
cd /home/seame/leo/tegra-demo-distro
source ./setup-env --machine jetson-orin-nano-devkit --distro tegrademo

# Build custom image
bitbake seame-headunit-image

# Output location
ls build/tmp/deploy/images/jetson-orin-nano-devkit/
# → seame-headunit-image-jetson-orin-nano-devkit.rootfs.tegraflash.tar.gz
```

**Incremental Build** (after code changes):
```bash
# Rebuild specific application
bitbake gearapp -c cleansstate
bitbake gearapp

# Rebuild entire image
bitbake seame-headunit-image
```

### Flashing Jetson Orin Nano

**Preparation**:
```bash
cd ~/jetson-flash
sudo rm -rf *
tar -xzf /path/to/seame-headunit-image-jetson-orin-nano-devkit.rootfs.tegraflash.tar.gz
ls -lh doflash.sh  # Verify extraction
```

**Enter Recovery Mode**:
1. Power off Jetson
2. Hold **RECOVERY** button (near power)
3. Connect USB-C to host PC
4. Power on Jetson (keep holding RECOVERY for 2 seconds)
5. Verify: `lsusb | grep -i nvidia`
   - Should show: `NVIDIA Corp. APX`

**Flash**:
```bash
sudo ./doflash.sh
# Expected: "Flashing succeeded" after ~5-10 minutes
```

**First Boot Verification**:
```bash
# Wait ~30 seconds after boot
ssh root@192.168.1.101

# Check displays
cat /sys/class/drm/card*/status
# Expected: 2x "connected"

# Check services
systemctl status weston
systemctl status vsomeip-routing-manager
systemctl status hu-mainapp-compositor
systemctl status gearapp
```

---

## 📅 Project Timeline & Achievements

### Phase 1: Foundation (Week 1-2)
**Objectives**: Platform setup, network configuration  
**Completed**:
- ✅ Yocto Scarthgap build environment
- ✅ Jetson Orin Nano L4T R36.4.4 integration
- ✅ Static IP configuration (systemd-networkd)
- ✅ SSH server deployment
- ✅ Dual display MST hub setup

**Key Challenges**:
- Yocto sstate cache behavior (9 hours debugging)
- Network configuration persistence
- Solution: Developed 5-level verification pipeline

### Phase 2: Middleware Integration (Week 3-4)
**Objectives**: IPC layer, CommonAPI code generation  
**Completed**:
- ✅ vsomeip 3.5.8 build recipe
- ✅ CommonAPI Core 3.2.4 (GCC 13 compatibility patch)
- ✅ CommonAPI SomeIP Runtime 3.2.4
- ✅ FIDL interface definition
- ✅ Stub/Proxy code generation

**Key Challenges**:
- GCC 13 removed transitive includes (`<string>` missing)
- Solution: Patched CommonAPI Core Types.hpp

### Phase 3: Application Development (Week 5-6)
**Objectives**: Qt5 applications, Wayland compositors  
**Completed**:
- ✅ 9 applications built and integrated
- ✅ 3-layer Wayland compositor architecture
- ✅ systemd service orchestration
- ✅ Custom Yocto image (`seame-headunit-image`)

**Key Challenges**:
- Qt text rendering invisible (7 attempts)
- Root cause: qtbase built without fontconfig
- Solution: Added `PACKAGECONFIG:append = " fontconfig"`

### Phase 4: External Communication (Week 7)
**Objectives**: vsomeip multicast routing, ECU1 ↔ ECU2 IPC  
**Completed**:
- ✅ Multicast route configuration (224.0.0.0/4)
- ✅ VehicleControlECU service provider (ECU1)
- ✅ Client applications (ECU2)
- ✅ End-to-end gear change demonstration

**Key Challenges**:
- systemd service startup race conditions
- IC app window positioning
- Solution: Proper `Before=`/`After=` dependencies

### Current Status (February 2026)
**Achievements**:
- ✅ All 3 SEA:ME projects completed (IC, HU, PDC)
- ✅ Production-grade middleware stack
- ✅ Custom Yocto distribution
- ✅ Centralized ECU architecture
- ✅ Documentation: 850+ lines (CUSTOMIZATION_LOG.md)

---

## 📂 Repository Structure

```
DES_Head-Unit/
├── app/                           # Application source code
│   ├── AmbientApp/               # Ambient lighting control
│   │   ├── src/
│   │   ├── qml/
│   │   ├── CMakeLists.txt
│   │   └── build.sh
│   ├── GearApp/                  # Gear selection interface
│   ├── MediaApp/                 # USB media player
│   ├── HomeScreenApp/            # Main menu
│   ├── HU_MainApp/               # HU compositor
│   ├── IC_app/                   # IC applications
│   │   ├── BatteryMeter/
│   │   ├── GearState/
│   │   └── Speedometer/
│   ├── VehicleControlECU/        # ECU1 service provider
│   └── config/                   # vsomeip configuration files
│
├── commonapi/                    # Middleware code generation
│   ├── fidl/                     # FIDL interface definitions
│   ├── generated/                # Auto-generated stub/proxy
│   │   ├── core/                 # CommonAPI core stubs
│   │   └── someip/               # vsomeip bindings
│   └── generate_code.sh
│
├── deps/                         # Third-party dependencies
│   ├── capicxx-core-runtime/
│   ├── capicxx-someip-runtime/
│   └── vsomeip/
│
├── meta/                         # Yocto layers
│   ├── meta-middleware/          # vsomeip, CommonAPI recipes
│   │   ├── conf/layer.conf
│   │   └── recipes-comm/
│   │       ├── vsomeip/
│   │       ├── commonapi-core/
│   │       ├── commonapi-someip/
│   │       └── commonapi-generated/
│   │
│   └── meta-seame-headunit/      # Application recipes
│       ├── conf/layer.conf
│       ├── recipes-apps/
│       │   ├── gearapp/
│       │   ├── mediaapp/
│       │   ├── ic-compositor/
│       │   └── ...
│       ├── recipes-middleware/
│       │   └── vsomeip-service/  # systemd service
│       ├── recipes-qt/qt5/
│       │   └── qtbase_%.bbappend # fontconfig fix
│       └── recipes-core/images/
│           └── seame-headunit-image.bb
│
├── docs/                         # Project documentation
│   ├── CHANGELOG_20251204_VSOMEIP_EXTERNAL_COMM.md
│   ├── ECU2_TESTING_GUIDE.md
│   ├── JETSON_INTEGRATION_PLAN.md
│   └── VSOMEIP_EXTERNAL_COMMUNICATION_PLAN.md
│
├── run-x86-all.sh               # Local development script
├── run-rpi-all.sh               # Raspberry Pi deployment
└── README.md                    # Project overview
```

**External Repository** (Yocto Build Environment):
```
/home/seame/leo/tegra-demo-distro/
├── layers/
│   ├── meta-tegra/              # NVIDIA Jetson BSP (OE4T)
│   ├── meta-middleware/         # Symlink to DES_Head-Unit/meta/meta-middleware
│   └── meta-seame-headunit/     # Symlink to DES_Head-Unit/meta/meta-seame-headunit
├── build/
│   ├── conf/
│   │   ├── local.conf           # Build configuration
│   │   └── bblayers.conf        # Layer configuration
│   └── tmp/
│       └── deploy/images/       # Build artifacts
└── CUSTOMIZATION_LOG.md         # Detailed build documentation
```

---

## ✅ Getting Started Checklist

### For New Developers

**Day 1: Environment Setup**
- [ ] Clone DES_Head-Unit repository
- [ ] Install Ubuntu 22.04 build dependencies
- [ ] Setup Yocto build environment
- [ ] Build local x86_64 test application
- [ ] Read CUSTOMIZATION_LOG.md (sections 1-3)

**Day 2: Hardware Familiarization**
- [ ] Identify Jetson Orin Nano, Raspberry Pi, displays
- [ ] Verify network connectivity (192.168.1.101 ↔ 192.168.1.100)
- [ ] SSH into Jetson: `ssh root@192.168.1.101`
- [ ] Check running services: `systemctl list-units --type=service`
- [ ] Explore display outputs: `cat /sys/class/drm/card*/status`

**Day 3: Code Walkthrough**
- [ ] Understand Qt5 QML structure (`app/GearApp/qml/`)
- [ ] Review CommonAPI client code (`app/GearApp/src/`)
- [ ] Examine FIDL definition (`commonapi/fidl/VehicleControl.fidl`)
- [ ] Study vsomeip configuration (`app/config/vsomeip_*.json`)
- [ ] Trace systemd service dependencies

**Week 2: Build & Deploy**
- [ ] Modify GearApp UI (change button color)
- [ ] Rebuild application: `bitbake gearapp -c cleansstate && bitbake gearapp`
- [ ] Rebuild image: `bitbake seame-headunit-image`
- [ ] Flash Jetson (recovery mode + doflash.sh)
- [ ] Verify changes on device

**Week 3: Feature Development**
- [ ] Add new QML component
- [ ] Implement CommonAPI method call
- [ ] Test end-to-end communication
- [ ] Debug with systemd logs: `journalctl -u gearapp`

---

## 📚 Resources & References

### Official Documentation

**Yocto Project**:
- [Yocto Quick Start](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html)
- [BitBake User Manual](https://docs.yoctoproject.org/bitbake/)
- [meta-tegra Layer](https://github.com/OE4T/meta-tegra)

**NVIDIA Jetson**:
- [Jetson Orin Nano Developer Kit](https://developer.nvidia.com/embedded/jetson-orin-nano-developer-kit)
- [L4T Documentation](https://docs.nvidia.com/jetson/archives/r36.4/DeveloperGuide/index.html)
- [JetPack 6.2.1 Release Notes](https://developer.nvidia.com/embedded/jetpack-sdk-621)

**Qt Framework**:
- [Qt 5.15 Documentation](https://doc.qt.io/qt-5/)
- [QML Language](https://doc.qt.io/qt-5/qmlapplications.html)
- [Qt Wayland Compositor](https://doc.qt.io/qt-5/qtwaylandcompositor-index.html)

**Middleware**:
- [vsomeip GitHub](https://github.com/COVESA/vsomeip)
- [CommonAPI C++ Tutorial](https://github.com/COVESA/capicxx-core-tools/wiki)
- [SOME/IP Protocol Specification](https://www.autosar.org/fileadmin/standards/R22-11/FO/AUTOSAR_PRS_SOMEIPProtocol.pdf)

### Project-Specific Documentation

**In this Repository**:
- [CUSTOMIZATION_LOG.md](../tegra-demo-distro/CUSTOMIZATION_LOG.md) - Complete build history and debugging guide
- [ECU2_TESTING_GUIDE.md](docs/ECU2_TESTING_GUIDE.md) - Jetson testing procedures
- [VSOMEIP_EXTERNAL_COMMUNICATION_PLAN.md](docs/VSOMEIP_EXTERNAL_COMMUNICATION_PLAN.md) - IPC architecture

**SEA:ME Project Guides**:
- [DES_Instrument-Cluster README](https://github.com/SEA-ME/DES_Instrument-Cluster/blob/main/README.md)
- [DES_Head-Unit README](https://github.com/SEA-ME/DES_Head-Unit)
- [DES_PDC-System README](https://github.com/SEA-ME/DES_PDC-System)

### Community Support

**Forums & Mailing Lists**:
- [Yocto Project Mailing List](https://lists.yoctoproject.org/g/yocto)
- [NVIDIA Jetson Forums](https://forums.developer.nvidia.com/c/agx-autonomous-machines/jetson-embedded-systems/)
- [Qt Forum](https://forum.qt.io/)

**Team Contacts**:
- Technical Lead: [GitHub @leo9044](https://github.com/leo9044)
- Repository: [DES_Head-Unit](https://github.com/leo9044/DES_Head-Unit)
- Yocto Build Repo: [PDC_Yocto_Jetson-orin-nano](https://github.com/leo9044/PDC_Yocto_Jetson-orin-nano)

---

## 🎯 Next Steps

### Immediate Priorities

1. **Familiarize with codebase** - Read this guide, clone repositories, explore code
2. **Setup development environment** - Install dependencies, build test applications
3. **Hands-on hardware** - Power on system, verify services, test applications
4. **First contribution** - Fix small bug or add minor feature

### Advanced Topics (After Onboarding)

- **CAN Bus Integration** - Connect speed sensor via MCP2515
- **PDC System** - Ultrasonic sensor Arduino interface
- **Performance Tuning** - Qt QML optimization, vsomeip latency reduction
- **Safety Features** - Watchdog timers, fault recovery
- **OTA Updates** - Over-the-air system updates with OSTree

### Learning Path Recommendations

**Week 1-2**: Yocto fundamentals, Qt5 basics  
**Week 3-4**: CommonAPI/vsomeip IPC  
**Week 5-6**: Wayland compositor architecture  
**Week 7+**: Independent feature development

---

## 🙏 Acknowledgments

**Technologies Used**:
- [Yocto Project](https://www.yoctoproject.org/) - Embedded Linux build system
- [meta-tegra (OE4T)](https://github.com/OE4T/meta-tegra) - NVIDIA Jetson BSP layer
- [vsomeip (COVESA)](https://github.com/COVESA/vsomeip) - SOME/IP middleware
- [CommonAPI (COVESA)](https://github.com/COVESA/) - IPC abstraction
- [Qt Project](https://www.qt.io/) - Application framework

**Inspired By**:
- SEA:ME Program ([Software Engineering in Automotive & Mobility](https://www.42wolfsburg.de/sea-me/))
- Modern automotive E/E architectures (Tesla, Rivian, Lucid)

---

**Last Updated**: February 25, 2026  
**Document Version**: 1.0  
**Maintained By**: SEA:ME Team Leo

---

**Questions?** Open an issue in the [DES_Head-Unit repository](https://github.com/leo9044/DES_Head-Unit/issues) or contact the team! 🚀
