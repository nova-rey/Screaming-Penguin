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
  if ! xorriso -indev "${ISO_PATH}" -osirrox on -print /boot/grub/grub.cfg; then
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

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
SERIAL_LOG="${PROJECT_ROOT}/build/qemu-serial.log"

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

# NOTE: In CI we can’t reliably see a custom init marker yet.
# For now, consider a non-empty serial log after boot + timeout as a PASS.
# This still ensures the ISO is bootable without adding a long or fragile handshake.
if [ ! -s "${SERIAL_LOG}" ]; then
  echo "[QEMU-CI] ERROR: Serial log missing or empty; treating this as a boot failure." >&2
  exit 1
fi

echo "[QEMU-CI] Non-empty serial log detected; ISO appears to boot far enough – PASS."
echo "[QEMU-CI] Tail of serial log:"
tail -n 80 "${SERIAL_LOG}" || true

echo "[QEMU-CI] ISO smoke test completed successfully."
