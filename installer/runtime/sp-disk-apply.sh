#!/bin/sh
# Screaming Penguin disk apply (Phase 5).
# Applies GPT partitioning and filesystem creation to the target disk.
#
# WARNING: This is destructive by design and must only be run after
# configuration and safety checks have passed.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_disk_apply() {
    if [ -z "${SP_TARGET_DISK_DEV:-}" ] || [ -z "${SP_TARGET_PART_BOOT:-}" ] || [ -z "${SP_TARGET_PART_ROOT:-}" ]; then
        log_error "Disk apply requested but device variables are not set."
        return 1
    fi

    if ! command -v sgdisk >/dev/null 2>&1; then
        log_error "sgdisk not found; cannot apply GPT layout."
        return 1
    fi

    if ! command -v mkfs.vfat >/dev/null 2>&1 || ! command -v mkfs.ext4 >/dev/null 2>&1; then
        log_error "mkfs.vfat or mkfs.ext4 not found; cannot create filesystems."
        return 1
    fi

    log_warn "Applying partitioning to target disk '$SP_TARGET_DISK_DEV' (destructive)."

    # Wipe existing partition table
    sgdisk --zap-all "$SP_TARGET_DISK_DEV"

    # Create EFI System partition (p1)
    sgdisk \
        -n 1:1MiB:+512MiB \
        -t 1:EF00 \
        -c 1:"EFI System" \
        "$SP_TARGET_DISK_DEV"

    # Create root partition (p2)
    sgdisk \
        -n 2:0:0 \
        -t 2:8300 \
        -c 2:"SP_ROOT" \
        "$SP_TARGET_DISK_DEV"

    # Inform kernel of partition changes
    if command -v partprobe >/dev/null 2>&1; then
        partprobe "$SP_TARGET_DISK_DEV" || log_warn "partprobe failed; continuing."
    fi

    # Filesystem creation
    log_info "Creating FAT32 filesystem on $SP_TARGET_PART_BOOT"
    mkfs.vfat -F32 "$SP_TARGET_PART_BOOT"

    log_info "Creating ext4 filesystem on $SP_TARGET_PART_ROOT"
    mkfs.ext4 -F "$SP_TARGET_PART_ROOT"

    log_info "Disk layout applied successfully to '$SP_TARGET_DISK_DEV'."
    return 0
}
