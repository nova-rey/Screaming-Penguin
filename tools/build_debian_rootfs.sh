#!/bin/sh
# Screaming Penguin - Debian Rootfs Builder (Phase 4)
#
# This script builds a minimal Debian Bookworm (amd64) root filesystem
# using debootstrap or mmdebstrap. All operations occur only within the
# repository under build/ and dist/.
#
# SAFETY REQUIREMENTS:
#   - MUST NOT modify the host system.
#   - MUST NOT touch real block devices.
#   - MUST NOT operate outside build/ and dist/.
#
# Produces:
#   dist/debian-rootfs-bookworm-amd64.tar.gz

set -eu

SUITE="bookworm"
ARCH="amd64"
BUILD_DIR="build/rootfs-${SUITE}-${ARCH}"
DIST_DIR="dist"
TARBALL="${DIST_DIR}/debian-rootfs-${SUITE}-${ARCH}.tar.gz"

echo "[SP-ROOTFS] Starting Debian rootfs build…"
echo "[SP-ROOTFS] Suite: ${SUITE}"
echo "[SP-ROOTFS] Arch:  ${ARCH}"
echo "[SP-ROOTFS] Build dir: ${BUILD_DIR}"
echo "[SP-ROOTFS] Output tarball: ${TARBALL}"

# Ensure directories exist
mkdir -p "${BUILD_DIR}"
mkdir -p "${DIST_DIR}"

# Clean previous contents safely
echo "[SP-ROOTFS] Cleaning build directory…"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Check for bootstrapping tool
if command -v mmdebstrap >/dev/null 2>&1; then
    TOOL="mmdebstrap"
elif command -v debootstrap >/dev/null 2>&1; then
    TOOL="debootstrap"
else
    echo "[SP-ROOTFS] ERROR: Neither debootstrap nor mmdebstrap is installed."
    exit 1
fi

echo "[SP-ROOTFS] Using bootstrap tool: ${TOOL}"

# Run bootstrap tool
if [ "${TOOL}" = "mmdebstrap" ]; then
    echo "[SP-ROOTFS] Running mmdebstrap…"
    mmdebstrap --variant=minbase "${SUITE}" "${BUILD_DIR}"
else
    echo "[SP-ROOTFS] Running debootstrap…"
    debootstrap --variant=minbase "${SUITE}" "${BUILD_DIR}"
fi

echo "[SP-ROOTFS] Bootstrap complete."

# Minimal sanitization
echo "[SP-ROOTFS] Applying minimal sanitization…"

# Set generic hostname
echo "penguin" > "${BUILD_DIR}/etc/hostname"

# Lock root password (root:!*:)
if [ -f "${BUILD_DIR}/etc/shadow" ]; then
    sed -i 's|^root:[^:]*:|root:*:|' "${BUILD_DIR}/etc/shadow"
fi

# Ensure /etc/os-release exists
if [ ! -f "${BUILD_DIR}/etc/os-release" ]; then
    echo "NAME=Debian" > "${BUILD_DIR}/etc/os-release"
    echo "VERSION=${SUITE}" >> "${BUILD_DIR}/etc/os-release"
fi

# Create tarball
echo "[SP-ROOTFS] Packaging rootfs tarball…"
tar -C "${BUILD_DIR}" -czf "${TARBALL}" .

echo "[SP-ROOTFS] Rootfs build complete."
echo "[SP-ROOTFS] Output: ${TARBALL}"
