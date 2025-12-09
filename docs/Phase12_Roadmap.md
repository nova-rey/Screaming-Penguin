# Phase 12 — Bootloader Install & Finalization

## Goal
- Complete the bootstrap by teaching the installer how to mount the EFI partition, write a correct `/etc/fstab`, and install GRUB so the target system can actually boot once the runtime hands control to it.

## Delivery checklist
- Add `installer/runtime/lib/bootloader.sh` that:
  - Honors `installer.write_gate` plus the new `SP_ENABLE_BOOTLOADER`, `SP_SKIP_BOOTLOADER`, and `SP_DEBUG_BOOTLOADER` toggles.
  - Mounts the EFI partition and generates `/etc/fstab` with root + EFI UUIDs retrieved via `blkid`.
  - Generates a minimal `/boot/grub/grub.cfg` from the files already present in the target tree.
  - Runs `grub-install --target=<grub_efi_target>` inside the chroot and signals `[SP-INSTALLER] bootloader START/END`.
- Wire the library into `installer/init/init.sh` after `sp_rootfs_deploy_and_configure`, emit a final `[SP-INSTALLER] COMPLETE` marker, and ensure planners/executor/rootfs/bootloader run in strict order.
- Extend `installer.runtime.lib.config_validation.sh` and `config/installer-config.example.yml` with the optional `installer.bootloader` block documenting the defaults mentioned above.
- Add `tests/installer/test_bootloader.py` to validate fstab generation, GRUB command assembly, gating behavior, and skip/debug semantics.
- Update `docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, `docs/architecture.md`, and the master roadmap (`docs/DEV_ROADMAP.md`) to describe Phase 12, the new config block, and the final completion cue.

## Done when
- The bootloader stage mounts EFI, regenerates `/etc/fstab`, installs GRUB, logs `[SP-INSTALLER] bootloader` markers, and hands back control.
- Config docs and validation describe the new `installer.bootloader` block and the optional skip/debug toggles.
- Tests cover the new helpers in a non-destructive way and the init shim only reaches the bootloader stage when its gating variables align.
