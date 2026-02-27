# OTA (Over-The-Air) 업데이트 학습 문서

> 작성 기준: `OTA_Head-Unit` 레포 + `tegra-demo-distro/NEXT_PROJECT_ANALYSIS.md` 참조  
> 대상 독자: OTA를 처음 접하는 임베디드 개발자

---

## 목차

1. [OTA 기본 개념](#1-ota-기본-개념)
2. [OTA_Head-Unit 레포 분석](#2-ota_head-unit-레포-분석)
3. [우리 프로젝트와의 연관성](#3-우리-프로젝트와의-연관성)

---

# 1. OTA 기본 개념

## 1.1 OTA란 무엇인가

**OTA(Over-The-Air)**는 네트워크를 통해 기기의 소프트웨어/펌웨어를 원격으로 업데이트하는 기술이다.  
스마트폰, 자동차, IoT 기기 등에서 물리적 접근 없이 업데이트를 배포할 수 있다.

```
[개발자 PC] → [업데이트 서버] → (인터넷/네트워크) → [차량/기기]
                                                         ↓
                                                    업데이트 적용
                                                    자동 재부팅
```

자동차에서 OTA가 중요한 이유:
- 차량이 딜러에 가지 않아도 버그 수정/기능 추가 가능
- Tesla가 대중화 → 현재 모든 OEM의 최우선 요구사항
- ECU(전자 제어 장치) 수십 개를 동시 관리해야 함

---

## 1.2 업데이트 스코프: 무엇을 업데이트하는가

OTA 업데이트는 크게 두 가지 레벨로 나뉜다.

### Scope 1 — 앱/서비스 레벨 업데이트

```
변경 대상: 앱 바이너리, 설정 파일, 개별 패키지
방법:      파일 복사 + systemd restart
위험도:    낮음 (앱만 교체, OS 무결)
A/B 필요:  No (롤백은 이전 패키지 버전으로)
예시:      Tesla에서 게임 앱 추가, 네비게이션 지도 업데이트
```

Linux 패키지 매니저 방식 (`rpm`, `deb`, `ipk`)이 여기에 해당한다.

### Scope 2 — OS/펌웨어 레벨 업데이트

```
변경 대상: Linux 커널, rootfs 전체, 부트로더
방법:      A/B 파티셔닝 필수 (실패 시 벽돌 방지)
위험도:    높음 (잘못되면 부팅 불가 → 차량이 멈춤)
A/B 필요:  Yes, 강력 권장
예시:      자동차 OEM의 ECU 펌웨어 리콜 업데이트
```

---

## 1.3 A/B 파티셔닝: OTA의 핵심 안전장치

OS 업데이트의 가장 큰 위험은 **업데이트 도중 전원이 꺼지면 기기가 벽돌이 된다**는 것이다.  
이를 해결하기 위해 A/B 파티셔닝(=Dual Bank, Redundant Update)을 사용한다.

```
┌──────────────────────────────────────────────────────────┐
│                    저장 장치 (SD/eMMC)                    │
│                                                          │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐            │
│  │  /boot    │  │ rootfs-A  │  │ rootfs-B  │  /data     │
│  │  (공용)   │  │ (슬롯 A) │  │ (슬롯 B) │  (영구)   │
│  │           │  │           │  │           │            │
│  │  커널     │  │ ★현재     │  │  대기      │            │
│  │  U-Boot   │  │  부팅 중  │  │ (업데이트  │            │
│  │  DTB      │  │           │  │  대상)     │            │
│  └───────────┘  └───────────┘  └───────────┘            │
└──────────────────────────────────────────────────────────┘
```

**업데이트 순서:**

```
1. 현재 슬롯 A에서 실행 중
2. 새 이미지를 슬롯 B에 기록 (A는 그대로)
3. 부트로더에게 "다음 부팅은 B 슬롯으로" 지시
4. 재부팅
5. B 슬롯으로 부팅 성공 → "부팅 성공 마커" 기록
6. 이후 부팅도 B 슬롯 사용 (A는 롤백용으로 유지)

실패 시:
5. B 슬롯 부팅 실패 (커널 패닉, watchdog 등)
6. 부트로더가 실패 감지 (boot_count > max)
7. 자동으로 A 슬롯으로 롤백
```

**핵심 보장**: 새 이미지가 아무리 망가져도 이전 슬롯으로 자동 복구된다.

---

## 1.4 부트로더의 역할

부트로더(U-Boot, GRUB 등)는 A/B OTA의 핵심 조율자다.

```
부트로더가 관리하는 환경 변수:
  ota_slot          = "a" 또는 "b"   → 어느 슬롯으로 부팅할지
  ota_boot_count    = 0, 1, 2, ...   → 현재 슬롯 부팅 시도 횟수
  ota_boot_max      = 3              → 최대 허용 시도 횟수
  ota_rollback_done = 0 또는 1       → 이미 롤백을 했는지
```

**U-Boot 부트 결정 로직:**

```
부팅 시작
  │
  ├── ota_boot_count++
  │
  ├── count <= max(3)?
  │     YES → 현재 ota_slot으로 부팅 시도
  │     NO  → rollback_done?
  │             NO  → 슬롯 전환 + rollback_done=1 + 재부팅
  │             YES → RESCUE 모드 (부트 딜레이 60초, UART 개입)
  │
  └── 부팅 성공 시
        → des-ota-boot-ok.sh: ota_boot_count=0 으로 리셋
           → "이 슬롯은 건강하다" 표시
```

부트카운터 리셋이 핵심이다. 성공적으로 부팅하면 카운터를 0으로 리셋해야  
다음 OTA 업데이트 때 다시 3번의 시도 기회가 주어진다.

---

## 1.5 Manifest: 업데이트 메타데이터

OTA 서버는 새 버전이 나오면 단순히 파일만 올리는 게 아니라  
**manifest.json**이라는 메타데이터 파일을 함께 배포한다.

```json
{
  "version": "1.0.1",
  "artifact": {
    "type": "rpm",           // rpm(앱 업데이트) 또는 image(OS 업데이트)
    "name": "headunit-1.0.1-r0.cortexa72.rpm",
    "url": "https://...",    // 실제 파일 다운로드 URL
    "sha256": "ea2a34...",   // 무결성 검증용 해시
    "size": 292148
  },
  "apply": {
    "reboot_required": true, // 재부팅 필요 여부
    "downtime_hint_sec": 30  // 예상 다운타임(초)
  },
  "rollback": {
    "strategy": "rpm-history",
    "max_attempts": 1
  },
  "signature": {
    "algo": "ed25519",       // 서명 알고리즘 (보안 검증)
    "value": "",
    "key_id": ""
  }
}
```

기기는 manifest를 먼저 다운로드해서 **"이 업데이트가 나에게 맞는가"**, **"파일이 변조되지 않았는가"**를 검증한 뒤에 실제 파일을 받는다.

---

## 1.6 SHA256 무결성 검증

파일 전송 중 손상이나 변조를 감지하기 위해 SHA256 해시를 사용한다.

```
서버:  sha256sum artifact.rpm → "ea2a34..." → manifest에 기록
클라이언트:
  1. manifest 다운로드 → sha256 값 확인
  2. artifact.rpm 다운로드
  3. sha256sum artifact.rpm → 계산한 해시
  4. 계산한 해시 == manifest의 sha256?
       YES → 안전, 적용
       NO  → 파일 손상 또는 변조! 중단
```

---

## 1.7 MQTT: 업데이트 알림 프로토콜

OTA 서버가 기기에 "새 업데이트가 있다"고 알리는 방법으로 **MQTT**를 자주 사용한다.

```
MQTT란?
- IoT에 최적화된 경량 pub/sub 메시지 프로토콜
- 브로커(중개 서버)를 통해 메시지 교환
- 기기가 항상 연결을 유지할 필요 없음 (QoS 1 = 최소 1회 전달 보장)

토픽 예시: des/ota/hu/HU-001/notify

서버 → 브로커 → 기기
  mosquitto_pub -h broker -t "des/ota/hu/HU-001/notify" -m '{"manifest_url": "..."}'
```

기기는 MQTT를 **구독(subscribe)**하고 있다가 메시지가 오면 OTA를 시작한다.

---

## 1.8 업데이트 시간 창 (Update Window)

차량이나 기기를 갑자기 재부팅하면 안 되는 상황이 있다.  
(예: 주행 중, 고객이 화면을 보는 중)

OTA 클라이언트는 **Update Window**를 설정할 수 있다.

```
UPDATE_WINDOW_START = "02:00"  # 새벽 2시부터
UPDATE_WINDOW_END   = "04:00"  # 새벽 4시까지만 적용

동작:
- 창 밖: 다운로드만 하고 pending(대기) 파일에 저장
- 창 안: 다운로드 + 즉시 적용 + 재부팅
- des-ota-apply.timer: 매일 02:00에 pending 파일 적용 시도
```

---

## 1.9 OTA 전체 구조 요약

```
┌─────────────────────────────────────────────────────────────────────┐
│                         OTA 전체 흐름                                │
│                                                                      │
│  개발자                서버                       기기               │
│    │                    │                          │                 │
│    │ 새 버전 빌드        │                          │                 │
│    │──────────────────→ │ artifact 업로드           │                 │
│    │                    │ manifest.json 생성        │                 │
│    │                    │ SHA256 계산               │                 │
│    │                    │──────── MQTT 발행 ──────→ │                 │
│    │                    │   "manifest_url": "..."   │                 │
│    │                    │                          │ manifest 다운로드│
│    │                    │ ←──────────────────────── │ artifact 다운로드│
│    │                    │                          │ SHA256 검증     │
│    │                    │                          │ 적용            │
│    │                    │                          │ 재부팅          │
│    │                    │                          │ boot-ok 마커    │
└─────────────────────────────────────────────────────────────────────┘
```

---

# 2. OTA_Head-Unit 레포 분석

## 2.1 레포 개요

| 항목 | 내용 |
|------|------|
| 대상 기기 | Raspberry Pi 4 (Head-Unit) |
| OS | Yocto Linux (poky 기반) |
| 아키텍처 | ARM Cortex-A72 |
| 업데이트 방식 | RPM 패키지 OTA + A/B 이미지 OTA |
| 알림 방식 | MQTT (`mosquitto`) |
| 저장소 | Oracle Cloud OCI Object Storage |
| 서명 알고리즘 | ed25519 (미구현, TODO 상태) |

---

## 2.2 디렉토리 구조

```
OTA_Head-Unit/
├── ota/                          ← OTA 구현의 핵심
│   ├── client/
│   │   ├── daemon/
│   │   │   └── main.cpp          ← OTA 클라이언트 데몬 (C++)
│   │   ├── scripts/
│   │   │   ├── des-ota-image-apply.sh  ← A/B 이미지 적용
│   │   │   └── des-ota-boot-ok.sh      ← 부팅 성공 마커
│   │   ├── systemd/
│   │   │   ├── des-ota-listener.service   ← MQTT 상시 수신
│   │   │   ├── des-ota-apply.service      ← pending 적용
│   │   │   ├── des-ota-apply.timer        ← 매일 02:00 실행
│   │   │   └── des-ota-boot-ok.service    ← 부팅 후 카운터 리셋
│   │   └── ota-client.env        ← 클라이언트 설정 (MQTT, 경로 등)
│   ├── server/
│   │   ├── release.sh            ← 릴리즈 자동화 스크립트
│   │   ├── release.env           ← 릴리즈 설정 변수
│   │   └── manifest.schema.json  ← manifest 구조 스키마
│   └── releases/
│       ├── 1.0.0/manifest.json   ← RPM OTA: des-ota-clientd 업데이트
│       └── 1.0.1/manifest.json   ← RPM OTA: headunit 앱 업데이트
├── yocto-workspace/
│   ├── meta-custom/
│   │   ├── meta-app/             ← 앱 레이어 (OTA 클라이언트 포함)
│   │   ├── meta-env/             ← 환경 레이어 (A/B WKS 파티션 정의)
│   │   └── meta-piracer/         ← PiRacer 하드웨어 레이어
│   └── build-des/conf/local.conf
├── DES_Instrument-Cluster/       ← IC (계기판) 관련 코드
├── Head-Unit/                    ← HU Qt 앱 소스
└── ARCHITECTURE.md
```

---

## 2.3 OTA 클라이언트 데몬 (`main.cpp`) 분석

`des-ota-clientd`는 C++로 작성된 단일 실행 파일이다. 세 가지 모드로 동작한다.

### 실행 모드

```
des-ota-clientd --listen           # MQTT 구독 → 메시지 오면 자동 처리
des-ota-clientd --apply-pending    # 대기 중인 업데이트 즉시 적용
des-ota-clientd --apply-manifest <URL>  # 특정 manifest URL로 즉시 업데이트
```

### 설정 구조 (`Config` struct)

```cpp
struct Config {
  // MQTT 설정
  mqtt_broker = "127.0.0.1"  // 브로커 주소
  mqtt_topic = "#"            // 구독 토픽 (ota-client.env에서 덮어씀)
  mqtt_qos = 1                // QoS 레벨

  // 경로 설정
  download_dir   = "/var/lib/des-ota/downloads"
  state_dir      = "/var/lib/des-ota"
  log_dir        = "/var/log/des-ota"

  // 업데이트 명령
  rpm_apply_cmd        // RPM 적용 명령 (예: "rpm -Uvh $ARTIFACT_PATH")
  image_apply_cmd      // 이미지 적용 명령 (des-ota-image-apply.sh 경로)
  rollback_cmd         // 롤백 명령
  reboot_cmd           // 재부팅 명령 ("systemctl reboot")

  // 업데이트 창
  update_window_start  // "02:00"
  update_window_end    // "04:00"
  apply_immediately    // true이면 창 무시하고 즉시 적용
};
```

### 핵심 처리 흐름 (`process_manifest`)

```
1. 업데이트 창 확인 → 창 밖이면 다운로드만 (pending 파일 저장)
2. manifest.json 다운로드 (curl 또는 wget)
3. manifest 파싱 (정규식으로 JSON 파싱 — 외부 라이브러리 없음)
4. 서명 필드 존재 확인 (require_signature=true 시)
   ⚠️ 실제 암호학적 검증은 미구현 (TODO 주석 있음)
5. artifact 파일 다운로드
6. SHA256 검증 (sha256sum 명령 사용)
7. pending 파일에 저장 (artifact_path, sha256, version 등)
8. 업데이트 창이면 → apply_artifact() 호출
9. reboot_required=true이면 → reboot_cmd 실행
```

### 로그 구조

```
일반 로그:  /var/log/des-ota/ota-clientd.log
이벤트 로그: /var/log/des-ota/ota-events.jsonl (JSON Lines 형식)
상태 파일:  /var/lib/des-ota/state.env
대기 파일:  /var/lib/des-ota/pending-image.env (이미지)
            /var/lib/des-ota/pending-package.env (RPM)
```

`ota-events.jsonl` 예시:
```json
{"ts":"2026-01-29T09:17:29Z","device":{"device_id":"HU-001"},"ota":{"ota_id":"1.0.1","current_version":"1.0.0","target_version":"1.0.1","phase":"VERIFY","event":"SUCCESS"},"evidence":{...}}
```

---

## 2.4 A/B 이미지 적용 스크립트 (`des-ota-image-apply.sh`)

이 스크립트가 실제로 새 OS 이미지를 SD 카드에 기록하는 핵심 로직이다.

### 지원 이미지 포맷

```bash
.ext4        # 비압축 ext4 rootfs
.ext4.bz2    # bzip2 압축 ext4 rootfs  ← 주로 사용
.ext4.gz     # gzip 압축
.ext4.xz     # xz 압축
# .wic는 전체 디스크 이미지 → 지원 안 함 (A/B는 rootfs 파티션만)
```

### 실행 단계별 설명

```bash
# 1. 현재 활성 슬롯 확인
CURRENT_SLOT=$(fw_printenv -n ota_slot)  # "a" 또는 "b"

# 2. 비활성 파티션 결정
if CURRENT_SLOT == "a":
    TARGET_DEV = "/dev/mmcblk0p3"  # 슬롯 B
    NEW_SLOT = "b"
else:
    TARGET_DEV = "/dev/mmcblk0p2"  # 슬롯 A
    NEW_SLOT = "a"

# 3. 안전 검사: 현재 마운트된 rootfs에 쓰지 않도록
# (findmnt + /proc/cmdline으로 현재 활성 rootfs 감지)
if TARGET_DEV == 현재_마운트된_rootfs:
    die "SAFETY: 활성 rootfs에 쓰려 함 — 중단"

# 4. 이미지 기록 (비압축/압축 자동 처리)
bzip2 -dc artifact.ext4.bz2 | dd of=/dev/mmcblk0p3 bs=4M iflag=fullblock conv=fsync

# 5. 파일시스템 무결성 검증
e2fsck -pf /dev/mmcblk0p3

# 6. U-Boot 환경 변수 업데이트
fw_setenv ota_slot "b"
fw_setenv ota_boot_count 0
fw_setenv ota_rollback_done 0

# 이후 des-ota-clientd가 systemctl reboot 호출
```

### Fallback 모드 (U-Boot 없는 경우)

U-Boot 환경 변수(`fw_printenv`)를 사용할 수 없는 경우,  
`/boot/cmdline.txt`의 `root=` 파라미터를 직접 수정하는 fallback이 있다.  
단, 이 경우 자동 롤백이 불가능하다는 경고가 출력된다.

---

## 2.5 부팅 성공 마커 (`des-ota-boot-ok.sh`)

```bash
# 시스템이 multi-user.target에 도달하면 실행
SLOT=$(fw_printenv -n ota_slot)       # 현재 슬롯
COUNT=$(fw_printenv -n ota_boot_count) # 현재 카운트

echo "Slot=${SLOT}  boot_count=${COUNT} → resetting to 0"

fw_setenv ota_boot_count 0   # 카운터 리셋 → "이 슬롯은 건강함"
fw_setenv ota_rollback_done 0
fw_setenv bootdelay 2         # 부트 딜레이를 정상값으로 복원
```

이 스크립트가 실행되지 않으면 `ota_boot_count`가 계속 올라가서  
결국 U-Boot가 이 슬롯을 "불량"으로 판단하고 롤백을 시도한다.

---

## 2.6 systemd 서비스 구성

```
부팅 순서:
  network-online.target
    │
    ├── des-ota-listener.service  (Type=simple, Restart=always)
    │     MQTT 상시 구독 → 업데이트 메시지 오면 처리
    │
    └── des-ota-apply.timer → 매일 02:00
          └── des-ota-apply.service (Type=oneshot)
                --apply-pending 실행 → 대기 중인 업데이트 적용

  multi-user.target
    └── des-ota-boot-ok.service (Type=oneshot, RemainAfterExit=yes)
          부트 카운터 리셋 → "이번 부팅 성공" 표시
```

**각 서비스 역할 정리:**

| 서비스 | 역할 | 실행 조건 |
|--------|------|-----------|
| `des-ota-listener` | MQTT 구독 상시 대기 | 네트워크 연결 후 항상 실행 |
| `des-ota-apply` | pending 업데이트 적용 | 타이머에 의해 매일 02:00 |
| `des-ota-boot-ok` | 부팅 성공 마커 기록 | 매 부팅 시 (multi-user.target) |

---

## 2.7 서버 측: `release.sh` 분석

`release.sh`는 새 버전을 배포할 때 개발자가 실행하는 스크립트다.

```bash
# release.env 설정 예시:
VERSION="1.0.2"
ARTIFACT_TYPE="rpm"                      # 또는 "image"
ARTIFACT_PATH="./headunit-1.0.2.rpm"
ARTIFACT_URL="https://cloud.../headunit-1.0.2.rpm"
MANIFEST_URL="https://cloud.../1.0.2/manifest.json"
MQTT_BROKER="129.159.241.110"
MQTT_TOPIC="des/ota/hu/HU-001/notify"
OCI_UPLOAD_ARTIFACT="true"
OCI_UPLOAD_MANIFEST="true"
```

```bash
./release.sh  # 실행 시 자동으로:
  # 1. ARTIFACT_PATH 파일 존재 확인
  # 2. SHA256 계산
  # 3. manifest.json 생성 (Python 인라인 스크립트)
  # 4. OCI 오브젝트 스토리지에 artifact + manifest 업로드
  # 5. MQTT 발행 → 기기에 알림
```

---

## 2.8 Manifest 실제 예시

**v1.0.0: OTA 클라이언트 자체 업데이트**
```json
{
  "version": "1.0.0",
  "artifact": {
    "type": "rpm",
    "name": "des-ota-clientd-1.0-r0.cortexa72.rpm",
    "url": "https://objectstorage.eu-frankfurt-1.oraclecloud.com/.../1.0.0/...",
    "sha256": "d38be1205e604a9797eb99be1daa720bfcaff9edba34c89db705981dbcb132b4",
    "size": 84137
  },
  "compatible": { "model": "DES-HU", "hw": "rpi4" },
  "apply": { "reboot_required": true, "downtime_hint_sec": 30 }
}
```

**v1.0.1: Head-Unit 앱 업데이트**
```json
{
  "version": "1.0.1",
  "artifact": {
    "type": "rpm",
    "name": "headunit-1.0.1-r0.cortexa72.rpm",
    "url": "https://objectstorage.eu-frankfurt-1.oraclecloud.com/.../1.0.1/...",
    "sha256": "ea2a348380cb2764fbe5eac31c0bd57d78045f0e2f3d62d68b6e25fb3c6b7e03",
    "size": 292148
  },
  "release": { "notes": "Headunit update (Navigation address change)." },
  "apply": { "reboot_required": true }
}
```

두 버전 모두 현재 `signature.value = ""`로 서명 검증이 미구현 상태다.

---

## 2.9 A/B 파티션 SD 카드 레이아웃

```
┌──────────┬──────────────┬──────────────┬───────────────┐
│  p1      │  p2          │  p3          │  p4           │
│  /boot   │  rootfs-a    │  rootfs-b    │  /data        │
│  vfat    │  ext4        │  ext4        │  ext4         │
│  128 MB  │  2.5 GB      │  2.5 GB      │  1 GB+        │
│          │  슬롯 A      │  슬롯 B      │  다운로드     │
│  커널    │  (활성 or    │  (활성 or    │  상태/로그    │
│  DTB     │   비활성)    │   비활성)    │  사용자 데이터│
│  U-Boot  │              │              │               │
│  boot.scr│              │              │               │
└──────────┴──────────────┴──────────────┴───────────────┘

WKS 파일: meta-env/wic/des-ab-sdimage.wks
```

`/data` 파티션은 OTA 업데이트 시에도 삭제되지 않는 영구 파티션이다.  
다운로드된 이미지, OTA 상태 파일, 로그, 사용자 데이터를 여기에 저장한다.

---

## 2.10 자동 롤백 상태 머신 전체 그림

```
부팅 시작
  │
  ▼
U-Boot: ota_boot_count++
  │
  ├── count <= ota_boot_max(3)?
  │     YES: ota_slot에 해당하는 파티션으로 부팅
  │     NO: rollback_done?
  │           NO:  슬롯 전환 (a↔b) + rollback_done=1 + 재부팅
  │           YES: RESCUE (bootdelay=60, UART 개입 대기)
  │
  ▼
커널 부팅 + 앱 실행
  │
  ├── 성공 (multi-user.target 도달):
  │     des-ota-boot-ok.service 실행
  │     → boot_count=0, rollback_done=0, bootdelay=2
  │     → "이 슬롯은 안전하다" 확정
  │
  └── 실패 (커널 패닉 / watchdog):
        재부팅 → 다시 U-Boot 시작
        boot_count가 max 초과할 때까지 반복
        → 자동 롤백
```

---

# 3. 우리 프로젝트와의 연관성

## 3.1 시스템 비교

| 항목 | OTA_Head-Unit 레포 | 우리 프로젝트 (tegra-demo-distro) |
|------|--------------------|------------------------------------|
| 기기 | Raspberry Pi 4 | **Jetson Orin Nano** (HU) + RPi 4 (ECU) |
| 아키텍처 | ARM Cortex-A72 | **ARM Cortex-A78AE** (Jetson) |
| 부트로더 | U-Boot | **NVIDIA CBoot/UEFI** (Jetson 고유) |
| A/B 파티셔닝 | SD카드 4파티션 (WKS) | **미구현** (현재 단일 파티션) |
| OTA 클라이언트 | des-ota-clientd (C++) | 없음 (미구현) |
| OTA 서버 | Oracle OCI + MQTT | 없음 (미구현) |
| Yocto | poky 기반 meta-custom | **tegra-demo-distro** (OE4T) |
| 앱 패키징 | RPM | RPM (동일) |
| 앱 구성 | Qt6, HomeScreen, IC | Qt6, HU앱 4개, IC앱 3개, vsomeip |

---

## 3.2 OTA_Head-Unit 레포에서 바로 가져올 수 있는 것

### 즉시 재사용 가능 (거의 그대로)

**① `des-ota-clientd` (C++ 데몬)**
- RPi → Jetson ARM64로 크로스컴파일만 변경 (`TARGET_ARCH = "aarch64"`)
- MQTT 브로커 주소, 토픽만 바꾸면 동일하게 동작
- `--listen`, `--apply-pending`, `--apply-manifest` 3가지 모드 모두 유용

**② `des-ota-boot-ok.sh` (부팅 성공 마커)**
- `fw_printenv/fw_setenv` → Jetson에서는 `nvbootctrl` 명령으로 대체
- 로직 자체(카운터 리셋, 슬롯 확정)는 동일

**③ `release.sh` (릴리즈 자동화)**
- SHA256 계산 + manifest.json 생성 + MQTT 발행 로직 그대로 사용 가능
- OCI 업로드 대신 다른 스토리지(AWS S3, HTTP 서버 등)로 변경 가능

**④ systemd 서비스 파일 4개**
- `des-ota-listener.service` — 그대로 사용 가능
- `des-ota-apply.service` + `des-ota-apply.timer` — 그대로 사용 가능
- `des-ota-boot-ok.service` — 그대로 사용 가능

**⑤ manifest.json 스키마 구조**
- `version`, `artifact.type/url/sha256`, `apply.reboot_required`, `signature` 필드 구조를 우리 시스템에도 그대로 적용

---

## 3.3 수정이 필요한 부분

### ① A/B 이미지 적용 스크립트 (`des-ota-image-apply.sh`)

OTA_Head-Unit은 **U-Boot 기반** RPi를 대상으로 한다.  
우리 Jetson은 **NVIDIA CBoot/UEFI** 기반이므로 부트로더 제어 방법이 다르다.

| | OTA_Head-Unit (RPi) | 우리 프로젝트 (Jetson) |
|--|--|--|
| 슬롯 확인 | `fw_printenv ota_slot` | `nvbootctrl get-current-slot` |
| 슬롯 전환 | `fw_setenv ota_slot b` | `nvbootctrl set-active-boot-slot 1` |
| A/B 활성화 | WKS 파일 수동 정의 | `USE_REDUNDANT_FLASH_LAYOUT = "1"` |
| 이미지 쓰기 | `dd` (bzip2/gz/xz 지원) | 동일 (`dd`) |
| 무결성 검증 | `e2fsck` | 동일 |

```bash
# RPi 방식 (OTA_Head-Unit):
fw_setenv ota_slot "b"
fw_setenv ota_boot_count 0

# Jetson 방식 (우리 프로젝트로 수정 시):
nvbootctrl set-active-boot-slot 1   # 0=A, 1=B
nvbootctrl set-slot-as-unbootable 1 # "아직 검증 안됨" 표시 (카운터 역할)
```

### ② Yocto 레시피 (`des-ota-clientd.bb`)

OTA_Head-Unit은 `meta-custom/meta-app` 레이어에 레시피가 있다.  
우리는 `meta-headunit` 레이어에 동일한 레시피를 추가해야 한다.

```bitbake
# 우리 레이어에 추가할 위치:
# meta-headunit/recipes-ota/des-ota-clientd/des-ota-clientd.bb
```

### ③ 파티션 레이아웃

OTA_Head-Unit은 SD카드 4파티션 WKS 파일로 A/B를 정의한다.  
우리는 `local.conf`에 한 줄 추가로 Tegra 전용 A/B 레이아웃을 활성화할 수 있다.

```bitbake
# tegra-demo-distro/local.conf에 추가:
USE_REDUNDANT_FLASH_LAYOUT = "1"
```

> ⚠️ 이 변경은 기존 플래시 이미지와 호환되지 않는다.  
> 반드시 `doflash.sh`로 **전체 재플래싱** 후 사용해야 한다.

---

## 3.4 우리 프로젝트 OTA 구현 로드맵

NEXT_PROJECT_ANALYSIS.md의 Phase 3~4를 기반으로, OTA_Head-Unit 레포에서 배운 내용을 적용한 구체적 순서:

### Phase 1: RPi (ECU) 앱 OTA — 레포 거의 그대로 재사용 가능

```
1. RPi에 mosquitto 클라이언트 설치
2. des-ota-clientd를 RPi용으로 크로스컴파일
3. Yocto 레시피에 패키지 포함
4. release.sh로 RPM 패키지 배포 테스트
5. MQTT 브로커를 Jetson에서 실행 (Jetson = OTA Gateway)
```

이 단계는 OTA_Head-Unit 레포와 하드웨어(RPi4, ARM A72)가 동일하므로  
**코드 수정 최소화**로 빠르게 검증 가능하다.

### Phase 2: Jetson (HU) 앱 OTA

```
1. MQTT 브로커 설치 (Jetson 로컬 또는 외부)
2. des-ota-clientd를 ARM64(A78AE)용으로 빌드
3. HU 앱을 RPM으로 패키징 (이미 bitbake로 가능)
4. release.sh로 배포 → Jetson이 자동 수신 + 적용
```

### Phase 3: Jetson A/B OS OTA

```
1. local.conf에 USE_REDUNDANT_FLASH_LAYOUT = "1" 추가
2. A/B 레이아웃으로 재플래싱
3. des-ota-image-apply.sh를 nvbootctrl 기반으로 수정
4. des-ota-boot-ok.sh를 nvbootctrl 기반으로 수정
5. 전체 OTA 파이프라인 통합 테스트
```

---

## 3.5 현재 미구현/개선 필요 사항

OTA_Head-Unit 레포 자체의 한계점과 우리 프로젝트에서 개선해야 할 점:

### 보안 (공통)

```
⚠️ des-ota-clientd/main.cpp에 명시적 TODO:
// TODO(security): Implement actual cryptographic signature verification.
// Currently only checks that signature fields are non-empty.

현재 상태: manifest의 signature.value 필드가 비어있어도 통과
          실제 ed25519 서명 검증 코드가 없음

개선 방향:
- 서버에서 manifest에 ed25519 서명 추가
- 클라이언트에서 공개키로 서명 검증
- TLS로 MQTT/HTTP 통신 암호화
```

### 호환성 검증

```
현재: manifest에 compatible.model/hw/os 필드 있으나
      클라이언트에서 이를 검증하는 코드가 없음

개선: 클라이언트가 자신의 하드웨어 정보와 manifest를 비교하여
     "이 업데이트가 이 기기에 맞는가" 확인
```

### 점진적 배포 (Canary Release)

```
현재: 모든 기기에 동시 배포 (MQTT broadcast)

개선 방향: manifest에 targets 필드 활용
  "targets": { "device_id": "HU-001" }   → 특정 기기만
  "targets": { "group": "beta-testers" } → 특정 그룹만
```

---

## 3.6 핵심 파일 인덱스 (우리 프로젝트 적용 시 참조)

| OTA_Head-Unit 파일 | 우리 프로젝트 적용 위치 | 수정 필요도 |
|---|---|---|
| `ota/client/daemon/main.cpp` | `meta-headunit/recipes-ota/des-ota-clientd/` | 최소 (컴파일 설정만) |
| `ota/client/scripts/des-ota-image-apply.sh` | `meta-headunit/recipes-ota/` | 많음 (nvbootctrl 대체) |
| `ota/client/scripts/des-ota-boot-ok.sh` | `meta-headunit/recipes-ota/` | 보통 (nvbootctrl 대체) |
| `ota/client/systemd/*.service` | `meta-headunit/recipes-ota/` | 최소 |
| `ota/server/release.sh` | 개발자 PC (서버 측) | 최소 (URL만 변경) |
| `ota/server/release.env` | 개발자 PC | 많음 (우리 환경에 맞게) |
| WKS 파티션 파일 | tegra-demo-distro local.conf | `USE_REDUNDANT_FLASH_LAYOUT = "1"` 한 줄로 대체 |

---

## 3.7 요약: OTA_Head-Unit이 우리에게 주는 것

```
✅ 즉시 활용 가능:
  - OTA 클라이언트 데몬 (C++) — 아키텍처만 바꾸면 동일 동작
  - 릴리즈 자동화 스크립트 (release.sh + manifest 생성)
  - systemd 서비스 구조 (listener + apply timer + boot-ok)
  - manifest.json 스키마 설계

🔧 수정 필요:
  - A/B 슬롯 제어: fw_setenv → nvbootctrl
  - 파티션 레이아웃: WKS 파일 → USE_REDUNDANT_FLASH_LAYOUT = "1"
  - Yocto 레이어: meta-custom → meta-headunit에 레시피 추가

⚠️ 우리가 직접 구현해야 할 것:
  - MQTT 브로커 설정 (Jetson에서 mosquitto 실행)
  - OCI → 우리가 사용할 스토리지로 변경
  - 실제 서명 검증 (현재 미구현)
  - Jetson nvbootctrl 기반 자동 롤백 통합
```

---

*문서 작성: 2026년, DES 프로젝트 학습 자료*  
*참조: `/home/seame/leo/OTA_Head-Unit/ota/README.md`, `ARCHITECTURE.md`, `ota/client/daemon/main.cpp`*  
*참조: `/home/seame/leo/tegra-demo-distro/NEXT_PROJECT_ANALYSIS.md` §3 OTA 업데이트*
