#!/bin/sh
# Screaming Penguin - QEMU Smoke Test for CI
# This script is intended to run in CI and must remain safe and self-contained.
#
# Current behavior (pre-bootloader wiring):
#   - Verifies that dist/screaming-penguin.img or dist/screaming-penguin.iso exists.
#   - Boots the image in QEMU (BIOS mode) with a timeout.
#   - Captures serial logs to build/qemu-ci.log.
#   - Treats successful QEMU execution (even if only partial) as a pass.
#
# Once a real kernel/initramfs/bootloader stack is wired, this script can be
# tightened to assert on specific Phase 2 log markers.

set -eu

IMG_PATH="dist/screaming-penguin.img"
ISO_PATH="dist/screaming-penguin.iso"
IMAGE=""
QEMU_OPTS=""
BUILD_DIR="build"
LOG_FILE="$BUILD_DIR/qemu-ci.log"

mkdir -p "$BUILD_DIR"

if [ -f "$IMG_PATH" ]; then
    IMAGE="$IMG_PATH"
    echo "[QEMU-CI] Found raw image: $IMAGE"
    QEMU_OPTS="-drive file=$IMAGE,format=raw"
elif [ -f "$ISO_PATH" ]; then
    IMAGE="$ISO_PATH"
    echo "[QEMU-CI] Found ISO image: $IMAGE"
    QEMU_OPTS="-cdrom $IMAGE"
else
    echo "[QEMU-CI] No bootable image found."
    echo "[QEMU-CI] Expected one of:"
    echo "  - $IMG_PATH"
    echo "  - $ISO_PATH"
    echo "[QEMU-CI] Run 'make img' or 'make iso' before invoking this smoke test."
    exit 1
fi

echo "[QEMU-CI] Starting QEMU smoke test (BIOS mode)…"
echo "[QEMU-CI] Image: $IMAGE"
echo "[QEMU-CI] Logs:  $LOG_FILE"

# Clean previous log
: > "$LOG_FILE"

# Run QEMU with a timeout to avoid hanging CI indefinitely.
# We allow QEMU to be killed by timeout; for now we only care that it runs at all.
set +e
# shellcheck disable=SC2086  # QEMU_OPTS intentionally word-split into multiple args
timeout 60s qemu-system-x86_64 \
    -m 1024 \
    $QEMU_OPTS \
    -serial stdio \
    -display none \
    2>&1 | tee "$LOG_FILE"
QEMU_RC=$?
set -e

if [ $QEMU_RC -eq 124 ]; then
    echo "[QEMU-CI] QEMU timed out after 60s (expected in current placeholder boot setup)."
elif [ $QEMU_RC -ne 0 ]; then
    echo "[QEMU-CI] QEMU exited with non-zero status: $QEMU_RC"
    echo "[QEMU-CI] Failing smoke test."
    exit 1
fi

# Basic sanity: ensure we captured some output.
if [ ! -s "$LOG_FILE" ]; then
    echo "[QEMU-CI] WARNING: QEMU log file is empty."
    echo "[QEMU-CI] Failing smoke test to avoid hiding silent failures."
    exit 1
fi

echo "[QEMU-CI] QEMU produced output. Placeholder smoke test passed."
echo "[QEMU-CI] NOTE: Strict Phase 2 log checks will be enabled once a real bootable stack is wired."

exit 0
