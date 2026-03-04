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

## 다음 단계

→ `CONTAINER_OTA_ROADMAP.md` 참조
