#!/usr/bin/env bash
set -euo pipefail

echo "[SP-INSTALLER] Building installer initramfs..."

ROOTDIR="$(pwd)"
BUILD_DIR="${ROOTDIR}/build/runtime-installer"
INITRAMFS_DIR="${BUILD_DIR}/rootfs"
OUT_INITRD="${BUILD_DIR}/initrd-installer.img"

rm -rf "${BUILD_DIR}"
mkdir -p "${INITRAMFS_DIR}"

# Create minimal directory tree
mkdir -p "${INITRAMFS_DIR}"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev,mnt/config,run}

# BusyBox
echo "[SP-INSTALLER] Installing BusyBox..."
busybox --install -s "${INITRAMFS_DIR}/bin"

# Installer /init
cat > "${INITRAMFS_DIR}/init" <<'EOF_INIT'
#!/bin/sh
set -e

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev

echo "[SP-INSTALLER] Init starting on $(tty)"

echo "[SP-INSTALLER] Locating CONFIG partition..."
CONFIG_DEV="$(blkid -L CONFIG || true)"

if [ -z "${CONFIG_DEV}" ]; then
    echo "[SP-INSTALLER] ERROR: CONFIG partition not found."
    exec sh
fi

mkdir -p /mnt/config
mount "${CONFIG_DEV}" /mnt/config

if [ ! -f /mnt/config/config/installer-config.yml ]; then
    echo "[SP-INSTALLER] ERROR: Missing installer-config.yml"
    exec sh
fi

echo "[SP-INSTALLER] Launching installer scripts..."
exec /bin/sh
EOF_INIT

chmod +x "${INITRAMFS_DIR}/init"

echo "[SP-INSTALLER] Creating initramfs..."
(
  cd "${INITRAMFS_DIR}"
  find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "${OUT_INITRD}"

echo "[SP-INSTALLER] Installer initramfs built: ${OUT_INITRD}"
