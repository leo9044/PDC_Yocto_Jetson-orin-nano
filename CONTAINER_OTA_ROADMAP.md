# 컨테이너 격리 + OTA 업데이트 로드맵

> **작성일**: 2026-03-04  **최종 수정**: 2026-03-07
> **기술 분석 원본**: `NEXT_PROJECT_ANALYSIS.md`
> **역할 분담**: leo → HU 컨테이너 + RPi OTA / chang → IC 컨테이너 + Jetson OTA

---

## 결정 사항 요약

| 항목 | 결정 | 근거 |
|------|------|------|
| VM/하이퍼바이저 | ❌ 배제 | Jetson Orin Nano 미지원, 학습 곡선 과도 |
| 컨테이너 격리 | ✅ Docker + cgroups | meta-virtualization 이미 bblayers.conf에 존재 |
| 네트워크 격리 | ❌ 포기 | vsomeip SOME/IP 멀티캐스트 → `--network=host` 필수 |
| 디스플레이 격리 | ❌ 포기 | Wayland 소켓 공유 마운트 필수 |
| 자원 경계 | ✅ cgroup memory 제한 | HU OOM이 IC에 전파 차단 |
| 컨테이너 단위 | ✅ 앱별 독립 이미지 | gearapp 하나만 OTA 교체 가능 |
| Jetson OS OTA | ✅ SWUpdate A/B | meta-tegrademo dynamic-layer로 이미 통합 존재 |
| RPi OS OTA | ✅ RAUC 또는 SWUpdate | Tegra 의존 없으므로 둘 다 가능 |
| 앱 OTA | ✅ Docker 이미지 교체 | OS 재부팅 없이 앱+라이브러리 통째 교체 |
| 디스플레이 구조 | ✅ 단일 디스플레이, wayland-2 소켓 | unified-compositor 하나가 IC+HU 전체 관리 |


---

## 현재 시스템 Wayland 구조 (단일 디스플레이)

```
[호스트]
  weston.service  →  wayland-1 소켓 생성
    └── unified-compositor.service  →  wayland-1 클라이언트 + wayland-2 서버 소켓 생성
          ├── IC 앱 3개  (WAYLAND_DISPLAY=wayland-2)
          │     speedometer-app, batterymeter-app, gearstate-app
          └── HU 앱 4개  (WAYLAND_DISPLAY=wayland-2)
                gearapp, homescreenapp, mediaapp, ambientapp

  vsomeip-routing-manager.service  (weston과 병렬, enP8p1s0 멀티캐스트 라우팅)
```

컨테이너화 후에도 **weston + vsomeip-routing-manager는 반드시 호스트에서 실행**.
unified-compositor도 Wayland 소켓을 생성하는 인프라 성격이므로 호스트 실행 권장.

---

## 역할 분담

| 영역 | leo | chang |
|------|-----|-------|
| 컨테이너 | HU 앱 컨테이너화 (gearapp, homescreen, media, ambient) | IC 앱 컨테이너화 (speedometer, batterymeter, gearstate) |
| OS OTA | RPi(Zonal ECU) A/B rootfs 업데이트 | Jetson(Infotainment) SWUpdate A/B 업데이트 |
| 앱 OTA | RPi VehicleControlECU 바이너리 업데이트 | Jetson HU/IC 컨테이너 이미지 업데이트 |
| 공동 | Jetson을 OTA 게이트웨이로 사용하는 파이프라인 구현 ||

---

## Phase 3: 컨테이너 격리

### Phase 3-0: 사전 준비 ✅ (완료)

- [x] Yocto 이미지에 Docker 추가 (`docker-moby 25.0.3`, 커밋 `acde3d32`)
- [x] cgroup v2 활성화 (`layer.conf`에 `UBOOT_EXTLINUX_KERNEL_ARGS:append`, 커밋 `9435347d`)
- [x] IC 앱 서비스 파일 bb 인라인 → 독립 `.service` 파일 분리 (커밋 `2bc8f961`)
- [x] Jetson에서 `docker run hello-world` 동작 확인 (root@192.168.86.247)

---

### Phase 3-1: leo — HU 앱 컨테이너화

**목표**: `gearapp`, `homescreenapp`, `mediaapp`, `ambientapp` 을 앱별 독립 컨테이너로 실행

#### 핵심 제약

```bash
# HU 앱 컨테이너 공통 실행 패턴
docker run \
  --network=host \                              # vsomeip 멀티캐스트 필수
  -v /run/user/1000:/run/user/1000 \            # Wayland 소켓 접근
  --user 1000:1000 \                            # UID=1000 (weston) 소켓 권한
  -e WAYLAND_DISPLAY=wayland-2 \               # unified-compositor 소켓
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_QUICK_BACKEND=software \               # GPU 불필요, /dev/dri 마운트 불필요
  -e QSG_RENDER_LOOP=basic \
  -e VSOMEIP_CONFIGURATION=/etc/vsomeip/routing_manager_ecu2.json \
  -e VSOMEIP_APPLICATION_NAME=GearApp \
  -e COMMONAPI_CONFIG=/usr/share/commonapi/commonapi.ini \
  --memory=512m --memory-swap=512m \           # cgroup 자원 경계
  --cpus=2.0 \
  hu-gearapp:1.0.0
```

> **WAYLAND_DISPLAY=wayland-2**: 단일 compositor 구조에서 모든 앱이 wayland-2 사용.
> 이전 문서의 wayland-3은 3-layer compositor 시절 값으로, 현재는 wayland-2가 맞다.

#### docker-compose.yml 구조 (실행 편의)

```yaml
# /etc/hu-apps/docker-compose.yml
# compose는 실행 편의 도구. 이미지는 각각 독립 (덩어리 아님).

x-hu-common: &hu-common
  network_mode: host
  user: "1000:1000"
  volumes:
    - /run/user/1000:/run/user/1000
  environment:
    WAYLAND_DISPLAY: wayland-2
    XDG_RUNTIME_DIR: /run/user/1000
    QT_QPA_PLATFORM: wayland
    QT_QUICK_BACKEND: software
    QSG_RENDER_LOOP: basic
    VSOMEIP_CONFIGURATION: /etc/vsomeip/routing_manager_ecu2.json
    COMMONAPI_CONFIG: /usr/share/commonapi/commonapi.ini
  restart: always

services:
  hu-gearapp:
    <<: *hu-common
    image: hu-gearapp:1.0.0          # 버전 태그 = OTA 단위
    mem_limit: 512m
    environment:
      <<: *hu-common  # 앵커 상속 + 앱별 추가
      VSOMEIP_APPLICATION_NAME: GearApp

  hu-homescreen:
    <<: *hu-common
    image: hu-homescreen:1.0.0
    environment:
      <<: *hu-common
      VSOMEIP_APPLICATION_NAME: HomeScreenApp

  hu-media:
    <<: *hu-common
    image: hu-media:1.0.0
    environment:
      <<: *hu-common
      VSOMEIP_APPLICATION_NAME: MediaApp

  hu-ambient:
    <<: *hu-common
    image: hu-ambient:1.0.0
    environment:
      <<: *hu-common
      VSOMEIP_APPLICATION_NAME: AmbientApp
```

#### 구현 순서

1. [x] `gearapp` 단독 컨테이너 실행 테스트
2. [x] vsomeip 연동 확인 — Client `010b` 등록, Gear 이벤트 수신 ✅
3. [x] wayland-2 소켓 마운트 + UID=1000 동작 확인 ✅
4. [x] `hu-gearapp:1.0.0` 이미지 빌드 및 태깅 ✅
5. [x] QML 화면 표시 확인 (`/usr/share/X11` 마운트로 xkb 경고 해결) ✅
6. [x] 나머지 3개 앱 컨테이너화 (homescreen, media, ambient) ✅
7. [x] `docker-compose.yml` 작성 및 전체 HU 그룹 실행 ✅
8. [x] systemd 서비스를 docker-compose 기반으로 교체 (`hu-apps.service`) ✅

---

### Phase 3-2: chang — IC 앱 컨테이너화

**목표**: `speedometer-app`, `batterymeter-app`, `gearstate-app` 컨테이너화

#### IC 앱 특이사항

- vsomeip 설정: `unicast: 127.0.0.1` (로컬호스트만) → HU 앱과 달리 외부 ECU 통신 없음
- `VehicleControlMock`이 동일 호스트에서 실행 중이어야 함
- `--network=host` 없어도 동작 가능하나 통일성을 위해 host 사용 권장

```bash
# IC 앱 컨테이너 공통 실행 패턴
docker run \
  --network=host \
  -v /run/user/1000:/run/user/1000 \
  --user 1000:1000 \
  -e WAYLAND_DISPLAY=wayland-2 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_QUICK_BACKEND=software \
  -e QSG_RENDER_LOOP=basic \
  -e VSOMEIP_CONFIGURATION=/etc/commonapi/vsomeip_speedometer.json \
  --memory=256m --memory-swap=256m \           # IC는 HU보다 작은 메모리 한도
  --cpus=1.0 \
  ic-speedometer:1.0.0
```

#### 구현 순서

1. [ ] `speedometer-app` 단독 컨테이너 테스트
2. [ ] `VehicleControlMock`과의 IPC 연동 확인 (unicast 127.0.0.1)
3. [ ] 나머지 2개 앱 컨테이너화
4. [ ] IC docker-compose.yml 작성

---

### Phase 3-3: 통합 검증 (공동)

- [ ] HU 컨테이너 + IC 컨테이너 동시 실행 시 화면 정상 표시 (단일 disp, wayland-2)
- [ ] cgroup 메모리 제한 효과 검증: HU 앱 메모리 강제 소비 시 IC 영향 없음 확인
- [ ] 컨테이너 crash 시 자동 재시작 (`restart: always`) 동작 확인
- [ ] SOME/IP 서비스 재시작 시 컨테이너 앱 graceful degradation 확인
- [ ] `docker-compose up -d --no-deps hu-gearapp`로 gearapp만 교체 테스트

---

## Phase 4: OTA 업데이트

### OTA 이중 구조 원칙

```
OS 레이어:   SWUpdate A/B 슬롯  →  커널/rootfs 변경 시 (재부팅 필요, 전체 이미지)
앱 레이어:   Docker 이미지 교체  →  앱/라이브러리 변경 시 (재부팅 없음, 수십 MB)
```

**컨테이너 OTA가 바이너리 직접 교체보다 나은 이유:**

| 관점 | 바이너리 교체 | 컨테이너 이미지 교체 |
|------|-------------|---------------------|
| 롤백 | ❌ 덮어씀 | ✅ 이전 이미지 태그 보존 |
| 라이브러리 업 | ❌ 호스트 전체 영향 | ✅ 이미지 내부만 변경 |
| 원자성 | ❌ 파일별 복사 | ✅ load 실패 = 기존 유지 |

---

### Phase 4-1: leo — RPi Zonal ECU OTA

#### Step 1: 앱 레벨 OTA (스크립트 기반, 개념 검증)

```bash
#!/bin/bash
# Jetson에서 실행하는 RPi 업데이트 스크립트
RPI_IP="192.168.1.100"
UPDATE_BIN="/tmp/VehicleControlECU_new"

# 1. 하드웨어 안전 정지 (모터/서보 PWM 0)
ssh root@${RPI_IP} "systemctl stop vehiclecontrol-ecu && sleep 1"

# 2. 바이너리 전송 + 교체
scp ${UPDATE_BIN} root@${RPI_IP}:/usr/bin/VehicleControlECU.new
ssh root@${RPI_IP} "mv /usr/bin/VehicleControlECU.new /usr/bin/VehicleControlECU && \
                    chmod +x /usr/bin/VehicleControlECU && \
                    systemctl start vehiclecontrol-ecu"
```

> ⚠️ `VehicleControlECU`는 pigpio 사용으로 root 권한 필요.
> 컨테이너화 시 `--cap-add SYS_RAWIO --device /dev/gpiomem --device /dev/i2c-1`.

#### Step 2: A/B rootfs OTA

```
RPi 파티션 목표:
  p1: boot  (FAT32, 공유)
  p2: rootfs_A  (현재)
  p3: rootfs_B  (대기)
  p4: data      (영구)
```

- [ ] RPi A/B 파티션 레이아웃 설계
- [ ] RAUC 또는 SWUpdate 설치 및 슬롯 설정
- [ ] 업데이트 번들 서명 인증서 생성
- [ ] 롤백 자동화 테스트

---

### Phase 4-2: chang — Jetson Infotainment OTA

#### Step 1: 컨테이너 이미지 OTA (앱 레이어)

```bash
# gearapp 단독 업데이트 (재부팅 없음)
docker load < hu-gearapp:1.0.1.tar.gz
docker-compose -f /etc/hu-apps/docker-compose.yml up -d --no-deps hu-gearapp

# 실패 시 롤백:
# docker-compose.yml에서 image: hu-gearapp:1.0.0 으로 변경 후 up
```

#### Step 2: OS A/B rootfs OTA (SWUpdate)

`meta-seame-ota` 레이어 이미 완성 (커밋 `bc240a74`):

```bash
# A/B 슬롯 확인
nvbootctrl dump-slots-info

# SWU 적용
swupdate -i seame-headunit-image.swu

# 재부팅 후 새 슬롯 부팅 → 성공 마크
nvbootctrl mark-boot-successful
```

- [ ] `bitbake seame-headunit-image` 빌드에 swupdate 포함 확인
- [ ] `.swu` 패키지 생성 및 서명 설정
- [ ] A→B 슬롯 업데이트 + 롤백 테스트
- [ ] 전원 차단 복구 테스트

---

### Phase 4-3: 공동 — Jetson OTA 게이트웨이

```
[Update Server (Oracle Cloud)]
      │ HTTPS TLS 1.3
      ▼
[Jetson OTA Gateway] (192.168.1.101)
      │ MQTT 알림 수신 → 패키지 다운로드 → 서명 검증 → 대상 판별
      │
      ├─→ IC/HU 앱: docker load + docker-compose up  (재부팅 없음)
      ├─→ Jetson OS: swupdate -i *.swu              (재부팅 필요)
      └─→ RPi: scp + ssh 또는 RAUC push             (RPi 재부팅)
```

- [ ] OTA 게이트웨이 데몬 구현 (Python 또는 Go)
- [ ] 업데이트 서버 구축 (HTTPS 파일 서버)
- [ ] 업데이트 매니페스트 형식 정의 (대상 ECU, 버전, 체크섬, 타입)
- [ ] 업데이트 결과 리포팅

---

## 전체 타임라인

```
Phase 3-0 ✅  Docker + cgroup v2 + IC 서비스 분리 완료
Phase 3-1 ✅  leo: HU 앱 4개 컨테이너화 + docker-compose + systemd 교체 완료
Phase 3-2 🔲  chang: IC 앱 컨테이너화
Phase 3-3 🔲  공동: 통합 검증 (단일 compositor + 전체 컨테이너)
Phase 4-1 🔲  leo: RPi 앱 레벨 OTA → A/B rootfs OTA
Phase 4-2 🔲  chang: 컨테이너 이미지 OTA → SWUpdate A/B OS OTA
Phase 4-3 🔲  공동: Jetson OTA 게이트웨이 파이프라인
```

---

## 핵심 파일 참조

| 항목 | 경로 |
|------|------|
| Docker 레이어 | `layers/meta-virtualization/` (bblayers.conf에 이미 있음) |
| SWUpdate OTA 레이어 | `layers/meta-seame-ota/conf/layer.conf` |
| SWUpdate Tegra 통합 | `layers/meta-tegrademo/dynamic-layers/meta-swupdate/` |
| Yocto 이미지 레시피 | `layers/meta-seame-headunit/recipes-core/images/seame-headunit-image.bb` |
| unified-compositor 서비스 | `recipes-apps/unified-compositor/files/unified-compositor.service` |
| HU 앱 서비스 파일 | `recipes-apps/{gearapp,homescreenapp,mediaapp,ambientapp}/files/*.service` |
| IC 앱 서비스 파일 | `recipes-apps/{speedometer,batterymeter,gearstate}-app/files/*.service` |
| vsomeip routing manager | `recipes-apps/vsomeip-service/` |
| weston.ini (portrait transform=90) | `recipes-graphics/wayland/weston-init/weston.ini` |

---

## 설계 원칙

1. **호스트 인프라 불변**: weston + vsomeip-routing-manager는 절대 컨테이너화 안 함
2. **앱별 독립 이미지**: HU 덩어리 X, 앱마다 이미지 하나 → gearapp 단독 OTA 가능
3. **OTA 이중 구조**: OS A/B (SWUpdate) + 앱 Docker 이미지 교체 (Tesla/AGL/SOAFEE 표준)
4. **롤백 경로 확보**: 이전 이미지 태그 보존, OS 슬롯 전환으로 모든 레이어에서 롤백 가능
5. **점진적 복잡도**: 단독 컨테이너 → compose → OTA → 게이트웨이 순서로 단계적 구현

