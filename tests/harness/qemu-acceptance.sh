#!/bin/sh
# Screaming Penguin - QEMU acceptance harness (Phase 6)
#
# This script exercises the Screaming Penguin installer end-to-end in QEMU:
#   1) Prepares a virtual target disk image.
#   2) Populates the /config partition inside the installer image with a
#      QEMU-specific installer-config and rootfs tarball.
#   3) Boots the installer image in QEMU and captures installation logs.
#   4) Boots the installed system from the target disk and captures logs.
#   5) Performs simple log checks to validate success.
#
# All operations are confined to:
#   - dist/ (installer image, rootfs tarball)
#   - build/ (target disk image, logs, temp mount)
#
# The script does NOT touch real host block devices, but it does use loop
# devices and may require sudo to mount the /config partition.

set -eu

IMAGE="dist/screaming-penguin.img"
ROOTFS_TARBALL="dist/debian-rootfs-bookworm-amd64.tar.gz"
TARGET_IMG="build/qemu-target.img"
INSTALL_LOG="build/qemu-install.log"
BOOT_LOG="build/qemu-installed-boot.log"
CONFIG_SRC="config/installer-config.qemu-basic.yml"
CONFIG_MNT="build/qemu-config-mnt"

TARGET_IMG_SIZE="20G"

# QEMU binary
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

ensure_tools() {
    if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
        echo "[QEMU-HARNESS] ERROR: $QEMU_BIN not found. Install QEMU or set QEMU_BIN." >&2
        exit 1
    fi
    if ! command -v qemu-img >/dev/null 2>&1; then
        echo "[QEMU-HARNESS] ERROR: qemu-img not found. Install QEMU utilities." >&2
        exit 1
    fi
    if ! command -v losetup >/dev/null 2>&1; then
        echo "[QEMU-HARNESS] ERROR: losetup not found; cannot attach installer image loop device." >&2
        exit 1
    fi
    if ! command -v mount >/dev/null 2>&1; then
        echo "[QEMU-HARNESS] ERROR: mount not available." >&2
        exit 1
    fi
    if ! command -v umount >/dev/null 2>&1; then
        echo "[QEMU-HARNESS] ERROR: umount not available." >&2
        exit 1
    fi
}

ensure_artifacts() {
    mkdir -p build

    if [ ! -f "$IMAGE" ]; then
        echo "[QEMU-HARNESS] ERROR: Installer image not found at $IMAGE"
        echo "[QEMU-HARNESS]        Run 'make img' first."
        exit 1
    fi

    if [ ! -f "$ROOTFS_TARBALL" ]; then
        echo "[QEMU-HARNESS] ERROR: Rootfs tarball not found at $ROOTFS_TARBALL"
        echo "[QEMU-HARNESS]        Run 'make rootfs' first."
        exit 1
    fi

    if [ ! -f "$CONFIG_SRC" ]; then
        echo "[QEMU-HARNESS] ERROR: QEMU installer config not found at $CONFIG_SRC"
        exit 1
    fi

    if [ ! -f "$TARGET_IMG" ]; then
        echo "[QEMU-HARNESS] Creating target disk image: $TARGET_IMG ($TARGET_IMG_SIZE)"
        qemu-img create -f qcow2 "$TARGET_IMG" "$TARGET_IMG_SIZE"
    else
        echo "[QEMU-HARNESS] Reusing existing target disk image: $TARGET_IMG"
    fi
}

populate_config_partition() {
    echo "[QEMU-HARNESS] Populating /config partition inside installer image…"

    mkdir -p "$CONFIG_MNT"

    # Attach the installer image as a loop device with partition scanning.
    loopdev="$(sudo losetup --find --show --partscan "$IMAGE")"
    echo "[QEMU-HARNESS] Attached loop device: $loopdev"

    config_part="${loopdev}p2"

    # Ensure the config partition exists
    if [ ! -b "$config_part" ]; then
        echo "[QEMU-HARNESS] ERROR: Expected config partition not found at $config_part" >&2
        sudo losetup -d "$loopdev" || true
        exit 1
    fi

    # Mount, clean, and populate.
    sudo mount "$config_part" "$CONFIG_MNT"
    echo "[QEMU-HARNESS] Mounted config partition at $CONFIG_MNT"

    sudo rm -rf "${CONFIG_MNT:?}/"*
    sudo mkdir -p "$CONFIG_MNT/rootfs" "$CONFIG_MNT/logs"

    sudo cp "$ROOTFS_TARBALL" "$CONFIG_MNT/rootfs/debian-rootfs.tar.gz"
    sudo cp "$CONFIG_SRC" "$CONFIG_MNT/installer-config.yml"

    sync || true

    sudo umount "$CONFIG_MNT"
    sudo losetup -d "$loopdev"

    echo "[QEMU-HARNESS] Config partition updated with rootfs and installer-config.yml."
}

run_install_phase() {
    echo "[QEMU-HARNESS] Starting QEMU install phase…"
    echo "[QEMU-HARNESS] Install log: $INSTALL_LOG"

    # Use virtio drives; inside the guest these typically show up as /dev/vda, /dev/vdb, etc.
    # The QEMU config uses the installer image as the boot device and the qcow2 as target.
    timeout 900 "$QEMU_BIN" \
        -m 2048 \
        -nographic \
        -serial mon:stdio \
        -drive file="$IMAGE",if=virtio,format=raw \
        -drive file="$TARGET_IMG",if=virtio,format=qcow2 \
        -boot order=c \
        >"$INSTALL_LOG" 2>&1 || true

    echo "[QEMU-HARNESS] Install phase finished (see log for details)."
}

run_boot_phase() {
    echo "[QEMU-HARNESS] Starting QEMU post-install boot phase…"
    echo "[QEMU-HARNESS] Boot log: $BOOT_LOG"

    timeout 300 "$QEMU_BIN" \
        -m 2048 \
        -nographic \
        -serial mon:stdio \
        -drive file="$TARGET_IMG",if=virtio,format=qcow2 \
        -boot order=c \
        >"$BOOT_LOG" 2>&1 || true

    echo "[QEMU-HARNESS] Boot phase finished (see log for details)."
}

check_logs() {
    echo "[QEMU-HARNESS] Checking logs for success markers…"

    # Basic sanity: did we reach FINISH and report success?
    if ! grep -q "State: FINISH" "$INSTALL_LOG"; then
        echo "[QEMU-HARNESS] ERROR: INSTALL_LOG missing 'State: FINISH' marker." >&2
        exit 1
    fi

    if ! grep -q "Installation completed successfully." "$INSTALL_LOG"; then
        echo "[QEMU-HARNESS] ERROR: INSTALL_LOG missing successful completion message." >&2
        exit 1
    fi

    # Check for hostname in boot log; must match the QEMU example config.
    HOSTNAME="sp-qemu-basic"

    if ! grep -q "$HOSTNAME" "$BOOT_LOG"; then
        echo "[QEMU-HARNESS] ERROR: BOOT_LOG does not contain expected hostname '$HOSTNAME'." >&2
        exit 1
    fi

    echo "[QEMU-HARNESS] Log checks passed. QEMU acceptance scenario succeeded."
}

main() {
    ensure_tools
    ensure_artifacts
    populate_config_partition
    run_install_phase
    run_boot_phase
    check_logs
}

main "$@"
