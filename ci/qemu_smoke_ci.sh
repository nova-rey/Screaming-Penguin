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
INIT_MARKER='[SP-INSTALLER] init reached'

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
    echo "[QEMU-CI] timeout(40s) reached; QEMU still running – acceptable if init marker present."
    ;;
  *)
    echo "[QEMU-CI] ERROR: QEMU exited with status ${qemu_status} – FAIL." >&2
    exit 1
    ;;
esac

if [ ! -f "${SERIAL_LOG}" ]; then
  echo "[QEMU-CI] ERROR: Serial log ${SERIAL_LOG} not found after QEMU run." >&2
  exit 1
fi

if ! grep -q "${INIT_MARKER}" "${SERIAL_LOG}"; then
  echo "[QEMU-CI] ERROR: Installer init marker not found in serial log." >&2
  echo "[QEMU-CI] Searched for: ${INIT_MARKER}" >&2
  echo "[QEMU-CI] Dumping last lines of serial log for debugging:" >&2
  tail -n 50 "${SERIAL_LOG}" || true
  exit 1
fi

echo "[QEMU-CI] Found installer init marker (${INIT_MARKER})."
echo "[QEMU-CI] ISO smoke test completed successfully."
