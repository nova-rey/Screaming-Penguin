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

echo "[QEMU-CI] Running QEMU against ISO (BIOS boot)…"
echo "[QEMU-CI] Using QEMU binary: ${QEMU_BIN}"

set +e
timeout 45 \
  "${QEMU_BIN}" \
    -m 1024 \
    -cdrom "${ISO_PATH}" \
    -boot d \
    -nographic \
    -serial mon:stdio \
    -no-reboot \
    -net none
qemu_status=$?
set -e

case "${qemu_status}" in
  0)
    echo "[QEMU-CI] QEMU exited cleanly (status 0) – PASS."
    ;;
  124)
    echo "[QEMU-CI] timeout(45s) reached; QEMU still running – PASS for smoke test."
    ;;
  *)
    echo "[QEMU-CI] ERROR: QEMU exited with status ${qemu_status} – FAIL." >&2
    exit 1
    ;;
esac

echo "[QEMU-CI] ISO smoke test completed successfully."
