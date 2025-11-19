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
# Minimal Screaming Penguin init for CI smoke tests.

set -eu

# Mount minimal pseudo-filesystems (best effort; ignore failures).
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true
mount -t devtmpfs dev /dev 2>/dev/null || true

MARKER='[SP-INSTALLER] init starting'

{
  # Try to shout the marker everywhere reasonable.
  echo "$MARKER" > /dev/console 2>/dev/null || true
  echo "$MARKER" > /dev/ttyS0 2>/dev/null || true
  echo "$MARKER" >&2 || true
} || true

# Give CI a moment to capture the output.
sleep 2

# Clean shutdown for QEMU CI; fall back to reboot if needed.
poweroff -f 2>/dev/null || halt -f 2>/dev/null || reboot -f
EOF_INIT

chmod +x "${INITRAMFS_DIR}/init"

echo "[SP-INSTALLER] Creating initramfs..."
(
  cd "${INITRAMFS_DIR}"
  find . -print0 | cpio --null -ov --format=newc
) | gzip -9 > "${OUT_INITRD}"

echo "[SP-INSTALLER] Installer initramfs built: ${OUT_INITRD}"
