# MP — Fix VFAT NLS/FAT Stack in Initramfs

## Symptom
- BusyBox rescue on hardware shows `/proc/filesystems` listing `vfat`, `blkid` reports `LABEL_FATBOOT="SP_CONFIG"`, yet `mount -t vfat` still fails with “unknown filesystem” despite the label being present.

## Hypothesis / root cause
- The initramfs lacks the FAT and NLS kernel module payload (or it is not loaded early enough) so `mount -t vfat` runs without the stack the hardware actually needs. Missing modules such as `fat`, `vfat`, `nls_cp437`, or `nls_iso8859-1` explain why `/proc/filesystems` advertises vfat but the mount still errors out.

## Fix summary
- The boot script now ships `sp_try_load_fat_stack`, which logs and best-effort `modprobe`s the FAT/VFAT/NLS stack (fat, vfat, nls_cp437, nls_iso8859-1) before any VFAT attempt and leaves a `fat-stack:` log trail to confirm readiness.
- The initramfs builder stages the actual kernel module blobs and dependency metadata (`*.ko*` under `kernel/fs/fat` + `kernel/fs/nls`, plus `modules.{dep,alias,builtin,order}`), so modprobe can resolve them when the installer runs.
- Rescue mode now dumps `/proc/filesystems`, `lsmod`, `modprobe nls_cp437/vfat` RCs, and the captured VFAT mount stderr to spotlight missing module failures.

## How to verify
1. On hardware rescue: `cat /proc/filesystems`, then `modprobe nls_cp437`, and finally `mount -t vfat /dev/sda1 /mnt` to validate the module stack resolves the mount.
2. During installer boots: watch for `[SP-INSTALLER] fat-stack: probing modules (fat vfat nls_cp437 nls_iso8859-1)` followed by `[SP-INSTALLER] fat-stack: ready` and a subsequent `[SP-INSTALLER] config-mount-ok` entry after the config partition mounts cleanly.
3. If the compromise persists, rescue logs now include the mount stderr, `lsmod`, `/proc/filesystems`, and the `modprobe ... rc=` lines from the failure for faster root-cause analysis.
