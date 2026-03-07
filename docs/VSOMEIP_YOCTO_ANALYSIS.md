# vsomeip Yocto 동작 분석

> **작성일**: 2026-03-07
> **목적**: Jetson Yocto 이미지에서 vsomeip가 레시피 설계대로 동작하는지,
> 현재 fallback으로 동작하는 이유를 분석

---

## 1. 레시피 설계 (의도된 구조)

### 1-1. vsomeip-service (routing manager)

**파일**: `layers/meta-seame-headunit/recipes-middleware/vsomeip-service/vsomeip-service_1.0.bb`

레시피가 `/etc/vsomeip/vsomeip-routing-manager.json` 을 설치하도록 설계되어 있음:

```bitbake
SRC_URI = "file://vsomeip-routing-manager.service \
           file://vsomeip-routing-manager.json \
"
do_install() {
    install -d ${D}${sysconfdir}/vsomeip
    install -m 0644 ${WORKDIR}/vsomeip-routing-manager.json ${D}${sysconfdir}/vsomeip/
}
```

`vsomeip-routing-manager.json` 내용:
```json
{
    "unicast": "192.168.1.101",
    "applications": [{ "name": "routingmanagerd", "id": "0x0100" }],
    "service-discovery": { "enable": "true", "multicast": "224.244.224.245", "port": "30490" }
}
```

→ **설계 의도**: routing manager가 unicast IP `192.168.1.101`로 바인딩되어
  RPi(`192.168.1.100`)에서 오는 SOME/IP 서비스 디스커버리를 수신

### 1-2. GearApp

**파일**: `layers/meta-seame-headunit/recipes-apps/gearapp/gearapp_1.0.bb`

```bitbake
# gearapp.service 환경변수:
# VSOMEIP_CONFIGURATION=/etc/vsomeip/routing_manager_ecu2.json
# VSOMEIP_APPLICATION_NAME=GearApp
# COMMONAPI_CONFIG=/usr/share/commonapi/commonapi.ini
```

→ **설계 의도**: GearApp이 자신만의 vsomeip 클라이언트 설정 파일을 읽어
  어떤 서비스(VehicleControl 0x1234/0x5678)를 구독할지 명시

---

## 2. 현재 실제 상태 (Jetson 192.168.86.46)

### 2-1. routing_manager_ecu2.json — 없음

```bash
$ find / -name 'routing_manager_ecu2.json' 2>/dev/null
# 출력 없음
```

- `vsomeip-routing-manager.json` 은 `/etc/vsomeip/`에 존재 ✅
- `routing_manager_ecu2.json` 은 없음 ❌ (gearapp.service 에서 참조하는 파일)

### 2-2. commonapi.ini — 없음

```bash
$ ls /usr/share/commonapi/
# No such file or directory
```

### 2-3. 그런데 GearApp은 정상 동작 중

```
GearApp[951]: Client 0105 successfully connected to routing ~> vsomeip-0
GearApp[951]: Application/Client 0105 is registered.
GearApp[951]: [vsomeip → GearManager] Gear update: "P"  ← 정상 수신 중
```

---

## 3. 왜 fallback이 동작하는가

### vsomeip IPC 소켓 구조

```
/tmp/vsomeip-0    (root 소유, routing manager 메인 소켓)
/tmp/vsomeip-101  (weston 소유, HomeScreenApp)
/tmp/vsomeip-105  (weston 소유, GearApp)
...
```

vsomeip 동작 원리:
1. `VSOMEIP_CONFIGURATION` 파일이 없거나 못 찾으면 → **설정 없이 초기화**
2. routing manager가 이미 실행 중이면 → `/tmp/vsomeip-0` 소켓 자동 발견
3. 클라이언트로 연결 후 `REGISTERED_ACK` 수신 → 정상 동작

즉 **GearApp 입장에서 vsomeip 설정 파일은 "있으면 더 좋지만 없어도 되는" 파일**:
- 설정 파일이 있으면: 포트, 서비스 ID, unicast IP 등을 명시적으로 지정
- 설정 파일이 없으면: routing manager가 이미 알고 있는 서비스 정보 기반으로 동작

CommonAPI도 마찬가지:
- `.ini` 없으면 → 기본 바인딩 경로(`/usr/lib/libCommonAPI-SomeIP.so`) 자동 탐색
- `/usr/lib/libCommonAPI-SomeIP.so.3.2.4` 존재 → 자동 로드됨

---

## 4. 실제 문제가 되는 상황

이 fallback 동작은 **현재 단일 Jetson 개발 환경**에서는 문제없지만,
다음 상황에서는 문제가 될 수 있다:

| 상황 | 문제 |
|------|------|
| RPi VehicleControlECU 연결 | GearApp이 어떤 포트로 외부 서비스를 찾을지 모름 → 서비스 디스커버리 실패 가능 |
| 컨테이너 실행 | routing manager `/tmp/vsomeip-0` 소켓 마운트 필요 (`-v /tmp:/tmp`) |
| 여러 ECU 환경 | unicast IP가 명시 안 돼서 잘못된 인터페이스로 바인딩될 수 있음 |

---

## 5. 권장 수정 사항

### 단기 (현재 동작 유지)

컨테이너 실행 시 `-v /tmp:/tmp` 추가로 vsomeip IPC 소켓 공유:
```bash
docker run ... -v /tmp:/tmp ... hu-gearapp:1.0.0
```

### 장기 (레시피 수정)

`gearapp_1.0.bb`에 vsomeip 클라이언트 설정 파일 추가:

```bitbake
SRC_URI += "file://vsomeip-gearapp.json \
            file://commonapi.ini \
"
do_install:append() {
    install -d ${D}${sysconfdir}/vsomeip
    install -m 0644 ${WORKDIR}/vsomeip-gearapp.json ${D}${sysconfdir}/vsomeip/
    install -d ${D}${datadir}/commonapi
    install -m 0644 ${WORKDIR}/commonapi.ini ${D}${datadir}/commonapi/
}
```

`vsomeip-gearapp.json` 내용 (RPi 연결용):
```json
{
    "unicast": "192.168.1.101",
    "applications": [{ "name": "GearApp", "id": "0x0105" }],
    "clients": [{ "service": "0x1234", "instance": "0x5678", "unreliable": "30501" }],
    "service-discovery": { "enable": "true", "multicast": "224.244.224.245", "port": "30490" }
}
```

---

## 6. 결론

| 항목 | 상태 | 설명 |
|------|------|------|
| routing manager 설정 | ✅ 정상 | `/etc/vsomeip/vsomeip-routing-manager.json` 존재 |
| GearApp vsomeip 설정 | ⚠️ fallback | `routing_manager_ecu2.json` 없음, IPC 소켓으로 자동 연결 |
| CommonAPI 설정 | ⚠️ fallback | `commonapi.ini` 없음, 라이브러리 자동 탐색 |
| 현재 동작 | ✅ 정상 | VehicleControlMock과 IPC 통신으로 gear 수신 중 |
| RPi 연결 시 | ❓ 미검증 | unicast/포트 설정 없어서 외부 서비스 디스커버리 불확실 |
