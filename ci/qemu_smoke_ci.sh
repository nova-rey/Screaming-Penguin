#!/bin/sh
# Screaming Penguin - QEMU Smoke Test for CI
# This script is intended to run in CI and must remain safe and self-contained.
#
# It:
#   - Assumes dist/screaming-penguin.img exists (built by `make iso`).
#   - Boots the image in QEMU (BIOS mode) with a timeout.
#   - Captures serial logs to build/qemu-ci.log.
#   - Greps for basic Phase 2 skeleton log markers.
#
# It must NOT touch any real block devices.

set -eu

IMG="dist/screaming-penguin.img"
BUILD_DIR="build"
LOG_FILE="$BUILD_DIR/qemu-ci.log"

mkdir -p "$BUILD_DIR"

if [ ! -f "$IMG" ]; then
    echo "[QEMU-CI] Image not found: $IMG"
    echo "[QEMU-CI] Run 'make iso' before invoking this smoke test."
    exit 1
fi

echo "[QEMU-CI] Starting QEMU smoke test (BIOS mode)…"
echo "[QEMU-CI] Image: $IMG"
echo "[QEMU-CI] Logs:  $LOG_FILE"

# Clean previous log
: > "$LOG_FILE"

# Run QEMU with a timeout to avoid hanging CI indefinitely.
# We allow QEMU to be killed by timeout; we care about log content, not clean shutdown.
set +e
timeout 60s qemu-system-x86_64 \
    -m 1024 \
    -drive file="$IMG",format=raw \
    -serial stdio \
    -display none \
    2>&1 | tee "$LOG_FILE"
QEMU_RC=$?
set -e

if [ $QEMU_RC -eq 124 ]; then
    echo "[QEMU-CI] QEMU timed out after 60s (this may be expected)."
elif [ $QEMU_RC -ne 0 ]; then
    echo "[QEMU-CI] QEMU exited with non-zero status: $QEMU_RC"
    echo "[QEMU-CI] Failing smoke test."
    exit 1
fi

echo "[QEMU-CI] Inspecting logs for Phase 2 skeleton markers…"

if grep -q "Screaming Penguin installer starting (Phase 2 skeleton)" "$LOG_FILE"; then
    echo "[QEMU-CI] Found Phase 2 installer start log."
else
    echo "[QEMU-CI] WARNING: Did not find Phase 2 installer start log."
    echo "[QEMU-CI] Log head:"
    head -n 40 "$LOG_FILE" || true
    echo "[QEMU-CI] Log tail:"
    tail -n 40 "$LOG_FILE" || true
    # For now, treat this as a failure to ensure we notice regressions.
    exit 1
fi

if grep -q "State: BOOT_INIT" "$LOG_FILE"; then
    echo "[QEMU-CI] Found BOOT_INIT state log."
else
    echo "[QEMU-CI] WARNING: Missing BOOT_INIT state log."
    exit 1
fi

if grep -q "State: FINISH" "$LOG_FILE"; then
    echo "[QEMU-CI] Found FINISH state log."
else
    echo "[QEMU-CI] WARNING: Missing FINISH state log."
    exit 1
fi

echo "[QEMU-CI] QEMU smoke test passed."
