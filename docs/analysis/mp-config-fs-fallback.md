# MP: config fs fallback analysis

## Current discovery stack
- `installer/init/init.sh` sets up runtime dirs and increments logging, including `sp_try_load_fat_modules` (lines ~450) and sources `installer/runtime/lib/config_discovery.sh`.
- `config_discovery.sh` still searches for label `SP_CONFIG` limited to label-based resolution. When a candidate is selected, `sp_mount_candidate` currently hardcodes a mount loop over `vfat` then `ext4`, always invoking `sp_try_load_fat_modules` before attempting mounts.
- Logging already captures mount failures for `vfat` (structured `state=discover-config` `event=mount-vfat-failed` entries) and ensures fatal markers surface to rescue mode.

## Problems/assumptions
- Despite the documented intent to prefer VFAT, `mount` attempts only succeed when the kernel has built-in VFAT support; when the module is missing, the failure propagates down, and even though `sp_try_load_fat_modules` runs, a hard failure indicates the installer cannot access `SP_CONFIG`.
- The current loop tries `ext4` after `vfat`, but the code path is fixed and not driven by configuration; there are no knobs for operators to opt into fallbacks. It also emits only `No such device` from `mount -t vfat` (the target device), so the fatal marker lacks context on other attempted fs types when new ones are introduced.

## Desired behavior for MP
1. Add `SP_CONFIG_FS_TYPES` environment/config knob defaulting to `vfat`, parsing comma-separated values in order.
2. `sp_mount_candidate` should iterate over the configured fs list, running `sp_try_load_fat_modules` before any `vfat` attempts, and logging `[SP-INSTALLER] config-mount-ok ...` on success.
3. On total mount failure emit `[SP-INSTALLER][FATAL] config-mount-failed dev=... tried=... last_rc=...` plus rescue diagnostics (`/proc/filesystems`, `lsmod`, optional `modprobe vfat`) so missing filesystem drivers are easier to diagnose.
4. Doc updates must explain `SP_CONFIG` default file system and optional ext4 fallback via the new knob.

These changes keep label discovery intact and keep `SP_CONFIG_FS_TYPES` opt-in for additional filesystems, ensuring VFAT remains default.
