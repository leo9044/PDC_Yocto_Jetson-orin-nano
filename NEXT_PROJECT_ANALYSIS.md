# 다음 프로젝트 기술 검토 보고서

> **작성일**: 2026-02-26  
> **대상**: 기존 시스템 기반 SDV 기술 스택 이식 계획  
> **목적**: 계획 단계에서 예방 가능한 문제를 사전에 식별하고 설계 결정의 근거를 마련

---

## 목차

1. [현재 시스템 기준점 (Baseline)](#1-현재-시스템-기준점)
2. [컨테이너 격리](#2-컨테이너-격리)
3. [OTA 업데이트](#3-ota-업데이트)
4. [기타 고려 사항](#4-기타-고려-사항)
5. [최종 권고 및 우선순위](#5-최종-권고-및-우선순위)

---

## 1. 현재 시스템 기준점

### 1.1 하드웨어 구성

```
[ NVIDIA Jetson Orin Nano ]  (ECU2 / HPC 역할)
  ├── CPU: Arm Cortex-A78AE × 6cores (1.7GHz)
  ├── GPU: 1024-core NVIDIA Ampere
  ├── RAM: 8GB LPDDR5
  ├── Storage: eMMC (bootloader/kernel) + microSD (rootfs)  ← 중요
  ├── Display: DP → DP-to-MiniDP → MST Hub → HDMI → MiniHDMI → Elecrow 13.3" 4K (단일)
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

#### 🔑 우리 프로젝트에서 컨테이너화의 진짜 의의

컨테이너를 **"격리 도구"** 로만 이해하면 우리 시스템에서는 의미 없어 보인다.
vsomeip(`--network=host`)와 Wayland 소켓 공유 때문에 네트워크/디스플레이 격리는
구조적으로 불가능하기 때문이다.

그러나 컨테이너의 본질적 가치는 세 가지다:

| 가치 | 우리 프로젝트 해당 여부 | 구체적 의미 |
|------|------------------------|-------------|
| **네트워크 격리** | ❌ vsomeip 멀티캐스트로 불가 | — |
| **파일시스템 격리** | △ 런타임 소켓은 공유, 바이너리는 격리 | 라이브러리 충돌 방지 |
| **자원 경계 (cgroup)** | ✅ **핵심** | HU OOM이 IC에 전파 차단 |
| **이미지 단위 배포** | ✅ **핵심** | OTA 단위 = 이미지 태그, 롤백 가능 |
| **개발 독립성** | ✅ **핵심** | leo(HU) / chang(IC) 책임 분리 |
| **오케스트레이션** | ✅ **핵심** | 컨테이너 재시작·순서·OTA 롤백 자동화 |

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

**확정 구조: 앱별 단독 컨테이너 + IC/HU 그룹 분리**

```
[호스트 — 절대 컨테이너화 안 함]
  weston.service                  ← Wayland 인프라
  vsomeip-routing-manager.service ← SOME/IP 인프라

[IC 그룹 — chang 담당, cgroup memory=256m]
  speedometer-app        → docker: ic-speedometer:버전
  batterymeter-app       → docker: ic-batterymeter:버전
  gearstate-app          → docker: ic-gearstate:버전
  이미지: 각각 독립 → chang이 IC 이미지만 빌드/OTA

[HU 그룹 — leo 담당, cgroup memory=512m]
  unified-compositor     → docker: hu-compositor:버전
  gearapp                → docker: hu-gearapp:버전
  homescreenapp          → docker: hu-homescreen:버전
  mediaapp               → docker: hu-media:버전
  ambientapp             → docker: hu-ambient:버전
  이미지: 각각 독립 → leo가 HU 이미지만 빌드/OTA
```

> **왜 앱별 단독 컨테이너인가?**
> HU 4개를 하나의 compose 덩어리로 묶으면 gearapp 하나를 업데이트해도
> 덩어리 전체를 재배포해야 한다. 이미지 단위 배포의 이점이 사라진다.
> 앱마다 이미지가 독립되어야 `docker load hu-gearapp:1.0.1`로 gearapp만 교체 가능.
> docker-compose.yml은 **실행 편의**를 위한 것이지 이미지 단위와 무관하다.

### 2.4 ⚠️ 예상 문제점: Wayland + 컨테이너

**가장 큰 기술적 장벽이다. 반드시 사전 검토 필요.**

**문제**: Wayland는 Unix socket으로 통신한다. 모든 소켓이 `XDG_RUNTIME_DIR=/run/user/1000` 안에 위치한다.
컨테이너는 기본적으로 자체 mount namespace를 가져서 호스트의 socket에 접근 불가.

#### 실제 소켓 번호 (서비스 파일에서 직접 확인)

> **주의**: 이 번호들은 서비스 파일과 QML 소스코드에서 직접 확인한 값이다.
> 직관적으로 Weston이 `wayland-0`을 쓸 것 같지만 **실제는 다르다.**

```
소켓 경로: /run/user/1000/wayland-N  (XDG_RUNTIME_DIR=/run/user/1000)

wayland-1 : Weston이 열고 대기  ← IC/HU 두 compositor가 여기에 CLIENT로 연결
wayland-2 : IC_Compositor가 생성  ← IC앱 3개가 여기에 연결
wayland-3 : HU_MainApp_Compositor가 생성  ← HU앱 4개가 여기에 연결

근거:
  ic-compositor_1.0.bb:         WAYLAND_DISPLAY=wayland-1 (클라이언트: Weston 연결)
  ic-compositor main.qml:       socketName: "wayland-2"  (서버: IC앱용)
  hu-mainapp-compositor.service: WAYLAND_DISPLAY=wayland-1 (클라이언트: Weston 연결)
  compositor_modular.qml:       socketName: "wayland-3"  (서버: HU앱용)
  batterymeter/speedometer/gearstate: WAYLAND_DISPLAY=wayland-2
  gearapp/mediaapp/ambientapp/homescreenapp: WAYLAND_DISPLAY=wayland-3
```

**전체 Wayland 계층 구조**:
```
┌────────────────────────────────────────────┐
│  Weston          ← wayland-1 소켓 생성     │
│    ├── IC_Compositor (클라이언트 wayland-1) │
│    │     └── wayland-2 소켓 생성           │
│    │           ├── BatteryMeter            │
│    │           ├── Speedometer             │
│    │           └── GearState              │
│    └── HU_Compositor (클라이언트 wayland-1)│
│          └── wayland-3 소켓 생성           │
│                ├── GearApp                │
│                ├── MediaApp               │
│                ├── AmbientApp             │
│                └── HomeScreenApp          │
└────────────────────────────────────────────┘
```

#### 컨테이너화를 위한 올바른 volume mount

**HU 앱 컨테이너 (leo 담당)**:
```bash
# ❌ 잘못된 방법 (wayland-0은 우리 시스템에 존재하지 않는다):
docker run -v /run/user/1000/wayland-0:/run/user/1000/wayland-0 ...

# ✅ 올바른 방법: XDG_RUNTIME_DIR 전체를 마운트
docker run \
  -v /run/user/1000:/run/user/1000 \
  --user 1000:1000 \
  -e WAYLAND_DISPLAY=wayland-3 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  --device /dev/dri/card0 \
  --device /dev/dri/renderD128 \
  -e QT_QPA_PLATFORM=wayland \
  hu-gearapp-container

# HU Compositor 컨테이너 (wayland-1 연결 → wayland-3 생성):
docker run \
  -v /run/user/1000:/run/user/1000 \
  --user 1000:1000 \
  -e WAYLAND_DISPLAY=wayland-1 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  --device /dev/dri/card0 \
  --device /dev/dri/renderD128 \
  hu-compositor-container
```

**IC 앱 컨테이너 (chang 담당)**:
```bash
docker run \
  -v /run/user/1000:/run/user/1000 \
  --user 1000:1000 \
  -e WAYLAND_DISPLAY=wayland-2 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  --device /dev/dri/card0 \
  --device /dev/dri/renderD128 \
  ic-speedometer-container
```

#### ⚠️ 추가 제약사항: 컨테이너 User/UID 문제

**모든 서비스에 `User=weston` (UID=1000)이 설정되어 있다.**

```
# HU 서비스 파일들에서 확인:
User=weston
Group=weston
Environment="XDG_RUNTIME_DIR=/run/user/1000"
```

이로 인해:

1. **Wayland 소켓 권한**: `/run/user/1000/wayland-*` 소켓은 UID=1000 소유
   → 컨테이너는 반드시 `--user 1000:1000`으로 실행하거나 이미지 내에 UID=1000 사용자를 생성해야 함

2. **소켓 대기 스크립트**: HU앱 서비스에는 다음 구문이 있다:
   ```bash
   # gearapp.service, mediaapp.service 등 HU앱 ExecStartPre:
   ExecStartPre=/bin/sh -c 'for i in $(seq 1 10); do \
     test -S /run/user/1000/wayland-3 && break || sleep 1; done'
   ```
   컨테이너가 `/run/user/1000`을 volume mount하지 않으면
   이 루프가 10초 후 실패하고 서비스가 시작되지 않는다.
   → **`/run/user/1000` 디렉토리 전체를 volume으로 마운트하는 것이 가장 안전**

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

#### ⚠️ 추가 이슈: `enP8p1s0` 인터페이스 이름 하드코딩

**vsomeip-routing-manager.service의 ExecStartPre에 인터페이스 이름이 박혀 있다:**
```bash
ExecStartPre=/sbin/ip route add 224.0.0.0/4 dev enP8p1s0
```

컨테이너 내부에서는 기본적으로 `eth0` 또는 `veth*` 형태의 가상 인터페이스가 보인다.
`enP8p1s0`는 호스트 전용 네트워크 인터페이스 이름이므로, 컨테이너에서 이 라우팅 명령이 실패한다.

**해결책**:
```bash
# 옵션 A (권장): routing manager를 호스트에서만 실행 (컨테이너 밖)
# 앱 컨테이너들은 --network=host로 라우팅 매니저에 접근

# 옵션 B: vsomeip 설정의 인터페이스 이름을 환경변수로 파라미터화
# vsomeip-routing-manager.json의 "unicast" 필드도 확인 필요:
#   "unicast" : "192.168.1.101"  ← 컨테이너 내부 IP와 다를 수 있음
```

**결론**: vsomeip routing manager는 **반드시 호스트에서 실행**해야 한다.
앱 컨테이너는 routing manager 클라이언트로만 동작하고, `--network=host`로 실제 네트워크 접근.

### 2.6 ⚠️ 추가 이슈: vehiclecontrolmock bb 파일의 하드코딩 경로

**`meta-middleware/recipes-comm/vehiclecontrolmock/vehiclecontrolmock_1.0.bb`에 chang의 로컬 경로가 하드코딩되어 있다:**

```bitbake
EXTERNALSRC = "/home/seame/ChangGit2/DES_Head-Unit/app/VehicleControlMock"
EXTERNALSRC_BUILD = "${EXTERNALSRC}/build"
EXTRA_OECMAKE += "-DCOMMONAPI_GEN_DIR=/home/seame/ChangGit2/DES_Head-Unit/commonapi/generated"
```

**문제점**:
- leo의 머신(`/home/seame/leo/`)에서 빌드하면 경로 없음으로 빌드 실패
- CI/CD 환경이나 다른 개발자 머신에서 재현 불가
- `meta-seame-headunit`의 다른 HU 앱들은 모두 `file://` 방식으로 소스를 레이어에 포함

**해결책**: `local.conf`에서 override (임시):
```bitbake
EXTERNALSRC:pn-vehiclecontrolmock = "/home/seame/leo/DES_Head-Unit/app/VehicleControlMock"
```
장기적으로는 HU 앱처럼 소스를 `file://`로 레이어에 포함시켜야 함.

### 2.6-B ℹ️ 참고: main_compositor.cpp의 오래된 주석 (코드 동작에는 무관)

`hu-mainapp-compositor/files/src/main_compositor.cpp` 주석이 실제 동작과 불일치:

```cpp
// 주석 (오래됨):  Connects to Weston (wayland-0), Creates wayland-1 socket
// 실제 동작:      WAYLAND_DISPLAY=wayland-1 → Weston 연결, socketName="wayland-3"
```

코드 동작에는 문제 없으나 디버그 로그 출력이 잘못된 정보를 표시함.

### 2.7 ⚠️ 예상 문제점: Yocto + Docker 이미지 관리

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

### 2.8 ⚠️ 예상 문제점: IC앱 서비스 파일이 bb 파일에 인라인 정의됨

```
HU앱 서비스 파일 위치 (분리된 .service 파일):
  recipes-apps/gearapp/files/gearapp.service       ← 독립 파일
  recipes-apps/mediaapp/files/mediaapp.service     ← 독립 파일
  recipes-apps/ambientapp/files/ambientapp.service ← 독립 파일
  ...

IC앱 서비스 파일 위치 (bb 파일 내 인라인):
  recipes-apps/ic-compositor/ic-compositor_1.0.bb  ← bb 파일 안에서 cat > EOF 방식으로 생성
  recipes-apps/batterymeter-app/batterymeter-app_1.0.bb   ← 동일
  recipes-apps/speedometer-app/speedometer-app_1.0.bb     ← 동일
  recipes-apps/gearstate-app/gearstate-app_1.0.bb         ← 동일
```

**실제 bb 파일 구조 (ic-compositor_1.0.bb)**:
```bitbake
do_install:append() {
    cat > ${D}${systemd_system_unitdir}/ic-compositor.service << EOF
    [Unit]
    ...
    Environment="WAYLAND_DISPLAY=wayland-1"
    ...
    EOF
}
```

**이것이 문제인 이유**:
1. **OTA 패키지화**: 서비스 파일을 수정하려면 전체 bb 파일을 재빌드해야 함 (HU앱처럼 서비스 파일만 교체 불가)
2. **컨테이너화**: 서비스 파일이 바이너리와 묶여 있어 컨테이너 환경변수 재설정이 어려움
3. **유지보수**: 서비스 파일 변경 시 소스 코드 패키지까지 재빌드 트리거됨

**권장 조치 (chang에게 전달)**:
```bitbake
# 현재 (인라인):
do_install:append() {
    cat > ... << EOF ... EOF
}

# 개선 (분리된 .service 파일):
SRC_URI += "file://ic-compositor.service"
do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/ic-compositor.service ${D}${systemd_system_unitdir}/
}
```

### 2.9 cgroups v2 확인 필요

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

#### ❓ 왜 자원 제한 없으면 한쪽 장애가 다른 쪽에 전파되나?

**Linux OOM Killer의 동작 방식** 때문이다.

```
[자원 제한 없는 상태]
Jetson RAM 8GB를 모든 프로세스가 공유:
  weston + vsomeip + IC 앱 3개 + HU 앱 4개 → 전부 같은 메모리 풀

GearApp 메모리 누수 발생:
  GearApp: 300MB → 1GB → 3GB → 6GB 급증
  → 커널 OOM 감지 → OOM Killer 실행
  → oom_score 기반으로 프로세스 선택해서 kill
  → GearApp을 kill해도 재시작 → 또 누수 → OOM 반복
  → 이 과정에서 OOM Killer가 Speedometer, BatteryMeter를 선택할 수 있음
  → IC 앱이 HU 앱 때문에 죽는 상황 발생
```

**더 조용한 문제 — 스왑 폭주:**
```
HU 앱이 메모리를 많이 쓰면 커널이 덜 쓰는 페이지를 디스크로 스왑
  → IC 앱의 메모리 페이지도 스왑 아웃될 수 있음
  → Speedometer가 속도값 읽으려고 메모리 접근
  → 페이지 폴트 → 디스크에서 스왑 인 대기 (수십~수백ms 지연)
  → IC 앱이 죽진 않았어도 UI가 프리즈된 것처럼 보임
```

**cgroup 메모리 제한이 해결하는 방식:**
```
HU 그룹: --memory=512m  (이 한도 내에서만 사용 가능)
  GearApp 누수 → 512MB 한도 도달
  → 커널이 HU cgroup 내에서만 OOM Kill (IC에 영향 없음)
  → IC cgroup(--memory=256m)은 완전히 분리된 메모리 풀
  → IC 앱 메모리는 HU에 의해 절대 침범되지 않음
```

> **한 줄 요약**: cgroup은 메모리 풀을 물리적으로 나눠서
> HU의 폭주가 IC의 물리 메모리를 빼앗아 가지 못하게 막는 경계선이다.

```bash
# 우리 프로젝트 적용 예시:
docker run --memory=512m --memory-swap=512m \
  --cpus=2.0 hu-gearapp:1.0.0   # HU: 최대 512MB, 2코어

docker run --memory=256m --memory-swap=256m \
  --cpus=1.0 ic-speedometer:1.0.0  # IC: 최대 256MB, 1코어
# → HU가 512MB를 다 써도 IC의 256MB는 보장됨
```

### 2.10 역할 분담 관점에서의 검토 (leo: HU, chang: IC)

**잘 나뉜 분담이다.** 이유:
- HU 앱과 IC 앱은 서로 다른 Wayland compositor를 사용 (`wayland-3` vs `wayland-2`)
- vsomeip에서 서로 다른 service를 consume → 충돌 없음
- 두 컨테이너의 격리가 독립적이라 병렬 개발 가능

#### 🆕 3차 검토 발견: IC앱들은 실제로 Mock 데이터를 사용한다

**IC앱 3개(BatteryMeter, Speedometer, GearState)의 vsomeip 설정:**
```json
// vsomeip_gearstate.json, vsomeip_speedometer.json, vsomeip_batterymeter.json:
{
    "unicast": "127.0.0.1",         ← 로컬호스트만 (외부 ECU와 통신 안 함)
    "routing": "VehicleControlMock"  ← Mock 서비스에서 데이터를 받음
}
```

반면 HU앱들(`routing_manager_ecu2.json`):
```json
{
    "unicast": "192.168.1.101",     ← Jetson의 실제 IP
    "routing": "routingmanagerd"    ← 실제 routing manager
}
```

**아키텍처 의미:**
```
RPi VehicleControlECU (192.168.1.100)
  └─→ SOME/IP over Ethernet
        └─→ Jetson routingmanagerd (192.168.1.101)
              └─→ HU앱들 (GearApp, MediaApp 등)  ← 실제 RPi 데이터 수신

VehicleControlMock (Jetson 내부)
  └─→ 로컬 IPC만
        └─→ IC앱들 (BatteryMeter, Speedometer, GearState)  ← Mock 데이터!
```

**컨테이너화 시 의미:**
- IC앱 컨테이너는 `--network=host`가 덜 중요 (어차피 로컬호스트 통신)
- 단, `VehicleControlMock` 프로세스도 동일 컨테이너 또는 접근 가능한 네트워크 내에 있어야 함
- OTA로 IC앱을 업데이트할 때 Mock 데이터 스킴도 함께 업데이트 필요

#### 🆕 3차 검토 발견: 모든 앱이 소프트웨어 렌더링 사용

**서비스 파일/bb 파일에서 확인:**
```bash
Environment="QT_QUICK_BACKEND=software"  ← 전 앱(HU + IC) 공통
```

**GPU 하드웨어 가속을 사용하지 않는다.** 이는:
1. **컨테이너화 시 GPU 디바이스 전달이 필수가 아님** → `/dev/dri/` 마운트 없어도 동작
2. 단, Wayland compositor 자체(Weston, IC/HU compositor)는 EGL이 필요할 수 있음
3. 성능 한계가 있으나 Jetson의 CPU 성능(6-core A78AE)으로 충분
4. **컨테이너 테스트를 훨씬 단순하게 할 수 있음** (GPU 권한 이슈 없음)

**주의점**: IC 컨테이너(chang)와 HU 컨테이너(leo)가 공유하는 리소스:
- vsomeip routing manager (호스트에서 실행해야 함, 컨테이너화 대상에서 제외)
- Weston compositor (`wayland-1`, 호스트)
- IC compositor (`wayland-2`, 호스트 또는 chang 컨테이너)
- HU compositor (`wayland-3`, 호스트 또는 leo 컨테이너)
- 네트워크 namespace (multicast routing, `--network=host` 필수)

---

### 2.11 산업 맥락 — vsomeip와 컨테이너 네트워크 격리

#### 왜 네트워크 격리를 포기하는가?

vsomeip는 SOME/IP(Service-Oriented Middleware over IP) 프로토콜을 구현하며,
service discovery에 **UDP 멀티캐스트(224.0.0.x)**를 사용한다.
멀티캐스트는 실제 NIC(`enP8p1s0`)에 직접 바인딩해야 하므로,
컨테이너의 가상 네트워크 인터페이스(veth)로는 동작하지 않는다.
따라서 `--network=host`가 필수이며, 이 순간 네트워크 격리는 0이 된다.

```
컨테이너 기본 네트워크 (bridge 모드):
  호스트 enP8p1s0 (192.168.1.101)
    └── docker0 bridge (172.17.0.1)
          └── veth → 컨테이너 eth0 (172.17.0.2)
  ← vsomeip multicast 라우팅 실패 (enP8p1s0 미접근)

--network=host 사용 시:
  컨테이너가 enP8p1s0를 직접 사용
  ← vsomeip 동작함, but 네트워크 격리 없음
```

#### 실제 산업에서는 어떻게 하나?

산업에서는 vsomeip/SOME/IP가 있는 환경에서 두 가지 접근을 사용한다:

**① 물리적 ECU 분리 (표준 접근)**

```
실제 차량:
  ECU A (HU SoC)  ─── Ethernet ─── ECU B (IC SoC)
  각 ECU는 물리적으로 분리되어 있으므로
  네트워크 격리를 소프트웨어로 흉내 낼 필요 자체가 없음
```

AUTOSAR Adaptive, SOAFEE 표준 모두 기본적으로
**HU와 IC는 서로 다른 물리 ECU**를 전제로 설계되어 있다.
컨테이너는 **하나의 ECU 안에서 여러 공급업체 소프트웨어를 격리**하는 용도이지,
ECU간 네트워크 격리를 대체하는 것이 아니다.

**② SOME/IP 프록시 패턴 (고급 접근)**

```
BMW, Bosch 일부 구현:
  vsomeip routing manager (호스트, --network=host)
      ↑ IPC (Unix socket 또는 shared memory)
  컨테이너 A (bridge 모드, 172.17.0.2)
  컨테이너 B (bridge 모드, 172.17.0.3)
```

컨테이너들은 `bridge` 모드로 격리된 네트워크를 갖고,
vsomeip routing manager만 호스트에서 실제 NIC를 사용하여 외부와 통신.
컨테이너들은 routing manager와 **내부 IPC**로만 통신.
이 구조에서는 컨테이너 간 네트워크 격리가 실현된다.

**③ 우리 프로젝트의 현실적 선택**

```
현재 우리 구조 (현실적 최선):
  호스트: weston + vsomeip-routing-manager  (--network=host로 실제 NIC 접근)
  IC 컨테이너: --network=host               (routing manager 클라이언트)
  HU 컨테이너: --network=host               (routing manager 클라이언트)
  → 네트워크 격리 없음, 하지만 cgroup 자원 격리는 있음
```

②번 프록시 패턴이 더 정석이지만 vsomeip IPC 설정 변경이 필요하고
우리 프로젝트 범위를 벗어난다. **네트워크 격리 포기, 자원 격리 + 배포 단위 집중이 현실적.**

#### 정리: 우리가 얻는 것과 포기하는 것

| 격리 종류 | 포기 여부 | 이유 |
|-----------|-----------|------|
| 네트워크 격리 | ❌ 포기 | vsomeip 멀티캐스트 → `--network=host` 필수 |
| 디스플레이 격리 | ❌ 포기 | Wayland 소켓 공유 마운트 필수 |
| 파일시스템 격리 | △ 부분 | 바이너리·라이브러리는 격리, 런타임 소켓은 공유 |
| **PID 격리** | ✅ 확보 | 컨테이너 기본 제공, HU 프로세스가 IC PID 접근 불가 |
| **자원 격리 (cgroup)** | ✅ 확보 | HU OOM → IC 메모리 보호됨 |
| **배포 단위 격리** | ✅ 확보 | 이미지 태그 = OTA 단위, 독립 롤백 가능 |
| **개발 독립성** | ✅ 확보 | leo 이미지 변경이 chang 이미지에 영향 없음 |

---

### 2.12 오케스트레이션 — 컨테이너 생명주기 자동 관리

**오케스트레이션(Orchestration)**이란 컨테이너를 **"띄우고, 죽이고, 재시작하고, 순서 맞추는"** 것을 자동으로 관리하는 것이다.

**현재 우리 시스템 — systemd가 이미 오케스트레이션 중:**
```
weston.service
  └── [After=weston] vsomeip-routing-manager.service
        └── [After=vsomeip] unified-compositor.service
              └── [After=unified-compositor] gearapp.service   (Restart=on-failure)
              └── [After=unified-compositor] mediaapp.service  (Restart=on-failure)
```
`After=`, `Requires=`, `Restart=on-failure` — 이게 이미 오케스트레이션이다.

**컨테이너 환경에서 docker-compose로 대응:**
```yaml
# docker-compose.yml
services:
  hu-compositor:
    image: hu-compositor:1.0.0
    restart: always                        # systemd Restart=on-failure 대응
    healthcheck:
      test: ["CMD", "test", "-S", "/run/user/1000/wayland-3"]

  hu-gearapp:
    image: hu-gearapp:1.0.1               # 버전 태그 = OTA 단위
    restart: always
    depends_on:
      hu-compositor:
        condition: service_healthy         # compositor 소켓 생성 후 시작 (After= 대응)
```

**OTA 시 오케스트레이션 — gearapp만 교체:**
```bash
docker load < hu-gearapp:1.0.1.tar.gz
docker-compose up -d --no-deps hu-gearapp   # gearapp만 재시작, 나머지 유지

# 실패 시 자동 롤백:
if ! docker inspect hu-gearapp --format='{{.State.Health.Status}}' | grep -q healthy; then
    docker-compose stop hu-gearapp
    sed -i 's/hu-gearapp:1.0.1/hu-gearapp:1.0.0/' docker-compose.yml
    docker-compose up -d --no-deps hu-gearapp
fi
```

| 역할 | systemd (현재) | docker-compose (컨테이너) |
|------|---------------|--------------------------|
| 시작 순서 | `After=`, `Requires=` | `depends_on: condition` |
| 재시작 정책 | `Restart=on-failure` | `restart: always` |
| 헬스체크 | `ExecStartPre` 루프 | `healthcheck` |
| OTA 롤백 | 없음 (수동) | 이전 이미지 태그로 교체 |

> **규모 참고**: Kubernetes는 멀티 노드 클러스터용 오케스트레이터다.
> 단일 Jetson에서는 docker-compose + systemd 조합으로 충분하다.

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

### 3.1-A 컨테이너 OTA vs 바이너리 직접 교체

**방법 A: 바이너리 직접 교체 (컨테이너 없음)**
```bash
systemctl stop gearapp
cp new_GearApp /usr/bin/GearApp   # 덮어씀 → 이전 버전 사라짐
systemctl start gearapp
```

**방법 B: 컨테이너 이미지 교체**
```bash
docker load < hu-gearapp:1.0.1.tar.gz  # load 완료 전까지 1.0.0 보존됨
docker stop gearapp-container
docker run hu-gearapp:1.0.1 ...
# 실패 시: docker run hu-gearapp:1.0.0  ← 즉시 롤백
```

| 관점 | 바이너리 직접 교체 | 컨테이너 이미지 교체 |
|------|-------------------|---------------------|
| **롤백** | ❌ 이전 파일 덮어씀 | ✅ 이전 이미지 태그 자동 보존 |
| **의존 라이브러리** | ⚠️ 라이브러리 따로 관리 | ✅ 이미지 내부에 전부 포함 |
| **원자성** | ❌ 파일 하나씩 복사 | ✅ `docker load` = 전부 아니면 없음 |
| **부분 실패** | ❌ 반쪽 상태 가능 | ✅ load 실패 = 기존 이미지 유지 |
| **라이브러리 버전 업** | ❌ 호스트 전체에 영향 | ✅ 이미지 내부에만 적용, 호스트 무관 |

**핵심 차이 — 라이브러리까지 통째로:**
```
바이너리 교체 방식:
  GearApp 1.0.1이 Qt 5.15.8 필요 → 호스트의 libQt5Core도 교체해야 함
  → 다른 앱(HomeScreen, MediaApp 등)에 영향 가능

컨테이너 이미지 방식:
  hu-gearapp:1.0.1 이미지 내부에 Qt 5.15.8 포함
  → 호스트 rootfs의 Qt 5.15.2는 그대로 유지
  → 다른 컨테이너/앱에 영향 없음
```

**실제 산업 표준 (Tesla, AGL, SOAFEE):**

이중 OTA 구조가 업계 표준이다:
```
OS 레이어:  SWUpdate A/B 슬롯  → 커널/rootfs 변경 시 (재부팅 필요)
앱 레이어:  컨테이너 이미지     → 앱/라이브러리 변경 시 (재부팅 없음, 30초 내 완료)
```
- **Tesla**: 게임, 브라우저, 주행 관련 앱을 컨테이너 이미지 단위로 무선 OTA
- **SOAFEE** (Arm + BMW/Toyota/GM): Uptane 프로토콜 기반 OCI 이미지 OTA를 표준으로 정의
- **AGL**: OSTree(OS OTA) + 컨테이너(앱 OTA) 이중 구조
- **우리 설계** (SWUpdate OS OTA + Docker 이미지 앱 OTA): 이 이중 구조와 정확히 일치

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

### 3.3-A 🚨 결정적 발견: meta-tegrademo에 SWUpdate 통합이 이미 존재한다

> **이것이 RAUC보다 SWUpdate를 우선 검토해야 하는 이유다.**

**`layers/meta-tegrademo/dynamic-layers/meta-swupdate/`** 디렉토리가 이미 존재한다.
OE4T(OpenEmbedded for Tegra) 팀이 이미 Jetson + SWUpdate 통합 레이어를 제공하고 있다.

```bash
# 활성화 방법 (README.md 기준):
cd repos
git submodule add https://github.com/sbabic/meta-swupdate
cd ../layers
ln -s ../repos/meta-swupdate
bitbake-layers add-layer ../layers/meta-swupdate

# local.conf에 추가:
IMAGE_INSTALL:append = " swupdate"
USE_REDUNDANT_FLASH_LAYOUT = "1"     # ← A/B 레이아웃 자동 설정
IMAGE_FSTYPES:append = " tar.gz"

# 빌드:
bitbake swupdate-image-tegra
```

**`USE_REDUNDANT_FLASH_LAYOUT = "1"` 한 줄이 A/B 파티션 레이아웃을 자동으로 설정해준다.**
수동 파티셔닝(`parted` 스크립트)을 직접 짤 필요가 없다.

**A/B 슬롯 상태 확인 명령** (Jetson에서):
```bash
nvbootctrl dump-slots-info
# 업데이트 후 출력 예시:
# Current boot slot: 0
# Capsule update status: 1  ← 업데이트 성공 시
```

**제공되는 핵심 기능**:
- Tegra Capsule Update (UEFI Firmware Update) 통합
- `TEGRA_SWUPDATE_BOOTLOADER_INSTALL_ONLY_IF_DIFFERENT`: rootfs만 바꿀 때 불필요한 부트로더 재플래싱 방지
- `TEGRA_SWUPDATE_LAST_CAPSULE_UPDATE_COMPLETE_SLOT_MARKER`: 업데이트 도중 전원 차단 복구 마커
- Lua 스크립트로 업데이트 절차 커스터마이징 가능

### 3.4 OTA 구현 옵션 비교

| 방법 | A/B 지원 | Yocto 통합 | Tegra 네이티브 | 복잡도 | 추천 |
|------|----------|------------|----------------|--------|------|
| **SWUpdate** | ✅ 지원 | meta-swupdate (**이미 tegra-demo-distro에 존재**) | ✅ **완전 통합** | 중간 | **1순위** |
| **RAUC** | ✅ 네이티브 | meta-rauc (별도 추가 필요) | ❌ 직접 구현 | 중간 | 2순위 |
| **Mender** | ✅ 네이티브 | meta-mender | ❌ | 중간 | 3순위 |
| **OSTree** | ✅ 네이티브 | meta-updater (AGL 사용) | ❌ | 높음 | 배제 |
| 직접 구현 (rsync/scp) | ❌ | 불필요 | - | 낮음 | Scope 1 학습용 |

**SWUpdate를 최우선 추천하는 이유** (3차 검토 결과로 1순위 변경):
- `layers/meta-tegrademo/dynamic-layers/meta-swupdate/`가 **이미 존재**
- Jetson의 `nvbootctrl` + Capsule Update와 네이티브 통합
- `USE_REDUNDANT_FLASH_LAYOUT = "1"` 한 줄로 A/B 파티션 자동 구성
- 1차 문서에서 추천한 RAUC는 Tegra용 native 통합이 없어 추가 구현 부담이 더 큼
- `bitbake swupdate-image-tegra` 하나로 업데이트 이미지 빌드

> **1차 문서의 RAUC 추천은 SWUpdate 통합 레이어 존재를 모르고 내린 결론이었다. 수정한다.**

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

#### ⚠️ 치명적 이슈: VehicleControlECU는 root 권한이 필요하다

**VehicleControlECU 소스 코드 (main.cpp)에서 확인:**
```cpp
#include <pigpio.h>

int main() {
    if (gpioInitialise() < 0) {
        // pigpio 초기화 실패 → 프로그램 종료
        return -1;  // ← sudo 없이 실행하면 여기서 죽는다
    }
    ...
}
```

**CMakeLists.txt**:
```cmake
find_library(PIGPIO_LIBRARY NAMES pigpio REQUIRED)
```

`pigpio`는 `/dev/gpiomem`, `/dev/mem`, I2C 디바이스(`/dev/i2c-*`)에 직접 접근하며,
이는 기본적으로 `root` 또는 `gpio`/`i2c` 그룹 권한이 필요하다.

**컨테이너화 시 선택지**:
```bash
# 방법 A: --privileged (가장 간단하지만 격리 의미가 없어짐)
docker run --privileged vehiclecontrol-container

# 방법 B: 최소 필요 권한 + 디바이스만 전달 (권장, 학습 목적으로 더 올바름)
docker run \
  --cap-add SYS_RAWIO \
  --device /dev/gpiomem \
  --device /dev/mem \
  --device /dev/i2c-1 \
  vehiclecontrol-container

# 방법 C: pigpio daemon (pigpiod) 방식
# 호스트에서 pigpiod를 root로 실행하고,
# 앱은 소켓으로 pigpiod에 연결 → root 불필요
ssh root@rpi "pigpiod"  # 호스트에서 한 번만
docker run \
  -e PIGPIO_ADDR=localhost \
  vehiclecontrol-container
```

**권장**: 컨테이너 격리 학습 목적으로는 **방법 B** 사용.
`--cap-add SYS_RAWIO`와 `--device` 옵션으로 최소 권한 원칙 시연 가능.

**OTA 중 하드웨어 안전 처리 순서**:
```bash
# 업데이트 전: 모터/서보 정지 필수
ssh root@192.168.1.100 << 'EOF'
  # PCA9685 PWM 출력 0으로 설정 (또는 systemd pre-stop hook)
  systemctl stop vehiclecontrol-ecu
  # 1초 대기 (하드웨어 안정화)
  sleep 1
  # 업데이트 적용
  cp /tmp/new_VehicleControlECU /usr/bin/VehicleControlECU
  systemctl start vehiclecontrol-ecu
EOF
```

**구현 순서 제안**:
1. 스크립트 기반 앱 업데이트 (scp + systemctl) → 개념 검증
2. 하드웨어 안전 처리 절차 (모터 정지 → 업데이트 → 재시작) 구현
3. RAUC 적용 → A/B rootfs 업데이트
4. Jetson을 OTA 게이트로 사용하는 파이프라인 구축

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

**Jetson 측 (chang) - SWUpdate 기반으로 수정**:
- [ ] `meta-swupdate` 서브모듈 추가 + `bitbake-layers add-layer`
- [ ] `local.conf`에 `USE_REDUNDANT_FLASH_LAYOUT = "1"` 추가 → A/B 자동 설정
- [ ] `bitbake swupdate-image-tegra` 빌드 테스트
- [ ] `nvbootctrl dump-slots-info`로 A/B 슬롯 상태 확인
- [ ] 서명용 X.509 인증서 생성 (SWUpdate도 서명 검증 지원)
- [ ] `TEGRA_SWUPDATE_LAST_CAPSULE_UPDATE_COMPLETE_SLOT_MARKER` 설정 (전원 차단 복구용)
- [ ] `TEGRA_SWUPDATE_BOOTLOADER_INSTALL_ONLY_IF_DIFFERENT = "true"` 설정 검토

> ~~RAUC slot 설정 (`/etc/rauc/system.conf`)~~ → SWUpdate로 대체  
> ~~meta-rauc Yocto 레이어 추가~~ → meta-swupdate는 이미 tegra-demo-distro에 dynamic-layer로 존재

**RPi 측 (leo)**:
- [ ] RPi 이미지 A/B 파티셔닝 (RAUC 또는 SWUpdate 선택 — RPi는 Tegra 통합 없으므로 둘 다 가능)
- [ ] VehicleControlECU 업데이트 절차 설계
- [ ] 업데이트 중 하드웨어 안전 처리 (모터 정지 → 업데이트 → 재시작)
- [ ] pigpio root 권한 컨테이너 옵션 결정 (`--cap-add SYS_RAWIO` vs `--privileged`)

#### ⚠️ 추가 이슈: vsomeip 라우팅 매니저 패키지 중복

**두 개의 패키지가 사실상 같은 서비스를 제공하며 설정이 충돌한다:**

```
패키지 1: meta-middleware/vsomeip-routingmanager
  - 서비스 파일: vsomeip-routingmanager.service
  - 설정: /etc/vsomeip/routing_manager_ecu2.json (unicast: 192.168.1.101)
  - User=root, WantedBy=multi-user.target
  - After=network-online.target

패키지 2: meta-seame-headunit/vsomeip-service
  - 서비스 파일: vsomeip-routing-manager.service (이름도 다름)
  - 설정: /etc/vsomeip/vsomeip-routing-manager.json (unicast: 192.168.1.101)
  - User 미지정(root), WantedBy=graphical.target
  - After=weston.service (Weston 의존)
  - ExecStartPre에 enP8p1s0 multicast 라우트 추가
```

두 패키지가 모두 IMAGE_INSTALL에 포함되면 **두 개의 routingmanagerd 인스턴스**가 실행 시도되고
`/tmp/vsomeip.lck` 파일 충돌로 두 번째 인스턴스가 실패한다.

**해결책**: 둘 중 하나만 이미지에 포함. 권장: `meta-seame-headunit/vsomeip-service`
(enP8p1s0 multicast 라우트 설정이 포함되어 있고, graphical.target에 묶여 Weston 순서 보장)

---

## 4. 기타 고려 사항

### 4.1 디스플레이 단일화 🔄 진행 중

#### 최종 확정 하드웨어 구성

```
Jetson DP → DP-to-MiniDP 어댑터 → WJESOG MST 허브 (HDMI 1포트만 사용)
         → Snowkids HDMI-to-MiniHDMI 케이블 → Elecrow 13.3" 4K (Mini HDMI 입력)

전원:
  MST 허브   : Micro USB → 외부 5V 충전기 (필수)
  Elecrow 모니터: USB-C → 전용 전원 어댑터 (6W, 필수)
```

> **ASUS ZenScreen MB166C 탈락 이유**: USB-C DP Alt Mode 방식으로 6W 전원이 필요한데,  
> Jetson DP 포트에서 해당 전력 공급 불가. Elecrow는 MiniHDMI 입력 + 별도 USB-C 전원으로 분리되어 문제 없음.

---

#### 현재 구조 (단일 compositor, wayland-2 소켓) ✅

```
Weston (wayland-1 소켓)
  └── HU_MainApp_Compositor  ← Weston에 클라이언트로 연결 (WAYLAND_DISPLAY=wayland-1)
        socketName: "wayland-2"  ← 앱들이 연결하는 별도 소켓
          ├── IC 앱 3개 (WAYLAND_DISPLAY=wayland-2)
          └── HU 앱 4개 (WAYLAND_DISPLAY=wayland-2)
```

**CompositorLayout 현재 상태 (TEST: DP landscape 1024×600)**

```
┌──────────────────────────────────────────────────────────────┐  ← 1024px
│  IC 영역(280px)  │ GearApp(130px) │   Main Area(614px)      │
│ ┌──────────────┐ │                │  ┌──────────────────┐   │
│ │ GearState    │ │   GearApp      │  │ HomeScreen       │   │  600px
│ │ (280×200)    │ │   (130×520)    │  │ / Media          │   │
│ ├──────────────┤ │                │  │ / Ambient        │   │
│ │ Speedometer  │ │                │  │ (614×520)        │   │
│ │ (280×200)    │ │                │  └──────────────────┘   │
│ ├──────────────┤ │                │  ┌──────────────────┐   │
│ │ BatteryMeter │ │                │  │  NavBar (80px)   │   │
│ │ (280×198)    │ │                │  └──────────────────┘   │
│ └──────────────┘ │                │                         │
└──────────────────┴────────────────┴─────────────────────────┘
```

---

#### 🎯 목표 레이아웃 (세로 portrait 화면 기준)

디스플레이: **600 × 1024** (portrait), 세로로 세워진 화면

```
┌─────────────────────────┐  ← 600px
│                         │
│   IC 영역  (600×340)    │
│                         │
│  ┌───────┬───────┬────┐ │
│  │Gear   │Speed  │Bat │ │  ← IC 앱 3개 가로로 나란히
│  │State  │ometer │tery│ │    각 앱: 200×340
│  │       │       │    │ │    (앱 내용은 세로 기준으로 그려짐 → 그대로 OK)
│  └───────┴───────┴────┘ │
├─────────────────────────┤  ← 구분선
│                         │
│  HU 영역  (600×684)     │
│                         │
│  ┌────┬────────────────┐ │
│  │ P  │                │ │
│  │ R  │                │ │
│  │ N  │  HomeScreen    │ │  ← GearApp(PRND): 130×604
│  │ D  │  / Media       │ │    HomeScreen 등: 470×604
│  │    │  / Ambient     │ │
│  │    │                │ │
│  └────┴────────────────┘ │
│  ┌─────────────────────┐ │
│  │   Navigation Bar    │ │  ← 하단 NavBar: 600×80
│  └─────────────────────┘ │
└─────────────────────────┘
      600px
```

**핵심 요약**:
- IC 3개 앱: **세로(portrait) 기준**으로 그려진 콘텐츠 → 세로 컨테이너(200×340)에 그대로 배치 ✅
- GearApp (PRND): **세로** 컨테이너 (130×604) → 세로 내용 그대로 배치 ✅
- HomeScreen 등 HU 메인: **세로** 컨테이너 (470×604) → 세로 내용 그대로 배치 ✅
- **결론**: 앱들은 portrait 기준으로 그려져 있고, 디스플레이도 portrait → **앱 내용 rotation 불필요**

---

#### 🔴 현재 문제 (DP TEST 모드에서 확인된 것)

현재 DP 연결 상태는 **landscape 1024×600**이므로,  
앱들(portrait 기준 렌더링)이 컨테이너에 들어가면 90도 틀어져 보임 → **DP 테스트에서는 정상이 아님**.

Elecrow portrait 화면으로 전환하면 앱 내용 방향이 맞음.

---

#### 🔧 Elecrow portrait 전환 시 변경 필요 항목 (4개 파일)

| 파일 | 변경 내용 |
|------|----------|
| `compositor_modular.qml` | `width: 600`, `height: 1024` |
| `CompositorLayout.qml` | IC → 상단 Row(600×340), HU → 하단 Col |
| `SurfaceRouter.qml` | IC: `Qt.size(200,340)`, GearApp: `Qt.size(130,604)`, HU: `Qt.size(470,524)` |
| `weston.ini` | `name=HDMI-A-1`, `transform=90` |

### 4.2 네트워크 보안 (OTA 관련)

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

### 4.3 vsomeip와 컨테이너/OTA의 상호작용

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

## 5. 최종 권고 및 우선순위

### 5.1 작업 우선순위 (권장 순서)

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

### 5.2 설계 원칙 (프로젝트 전체에 적용)

1. **점진적 복잡도**: 스크립트 → 컨테이너 → OTA → 보안 순서로 쌓아올려라
2. **가역성 확보**: 모든 변경에 롤백 경로를 설계. OTA는 실패 시 자동 롤백이 기본
3. **기존 스택 보존**: vsomeip, Qt, Wayland는 이미 동작 중. 이걸 컨테이너 안으로 이동하는 것이지 교체가 아님
4. **검증 가능한 마일스톤**: "OTA 성공"이 아니라 "업데이트 후 GearApp이 정상 작동"처럼 앱 레벨로 검증

### 5.3 빠른 참조: 각 기술별 핵심 키워드

| 기술 | Yocto 레이어 | 핵심 명령 | 주요 문서 |
|------|-------------|-----------|----------|
| Docker | meta-virtualization (이미 있음) | `IMAGE_INSTALL += "docker-moby"` | docs.docker.com |
| SWUpdate | meta-swupdate (tegra-demo-distro에 이미 dynamic-layer 존재) | `bitbake swupdate-image-tegra` | sbabic.github.io/swupdate |
| cgroup v2 | kernel config | `systemd.unified_cgroup_hierarchy=1` | kernel.org/doc/cgroup-v2 |
| Wayland in container | - | `-v /run/user/1000:/run/user/1000 --user 1000:1000` | wayland.freedesktop.org |
| NVIDIA BUP | meta-tegra (이미 있음) | `tegra-bup-payload` | developer.nvidia.com |
| Tegra A/B OTA | meta-swupdate dynamic-layer | `USE_REDUNDANT_FLASH_LAYOUT = "1"` | layers/meta-tegrademo/dynamic-layers/meta-swupdate/README.md |

---

**문서 버전**: 1.2  
**다음 검토 시점**: Phase 1 완료 후 (설계 가정 재검증 필요)

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|-----------|
| 1.0 | 2026-02-26 | 최초 작성 (시스템 분석 기반) |
| 1.1 | 2026-02-26 | 2차 정밀 검토 반영: Wayland 소켓 번호 수정 (wayland-0→1), HU/IC 앱 실제 소켓 번호 확인, 컨테이너 User/UID 제약 추가, pigpio root 요건 추가, IC앱 인라인 서비스 정의 이슈 추가, enP8p1s0 하드코딩 이슈 추가 |
| 1.2 | 2026-02-26 | 3차 정밀 검토 반영: **OTA 1순위를 RAUC→SWUpdate로 변경** (meta-tegrademo에 이미 통합 레이어 존재), IC앱이 Mock 데이터 사용(unicast:127.0.0.1, routing:VehicleControlMock) 발견, 모든 앱 QT_QUICK_BACKEND=software(GPU 불필요) 발견, vsomeip 라우팅 매니저 패키지 중복 충돌 이슈 추가, vehiclecontrolmock EXTERNALSRC 하드코딩 경로 경고 추가, main_compositor.cpp 오래된 주석(wayland-0) 경고 추가 |
| 1.3 | 2026-03-02 | 디스플레이 단일화 완료: ASUS ZenScreen 탈락(6W DP 전력 공급 불가) → Elecrow 13.3" 4K + MiniHDMI 확정. 3-layer compositor → 단일 compositor 전환 완료. IC compositor 비활성화, 모든 앱 WAYLAND_DISPLAY=wayland-1 통일. |
| 1.4 | 2026-03-07 | 컨테이너화 의의 재정립 및 산업 맥락 추가: 2.1 가치 표에 오케스트레이션 항목 추가. 2.3 컨테이너화 대상을 앱별 독립 이미지 구조로 재정의. 2.9에 OOM Killer/스왑 전파 원리 및 cgroup 해결 방식 추가. 2.11 vsomeip 네트워크 격리 산업 맥락(물리 ECU 분리/프록시 패턴/우리 선택) 추가. 2.12 오케스트레이션 섹션 신규 추가 (systemd↔docker-compose 대응표). 3.1-A 컨테이너 OTA vs 바이너리 교체 비교 및 Tesla/SOAFEE/AGL 산업 표준 추가. |
