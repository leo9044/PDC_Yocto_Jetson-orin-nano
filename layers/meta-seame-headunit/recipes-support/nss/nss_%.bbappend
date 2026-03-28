# NSS 3.98 fix: ecp_secp384r1_wrap.c compile failure in Linux_SINGLE_SHLIB build
#
# Root cause: The first build attempt silently fails to compile
# ecp_secp384r1_wrap.c (a new file added in NSS 3.96+), leaving a zero-byte
# ecp_secp384r1_wrap.o. Subsequent builds consider the zero-byte file
# "up to date" and skip recompilation, causing the final link of
# libfreeblpriv3.so to fail with:
#   undefined reference to 'ec_group_set_secp384r1'
#
# Fix: Remove any zero-byte .o files before compilation so that
# the NSS build system recompiles them properly.
# This is targeted at the Linux_SINGLE_SHLIB child build directory.

do_compile:prepend() {
    # Remove stale zero-byte object files from previous failed build attempts.
    # GNU make considers a file "up to date" as long as it exists and its
    # timestamp is newer than the source — even if it is empty. Removing
    # zero-byte objects forces a clean recompile of those translation units.
    find "${S}/nss/lib/freebl" -name "*.o" -size 0 -delete 2>/dev/null || true
    bbnote "Removed any stale zero-byte .o files from nss/lib/freebl"
}
