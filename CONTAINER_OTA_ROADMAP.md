# 컨테이너 격리 + OTA 업데이트 로드맵

> **작성일**: 2026-03-04  
> **기술 분석 원본**: `NEXT_PROJECT_ANALYSIS.md`  
> **역할 분담**: leo → HU 컨테이너 + RPi OTA / chang → IC 컨테이너 + Jetson OTA

---

## 결정 사항 요약

| 항목 | 결정 | 근거 |
|------|------|------|
| VM/하이퍼바이저 | ❌ 배제 | Jetson Orin Nano 미지원, 학습 곡선 과도 |
| 컨테이너 격리 | ✅ Docker + namespaces/cgroups | meta-virtualization 이미 bblayers.conf에 존재 |
| Jetson OTA | ✅ SWUpdate | meta-tegrademo dynamic-layer로 이미 통합 존재 |
| RPi OTA | ✅ RAUC 또는 SWUpdate | Tegra 의존 없으므로 둘 다 가능 |
| 디스플레이 | ✅ 단일 디스플레이 유지 | 디버깅 난이도, OTA 메인 집중, OS OTA 시 compositor도 함께 업데이트 |

---

## 역할 분담

| 영역 | leo | chang |
|------|-----|-------|
| 컨테이너 | HU 앱 컨테이너화 | IC 앱 컨테이너화 |
| OTA | RPi(Zonal ECU) 차량 제어 SW 업데이트 | Jetson 인포테인먼트 SW 업데이트 |
| 공동 | Jetson을 OTA 게이트웨이로 사용하여 무선 파일 수신 파이프라인 구현 ||

---

## Phase 3: 컨테이너 격리

### Phase 3-0: 사전 준비 (공동)

- [ ] Yocto 이미지에 Docker 추가
  ```bitbake
  # seame-headunit-image.bb
  IMAGE_INSTALL:append = " docker-moby"
  ```
  > `meta-virtualization`이 이미 `bblayers.conf`에 있으므로 레이어 추가 불필요

- [ ] cgroup v2 활성화 확인
  ```bash
  # 보드에서:
  cat /sys/fs/cgroup/cgroup.controllers
  # 비어있으면 local.conf에 추가:
  # APPEND:append = " systemd.unified_cgroup_hierarchy=1"
  ```

- [ ] IC 앱 서비스 파일 bb 인라인 → 별도 .service 파일로 분리 (leo)
  > 현재 IC 앱 3개는 bb 파일 안에 heredoc으로 서비스 유닛 정의.
  > 컨테이너 환경변수 수정 시 전체 재빌드 필요하므로 HU 앱처럼 분리 필요.

---

### Phase 3-1: leo — HU 앱 컨테이너화

**목표**: `gearapp`, `homescreenapp`, `mediaapp`, `ambientapp` 을 Docker 컨테이너로 실행

**핵심 제약 (반드시 지켜야 동작):**

1. **Wayland 소켓 마운트**  
   현재 앱들은 `WAYLAND_DISPLAY=wayland-2`, 소켓 경로 `/run/user/1000/wayland-2`
   ```bash
   docker run \
     -v /run/user/1000:/run/user/1000 \
     --user 1000:1000 \
     -e WAYLAND_DISPLAY=wayland-2 \
     -e XDG_RUNTIME_DIR=/run/user/1000 \
     -e QT_QPA_PLATFORM=wayland \
     -e QT_QUICK_BACKEND=software \
     -e QSG_RENDER_LOOP=basic \
     hu-gearapp:latest
   ```

2. **vsomeip 네트워크**  
   HU 앱들은 `192.168.1.101` unicast + SOME/IP 멀티캐스트 사용
   ```bash
   docker run --network=host ...
   ```
   > vsomeip routing manager는 반드시 호스트에서 실행. 컨테이너에서 실행하면
   > `enP8p1s0` 인터페이스를 찾지 못해 multicast 라우팅 실패.

3. **GPU 불필요** (`QT_QUICK_BACKEND=software`)  
   → `/dev/dri` 마운트 없어도 동작

4. **User UID=1000 (weston)**  
   소켓 권한이 UID=1000 소유이므로 컨테이너 내 사용자도 UID=1000이어야 함

**구현 순서:**
1. `gearapp` 단독 컨테이너 실행 테스트 (가장 단순한 앱으로 시작)
2. vsomeip 연동 확인 (PRND 표시 동작 여부)
3. 나머지 3개 앱 컨테이너화
4. `docker-compose.yml`로 HU 앱 그룹 정의
5. systemd 서비스를 `docker run`으로 교체

**cgroup 리소스 제한 예시 (학습 목적):**
```bash
docker run \
  --cpus="2.0" \
  --memory="512m" \
  --memory-swap="512m" \
  hu-gearapp:latest
```

---

### Phase 3-2: chang — IC 앱 컨테이너화

**목표**: `speedometer-app`, `batterymeter-app`, `gearstate-app` 컨테이너화

**IC 앱 특이사항:**
- vsomeip 설정: `unicast: 127.0.0.1` (로컬호스트만) → `--network=host` 없어도 동작 가능
- `VehicleControlMock`이 동일 호스트에서 실행 중이어야 함
  → Mock 컨테이너 또는 호스트 실행 중 선택 필요

**구현 순서:**
1. IC 앱 서비스 파일 bb 인라인 → 별도 .service 파일로 분리 (선행 작업)
2. `speedometer-app` 단독 컨테이너 테스트
3. `VehicleControlMock`과의 IPC 연동 확인
4. 나머지 2개 앱 컨테이너화

---

### Phase 3-3: 통합 검증 (공동)

- [ ] HU 컨테이너 + IC 컨테이너 동시 실행 시 화면 정상 표시
- [ ] SOME/IP 서비스 재시작 시 컨테이너 앱 graceful degradation 확인
- [ ] cgroup 리소스 제한 적용 후 성능 측정
- [ ] 컨테이너 crash 시 자동 재시작 (`--restart=on-failure`) 동작 확인

---

## Phase 4: OTA 업데이트

### Phase 4-1: leo — RPi Zonal ECU OTA

**목표**: RPi의 `VehicleControlECU` 바이너리를 Jetson OTA 게이트웨이를 통해 업데이트

#### Step 1: 앱 레벨 OTA (스크립트 기반)

```bash
# Jetson에서 실행하는 RPi 업데이트 스크립트 (개념 검증용)
#!/bin/bash
RPI_IP="192.168.1.100"
UPDATE_BIN="/tmp/VehicleControlECU_new"

# 1. 모터/서보 안전 정지 (하드웨어 보호)
ssh root@${RPI_IP} "systemctl stop vehiclecontrol-ecu && sleep 1"

# 2. 바이너리 전송
scp ${UPDATE_BIN} root@${RPI_IP}:/tmp/

# 3. 교체 및 재시작
ssh root@${RPI_IP} "cp /tmp/VehicleControlECU_new /usr/bin/VehicleControlECU && \
                     chmod +x /usr/bin/VehicleControlECU && \
                     systemctl start vehiclecontrol-ecu"
```

> ⚠️ `VehicleControlECU`는 pigpio 사용으로 root 권한 필요.
> 컨테이너화 시 `--cap-add SYS_RAWIO --device /dev/gpiomem --device /dev/i2c-1` 사용.

#### Step 2: A/B rootfs OTA (RAUC 또는 SWUpdate)

**RPi 파티션 구조 목표:**
```
/dev/mmcblk0:
  p1: boot  (FAT32, 공유)
  p2: rootfs_A  (현재 부팅 중)
  p3: rootfs_B  (업데이트 대기)
  p4: data      (영구 보관)
```

- [ ] RPi A/B 파티션 레이아웃 설계 및 적용
- [ ] RAUC 또는 SWUpdate 설치 및 슬롯 설정
- [ ] 업데이트 번들 서명 인증서 생성
- [ ] 롤백 자동화 테스트 (업데이트 실패 시 A 슬롯으로 복귀)

---

### Phase 4-2: chang — Jetson Infotainment OTA

**목표**: Yocto rootfs 전체를 A/B 방식으로 무중단 업데이트

**도구: SWUpdate** (meta-tegrademo에 dynamic-layer로 이미 통합됨)

#### 활성화 방법:
```bash
# 1. meta-swupdate 서브모듈 추가
cd repos
git submodule add https://github.com/sbabic/meta-swupdate
cd ../layers && ln -s ../repos/meta-swupdate

# 2. local.conf 추가
USE_REDUNDANT_FLASH_LAYOUT = "1"     # A/B 파티션 자동 구성
IMAGE_INSTALL:append = " swupdate"
IMAGE_FSTYPES:append = " tar.gz"

# 3. 빌드
bitbake swupdate-image-tegra
```

#### A/B 슬롯 확인:
```bash
nvbootctrl dump-slots-info
# Current boot slot: 0  ← A슬롯 부팅 중
```

- [ ] `meta-swupdate` 통합 및 `USE_REDUNDANT_FLASH_LAYOUT = "1"` 적용
- [ ] `bitbake swupdate-image-tegra` 빌드 테스트
- [ ] 업데이트 번들 서명 설정
- [ ] 업데이트 적용 후 `nvbootctrl`로 슬롯 전환 확인
- [ ] 전원 차단 복구 테스트 (업데이트 중 강제 종료 → 이전 슬롯으로 자동 복귀)

---

### Phase 4-3: 공동 — Jetson OTA 게이트웨이

**목표**: Jetson이 외부(클라우드/서버)에서 업데이트를 받아 각 ECU에 배포하는 파이프라인

```
[Update Server]
      │ HTTPS (TLS 1.3)
      ▼
[Jetson OTA Gateway] (192.168.1.101)
      │ 업데이트 수신 + 서명 검증 + 대상 ECU 판별
      │
      ├─→ 자신의 Yocto rootfs 업데이트 (SWUpdate)
      │
      └─→ RPi에 업데이트 전달 (SSH/SCP + RAUC)
              │
              ▼
        [RPi Zonal ECU] (192.168.1.100)
```

**구현 요소:**
- [ ] OTA 게이트웨이 데몬 구현 (Python 또는 Go)
  - HTTPS 다운로드
  - 서명 검증 (X.509)
  - 대상 ECU 식별 및 라우팅
- [ ] 업데이트 서버 구축 (간단한 HTTPS 파일 서버)
- [ ] 업데이트 매니페스트 형식 정의 (버전, 대상, 체크섬)
- [ ] 업데이트 결과 리포팅

---

## 전체 타임라인

```
Phase 3-0 (사전 준비)     : Docker 이미지 추가, cgroup 확인, IC 서비스 파일 분리
Phase 3-1 (leo HU)        : HU 앱 컨테이너화
Phase 3-2 (chang IC)      : IC 앱 컨테이너화
Phase 3-3 (공동 통합)      : 전체 컨테이너 동시 실행 검증
Phase 4-1 (leo RPi OTA)   : RPi 앱 레벨 → A/B OTA
Phase 4-2 (chang Jetson)  : SWUpdate A/B rootfs OTA
Phase 4-3 (공동 Gateway)  : Jetson OTA 게이트웨이 파이프라인
```

---

## 핵심 파일/경로 참조

| 항목 | 경로 |
|------|------|
| Docker 레이어 | `layers/meta-virtualization/` (이미 bblayers.conf에 있음) |
| SWUpdate Tegra 통합 | `layers/meta-tegrademo/dynamic-layers/meta-swupdate/` |
| Yocto 이미지 레시피 | `layers/meta-seame-headunit/recipes-core/images/seame-headunit-image.bb` |
| unified-compositor 서비스 | `recipes-apps/unified-compositor/files/unified-compositor.service` |
| HU 앱 서비스 파일 | `recipes-apps/{gearapp,homescreenapp,mediaapp,ambientapp}/files/*.service` |
| IC 앱 bb (inline service) | `recipes-apps/{speedometer,batterymeter,gearstate}-app/*_1.0.bb` |
| vsomeip routing manager | `recipes-apps/vsomeip-service/` |
| weston.ini | `recipes-graphics/wayland/weston-init/weston.ini` |

---

## 설계 원칙

1. **점진적 복잡도**: 스크립트 → 컨테이너 → OTA → 보안 순서로 단계적으로
2. **기존 스택 보존**: vsomeip, Qt, Wayland는 동작 중. 컨테이너 안으로 이동하는 것, 교체가 아님
3. **롤백 경로 확보**: OTA는 실패 시 자동 롤백 설계 필수
4. **검증 가능한 마일스톤**: "OTA 성공"보다 "업데이트 후 GearApp 정상 표시" 단위로 검증
5. **역할 독립성**: HU(leo)와 IC(chang)는 서로 다른 Wayland 소켓/vsomeip 서비스 사용 → 병렬 개발 가능
