# Phase 9 Roadmap

Phase 9 focuses on planning the disk layout without performing any writes. The goal is to make the EFI+root partition map deterministic, observable, and machine-readable so Phase 10 can safely apply it.

- Introduce `installer/runtime/lib/disk_layout.sh`, a non-destructive planner that reads `target.disk` plus an optional `installer.disk_layout` tuning block (EFI size, alignments, and reserved guard) and emits a GPT plan with exactly one FAT32 EFI partition and one ext4 root partition.
- Expose the raw plan via `sp_print_layout_plan`, and let init logging (gated by `SP_DEBUG_DISK_LAYOUT=1`) wrap the emitted plan in `[SP-INSTALLER] disk-layout plan START`/`END` markers while mirroring the body to the serial console.
- Document the planner in the config schema, architecture overview, and installer contract so tooling and CI know the plan surface exists, and add the new Phase 9 entry to the master roadmap.
- Keep `installer.write_gate` enforced, keep `sp_plan_partitioning` non-destructive, and defer actual GPT writes and filesystems until the execute phase that consumes the declarative plan.
