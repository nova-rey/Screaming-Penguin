#!/bin/sh
# Shared helpers for installer GRUB configuration and EFI artifacts.

sp_resolve_grub_efi_binary() {
    if [ -n "${SP_GRUB_EFI_BIN:-}" ]; then
        printf '%s' "$SP_GRUB_EFI_BIN"
        return 0
    fi

    for candidate in \
        /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
        /usr/lib/grub/x86_64-efi-signed/grubx64.efi \
        /usr/lib/grub/x86_64-efi/grubx64.efi \
        /usr/lib/grub/x86_64-efi-signed/grubx64.efi \
        /usr/lib/grub/efi/x86_64/grubx64.efi \
        /usr/lib/grub/x86_64-efi/uefi/grubx64.efi; do
        if [ -f "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

sp_installer_grub_kernel_lines() {
    linux_args="${1:-quiet}"
    initrd_args="${2:-}"

    printf '    linux /boot/vmlinuz-installer %s\n' "$linux_args"

    if [ -n "$initrd_args" ]; then
        printf '    initrd /boot/initrd-installer.img %s\n' "$initrd_args"
    else
        printf '    initrd /boot/initrd-installer.img\n'
    fi
}
