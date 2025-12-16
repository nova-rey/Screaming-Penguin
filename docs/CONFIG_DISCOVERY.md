# Config Discovery

The installer now performs configuration discovery with a BusyBox-only toolchain inside the initrd. Initramfs no longer depends on `/dev/disk/by-label`; instead, the discovery script probes filesystem labels directly via `blkid` so the `SP_CONFIG` volume can be located without udev links. The script reads sysfs (`/sys/block`) and `/dev` directly and relies on BusyBox applets such as `mount`, `readlink`, `cat`, and `sh`.

## BusyBox-first philosophy

- _Mounts are read-only._ Candidates are mounted with `mount -o ro -t vfat` and `mount -o ro -t ext4` until `/config/installer-config.yml` is found. Failed mounts are unmounted and the mount point is swept clean.
- _Configuration state is exported._ When a match is found, `SP_CONFIG_PATH` and `CONFIG_MOUNT` are set (`CONFIG_MOUNT=${SP_CONFIG_MOUNT_POINT:-/config}`) so later stages operate from the mounted tree.
- _Logging is deterministic._ Every attempt logs a `state=discover-config` entry, the reason for rejection, and the label (if available). A candidate summary is emitted before failure, and `sp_enter_rescue_mode "missing-config"` is called so PID 1 stays blocking the write gate rather than panicking.

## Discovery order

1. **Label media.** The contents of `${SP_CONFIG_LABEL_DIR%/}/${SP_CONFIG_LABEL_NAME}` are resolved with `readlink -f`; the pointed node is attempted first so labeled installer media remain the preferred source.
2. **Removable disks.** `/sys/block/*/removable` is consulted next. Each removable disk path (`${SP_DEV_ROOT:-/dev}/${device}`) is logged before mount attempts.
3. **All partitions.** Every sysfs partition entry under `/sys/block/*` is enumerated last, maximizing coverage without blocking on non-removable media.

Each phase respects the exclusion list (`SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES`, default `loop ram fd sr dm`), logs when no candidates exist, and never retries devices the script already attempted.

## Failure guarantees

- _No panics, no `exit` from PID 1._ Discovery never aborts the initramfs in an uncontrolled way. After the candidate summary, `sp_enter_rescue_mode` is invoked to block the write gate, log diagnostics, bind `/proc`, `/sys`, `/dev`, and launch a BusyBox shell.
- _Write gate remains BLOCKED._ `sp_write_gate_blocked` is triggered every time rescue mode runs, and the rescue helper records the blocked state before handing control to `/bin/sh`.
- _Deterministic rescue diagnostics._ Rescue mode now catalogs `/sys/block`, `/proc/partitions`, and `/dev/disk/by-label` entries before shell hand-off, all via BusyBox-friendly commands.
