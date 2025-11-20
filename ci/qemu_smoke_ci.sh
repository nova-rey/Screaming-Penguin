#!/usr/bin/env bash
set -euo pipefail

echo "[QEMU-CI] Starting QEMU ISO smoke test…"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_PATH="${PROJECT_ROOT}/dist/screaming-penguin.iso"

if [ ! -f "${ISO_PATH}" ]; then
  echo "[QEMU-CI] ERROR: ISO not found at ${ISO_PATH}" >&2
  exit 1
fi

echo "[QEMU-CI] Using ISO at: ${ISO_PATH}"
ls -lh "${ISO_PATH}"

echo "[QEMU-CI] El Torito entries (xorriso):"
xorriso -indev "${ISO_PATH}" -report_el_torito plain || {
  echo "[QEMU-CI] ERROR: Failed to inspect El Torito boot entries." >&2
  exit 1
}

echo "[QEMU-CI] Dumping /boot/grub/grub.cfg from ISO (if available)..."
if command -v xorriso >/dev/null 2>&1; then
  if ! xorriso -indev "${ISO_PATH}" -osirrox on -extract /boot/grub/grub.cfg - 2>/dev/null; then
    echo "[QEMU-CI] WARNING: Could not read /boot/grub/grub.cfg from ISO."
  fi
else
  echo "[QEMU-CI] xorriso not available; skipping grub.cfg dump."
fi

echo "[QEMU-CI] Checking ISO for installer kernel/initrd..."
has_kernel=0

if xorriso -indev "${ISO_PATH}" -- -ls /boot/vmlinuz-installer >/dev/null 2>&1; then
  echo "[QEMU-CI] Found /boot/vmlinuz-installer inside ISO."
  has_kernel=1
elif xorriso -indev "${ISO_PATH}" -- -ls /boot/vmlinuz >/dev/null 2>&1; then
  echo "[QEMU-CI] Found /boot/vmlinuz inside ISO."
  has_kernel=1
fi

if [ "${has_kernel}" -ne 1 ]; then
  echo "[QEMU-CI] ERROR: No suitable installer kernel found (neither /boot/vmlinuz-installer nor /boot/vmlinuz)." >&2
  exit 1
fi

echo "[QEMU-CI] Verifying initramfs contents..."
INITRD_EXTRACT="${PROJECT_ROOT}/build/initrd-installer.img"
mkdir -p "$(dirname "${INITRD_EXTRACT}")"

if ! xorriso -indev "${ISO_PATH}" -osirrox on -extract /boot/initrd-installer.img "${INITRD_EXTRACT}" 2>/dev/null; then
  echo "[QEMU-CI] ERROR: Failed to extract /boot/initrd-installer.img from ISO." >&2
  exit 1
fi

if ! lsinitramfs "${INITRD_EXTRACT}" | grep -E '^init$'; then
  echo "[QEMU-CI] ERROR: init not found in installer initramfs." >&2
  exit 1
fi

if ! lsinitramfs "${INITRD_EXTRACT}" | grep -E '^bin/busybox$'; then
  echo "[QEMU-CI] ERROR: /bin/busybox not found in installer initramfs." >&2
  exit 1
fi

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
SERIAL_LOG="${PROJECT_ROOT}/build/qemu-serial.log"
INIT_MARKER="[SP-INSTALLER] init reached"

mkdir -p "$(dirname "${SERIAL_LOG}")"
rm -f "${SERIAL_LOG}"

echo "[QEMU-CI] Running QEMU against ISO (BIOS boot)…"
echo "[QEMU-CI] Using QEMU binary: ${QEMU_BIN}"
echo "[QEMU-CI] Serial log will be written to: ${SERIAL_LOG}"

set +e
timeout 40s \
  "${QEMU_BIN}" \
    -m 1024 \
    -cdrom "${ISO_PATH}" \
    -boot d \
    -no-reboot \
    -display none \
    -serial "file:${SERIAL_LOG}" \
    -net none
qemu_status=$?
set -e

case "${qemu_status}" in
  0)
    echo "[QEMU-CI] QEMU exited cleanly (status 0)."
    ;;
  124)
    echo "[QEMU-CI] timeout(40s) reached; QEMU still running – acceptable if serial output captured."
    ;;
  *)
    echo "[QEMU-CI] ERROR: QEMU exited with status ${qemu_status} – FAIL." >&2
    exit 1
    ;;
esac

# Require a non-empty serial log and our installer init marker so we know the
# ISO boot reached early init.
if [ ! -s "${SERIAL_LOG}" ]; then
  if [ -f "${SERIAL_LOG}" ]; then
    echo "[QEMU-CI] Serial log exists; size (bytes): $(wc -c < "${SERIAL_LOG}" || echo "unknown")"
  else
    echo "[QEMU-CI] Serial log file '${SERIAL_LOG}' does not exist."
  fi
  echo "[QEMU-CI] ERROR: Serial log missing or empty; treating this as a boot failure." >&2
  exit 1
fi

if ! grep -Fq "${INIT_MARKER}" "${SERIAL_LOG}"; then
  echo "[QEMU-CI] ERROR: Installer init marker not detected in serial log." >&2
  echo "[QEMU-CI] Expected marker: ${INIT_MARKER}" >&2
  echo "[QEMU-CI] Tail of serial log for debugging:" >&2
  tail -n 80 "${SERIAL_LOG}" >&2 || true
  exit 1
fi

echo "[QEMU-CI] Installer init marker detected; ISO boot reached early init – PASS."
echo "[QEMU-CI] Tail of serial log:"
tail -n 80 "${SERIAL_LOG}" || true

echo "[QEMU-CI] ISO smoke test completed successfully."
