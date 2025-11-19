#!/usr/bin/env bash
set -euo pipefail

echo "[SP-INSTALLER] Building installer initramfs..."

ROOTDIR="$(pwd)"
WORKDIR="${ROOTDIR}/build/runtime-installer"
INITRD_ROOT="${WORKDIR}/initrd-root"

# Output directory for the installer initramfs image.
# DIST_DIR can override this; default is "dist".
INSTALLER_OUT_DIR="${DIST_DIR:-dist}"
mkdir -p "${INSTALLER_OUT_DIR}"

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
    cd "${INITRD_ROOT}"
    find . -print0 \
      | cpio --null --owner root:root -H newc -o \
      | gzip -9 > "${INSTALLER_OUT_DIR}/initrd-installer.img"
)

# ----------------------------
# Sanity check: /init must exist in initramfs
# ----------------------------
if ! gzip -cd "${INSTALLER_OUT_DIR}/initrd-installer.img" | cpio -t 2>/dev/null | grep -qx './init'; then
    echo "[SP-BUILD] ERROR: initrd-installer.img is missing ./init"
    echo "[SP-BUILD]       Check INITRD_ROOT contents and init creation block."
    exit 1
fi

echo "[SP-INSTALLER] Installer initramfs built: ${INSTALLER_OUT_DIR}/initrd-installer.img"
