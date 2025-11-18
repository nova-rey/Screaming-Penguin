# Screaming Penguin ISO Build and Boot Process (v1)

This document explains how the Screaming Penguin ISO is constructed and how to test it manually.

## Build Pipeline

`make iso` now performs the following steps:

1. Build minimal Debian runtime (`build/runtime/`)
2. Build the custom installer initramfs (`build/runtime-installer/initrd-installer.img`)
3. Construct the ISO tree:
   - `boot/vmlinuz`
   - `boot/initrd-install.img`
   - `boot/grub/grub.cfg`
4. Install EFI bootloader (`bootx64.efi`)
5. Generate hybrid ISO using `xorriso`

## Boot Behavior

Booting the ISO loads:

linux /boot/vmlinuz root=/dev/ram0 rdinit=/init
initrd /boot/initrd-install.img

The custom initramfs:
- mounts `/proc`, `/sys`, `/dev`
- locates `CONFIG` by label
- mounts it at `/mnt/config`
- launches installer scripts

## Manual Testing

### Test ISO Locally with QEMU

qemu-system-x86_64 -m 1024 
-cdrom dist/screaming-penguin.iso 
-nographic

Look for:

[SP-INSTALLER] Locating CONFIG partition…

### USB Creation

Use any ISO writer:
- Rufus (Windows)
- Popsicle / Disks (Linux)
- BalenaEtcher (Cross-platform)

After flashing, create a second FAT32 partition named `CONFIG` and place:

- `config/installer-config.yml`
- `config/debian-rootfs.tar.gz`
