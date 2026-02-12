# Enable fontconfig support in Qt
PACKAGECONFIG:append = " fontconfig"

# Ensure fontconfig is available at build time
DEPENDS += "fontconfig"
