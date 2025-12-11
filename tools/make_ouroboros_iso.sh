#!/usr/bin/env bash
#
# make_ouroboros_iso.sh
#
# Scaffold for building the Ouroboros installer ISO.
# This script currently does NOT produce a working ISO; it documents
# the intended build flow and directory layout.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
INITRAMFS_ROOT="${ROOT_DIR}/initramfs_root"
INITRAMFS_IMG="${BUILD_DIR}/initramfs_ouroboros.cpio.gz"
ISO_ROOT="${BUILD_DIR}/iso-root"
OUTPUT_ISO="${DIST_DIR}/sp-ouroboros-installer.iso"

mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${ISO_ROOT}"

echo "[ouroboros][iso] building initramfs image at ${INITRAMFS_IMG}"

if [ ! -f "${INITRAMFS_ROOT}/init" ]; then
    echo "[ouroboros][iso] ERROR: ${INITRAMFS_ROOT}/init not found" >&2
    exit 1
fi

# Placeholder for actual initramfs build:
#   (cd "${INITRAMFS_ROOT}" && find . | cpio -H newc -o) | gzip > "${INITRAMFS_IMG}"
#
# For now, we just warn.
echo "[ouroboros][iso] WARNING: initramfs build is not implemented; this is a scaffold."

# Placeholder for copying kernel and bootloader files into ${ISO_ROOT}
# and invoking genisoimage/xorriso. The actual implementation will depend
# on the host distribution and Screaming Penguin's main runtime layout.

cat <<'EOT'

[ouroboros][iso] Scaffold only.

To complete this script in a future phase, we expect to:

1. Select a kernel and initramfs to include in the ISO:
   - Copy vmlinuz → ${ISO_ROOT}/vmlinuz
   - Copy ${INITRAMFS_IMG} → ${ISO_ROOT}/initrd.img

2. Populate isolinux/syslinux bootloader files under:
   - ${ISO_ROOT}/isolinux/

3. Invoke a tool such as genisoimage or xorriso, e.g.:

   genisoimage \\
     -o "${OUTPUT_ISO}" \\
     -b isolinux/isolinux.bin \\
     -c isolinux/boot.cat \\
     -no-emul-boot \\
     -boot-load-size 4 \\
     -boot-info-table \\
     "${ISO_ROOT}"

This script intentionally stops here to avoid producing half-baked boot
artifacts. It exists to define layout and expectations for future work.
EOT
