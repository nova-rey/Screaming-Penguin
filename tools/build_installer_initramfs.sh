#!/usr/bin/env bash
set -euo pipefail

echo "[SP-INSTALLER] Building installer initramfs..."

ROOTDIR="$(pwd)"
WORKDIR="${ROOTDIR}/build/runtime-installer"
INSTALLER_DIR="${WORKDIR}"
INITRD_ROOT="${WORKDIR}/rootfs"
OUT_INITRD="${INSTALLER_DIR}/initrd-installer.img"

rm -rf "${WORKDIR}"
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

# Minimal boot scaffolding
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs dev /dev

# For now drop to a shell; replaced later by full installer
exec /bin/sh
EOF_INIT

chmod +x "${INITRD_ROOT}/init"

echo "[SP-INSTALLER] Creating initramfs..."
(
    cd "${INITRD_ROOT}"
    find . -print0 \
      | cpio --null --owner root:root -H newc -o \
      | gzip -9 > "${INSTALLER_DIR}/initrd-installer.img"
)

echo "[SP-INSTALLER] Installer initramfs built: ${OUT_INITRD}"
