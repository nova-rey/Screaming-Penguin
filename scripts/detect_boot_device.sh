#!/bin/sh
#
# detect_boot_device.sh
#
# Best-effort detection of the USB device we originally booted from.
# This MUST NOT guess internal disks. If detection fails or is ambiguous,
# the script exits non-zero and prints an error message.
#

set -eu

LABEL="${OUROBOROS_BOOT_LABEL:-SP_OUROBOROS}"

err() {
    echo "[ouroboros][detect_boot_device] ERROR: $*" >&2
    exit 1
}

detect_by_label() {
    if [ -e "/dev/disk/by-label/${LABEL}" ]; then
        # Resolve symlink to underlying block device
        realpath "/dev/disk/by-label/${LABEL}"
        return 0
    fi
    return 1
}

detect_by_live_mount() {
    # Common live-media mountpoints (Debian-style and variants)
    for mp in /run/live/medium /run/initramfs/live /live/image; do
        if mountpoint -q "$mp"; then
            dev_name=$(lsblk -o NAME,MOUNTPOINT -nr | awk -v mp="$mp" '$2==mp {print $1}')
            if [ -n "$dev_name" ]; then
                echo "/dev/${dev_name}"
                return 0
            fi
        fi
    done
    return 1
}

main() {
    if dev_path=$(detect_by_label 2>/dev/null); then
        echo "$dev_path"
        exit 0
    fi

    if dev_path=$(detect_by_live_mount 2>/dev/null); then
        echo "$dev_path"
        exit 0
    fi

    err "Could not determine boot USB device. Check OUROBOROS_BOOT_LABEL or live-media mountpoints."
}

main "$@"
