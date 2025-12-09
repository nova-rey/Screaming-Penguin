# Phase 13 — Installer Media Bootability

## Goal
- Guarantee that the raw installer `.img` artifact produced by Screaming Penguin boots on UEFI/BIOS systems by building a GPT layout with a FAT32 ESP that hosts the real installer kernel, initrd, and GRUB EFI payload.

## Delivery checklist
- Rework `tools/make_installer_img.sh` to truncate the image, create GPT partitions, format the ESP as FAT32, and copy `/boot/vmlinuz-installer` + `/boot/initrd-installer.img` into the boot tree.
- Place `grubx64.efi` inside the ESP, ensure `EFI/BOOT/BOOTX64.EFI` exists, and write `EFI/BOOT/grub.cfg` with `search --no-floppy`/`set default=0`/`set timeout=0` plus the `Screaming Penguin Installer` entry that loads the kernel/initrd.
- Add `tools/grub_shared.sh` so both the `.img` and `.iso` builders render the same `linux`/`initrd` lines (the ISO still appends its serial+BIOS options), keeping the loader config in sync.
- Create `tests/installer/test_installer_media_bootability.py` to build a small image, mount the ESP via loop, verify the FAT32 signature, and confirm `/EFI/BOOT/BOOTX64.EFI` plus `grub.cfg` referencing `vmlinuz-installer`/`initrd-installer.img` are present.
- Update the documentation trail (`docs/installer_contract.md`, `docs/architecture.md`, `docs/CONFIG_SCHEMA.md`, and `docs/DEV_ROADMAP.md`) plus the bibles to reflect Phase 13’s completion and the new shared GRUB helper.

## Done when
- `tools/make_installer_img.sh` emits a GPT image whose ESP is FAT32, contains `/EFI/BOOT/BOOTX64.EFI`, and a `grub.cfg` that loads `/boot/vmlinuz-installer` + `/boot/initrd-installer.img`.
- Tests/CI verify the ESP mounts as FAT32 and `grub.cfg` references the installer kernel/initrd.
- The roadmap, contract, architecture, and phase documentation call out Phase 13 and its guarantees, and the bibles log the milestone as complete.
