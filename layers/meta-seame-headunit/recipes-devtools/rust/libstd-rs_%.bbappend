# libstd-rs do_install fix: upstream recipe uses 'cp *' which fails when Rust's
# incremental build system leaves stale temporary directories (e.g. rmetaG2RTNY)
# inside the deps/ directory.
#
# Root cause: Rust's incremental compilation creates temporary directories with
# random names alongside the .rlib/.rmeta artifacts. The upstream do_install
# does 'cp deps/* ${D}${rustlibdir}' which fails on any directory entry because
# cp requires -r for directories.
#
# Fix: Override do_install to remove any stale directories from deps/ before
# the copy, keeping only the regular files (.rlib, .rmeta, .so) that are
# actually needed for the Rust toolchain.

do_install() {
    mkdir -p ${D}${rustlibdir}

    # Remove incremental build dependency files (.d) - upstream does this too
    rm -f ${B}/${RUST_TARGET_SYS}/${BUILD_DIR}/deps/*.d

    # Remove any stale directories left by Rust's incremental build system.
    # These are temporary directories with random names that are not needed
    # for installation and cause 'cp *' to fail without -r.
    find ${B}/${RUST_TARGET_SYS}/${BUILD_DIR}/deps/ -maxdepth 1 -mindepth 1 -type d -exec rm -rf {} +

    # Copy only regular files (.rlib, .rmeta, .so) to the install destination
    find ${B}/${RUST_TARGET_SYS}/${BUILD_DIR}/deps/ -maxdepth 1 -type f -exec cp {} ${D}${rustlibdir} \;
}
