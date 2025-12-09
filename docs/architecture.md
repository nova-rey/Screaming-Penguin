# Screaming Penguin Architecture

The installer is split into multiple stages that run inside the initramfs, the helper runtime shell, and the eventual installed system. The current Phase 8 focus is to keep write operations locked behind a deliberate gate.

## Early boot flow
- `/init` starts inside the initramfs and sources the `installer/init/init.sh` bootstrap.
- The bootstrap discovers `/config/installer-config.yml`, reads at least the `target_disk` field, probes `/sys/block`, and builds a sanitized picture of the machine before any disk modifications.
- A lightweight Python helper under `installer/python/write_gate.py` can parse the same YAML file for tooling or future stages.

## Write-gate discipline
- `installer.write_gate` is now a required boolean field; missing or `false` means no disk writes may ever execute. The gate runs before disk discovery completes, ensuring every subsequent stage sees the same guarantee.
- When the gate is satisfied the init script prints `[SP-INSTALLER] write-gate OK`. If it is missing or explicit `false`, the boot path logs `[SP-INSTALLER] write-gate BLOCKED` to both console and serial, and the process exits with an error.
- `installer/runtime/lib/config_validation.sh` revalidates this flag with `yq` so the Phase 5 state machine never starts unless the gate remains `true`.

## Disk layout planner
- Phase 9 plants `installer/runtime/lib/disk_layout.sh` in the runtime libs. It reads `target.disk`, the optional `installer.disk_layout` tuning block from `installer-config.yml`, and deterministic `/sys/block` metadata to emit a GPT plan (EFI + root) without ever running partitioners or filesystem writers.
- The init script sources the planner after the write gate clears and, when `SP_DEBUG_DISK_LAYOUT=1`, emits `[SP-INSTALLER] disk-layout plan START`, prints the JSON plan, writes the plan body and `[SP-INSTALLER] disk-layout plan END` lines into the serial log, and leaves the produced plan for later phases that will perform the destructive work.
- Until the execute phase consumes that plan, writes remain gated off (`sp_plan_partitioning` still only logs and never mutates the device, and the runtime state machine will still refuse to touch disks without the gate).

## Disk execution
- Phase 10 consumes the JSON plan, revalidates `installer.write_gate`, and only runs when `SP_ENABLE_DISK_EXECUTE=1` (the CI toggle keeps destructive work opt-in). The executor logs `[SP-INSTALLER] disk-exec START`, writes the GPT table via `sgdisk`, echoes the new layout with `sfdisk -l`, and formats EFI (`mkfs.vfat -F 32`) and root (`mkfs.ext4 -F`) before logging `[SP-INSTALLER] disk-exec END`.
- The executor tracks EFI+root device paths, enforces the write gate again, and exits non-zero if any `sgdisk` or `mkfs` step fails so the boot path never leaves a partially formatted disk.
- A dedicated harness (`tests/installer/test_disk_execute.py`) drives a 3 GiB file in `build/`, invokes both the planner and executor under `SP_ENABLE_DISK_EXECUTE=1`, and asserts the partitions exist, carry EFI+Linux GPT type codes, and remain mountable via loop offsets.

## Rootfs deployment
- Phase 11 mounts the formatted root partition (tracked as `SP_DISK_EXECUTE_ROOT_PART`), extracts `installer.rootfs.tarball` (default `/config/os/rootfs.tar.gz`), binds `/dev`, `/proc`, `/sys`, and `/run`, and chroots into `/mnt/target` to seed hostname, timezone, locale, user, and SSH keys before leaving the target ready for bootloader configuration.
- The rootfs stage emits `[SP-INSTALLER] rootfs` markers around each step and honors `SP_SKIP_ROOTFS_DEPLOY=1`, `SP_SKIP_CHROOT_CONFIG=1`, and `SP_DEBUG_ROOTFS=1` so CI can validate the span without performing destructive work.

## Phase 12 — Bootloader install

- Phase 12 takes place after Phase 11 completes. It remounts the root tree, mounts the EFI partition into `/boot/efi`, writes `/etc/fstab` using the UUIDs discovered via `blkid`, generates a minimal `/boot/grub/grub.cfg` (pointing at the discovered kernel/initrd), and chroots to run `grub-install --target=<grub_efi_target>` so the installer kernel becomes bootable.
- The stage is gated by two new toggles: `SP_ENABLE_BOOTLOADER=1` must be set before any GRUB work runs, while `SP_SKIP_BOOTLOADER=1` skips the stage but leaves behind the `[SP-INSTALLER] bootloader` markers. Debug logging is available via `SP_DEBUG_BOOTLOADER=1`.
- A new config block `installer.bootloader` exposes the defaults for `efi_mount_point`, `fstab_*_options`, `grub_efi_target`, `bootloader_id`, `grub_cfg_path`, `grub_timeout`, and `menu_entry`. These values are also consumed by the validator in `installer/runtime/lib/config_validation.sh`.
- After the bootloader work finalizes, the init script writes `state=complete` and a literal `[SP-INSTALLER] COMPLETE` line so observers can detect that planner → executor → rootfs → bootloader all completed in order.

## Phase 13 — Installer media bootability

- With the installer tree now writing a bootloader to the target disk, Phase 13 makes the installer image itself a valid USB by building a GPT table whose first partition is a FAT32 ESP that hosts `/EFI/BOOT/BOOTX64.EFI`, `/EFI/BOOT/grub.cfg`, and the real installer kernel/initrd under `/boot`.
- The ESP's `grub.cfg` is generated with the shared helper so both the `.img` and `.iso` builders reference `/boot/vmlinuz-installer` and `/boot/initrd-installer.img`, while the script copies `grubx64.efi` into `EFI/BOOT` and ensures `BOOTX64.EFI` exists for removable firmware lookups. A new installer-media test mounts the ESP via loop, validates the FAT32 signature, and inspects `grub.cfg` for the canonical kernel/initrd paths before asserting Phase 13 is complete.

## Testing and tooling hooks
- Tests under `tests/installer` now verify the init script emits the required markers and that the Python helper rejects invalid gate states.
- Documentation (contracts and roadmap) highlights the write-gate as the single switch that must be enabled before any installer writes run.
