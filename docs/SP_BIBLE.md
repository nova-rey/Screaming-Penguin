This file is an additive history log. Future agents must only append entries; they must not edit or delete existing content.

# Screaming Penguin Bible

This document is the long-term narrative log for Screaming Penguin development.

**Rules:**

- This file is **additive only**.
- Do **not** rewrite, reorder, or delete existing entries.
- Each meaningful pull request or major change should add a short entry at the end:
  - Date (ISO format).
  - Short title.
  - 2–5 sentences describing what changed and why.

---

## Entry 000 — Project Kickoff and v0 Definition

**Date:** 2025-11-15

Screaming Penguin was defined as a config-driven, headless-friendly Debian installer delivered as a USB image. The v0 scope focuses on x86_64, full-disk wipe installs, and a two-partition USB layout with a read-only boot environment and a writable `/config` partition. The design emphasizes safety (no disk guessing, USB protection, erase word confirmation) and repeatability via a prebuilt rootfs tarball. Initial documentation (design, roadmap, philosophy, Bible, and agent entrypoint) was specified to anchor all future development steps.

## Entry 001 — Phase 2 Documentation Framework

**Date:** 2025-11-16

Phase 2 was formally defined and documented. This phase establishes the initramfs structure, runtime skeleton, and state machine framework for the Screaming Penguin installer. No destructive actions are implemented at this stage; the system must only log state transitions and complete a dry run inside QEMU. This documentation provides the structural contract required before implementing any real installation logic.

## Entry 002 — Phase 2 Skeleton Runtime and Initramfs

**Date:** 2025-11-16

The initramfs and runtime skeleton for Screaming Penguin were created, including the non-destructive installer state machine. Initramfs hooks, runtime modules, and logging libraries were added to support a dry-run installer that logs each state transition without touching disks. This establishes the structural foundation required for later phases to add real configuration, safety checks, and installation behavior.
