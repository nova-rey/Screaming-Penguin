#!/usr/bin/env bash
set -euo pipefail

# Determine project root (one directory above tools/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
INITRAMFS_DIR="${PROJECT_ROOT}/build/installer-initramfs"
RUNTIME_LIB_SRC="${PROJECT_ROOT}/installer/runtime/lib"
RUNTIME_CHROOT_MODULES="${SP_INSTALLER_RUNTIME_CHROOT_MODULES:-${PROJECT_ROOT}/build/runtime-chroot/lib/modules}"
MIN_INITRD_SIZE_BYTES="${SP_MIN_INITRD_SIZE_BYTES:-$((1 * 1024 * 1024))}"

echo "[SP-INSTALLER] Building installer initramfs..."

INITRD_ROOT="${INITRAMFS_DIR}"
INIT_SCRIPT_SRC="${PROJECT_ROOT}/installer/init/init.sh"

_is_busybox_static() {
  local candidate="$1"
  if command -v file >/dev/null 2>&1 && file "${candidate}" | grep -q "statically linked"; then
    return 0
  fi

  if command -v ldd >/dev/null 2>&1; then
    local ldd_out
    ldd_out="$(ldd "${candidate}" 2>&1 || true)"
    if echo "${ldd_out}" | grep -q "not a dynamic executable"; then
      return 0
    fi
  fi

  return 1
}

_determine_kernel_version() {
  local kernel_image="$1"
  local detected_version=""
  local runtime_versions=()
  local runtime_note=""

  DETECTION_METHOD=""

  if [ -n "${SP_INSTALLER_KERNEL_VERSION:-}" ]; then
    detected_version="${SP_INSTALLER_KERNEL_VERSION}"
    DETECTION_METHOD="override (SP_INSTALLER_KERNEL_VERSION)"
    KERNEL_VERSION="${detected_version}"
    return 0
  fi

  if [ -d "${RUNTIME_CHROOT_MODULES}" ]; then
    mapfile -t runtime_versions < <(find "${RUNTIME_CHROOT_MODULES}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  fi

  if [ "${#runtime_versions[@]}" -gt 1 ]; then
    local version_list="${runtime_versions[0]}"
    for version in "${runtime_versions[@]:1}"; do
      version_list+=", ${version}"
    done
    echo "[SP-BUILD] ERROR: Multiple kernel versions found in ${RUNTIME_CHROOT_MODULES}: ${version_list}; set SP_INSTALLER_KERNEL_VERSION to pick one." >&2
    return 1
  fi

  if [ "${#runtime_versions[@]}" -eq 1 ]; then
    detected_version="${runtime_versions[0]}"
    DETECTION_METHOD="runtime-chroot (${detected_version})"
  fi

  if [ -z "${detected_version}" ] && [ -L "${kernel_image}" ]; then
    local symlink_name
    symlink_name="$(basename "$(readlink "${kernel_image}")")"
    if [[ "${symlink_name}" == vmlinuz-* ]]; then
      detected_version="${symlink_name#vmlinuz-}"
      DETECTION_METHOD="symlink (${symlink_name})"
    fi
  fi

  if [ -z "${detected_version}" ]; then
    if [ -d "${RUNTIME_CHROOT_MODULES}" ]; then
      runtime_note="runtime-chroot modules under ${RUNTIME_CHROOT_MODULES}"
    else
      runtime_note="runtime-chroot modules missing at ${RUNTIME_CHROOT_MODULES}; run tools/build_runtime.sh"
    fi
    echo "[SP-BUILD] ERROR: Unable to determine installer kernel version; checked SP_INSTALLER_KERNEL_VERSION, ${runtime_note}, and symlink target of ${kernel_image}. Set SP_INSTALLER_KERNEL_VERSION or ensure runtime-chroot modules exist." >&2
    return 1
  fi

  KERNEL_VERSION="${detected_version}"
  return 0
}

INSTALLER_KERNEL_IMAGE="${SP_INSTALLER_KERNEL_IMAGE:-${PROJECT_ROOT}/build/runtime/vmlinuz}"

if [ ! -f "${INSTALLER_KERNEL_IMAGE}" ]; then
  DIST_KERNEL="${DIST_DIR}/vmlinuz-installer"
  if [ -f "${DIST_KERNEL}" ]; then
    INSTALLER_KERNEL_IMAGE="${DIST_KERNEL}"
  fi
fi

if [ ! -f "${INSTALLER_KERNEL_IMAGE}" ]; then
  echo "[SP-BUILD] ERROR: Installer kernel binary missing: ${INSTALLER_KERNEL_IMAGE}" >&2
  exit 1
fi

if ! _determine_kernel_version "${INSTALLER_KERNEL_IMAGE}"; then
  exit 1
fi

MODULES_ROOT="${SP_INSTALLER_MODULES_ROOT:-/lib/modules}"
MODULES_SRC="${SP_INSTALLER_MODULES_SRC:-${MODULES_ROOT}/${KERNEL_VERSION}}"
MODULES_DST="${INITRD_ROOT}/lib/modules/${KERNEL_VERSION}"

echo "[SP-INSTALLER] Installer kernel image: ${INSTALLER_KERNEL_IMAGE}"
echo "[SP-INSTALLER] Kernel version detection method: ${DETECTION_METHOD}"
echo "[SP-INSTALLER] Installer kernel version: ${KERNEL_VERSION}"
echo "[SP-INSTALLER] Kernel modules source: ${MODULES_SRC}"
echo "[SP-INSTALLER] Kernel modules destination: ${MODULES_DST}"

if [ "${SP_INSTALLER_KERNEL_DETECT_MODE:-0}" = "1" ]; then
  exit 0
fi

# Ensure output directories exist
mkdir -p "${DIST_DIR}"
mkdir -p "${INITRAMFS_DIR}"

rm -rf "${INITRAMFS_DIR:?}/"*
mkdir -p "${INITRD_ROOT}"

# Create minimal directory tree
mkdir -p "${INITRD_ROOT}"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev,mnt/config,run}
mkdir -p "${INITRD_ROOT}/runtime/lib"
mkdir -p "${INITRD_ROOT}/lib/modules"

echo "[SP-INSTALLER] Installing BusyBox..."
BUSYBOX_PATH="${SP_BUSYBOX_BIN:-$(command -v busybox-static || command -v busybox || true)}"
STATIC_CANDIDATE="$(command -v busybox-static || true)"
if [ -n "${STATIC_CANDIDATE}" ] && [ "${BUSYBOX_PATH}" != "${STATIC_CANDIDATE}" ]; then
  echo "[SP-INSTALLER] Preferring busybox-static at ${STATIC_CANDIDATE} over ${BUSYBOX_PATH:-N/A}."
  BUSYBOX_PATH="${STATIC_CANDIDATE}"
fi

if [ -z "${BUSYBOX_PATH}" ]; then
  echo "[SP-BUILD] ERROR: busybox/busybox-static not found on build host; cannot build installer initramfs." >&2
  exit 1
fi

echo "[SP-INSTALLER] BusyBox candidate: ${BUSYBOX_PATH}"
if command -v file >/dev/null 2>&1; then
  file "${BUSYBOX_PATH}" || true
fi
if command -v ldd >/dev/null 2>&1; then
  ldd "${BUSYBOX_PATH}" || true
fi

if _is_busybox_static "${BUSYBOX_PATH}"; then
  echo "[SP-INSTALLER] BusyBox is static; no shared library staging required."
else
  echo "[SP-INSTALLER] BusyBox appears dynamic; attempting to source a static binary..."
  if command -v apt-get >/dev/null 2>&1; then
    echo "[SP-INSTALLER] Installing busybox-static via apt (if available)..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y busybox-static
    BUSYBOX_PATH="${SP_BUSYBOX_BIN:-$(command -v busybox-static || command -v busybox || true)}"
    echo "[SP-INSTALLER] BusyBox candidate after install: ${BUSYBOX_PATH:-none}"
  fi
fi

if [ -z "${BUSYBOX_PATH}" ]; then
  echo "[SP-BUILD] ERROR: busybox/busybox-static not found on build host; cannot build installer initramfs." >&2
  exit 1
fi

echo "[SP-INSTALLER] Final BusyBox selection: ${BUSYBOX_PATH}"
if command -v file >/dev/null 2>&1; then
  file "${BUSYBOX_PATH}" || true
fi
if command -v ldd >/dev/null 2>&1; then
  ldd "${BUSYBOX_PATH}" || true
fi

# Stage BusyBox for the initramfs; /bin/busybox must exist so the /init
# shebang (#!/bin/busybox sh) has a working interpreter.
install -m 0755 "${BUSYBOX_PATH}" "${INITRD_ROOT}/bin/busybox"
chmod 0755 "${INITRD_ROOT}/bin/busybox"

# If BusyBox is dynamically linked, pull in its shared libraries so PID 1 can
# exec /bin/sh without tripping "No working init found" at boot.
BUSYBOX_DYNAMIC=1
if _is_busybox_static "${INITRD_ROOT}/bin/busybox"; then
  BUSYBOX_DYNAMIC=0
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
  for applet in sh mount mkdir echo sleep umount cat mknod; do
    ln -sf busybox "${applet}"
  done
)

BUSYBOX_BIN="${INITRD_ROOT}/bin/busybox"

REQUIRED_APPLETS=(
  cat
  echo
  mdev
  mknod
  mount
  modprobe
  sh
  sleep
  umount
)

for applet in "${REQUIRED_APPLETS[@]}"; do
  if ! "${BUSYBOX_BIN}" --list | grep -Fxq "${applet}"; then
    echo "[SP-BUILD] ERROR: BusyBox is missing required applet: ${applet}" >&2
    exit 1
  fi
done

if [ ! -d "${RUNTIME_LIB_SRC}" ]; then
  echo "[SP-BUILD] ERROR: Missing runtime library directory: ${RUNTIME_LIB_SRC}" >&2
  exit 1
fi

echo "[SP-INSTALLER] Staging runtime helpers..."
RUNTIME_LIB_DST="${INITRD_ROOT}/runtime/lib"
cp -a "${RUNTIME_LIB_SRC}/." "${RUNTIME_LIB_DST}/"
REQUIRED_RUNTIME_LIBS=(
  rescue_mode.sh
  disk_layout.sh
  disk_execute.sh
  rootfs_deploy.sh
  bootloader.sh
  config_discovery.sh
)
for lib in "${REQUIRED_RUNTIME_LIBS[@]}"; do
  if [ ! -f "${RUNTIME_LIB_DST}/${lib}" ]; then
    echo "[SP-BUILD] ERROR: Runtime helper missing: ${lib}" >&2
    exit 1
  fi
done

echo "[SP-INSTALLER] Runtime helpers staged in ${RUNTIME_LIB_DST}"

echo "[SP-INSTALLER] Staging kernel modules from ${MODULES_SRC} to ${MODULES_DST}"

if [ ! -d "${MODULES_SRC}" ]; then
  echo "[SP-BUILD] ERROR: Kernel modules directory missing: ${MODULES_SRC}" >&2
  exit 1
fi

mkdir -p "${MODULES_DST}"
cp -a "${MODULES_SRC}/." "${MODULES_DST}/"

echo "[SP-INSTALLER] Creating init script..."
if [ ! -f "${INIT_SCRIPT_SRC}" ]; then
  echo "[SP-BUILD] ERROR: init script source missing: ${INIT_SCRIPT_SRC}" >&2
  exit 1
fi

# Place the installer /init at the root of the initramfs so the kernel
# runs our CI-visible entrypoint for smoke testing.
install -m 0755 "${INIT_SCRIPT_SRC}" "${INITRD_ROOT}/init"
chmod 0755 "${INITRD_ROOT}/init"

echo "[SP-INSTALLER] Creating initramfs..."
(
  cd "${INITRD_ROOT}"
  find . | cpio -o -H newc | gzip -9 > "${DIST_DIR}/initrd-installer.img"
)

INITRD_PATH="${DIST_DIR}/initrd-installer.img"
if ! INITRD_SIZE_BYTES=$(stat -c '%s' "${INITRD_PATH}" 2>/dev/null); then
  echo "[SP-BUILD] ERROR: Unable to stat ${INITRD_PATH}" >&2
  exit 1
fi

if [ "${INITRD_SIZE_BYTES}" -lt "${MIN_INITRD_SIZE_BYTES}" ]; then
  echo "[SP-BUILD] ERROR: initrd-installer.img is too small (${INITRD_SIZE_BYTES} < ${MIN_INITRD_SIZE_BYTES})" >&2
  echo "[SP-BUILD]       Ensure the staging tree includes /init, /runtime/lib, and the BusyBox shell." >&2
  exit 1
fi

echo "[SP-INSTALLER] initrd-installer.img size: ${INITRD_SIZE_BYTES} bytes (minimum ${MIN_INITRD_SIZE_BYTES})"

# ----------------------------
# Sanity check: /init must exist in initramfs
# ----------------------------
if ! gzip -cd "${INITRD_PATH}" | cpio -t 2>/dev/null | grep -Eq '^(init|./init)$'; then
    echo "[SP-BUILD] ERROR: initrd-installer.img is missing ./init"
    echo "[SP-BUILD]       Check INITRD_ROOT contents and init creation block."
    exit 1
fi

echo "[SP-INSTALLER] init and /bin/busybox permissions within initramfs:"
gzip -cd "${DIST_DIR}/initrd-installer.img" 2>/dev/null | cpio -tv 2>/dev/null | \
  grep -E '(^-.* init$|^-.* bin/busybox$)' || true

echo "[SP-INSTALLER] Installer initramfs built: ${DIST_DIR}/initrd-installer.img"
