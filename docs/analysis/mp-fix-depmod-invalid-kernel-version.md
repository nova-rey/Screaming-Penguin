# MP: Skip depmod when kernel version override is invalid

## Observed behavior
- `tools/build_installer_initramfs.sh` unconditionally runs `depmod -b <initrd> ${KERNEL_VERSION}` once the kernel version is determined (override > runtime > symlink).
- `SP_INSTALLER_KERNEL_VERSION` is set to `test-kernel` during the installer initrd smoke test, which causes `depmod` to exit with `Bad version passed` when `set -e` is in effect, aborting the build script and failing the test.

## Desired behavior
- Production builds that detect a real kernel version should still run `depmod` and fail loudly if it fails (preserving the existing strictness).
- CI/external runs that rely on a fake override string should skip `depmod` safely when the override clearly isn't a real kernel version, log a warning, and continue.

## Decision
Use a lightweight version gate: only run `depmod` when `SP_INSTALLER_KERNEL_VERSION` (or whatever version was detected) begins with a digit (`^[0-9]`). Fake overrides such as `test-kernel` get logged with a warning and skip `depmod`. This keeps real builds strict while letting the CI harness succeed. Subsequent commits will document the new behavior in `docs/analysis/mp-fix-depmod-invalid-kernel-version.md` and adjust the test expectations accordingly.
