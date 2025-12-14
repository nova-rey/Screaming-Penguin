#!/bin/sh
# shellcheck shell=sh

# Bootloader support shared by the installer runtime.
# Handles EFI mount, fstab write-up, GRUB install inside the chroot,
# and the final bootloader stage gate markers.

SP_BOOTLOADER_DEFAULT_EFI_MOUNTPOINT="/boot/efi"
SP_BOOTLOADER_DEFAULT_GRUB_TARGET="x86_64-efi"
SP_BOOTLOADER_DEFAULT_BOOTLOADER_ID="screaming-penguin"
SP_BOOTLOADER_DEFAULT_GRUB_CFG_PATH="/boot/grub/grub.cfg"
SP_BOOTLOADER_DEFAULT_GRUB_TIMEOUT="5"
SP_BOOTLOADER_DEFAULT_GRUB_MENUENTRY="Screaming Penguin"
SP_BOOTLOADER_DEFAULT_FSTAB_ROOT_OPTS="defaults,noatime"
SP_BOOTLOADER_DEFAULT_FSTAB_EFI_OPTS="umask=0077,fmask=0077,dmask=0077"
SP_DISK_BY_UUID_DIR="${SP_DISK_BY_UUID_DIR:-/dev/disk/by-uuid}"

sp_bootloader_log() {
    sp_log "state=bootloader" "$@"
}

sp_bootloader_marker() {
    marker="$1"
    shift
    sp_bootloader_log "marker=$marker" "$@"
}

sp_bootloader_debug() {
    if [ "${SP_DEBUG_BOOTLOADER:-0}" = "1" ]; then
        sp_bootloader_log "debug=1" "$@"
    fi
}

sp_bootloader_config_value() {
    expr="$1"
    default="$2"

    if [ -n "${SP_CONFIG_PATH:-}" ] && command -v sp_rootfs_yq_value >/dev/null 2>&1; then
        value=$(sp_rootfs_yq_value "$expr")
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return 0
        fi
    fi

    printf '%s' "$default"
}

sp_bootloader_uuid_for_partition() {
    part="$1"
    if [ -z "$part" ]; then
        return 1
    fi

    if [ ! -d "${SP_DISK_BY_UUID_DIR}" ]; then
        sp_bootloader_log "step=uuid" "result=failed" "reason=by-uuid-missing" "path=${SP_DISK_BY_UUID_DIR}"
        return 1
    fi

    for entry in "${SP_DISK_BY_UUID_DIR}"/*; do
        if [ ! -e "$entry" ]; then
            continue
        fi

        target=$(readlink -f "$entry" 2>/dev/null || true)
        if [ "$target" = "$part" ]; then
            printf '%s\n' "$(basename "$entry")"
            return 0
        fi
    done

    return 1
}

sp_bootloader_efi_mount_point() {
    efi_rel=$(sp_bootloader_config_value '.installer.bootloader.efi_mount_point // ""' "")
    if [ -z "$efi_rel" ]; then
        efi_rel="$SP_BOOTLOADER_DEFAULT_EFI_MOUNTPOINT"
    fi

    printf '%s' "$efi_rel"
}

sp_bootloader_mount_efi() {
    efi_part="${SP_DISK_EXECUTE_EFI_PART:-}"
    if [ -z "$efi_part" ]; then
        sp_bootloader_log "step=mount-efi" "result=failed" "reason=efi-partition-missing"
        return 1
    fi

    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target_dir" ]; then
        sp_bootloader_log "step=mount-efi" "result=failed" "reason=target-missing"
        return 1
    fi

    efi_mount_rel=$(sp_bootloader_efi_mount_point)
    efi_mount="$target_dir$efi_mount_rel"

    mkdir -p "$efi_mount"
    if ! mount "$efi_part" "$efi_mount" >/dev/null 2>&1; then
        sp_bootloader_log "step=mount-efi" "result=failed" "reason=mount-failed" "partition=$efi_part" "path=$efi_mount"
        return 1
    fi

    SP_BOOTLOADER_EFI_MOUNTED=1
    SP_BOOTLOADER_EFI_PATH="$efi_mount"
    sp_bootloader_log "step=mount-efi" "result=ok" "partition=$efi_part" "path=$efi_mount"
    return 0
}

sp_bootloader_unmount_efi() {
    if [ "${SP_BOOTLOADER_EFI_MOUNTED:-0}" != "1" ]; then
        return 0
    fi

    mount_point="${SP_BOOTLOADER_EFI_PATH:-}"
    if [ -n "$mount_point" ]; then
        umount "$mount_point" >/dev/null 2>&1 || sp_bootloader_log "step=unmount-efi" "result=warn" "path=$mount_point"
    fi

    SP_BOOTLOADER_EFI_MOUNTED=0
}

sp_bootloader_find_kernel() {
    root="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$root" ]; then
        return 1
    fi

    for candidate in "$root"/boot/vmlinuz "$root"/boot/vmlinuz-* "$root"/boot/vmlinuz.* "$root"/boot/kernel* "$root"/vmlinuz "$root"/vmlinuz-*; do
        if [ -f "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

sp_bootloader_find_initrd() {
    root="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$root" ]; then
        return 1
    fi

    for candidate in "$root"/boot/initrd.img "$root"/boot/initrd.img-* "$root"/boot/initramfs-* "$root"/initrd.img "$root"/initrd.img-*; do
        if [ -f "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

sp_bootloader_relative_path() {
    path="$1"
    root="$2"
    if [ -z "$path" ] || [ -z "$root" ]; then
        return 1
    fi

    case "$path" in
        "$root"*)
            printf '%s' "${path#"${root}"}"
            ;;
        *)
            printf '%s' "$path"
            ;;
    esac
}

sp_bootloader_generate_fstab() {
    root_uuid=$(sp_bootloader_uuid_for_partition "$SP_DISK_EXECUTE_ROOT_PART") || root_uuid=""
    efi_uuid=$(sp_bootloader_uuid_for_partition "$SP_DISK_EXECUTE_EFI_PART") || efi_uuid=""

    if [ -z "$root_uuid" ]; then
        sp_bootloader_log "step=fstab" "result=failed" "reason=root-uuid-missing"
        return 1
    fi

    if [ -z "$efi_uuid" ]; then
        sp_bootloader_log "step=fstab" "result=failed" "reason=efi-uuid-missing"
        return 1
    fi

    root_opts=$(sp_bootloader_config_value '.installer.bootloader.fstab_root_options // ""' "")
    if [ -z "$root_opts" ]; then
        root_opts="$SP_BOOTLOADER_DEFAULT_FSTAB_ROOT_OPTS"
    fi

    efi_opts=$(sp_bootloader_config_value '.installer.bootloader.fstab_efi_options // ""' "")
    if [ -z "$efi_opts" ]; then
        efi_opts="$SP_BOOTLOADER_DEFAULT_FSTAB_EFI_OPTS"
    fi

    target="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target" ]; then
        sp_bootloader_log "step=fstab" "result=failed" "reason=target-missing"
        return 1
    fi

    fstab_path="$target/etc/fstab"
    mkdir -p "$target/etc"
    efi_mount_rel=$(sp_bootloader_efi_mount_point)

    cat <<EOF >"$fstab_path"
UUID=$root_uuid / ext4 $root_opts 0 1
UUID=$efi_uuid $efi_mount_rel vfat $efi_opts 0 2
EOF

    sp_bootloader_log "step=fstab" "result=ok" "path=$fstab_path"
    return 0
}

sp_bootloader_generate_grub_cfg() {
    target="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target" ]; then
        sp_bootloader_log "step=grub-cfg" "result=failed" "reason=target-missing"
        return 1
    fi

    root_uuid=$(sp_bootloader_uuid_for_partition "$SP_DISK_EXECUTE_ROOT_PART") || root_uuid=""
    if [ -z "$root_uuid" ]; then
        sp_bootloader_log "step=grub-cfg" "result=failed" "reason=root-uuid-missing"
        return 1
    fi

    kernel_path=$(sp_bootloader_find_kernel)
    if [ -z "$kernel_path" ]; then
        sp_bootloader_log "step=grub-cfg" "result=failed" "reason=kernel-missing"
        return 1
    fi

    initrd_path=$(sp_bootloader_find_initrd) || initrd_path=""

    relative_kernel=$(sp_bootloader_relative_path "$kernel_path" "$target")
    relative_initrd=""
    if [ -n "$initrd_path" ]; then
        relative_initrd=$(sp_bootloader_relative_path "$initrd_path" "$target")
    fi

    timeout=$(sp_bootloader_config_value '.installer.bootloader.grub_timeout // ""' "")
    if [ -z "$timeout" ]; then
        timeout="$SP_BOOTLOADER_DEFAULT_GRUB_TIMEOUT"
    fi

    entry_name=$(sp_bootloader_config_value '.installer.bootloader.menu_entry // ""' "")
    if [ -z "$entry_name" ]; then
        entry_name="$SP_BOOTLOADER_DEFAULT_GRUB_MENUENTRY"
    fi

    grub_cfg_rel=$(sp_bootloader_config_value '.installer.bootloader.grub_cfg_path // ""' "")
    if [ -z "$grub_cfg_rel" ]; then
        grub_cfg_rel="$SP_BOOTLOADER_DEFAULT_GRUB_CFG_PATH"
    fi

    grub_cfg_path="$target$grub_cfg_rel"
    mkdir -p "$(dirname "$grub_cfg_path")"

    cat <<EOF >"$grub_cfg_path"
set rootuuid=$root_uuid
search --no-floppy --fs-uuid "$root_uuid" --set=root
set default=0
set timeout=$timeout

menuentry "$entry_name" {
  linux $relative_kernel root=UUID=$root_uuid ro quiet
EOF

    if [ -n "$relative_initrd" ]; then
        cat <<EOF >>"$grub_cfg_path"
  initrd $relative_initrd
EOF
    fi

    cat <<'EOF' >>"$grub_cfg_path"
}
EOF

    sp_bootloader_log "step=grub-cfg" "result=ok" "path=$grub_cfg_path" "kernel=$relative_kernel" "initrd=${relative_initrd:-none}"
    sp_bootloader_debug "root-uuid=$root_uuid" "timeout=$timeout" "entry=$entry_name"
    return 0
}

sp_bootloader_install_grub() {
    grub_target=$(sp_bootloader_config_value '.installer.bootloader.grub_efi_target // ""' "")
    if [ -z "$grub_target" ]; then
        grub_target="$SP_BOOTLOADER_DEFAULT_GRUB_TARGET"
    fi

    bootloader_id=$(sp_bootloader_config_value '.installer.bootloader.bootloader_id // ""' "")
    if [ -z "$bootloader_id" ]; then
        bootloader_id="$SP_BOOTLOADER_DEFAULT_BOOTLOADER_ID"
    fi

    efi_dir="${SP_BOOTLOADER_EFI_PATH:-}"
    if [ -z "$efi_dir" ]; then
        sp_bootloader_log "step=grub-install" "result=failed" "reason=efi-not-mounted"
        return 1
    fi

    sp_bootloader_debug "chroot-root=$SP_ROOTFS_TARGET_DIR" "grub-target=$grub_target" "efi-dir=$efi_dir" "loader-id=$bootloader_id"

    if ! sp_rootfs_chroot_exec \
        grub-install \
        --target="$grub_target" \
        --efi-directory="$efi_dir" \
        --bootloader-id="$bootloader_id" \
        --recheck \
        --no-floppy \
        >/dev/null 2>&1; then
        sp_bootloader_log "step=grub-install" "result=failed" "reason=grub-install-failed"
        return 1
    fi

    sp_bootloader_log "step=grub-install" "result=ok"
    return 0
}

sp_install_bootloader_and_finalize() {
    sp_bootloader_marker "START"

    if [ "${SP_SKIP_BOOTLOADER:-0}" = "1" ]; then
        sp_bootloader_log "result=skipped" "reason=skip-flag"
        sp_bootloader_marker "END"
        return 0
    fi

    if [ "${SP_ENABLE_BOOTLOADER:-0}" != "1" ]; then
        sp_bootloader_log "result=skipped" "reason=toggle-disabled"
        sp_bootloader_marker "END"
        return 0
    fi

    if [ "${SP_ENABLE_DISK_EXECUTE:-0}" != "1" ]; then
        sp_bootloader_log "result=skipped" "reason=disk-exec-disabled"
        sp_bootloader_marker "END"
        return 0
    fi

    if [ "${SP_MODE:-SMOKE}" != "INSTALL" ]; then
        sp_bootloader_log "result=skipped" "reason=mode-${SP_MODE:-unknown}"
        sp_bootloader_marker "END"
        return 0
    fi

    if ! sp_disk_execute_require_write_gate; then
        sp_bootloader_log "result=failed" "reason=write-gate"
        sp_bootloader_marker "END"
        return 1
    fi

    sp_rootfs_determine_target_dir
    if [ -z "${SP_ROOTFS_TARGET_DIR:-}" ]; then
        sp_bootloader_log "result=failed" "reason=target-unknown"
        sp_bootloader_marker "END"
        return 1
    fi

    result=0
    sp_rootfs_mount_target && sp_rootfs_bind_virtuals || result=1

    if [ "$result" -ne 0 ]; then
        sp_bootloader_log "result=failed" "reason=rootfs-mount-failed"
        sp_bootloader_marker "END"
        sp_bootloader_unmount_efi
        sp_rootfs_unmount_virtuals
        sp_rootfs_unmount_target
        return 1
    fi

    if ! sp_bootloader_mount_efi; then
        result=1
    fi

    if [ "$result" -eq 0 ] && ! sp_bootloader_generate_fstab; then
        result=1
    fi

    if [ "$result" -eq 0 ] && ! sp_bootloader_generate_grub_cfg; then
        result=1
    fi

    if [ "$result" -eq 0 ] && ! sp_bootloader_install_grub; then
        result=1
    fi

    sp_bootloader_unmount_efi
    sp_rootfs_unmount_virtuals
    sp_rootfs_unmount_target

    if [ "$result" -ne 0 ]; then
        sp_bootloader_log "result=failed" "reason=bootloader-stage-failed"
        sp_bootloader_marker "END"
        return 1
    fi

    sp_bootloader_log "result=ok"
    sp_bootloader_marker "END"
    return 0
}
