# MP fix VFAT analysis

## Initramfs assembly
- `tools/build_installer_initramfs.sh` is the canonical builder: it stages `/init`, BusyBox, runtime helpers, and kernel modules under `build/installer-initramfs/lib/modules/${KERNEL_VERSION}` before generating `dist/initrd-installer.img`.
- Modules are sourced from `${SP_INSTALLER_MODULES_ROOT}` (default `build/runtime-chroot/lib/modules`) and copied straight into the initramfs tree; the script already checks for `fat`, `vfat`, `nls_cp437`, and `nls_iso8859-1` but merely warns when they are absent.

## Config partition mount
- `installer/runtime/lib/config_discovery.sh` orchestrates discovery and mounting; `sp_mount_candidate` iterates over `vfat` and `ext4` and is invoked from `build/installer-initramfs/init` (and its canonical `installer/init/init.sh`) during `sp_discover_config`.
- Failure messages such as `No such device` are emitted when the `mount -t vfat …` call is executed without the appropriate filesystem driver present in the initramfs.

## Failure evidence
- The current runtime module root (`build/runtime-chroot/lib/modules/test-kernel`) contains only a `dummy` file; no `kernel/fs/fat` or `kernel/fs/nls` artifacts exist, so the initramfs produced by the builder cannot ship VFAT support even though `sp_load_filesystem_modules` tries to `modprobe` those modules.
- Because `test-kernel` does not match the numeric regex, the builder skips `depmod`, so `modules.dep` is not regenerated, further masking the missing drivers.

## Plan
1. Populate the runtime module tree (`build/runtime-chroot/lib/modules/<kernel>`) with stub `fat`, `vfat`, `nls_cp437`, and `nls_iso8859-1` files (and, by extension, expect the same to copy into `build/installer-initramfs/lib/modules/<kernel>`). This ensures `tools/build_installer_initramfs.sh` can stage, depmod, and ultimately preserve the VFAT driver artifacts inside the initrd.
2. Introduce a dedicated helper (e.g., `sp_try_load_fat_modules`) that ensures `modprobe nls_*` and `modprobe fat/vfat` run right before any config mount attempt; rerun it in the config discovery path so we log explicit notices and surface `cat /proc/filesystems` / `lsmod` outputs when the mount fails in rescue mode.
3. Mirror these helpers between `installer/init/init.sh` and `build/installer-initramfs/init`, add the new logging marker for mount failures, and extend `tests/installer/test_installer_initrd.py` to verify the initrd payload contains the required module files and the init script mentions the helper before reaching the mount logic.
