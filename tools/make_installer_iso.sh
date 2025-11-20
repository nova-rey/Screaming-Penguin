#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
ISO_ROOT="${BUILD_DIR}/iso-root"
RUNTIME_DIR="${BUILD_DIR}/runtime"
INSTALLER_DIR="${BUILD_DIR}/installer"
RUNTIME_KERNEL_PATH="${BUILD_DIR}/runtime/vmlinuz"
INSTALLER_INITRD_PATH="${BUILD_DIR}/initrd-installer.img"
DIST_DIR="${PROJECT_ROOT}/dist"
ISO_OUT="${DIST_DIR}/screaming-penguin.iso"
ISO_BOOT_DIR="${ISO_ROOT}/boot"
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
  local INIT_SCRIPT_SRC="${PROJECT_ROOT}/installer/init/init.sh"

  mkdir -p "${RUNTIME_DIR}"
  mkdir -p "${INSTALLER_DIR}"

  rm -rf "${INITRD_ROOT}"
  mkdir -p "${INITRD_ROOT}"/{bin,sbin,etc,proc,sys,dev,run,tmp}

  echo "[SP-INSTALLER] Installing BusyBox..."
  # Use whatever BusyBox is available on the build host; prefer static to avoid
  # missing ld.so/glibc inside the initramfs.
  local BUSYBOX_PATH
  BUSYBOX_PATH="${SP_BUSYBOX_BIN:-$(command -v busybox-static || command -v busybox || true)}"
  if [ -z "${BUSYBOX_PATH}" ]; then
    echo "[SP-BUILD] ERROR: busybox/busybox-static not found on build host; cannot build installer initramfs."
    exit 1
  fi

  cp "${BUSYBOX_PATH}" "${INITRD_ROOT}/bin/busybox"
  chmod 0755 "${INITRD_ROOT}/bin/busybox"

  # If the busybox copy is dynamically linked, include its shared libraries so
  # /init has a working interpreter (prevents "No working init found").
  local BUSYBOX_DYNAMIC=1
  if command -v file >/dev/null 2>&1; then
    if file "${INITRD_ROOT}/bin/busybox" | grep -q "statically linked"; then
      BUSYBOX_DYNAMIC=0
    fi
  else
    local LDD_OUTPUT
    LDD_OUTPUT="$(ldd "${BUSYBOX_PATH}" 2>&1 || true)"
    if echo "${LDD_OUTPUT}" | grep -q "not a dynamic executable"; then
      BUSYBOX_DYNAMIC=0
    fi
  fi

  if [ "${BUSYBOX_DYNAMIC}" -eq 1 ]; then
    echo "[SP-INSTALLER] BusyBox is dynamically linked; copying shared libraries..."
    ldd "${BUSYBOX_PATH}" 2>/dev/null | awk '/=>/ {print $3} /^\// {print $1}' | while read -r lib; do
      [ -z "${lib}" ] && continue
      mkdir -p "${INITRD_ROOT}$(dirname "${lib}")"
      cp -L "${lib}" "${INITRD_ROOT}${lib}"
    done
  fi

  (
    cd "${INITRD_ROOT}/bin"
    for applet in sh mount mkdir echo dmesg sleep; do
      ln -sf busybox "${applet}"
    done
  )

  echo "[SP-INSTALLER] Creating init script..."
  if [ ! -f "${INIT_SCRIPT_SRC}" ]; then
    echo "[SP-BUILD] ERROR: init script source missing: ${INIT_SCRIPT_SRC}" >&2
    exit 1
  fi

  # Place the installer /init at the root of the initramfs so the kernel
  # executes our CI marker + shell entrypoint (consumed by QEMU smoke test).
  cp "${INIT_SCRIPT_SRC}" "${INITRD_ROOT}/init"
  chmod 0755 "${INITRD_ROOT}/init"

  echo "[SP-INSTALLER] Creating initramfs..."
  (
    cd "${INITRD_ROOT}"
    # Use newc format and gzip compression; this matches the runtime initrd.
    find . -print0 \
      | cpio --null --quiet -o -H newc \
      | gzip -9 > "${INSTALLER_INITRD_PATH}"
  )

  # Sanity check: confirm that the archive actually contains a root-level /init.
  echo "[SP-INSTALLER] Verifying installer initramfs contains /init..."
  if ! gzip -dc "${INSTALLER_INITRD_PATH}" 2>/dev/null \
      | cpio -t 2>/dev/null \
      | grep -Eq '(^init$|^\./init$)'; then
    echo "[SP-BUILD] ERROR: initrd-installer.img is missing ./init"
    echo "[SP-BUILD]        Check INITRD_ROOT contents and init creation block."
    exit 1
  fi
}

echo "[SP-ISO] Building hybrid ISO image..."

rm -rf "${ISO_ROOT}"
mkdir -p "${ISO_BOOT_DIR}"

echo "[SP-ISO] Building installer initramfs..."
_build_installer_initramfs

echo "[SP-ISO] Preparing /boot contents for ISO..."
mkdir -p "${ISO_ROOT}/boot"

if [ ! -f "${RUNTIME_KERNEL_PATH}" ]; then
  echo "[SP-ISO] ERROR: Runtime kernel not found at ${RUNTIME_KERNEL_PATH}" >&2
  exit 1
fi

if [ ! -f "${INSTALLER_INITRD_PATH}" ]; then
  echo "[SP-ISO] ERROR: Installer initrd not found at ${INSTALLER_INITRD_PATH}" >&2
  exit 1
fi

cp "${RUNTIME_KERNEL_PATH}" "${ISO_ROOT}/boot/vmlinuz-installer"
cp "${INSTALLER_INITRD_PATH}" "${ISO_ROOT}/boot/initrd-installer.img"

echo "[SP-ISO] /boot contents in ISO root:"
ls -lh "${ISO_ROOT}/boot"

cp -f "${RUNTIME_KERNEL_PATH}" "${DIST_KERNEL_PATH}"
cp -f "${INSTALLER_INITRD_PATH}" "${DIST_INITRD_PATH}"

echo "[SP-ISO] Writing GRUB configuration..."
mkdir -p "${ISO_ROOT}/boot/grub"

cat > "${ISO_ROOT}/boot/grub/grub.cfg" <<'EOF_GRUB'
set timeout=0
set default=0

serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial

menuentry "Screaming Penguin Installer" {
    search --file --set=root /boot/vmlinuz-installer
    linux /boot/vmlinuz-installer root=/dev/ram0 rdinit=/init console=tty0 console=ttyS0,115200n8 earlyprintk=serial
    initrd /boot/initrd-installer.img
}
EOF_GRUB

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
cp /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi "${ISO_ROOT}/efi/boot/bootx64.efi"

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
