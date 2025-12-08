#!/bin/sh
# Screaming Penguin rootfs apply (Phase 5).
# Mounts target partitions and extracts the rootfs tarball.

set -eu

: "${SP_ROOTFS_SCRIPT_DIR:=$(cd "$(dirname "$0")" && pwd)}"

if [ -n "${SP_RUNTIME_LIB_DIR:-}" ]; then
    LOGGING_LIB="$SP_RUNTIME_LIB_DIR/logging.sh"
else
    LOGGING_LIB="$SP_ROOTFS_SCRIPT_DIR/lib/logging.sh"
fi
# shellcheck disable=SC1091
. "$LOGGING_LIB"

sp_rootfs_apply() {
    : "${SP_TARGET_MNT:=/mnt/target}"

    if [ -z "${SP_TARGET_PART_BOOT:-}" ] || [ -z "${SP_TARGET_PART_ROOT:-}" ]; then
        log_error "Rootfs apply requested but partition variables are not set."
        return 1
    fi

    if [ -z "${SP_CFG_ROOTFS_PATH:-}" ] || [ ! -f "$SP_CFG_ROOTFS_PATH" ]; then
        log_error "Rootfs tarball missing at '$SP_CFG_ROOTFS_PATH'."
        return 1
    fi

    if ! command -v tar >/dev/null 2>&1; then
        log_error "tar not found; cannot extract rootfs."
        return 1
    fi

    log_info "Preparing mount points under '$SP_TARGET_MNT'…"
    mkdir -p "$SP_TARGET_MNT"
    mkdir -p "$SP_TARGET_MNT/boot/efi"

    log_info "Mounting root partition: $SP_TARGET_PART_ROOT"
    mount "$SP_TARGET_PART_ROOT" "$SP_TARGET_MNT"

    log_info "Mounting EFI partition: $SP_TARGET_PART_BOOT"
    mount "$SP_TARGET_PART_BOOT" "$SP_TARGET_MNT/boot/efi"

    log_info "Extracting rootfs from '$SP_CFG_ROOTFS_PATH' into '$SP_TARGET_MNT'…"
    tar -C "$SP_TARGET_MNT" -xzf "$SP_CFG_ROOTFS_PATH"

    log_info "Rootfs extraction complete."
    return 0
}
