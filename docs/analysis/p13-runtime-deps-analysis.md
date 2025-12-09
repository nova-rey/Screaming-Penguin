# Phase 13 Runtime Dependencies Analysis

## Current Makefile target graph
- `img` simply invokes `tools/make_installer_img.sh`, which now requires `/dist/vmlinuz-installer` and `/dist/initrd-installer.img` (or the `build/runtime`/`build/initrd-installer.img` fallbacks) but does not trigger any runtime build.
- `iso` builds the runtime via `bash tools/build_runtime.sh` and then runs `tools/make_installer_iso.sh`, which builds the installer initramfs, stages `/boot/vmlinuz-installer` + `/boot/initrd-installer.img`, and copies those artifacts into `dist/`.
- `dist-release` depends on `img`, `iso`, and `rootfs` in that listed order, so it runs `img` before `iso` and therefore before the runtime artifacts exist.

## CI failure root cause
`make dist-release` runs `img` first, but `img` now fails because `tools/make_installer_img.sh` immediately checks for the installer kernel/initramfs. Since `iso` (and its runtime build) had not run yet, neither `dist/vmlinuz-installer` nor `build/initrd-installer.img` existed, so the Phase 13 `.img` builder prints `[SP-IMG] ERROR: Missing installer artifacts.` and CI aborts.

## New target graph
- Introduce a `installer-runtime` target that runs `tools/build_runtime.sh`, invokes `tools/build_installer_initramfs.sh`, copies the runtime kernel into `dist/vmlinuz-installer`, and mirrors the initrd into `build/initrd-installer.img` so both `.img` and `.iso` can find the artifacts.
- `img` depends on `installer-runtime` and continues to run `tools/make_installer_img.sh`, so the required kernel/initrd are guaranteed before partitioning begins.
- `iso` also depends on `installer-runtime` and then runs `tools/make_installer_iso.sh`, which still rebuilds the installer initramfs when needed but now can rely on the shared runtime output for the kernel/initrd copies that are part of the media.
- `dist-release` depends on `installer-runtime` (explicitly or implicitly via `img`/`iso`) so the runtime is always built before `.img`/`.iso` and the release assembly sees the correct artifacts in `dist/`.

## Installer-runtime responsibilities
1. Build the installer runtime kernel via `tools/build_runtime.sh`, producing `build/runtime/vmlinuz` (and its accompanying initrd) and copying the kernel into `dist/vmlinuz-installer` for downstream users.
2. Invoke `tools/build_installer_initramfs.sh` to emit `dist/initrd-installer.img` and copy that artifact to `build/initrd-installer.img`, satisfying both the `.img` script fallback and the `.iso` staging needs.
3. Serve as the single source of truth for the installer runtime so that both `make img` and `make iso` share the same runtime output and `make dist-release` now respects the dependency ordering required by Phase 13.
