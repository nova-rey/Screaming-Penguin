#!/bin/sh
# shellcheck shell=sh

set -eu

: "${SP_TARGET_MNT:=/mnt/target}"
: "${SP_BOOTLOADER_CONFIGURED:=0}"

sp_bootloader_config_value() {
    key="$1"
    default="$2"
    value=""

    if [ -n "${SP_CONFIG_PATH:-}" ] && command -v sp_disk_layout_yaml_value >/dev/null 2>&1; then
        if cfg=$(sp_disk_layout_yaml_value "$SP_CONFIG_PATH" "$key" 2>/dev/null); then
            value="$cfg"
        fi
    fi

    if [ -z "$value" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$value"
    fi
}

sp_bootloader_init_config() {
    if [ "${SP_BOOTLOADER_CONFIGURED:-0}" = "1" ]; then
        return 0
    fi

    SP_BOOTLOADER_GRUB_TARGET=$(sp_bootloader_config_value 'installer.bootloader.grub_efi_target' 'x86_64-efi')
    SP_BOOTLOADER_BOOTLOADER_ID=$(sp_bootloader_config_value 'installer.bootloader.grub_bootloader_id' 'ScreamingPenguin')
    SP_BOOTLOADER_TIMEOUT=$(sp_bootloader_config_value 'installer.bootloader.grub_timeout' '5')
    SP_BOOTLOADER_FSTAB_ROOT_OPTS=$(sp_bootloader_config_value 'installer.bootloader.fstab_root_options' 'defaults')
    SP_BOOTLOADER_FSTAB_ROOT_FREQ=$(sp_bootloader_config_value 'installer.bootloader.fstab_root_freq' '1')
    SP_BOOTLOADER_FSTAB_ROOT_PASS=$(sp_bootloader_config_value 'installer.bootloader.fstab_root_pass' '1')
    SP_BOOTLOADER_FSTAB_EFI_OPTS=$(sp_bootloader_config_value 'installer.bootloader.fstab_efi_options' 'umask=0077')
    SP_BOOTLOADER_FSTAB_EFI_FREQ=$(sp_bootloader_config_value 'installer.bootloader.fstab_efi_freq' '0')
    SP_BOOTLOADER_FSTAB_EFI_PASS=$(sp_bootloader_config_value 'installer.bootloader.fstab_efi_pass' '0')

    SP_BOOTLOADER_CONFIGURED=1
}

sp_bootloader_partition_path() {
    role="$1"
    part=""

    case "$role" in
        root)
            part="${SP_DISK_EXECUTE_ROOT_PART:-${SP_TARGET_PART_ROOT:-}}"
            ;;
        efi)
            part="${SP_DISK_EXECUTE_EFI_PART:-${SP_TARGET_PART_BOOT:-}}"
            ;;
        *)
            part=""
            ;;
    esac

    if [ -z "$part" ]; then
        return 1
    fi

    printf '%s' "$part"
}

sp_bootloader_partition_uuid() {
    part="$1"

    if [ -z "$part" ]; then
        return 1
    fi

    if ! command -v blkid >/dev/null 2>&1; then
        return 2
    fi

    uuid=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
    if [ -z "$uuid" ]; then
        return 3
    fi

    printf '%s' "$uuid"
}

sp_bootloader_is_mounted() {
    target="$1"

    if command -v mountpoint >/dev/null 2>&1; then
        if mountpoint -q "$target" 2>/dev/null; then
            return 0
        fi
        return 1
    fi

    if [ -r /proc/mounts ]; then
        if grep -q " $target " /proc/mounts 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

sp_bootloader_mount_virtual_filesystems() {
    for dir in dev sys proc run; do
        host="/$dir"
        target="$SP_TARGET_MNT/$dir"

        if [ ! -d "$host" ]; then
            continue
        fi

        mkdir -p "$target"

        if sp_bootloader_is_mounted "$target"; then
            continue
        fi

        if ! mount --bind "$host" "$target" >/dev/null 2>&1; then
            sp_log "state=bootloader" "result=failed" "reason=mount-$dir-failed"
            return 1
        fi
    done

    return 0
}

sp_bootloader_umount_virtual_filesystems() {
    for dir in run sys proc dev; do
        target="$SP_TARGET_MNT/$dir"
        if sp_bootloader_is_mounted "$target"; then
            umount "$target" >/dev/null 2>&1 || true
        fi
    done
}

sp_bootloader_find_artifact() {
    for candidate in "$@"; do
        case "$candidate" in
            *'*'*)
                continue
                ;;
        esac

        if [ -f "$candidate" ]; then
            rel=${candidate#"$SP_TARGET_MNT"}
            if [ -z "$rel" ]; then
                rel="/"
            fi
            printf '%s' "$rel"
            return 0
        fi
    done
    return 1
}

sp_bootloader_detect_kernel() {
    if kernel_path=$(sp_bootloader_find_artifact "$SP_TARGET_MNT/boot/vmlinuz" "$SP_TARGET_MNT/boot/vmlinuz-"*); then
        printf '%s' "$kernel_path"
        return 0
    fi
    return 1
}

sp_bootloader_detect_initrd() {
    if initrd_path=$(sp_bootloader_find_artifact "$SP_TARGET_MNT/boot/initrd.img" "$SP_TARGET_MNT/boot/initrd.img-"* "$SP_TARGET_MNT/boot/initramfs-"*); then
        printf '%s' "$initrd_path"
        return 0
    fi
    return 1
}

sp_bootloader_generate_fstab() {
    sp_bootloader_init_config
    root_part="$(sp_bootloader_partition_path root)" || {
        sp_log "state=bootloader" "result=failed" "reason=root-partition-missing"
        return 1
    }
    efi_part="$(sp_bootloader_partition_path efi)" || {
        sp_log "state=bootloader" "result=failed" "reason=efi-partition-missing"
        return 1
    }

    root_uuid="$(sp_bootloader_partition_uuid "$root_part")" || {
        sp_log "state=bootloader" "result=failed" "reason=root-uuid-missing"
        return 1
    }
    efi_uuid="$(sp_bootloader_partition_uuid "$efi_part")" || {
        sp_log "state=bootloader" "result=failed" "reason=efi-uuid-missing"
        return 1
    }

    mkdir -p "$SP_TARGET_MNT/etc"

    cat <<FSTAB >"$SP_TARGET_MNT/etc/fstab"
UUID=$root_uuid / ext4 $SP_BOOTLOADER_FSTAB_ROOT_OPTS $SP_BOOTLOADER_FSTAB_ROOT_FREQ $SP_BOOTLOADER_FSTAB_ROOT_PASS
UUID=$efi_uuid /boot/efi vfat $SP_BOOTLOADER_FSTAB_EFI_OPTS $SP_BOOTLOADER_FSTAB_EFI_FREQ $SP_BOOTLOADER_FSTAB_EFI_PASS
FSTAB

    sp_log "state=bootloader" "phase=fstab" "result=ok" "root_uuid=$root_uuid" "efi_uuid=$efi_uuid"
    return 0
}

sp_bootloader_generate_grub_cfg() {
    sp_bootloader_init_config
    root_part="$(sp_bootloader_partition_path root)" || return 1
    root_uuid="$(sp_bootloader_partition_uuid "$root_part")" || return 1

    kernel_entry="/boot/vmlinuz"
    if kernel_path=$(sp_bootloader_detect_kernel); then
        kernel_entry="$kernel_path"
    else
        sp_log "state=bootloader" "warning=kernel-missing" "note=fallback-to-/boot/vmlinuz"
    fi

    initrd_entry=""
    if initrd_path=$(sp_bootloader_detect_initrd); then
        initrd_entry="$initrd_path"
    fi

    initrd_line=""
    if [ -n "$initrd_entry" ]; then
        initrd_line="    initrd $initrd_entry"
    fi

    mkdir -p "$SP_TARGET_MNT/boot/grub"
    cat <<GRUBCFG >"$SP_TARGET_MNT/boot/grub/grub.cfg"
set timeout=$SP_BOOTLOADER_TIMEOUT
set default=0

menuentry 'Screaming Penguin' {
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid $root_uuid --set=root
    linux $kernel_entry root=UUID=$root_uuid ro quiet
$initrd_line
}
GRUBCFG

    sp_log "state=bootloader" "phase=grub-cfg" "result=ok" "kernel=$kernel_entry"
    return 0
}

sp_bootloader_debug_log() {
    if [ "${SP_DEBUG_BOOTLOADER:-0}" != "1" ]; then
        return 0
    fi
    sp_log "state=bootloader" "debug=$1"
}

sp_bootloader_chroot_exec() {
    command_line="$1"
    sp_bootloader_debug_log "chroot-cmd=$command_line"
    chroot "$SP_TARGET_MNT" /bin/sh -eu -c "$command_line"
}

sp_bootloader_install_grub() {
    sp_bootloader_init_config

    if ! sp_bootloader_mount_virtual_filesystems; then
        return 1
    fi

    cmd="grub-install --target=$SP_BOOTLOADER_GRUB_TARGET --efi-directory=/boot/efi --bootloader-id=$SP_BOOTLOADER_BOOTLOADER_ID --recheck"
    if ! sp_bootloader_chroot_exec "$cmd"; then
        sp_bootloader_umount_virtual_filesystems
        sp_log "state=bootloader" "result=failed" "reason=grub-install-failed"
        return 1
    fi

    sp_bootloader_umount_virtual_filesystems
    sp_log "state=bootloader" "phase=grub-install" "result=ok"
    return 0
}

sp_bootloader_skip_reason() {
    if [ "${SP_SKIP_BOOTLOADER:-0}" = "1" ]; then
        printf 'skip-flag'
        return 0
    fi

    if [ "${SP_ENABLE_BOOTLOADER:-0}" != "1" ]; then
        printf 'toggle-disabled'
        return 0
    fi

    if [ "${SP_ENABLE_DISK_EXECUTE:-0}" != "1" ]; then
        printf 'disk-exec-disabled'
        return 0
    fi

    if [ "${SP_BOOTLOADER_READY:-0}" != "1" ]; then
        printf 'bootloader-not-ready'
        return 0
    fi

    return 1
}

sp_install_bootloader_and_finalize() {
    if ! sp_enforce_write_gate; then
        sp_log "state=bootloader" "result=failed" "reason=write-gate-unavailable"
        return 1
    fi

    if reason=$(sp_bootloader_skip_reason); then
        sp_log "state=bootloader" "result=skipped" "reason=$reason"
        return 0
    fi

    if ! sp_bootloader_is_mounted "$SP_TARGET_MNT"; then
        sp_log "state=bootloader" "result=failed" "reason=rootfs-not-mounted"
        return 1
    fi

    sp_bootloader_init_config
    sp_log "state=bootloader" "marker=START"

    if ! sp_bootloader_generate_fstab; then
        sp_log "state=bootloader" "result=failed" "reason=fstab"
        sp_log "state=bootloader" "marker=END"
        return 1
    fi

    if ! sp_bootloader_generate_grub_cfg; then
        sp_log "state=bootloader" "result=failed" "reason=grub-cfg"
        sp_log "state=bootloader" "marker=END"
        return 1
    fi

    if ! sp_bootloader_install_grub; then
        sp_log "state=bootloader" "marker=END"
        return 1
    fi

    sp_log "state=bootloader" "marker=END" "result=ok"
    return 0
}
