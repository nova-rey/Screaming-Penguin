#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
ISO_ROOT="${BUILD_DIR}/iso-root"
RUNTIME_DIR="${BUILD_DIR}/runtime"
INSTALLER_DIR="${BUILD_DIR}/installer"
RUNTIME_KERNEL="${BUILD_DIR}/runtime/vmlinuz"
RUNTIME_INITRD="${BUILD_DIR}/runtime/initrd.img"
INSTALLER_INITRD_PATH="${BUILD_DIR}/initrd-installer.img"
DIST_DIR="${PROJECT_ROOT}/dist"
ISO_OUT="${DIST_DIR}/screaming-penguin.iso"
ISO_BOOT_DIR="${ISO_ROOT}/boot"
DIST_KERNEL="${DIST_DIR}/vmlinuz-installer"
DIST_INITRD="${DIST_DIR}/initrd-installer.img"

GRUB_HELPER="${PROJECT_ROOT}/tools/grub_shared.sh"
if [ ! -f "${GRUB_HELPER}" ]; then
  echo "[SP-ISO] ERROR: Missing GRUB helper: ${GRUB_HELPER}" >&2
  exit 1
fi

# shellcheck source=tools/grub_shared.sh
. "${GRUB_HELPER}"

mkdir -p "${DIST_DIR}"

if [ -f "${RUNTIME_KERNEL}" ] && [ -f "${RUNTIME_INITRD}" ]; then
  SP_BOOT_KERNEL="${RUNTIME_KERNEL}"
  SP_BOOT_INITRD="${RUNTIME_INITRD}"
elif [ -f "${DIST_KERNEL}" ] && [ -f "${DIST_INITRD}" ]; then
  echo "[SP-ISO] Runtime kernel not found in build/runtime; falling back to dist/ artifacts..."
  SP_BOOT_KERNEL="${DIST_KERNEL}"
  SP_BOOT_INITRD="${DIST_INITRD}"
else
  echo "[SP-ISO] ERROR: Runtime kernel not found at ${RUNTIME_KERNEL}/${RUNTIME_INITRD} or ${DIST_KERNEL}/${DIST_INITRD}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build minimal installer initramfs (BusyBox + /init) for the ISO
# ---------------------------------------------------------------------------
_build_installer_initramfs() {
  echo "[SP-INSTALLER] Building installer initramfs..."

  # Root of the installer initramfs tree
  local INITRD_ROOT="${BUILD_DIR}/installer-initrd"
  local INIT_SCRIPT_SRC="${PROJECT_ROOT}/installer/init/init.sh"

  _is_busybox_static() {
    local candidate="$1"
    if command -v file >/dev/null 2>&1 && file "${candidate}" | grep -q "statically linked"; then
      return 0
    fi

    if command -v ldd >/dev/null 2>&1; then
      local ldd_out
      ldd_out="$(ldd "${candidate}" 2>&1 || true)"
      if echo "${ldd_out}" | grep -q "not a dynamic executable"; then
        return 0
      fi
    fi

    return 1
  }

  mkdir -p "${RUNTIME_DIR}"
  mkdir -p "${INSTALLER_DIR}"

  rm -rf "${INITRD_ROOT}"
  mkdir -p "${INITRD_ROOT}"/{bin,sbin,etc,proc,sys,dev,run,tmp}

  echo "[SP-INSTALLER] Installing BusyBox..."
  # Use whatever BusyBox is available on the build host; prefer static to avoid
  # missing ld.so/glibc inside the initramfs.
  local BUSYBOX_PATH
  BUSYBOX_PATH="${SP_BUSYBOX_BIN:-$(command -v busybox-static || command -v busybox || true)}"
  local STATIC_CANDIDATE
  STATIC_CANDIDATE="$(command -v busybox-static || true)"
  if [ -n "${STATIC_CANDIDATE}" ] && [ "${BUSYBOX_PATH}" != "${STATIC_CANDIDATE}" ]; then
    echo "[SP-INSTALLER] Preferring busybox-static at ${STATIC_CANDIDATE} over ${BUSYBOX_PATH:-N/A}."
    BUSYBOX_PATH="${STATIC_CANDIDATE}"
  fi

  if [ -z "${BUSYBOX_PATH}" ]; then
    echo "[SP-BUILD] ERROR: busybox/busybox-static not found on build host; cannot build installer initramfs."
    exit 1
  fi

  echo "[SP-INSTALLER] BusyBox candidate: ${BUSYBOX_PATH}"
  if command -v file >/dev/null 2>&1; then
    file "${BUSYBOX_PATH}" || true
  else
    echo "[SP-INSTALLER] 'file' not available; skipping BusyBox file inspection."
  fi
  if command -v ldd >/dev/null 2>&1; then
    ldd "${BUSYBOX_PATH}" || true
  else
    echo "[SP-INSTALLER] 'ldd' not available; skipping BusyBox dependency inspection."
  fi

  if _is_busybox_static "${BUSYBOX_PATH}"; then
    echo "[SP-INSTALLER] BusyBox is static; no shared library staging required."
  else
    echo "[SP-INSTALLER] BusyBox appears dynamic; attempting to source a static binary..."
    if command -v apt-get >/dev/null 2>&1; then
      echo "[SP-INSTALLER] Installing busybox-static via apt (if available)..."
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y busybox-static
      BUSYBOX_PATH="${SP_BUSYBOX_BIN:-$(command -v busybox-static || command -v busybox || true)}"
      echo "[SP-INSTALLER] BusyBox candidate after install: ${BUSYBOX_PATH:-none}"
    fi
  fi

  if [ -z "${BUSYBOX_PATH}" ]; then
    echo "[SP-BUILD] ERROR: busybox/busybox-static not found on build host; cannot build installer initramfs." >&2
    exit 1
  fi

  echo "[SP-INSTALLER] Final BusyBox selection: ${BUSYBOX_PATH}"
  if command -v file >/dev/null 2>&1; then
    file "${BUSYBOX_PATH}" || true
  fi
  if command -v ldd >/dev/null 2>&1; then
    ldd "${BUSYBOX_PATH}" || true
  fi

  # Stage BusyBox for the initramfs; /bin/busybox must exist so the /init
  # shebang (#!/bin/busybox sh) has a working interpreter.
  install -m 0755 "${BUSYBOX_PATH}" "${INITRD_ROOT}/bin/busybox"
  chmod 0755 "${INITRD_ROOT}/bin/busybox"

  # If the busybox copy is dynamically linked, include its shared libraries so
  # /init has a working interpreter (prevents "No working init found").
  local BUSYBOX_DYNAMIC=1
  if _is_busybox_static "${INITRD_ROOT}/bin/busybox"; then
    BUSYBOX_DYNAMIC=0
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
  install -m 0755 "${INIT_SCRIPT_SRC}" "${INITRD_ROOT}/init"
  chmod 0755 "${INITRD_ROOT}/init"
  echo "[SP-INSTALLER] Staged /init -> ${INITRD_ROOT}/init (mode $(stat -c %a "${INITRD_ROOT}/init"))"

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
  INITRD_FILE_LIST="$(gzip -dc "${INSTALLER_INITRD_PATH}" 2>/dev/null | cpio -t 2>/dev/null)"

  echo "[SP-INSTALLER] initramfs file list:"
  printf '%s\n' "${INITRD_FILE_LIST}"

  echo "[SP-INSTALLER] init and /bin/busybox permissions within initramfs:"
  gzip -dc "${INSTALLER_INITRD_PATH}" 2>/dev/null | cpio -tv 2>/dev/null | grep -E '(^-.* init$|^-.* bin/busybox$)' || true

  if ! printf '%s\n' "${INITRD_FILE_LIST}" | grep -Eq '(^init$|^\./init$)'; then
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

if [ ! -f "${INSTALLER_INITRD_PATH}" ]; then
  echo "[SP-ISO] ERROR: Installer initrd not found at ${INSTALLER_INITRD_PATH}" >&2
  exit 1
fi

cp "${SP_BOOT_KERNEL}" "${ISO_ROOT}/boot/vmlinuz-installer"
cp "${SP_BOOT_INITRD}" "${ISO_ROOT}/boot/initrd-installer.img"

echo "[SP-ISO] /boot contents in ISO root:"
ls -lh "${ISO_ROOT}/boot"

cp -f "${SP_BOOT_KERNEL}" "${DIST_KERNEL}"
cp -f "${INSTALLER_INITRD_PATH}" "${DIST_INITRD}"

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
