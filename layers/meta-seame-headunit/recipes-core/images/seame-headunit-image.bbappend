# Copy fonts to /usr/lib/fonts for Qt compatibility
# Qt looks for fonts in /usr/lib/fonts but Yocto installs them in /usr/share/fonts

copy_fonts_for_qt() {
    # Create /usr/lib/fonts directory in the rootfs
    install -d ${IMAGE_ROOTFS}/usr/lib/fonts
    
    # Copy all fonts from /usr/share/fonts to /usr/lib/fonts
    if [ -d ${IMAGE_ROOTFS}/usr/share/fonts ]; then
        cp -r ${IMAGE_ROOTFS}/usr/share/fonts/* ${IMAGE_ROOTFS}/usr/lib/fonts/ 2>/dev/null || true
    fi
}

ROOTFS_POSTPROCESS_COMMAND += "copy_fonts_for_qt; "
