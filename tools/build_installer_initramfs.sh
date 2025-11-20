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

# Stage BusyBox for the initramfs; /bin/busybox must exist so the /init
# shebang (#!/bin/busybox sh) has a working interpreter.
install -m 0755 "${BUSYBOX_PATH}" "${INITRD_ROOT}/bin/busybox"

# If BusyBox is dynamically linked, pull in its shared libraries so PID 1 can
# exec /bin/sh without tripping "No working init found" at boot.
BUSYBOX_DYNAMIC=1
if command -v file >/dev/null 2>&1; then
  if file "${INITRD_ROOT}/bin/busybox" | grep -q "statically linked"; then
    BUSYBOX_DYNAMIC=0
  fi
else
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
  for applet in sh mount mkdir echo sleep; do
    ln -sf busybox "${applet}"
  done
)

echo "[SP-INSTALLER] Creating init script..."
if [ ! -f "${INIT_SCRIPT_SRC}" ]; then
  echo "[SP-BUILD] ERROR: init script source missing: ${INIT_SCRIPT_SRC}" >&2
  exit 1
fi

# Place the installer /init at the root of the initramfs so the kernel
# runs our CI-visible entrypoint for smoke testing.
install -m 0755 "${INIT_SCRIPT_SRC}" "${INITRD_ROOT}/init"

echo "[SP-INSTALLER] Creating initramfs..."
(
  cd "${INITRD_ROOT}"
  find . | cpio -o -H newc | gzip -9 > "${DIST_DIR}/initrd-installer.img"
)

# ----------------------------
# Sanity check: /init must exist in initramfs
# ----------------------------
if ! gzip -cd "${DIST_DIR}/initrd-installer.img" | cpio -t 2>/dev/null | grep -Eq '^(init|./init)$'; then
    echo "[SP-BUILD] ERROR: initrd-installer.img is missing ./init"
    echo "[SP-BUILD]       Check INITRD_ROOT contents and init creation block."
    exit 1
fi

echo "[SP-INSTALLER] Installer initramfs built: ${DIST_DIR}/initrd-installer.img"
