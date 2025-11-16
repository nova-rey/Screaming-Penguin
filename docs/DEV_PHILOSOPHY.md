# Screaming Penguin — Development Philosophy

This document defines the guiding principles for developing and maintaining Screaming Penguin.

## 1. Safety First

- Destructive operations must always be **explicit**, **audited**, and **guarded**.
- The installer must never silently guess a target disk.
- Protection against wiping the installer USB is mandatory.
- It is acceptable to refuse to run rather than risk ambiguous behavior.

## 2. Headless-First Design

- Assume no graphical environment and limited or no human interaction.
- Console output, logs, and optional audio cues are the primary feedback channels.
- Any interactive prompts must be:
  - Minimal.
  - Clear and unambiguous.
  - Optional where configuration allows.

## 3. Determinism and Reproducibility

- Given the same image, config, and hardware layout, the installer should behave identically.
- Build processes (ISO and rootfs) must be documented and repeatable.
- Avoid hidden dependencies on host environment state.

## 4. Minimalism Over Complexity

- Prefer **simple, well-understood tools** (BusyBox, debootstrap, GRUB) over complex stacks.
- Use shell scripts for glue and orchestration.
- Introduce higher-level dependencies (e.g., Python) only when clearly justified.

## 5. Documentation as a First-Class Artifact

- Every significant behavior must be captured in `docs/`.
- Design documents should match the implementation:
  - When behavior changes, update docs in the same change set.
- Example configurations and schemas should be kept in sync with runtime expectations.

## 6. Clear Configuration Surface

- The YAML configuration schema should be:
  - Explicit.
  - Versioned.
  - Validated early.
- Avoid “magic defaults” that guess critical behavior.
- If a configuration is incomplete or unsafe, fail early with a clear error.

## 7. Additive History

- Project history lives in `docs/SP_BIBLE.md`.
- The Bible is **additive only**:
  - New entries are appended.
  - Existing entries are not rewritten.
- Each meaningful change set should correspond to a short Bible entry.

## 8. Testability

- Design the runtime with QEMU-based testing in mind.
- Critical states (e.g., PLAN_INSTALL, EXECUTE_INSTALL) should emit logs that tests can assert on.
- When in doubt, prefer slightly more logging to aid debugging.

## 9. Portability Within Scope

- v0 targets Debian and x86_64 only, but avoid unnecessary assumptions that would block future extension.
- Keep installer logic and distro-specific details separated where practical.

## 10. Boring When It Matters

- For components like partitioning, filesystem creation, and bootloader installation, prioritize:
  - Predictability.
  - Readability.
  - Use of standard patterns.
- “Boring” is a feature for low-level system installers.

These principles are intended to remain stable over time. If the project’s scope changes radically, update this document consciously rather than allowing implicit drift.
