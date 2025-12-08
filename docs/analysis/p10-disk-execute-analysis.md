# Phase 10 Checkpoint 1 — Disk Execute Analysis

## A1. Repository survey
- `installer/init/init.sh` already handles bootstrap, `installer.write_gate`, config discovery, disk probing, and the Phase 9 planner via `installer/runtime/lib/disk_layout.sh`, but it currently never runs `sgdisk`, `sfdisk`, `mkfs.*`, or real partitioning.
- `installer/runtime/lib/disk_layout.sh` guarantees the planner APIs (`sp_plan_gpt_layout`/`sp_print_layout_plan`) populate `SP_DISK_LAYOUT_LAST_PLAN` with deterministic JSON describing EFI+root partitions and never mutates disks. The init script currently sources this file after gate enforcement and optionally logs the plan when `SP_DEBUG_DISK_LAYOUT=1`.
- Tests under `tests/installer` cover the planner and gate helpers. Docs (`docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, `docs/architecture.md`, `docs/Phase9_Roadmap.md`) describe the planning blockade and gate discipline but do not yet describe execution. `docs/DEV_ROADMAP.md` lacks any Phase 10 entry.

## A2. Execution surface needs (Phase 10 scope)
1. An executor must re-read `SP_DISK_LAYOUT_LAST_PLAN` (or rerun `sp_plan_gpt_layout`) to know which partitions to lay down, as the Phase 9 plan is the single source of truth for destructive work.
2. The executor must strongly re-validate `installer.write_gate` immediately before any writes to keep the gate effective even if configs change after the planner ran.
3. Partitioning should happen with GPT tooling (`sgdisk`/`sfdisk`) and filesystems created via `mkfs.vfat` and `mkfs.ext4`; all calls must log with `[SP-INSTALLER]` markers and emit clear success/failure messages plus dedicated `disk-exec START`/`END` markers.
4. No production path should ever touch real disks unless `installer.write_gate` is `true`, the installer mode is `INSTALL`, and the environment explicitly sets `SP_ENABLE_DISK_EXECUTE=1`; tests must use a disposable 2–4 GB virtual disk file under `build/` so CI never hits `/dev/sdX`.
5. The executor needs a small Python helper to parse the JSON plan and expose partition metadata (indexes, types, start/size, target filesystems) so the shell script can iterate without brittle text parsing.

## A3. Planned touches
- `installer/runtime/lib/disk_execute.sh` gains the executor layer with helpers: JSON loader, `sp_execute_gpt_plan`, `sp_execute_partitioning`, `sp_execute_mkfs_efi`, `sp_execute_mkfs_root`, write-gate revalidation, and `[SP-INSTALLER] disk-exec START/END` logging.
- `installer/init/init.sh` will source the new executor, gate execution on `installer.write_gate == true`, `SP_ENABLE_DISK_EXECUTE=1`, and the absence of skip/debug-only modes, and invoke `sp_execute_gpt_plan` in install mode after readiness checks.
- `tests/installer/test_disk_execute.py` will orchestrate a sparse disk file (2–4 GB), run the planner to get JSON, invoke the executor with `SP_ENABLE_DISK_EXECUTE=1`, and assert the EFI FAT32 + ext4 partitions exist and are mountable without ever hitting real block devices.
- Documentation updates (`docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, `docs/architecture.md`) will describe the execute phase, the gating semantics, and the logging markers. A new Phase 10 roadmap (`docs/Phase10_Roadmap.md`) and this analysis doc capture the checkpoint plan.
- Additional doc update in `docs/DEV_ROADMAP.md` (Block C) will include the new phase, and any “Screaming Penguin bible” sections impacted by this extension.

## A4. Implementation plan
1. Build `installer/runtime/lib/disk_execute.sh` with POSIX shell functions that:
   - Source or compute `SP_DISK_LAYOUT_LAST_PLAN` via `sp_plan_gpt_layout`.
   - Use a bundled Python helper (invoked via `python3`/`python`) to parse the JSON and emit shell-friendly variables for each partition (index, name, type codes, start/size, filesystem) along with metadata such as the target disk base name.
   - Re-run `sp_enforce_write_gate` (or equivalent logic) before making any writes; abort if the gate is missing, false, or the plan doesn't mention the current target disk.
   - Execute GPT writes with `sgdisk`/`sfdisk` and log each command result, including `[SP-INSTALLER] disk-exec START`, per-step logs (`partitioning`, `mkfs`), and `[SP-INSTALLER] disk-exec END` so CI can detect the window.
   - Format the EFI partition with `mkfs.vfat -F32` and the root with `mkfs.ext4`, verifying their presence (and optionally mounting them to check `mount`/`umount`).
2. Extend `installer/init/init.sh` to source the new script (after `disk_layout.sh`) and, when in INSTALL mode with `installer.write_gate` satisfied and `SP_ENABLE_DISK_EXECUTE=1`, call `sp_execute_gpt_plan` after readiness and before falling back to idle shell; ensure debug-only skips (`SP_SKIP_CONFIG_DISCOVERY`, etc.) either short-circuit or log reasons for skipping the executor.
3. Implement `tests/installer/test_disk_execute.py` to:
   - Create a temporary sparse disk file (e.g., `dd if=/dev/zero of=build/test-disk bs=1 count=0 seek=3G`).
   - Set `SP_CONFIG_PATH` to a config that targets this fake disk and run the planner to obtain JSON (probably via `sp_print_layout_plan`).
   - Set `SP_ENABLE_DISK_EXECUTE=1`, point relevant `SP_*` vars at the fake disk file, run the executor, and verify the created partition table exists (using `sgdisk -p` or `parted -s` to inspect), the GPT type/number matches expectations, and mounting the partitions (via `mount -o loop`) succeeds for EFI FAT32 and ext4 root.
   - Clean up mounts/disks and ensure failure if the gate is off or `SP_ENABLE_DISK_EXECUTE` is missing.
4. Update docs:
   - `docs/CONFIG_SCHEMA.md` should mention execution requirements, document `installer.write_gate` as gating for disk write, and mention `SP_ENABLE_DISK_EXECUTE` toggles for CI.
   - `docs/installer_contract.md` should record the new `[SP-INSTALLER] disk-exec` markers, `SP_ENABLE_DISK_EXECUTE` toggle, and the guarantee that Phase 10 will only write once stabilised plan/gate.
   - `docs/architecture.md` should highlight the new executor layer, partitioning/formatting flow, gating, and logging semantics.
   - `docs/Phase10_Roadmap.md` should narrate the Phase 10 deliverables (executor, safety harness, tests) analogous to the Phase 9 roadmap.
5. Block C will run `pytest -q`, `ruff check .`, `black --check installer tests`, and `shellcheck -x installer/init/init.sh installer/runtime/lib/*.sh`, fixing failures as needed, then update `docs/DEV_ROADMAP.md` and any bible entry to reflect Phase 10 completion and summarize results.
