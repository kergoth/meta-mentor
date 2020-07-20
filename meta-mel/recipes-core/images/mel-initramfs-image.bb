DESCRIPTION = "MEL Image initramfs"

PACKAGE_INSTALL = "initramfs-framework-base ${VIRTUAL-RUNTIME_base-utils} udev base-passwd ${ROOTFS_BOOTSTRAP_INSTALL}"

IMAGE_FEATURES = "${@bb.utils.contains('USER_FEATURES', 'encrypted-fs', 'encrypted-fs', '', d)}"

export IMAGE_BASENAME = "mel-initramfs-image"
IMAGE_LINGUAS = ""

LICENSE = "MIT"

IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"
inherit core-image

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# We don't care about root password for login on initramfs images
IMAGE_QA_COMMANDS_remove = "image_check_zapped_root_password"

BAD_RECOMMENDATIONS += "busybox-syslog"

COMPATIBLE_HOST_mel = "(arm|aarch64|i.86|x86_64).*-linux"
