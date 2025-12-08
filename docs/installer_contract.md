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
