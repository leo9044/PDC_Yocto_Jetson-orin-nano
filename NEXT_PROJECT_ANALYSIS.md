# 다음 프로젝트 기술 검토 보고서

> **작성일**: 2026-02-26  
> **대상**: 기존 시스템 기반 SDV 기술 스택 이식 계획  
> **목적**: 계획 단계에서 예방 가능한 문제를 사전에 식별하고 설계 결정의 근거를 마련

---

## 목차

1. [현재 시스템 기준점 (Baseline)](#1-현재-시스템-기준점)
2. [컨테이너 격리](#2-컨테이너-격리)
3. [OTA 업데이트](#3-ota-업데이트)
4. [로우레벨 (MCU FOTA)](#4-로우레벨-mcu-fota)
5. [기타 고려 사항](#5-기타-고려-사항)
6. [취업 경쟁력 평가](#6-취업-경쟁력-평가)
7. [최종 권고 및 우선순위](#7-최종-권고-및-우선순위)

---

## 1. 현재 시스템 기준점

### 1.1 하드웨어 구성

```
[ NVIDIA Jetson Orin Nano ]  (ECU2 / HPC 역할)
  ├── CPU: Arm Cortex-A78AE × 6cores (1.7GHz)
  ├── GPU: 1024-core NVIDIA Ampere
  ├── RAM: 8GB LPDDR5
  ├── Storage: eMMC (bootloader/kernel) + microSD (rootfs)  ← 중요
  ├── Display: DP-2 (HU) + DP-3 (IC) via MST Hub
  ├── Network: enP8p1s0 (192.168.1.101)
  └── OS: Custom Yocto Linux (Scarthgap, L4T R36.4.4)

[ Raspberry Pi 4 ]  (ECU1 / Zonal ECU 역할)
  ├── CPU: Cortex-A72 × 4cores
  ├── RAM: 4/8GB
  ├── Storage: microSD (전체)  ← 중요
  ├── Network: eth0 (192.168.1.100)
  └── OS: Raspberry Pi OS (or Ubuntu)

[ PiRacer ]  (물리적 차량 플랫폼)
  ├── PCA9685 PWM (0x40: steering, 0x60: throttle)
  ├── INA219 battery monitor (0x41)
  └── ShanWan USB Gamepad
```

### 1.2 소프트웨어 스택

```
┌─── Jetson (ECU2) ───────────────────────────────────────┐
│  Layer 5 (Apps)    : 9개 Qt5 QML 앱                     │
│  Layer 4 (UI)      : Wayland/Weston 3-level compositor  │
│  Layer 3 (IPC)     : vsomeip 3.5.8 + CommonAPI 3.2.4    │
│  Layer 2 (Runtime) : systemd, Weston compositor         │
│  Layer 1 (OS)      : Yocto Scarthgap + L4T R36.4.4      │
└─────────────────────────────────────────────────────────┘
           │ SOME/IP over Ethernet (192.168.1.0/24)
┌─── RPi (ECU1) ──────────────────────────────────────────┐
│  VehicleControlECU : vsomeip service provider           │
│  Hardware drivers  : pigpio, I2C (PCA9685, INA219)      │
│  OS                : Raspberry Pi OS / Ubuntu           │
└─────────────────────────────────────────────────────────┘
```

### 1.3 핵심 제약: 스토리지 구조

**Jetson Orin Nano의 스토리지 레이아웃은 이후 모든 OTA 설계의 출발점이다.**

```
eMMC (온보드):
  ├── QSP partition : QSPI 부트로더 (CBoot, MB1, MB2...)
  ├── LNX           : Linux 커널 + DTB
  ├── APP           : rootfs (현재 우리 이미지가 여기 들어감)
  └── ...기타 TEE/TOS 파티션

microSD (외장):
  └── rootfs 대용으로 사용 가능 (TNSPEC_BOOTDEV_DEFAULT = "mmcblk1p1")
      ← local.conf에서 현재 이렇게 설정되어 있음
```

**결론**: 현재 우리는 rootfs를 microSD에 올리는 구조. 
이는 A/B 파티셔닝 없이도 SD카드 통째로 교체가 가능하나, 
프로덕션급 OTA에서는 문제가 된다 (자세한 내용 → OTA 섹션).

---

## 2. 컨테이너 격리

### 2.1 결론 요약

| 방법 | 가능성 | 노력 | 권장 여부 |
|------|--------|------|-----------|
| Hypervisor (KVM/Xen) | ❌ Jetson Orin Nano 미지원 수준 | 매우 높음 | 배제 |
| Docker (OCI container) | ✅ meta-virtualization 이미 있음 | 중간 | 추천 |
| systemd-nspawn | ✅ systemd 내장 | 낮음 | 가능 |
| Linux namespaces/cgroups 직접 구현 | ✅ 학습 목적 최적 | 중간 | 추천 |

### 2.2 핵심 기회: meta-virtualization 이미 bblayers.conf에 있다

```bash
# 현재 bblayers.conf 분석 결과:
BBLAYERS ?= " \
  ...
  /home/seame/leo/tegra-demo-distro/layers/meta-virtualization \  ← 이미 존재!
  ...
"
```

`meta-virtualization`에는 이미 다음이 준비되어 있다:
- `docker-moby` (Docker Engine)
- `crun` (OCI 컨테이너 런타임, Docker 대안 - 더 가벼움)
- `containerd`
- `cgroup-lite`

**즉, IMAGE_INSTALL에 추가만 하면 된다. 새 레이어 추가 불필요.**

### 2.3 컨테이너화 대상 정의

**HU 도메인 (leo 담당)**:
```
컨테이너 분리 전: systemd 서비스로 직접 실행
  weston.service
    └── hu-mainapp-compositor.service
        ├── gearapp.service
        ├── mediaapp.service
        ├── ambientapp.service
        └── homescreenapp.service

컨테이너 분리 후 (목표):
  weston.service  (호스트)
    └── HU-container (cgroup v2 제한)
        ├── GearApp  (namespace 격리)
        ├── MediaApp
        └── ...
```

### 2.4 ⚠️ 예상 문제점: Wayland + 컨테이너

**가장 큰 기술적 장벽이다. 반드시 사전 검토 필요.**

**문제**: Wayland는 Unix socket(`/run/wayland-0`, `/run/wayland-1` 등)으로 통신.
컨테이너는 기본적으로 자체 mount namespace를 가져서 호스트의 socket에 접근 불가.

**해결 방법**:

```bash
# 방법 1: Socket을 volume으로 바인드 마운트
docker run \
  -v /run/wayland-0:/run/wayland-0 \
  -v /tmp/xdg:/tmp/xdg \
  -e WAYLAND_DISPLAY=wayland-0 \
  -e XDG_RUNTIME_DIR=/tmp/xdg \
  my-hu-app

# 방법 2: --network=host + XDG_RUNTIME_DIR 공유
# 방법 3: Weston-in-container (nested compositor 구조와 연계 가능)
```

**우리 기존 아키텍처와의 호환성**:
- 현재 HU_MainApp_Compositor가 `wayland-1`에서 동작
- IC_Compositor가 `wayland-2`에서 동작
- **Wayland socket을 컨테이너에 바인드 마운트하는 방식으로 기존 구조 유지 가능**
- 단, GPU 가속이 필요하면 `/dev/dri/` 도 전달해야 함

```bash
docker run \
  -v /run/wayland-0:/run/wayland-0 \
  -v /tmp/xdg:/tmp/xdg \
  --device /dev/dri/card0 \        # GPU 접근
  --device /dev/dri/renderD128 \   # EGL render node
  -e WAYLAND_DISPLAY=wayland-0 \
  -e XDG_RUNTIME_DIR=/tmp/xdg \
  -e QT_QPA_PLATFORM=wayland \
  hu-container
```

### 2.5 ⚠️ 예상 문제점: vsomeip + 컨테이너

vsomeip의 routing manager는 `/tmp/vsomeip.lck` 파일 락과 Unix socket을 사용.

```bash
# vsomeip 컨테이너 구성 시 필요한 공유:
docker run \
  --network=host \                  # SOME/IP는 IP multicast 사용 → host 네트워크 필요
  -v /tmp/vsomeip.lck:/tmp/vsomeip.lck \
  -v /tmp/vsomeip:/tmp/vsomeip \    # routing manager IPC
  gearapp-container
```

**주의**: `--network=host`를 쓰면 네트워크 격리가 없어짐.
진정한 격리를 원하면 vsomeip routing manager를 컨테이너 밖(호스트)에서 실행하고,
앱 컨테이너는 routing manager에 연결하는 방식으로 설계해야 한다.

### 2.6 ⚠️ 예상 문제점: Yocto + Docker 이미지 관리

Docker를 Yocto 이미지 안에서 쓰는 것과 Docker로 Yocto 빌드 결과물을 패키징하는 것은 다르다.

**선택지**:
```
[A] 호스트 OS(Yocto)에 Docker 설치 → 앱을 Docker 컨테이너로 실행
    장점: 기존 Yocto 빌드 인프라 활용
    단점: Yocto rootfs가 무거워짐 (~500MB Docker daemon)

[B] 앱을 OCI 이미지로 빌드 → Yocto rootfs에 embed
    장점: 프로덕션 접근법
    단점: 빌드 파이프라인 복잡성 증가

[C] crun + minimal container (Docker 없이)
    장점: 가볍고, 학습 목적에 더 적합
    단점: Docker hub의 이미지 재사용 불가
```

**권장**: 학습 목적으로는 **[A] Docker 설치** 후 컨테이너 실험. 
추후 OTA와 연계 시 **[B]** 방향으로 발전.

### 2.7 cgroups v2 확인 필요

```bash
# Jetson에서 확인:
cat /proc/filesystems | grep cgroup
# 또는
mount | grep cgroup
# 또는
ls /sys/fs/cgroup/

# L4T 5.15 커널에서 cgroup v2 활성화 여부 확인
cat /sys/fs/cgroup/cgroup.controllers
```

L4T R36.4.4 (커널 5.15 기반)는 cgroup v2를 지원하지만,
Yocto 이미지의 커널 config에서 활성화 여부 확인 필요.

```bitbake
# Yocto에서 cgroup v2 활성화:
# local.conf 또는 machine.conf에 추가
APPEND:append = " systemd.unified_cgroup_hierarchy=1"
```

### 2.8 역할 분담 관점에서의 검토 (leo: HU, chang: IC)

**잘 나뉜 분담이다.** 이유:
- HU 앱과 IC 앱은 서로 다른 Wayland compositor를 사용 (`wayland-1` vs `wayland-2`)
- vsomeip에서 서로 다른 service를 consume → 충돌 없음
- 두 컨테이너의 격리가 독립적이라 병렬 개발 가능

**주의점**: IC 컨테이너(chang)와 HU 컨테이너(leo)가 공유하는 리소스:
- vsomeip routing manager (호스트에서 실행해야 함)
- Weston compositor (wayland-0, 호스트)
- 네트워크 namespace (multicast routing)

---

## 3. OTA 업데이트

### 3.1 스코프 결정: 무엇을 업데이트할 것인가?

**Scope 1 (앱/서비스 레벨)** vs **Scope 2 (OS/펌웨어 레벨)**의 차이는 근본적이다.

```
Scope 1 (앱 업데이트):
  변경 대상: GearApp, MediaApp, VehicleControlECU 바이너리
  방법: 파일 복사 + systemd restart
  위험도: 낮음 (앱만 교체, OS 무결)
  A/B 필요?: No (앱 단위 롤백 가능)
  예시: Tesla에서 게임 앱 추가, 주행 파라미터 업데이트

Scope 2 (OS/펌웨어 업데이트):
  변경 대상: Linux 커널, rootfs 전체, 부트로더
  방법: A/B 파티셔닝 필수 (실패 시 벽돌 방지)
  위험도: 높음 (잘못되면 부팅 불가)
  A/B 필요?: Yes, 강력 권장
  예시: 자동차 OEM의 ECU 펌웨어 리콜 업데이트
```

**권장**: 두 스코프 모두 구현. 단, 순서를 분리해서:
1. 먼저 Scope 1(앱) OTA 구현 → 검증
2. 그 다음 Scope 2(OS) OTA로 확장

### 3.2 Jetson OTA: 우리 스택의 현실

**Jetson Orin Nano의 저장소 구조가 OTA 설계를 제약한다.**

```
현재 파티션 레이아웃 (flash_t234_qspi_sd.xml 기반):

QSPI Flash (온보드, ~32MB):
  ├── BCT (Boot Control Table)
  ├── MB1 (MicroBoot 1 - secure monitor)
  ├── MB2 (MicroBoot 2)
  ├── CPH (CPU boot header)
  ├── TOS (Trusted OS)
  ├── EKS (Encryption Key Storage)
  ├── LNX (Linux kernel + DTB)  ← 커널 업데이트 시 여기
  └── APP (rootfs 시작점)

microSD (외장):
  └── rootfs 파티션  ← 현재 우리 이미지
```

**핵심 문제**: QSPI Flash는 용량이 매우 작다(~32MB). A/B 파티셔닝이 거의 불가능.
rootfs(~수GB)를 A/B로 관리하려면 microSD 또는 eMMC에 2개 파티션이 필요.

**실현 가능한 A/B 구조**:
```
microSD 파티션 구성 (수동으로 repartitioning 필요):
  ├── /dev/mmcblk1p1 → rootfs_A  (현재 부팅 중)
  ├── /dev/mmcblk1p2 → rootfs_B  (대기 파티션)
  └── /dev/mmcblk1p3 → data      (영구 데이터)

부트 선택: QSPI의 LNX 파티션에서 커널 파라미터로 rootfs 지정
  root=/dev/mmcblk1p1  (A)
  root=/dev/mmcblk1p2  (B)
```

### 3.3 NVIDIA Jetson의 네이티브 OTA: BUP (Bootloader Update Package)

`orin-nano.inc` 파일에서 이미 확인됨:
```bitbake
TEGRA_BUPGEN_SPECS ?= "fab=000;boardsku=0005;boardrev=;chipsku=00:00:00:D5;bup_type=bl \
                        fab=000;boardsku=0005;boardrev=;bup_type=kernel"
```

NVIDIA는 `tegraflash`와 함께 **BUP (Bootloader Update Package)** 포맷을 지원.
이는 QSPI 영역(MB1, MB2, 커널)의 OTA 업데이트를 위한 NVIDIA 전용 메커니즘이다.

**활용 가능성**: BUP는 커널/부트로더 업데이트에 사용 가능하나 학습 곡선이 있음.
초기에는 rootfs OTA에 집중하고 BUP는 나중에.

### 3.4 OTA 구현 옵션 비교

| 방법 | A/B 지원 | Yocto 통합 | 복잡도 | 추천 |
|------|----------|------------|--------|------|
| **OSTree** | ✅ 네이티브 | meta-updater (AGL 사용) | 높음 | Scope 2에 최적 |
| **RAUC** | ✅ 네이티브 | meta-rauc | 중간 | **강력 추천** |
| **Mender** | ✅ 네이티브 | meta-mender | 중간 | 괜찮음, 상용화 |
| **SWUpdate** | ✅ 지원 | meta-swupdate | 중간 | 유연함 |
| 직접 구현 (rsync/scp) | ❌ | 불필요 | 낮음 | Scope 1 학습용 |

**RAUC를 추천하는 이유**:
- 독일 Pengutronix 개발, 자동차 산업 표준 수준
- meta-rauc Yocto 레이어 제공 (Scarthgap 호환)
- A/B 파티션 + 롤백 자동화 내장
- 서명 검증(X.509) 지원 → 보안 시연 가능
- Mender보다 오픈소스 친화적

### 3.5 역할 분담별 OTA 구체적 접근

#### leo 담당: Raspberry Pi (Zonal ECU) OTA

**RPi는 Jetson보다 OTA 구현이 훨씬 쉽다.**

```
RPi 저장소 구조 (단순):
  /dev/mmcblk0:
    ├── p1: boot (FAT32, 256MB)  - 커널/부트로더
    └── p2: rootfs (ext4, 나머지)

A/B를 위한 repartitioning 목표:
  /dev/mmcblk0:
    ├── p1: boot (공유)
    ├── p2: rootfs_A (현재)
    ├── p3: rootfs_B (업데이트 대기)
    └── p4: data (영구)
```

**VehicleControlECU 앱 업데이트 (Scope 1)**:
```bash
# 간단한 앱 OTA 구현 예시:
# Jetson이 업데이트 파일을 받아 RPi에 전달

# OTA Gateway (Jetson) → Zonal ECU (RPi)
scp new_VehicleControlECU root@192.168.1.100:/tmp/
ssh root@192.168.1.100 "systemctl stop vehiclecontrol-ecu && \
  cp /tmp/new_VehicleControlECU /usr/bin/VehicleControlECU && \
  systemctl start vehiclecontrol-ecu"
```

**구현 순서 제안**:
1. 스크립트 기반 앱 업데이트 (scp + systemctl) → 개념 검증
2. RAUC 적용 → A/B rootfs 업데이트
3. Jetson을 OTA 게이트로 사용하는 파이프라인 구축

#### chang 담당: Jetson Orin Nano (Infotainment) OTA

**Jetson은 더 복잡하다. 주의사항:**

**문제 1: 현재 microSD rootfs 구조**
- 현재는 단일 파티션. A/B를 위해 microSD를 repartitioning해야 함
- `parted`로 온라인 파티셔닝은 rootfs가 마운트된 상태에서 위험
- **해결책**: 초기 이미지 플래시 시 A/B 파티션 레이아웃으로 미리 설정

**문제 2: `tegraflash`는 full flash이지 incremental OTA가 아님**
- `doflash.sh`는 전체 플래시 → OTA에 부적합
- OTA는 rootfs 파티션만 업데이트해야 함

**문제 3: GPU 드라이버 통합 패키지**
- L4T의 NVIDIA 그래픽 드라이버는 커널 모듈과 userspace가 버전이 맞아야 함
- rootfs만 업데이트하면 커널 모듈 버전 불일치 가능
- **해결책**: 커널과 rootfs를 함께 업데이트하거나, 드라이버를 rootfs 외부로 분리

### 3.6 공동 작업: Jetson을 OTA 게이트웨이로

```
[Cloud/Server]
     │
     │ HTTPS (TLS)
     ▼
[Jetson OTA Gateway] (192.168.1.101)
     │ 업데이트 파일 다운로드
     │ 서명 검증
     │ 업데이트 오케스트레이션
     │
     ├── 자신의 인포테인먼트 업데이트 (chang)
     │
     └── RPi에 업데이트 전달 (leo)
           │
           ▼
       [RPi Zonal ECU] (192.168.1.100)
```

**구현 방법론**:
```python
# OTA 게이트웨이 pseudo-code (Python/Go로 구현)
class OTAGateway:
    def receive_update_package(self, url):
        # 1. HTTPS로 업데이트 다운로드
        download(url, "/tmp/update.raucb")
        # 2. 서명 검증
        verify_signature("/tmp/update.raucb", "cert.pem")
        # 3. 대상 ECU 판별
        target = determine_target("/tmp/update.raucb")
        
        if target == "jetson":
            # 자신에게 RAUC 적용
            rauc_install("/tmp/update.raucb")
        elif target == "rpi":
            # RPi에 전달
            push_to_zonal_ecu("192.168.1.100", "/tmp/update.raucb")
```

### 3.7 ⚠️ 중요: OTA 구현 전 필수 작업 목록

**Jetson 측 (chang)**:
- [ ] microSD A/B 파티션 레이아웃 설계 (parted 스크립트)
- [ ] RAUC slot 설정 (`/etc/rauc/system.conf`)
- [ ] meta-rauc Yocto 레이어 추가 (Scarthgap 호환 확인)
- [ ] 서명용 X.509 인증서 생성
- [ ] 부트 카운터 + 롤백 로직 (u-boot 또는 RAUC 내장)

**RPi 측 (leo)**:
- [ ] RPi 이미지 A/B 파티셔닝
- [ ] RAUC 또는 직접 스크립트 선택
- [ ] VehicleControlECU 업데이트 절차 설계
- [ ] 업데이트 중 하드웨어 안전 처리 (모터 정지 등)

---

## 4. 로우레벨 (MCU FOTA)

### 4.1 구조 목표

```
현재:          RPi → PiRacer (I2C 직접)
목표: RPi → 텔레칩스 MCU → PiRacer (실차 구조 모방)

실차 구조:
  HPC/Zonal ECU (RPi) 
       │ UART/CAN
       ▼
  MCU (텔레칩스)  ← AUTOSAR MCAL 수준 추상화
       │ PWM/ADC/GPIO
       ▼
  Actuators/Sensors (모터, 서보, 센서)
```

### 4.2 텔레칩스 MCU 연동 시 예상 과제

**통신 인터페이스 선택**:
```
RPi ↔ MCU 가능한 인터페이스:
  - UART (TX/RX): 가장 단순, 디버깅 용이
  - SPI: 고속, GPIO 필요
  - CAN: 실차에 가장 가까움 (MCP2515 모듈 사용)
  - I2C: 이미 사용 중 (PCA9685 등)

권장: UART 먼저 검증 → CAN으로 발전
```

**프로토콜 설계**:
```c
// MCU ↔ RPi 프로토콜 예시
typedef struct {
    uint8_t  start_byte;   // 0xAA
    uint8_t  cmd;          // 0x01: gear, 0x02: speed, 0x03: steering
    uint16_t value;        // 명령 값
    uint8_t  checksum;     // XOR
    uint8_t  end_byte;     // 0x55
} MCUCommand;
```

**FOTA (Firmware Over-The-Air) for MCU**:
```
업데이트 경로:
  Cloud → Jetson (Gateway) → RPi → MCU (UART bootloader)

MCU bootloader 요구사항:
  - UART 부트로더 지원 (대부분의 ARM Cortex-M에서 지원)
  - 텔레칩스 MCU의 부트로더 모드 진입 방법 확인 필요
  - CRC 검증 내장

RPi에서 MCU 플래싱:
  - stm32flash, esptool 같은 호스트 툴
  - 텔레칩스 MCU에 맞는 툴 확인 필요
```

### 4.3 ⚠️ 중요 검토 사항

1. **텔레칩스 MCU 사양 확인 필수**: FOTA 지원 여부, 부트로더 존재 여부
2. **물리적 연결 핀맵**: RPi GPIO와 MCU UART/SPI 핀 연결도 사전 설계
3. **전원 관리**: MCU 플래싱 중 전원 차단 시나리오 (watchdog 필수)
4. **PiRacer와의 호환성**: 기존 I2C 제어를 MCU로 대체할 때 하드웨어 수정 범위

---

## 5. 기타 고려 사항

### 5.1 디스플레이 고민

**현재 구조의 복잡성**:
```
Weston (wayland-0)
  ├── IC_Compositor (wayland-2)  → IC 앱들
  └── HU_MainApp_Compositor (wayland-1) → HU 앱들
```

**컨테이너 격리 관점에서의 디스플레이 단순화 검토**:

| 구조 | 장점 | 단점 |
|------|------|------|
| 현재 3-layer compositor | 완전 분리 | 컨테이너화 복잡 |
| 단순화: Weston만 사용, 앱 직접 연결 | 컨테이너화 용이 | HU/IC 분리 약해짐 |
| DRM/KMS 직접 제어 | 최고 성능 | 학습 곡선 매우 높음 |

**결론**: OTA/컨테이너 실험에 집중하려면 **디스플레이 스택 단순화가 유리**.
그러나 기존 작업을 버리는 건 비효율적이므로,
**컨테이너 내에서 기존 Wayland socket 공유 방식으로 유지** 권장.

**디스플레이 교체 시 어댑터 문제**:
- 현재 MST Hub (DisplayPort Multi-Stream) 사용
- 다른 디스플레이(HDMI)로 교체 시 `DP to HDMI` 어댑터 필요
- 해상도/타이밍 설정은 Weston의 `weston.ini`에서 조정 가능
- 단, `weston.ini`는 현재 Yocto 이미지에 하드코딩되어 있어 OTA 연계 고려 필요

### 5.2 네트워크 보안 (OTA 관련)

현재 네트워크는 192.168.1.0/24 로컬만 사용. OTA 게이트웨이 구현 시:

```
필수 보안 요소:
  1. TLS 1.3으로 다운로드 채널 암호화
  2. 업데이트 패키지 서명 검증 (X.509)
  3. Rollback protection (downgrade attack 방지)
  4. 버전 관리 및 manifest 파일

선택적 보안 요소:
  - Secure Boot (Jetson은 지원하나 설정 복잡)
  - TPM 기반 키 관리
```

### 5.3 vsomeip와 컨테이너/OTA의 상호작용

**OTA 업데이트 중 vsomeip 서비스 처리**:
```bash
# 안전한 업데이트 절차:
# 1. 서비스 graceful shutdown 순서 (역순)
systemctl stop gearapp mediaapp ambientapp homescreenapp
systemctl stop hu-mainapp-compositor ic-compositor
systemctl stop vsomeip-routing-manager  # 마지막에 중단

# 2. 업데이트 적용
rauc install /tmp/update.raucb

# 3. 재부팅 → systemd가 순서대로 재시작
reboot
```

**VehicleControlECU(RPi) 업데이트 중 Jetson 앱 처리**:
- RPi 서비스가 내려가면 vsomeip service 0x1234 미응답
- Jetson의 앱들이 service discovery timeout으로 오류 발생
- **해결책**: CommonAPI의 availability handler 구현으로 graceful degradation

---

## 6. 취업 경쟁력 평가

### 6.1 SDV 기술 스택 vs VLM/AI 접근 비교

**질문**: "이 프로젝트가 취업 시장에서 유의미한가? VLM 같은 게 더 눈에 띄지 않나?"

**결론 먼저**: **SDV 스택이 더 경쟁력 있다. 특히 자동차 업계에서는.**

**SDV 스택의 강점**:
```
[현대모비스, 현대오토에버, LG전자 VS, 만도, 보쉬코리아 관점]

- OTA: 2024년 이후 모든 OEM의 최우선 과제. 실제 구현 경험 = 즉시 전력
- 컨테이너 격리: SDV 아키텍처의 핵심 (AUTOSAR Adaptive는 컨테이너 기반)
- vsomeip/CommonAPI: COVESA 표준. 이걸 아는 신입은 극히 드물다
- Yocto: Embedded Linux의 업계 표준. 다룰 수 있는 신입 희귀
- 하드웨어 + 소프트웨어 연계: "로우레벨 이해하는 SW 인재" = 수요 높음

[취업 시장 현실]
신입이 VLM/LLM으로 접근하면:
  - 경쟁자: 대학원생, AI 전공자, 빅테크 인턴 경험자들
  - 차별화 어려움: 모두가 fine-tuning, RAG 등을 한다

신입이 SDV 스택으로 접근하면:
  - 경쟁자: 거의 없음 (Yocto + OTA + vsomeip 조합을 아는 신입은 극히 드물다)
  - 차별화: 즉각적 ("Jetson에서 OTA 구현해봤습니다"는 면접관이 직접 물어본다)
```

**3학년으로서의 시간 배분 제안**:
```
지금 (3학년):
  - SDV 스택 완성 (OTA + 컨테이너) → 포트폴리오 핵심
  - AI/ML은 선택과목 정도

나중 (4학년 또는 졸업 후):
  - VLM 등 최신 AI → in-cabin AI (운전자 모니터링, 음성 명령)
  - 이걸 SDV 스택 위에 얹으면 최강 조합
```

**VLM이 오히려 유리한 케이스**: 네이버, 카카오, 스타트업 등 인터넷 기업의 자동차 서비스 팀.
하지만 자동차 OEM/1차 부품사에서는 SDV 경험이 압도적으로 유리하다.

---

## 7. 최종 권고 및 우선순위

### 7.1 작업 우선순위 (권장 순서)

```
Phase 1 (기반 정비, 1-2주):
  [ ] Yocto 이미지에 Docker/crun 추가 (meta-virtualization 이미 있음)
  [ ] cgroup v2 활성화 확인 및 설정
  [ ] microSD A/B 파티션 레이아웃 설계

Phase 2 (컨테이너화, 2-3주):
  [ ] leo: HU 앱 컨테이너화 (Wayland socket 바인드 마운트)
  [ ] chang: IC 앱 컨테이너화
  [ ] vsomeip routing manager를 호스트에 유지하는 구조 확립
  [ ] 컨테이너 리소스 제한 (cgroup: CPU/메모리 쿼터)

Phase 3 (앱 레벨 OTA, 3-4주):
  [ ] leo: RPi 앱 업데이트 스크립트 (scp + systemctl)
  [ ] chang: Jetson 컨테이너 이미지 업데이트 (docker pull 방식)
  [ ] 공동: Jetson OTA 게이트웨이 (HTTP 서버 + 다운로드 + 배포)

Phase 4 (OS 레벨 OTA, 4-6주):
  [ ] RAUC 도입 (meta-rauc Yocto 레이어)
  [ ] A/B 파티션 기반 전체 rootfs 업데이트
  [ ] 서명 검증 + 롤백 자동화

Phase 5 (로우레벨, 여유 시 진행):
  [ ] 텔레칩스 MCU 연결 (UART)
  [ ] MCU 프로토콜 설계
  [ ] FOTA 파이프라인 (RPi → MCU)
```

### 7.2 설계 원칙 (프로젝트 전체에 적용)

1. **점진적 복잡도**: 스크립트 → 컨테이너 → OTA → 보안 순서로 쌓아올려라
2. **가역성 확보**: 모든 변경에 롤백 경로를 설계. OTA는 실패 시 자동 롤백이 기본
3. **기존 스택 보존**: vsomeip, Qt, Wayland는 이미 동작 중. 이걸 컨테이너 안으로 이동하는 것이지 교체가 아님
4. **검증 가능한 마일스톤**: "OTA 성공"이 아니라 "업데이트 후 GearApp이 정상 작동"처럼 앱 레벨로 검증

### 7.3 빠른 참조: 각 기술별 핵심 키워드

| 기술 | Yocto 레이어 | 핵심 명령 | 주요 문서 |
|------|-------------|-----------|----------|
| Docker | meta-virtualization (이미 있음) | `IMAGE_INSTALL += "docker-moby"` | docs.docker.com |
| RAUC | meta-rauc (추가 필요) | `rauc install bundle.raucb` | rauc.readthedocs.io |
| cgroup v2 | kernel config | `systemd.unified_cgroup_hierarchy=1` | kernel.org/doc/cgroup-v2 |
| Wayland in container | - | `-v /run/wayland-0:/run/wayland-0` | wayland.freedesktop.org |
| NVIDIA BUP | meta-tegra (이미 있음) | `tegra-bup-payload` | developer.nvidia.com |

---

**문서 버전**: 1.0  
**다음 검토 시점**: Phase 1 완료 후 (설계 가정 재검증 필요)
