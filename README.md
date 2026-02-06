# Jetson Orin Nano Yocto BSP for Head Unit & Instrument Cluster

Yocto Scarthgap 기반 Jetson Orin Nano용 커스텀 빌드 설정

## 🎯 개요

이 레포지토리는 **OE4T tegra-demo-distro**를 기반으로 Jetson Orin Nano에서 발생하는 빌드 오류를 수정한 설정을 포함합니다.

## 📋 해결한 문제

1. **OpenSSL 3.2.6 EC2 링크 오류**
   - `BN_GF2m_add` undefined reference
   - 해결: EC2 지원 비활성화 (`no-ec2m`)

2. **GCC 13.4 / binutils 2.42 순환 참조**
   - LTO (Link Time Optimization) 관련 오류
   - 해결: LTO 비활성화

3. **EDK2 펌웨어 빌드 오류**
   - GenFw DOS header 오류
   - 해결: EDK2용 LTO 비활성화

4. **DocBook XML 다운로드 실패**
   - 네트워크 fetch 오류
   - 해결: 수동 다운로드 및 로컬 캐시 사용

## 🚀 빌드 방법

### 1. OE4T tegra-demo-distro 클론

```bash
git clone https://github.com/OE4T/tegra-demo-distro.git
cd tegra-demo-distro
git checkout scarthgap
git submodule update --init
```

### 2. 빌드 환경 설정

```bash
source ./setup-env --machine jetson-orin-nano-devkit --distro tegrademo
```

### 3. local.conf 패치 적용

```bash
# 이 레포의 local.conf.patch 다운로드
wget https://raw.githubusercontent.com/leo9044/PDC_Yocto_Jetson-orin-nano/main/local.conf.patch

# 패치 적용
cat ../local.conf.patch >> conf/local.conf
```

### 4. DocBook XML 수동 다운로드 (선택)

네트워크 문제로 fetch 실패 시:

```bash
cd ~/Downloads
wget http://docs.oasis-open.org/docbook/xml/4.1.2/docbkx412.zip
wget http://ftp.fau.de/macports/distfiles/docbook-xml/docbook-xml-4.2.zip
wget http://ftp.fau.de/macports/distfiles/docbook-xml/docbook-xml-4.3.zip
wget http://ftp.fau.de/macports/distfiles/docbook-xml/docbook-xml-4.4.zip
wget http://ftp.fau.de/macports/distfiles/docbook-xml/docbook-xml-4.5.zip

# Yocto 다운로드 폴더로 이동
mv *.zip ~/tegra-demo-distro/build/downloads/
```

### 5. 빌드 실행

```bash
cd ~/tegra-demo-distro/build
bitbake core-image-weston
```

**예상 빌드 시간:** 2-4시간 (첫 빌드)

### 6. 플래시

```bash
cd ~
mkdir jetson-flash
cd jetson-flash
tar xzf ~/tegra-demo-distro/build/tmp/deploy/images/jetson-orin-nano-devkit/core-image-weston*.tegraflash.tar.gz

# Jetson을 Recovery 모드로 진입:
# 1. FC REC 핀과 GND 연결
# 2. 전원 OFF → 5초 대기 → 전원 ON
# 3. FC REC 연결 해제
# 4. USB-C로 호스트 PC 연결

# Recovery 모드 확인
lsusb | grep -i nvidia

# 플래시 실행
sudo ./doflash.sh
```

플래시 완료 후 Jetson이 자동 재부팅되며 Weston 화면이 나타납니다.

## 📦 빌드 산출물

- `core-image-weston*.tegraflash.tar.gz` (~300MB)
- `core-image-weston.ext4` (루트 파일시스템)
- `boot.img` (커널 + 디바이스 트리)

## 🔧 local.conf 주요 설정

### OpenSSL 수정
```bash
EXTRA_OECONF:append:pn-openssl = " no-ec2m"
```

### LTO 비활성화 (GCC/binutils)
```bash
TARGET_CFLAGS:remove = "-flto"
TARGET_CXXFLAGS:remove = "-flto"
SELECTED_OPTIMIZATION:remove = "-flto"
```

### EDK2 펌웨어 LTO 비활성화
```bash
TARGET_CFLAGS:pn-edk2-firmware-tegra:remove = "-flto"
TARGET_CXXFLAGS:pn-edk2-firmware-tegra:remove = "-flto"
SELECTED_OPTIMIZATION:pn-edk2-firmware-tegra:remove = "-flto"
```

## 🛠️ 빌드 최적화 (선택)

빌드 속도 향상을 위해:

```bash
# local.conf에 추가
BB_NUMBER_THREADS ?= "8"    # CPU 코어 수
PARALLEL_MAKE ?= "-j 8"     # 병렬 빌드 수
```

## 📖 참고 자료

- [OE4T tegra-demo-distro](https://github.com/OE4T/tegra-demo-distro)
- [meta-tegra](https://github.com/OE4T/meta-tegra)
- [Yocto Project Scarthgap](https://docs.yoctoproject.org/5.0/)
- [NVIDIA Jetson Orin Nano](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-orin/)

## 🐛 알려진 문제

### GCC 13.4 LTO 이슈
- **증상**: `undefined reference` 오류
- **원인**: GCC 13.4에서 LTO가 기본 활성화
- **해결**: LTO 비활성화

### OpenSSL EC2 링크 오류
- **증상**: `BN_GF2m_add` undefined reference
- **원인**: OpenSSL 3.2.6 EC2 구현 버그
- **해결**: `no-ec2m` 옵션 사용 (대부분 앱은 EC2 미사용)

### EDK2 펌웨어 빌드 실패
- **증상**: GenFw DOS header 오류
- **원인**: LTO와 EDK2 빌드 시스템 충돌
- **해결**: EDK2에 대해 LTO 비활성화

## 💡 팁

### 빌드 재개
빌드 중단 시:
```bash
cd ~/tegra-demo-distro/build
bitbake core-image-weston
```

### 특정 패키지 재빌드
```bash
bitbake <package-name> -c cleansstate
bitbake <package-name>
```

### 디스크 공간 정리
```bash
# 빌드 캐시 정리 (주의: 재빌드 시간 증가)
rm -rf ~/tegra-demo-distro/build/tmp
```

## 📝 라이선스

OE4T 프로젝트의 라이선스를 따릅니다.

## 🙏 기여

버그 리포트 및 개선 사항은 이슈로 등록해주세요.

## ✅ 검증 완료

- Jetson Orin Nano Developer Kit
- L4T R36.4.4
- Yocto Scarthgap (5.0)
- core-image-weston 정상 부팅 확인

---

**Built with ❤️ for autonomous vehicle development**