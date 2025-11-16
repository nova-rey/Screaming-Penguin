# Screaming Penguin — Debian Rootfs Build Guide

This document describes how Screaming Penguin constructs a reproducible Debian root filesystem tarball for use by the installer. The rootfs tarball is placed on the writable `/config` partition of the USB media and later extracted onto the target disk during installation.

---

## Overview

Phase 4 introduces a safe, deterministic rootfs builder that operates entirely within the repository filesystem structure using tools such as `debootstrap` or `mmdebstrap`. The builder does **not** modify the host system, does **not** install packages globally, and does **not** touch real block devices.

All work occurs under:

- `build/rootfs-<suite>-<arch>/`  
- `dist/debian-rootfs-<suite>-<arch>.tar.gz`

The installer expects a rootfs tarball at:

/config/rootfs/debian-rootfs.tar.gz

The builder will generate a versioned tarball under `dist/` and may optionally copy or symlink it to the canonical `/config` path depending on project policy.

---

## Default Configuration (v1)

- **Suite:** Debian Bookworm (stable)  
- **Architecture:** amd64  
- **Mirror:** Debian default mirror (overridable later)  
- **Packages:** Minimal base system (equivalent to standard debootstrap minbase)

These defaults ensure predictable builds and stable CI behavior.

---

## Build Pipeline (Conceptual)

1. Create an isolated build directory, e.g.:  
   `build/rootfs-bookworm-amd64/`

2. Run the Debian bootstrap tool:  
   - `debootstrap bookworm <build-dir>`  
   or  
   - `mmdebstrap --variant=minbase bookworm <build-dir>`

3. Apply minimal sanitization:
   - Lock the root password inside the rootfs.
   - Ensure a generic hostname exists.
   - Ensure `/etc/os-release` is valid.

4. Archive the result:  
   `dist/debian-rootfs-bookworm-amd64.tar.gz`

5. Optionally copy/symlink the final tarball to:  
   `config/rootfs/debian-rootfs.tar.gz`

---

## Safety Guarantees

- All filesystem operations are restricted to `build/` and `dist/`.
- The builder must never assume privilege beyond local directory ownership.
- No destructive commands (e.g., `mkfs`, `parted`, `grub-install`) may appear in this phase.
- Any `chroot` must point only to the temporary rootfs directory produced by the builder.

---

## Future Enhancements

Later phases may add:

- Additional suites (Trixie, Sid)  
- Alternate profiles (server-min, desktop-min)  
- Cached package layers  
- Rootfs CI pipelines (optional)

Phase 4 intentionally keeps the scope narrow to ensure stability and reproducibility.
