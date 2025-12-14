#!/bin/sh
# Screaming Penguin safety checks (Phase 5).
# Validates target disk, rootfs presence, and basic environment.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/logging.sh"

sp_safety_prepare_devices() {
    if [ -z "${SP_CFG_TARGET_DISK:-}" ]; then
        log_error "SP_CFG_TARGET_DISK is not set; did config load succeed?"
        return 1
    fi

    case "$SP_CFG_TARGET_DISK" in
        /dev/*) SP_TARGET_DISK_DEV="$SP_CFG_TARGET_DISK" ;;
        *) SP_TARGET_DISK_DEV="/dev/$SP_CFG_TARGET_DISK" ;;
    esac

    case "$SP_TARGET_DISK_DEV" in
        *[0-9]) part_suffix="p" ;;
        *) part_suffix="" ;;
    esac

    SP_TARGET_PART_BOOT="${SP_TARGET_DISK_DEV}${part_suffix}1"
    SP_TARGET_PART_ROOT="${SP_TARGET_DISK_DEV}${part_suffix}2"

    export SP_TARGET_DISK_DEV SP_TARGET_PART_BOOT SP_TARGET_PART_ROOT

    log_info "Target disk resolved: $SP_TARGET_DISK_DEV"
    log_info "Planned partitions: boot=$SP_TARGET_PART_BOOT root=$SP_TARGET_PART_ROOT"
}

sp_safety_check_not_usb() {
    # Optional boot disk hint; if unset, we log a warning only.
    boot_disk="${SP_BOOT_DISK:-}"

    if [ -n "$boot_disk" ]; then
        if [ "$boot_disk" = "$SP_TARGET_DISK_DEV" ] || [ "/dev/$boot_disk" = "$SP_TARGET_DISK_DEV" ]; then
            log_error "Safety check failed: target disk matches boot device ($boot_disk)."
            return 1
        fi
    else
        log_warn "SP_BOOT_DISK not set; cannot strictly verify that target disk != USB boot device."
    fi

    return 0
}

sp_safety_check_rootfs() {
    if [ -z "${SP_CFG_ROOTFS_PATH:-}" ]; then
        log_error "SP_CFG_ROOTFS_PATH is not set."
        return 1
    fi

    if [ ! -f "$SP_CFG_ROOTFS_PATH" ]; then
        log_error "Rootfs tarball not found at '$SP_CFG_ROOTFS_PATH'."
        return 1
    fi

    log_info "Rootfs tarball present at '$SP_CFG_ROOTFS_PATH'."
    return 0
}

sp_safety_check_all() {
    sp_safety_prepare_devices || return 1
    sp_safety_check_not_usb || return 1
    sp_safety_check_rootfs || return 1
    return 0
}
