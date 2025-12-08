# Phase 10 Roadmap

Phase 10 consumes the deterministic disk layout plan created in Phase 9 and performs the actual GPT writes plus filesystem creation. The goal is to make destructive disk changes safe, auditable, and testable before any installer code is deemed release-ready.

- Add `installer/runtime/lib/disk_execute.sh`, which re-runs the planner, re-validates `installer.write_gate`, wipes the target disk, writes the GPT entries with `sgdisk`, and formats EFI (FAT32) + root (ext4) partitions with `mkfs.vfat`/`mkfs.ext4` while emitting `[SP-INSTALLER] disk-exec START/END` markers.
- Integrate the executor into `installer/init/init.sh`, making it run only when the gate is `true`, `SP_MODE=INSTALL`, and the environment explicitly sets `SP_ENABLE_DISK_EXECUTE=1` (CI-safe toggle that keeps dry runs default).
- Introduce the Phase 10 harness (`tests/installer/test_disk_execute.py`) that allocates a 3 GB disk image under `build/`, runs the planner, invokes the executor, and asserts that the EFI + root partitions now exist, carry the correct GPT type codes, and mount successfully via loop offsets.
- Update `docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, and `docs/architecture.md` to describe the execute phase, the gating rules, and the new logging markers so downstream tooling knows when writes happen.
- Keep real disks untouched by CI and the executor unless the gate is explicitly satisfied and `SP_ENABLE_DISK_EXECUTE=1`; the harness, docs, and `docs/DEV_ROADMAP.md` capture this behavior.
