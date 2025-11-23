## Phase 1 — Reassemble Full Initramfs Functionality

- [ ] **P1-A — Initramfs Utilities & Logging Design**  
      Define the required BusyBox applets, device-detection behavior, logging scheme, and early error surfaces. *(Design/docs only; no code changes.)*

- [ ] **P1-B — Initramfs Utilities & Logging Implementation**  
      Implement the utilities and logging scheme in the initramfs scripts, wiring all major steps to the unified logging and error model.

- [ ] **P1-C — Config Stub Wiring (Non-Fatal)**  
      Add a config helper (`config.sh`) and a non-fatal `sp_config_probe` call from `init` that logs the presence/absence of `/config/installer-config.yml` and stages it into `/run` when available, without changing CI behavior.
