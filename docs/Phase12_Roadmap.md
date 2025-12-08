# Phase 12 Roadmap

Phase 12 delivers the **final bootstrap** stage inside the initramfs so the installed system ends up with a mounted rootfs, a valid `/etc/fstab`, and a working EFI GRUB installation before the installer exits.

- Add `installer/runtime/lib/bootloader.sh`, which mounts the EFI partition, rewrites `/etc/fstab` with `blkid` UUIDs, generates a minimal `grub.cfg`, runs `grub-install --target=<grub_efi_target> --efi-directory=/boot/efi --bootloader-id=<id> --recheck`, and emits `[SP-INSTALLER] bootloader START/END` markers while honoring `SP_ENABLE_BOOTLOADER`, `SP_SKIP_BOOTLOADER`, and `SP_DEBUG_BOOTLOADER`.
- Update `installer/init/init.sh` so that after planner/executor succeeds and the install mode is `INSTALL`, it runs `sp_safety_prepare_devices`, `sp_rootfs_apply`, `sp_install_bootloader_and_finalize`, and finally logs a `[SP-INSTALLER] COMPLETE` marker while still gating on `installer.write_gate` plus the new toggles.
- Wire the new config schema section (`installer.bootloader`) into `docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, and `docs/architecture.md`, describe the new skip/debug knobs, and expand `config/installer-config.example.yml` with sensible defaults (`grub_efi_target: x86_64-efi`, `fstab_*` parameters, etc.).
- Author `tests/installer/test_bootloader.py` to validate fstab generation, chroot-command assembly, gating behavior (`SP_ENABLE_BOOTLOADER`, `SP_SKIP_BOOTLOADER`, `SP_DEBUG_BOOTLOADER`), and that the init script invokes the bootloader only when the toggles allow it.
- Update the master roadmap (`docs/DEV_ROADMAP.md`) with a Phase 12 section referencing this work and link to the new Phase 12 roadmap document.
