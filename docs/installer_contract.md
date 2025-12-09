# Screaming Penguin Installer Contract

This document records the guarantees that the installer boot path makes to the live system and to any manifest describing the installation.

## Configuration contract
- The installer always looks for `/config/installer-config.yml` (falling back to `/mnt/config/installer-config.yml`).
- The configuration must include an `installer` section with a boolean `write_gate` key. This key is **required** and must be `true` before any disk operations may run.
- If `installer.write_gate` is missing or evaluates to `false`, the initramfs immediately aborts with a clear error, emits `[SP-INSTALLER] write-gate BLOCKED` to both console and serial, and the runtime validator refuses to load the rest of the configuration.

## Runtime contract
- The initramfs respects the gate before it resolves the target disk, probes devices, or even enters the idle shell. Logs produced while the gate is satisfied include `[SP-INSTALLER] write-gate OK` so CI and diagnostics can confirm the condition.
- `installer/runtime/lib/config_validation.sh` and the Python helper under `installer/python/write_gate.py` both enforce the gate so Phase 5 will also abort if the flag is absent or disabled.
- Before any destructive disk commands run (Phase 9), the planner described in `installer/runtime/lib/disk_layout.sh` consumes the same config, produces a deterministic GPT layout (EFI + root), and prints a machine-readable JSON plan. When `SP_DEBUG_DISK_LAYOUT=1` the init script emits `[SP-INSTALLER] disk-layout plan START`, the plan body lines, and `[SP-INSTALLER] disk-layout plan END` to both console and serial so future phases and tooling can observe exactly what will be written.
- Once `installer.write_gate` is true and CI toggles `SP_ENABLE_DISK_EXECUTE=1`, the init script re-invokes the planner, logs `[SP-INSTALLER] disk-exec START/END`, runs `sgdisk` to paint the GPT table, inspects the result with `sfdisk -l`, and formats EFI+root with `mkfs.vfat`/`mkfs.ext4`. The executor exits non-zero if any step fails, and no destructively phase runs unless both the gate and toggle stay satisfied.
- After the disk executor finishes, Phase 11 mounts the freshly-created root partition (`SP_DISK_EXECUTE_ROOT_PART`) at `/mnt/target` (or the configured override), extracts `installer.rootfs.tarball` (default `/config/os/rootfs.tar.gz`), bind-mounts `/dev`, `/proc`, `/sys`, and `/run`, and chroots to configure hostname, timezone, locale, the primary user (`installer.rootfs.username`), and SSH keys.
- The rootfs stage logs `[SP-INSTALLER] rootfs START/END` spans and honors `SP_SKIP_ROOTFS_DEPLOY=1`, `SP_SKIP_CHROOT_CONFIG=1`, and `SP_DEBUG_ROOTFS=1` so CI can exercise the logic without touching real hardware.
- Phase 12 installs GRUB. The bootloader library reads the optional `installer.bootloader` block, mounts the EFI partition, writes `/etc/fstab` with `blkid`-sourced UUIDs for root + EFI, generates a minimal `/boot/grub/grub.cfg`, and runs `grub-install --target=<grub_efi_target>` inside the chroot so `SP_DISK_EXECUTE_ROOT_PART` becomes bootable. The stage only runs when `SP_ENABLE_BOOTLOADER=1`, skips cleanly via `SP_SKIP_BOOTLOADER=1`, and emits extra detail when `SP_DEBUG_BOOTLOADER=1`.
- `[SP-INSTALLER] bootloader START/END` marks bracket the GRUB work, and the installer now adds a final `[SP-INSTALLER] COMPLETE` marker after all stages finish so consumers can tell the install reached its terminal state.
