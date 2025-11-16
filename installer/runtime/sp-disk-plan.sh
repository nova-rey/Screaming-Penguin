#!/bin/sh
# Screaming Penguin disk planning (Phase 5).
# Describes the GPT layout; actual disk changes happen in sp-disk-apply.sh.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_disk_plan() {
    if [ -z "${SP_TARGET_DISK_DEV:-}" ] || [ -z "${SP_TARGET_PART_BOOT:-}" ] || [ -z "${SP_TARGET_PART_ROOT:-}" ]; then
        log_error "Disk plan requested but device variables are not set."
        return 1
    fi

    log_info "Planning GPT layout for '$SP_TARGET_DISK_DEV':"
    log_info "  - Partition 1 (EFI System, FAT32): $SP_TARGET_PART_BOOT"
    log_info "  - Partition 2 (Linux root, ext4): $SP_TARGET_PART_ROOT"
    return 0
}
