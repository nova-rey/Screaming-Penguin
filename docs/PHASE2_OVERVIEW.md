# Screaming Penguin — Phase 2 Overview  
## Initramfs & Runtime Skeleton

Phase 2 defines the structural foundation of the Screaming Penguin installer.  
No destructive behavior is implemented in this phase.  
The objective is to create a complete but non-functional framework that boots, logs, and executes a dry run of the installer lifecycle.

---

## Phase 2 Objectives

### 1. Initramfs Structure
A minimal initramfs environment based on BusyBox, containing:
- `installer/initramfs/init` — first script executed after kernel handoff.
- `installer/initramfs/hooks/` — modular early-stage scripts for:
  - Mounting `/config`
  - Initializing optional audio support
  - Launching the runtime orchestrator

These hooks must only contain placeholder logic and logging.

---

### 2. Runtime Skeleton

The runtime directory under `installer/runtime/` must contain structural placeholders for all modules required in v1:

- `sp-installer` — orchestrator and state machine entrypoint.
- `sp-disk-plan.sh` — future module for partition planning.
- `sp-disk-apply.sh` — future module for disk partitioning and filesystem operations.
- `sp-rootfs-apply.sh` — future module for rootfs extraction.
- `sp-chroot-setup.sh` — future module for post-install configuration inside chroot.
- `sp-audio.sh` — future helper for audio cues.
- `lib/logging.sh`, `lib/config_validation.sh`, `lib/safety_checks.sh` — future shared libraries.

Every script must:
- Contain a shebang.
- Contain a header comment describing the intended future role.
- Log entry if executed.
- Contain no real logic, no partitioning, no file system commands, no GRUB operations.

---

### 3. State Machine Skeleton

Implement a non-destructive state machine:

BOOT_INIT → LOAD_CONFIG → PLAN_INSTALL → CONFIRM_INSTALL → EXECUTE_INSTALL → FINISH

For Phase 2:
- Each state logs “Entered <STATE>”.
- EXECUTE_INSTALL returns immediately with no operations.
- The installer must terminate safely.

---

### 4. QEMU Testability

By the end of Phase 2:
- Booting the image in QEMU should reach the installer runtime.
- Logs should show sequential entry into:
  - BOOT_INIT  
  - LOAD_CONFIG  
  - PLAN_INSTALL  
  - CONFIRM_INSTALL  
  - EXECUTE_INSTALL  
  - FINISH
- Installer must abort safely after logging FINISH.

---

## Out of Scope for Phase 2

Phase 2 *must not* implement:
- Partitioning
- Filesystem creation
- Disk wiping
- Rootfs extraction
- GRUB installation
- User configuration
- Actual YAML parsing
- Safety checks
- Any destructive operations

Phase 2 builds the body. Later phases bring it to life.
