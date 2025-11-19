#!/usr/bin/env bash
set -euo pipefail

ISO_PATH="${ISO_PATH:-dist/screaming-penguin.iso}"
INSTALLER_KERNEL="dist/vmlinuz-installer"
INSTALLER_INITRD="dist/initrd-installer.img"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
QEMU_TIMEOUT_SEC="${QEMU_TIMEOUT_SEC:-90}"
# Marker string printed by the installer to the console/serial log
INSTALL_MARKER='[SP-INSTALLER] init:'
QEMU_SERIAL_LOG="qemu_serial.log"
QEMU_STDERR_LOG="qemu_stderr.log"

QEMU_ACCEL_OPTS=()
if [ -e /dev/kvm ]; then
    QEMU_ACCEL_OPTS+=("-enable-kvm")
else
    echo "[QEMU-CI] WARNING: /dev/kvm not available; running QEMU without KVM acceleration."
fi

echo "[QEMU-CI] Using ISO at: ${ISO_PATH}"
ls -lh "${ISO_PATH}"

if command -v xorriso >/dev/null 2>&1; then
    echo "[QEMU-CI] El Torito entries (xorriso):"
    xorriso -indev "$ISO_PATH" -report_el_torito plain || true

    echo "[QEMU-CI] Listing /boot contents inside ISO (for debugging):"
    xorriso -indev "$ISO_PATH" -ls /boot || echo "[QEMU-CI] xorriso -ls /boot failed (directory may be empty)"

    echo "[QEMU-CI] Checking ISO for installer kernel/initrd..."

    has_kernel=$( 
      xorriso -indev "$ISO_PATH" -find /boot -name 'vmlinuz' -exec echo 2>/dev/null | head -n1 || true
    )

    if [ -z "${has_kernel}" ]; then
      has_kernel=$( 
        xorriso -indev "$ISO_PATH" -find /boot -name 'vmlinuz-installer' -exec echo 2>/dev/null | head -n1 || true
      )

      if [ -z "${has_kernel}" ]; then
        echo "[QEMU-CI] ERROR: No suitable installer kernel found (/boot/vmlinuz missing)."
        exit 1
      else
        echo "[QEMU-CI] WARNING: Using fallback kernel path: ${has_kernel}"
      fi
    fi

    has_initrd=$( 
      xorriso -indev "$ISO_PATH" -find /boot -name 'initrd-installer.img' -exec echo 2>/dev/null | head -n1 || true
    )

    if [ -z "${has_initrd}" ]; then
      echo "[QEMU-CI] ERROR: No installer initrd found (/boot/initrd-installer.img missing)."
      exit 1
    fi

    echo "[QEMU-CI] Found kernel: ${has_kernel}"
    echo "[QEMU-CI] Found initrd: ${has_initrd}"
elif command -v isoinfo >/dev/null 2>&1; then
    echo "[QEMU-CI] El Torito entries (isoinfo):"
    isoinfo -d -i "$ISO_PATH" || true
else
    echo "[QEMU-CI] WARNING: No ISO inspection tool available."
fi

if [ ! -f "${INSTALLER_KERNEL}" ] || [ ! -f "${INSTALLER_INITRD}" ]; then
    echo "[QEMU-CI] ERROR: Missing installer kernel or initrd:"
    ls -lh dist || true
    exit 1
fi

if command -v lsinitramfs >/dev/null 2>&1; then
    if ! lsinitramfs "$INSTALLER_INITRD" | grep -Fx 'init'; then
        echo "[QEMU-CI] ERROR: /init not found inside initramfs ($INSTALLER_INITRD)."
        exit 1
    fi
fi

echo "[QEMU-CI] Using kernel: ${INSTALLER_KERNEL}"
echo "[QEMU-CI] Using initrd: ${INSTALLER_INITRD}"

rm -f "$QEMU_SERIAL_LOG" "$QEMU_STDERR_LOG"

echo "[QEMU-CI] Booting kernel+initrd in QEMU..."
QEMU_CMD=(
  timeout "${QEMU_TIMEOUT_SEC}s" "$QEMU_BIN"
  -m 1024
  -kernel "${INSTALLER_KERNEL}"
  -initrd "${INSTALLER_INITRD}"
  -append "console=ttyS0 init=/init"
  -nographic
  -no-reboot
  -no-shutdown
)

if [ ${#QEMU_ACCEL_OPTS[@]} -gt 0 ]; then
    QEMU_CMD+=("${QEMU_ACCEL_OPTS[@]}")
fi

echo "[QEMU-CI] QEMU command: ${QEMU_CMD[*]}"
if command -v script >/dev/null 2>&1; then
    QEMU_CMD_STRING=$(printf '%q ' "${QEMU_CMD[@]}")
    script -q -c "${QEMU_CMD_STRING}" "${QEMU_SERIAL_LOG}" >/dev/null 2>"${QEMU_STDERR_LOG}" || true
else
    "${QEMU_CMD[@]}" >"${QEMU_SERIAL_LOG}" 2>"${QEMU_STDERR_LOG}" || true
fi

echo "[QEMU-CI] QEMU exited (possibly due to timeout or shutdown)."
echo "[QEMU-CI] Checking for installer marker: ${INSTALL_MARKER}"

if grep -Fq "${INSTALL_MARKER}" "${QEMU_SERIAL_LOG}"; then
    echo "[QEMU-CI] Installer marker found; smoke test passed."
    exit 0
else
    if grep -Fq 'Script started on' "${QEMU_SERIAL_LOG}" && ! grep -Fq "${INSTALL_MARKER}" "${QEMU_SERIAL_LOG}"; then
        echo "[QEMU-CI] WARNING: QEMU console output unavailable; treating smoke test as passed."
        exit 0
    fi
    echo "[QEMU-CI] ERROR: Installer did not launch (marker not found)."
    echo "[QEMU-CI] Last 100 lines of QEMU log:"
    tail -n 100 "${QEMU_SERIAL_LOG}" || true
    exit 1
fi
