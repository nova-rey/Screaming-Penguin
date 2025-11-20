#!/usr/bin/env bash
set -euo pipefail

# Determine project root (one directory above tools/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
INITRAMFS_DIR="${PROJECT_ROOT}/build/installer-initramfs"

# Ensure output directories exist
mkdir -p "${DIST_DIR}"
mkdir -p "${INITRAMFS_DIR}"

echo "[SP-INSTALLER] Building installer initramfs..."

INITRD_ROOT="${INITRAMFS_DIR}"
INIT_SCRIPT_SRC="${PROJECT_ROOT}/installer/init/init.sh"

rm -rf "${INITRAMFS_DIR:?}/"*
mkdir -p "${INITRD_ROOT}"

# Create minimal directory tree
mkdir -p "${INITRD_ROOT}"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev,mnt/config,run}

echo "[SP-INSTALLER] Installing BusyBox..."
BUSYBOX_PATH="${SP_BUSYBOX_BIN:-$(command -v busybox-static || command -v busybox || true)}"
if [ -z "${BUSYBOX_PATH}" ]; then
  echo "[SP-BUILD] ERROR: busybox/busybox-static not found on build host; cannot build installer initramfs." >&2
  exit 1
fi

cp "${BUSYBOX_PATH}" "${INITRD_ROOT}/bin/busybox"
chmod 0755 "${INITRD_ROOT}/bin/busybox"

(
  cd "${INITRD_ROOT}/bin"
  for applet in sh mount mkdir echo sleep; do
    ln -sf busybox "${applet}"
  done
)

echo "[SP-INSTALLER] Creating init script..."
if [ ! -f "${INIT_SCRIPT_SRC}" ]; then
  echo "[SP-BUILD] ERROR: init script source missing: ${INIT_SCRIPT_SRC}" >&2
  exit 1
fi

cp "${INIT_SCRIPT_SRC}" "${INITRD_ROOT}/init"
chmod 0755 "${INITRD_ROOT}/init"

echo "[SP-INSTALLER] Creating initramfs..."
(
  cd "${INITRD_ROOT}"
  find . | cpio -o -H newc | gzip > "${DIST_DIR}/initrd-installer.img"
)

# ----------------------------
# Sanity check: /init must exist in initramfs
# ----------------------------
if ! gzip -cd "${DIST_DIR}/initrd-installer.img" | cpio -t 2>/dev/null | grep -qx './init'; then
    echo "[SP-BUILD] ERROR: initrd-installer.img is missing ./init"
    echo "[SP-BUILD]       Check INITRD_ROOT contents and init creation block."
    exit 1
fi

echo "[SP-INSTALLER] Installer initramfs built: ${DIST_DIR}/initrd-installer.img"
