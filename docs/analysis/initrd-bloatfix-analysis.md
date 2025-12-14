# initrd bloatfix analysis

## Inventory: initrd creation + packaging
- `tools/build_installer_initramfs.sh` is the only builder that writes the Screaming Penguin installer initramfs. It prepares `${INITRD_ROOT}` (aka `build/installer-initramfs`), stages BusyBox, drops `${PROJECT_ROOT}/installer/init/init.sh` into `/init`, and then runs `find . | cpio -o -H newc | gzip -9` into `dist/initrd-installer.img`.
- `installer/init/init.sh` expects `/init` as PID 1 and sources scripts from `$SP_SCRIPT_DIR/../runtime/lib`, i.e. `/runtime/lib` inside the initramfs tree (see lines 33‑74 for the helper list: `rescue_mode.sh`, `disk_layout.sh`, `disk_execute.sh`, `rootfs_deploy.sh`, `bootloader.sh`, `config_discovery.sh`).
- The artifact lifecycle is:
  1. `tools/build_installer_initramfs.sh` → `dist/initrd-installer.img`.
  2. `Makefile` `installer-runtime` target copies that file into `build/initrd-installer.img` so the `.img` builder has a fallback artifact.
  3. `tools/make_installer_iso.sh` rebuilds the initramfs before copying `dist/initrd-installer.img` into the ISO tree.
  4. `tools/make_installer_img.sh` then picks the same `dist/initrd-installer.img` (or the `build/` fallback) when populating `/boot/initrd-installer.img`.

## Observations: failure mode / expected vs actual contents
- After running the builder, `gzip -cd dist/initrd-installer.img | cpio -t -H newc` lists only `.`, `init`, `/bin/busybox`, and the helper symlinks (sh/mount/etc.). There is no `runtime/lib/*` inside the archive; the tree is just BusyBox plus `/init`.
- The initramfs size is tiny: `dist/initrd-installer.img` reports `4333` 512-byte blocks (≈2.2 MiB) because it only packages BusyBox and `/init`. The runtime libraries that `installer/init/init.sh` expects are absent, so nothing beyond `/init` and BusyBox is shipped to the kernel.
- Because `/init` attempts to `source` the runtime helpers and they are missing, the installer cannot reach rescue/disk/bootloader functionality. A tiny payload correlates with a missing runtime stack, so the initrd location can be as small as 1.1 MiB (per the reported symptom) even though the builder still succeeds without complaint.

## Root cause and required files to change
- **Root cause:** `tools/build_installer_initramfs.sh` never stages any files under `/runtime/lib`, so the wired-in helpers (`rescue_mode.sh`, `disk_layout.sh`, `disk_execute.sh`, `rootfs_deploy.sh`, `bootloader.sh`, `config_discovery.sh`) are missing from the initramfs even though `installer/init/init.sh` references them. There is also no guard for missing scripts or for the initrd size, so the pipeline happily creates an undersized payload.
- **Files that must change:**
  - `tools/build_installer_initramfs.sh` – stage `${PROJECT_ROOT}/installer/runtime/lib` into the initramfs tree, fail if the required runtime libs are absent, add a size sanity check, and make it impossible to reuse stale or placeholder initrds.
  - Add a deterministic test under `tests/installer/` (e.g. a new `test_installer_initrd.py`) that rebuilds the initramfs, unpacks `dist/initrd-installer.img`, and asserts `/init`, `/runtime/lib/*`, and the minimum size threshold are present. The test proves missing payloads will break.
  - The analysis doc itself (`docs/analysis/initrd-bloatfix-analysis.md`) records the investigative findings required by Block A.

## Expected vs actual artifact chain
- **Expected:** The minified initramfs is produced by `tools/build_installer_initramfs.sh` as follows: stage `/init`, `/bin/busybox`, `/runtime/lib/<helpers>`, then `find`/`cpio`/`gzip` into `dist/initrd-installer.img`; `Makefile` mirrors the same artifact into `build/`, and both `tools/make_installer_iso.sh` and `tools/make_installer_img.sh` copy `dist/initrd-installer.img` into the ISO/IMG build trees so the kernel loads an initrd that contains `/init`, the runtime libs, and a rescue shell.
- **Actual:** `tools/build_installer_initramfs.sh` currently only stages BusyBox and `/init`, so the compressed artifact is ∼1–2 MiB, lacks `/runtime/lib`, and the runtime script cannot be executed. No size guard or runtime-lib validation exists, so the just-built artifact is still treated as valid and copied into the ISO/IMG trees, leading to a boot pipeline that spins up an empty environment instead of the installer runtime.
