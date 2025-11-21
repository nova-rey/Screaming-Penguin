# Screaming Penguin — Initramfs Reconstruction

This document captures the teardown, validation, and seven-stage rebuild of the installer initramfs.

---

## Teardown and Validation

- Extracted the installer initramfs from the ISO to audit contents and permissions.
- Confirmed `/init` and `/bin/busybox` existed, but `/init` lacked executable permissions and never ran as PID1.
- Observed kernel boot reaching **"Run /init as init process"** before failing with **/init not found or not executable (error -2)**.
- Kernel exhausted fallback init paths and panicked; QEMU-CI never observed the required **"[SP-INSTALLER] init reached"** marker.
- Performed a minimal rebuild using only BusyBox and a stub init to validate QEMU behavior and confirm the permission issue.

## Seven-Stage Init Reconstruction

- **Stage 1:** Minimal init stub with hardcoded echo validated serial output.
- **Stage 2:** Rebuilt BusyBox unpack with PATH setup to reestablish shell applets.
- **Stage 3:** Reintroduced mode detection logic for installer vs. runtime selection.
- **Stage 4:** Added logging scaffold and serial pipe to retain early boot visibility.
- **Stage 5:** Added mount scaffolding and device probing placeholders.
- **Stage 6:** Reintroduced the config loader stub (no parsing yet) to restore flow.
- **Stage 7:** Restored full installer bootstrap with hooks, mode banners, and serial markers.

All seven stages passed across the CI suite and restored deterministic init execution under QEMU.
