# MP — Populate `/dev/disk/by-label` before discovery

## Symptom
- Installer boots show VFAT config media detected via `blkid` and `/proc/filesystems` advertising `vfat`, yet config discovery fails with “device missing” when referencing `/dev/disk/by-label/SP_CONFIG`.
- The same hardware/disk exposes `/dev/sdX1` and the VFAT partition, so nothing is actually wrong with the hardware or label, just the label namespace itself is missing.

## Hypothesis / root cause
- The initramfs previously relied on the kernel to populate `/dev/disk/by-label`, but when a VFAT label is used for config the kernel populates that namespace later than config discovery runs. Having the block devices already mounted and the FAT stack loaded is not enough because the installer still needs that directory populated to resolve the label.
- Without any `blkid`-driven symlinks, config discovery skips the device even though the VFAT partition is present, so VFAT + block device availability were not sufficient to reach the install config.

## Fix summary
- `sp_try_load_fat_stack` now runs before config discovery so VFAT (`fat`, `vfat`, `nls_cp437`, `nls_iso8859-1`) modules are loaded before we probe labels.
- `sp_populate_disk_by_label` scans `blkid -o export` to synthesize `/dev/disk/by-label/<label>` symlinks before discovery begins. It only links a device when both `DEVNAME` and `LABEL` are emitted, and it is a best-effort, non-fatal operation with logging so we do not race with later udev behavior.
- Config discovery logs a warning when `/dev/disk/by-label` is still missing, keeping troubleshooting concrete if the population step failed.

## How to verify
1. Build the installer initramfs and inspect `build/installer-initramfs/init` for `sp_populate_disk_by_label`, the `blkid -o export` loop, and the `/dev/disk/by-label` directory creation logic (`tests/installer/test_initramfs_by_label_population.py` checks for these strings).
2. Boot the installer with VFAT config media; watch for `[SP-INSTALLER] by-label link: SP_CONFIG -> /dev/...` in the early logs, followed by `[SP-INSTALLER] config-mount-ok` without previously observed “device missing” errors.
3. If the guard warning still appears, the population helper either failed to find `blkid` or returned before the directory was ready, which narrows down the next diagnostics step.
