# Screaming Penguin — ISO / USB Image Build Plan

This document describes the **conceptual build pipeline** for producing the Screaming Penguin installer image.  
Phase 3 focuses on defining the process and outputs; later milestones will implement the actual build script.

The end goal is a bootable, two-partition disk image that can be written to a USB device and used to run the Screaming Penguin installer.

---

## 1. Target Artifact

The build process produces a raw disk image file, for example:

- `dist/screaming-penguin.img`

This image is intended to be written to a USB device on a host system using tools such as:

- `dd` / `pv`
- `cp` (on some systems)
- Dedicated GUI imaging tools (e.g., `balenaEtcher`, `Rufus`) that support raw images.

The image itself will contain a GPT partition table with:

- Partition 1 (p1): bootable read-only environment.
- Partition 2 (p2): writable `/config` partition (FAT32).

---

## 2. Partition Layout

### 2.1 GPT Table

The image uses a **GPT** partition table to support both BIOS and UEFI firmware environments.

### 2.2 Partition 1 — Boot Environment

- Purpose: provide a minimal Linux environment to run the Screaming Penguin initramfs and runtime.
- Contents:
  - Linux kernel.
  - Initramfs containing:
    - BusyBox.
    - `installer/initramfs/` scripts.
    - `installer/runtime/` scripts.
  - Bootloader (GRUB or equivalent) and configuration.
- Filesystem / format:
  - May be implemented as:
    - ISO9660 with El Torito boot entries, and/or
    - squashfs or other read-only representation, depending on the chosen tooling.
- Requirements:
  - Must be bootable in both BIOS and UEFI modes when written to a USB device.
  - Must ensure that the initramfs can locate and (in later phases) mount the `/config` partition.

### 2.3 Partition 2 — `/config` (FAT32)

- Filesystem: FAT32.
- Label: recommended `SP_CONFIG` (or similar).
- Runtime mount point: `/config`.
- Intended contents at runtime:
  - `installer-config.yml`
  - `rootfs/debian-rootfs.tar.gz`
  - `logs/` (written by the installer)
- Shipping image expectations:
  - The built image may include an empty filesystem with the required directory structure (e.g. `rootfs/`, `logs/`).
  - Users will populate configs and rootfs tarballs on this partition after imaging.

---

## 3. Host Build Environment (Conceptual)

The build process is expected to run on a Linux host with tools such as:

- `dd` or `truncate` — to create the raw image file.
- `parted` or `sgdisk` — to partition the image.
- `losetup` / `kpartx` — to map image partitions to loop devices.
- `mkfs.vfat` — to format the FAT32 `/config` partition.
- `grub-mkrescue` and/or `xorriso` — to build bootable content for the boot partition, depending on the chosen bootloader strategy.
- Core utilities (`cp`, `mkdir`, `mount`, `umount`).

Exact implementation details will be determined in a later milestone, but the above defines the expected toolchain.

---

## 4. High-Level Build Steps (Planned)

These steps describe the intended pipeline for `tools/make_installer_iso.sh` or equivalent.

1. **Prepare Build Directories**
   - Create a `build/` directory for intermediate artifacts.
   - Create a `dist/` directory for final artifacts.

2. **Create Raw Image File**
   - Use `truncate` or `dd` to create a zero-filled file of a fixed size (e.g., 2–4 GiB).
   - This file represents the future installer disk image.

3. **Partition the Image**
   - Use `parted` or `sgdisk` to:
     - Create a GPT partition table.
     - Create partition 1 (p1) for the boot environment.
     - Create partition 2 (p2) for the FAT32 `/config` partition.
   - Use `losetup` and `kpartx` (or equivalent) to map the image’s partitions to loop devices for formatting and population.

4. **Populate Partition 1 (Boot Environment)**
   - Assemble a boot tree containing:
     - Kernel image.
     - Initramfs image (including `installer/initramfs` and `installer/runtime`).
     - Bootloader configuration files.
   - Use `grub-mkrescue` and/or `xorriso` to create ISO9660- or El Torito-compatible content as required by the chosen bootloader approach.
   - Copy or embed the resulting bootable content into partition 1 of the raw image.

5. **Format and Populate Partition 2 (`/config`)**
   - Format p2 as FAT32 using `mkfs.vfat`.
   - Optionally create the following directories on p2:
     - `/config/rootfs/`
     - `/config/logs/`
   - Do not include user-specific `installer-config.yml` or rootfs tarballs in the shipped image; these are expected to be added by the user.

6. **Finalize and Sync**
   - Ensure all data is flushed to the image file.
   - Detach loop devices and clean up temporary mappings.
   - Place the final image at:
     - `dist/screaming-penguin.img`

---

## 5. Usage Expectations

Once implemented, the image build script (planned: `tools/make_installer_iso.sh`) will:

- Be invoked either directly or via a `Makefile` target (e.g. `make image` or `make iso`).
- Produce `dist/screaming-penguin.img` on a supported build host.
- Expect the user to:
  - Write the image to a USB device on their own system.
  - Mount the `/config` partition on that device.
  - Add:
    - `installer-config.yml`
    - `rootfs/debian-rootfs.tar.gz`
  - Boot a machine from the USB to run the installer.

---

## 6. Phase 3 Boundaries

Phase 3 is limited to:

- Defining and documenting the image build process.
- Implementing the image build script and related tooling (in later checkpoints).
- Ensuring the resulting image is suitable for booting the Screaming Penguin initramfs environment.

Phase 3 explicitly does **not**:

- Implement or change any logic that partitions or writes to target disks.
- Implement rootfs installation on target disks.
- Implement configuration parsing or safety checks beyond what exists in earlier phases.

These responsibilities belong to later milestones in the roadmap.
