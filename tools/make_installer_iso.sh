#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
ISO_ROOT="${BUILD_DIR}/iso-root"
DIST_DIR="${PROJECT_ROOT}/dist"
ISO_OUT="${DIST_DIR}/screaming-penguin.iso"
DIST_KERNEL="${DIST_DIR}/vmlinuz-installer"
DIST_INITRD="${DIST_DIR}/initrd-installer.img"

SP_ISO_BOOT_DIR="${SP_ISO_BOOT_DIR:-${ISO_ROOT}/boot}"
SP_ISO_KERNEL="${SP_ISO_KERNEL:-${SP_ISO_BOOT_DIR}/vmlinuz-installer}"
SP_ISO_INITRD="${SP_ISO_INITRD:-${SP_ISO_BOOT_DIR}/initrd-installer.img}"

GRUB_HELPER="${PROJECT_ROOT}/tools/grub_shared.sh"
if [ ! -f "${GRUB_HELPER}" ]; then
  echo "[SP-ISO] ERROR: Missing GRUB helper: ${GRUB_HELPER}" >&2
  exit 1
fi

# shellcheck source=tools/grub_shared.sh
. "${GRUB_HELPER}"

mkdir -p "${DIST_DIR}"


echo "[SP-ISO] Building installer initramfs..."
bash "${PROJECT_ROOT}/tools/build_installer_initramfs.sh"

if [ ! -f "${DIST_INITRD}" ]; then
  echo "[SP-ISO] ERROR: Installer initrd not found at ${DIST_INITRD}" >&2
  exit 1
fi

echo "[SP-ISO] Building hybrid ISO image..."

rm -rf "${ISO_ROOT}"

echo "[SP-ISO] Preparing /boot contents for ISO..."
mkdir -p "${SP_ISO_BOOT_DIR}"

if [ ! -f "${DIST_KERNEL}" ]; then
  echo "[SP-ISO] ERROR: Installer kernel not found at ${DIST_KERNEL}" >&2
  exit 1
fi

cp "${DIST_KERNEL}" "${SP_ISO_KERNEL}"
cp "${DIST_INITRD}" "${SP_ISO_INITRD}"

echo "[SP-ISO] /boot contents in ISO root:"
ls -lh "${SP_ISO_BOOT_DIR}"

echo "[SP-ISO] Writing GRUB configuration..."
mkdir -p "${ISO_ROOT}/boot/grub"

GRUB_CFG="${ISO_ROOT}/boot/grub/grub.cfg"
LINUX_ARGS="root=/dev/ram0 rdinit=/init console=tty0 console=ttyS0,115200n8 earlyprintk=serial"
cat <<'EOF_GRUB' > "${GRUB_CFG}"
set timeout=0
set default=0

serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial

menuentry "Screaming Penguin Installer" {
    search --file --set=root /boot/vmlinuz-installer
EOF_GRUB
sp_installer_grub_kernel_lines "${LINUX_ARGS}" "" >> "${GRUB_CFG}"
cat <<'EOF_GRUB_END' >> "${GRUB_CFG}"
}
EOF_GRUB_END

GRUB_CFG="${ISO_ROOT}/boot/grub/grub.cfg"

# Keep the BIOS core image minimal: only the modules we actually need
# and the embedded grub.cfg. If we load too many modules here, the
# resulting core image can exceed the BIOS size limit (~0x78000 bytes)
# and grub-mkstandalone will fail with "core image is too big".
GRUB_BIOS_MODULES="biosdisk part_msdos part_gpt iso9660 normal linux search search_fs_uuid search_fs_file configfile serial terminal"

echo "[SP-ISO] Building BIOS GRUB core image..."
GRUB_BIOS_IMG="${ISO_ROOT}/boot/grub/grub.img"
GRUB_BIOS_CORE="${BUILD_DIR}/grub-core.img"
GRUB_BIOS_CDBOOT="/usr/lib/grub/i386-pc/cdboot.img"

grub-mkstandalone \
  -O i386-pc \
  -o "${GRUB_BIOS_CORE}" \
  --install-modules="${GRUB_BIOS_MODULES}" \
  --modules="${GRUB_BIOS_MODULES}" \
  --compress=xz \
  --locales="" \
  --fonts="" \
  "boot/grub/grub.cfg=${GRUB_CFG}"

cat "${GRUB_BIOS_CDBOOT}" "${GRUB_BIOS_CORE}" > "${GRUB_BIOS_IMG}"
rm -f "${GRUB_BIOS_CORE}"

if [ -f "${GRUB_BIOS_IMG}" ]; then
  echo "[SP-ISO] BIOS core size: $(stat -c '%s' "${GRUB_BIOS_IMG}") bytes (limit: 491520)"
fi

# The kernel and initrd are *not* part of the BIOS core image; they are
# added to the ISO tree separately and loaded by grub.cfg at boot time.

echo "[SP-ISO] Creating EFI boot image..."
mkdir -p "${ISO_ROOT}/efi/boot"
GRUB_EFI_BINARY=""
if ! GRUB_EFI_BINARY=$(sp_resolve_grub_efi_binary); then
  GRUB_EFI_BINARY=""
fi

if [ -z "${GRUB_EFI_BINARY}" ]; then
  echo "[SP-ISO] ERROR: grubx64.efi not found (install grub-efi-amd64-bin or set SP_GRUB_EFI_BIN)." >&2
  exit 1
fi

cp "${GRUB_EFI_BINARY}" "${ISO_ROOT}/efi/boot/bootx64.efi"

echo "[SP-ISO] Building final ISO..."
# Ensure output directory exists for the ISO
mkdir -p "$(dirname "${ISO_OUT}")"

echo "[SP-ISO] Debug: contents of ISO_ROOT/boot before xorriso:"
if [ -d "${ISO_ROOT}/boot" ]; then
  ls -lh "${ISO_ROOT}/boot"
else
  echo "[SP-ISO] WARNING: ${ISO_ROOT}/boot does not exist"
fi

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
  "${ISO_ROOT}"

echo "[SP-ISO] ISO built: ${ISO_OUT}"
