#!/usr/bin/env bash
set -euo pipefail

ROOTDIR="$(pwd)"
BUILD_DIR="${ROOTDIR}/build/iso"
RUNTIME_DIR="${ROOTDIR}/build/runtime"
INSTALLER_DIR="${ROOTDIR}/build/runtime-installer"
ISO_OUT="${ROOTDIR}/dist/screaming-penguin.iso"

echo "[SP-ISO] Building hybrid ISO image..."

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/boot"

echo "[SP-ISO] Preparing base runtime kernel..."
cp "${RUNTIME_DIR}/vmlinuz" "${BUILD_DIR}/boot/vmlinuz"

echo "[SP-ISO] Building installer initramfs..."
bash tools/build_installer_initramfs.sh
cp "${INSTALLER_DIR}/initrd-installer.img" "${BUILD_DIR}/boot/initrd-install.img"

echo "[SP-ISO] Writing GRUB configuration..."
mkdir -p "${BUILD_DIR}/boot/grub"

cat > "${BUILD_DIR}/boot/grub/grub.cfg" <<'EOF_GRUB'
set default=0
set timeout=0

menuentry "Screaming Penguin Installer" {
    linux /boot/vmlinuz root=/dev/ram0 rdinit=/init quiet
    initrd /boot/initrd-install.img
}
EOF_GRUB

GRUB_CFG="${BUILD_DIR}/boot/grub/grub.cfg"

# Keep the BIOS core image minimal: only the modules we actually need
# and the embedded grub.cfg. If we load too many modules here, the
# resulting core image can exceed the BIOS size limit (~0x78000 bytes)
# and grub-mkstandalone will fail with "core image is too big".
GRUB_BIOS_MODULES="biosdisk iso9660 normal linux"

echo "[SP-ISO] Building BIOS GRUB core image..."
GRUB_BIOS_IMG="${BUILD_DIR}/boot/grub/grub.img"

grub-mkstandalone \
  -O i386-pc \
  -o "${GRUB_BIOS_IMG}" \
  --modules="${GRUB_BIOS_MODULES}" \
  --locales="" \
  --fonts="" \
  "boot/grub/grub.cfg=${GRUB_CFG}"

# The kernel and initrd are *not* part of the BIOS core image; they are
# added to the ISO tree separately and loaded by grub.cfg at boot time.

echo "[SP-ISO] Creating EFI boot image..."
mkdir -p "${BUILD_DIR}/efi/boot"
cp /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi "${BUILD_DIR}/efi/boot/bootx64.efi"

echo "[SP-ISO] Building final ISO..."
# Ensure output directory exists for the ISO
mkdir -p "$(dirname "${ISO_OUT}")"
xorriso -as mkisofs \
  -iso-level 3 \
  -o "${ISO_OUT}" \
  -full-iso9660-filenames \
  -eltorito-boot boot/grub/grub.img \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-catalog boot/grub/boot.cat \
  -eltorito-alt-boot \
  -e efi/boot/bootx64.efi \
  -no-emul-boot \
  "${BUILD_DIR}"

echo "[SP-ISO] ISO built: ${ISO_OUT}"