# Phase 8 Checkpoint 1 — Write-Gate Analysis

## Repository Survey
- `installer/init/init.sh` is the initramfs bootstrap invoked by `installer/initramfs/init`; it already discovers `/config/installer-config.yml`, parses `target_disk`, probes disks, and summarizes readiness without ever touching partitions.
- The runtime installer lives under `installer/runtime`; `installer/runtime/lib/config_validation.sh` drives configuration loading with `yq`, and `installer/runtime/sp-installer` relies on that validator for every state transition.
- There are no existing Python helpers or schema validators in `installer/python`; the only config awareness in `installer/` today is the shell `config_validation.sh` and the tiny initramfs stub helpers under `installer/initramfs`.

## Config Loading Details
- `sp_discover_config` in `installer/init/init.sh` probes `/config/installer-config.yml` (then `/mnt/config/...`) and sets `SP_CONFIG_PATH`. All downstream config parsing (`sp_load_config`) reads this path.
- The runtime `SP_CONFIG_PATH` defaults to `/config/installer-config.yml` in `installer/runtime/sp-installer`, so the same file is shipped for runtime validation.

## Init Scripts
- The initramfs entrypoint is `installer/initramfs/init`; it sources `/initramfs/lib/config.sh` when available and merely hands off to the installer stub after logging, so the real gating work must happen in `installer/init/init.sh`.

## Write-Gate Failure Surface
- The new gate must run immediately after the config file is loaded in `installer/init/init.sh` so that the initramfs stage exits before any disk work occurs when `installer.write_gate` is missing or `false`.
- The gate should print `[SP-INSTALLER] write-gate BLOCKED`/`OK` markers and stop execution before `sp_idle_shell` remains, and it should make absolutely sure the failure path emits to both the console and serial ports.
- The runtime validator should also know about `installer.write_gate` so that the Phase 5 installer exits with a clear error if the gate flips states once the `/config` partition is mounted.

## Planned Modifications
1. Extend the config example and schema docs with the required `installer.write_gate` boolean and note that no disk writes are allowed unless it is `true`.
2. Introduce `installer/python` with a `write_gate` helper that parses YAML, asserts the field exists, enforces `bool`, and raises structured errors; expose this via a new package entrypoint for future tooling.
3. Modify `installer/runtime/lib/config_validation.sh` to read and normalize `.installer.write_gate`, treating a missing/disabled gate as a validation failure.
4. Rework `installer/init/init.sh` (full-file rewrite per instructions) to: support configurable log/serial devices for testing, parse `installer.write_gate`, log the `[SP-INSTALLER] write-gate OK/BLOCKED` markers, emit console+serial errors, exit non-zero on failure, and optionally short-circuit `sp_idle_shell` when a test token is set.
5. Add `tests/installer` pytest coverage for the Python helper (missing/false/true scenarios) plus a shell-script test that seeds a fake console/serial log and asserts the new markers and exit codes.
6. Update docs: `docs/installer_contract.md`, `docs/architecture.md`, `docs/Phase8_Roadmap.md` (create if needed) to describe the write-gate requirement and emphasize that no disk writes happen unless the gate is enabled.

## Testing & Validation Plan
- Post-implementation we must run `pytest -q`, then `ruff` and `black` over the new Python code and any other lintable files.
- Tests must cover every gate scenario (missing field, `false`, `true`) and confirm the init script emits the specified markers in both console and serial logs.

