# CI Workflows

## CI Smoke (PR + Push)

`CI Smoke` is the lightweight validation lane defined in `.github/workflows/ci.yml`.
It triggers on every push to `main`, `master`, `develop`, `**/feature/**`, and on
`pull_request` events so that authors see feedback quickly.

The job installs ShellCheck, Python tooling, and then runs `make ci-smoke`, which
executes a consistent sequence of fast, deterministic steps:

- `shellcheck tools/*.sh`
- `python3 -m compileall -q .`
- `pytest tests/installer/test_installer_media_bootability.py` — this test suite
  builds the installer `.img` in a short-lived workspace, validates the GPT
  layout, ensures FAT32 ESP contents (`/EFI/BOOT`, `grub.cfg`) are in place, and
  checks for the canonical kernel/initrd pair without ever booting the image.
- Optional `ruff` / `black --check` passes when configs are present.
- `make ci-smoke` now sets `PYTHONUNBUFFERED=1` and `CI_SMOKE_PYTEST_TIMEOUT_SECONDS` (default 600) so the entire pytest session is bounded and progress lines flush immediately.
- The job runs a fast collection-only pass before the bounded installer suite to fail fast on missing imports or deps.
- The installer suite is invoked with `-vv`, `--maxfail=1`, `--durations=25 --durations-min=0.5`, and `-o console_output_style=progress` so every progressing test name shows up in the logs — the last-emitted name is the one to inspect when the timeout fires.
- When `pytest-timeout` is available, `tools/ci_smoke.sh` also appends `--timeout=60 --timeout-method=thread` to kill wedged tests before the outer CI timeout.

With the ISO builder removed, this smoke lane no longer exercises any ISO logic
and focuses entirely on the canonical `.img` artifact.

## Manual & Periodic Workflows

The longer-running jobs that stay in the repo are:

- `installer-runtime-ci` — syntax checks over `installer/runtime/**/*.sh` (push,
  pull_request, manual).
- `rootfs-ci` — manual/weekly validation of the Debian rootfs builder (`make
  rootfs`).
- `qemu-acceptance-ci` — occupies the weekly schedule but now depends on the
  canonical `.img` (`make img`) before running `make qemu-acceptance`.
- `dist-release-ci` — manual/weekly packaging that assembles `.img`, the rootfs
  tarball, and example configs in `dist/release`.

The former `ci-iso-build` workflow has been removed, and the `make iso` / `make
ci-iso` targets now print a clear failure (see `Makefile` and
`tools/make_installer_iso.sh`). All ISO-specific logic in helpers (`tools/ci_iso.sh`
and `ci/qemu_smoke_ci.sh`) has been disabled or deleted. The canonical `.img`
path is the only supported media for PRs and default CI; any hybrid ISO work is
handled by the Ouroboros side project (see
`docs/analysis/sp-mp-prune-iso-analysis.md`).

## Local Commands

- `make ci-smoke` — Run the PR-friendly smoke suite locally so you know the
  checks that will run on GitHub Actions.
- `make img` — Builds the canonical installer `.img` using
  `tools/make_installer_img.sh` and the shared runtime artifacts.
- `make qemu-acceptance` — Exercises the full QEMU acceptance harness against
  `dist/screaming-penguin.img`.

The following commands now fail early with a deprecation message:

- `make iso`
- `make ci-iso`

If you have a compelling ISO requirement, use the Ouroboros side project instead
of this repository.

## Diagnosing ‘no disks found’ boots

The initramfs now logs kernel/module state and `/sys/block` contents before and
after the storage bootstrap. Look for `[SP-INSTALLER] sys_block_pre_modprobe=…`
and `[SP-INSTALLER] sys_block_post_modprobe=…` lines to see what the kernel
already knows about block devices independent of udev. When `/lib/modules/$(uname
-r)` is missing, you will also see `[SP-INSTALLER][FATAL] kernel-modules-missing
kernel=<release>`, and if `/sys/block` is still empty after the probe you get
`[SP-INSTALLER][FATAL] no-block-devices-after-storage-bootstrap` before the
installer drops into the rescue shell.
