# Phase 9 Checkpoint 1 — Disk Layout Analysis

## A1. Repository survey
- `installer/init/init.sh` currently bootstraps the initramfs, enforces `installer.write_gate`, discovers `/config/installer-config.yml`, parses `target_disk`, probes `/sys/block`, and emits readiness/plan logs without ever touching disks. The probe stage writes per-disk/partition metadata, and the existing `sp_plan_partitioning` helper already estimates a GPT plan (EFI + root) but only records it via logging, not a structured surface.
- `installer/runtime/lib/config_validation.sh` uses `yq` to load the same config file, enforces `target.disk`, the write gate, hostname/timezone/locale/user requirements, and normalizes bools for runtime validation. No disk-layout-specific config exists yet beyond the top-level `target.disk` setting in `config/installer-config.example.yml`.
- Docs mention `target.disk`, `installer.write_gate`, and the boot contract/architecture emphasis on the gate, but there is no mention of a planned layout model, layout config keys, or a machine-readable plan surface. Tests cover only the write gate via shell+Python helpers.

## A2. v1 disk layout model
**Assumptions (Phase 9 scope)**
1. Phase 9 runs in a single-disk scenario: we target exactly one block device, and the workflow assumes a full-disk wipe will be performed in a later phase.
2. The disk gets a GPT partition table with two partitions: an EFI System Partition (FAT32) and a Linux root partition (ext4). No other partitions (swap, data, recovery) are modeled yet.
3. Layout decisions happen before destructive commands; this checkpoint only plans sizes/positions and emits a declarative plan.

**Config surface and defaults**
- Reuse `target.disk` at the top level (already parsed by init/config validation) as the canonical install target. The planner adds an optional `installer.disk_layout` block for tuning.
- `installer.disk_layout` keys:
  - `efi_size_mib` (default `512`): requested size for the EFI partition.
  - `efi_alignment_mib` (default `1`): alignment for the EFI start offset (MiB).
  - `root_alignment_mib` (default `1`): alignment for the root start.
  - `root_reserved_mib` (default `4`): guard space to leave unused at the end of disk to avoid rounding issues.
  - Future keys (e.g., `root_size_mib`) can be added later, but Phase 9 only needs EFI + root spanning the remainder.
- These defaults keep the planner deterministic while allowing overrides for testing or future tuning.

**Planner output schema**
The planner exposes a JSON-like plan that looks like this:
```
{
  "target_disk": "/dev/nvme0n1",
  "table": "gpt",
  "partitions": [
    {"index": 1, "role": "efi",  "type": "EFI System",    "start_mib": 1, "size_mib": 512, "filesystem": "fat32"},
    {"index": 2, "role": "root", "type": "Linux filesystem", "start_mib": 513, "size_mib": 102400, "filesystem": "ext4"}
  ]
}
```
Every partition entry documents the index, GPT role-friendly name, start/size (MiB), and intended filesystem. `sp_print_layout_plan` emits this plan to stdout, and the init script (when `SP_DEBUG_DISK_LAYOUT=1`) wraps the plan with `[SP-INSTALLER] disk-layout plan START/END` markers in both console and serial logs so CI can detect the span.

## A3. Planned touches
1. `installer/runtime/lib/disk_layout.sh` (new): host `sp_select_target_disk`, `sp_plan_gpt_layout`, `sp_print_layout_plan`, helper constants/parsers, and guard checks (no destructive commands). Will expose an API for runtime and init to query a dry-run plan.
2. `installer/init/init.sh`: source the new planner when gates are satisfied, add `SP_DEBUG_DISK_LAYOUT` handling to emit plan markers, and ensure we never plan/warn if the write gate is false. Existing disk probing/logging remains untouched.
3. `config/installer-config.example.yml`: add the new `installer.disk_layout` block with defaults and doc comments inline so downstream users know about the tuning knobs.
4. `docs/CONFIG_SCHEMA.md`: describe the new keys, their types (`integer`), defaults, and Phase 9 limitations (single disk, GPT, EFI+root).\
5. `docs/installer_contract.md`: mention the new planning stage, the machine-readable plan surface, and the `[SP-INSTALLER] disk-layout plan` markers that precede destructive phases.
6. `docs/architecture.md`: add a short section on the planner, covering where it lives, how it is invoked (write-gate gated + optional debug env), and how it feeds the future execute phase.
7. `docs/Phase9_Roadmap.md`: a new phase summary noting that Phase 9 adds a non-destructive layout planner, but actual writes wait for later work. (Keep style consistent with Phase 8 doc.)
8. `tests/installer/test_disk_layout_planner.py`: pytest-based coverage that runs the planner in a fake config environment, verifies the JSON plan, and ensures errors surface for missing disks or invalid configs.
9. Potential helper tests or fixtures (e.g., `tests/installer/conftest.py` if needed) to share temp files.
10. Any small `docs` references (e.g., update `docs/DEV_ROADMAP.md` or other roadmaps) can be deferred unless explicitly needed.

## A4. Implementation plan
1. Draft `installer/runtime/lib/disk_layout.sh` with:
   - A minimal YAML extractor (pure POSIX) that can read `target.disk` and the new `installer.disk_layout.*` keys from `SP_CONFIG_PATH`/`installer-config.yml`.
   - `sp_select_target_disk` that prefers `SP_TARGET_DISK`/`SP_CFG_TARGET_DISK` but can fall back to parsing `target.disk`. Clear error when unspecified or not a block device.
   - `sp_plan_gpt_layout` that, given a disk path, reads disk size, applies defaults/alignments, and builds an array describing EFI + root partitions.
   - `sp_print_layout_plan` that emits the JSON plan (single-quoted or pretty-printed) and returns non-zero on errors.
2. Update `installer/init/init.sh` to source the new library after the write gate and target disk resolution. When `SP_DEBUG_DISK_LAYOUT=1` and the write gate is satisfied, wrap `sp_print_layout_plan` between `[SP-INSTALLER] disk-layout plan START` and `END` markers written to both console and serial; ensure we still refuse to plan when the gate is blocked.
3. Extend `config/installer-config.example.yml` with `installer.disk_layout` (defaults as above) and minimal inline narrative. Update `docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, `docs/architecture.md`, and create `docs/Phase9_Roadmap.md` to explain the planner, config knobs, plan schema, and the deferral of actual disk writes.
4. Add `tests/installer/test_disk_layout_planner.py` that
   - Writes simple temp configs, invokes `bash -c 'source ...; sp_print_layout_plan'`, and parses the resulting JSON to verify EFI/root ranges and metadata.
   - Verifies failure when no disk is specified or disk metadata cannot be read (e.g., by pointing at `/dev/null` or invalid config).
   - Runs the planner twice with env overrides (custom `SP_CONFIG_PATH`, tune `efi_size_mib`, etc.) to ensure config overrides work and plan is deterministic.
5. Run the required verification commands (`pytest -q`, `ruff check .`, `black --check installer tests`) and confirm the planner logs show start/end markers when `SP_DEBUG_DISK_LAYOUT=1` is set (via tests or manual run). Include any necessary CI hints if a job must set the debug flag.
