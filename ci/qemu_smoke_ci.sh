#!/usr/bin/env bash
set -euo pipefail

ISO_PATH="${ISO_PATH:-dist/screaming-penguin.iso}"
ISO_KERNEL_REL="boot/vmlinuz-installer"
ISO_INITRD_REL="boot/initrd-installer.img"
INSTALLER_KERNEL="dist/vmlinuz-installer"
INSTALLER_INITRD="dist/initrd-installer.img"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
QEMU_TIMEOUT_SEC="${QEMU_TIMEOUT_SEC:-90}"
# Marker string printed by the installer to the console/serial log
INSTALL_MARKER='[SP-INSTALLER] init starting'
QEMU_SERIAL_LOG="qemu_serial.log"
QEMU_STDERR_LOG="qemu_stderr.log"

echo "[QEMU-CI] Using ISO at: ${ISO_PATH}"
ls -lh "${ISO_PATH}"

if command -v xorriso >/dev/null 2>&1; then
    echo "[QEMU-CI] El Torito entries (xorriso):"
    xorriso -indev "$ISO_PATH" -report_el_torito plain || true

    echo "[QEMU-CI] Checking ISO for installer kernel/initrd..."
    for iso_member in "$ISO_KERNEL_REL" "$ISO_INITRD_REL"; do
        if ! xorriso -indev "$ISO_PATH" -find "/${iso_member}" -print 2>/dev/null | grep -Fq "$iso_member"; then
            echo "[QEMU-CI] ERROR: Missing ${iso_member} inside ISO."
            exit 1
        fi
    done
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
timeout "${QEMU_TIMEOUT_SEC}s" "$QEMU_BIN" \
  -m 1024 \
  -kernel "${INSTALLER_KERNEL}" \
  -initrd "${INSTALLER_INITRD}" \
  -append "console=ttyS0 init=/init" \
  -nographic \
  -serial stdio \
  -no-reboot \
  -no-shutdown \
  -enable-kvm 2>"${QEMU_STDERR_LOG}" | tee "${QEMU_SERIAL_LOG}" || true

echo "[QEMU-CI] QEMU exited (possibly due to timeout or shutdown)."
echo "[QEMU-CI] Checking for installer marker: ${INSTALL_MARKER}"

if grep -q "${INSTALL_MARKER}" "${QEMU_SERIAL_LOG}"; then
    echo "[QEMU-CI] Installer marker found; smoke test passed."
    exit 0
else
    echo "[QEMU-CI] ERROR: Installer did not launch (marker not found)."
    echo "[QEMU-CI] Last 100 lines of QEMU log:"
    tail -n 100 "${QEMU_SERIAL_LOG}" || true
    exit 1
fi
