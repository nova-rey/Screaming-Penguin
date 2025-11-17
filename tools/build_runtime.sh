#!/usr/bin/env bash
set -euo pipefail

# Build a minimal Debian-based boot runtime that produces:
#   - build/runtime/vmlinuz
#   - build/runtime/initrd.img
#
# This runtime is for ISO boot only. End users never enter this chroot.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUITE="${SP_RUNTIME_SUITE:-bookworm}"
ARCH="${SP_RUNTIME_ARCH:-amd64}"

CHROOT_DIR="${PROJECT_ROOT}/build/runtime-chroot"
RUNTIME_DIR="${PROJECT_ROOT}/build/runtime"

echo "[SP-RUNTIME] Building minimal boot runtime…"
echo "[SP-RUNTIME] Suite: ${SUITE}"
echo "[SP-RUNTIME] Arch:  ${ARCH}"
echo "[SP-RUNTIME] Chroot: ${CHROOT_DIR}"
echo "[SP-RUNTIME] Out:    ${RUNTIME_DIR}"

mkdir -p "${CHROOT_DIR}" "${RUNTIME_DIR}"

echo "[SP-RUNTIME] Cleaning existing chroot directory…"
rm -rf "${CHROOT_DIR:?}"/*

DEBOOTSTRAP_BIN="${SP_DEBOOTSTRAP_BIN:-debootstrap}"

echo "[SP-RUNTIME] Running debootstrap (minbase)…"
"${DEBOOTSTRAP_BIN}" \
  --arch="${ARCH}" \
  --variant=minbase \
  "${SUITE}" \
  "${CHROOT_DIR}" \
  https://deb.debian.org/debian

# Provide a minimal sources.list
cat > "${CHROOT_DIR}/etc/apt/sources.list" <<EOF2
deb http://deb.debian.org/debian ${SUITE} main
EOF2

echo "[SP-RUNTIME] Installing generic kernel inside chroot…"
chroot "${CHROOT_DIR}" /bin/sh -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends linux-image-amd64
'

echo "[SP-RUNTIME] Locating kernel and initrd…"
KERNEL_PATH="$(find "${CHROOT_DIR}/boot" -maxdepth 1 -type f -name "vmlinuz-*" | sort | tail -n 1 || true)"
INITRD_PATH="$(find "${CHROOT_DIR}/boot" -maxdepth 1 -type f -name "initrd.img-*" | sort | tail -n 1 || true)"

if [ -z "${KERNEL_PATH}" ] || [ -z "${INITRD_PATH}" ]; then
  echo "[SP-RUNTIME] ERROR: Missing vmlinuz-* or initrd.img-* in chroot /boot" >&2
  exit 1
fi

echo "[SP-RUNTIME] Copying kernel and initrd to runtime directory…"
cp "${KERNEL_PATH}" "${RUNTIME_DIR}/vmlinuz"
cp "${INITRD_PATH}" "${RUNTIME_DIR}/initrd.img"

echo "[SP-RUNTIME] Runtime build complete."
echo "[SP-RUNTIME] Kernel: ${RUNTIME_DIR}/vmlinuz"
echo "[SP-RUNTIME] Initrd: ${RUNTIME_DIR}/initrd.img"
