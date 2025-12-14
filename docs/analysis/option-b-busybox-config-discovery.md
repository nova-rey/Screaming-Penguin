# Option B — BusyBox-only Config Discovery

## Current discovery state

- `installer/runtime/lib/config_discovery.sh` currently prefers `/dev/disk/by-label/SP_CONFIG`, then asks `blkid` for every VFAT partition, and probes candidates with `mount -t vfat -o ro`. Every failure is logged; diagnostic hooks ship `lsblk`, `blkid`, and `udevadm settle` output before dropping into `sp_enter_rescue_mode`.
- `installer/runtime/lib/rescue_mode.sh` also runs `lsblk -f` and `blkid` to produce diagnostics before hunting for a shell.
- `installer/init/init.sh` exposes a supplemental `lsblk` probe and, on discovery failures, relies on `sp_enter_rescue_mode`. Together these scripts use `blkid`, `lsblk`, and `udevadm`, none of which exist in the BusyBox-only initramfs we intend to ship.
- Tests under `tests/installer/test_config_discovery.py` exercise those commands via stub binaries to keep the suite fast, but the runtime still references `blkid`/`lsblk`.

## BusyBox applet availability

- `sp_bootstrap` invokes `/bin/busybox --install -s /bin`, so the initramfs ships BusyBox-provided `mount`, `sh`, `ls`, `cat`, `grep`, and `readlink`. These applets are guaranteed in early boot, and no BusyBox-only path in the installer currently invokes any other external helper.
- There is no guarantee `blkid`, `lsblk`, or `udevadm` are present, so the discovery path must rely strictly on BusyBox applets plus sysfs/procfs inspection.

## Desired BusyBox-only discovery algorithm

1. Prefer `/dev/disk/by-label/SP_CONFIG` if the linker exists and points at a block node. This keeps the labeled media path intact.
2. Enumerate `/sys/block/*` and:
   - Skip `loop`, `ram`, `fd`, `sr`, and `dm` devices.
   - Keep removable disks first by reading `/sys/block/<dev>/removable`.
   - Collect partition nodes from `/sys/block/<dev>/<dev>*` to be evaluated last.
3. For each candidate path (preferred order: label → removable disks → all partitions):
   - Log the attempt deterministically via structured logging helpers.
   - Try mounting read-only first as VFAT (`mount -o ro -t vfat ...`), then EXT4.
   - Check for the sentinel file `/config/installer-config.yml` after each successful mount.
   - Unmount and clean `/config` on failure; leave it mounted when the config file exists and export `CONFIG_MOUNT=/config`.

## Failure semantics

- Discovery never panics; all failures call `sp_enter_rescue_mode "missing-config"` and return to PID 1 so the BusyBox rescue shell can be launched.
- The write gate stays blocked while rescue mode runs (`sp_write_gate_blocked` is invoked inside `sp_enter_rescue_mode`), and the `installer` never proceeds to disk writes.
- Rescue mode uses BusyBox `sh`, logs label directory contents via `readlink`, and records diagnostics from `/sys/block` instead of `lsblk`/`blkid`. If no shell can be exec’d, it loops indefinitely instead of exiting.
- The algorithm logs every candidate and maintains `SP_CONFIG_DISCOVERY_ATTEMPT_COUNT`/`_LOG` for auditability before summarizing failures in the new doc.

After this analysis, implementation continues directly into Block B as instructed.
