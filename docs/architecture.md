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

## Testing and tooling hooks
- Tests under `tests/installer` now verify the init script emits the required markers and that the Python helper rejects invalid gate states.
- Documentation (contracts and roadmap) highlights the write-gate as the single switch that must be enabled before any installer writes run.
