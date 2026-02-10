SUMMARY = "CommonAPI C++ - IPC middleware abstraction layer"
DESCRIPTION = "CommonAPI C++ provides a language binding for the Franca IDL"
HOMEPAGE = "https://github.com/COVESA/capicxx-core-runtime"
LICENSE = "MPL-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=815ca599c9df247a0c7f619bab123dad"

SRC_URI = "git://github.com/COVESA/capicxx-core-runtime.git;protocol=https;branch=master \
           file://0001-Add-missing-string-includes.patch \
          "
# capicxx-core-runtime 3.2.4 (last stable release)
SRCREV = "9eb5d398a0ea10c39b30ebf2789c6ae365c1895e"
PV = "3.2.4"

S = "${WORKDIR}/git"

inherit cmake

EXTRA_OECMAKE = " \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
"

FILES:${PN} += " \
    ${libdir}/libCommonAPI.so.* \
"

FILES:${PN}-dev += " \
    ${includedir}/CommonAPI \
    ${libdir}/cmake/CommonAPI-* \
"

BBCLASSEXTEND = "native nativesdk"
