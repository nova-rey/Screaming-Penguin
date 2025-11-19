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

rm -rf "${INITRAMFS_DIR:?}/"*
mkdir -p "${INITRD_ROOT}"

# Create minimal directory tree
mkdir -p "${INITRD_ROOT}"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev,mnt/config,run}

# BusyBox
echo "[SP-INSTALLER] Installing BusyBox..."
busybox --install -s "${INITRD_ROOT}/bin"

echo "[SP-INSTALLER] Creating init script..."

# Basic directories needed by init
mkdir -p \
  "${INITRD_ROOT}/proc" \
  "${INITRD_ROOT}/sys" \
  "${INITRD_ROOT}/dev"

INIT_SCRIPT="${INITRD_ROOT}/init"

cat > "${INIT_SCRIPT}" << 'EOF'
#!/bin/busybox sh
# Minimal Screaming Penguin installer init (stub)

set -e

# Mount core pseudo-filesystems
mount -t proc proc /proc
mount -t sysfs sys /sys

# Try devtmpfs first; fall back to tmpfs if unavailable
if ! mount -t devtmpfs devtmpfs /dev 2>/dev/null; then
    mount -t tmpfs tmpfs /dev
fi

echo "[SP-INSTALLER] init: Screaming Penguin installer stub starting..."
echo "[SP-INSTALLER] init: Dropping into BusyBox shell (placeholder installer)."

exec /bin/sh
EOF

chmod +x "${INIT_SCRIPT}"

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
