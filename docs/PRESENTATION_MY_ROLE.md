# 발표 자료 — 시스템 엔지니어 Leo

> **발표 핵심 메시지**: "나는 앱을 만든 게 아니라, 앱이 실행될 수 있는 **시스템 전체를 설계하고 구축**했다"

---

## 슬라이드 구성

> IC 파트 → Leo 파트 순서로 발표.
>
> 슬라이드 1 — 우리 시스템 소개  
> 슬라이드 2 — 왜 Jetson인가, 왜 이더넷인가  
> 슬라이드 3 — 시스템 엔지니어로서 내가 한 것  
> 슬라이드 3-1 — Yocto BSP: RPi와 다른 것들  
> 슬라이드 3-2 — Wayland Compositor: 7개 앱을 한 화면에  
> 슬라이드 3-3 — 컨테이너 격리 + OTA 이중 구조  
> 슬라이드 4 — 앞으로: 시우 팀과 합치기

---

## 슬라이드 1 — 우리 시스템 소개

**제목**: "SDV Head Unit — 두 ECU로 구성된 차량 인포테인먼트 시스템"

```
[ RPi 4  — ECU1 (Zonal) ]  ←── 이더넷 직결 (SOME/IP) ──→  [ Jetson Orin Nano — ECU2 (Central) ]
  VehicleControl                                              HU 앱 4개 (Docker 컨테이너)
  차량 신호 처리                                               IC 앱 3개 (systemd)
  (기어, 속도, 배터리)                                         Wayland Compositor
  192.168.1.100                                               OTA (SWUpdate A/B)
                                                              192.168.1.101
                                                               ↓ DP → MiniHDMI
                                                           [ 13.3" 디스플레이 600×1024 ]
```

**발표 멘트**:
> "IC 팀이 방금 설명한 속도계, 계기판 앱이 실행되는 플랫폼 전체를 제가 구축했습니다.
> RPi는 차량 신호를 담당하는 Zonal ECU, Jetson은 디스플레이와 서비스 관리를 담당하는 Central ECU입니다.
> 실제 SDV의 Zonal/Central 구조와 동일한 역할 분리입니다."

---

## 슬라이드 2 — 왜 Jetson인가, 왜 이더넷인가

**제목**: "요구사항을 따라가면 결론은 하나였다"

### 요구사항 → 제약 → 결론

| 요구사항 | 제약 | 결론 |
|----------|------|------|
| OTA + 롤백 | A/B 파티션 필요 | RPi는 직접 구성해야 함, Jetson은 **16개 파티션 내장** |
| 앱 격리 + 자동복구 | 컨테이너 런타임 필요 | RPi 비공식, Jetson **NVIDIA Container Runtime 공식 지원** |
| 앱 확장 + 중앙 관리 | 디스플레이·서비스를 한 곳에 집중 | RPi 분산 구조는 관리 복잡, **중앙집중형이 유일한 답** |
| SDV 구조 재현 | Zonal/Central ECU 역할 분리 | RPi 2대로는 역할 구분 모호, **Jetson이 Central에 적합** |
| Yocto 기반 빌드 | BSP 공식 지원 필요 | **NVIDIA OE4T (L4T R36.4.4) 공식 BSP 존재** |

> **중앙집중형 + Jetson Orin Nano — 선택이 아니라 요구사항의 결과였다.**

---

### 왜 이더넷인가 (CAN과 비교)

| | CAN | 이더넷 (채택) |
|--|-----|--------------|
| 대역폭 | ~1 Mbps | 1 Gbps |
| 데이터 단위 | 8바이트 프레임 | 제한 없음 |
| 향후 카메라 프레임 전송 | ❌ 불가 | ✅ 동일 인프라 재사용 가능 |
| 미들웨어 | 직접 파싱 필요 | ✅ SOME/IP — 서비스 ID 기반 자동 discovery |

**SOME/IP 확장성**: 신호 추가 시 소켓 코드 수정 없이 설정 파일(JSON)만 수정.
앱이 늘어나도 서비스 등록만 하면 기존 앱에 영향 없음.

---

## 슬라이드 3 — 시스템 엔지니어로서 내가 한 것

**제목**: "앱이 실행되는 환경을 처음부터 만들었다"

```
내가 한 것                               결과
─────────────────────────────────────────────────────────────────────
Yocto L4T BSP 빌드 + 오류 4건 패치    → Jetson에 커스텀 OS 올림
Wayland Compositor 설계 (QML 3개)     → IC/HU 7개 앱 단일 화면 제어
Docker 컨테이너화 (FROM scratch)       → 앱 격리 + 자동 복구
OTA 이중 구조 설계                     → OS 레이어 + 앱 레이어 독립 업데이트
SOME/IP 설정 파일 8개 작성             → RPi ↔ Jetson 서비스 연결
systemd 유닛 + 부팅 순서 설계          → 전원 ON → 자동 실행
```

> 다음 3장에서 각각 자세히 설명합니다.

---

## 슬라이드 3-1 — Yocto BSP: RPi와 다른 것들

**제목**: "Jetson에 OS 올리기 — RPi와 무엇이 달랐나"

```
RPi:    meta-raspberrypi 레이어 하나 → bitbake core-image-weston → 끝

Jetson: OE4T tegra-demo-distro (NVIDIA 공식)
          ├── meta-tegra          ← L4T R36.4.4 BSP
          ├── meta-tegrademo
          └── meta-seame-*        ← 우리가 직접 추가한 레이어
```

**실제로 마주친 빌드 오류 (RPi에선 만날 수 없는 문제들)**:

| 오류 | 원인 | 해결 |
|------|------|------|
| OpenSSL `BN_GF2m_add` 링크 실패 | EC2 타원곡선이 L4T 빌드와 충돌 | `no-ec2m` 패치 |
| GCC 13.4 + binutils LTO 순환참조 | LTO 조합 버그 | LTO 비활성화 |
| EDK2 GenFw DOS header 오류 | 동일한 LTO 문제 | EDK2 전용 LTO 비활성화 |
| DocBook XML fetch 실패 | 네트워크 URL 변경 | 수동 다운로드 → `DL_DIR` 배치 |

**커널 파라미터 전달 방식의 차이**:
```
RPi:    cmdline.txt 한 줄 수정
Jetson: UBOOT_EXTLINUX_KERNEL_ARGS:append = " systemd.unified_cgroup_hierarchy=1"
        → 이걸 모르면 cgroup v2가 안 켜진 채로 Docker 실행됨. 실제로 그랬음.
```

**파티션 구조**:
```
RPi:    boot + rootfs = 2개
Jetson: 부트로더/TOS/펌웨어/A슬롯/B슬롯/... = 16개
        → SWUpdate A/B OTA가 의미 있는 이유. RPi는 이 구조를 따로 만들어야 함.
```

**Recovery 경험**: SWUpdate 테스트 중 브릭 → Recovery 버튼 + USB-C → `lsusb` 확인 → `sudo ./doflash.sh` → 복원.
RPi는 SD카드 교체가 전부. Jetson은 하드웨어 Recovery 프로세스 자체가 임베디드 경험.

---

## 슬라이드 3-2 — Wayland Compositor: 7개 앱을 한 화면에

**제목**: "NVIDIA 공식 문서의 배신, 그리고 직접 설계"

**공식 문서에서 추천한 방법**: Jetson에서 IVI Shell 사용 가능하다고 명시.
→ 실제로는 **DriveOS 전용** 기능이었음. Yocto + Weston 환경에서는 동작하지 않음.

**결국 직접 설계한 Nested Compositor 구조**:
```
Weston (wayland-1 소켓)                ← 디스플레이 서버
  └── unified-compositor               ← 내가 QML로 설계
        wayland-2 소켓 생성
        sendConfigure()로 각 앱에 크기 지시
          ├── IC 앱 3개 (systemd)
          │     Speedometer 200×340
          │     GearState   200×340
          │     BatteryMeter 200×340
          └── HU 앱 4개 (Docker 컨테이너)
                GearApp     130×604
                HomeScreen  470×524
                MediaApp    470×524
                AmbientApp  470×524
```

**설계한 QML 3개**:

| 파일 | 역할 |
|------|------|
| `CompositorLayout.qml` | IC 영역(상단 340px) / HU 영역(하단 604px) 픽셀 단위 분할 |
| `SurfaceRouter.qml` | 앱 title로 식별 → 해당 영역에 자동 배치 |
| `compositor_modular.qml` | 위 둘을 합쳐 Weston에 하나의 창으로 등록 |

**트레이드오프**: GPU 렌더링(opengl + threaded) 시도 →
Qt Wayland Compositor + Render Thread 간 EGL race condition → 크래시 루프 →
**소프트웨어 렌더링으로 롤백** (현재 CPU 42% 사용 중, 미완 인정)

---

## 슬라이드 3-3 — 컨테이너 격리 + OTA 이중 구조

**제목**: "앱 격리와 업데이트 — 두 계층 설계"

**컨테이너화 결정 과정**:
```
시도 1: ubuntu 베이스 이미지
  → 800MB, Yocto 크로스컴파일 결과물과 arm64 ABI 불일치 → 포기

시도 2: FROM scratch + 호스트 /usr/lib 마운트
  → 203~537KB, 바이너리+QML만 포함 → 채택

네트워크: --network=bridge (격리 시도)
  → vsomeip SOME/IP 멀티캐스트(224.0.0.1) 물리 인터페이스 필요 → 불가
  → --network=host 강제, --memory=512m cgroup으로 메모리만 격리
```

**OTA 이중 구조**:
```
OS 레이어:   SWUpdate A/B 슬롯
              커널/rootfs 변경 → 재부팅 필요, 실패 시 이전 슬롯 자동 복귀
              빌드 완료: demo-image-base.swu (451MB)

앱 레이어:   Docker 이미지 태그 교체
              앱 변경 → 재부팅 없음, docker-compose.yml 태그만 수정 → 30초 이내 롤백
```

실측: 컨테이너 4개 RestartCount 0 / 메모리 764MB / 7.4GB  
이 구조는 Tesla, AGL, SOAFEE (Arm + BMW + Toyota + GM) 표준과 동일.

**솔직한 한계**: SWUpdate 이미지 빌드까지 완료, 실제 OTA 전송 테스트는 미완.

---

## 슬라이드 4 — 앞으로: 시우 팀과 합치기

**제목**: "확장성 입증 — 자율주행 팀과의 통합"

**시우 팀**: 자율주행 팀. 동일하게 Jetson을 사용.

**통합 시나리오**:
```
현재
  [ RPi ECU1 ]  ←── SOME/IP ──→  [ Jetson (우리) ECU2 ]
                                   HU/IC 앱 7개

통합 후
  [ RPi ECU1 ]  ←── SOME/IP ──→  [ Jetson (우리) ECU2 ]  ←── 게이트웨이 ──→  [ 시우 팀 Jetson ]
                                   기존 앱 유지                                  자율주행 앱
                                   + OTA 게이트웨이 역할
```

**이 통합이 증명하는 것**:
- SOME/IP 서비스 기반 구조: 새 ECU 추가 시 기존 앱 코드 변경 없음
- Docker 컨테이너: 자율주행 앱을 독립 이미지로 배포 가능
 - Jetson을 게이트웨이로: 자율주행 판단 결과를 SOME/IP로 HU에 전달 → 화면 표시까지

> **"앱이 늘어나도 구조가 바뀌지 않는다" — 중앙집중형 설계의 확장성 입증**

---

**솔직한 한계 (발표 마무리)**:
- SWUpdate A/B 빌드(451MB) 완료, 실제 OTA 전송 테스트 미완
- GPU 렌더링 미완 (소프트웨어 렌더링 CPU 42% 사용 중)

---

## 0. 전체 시스템 다이어그램

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         물리 하드웨어 구성                                        │
│                                                                                  │
│   ┌──────────────────────┐   이더넷 직결 (192.168.1.x)   ┌─────────────────────┐ │
│   │   Raspberry Pi 4     │◄─────────────────────────────►│  Jetson Orin Nano   │ │
│   │   ECU1               │                               │  ECU2               │ │
│   │   192.168.1.100      │                               │  192.168.1.101      │ │
│   │                      │                               │  (WiFi: .86.31)     │ │
│   │  VehicleControlECU   │                               │                     │ │
│   │  (SOME/IP 서버)       │                               │  [아래 소프트웨어]   │ │
│   │  service: 0x1234     │                               │                     │ │
│   └──────────────────────┘                               └─────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                  Jetson Orin Nano — 소프트웨어 스택 (ECU2)                        │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  [호스트 — 컨테이너화 안 함]                                               │   │
│  │                                                                          │   │
│  │  weston.service ──────────────────────────────────────── wayland-1 소켓  │   │
│  │  vsomeip-routing-manager.service ─── enP8p1s0 (이더넷) ── SOME/IP 라우팅 │   │
│  └─────────────────────────┬────────────────────────────────────────────────┘   │
│                             │ wayland-1 클라이언트                               │
│  ┌──────────────────────────▼───────────────────────────────────────────────┐   │
│  │  unified-compositor.service  (systemd, 호스트 직접 실행)                  │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐ │   │
│  │  │  compositor_modular.qml                                             │ │   │
│  │  │  ├── SurfaceRouter: 앱 title → 화면 위치 매핑                        │ │   │
│  │  │  ├── sendConfigure: 각 앱에 크기 지정 (Wayland 프로토콜)             │ │   │
│  │  │  └── wayland-2 소켓 생성 ────────────────────────────────────────┐  │ │   │
│  │  └─────────────────────────────────────────────────────────────────│──┘ │   │
│  │                                                                     │    │   │
│  │  IC 앱 (systemd 직접)        wayland-2 클라이언트◄───────────────────┤    │   │
│  │  ├── speedometer-app.service ──────────────────────────────────────►│    │   │
│  │  ├── batterymeter-app.service ─────────────────────────────────────►│    │   │
│  │  └── gearstate-app.service ────────────────────────────────────────►│    │   │
│  │                                                                     │    │   │
│  │  HU 앱 (Docker 컨테이너)      wayland-2 클라이언트◄───────────────────┘    │   │
│  │  hu-apps.service (docker-compose up)                                │    │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │    │   │
│  │  │ hu-gearapp:1.0.0     │ hu-homescreen:1.0.0                     │ │    │   │
│  │  │ hu-media:1.0.0       │ hu-ambient:1.0.0                        │ │    │   │
│  │  │                                                                │ │    │   │
│  │  │ 공통: --network=host, -v /run/user/1000, -v /tmp, -v /usr/lib  │ │    │   │
│  │  │       --memory=512m  (cgroup v2)                               │ │    │   │
│  │  └────────────────────────────────────────────────────────────────┘ │    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │   │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                         SOME/IP 통신 흐름                                         │
│                                                                                  │
│  RPi (VehicleControlECU)                    Jetson                               │
│  ┌─────────────────────┐                   ┌──────────────────────────────────┐  │
│  │ VehicleControl 서버  │                   │ vsomeip-routing-manager          │  │
│  │ service: 0x1234     │◄─── 이더넷 ───────►│ (routingmanagerd, id: 0xFFFF)    │  │
│  │ instance: 0x5678    │  SOME/IP 멀티캐스트 │                                  │  │
│  └─────────────────────┘  224.0.0.1:30490  │  ┌─ GearApp     (id: 0x0100)     │  │
│                                             │  ├─ HomeScreen  (id: 0x1400)     │  │
│                                             │  ├─ MediaApp    (id: 0x1236)     │  │
│                                             │  └─ AmbientApp  (id: 0x0200)     │  │
│                                             │       ↑                          │  │
│                                             │  /tmp/vsomeip-0 (IPC 소켓)       │  │
│                                             └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                         OTA 이중 구조                                             │
│                                                                                  │
│  OS 레이어 (SWUpdate A/B)              앱 레이어 (Docker 이미지)                   │
│  ┌─────────────────────────┐          ┌──────────────────────────────────────┐   │
│  │ A슬롯: 현재 실행 중      │          │ hu-gearapp:1.0.0  (현재)             │   │
│  │ B슬롯: 업데이트 대기     │          │ hu-gearapp:1.0.1  (업데이트)         │   │
│  │                         │          │                                      │   │
│  │ 커널/rootfs 변경 시 사용 │          │ 앱 변경 시 사용 (재부팅 불필요)       │   │
│  │ 재부팅 필요             │          │ docker-compose.yml 태그만 변경        │   │
│  │ .swu 파일 451MB         │          │ → 즉시 롤백 가능                     │   │
│  └─────────────────────────┘          └──────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                         디스플레이 레이아웃 (600×1024 portrait)                   │
│                                                                                  │
│  ┌─────────────────────────┐  ← 600px                                            │
│  │  GearState │Speedometer │BatteryMeter │  ← IC 영역 (상단 340px)               │
│  │  (200×340) │ (200×340)  │  (200×340)  │    systemd 직접 실행                  │
│  ├─────────────────────────┤                                                     │
│  │ G │                     │                                                     │
│  │ e │   HomeScreen        │  ← HU 영역 (하단 604px)                             │
│  │ a │   / Media           │    Docker 컨테이너                                   │
│  │ r │   / Ambient         │    GearApp: 130×604 (좌측)                          │
│  │   │   (470×524)         │    Main: 470×524                                    │
│  ├─────────────────────────┤                                                     │
│  │      Navigation Bar      │  ← NavBar (80px)                                   │
│  └─────────────────────────┘                                                     │
│  Weston transform=90 (GPU 레벨 회전, 앱 코드에 rotation 없음)                     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. 내가 한 일을 한 문장으로

> **"Raspberry Pi 기반 단일 프로세스 시스템을, Jetson Orin Nano 위에서 앱별 독립 컨테이너로 실행되는 자동차 인포테인먼트 시스템으로 전환했다."**

---

## 2. 왜 "구체적인 기술이 없다"는 느낌이 드는가

**착각의 원인**: 시스템 엔지니어의 기술은 **눈에 안 보인다**.

앱 개발자는 코드를 짜면 화면에 뭔가 뜬다. 즉시 보인다.  
시스템 엔지니어는 코드를 짜면 **아무것도 뜨지 않는 게 성공**인 경우가 많다.  
(서비스가 조용히 뜨고, 충돌 없이 격리되고, 부팅이 자동으로 되는 것)

**내가 다룬 기술 스택 (실제 커밋/로그 기반):**

| 영역 | 기술 | 증거 |
|------|------|------|
| 임베디드 빌드 | Yocto Scarthgap, BitBake 레시피 작성 | 레시피 파일 수십 개 |
| 디스플레이 서버 | Wayland, Weston, Qt Wayland Compositor | `wayland-2` 소켓 설계 |
| IPC/미들웨어 | vsomeip (SOME/IP), CommonAPI | 설정 파일 8개, application ID 매핑 |
| 컨테이너 | Docker (arm64), FROM scratch 이미지 | 4개 이미지 (~200–537KB) |
| OTA | SWUpdate A/B 파티션, docker-compose 롤백 | `demo-image-base.swu` 451MB |
| 시스템 서비스 | systemd 유닛 설계, 부팅 순서 제어 | `hu-apps.service`, `WantedBy` 체인 |
| 네트워크 | 이더넷 직결 (192.168.1.x), SOME/IP 멀티캐스트 | RPi ↔ Jetson 서비스 연결 확인 |

---

## 3. 발표 구조 (권장)

### 3.1 문제에서 시작 — "기존 시스템의 한계"

```
[기존 — 단일 RPi]
  RPi 하나에서 ECU1(VehicleControl) + ECU2(HU 앱) 모두 실행
  → 단일 장애점: HU 앱 크래시 = VehicleControl도 영향
  → 업데이트 단위: SD카드 전체 교체 (운영 중 롤백 불가)
  → 디스플레이 제약: Weston에 앱이 직접 붙음 → 레이아웃 제어 불가
```

```
[중간 — RPi 2대 구성 (타팀)]
  RPi ECU1 (VehicleControl) + RPi ECU2 (HU 앱)
  → ECU 역할 분리는 달성
  → 여전히: SD카드 기반, 컨테이너 없음, GPU 없음, OTA 없음
  → HU 앱이 Weston에 직접 붙어 레이아웃 제어 어려움
```

```
[우리 — Jetson 전환]
  RPi ECU1 (VehicleControl) + Jetson Orin Nano ECU2 (HU 앱 컨테이너)
  → ECU 역할 분리 유지
  → 추가 달성: 컨테이너 격리, OTA 이중구조, Compositor 기반 레이아웃 제어
```

---

### 3.2 내가 설계한 것 — "Compositor 기반 디스플레이 아키텍처"

**기존 구조의 문제**:

```
Weston
  ├── IC_Compositor  → IC 앱 3개  (디스플레이 1 전용)
  └── HU_Compositor  → HU 앱 4개  (디스플레이 2 전용)
```
소켓 3개, 서비스 9개, 디스플레이 2개 필요.  
단일 디스플레이 환경에서 동작 자체가 불가.

**내가 설계한 구조**:

```
Weston (wayland-1)
  └── unified-compositor  ← 내가 설계/구현한 QML Compositor
        socketName: "wayland-2"
          ├── IC 앱 3개  (GearState, Speedometer, BatteryMeter)
          └── HU 앱 4개  (GearApp, HomeScreen, Media, Ambient)
```

**핵심 기술 포인트**:
- `sendConfigure`: Compositor가 각 앱에게 "이 크기로 그려라"를 명령 (Wayland 프로토콜 메시지)
- `SurfaceRouter.qml`: 앱 title로 앱을 식별 → 레이아웃 위치에 자동 배치
- `transform=90`: Weston이 GPU 레벨에서 화면 회전 → 앱 코드에 rotation 불필요

**결과**: 세로 화면(600×1024) 위에 IC 영역 + HU 영역 + NavBar를 픽셀 단위로 제어.

---

### 3.3 내가 해결한 것 — "컨테이너 격리 + SOME/IP 외부 통신"

**Docker 컨테이너화의 실제 어려움** (단순히 `docker run`이 아님):

1. **라이브러리 문제**: Yocto 크로스컴파일 결과물은 arm64 전용 → 일반 apt 라이브러리와 ABI 불일치  
   → `FROM scratch` + 호스트 `/usr/lib` 마운트로 해결  
   → 이미지 크기: 203KB~537KB (바이너리+QML만)

2. **Wayland 소켓 문제**: 컨테이너는 `/run/user/1000`에 접근 불가  
   → 마운트 목록 하나씩 디버깅으로 확정 (9개 마운트)

3. **vsomeip IPC vs 외부 통신**: 설정 파일 없으면 `/tmp/vsomeip-0` fallback → RPi 서비스 발견 불가  
   → application ID 매핑 + unicast 바인딩 설정 파일 8개 작성  
   → routingmanagerd `id: 0xFFFF` 수정, `routing` 필드 추가  
   → **결과: `VehicleControl service is now available!`** (RPi ↔ Jetson 서비스 발견 확인)

**실측 수치**:
```
이미지 크기:   203KB ~ 537KB (FROM scratch)
RestartCount:  0 (4개 컨테이너 모두)
메모리 사용:   764MB / 7.4GB
MediaApp CPU:  42.54% (소프트웨어 렌더링 — 미최적화 인정)
```

---

### 3.4 내가 설계한 것 — "OTA 이중 구조"

```
OS 레이어:   SWUpdate A/B 슬롯
              → 커널/rootfs 변경 시 사용 (재부팅 필요)
              → 빌드 결과: demo-image-base.swu (451MB)

앱 레이어:   Docker 이미지 태그 교체
              → 앱/라이브러리 변경 시 (재부팅 없음)
              → docker pull hu-gearapp:1.0.1 → docker-compose up → 즉시 반영
              → 문제 시 docker-compose.yml 태그만 이전 버전으로 수정 → 즉시 롤백
```

**이게 왜 중요한가?**  
타팀 RPi 구성에서 앱 업데이트 = SD카드 전체 교체 or scp로 바이너리 복사 (운영 중 롤백 불가).  
우리 구조는 앱 레이어를 **이미지 단위**로 관리 → OTA 업데이트 후 30초 이내 이전 버전으로 복구 가능.

이 구조는 **Tesla, AGL(Automotive Grade Linux), SOAFEE(Arm+BMW+Toyota+GM)** 표준과 동일한 이중 구조.

---

## 4. 단일 RPi / RPi 2대 / 우리 시스템 비교표

| 항목 | 단일 RPi | RPi 2대 | **Jetson (우리)** |
|------|---------|---------|-----------------|
| ECU 분리 | ❌ ECU1+ECU2 혼합 | ✅ 분리 | ✅ 분리 |
| 디스플레이 제어 | Weston 직접 연결 | Weston 직접 연결 | ✅ Compositor 중간 레이어 (픽셀 단위 제어) |
| 앱 격리 | ❌ 단일 프로세스 | ❌ 단일 프로세스 | ✅ 앱별 독립 컨테이너 (cgroup 메모리 한도) |
| OTA | ❌ 없음 | ❌ 없음 | ✅ SWUpdate A/B + Docker 이미지 교체 이중 구조 |
| 장애 격리 | ❌ 앱 하나 죽으면 전체 영향 | ❌ 동일 | ✅ 컨테이너 크래시 → 해당 컨테이너만 `restart: always` |
| 업데이트 롤백 | ❌ SD카드 교체 | ❌ SD카드 교체 | ✅ 이미지 태그 변경 → 30초 이내 롤백 |
| GPU | VideoCore VI (소프트웨어 렌더링 동일) | VideoCore VI | NVIDIA Ampere (GPU 렌더링 준비됨, 현재 미적용) |
| RAM | 4GB LPDDR4 | 4GB×2 | 8GB LPDDR5 |
| 저장소 | microSD (신뢰성 낮음) | microSD | eMMC (신뢰성 높음, 운영환경 적합) |
| 빌드 시스템 | Yocto | Yocto | ✅ Yocto + L4T BSP (NVIDIA 공식 지원) |

---

## 5. 솔직하게 인정할 부분 (질문 방어용)

| 질문 | 솔직한 답변 |
|------|-------------|
| "GPU 렌더링은 왜 안 됐나요?" | Qt5 + Wayland + Jetson 조합에서 EGL 초기화 실패. threaded 렌더 루프와 Qt Wayland Compositor가 race condition 유발. Qt6 + opengl 조합으로 재시도 필요. |
| "SWUpdate 실제 업데이트 해봤나요?" | A/B 파티션 이미지 빌드(451MB)까지 완료. 실제 OTA 전송 테스트는 미완. Docker 앱 레이어 롤백은 실측 완료. |
| "컨테이너 네트워크 격리는 왜 안 됐나요?" | vsomeip SOME/IP는 멀티캐스트(224.0.0.1) 사용 → bridge 네트워크로는 물리 인터페이스에 바인딩 불가. `--network=host`가 불가피한 선택. |
| "RPi랑 성능 차이가 실제로 있나요?" | 현재 소프트웨어 렌더링으로 CPU 42.54% 사용 중. GPU 렌더링 전환 시 유의미한 차이 예상. eMMC 저장소 신뢰성 차이는 운영 환경에서 중요. |

---

## 6. Jetson을 선택한 이유 — 임베디드 고차원 경험

> **핵심 메시지**: "RPi에서는 경험할 수 없는 임베디드 개발자로서의 역량을 기르고 싶었다"

RPi는 `apt install`과 SD카드 교체로 대부분의 문제가 해결된다.  
Jetson은 다르다. 아래는 이 프로젝트에서 **실제로 겪은** RPi와의 차이점이다.

### 6.1 BSP 수준 빌드 오류 직접 패치

RPi Yocto는 `meta-raspberrypi` 하나로 끝난다.  
Jetson은 NVIDIA **L4T R36.4.4** 위에 OE4T `tegra-demo-distro` + `meta-tegra` 레이어를 직접 구성해야 한다.

실제로 마주친 오류들:
```
1. OpenSSL 3.2.6 EC2 링크 오류       → no-ec2m 패치 적용
2. GCC 13.4 / binutils 2.42 LTO 순환 참조  → LTO 비활성화
3. EDK2 GenFw DOS header 오류        → EDK2용 LTO 별도 비활성화
4. DocBook XML 네트워크 fetch 실패    → 수동 다운로드 + 로컬 캐시
```
이 오류들은 RPi 빌드에서는 만날 수 없다. BSP 계층 자체를 이해해야 해결 가능하다.

### 6.2 커널 파라미터 전달 방식 — EXTLINUX

RPi: `cmdline.txt` 한 줄 수정으로 끝.  
Jetson: U-Boot EXTLINUX 방식으로 전달해야 함.

```bitbake
# 틀린 방법 (RPi 방식으로 접근하면 동작 안 함)
APPEND:append = " systemd.unified_cgroup_hierarchy=1"

# 맞는 방법
UBOOT_EXTLINUX_KERNEL_ARGS:append = " systemd.unified_cgroup_hierarchy=1"
```

이 차이를 모르면 cgroup v2가 활성화 안 된 채로 Docker를 쓰게 된다. 실제로 그랬다.

### 6.3 Recovery Mode 직접 경험

SWUpdate 빌드 테스트 중 잘못된 이미지 압축 해제 → Jetson 화면 "신호 없음" (브릭).

```
1. Jetson Recovery 버튼 누른 채로 USB-C 연결
2. lsusb에서 NVIDIA Recovery 장치 확인
3. tegraflash 디렉토리에서 sudo ./doflash.sh 실행
4. Exit Code 0 → 정상 복원
```

RPi 브릭은 SD카드 다시 굽는 게 전부다. Jetson은 **하드웨어 Recovery 프로세스 자체가 임베디드 경험**이다.

### 6.4 파티션 구조

```
RPi:    mmcblk0p1 (boot) + mmcblk0p2 (rootfs) = 2개
Jetson: mmcblk0p1 ~ mmcblk0p16                = 16개
        (부트로더, TOS, 펌웨어, VER, A슬롯, B슬롯, ...)
```

SWUpdate A/B 파티션이 의미 있는 이유가 여기 있다.  
Jetson은 파티션 구조 자체가 A/B 전환을 위해 설계되어 있다.

### 6.5 NVIDIA Container Runtime

RPi Docker는 cgroup 설정만 하면 끝.  
Jetson에서 GPU를 컨테이너에 노출하려면:

```json
// /etc/docker/daemon.json
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime"
    }
  }
}
```

이 구조를 이해해야 컨테이너 안에서 CUDA/OpenGL이 동작한다.  
현재 소프트웨어 렌더링을 쓰고 있지만, GPU 렌더링 전환의 기반 구조는 이미 갖춰져 있다.

---

## 7. 발표 핵심 키워드 3가지

1. **"시스템 레이어 설계"** — Weston → Compositor → 앱 → 컨테이너 계층 설계
2. **"운영 가능한 구조"** — 크래시 자동 복구, 이미지 단위 롤백, 부팅 자동 실행
3. **"표준 준수"** — SOAFEE 이중 OTA 구조, SOME/IP (ISO 23554), Wayland 프로토콜
