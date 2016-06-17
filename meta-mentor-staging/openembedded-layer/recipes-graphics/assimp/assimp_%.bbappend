DEPENDS += "zlib"
DEPENDS_remove = "${@bb.utils.contains('PACKAGECONFIG', 'boost', '', 'boost', d)}"

EXTRA_OECMAKE += "\
    '-DASSIMP_LIB_INSTALL_DIR=${libdir}' \
    '-DASSIMP_INCLUDE_INSTALL_DIR=${includedir}' \
    '-DASSIMP_BIN_INSTALL_DIR=${bindir}' \
"

PACKAGECONFIG ?= "static tools"
PACKAGECONFIG[boost] = "-DASSIMP_ENABLE_BOOST_WORKAROUND=OFF,-DASSIMP_ENABLE_BOOST_WORKAROUND=ON,boost"
PACKAGECONFIG[samples] = "-DASSIMP_BUILD_SAMPLES=ON,-DASSIMP_BUILD_SAMPLES=OFF,freeglut"
PACKAGECONFIG[static] = "-DASSIMP_BUILD_STATIC_LIB=ON,-DASSIMP_BUILD_STATIC_LIB=OFF,"
PACKAGECONFIG[tools] = "-DASSIMP_BUILD_ASSIMP_TOOLS=ON,-DASSIMP_BUILD_ASSIMP_TOOLS=OFF,"

PACKAGE_BEFORE_PN += "${PN}-samples"
FILES_${PN}-samples = "${bindir}/assimp_*"
