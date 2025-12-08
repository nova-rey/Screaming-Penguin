# Phase 8 Roadmap

The Phase 8 goal is to lock the installer against accidental disk writes until a deliberate gate is enabled.

- Introduce the `installer.write_gate` boolean inside `/config/installer-config.yml` and require it to be `true` before any disk operations run. This field lives alongside the existing sections and must be documented everywhere the config contract is described.
- Enforce the gate inside `installer/init/init.sh` so that the initramfs announces `[SP-INSTALLER] write-gate OK` when satisfied and `[SP-INSTALLER] write-gate BLOCKED` (console + serial) before exiting if the gate is missing or false.
- Propagate the gate into the Phase 5 runtime validator (`installer/runtime/lib/config_validation.sh`) and a Python helper (`installer/python/write_gate.py`) so tooling and the runtime state machine also refuse to proceed when the gate degrades.
- Expand the installer tests to cover missing/false/true gate scenarios and add a stub that runs `installer/init/init.sh` in a simulated environment to verify the output markers. These tests, plus the documentation updates, make the write gate observable and enforceable in CI.
