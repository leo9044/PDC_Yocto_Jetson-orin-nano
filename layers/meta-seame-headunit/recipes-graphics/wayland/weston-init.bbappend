FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Override weston.ini to enable portrait mode (transform=90) for
# the Elecrow 13.3" 4K display mounted vertically (600x1024 logical).
SRC_URI:append = " file://weston.ini"
