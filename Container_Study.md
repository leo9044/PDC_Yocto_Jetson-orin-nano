# 컨테이너 격리 학습 문서

> 작성 기준: `tegra-demo-distro/NEXT_PROJECT_ANALYSIS.md` §2 참조  
> 대상 독자: 컨테이너를 처음 접하는 임베디드 개발자

---

## 목차

1. [컨테이너 기본 개념](#1-컨테이너-기본-개념)
2. [우리 시스템에서의 컨테이너](#2-우리-시스템에서의-컨테이너)
3. [핵심 기술 문제와 해결책](#3-핵심-기술-문제와-해결책)
4. [구현 로드맵](#4-구현-로드맵)

---

# 1. 컨테이너 기본 개념

## 1.1 컨테이너란 무엇인가

컨테이너는 **프로세스를 격리된 환경에서 실행하는 기술**이다.  
VM(가상머신)과 달리 OS 커널을 공유하므로 훨씬 가볍다.

```
VM:
  ┌────────────────────────────────────────┐
  │  앱 A    │  앱 B    │  앱 C            │
  │  Guest OS│  Guest OS│  Guest OS        │  ← OS가 3개 → 무거움
  │  Hypervisor (KVM, Xen, VMware)         │
  │  Host OS                               │
  └────────────────────────────────────────┘

컨테이너:
  ┌────────────────────────────────────────┐
  │  앱 A    │  앱 B    │  앱 C            │
  │  컨테이너│  컨테이너│  컨테이너        │  ← OS 커널 공유 → 가벼움
  │  Host OS (커널 1개)                    │
  └────────────────────────────────────────┘
```

자동차 소프트웨어에서 컨테이너가 중요한 이유:
- **도메인 격리**: 인포테인먼트 앱이 충돌해도 ADAS 앱에 영향 없음
- **OTA 단위**: 앱 컨테이너 이미지 단위로 독립 업데이트 가능
- **재현 가능성**: "내 PC에서는 되는데..." 문제 해결

---

## 1.2 컨테이너의 핵심 기술: Linux Namespaces

컨테이너는 새로운 기술이 아니다. Linux 커널의 **namespace**와 **cgroup** 기능을 편리하게 포장한 것이다.

### Namespace — "격리"를 담당

namespace는 프로세스가 보는 "세계"를 분리한다.

```
Namespace 종류:
  pid   → 프로세스 ID 격리
          컨테이너 안에서 PID 1이 호스트의 PID 1과 다른 프로세스
  
  net   → 네트워크 격리
          컨테이너는 자체 네트워크 인터페이스, IP, 라우팅 테이블 보유
  
  mnt   → 파일시스템 마운트 격리
          컨테이너는 자체 파일시스템 트리 보유 (chroot의 발전형)
  
  uts   → 호스트명 격리
          컨테이너마다 다른 hostname 가능
  
  ipc   → IPC(프로세스간 통신) 격리
          공유 메모리, 메시지 큐 격리
  
  user  → 사용자 ID 격리
          컨테이너 안의 root가 호스트의 root가 아님
```

직접 확인해보기:
```bash
# 현재 프로세스의 namespace 확인
ls -la /proc/self/ns/

# 새 namespace로 격리된 shell 실행 (컨테이너의 원리)
unshare --pid --fork --mount-proc bash
# 이 shell 안에서 ps aux → 프로세스가 거의 없음 (격리됨)
```

### cgroup — "제한"을 담당

cgroup(Control Group)은 프로세스 그룹의 **자원 사용량을 제한**한다.

```
제한 가능한 자원:
  cpu     → CPU 사용률 상한 (예: 최대 50%)
  memory  → 메모리 상한 (예: 최대 512MB)
  blkio   → 디스크 I/O 속도 제한
  devices → 접근 가능한 디바이스 목록 (/dev/dri/card0 등)
  pids    → 생성 가능한 프로세스 수 제한
```

```bash
# cgroup v2 마운트 포인트 확인 (Jetson에서)
ls /sys/fs/cgroup/

# 예시: 특정 프로세스의 cgroup 확인
cat /proc/self/cgroup
```

---

## 1.3 OCI, Docker, crun의 관계

```
OCI (Open Container Initiative):
  컨테이너 이미지/런타임 표준 규격
  → "컨테이너 이미지가 어떻게 생겼어야 하는가"의 표준

Docker:
  OCI 표준을 구현한 가장 유명한 도구
  컨테이너 빌드(Dockerfile) + 실행(docker run) + 관리(docker ps)
  내부적으로 containerd → runc(OCI runtime) 사용

containerd:
  Docker에서 분리된 컨테이너 런타임
  Docker 없이 단독으로 사용 가능

crun:
  C로 작성된 경량 OCI 런타임 (runc 대안)
  Yocto/임베디드 환경에 적합 (바이너리 크기 작음)
  Docker나 containerd 없이 OCI 이미지 직접 실행 가능
```

**우리 Yocto 이미지에서 선택지:**

| 방법 | 장점 | 단점 | 권장 상황 |
|------|------|------|-----------|
| Docker (docker-moby) | 친숙한 CLI, hub 이미지 재사용 | ~500MB 오버헤드 | 개발/학습 초기 |
| crun + containerd | 경량, Yocto 친화적 | 학습 곡선 | 프로덕션 |
| systemd-nspawn | 추가 설치 불필요 | 기능 제한적 | 간단한 격리 |

> **현재 우리 선택**: `meta-virtualization` 레이어가 이미 `bblayers.conf`에 포함되어 있어서  
> `IMAGE_INSTALL`에 `docker-moby` 또는 `crun`만 추가하면 사용 가능하다.

---

## 1.4 컨테이너 이미지란

컨테이너 이미지는 **앱 실행에 필요한 파일시스템의 스냅샷**이다.

```
레이어 구조:
  ┌─────────────────────────────────┐
  │  Layer 4: 앱 바이너리 (GearApp) │  ← 변경 시 이 레이어만 재빌드
  ├─────────────────────────────────┤
  │  Layer 3: Qt6 라이브러리        │
  ├─────────────────────────────────┤
  │  Layer 2: vsomeip 라이브러리    │
  ├─────────────────────────────────┤
  │  Layer 1: 베이스 OS (Alpine 등) │  ← 거의 변경 없음
  └─────────────────────────────────┘
  
  → 하위 레이어는 캐시됨 → 앱만 바뀌면 Layer 4만 전송
  → OTA 효율적 업데이트의 핵심
```

Yocto 빌드 결과물로 이미지 만들기:
```bitbake
# local.conf에 추가
IMAGE_FSTYPES += "container"
# 또는 meta-virtualization의 container-image 클래스 사용
```

---

## 1.5 cgroup v1 vs v2

```
cgroup v1 (구버전):
  각 자원(cpu, memory, blkio...)마다 별도 계층 구조
  /sys/fs/cgroup/cpu/, /sys/fs/cgroup/memory/ 등 각각 존재
  관리 복잡, 컨테이너 간 자원 조율 어려움

cgroup v2 (현재 표준):
  단일 계층 구조로 통합
  /sys/fs/cgroup/ 하나에서 모든 자원 제어
  systemd와 더 잘 통합됨
  Docker 20.10+, crun 모두 v2 지원

Jetson L4T R36.4.4 (커널 5.15):
  cgroup v2 지원하나 Yocto 이미지에서 활성화 여부 확인 필요
```

```bash
# Jetson에서 확인
cat /sys/fs/cgroup/cgroup.controllers
# 출력 예시: cpuset cpu io memory hugetlb pids rdma misc
# 이 파일이 있으면 cgroup v2 활성화됨

# cgroup v2 강제 활성화 (local.conf)
APPEND:append = " systemd.unified_cgroup_hierarchy=1"
```

---

# 2. 우리 시스템에서의 컨테이너

## 2.1 현재 구조 (컨테이너 없음)

```
Jetson 호스트 OS
  │
  ├── weston.service              (Wayland 디스플레이 서버)
  │     wayland-1 소켓 생성
  │
  ├── ic-compositor.service       (wayland-1 연결 → wayland-2 생성)
  │     ├── batterymeter.service  (wayland-2 연결)
  │     ├── speedometer.service   (wayland-2 연결)
  │     └── gearstate.service     (wayland-2 연결)
  │
  ├── hu-compositor.service       (wayland-1 연결 → wayland-3 생성)
  │     ├── gearapp.service       (wayland-3 연결)
  │     ├── mediaapp.service      (wayland-3 연결)
  │     ├── ambientapp.service    (wayland-3 연결)
  │     └── homescreenapp.service (wayland-3 연결)
  │
  └── vsomeip-routing-manager.service
```

모든 서비스가 호스트 OS 위에서 직접 실행 중 → 격리 없음.  
하나의 앱이 메모리를 과점해도 다른 앱을 보호할 수 없다.

---

## 2.2 목표 구조 (컨테이너 적용 후)

```
Jetson 호스트 OS
  │
  ├── weston.service              ← 호스트에서 실행 (공용 디스플레이 서버)
  │     wayland-1 소켓
  │
  ├── vsomeip-routing-manager     ← 호스트에서 실행 (네트워크 요구사항)
  │
  ├── [IC 컨테이너]  ─────────── cgroup 메모리/CPU 제한
  │     ic-compositor             (wayland-1 연결 → wayland-2 생성)
  │     ├── batterymeter          (wayland-2 연결)
  │     ├── speedometer           (wayland-2 연결)
  │     └── gearstate             (wayland-2 연결)
  │
  └── [HU 컨테이너]  ─────────── cgroup 메모리/CPU 제한
        hu-compositor             (wayland-1 연결 → wayland-3 생성)
        ├── gearapp               (wayland-3 연결)
        ├── mediaapp              (wayland-3 연결)
        ├── ambientapp            (wayland-3 연결)
        └── homescreenapp         (wayland-3 연결)
```

컨테이너 적용으로 얻는 것:
- **도메인 격리**: HU 앱 충돌이 IC 앱에 영향 없음
- **자원 제한**: HU 컨테이너가 메모리를 과점하면 cgroup이 차단
- **OTA 단위**: IC 컨테이너 이미지만 업데이트 가능 (HU는 그대로)
- **재현성**: 개발 환경과 Jetson 환경이 동일한 컨테이너 이미지 사용

---

## 2.3 역할 분담

| | IC 도메인 | HU 도메인 |
|--|-----------|-----------|
| Wayland 소켓 | wayland-2 | wayland-3 |
| vsomeip 데이터 | VehicleControlMock (로컬) | RPi VehicleControlECU (이더넷) |
| 앱 수 | 4개 (compositor + 3앱) | 5개 (compositor + 4앱) |
| GPU 필요 | 없음 (software rendering) | 없음 (software rendering) |
| network=host 필요 | 덜 중요 (127.0.0.1 통신) | 필수 (SOME/IP 멀티캐스트) |

> `QT_QUICK_BACKEND=software`가 모든 서비스에 설정되어 있어  
> `/dev/dri/` 디바이스 전달 없이도 컨테이너가 동작한다. → 컨테이너 테스트가 단순해짐

---

# 3. 핵심 기술 문제와 해결책

## 3.1 문제 1: Wayland 소켓 접근

### 왜 문제인가

Wayland는 Unix 도메인 소켓(`/run/user/1000/wayland-N`)으로 통신한다.  
컨테이너는 기본적으로 자체 mount namespace를 가지므로 호스트 소켓에 접근 불가능하다.

```
호스트:     /run/user/1000/wayland-1  (Weston이 생성)
컨테이너:   /run/user/1000/wayland-1  (없음 → 앱이 연결 실패)
```

### 해결책: volume mount

```bash
# XDG_RUNTIME_DIR 전체를 컨테이너에 마운트
docker run \
  -v /run/user/1000:/run/user/1000 \   # ← 소켓 디렉토리 공유
  --user 1000:1000 \                   # ← weston 유저와 UID 일치
  -e WAYLAND_DISPLAY=wayland-3 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_QUICK_BACKEND=software \
  hu-container
```

### 왜 wayland-0이 아닌가

직관적으로 Weston이 `wayland-0`을 쓸 것 같지만 **실제는 다르다.**

```
우리 서비스 파일에서 직접 확인한 값:

  weston           → wayland-1 생성
  ic-compositor    → WAYLAND_DISPLAY=wayland-1 (Weston에 연결)
                   → socketName="wayland-2" (IC앱용 서버)
  hu-compositor    → WAYLAND_DISPLAY=wayland-1 (Weston에 연결)
                   → socketName="wayland-3" (HU앱용 서버)
  IC앱 3개         → WAYLAND_DISPLAY=wayland-2
  HU앱 4개         → WAYLAND_DISPLAY=wayland-3
```

컨테이너 실행 시 이 번호를 정확히 지정해야 한다.

### 소켓 대기 스크립트 문제

HU앱 서비스 파일에 이런 코드가 있다:
```bash
# gearapp.service ExecStartPre:
/bin/sh -c 'for i in $(seq 1 10); do \
  test -S /run/user/1000/wayland-3 && break || sleep 1; done'
```

컨테이너가 `/run/user/1000`을 마운트하지 않으면  
이 루프가 10초 후 타임아웃 → 앱 시작 실패.  
→ **`-v /run/user/1000:/run/user/1000` 마운트가 필수인 이유.**

---

## 3.2 문제 2: vsomeip + 컨테이너

### 왜 문제인가

vsomeip는 두 가지 방식으로 통신한다:
```
1. Unix socket  → /tmp/vsomeip.lck, /tmp/vsomeip/ (로컬 IPC)
2. UDP 멀티캐스트 → 224.0.0.0/4 (이더넷 브로드캐스트)
```

컨테이너는 기본적으로 자체 network namespace를 가지므로:
- Unix socket: 호스트의 `/tmp/vsomeip`에 접근 불가
- 멀티캐스트: 컨테이너 내부 가상 인터페이스로는 호스트 이더넷 멀티캐스트 수신 불가

### 해결책

```bash
docker run \
  --network=host \                      # 호스트 네트워크 그대로 사용
  -v /tmp/vsomeip:/tmp/vsomeip \        # routing manager IPC 공유
  -v /tmp/vsomeip.lck:/tmp/vsomeip.lck \
  hu-container
```

> **`--network=host`의 트레이드오프**:  
> 네트워크 격리가 없어진다. 컨테이너가 호스트의 모든 네트워크에 접근 가능.  
> 하지만 vsomeip SOME/IP 통신을 위해서는 현재로서는 불가피한 선택이다.

### vsomeip routing manager는 호스트에서 실행

```
❌ 잘못된 구조:
  [컨테이너 안에서 routing manager 실행]
  → ExecStartPre의 "ip route add 224.0.0.0/4 dev enP8p1s0" 실패
  → 컨테이너 내부에 enP8p1s0 인터페이스가 없음

✅ 올바른 구조:
  [호스트]  vsomeip-routing-manager.service 실행
  [컨테이너] --network=host로 호스트 routing manager에 클라이언트로 연결
```

---

## 3.3 문제 3: UID 불일치

모든 서비스에 `User=weston`(UID=1000)이 설정되어 있다.

```bash
# 확인: Wayland 소켓 소유자
ls -la /run/user/1000/wayland-1
# → srwxrwxrwx 1 weston weston ... wayland-1

# 컨테이너가 root로 실행되면?
docker run ubuntu ls -la /run/user/1000/
# → Permission denied (소켓이 UID=1000 소유이므로)
```

해결책:
```bash
# 방법 1: --user 플래그
docker run --user 1000:1000 ...

# 방법 2: Dockerfile에서 동일 UID 사용자 생성
RUN useradd -u 1000 -g 1000 weston
USER weston
```

---

## 3.4 문제 4: IC앱 서비스 파일 인라인 정의

HU앱은 서비스 파일이 분리되어 있지만, IC앱은 bb 파일 안에 인라인으로 정의되어 있다.

```
HU앱 (분리됨 - 좋음):
  recipes-apps/gearapp/files/gearapp.service  ← 독립 파일

IC앱 (인라인 - 문제):
  recipes-apps/batterymeter-app/batterymeter-app_1.0.bb
    do_install:append() {
        cat > ${D}/.../batterymeter.service << EOF  ← bb 파일 안에 서비스 정의
        ...
        EOF
    }
```

컨테이너화 시 문제가 되는 이유:
- 서비스 파일에서 환경변수(`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`)를 바꾸려면
  bb 파일 전체를 재빌드해야 함
- 컨테이너 환경에서는 이 환경변수를 런타임에 주입하는 방식이 더 유연함

개선 방향:
```bitbake
# 현재 (인라인):
do_install:append() {
    cat > ${D}${systemd_system_unitdir}/batterymeter.service << EOF
    [Service]
    Environment="WAYLAND_DISPLAY=wayland-2"
    ...
    EOF
}

# 개선 (분리 파일):
SRC_URI += "file://batterymeter.service"
do_install:append() {
    install -m 0644 ${WORKDIR}/batterymeter.service \
        ${D}${systemd_system_unitdir}/
}
```

---

## 3.5 문제 5: Yocto에서 Docker 이미지 관리

### 선택지 비교

```
[A] Yocto rootfs에 Docker 설치 → 앱을 Docker 컨테이너로 실행
    
    장점: 기존 Yocto 빌드 인프라 그대로
          docker pull, docker run 등 친숙한 CLI
    단점: Docker daemon ~500MB → rootfs 커짐
          Docker socket(/var/run/docker.sock) 권한 관리

[B] OCI 이미지를 Yocto 빌드로 생성 → rootfs에 embed
    
    장점: 프로덕션 접근법
          Yocto가 컨테이너 이미지까지 빌드
    단점: 빌드 파이프라인 복잡
          bitbake container-image 클래스 학습 필요

[C] crun만 설치 (Docker 없이 OCI 이미지 실행)
    
    장점: 경량 (~수MB)
          Docker hub 이미지도 skopeo로 변환 후 사용 가능
    단점: docker CLI 없음 (runc/crun 직접 사용)
```

**권장 순서**:
1. 개발/학습 초기: **[A] Docker 설치** → `docker run`으로 빠르게 실험
2. OTA 연동 시: **[B] OCI 이미지 Yocto 빌드** → 이미지 자체를 OTA 대상으로

---

## 3.6 IC앱 데이터 경로 주의

IC앱 3개는 실제 RPi 데이터가 아닌 **Mock 데이터**를 사용한다.

```json
// vsomeip_batterymeter.json (IC앱):
{
    "unicast": "192.168.1.101",    ← 수정됨 (기존: 127.0.0.1)
    "routing": "routingmanagerd"   ← 수정됨 (기존: VehicleControlMock)
}
```

> 이전 세션에서 `127.0.0.1` → `192.168.1.101`, `VehicleControlMock` → `routingmanagerd`로  
> 수정하여 실제 RPi 데이터를 받도록 변경했다. (커밋 cb845abe)

컨테이너화 시 의미:
- IC앱 컨테이너도 `--network=host`가 필요하다 (SOME/IP 이더넷 통신)
- IC 컨테이너와 HU 컨테이너 모두 동일한 vsomeip routing manager를 공유

---

# 4. 구현 로드맵

## 4.1 단계별 접근

```
Step 1: Docker 설치 확인 (Yocto 이미지)
─────────────────────────────────────────
local.conf에 추가:
  IMAGE_INSTALL:append = " docker-moby"
  APPEND:append = " systemd.unified_cgroup_hierarchy=1"

빌드 후 Jetson에서 확인:
  docker --version
  systemctl status docker
  cat /sys/fs/cgroup/cgroup.controllers


Step 2: 단순 컨테이너 실행 테스트
─────────────────────────────────────────
# Jetson에서 직접 테스트 (빌드 없이)
docker run --rm hello-world

# Wayland 소켓 접근 테스트
docker run --rm \
  -v /run/user/1000:/run/user/1000 \
  --user 1000:1000 \
  -e WAYLAND_DISPLAY=wayland-1 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  ubuntu:22.04 \
  ls -la /run/user/1000/


Step 3: HU 앱 단일 컨테이너화
─────────────────────────────────────────
# Dockerfile 작성 (GearApp 단일)
FROM scratch
COPY --from=yocto-build /usr/bin/gearapp /usr/bin/
COPY --from=yocto-build /usr/lib/libvsomeip* /usr/lib/
...

# 실행
docker run \
  -v /run/user/1000:/run/user/1000 \
  -v /tmp/vsomeip:/tmp/vsomeip \
  --network=host \
  --user 1000:1000 \
  -e WAYLAND_DISPLAY=wayland-3 \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_QUICK_BACKEND=software \
  hu-gearapp


Step 4: IC/HU 전체 도메인 컨테이너화
─────────────────────────────────────────
# HU 컨테이너 (compositor + 4앱)
# IC 컨테이너 (compositor + 3앱)
# cgroup 제한 적용 (메모리, CPU)
# 컨테이너 자동 시작 (systemd unit으로 docker run 감쌈)


Step 5: OTA와 연동
─────────────────────────────────────────
# 컨테이너 이미지를 OTA 단위로 배포
# HU 컨테이너 이미지만 업데이트 → IC는 그대로
# Jetson이 OTA Gateway로 컨테이너 이미지 수신 → 내부 적용
```

---

## 4.2 실제로 해볼 수 있는 첫 단계

Jetson 없이 지금 당장 개념을 확인하는 방법:

```bash
# 1. namespace 직접 체험
sudo unshare --pid --fork --mount-proc bash
ps aux  # 프로세스가 거의 없음 → PID namespace 격리 확인
exit

# 2. cgroup 메모리 제한 체험
# 특정 프로세스를 512MB로 제한
sudo cgcreate -g memory:/test-group
echo $((512 * 1024 * 1024)) | sudo tee /sys/fs/cgroup/memory/test-group/memory.limit_in_bytes
sudo cgexec -g memory:/test-group bash
# 이 shell에서 메모리를 512MB 초과 사용하면 OOM kill됨

# 3. Docker로 격리 원리 확인
docker run --rm -it ubuntu bash
cat /proc/self/cgroup   # 컨테이너 전용 cgroup 확인
ip addr                 # 컨테이너 전용 네트워크 인터페이스 확인
ps aux                  # 격리된 프로세스 공간 확인
```

---

## 4.3 핵심 요약

```
컨테이너 = namespace(격리) + cgroup(제한)

우리 시스템 적용 시 핵심 포인트:
  ✅ Wayland 소켓: -v /run/user/1000:/run/user/1000 마운트 필수
  ✅ vsomeip: --network=host, /tmp/vsomeip 마운트 필수
  ✅ UID: --user 1000:1000 (weston 유저와 일치)
  ✅ routing manager: 반드시 호스트에서 실행 (컨테이너 밖)
  ✅ GPU: software rendering이라 /dev/dri 마운트 불필요 → 테스트 단순
  ✅ cgroup v2: local.conf에 systemd.unified_cgroup_hierarchy=1 추가

OTA와의 연관:
  컨테이너 이미지 단위 OTA = "IC 앱만 업데이트, HU는 그대로"
  Jetson이 게이트웨이로 컨테이너 이미지를 받아 내부에 배포
  → 중앙 집중형 아키텍처의 OTA 이점을 소프트웨어적으로 실현
```

---

*문서 작성: 2026년 2월, DES 프로젝트 학습 자료*  
*참조: `/home/seame/leo/tegra-demo-distro/NEXT_PROJECT_ANALYSIS.md` §2 컨테이너 격리*
