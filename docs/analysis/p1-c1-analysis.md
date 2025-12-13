# Phase 1 Checkpoint 1 Analysis

## Deep scan
- `ouroboros/tools/make_ouroboros_iso.sh` is a stub that only prints notices and no longer produces artefacts; there is nothing yet wiring the initramfs/ISO build.
- `ouroboros/initramfs_root/init` currently mounts proc/sys/dev and unconditionally invokes the reimage script, so the runtime logic is already close to the desired flow but there is no initramfs image or BusyBox payload yet.
- `ouroboros/scripts/{detect_boot_device.sh,sanity_checks.sh,reimage_usb_from_ram.sh}` exist and default to dry-run behavior, so the safety constraints are already baked in.
- There is no busybox binary or initramfs payload under `ouroboros/initramfs_root/`, no ISO builder output, and `ouroboros/docs/` only contains the overview doc.

## Human brief validation
- The boot-time requirements (kernel + initramfs loading into RAM, invoking `/init`, mounting virtual fs, running the reimage script without touching host disks) are achievable once we build a proper initramfs that bundles BusyBox and the `ouroboros/scripts/` tree and ensure the ISO includes the kernel/initramfs pair.
- We have `/usr/bin/busybox` available on the host (statically linked) but not yet staged in the repo; we can copy it into `ouroboros/initramfs_root/bin/` so the initramfs has all necessary utilities (`sh`, `mount`, `lsblk`, `blkid`, `dd`, `sgdisk`, `realpath`).
- The host currently lacks `xorriso`, `syslinux`/`isolinux`, and `qemu-system-x86_64`, so the builder script must either install or document these prerequisites before running; we will install them via `apt` so the QEMU smoke test can succeed during this run.
- Kernel images are not under `/boot` yet (the directory is empty) so the builder must either fail fast or install a kernel package; we will fetch the kernel by installing the `linux-image-amd64` meta-package so the selection logic can find `/boot/vmlinuz-<version>`.

## Files requiring creation/modification
- `ouroboros/tools/make_ouroboros_iso.sh` → replace the stub with a real builder that stages the initramfs, copies the host kernel, prepares an isolinux tree, and emits `ouroboros/dist/sp-ouroboros.iso` with a verbose kernel command line.
- `ouroboros/initramfs_root/init` (if adjustments are needed to ensure correct path handling or logging inside a real initramfs) and the initramfs payload (`ouroboros/initramfs_root/bin/busybox` plus required directories).
- `ouroboros/docs/qemu-test.md` → document the QEMU invocation we use for the smoke test.
- `docs/analysis/p1-c1-analysis.md` → this file (analysis + plan now, verification notes appended later).

## Implementation plan
1. Stage the initramfs payload: create `ouroboros/initramfs_root/bin/`, copy the host BusyBox binary there, create the necessary symlinks for `sh`, `mount`, `lsblk`, `blkid`, `dd`, `sgdisk`, `realpath`, and ensure the init script can run from `/bin` with a minimal PATH.
2. Update the ISO builder script to:
   * Validate dependencies (`cpio`, `gzip`, `xorriso`, `realpath`, `syslinux`/`isolinux`, etc.) and install the kernel if needed.
   * Build a compressed cpio initramfs from `ouroboros/initramfs_root/`, including the `ouroboros/scripts/` tree.
   * Detect a host kernel image (`/boot/vmlinuz-$(uname -r)` or the first available `/boot/vmlinuz-*`) and copy it plus the initramfs into a new ISO layout that uses `isolinux` with a verbose `init=/init rd.auto=0 loglevel=3` kernel line.
   * Emit `ouroboros/dist/sp-ouroboros.iso` using `xorriso` with `isolinux/isolinux.bin` and `isolinux/ldlinux.c32` and label the ISO `SP_OUROBOROS`.
3. Add a documented QEMU invocation (`ouroboros/docs/qemu-test.md`) that boots the ISO headlessly (e.g., `-nographic -serial mon:stdio -boot d`) to let us observe `/init` and the dry-run script.
4. Run the new builder, boot the ISO via QEMU, observe the dry-run messaging from `ouroboros/scripts/reimage_usb_from_ram.sh`, and append the verification notes to this analysis file.

## Constraints and next steps
- Destructive behavior remains gated by `OUROBOROS_ENABLE_DESTRUCTIVE`; we will not set it during this checkpoint.
- Any missing dependencies (`xorriso`, `syslinux`, `qemu-system-x86_64`, etc.) will be installed locally before building/testing so the workflow can complete.
- After Block B we will immediately proceed to Block C without pausing, as required by the unified agent instruction.
## Block C verification
- `ouroboros/tools/make_ouroboros_iso.sh` now produces `ouroboros/dist/sp-ouroboros.iso` by bundling `ouroboros/initramfs_root/` (with BusyBox symlinks and the `ouroboros/scripts` tree), copying the host kernel, and building an `isolinux` layout that boots with `init=/init rd.auto=0 loglevel=3`.
- A headless smoke test (`timeout 120s qemu-system-x86_64 -m 2048 -smp 2 -nographic -serial mon:stdio -no-reboot -cdrom ouroboros/dist/sp-ouroboros.iso -boot d`) shows the kernel loading, `/init` mounting `/proc`, `/sys`, `/dev`, running the rewritten `sanity_checks.sh` and `reimage_usb_from_ram.sh`, and finally reporting `detect_boot_device` fails because the label `OUROBOROS_BOOT` is unavailable in this VM; the script exits cleanly without destructive actions.
