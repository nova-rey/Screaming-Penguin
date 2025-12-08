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

## Testing and tooling hooks
- Tests under `tests/installer` now verify the init script emits the required markers and that the Python helper rejects invalid gate states.
- Documentation (contracts and roadmap) highlights the write-gate as the single switch that must be enabled before any installer writes run.
