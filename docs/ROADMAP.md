## Phase 1 — Reassemble Full Initramfs Functionality

**Goal:** Restore the core initramfs capabilities that were removed during the minimal-boot debugging phase, while keeping CI green and behavior predictable.

Phase 1 is broken down into smaller, explicitly scoped steps:

- **P1-A — Initramfs Utilities & Logging Design**  
  - Define which BusyBox applets and system utilities are required by the installer.  
  - Specify how hardware/block-device detection should behave at initramfs time.  
  - Design a unified logging and error-reporting scheme (serial console + on-disk logs).  
  - Identify the minimal error surfaces needed for early-boot failures (config, disk selection, partitioning, rootfs extraction).

- **P1-B — Initramfs Utilities & Logging Implementation** *(later)*  
  - Wire up the utilities and logging functions inside the initramfs scripts.  
  - Ensure early-boot errors are reported consistently and visibly.

Subsequent Phase 1 steps (P1-C, P1-D, etc.) will handle config parsing stubs, partitioning stubs, and other higher-level behaviors once the foundational utilities and logging are in place.
