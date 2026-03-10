# PDC Yocto Jetson Orin Nano — 프로젝트 진행 기록

> **플랫폼**: NVIDIA Jetson Orin Nano (ECU2) + Raspberry Pi 4 (ECU1)  
> **빌드 시스템**: Yocto Scarthgap + L4T R36.4.4  
> ⚠️ 계획 및 로드맵은 `NEXT_PROJECT_ANALYSIS.md` 참조. 이 파일은 완료된 작업만 기록.  
> ⚠️ 다음 Phase 계획은 `CONTAINER_OTA_ROADMAP.md` 참조.

---

## Phase 1: 단일 디스플레이 통합 Compositor ✅

> 기간: ~2026-03-02  
> 목표: 듀얼 디스플레이 3-layer compositor → 단일 디스플레이 단일 compositor

### 1.1 배경 — 이전 구조 (3-layer compositor)

```
Weston (wayland-1)
  ├── IC_Compositor  (wayland-2)  → IC 앱 3개  ← 디스플레이 1 (IC 전용)
  └── HU_Compositor  (wayland-3)  → HU 앱 4개  ← 디스플레이 2 (HU 전용)
```

- 소켓 3개, 서비스 9개, 디스플레이 2개 필요
- 단일 디스플레이 환경에서는 과도한 복잡도

### 1.2 하드웨어 확정

```
Jetson DP 포트
  → DP-to-MiniDP 어댑터
  → WJESOG MST 허브 (HDMI 포트 1개 사용)
  → Snowkids HDMI-to-MiniHDMI 케이블
  → Elecrow 13.3" 4K 디스플레이 (MiniHDMI 입력)
      세로(portrait) 장착, 600×1024 해상도 사용

전원:
  MST 허브  : Micro USB → 외부 5V
  Elecrow   : USB-C → 전용 어댑터 6W
```

> **ASUS ZenScreen 탈락 이유**: USB-C DP Alt Mode 전력(6W)을 Jetson DP 포트에서 공급 불가.  
> Elecrow는 MiniHDMI(영상) + USB-C(전원) 분리 구조라 문제 없음.

### 1.3 현재 구조 (단일 compositor)

```
Weston (wayland-1 소켓)
  └── HU_MainApp_Compositor  ← wayland-1 클라이언트로 연결
        socketName: "wayland-2"  ← 7개 앱이 이 소켓으로 연결
          ├── IC 앱 3개  (GearState, Speedometer, BatteryMeter)
          └── HU 앱 4개  (GearApp, HomeScreen, Media, Ambient)
```

**왜 wayland-2 소켓이 필요한가?**  
앱들이 Weston(wayland-1)에 직접 연결하면 Weston이 각 앱을 독립 전체화면 클라이언트로 취급.  
별도 소켓(wayland-2)을 만들어 Compositor가 `sendConfigure`로 창 크기를 제어할 수 있게 함.

### 1.4 화면 레이아웃 (portrait 600×1024)

```
┌─────────────────────────┐  ← 600px
│  GearState│Speedom│Bat  │  IC 영역 (상단 340px)
│  (200×340)│(200×340)│(200×340)│
├─────────────────────────┤
│  P │                    │
│  R │   HomeScreen       │  HU 영역 (하단 684px)
│  N │   / Media          │  GearApp(PRND): 130×604
│  D │   / Ambient        │  Main: 470×524
├─────────────────────────┤
│      Navigation Bar      │  NavBar (80px)
└─────────────────────────┘
```

**Weston transform=90 방식**:  
물리 화면은 landscape이지만 Weston이 OS 레벨에서 90도 회전 → 앱 입장에서 portrait  
→ 앱 코드에 rotation 불필요, 터치 좌표 변환도 Weston이 처리

### 1.5 커밋 히스토리

| 커밋 | 내용 |
|------|------|
| `da417a77` | 단일 compositor 전환, ic-compositor disable, 7개 앱 wayland-1 통일 |
| `93cdea1e` | portrait 레이아웃 600×1024 (IC top 340px / HU bottom 684px) |
| `38c71afc` | weston.ini portrait transform=90 |
| `c312edd1` | DP 테스트 모드 전환 (landscape 1024×600) |
| `99b06f56` | wayland-2 소켓 도입 (앱 전체화면 문제 수정, 10 files changed) |
| `7ea834ab` | portrait 모드 최종 전환 (HDMI-A-1 transform=90 활성) |

### 1.6 주요 파일 위치 및 역할

```
layers/meta-seame-headunit/
  ┌─ recipes-apps/hu-mainapp-compositor/files/qml/ ──────────────────────────
  │
  │  compositor_modular.qml
  │  ├─ 역할: QML 최상위 진입점. WaylandCompositor 루트 객체 선언
  │  ├─ 동작: wayland-2 소켓 생성 → 앱 연결 수신 → XdgShell 이벤트 처리
  │  │         → SurfaceRouter.routeSurface() 호출하여 앱을 컨테이너에 배치
  │  │         → WaylandOutput으로 Weston(wayland-1)에 600×1024 창을 띄움
  │  └─ 참고: QML은 UI 설계도, 실제 Wayland 프로토콜 처리는
  │            Qt Wayland Compositor C++ 라이브러리가 담당
  │
  │  CompositorLayout.qml
  │  ├─ 역할: 화면 분할 레이아웃 설계도 (픽셀 단위 자리 배치)
  │  ├─ 동작: 화면을 IC 영역(상단 340px) / HU 영역(하단 684px) / NavBar(80px)
  │  │         로 분할. 각 영역에 "컨테이너(Item)" 를 선언해 자리만 잡아둠.
  │  │         실제 앱 화면은 SurfaceRouter가 해당 컨테이너에 끼워 넣음.
  │  └─ 비유: HTML의 <div> 레이아웃과 동일한 개념
  │
  │  SurfaceRouter.qml
  │  ├─ 역할: 앱 식별자 → 컨테이너 매핑 테이블 + 배치 실행기
  │  ├─ 동작: ① 앱 title("GearState", "Speedometer" 등)로 앱 식별
  │  │         ② getSuggestedSize()로 sendConfigure 크기 결정
  │  │            (Compositor → 앱에게 "이 크기로 그려라" 요청)
  │  │         ③ routeSurface()로 해당 컨테이너에 ShellSurfaceItem 삽입
  │  └─ 참고: sendConfigure는 Wayland 프로토콜 메시지.
  │            앱이 이 크기를 무시하면 컨테이너 크기와 불일치 발생
  │            (현재 IC 앱들의 Window 하드코딩 문제 원인)
  │
  ├─ recipes-graphics/wayland/ ──────────────────────────────────────────────
  │
  │  weston-init.bbappend
  │  └─ 역할: Yocto 빌드 시 weston-init 패키지에 weston.ini 파일을 추가하는
  │            BitBake 확장 레시피 (SRC_URI:append로 파일 주입)
  │
  │  weston-init/weston.ini
  │  ├─ 역할: Weston 디스플레이 서버 설정 파일
  │  ├─ 동작: [output] name=HDMI-A-1 transform=90
  │  │         → OS/앱 입장에서 화면이 portrait(600×1024)로 보이게 함
  │  │         → 앱 코드에 rotation 불필요, 터치 좌표도 Weston이 자동 변환
  │  └─ 핵심: transform은 Weston이 GPU에서 처리 → 앱별 rotation보다 효율적
  │
  ├─ recipes-apps/{gearapp,homescreenapp,mediaapp,ambientapp}/files/*.service ─
  │
  │  *.service (systemd 서비스 파일)
  │  ├─ 역할: 앱을 systemd 서비스로 등록, 부팅 시 자동 실행
  │  ├─ 동작: ExecStartPre로 wayland-2 소켓 생성 대기(최대 20초)
  │  │         → 소켓 확인 후 앱 실행 (Compositor보다 늦게 뜨도록 보장)
  │  │         Restart=on-failure로 앱 크래시 시 자동 재시작
  │  └─ 환경변수: WAYLAND_DISPLAY=wayland-2 (Weston이 아닌 Compositor에 연결)
  │
  └─ recipes-apps/{batterymeter,speedometer,gearstate}-app/*_1.0.bb ─────────

     *_1.0.bb (BitBake 레시피)
     ├─ 역할: IC 앱 빌드 방법 + systemd 서비스 파일 인라인 정의
     ├─ 동작: HU 앱(.service 파일 별도)과 달리 IC 앱은 bb 파일 안에
     │         서비스 유닛을 heredoc으로 직접 작성 (구조는 동일)
     └─ 이유: IC 앱이 bb 파일 하나로 빌드+서비스 설정을 한 번에 관리
```

---

## Phase 2: unified-compositor 리팩토링 + 렌더링 안정화 ✅

> 기간: 2026-03-02 ~ 2026-03-04  
> 목표: compositor 명칭 통일, GPU 렌더링 시도 및 롤백, software 렌더링 최종 확정

### 2.1 unified-compositor 리네이밍

기존 `hu-mainapp-compositor`를 `unified-compositor`로 전체 리네이밍.

**변경 이유**: IC 앱까지 포함한 단일 compositor가 됐으므로 "HU 전용"이라는 명칭이 부정확.

변경 범위: `recipes-apps/hu-mainapp-compositor/` → `recipes-apps/unified-compositor/`,
`meta-seame-headunit.bb` IMAGE_INSTALL, `qml_compositor.qrc` 삭제된 SVG 참조 제거.

| 커밋 | 내용 |
|------|------|
| `42d882de` | refactor: rename hu-mainapp-compositor → unified-compositor |
| `c652ef06` | fix: remove deleted SVG references from qml_compositor.qrc |

### 2.2 GPU 렌더링 테스트 → 실패 → software 롤백

**시도한 설정:**

| 앱 구분 | QSG_RENDER_LOOP | QT_QUICK_BACKEND |
|---------|----------------|------------------|
| unified-compositor | `basic` | `opengl` |
| HU 앱 4개 + IC 앱 3개 | `threaded` | `opengl` |

**결과: 앱 전체 깜빡임 (크래시 루프)**

원인: `Restart=always` + EGL 초기화 실패 → 3초마다 재시작 루프.
Qt Wayland Compositor 역할 앱에서 `threaded` 사용 시 surface management race condition 유발.

**최종 결론**: Jetson Orin Nano + Qt5 + Wayland 스택에서 `QT_QUICK_BACKEND=opengl` 사용 불가.
GPU 렌더링 재시도는 SSH/UART 접근 가능 시 로그 분석 후 판단.

**최종 확정 렌더링 설정 (전 앱 공통):**
```
QSG_RENDER_LOOP=basic
QT_QUICK_BACKEND=software
```

| 커밋 | 내용 |
|------|------|
| `15905922` | test: switch to GPU rendering (opengl+threaded) |
| `2d73449e` | fix: unified-compositor QSG_RENDER_LOOP basic으로 수정 |
| `3e7781c5` | revert: restore software rendering ← **현재 HEAD** |

### 2.3 현재 서비스 기동 순서

```
weston.service
  └── unified-compositor.service
        ├── gearapp / homescreenapp / mediaapp / ambientapp
        └── speedometer-app / batterymeter-app / gearstate-app

vsomeip-routing-manager.service (병렬)
  └── vehiclecontrolmock.service
```

### 2.4 알려진 미해결 사항

| 항목 | 상태 | 비고 |
|------|------|------|
| GPU 렌더링 (opengl) | ❌ EGL 초기화 실패 | 로그 분석 필요 |
| UART 콘솔 접근 | ❌ | ttyTCU0은 USB-C Device Mode로만 노출, Yocto 이미지에 USB gadget 미설정 |
| weston-terminal 아이콘 | 의도적 없음 | `panel-position=none` 설정 |

---

## Phase 3: 컨테이너 격리 🔄

> 기간: 2026-03-05 ~  
> 목표: HU/IC 앱을 Docker 컨테이너로 격리 실행

### 3.0 사전 준비 ✅

**Docker 추가 (2026-03-05)**

`seame-headunit-image.bb`에 `docker-moby` 추가.  
`meta-virtualization` 레이어가 이미 `bblayers.conf`에 포함되어 있어 레이어 추가 불필요.  
`tegrademo.inc`의 `DISTRO_FEATURES`에 `virtualization`이 이미 포함되어 있어 별도 설정 불필요.

**cgroup v2 활성화**

`layer.conf`에 `UBOOT_EXTLINUX_KERNEL_ARGS:append = " systemd.unified_cgroup_hierarchy=1"` 추가.  
Jetson은 `APPEND:append`가 아닌 EXTLINUX 방식으로 커널 파라미터를 추가함.  
`local.conf`가 `.gitignore` 대상이므로 `layer.conf`로 이동 (git 추적 가능).

**IC 앱 서비스 파일 분리 (선행 완료)**

커밋 `2bc8f961`: bb 인라인 heredoc → 독립 `.service` 파일 3개로 분리.  
컨테이너 환경변수 수정 시 bb 전체 재빌드 없이 서비스 파일만 교체 가능.

**Weston 터미널 복구**

`weston.ini`에서 `panel-position=none` → `bottom`, `[launcher]` 섹션 추가.  
SSH 접속을 위해 IP 확인 가능하도록 복구.

**빌드 결과 확인**

```
docker-moby          25.0.3   ← 포함됨
docker-moby-cli      25.0.3
containerd           v2.0.7
runc                 1.1.14
```

**보드 동작 확인 (SSH: root@192.168.86.247)**

```
docker.service: active (running)
docker run --rm hello-world → 정상 동작 (arm64v8)
```

| 커밋 | 내용 |
|------|------|
| `2bc8f961` | refactor: IC 앱 서비스 파일 bb 인라인 → 독립 파일 |
| `acde3d32` | feat(phase3-0): add docker-moby + cgroup v2 kernel param |
| `9435347d` | fix(phase3-0): move cgroup v2 param to layer.conf |
| `6ab0e55d` | fix(phase3-0): remove docker-moby-contrib (unnecessary) |
| `fa5e200a` | fix: restore weston panel + terminal launcher |

### 3.1 컨테이너화 설계 확정 ✅ (2026-03-07)

**대화 기반 설계 재정립** — 핵심 결정 사항:

#### 컨테이너화의 진짜 의의 (재정립)

| 이점 | 적용 여부 | 이유 |
|------|-----------|------|
| 네트워크 격리 | ❌ 포기 | vsomeip SOME/IP 멀티캐스트 → `--network=host` 필수 |
| 디스플레이 격리 | ❌ 포기 | Wayland 소켓(`/run/user/1000`) 공유 마운트 필수 |
| **자원 경계 (cgroup)** | ✅ 핵심 | HU OOM이 IC 앱에 전파되지 않도록 메모리 풀 분리 |
| **이미지 단위 배포** | ✅ 핵심 | 앱+라이브러리를 통째로 교체, 이전 태그로 즉시 롤백 |
| **개발 독립성** | ✅ 핵심 | leo(HU) / chang(IC) 이미지 분리, 서로 영향 없음 |
| **오케스트레이션** | ✅ 핵심 | docker-compose로 컨테이너 재시작·순서·OTA 롤백 자동화 |


#### 확정된 컨테이너 구조

```
[호스트 — 절대 컨테이너화 안 함]
  weston.service                    ← Wayland 인프라 (wayland-1 소켓)
  vsomeip-routing-manager.service   ← SOME/IP 인프라 (enP8p1s0 멀티캐스트)

[IC 그룹 — chang 담당, --memory=256m]
  ic-compositor      → docker: ic-compositor:버전
  speedometer-app    → docker: ic-speedometer:버전
  batterymeter-app   → docker: ic-batterymeter:버전
  gearstate-app      → docker: ic-gearstate:버전

[HU 그룹 — leo 담당, --memory=512m]
  unified-compositor → docker: hu-compositor:버전
  gearapp            → docker: hu-gearapp:버전
  homescreenapp      → docker: hu-homescreen:버전
  mediaapp           → docker: hu-media:버전
  ambientapp         → docker: hu-ambient:버전
```

> **앱별 단독 이미지** (덩어리 아님): `docker load hu-gearapp:1.0.1`로 gearapp만 OTA 가능.
> docker-compose.yml은 실행 편의 도구이며 이미지 단위와 무관.

#### 현재 Wayland 소켓 구조 (단일 compositor 기준)

```
weston (wayland-1 소켓 생성)
  └── unified-compositor (wayland-1 클라이언트, wayland-2 서버 소켓 생성)
        ├── IC 앱 3개 (WAYLAND_DISPLAY=wayland-2)
        └── HU 앱 4개 (WAYLAND_DISPLAY=wayland-2)

컨테이너 마운트 필수:
  -v /run/user/1000:/run/user/1000
  --user 1000:1000
  -e WAYLAND_DISPLAY=wayland-2
  -e XDG_RUNTIME_DIR=/run/user/1000
  --network=host
  -e VSOMEIP_CONFIGURATION=...
```

#### OTA 이중 구조 확정

```
OS 레이어:  SWUpdate A/B 슬롯 → 커널/rootfs 변경 시 (재부팅 필요)
앱 레이어:  Docker 이미지 교체 → 앱/라이브러리 변경 시 (재부팅 없음)
```

이는 Tesla, AGL, SOAFEE(Arm+BMW/Toyota/GM) 표준과 동일한 이중 구조.

### 3.2 SWUpdate A/B 빌드 완료 ✅ (2026-03-06)

**meta-seame-ota 레이어 신설** (커밋 `bc240a74`):

```
layers/meta-seame-ota/conf/layer.conf:
  LAYERDEPENDS_meta-seame-ota = "core tegra swupdate"
  USE_REDUNDANT_FLASH_LAYOUT = "1"    ← A/B 파티션 자동 구성
  IMAGE_INSTALL:append = " swupdate"
  IMAGE_FSTYPES:append = " tar.gz"
```

**빌드 결과:**
```
bitbake swupdate-image-tegra
→ 8344/8344 tasks succeeded
→ demo-image-base-jetson-orin-nano-devkit.swu (451MB)
→ demo-image-base-jetson-orin-nano-devkit.tegraflash.tar.gz (480MB)
```

**Jetson 복원 사고 및 복구 (2026-03-06):**

SWUpdate 빌드 테스트를 위해 `demo-image-base`를 `jetson-flash-2`에 잘못 압축 해제 →
Jetson 화면 "신호 없음". `seame-headunit-image-jetson-orin-nano-devkit.rootfs-20260305141747.tegraflash.tar.gz`로
Recovery 모드에서 `sudo ./doflash.sh` 재실행 → Exit Code 0, 정상 복원.

| 커밋 | 내용 |
|------|------|
| `bc240a74` | feat: add meta-seame-ota layer with SWUpdate A/B config |

---

### 3.3 GearApp 컨테이너화 검증 PoC(Proof of Concept) ✅ (2026-03-07)

**목표**: HU 앱 중 첫 번째인 GearApp을 컨테이너로 실행하고 화면 표시 확인

#### 컨테이너 구조 확정

`FROM scratch` + 호스트 라이브러리 마운트 방식:
- 이미지에는 `/usr/bin/GearApp` + QML 파일만 포함 (~216KB)
- Qt, vsomeip, CommonAPI 라이브러리는 호스트 `/usr/lib` 읽기 전용 마운트
- 이유: Yocto 크로스컴파일 결과물을 그대로 사용, arm64 라이브러리 재빌드 불필요

#### 필수 마운트 목록 (디버깅으로 확정)

| 마운트 | 이유 |
|--------|------|
| `/run/user/1000:/run/user/1000` | wayland-2 소켓 (unified-compositor 접근) |
| `/tmp:/tmp` | vsomeip IPC 소켓 (`/tmp/vsomeip-0`, `/tmp/vsomeip-10b`) |
| `/usr/lib:/usr/lib:ro` | Qt5, vsomeip3, CommonAPI 라이브러리 |
| `/usr/lib/plugins:/usr/lib/plugins:ro` | Qt Wayland 플러그인 (`libqwayland-generic.so` 등) |
| `/usr/lib/qml:/usr/lib/qml:ro` | QML 모듈 (QtQuick, QtGraphicalEffects 등) |
| `/usr/share/fonts:/usr/share/fonts:ro` | 폰트 렌더링 |
| `/etc/fonts:/etc/fonts:ro` | fontconfig 설정 |
| `/usr/share/X11:/usr/share/X11:ro` | xkb 키보드 레이아웃 (없으면 Qt Wayland 경고) |
| `/var/cache/fontconfig:/var/cache/fontconfig` | 폰트 캐시 쓰기 (없으면 경고만, 동작은 함) |

#### vsomeip 동작 확인

- GearApp 서비스 파일의 `VSOMEIP_CONFIGURATION=/etc/vsomeip/routing_manager_ecu2.json` → 파일 없음
- vsomeip가 `/tmp/vsomeip-0` 소켓으로 자동 fallback 연결
- routing manager에 Client `010b`로 등록, VehicleControl 서비스 구독 정상
- **결론**: 컨테이너 내에서도 vsomeip IPC 정상 동작 (설정 파일 불필요)
- 상세 분석: `docs/VSOMEIP_YOCTO_ANALYSIS.md`

#### 최종 실행 명령 (검증 완료)

```bash
docker run -d \
  --name hu-gearapp \
  --network=host \
  -v /run/user/1000:/run/user/1000 \
  -v /tmp:/tmp \
  -v /usr/lib:/usr/lib:ro \
  -v /usr/lib/plugins:/usr/lib/plugins:ro \
  -v /usr/lib/qml:/usr/lib/qml:ro \
  -v /usr/share/fonts:/usr/share/fonts:ro \
  -v /etc/fonts:/etc/fonts:ro \
  -v /usr/share/X11:/usr/share/X11:ro \
  -v /var/cache/fontconfig:/var/cache/fontconfig \
  --user 1000:1000 \
  --memory=512m --memory-swap=512m \
  -e WAYLAND_DISPLAY=wayland-2 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
  -e QSG_RENDER_LOOP=basic \
  -e QT_QUICK_BACKEND=software \
  -e LD_LIBRARY_PATH=/usr/lib \
  -e QT_PLUGIN_PATH=/usr/lib/plugins \
  -e QML2_IMPORT_PATH=/usr/lib/qml \
  -e VSOMEIP_APPLICATION_NAME=GearApp \
  hu-gearapp:1.0.0
```

#### 결과

- ✅ 컨테이너 실행 성공 (`docker ps` 상태 `running`)
- ✅ vsomeip Client `010b` routing manager 등록 완료
- ✅ VehicleControl 서비스 구독 및 Gear 이벤트 수신 (`Gear update: "P"`)
- ✅ QML GUI 화면 표시 확인 (`(0, 0, 130, 1000)` Left Panel)
- ✅ cgroup 메모리 제한 `--memory=512m` 적용

#### 관련 파일

| 파일 | 경로 |
|------|------|
| Dockerfile | `containers/hu-gearapp/Dockerfile` |
| 빌드 스크립트 | `containers/hu-gearapp/build.sh` |
| 실행 스크립트 | `containers/hu-gearapp/run.sh` |
| vsomeip 분석 | `docs/VSOMEIP_YOCTO_ANALYSIS.md` |

---

### 3.4 HU 앱 전체 컨테이너화 + systemd 교체 ✅ (2026-03-09)

**목표**: 나머지 HU 앱 3개 컨테이너화 + docker-compose 통합 + 부팅 자동 실행

#### 완료 내용

**이미지 빌드 (4개 앱 모두)**
```
hu-gearapp:1.0.0     203KB
hu-homescreen:1.0.0  400KB
hu-media:1.0.0       476KB
hu-ambient:1.0.0     537KB
```
모두 `FROM scratch` 방식 — 바이너리+QML만 포함, 라이브러리는 호스트 마운트

**docker-compose.yml 작성** (`/etc/hu-apps/docker-compose.yml`)
- 앱 4개 공통 설정을 YAML 앵커(`x-hu-common`)로 관리
- `restart: always` → 컨테이너 crash 시 자동 재시작
- `mem_limit: 512m` → cgroup 메모리 한도

**docker-compose 설치 (arm64 바이너리)**
- Yocto `docker-moby`에 compose 플러그인 미포함 확인
- 개발 PC에서 `docker-compose v2.24.6 linux/aarch64` 다운로드 후 scp 전송
- `/usr/local/bin/docker-compose` → `/usr/bin/docker-compose` 심링크

**hu-apps.service 설치** (기존 4개 서비스 대체)
```
기존: gearapp.service, homescreenapp.service, mediaapp.service, ambientapp.service
교체: hu-apps.service (docker-compose up 단일 서비스)
```
- 기존 서비스 4개 `disable` 처리
- `hu-apps.service` → `multi-user.target` 자동 시작

#### 최종 확인
```
NAMES           STATUS         IMAGE
hu-gearapp      Up 9 seconds   hu-gearapp:1.0.0
hu-media        Up 9 seconds   hu-media:1.0.0
hu-ambient      Up 9 seconds   hu-ambient:1.0.0
hu-homescreen   Up 9 seconds   hu-homescreen:1.0.0
```
화면 표시 4개 앱 전부 정상 ✅

#### 관련 파일

| 파일 | 경로 |
|------|------|
| docker-compose | `containers/hu-apps/docker-compose.yml` |
| systemd 서비스 | `containers/hu-apps/hu-apps.service` |
| 빌드 스크립트 | `containers/hu-apps/build-all.sh` |
| 설치 스크립트 | `containers/hu-apps/install.sh` |

---

### 3.5 vsomeip 설정 파일 정상화 ✅ (2026-03-09)

#### 배경
컨테이너 실행은 성공했지만 각 앱이 `VSOMEIP_CONFIGURATION` 없이 IPC fallback으로만 동작 중.
이더넷 직결(192.168.1.x) 환경에서 RPi ↔ Jetson SOME/IP 외부 통신이 안 되는 상태였음.

#### 원인 분석
- Jetson IP: `192.168.1.101` (이더넷 `enP8p1s0`) — 이더넷 미연결 시 NO-CARRIER
- routingmanagerd: `/etc/vsomeip/vsomeip-routing-manager.json` 사용 중, `unicast: 192.168.1.101` 바인딩
- 각 앱: `VSOMEIP_CONFIGURATION` 미설정 → fallback으로 `/tmp/vsomeip-0` IPC만 사용
- GitHub 원본(`routing_manager_ecu2.json`)과 실제 설치 파일의 `id` 불일치 (`0xFFFF` vs `0x0100`), `routing` 필드 누락

#### 조치 내용

**1. 앱별 vsomeip 설정 파일 신규 작성 (GitHub 원본 기반)**

| 앱 | vsomeip 설정 | application id |
|---|---|---|
| GearApp | `vsomeip_gearapp.json` | `0x0100` |
| HomeScreenApp | `vsomeip_homescreen.json` | `0x1400` |
| MediaApp | `vsomeip_mediaapp.json` | `0x1236` |
| AmbientApp | `vsomeip_ambientapp.json` | `0x0200` |

**2. Yocto 레시피 4개 수정**
- `SRC_URI`에 `config/vsomeip_*.json` + `config/commonapi_*.ini` 추가
- `do_install`에 `/etc/commonapi/` 설치 코드 추가
- `FILES`에 `/etc/commonapi/` 경로 추가
- `bitbake gearapp homescreenapp mediaapp ambientapp` 빌드 완료

**3. routing manager 설정 수정**
- `vsomeip-routing-manager.json`: `id 0x0100 → 0xFFFF`, `"routing": "routingmanagerd"` 추가

**4. docker-compose.yml 수정**
- `/etc/commonapi:/etc/commonapi:ro` 마운트 추가
- 각 앱에 `VSOMEIP_CONFIGURATION` + `COMMONAPI_CONFIG` 환경변수 추가

#### 결과
```
VSOMEIP_CONFIGURATION: "/etc/commonapi/vsomeip_gearapp.json"  ✅
Loading configuration file '/etc/commonapi/commonapi_gearapp.ini'         ✅
Instantiating routing manager [Proxy]                                      ✅
Client 010b successfully connected to routing ~> vsomeip-0                ✅
VehicleControl service is now available!                                   ✅ RPi 서비스 발견
```

#### 관련 파일

| 파일 | 경로 |
|------|------|
| GearApp vsomeip | `layers/meta-seame-headunit/recipes-apps/gearapp/files/config/vsomeip_gearapp.json` |
| HomeScreenApp vsomeip | `layers/meta-seame-headunit/recipes-apps/homescreenapp/files/config/vsomeip_homescreen.json` |
| MediaApp vsomeip | `layers/meta-seame-headunit/recipes-apps/mediaapp/files/config/vsomeip_mediaapp.json` |
| AmbientApp vsomeip | `layers/meta-seame-headunit/recipes-apps/ambientapp/files/config/vsomeip_ambientapp.json` |
| routing manager | `layers/meta-seame-headunit/recipes-middleware/vsomeip-service/files/vsomeip-routing-manager.json` |
| docker-compose | `containers/hu-apps/docker-compose.yml` |

---

## 다음 단계

→ `CONTAINER_OTA_ROADMAP.md` 참조
