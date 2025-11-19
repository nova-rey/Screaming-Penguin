#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/iso"
RUNTIME_DIR="${PROJECT_ROOT}/build/runtime"
DIST_DIR="${PROJECT_ROOT}/dist"
ISO_OUT="${DIST_DIR}/screaming-penguin.iso"
ISO_BOOT_DIR="${BUILD_DIR}/boot"
ISO_KERNEL_PATH="${ISO_BOOT_DIR}/vmlinuz-installer"
ISO_INITRD_PATH="${ISO_BOOT_DIR}/initrd-installer.img"
DIST_KERNEL_PATH="${DIST_DIR}/vmlinuz-installer"
DIST_INITRD_PATH="${DIST_DIR}/initrd-installer.img"

mkdir -p "${DIST_DIR}"

# ---------------------------------------------------------------------------
# Build minimal installer initramfs (BusyBox + /init) for the ISO
# ---------------------------------------------------------------------------
_build_installer_initramfs() {
  echo "[SP-INSTALLER] Building installer initramfs..."

  # Root of the installer initramfs tree
  local INITRD_ROOT="${BUILD_DIR}/installer-initrd"
  local INSTALLER_INITRD="${RUNTIME_DIR}/initrd-installer.img"

  mkdir -p "${RUNTIME_DIR}"

  rm -rf "${INITRD_ROOT}"
  mkdir -p "${INITRD_ROOT}"/{bin,sbin,etc,proc,sys,dev,run,tmp}

  echo "[SP-INSTALLER] Installing BusyBox..."
  # Use whatever BusyBox is available on the build host; we only need a few applets.
  local BUSYBOX_PATH
  BUSYBOX_PATH="$(command -v busybox || true)"
  if [ -z "${BUSYBOX_PATH}" ]; then
    echo "[SP-BUILD] ERROR: busybox not found on build host; cannot build installer initramfs."
    exit 1
  fi

  cp "${BUSYBOX_PATH}" "${INITRD_ROOT}/bin/busybox"
  chmod 0755 "${INITRD_ROOT}/bin/busybox"

  (
    cd "${INITRD_ROOT}/bin"
    for applet in sh mount mkdir echo dmesg; do
      ln -sf busybox "${applet}"
    done
  )

  echo "[SP-INSTALLER] Creating init script..."
  # IMPORTANT: this must be `/init` at the archive root so the kernel can execute it.
  cat > "${INITRD_ROOT}/init" <<'EOF'
#!/bin/sh
# Minimal Screaming Penguin installer init
# This is a placeholder skeleton: mount basic filesystems and drop to a shell.

echo "[SP-INSTALLER] init: starting minimal installer environment..."

# Mount essential pseudo-filesystems
mount -t proc proc /proc 2>/dev/null || echo "[SP-INSTALLER] warning: failed to mount /proc"
mount -t sysfs sysfs /sys 2>/dev/null || echo "[SP-INSTALLER] warning: failed to mount /sys"
mount -t devtmpfs devtmpfs /dev 2>/dev/null || echo "[SP-INSTALLER] warning: failed to mount /dev"

# For now, just drop to a shell; the real installer state machine will hook in later.
exec /bin/sh
EOF

  chmod 0755 "${INITRD_ROOT}/init"

  echo "[SP-INSTALLER] Creating initramfs..."
  (
    cd "${INITRD_ROOT}"
    # Use newc format and gzip compression; this matches the runtime initrd.
    find . -print0 \
      | cpio --null --quiet -o -H newc \
      | gzip -9 > "${INSTALLER_INITRD}"
  )

  # Sanity check: confirm that the archive actually contains a root-level /init.
  echo "[SP-INSTALLER] Verifying installer initramfs contains /init..."
  if ! gzip -dc "${INSTALLER_INITRD}" 2>/dev/null \
      | cpio -t 2>/dev/null \
      | grep -Eq '(^init$|^\./init$)'; then
    echo "[SP-BUILD] ERROR: initrd-installer.img is missing ./init"
    echo "[SP-BUILD]        Check INITRD_ROOT contents and init creation block."
    exit 1
  fi
}

echo "[SP-ISO] Building hybrid ISO image..."

rm -rf "${BUILD_DIR}"
mkdir -p "${ISO_BOOT_DIR}"

echo "[SP-ISO] Preparing base runtime kernel..."
cp "${RUNTIME_DIR}/vmlinuz" "${ISO_KERNEL_PATH}"
cp "${RUNTIME_DIR}/vmlinuz" "${DIST_KERNEL_PATH}"

echo "[SP-ISO] Building installer initramfs..."
_build_installer_initramfs
cp "${RUNTIME_DIR}/initrd-installer.img" "${ISO_INITRD_PATH}"
cp "${RUNTIME_DIR}/initrd-installer.img" "${DIST_INITRD_PATH}"

echo "[SP-ISO] Writing GRUB configuration..."
mkdir -p "${BUILD_DIR}/boot/grub"

cat > "${BUILD_DIR}/boot/grub/grub.cfg" <<'EOF_GRUB'
# Screaming Penguin grub configuration

set default=0
set timeout=0

serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial console
terminal_output serial console

menuentry "Screaming Penguin Installer (stub)" {
    linux /boot/vmlinuz-installer \
        root=/dev/ram0 rw \
        console=tty0 console=ttyS0,115200 \
        quiet
    initrd /boot/initrd-installer.img
}
EOF_GRUB

GRUB_CFG="${BUILD_DIR}/boot/grub/grub.cfg"

# Keep the BIOS core image minimal: only the modules we actually need
# and the embedded grub.cfg. If we load too many modules here, the
# resulting core image can exceed the BIOS size limit (~0x78000 bytes)
# and grub-mkstandalone will fail with "core image is too big".
GRUB_BIOS_MODULES="biosdisk part_msdos part_gpt iso9660 normal linux search search_fs_uuid search_fs_file configfile"

echo "[SP-ISO] Building BIOS GRUB core image..."
GRUB_BIOS_IMG="${BUILD_DIR}/boot/grub/grub.img"

grub-mkstandalone \
  -O i386-pc \
  -o "${GRUB_BIOS_IMG}" \
  --install-modules="${GRUB_BIOS_MODULES}" \
  --modules="${GRUB_BIOS_MODULES}" \
  --compress=xz \
  --locales="" \
  --fonts="" \
  "boot/grub/grub.cfg=${GRUB_CFG}"

if [ -f "${GRUB_BIOS_IMG}" ]; then
  echo "[SP-ISO] BIOS core size: $(stat -c '%s' "${GRUB_BIOS_IMG}") bytes (limit: 491520)"
fi

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