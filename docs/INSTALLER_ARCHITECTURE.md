# Installer Architecture

## BusyBox-only early boot

- The initramfs is self-contained: `/bin/busybox --install -s /bin` brings along `mount`, `sh`, `ls`, `cat`, `readlink`, and the other applets needed during config discovery and rescue. No util-linux binaries are required before the new root is mounted.
- `sp_discover_config` walks `/sys/block` and `/dev`, mounting read-only VFAT/EXT4 candidates in a deterministic order (label → removable → partitions) described in `docs/CONFIG_DISCOVERY.md`. Each candidate is logged before it is touched so failures are reproducible.
- Rescue mode binds `/dev`, `/proc`, and `/sys` before launching a BusyBox shell, logs the blocked write gate, and enumerates `/sys/block`, `/proc/partitions`, and `/dev/disk/by-label` with BusyBox-friendly helpers.

## Removing util-linux ties

- The runtime no longer references `blkid`, `lsblk`, or `udevadm`. UUID discovery in `installer/runtime/lib/bootloader.sh` now walks `/dev/disk/by-uuid` with `readlink -f` instead of invoking `blkid`, keeping Phase 12 compatible with early boot determinism.
- All disk discovery and diagnostic paths are controlled by POSIX `sh` and BusyBox command exports, so the installer can be reproduced without relying on external toolchains at initramfs startup.
