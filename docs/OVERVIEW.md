# Screaming Penguin — Initramfs Recovery Overview

This document summarizes the initramfs failure that blocked QEMU boots and the recovery steps used to restore the installer pipeline.

---

## Root Cause Summary

- Kernel reliably reached **"Run /init as init process"** before failing.
- `/init` inside the initramfs was missing executable permissions and not launched under PID1, yielding `error -2` for **/init not found or not executable**.
- The kernel exhausted fallback init paths and panicked.
- QEMU-CI failures stemmed from the missing installer marker **"[SP-INSTALLER] init reached"**.
- Early initramfs directories and binaries existed, but the mkinitfs layout stripped the executable bit from `/init`.

## Remediation Snapshot

- Extracted the installer initramfs from the ISO to validate contents and permissions.
- Verified `/init` and `/bin/busybox` were present, then confirmed the wrong permissions and boot sequencing.
- Rebuilt a minimal initramfs with a stub init and BusyBox to prove the boot path under QEMU.
- Incrementally reconstructed the init flow across seven stages, restoring installer logic and serial markers.
- Stabilized QEMU-CI with preflight asset checks, serial log flushing, and mandatory installer markers.
