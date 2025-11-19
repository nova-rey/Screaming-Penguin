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

# ----------------------------
# Create /init entry point
# ----------------------------
cat > "${INITRD_ROOT}/init" << 'EOF_INIT'
#!/bin/sh
echo "[SP-INSTALLER] init starting"

# Minimal early-boot scaffolding
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs dev /dev

# For now, drop to a shell; installer state machine will replace this later.
exec /bin/sh
EOF_INIT

chmod +x "${INITRD_ROOT}/init"

echo "[SP-INSTALLER] Creating initramfs..."
(
    cd "${INITRAMFS_DIR}"
    find . -print0 \
      | cpio --null --owner root:root -H newc -o \
      | gzip -9 > "${DIST_DIR}/initrd-installer.img"
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
