# Screaming Penguin — Continuous Integration Overview

This document describes the Continuous Integration (CI) strategy for Screaming Penguin.

The CI pipeline is designed to provide safety and feedback for a shell-heavy, installer-focused project without ever touching real block devices on the CI runner. All destructive operations are restricted to image files and loop devices created from those files.

CI is implemented using GitHub Actions.

---

## Goals

The CI pipeline aims to answer the following questions on every push and pull request:

1. **Sanity:** Does the repository structure and shell code pass basic static checks?
2. **Build:** Can the Screaming Penguin installer image be built cleanly on a fresh host?
3. **Boot:** Does the built image boot under QEMU far enough to reach the Phase 2 installer skeleton and log activity?

Future expansions may include full end-to-end installation tests in a QEMU VM, but these are not required for the initial v1 scope.

---

## Current CI Jobs

### 1. Lint — ShellCheck

The CI pipeline runs ShellCheck on all tracked `*.sh` files:

- `tools/*.sh`
- `installer/initramfs/**/*.sh`
- `installer/runtime/**/*.sh`
- `tests/harness/*.sh`
- `ci/*.sh`

This provides early detection of:

- Quoting issues
- Unset variable use
- Suspicious patterns (`rm -rf`, globbing, etc.)
- Other common shell errors

### 2. Build — Installer Image

The CI pipeline runs:

```sh
make iso

This calls the Screaming Penguin image builder (e.g. tools/make_installer_iso.sh) and is expected to:
•Create a raw disk image at dist/screaming-penguin.img.
•Partition the image with GPT into:
•Partition 1 (boot environment).
•Partition 2 (FAT32 /config).
•Format the /config partition as FAT32.
•Populate the boot partition with at least a minimal boot tree, including:
•Kernel placeholder.
•Initramfs tree.
•Bootloader configuration placeholders.

All actions must operate only on files under the repository (build/, dist/) and loop devices mapped from those files.

3. QEMU Smoke Boot

After building the image, CI runs a QEMU-based smoke test using:
•ci/qemu_smoke_ci.sh

The smoke test:
•Boots the built image in QEMU (BIOS mode).
•Captures serial output.
•Looks for evidence that the Phase 2 installer skeleton is running (e.g., log lines emitted by sp-installer).
•Uses a timeout to ensure CI does not hang indefinitely.

The smoke test does not currently assert full installer functionality; it verifies that:
•The image is structurally valid.
•The kernel and initramfs start.
•The Phase 2 state machine runs and logs without crashing.

---

## Safety Constraints

To keep CI safe and predictable:
•CI must never reference or operate on real block devices such as /dev/sdX or /dev/nvme0n1.
•All destructive operations must be confined to:
•Raw image files under dist/.
•Temporary directories under build/.
•Loop devices created from those image files within the CI job.
•CI should not attempt to run full installation flows that write to persistent devices on the CI runner.

---

## Future Work (Post-v1)

After the v1 installer is stable and the rootfs builder and installation path are solid, CI may be extended to include:
•Full QEMU-based installation tests:
•Boot installer in a QEMU VM.
•Attach a blank virtual disk as the target.
•Provide a known-good installer-config.yml and rootfs tarball.
•Run a full installation.
•Reboot QEMU from the installed disk and verify basic system properties (hostname, login, etc.).

These full integration tests would likely run on a reduced schedule (e.g., nightly or on main-branch merges) rather than every pull request, to keep CI duration reasonable.

---

## Summary

The Screaming Penguin CI pipeline provides:
•Static safety via ShellCheck.
•Build validation via make iso.
•Runtime sanity via QEMU smoke boot.

This combination helps prevent regressions in the installer image and catches errors early, while respecting the unique constraints of an installer-focused repository.

---

## Rootfs CI Harness (Phase 4 Optional)

A separate CI workflow validates the Debian rootfs builder:

- **Workflow file:** `.github/workflows/rootfs-ci.yml`
- **Triggers:**
  - Manual (`workflow_dispatch`)
  - Weekly cron schedule (`0 3 * * 0`)

The rootfs CI job:

1. Installs `debootstrap` and related tools on the CI runner.
2. Runs `make rootfs` to build the Debian Bookworm (amd64) root filesystem.
3. Verifies that the expected tarball exists and is non-empty:
   - `dist/debian-rootfs-bookworm-amd64.tar.gz`
4. Inspects the tarball contents and asserts the presence of:
   - `etc/os-release`
   - `bin/sh`

This workflow does not run on every push or pull request to avoid
overloading Debian mirrors and to keep PR latency low. It is intended
for periodic validation of the rootfs builder and can be triggered
manually when needed.

## Installer Runtime CI (Phase 5)

The installer runtime shell scripts are validated by a dedicated CI workflow:

- **Workflow file:** `.github/workflows/installer-runtime-ci.yml`
- **Triggers:**
  - On push and pull request affecting `installer/runtime/**`
  - Manual (`workflow_dispatch`)

The job performs a POSIX shell syntax check using `sh -n` over all
`installer/runtime/*.sh` files. This ensures that the installer orchestration
and helper scripts remain syntactically valid without executing them or
touching any block devices.

This workflow complements the main image build and QEMU smoke tests by
providing a fast, low-risk verification path focused specifically on the
installer runtime.

## QEMU Acceptance CI (Phase 6)

A dedicated QEMU acceptance workflow exercises the Screaming Penguin
installer end-to-end on a virtual disk:

- **Workflow file:** `.github/workflows/qemu-acceptance-ci.yml`
- **Triggers:**
  - Manual (`workflow_dispatch`)
  - Weekly cron schedule (`0 4 * * 0`)

The QEMU acceptance job:

1. Installs QEMU and required tools (`qemu-system-x86`, `qemu-utils`, and
   supporting utilities).
2. Builds the Screaming Penguin installer image via `make iso`.
3. Builds the Debian Bookworm rootfs via `make rootfs`.
4. Runs the QEMU acceptance harness using `make qemu-acceptance`, which:
   - Prepares a virtual target disk image under `build/`.
   - Populates the `/config` partition inside the installer image with the
     QEMU example config and rootfs tarball.
   - Boots the installer image in QEMU and runs a full install to the virtual
     disk.
   - Boots from the installed disk and captures console logs.
5. Uploads the QEMU logs (`build/qemu-install.log` and
   `build/qemu-installed-boot.log`) as CI artifacts.

This workflow focuses on the happy-path acceptance scenario and is intended
for periodic validation rather than per-PR gating, due to runtime and
resource considerations.


## Dist-Release CI (Phase 7)

The dist-release CI workflow validates that the release packaging process
continues to work as expected.

- **Workflow file:** `.github/workflows/dist-release-ci.yml`
- **Triggers:**
  - Manual (`workflow_dispatch`)
  - Weekly cron schedule (`30 4 * * 0`)

The dist-release job:

1. Installs the required build tools and dependencies (including QEMU
   utilities and debootstrap).
2. Runs `make dist-release` using sudo, which:
   - Builds the Screaming Penguin installer image (if needed).
   - Builds the Debian Bookworm rootfs tarball (if needed).
   - Assembles the v1.0.0 release bundle under `dist/release/`, including:
     - Installer image
     - Rootfs tarball
     - Example configs
     - `SHA256SUMS`
3. Lists the contents of `dist/` and `dist/release/` for visibility.
4. Prints the `SHA256SUMS` file if present.
5. Uploads the entire `dist/release` directory as a CI artifact.

This workflow is designed as a packaging dry run and is not used as a strict
per-PR gate. It provides periodic confidence that the release bundle remains
buildable from the main branch.

## v1 Release Readiness Checklist (Phase 8)

This checklist describes the minimal conditions that must be satisfied before
cutting a v1.0.0 release of Screaming Penguin:

- `make dist-release` successfully assembles a complete release bundle
- ISO builds successfully and boots under QEMU
- Rootfs tarball builds successfully
- All user-facing documentation is accurate and free of placeholder language
- README reflects the final state of the project
- Example configs are valid and tested under QEMU
- Release notes for v1.0.0 are finalized
- CI workflows (main + dist-release) run without errors
- Logs are correctly written to `/config/logs/`
- No temporary or transitional references to Phases 5–7 remain in docs
## Release Flow Summary (v1.0.0)

For Screaming Penguin v1.0.0, the recommended release flow is:

1. Ensure main CI is green on the target release commit.
2. Optionally run:
   - QEMU acceptance workflow
   - Dist-release CI workflow
3. Build the local release bundle with `make dist-release`.
4. Verify checksums in `dist/release/SHA256SUMS`.
5. Tag the release commit (e.g. `v1.0.0`) and push the tag.
6. Create a GitHub Release using:
   - Release artifacts from `dist/release/`
   - Content from `docs/RELEASE_NOTES_v1.0.0.md`.

CI does not currently publish releases automatically; the release step is
intentionally human-driven.


⸻
