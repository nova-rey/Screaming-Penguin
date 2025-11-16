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

## Entry 003 — Phase 3 Image Builder Planning

**Date:** 2025-11-16

Phase 3 was formally defined as the ISO / USB image builder milestone for Screaming Penguin. The roadmap and ISO build plan were updated to describe a GPT-based raw image with a bootable read-only partition and a writable FAT32 `/config` partition. This phase is explicitly limited to producing the installer image itself, leaving target disk installation and configuration logic to later milestones.

## Entry 004 — Phase 3 Image Builder Implementation

**Date:** 2025-11-16

Implemented the Screaming Penguin raw image builder (Phase 3). Added tools/make_installer_iso.sh, Makefile build targets, and the QEMU smoke test harness. The builder safely creates a GPT-based image with a bootable partition and a writable FAT32 /config partition entirely within local files. No destructive operations target real block devices. The resulting image boots in QEMU and reaches the Phase 2 installer skeleton.

## Entry 005 — CI Pipeline Established

**Date:** 2025-11-16

A GitHub Actions CI pipeline was added for Screaming Penguin. The workflow runs ShellCheck on all shell scripts, builds the installer image via `make iso`, and performs a QEMU-based smoke test using the generated raw image. The QEMU smoke test boots the image in a virtual machine, captures logs, and verifies that the Phase 2 installer skeleton runs through its primary states (including BOOT_INIT and FINISH). All CI operations are confined to repository files, build artifacts, and loop devices created from the image; no real block devices are ever touched.

## Entry 006 — Phase 4 Design Kickoff (Rootfs Builder)

**Date:** 2025-11-16

Defined the full design for Phase 4 of Screaming Penguin: the Debian rootfs builder. Added ROOTFS_BUILD.md with a detailed description of build constraints, default suite (Debian Bookworm), architecture (amd64), safety guarantees, and expected artifact layout under build/ and dist/. Updated DEV_ROADMAP.md and CONFIG_SCHEMA.md accordingly. No scripts or Makefile changes were introduced in this checkpoint.
## Entry 007 — Phase 4 Rootfs Builder Implemented

**Date:** 2025-11-16

Implemented the Debian rootfs builder (Phase 4). Added the executable script
`tools/build_debian_rootfs.sh`, the `make rootfs` target, and updated gitignore
accordingly. The builder creates a minimal Debian Bookworm (amd64) filesystem
under build/ and packages it into a versioned tarball under dist/. Safety
constraints are enforced: no host system modification and no real block device
access. Documentation updated to describe the implemented pipeline.


## Entry 008 — Rootfs CI Harness Added

**Date:** 2025-11-16

Added a dedicated GitHub Actions workflow for the Debian rootfs builder.
The `rootfs-ci` workflow can be triggered manually or on a weekly schedule.
It installs debootstrap, runs `make rootfs` to produce
`dist/debian-rootfs-bookworm-amd64.tar.gz`, and verifies that the tarball
exists, is non-empty, and contains key files such as etc/os-release and bin/sh.
This CI job does not run on every push or pull request and is intended as a
periodic validation of the rootfs bakery.

## Entry 009 — Phase 5 Installer Runtime Kickoff

**Date:** 2025-11-16

Began Phase 5 by defining the full installer runtime architecture, state
machine, safety model, logging requirements, and chroot configuration
contract. Added INSTALLER_RUNTIME.md, updated DEV_ROADMAP.md and
CONFIG_SCHEMA.md, and created placeholder directories for the future
runtime scripts. No executable code was introduced in this checkpoint.

## Entry 010 — Phase 5 Installer Runtime Implemented

**Date:** 2025-11-16

Replaced the Phase 2 skeleton runtime with a functional Phase 5 installer
core. Implemented logging, configuration loading and validation using yq,
safety checks for target disk and rootfs, disk planning and application with
GPT + EFI + ext4, rootfs extraction, chroot-based system configuration
(hostname, locale, timezone, user, SSH, GRUB), and the full installer state
machine in sp-installer. Audio hooks were implemented as best-effort helpers
for startup and completion. Initramfs wiring and CI coverage remain for later
checkpoints.

## Entry 011 — Phase 5 Installer CI and Polish

**Date:** 2025-11-16

Completed Phase 5 by adding CI coverage for the installer runtime scripts.
Introduced a dedicated GitHub Actions workflow (`installer-runtime-ci.yml`)
that runs `sh -n` over all installer/runtime shell scripts on relevant pushes
and pull requests. Updated CI_OVERVIEW.md to document this workflow. No
runtime behavior changes were made in this checkpoint; it strictly improves
confidence in the installer shell code.

## Entry 012 — Phase 6 QEMU Harness Kickoff

**Date:** 2025-11-16

Started Phase 6 by defining the QEMU test harness architecture and the initial
v1 acceptance test matrix. Added QEMU_TESTS.md describing the two-phase QEMU
flow (install and post-install boot), the planned harness file layout, and
the three core acceptance cases (happy path, SSH-disabled with password, and
ERASE-word safety failure). Updated DEV_ROADMAP.md and created a harness
placeholder under tests/harness/. No executable code or CI workflows were
introduced in this checkpoint.

```markdown
## Entry 013 — Phase 6 QEMU Harness Implemented

**Date:** 2025-11-16

Implemented the initial QEMU acceptance harness. Added
`tests/harness/qemu-acceptance.sh` to exercise the installer end-to-end in
QEMU using a virtual target disk and a QEMU-specific installer-config. The
harness populates the /config partition inside the installer image with the
rootfs tarball and config, runs an install phase, then boots the installed
system and checks logs for success markers (FINISH state, successful install,
expected hostname). Added `config/installer-config.qemu-basic.yml` as a
known-good example config and wired everything through a `make qemu-acceptance`
target. Updated QEMU_TESTS.md with implementation notes. CI integration for
these tests will be handled in a later checkpoint.
```


## Entry 014 — Phase 6 QEMU CI Integrated

**Date:** 2025-11-16

Completed Phase 6 by wiring the QEMU acceptance harness into CI. Added a
dedicated GitHub Actions workflow (`qemu-acceptance-ci.yml`) that installs
QEMU, builds the Screaming Penguin installer image and Debian Bookworm
rootfs, runs `make qemu-acceptance`, and uploads the QEMU install and
post-install boot logs as artifacts. Updated CI_OVERVIEW.md to document the
new workflow and clarified that it is triggered manually and on a weekly
schedule rather than on every push or pull request. No installer or rootfs
behavior changes were made in this checkpoint.


## Entry 015 — Phase 7 User Docs & Packaging Kickoff

**Date:** 2025-11-16

Started Phase 7 by defining the user-facing documentation structure, release
artifact layout, and versioning approach for Screaming Penguin v1.0.0. Added
skeletons for GETTING_STARTED.md, INSTALLER_USAGE.md, CONFIG_REFERENCE.md,
SAFETY.md, TROUBLESHOOTING.md, and RELEASE_NOTES_v1.0.0.md. Updated
DEV_ROADMAP.md to reflect Phase 7 goals and added a README section pointing to
the new documentation. No runtime, packaging, or CI behavior was added in this
checkpoint.
