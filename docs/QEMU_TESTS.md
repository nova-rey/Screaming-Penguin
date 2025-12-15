# Screaming Penguin — QEMU Test Harness & Acceptance Tests (Phase 6)

This document describes the design of the QEMU-based test harness and the
initial v1 acceptance test matrix for Screaming Penguin.

Phase 6 focuses purely on testing and verification. The installer runtime and
rootfs builder behavior are defined in earlier phases and are not modified
here.

---

## 1. Objectives

The QEMU test harness must:

1. Verify that Screaming Penguin can install a Debian Bookworm (amd64) system
   onto a virtual disk using a configuration file on the `/config` partition.
2. Confirm that the installed system can boot in QEMU and present basic
   expected indicators (e.g., hostname).
3. Operate entirely on repository-local artifacts and files:
   - `dist/` for the installer image and rootfs tarball
   - `build/` for temporary disk images and logs
   - `tests/` and `config/` for harness scripts and configs
4. Avoid any interaction with real host block devices.

---

## 2. Harness Architecture

The harness is conceptually split into two phases:

1. **Install Phase**
   - Use `dist/screaming-penguin.img` as the bootable installer image.
   - Create a blank virtual disk image, e.g. `build/qemu-target.img`.
   - Provide a `/config` tree to the installer environment containing:
     - `installer-config.yml` (QEMU-specific config)
     - `rootfs/debian-rootfs.tar.gz` (rootfs tarball produced by Phase 4).
   - Launch QEMU with:
     - the installer image as the boot device,
     - the blank disk as the target disk,
     - a mechanism for exposing `/config` to the initramfs.
   - Allow the installer to run non-interactively until completion or timeout.
   - Capture console output and write it to, e.g.:
     - `build/qemu-install.log`.

2. **Post-Install Boot Phase**
   - Re-launch QEMU, this time booting directly from the installed disk image:
     - `build/qemu-target.img` as the primary boot device.
   - Capture console output, e.g.:
     - `build/qemu-installed-boot.log`.
   - Verify that:
     - GRUB starts.
     - Debian boots.
     - The configured hostname appears in the console output or login banner.

The implementation details (exact QEMU command-line flags, disk formats,
and configuration injection mechanism) are handled in Phase 6 Prompt B.

---

## 3. Acceptance Test Matrix (v1)

The following scenarios define the initial acceptance coverage for v1.

### Case 1 — Happy Path Basic Install

**Configuration:**

- Single virtual disk target (e.g. `/dev/vda` inside the guest).
- SSH enabled.
- At least one `ssh.authorized_keys` entry.
- User:
  - name: non-empty string
  - sudo: `true`

**Expected result:**

- Installer reaches FINISH with status `ok`.
- `build/qemu-install.log` shows:
  - State transitions BOOT_INIT → LOAD_CONFIG → PLAN_INSTALL → CONFIRM_INSTALL → EXECUTE_INSTALL → FINISH.
- `build/qemu-installed-boot.log` shows:
  - GRUB load.
  - Debian boot messages.
  - Hostname matching `system.hostname` from the config.

### Case 2 — SSH Disabled, Password Required

**Configuration:**

- SSH disabled (`ssh.enable: false`).
- `user.password_hash` set.
- User name non-empty.

**Expected result:**

- Installer accepts configuration and completes EXECUTE_INSTALL successfully.
- Installed system boots in QEMU.
- No requirement for SSH keys in this scenario.

### Case 3 — Safety Failure: Wrong ERASE Word

**Configuration:**

- `safety.require_erase_word: true`.
- Harness simulates incorrect user input for the ERASE confirmation.

**Expected result:**

- Installer aborts in the CONFIRM_INSTALL state.
- `build/qemu-install.log` indicates ERASE confirmation mismatch.
- No partitioning or filesystem operations are performed on the virtual target disk
  (from the harness perspective, this typically means no successful disk apply
  step and no filesystems created).

Future phases may add additional cases (e.g., alternate users, additional
validation conditions) without changing the core harness structure defined here.

---

## 4. File Layout (Planned)

Phase 6 will introduce the following locations:

- `tests/harness/`
  - Shell scripts or helper tools for:
    - QEMU install runs
    - Post-install boot runs

- `config/installer-config.qemu-basic.yml`
  - Example configuration for the happy-path QEMU install scenario.

- `build/`
  - Scratch space for:
    - `qemu-target.img`
    - `qemu-install.log`
    - `qemu-installed-boot.log`

Implementation of these scripts and example configs occurs in Phase 6 Prompt B.

---

## 5. CI Integration (Preview)

Phase 6 defines the design for QEMU-based tests; CI integration is handled by
a later prompt for this phase.

The expected CI approach is:

- A GitHub Actions workflow that can:
  - Be triggered manually (`workflow_dispatch`).
  - Optionally run on a schedule (e.g., nightly or weekly).
- Run the QEMU test harness for at least the happy-path scenario.
- Archive QEMU logs as CI artifacts for inspection.

Per-PR gating on full QEMU runs is considered out of scope for v1 due to
runtime and resource constraints.

## 6. Implementation Notes (Phase 6)

The primary harness entrypoint is:

- `tests/harness/qemu-acceptance.sh`

This script:

1. Verifies that:
   - `dist/screaming-penguin.img` exists (built by `make img`).
   - `dist/debian-rootfs-bookworm-amd64.tar.gz` exists (built by `make rootfs`).
   - `config/installer-config.qemu-basic.yml` exists.

2. Creates or reuses a virtual target disk image:
   - `build/qemu-target.img` (qcow2, e.g. 20G).

3. Attaches the installer image as a loop device and updates the internal
   `/config` partition with:
   - `installer-config.yml` from `config/installer-config.qemu-basic.yml`
   - `rootfs/debian-rootfs.tar.gz` copied from the rootfs tarball in `dist/`.

4. Runs QEMU in two phases:
   - **Install phase:** boots the installer image, using the qcow2 disk as the
     target, and captures console output to `build/qemu-install.log`.
   - **Post-install boot phase:** boots from the installed target disk and
     captures console output to `build/qemu-installed-boot.log`.

5. Performs basic log checks:
   - Confirms that the installer reaches the FINISH state and reports a
     successful installation.
   - Confirms that the configured hostname (from the QEMU example config)
     appears in the post-install boot log.

Developers can run the end-to-end happy-path acceptance scenario locally with:

```bash
make img
make rootfs
make qemu-acceptance

The harness relies on QEMU (qemu-system-x86_64), qemu-img, and loop device
support. It may prompt for sudo in order to mount the /config partition of
the installer image. All modifications are confined to the repository’s
build/ and dist/ directories and do not touch real host block devices.
